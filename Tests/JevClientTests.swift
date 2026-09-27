import Foundation

private final class MockJevProtocol: URLProtocol, @unchecked Sendable {
    static let lock = NSLock()
    static var metadataStatus = 200
    static var selectionStatus = 200
    static var confidence = 0.9
    static var choice = "C0"
    static var posts = 0
    static var delay: TimeInterval = 0
    private let stateLock = NSLock()
    private var stopped = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let isPost = request.httpMethod == "POST"
        if isPost { Self.posts += 1 }
        let status = isPost ? Self.selectionStatus : Self.metadataStatus
        let choice = Self.choice, confidence = Self.confidence, delay = isPost ? Self.delay : 0
        Self.lock.unlock()
        precondition(request.url?.host == "api.typesafe.ai")
        precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-test-key-not-real")
        let body: [String: Any] = isPost ? ["model": JevRequest.model, "answers": ["pick": [
            "type": "choice", "choice": choice, "confidence": confidence,
            "probabilities": ["C0":0.51,"C1":0.49,"NONE":0]]]] : ["models": []]
        let data = try! JSONSerialization.data(withJSONObject: body)
        DispatchQueue.global().asyncAfter(deadline: .now()+delay) {
            self.stateLock.lock(); defer { self.stateLock.unlock() }
            guard !self.stopped else { return }
            let response = HTTPURLResponse(url: self.request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: data)
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() { stateLock.lock(); stopped = true; stateLock.unlock() }
    static func configure(metadata: Int = 200, selection: Int = 200, confidence: Double = 0.9, choice: String = "C0", delay: TimeInterval = 0) {
        lock.lock(); defer { lock.unlock() }
        metadataStatus = metadata; selectionStatus = selection
        self.confidence = confidence; self.choice = choice; self.delay = delay
    }
    static var postCount: Int { lock.lock(); defer { lock.unlock() }; return posts }
}

@main struct JevClientTests {
    static func wait(_ predicate: () -> Bool) {
        let deadline = Date().addingTimeInterval(5)
        while !predicate() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        precondition(predicate(), "Native client callback timed out")
    }
    static func main() throws {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("cuekit-client-tests-\(UUID().uuidString)")
        setenv("CUEKIT_DATASET_ROOT", output.path, 1)
        defer { unsetenv("CUEKIT_DATASET_ROOT"); try? FileManager.default.removeItem(at: output) }
        let attempts = output.appendingPathExtension("attempts")
        defer { try? FileManager.default.removeItem(at: attempts) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockJevProtocol.self]
        let session = URLSession(configuration: config)
        let client = JevClient(credential: { "synthetic-test-key-not-real" }, session: session)
        defer { client.stop() }
        for code in [401, 403, 500, 200] {
            MockJevProtocol.configure(metadata: code)
            var validation: Result<Void, Error>?
            client.verifyCredential("synthetic-test-key-not-real") { validation = $0 }
            wait { validation != nil }
            switch validation! {
            case .success: precondition(code == 200)
            case .failure: precondition(code != 200)
            }
        }
        var ready = false, message = ""
        client.onState = { text, isReady in
            precondition(Thread.isMainThread)
            message = text; ready = isReady
        }
        MockJevProtocol.configure(metadata: 401)
        client.start()
        wait { message.contains("rejected") }
        precondition(!ready, "Invalid key must not report ready")
        MockJevProtocol.configure()
        client.start(); wait { ready }
        let clips = [Clip(id:"phone",text:"+1 202 555 0147",app:"Fixture",copiedAt:.now),
                     Clip(id:"email",text:"email@example.org",app:"Fixture",copiedAt:.now,hint:"My email address",pinned:true)]
        func select(_ input: [Clip]? = nil) -> Result<SelectionReply, Error> {
            var response: Result<SelectionReply, Error>?
            let dataset = try! SmartPasteDataset(root: attempts)
            client.select(context: "My phone number:", clips: input ?? clips, dataset: dataset) {
                precondition(Thread.isMainThread); response = $0
            }
            wait { response != nil }; return response!
        }
        MockJevProtocol.configure(confidence: 0.7)
        precondition(try! select().get().usesLatestClipboard)
        MockJevProtocol.configure(confidence: 0.700001)
        precondition(try! select().get().ranked.first?.id == "phone")
        MockJevProtocol.configure(choice: "C9")
        if case .success = select() { fatalError("Malformed response used as a paste or fallback") }
        MockJevProtocol.configure(selection: 401)
        if case .success = select() { fatalError("HTTP failure used as a paste or fallback") }
        wait { !ready }
        MockJevProtocol.configure()
        client.start(); wait { ready }
        let before = MockJevProtocol.postCount
        let secret = Clip(id:"secret",text:"synthetic-test-key-not-real",app:"Fixture",copiedAt:.now)
        if case .success = select([secret]) { fatalError("Credential sent") }
        let hiddenSecret = Clip(id:"hidden", text:String(repeating: "x", count: 5000) + "synthetic-test-key-not-real" + String(repeating: "x", count: 5000), app:"Fixture", copiedAt:.now)
        if case .success = select([hiddenSecret]) { fatalError("Credential hidden by excerpting was accepted") }
        precondition(MockJevProtocol.postCount == before)
        let brokenDataset = try SmartPasteDataset(root: attempts)
        do { try brokenDataset.append("invalid", ["value": Double.infinity]); fatalError("Expected storage failure") } catch { }
        var blockedResult: Result<SelectionReply, Error>?
        client.select(context: "Fixture", clips: clips, dataset: brokenDataset) { blockedResult = $0 }
        wait { blockedResult != nil }
        if case .success = blockedResult! { fatalError("Unrecorded inference was allowed") }
        precondition(MockJevProtocol.postCount == before, "Storage failure must prevent HTTP dispatch")
        MockJevProtocol.configure(delay: 0.5)
        var staleCallback = false
        client.select(context: "Fixture", clips: clips) { _ in staleCallback = true }
        wait { MockJevProtocol.postCount > before }
        ready = false; client.stop(); MockJevProtocol.configure(); client.start(); wait { ready }
        precondition(try! select().get().ranked.first?.id == "phone")
        let until = Date().addingTimeInterval(0.6)
        while Date() < until { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        precondition(!staleCallback, "Cancelled generation must not deliver a stale selection")
        let attemptFiles = try FileManager.default.contentsOfDirectory(at: attempts, includingPropertiesForKeys: nil)
        precondition(attemptFiles.count == 8)
        var requests = 0, responses = 0, failures = 0
        for file in attemptFiles {
            let text = try String(contentsOf: file, encoding: .utf8)
            precondition(!text.contains("synthetic-test-key-not-real") && !text.contains("Authorization"))
            let rows = try text.split(separator: "\n").map { try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any] }
            precondition(rows.first?["event"] as? String == "attempt")
            requests += rows.filter { $0["event"] as? String == "request" }.count
            responses += rows.filter { $0["event"] as? String == "response" }.count
            failures += rows.filter { $0["event"] as? String == "inference_failed" }.count
            for row in rows where row["event"] as? String == "request" {
                let data = row["data"] as! [String: Any]
                precondition(data["request"] is [String: Any] && data["candidate_id_map"] is [String: String])
            }
        }
        precondition(requests == 5 && responses == 3 && failures == 4)
        print("PASS: durable request/response journals; fallback and failures; configured secret rejected before persistence")
        #if CUEKIT_DEVELOPMENT
        let records = try FileManager.default.contentsOfDirectory(at: output, includingPropertiesForKeys: nil)
        precondition(!records.isEmpty)
        for url in records {
            let text = try String(contentsOf: url, encoding: .utf8)
            precondition(!text.contains("synthetic-test-key-not-real") && !text.contains("Authorization"))
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            precondition((attrs[.posixPermissions] as! NSNumber).intValue == 0o600)
        }
        #else
        precondition(!FileManager.default.fileExists(atPath: output.path), "Release must ignore dataset environment variables")
        #endif
        print("PASS: native HTTPS lifecycle with mocked transport; rejected key, confidence fallback, errors, cancellation, secret rejection and recording boundary")
    }
}
