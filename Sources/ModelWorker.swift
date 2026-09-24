import Foundation

struct RankedClip: Decodable {
    let id: String
    let score: Double
}
struct WorkerReply: Decodable {
    let type: String
    var ranked: [RankedClip]?
    var elapsed_ms: Double?
    var error: String?
    var eligible: Int?
    var queue_ms: Double?
    var decision: String?
    var model_choice: String?
    var recency_changed: Bool?

    var usesLatestClipboard: Bool {
        type == "result" && ranked?.isEmpty == true &&
            error == "No clear clipboard match. Choose an item from History."
    }
}

/// One serial, private pipe worker. No listening port and no saved request content.
final class ModelWorker {
    static func requestPayload(context: String, clips: [Clip], now: Date = Date()) -> [String: Any] {
        let excerpts = CandidateText.forClips(clips)
        return ["context": context,
            "items": clips.enumerated().map { index, clip in
                let source = clip.candidateSourceContext ?? clip.provenance?.requestContext ?? "Source unknown"
                let sourceExcerpt = String(source.prefix(300))
                return ["id": clip.id,
                 "text": excerpts[index],
                 "text_truncated": excerpts[index] != clip.candidateText,
                 "app": String((clip.pinned ? "Persistent entry" : clip.provenance?.sourceApp ?? "Unknown source").prefix(200)),
                 "source_context": sourceExcerpt,
                 "source_context_truncated": sourceExcerpt != source,
                 "kind": clip.kind.rawValue,
                 "recency_rank": index,
                 "age_seconds": clip.pinned ? 0 : max(0, now.timeIntervalSince(clip.copiedAt)),
                 "pinned": clip.pinned,
                 "hint": clip.hint] as [String: Any]
            }]
    }
    private let queue = DispatchQueue(label: "JevClipboard.model")
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private let root: URL
    private let credential: () throws -> String
    private let lock = NSLock()
    private var starting = false
    private var busy = false
    private var enabled = false
    var onState: ((String, Bool) -> Void)?

    init(root: URL, credential: @escaping () throws -> String = JevCredential.load) {
        self.root = root
        self.credential = credential
        signal(SIGPIPE, SIG_IGN)
    }

    func start() {
        lock.lock(); enabled = true; lock.unlock()
        scheduleStart()
    }

    private func scheduleStart() {
        lock.lock()
        guard enabled && !starting else { lock.unlock(); return }
        starting = true
        lock.unlock()
        queue.async { [weak self] in
            guard let self else { return }
            defer { self.lock.lock(); self.starting = false; self.lock.unlock() }
            do {
                self.stopProcess()
                self.report("Connecting Jev…", false)
                let key = try self.credential()
                let process = Process(), toWorker = Pipe(), fromWorker = Pipe()
                let python = URL(fileURLWithPath: "/usr/bin/python3")
                guard FileManager.default.isExecutableFile(atPath: python.path) else {
                    throw ClipboardError.message("Model runtime is missing. See README setup.")
                }
                process.executableURL = python
                process.arguments = ["-u", self.root.appendingPathComponent("runtime/jev_worker.py").path]
                process.currentDirectoryURL = self.root.appendingPathComponent("runtime")
                var env = ProcessInfo.processInfo.environment
                env["HF_HUB_OFFLINE"] = "1"
                env["TOKENIZERS_PARALLELISM"] = "false"
                env["PYTHONDONTWRITEBYTECODE"] = "1"
                process.environment = env
                process.standardInput = toWorker
                process.standardOutput = fromWorker
                process.standardError = FileHandle.nullDevice // Never persist private exception payloads.
                self.lock.lock()
                guard self.enabled else { self.lock.unlock(); return }
                self.process = process
                self.input = toWorker.fileHandleForWriting
                self.output = fromWorker.fileHandleForReading
                do { try process.run(); self.lock.unlock() }
                catch { self.lock.unlock(); throw error }
                var setup = try JSONSerialization.data(withJSONObject: ["api_key": key])
                setup.append(10)
                try toWorker.fileHandleForWriting.write(contentsOf: setup)
                setup.resetBytes(in: 0..<setup.count)
                let reply = try self.readReply(timeout: 10)
                guard reply.type == "ready" else { throw ClipboardError.message("Jev could not warm up.") }
                self.report("Jev ready · hosted direct selection", true)
            } catch {
                self.stopProcess()
                self.report(error.localizedDescription, false)
            }
        }
    }

