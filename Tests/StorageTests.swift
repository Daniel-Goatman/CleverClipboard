import Foundation

@main struct StorageTests {
    static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("jev-store-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ClipboardStore(root: folder)
        var (history, pins) = store.load()
        precondition(history.items.isEmpty && pins.isEmpty)
        let legacy = #"{"version":1,"items":[],"pins":[{"id":0,"name":"Email","value":"me@example.org","hint":"my email address"},{"id":1,"name":"Mobile","value":"+61 400 000 000","hint":""}]}"#
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(legacy.utf8).write(to: folder.appendingPathComponent("Library.json"))
        (history, pins) = store.load()
        precondition(pins.count == 2 && pins[0].description == "my email address")
        precondition(pins[1].description == "Mobile" && pins[1].value == "+61 400 000 000")
        pins.append(PinnedEntry(id: 2, description: "work URL", value: "https://example.org"))
        history.add("A sentence", app: "Notes")
        let id = UUID().uuidString, bytes = Data(repeating: 7, count: 300)
        try store.writeImage(bytes, id: id)
        precondition(history.addImage(id: id, dataCount: bytes.count, type: "public.png", app: "Screenshot"))
        history.updateOCR(id: id, text: "Invoice #104")
        try store.save(history: history, pins: pins)
        var (restored, savedPins) = store.load()
        precondition(restored.items.count == 2 && restored.items.first?.ocrText == "Invoice #104")
        precondition(savedPins == pins && store.readImage(id: id) == bytes)
        let saved = try Data(contentsOf: folder.appendingPathComponent("Library.json"))
        let savedVersion = try JSONDecoder().decode(SavedLibrary.self, from: saved).version
        precondition(savedVersion == 3)
        precondition(!String(decoding: saved, as: UTF8.self).contains("\"name\""))
        precondition(CandidateText.forClip(restored.items[0], candidateCount: 52).contains("Invoice #104"))
        restored.clear()
        try store.save(history: restored, pins: savedPins)
        precondition(store.readImage(id: id) == nil)
        let (cleared, retainedPins) = store.load()
        precondition(cleared.items.isEmpty && retainedPins == pins)
        savedPins[0].value = String(repeating: "x", count: History.maximumTextBytes + 1)
        do { try store.save(history: restored, pins: savedPins); fatalError("Oversized pin saved") }
        catch ClipboardStore.StoreError.invalidPins { }
        savedPins = pins
        savedPins.remove(at: 1)
        for id in 3..<PinnedEntry.maximumCount + 1 {
            savedPins.append(PinnedEntry(id: id, description: "item \(id)", value: "value \(id)"))
        }
        precondition(savedPins.count == PinnedEntry.maximumCount)
        try store.save(history: restored, pins: savedPins)
        precondition(store.load().1 == savedPins)
        let resume = folder.appendingPathComponent("Resume.pdf")
        try Data("%PDF-1.4\nexample".utf8).write(to: resume)
        var fileEntry = try store.importAsset(from: resume, id: 100, kind: .file)
        fileEntry.description = "My resume for job applications"
        let storedResume = store.assetPath(fileEntry)!
        precondition(storedResume.path != resume.path && FileManager.default.fileExists(atPath: storedResume.path))
        try FileManager.default.removeItem(at: resume)
        precondition(FileManager.default.fileExists(atPath: storedResume.path))
        let png = folder.appendingPathComponent("Picture.png")
        let pngData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl6fQAAAABJRU5ErkJggg==")!
        try pngData.write(to: png)
        var imageEntry = try store.importAsset(from: png, id: 101, kind: .image)
        imageEntry.description = "My profile picture"
        precondition(imageEntry.assetType == "public.png" && store.assetPath(imageEntry) != nil)
        let assetPins = [fileEntry, imageEntry]
        try store.save(history: restored, pins: assetPins)
        let (_, restoredAssets) = store.load()
        precondition(restoredAssets == assetPins)
        precondition(restoredAssets[0].clip?.kind == .file && restoredAssets[0].clip?.candidateText.contains("Resume.pdf") == true)
        precondition(restoredAssets[1].clip?.kind == .image)
        let allKinds = ClipboardSelection.candidates(history: restored, pins: assetPins, destinationRole: "AXWindow")
        precondition(allKinds.contains { $0.kind == .file } && allKinds.contains { $0.kind == .image })
        let textOnly = ClipboardSelection.candidates(history: restored, pins: assetPins, destinationRole: "AXTextField")
        precondition(textOnly.allSatisfy { $0.kind == .text })
        let richComposer = ClipboardSelection.candidates(history: restored, pins: assetPins, destinationRole: "AXTextArea")
        precondition(richComposer.contains { $0.kind == .file })
        do {
            _ = try store.importAsset(from: png, id: 102, kind: .image,
                                      otherAssetBytes: ClipboardStore.maximumSavedTotalBytes)
            fatalError("Exceeded saved asset limit")
        } catch ClipboardStore.StoreError.invalidAsset { }
        try store.save(history: restored, pins: [imageEntry])
        store.removeUnusedAssets(keeping: [imageEntry])
        precondition(!FileManager.default.fileExists(atPath: storedResume.path))
        savedPins.append(PinnedEntry(id: 99, description: "extra", value: "too many"))
        do { try store.save(history: restored, pins: savedPins); fatalError("Too many pins saved") }
        catch ClipboardStore.StoreError.invalidPins { }
        var fullHistory = History()
        for n in 0..<50 { fullHistory.add("history \(n)", app: "Fixture") }
        let candidates = ClipboardSelection.candidates(history: fullHistory, pins: Array(savedPins.prefix(PinnedEntry.maximumCount)))
        precondition(candidates.count == ClipboardSelection.maximumCandidates)
        precondition(candidates.filter(\.pinned).count == PinnedEntry.maximumCount)
        precondition(candidates.filter { !$0.pinned }.count == 32)
        print("PASS: v1/v2 migration, v3 assets, OCR, file snapshot, limits, candidate filtering and cleanup")
    }
}
