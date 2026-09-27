import AppKit
import ApplicationServices
import ScreenCaptureKit
import Vision
import CryptoKit
import Carbon

enum ClipboardError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

func axValue(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
    return value
}

func axElement(_ element: AXUIElement, _ key: String) -> AXUIElement? {
    guard let value = axValue(element, key), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return (value as! AXUIElement)
}

func axText(_ element: AXUIElement, _ key: String) -> String {
    String((axValue(element, key) as? String ?? "").prefix(1000))
}

func axPlainText(_ raw: Any?) -> String? {
    if let text = raw as? String { return text }
    if let attributed = raw as? NSAttributedString { return attributed.string }
    return nil
}

func axMarkerRange(_ element: AXUIElement, _ key: String) -> AXTextMarkerRange? {
    guard let raw = axValue(element, key), CFGetTypeID(raw) == AXTextMarkerRangeGetTypeID() else { return nil }
    return (raw as! AXTextMarkerRange)
}

/// Injectable read-only AX access keeps provider behavior testable without a
/// fabricated successful insertion context bypassing the actual adapter.
struct AXTextReader {
    let element: AXUIElement
    var attribute: (String) -> CFTypeRef?
    var parameter: (String, CFTypeRef) -> CFTypeRef?

    init(_ element: AXUIElement) {
        self.element = element
        attribute = { axValue(element, $0) }
        parameter = { name, argument in
            var value: CFTypeRef?
            guard AXUIElementCopyParameterizedAttributeValue(element, name as CFString,
                argument, &value) == .success else { return nil }
            return value
        }
    }
}

struct InputTarget {
    let pid: pid_t
    let appName: String
    let bundleID: String
    let destinationRole: String
    let element: AXUIElement
    let caretElement: AXUIElement?
    let caretFingerprint: String?
    let window: AXUIElement
    let fingerprint: String
    let windowTitle: String
    let fieldText: String
    let evidence: FieldEvidence
    let frame: CGRect?

