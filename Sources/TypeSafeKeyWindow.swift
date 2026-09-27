import AppKit
import SwiftUI

final class TypeSafeKeyModel: ObservableObject {
    typealias Verify = (String, @escaping (Result<Void, Error>) -> Void) -> URLSessionDataTask?
    @Published var key = ""
    @Published private(set) var verifying = false
    @Published private(set) var saved = false
    @Published private(set) var error: String?
    private let verify: Verify
    private let save: (String) throws -> Void
    private var task: URLSessionDataTask?
    private var generation = UUID()
    var onSaved: (() -> Void)?

    init(verify: @escaping Verify, save: @escaping (String) throws -> Void = JevCredential.save) {
        self.verify = verify; self.save = save
    }
    func submit() {
        guard !verifying, !saved else { return }
        let candidate = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard JevCredential.isValidFormat(candidate) else {
            error = "Enter a valid TypeSafe API key."; return
        }
        error = nil; verifying = true
        let token = UUID(); generation = token
        task = verify(candidate) { [weak self] result in
            guard let self, self.generation == token else { return }
            self.task = nil; self.verifying = false
            do {
                try result.get()
                try self.save(candidate)
                self.key = ""; self.saved = true
                self.onSaved?()
            } catch {
                // Never echo credential text or an arbitrary server/error body.
                self.error = Self.safeMessage(error)
            }
        }
    }
    private static func safeMessage(_ error: Error) -> String {
        switch error.localizedDescription {
        case "TypeSafe rejected the API key. Update it from the menu.":
            return "This key was rejected by TypeSafe. Check it and try again."
        case "Could not reach TypeSafe. Check your connection and try again.":
            return "Could not connect to TypeSafe. Check your internet connection and try again."
        case "TypeSafe rate limit reached. Try again shortly.":
            return "TypeSafe is rate limiting requests. Try again shortly."
        case "macOS could not save the TypeSafe key in Keychain.":
            return "The key is valid, but macOS could not save it in Keychain. Try again."
        default: return "Could not verify the key. Try again shortly. Your saved key has not changed."
        }
    }
    func reset() {
        generation = UUID(); task?.cancel(); task = nil
        key = ""; error = nil; verifying = false; saved = false
    }
}

struct TypeSafeKeyView: View {
    @ObservedObject var model: TypeSafeKeyModel
    var close: () -> Void
    @FocusState private var keyFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Connect to TypeSafe", systemImage: "key.fill")
                .font(.system(size: 22, weight: .medium))
            Text("Enter your API key to enable Smart Paste. Cuekit verifies it with TypeSafe before saving it in macOS Keychain.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if model.saved {
                Label("Key verified and saved", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).accessibilityLabel("Key verified and saved in Keychain")
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("API key").font(.headline)
                    SecureField("Enter TypeSafe API key", text: $model.key)
                        .carbonField().focused($keyFocused)
                        .disabled(model.verifying).accessibilityLabel("TypeSafe API key")
                    Text("Verification sends only your key to TypeSafe, not clipboard content.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if model.verifying {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Verifying key…").foregroundStyle(.secondary)
                }
            } else if let error = model.error {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button(model.saved ? "Done" : "Cancel", action: close)
                    .keyboardShortcut(model.saved ? .defaultAction : .cancelAction)
                if !model.saved {
                    Button("Verify & Save") { model.submit() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(CarbonButtonStyle(prominent: true))
                        .disabled(model.verifying || model.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(width: 400, alignment: .leading)
        .frame(minHeight: 280, alignment: .topLeading).padding(24)
        .carbonRoot()
        .onAppear { keyFocused = true }
        .onExitCommand(perform: close)
    }
}

final class TypeSafeKeyWindow: NSWindowController, NSWindowDelegate {
    let model: TypeSafeKeyModel
    var onClose: (() -> Void)?

    init(model: TypeSafeKeyModel) {
        self.model = model
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 448, height: 340),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "TypeSafe API Key"
        CarbonTheme.apply(to: window)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: TypeSafeKeyView(model: model, close: { [weak self] in self?.close() }))
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func present() {
        if window?.isVisible != true { model.reset() }
        showWindow(nil); window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func windowWillClose(_ notification: Notification) { model.reset(); onClose?() }
}
