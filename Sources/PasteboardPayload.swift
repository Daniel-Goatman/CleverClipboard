import AppKit

/// Resolve stored content before clearing the live pasteboard. A file entry
/// writes a file URL, while an image entry writes image bytes.
struct PasteboardPayload {
    enum Content {
        case text(String)
        case image(Data, NSPasteboard.PasteboardType)
        case file(URL)
    }
    let content: Content
    init(content: Content) { self.content = content }

    /// Strip rich-text/HTML source styling for a latest-item fallback, while
    /// leaving copied files and images in their original pasteable formats.
    static func plainTextForLatest(_ pasteboard: NSPasteboard) -> String? {
        let types = Set(pasteboard.types ?? [])
        let nonText: Set<NSPasteboard.PasteboardType> = [
            .fileURL, .png, .tiff, NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("public.heic"),
            NSPasteboard.PasteboardType("NSFilenamesPboardType")
        ]
        guard types.isDisjoint(with: nonText) else { return nil }
        return pasteboard.string(forType: .string)
    }

    init?(clip: Clip, store: ClipboardStore) {
        switch clip.kind {
        case .text:
            content = .text(clip.text)
        case .image:
            guard let type = clip.imageType else { return nil }
            let data = clip.pinned ? store.assetPath(clip).flatMap { try? Data(contentsOf: $0) }
                                   : store.readImage(id: clip.id)
            guard let data else { return nil }
            content = .image(data, NSPasteboard.PasteboardType(type))
        case .file:
            guard let url = store.assetPath(clip), FileManager.default.fileExists(atPath: url.path) else { return nil }
            content = .file(url)
        }
    }

    @discardableResult func write(to pasteboard: NSPasteboard) -> Bool {
        pasteboard.clearContents()
        switch content {
        case .text(let text): return pasteboard.setString(text, forType: .string)
        case .image(let data, let type): return pasteboard.setData(data, forType: type)
        case .file(let url): return pasteboard.writeObjects([url as NSURL])
        }
    }
}
