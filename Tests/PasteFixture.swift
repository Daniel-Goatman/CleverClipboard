import AppKit
import OSLog

final class FixtureDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var keyboardMonitor: Any?
    var loadTimer: Timer?
    let tabs = NSTabView()
    let status = NSTextField(labelWithString: "Load the samples, then focus a field and press ⌘⇧V once.")
    let loadButton = NSButton(title: "Load 13 samples", target: nil, action: nil)
    var checks: [(read: () -> String, expected: String, initial: String, reset: () -> Void, label: NSTextField, page: Int)] = []
    static let longNote = "Project Cedar handover\n" + String(repeating: "Keep the original line breaks, punctuation and complete text.\n", count: 45) + "END OF HANDOVER — complete."
    static let samples = [
        "Alice Chen", "Cedar Studio", "alice.chen@example.org", "+1 202 555 0147",
        "https://cedar.example.org", "8 Cedar Road, Perth WA 6000",
        "bob.morgan@example.net", "https://harbour.example.net",
        "Lunch tomorrow at noon works for me.",
        "Design review\n• Confirm the colour palette\n• Review the mobile layout\nNext meeting: Thursday.",
        "Zoë’s café — déjà vu ☕️\n你好 · مرحباً · hello", longNote,
        "Delivery update: your order is ready for collection."
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { event in
            if [9, 55, 56, 54, 60].contains(event.keyCode) {
                let synthetic = event.cgEvent?.getIntegerValueField(.eventSourceUserData) == 0x4C415941
                Logger(subsystem: "local.daniel.ClipboardTest", category: "keyboard").notice("type=\(event.type.rawValue, privacy: .public) key=\(event.keyCode, privacy: .public) flags=\(event.modifierFlags.rawValue, privacy: .public) synthetic=\(synthetic, privacy: .public)")
            }
            return event
        }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 790, height: 750),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.minSize = NSSize(width: 760, height: 700)
        window.title = "Clipboard Test — synthetic data only"
        let root = NSView()
        window.contentView = root
        let heading = NSTextField(labelWithString: "Clipboard coverage")
        heading.font = .systemFont(ofSize: 23, weight: .semibold)
        let intro = note("Use ⌘⇧V in each field. Check results after pasting. All samples are fictional; nothing is submitted.")
        loadButton.target = self; loadButton.action = #selector(loadSamples)
        let clear = NSButton(title: "Reset fields", target: self, action: #selector(resetFields))
        let check = NSButton(title: "Check this tab", target: self, action: #selector(checkResults))
        let buttons = NSStackView(views: [loadButton, clear, check])
        buttons.spacing = 10
        let top = vertical([heading, intro, buttons, status])
        top.spacing = 10
        [top, tabs].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; root.addSubview($0) }
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: root.topAnchor, constant: 22),
            top.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            top.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            tabs.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 18),
            tabs.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            tabs.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            tabs.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20)
        ])

        let basics = page("Everyday fields", subtitle: "Contact: Alice Chen · Cedar Studio. Try Tab / Shift-Tab between inputs.")
        field(basics, "Email", label: "Alice Chen email address", expected: Self.samples[2], page: 0)
        field(basics, "Phone", label: "Phone number", expected: Self.samples[3], page: 0)
        field(basics, "Website", label: "Cedar Studio website URL", expected: Self.samples[4], page: 0)
        field(basics, "Street address", label: "Home street address", expected: Self.samples[5], page: 0)
        field(basics, "Full name", label: "Contact full name", expected: Self.samples[0], page: 0)
        field(basics, "Company", label: "Company name", expected: Self.samples[1], page: 0)
        field(basics, "Prefilled email", label: "Alice Chen email address", expected: Self.samples[2], initial: "replace-me", page: 0)
        basics.addArrangedSubview(note("For Prefilled email, select all before pasting. Name and company exercise broader model matching."))
        basics.addArrangedSubview(note("Click this blank-area text while an input stays focused, then paste. It should still use that input."))

        let context = page("Competing matches", subtitle: "Both contacts and both company websites are in history. The focused field identifies the intended match.")
        field(context, "Alice’s email", label: "Alice Chen email address", expected: Self.samples[2], page: 1)
        field(context, "Bob’s email", label: "Bob Morgan email address", expected: Self.samples[6], page: 1)
        field(context, "Cedar website", label: "Cedar Studio website URL", expected: Self.samples[4], page: 1)
        field(context, "Harbour website", label: "Harbour company website URL", expected: Self.samples[7], page: 1)
        field(context, "Lunch reply", label: "Reply message confirming lunch tomorrow at noon", expected: Self.samples[8], page: 1)
        field(context, "Order update", label: "Message about an order ready for collection", expected: Self.samples[12], page: 1)
        context.addArrangedSubview(note("Switch test: invoke in Alice’s email, then immediately click Bob’s email. The pending paste should cancel. Invoke again after Bob is focused."))
        context.addArrangedSubview(note("Repeat test: paste once, release every key, then tap only ⌘⇧. The field should stay unchanged. Each new ⌘⇧V is a new paste."))

        let text = page("Text & safety", subtitle: "Multiline, Unicode, long original text and fields that must not receive a smart paste.")
        textArea(text, "Meeting notes", label: "Design review meeting notes with next meeting Thursday", expected: Self.samples[9], page: 2)
        textArea(text, "Unicode", label: "Multilingual café greeting message with coffee emoji", expected: Self.samples[10], page: 2)
        textArea(text, "Long text", label: "Project Cedar handover notes complete original text", expected: Self.samples[11], page: 2)
        field(text, "Secure field", label: "Password", expected: "", page: 2, secure: true)
        field(text, "Read-only", label: "Read-only reference", expected: "Read-only reference", initial: "Read-only reference", page: 2, editable: false)
        text.addArrangedSubview(note("Secure field: smart paste should refuse. Read-only: text must stay unchanged. A matching check alone does not prove the shortcut was attempted."))
        text.addArrangedSubview(note("Escape cancels pending work. Typing, moving the cursor, switching apps or copying new text during selection should also prevent the old paste."))
        window.center(); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func vertical(_ views: [NSView] = []) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        return stack
    }
    func note(_ value: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: value)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }
    func page(_ name: String, subtitle: String) -> NSStackView {
        let item = NSTabViewItem(identifier: tabs.numberOfTabViewItems)
        item.label = name
        let container = NSView()
        let stack = vertical([note(subtitle)])
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -14)
        ])
        item.view = container; tabs.addTabViewItem(item)
        return stack
    }
    func row(_ stack: NSStackView, title: String, input: NSView, result: NSTextField) {
        let label = NSTextField(labelWithString: title)
        label.widthAnchor.constraint(equalToConstant: 112).isActive = true
        result.widthAnchor.constraint(equalToConstant: 95).isActive = true
        result.font = .systemFont(ofSize: 11)
        result.textColor = .secondaryLabelColor
        let row = NSStackView(views: [label, input, result])
        row.alignment = .centerY; row.spacing = 10
        input.setContentHuggingPriority(.defaultLow, for: .horizontal)
        input.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    func field(_ stack: NSStackView, _ title: String, label: String, expected: String, initial: String = "", page: Int, secure: Bool = false, editable: Bool = true) {
        let input: NSTextField = secure ? NSSecureTextField() : NSTextField()
        input.placeholderString = title; input.setAccessibilityLabel(label)
        input.stringValue = initial; input.isEditable = editable
        let result = NSTextField(labelWithString: "Not checked")
        row(stack, title: title, input: input, result: result)
        checks.append(({ input.stringValue }, expected, initial, { input.stringValue = initial }, result, page))
    }
    func textArea(_ stack: NSStackView, _ title: String, label: String, expected: String, page: Int) {
        let scroll = NSScrollView()
        scroll.borderType = .bezelBorder; scroll.hasVerticalScroller = true
        scroll.heightAnchor.constraint(equalToConstant: 74).isActive = true
        let input = NSTextView(frame: NSRect(x: 0, y: 0, width: 380, height: 74))
        input.isRichText = false; input.font = .systemFont(ofSize: 13)
        input.isVerticallyResizable = true; input.isHorizontallyResizable = false
        input.autoresizingMask = [.width]
        input.textContainer?.widthTracksTextView = true
        input.setAccessibilityLabel(label)
        scroll.documentView = input
        let result = NSTextField(labelWithString: "Not checked")
        row(stack, title: title, input: scroll, result: result)
        checks.append(({ input.string }, expected, "", { input.string = "" }, result, page))
    }
    @objc func loadSamples() {
        guard loadTimer == nil else { return }
        loadButton.isEnabled = false
        var index = 0
        status.stringValue = "Loading samples… wait before pasting."
        loadTimer = Timer.scheduledTimer(withTimeInterval: 0.65, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            if index == Self.samples.count {
                timer.invalidate(); self.loadTimer = nil; self.loadButton.isEnabled = true
                self.status.stringValue = "13 samples copied. Focus a field and press ⌘⇧V; release all keys."
                return
            }
            let pb = NSPasteboard.general
            pb.clearContents(); pb.setString(Self.samples[index], forType: .string)
            index += 1
            self.status.stringValue = "Loading sample \(index) of 13…"
        }
    }
    @objc func resetFields() {
        window.makeFirstResponder(nil)
        for entry in checks { entry.reset(); entry.label.stringValue = "Not checked"; entry.label.textColor = .secondaryLabelColor }
        status.stringValue = "Fields reset. Clipboard history is unchanged."
    }
    @objc func checkResults() {
        window.makeFirstResponder(nil)
        let page = tabs.indexOfTabViewItem(tabs.selectedTabViewItem!)
        var matches = 0
        let entries = checks.filter { $0.page == page }
        for entry in entries {
            let value = entry.read()
            let match = value == entry.expected
            if match { matches += 1 }
            entry.label.stringValue = match ? "Matches" : value == entry.initial ? "Not filled" : "Mismatch"
            entry.label.textColor = match ? .systemGreen : .secondaryLabelColor
        }
        status.stringValue = "\(matches)/\(entries.count) values match on this tab. Secure/read-only checks require an actual paste attempt."
    }
    func applicationWillTerminate(_ notification: Notification) {
        loadTimer?.invalidate()
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main struct PasteFixture {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = FixtureDelegate(); app.delegate = delegate
        let menu = NSMenu(), item = NSMenuItem(), submenu = NSMenu()
        submenu.addItem(withTitle: "Quit Clipboard Test", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = submenu; menu.addItem(item)
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit; menu.addItem(editItem); app.mainMenu = menu
        withExtendedLifetime(delegate) { app.run() }
    }
}
