import AppKit
import SwiftUI
import Vision

/// Production Settings and menu presentation with synthetic permission states only.
@main struct PermissionPresentationTests {
    static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let model = SettingsModel()
        model.connected = true
        for granted in [false, true, false] {
            model.accessibilityAllowed = granted
            model.screenRecordingAllowed = granted
            for name in ["Accessibility", "Screen Recording"] {
                let item = SettingsModel.permissionMenuItem(name, allowed: granted, symbol: "accessibility", action: NSSelectorFromString("manage:"), target: nil)
                precondition(item.title == (granted ? "\(name): Granted" : "Allow \(name)…"))
                precondition(item.image != nil && item.action != nil)
                precondition(item.toolTip!.contains("System Settings"))
            }
        }
        let host = NSHostingView(rootView: SettingsView(model: model))
        host.frame = NSRect(x: 0, y: 0, width: 740, height: 580)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        CarbonTheme.apply(to: window); window.styleMask.remove(.fullSizeContentView)
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000)); window.orderFront(nil)
        // Change the same visible view through its production timer refresh callback.
        for granted in [false, true, false] {
            var refreshes = 0
            model.onRefresh = {
                refreshes += 1
                model.accessibilityAllowed = granted
                model.screenRecordingAllowed = granted
            }
            RunLoop.current.run(until: Date().addingTimeInterval(1.3))
            precondition(refreshes > 0, "Visible Settings must refresh without app activation")
            host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let name = granted ? "granted" : "denied"
            try bitmap.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name + ".png"))
            let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
            try VNImageRequestHandler(cgImage: bitmap.cgImage!).perform([request])
            let strings = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            let text = strings.joined(separator: " ")
            for label in ["Accessibility", "Screen Recording", "Required", "Optional"] {
                precondition(text.contains(label), "Missing \(label): \(text)")
            }
            let expected = granted ? "Granted" : "Not granted"
            precondition(strings.filter { $0 == expected }.count == 2, "Both permission rows must show \(expected): \(text)")
            if granted { precondition(!text.contains("Not granted") && !text.contains("Allow Accessibility")) }
        }
        window.orderOut(nil)
        print("PASS: menu granted/denied/revoked states and visible Settings timer refresh with two rendered status labels")
    }
}
