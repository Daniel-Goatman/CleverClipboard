import Foundation

enum CandidateText {
    // Only selection evidence is excerpted; the paste payload stays in Clip.
    static func forClips(_ clips: [Clip]) -> [String] {
        let sources = clips.map(\.candidateText)
        let sizes = sources.map { $0.utf8.count }
        var limits = Array(repeating: min(4000, 12000 / max(1, clips.count)), count: clips.count)
        var remaining = 12000 - zip(sizes, limits).reduce(0) { $0 + min($1.0, $1.1) }
        while remaining > 0 {
            var advanced = false
            for i in sizes.indices where limits[i] < min(sizes[i], 4000) && remaining > 0 {
                limits[i] += 1
                remaining -= 1
                advanced = true
            }
            if !advanced { break }
        }
        return zip(sources, limits).map { excerpt($0.0, limit: $0.1) }
    }

    static func forClip(_ clip: Clip, candidateCount: Int) -> String {
        excerpt(clip.candidateText, limit: min(1600, 12000 / max(1, candidateCount)))
    }

    static func excerpt(_ source: String, limit: Int) -> String {
        let bytes = Array(source.utf8)
        if bytes.count <= limit { return source }
        let marker = " … "
        if limit <= 2 * marker.utf8.count {
            return validUTF8Prefix(Array(bytes.prefix(max(0, limit))))
        }
        let usable = max(0, limit - 2 * marker.utf8.count)
        let headCount = usable * 2 / 5
        let middleCount = usable * 3 / 10
        let tailCount = usable - headCount - middleCount
        let middleStart = max(headCount, min((bytes.count - middleCount) / 2,
                                              bytes.count - tailCount - middleCount))
        let front = validUTF8Prefix(Array(bytes.prefix(headCount)))
        let middle = validUTF8Middle(Array(bytes[middleStart..<(middleStart + middleCount)]))
        let back = validUTF8Suffix(Array(bytes.suffix(tailCount)))
        return front + marker + middle + marker + back
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
    private static func validUTF8Middle(_ bytes: [UInt8]) -> String {
        for start in 0...min(3, bytes.count) {
            let slice = Array(bytes.dropFirst(start))
            let decoded = validUTF8Prefix(slice)
            if !decoded.isEmpty { return decoded }
        }
        return ""
    }
}
