import Foundation

enum CandidateText {
    static func forClip(_ clip: Clip, candidateCount: Int) -> String {
        let limit = min(1600, 12000 / max(1, candidateCount))
        let source = clip.candidateText
        let bytes = Array(source.utf8)
        if bytes.count <= limit { return source }
        let frontCount = limit * 3 / 4
        let backCount = limit / 4 - 8
        let front = validUTF8Prefix(Array(bytes.prefix(frontCount)))
        let back = validUTF8Suffix(Array(bytes.suffix(max(0, backCount))))
        return front + " … " + back
    }
    private static func validUTF8Prefix(_ bytes: [UInt8]) -> String {
        var data = bytes
        while !data.isEmpty {
            if let value = String(bytes: data, encoding: .utf8) { return value }
            data.removeLast()
        }
        return ""
    }
    private static func validUTF8Suffix(_ bytes: [UInt8]) -> String {
        var data = bytes
        while !data.isEmpty {
            if let value = String(bytes: data, encoding: .utf8) { return value }
            data.removeFirst()
        }
        return ""
    }
}
