import Foundation
import OSLog

enum PasteStage: String {
    case accepted, busy, snapshot_started, snapshot_ready
    case windows_started, windows_ready, screenshot_started, screenshot_ready, ocr_started, ocr_ready
    case validation_started, validation_ready, ranking_started, ranking_ready
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
        case "Allow Accessibility in System Settings, then try again.": return .accessibility
        case "Allow Screen Recording in System Settings to use window context.": return .screen_recording
        case "Smart paste is disabled while secure keyboard input is active.", "Smart paste is disabled in secure fields.": return .secure_input
        case "Accessibility is unavailable or secure keyboard input is active.": return .accessibility
        case "Select a text field in another app first.", "This app does not expose a focused input. Use clipboard history from the menu.": return .no_input
        case "Select an editable text field first. You can also copy an item from the menu.": return .not_editable
        case "Could not identify the focused window. Try selecting the input again.": return .window_unidentified
        case "Active app changed. Select the destination and try again.": return .app_changed
        case "Active window changed. Try again.": return .window_changed
        case "Focused input changed. Try again.": return .input_changed
        case "Input text or cursor changed during selection. Try again.": return .text_or_cursor_changed
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
    let id = UUID()
    private let start = ProcessInfo.processInfo.systemUptime
    private let lock = NSLock()
    private var ended = false
    private var stage = PasteStage.accepted
    private let sink: (String) -> Void

    init(sink: @escaping (String) -> Void = { line in
        #if CUEKIT_DEVELOPMENT
        Logger(subsystem: "local.daniel.LayaClipboard", category: "diagnostics").notice("\(line, privacy: .public)")
        #endif
    }) { self.sink = sink }

    func record(_ event: PasteStage, reason: PasteReason = .none,
                count: Int = -1, modelMS: Double = -1, queueMS: Double = -1, waitMS: Double = -1, errorCode: Int = 0) {
        lock.lock(); defer { lock.unlock() }
        guard !ended else { return }
        let previous = stage
        if event != .busy { stage = event }
        if [.paste_posted, .failed, .cancelled].contains(event) { ended = true }
        let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1000
        sink(String(format: "request=%@ event=%@ after=%@ elapsed_ms=%.1f reason=%@ count=%d model_ms=%.1f queue_ms=%.1f wait_ms=%.1f error_code=%d",
                    id.uuidString, event.rawValue, previous.rawValue, elapsed, reason.rawValue,
                    count, modelMS, queueMS, waitMS, errorCode))
    }
}
