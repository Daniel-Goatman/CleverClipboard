import AppKit
import ImageIO
import Vision

struct ImageOCR {
    static let maximumBlocks = 40
    static let maximumTextCharacters = 1200
    static let maximumBlockCharacters = 160

    // Visual ordering only; no receipt row, column, or field relationship is inferred.
    static func result(from observations: [OCRBlock]) -> OCRResult {
        let ordered = observations.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { a, b in
                let rowA = Int((a.y * 100).rounded()), rowB = Int((b.y * 100).rounded())
                if rowA != rowB { return rowA > rowB }
                if a.x != b.x { return a.x < b.x }
                return a.text < b.text
            }
        var blocks: [OCRBlock] = []
        var remaining = maximumTextCharacters
        var truncated = ordered.count > maximumBlocks
        for block in ordered.prefix(maximumBlocks) {
            let clean = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let budget = min(maximumBlockCharacters, remaining - (blocks.isEmpty ? 0 : 3))
            if budget <= 0 { truncated = true; break }
            let bounded = String(clean.prefix(budget))
            truncated = truncated || bounded.count < clean.count
            blocks.append(OCRBlock(text: bounded, confidence: min(1, max(0, block.confidence)),
                                   x: min(1, max(0, block.x)), y: min(1, max(0, block.y)),
                                   width: min(1, max(0, block.width)), height: min(1, max(0, block.height))))
            remaining -= bounded.count + (blocks.count == 1 ? 0 : 3)
        }
        return OCRResult(status: blocks.isEmpty ? .noText : .ready, blocks: blocks, truncated: truncated)
    }

    static func analyze(_ data: Data) -> OCRResult {
        guard let source = CGImageSourceCreateWithData(data as CFData,
                  [kCGImageSourceShouldCache: false] as CFDictionary),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 3000
              ] as CFDictionary) else { return OCRResult(status: .failed, blocks: [], truncated: false) }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        do { try VNImageRequestHandler(cgImage: cgImage).perform([request]) }
        catch { return OCRResult(status: .failed, blocks: [], truncated: false) }
        let blocks = (request.results ?? []).compactMap { observation -> OCRBlock? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox
            return OCRBlock(text: candidate.string, confidence: Double(candidate.confidence),
                            x: box.minX, y: box.minY, width: box.width, height: box.height)
        }
        return result(from: blocks)
    }

    // Saved-entry import currently stores only the compatibility text rendering.
    static func recognize(_ data: Data) -> String { analyze(data).plainText }
}
