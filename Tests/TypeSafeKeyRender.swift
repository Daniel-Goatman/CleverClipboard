import AppKit
import SwiftUI

@main struct TypeSafeKeyRender {
    static func main() throws {
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for dark in [false, true] {
            for state in ["empty", "verifying", "invalid", "saved"] {
                var respond: ((Result<Void, Error>) -> Void)?
                let model = TypeSafeKeyModel(verify: { _, done in respond = done; return nil }, save: { _ in })
                if state != "empty" {
                    model.key = "synthetic-test-key-not-real"; model.submit()
                    if state == "invalid" { respond?(.failure(ClipboardError.message("TypeSafe rejected the API key. Update it from the menu."))) }
                    if state == "saved" { respond?(.success(())) }
                }
                let controller = TypeSafeKeyWindow(model: model)
                let window = controller.window!
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                window.orderFront(nil)
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
                window.layoutIfNeeded()
                let view = window.contentView!
                view.layoutSubtreeIfNeeded()
                guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("Cannot render key window") }
                view.cacheDisplay(in: view.bounds, to: rep)
                try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("\(dark ? "dark" : "light")-\(state).png"))
                window.orderOut(nil)
                precondition(view.bounds.width >= 440 && view.bounds.height > 200)
            }
        }
        print("Rendered actual secure-entry window in light/dark: empty, verifying, invalid, saved. No clipboard, Keychain or network access.")
    }
}
