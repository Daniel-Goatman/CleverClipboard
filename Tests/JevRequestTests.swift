import Foundation

@main struct JevRequestTests {
    static func main() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let fixtures = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
        for fixture in fixtures {
            let actual = try JevRequest.make(fixture["payload"] as! [String: Any])
            let expected = fixture["request"] as! [String: Any]
            precondition(NSDictionary(dictionary: actual.body).isEqual(to: expected), "Native request parity failed: \(fixture["name"]!)")
            precondition(actual.ids == fixture["ids"] as! [String])
            precondition(try! JevRequest.encode(actual.body).count <= JevRequest.maximumBytes)
        }
        let ids = ["phone", "email"]
        func response(_ confidence: Any, choice: String = "C0", probabilities: [String: Any] = ["C0":0.51,"C1":0.49,"NONE":0]) -> [String: Any] {
            ["model": JevRequest.model, "answers": ["pick": ["type":"choice", "choice": choice,
                "confidence": confidence, "probabilities": probabilities]]]
        }
        for confidence in [0.0, 0.69, 0.7] {
            let result = try JevRequest.result(response(confidence), ids: ids)
            precondition(result.usesLatestClipboard && result.fallback_reason == "low_confidence")
            precondition(result.model_choice == "phone" && result.ranked.isEmpty)
        }
        for confidence in [0.700001, 0.71, 0.99] {
            let result = try JevRequest.result(response(confidence), ids: ids)
            precondition(!result.usesLatestClipboard && result.ranked.first?.id == "phone", "Jev's choice must not be overridden")
        }
        let none = try JevRequest.result(response(1, choice: "NONE", probabilities: ["C0":0,"C1":0,"NONE":1]), ids: ids)
        precondition(none.usesLatestClipboard && none.fallback_reason == "no_match")
        let flat = try JevRequest.result(response(0.01, probabilities: ["C0":0.34,"C1":0.33,"NONE":0.33]), ids: ids)
        precondition(flat.usesLatestClipboard)
        var badModel = response(1); badModel["model"] = "other"
        for invalid in [badModel, response(true), response(Double.nan), response(1, choice: "invented"),
                        response(1, probabilities: ["C0": 0.5, "C1": 0.1, "NONE":0]),
                        response(1, choice: "C1"), response(1, probabilities: ["C0":true,"C1":0,"NONE":0])] {
            do { _ = try JevRequest.result(invalid, ids: ids); fatalError("Invalid response accepted") }
            catch ClipboardError.message { }
        }
        precondition(JevRequest.containsSecret(["nested":["test-key"]], key: "test-key"))
        print("PASS: \(fixtures.count) native/Python request fixtures; Jev-only decisions, confidence boundary, NONE, invalid responses")
    }
}
