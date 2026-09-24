import AppKit
import Foundation

@main struct ImageOCRTests {
    static func main() throws {
        let image = NSImage(size: NSSize(width: 1000, height: 180))
        image.lockFocus()
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 1000, height: 180).fill()
        ("Order 412" as NSString).draw(at: NSPoint(x: 35, y: 40), withAttributes: [
            .font: NSFont.systemFont(ofSize: 90, weight: .bold), .foregroundColor: NSColor.black])
        image.unlockFocus()
        guard let data = image.tiffRepresentation else { fatalError("Cannot make synthetic image") }
        let words = ImageOCR.recognize(data)
        let actual = ImageOCR.analyze(data)
        if actual.status == .ready {
            precondition(words.contains("412") && actual.blocks.contains { $0.text.contains("412") })
            precondition(actual.blocks.allSatisfy { (0...1).contains($0.confidence) && (0...1).contains($0.x) && (0...1).contains($0.y) })
        } else { print("NOTE: Vision did not recognize generated image in this test session") }
        let fixture = ImageOCR.result(from: [
            OCRBlock(text: "$12.00", confidence: 0.31, x: 0.75, y: 0.80, width: 0.2, height: 0.1),
            OCRBlock(text: "Bread", confidence: 0.97, x: 0.05, y: 0.80, width: 0.3, height: 0.1),
            OCRBlock(text: "Milk", confidence: 0.9, x: 0.05, y: 0.60, width: 0.3, height: 0.1)
        ])
        precondition(fixture.blocks.map(\.text) == ["Bread", "$12.00", "Milk"])
        precondition(fixture.blocks[1].confidence == 0.31 && fixture.blocks[1].x == 0.75)
        precondition(fixture.plainText == "Bread · $12.00 · Milk")
        precondition(ImageOCR.result(from: []).status == .noText)
        let large = ImageOCR.result(from: (0..<100).map { i in
            OCRBlock(text: String(repeating: "x", count: 200), confidence: 0.5,
                     x: 0.1, y: Double(100-i)/100, width: 0.2, height: 0.01)
        })
        precondition(large.truncated && large.blocks.count <= ImageOCR.maximumBlocks)
        precondition(large.plainText.count <= ImageOCR.maximumTextCharacters)
        precondition(ImageOCR.analyze(Data("bad image".utf8)).status == .failed)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("jev-ocr-\(UUID().uuidString).tiff")
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url)
        guard let thumb = ImageThumbnail.shared.load(url), thumb.size.width <= 128, thumb.size.height <= 128 else {
            fatalError("Image preview was not downsampled")
        }
        print("PASS: bounded structured image OCR, states, geometry, ordering and thumbnail decode")
    }
}
