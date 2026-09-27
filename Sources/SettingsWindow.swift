import AppKit
import SwiftUI

final class SettingsModel: ObservableObject {
    @Published var connected = false
    @Published var connectionStatus = "Not connected"
    @Published var accessibilityAllowed = false
    @Published var screenRecordingAllowed = false
    @Published var shortcutRegistered = true
    static func permissionMenuItem(_ name: String, allowed: Bool, symbol: String, action: Selector, target: AnyObject?) -> NSMenuItem {
        let item = NSMenuItem(title: allowed ? "\(name): Granted" : "Allow \(name)…", action: action, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: allowed ? "checkmark.circle" : symbol, accessibilityDescription: nil)
        item.toolTip = "Manage \(name) permission in System Settings"
        item.target = target
        return item
    }

    var onRefresh: () -> Void = {}
    var onReconnect: () -> Void = {}
    var onKey: () -> Void = {}
    var onAccessibility: () -> Void = {}
    var onScreenRecording: () -> Void = {}
    var onClipboard: () -> Void = {}
}

enum SettingsPage: String, CaseIterable, Identifiable {
    case general = "General", smartPaste = "Smart Paste", connection = "Connection"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .smartPaste: return "doc.on.clipboard"
        case .connection: return "link"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @State private var page: SettingsPage
    init(model: SettingsModel, initialPage: SettingsPage = .smartPaste) {
        self.model = model; _page = State(initialValue: initialPage)
    }
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    if let icon = AppBrand.icon {
                        Image(nsImage: icon).resizable().interpolation(.high)
                            .frame(width: 48, height: 48).accessibilityLabel("Cuekit logo")
                    }
                    Text(AppBrand.name).font(.system(size: 22, weight: .medium))
                }.padding(.horizontal, 16).padding(.top, 20)
                VStack(spacing: 5) {
                    ForEach(SettingsPage.allCases) { item in
                        Button { page = item } label: {
                            HStack(spacing: 12) {
                                Image(systemName: item.symbol).font(.system(size: 18, weight: .light)).frame(width: 24)
                                Text(item.rawValue)
                                Spacer(minLength: 0)
                            }.padding(12).contentShape(Rectangle())
                                .background(page == item ? CarbonTheme.selection : .clear, in: RoundedRectangle(cornerRadius: 7))
                        }.buttonStyle(.plain).modifier(CarbonHover()).accessibilityAddTraits(page == item ? .isSelected : [])
                    }
                }
                Spacer()
            }.padding(12).frame(width: 200).background(Color.white.opacity(0.018))
            Divider().opacity(0.25)
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(page.rawValue).font(.system(size: 22, weight: .medium))
                        Text(subtitle).foregroundStyle(CarbonTheme.secondary)
                    }.padding(.bottom, 2)
                    switch page {
                    case .smartPaste: smartPaste
                    case .general: general
                    case .connection: connection
                    }
                }.padding(30).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.frame(minWidth: 740, minHeight: 580).carbonRoot()
            .onAppear(perform: model.onRefresh)
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in model.onRefresh() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.onRefresh() }
    }
    private var subtitle: String {
        switch page {
        case .general: return "Your clipboard, kept close."
        case .smartPaste: return "The right clip, in context."
        case .connection: return "Connect your TypeSafe account."
        }
    }
    private var smartPaste: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("Shortcut"); Spacer()
                ForEach(["⇧", "⌘", "V"], id: \.self) { key in
                    Text(key).font(.system(size: 16, weight: .medium)).frame(width: 36, height: 33).carbonCard()
                }
            }.padding(16).carbonCard()
            if !model.shortcutRegistered {
                Label("This shortcut is in use. Smart Paste is available from the menu.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange).font(.system(size: 12))
            }
            connectionRow
            permissions
            Text("Smart Paste sends relevant text to TypeSafe.")
                .font(.system(size: 12)).foregroundStyle(CarbonTheme.secondary)
        }
    }
    private var connectionRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connection").font(.system(size: 13, weight: .medium))
            HStack(spacing: 12) {
                Image(systemName: "link").font(.system(size: 21, weight: .light))
                Text("TypeSafe"); Spacer()
                Label(model.connected ? "Connected" : "Unavailable", systemImage: model.connected ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .font(.system(size: 11)).foregroundStyle(model.connected ? CarbonTheme.ink : .orange)
                Button("Reconnect", action: model.onReconnect)
            }.padding(15).carbonCard()
        }
    }
    private var permissions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Permissions").font(.system(size: 13, weight: .medium))
            VStack(spacing: 0) {
                permission("Accessibility", symbol: "accessibility", allowed: model.accessibilityAllowed, requirement: "Required", action: model.onAccessibility)
                CarbonDivider().padding(.horizontal, 15)
                permission("Screen Recording", symbol: "rectangle.inset.filled", allowed: model.screenRecordingAllowed, requirement: "Optional", action: model.onScreenRecording)
            }.carbonCard()
        }
    }
    private func permission(_ name: String, symbol: String, allowed: Bool, requirement: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 20, weight: .light)).frame(width: 25)
                Text(name); Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Label(allowed ? "Granted" : "Not granted", systemImage: allowed ? "checkmark.circle" : "minus.circle")
                        .font(.system(size: 12)).foregroundStyle(CarbonTheme.ink)
                    Text(requirement).font(.system(size: 10)).foregroundStyle(CarbonTheme.secondary)
                }
                Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(CarbonTheme.secondary)
            }.padding(17).contentShape(Rectangle())
        }.buttonStyle(.plain).modifier(CarbonHover()).help("Manage \(name) permission in System Settings")
    }
    private var general: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Clipboard collection").font(.system(size: 14, weight: .medium))
                    Text("Collect text, images and files as you copy.")
                        .font(.system(size: 12)).foregroundStyle(CarbonTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)

            }.padding(.vertical, 20)
            CarbonDivider()
            generalRow("History", summary: "50 items · 128 MB", detail: "Older clips make room for new ones. Copied files are kept as separate snapshots, up to 20 MB each.")
            CarbonDivider()
            generalRow("Always Available", summary: "20 entries · 512 MB", detail: "Reusable text, links, images and files. Saved entries remain after clearing history.")
            CarbonDivider()
            Button(action: model.onClipboard) {
                HStack(spacing: 8) {
                    Text("Open Clipboard")
                    Image(systemName: "arrow.up.right").font(.system(size: 11))
                }
            }.padding(.top, 22)
        }
    }
    private func generalRow(_ title: String, summary: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(title).font(.system(size: 14, weight: .medium))
                Spacer(minLength: 8)
                Text(summary).font(.system(size: 11)).foregroundStyle(CarbonTheme.secondary)
                    .fixedSize(horizontal: true, vertical: false)
            }
            Text(detail).font(.system(size: 12)).foregroundStyle(CarbonTheme.secondary)
                .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }.padding(.vertical, 22)
    }
    private var connection: some View {
        VStack(alignment: .leading, spacing: 24) {
            connectionRow
            Text(model.connectionStatus).font(.system(size: 12)).foregroundStyle(CarbonTheme.secondary).textSelection(.enabled)
            info("Your API key", "Cuekit verifies your key with TypeSafe before saving it in macOS Keychain. Your existing key remains unchanged if verification fails.")
            Button { model.onKey() } label: { Label("Manage API Key…", systemImage: "key") }
                .buttonStyle(CarbonButtonStyle(prominent: true))
            info("Hosted service", "Smart Paste requires internet access and your own TypeSafe account. Hosted selections may incur charges.")
        }
    }
    private func info(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13, weight: .medium))
            Text(detail).font(.system(size: 12)).foregroundStyle(CarbonTheme.secondary).fixedSize(horizontal: false, vertical: true).lineSpacing(3)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18).carbonCard()
    }
}
