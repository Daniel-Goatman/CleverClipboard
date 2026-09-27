import AppKit
import SwiftUI
import Vision

@main struct SmartPasteErrorTests {
    static func main() throws {
        let denied = SmartPasteFailure(message: "Allow Accessibility in System Settings, then try again.", reason: .accessibility)
        precondition(denied.recovery == .accessibility && denied.detail.contains("Applications"))
        let screen = SmartPasteFailure(message: "", reason: .screen_recording)
        precondition(screen.recovery == .screenRecording)
        let granted = SmartPasteFailure(message: "", reason: .accessibility, accessibilityAllowed: true)
        precondition(granted.recovery == nil && granted.detail.contains("granted now"))
        let screenGranted = SmartPasteFailure(message: "", reason: .screen_recording, screenRecordingAllowed: true)
        precondition(screenGranted.recovery == nil && screenGranted.detail.contains("granted now"))
        let secure = SmartPasteFailure(message: "", reason: .secure_input)
        precondition(!secure.detail.contains("Allow") && secure.detail.contains("Secure keyboard input"))
        let storage = SmartPasteFailure(message: "Could not save the Smart Paste dataset. Nothing was pasted.", reason: .native_error)
        precondition(storage.detail.contains("save this attempt") && storage.recovery == nil)
        let postStorage = SmartPasteFailure(message: "Paste events were sent, but the dataset outcome could not be saved. Check available disk space.", reason: .native_error)
        precondition(postStorage.title == "Dataset recording incomplete" && postStorage.recovery == nil)
        let network = SmartPasteFailure(message: "Could not reach TypeSafe. Check your connection and try again.", reason: .native_error)
        precondition(network.recovery == .settings && network.detail.contains("internet"))
        let changed = SmartPasteFailure(message: "", reason: .clipboard_changed)
        precondition(changed.recovery == nil && changed.detail.contains("clipboard changed"))
        let untrusted = "synthetic-private-clipboard-value"
        let unknown = SmartPasteFailure(message: untrusted, reason: .native_error)
        precondition(!unknown.detail.contains(untrusted))
        precondition(SmartPasteFailure(message: "", reason: .secure_input).recovery == nil)
        print("PASS: error recovery routing and arbitrary-error-content exclusion")
        guard let index = CommandLine.arguments.firstIndex(of: "--render"), CommandLine.arguments.indices.contains(index + 1) else { return }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let out = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let controller = SmartPasteErrorWindow()
        controller.configure(denied, recover: { _ in })
        precondition(controller.panel.styleMask.contains(.nonactivatingPanel))
        precondition(controller.panel.level == .floating && !controller.panel.hidesOnDeactivate)
        precondition(!controller.panel.isVisible)
        let original = controller.panel
        controller.configure(network, recover: { _ in })
        precondition(controller.panel === original, "Repeated failures must reuse one panel")
        controller.dismiss()
        precondition(!controller.panel.isVisible && controller.panel.contentView == nil)
        for (name, failure, required) in [
            ("accessibility", denied, ["Nothing was pasted", "Dismiss", "Open Accessibility Settings", "Applications"]),
            ("accessibility-granted", granted, ["Accessibility is granted now", "Dismiss"]),
            ("screen-granted", screenGranted, ["Screen Recording is granted now", "Dismiss"]),
            ("secure-input", secure, ["Secure keyboard input", "Dismiss"]),
            ("storage", storage, ["Nothing was pasted", "save this attempt", "Dismiss"]),
            ("storage-after-paste", postStorage, ["Dataset recording incomplete", "Paste events were sent", "Dismiss"]),
            ("connection", network, ["Nothing was pasted", "Dismiss", "Open Cuekit Settings", "internet"]),
            ("clipboard-changed", changed, ["Nothing was pasted", "Dismiss", "clipboard changed"])
        ] {
            let host = NSHostingView(rootView: SmartPasteErrorView(failure: failure, dismiss: {}, recover: { _ in }))
            let size = host.fittingSize
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
            CarbonTheme.apply(to: window); window.styleMask.remove(.fullSizeContentView)
            window.contentView = host
            window.setFrameOrigin(NSPoint(x: -10000, y: -10000)); window.orderFront(nil)
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name + ".png"))
            let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
            try VNImageRequestHandler(cgImage: bitmap.cgImage!).perform([request])
            let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
            for word in required { precondition(text.localizedCaseInsensitiveContains(word), "Missing rendered control: \(word) in \(text)") }
            precondition(!text.contains(untrusted))
            if failure.recovery == nil { precondition(!text.contains("Open Cuekit Settings")) }
            window.orderOut(nil)
        }
        print("PASS: offscreen production error views, readable recovery controls, nonactivating panel reuse and dismissal")
    }
}
