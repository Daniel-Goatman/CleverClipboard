import Foundation

@main struct CombinedBridgeTests {
    static func main() throws {
        let at = Date(timeIntervalSince1970: 1_700_000_000)
        func source(_ label: String) -> ClipProvenance {
            ClipProvenance(sourceApp: "Safari", sourceBundleID: "com.apple.Safari", writer: nil,
                foregroundAtPoll: "Mail", association: "keyboard_copy", windowTitle: "Q3",
                fieldLabel: label, fieldIdentifier: label.lowercased(), declaredSource: nil)
        }
        var history = History()
        precondition(history.add("1200", app: "Safari", provenance: source("Revenue"), at: at))
        precondition(history.add("1200", app: "Safari", provenance: source("Deposit"), at: at.addingTimeInterval(1)))
        precondition(history.addImage(id: "receipt", dataCount: 100, type: "public.png", app: "Safari"))
        guard let revision = history.items.first(where: { $0.id == "receipt" })?.imageRevision else { fatalError() }
        let ocr = ImageOCR.result(from: [
            OCRBlock(text: "Bread", confidence: 0.97, x: 0.05, y: 0.80, width: 0.3, height: 0.1),
            OCRBlock(text: "$12.00", confidence: 0.31, x: 0.75, y: 0.80, width: 0.2, height: 0.1)])
        precondition(history.updateOCR(id: "receipt", imageRevision: revision, result: ocr))
        let reloaded = try JSONDecoder().decode([Clip].self, from: JSONEncoder().encode(history.items))
        var restored = History(); restored.restore(reloaded)
        let candidates = ClipboardSelection.candidates(history: restored, pins: [], destinationRole: "AXTextArea")
        precondition(candidates.count == 2)
        guard let text = candidates.first(where: { $0.kind == .text }) else { fatalError() }
        precondition(text.text == "1200")
        precondition(text.candidateSourceContext?.contains("Revenue") == true)
        precondition(text.candidateSourceContext?.contains("Deposit") == true)
        var longSource = text
        longSource.candidateSourceContext = String(repeating: "A", count: 250) +
            "DISTINCT-SOURCE-LABEL" + String(repeating: "B", count: 550)
        let shortened = ModelWorker.requestPayload(context: "Input label: Revenue", clips: [longSource])
        let shortenedItem = (shortened["items"] as! [[String: Any]])[0]
        precondition(shortenedItem["source_context_truncated"] as? Bool == true)
        let payload = ModelWorker.requestPayload(context: "Input label: Revenue", clips: candidates, now: at.addingTimeInterval(2))
        let wrapped: [String: Any] = ["payload": payload, "text_id": text.id, "original_text": text.text]
        let output = try JSONSerialization.data(withJSONObject: wrapped, options: [.sortedKeys])
        FileHandle.standardOutput.write(output)
    }
}
