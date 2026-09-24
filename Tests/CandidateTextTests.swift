import Foundation

@main struct CandidateTextTests {
    static func main() {
        let long = String(repeating: "A", count: 3000) + "DISTINGUISHING-MIDDLE" + String(repeating: "Z", count: 3000)
        let clips = [Clip(id: "short", text: "brief", app: "Notes", copiedAt: .now),
                     Clip(id: "long", text: long, app: "Notes", copiedAt: .now)]
        let excerpts = CandidateText.forClips(clips)
        precondition(excerpts[0] == "brief")
        precondition(excerpts[1].contains("DISTINGUISHING-MIDDLE"))
        precondition(excerpts[1].utf8.count > 1600)
        precondition(clips[1].text == long)
        let many = (0..<52).map { Clip(id: String($0), text: String(repeating: "🙂字", count: 1000), app: "Notes", copiedAt: .now) }
        let limited = CandidateText.forClips(many)
        precondition(limited.count == 52)
        precondition(limited.reduce(0) { $0 + $1.utf8.count } <= 12000)
        precondition(CandidateText.forClips(many) == limited)
    }
}
