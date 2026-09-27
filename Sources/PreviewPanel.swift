import AppKit

final class PreviewPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    private var actions: [() -> Void] = []
    private var buttons: [NSButton] = []

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 430, height: 280),
                   styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                   backing: .buffered, defer: false)
        CarbonTheme.apply(to: self)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
    }

    func show(title: String, detail: String, fullText: String? = nil, rows: [(String, String, () -> Void)] = [],
              paste: (() -> Void)? = nil, cancel: @escaping () -> Void) {
        actions.removeAll(); buttons.removeAll()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 18, right: 20)

        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 18, weight: .medium)
        stack.addArrangedSubview(heading)
        let subtitle = NSTextField(wrappingLabelWithString: detail)
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = NSColor(srgbRed: 0.69, green: 0.70, blue: 0.68, alpha: 1)
        subtitle.preferredMaxLayoutWidth = 390
        subtitle.widthAnchor.constraint(equalToConstant: 390).isActive = true
        stack.addArrangedSubview(subtitle)
        if let fullText {
            let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 386, height: 100))
            text.string = fullText
            text.isEditable = false
            text.isSelectable = false
            text.font = .systemFont(ofSize: 13)
            text.drawsBackground = false
            text.textContainerInset = NSSize(width: 8, height: 8)
            text.textContainer?.widthTracksTextView = true
            text.autoresizingMask = [.width]
            text.setAccessibilityLabel("Selected clipboard text")
            let scroll = NSScrollView()
            scroll.documentView = text
            scroll.hasVerticalScroller = true
            scroll.borderType = .bezelBorder
            scroll.widthAnchor.constraint(equalToConstant: 390).isActive = true
            scroll.heightAnchor.constraint(equalToConstant: 100).isActive = true
            stack.addArrangedSubview(scroll)
        }
        for (index, row) in rows.enumerated() {
            let button = NSButton(title: row.0, target: self, action: #selector(clicked(_:)))
            button.tag = actions.count
            actions.append(row.2)
            button.bezelStyle = .rounded
            button.alignment = .left
            button.font = .systemFont(ofSize: 13, weight: index == 0 ? .medium : .regular)
            button.lineBreakMode = .byTruncatingTail
            button.toolTip = row.1
            button.setAccessibilityLabel(row.1)
            button.widthAnchor.constraint(equalToConstant: 390).isActive = true
            buttons.append(button)
            stack.addArrangedSubview(button)
        }
        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.spacing = 10
        if let paste {
            footer.addArrangedSubview(actionButton("Paste  ⌘⇧V", action: paste))
        }
        footer.addArrangedSubview(actionButton("Cancel  Esc", action: cancel))
        stack.addArrangedSubview(footer)
        let view = CarbonBackdropView(frame: NSRect(x: 0, y: 0, width: 430, height: 600))
        view.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        contentView = view
        view.layoutSubtreeIfNeeded()
        let height = max(170, stack.fittingSize.height)
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1000, height: 700)
        setFrame(NSRect(x: frame.maxX - 450, y: frame.maxY - height - 20, width: 430, height: height), display: true)
        orderFrontRegardless()
    }

    func dismiss() {
        orderOut(nil)
        actions.removeAll(); buttons.removeAll()
        contentView = nil
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> NSButton {
        let button = NSButton(title: title, target: self, action: #selector(clicked(_:)))
        button.tag = actions.count
        actions.append(action)
        button.bezelStyle = .rounded
        return button
    }

    @objc private func clicked(_ sender: NSButton) {
        guard actions.indices.contains(sender.tag) else { return }
        let action = actions[sender.tag]
        action()
    }
}
