import AppKit

enum AppBrand {
    static let name = "Cuekit"
    static let icon: NSImage? = Bundle.main.url(forResource: "Cuekit", withExtension: "icns")
        .flatMap { NSImage(contentsOf: $0) }

    // A native template version of the approved stepped-stack mark. No tile:
    // macOS supplies the right ink for both light and dark menu bars.
    static let menuIcon: NSImage = {
        let image = NSImage(size: NSSize(width: 20, height: 18), flipped: true) { _ in
            let back = [NSRect(x: 1, y: 1, width: 13, height: 6),
                        NSRect(x: 3.5, y: 11, width: 13, height: 6)]
            for rect in back {
                NSColor.black.withAlphaComponent(0.5).setStroke()
                let card = NSBezierPath(roundedRect: rect, xRadius: 1.7, yRadius: 1.7)
                card.lineWidth = 1.2
                card.stroke()
                let text = NSBezierPath()
                text.lineWidth = 1.1
                text.lineCapStyle = .round
                text.move(to: NSPoint(x: rect.minX + 3, y: rect.midY))
                text.line(to: NSPoint(x: rect.maxX - 3, y: rect.midY))
                text.stroke()
            }
            let selected = NSRect(x: 6, y: 6, width: 13, height: 6)
            let mask = NSBezierPath(roundedRect: selected.insetBy(dx: -0.6, dy: -0.6),
                                    xRadius: 2.2, yRadius: 2.2)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.compositingOperation = .clear
            NSColor.clear.setFill()
            mask.fill()
            NSGraphicsContext.restoreGraphicsState()
            NSColor.black.setStroke()
            let card = NSBezierPath(roundedRect: selected, xRadius: 1.7, yRadius: 1.7)
            card.lineWidth = 1.5
            card.stroke()
            let text = NSBezierPath()
            text.lineWidth = 1.3
            text.lineCapStyle = .round
            text.move(to: NSPoint(x: 9, y: 9))
            text.line(to: NSPoint(x: 16, y: 9))
            text.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = name
        return image
    }()
}
