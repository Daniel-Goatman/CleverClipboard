import Foundation
import Darwin

@main struct WorkerTests {
    static func main() {
        let worker = ModelWorker(root: URL(fileURLWithPath: CommandLine.arguments[1]), credential: { "synthetic-test-key-not-real" })
        var stage = 0
        var ended = false
        worker.onState = { message, ready in
            guard ready else { print("worker: \(message)"); return }
            if stage == 0 {
                stage = 1
                let clip = Clip(id: "email", text: "worker@example.org", app: "Fixture", copiedAt: Date())
                worker.select(context: "App: Test\nInput label: Email", clips: [clip]) { result in
                    guard case .success(let reply) = result, reply.ranked?.first?.id == "email" else {
                        fatalError("Live pipe selection failed: \(result)")
                    }
                    worker.keepWarm { success in
                        precondition(success, "Keepalive must receive a ready reply")
                        // Restart during a second keepalive to exercise the former handle-close race.
                        worker.keepWarm()
                        stage = 2
                        worker.stop()
                        worker.start()
                    }
                }
            } else if stage == 2 {
                stage = 3
                let clip = Clip(id: "url", text: "https://example.org", app: "Fixture", copiedAt: Date())
                let field = ContextField(role: "AXTextField", subrole: "", identifier: "fixture", attributes: [:], linkedLabels: ["Website URL"], bounds: [100,100,200,30])
                let context = try! FieldEvidence(app: "Fixture", bundleID: "fixture", windowTitle: "Form", field: field).encoded()
                worker.select(context: context, clips: [clip]) { result in
                    guard case .success(let reply) = result, reply.ranked?.first?.id == "url" else {
                        fatalError("Restarted pipe selection failed")
                    }
                    worker.select(context: "App: Safari\nInput label: Phone number", clips: [clip]) { result in
                        guard case .success(let reply) = result, reply.usesLatestClipboard else {
                            fatalError("No-match must reach native normal-paste fallback through the live pipe")
                        }
                        worker.stop()
                        ended = true
                        print("PASS: native worker startup/warmup, legacy and structured context selection, keepalive, restart and live no-match fallback")
                    }
                }
            }
        }
        worker.start()
        let deadline = Date().addingTimeInterval(60)
        while !ended && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
        worker.stop()
        precondition(ended, "Worker integration test timed out")
    }
}