    static func snapshot() throws -> InputTarget {
        guard !IsSecureEventInputEnabled() else {
            throw ClipboardError.message("Smart paste is disabled while secure keyboard input is active.")
        }
        guard AXIsProcessTrusted() else {
            throw ClipboardError.message("Accessibility was unavailable for this attempt. Check permissions in Settings, then try again.")
        }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            throw ClipboardError.message("Select a text field in another app first.")
        }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.4)
        guard let window = axElement(root, kAXFocusedWindowAttribute) else {
            throw ClipboardError.message("This app does not expose an active window. Use clipboard history from the menu.")
        }
        // A page or canvas can handle Paste without focusing a text input.
        let focused = axElement(root, kAXFocusedUIElementAttribute) ?? window
        let role = axText(focused, kAXRoleAttribute)
        let subrole = axText(focused, kAXSubroleAttribute)
        guard subrole != kAXSecureTextFieldSubrole,
              !subrole.localizedCaseInsensitiveContains("secure") else {
            throw ClipboardError.message("Smart paste is disabled in secure fields.")
        }
        var settable = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(focused, kAXValueAttribute as CFString, &settable)
        var editable = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role) || settable.boolValue
        let fingerprint = signature(focused)
        var evidence = FieldEvidence.collect(focused, app: app, window: window)
        var caretElement: AXUIElement? = nil
        // The focused container can own a web selection without exposing a
        // settable AXValue. Do not use that capability as a prerequisite.
        if !CFEqual(focused, window) && evidence.insertion == nil,
           let match = InsertionContext.findDescendant(focused) {
            evidence.insertion = match.context
            caretElement = match.element
        }
        editable = editable || evidence.insertion != nil
        let caretFingerprint = caretElement.map { signature($0) }
        if evidence.field.role.isEmpty { evidence.field.role = role }
        if evidence.field.subrole.isEmpty { evidence.field.subrole = subrole }
        evidence.destinationKind = editable ? "editable" : "window"
        if !editable { evidence.field.bounds = FieldEvidence.bounds(rect(window)) }
        guard signature(focused) == fingerprint else {
            throw ClipboardError.message("Input text or cursor changed while reading context. Try again.")
        }
        return InputTarget(pid: app.processIdentifier, appName: app.localizedName ?? "App",
                           bundleID: app.bundleIdentifier ?? "", destinationRole: role,
                           element: focused, caretElement: caretElement, caretFingerprint: caretFingerprint,
                           window: window,
                           fingerprint: fingerprint, windowTitle: axText(window, kAXTitleAttribute),
                           fieldText: try evidence.encoded(), evidence: evidence, frame: rect(window))
    }

    static func signature(_ element: AXUIElement) -> String {
        let ordinary = axValue(element, kAXSelectedTextRangeAttribute)
        let selection = ordinary.flatMap { CFGetTypeID($0) == AXValueGetTypeID() ? $0 : nil }
            ?? axValue(element, "AXSelectedTextMarkerRange")
        return fingerprint(value: axPlainText(axValue(element, kAXValueAttribute)) ?? "",
                           selectionValue: selection)
    }

    static func fingerprint(value: String, selectionValue: CFTypeRef?) -> String {
        // Hash the full value in memory; AXValue descriptions include unstable addresses.
        var selection = "unavailable"
        if let raw = selectionValue, CFGetTypeID(raw) == AXValueGetTypeID() {
            var range = CFRange()
            if AXValueGetValue(raw as! AXValue, .cfRange, &range) {
                selection = "\(range.location):\(range.length)"
            }
        } else if let raw = selectionValue, CFGetTypeID(raw) == AXTextMarkerRangeGetTypeID() {
            let range = raw as! AXTextMarkerRange
            let start = AXTextMarkerRangeCopyStartMarker(range)
            let end = AXTextMarkerRangeCopyEndMarker(range)
            let startBytes = Data(bytes: AXTextMarkerGetBytePtr(start), count: AXTextMarkerGetLength(start))
            let endBytes = Data(bytes: AXTextMarkerGetBytePtr(end), count: AXTextMarkerGetLength(end))
            selection = SHA256.hash(data: startBytes + endBytes).description
        }
        return SHA256.hash(data: Data((value + "\u{0}" + selection).utf8)).description
    }

    func validateCurrent() throws {
        guard !IsSecureEventInputEnabled() else {
            throw ClipboardError.message("Smart paste is disabled while secure keyboard input is active.")
        }
        guard AXIsProcessTrusted() else {
            throw ClipboardError.message("Accessibility was unavailable for this attempt. Check permissions in Settings, then try again.")
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
            throw ClipboardError.message("Active app changed. Select the destination and try again.")
        }
        let root = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(root, 0.4)
        guard let currentWindow = axElement(root, kAXFocusedWindowAttribute), CFEqual(currentWindow, window) else {
            throw ClipboardError.message("Active window changed. Try again.")
        }
        let focused = axElement(root, kAXFocusedUIElementAttribute) ?? currentWindow
        guard CFEqual(focused, element) else {
            throw ClipboardError.message("Paste destination changed. Try again.")
        }
        guard !axText(focused, kAXSubroleAttribute).localizedCaseInsensitiveContains("secure") else {
            throw ClipboardError.message("Smart paste is disabled in secure fields.")
        }
        guard Self.signature(focused) == fingerprint else {
            throw ClipboardError.message("Input text or cursor changed during selection. Try again.")
        }
        if let caretElement, let caretFingerprint {
            guard Self.signature(caretElement) == caretFingerprint,
                  InsertionContext.collect(caretElement) != nil else {
                throw ClipboardError.message("Input text or cursor changed during selection. Try again.")
            }
        }
        // Window titles and nearby labels can change without changing the paste destination.
    }

    func isCurrent() -> Bool { (try? validateCurrent()) != nil }

    static func rect(_ element: AXUIElement) -> CGRect? {
        guard let p = axValue(element, kAXPositionAttribute), let s = axValue(element, kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point),
              AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }
}

struct CapturedContext {
    let text: String
    let milliseconds: Double
    let captureMilliseconds: Double
    let ocrMilliseconds: Double
}

