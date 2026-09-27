import AppKit
import SwiftUI

/// Only fixed, local explanations enter the error panel; never echo an arbitrary
/// error body, credential, clipboard value or destination text.
struct SmartPasteFailure {
    enum Recovery {
        case accessibility, screenRecording, settings
        var title: String {
            switch self {
            case .accessibility: return "Open Accessibility Settings"
            case .screenRecording: return "Open Screen Recording Settings"
            case .settings: return "Open Cuekit Settings"
            }
        }
    }
    var title = "Nothing was pasted"
    let detail: String
    let recovery: Recovery?

    init(message: String, reason: PasteReason, accessibilityAllowed: Bool = false, screenRecordingAllowed: Bool = false) {
        switch reason {
        case .accessibility:
            detail = accessibilityAllowed
                ? "Accessibility is granted now. Try Smart Paste again in the intended field."
                : "Accessibility was unavailable for this attempt. Check Cuekit in Applications in System Settings → Privacy & Security → Accessibility, then try again."
            recovery = accessibilityAllowed ? nil : .accessibility
        case .screen_recording:
            detail = screenRecordingAllowed
                ? "Screen Recording is granted now. Try Smart Paste again in the intended field."
                : "Screen Recording was unavailable for this attempt. Check Cuekit in System Settings, then reopen Cuekit if macOS asks you to."
            recovery = screenRecordingAllowed ? nil : .screenRecording
        case .secure_input:
            detail = "Secure keyboard input or a secure field blocked this attempt. Finish secure entry, select a regular text field, and try again."
            recovery = nil
        case .worker_unavailable, .worker_error, .worker_timeout, .worker_busy:
            detail = "TypeSafe is unavailable or did not finish the request. Check the connection in Cuekit Settings, then try again."
            recovery = .settings
        case .no_input, .not_editable, .window_unidentified:
            detail = "Select an editable text field in another app, then press ⌘⇧V again."
            recovery = nil
        case .app_changed, .window_changed, .input_changed, .text_or_cursor_changed:
            detail = "The destination changed while Smart Paste was working. Keep the cursor in the intended field and try again."
            recovery = nil
        case .clipboard_changed, .lease_invalid:
            detail = "The clipboard changed or the request expired. Keep the destination selected and try again."
            recovery = nil
        case .empty_history, .no_match:
            detail = "No suitable clipboard item was available. Copy an item or choose one from Clipboard History."
            recovery = nil
        case .clipboard_write, .event_creation:
            detail = "Cuekit could not prepare or insert the clipboard item. Try again, or copy an item from Clipboard History and paste it with ⌘V."
            recovery = nil
        case .modifiers_held:
            detail = "Release the shortcut keys, then try again."
            recovery = nil
        default:
            switch message {
            case "Could not save the Smart Paste dataset. Nothing was pasted.":
                detail = "Cuekit could not save this attempt locally. Check available disk space and access to the SmartPasteDataset folder, then try again."
                recovery = nil
            case "Paste events were sent, but the dataset outcome could not be saved. Check available disk space.":
                title = "Dataset recording incomplete"
                detail = "Paste events were sent, but Cuekit could not save the final outcome. Check available disk space before the next attempt."
                recovery = nil
            case "TypeSafe rejected the API key. Update it from the menu.", "Configure the TypeSafe API key from the menu.", "Configure a valid TypeSafe API key from the menu.":
                detail = "TypeSafe needs a valid API key. Check your connection in Cuekit Settings."
                recovery = .settings
            case "Could not reach TypeSafe. Check your connection and try again.", "TypeSafe service unavailable. Nothing was pasted; try again.":
                detail = "Could not reach TypeSafe. Check your internet connection and try again."
                recovery = .settings
            case "TypeSafe rate limit reached. Try again shortly.":
                detail = "TypeSafe is limiting requests. Wait a moment, then try again."
                recovery = nil
            case "Clipboard/context contains the API key. Nothing was sent.":
                detail = "Smart Paste found your API key in the clipboard or destination context. Remove it before trying again. Nothing was sent."
                recovery = nil
            case "Saved item is unavailable. Nothing was pasted.":
                detail = "The saved item is no longer available. Replace it in Always Available, then try again."
                recovery = nil
            case "This app does not expose an active window. Use clipboard history from the menu.":
                detail = "The destination app does not expose an active window. Copy an item from Clipboard History and paste it with ⌘V."
                recovery = nil
            default:
                detail = "Smart Paste could not complete. Try again, or check your connection in Cuekit Settings."
                recovery = .settings
            }
        }
    }
}

struct SmartPasteErrorView: View {
    let failure: SmartPasteFailure
    var dismiss: () -> Void
    var recover: (SmartPasteFailure.Recovery) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(failure.title, systemImage: "exclamationmark.circle")
                .font(.system(size: 18, weight: .medium))
            Text(failure.detail).font(.system(size: 13))
                .foregroundStyle(CarbonTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Dismiss", action: dismiss).keyboardShortcut(.cancelAction)
                Spacer(minLength: 8)
                if let recovery = failure.recovery {
                    Button(recovery.title) { recover(recovery) }
                        .buttonStyle(CarbonButtonStyle(prominent: true))
                }
            }
        }.padding(22).frame(width: 430).carbonRoot()
    }
}

/// Floats above the destination without taking keyboard focus or blocking its UI.
final class SmartPasteErrorWindow {
    let panel: NSPanel

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 430, height: 200),
                        styleMask: [.nonactivatingPanel, .titled, .closable, .fullSizeContentView],
                        backing: .buffered, defer: false)
        panel.title = "Smart Paste"
        CarbonTheme.apply(to: panel)
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
    }

    func configure(_ failure: SmartPasteFailure, recover: @escaping (SmartPasteFailure.Recovery) -> Void) {
        let host = NSHostingView(rootView: SmartPasteErrorView(failure: failure,
            dismiss: { [weak self] in self?.dismiss() },
            recover: { [weak self] action in self?.dismiss(); recover(action) }))
        panel.contentView = host
        panel.setContentSize(NSSize(width: 430, height: max(180, host.fittingSize.height)))
    }

    func show(_ failure: SmartPasteFailure, recover: @escaping (SmartPasteFailure.Recovery) -> Void) {
        configure(failure, recover: recover)
        let height = panel.frame.height
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1000, height: 700)
        panel.setFrame(NSRect(x: frame.maxX - 450, y: frame.maxY - height - 20, width: 430, height: height), display: true)
        panel.orderFrontRegardless()
        NSAccessibility.post(element: panel, notification: .announcementRequested,
                             userInfo: [.announcement: failure.title + ". " + failure.detail,
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    func dismiss() {
        panel.orderOut(nil)
        panel.contentView = nil
    }
}
