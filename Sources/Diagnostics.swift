import Foundation
import OSLog
import Darwin

enum PasteStage: String {
    case accepted, busy, snapshot_started, snapshot_ready
    case windows_started, windows_ready, screenshot_started, screenshot_ready, ocr_started, ocr_ready
    case validation_started, validation_ready, ranking_started, ranking_ready, paste_prepared
    case modifiers_waiting, modifiers_released, latest_clipboard, paste_posted, failed, cancelled
}

enum PasteReason: String {
    case none, user_cancelled, worker_unavailable, empty_history, accessibility, secure_input
    case screen_recording, shutdown, no_input, not_editable, window_unidentified, app_changed, window_changed, input_changed
    case text_or_cursor_changed, clipboard_changed, lease_invalid, no_match, modifiers_held
    case event_creation, clipboard_write, worker_busy, worker_timeout, worker_error, native_error

    // Exact allowlist: unknown/native errors are never copied into diagnostics.
    static func classify(_ message: String) -> PasteReason {
        switch message {
        case "Copy some text first. Laya remembers new copies while running.": return .empty_history
        case "Allow Accessibility in System Settings, then try again.", "Accessibility was unavailable for this attempt. Check permissions in Settings, then try again.": return .accessibility
        case "Allow Screen Recording in System Settings to use window context.": return .screen_recording
        case "Smart paste is disabled while secure keyboard input is active.", "Smart paste is disabled in secure fields.": return .secure_input
        case "Select a text field in another app first.", "This app does not expose a focused input. Use clipboard history from the menu.": return .no_input
        case "Select an editable text field first. You can also copy an item from the menu.": return .not_editable
        case "Could not identify the focused window. Try selecting the input again.": return .window_unidentified
        case "Active app changed. Select the destination and try again.": return .app_changed
        case "Active window changed. Try again.": return .window_changed
        case "Focused input changed. Try again.", "Paste destination changed. Try again.": return .input_changed
        case "Input text or cursor changed during selection. Try again.", "Input text or cursor changed while reading context. Try again.": return .text_or_cursor_changed
        case "Clipboard changed. Press ⌘⇧V to try again.", "Clipboard changed before pasting. Try again.": return .clipboard_changed
        case "Clipboard changed or selection timed out. Try again.": return .lease_invalid
        case "No clear clipboard match. Choose an item from History.", "No matching clipboard text.", "No copied text matches this field's format. Copy a suitable value or use History.": return .no_match
        case "Release the shortcut keys and try again.": return .modifiers_held
        case "macOS could not create a paste event.": return .event_creation
        case "Could not prepare the clipboard.": return .clipboard_write
        case "Jev is finishing the previous selection. Try again in a moment.": return .worker_busy
        case "Jev timed out. Try again after it restarts.": return .worker_timeout
        case "Jev is unavailable. Restart it from the menu.", "Model worker exited.", "Model pipe closed.", "Model pipe failed.", "Invalid model response.": return .worker_error
        default: return .native_error
        }
    }
}

/// No content-bearing string parameter is accepted by the logging interface.
final class PasteTrace: @unchecked Sendable {
    let id: UUID
    let dataset: SmartPasteDataset?
    private let start = ProcessInfo.processInfo.systemUptime
    private let lock = NSLock()
    private var ended = false
    private var stage = PasteStage.accepted
    private let sink: (String) -> Void

    init(dataset: SmartPasteDataset? = nil, sink: @escaping (String) -> Void = { line in
        // Static reason codes, request IDs and numeric timings only; no user content.
        Logger(subsystem: "local.daniel.LayaClipboard", category: "diagnostics").notice("\(line, privacy: .public)")
    }) { self.sink = sink; self.dataset = dataset; self.id = dataset?.id ?? UUID() }

    func checkRecording() throws { try dataset?.check() }

