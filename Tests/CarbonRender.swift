import AppKit
import SwiftUI
import PDFKit
import Vision

/// Actual production views, synthetic data only. Never starts AppDelegate, reads the clipboard or Keychain, or calls TypeSafe.
@main struct CarbonRender {
    static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.regular)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        precondition(AppBrand.icon?.representations.count ?? 0 >= 8, "Packaged multi-resolution Carbon icon is required")
        precondition(AppBrand.menuIcon.isTemplate && AppBrand.menuIcon.size == NSSize(width: 20, height: 18))
        let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let model = HistoryWindowModel()
        let imageURL = out.appendingPathComponent("fixture-image.png")
        // Demo-only assets: use the real app artwork and a readable product overview.
        // Reserved .example addresses below are illustrative, never live contact details.
        var iconRect = CGRect(x: 0, y: 0, width: 512, height: 512)
        let icon = AppBrand.icon!.cgImage(forProposedRect: &iconRect, context: nil, hints: nil)!
        let imageData = NSBitmapImageRep(cgImage: icon).representation(using: .png, properties: [:])!
        try imageData.write(to: imageURL)
        let pdfURL = out.appendingPathComponent("fixture.pdf")
        let overview = DemoOverviewView(frame: NSRect(x: 0, y: 0, width: 595, height: 842))
        let pdfData = overview.dataWithPDF(inside: overview.bounds)
        try pdfData.write(to: pdfURL)
        let imageBytes = imageData.count, pdfBytes = pdfData.count
        let date = Date(timeIntervalSince1970: 1790416800)
        model.items = [
            Clip(id: "text", text: "Could you send me the Cuekit overview before our call?", app: "Mail", copiedAt: date),
            Clip(id: "link", text: "https://cuekit.example", app: "Safari", copiedAt: date),
            Clip(id: "image", text: "", app: "Preview", copiedAt: date, kind: .image, imageBytes: imageBytes),
            Clip(id: "pdf", text: "", app: "Finder", copiedAt: date, kind: .file, assetID: "pdf", fileName: "Cuekit overview.pdf", fileType: "com.adobe.pdf", fileBytes: pdfBytes)
        ]
        model.imageURL = { _ in imageURL }; model.fileURL = { _ in pdfURL }
        var photo = PinnedEntry(id: 1, description: "Cuekit app icon for listings and press kits", value: "")
        photo.kind = .image; photo.assetID = "photo"; photo.assetName = "Cuekit icon.png"; photo.assetType = "public.png"; photo.assetBytes = imageBytes
        var file = PinnedEntry(id: 2, description: "Cuekit product overview to share with new users", value: "")
        file.kind = .file; file.assetID = "pdf"; file.assetName = "Cuekit overview.pdf"; file.assetType = "com.adobe.pdf"; file.assetBytes = pdfBytes
        model.updatePins([PinnedEntry(id: 0, description: "Public website for Cuekit", value: "https://cuekit.example"), photo, file,
                          PinnedEntry(id: 3, description: "Cuekit support email", value: "support@cuekit.example")])
        model.assetURL = { $0.kind == .image ? imageURL : pdfURL }
        model.onSavePins = { [weak model] entries in model?.updatePins(entries); return true }
        model.onDelete = { [weak model] id in model?.items.removeAll { $0.id == id } }
        model.onClear = { [weak model] in model?.items.removeAll() }
        model.onCopy = { [weak model] _ in model?.message = "Copied (synthetic fixture)" }
        let settings = SettingsModel(); settings.connected = true; settings.accessibilityAllowed = true
        settings.connectionStatus = "Connected to TypeSafe (synthetic fixture)"
        let size = NSSize(width: 1000, height: 680)
        if !CommandLine.arguments.contains("--interactive-only") {
        try render(HistoryWindowView(model: model), size: size, name: "history", out: out, required: ["History", "Always Available", "Copy", "Clear History"], forbidden: ["Pause", "Resume"])
        model.beginEditing(); model.drafts[3].description = "Support email address for Cuekit"
        try render(HistoryWindowView(model: model, initialTab: 1), size: size, name: "always-available", out: out, required: ["Description", "Value", "Save Changes", "Unsaved changes"])
        try render(HistoryWindowView(model: model, initialTab: 1), size: NSSize(width: 820, height: 560), name: "always-available-minimum", out: out, required: ["Save Changes", "Add Entry"])
        for page in SettingsPage.allCases {
            try render(SettingsView(model: settings, initialPage: page), size: NSSize(width: 840, height: 640), name: "settings-\(page.rawValue.replacingOccurrences(of: " ", with: "-").lowercased())", out: out, required: page == .general ? ["Clipboard collection", "Open Clipboard"] : (page == .smartPaste ? ["Smart Paste", "Granted", "Required", "Optional"] : [page.rawValue]), forbidden: ["Privacy", "Pause", "Resume", "Carbon"])
        }
        try render(SettingsView(model: settings, initialPage: .general), size: NSSize(width: 740, height: 580), name: "settings-general-minimum", out: out, required: ["History", "Always Available", "Open Clipboard"], forbidden: ["Privacy", "Pause", "Resume", "Carbon"])
        settings.connected = false; settings.accessibilityAllowed = false; settings.shortcutRegistered = false
        try render(SettingsView(model: settings), size: NSSize(width: 740, height: 580), name: "settings-unavailable", out: out, required: ["Unavailable", "Not granted", "Required", "Optional"], forbidden: ["Carbon"])
        let empty = HistoryWindowModel()
        try render(HistoryWindowView(model: empty), size: size, name: "empty-history", out: out, required: ["Your clipboard starts here"])
        try render(HistoryWindowView(model: empty, initialTab: 1), size: size, name: "empty-saved", out: out, required: ["Always within reach"])
        if !CommandLine.arguments.contains("--offscreen") { try measureSwitching(model: model, out: out) }
        print("PASS: rendered production Carbon views with synthetic fixtures; required controls detected by OCR")
        }
        if CommandLine.arguments.contains("--interactive") || CommandLine.arguments.contains("--interactive-only") {
            let menu = NSMenu(); let edit = NSMenu(); let item = NSMenuItem(); item.submenu = edit; menu.addItem(item)
            for (title, selector, key) in [("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a"), ("Undo", "undo:", "z")] {
                edit.addItem(withTitle: title, action: Selector(selector), keyEquivalent: key)
            }
            NSApp.mainMenu = menu
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            CarbonTheme.apply(to: window); window.title = "Carbon UI fixture"
            if CommandLine.arguments.contains("--settings") {
                window.contentView = NSHostingView(rootView: SettingsView(model: settings, initialPage: CommandLine.arguments.contains("--general") ? .general : .smartPaste))
            } else {
                window.contentView = NSHostingView(rootView: HistoryWindowView(model: model, initialTab: 1))
            }
            window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
            withExtendedLifetime(window) { NSApp.run() }
        }
    }
    static func measureSwitching(model: HistoryWindowModel, out: URL) throws {
        let host = NSHostingView(rootView: HistoryWindowView(model: model))
        host.frame = NSRect(x: 0, y: 0, width: 1000, height: 680)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        CarbonTheme.apply(to: window); window.contentView = host; window.orderFront(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        var timings: [Double] = []
        for index in 0..<14 {
            let start = ProcessInfo.processInfo.systemUptime
            model.selectedTab = index % 2
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
            let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1000
            if index >= 4 { timings.append(elapsed) }
        }
        let maxMS = timings.max() ?? 0
        let report: [String: Any] = ["layout_and_display_ms": timings, "max_ms": maxMS,
            "scope": "Production views, warm tab switches with 4 synthetic history and saved entries; includes a 10ms runloop interval, not end-to-end input latency"]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: out.appendingPathComponent("tab-switch-timing.json"))
        precondition(maxMS < 250, "Tab layout/display stalled: \(maxMS) ms")
        window.orderOut(nil)
    }
        static func render<V: View>(_ view: V, size: NSSize, name: String, out: URL, required: [String], forbidden: [String] = []) throws {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        CarbonTheme.apply(to: window); window.contentView = host
        if CommandLine.arguments.contains("--offscreen") {
            window.setFrameOrigin(NSPoint(x: -10000, y: -10000)); window.orderFront(nil)
        } else {
            window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        window.layoutIfNeeded(); host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        // AppKit cacheDisplay omits SwiftUI scroll layers under full-size titlebars.
        // Capture content with the standard content rect; verify full window chrome in the live fixture.
        window.styleMask.remove(.fullSizeContentView)
        window.layoutIfNeeded(); host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        let frameView = host
        guard let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { fatalError("Render failed") }
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name + ".png"))
        let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage: rep.cgImage!).perform([request])
        var text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        // Vision sometimes recognizes Latin Copy using visually identical Cyrillic letters.
        for (from, to) in [("С", "C"), ("о", "o"), ("р", "p"), ("у", "y")] { text = text.replacingOccurrences(of: from, with: to) }
        for word in required {
            if !text.localizedCaseInsensitiveContains(word) { FileHandle.standardError.write(Data("Missing OCR control in \(name): \(word). Recognized: \(text)\n".utf8)) }
            precondition(text.localizedCaseInsensitiveContains(word), "\(name): missing rendered control \(word): \(text)") }
        for word in forbidden {
            precondition(!text.localizedCaseInsensitiveContains(word), "\(name): removed content still visible: \(word)")
        }
        window.orderOut(nil)
    }
}

