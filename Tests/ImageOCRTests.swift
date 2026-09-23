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
        precondition(words.contains("412"), "OCR did not find synthetic order number: \(words)")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("jev-ocr-\(UUID().uuidString).tiff")
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url)
        guard let thumb = ImageThumbnail.shared.load(url), thumb.size.width <= 128, thumb.size.height <= 128 else {
            fatalError("Image preview was not downsampled")
        }
        print("PASS: bounded local image OCR and thumbnail decode")
    }
}