enum ContextCapture {
    static func capture(_ target: InputTarget, trace: PasteTrace? = nil) async throws -> CapturedContext {
        let start = Date()
        func axOnly() -> CapturedContext {
            CapturedContext(text: target.fieldText, milliseconds: Date().timeIntervalSince(start)*1000,
                            captureMilliseconds: 0, ocrMilliseconds: 0)
        }
        // Explicit AX labels need no screenshot. Missing capture permission does not
        // invalidate already usable AX context; uncertain context falls back normally.
        if !target.evidence.needsOCR || target.evidence.field.bounds.count != 4 || !CGPreflightScreenCaptureAccess() {
            return axOnly()
        }
        trace?.record(.windows_started)
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) else {
            return axOnly()
        }
        trace?.record(.windows_ready)
        let windows = content.windows.filter {
            $0.owningApplication?.processID == target.pid && $0.windowLayer == 0 && $0.frame.width > 50
        }
        // Require a matching focused window, rather than capturing another window from this app.
        let candidates = windows.filter { candidate in
            if let rect = target.frame {
                return abs(rect.minX - candidate.frame.minX) < 8 && abs(rect.minY - candidate.frame.minY) < 8
                    && abs(rect.width - candidate.frame.width) < 8 && abs(rect.height - candidate.frame.height) < 8
            }
            return !target.windowTitle.isEmpty && candidate.title == target.windowTitle
        }
        guard candidates.count == 1, let window = candidates.first else { return axOnly() }
        let config = SCStreamConfiguration()
        let scale = min(1, 1400 / max(window.frame.width, window.frame.height))
        config.width = max(1, Int(window.frame.width * scale))
        config.height = max(1, Int(window.frame.height * scale))
        config.showsCursor = false
        trace?.record(.screenshot_started)
        guard let image = try? await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: config) else {
            return axOnly()
        }
        let capturedAt = Date()
        trace?.record(.screenshot_ready)
        trace?.record(.ocr_started)
        let inputBounds = target.evidence.field.bounds
        let windowFrame = window.frame
        let ocrTask = Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false
            if inputBounds.count == 4 {
                let input = CGRect(x: inputBounds[0], y: inputBounds[1], width: inputBounds[2], height: inputBounds[3])
                let region = input.insetBy(dx: -260, dy: -100).intersection(windowFrame)
                if !region.isNull {
                    request.regionOfInterest = CGRect(x: (region.minX-windowFrame.minX)/windowFrame.width,
                        y: 1-(region.maxY-windowFrame.minY)/windowFrame.height,
                        width: region.width/windowFrame.width, height: region.height/windowFrame.height)
                }
            }
            try VNImageRequestHandler(cgImage: image).perform([request])
            return (request.results ?? []).prefix(24).compactMap { observation -> ContextText? in
                guard let candidate = observation.topCandidates(1).first, candidate.confidence >= 0.65 else { return nil }
                let b = observation.boundingBox
                let rect = CGRect(x: windowFrame.minX+b.minX*windowFrame.width,
                    y: windowFrame.minY+(1-b.maxY)*windowFrame.height,
                    width: b.width*windowFrame.width, height: b.height*windowFrame.height)
                return ContextText(text: String(candidate.string.prefix(160)), role: kAXStaticTextRole,
                    source: "ocr", bounds: FieldEvidence.bounds(rect), confidence: Double(candidate.confidence))
            }
        }
        guard let text = try? await ocrTask.value else { return axOnly() }
        trace?.record(.ocr_ready)
        var evidence = target.evidence
        evidence.ocr = text
        let context = (try? evidence.encoded()) ?? target.fieldText
        return CapturedContext(text: context,
                               milliseconds: Date().timeIntervalSince(start) * 1000,
                               captureMilliseconds: capturedAt.timeIntervalSince(start) * 1000,
                               ocrMilliseconds: Date().timeIntervalSince(capturedAt) * 1000)
    }
}

// Captured facts remain separate from model interpretations and editable values.
struct ContextText: Codable {
    var text: String
    var role: String
    var source: String = "ax"
    var bounds: [Double] = []
    var depth: Int = 0
    var confidence: Double = 1
}
struct ContextField: Codable {
    var role: String
    var subrole: String
    var identifier: String
    var attributes: [String: String]
    var linkedLabels: [String]
    var bounds: [Double]
}
/// AX text ranges use UTF-16 offsets, not Swift Character offsets.
struct InsertionContext: Codable, Equatable {
    var source = "ax_value_and_selected_text_range"
    var before: String
    var after: String
    var replacing: String
    var isReplacement: Bool

    static func excerpt(_ text: Substring, bytes: Int, suffix: Bool = false) -> String {
        func take<S: Sequence>(_ scalars: S) -> String where S.Element == Unicode.Scalar {
            var result = "", used = 0
            for scalar in scalars {
                let size = String(scalar).utf8.count
                if used + size > bytes { break }
                result.unicodeScalars.append(scalar); used += size
            }
            return result
        }
        if suffix {
            let reversed = take(text.unicodeScalars.reversed())
            return String(String.UnicodeScalarView(reversed.unicodeScalars.reversed()))
        }
        return take(text.unicodeScalars)
    }