    func record(_ event: PasteStage, reason: PasteReason = .none,
                count: Int = -1, modelMS: Double = -1, queueMS: Double = -1, waitMS: Double = -1, errorCode: Int = 0) {
        lock.lock(); defer { lock.unlock() }
        guard !ended else { return }
        let previous = stage
        if event != .busy { stage = event }
        if [.paste_posted, .failed, .cancelled].contains(event) { ended = true }
        let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1000
        do {
            try dataset?.append("stage", ["stage": event.rawValue, "after": previous.rawValue,
                "reason": reason.rawValue, "elapsed_ms": elapsed, "count": count,
                "model_ms": modelMS, "error_code": errorCode])
        } catch { /* The sticky error is checked before inference and paste dispatch. */ }
        sink(String(format: "request=%@ event=%@ after=%@ elapsed_ms=%.1f reason=%@ count=%d model_ms=%.1f queue_ms=%.1f wait_ms=%.1f error_code=%d",
                    id.uuidString, event.rawValue, previous.rawValue, elapsed, reason.rawValue,
                    count, modelMS, queueMS, waitMS, errorCode))
    }
}


/// One durable journal per invocation. Content enters only after JevClient's key checks.
/// Terminal stages describe dispatch, never target acceptance or correctness.
final class SmartPasteDataset: @unchecked Sendable {
    static let recordingPreference = "SaveSmartPasteDataset"

    /// Unset preferences are false. Check before opening or creating any dataset files.
    static func beginIfEnabled(defaults: UserDefaults = .standard,
                               root: URL = SmartPasteDataset.defaultRoot) throws -> SmartPasteDataset? {
        guard defaults.bool(forKey: recordingPreference) else { return nil }
        return try SmartPasteDataset(root: root)
    }

    enum Failure: LocalizedError {
        case write
        var errorDescription: String? { "Could not save the Smart Paste dataset. Nothing was pasted." }
    }
    static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Jev Clipboard/SmartPasteDataset", isDirectory: true)
    }
    let id = UUID()
    private let lock = NSLock()
    private var descriptor: Int32 = -1
    private var failed = false
    private var sequence = 0

    init(root: URL = SmartPasteDataset.defaultRoot) throws {
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
            let directory = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard directory >= 0 else { throw Failure.write }
            defer { close(directory) }
            var info = stat()
            guard fstat(directory, &info) == 0, info.st_uid == getuid(), info.st_mode & 0o077 == 0 else { throw Failure.write }
            descriptor = openat(directory, id.uuidString + ".attempt.jsonl", O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard descriptor >= 0 else { throw Failure.write }
            try append("attempt", ["schema_version": 3, "label_status": "unlabelled",
                "paste_outcome": "not_observed", "model": "jev-1.13.0"])
            guard fsync(directory) == 0 else { throw Failure.write }
        } catch {
            if descriptor >= 0 { close(descriptor); descriptor = -1 }
            throw Failure.write
        }
    }
    deinit { if descriptor >= 0 { close(descriptor) } }

    func check() throws {
        lock.lock(); defer { lock.unlock() }
        if failed { throw Failure.write }
    }
    func append(_ event: String, _ fields: [String: Any]) throws {
        lock.lock(); defer { lock.unlock() }
        guard !failed else { throw Failure.write }
        do {
            let object: [String: Any] = ["record_id": id.uuidString, "sequence": sequence,
                "timestamp": ISO8601DateFormatter().string(from: Date()), "event": event, "data": fields]
            guard JSONSerialization.isValidJSONObject(object) else { throw Failure.write }
            var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            data.append(0x0a)
            try data.withUnsafeBytes { buffer in
                var offset = 0
                while offset < buffer.count {
                    let written = Darwin.write(descriptor, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                    if written < 0 && errno == EINTR { continue }
                    guard written > 0 else { throw Failure.write }
                    offset += written
                }
            }
            guard fsync(descriptor) == 0 else { throw Failure.write }
            sequence += 1
        } catch { failed = true; throw Failure.write }
    }
}
