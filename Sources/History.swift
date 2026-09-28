import Foundation

/// A global key event has no authenticated target application. Reject a source
/// inference if focus changed between the last foreground sample and callback.
struct CopyForegroundGate {
    private(set) var lastPollPID: Int32?
    private(set) var lastActivationUptime: TimeInterval?

    mutating func observePoll(pid: Int32?) { lastPollPID = pid }
    mutating func activated(at uptime: TimeInterval) { lastActivationUptime = uptime }

    func allows(eventAt: TimeInterval, callbackAt: TimeInterval, pid: Int32) -> Bool {
        guard lastPollPID == pid, eventAt <= callbackAt else { return false }
        if let activation = lastActivationUptime,
           activation >= eventAt && activation <= callbackAt { return false }
        return true
    }
}

/// A copy event is evidence of intent, not an authenticated pasteboard writer.
struct CopyObservation {
    let app: String
    let bundleID: String
    let at: Date
    let pasteboardChange: Int
    let windowTitle: String?
    let fieldLabel: String?
    let fieldIdentifier: String?
    let selectedText: String?
}

struct ClipProvenance: Codable, Equatable {
    let sourceApp: String?
    let sourceBundleID: String?
    let writer: String?
    let foregroundAtPoll: String?
    let association: String // keyboard_copy, own_write, or unknown
    let windowTitle: String?
    let fieldLabel: String?
    let fieldIdentifier: String?
    let declaredSource: String? // Pasteboard-supplied and unauthenticated.

    var establishedLocation: String? {
        guard association == "keyboard_copy", let sourceBundleID,
              let windowTitle, !windowTitle.isEmpty, let fieldLabel, !fieldLabel.isEmpty,
              let fieldIdentifier, !fieldIdentifier.isEmpty else { return nil }
        return sourceBundleID + "\u{1f}" + windowTitle + "\u{1f}" + fieldLabel + "\u{1f}" + fieldIdentifier
    }
    var requestContext: String {
        guard association == "keyboard_copy", let sourceApp else { return "Source unknown" }
        var parts = ["Copy event in " + sourceApp]
        if let fieldLabel { parts.append("Selected field: " + fieldLabel) }
        if let windowTitle { parts.append("Window: " + windowTitle) }
        return parts.joined(separator: " · ")
    }
    static func ownWrite(original: ClipProvenance?) -> ClipProvenance {
        ClipProvenance(sourceApp: original?.sourceApp, sourceBundleID: original?.sourceBundleID,
                       writer: "CleverClipboard", foregroundAtPoll: original?.foregroundAtPoll,
                       association: "own_write", windowTitle: nil, fieldLabel: nil,
                       fieldIdentifier: nil,
                       declaredSource: nil)
    }
    static func resolve(observation: CopyObservation?, changedAt: Date, changeCount: Int,
                        foreground: String?, declaredSource: String?, payload: String?) -> ClipProvenance {
        let declaration = declaredSource.map { String($0.prefix(100)) }
        guard let observation,
              // Global key monitors are asynchronous: the write may precede this callback.
              changeCount >= observation.pasteboardChange,
              changedAt.timeIntervalSince(observation.at) >= 0,
              changedAt.timeIntervalSince(observation.at) <= 0.8,
              declaration == nil || declaration == observation.bundleID else {
            return ClipProvenance(sourceApp: nil, sourceBundleID: nil, writer: nil,
                                  foregroundAtPoll: foreground.map { String($0.prefix(100)) },
                                  association: "unknown", windowTitle: nil, fieldLabel: nil,
                                  fieldIdentifier: nil,
                                  declaredSource: declaration)
        }
        let matches = payload != nil && observation.selectedText != nil &&
            payload!.replacingOccurrences(of: "\r\n", with: "\n") ==
            observation.selectedText!.replacingOccurrences(of: "\r\n", with: "\n")
        return ClipProvenance(sourceApp: String(observation.app.prefix(100)),
                              sourceBundleID: String(observation.bundleID.prefix(100)), writer: nil,
                              foregroundAtPoll: foreground.map { String($0.prefix(100)) },
                              association: "keyboard_copy",
                              windowTitle: matches ? observation.windowTitle.map { String($0.prefix(100)) } : nil,
                              fieldLabel: matches ? observation.fieldLabel.map { String($0.prefix(100)) } : nil,
                              fieldIdentifier: matches ? observation.fieldIdentifier.map { String($0.prefix(100)) } : nil,
                              declaredSource: declaration)
    }
}