    static func make(value: String, range: CFRange?) -> InsertionContext? {
        guard let range, range.location >= 0, range.length >= 0 else { return nil }
        let units = value.utf16
        guard range.location <= units.count, range.length <= units.count - range.location else { return nil }
        let start16 = units.index(units.startIndex, offsetBy: range.location)
        let end16 = units.index(start16, offsetBy: range.length)
        // String.Index conversion alone may allow a position inside a surrogate pair.
        guard let start = start16.samePosition(in: value.unicodeScalars),
              let end = end16.samePosition(in: value.unicodeScalars) else { return nil }
        let before = excerpt(value[..<start], bytes: 600, suffix: true)
        let after = excerpt(value[end...], bytes: 240)
        let replacing = excerpt(value[start..<end], bytes: 160)
        return InsertionContext(before: before, after: after, replacing: replacing, isReplacement: range.length > 0)
    }

    static func collect(_ element: AXUIElement) -> InsertionContext? {
        guard !axText(element, kAXSubroleAttribute).localizedCaseInsensitiveContains("secure") else { return nil }
        // Read the value and range together, before/after fingerprint checks reject edits.
        var raw: CFArray?
        let keys = [kAXValueAttribute, kAXSelectedTextRangeAttribute]
        var value: String?
        var selectedRange: Any?
        if AXUIElementCopyMultipleAttributeValues(element, keys as CFArray, [], &raw) == .success,
           let values = raw as? [Any], values.count == 2 {
            value = axPlainText(values[0])
            selectedRange = values[1]
        }
        // Some rich editors reject the batch call while exposing both
        // attributes individually. Keep this fallback bounded by the element's
        // short AX messaging timeout.
        if value == nil { value = axPlainText(axValue(element, kAXValueAttribute)) }
        if selectedRange == nil || CFGetTypeID(selectedRange! as CFTypeRef) != AXValueGetTypeID() {
            selectedRange = axValue(element, kAXSelectedTextRangeAttribute)
        }
        if let value, let selectedRange,
           CFGetTypeID(selectedRange as CFTypeRef) == AXValueGetTypeID() {
            var range = CFRange()
            if AXValueGetValue(selectedRange as! AXValue, .cfRange, &range),
               let context = make(value: value, range: range) { return context }
        }
        return collectTextMarkers(element)
    }

    static func collectTextMarkers(_ element: AXUIElement, reader supplied: AXTextReader? = nil) -> InsertionContext? {
        let reader = supplied ?? AXTextReader(element)
        func range(_ raw: CFTypeRef?) -> AXTextMarkerRange? {
            guard let raw, CFGetTypeID(raw) == AXTextMarkerRangeGetTypeID() else { return nil }
            return (raw as! AXTextMarkerRange)
        }
        func marker(_ raw: CFTypeRef?) -> AXTextMarker? {
            guard let raw, CFGetTypeID(raw) == AXTextMarkerGetTypeID() else { return nil }
            return (raw as! AXTextMarker)
        }
        guard let selected = range(reader.attribute("AXSelectedTextMarkerRange")) else { return nil }
        let start = AXTextMarkerRangeCopyStartMarker(selected)
        let end = AXTextMarkerRangeCopyEndMarker(selected)
        // WebKit exposes the element's extent through a *parameterized* query,
        // not an AXTextMarkerRange attribute. Prefer that focused-element scope.
        let entire = range(reader.parameter("AXTextMarkerRangeForUIElement", element))
        var first = entire.map { AXTextMarkerRangeCopyStartMarker($0) }
        var last = entire.map { AXTextMarkerRangeCopyEndMarker($0) }
        // Other providers expose only line ranges or document endpoints.
        if first == nil, let line = range(reader.parameter("AXLineTextMarkerRangeForTextMarker", start)) {
            first = AXTextMarkerRangeCopyStartMarker(line)
        }
        if last == nil, let line = range(reader.parameter("AXLineTextMarkerRangeForTextMarker", end)) {
            last = AXTextMarkerRangeCopyEndMarker(line)
        }
        if first == nil { first = marker(reader.attribute("AXStartTextMarker")) }
        if last == nil { last = marker(reader.attribute("AXEndTextMarker")) }
        guard let first, let last else { return nil }
        func text(_ from: AXTextMarker, _ to: AXTextMarker) -> String? {
            let span = AXTextMarkerRangeCreate(nil, from, to)
            return axPlainText(reader.parameter("AXStringForTextMarkerRange", span))
        }
        guard let before = text(first, start), let after = text(end, last),
              let replacing = text(start, end) else { return nil }
        return InsertionContext(source: "ax_text_marker_range",
            before: excerpt(before[...], bytes: 600, suffix: true),
            after: excerpt(after[...], bytes: 240),
            replacing: excerpt(replacing[...], bytes: 160),
            isReplacement: !replacing.isEmpty)
    }

