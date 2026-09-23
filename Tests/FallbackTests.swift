import Foundation

@main struct FallbackTests {
    static func main() throws {
        func decode(_ text: String) throws -> WorkerReply {
            try JSONDecoder().decode(WorkerReply.self, from: Data(text.utf8))
        }
        let latest = try decode(#"{"type":"result","ranked":[],"error":"No clear clipboard match. Choose an item from History."}"#)
        precondition(latest.usesLatestClipboard)
        for response in [
            #"{"type":"result","ranked":[],"error":"No pasteable clipboard item."}"#,
            #"{"type":"error","ranked":[],"error":"No clear clipboard match. Choose an item from History."}"#,
            #"{"type":"result","ranked":[],"error":"Selection failed. Try a smaller text clipboard."}"#,
            #"{"type":"result","ranked":[]}"#,
            #"{"type":"result","ranked":[{"id":"chosen","score":0.9}]}"#
        ] {
            let reply = try decode(response)
            precondition(!reply.usesLatestClipboard, "Only explicit model abstention may use ordinary paste")
        }
        print("PASS: model no-match uses latest; errors and selected items do not")
    }
}
