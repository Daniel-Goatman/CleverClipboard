import Foundation

private final class JevSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // The credential has one intended host; do not follow provider redirects.
        completionHandler(nil)
    }
}

/// Native HTTPS client. Mutable state belongs to one serial queue; UI callbacks use main.
final class JevClient {
    private let queue = DispatchQueue(label: "Cuekit.jev", qos: .userInitiated)
    private let session: URLSession
    private let credential: () throws -> String
    private var task: URLSessionDataTask?
    private var generation = UUID()
    private var key: String?
    private var busy = false
    private var enabled = false
    var onState: ((String, Bool) -> Void)?

    init(credential: @escaping () throws -> String = JevCredential.load, session: URLSession? = nil) {
        self.credential = credential
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        configuration.waitsForConnectivity = false
        self.session = session ?? URLSession(configuration: configuration, delegate: JevSessionDelegate(), delegateQueue: nil)
    }
    deinit { session.invalidateAndCancel() }

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            self.generation = UUID(); let generation = self.generation
            self.task?.cancel(); self.busy = false; self.enabled = true; self.key = nil
            self.report("Checking TypeSafe connection…", false)
            do {
                let key = try self.credential()
                guard JevCredential.isValidFormat(key) else { throw ClipboardError.message("Configure a valid TypeSafe API key from the menu.") }
                self.key = key
                let request = self.request(path: "models", key: key)
                self.task = self.session.dataTask(with: request) { [weak self] data, response, error in
                    guard let self else { return }
                    self.queue.async {
                        guard self.enabled, self.generation == generation else { return }
                        self.task = nil
                        do {
                            _ = try Self.checkedResponse(data, response, error)
                            self.report("TypeSafe connected · Smart Paste ready", true)
                        } catch { self.report(error.localizedDescription, false) }
                    }
                }
                self.task?.resume()
            } catch { self.report(error.localizedDescription, false) }
        }
    }

    /// Validates a proposed key without changing the active credential or selection.
    @discardableResult
    func verifyCredential(_ text: String, completion: @escaping (Result<Void, Error>) -> Void) -> URLSessionDataTask? {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard JevCredential.isValidFormat(key) else {
            DispatchQueue.main.async { completion(.failure(ClipboardError.message("Enter a valid TypeSafe API key."))) }
            return nil
        }
        let task = session.dataTask(with: request(path: "models", key: key)) { data, response, error in
            let result: Result<Void, Error> = Result { _ = try Self.checkedResponse(data, response, error) }
            DispatchQueue.main.async { completion(result) }
        }
        task.resume()
        return task
    }

    func select(context: String, clips: [Clip], dataset: SmartPasteDataset? = nil, completion: @escaping (Result<SelectionReply, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            func complete(_ value: Result<SelectionReply, Error>) {
                var outcome = value
                if case .failure(let error) = value {
                    do { try dataset?.append("inference_failed", ["reason": PasteReason.classify(error.localizedDescription).rawValue]) }
                    catch { outcome = .failure(error) }
                }
                let final = outcome
                DispatchQueue.main.async { completion(final) }
            }
            guard !self.busy else {
                complete(.failure(ClipboardError.message("Jev is finishing the previous selection. Try again in a moment."))); return
            }
            guard self.enabled, let key = self.key, self.task == nil else {
                complete(.failure(ClipboardError.message("TypeSafe is not connected. Reconnect from the menu."))); return
            }
            let generation = self.generation, started = ProcessInfo.processInfo.systemUptime
            do {
                // Reject the key before truncating any candidate or source context.
                let raw: [String: Any] = ["context": context, "clips": clips.map {
                    [$0.candidateText, $0.hint, $0.candidateSourceContext ?? "",
                     $0.provenance?.requestContext ?? "", $0.provenance?.sourceApp ?? ""]
                }]
                guard !JevRequest.containsSecret(raw, key: key) else { throw ClipboardError.message("Clipboard/context contains the API key. Nothing was sent.") }
                let payload = JevRequest.payload(context: context, clips: clips)
                guard !JevRequest.containsSecret(payload, key: key) else { throw ClipboardError.message("Clipboard/context contains the API key. Nothing was sent.") }
                let prepared = try JevRequest.make(payload)
                guard !JevRequest.containsSecret(prepared.body, key: key) else { throw ClipboardError.message("Clipboard/context contains the API key. Nothing was sent.") }
                var request = self.request(path: "systemone", key: key)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JevRequest.encode(prepared.body)
                #if CUEKIT_DEVELOPMENT
                let record = try DevelopmentDataset.begin(request: prepared.body, ids: prepared.ids)
                #endif
                try dataset?.append("request", ["request": prepared.body,
                    "candidate_id_map": Dictionary(uniqueKeysWithValues: prepared.ids.enumerated().map { ("C\($0.offset)", $0.element) }),
                    "transport_status": "prepared_send_not_confirmed"])
                self.busy = true
                self.task = self.session.dataTask(with: request) { [weak self] data, response, error in
                    guard let self else { return }
                    self.queue.async {
                        guard self.enabled, self.generation == generation else { return }
                        self.task = nil; self.busy = false
                        do {
                            let data = try Self.checkedResponse(data, response, error)
                            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                                  !JevRequest.containsSecret(parsed, key: key) else {
                                throw ClipboardError.message("Invalid Jev response. Nothing was pasted.")
                            }
                            var result = try JevRequest.result(parsed, ids: prepared.ids)
                            result.elapsed_ms = (ProcessInfo.processInfo.systemUptime-started)*1000
                            #if CUEKIT_DEVELOPMENT
                            try record?.finish(response: parsed, result: result, error: nil)
                            #endif
                            let selection = try JSONSerialization.jsonObject(with: JSONEncoder().encode(result))
                            try dataset?.append("response", ["response": parsed, "selection_result": selection,
                                "paste_outcome": "not_observed", "label_status": "unlabelled"])
                            complete(.success(result))
                        } catch {
                            if let response = response as? HTTPURLResponse, [401,403].contains(response.statusCode) {
                                self.report("TypeSafe rejected the API key. Update it from the menu.", false)
                            }
                            #if CUEKIT_DEVELOPMENT
                            try? record?.finish(response: nil, result: nil, error: "Selection failed")
                            #endif
                            complete(.failure(error))
                        }
                    }
                }
                self.task?.resume()
            } catch { complete(.failure(error)) }
        }
    }

    private func request(path: String, key: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.typesafe.ai/v1/" + path)!)
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        return request
    }
    private static func checkedResponse(_ data: Data?, _ response: URLResponse?, _ error: Error?) throws -> Data {
        guard error == nil, let response = response as? HTTPURLResponse, let data else {
            throw ClipboardError.message("Could not reach TypeSafe. Check your connection and try again.")
        }
        switch response.statusCode {
        case 200: break
        case 401,403: throw ClipboardError.message("TypeSafe rejected the API key. Update it from the menu.")
        case 429: throw ClipboardError.message("TypeSafe rate limit reached. Try again shortly.")
        default: throw ClipboardError.message("TypeSafe service unavailable. Nothing was pasted; try again.")
        }
        guard data.count <= 128_000 else { throw ClipboardError.message("Invalid Jev response. Nothing was pasted.") }
        return data
    }
    private func report(_ message: String, _ ready: Bool) {
        DispatchQueue.main.async { [weak self] in self?.onState?(message, ready) }
    }
    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.enabled = false; self.generation = UUID(); self.key = nil
            self.task?.cancel(); self.task = nil; self.busy = false
        }
    }
}
