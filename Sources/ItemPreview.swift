import AppKit
import SwiftUI
import PDFKit
import UniformTypeIdentifiers

/// Presentation only: never infers semantic categories from prose and never fetches URLs.
enum ItemPresentation {
    static func link(in text: String) -> URL? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count <= 8192, !value.contains(where: { $0.isWhitespace }),
              let components = URLComponents(string: value),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil else { return nil }
        return components.url
    }
    static func isImage(name: String?, type: String?) -> Bool {
        if let type, let value = UTType(type), value.conforms(to: .image) { return true }
        return name.flatMap { UTType(filenameExtension: ($0 as NSString).pathExtension) }?.conforms(to: .image) == true
    }
    static func isPDF(name: String?, type: String?) -> Bool {
        type == "com.adobe.pdf" || type == "application/pdf" ||
            (name.map { ($0 as NSString).pathExtension.lowercased() == "pdf" } ?? false)
    }
    static func label(for clip: Clip) -> String {
        switch clip.kind {
        case .text: return link(in: clip.text) == nil ? "Text" : "Link"
        case .image: return "Image"
        case .file: return isPDF(name: clip.fileName, type: clip.fileType) ? "PDF" : "File"
        }
    }
    static func matches(_ clip: Clip, query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || [clip.text, clip.app, clip.fileName ?? "", clip.ocrText, label(for: clip)]
            .contains { $0.localizedStandardContains(query) }
    }
}

// NSCache is thread-safe; PDFDocument instances stay confined to the serial queue.
private final class PDFThumbnailCache: @unchecked Sendable {
    static let shared = PDFThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()
    private let queue = DispatchQueue(label: "cleverclipboard.pdf-previews", qos: .userInitiated)
    init() { cache.totalCostLimit = 16 * 1024 * 1024 }
    func load(_ url: URL) async -> NSImage? {
        guard url.isFileURL else { return nil }
        if let image = cache.object(forKey: url.path as NSString) { return image }
        return await withCheckedContinuation { continuation in
            queue.async {
                let image: NSImage? = autoreleasepool {
                    guard let document = PDFDocument(url: url), !document.isLocked,
                          let page = document.page(at: 0) else { return nil }
                    return page.thumbnail(of: NSSize(width: 240, height: 320), for: .cropBox)
                }
                if let image { self.cache.setObject(image, forKey: url.path as NSString, cost: 240 * 320 * 4) }
                continuation.resume(returning: image)
            }
        }
    }
}

struct AssetPreview: View {
    let url: URL?
    let kind: Clip.Kind
    var name: String? = nil
    var type: String? = nil
    var large = false
    var compact = false
    @State private var pdfImage: NSImage?
    @State private var showImage = false
    private var imageAsset: Bool { kind == .image || (kind == .file && ItemPresentation.isImage(name: name, type: type)) }
    private var pdf: Bool { kind == .file && ItemPresentation.isPDF(name: name, type: type) }
    var body: some View {
        Group {
            if (imageAsset || pdf) && !large {
                Button { showImage = true } label: {
                    Group {
                        if pdf {
                            Image(systemName: "doc.text").font(.system(size: compact ? 27 : 32, weight: .ultraLight))
                        } else if let url, let image = ImageThumbnail.shared.load(url) {
                            Image(nsImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 3))
                        } else {
                            ImageOutline().stroke(style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
                                .frame(width: compact ? 30 : 36, height: compact ? 24 : 29)
                        }
                    }
                        .foregroundStyle(CarbonTheme.ink)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                }.buttonStyle(.plain).modifier(CarbonHover()).help(pdf ? "Preview PDF" : "Preview image").accessibilityLabel(pdf ? "Preview PDF" : "Preview image")
                    .popover(isPresented: $showImage) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(name ?? (pdf ? "PDF" : "Image")).font(.system(size: 14, weight: .medium))
                            if pdf, let url {
                                LocalPDFPreview(url: url).frame(width: 440, height: 340)
                            } else if let url, let image = NSImage(contentsOf: url) {
                                Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: 480, maxHeight: 360)
                            } else {
                                Text("Image preview unavailable").foregroundStyle(CarbonTheme.secondary)
                            }
                        }.padding(20).carbonRoot()
                    }
            } else if let url, imageAsset, let image = ImageThumbnail.shared.load(url) {
                Image(nsImage: image).resizable().scaledToFit()
            } else if let pdfImage, pdf {
                Image(nsImage: pdfImage).resizable().scaledToFit()
            } else {
                Image(systemName: imageAsset ? "photo" : pdf ? "doc.richtext" : "doc")
                    .font(.system(size: large ? 44 : 25, weight: .light))
                    .foregroundStyle(CarbonTheme.secondary)
            }
        }
        .frame(width: large ? 260 : compact ? 56 : 52, height: large ? 210 : compact ? 36 : 54)
        .padding(4)
        .accessibilityLabel(pdf ? "PDF first-page preview" : imageAsset ? "Image preview" : "File")
        .task(id: url) {
            pdfImage = nil
            guard pdf, large, let url else { return }
            let result = await PDFThumbnailCache.shared.load(url)
            guard !Task.isCancelled else { return }
            pdfImage = result
        }
    }
}

struct LinkPreview: View {
    let url: URL
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "link").font(.system(size: 23, weight: .light))
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(url.host ?? "Link").font(.system(size: 14, weight: .medium)).lineLimit(1)
                Text(url.absoluteString).font(.system(size: 11)).foregroundStyle(CarbonTheme.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 8).accessibilityElement(children: .combine)
    }
}

/// Full-content preview is opened explicitly; compact cards remain monochrome line art.
private struct LocalPDFPreview: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = CarbonTheme.background
        view.document = PDFDocument(url: url)
        return view
    }
    func updateNSView(_ view: PDFView, context: Context) {}
}

/// A monochrome outline: no filled mountains or coloured placeholder artwork.
private struct ImageOutline: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRoundedRect(in: rect.insetBy(dx: 0.5, dy: 0.5), cornerSize: CGSize(width: 3, height: 3))
        path.addEllipse(in: CGRect(x: rect.width * 0.68, y: rect.height * 0.20, width: rect.height * 0.17, height: rect.height * 0.17))
        path.move(to: CGPoint(x: rect.width * 0.10, y: rect.height * 0.79))
        path.addLine(to: CGPoint(x: rect.width * 0.37, y: rect.height * 0.40))
        path.addLine(to: CGPoint(x: rect.width * 0.61, y: rect.height * 0.73))
        path.addLine(to: CGPoint(x: rect.width * 0.73, y: rect.height * 0.57))
        path.addLine(to: CGPoint(x: rect.width * 0.90, y: rect.height * 0.79))
        return path
    }
}
