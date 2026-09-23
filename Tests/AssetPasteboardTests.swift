import AppKit

@main struct AssetPasteboardTests {
    static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("jev-paste-assets-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = ClipboardStore(root: folder.appendingPathComponent("Store"))
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }

        let resume = folder.appendingPathComponent("Resume.pdf")
        try Data("%PDF-1.4\nexample".utf8).write(to: resume)
        var file = try store.importAsset(from: resume, id: 1, kind: .file)
        file.description = "My resume"
        let filePayload = PasteboardPayload(clip: file.clip!, store: store)!
        precondition(filePayload.write(to: board))
        let urls = board.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []
        precondition(urls.count == 1 && urls[0] == store.assetPath(file))
        precondition(FileManager.default.fileExists(atPath: urls[0].path))

        let image = folder.appendingPathComponent("Picture.png")
        let bytes = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl6fQAAAABJRU5ErkJggg==")!
        try bytes.write(to: image)
        let imageEntry = try store.importAsset(from: image, id: 2, kind: .image)
        let imagePayload = PasteboardPayload(clip: imageEntry.clip!, store: store)!
        precondition(imagePayload.write(to: board))
        precondition(board.data(forType: .png) == bytes)
        precondition(PasteboardPayload.plainTextForLatest(board) == nil)

        // Rich source text must become a plain string before the destination
        // receives ⌘V; copied assets keep their original pasteboard formats.
        board.clearContents()
        precondition(board.setString("Call me here", forType: .string))
        precondition(board.setData(Data("{\\rtf1\\ansi Styled}".utf8), forType: .rtf))
        let plain = PasteboardPayload.plainTextForLatest(board)
        precondition(plain == "Call me here")
        precondition(PasteboardPayload(content: .text(plain!)).write(to: board))
        precondition(board.string(forType: .string) == "Call me here")
        precondition(board.data(forType: .rtf) == nil)

        precondition(filePayload.write(to: board))
        precondition(PasteboardPayload.plainTextForLatest(board) == nil)

        try FileManager.default.removeItem(at: store.assetPath(file)!)
        precondition(PasteboardPayload(clip: file.clip!, store: store) == nil)
        precondition((board.readObjects(forClasses: [NSURL.self], options: nil) as? [URL])?.count == 1)
        print("PASS: file URL, image bytes, plain-text fallback and unavailable-asset preflight")
    }
}
