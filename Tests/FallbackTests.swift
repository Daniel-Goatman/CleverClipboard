import Foundation

@main struct FallbackTests {
    static func main() {
        var reply = SelectionReply()
        reply.decision = "latest"; reply.fallback_reason = "low_confidence"
        precondition(reply.usesLatestClipboard)
        reply.fallback_reason = "no_match"
        precondition(reply.usesLatestClipboard)
        reply.decision = "jev"
        precondition(!reply.usesLatestClipboard)
        reply.decision = "latest"; reply.type = "error"
        precondition(!reply.usesLatestClipboard)
        reply.type = "result"; reply.ranked = [RankedClip(id: "selected", score: 0.9)]
        precondition(!reply.usesLatestClipboard)
        print("PASS: explicit low-confidence/no-match fallback; errors and selected results cannot fall back")
    }
}
