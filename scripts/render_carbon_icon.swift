import AppKit

/// Deterministic native master of the approved stepped-stack mark; no font or image dependencies.
@main struct RenderCarbonIcon {
    static func image(size: Int) -> Data {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
        let tile = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 204, yRadius: 204)
        context.saveGState()
        tile.addClip()
        NSGradient(starting: NSColor(white: 0.075, alpha: 1), ending: NSColor(white: 0.22, alpha: 1))!
            .draw(in: tile, angle: 70)
        if size >= 64 {
            var seed: UInt32 = 49017
            for _ in 0..<100000 {
                seed = seed &* 1664525 &+ 1013904223; let x = CGFloat((seed >> 16) % 1024)
                seed = seed &* 1664525 &+ 1013904223; let y = CGFloat((seed >> 16) % 1024)
                let bright = (seed >> 24) & 4 == 0
                NSColor(white: bright ? 1 : 0, alpha: bright ? 0.035 : 0.13).setFill()
                NSRect(x: x, y: y, width: 1.2, height: 1.2).fill(using: .sourceOver)
            }
        }
        context.restoreGState()
        NSColor(white: 0.7, alpha: 0.25).setStroke(); tile.lineWidth = 2; tile.stroke()
        let ivory = NSColor(srgbRed: 0.94, green: 0.925, blue: 0.88, alpha: 1)
        func card(_ rect: NSRect, front: Bool) {
            let outline = NSBezierPath(roundedRect: rect, xRadius: 35, yRadius: 35)
            if front {
                NSColor(white: 0.125, alpha: 1).setFill()
                let backing = NSBezierPath(roundedRect: rect.insetBy(dx: -15, dy: -15), xRadius: 47, yRadius: 47)
                backing.fill()
            }
            (front ? ivory : NSColor(srgbRed: 0.66, green: 0.66, blue: 0.62, alpha: 1)).setStroke()
            outline.lineWidth = size <= 32 ? 34 : 28; outline.stroke()
            let text = NSBezierPath(); text.lineWidth = size <= 32 ? 29 : 24; text.lineCapStyle = .round
            text.move(to: NSPoint(x: rect.minX + 60, y: rect.maxY - 58))
            text.line(to: NSPoint(x: rect.maxX - 60, y: rect.maxY - 58))
            if size >= 32 {
                text.move(to: NSPoint(x: rect.minX + 60, y: rect.minY + 54))
                text.line(to: NSPoint(x: rect.minX + 235, y: rect.minY + 54))
            }
            text.stroke()
        }
        card(NSRect(x: 183, y: 579, width: 487, height: 168), front: false)
        card(NSRect(x: 213, y: 279, width: 487, height: 168), front: false)
        card(NSRect(x: 354, y: 429, width: 487, height: 168), front: true)
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])!
    }
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let iconset = root.appendingPathComponent("Cuekit.iconset")
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        for size in [16, 32, 128, 256, 512] {
            try image(size: size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
            try image(size: size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
        }
        try image(size: 1024).write(to: root.appendingPathComponent("Cuekit.png"))
        print("Rendered Carbon master and all standard/Retina representations")
    }
}
