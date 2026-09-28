import Foundation

@main struct DiagnosticsTests {
    static func main() throws {
        try testDatasetOptIn()
        try testDataset()
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
        precondition(PasteReason.classify("Accessibility was unavailable for this attempt. Check permissions in Settings, then try again.") == .accessibility)
        let privateMessage = "secret-example@example.org and private OCR text"
        let reason = PasteReason.classify(privateMessage)
        precondition(reason == .native_error)
        precondition(!lines.joined().contains(privateMessage))
        precondition(PasteReason.classify("Focused input changed. Try again.") == .input_changed)
        precondition(PasteReason.classify("Clipboard changed before pasting. Try again.") == .clipboard_changed)
        precondition(PasteReason.classify("No copied text matches this field's format. Copy a suitable value or use History.") == .no_match)
        precondition(PasteReason.classify("Paste destination changed. Try again.") == .input_changed)
        precondition(PasteReason.classify("Input text or cursor changed while reading context. Try again.") == .text_or_cursor_changed)
        precondition(PasteReason.classify("Smart paste is disabled while secure keyboard input is active.") == .secure_input)
        precondition(PasteReason.classify("Allow Accessibility in System Settings, then try again.") == .accessibility)
        if CommandLine.arguments.contains("--emit") {
            let production = PasteTrace()
            production.record(.accepted, count: 0)
            production.record(.failed, reason: .secure_input)
            print("Synthetic production-sink request=\(production.id.uuidString)")
        }
        print("PASS: correlated numeric diagnostics, busy state, one terminal outcome, static reasons and unknown-message privacy")
    }
    static func testDatasetOptIn() throws {
        // Volatile preferences never write the user's actual recording setting.
        let defaults = UserDefaults(suiteName: "cleverclipboard-test-\(UUID().uuidString)")!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cleverclipboard-opt-in-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        precondition(defaults.object(forKey: SmartPasteDataset.recordingPreference) == nil)
        let absent = try SmartPasteDataset.beginIfEnabled(defaults: defaults, root: root)
        precondition(absent == nil, "Fresh installs must not record")
        precondition(!FileManager.default.fileExists(atPath: root.path), "Disabled recording must not create the directory")

        defaults.setVolatileDomain([SmartPasteDataset.recordingPreference: true], forName: UserDefaults.argumentDomain)
        let enabled = try SmartPasteDataset.beginIfEnabled(defaults: defaults, root: root)
        precondition(enabled != nil, "Explicit opt-in must start recording")
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        precondition(files.count == 1 && files[0].pathExtension == "jsonl")
        let original = try Data(contentsOf: files[0])

        defaults.setVolatileDomain([SmartPasteDataset.recordingPreference: false], forName: UserDefaults.argumentDomain)
        let disabled = try SmartPasteDataset.beginIfEnabled(defaults: defaults, root: root)
        precondition(disabled == nil, "Opt-out must stop new journals")
        let remaining = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        let preserved = try Data(contentsOf: files[0])
        precondition(remaining == files && preserved == original, "Opt-out must preserve existing records")

        // An unusable output path must not break Smart Paste when recording is off.
        let invalid = files[0].appendingPathComponent("not-a-directory")
        let skipped = try SmartPasteDataset.beginIfEnabled(defaults: defaults, root: invalid)
        precondition(skipped == nil)
        defaults.setVolatileDomain([SmartPasteDataset.recordingPreference: true], forName: UserDefaults.argumentDomain)
        do {
            _ = try SmartPasteDataset.beginIfEnabled(defaults: defaults, root: invalid)
            fatalError("Enabled recording must still fail closed on a storage error")
        } catch { }
        print("PASS: dataset default off, explicit opt-in, opt-out preserves records, disabled recording bypasses storage failures")
    }

    static func testDataset() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cleverclipboard-attempts-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        for reason in [PasteReason.accessibility, .worker_unavailable, .worker_busy, .secure_input] {
            let dataset = try SmartPasteDataset(root: root)
            let trace = PasteTrace(dataset: dataset, sink: { _ in })
            precondition(trace.id == dataset.id)
            trace.record(.accepted)
            trace.record(.failed, reason: reason)
            trace.record(.paste_posted) // Must not overwrite a terminal failure.
            try trace.checkRecording()
        }
        let cancelled = try SmartPasteDataset(root: root)
        let trace = PasteTrace(dataset: cancelled, sink: { _ in })
        trace.record(.accepted); trace.record(.cancelled, reason: .user_cancelled)
        let posted = try SmartPasteDataset(root: root)
        let successful = PasteTrace(dataset: posted, sink: { _ in })
        successful.record(.accepted); successful.record(.paste_prepared); successful.record(.paste_posted)
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        precondition(files.count == 6)
        for file in files {
            let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as! NSNumber
            precondition(mode.intValue == 0o600)
            let content = try String(contentsOf: file, encoding: .utf8)
            let rows = try content.split(separator: "\n").map { try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any] }
            precondition(rows.enumerated().allSatisfy { ($0.element["sequence"] as? Int) == $0.offset })
            precondition((rows[0]["data"] as! [String: Any])["label_status"] as? String == "unlabelled")
            let stages = rows.dropFirst().map { ($0["data"] as! [String: Any])["stage"] as! String }
            precondition(stages.filter { ["failed", "cancelled", "paste_posted"].contains($0) }.count == 1)
        }
        let broken = try SmartPasteDataset(root: root)
        do { try broken.append("test", ["invalid": Double.infinity]); fatalError("Invalid record accepted") }
        catch { }
        do { try broken.check(); fatalError("Recording failure was not sticky") } catch { }
        let link = root.appendingPathComponent("linked")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
        do { _ = try SmartPasteDataset(root: link); fatalError("Symlink accepted") } catch { }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        do { _ = try SmartPasteDataset(root: root); fatalError("Public directory accepted") } catch { }
        print("PASS: per-attempt private durable journals, early/busy failures, cancellation, dispatch, sticky write failure and unsafe directory rejection")
    }

}