struct OCRBlock: Codable, Equatable {
    let text: String
    let confidence: Double
    // Vision's normalized image coordinates: origin at the lower left.
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

enum OCRStatus: String, Codable { case unknown, pending, ready, noText, failed }

struct OCRResult: Equatable {
    let status: OCRStatus
    let blocks: [OCRBlock]
    let truncated: Bool
    var plainText: String { blocks.map(\.text).joined(separator: " · ") }
}

struct Clip: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case text, image, file }
    let id: String
    let text: String
    let app: String
    let copiedAt: Date
    var kind: Kind = .text
    var imageType: String? = nil
    var imageBytes: Int = 0
    var ocrText: String = ""
    var ocrStatus: OCRStatus = .unknown
    var ocrBlocks: [OCRBlock] = []
    var ocrTruncated: Bool = false
    var imageRevision: String? = nil
    var hint: String = ""
    var pinned: Bool = false
    var assetID: String? = nil
    var fileName: String? = nil
    var fileType: String? = nil
    var fileBytes: Int = 0
    var provenance: ClipProvenance? = nil
    // Request-only summary; history persists each occurrence's provenance instead.
    var candidateSourceContext: String? = nil
    private enum CodingKeys: String, CodingKey {
        case id, text, app, copiedAt, kind, imageType, imageBytes, ocrText, ocrStatus,
             ocrBlocks, ocrTruncated, imageRevision, hint, pinned,
             assetID, fileName, fileType, fileBytes, provenance
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        text = try c.decode(String.self, forKey: .text)
        app = try c.decode(String.self, forKey: .app)
        copiedAt = try c.decode(Date.self, forKey: .copiedAt)
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .text
        imageType = try c.decodeIfPresent(String.self, forKey: .imageType)
        imageBytes = try c.decodeIfPresent(Int.self, forKey: .imageBytes) ?? 0
        ocrText = try c.decodeIfPresent(String.self, forKey: .ocrText) ?? ""
        ocrStatus = try c.decodeIfPresent(OCRStatus.self, forKey: .ocrStatus) ?? .unknown
        ocrBlocks = try c.decodeIfPresent([OCRBlock].self, forKey: .ocrBlocks) ?? []
        ocrTruncated = try c.decodeIfPresent(Bool.self, forKey: .ocrTruncated) ?? false
        imageRevision = try c.decodeIfPresent(String.self, forKey: .imageRevision)
        hint = try c.decodeIfPresent(String.self, forKey: .hint) ?? ""
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        assetID = try c.decodeIfPresent(String.self, forKey: .assetID)
        fileName = try c.decodeIfPresent(String.self, forKey: .fileName)
        fileType = try c.decodeIfPresent(String.self, forKey: .fileType)
        fileBytes = try c.decodeIfPresent(Int.self, forKey: .fileBytes) ?? 0
        provenance = try c.decodeIfPresent(ClipProvenance.self, forKey: .provenance)
    }
    var bytes: Int { kind == .image ? imageBytes : kind == .file ? fileBytes : text.utf8.count }
    var preview: String {
        switch kind {
        case .image: return ocrText.isEmpty ? "Image" : "Image · " + String(ocrText.replacingOccurrences(of: "\n", with: " ").prefix(80))
        case .file: return fileName ?? "File"
        case .text: return String(text.replacingOccurrences(of: "\n", with: " ↵ ").prefix(100))
        }
    }
    var candidateText: String {
        switch kind {
        case .image:
            switch ocrStatus {
            case .pending: return "Image OCR pending"
            case .failed: return "Image OCR failed"
            case .noText: return "Image OCR found no text"
            case .unknown, .ready:
                let prefix = ocrStatus == .unknown ? "Image OCR (legacy, confidence unknown): " : "Image OCR (uncertain): "
                if !ocrBlocks.isEmpty {
                    return prefix + ocrBlocks.map { block in
                        String(format: "[x %.2f y %.2f confidence %.2f] %@", block.x, block.y, block.confidence, block.text)
                    }.joined(separator: " · ") + (ocrTruncated ? " [truncated]" : "")
                }
                return ocrText.isEmpty ? "Image OCR status unknown" : prefix + ocrText
            }
        case .file: return "File: \(fileName ?? "Unnamed file") · type: \(fileType ?? "unknown") · size: \(fileBytes) bytes"
        case .text: return text
        }
    }
    init(id: String, text: String, app: String, copiedAt: Date, kind: Kind = .text,
         imageType: String? = nil, imageBytes: Int = 0, ocrText: String = "", hint: String = "", pinned: Bool = false,
         assetID: String? = nil, fileName: String? = nil, fileType: String? = nil, fileBytes: Int = 0,
         provenance: ClipProvenance? = nil) {
        self.id = id; self.text = text; self.app = app; self.copiedAt = copiedAt; self.kind = kind
        self.imageType = imageType; self.imageBytes = imageBytes; self.ocrText = ocrText; self.hint = hint; self.pinned = pinned
        self.assetID = assetID; self.fileName = fileName; self.fileType = fileType; self.fileBytes = fileBytes
        self.provenance = provenance
    }
}

