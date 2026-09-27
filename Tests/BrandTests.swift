import AppKit
import SwiftUI

@main struct BrandTests {
    static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        precondition(AppBrand.name == "Cuekit")
        guard let icon = AppBrand.icon else { fatalError("Packaged Cuekit.icns is missing or unreadable") }
        precondition(icon.representations.count >= 8, "Icon must include multiple standard and Retina sizes")
        precondition(AppBrand.menuIcon.isTemplate)
        precondition(AppBrand.menuIcon.accessibilityDescription == "Cuekit")
        precondition(AppBrand.menuIcon.size == NSSize(width: 20, height: 18))
        guard let data = AppBrand.menuIcon.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: data) else { fatalError("Menu glyph does not render") }
        let pixels = (0..<bitmap.pixelsHigh).flatMap { y in
            (0..<bitmap.pixelsWide).compactMap { x in bitmap.colorAt(x: x, y: y)?.alphaComponent }
        }
        precondition(pixels.contains { $0 > 0.9 }, "Selected card must contain visible ink")
        precondition(pixels.contains { $0 == 0 }, "Menu glyph needs transparent negative space")
        precondition(pixels.filter { $0 > 0.1 }.count < pixels.count * 3 / 4,
                     "Glyph must remain line art, not a filled rectangle")

        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try write(icon, size: NSSize(width: 256, height: 256), to: output.appendingPathComponent("app-icon.png"))
        try write(AppBrand.menuIcon, size: NSSize(width: 200, height: 180), to: output.appendingPathComponent("menu-glyph.png"))

        let model = HistoryWindowModel()
        model.items = [Clip(id: "brand-fixture", text: "Synthetic clipboard item", app: "Fixture", copiedAt: Date())]
        let view = NSHostingView(rootView: HistoryWindowView(model: model))
        view.frame = NSRect(x: 0, y: 0, width: 820, height: 560)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.title = AppBrand.name
        window.contentView = view
        window.layoutIfNeeded()
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("History view did not render") }
        view.cacheDisplay(in: view.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("history-window.png"))
        print("Branding passed: packaged multiresolution icon, template glyph, transparent line art, synthetic history rendering")
    }

    static func write(_ image: NSImage, size: NSSize, to url: URL) throws {
        let canvas = NSImage(size: size)
        canvas.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.draw(in: NSRect(origin: .zero, size: size))
        canvas.unlockFocus()
        let rep = NSBitmapImageRep(data: canvas.tiffRepresentation!)!
        try rep.representation(using: .png, properties: [:])!.write(to: url)
    }
}
