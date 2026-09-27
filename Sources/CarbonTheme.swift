import AppKit
import SwiftUI

/// Shared native Carbon tokens. Grain is generated once, stays still, and never covers text.
enum CarbonTheme {
    static let background = NSColor(srgbRed: 0.095, green: 0.100, blue: 0.098, alpha: 1)
    static let ink = Color(red: 0.94, green: 0.925, blue: 0.88)
    static let secondary = Color(red: 0.69, green: 0.70, blue: 0.68)
    static let line = Color.white.opacity(0.10)
    static let panel = Color.white.opacity(0.035)
    static let selection = Color.white.opacity(0.16)
    static let grain: NSImage = {
        let size = 384
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: size * 4, bitsPerPixel: 32)!
        var seed: UInt32 = 74219
        let bytes = rep.bitmapData!
        for i in 0..<(size * size) {
            seed = seed &* 1664525 &+ 1013904223
            let light = UInt8((seed >> 24) & 1) == 0 ? UInt8(255) : UInt8(0)
            bytes[i * 4] = light; bytes[i * 4 + 1] = light; bytes[i * 4 + 2] = light
            bytes[i * 4 + 3] = UInt8(4 + ((seed >> 16) % 9))
        }
        let image = NSImage(size: NSSize(width: 192, height: 192)); image.addRepresentation(rep)
        return image
    }()

    static func apply(to window: NSWindow) {
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = background
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        if window.styleMask.contains(.titled) {
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarSeparatorStyle = .none
        }
    }
}

struct CarbonBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.118, green: 0.121, blue: 0.120),
                                    Color(red: 0.078, green: 0.081, blue: 0.080)], startPoint: .top, endPoint: .bottom)
            Image(nsImage: CarbonTheme.grain).resizable(resizingMode: .tile).opacity(0.30)
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// Hover tint is shared by plain controls, tabs, menus and preview buttons.
struct CarbonHover: ViewModifier {
    var prominent = false
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false
    func body(content: Content) -> some View {
        content.overlay(RoundedRectangle(cornerRadius: 6)
            .fill((prominent ? Color.black : Color.white).opacity(enabled && hovering ? 0.075 : 0))
            .allowsHitTesting(false))
            .onHover { hovering = $0 }
    }
}

struct CarbonButtonStyle: ButtonStyle {
    var prominent = false
    var bordered = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .regular))
            .padding(.horizontal, prominent || bordered ? 13 : 8).padding(.vertical, 8)
            .foregroundStyle(prominent ? Color.black.opacity(0.9) : CarbonTheme.ink)
            .background {
                if prominent { RoundedRectangle(cornerRadius: 6).fill(CarbonTheme.ink) }
                else if bordered { CarbonControlSurface() }
            }
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .modifier(CarbonHover(prominent: prominent))
            .opacity(enabled ? (configuration.isPressed ? 0.65 : 1) : 0.35)
    }
}

struct CarbonControlSurface: View {
    var selected = false
    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(LinearGradient(colors: [Color.white.opacity(selected ? 0.22 : 0.095),
                                          Color.white.opacity(selected ? 0.14 : 0.035)], startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(selected ? 0.18 : 0.10), lineWidth: 0.5))
    }
}

struct CarbonTabs: View {
    @Binding var selection: Int
    @FocusState private var focused: Int?
    private let labels = ["History", "Always Available"]
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<labels.count, id: \.self) { index in
                Button { selection = index } label: {
                    Text(labels[index]).font(.system(size: 12, weight: .regular))
                        .foregroundStyle(selection == index ? CarbonTheme.ink : CarbonTheme.secondary)
                        .frame(width: 132, height: 30)
                        .background { if selection == index { CarbonControlSurface(selected: true) } }
                        .contentShape(RoundedRectangle(cornerRadius: 6))
                        .modifier(CarbonHover())
                }.buttonStyle(.plain).focused($focused, equals: index)
                    .accessibilityLabel(labels[index])
                    .accessibilityAddTraits(selection == index ? .isSelected : [])
                    .accessibilityHint("Show \(labels[index])")
            }
        }.padding(1).background(CarbonControlSurface())
        .onMoveCommand { direction in
            guard focused != nil else { return }
            if direction == .left { selection = 0; focused = 0 }
            if direction == .right { selection = 1; focused = 1 }
        }
        .transaction { $0.animation = nil }
    }
}

struct CarbonDivider: View {
    var vertical = false
    var body: some View {
        Rectangle().fill(Color.white.opacity(0.09))
            .frame(width: vertical ? 0.5 : nil, height: vertical ? nil : 0.5)
            .accessibilityHidden(true)
    }
}

/// Scalable stepped-stack mark, drawn directly on the window without a tile.
struct CarbonLogo: View {
    var body: some View {
        GeometryReader { proxy in
            let sx = proxy.size.width / 100, sy = proxy.size.height / 80
            Path { p in
                for rect in [CGRect(x: 3, y: 4, width: 66, height: 23), CGRect(x: 14, y: 53, width: 66, height: 23), CGRect(x: 33, y: 29, width: 64, height: 23)] {
                    p.addRoundedRect(in: CGRect(x: rect.minX*sx, y: rect.minY*sy, width: rect.width*sx, height: rect.height*sy), cornerSize: CGSize(width: 4*sx, height: 4*sy))
                    for y in [rect.minY+8, rect.minY+15] {
                        p.move(to: CGPoint(x: (rect.minX+9)*sx, y: y*sy))
                        p.addLine(to: CGPoint(x: (rect.maxX-(y == rect.minY+8 ? 9 : 24))*sx, y: y*sy))
                    }
                }
            }.stroke(CarbonTheme.ink, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }.accessibilityHidden(true)
    }
}

struct CarbonField: ViewModifier {
    func body(content: Content) -> some View {
        content.textFieldStyle(.plain).padding(10)
            .background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(CarbonTheme.line))
    }
}

struct CarbonRoot: ViewModifier {
    func body(content: Content) -> some View {
        content.font(.system(size: 13)).foregroundStyle(CarbonTheme.ink)
            .tint(CarbonTheme.ink).buttonStyle(CarbonButtonStyle())
            .background(CarbonBackground().ignoresSafeArea()).environment(\.colorScheme, .dark)
    }
}

extension View {
    func carbonRoot() -> some View { modifier(CarbonRoot()) }
    func carbonField() -> some View { modifier(CarbonField()) }
    func carbonCard() -> some View {
        background(CarbonTheme.panel, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(CarbonTheme.line))
    }
}

final class CarbonBackdropView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    override var isOpaque: Bool { true }
    override func setFrameSize(_ newSize: NSSize) {
        let changed = frame.size != newSize
        super.setFrameSize(newSize)
        if changed { needsDisplay = true }
    }
    override func draw(_ dirtyRect: NSRect) {
        CarbonTheme.background.setFill(); bounds.fill()
        NSGradient(colors: [NSColor(srgbRed: 0.078, green: 0.081, blue: 0.080, alpha: 1),
                            NSColor(srgbRed: 0.118, green: 0.121, blue: 0.120, alpha: 1)])?
            .draw(in: bounds, angle: 90)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setAlpha(0.30)
        NSColor(patternImage: CarbonTheme.grain).setFill(); bounds.fill(using: .sourceOver)
        NSGraphicsContext.restoreGraphicsState()
    }
}
