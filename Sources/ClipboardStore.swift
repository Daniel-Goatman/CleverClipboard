import Foundation
import UniformTypeIdentifiers
import Darwin

struct SavedLibrary: Codable {
    var version: Int = 3
    var items: [Clip]
    var pins: [PinnedEntry]
}

final class ClipboardStore {
    let root: URL
    private(set) var loadError: StoreError?
    private var images: URL { root.appendingPathComponent("Images", isDirectory: true) }
    private var savedAssets: URL { root.appendingPathComponent("SavedAssets", isDirectory: true) }
    private var historyFiles: URL { root.appendingPathComponent("HistoryFiles", isDirectory: true) }
    private var metadata: URL { root.appendingPathComponent("Library.json") }

    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Jev Clipboard", isDirectory: true)
    }
    private func prepare() throws {
        if let loadError { throw loadError }
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.createDirectory(at: historyFiles, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.createDirectory(at: savedAssets, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
    }
    private func imageURL(_ id: String) -> URL? {
        guard UUID(uuidString: id) != nil else { return nil }
        return images.appendingPathComponent(id + ".image")
    }
    func load() -> (History, [PinnedEntry]) {
        var history = History()
        let saved: SavedLibrary
        do {
            let data = try Data(contentsOf: metadata)
            saved = try JSONDecoder().decode(SavedLibrary.self, from: data)
            guard [1, 2, 3].contains(saved.version) else { throw StoreError.unreadableLibrary }
            loadError = nil
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            // A missing library is the only normal empty-library case.
            loadError = nil
            return (history, PinnedEntry.defaults)
        } catch {
            // Do not let the next clipboard poll overwrite metadata or prune
            // assets belonging to a library we could not read.
            loadError = .unreadableLibrary
            return (history, PinnedEntry.defaults)
        }
        history.restore(saved.items.filter { clip in
            if clip.kind == .text { return clip.bytes <= History.maximumTextBytes }
            if clip.kind == .file {
                guard !clip.pinned, clip.assetID == clip.id, clip.fileBytes > 0,
                      clip.fileBytes <= History.maximumItemBytes, let url = assetPath(clip),
                      let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]) else { return false }
                return values.isRegularFile == true && values.isSymbolicLink != true && values.fileSize == clip.fileBytes
            }
            guard let url = imageURL(clip.id), clip.bytes <= History.maximumItemBytes,
                  ["public.png", "public.tiff", "public.jpeg", "public.heic"].contains(clip.imageType ?? ""),
                  let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return false }
            return size == clip.imageBytes
        })
        var seen = Set<Int>()
        let pins = saved.pins.prefix(PinnedEntry.maximumCount).filter { entry in
            guard entry.id >= 0,
                  entry.value.utf8.count <= History.maximumTextBytes,
                  entry.description.utf8.count <= 1000,
                  validAsset(entry) else { return false }
            return seen.insert(entry.id).inserted
        }
        return (history, pins)
    }
    func writeImage(_ data: Data, id: String) throws {
        guard data.count <= History.maximumItemBytes, let url = imageURL(id) else { throw StoreError.invalidImage }
        try prepare(); try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    func readImage(id: String) -> Data? {
        guard let url = imageURL(id) else { return nil }
        return try? Data(contentsOf: url)
    }
    func imagePath(id: String) -> URL? { imageURL(id) }
    static let maximumSavedAssetBytes = 50 * 1024 * 1024
    static let maximumSavedTotalBytes = 512 * 1024 * 1024

    func assetPath(_ entry: PinnedEntry) -> URL? {
        guard let id = entry.assetID, UUID(uuidString: id) != nil,
              let name = entry.assetName, !name.isEmpty, name != ".", name != "..",
              (name as NSString).lastPathComponent == name else { return nil }
        return savedAssets.appendingPathComponent(id, isDirectory: true).appendingPathComponent(name)
    }
    func assetPath(_ clip: Clip) -> URL? {
        guard let id = clip.assetID, UUID(uuidString: id) != nil,
              let name = clip.fileName, !name.isEmpty, name != ".", name != "..",
              (name as NSString).lastPathComponent == name else { return nil }
        return (clip.pinned ? savedAssets : historyFiles).appendingPathComponent(id, isDirectory: true).appendingPathComponent(name)
    }
    private func validAsset(_ entry: PinnedEntry) -> Bool {
        if entry.kind == .text { return entry.assetID == nil }
        guard [.image, .file].contains(entry.kind), entry.value.isEmpty,
              entry.assetBytes > 0, entry.assetBytes <= Self.maximumSavedAssetBytes,
              let url = assetPath(entry), let type = entry.assetType, !type.isEmpty,
              let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size == entry.assetBytes else { return false }
        if entry.kind == .image {
            return ["public.png", "public.tiff", "public.jpeg", "public.heic"].contains(type)
        }
        return true
    }

    func importAsset(from source: URL, id: Int, kind: Clip.Kind, otherAssetBytes: Int = 0) throws -> PinnedEntry {
        guard kind == .image || kind == .file else { throw StoreError.invalidAsset }
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize,
              size > 0, size <= Self.maximumSavedAssetBytes,
              otherAssetBytes + size <= Self.maximumSavedTotalBytes else { throw StoreError.invalidAsset }
        let name = source.lastPathComponent
        guard !name.isEmpty, name != ".", name != "..", (name as NSString).lastPathComponent == name else {
            throw StoreError.invalidAsset
        }
        let ext = source.pathExtension.lowercased()
        let knownTypes = ["png": "public.png", "jpg": "public.jpeg", "jpeg": "public.jpeg",
                          "tif": "public.tiff", "tiff": "public.tiff", "heic": "public.heic",
                          "pdf": "com.adobe.pdf", "docx": "org.openxmlformats.wordprocessingml.document",
                          "doc": "com.microsoft.word.doc", "txt": "public.plain-text"]
        let discovered = UTType(filenameExtension: ext)?.identifier
        let type = knownTypes[ext] ?? ((discovered?.hasPrefix("dyn.") == false) ? discovered! : UTType.data.identifier)
        if kind == .image && !["public.png", "public.tiff", "public.jpeg", "public.heic"].contains(type) {
            throw StoreError.unsupportedImage
        }
        try prepare()
        let assetID = UUID().uuidString
        let directory = savedAssets.appendingPathComponent(assetID, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        let destination = directory.appendingPathComponent(name)
        do {
            try FileManager.default.copyItem(at: source, to: destination)
            let copiedSize = try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard copiedSize > 0 && copiedSize <= Self.maximumSavedAssetBytes else { throw StoreError.invalidAsset }
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            var entry = PinnedEntry(id: id, description: "", value: "")
            entry.kind = kind; entry.assetID = assetID; entry.assetName = name
            entry.assetType = type; entry.assetBytes = copiedSize
            if kind == .image, let data = try? Data(contentsOf: destination) {
                entry.ocrText = ImageOCR.recognize(data)
            }
            return entry
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    struct FileSnapshot {
        let name: String
        let type: String
        let data: Data
    }
    /// Off-main bounded read. Reject links, folders, devices and oversized/cloud placeholders.
    static func readFileSnapshot(from source: URL) throws -> FileSnapshot {
        guard source.isFileURL else { throw StoreError.invalidHistoryFile }
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let descriptor = open(source.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { throw StoreError.invalidHistoryFile }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var attributes = stat()
        guard fstat(descriptor, &attributes) == 0,
              (attributes.st_mode & S_IFMT) == S_IFREG,
              attributes.st_size > 0, attributes.st_size <= History.maximumItemBytes else { throw StoreError.invalidHistoryFile }
        var data = Data()
        while let chunk = try handle.read(upToCount: 256 * 1024), !chunk.isEmpty {
            guard data.count + chunk.count <= History.maximumItemBytes else { throw StoreError.invalidHistoryFile }
            data.append(chunk)
        }
        guard !data.isEmpty else { throw StoreError.invalidHistoryFile }
        let name = source.lastPathComponent
        guard !name.isEmpty, name != ".", name != "..", (name as NSString).lastPathComponent == name else { throw StoreError.invalidHistoryFile }
        let type = UTType(filenameExtension: source.pathExtension)?.identifier ?? UTType.data.identifier
        return FileSnapshot(name: name, type: type, data: data)
    }
    /// Commit on the app's serial/main owner; no pruning races with an in-flight read.
    func writeHistoryFile(_ snapshot: FileSnapshot, app: String, at: Date = Date(), provenance: ClipProvenance? = nil) throws -> Clip {
        guard snapshot.data.count > 0, snapshot.data.count <= History.maximumItemBytes,
              !snapshot.name.isEmpty, snapshot.name != ".", snapshot.name != "..",
              (snapshot.name as NSString).lastPathComponent == snapshot.name else { throw StoreError.invalidHistoryFile }
        try prepare()
        let id = UUID().uuidString
        let directory = historyFiles.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            let url = directory.appendingPathComponent(snapshot.name)
            try snapshot.data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return Clip(id: id, text: "", app: app, copiedAt: at, kind: .file, assetID: id,
                        fileName: snapshot.name, fileType: snapshot.type, fileBytes: snapshot.data.count, provenance: provenance)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    func removeUnusedAssets(keeping entries: [PinnedEntry], protectedAssetID: String? = nil) {
        guard loadError == nil else { return }
        var keep = Set(entries.compactMap(\.assetID))
        if let protectedAssetID { keep.insert(protectedAssetID) }
        for url in (try? FileManager.default.contentsOfDirectory(at: savedAssets, includingPropertiesForKeys: nil)) ?? []
        where UUID(uuidString: url.lastPathComponent) != nil && !keep.contains(url.lastPathComponent) {
            try? FileManager.default.removeItem(at: url)
        }
    }
    func save(history: History, pins: [PinnedEntry], protectedHistoryAssetID: String? = nil) throws {
        try prepare()
        guard pins.count <= PinnedEntry.maximumCount,
              Set(pins.map(\.id)).count == pins.count,
              pins.allSatisfy({ $0.id >= 0 && $0.value.utf8.count <= History.maximumTextBytes &&
                  $0.description.utf8.count <= 1000 && validAsset($0) }),
              pins.reduce(0, { $0 + $1.assetBytes }) <= Self.maximumSavedTotalBytes else {
            throw StoreError.invalidPins
        }
        let data = try JSONEncoder().encode(SavedLibrary(items: history.items, pins: pins))
        try data.write(to: metadata, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: metadata.path)
        var retainedFiles = Set(history.items.filter { $0.kind == .file }.compactMap(\.assetID))
        if let protectedHistoryAssetID { retainedFiles.insert(protectedHistoryAssetID) }
        for directory in (try? FileManager.default.contentsOfDirectory(at: historyFiles, includingPropertiesForKeys: nil)) ?? []
        where UUID(uuidString: directory.lastPathComponent) != nil && !retainedFiles.contains(directory.lastPathComponent) {
            try? FileManager.default.removeItem(at: directory)
        }
        let retained = Set(history.items.filter { $0.kind == .image }.map { $0.id + ".image" })
        for file in (try? FileManager.default.contentsOfDirectory(at: images, includingPropertiesForKeys: nil)) ?? []
        where file.pathExtension == "image" && !retained.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }
    enum StoreError: LocalizedError {
        case invalidImage, invalidPins, invalidAsset, unsupportedImage, unreadableLibrary, invalidHistoryFile
        var errorDescription: String? {
            switch self {
            case .invalidHistoryFile: return "History captures regular files up to 20 MB; folders, links and unavailable files are skipped."
            case .invalidImage: return "Image exceeds clipboard storage limit."
            case .invalidPins: return "Saved entries are invalid or exceed the storage limit."
            case .invalidAsset: return "Choose one regular file under 50 MB."
            case .unsupportedImage: return "Use a PNG, JPEG, TIFF or HEIC image."
            case .unreadableLibrary: return "Clipboard library could not be read. Existing files are preserved and saving is disabled. Restore Library.json from a backup, then restart CleverClipboard."
            }
        }
    }
}
