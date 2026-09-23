import AppKit
import Vision

@main struct PanelTests {
    static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let panel = PreviewPanel()
        panel.appearance = NSAppearance(named: .aqua)
        panel.show(title: "Suggested clipboard item",
                   detail: "Sample data · model timing not yet measured\nReview the text, then press ⌘⇧V again to paste.",
                   fullText: "hello@example.com",
                   rows: [("●  hello@example.com", "Email from Contacts", {}),
                          ("    21 Paperbark Lane, Perth WA 6000", "Address from Maps", {}),
                          ("    Let's meet at 10 tomorrow.", "Message from Notes", {})],
                   paste: {}, cancel: {})
        guard let view = panel.contentView else { fatalError("Missing content") }
        view.layoutSubtreeIfNeeded()
        precondition(!panel.canBecomeKey && !panel.canBecomeMain)
        precondition(panel.frame.width == 430)
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage: bitmap.cgImage!).perform([request])
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        precondition(text.contains("hello@example.com"), "Rendered email must be readable by OCR")
        precondition(text.contains("Cancel"), "Footer must remain visible")
        panel.dismiss()
        precondition(!panel.isVisible && panel.contentView == nil)
        print("PASS: native preview render, readable sample OCR, nonactivating focus, visible footer, clear on dismiss")
    }
}