struct PinnedEntry: Codable, Equatable, Identifiable {
    let id: Int
    var description: String
    var value: String
    var kind: Clip.Kind = .text
    var assetID: String? = nil
    var assetName: String? = nil
    var assetType: String? = nil
    var assetBytes: Int = 0
    var ocrText: String = ""
    static let maximumCount = 20
    static let defaults: [PinnedEntry] = []

    // Version 1 stored a separate title and purpose hint. The purpose hint is
    // the new description; retain the title only when no hint was provided.
    private enum CodingKeys: String, CodingKey {
        case id, description, value, name, hint, kind, assetID, assetName, assetType, assetBytes, ocrText
    }
    init(id: Int, description: String, value: String) {
        self.id = id; self.description = description; self.value = value
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        value = try container.decode(String.self, forKey: .value)
        kind = try container.decodeIfPresent(Clip.Kind.self, forKey: .kind) ?? .text
        assetID = try container.decodeIfPresent(String.self, forKey: .assetID)
        assetName = try container.decodeIfPresent(String.self, forKey: .assetName)
        assetType = try container.decodeIfPresent(String.self, forKey: .assetType)
        assetBytes = try container.decodeIfPresent(Int.self, forKey: .assetBytes) ?? 0
        ocrText = try container.decodeIfPresent(String.self, forKey: .ocrText) ?? ""
        if let current = try container.decodeIfPresent(String.self, forKey: .description) {
            description = current
        } else {
            let hint = try container.decodeIfPresent(String.self, forKey: .hint) ?? ""
            let name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
            description = hint.isEmpty ? name : hint
        }
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(description, forKey: .description)
        try container.encode(value, forKey: .value)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(assetID, forKey: .assetID)
        try container.encodeIfPresent(assetName, forKey: .assetName)
        try container.encodeIfPresent(assetType, forKey: .assetType)
        try container.encode(assetBytes, forKey: .assetBytes)
        if !ocrText.isEmpty { try container.encode(ocrText, forKey: .ocrText) }
    }
    var clip: Clip? {
        if kind == .text {
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return Clip(id: "pin-\(id)", text: value, app: "Persistent entry", copiedAt: .distantPast,
                        hint: description, pinned: true)
        }
        guard let assetID, let assetName, assetBytes > 0 else { return nil }
        return Clip(id: "pin-\(id)", text: "", app: "Persistent entry", copiedAt: .distantPast,
                    kind: kind, imageType: kind == .image ? assetType : nil,
                    imageBytes: kind == .image ? assetBytes : 0, ocrText: ocrText,
                    hint: description, pinned: true, assetID: assetID,
                    fileName: assetName, fileType: assetType, fileBytes: kind == .file ? assetBytes : 0)
    }
}

enum ClipboardSelection {
    static let maximumCandidates = 52
    static func candidates(history: History, pins: [PinnedEntry], destinationRole: String = "") -> [Clip] {
        // AXTextArea can be a rich composer; an ordinary AXTextField/ComboBox
        // is reliably text-only. Unknown/window destinations keep every kind.
        let textOnly = ["AXTextField", "AXComboBox"].contains(destinationRole)
        let active = pins.compactMap(\.clip).filter { !textOnly || $0.kind == .text }
        let ordinaryLimit = max(0, maximumCandidates - active.count)
        var seenText = Set<String>()
        let ordinary = history.items.filter { clip in
            guard !textOnly || clip.kind == .text else { return false }
            return clip.kind != .text || seenText.insert(clip.text).inserted
        }
        let grouped = ordinary.prefix(ordinaryLimit).map { original -> Clip in
            guard original.kind == .text else { return original }
            var clip = original
            let contexts = history.items.filter { $0.kind == .text && $0.text == clip.text }
                .compactMap { $0.provenance?.requestContext }
            var distinct: [String] = []
            for context in contexts where context != "Source unknown" && !distinct.contains(context) {
                distinct.append(context)
                if distinct.count == 3 { break }
            }
            if contexts.contains("Source unknown") {
                distinct.append(distinct.isEmpty ? "Source unknown" : "Other occurrences: source unknown")
            }
            if !distinct.isEmpty { clip.candidateSourceContext = distinct.joined(separator: " | ") }
            return clip
        }
        return grouped + active
    }
}

