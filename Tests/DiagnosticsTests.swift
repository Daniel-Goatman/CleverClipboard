import Foundation

@main struct DiagnosticsTests {
    static func main() {
        var lines: [String] = []
        let trace = PasteTrace { lines.append($0) }
        trace.record(.accepted, count: 50)
        trace.record(.ranking_started)
        trace.record(.busy)
        trace.record(.ranking_ready, count: 2, modelMS: 123, queueMS: 45)
        trace.record(.modifiers_waiting)
        trace.record(.failed, reason: .modifiers_held)
        trace.record(.cancelled, reason: .user_cancelled)
        trace.record(.paste_posted)
        precondition(lines.count == 6, "A failed request must have exactly one terminal event")
        precondition(lines.allSatisfy { $0.contains("request=\(trace.id.uuidString)") })
        precondition(lines[3].contains("after=ranking_started"), "Busy must not replace the running stage")
        precondition(lines[3].contains("count=2 model_ms=123.0 queue_ms=45.0"))
        precondition(lines[5].contains("reason=modifiers_held"))
        let privateMessage = "secret-example@example.org and private OCR text"
        let reason = PasteReason.classify(privateMessage)
        precondition(reason == .native_error)
        precondition(!lines.joined().contains(privateMessage))
        precondition(PasteReason.classify("Focused input changed. Try again.") == .input_changed)
        precondition(PasteReason.classify("Clipboard changed before pasting. Try again.") == .clipboard_changed)
        precondition(PasteReason.classify("No copied text matches this field's format. Copy a suitable value or use History.") == .no_match)
        print("PASS: correlated numeric diagnostics, busy state, one terminal outcome, static reasons and unknown-message privacy")
    }
}
