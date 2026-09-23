import AppKit
import ImageIO
import Vision

struct ImageOCR {
    static func recognize(_ data: Data) -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData,
                  [kCGImageSourceShouldCache: false] as CFDictionary),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 3000
              ] as CFDictionary) else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        do { try VNImageRequestHandler(cgImage: cgImage).perform([request]) }
        catch { return "" }
        return String((request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " · ").prefix(1200))
    }
}