struct History {
    static let maximumCount = 50
    static let maximumBytes = 128 * 1024 * 1024
    static let maximumTextBytes = 256 * 1024
    static let maximumItemBytes = 20 * 1024 * 1024
    private(set) var items: [Clip] = []
    var bytes: Int { items.reduce(0) { $0 + $1.bytes } }

    static func shouldIgnore(types: [String]) -> Bool {
        let markers = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType",
                       "org.nspasteboard.AutoGeneratedType", "com.agilebits.onepassword"]
        return types.contains { type in markers.contains { type.hasPrefix($0) } }
    }

    @discardableResult mutating func add(_ text: String, app: String,
                                        provenance: ClipProvenance? = nil, at: Date = Date()) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.utf8.count <= Self.maximumTextBytes else { return false }
        var occurrenceID = UUID().uuidString
        if let location = provenance?.establishedLocation,
           let index = items.firstIndex(where: { $0.kind == .text && !$0.pinned && $0.text == text &&
               $0.provenance?.establishedLocation == location }) {
            occurrenceID = items[index].id
            items.remove(at: index)
        }
        items.insert(Clip(id: occurrenceID, text: text, app: app, copiedAt: at,
                          provenance: provenance), at: 0)
        trim(); return true
    }

    @discardableResult mutating func addImage(id: String, dataCount: Int, type: String, app: String,
                                             provenance: ClipProvenance? = nil) -> Bool {
        guard dataCount > 0 && dataCount <= Self.maximumItemBytes else { return false }
        var clip = Clip(id: id, text: "", app: app, copiedAt: Date(), kind: .image,
                        imageType: type, imageBytes: dataCount, provenance: provenance)
        clip.ocrStatus = .pending
        clip.imageRevision = UUID().uuidString
        items.insert(clip, at: 0)
        trim(); return items.contains { $0.id == id }
    }

    @discardableResult mutating func addFile(_ clip: Clip) -> Bool {
        guard clip.kind == .file, !clip.pinned, clip.fileBytes > 0,
              clip.fileBytes <= Self.maximumItemBytes, UUID(uuidString: clip.id) != nil,
              clip.assetID == clip.id else { return false }
        items.insert(clip, at: 0)
        trim(); return items.contains { $0.id == clip.id }
    }

    mutating func updateOCR(id: String, text: String) {
        guard let index = items.firstIndex(where: { $0.id == id && $0.kind == .image }) else { return }
        items[index].ocrText = String(text.prefix(1200))
        items[index].ocrStatus = text.isEmpty ? .noText : .ready
    }
    @discardableResult mutating func updateOCR(id: String, imageRevision: String, result: OCRResult) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id && $0.kind == .image &&
            $0.imageRevision == imageRevision && $0.ocrStatus == .pending }) else { return false }
        items[index].ocrStatus = result.status
        items[index].ocrBlocks = result.blocks
        items[index].ocrText = result.plainText
        items[index].ocrTruncated = result.truncated
        return true
    }
    @discardableResult mutating func delete(id: String) -> Bool {
        let old = items.count; items.removeAll { $0.id == id }; return items.count != old
    }
    mutating func restore(_ clips: [Clip]) {
        items = clips.map { original in
            var clip = original
            // An OCR job from a previous process cannot complete after restart.
            if clip.ocrStatus == .pending { clip.ocrStatus = .failed }
            return clip
        }
        trim()
    }
    mutating func removeCredential(_ key: String) {
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        items.removeAll { $0.kind == .text && $0.text.trimmingCharacters(in: .whitespacesAndNewlines) == value }
    }
    mutating func clear() { items.removeAll(keepingCapacity: false) }
    private mutating func trim() {
        while items.count > Self.maximumCount || bytes > Self.maximumBytes { items.removeLast() }
    }
}

struct PasteLease {
    let clipboardVersion: Int
    let createdAt: Date
    func valid(clipboardVersion current: Int, now: Date = Date()) -> Bool {
        current == clipboardVersion && now.timeIntervalSince(createdAt) < 30
    }
}