    func select(context: String, clips: [Clip], completion: @escaping (Result<WorkerReply, Error>) -> Void) {
        let enqueuedAt = ProcessInfo.processInfo.systemUptime
        lock.lock()
        guard !busy else {
            lock.unlock()
            completion(.failure(ClipboardError.message("Jev is finishing the previous selection. Try again in a moment.")))
            return
        }
        busy = true
        lock.unlock()
        queue.async { [weak self] in
            guard let self else { return }
            defer { self.lock.lock(); self.busy = false; self.lock.unlock() }
            let queueMS = (ProcessInfo.processInfo.systemUptime - enqueuedAt) * 1000
            do {
                guard self.process?.isRunning == true, let input = self.input else {
                    throw ClipboardError.message("Jev is unavailable. Restart it from the menu.")
                }
                let payload = Self.requestPayload(context: context, clips: clips)
                var data = try JSONSerialization.data(withJSONObject: payload)
                data.append(10)
                try input.write(contentsOf: data)
                var reply = try self.readReply(timeout: 12)
                reply.queue_ms = queueMS
                guard reply.type == "result" else {
                    DispatchQueue.main.async { completion(.failure(ClipboardError.message(reply.error ?? "Jev could not select an item."))) }
                    return
                }
                guard reply.ranked?.isEmpty == false || reply.usesLatestClipboard else {
                    DispatchQueue.main.async { completion(.failure(ClipboardError.message(reply.error ?? "No matching clipboard text."))) }
                    return
                }
                DispatchQueue.main.async { completion(.success(reply)) }
            } catch {
                self.stopProcess()
                self.report("Jev stopped — restarting…", false)
                DispatchQueue.main.async { completion(.failure(error)) }
                self.scheduleStart()
            }
        }
    }

    func keepWarm(completion: ((Bool) -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.process?.isRunning == true else {
                DispatchQueue.main.async { completion?(false) }
                self.scheduleStart(); return
            }
            do {
                try self.input?.write(contentsOf: Data("{\"ping\":true}\n".utf8))
                guard try self.readReply(timeout: 12).type == "ready" else {
                    throw ClipboardError.message("Jev health check failed.")
                }
                DispatchQueue.main.async { completion?(true) }
            } catch {
                self.stopProcess()
                self.report("Jev stopped — restarting…", false)
                DispatchQueue.main.async { completion?(false) }
                self.scheduleStart()
            }
        }
    }

    private func readReply(timeout: TimeInterval) throws -> WorkerReply {
        // poll bounds pipe reads; a hung GPU never blocks the main thread indefinitely.
        guard let output else { throw ClipboardError.message("Model pipe closed.") }
        let deadline = Date().addingTimeInterval(timeout)
        var buffer = Data()
        while Date() < deadline {
            var fd = pollfd(fd: output.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&fd, 1, 100)
            if ready < 0 { throw ClipboardError.message("Model pipe failed.") }
            if ready == 0 { continue }
            guard let byte = try output.read(upToCount: 1), !byte.isEmpty else {
                throw ClipboardError.message("Model worker exited.")
            }
            if byte[0] == 10 { return try JSONDecoder().decode(WorkerReply.self, from: buffer) }
            buffer.append(byte)
            if buffer.count > 64_000 { throw ClipboardError.message("Invalid model response.") }
        }
        throw ClipboardError.message("Jev timed out. Try again after it restarts.")
    }

    private func report(_ message: String, _ ready: Bool) {
        DispatchQueue.main.async { [weak self] in self?.onState?(message, ready) }
    }

    private func stopProcess() {
        lock.lock()
        defer { lock.unlock() }
        if process?.isRunning == true { process?.terminate() }
        try? input?.close()
        try? output?.close()
        input = nil; output = nil; process = nil
    }

    func stop() {
        // Terminate promptly, but only the serial I/O queue may close its handles.
        // Closing a Foundation handle during another thread's write raises an NSException.
        lock.lock()
        enabled = false
        if process?.isRunning == true { process?.terminate() }
        lock.unlock()
        queue.async { [weak self] in self?.stopProcess() }
    }
}
