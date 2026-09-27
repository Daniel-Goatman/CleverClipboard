import Foundation

@main struct CarbonFileTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("carbon-files-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Project brief.pdf")
        let original = Data("%PDF-1.4\nSynthetic file snapshot".utf8)
        try original.write(to: source)
        let snapshot = try ClipboardStore.readFileSnapshot(from: source)
        let store = ClipboardStore(root: root.appendingPathComponent("Store"))
        _ = store.load()
        let clip = try store.writeHistoryFile(snapshot, app: "Fixture")
        var history = History(); precondition(history.addFile(clip))
        let pin = try store.importAsset(from: source, id: 0, kind: .file)
        try store.save(history: history, pins: [pin])
        let captured = store.assetPath(clip)!, pinned = store.assetPath(pin)!
        precondition(captured.path != pinned.path && captured.path != source.path)
        try Data("changed".utf8).write(to: source)
        let capturedBytes = try Data(contentsOf: captured)
        precondition(capturedBytes == original, "Capture must be an independent snapshot")
        try FileManager.default.removeItem(at: source)
        let reloaded = store.load()
        precondition(reloaded.0.items == [clip] && reloaded.1 == [pin])
        guard let payload = PasteboardPayload(clip: clip, store: store), case .file(let pasteURL) = payload.content else { fatalError("Expected file paste payload") }
        precondition(pasteURL == captured, "Paste resolves history storage, not SavedAssets")
        let permissions = try FileManager.default.attributesOfItem(atPath: captured.path)[.posixPermissions] as! NSNumber
        precondition(permissions.intValue == 0o600)
        history.clear()
        try store.save(history: history, pins: [pin], protectedHistoryAssetID: clip.assetID)
        precondition(FileManager.default.fileExists(atPath: captured.path), "Current pasteboard file remains pasteable after Clear History")
        precondition(FileManager.default.fileExists(atPath: pinned.path), "Clear History must not touch Always Available")
        try store.save(history: history, pins: [pin])
        precondition(!FileManager.default.fileExists(atPath: captured.path), "Released history files are pruned")
        precondition(FileManager.default.fileExists(atPath: pinned.path))
        let missing = try store.writeHistoryFile(snapshot, app: "Fixture")
        precondition(history.addFile(missing)); try store.save(history: history, pins: [pin])
        try FileManager.default.removeItem(at: store.assetPath(missing)!)
        precondition(store.load().0.items.isEmpty, "Missing snapshot cannot reappear as pasteable history")
        let empty = root.appendingPathComponent("empty"); try Data().write(to: empty)
        let symlink = root.appendingPathComponent("link.pdf")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: pinned)
        let oversized = root.appendingPathComponent("large.bin")
        FileManager.default.createFile(atPath: oversized.path, contents: nil)
        let handle = try FileHandle(forWritingTo: oversized)
        try handle.truncate(atOffset: UInt64(History.maximumItemBytes + 1)); try handle.close()
        for url in [root, empty, symlink, oversized, URL(string: "https://example.com/file.pdf")!] {
            do { _ = try ClipboardStore.readFileSnapshot(from: url); fatalError("Unsupported file accepted: \(url.lastPathComponent)") }
            catch ClipboardStore.StoreError.invalidHistoryFile { }
        }
        var bounded = History()
        for _ in 0..<8 {
            let id = UUID().uuidString
            precondition(bounded.addFile(Clip(id: id, text: "", app: "Fixture", copiedAt: Date(), kind: .file,
                                             assetID: id, fileName: "large.pdf", fileType: "com.adobe.pdf", fileBytes: History.maximumItemBytes)))
        }
        precondition(bounded.items.count == 6 && bounded.bytes <= History.maximumBytes)
        let candidates = ClipboardSelection.candidates(history: bounded, pins: [], destinationRole: "AXTextField")
        precondition(candidates.isEmpty, "File histories stay excluded from plain text destinations")
        let metadata = root.appendingPathComponent("Store/Library.json")
        try Data("broken library".utf8).write(to: metadata); _ = store.load()
        do { _ = try store.writeHistoryFile(snapshot, app: "Fixture"); fatalError("Wrote into unreadable library") }
        catch ClipboardStore.StoreError.unreadableLibrary { }
        precondition(FileManager.default.fileExists(atPath: pinned.path))
        print("PASS Carbon files: bounded regular-file capture, snapshot/reload/paste path, permissions, protected paste, cleanup isolation, missing files, byte eviction, text-only filtering and damaged-store guard")
    }
}
