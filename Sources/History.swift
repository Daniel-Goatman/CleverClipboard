import Foundation

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
    var hint: String = ""
    var pinned: Bool = false
    var assetID: String? = nil
    var fileName: String? = nil
    var fileType: String? = nil
    var fileBytes: Int = 0
    private enum CodingKeys: String, CodingKey {
        case id, text, app, copiedAt, kind, imageType, imageBytes, ocrText, hint, pinned,
             assetID, fileName, fileType, fileBytes
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
        hint = try c.decodeIfPresent(String.self, forKey: .hint) ?? ""
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        assetID = try c.decodeIfPresent(String.self, forKey: .assetID)
        fileName = try c.decodeIfPresent(String.self, forKey: .fileName)
        fileType = try c.decodeIfPresent(String.self, forKey: .fileType)
        fileBytes = try c.decodeIfPresent(Int.self, forKey: .fileBytes) ?? 0
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
        case .image: return ocrText.isEmpty ? "Image with no readable text" : "Image OCR: " + ocrText
        case .file: return "File: \(fileName ?? "Unnamed file") · type: \(fileType ?? "unknown") · size: \(fileBytes) bytes"
        case .text: return text
        }
    }
    init(id: String, text: String, app: String, copiedAt: Date, kind: Kind = .text,
         imageType: String? = nil, imageBytes: Int = 0, ocrText: String = "", hint: String = "", pinned: Bool = false,
         assetID: String? = nil, fileName: String? = nil, fileType: String? = nil, fileBytes: Int = 0) {
        self.id = id; self.text = text; self.app = app; self.copiedAt = copiedAt; self.kind = kind
        self.imageType = imageType; self.imageBytes = imageBytes; self.ocrText = ocrText; self.hint = hint; self.pinned = pinned
        self.assetID = assetID; self.fileName = fileName; self.fileType = fileType; self.fileBytes = fileBytes
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
        let ordinary = history.items.filter { !textOnly || $0.kind == .text }
        return Array(ordinary.prefix(ordinaryLimit)) + active
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

    @discardableResult mutating func add(_ text: String, app: String) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.utf8.count <= Self.maximumTextBytes else { return false }
        items.removeAll { $0.kind == .text && !$0.pinned && $0.text == text }
        items.insert(Clip(id: UUID().uuidString, text: text, app: app, copiedAt: Date()), at: 0)
        trim(); return true
    }

    @discardableResult mutating func addImage(id: String, dataCount: Int, type: String, app: String) -> Bool {
        guard dataCount > 0 && dataCount <= Self.maximumItemBytes else { return false }
        items.insert(Clip(id: id, text: "", app: app, copiedAt: Date(), kind: .image,
                          imageType: type, imageBytes: dataCount), at: 0)
        trim(); return items.contains { $0.id == id }
    }

    mutating func updateOCR(id: String, text: String) {
        guard let index = items.firstIndex(where: { $0.id == id && $0.kind == .image }) else { return }
        items[index].ocrText = String(text.prefix(1200))
    }
    @discardableResult mutating func delete(id: String) -> Bool {
        let old = items.count; items.removeAll { $0.id == id }; return items.count != old
    }
    mutating func restore(_ clips: [Clip]) { items = clips; trim() }
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