    static func capabilitySummary(_ element: AXUIElement) -> String {
        var attributes: CFArray?, parameters: CFArray?
        let a = AXUIElementCopyAttributeNames(element, &attributes)
        let p = AXUIElementCopyParameterizedAttributeNames(element, &parameters)
        let names = Set(attributes as? [String] ?? [])
        let params = Set(parameters as? [String] ?? [])
        // Only fixed feature names and booleans; no attribute values or content.
        return "attributes_status=\(a.rawValue) parameters_status=\(p.rawValue) value=\(names.contains(kAXValueAttribute)) range=\(names.contains(kAXSelectedTextRangeAttribute)) selected_markers=\(names.contains("AXSelectedTextMarkerRange")) element_extent=\(params.contains("AXTextMarkerRangeForUIElement")) line_extent=\(params.contains("AXLineTextMarkerRangeForTextMarker")) start=\(names.contains("AXStartTextMarker")) end=\(names.contains("AXEndTextMarker")) marker_text=\(params.contains("AXStringForTextMarkerRange"))"
    }

    static func findDescendant(_ root: AXUIElement) -> (context: InsertionContext, element: AXUIElement)? {
        // Search only for a child that the provider identifies as focused.
        // A nonfocused field may expose a stale/default selection of its own.
        let deadline = ProcessInfo.processInfo.systemUptime + 0.10
        var queue = (axValue(root, kAXChildrenAttribute) as? [AXUIElement] ?? []).prefix(20)
            .map { ($0, 1) }
        var visited = 0
        while !queue.isEmpty, visited < 24, ProcessInfo.processInfo.systemUptime < deadline {
            let (node, depth) = queue.removeFirst()
            visited += 1
            AXUIElementSetMessagingTimeout(node, 0.025)
            if axValue(node, kAXFocusedAttribute) as? Bool == true, let context = collect(node) {
                return (context, node)
            }
            if depth < 2, let children = axValue(node, kAXChildrenAttribute) as? [AXUIElement] {
                queue.append(contentsOf: children.prefix(8).map { ($0, depth + 1) })
            }
        }
        return nil
    }
}
struct FieldEvidence: Codable {
    var version = 2
    var destinationKind = "editable"
    var app: String
    var bundleID: String
    var windowTitle: String
    var field: ContextField
    var ancestors: [ContextText] = []
    var nearby: [ContextText] = []
    var ocr: [ContextText] = []
    var nearbyInputs: [[Double]] = []
    var headings: [ContextText] = []
    var budgetExhausted = false
    var insertion: InsertionContext? = nil

