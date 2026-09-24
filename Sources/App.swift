import AppKit
import Carbon
import OSLog
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private var history = History()
    private var pins = PinnedEntry.defaults
    private let store = ClipboardStore()
    private let historyModel = HistoryWindowModel()
    private var historyWindow: NSWindow?
    private var lastChange = NSPasteboard.general.changeCount
    private var lastClipboardPollUptime = ProcessInfo.processInfo.systemUptime
    private var copyForegroundGate = CopyForegroundGate()
    private var recentCopy: CopyObservation?
    private var clipboardProvenance: ClipProvenance?
    private var copyMonitor: Any?
    private var activationMonitor: NSObjectProtocol?
    private var clipboardAssetID: String?
    private var paused = false
    private var ready = false
    private var status = "Starting Jev…"
    private var workerStatus = "Starting Jev…"
    private var statusItem: NSStatusItem!
    private var worker: ModelWorker!
    private var timer: Timer?
    private var warmTimer: Timer?
    private var hotKey: EventHotKeyRef?
    private var shortcutRegistered = false
    private var shortcutLatch = ShortcutLatch()
    private var shortcutReleaseTimer: Timer?
    private var escapeMonitor: Any?
    private var localEscapeMonitor: Any?
    private var requestID = UUID()
    private var selecting = false
    private var target: InputTarget?
    private var lease: PasteLease?
    private var suggestions: [Clip] = []
    private var selected: Clip?
    private var timing = ""
    private var operationStatus: String?
    private var pulseTimer: Timer?
    private var pulsePhase = false
    private var pulseToken = UUID()
    private var requestStarted = Date()
    private var trace: PasteTrace?
    private var verifiedJev = false
    private var fixture = ProcessInfo.processInfo.arguments.contains("--demo")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()
        (history, pins) = store.load()
        configureHistoryModel()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "Jev Clipboard")
        rebuildMenu()
        registerShortcut()
        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.cancel() }
        }
        localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.cancel() }
            return event
        }
        // Observe a normal copy without consuming or replaying the event.
        copyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 8, event.modifierFlags.contains(.command),
                  !event.modifierFlags.contains(.option), !event.modifierFlags.contains(.control),
                  !event.modifierFlags.contains(.shift) else { return }
            self?.observeCopy(event: event)
        }
        activationMonitor = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.copyForegroundGate.activated(at: ProcessInfo.processInfo.systemUptime)
        }
        copyForegroundGate.observePoll(pid: NSWorkspace.shared.frontmostApplication?.processIdentifier)
        if fixture {
            history.add("21 Paperbark Lane, Perth WA 6000", app: "Maps")
            history.add("hello@example.com", app: "Contacts")
            history.add("Let's meet at 10 tomorrow.", app: "Notes")
            suggestions = [history.items[1], history.items[2], history.items[0]]
            selected = suggestions.first
            timing = "Demo · sample data only"
            status = "Demo · sample data only"
            operationStatus = "Paste sent to Sample Form"
            ready = true; rebuildMenu(); updateIcon()
            DispatchQueue.main.async { self.statusItem.button?.performClick(nil) }
            return
        }
        let root = Bundle.main.bundleURL.deletingLastPathComponent()
        worker = ModelWorker(root: root)
        worker.onState = { [weak self] message, isReady in
            guard let self else { return }
            self.ready = isReady
            self.workerStatus = message
            self.status = self.shortcutRegistered ? message : "⌘⇧V is in use. Use Smart Paste from the menu. · \(message)"
            self.rebuildMenu()
            if self.pulseTimer == nil { self.updateIcon() }
            self.writeLaunchStatus(ready: isReady)
            if isReady && !self.verifiedJev && ProcessInfo.processInfo.arguments.contains("--verify-jev") {
                self.verifiedJev = true
                self.verifyJev()
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--configure-jev-from-clipboard") {
            configureJev()
        } else { worker.start() }
        timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in self?.pollClipboard() }
        warmTimer = Timer.scheduledTimer(withTimeInterval: 45, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.worker.keepWarm()
        }
        if ProcessInfo.processInfo.arguments.contains("--show-history") {
            DispatchQueue.main.async { self.openHistoryWindow() }
        }
    }

    private func writeLaunchStatus(ready: Bool, smokePassed: Bool? = nil) {
        // Diagnostic flags only: no clipboard/context/key content.
        var data: [String: Any] = ["pid": ProcessInfo.processInfo.processIdentifier,
            "bundle": Bundle.main.bundlePath, "worker_ready": ready,
            "shortcut_registered": shortcutRegistered,
            "accessibility": AXIsProcessTrusted(), "screen_capture": CGPreflightScreenCaptureAccess(),
            "backend": "jev-1.13.0", "worker_status": workerStatus,
            "timestamp": Date().timeIntervalSince1970]
        if let smokePassed { data["synthetic_api_selection_passed"] = smokePassed }
        let file = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("results/jev-app/launch-status.json")
        if let encoded = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]) {
            try? encoded.write(to: file, options: .atomic)
        }
    }

    private func verifyJev() {
        let samples = [Clip(id: "smoke-url", text: "https://example.org", app: "Fixture", copiedAt: Date()),
                       Clip(id: "smoke-email", text: "test@example.org", app: "Fixture", copiedAt: Date())]
        worker.select(context: "App: Safari\nInput label: Website URL", clips: samples) { [weak self] result in
            guard let self else { return }
            let passed: Bool
            if case .success(let reply) = result { passed = reply.ranked?.first?.id == "smoke-url" }
            else { passed = false }
            self.writeLaunchStatus(ready: self.ready, smokePassed: passed)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        trace?.record(.cancelled, reason: .shutdown)
        worker?.stop()
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        if let localEscapeMonitor { NSEvent.removeMonitor(localEscapeMonitor) }
        if let copyMonitor { NSEvent.removeMonitor(copyMonitor) }
        if let activationMonitor { NSWorkspace.shared.notificationCenter.removeObserver(activationMonitor) }
        timer?.invalidate(); warmTimer?.invalidate(); pulseTimer?.invalidate()
    }

    private func registerShortcut() {
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, data in
            guard let event, let data else { return noErr }
            let app = Unmanaged<AppDelegate>.fromOpaque(data).takeUnretainedValue()
            let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            Logger(subsystem: "local.daniel.LayaClipboard", category: "shortcut").notice("pressed=\(pressed, privacy: .public)")
            if pressed {
                if app.shortcutLatch.press() {
                    app.watchShortcutRelease()
                    app.smartPaste()
                }
            } else { app.shortcutLatch.release(vIsDown: PasteKeyboard.physicalVDown()) }
            return noErr
        }, specs.count, &specs, Unmanaged.passUnretained(self).toOpaque(), nil)
        let result = RegisterEventHotKey(UInt32(kVK_ANSI_V), UInt32(cmdKey | shiftKey),
            EventHotKeyID(signature: 0x4C415941, id: 1), GetApplicationEventTarget(), 0, &hotKey)
        shortcutRegistered = result == noErr
        if !shortcutRegistered { status = "⌘⇧V is in use. Use Smart Paste from the menu." }
    }

    // Carbon can report release when a modifier lifts before V. Only a physical
    // V release rearms the shortcut; synthetic PID-directed paste cannot rearm it.
    private func watchShortcutRelease() {
        shortcutReleaseTimer?.invalidate()
        shortcutReleaseTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            if !PasteKeyboard.physicalVDown() {
                self.shortcutLatch.release(vIsDown: false)
                timer.invalidate()
                self.shortcutReleaseTimer = nil
            }
        }
    }

    private func observeCopy(event: NSEvent) {
        let uptime = ProcessInfo.processInfo.systemUptime
        // A late asynchronous monitor callback must not be applied to the next change.
        guard event.timestamp > lastClipboardPollUptime,
              uptime >= event.timestamp, uptime - event.timestamp <= 0.15 else { return }
        let observedAt = Date().addingTimeInterval(event.timestamp - uptime)
        let priorChange = NSPasteboard.general.changeCount
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier else { recentCopy = nil; return }
        guard copyForegroundGate.allows(eventAt: event.timestamp, callbackAt: uptime,
                                        pid: app.processIdentifier) else { recentCopy = nil; return }
        var selected: String?, label: String?, fieldIdentifier: String?, windowTitle: String?
        if AXIsProcessTrusted(), !IsSecureEventInputEnabled() {
            let root = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(root, 0.08)
            if let focused = axElement(root, kAXFocusedUIElementAttribute),
               !axText(focused, kAXSubroleAttribute).localizedCaseInsensitiveContains("secure") {
                AXUIElementSetMessagingTimeout(focused, 0.04)
                if let rawRange = axValue(focused, kAXSelectedTextRangeAttribute),
                   CFGetTypeID(rawRange) == AXValueGetTypeID() {
                    var range = CFRange()
                    if AXValueGetValue(rawRange as! AXValue, .cfRange, &range),
                       range.length > 0, range.length <= 1024 {
                        selected = (axValue(focused, kAXSelectedTextAttribute) as? String).flatMap {
                            $0.utf8.count <= 1024 && !$0.isEmpty ? $0 : nil
                        }
                    }
                }
                if selected != nil {
                    fieldIdentifier = axText(focused, "AXIdentifier")
                    let titleElement = axElement(focused, kAXTitleUIElementAttribute)
                    label = titleElement.map { axText($0, kAXValueAttribute) } ??
                        [kAXTitleAttribute, kAXDescriptionAttribute, "AXPlaceholderValue"]
                            .map { axText(focused, $0) }.first { !$0.isEmpty }
                    if let window = axElement(root, kAXFocusedWindowAttribute) {
                        windowTitle = axText(window, kAXTitleAttribute)
                    }
                }
            }
        }
        recentCopy = CopyObservation(app: app.localizedName ?? bundleID, bundleID: bundleID,
                                     at: observedAt, pasteboardChange: priorChange,
                                     windowTitle: windowTitle, fieldLabel: label,
                                     fieldIdentifier: fieldIdentifier, selectedText: selected)
    }

    private func pollClipboard() {
        let pb = NSPasteboard.general
        let foreground = NSWorkspace.shared.frontmostApplication
        defer { copyForegroundGate.observePoll(pid: foreground?.processIdentifier) }
        guard pb.changeCount != lastChange else { return }
        lastChange = pb.changeCount
        lastClipboardPollUptime = ProcessInfo.processInfo.systemUptime
        let observed = foreground?.localizedName
        let declared = pb.string(forType: NSPasteboard.PasteboardType("org.nspasteboard.source"))
        let copiedText = pb.string(forType: .string)
        let provenance = ClipProvenance.resolve(observation: recentCopy, changedAt: Date(),
            changeCount: pb.changeCount, foreground: observed, declaredSource: declared,
            payload: copiedText)
        clipboardProvenance = provenance
        recentCopy = nil
        clipboardAssetID = nil
        if selecting { showError("Clipboard changed. Press ⌘⇧V to try again.") }
        guard !paused, !History.shouldIgnore(types: (pb.types ?? []).map(\.rawValue)) else { return }
        let app = provenance.sourceApp ?? "Unknown source"
        if let kind = [NSPasteboard.PasteboardType.png, .tiff, NSPasteboard.PasteboardType("public.jpeg"), NSPasteboard.PasteboardType("public.heic")].first(where: { pb.data(forType: $0) != nil }),
           let data = pb.data(forType: kind), data.count <= History.maximumItemBytes {
            let id = UUID().uuidString
            do {
                try store.writeImage(data, id: id)
                guard history.addImage(id: id, dataCount: data.count, type: kind.rawValue,
                                       app: app, provenance: provenance) else { return }
                guard let revision = history.items.first(where: { $0.id == id })?.imageRevision else { return }
                persistHistory()
                DispatchQueue.global(qos: .utility).async { [weak self] in
                    let result = ImageOCR.analyze(data)
                    DispatchQueue.main.async {
                        guard let self,
                              self.history.updateOCR(id: id, imageRevision: revision, result: result) else { return }
                        self.persistHistory()
                    }
                }
            } catch { operationStatus = "Could not store copied image"; rebuildMenu() }
            return
        }
        if let text = copiedText, history.add(text, app: app, provenance: provenance) { persistHistory() }
    }

    @objc func smartPaste() {
        guard !selecting else { trace?.record(.busy); return }
        let trace = PasteTrace(); self.trace = trace
        trace.record(.accepted, count: history.items.count)
        guard !paused else { showError("Clipboard collection is paused. Resume it from the menu."); return }
        pollClipboard()
        guard ready else { showError(status, reason: .worker_unavailable); return }
        let started = Date(); requestStarted = started
        do {
            trace.record(.snapshot_started)
            let target = try InputTarget.snapshot()
            trace.record(.snapshot_ready)
            Logger(subsystem: "local.daniel.LayaClipboard", category: "context")
                .notice("role=\(target.destinationRole, privacy: .public) caret_source=\(target.evidence.insertion?.source ?? "none", privacy: .public) ocr_needed=\(target.evidence.needsOCR, privacy: .public)")
            let capability = InsertionContext.capabilitySummary(target.element)
            Logger(subsystem: "local.daniel.LayaClipboard", category: "context")
                .notice("\(capability, privacy: .public) before_bytes=\(target.evidence.insertion?.before.utf8.count ?? 0, privacy: .public) after_bytes=\(target.evidence.insertion?.after.utf8.count ?? 0, privacy: .public)")
            self.target = target
            lease = PasteLease(clipboardVersion: NSPasteboard.general.changeCount, createdAt: Date())
            let id = trace.id; requestID = id; selecting = true
            let items = ClipboardSelection.candidates(history: history, pins: pins,
                                                      destinationRole: target.destinationRole)
            operationStatus = "Selecting for \(target.appName)…"
            suggestions.removeAll(); selected = nil
            startPulse(); rebuildMenu()
            if items.isEmpty {
                self.timing = "No history · latest clipboard"
                self.paste(useLatestClipboard: true)
                return
            }
            Task { @MainActor in
                do {
                    let context = try await ContextCapture.capture(target, trace: trace)
                    guard self.requestID == id else { return }
                    try self.validateTarget(target)
                    trace.record(.ranking_started, count: items.count)
                    self.worker.select(context: context.text, clips: items) { [weak self] result in
                        guard let self, self.requestID == id else { return }
                        switch result {
                        case .success(let reply):
                            trace.record(.ranking_ready, count: reply.eligible ?? reply.ranked?.count ?? 0,
                                         modelMS: reply.elapsed_ms ?? -1, queueMS: reply.queue_ms ?? -1)
                            let safeDecision = ["jev", "latest"].contains(reply.decision ?? "")
                                ? reply.decision! : "unknown"
                            let originalIndex = items.firstIndex { $0.id == reply.model_choice } ?? -1
                            let selectedIndex = items.firstIndex { $0.id == reply.ranked?.first?.id } ?? -1
                            Logger(subsystem: "local.daniel.LayaClipboard", category: "selection")
                                .notice("decision=\(safeDecision, privacy: .public) role=\(target.destinationRole, privacy: .public) candidates=\(items.count, privacy: .public) model_index=\(originalIndex, privacy: .public) final_index=\(selectedIndex, privacy: .public) recency_changed=\(reply.recency_changed ?? false, privacy: .public) score=\(reply.ranked?.first?.score ?? -1, privacy: .public)")
                            do { try self.validateTarget(target) }
                            catch { self.showError(error.localizedDescription, errorCode: (error as NSError).code); return }
                            guard self.lease?.valid(clipboardVersion: NSPasteboard.general.changeCount) == true else {
                                self.showError("Clipboard changed or selection timed out. Try again."); return
                            }
                            let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
                            self.suggestions = (reply.ranked ?? []).compactMap { byID[$0.id] }
                            self.selected = self.suggestions.first
                            let total = Date().timeIntervalSince(started) * 1000
                            self.timing = String(format: "%.0f ms selection · %.0f ms capture · %.0f ms OCR · %.0f ms Jev API", total, context.captureMilliseconds, context.ocrMilliseconds, reply.elapsed_ms ?? 0)
                            self.paste(useLatestClipboard: reply.usesLatestClipboard)
                        case .failure(let error): self.showError(error.localizedDescription, errorCode: (error as NSError).code)
                        }
                    }
                } catch {
                    guard self.requestID == id else { return }
                    self.showError(error.localizedDescription, errorCode: (error as NSError).code)
                }
            }
        } catch { showError(error.localizedDescription, errorCode: (error as NSError).code) }
    }

    private func paste(useLatestClipboard: Bool = false) {
        guard !fixture, let target, useLatestClipboard || selected != nil else {
            showError("No matching clipboard text."); return
        }
        do { try validateTarget(target) }
        catch { showError(error.localizedDescription, errorCode: (error as NSError).code); return }
        guard lease?.valid(clipboardVersion: NSPasteboard.general.changeCount) == true else {
            showError("Clipboard changed or selection timed out. Try again."); return
        }
        // Selection begins on key-down. Deliver immediately when ready, even
        // while the invoking keys remain physically held.
        do { try self.validateTarget(target) }
        catch { self.showError(error.localizedDescription, errorCode: (error as NSError).code); return }
        guard self.lease?.valid(clipboardVersion: NSPasteboard.general.changeCount) == true else {
            self.showError("Clipboard changed before pasting. Try again."); return
        }
        guard let events = PasteKeyboard.events() else {
            self.showError("macOS could not create a paste event."); return
        }
        let pb = NSPasteboard.general
        if useLatestClipboard, let text = PasteboardPayload.plainTextForLatest(pb) {
            guard PasteboardPayload(content: .text(text)).write(to: pb) else {
                self.showError("Could not prepare the clipboard."); return
            }
            self.lastChange = pb.changeCount
            self.clipboardProvenance = .ownWrite(original: self.clipboardProvenance)
        }
        if !useLatestClipboard, let selected {
            guard let payload = PasteboardPayload(clip: selected, store: store) else {
                self.showError("Saved item is unavailable. Nothing was pasted."); return
            }
            guard payload.write(to: pb) else { self.showError("Could not prepare the clipboard."); return }
            self.lastChange = pb.changeCount
            self.clipboardProvenance = .ownWrite(original: selected.provenance)
            self.clipboardAssetID = selected.assetID
        }
        // Ordinary fallback leaves the system pasteboard (including rich formats)
        // untouched. The lease above still proves it is the clipboard from invocation.
        if useLatestClipboard { self.trace?.record(.latest_clipboard) }
        self.requestID = UUID(); self.selecting = false; self.target = nil; self.lease = nil
        self.operationStatus = useLatestClipboard ? "Latest clipboard → \(target.appName)" : "Jev match → \(target.appName)"
        let totalMilliseconds = Date().timeIntervalSince(self.requestStarted) * 1000
        self.timing += String(format: " · %.0f ms to paste", totalMilliseconds)
        Logger(subsystem: "local.daniel.LayaClipboard", category: "performance").info("smart_paste_ms=\(totalMilliseconds, privacy: .public)")
        self.rebuildMenu(); self.finishPulse()
        // Address the verified PID so an app switch cannot redirect the paste elsewhere.
        for event in events { event.postToPid(target.pid) }
        self.trace?.record(.paste_posted)
    }

    private func validateTarget(_ target: InputTarget) throws {
        trace?.record(.validation_started)
        try target.validateCurrent()
        trace?.record(.validation_ready)
    }

    private func cancel() {
        trace?.record(.cancelled, reason: .user_cancelled)
        let wasSelecting = selecting
        requestID = UUID(); selecting = false; target = nil; lease = nil
        stopPulse()
        if wasSelecting { operationStatus = "Selection cancelled" }
        rebuildMenu()
    }

    private func showError(_ message: String, reason: PasteReason? = nil, errorCode: Int = 0) {
        trace?.record(.failed, reason: reason ?? PasteReason.classify(message), errorCode: errorCode)
        cancel()
        operationStatus = message
        statusItem.button?.toolTip = message
        startPulse(); finishPulse(); rebuildMenu()
    }

    private func updateIcon() {
        statusItem.button?.image = NSImage(systemSymbolName: ready ? "clipboard.fill" : "clipboard", accessibilityDescription: "Jev Clipboard")
        statusItem.button?.contentTintColor = nil
        statusItem.button?.alphaValue = 1
        statusItem.button?.toolTip = operationStatus ?? status
    }

    private func startPulse() {
        stopPulse()
        statusItem.button?.contentTintColor = .controlAccentColor
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let timer = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.pulsePhase.toggle()
            self.statusItem.button?.alphaValue = self.pulsePhase ? 0.45 : 1
        }
        pulseTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func finishPulse() {
        let token = pulseToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.pulseToken == token else { return }
            self.stopPulse()
        }
    }

    private func stopPulse() {
        pulseToken = UUID(); pulseTimer?.invalidate(); pulseTimer = nil
        updateIcon()
    }

    func menuWillOpen(_ menu: NSMenu) { rebuildMenu() }

    private func rebuildMenu() {
        let menu = statusItem.menu ?? NSMenu()
        menu.removeAllItems()
        menu.delegate = self
        if !ready { menu.addItem(NSMenuItem(title: status, action: nil, keyEquivalent: "")) }
        add(menu, "Open Clipboard…", #selector(openHistoryWindow))
        add(menu, "Smart Paste  ⌘⇧V", #selector(menuSmartPaste))
        if selecting { add(menu, "Cancel Selection", #selector(cancelSelection)) }
        add(menu, paused ? "Resume Collection" : "Pause Collection", #selector(togglePause))
        menu.addItem(.separator())
        let troubleshooting = NSMenuItem(title: "Troubleshooting", action: nil, keyEquivalent: "")
        let tools = NSMenu()
        tools.addItem(NSMenuItem(title: status, action: nil, keyEquivalent: ""))
        if !timing.isEmpty { tools.addItem(NSMenuItem(title: timing, action: nil, keyEquivalent: "")) }
        tools.addItem(.separator())
        add(tools, "Allow Accessibility…", #selector(accessibility))
        add(tools, "Allow Screen Recording…", #selector(screenPermission))
        add(tools, "Set TypeSafe Key from Clipboard…", #selector(configureJev))
        add(tools, "Restart Jev", #selector(restart))
        troubleshooting.submenu = tools
        menu.addItem(troubleshooting)
        menu.addItem(.separator())
        add(menu, "Quit Jev Clipboard", #selector(quit))
        statusItem.menu = menu
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem(title: "Jev Clipboard", action: nil, keyEquivalent: "")
        let appMenu = NSMenu()
        let quitItem = appMenu.addItem(withTitle: "Quit Jev Clipboard", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        for (title, action, key, modifiers) in [
            ("Undo", "undo:", "z", NSEvent.ModifierFlags.command),
            ("Redo", "redo:", "z", [.command, .shift]),
            ("Cut", "cut:", "x", .command),
            ("Copy", "copy:", "c", .command),
            ("Paste", "paste:", "v", .command),
            ("Select All", "selectAll:", "a", .command)
        ] {
            let item = NSMenuItem(title: title, action: Selector(action), keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            editMenu.addItem(item)
        }
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    private func add(_ menu: NSMenu, _ title: String, _ action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self; menu.addItem(item)
    }
    @objc private func menuSmartPaste() {
        DispatchQueue.main.async { self.smartPaste() }
    }
    @objc private func cancelSelection() { cancel() }
    @objc private func togglePause() { paused.toggle(); cancel(); rebuildMenu(); refreshHistoryModel() }
    @objc private func clearHistory() {
        history.clear(); suggestions.removeAll(); selected = nil; timing = ""; operationStatus = nil
        cancel(); persistHistory()
    }
    private func persistHistory() {
        do { try store.save(history: history, pins: pins) }
        catch { operationStatus = "Could not save clipboard history" }
        refreshHistoryModel(); rebuildMenu()
    }
    private func refreshHistoryModel() {
        historyModel.items = history.items
        historyModel.pins = pins
        historyModel.paused = paused
        historyModel.message = operationStatus ?? ""
    }
    private func configureHistoryModel() {
        historyModel.imageURL = { [weak self] id in self?.store.imagePath(id: id) }
        historyModel.onCopy = { [weak self] id in self?.copyItem(id: id) }
        historyModel.onDelete = { [weak self] id in
            guard let self, self.history.delete(id: id) else { return }
            self.persistHistory()
        }
        historyModel.onClear = { [weak self] in self?.clearHistory() }
        historyModel.onPause = { [weak self] in self?.togglePause() }
        historyModel.assetURL = { [weak self] entry in self?.store.assetPath(entry) }
        historyModel.onImportAsset = { [weak self] id, url, kind, otherBytes, completion in
            guard let self else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                let result = Result { try self.store.importAsset(from: url, id: id, kind: kind,
                                                                  otherAssetBytes: otherBytes) }
                DispatchQueue.main.async { completion(result) }
            }
        }
        historyModel.onSavePins = { [weak self] newPins in
            guard let self, newPins.count <= PinnedEntry.maximumCount else { return }
            self.cancel()
            let previous = self.pins
            self.pins = newPins
            do {
                try self.store.save(history: self.history, pins: self.pins)
                self.store.removeUnusedAssets(keeping: self.pins, protectedAssetID: self.clipboardAssetID)
                self.operationStatus = "Persistent entries saved"
            } catch {
                self.pins = previous
                self.operationStatus = error.localizedDescription
            }
            self.refreshHistoryModel(); self.rebuildMenu()
        }
        refreshHistoryModel()
    }
    private func copyItem(id: String) {
        guard let clip = (history.items + pins.compactMap(\.clip)).first(where: { $0.id == id }) else { return }
        cancel()
        let pb = NSPasteboard.general
        guard let payload = PasteboardPayload(clip: clip, store: store), payload.write(to: pb) else { return }
        lastChange = pb.changeCount
        clipboardProvenance = .ownWrite(original: clip.provenance)
        clipboardAssetID = clip.assetID
        operationStatus = "Copied \(clip.kind.rawValue)"
        refreshHistoryModel(); rebuildMenu()
    }
    @objc private func openHistoryWindow() {
        if historyWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "Jev Clipboard"
            window.center()
            window.contentView = NSHostingView(rootView: HistoryWindowView(model: historyModel))
            window.isReleasedWhenClosed = false
            window.delegate = self
            historyWindow = window
        }
        refreshHistoryModel()
        NSApp.setActivationPolicy(.regular)
        historyWindow?.deminiaturize(nil)
        historyWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    @objc private func configureJev() {
        cancel()
        do {
            guard let key = NSPasteboard.general.string(forType: .string) else {
                throw ClipboardError.message("Copy your TypeSafe API key first.")
            }
            try JevCredential.save(key)
            // A copied credential must not enter candidate history.
            history.clear(); suggestions.removeAll(); selected = nil
            persistHistory()
            lastChange = NSPasteboard.general.changeCount
            operationStatus = "Key saved in macOS Keychain"
            ready = false; worker?.start()
        } catch { showError(error.localizedDescription) }
    }
    @objc private func restart() { cancel(); ready = false; worker?.start() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func accessibility() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }
    @objc private func screenPermission() { CGRequestScreenCaptureAccess() }
}

@main struct LayaClipboardMain {
    static func main() {
        let app = NSApplication.shared
        // Explicit local diagnostic mode: capability names, lengths and fixture
        // comparisons only. No raw AX text, clipboard access or hosted requests.
        if let index = CommandLine.arguments.firstIndex(of: "--inspect-focused-app"),
           CommandLine.arguments.count > index + 1 {
            let bundleID = CommandLine.arguments[index + 1]
            var report: [String: Any] = ["trusted": AXIsProcessTrusted(),
                "timestamp": Date().timeIntervalSince1970, "target_bundle": bundleID]
            if let target = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                let root = AXUIElementCreateApplication(target.processIdentifier)
                AXUIElementSetMessagingTimeout(root, 0.2)
                if let focused = axElement(root, kAXFocusedUIElementAttribute) {
                    let started = Date()
                    let captured = InsertionContext.collect(focused)
                        ?? InsertionContext.findDescendant(focused)?.context
                    report["role"] = axText(focused, kAXRoleAttribute)
                    report["capabilities"] = InsertionContext.capabilitySummary(focused)
                    report["source"] = captured?.source ?? "none"
                    report["before_bytes"] = captured?.before.utf8.count ?? 0
                    report["after_bytes"] = captured?.after.utf8.count ?? 0
                    report["capture_ms"] = Date().timeIntervalSince(started) * 1000
                    // Only our synthetic fixture gets content assertions.
                    if bundleID == "local.daniel.JevCaptureFixture" {
                        report["fixture_before_matches"] = captured?.before.hasSuffix("Synthetic reference: ") == true
                        report["fixture_after_matches"] = captured?.after.hasPrefix(" for this request.") == true
                    }
                } else { report["error"] = "focused_element_unavailable" }
            } else { report["error"] = "target_not_running" }
            let data = try! JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
            let output = Bundle.main.bundleURL.deletingLastPathComponent()
                .appendingPathComponent("results/jev-app/capture-diagnostics.json")
            try? data.write(to: output, options: .atomic)
            print(String(data: data, encoding: .utf8)!)
            return
        }
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