/// A genuine one-page PDF fixture, rather than the image fixture wrapped in a PDF.
private final class DemoOverviewView: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill(); bounds.fill()
        func text(_ value: String, y: CGFloat, size: CGFloat, bold: Bool = false) {
            (value as NSString).draw(in: NSRect(x: 48, y: y, width: 499, height: 120), withAttributes: [
                .font: NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular),
                .foregroundColor: NSColor.black
            ])
        }
        text("Cuekit", y: 54, size: 32, bold: true)
        text("Product overview · illustrative demo document", y: 105, size: 12)
        text("A clipboard companion for macOS", y: 168, size: 21, bold: true)
        text("Keep recent clips in History and save reusable text, links, images and files in Always Available.", y: 213, size: 15)
        text("History", y: 315, size: 18, bold: true)
        text("Search recent clips, inspect their contents and copy an item again.", y: 354, size: 15)
        text("Always Available", y: 450, size: 18, bold: true)
        text("Give each saved value a description that explains what it is and where it belongs. Save your changes to keep it available.", y: 489, size: 15)
        text("Example: “Public website for Cuekit” describes a website URL. It is not an instruction to wait for someone to request a link.", y: 616, size: 14)
        text("All .example addresses in this preview are fictional.", y: 754, size: 11)
    }
}