    static func bounds(_ rect: CGRect?) -> [Double] {
        guard let rect else { return [] }
        return [rect.minX, rect.minY, rect.width, rect.height]
    }
    static func metadata(_ node: AXUIElement, deadline: TimeInterval) -> [String: String] {
        let keys = [kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute,
                    kAXDescriptionAttribute, kAXHelpAttribute, "AXPlaceholderValue", "AXIdentifier"]
        var raw: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(node, keys as CFArray, [], &raw) == .success,
              let values = raw as? [Any], values.count == keys.count else {
            var fallback: [String: String] = [:]
            for key in keys where ProcessInfo.processInfo.systemUptime < deadline {
                let value = String(axText(node, key).prefix(220))
                if !value.isEmpty { fallback[key] = value }
            }
            return fallback
        }
        return Dictionary(uniqueKeysWithValues: zip(keys, values).compactMap { key, value in
            guard let text = value as? String, !text.isEmpty else { return nil }
            return (key, String(text.prefix(220)))
        })
    }
    static func collect(_ target: AXUIElement, app: NSRunningApplication, window: AXUIElement) -> FieldEvidence {
        let deadline = ProcessInfo.processInfo.systemUptime + 0.12
        AXUIElementSetMessagingTimeout(target, 0.05)
        let attrs = metadata(target, deadline: deadline)
        var labels: [String] = []
        if let title = axElement(target, kAXTitleUIElementAttribute) {
            let text = [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute]
                .map { axText(title, $0) }.first { !$0.isEmpty }
            if let text { labels.append(String(text.prefix(180))) }
        }
        let names = [("title", kAXTitleAttribute), ("description", kAXDescriptionAttribute),
                     ("help", kAXHelpAttribute), ("placeholder", "AXPlaceholderValue")]
        let field = ContextField(role: attrs[kAXRoleAttribute] ?? "", subrole: attrs[kAXSubroleAttribute] ?? "",
            identifier: attrs["AXIdentifier"] ?? "", attributes: Dictionary(uniqueKeysWithValues: names.compactMap { name, key in
                attrs[key].map { (name, $0) }
            }), linkedLabels: labels, bounds: bounds(InputTarget.rect(target)))
        var evidence = FieldEvidence(app: app.localizedName ?? "App", bundleID: app.bundleIdentifier ?? "",
            windowTitle: String(axText(window, kAXTitleAttribute).prefix(160)), field: field)
        evidence.insertion = InsertionContext.collect(target)
        var node = target
        var seen: [AXUIElement] = [target]
        var visited = 0
        for depth in 0..<4 {
            guard ProcessInfo.processInfo.systemUptime < deadline,
                  let parent = axElement(node, kAXParentAttribute), !seen.contains(where: { CFEqual($0, parent) }) else { break }
            seen.append(parent)
            AXUIElementSetMessagingTimeout(parent, 0.025)
            let meta = metadata(parent, deadline: deadline)
            let role = meta[kAXRoleAttribute] ?? ""
            let text = meta[kAXTitleAttribute] ?? meta[kAXDescriptionAttribute] ?? ""
            if role == kAXWindowRole || role == kAXApplicationRole { break }
            evidence.ancestors.append(ContextText(text: text, role: role, depth: depth))
            if let children = axValue(parent, kAXChildrenAttribute) as? [AXUIElement] {
                for child in children.prefix(24) {
                    guard visited < 36, ProcessInfo.processInfo.systemUptime < deadline else { break }
                    visited += 1
                    if CFEqual(child, target) { continue }
                    AXUIElementSetMessagingTimeout(child, 0.025)
                    let childMeta = metadata(child, deadline: deadline)
                    if [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(childMeta[kAXRoleAttribute] ?? "") {
                        let rect = bounds(InputTarget.rect(child))
                        if !rect.isEmpty && evidence.nearbyInputs.count < 20 { evidence.nearbyInputs.append(rect) }
                    }
                    guard [kAXStaticTextRole, "AXHeading"].contains(childMeta[kAXRoleAttribute] ?? "") else { continue }
                    let label = String((childMeta[kAXTitleAttribute] ?? childMeta[kAXDescriptionAttribute] ?? axText(child, kAXValueAttribute)).prefix(160))
                    guard !label.isEmpty else { continue }
                    if let targets = axValue(child, kAXServesAsTitleForUIElementsAttribute) as? [AXUIElement],
                       targets.contains(where: { CFEqual($0, target) }) {
                        evidence.field.linkedLabels.append(label)
                    }
                    let observation = ContextText(text: label, role: childMeta[kAXRoleAttribute] ?? kAXStaticTextRole,
                        bounds: bounds(InputTarget.rect(child)), depth: depth)
                    evidence.nearby.append(observation)
                    if observation.role == "AXHeading", evidence.headings.count < 8 {
                        evidence.headings.append(observation)
                    }
                }
            }
            node = parent
            if role == kAXToolbarRole || role == "AXWebArea" { break }
        }
        evidence.budgetExhausted = ProcessInfo.processInfo.systemUptime >= deadline || visited >= 36
        return evidence
    }
    var needsOCR: Bool {
        if destinationKind == "window" { return true }
        if insertion == nil && ["AXTextArea", "AXWebArea"].contains(field.role) { return true }
        let generic: Set<String> = ["", "text", "text field", "text area", "input", "edit", "editor", "rich text editor", "search", "message", "message body", "message content", "email body", "mail body", "reply", "notes", "description", "comment", "write a message", "type here", "enter text", "content", "web content", "document", "body", "composer", "form", "group"]
        let labels = field.linkedLabels + ["title", "description", "placeholder"].compactMap { field.attributes[$0] }
        return !labels.contains { !generic.contains($0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) }
    }
    func encoded() throws -> String {
        var copy = self
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        while true {
            let data = try encoder.encode(copy)
            guard let text = String(data: data, encoding: .utf8) else { throw ClipboardError.message("Could not encode field context.") }
            if data.count <= 5800 { return text }
            if !copy.ocr.isEmpty { copy.ocr.removeLast() }
            else if !copy.nearby.isEmpty { copy.nearby.removeLast() }
            else if !copy.headings.isEmpty { copy.headings.removeLast() }
            else { throw ClipboardError.message("Field context exceeds the local limit.") }
        }
    }
}
