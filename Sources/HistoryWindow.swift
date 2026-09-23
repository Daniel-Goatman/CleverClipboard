import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class HistoryWindowModel: ObservableObject {
    @Published var items: [Clip] = []
    @Published var pins: [PinnedEntry] = PinnedEntry.defaults
    @Published var paused = false
    @Published var message = ""
    var imageURL: (String) -> URL? = { _ in nil }
    var onCopy: (String) -> Void = { _ in }
    var onDelete: (String) -> Void = { _ in }
    var onClear: () -> Void = {}
    var onPause: () -> Void = {}
    var onSavePins: ([PinnedEntry]) -> Void = { _ in }
    var assetURL: (PinnedEntry) -> URL? = { _ in nil }
    var onImportAsset: (Int, URL, Clip.Kind, Int, @escaping (Result<PinnedEntry, Error>) -> Void) -> Void =
        { _, _, _, _, _ in }
    var activeEntryCount: Int { pins.filter { $0.clip != nil }.count }
    var ordinaryCandidateCount: Int { max(0, ClipboardSelection.maximumCandidates - activeEntryCount) }
    var candidateCount: Int { min(items.count, ordinaryCandidateCount) + activeEntryCount }
}

struct HistoryWindowView: View {
    @ObservedObject var model: HistoryWindowModel
    @State private var tab = 0
    @State private var selection: String?
    @State private var drafts = PinnedEntry.defaults
    @State private var confirmClear = false
    @State private var showImporter = false
    @State private var importKind: Clip.Kind = .file
    @State private var importTargetID: Int?
    @State private var importBusy = false
    @State private var importMessage = ""
    private var selected: Clip? { model.items.first { $0.id == selection } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Jev Clipboard").font(.title2.bold())
                Spacer()
                Text("\(model.items.count)/50 · \(ByteCountFormatter.string(fromByteCount: Int64(model.items.reduce(0) {$0+$1.bytes}), countStyle: .memory))")
                    .foregroundStyle(.secondary)
            }.padding([.top, .horizontal])
            Picker("View", selection: $tab) {
                Text("History").tag(0)
                Text("Always Available").tag(1)
            }.pickerStyle(.segmented).frame(width: 330).padding(12)
            if tab == 0 { historyContent } else { pinsContent }
            Divider()
            HStack {
                if tab == 0 {
                    Button(model.paused ? "Resume Collection" : "Pause Collection") { model.onPause() }
                    Button("Clear History") { confirmClear = true }.disabled(model.items.isEmpty)
                } else {
                    Menu {
                        Button("Text") { addTextEntry() }
                        Button("Image…") { beginImport(.image) }
                        Button("File…") { beginImport(.file) }
                    } label: { Label("Add Entry", systemImage: "plus") }
                    .disabled(drafts.count >= PinnedEntry.maximumCount || importBusy)
                    Text("\(drafts.count)/\(PinnedEntry.maximumCount) · \(ByteCountFormatter.string(fromByteCount: Int64(drafts.reduce(0) { $0 + $1.assetBytes }), countStyle: .file)) / 512 MB")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if !importMessage.isEmpty {
                    Text(importMessage).foregroundStyle(.secondary).lineLimit(1)
                } else if tab == 1 && drafts != model.pins {
                    Text("Unsaved changes").foregroundStyle(.secondary)
                } else if !model.message.isEmpty {
                    Text(model.message).foregroundStyle(.secondary).lineLimit(1)
                }
                if tab == 1 {
                    Button("Save Changes") { model.onSavePins(drafts); importMessage = "" }
                        .disabled(drafts == model.pins || importBusy)
                        .keyboardShortcut("s", modifiers: .command)
                }
            }.padding(12)
        }
        .frame(minWidth: 700, minHeight: 480)
        .onAppear { drafts = model.pins; if selection == nil { selection = model.items.first?.id } }
        .onChange(of: model.pins) { _, newValue in drafts = newValue }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: importKind == .image ? [.image] : [.item]) { result in
            guard case .success(let url) = result, let id = importTargetID else {
                if case .failure(let error) = result { importMessage = error.localizedDescription }
                return
            }
            importBusy = true; importMessage = "Importing…"
            let kind = importKind
            let otherBytes = drafts.filter { $0.id != id }.reduce(0) { $0 + $1.assetBytes }
            model.onImportAsset(id, url, kind, otherBytes) { imported in
                importBusy = false
                switch imported {
                case .success(var entry):
                    if let index = drafts.firstIndex(where: { $0.id == id }) {
                        entry.description = drafts[index].description
                        drafts[index] = entry
                    } else { drafts.append(entry) }
                    importMessage = "Asset imported · save changes to keep it"
                case .failure(let error): importMessage = error.localizedDescription
                }
            }
        }
        .confirmationDialog("Clear all ordinary clipboard history?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { model.onClear(); selection = nil }
        } message: { Text("Always Available entries will remain.") }
    }

    private var historyContent: some View {
        HStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(model.items) { clip in
                    HStack(spacing: 9) {
                        if clip.kind == .image, let url = model.imageURL(clip.id), let image = ImageThumbnail.shared.load(url) {
                            Image(nsImage: image).resizable().scaledToFill().frame(width: 42, height: 34).clipped().cornerRadius(4)
                        } else {
                            Image(systemName: "doc.on.clipboard").frame(width: 42, height: 34)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(clip.preview).lineLimit(2)
                            Text("\(clip.app) · \(clip.copiedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }.tag(clip.id).accessibilityLabel("\(clip.kind.rawValue), \(clip.preview), copied from \(clip.app)")
                }
            }.frame(width: 290)
            Divider()
            if let clip = selected {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(clip.kind == .image ? "Image" : "Text").font(.headline)
                            Spacer()
                            Button("Copy") { model.onCopy(clip.id) }
                            Button("Delete", role: .destructive) { model.onDelete(clip.id); selection = model.items.first?.id }
                        }
                        if clip.kind == .image, let url = model.imageURL(clip.id), let image = NSImage(contentsOf: url) {
                            Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 220)
                        } else {
                            Text(clip.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Divider()
                        Text("Text sent to Jev").font(.headline)
                        if let index = model.items.firstIndex(where: { $0.id == clip.id }),
                           index < model.ordinaryCandidateCount {
                            Text(CandidateText.forClip(clip, candidateCount: max(1, model.candidateCount)))
                                .font(.system(.body, design: .monospaced)).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text("This older history item is stored but outside the current Smart Paste candidate limit. You can still copy it here.")
                                .foregroundStyle(.secondary)
                        }
                        Text("Jev also receives type, source app, copy age, and order. Image pixels stay local.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding()
                }.frame(maxWidth: .infinity)
            } else {
                ContentUnavailableView("No item selected", systemImage: "clipboard", description: Text("Copy text or an image to add it to history."))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var pinsContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                Text("Saved entries remain available after clearing history. Describe where each value belongs.")
                    .font(.callout).foregroundStyle(.secondary).padding(.bottom, 6)
                if !drafts.isEmpty {
                    HStack(spacing: 10) {
                        Text("Description").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Value").frame(maxWidth: .infinity, alignment: .leading)
                        Color.clear.frame(width: 60)
                    }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 10)
                }
                ForEach(drafts) { entry in
                    let editable = Binding<PinnedEntry>(
                        get: { drafts.first(where: { $0.id == entry.id }) ?? entry },
                        set: { updated in
                            guard let index = drafts.firstIndex(where: { $0.id == entry.id }) else { return }
                            drafts[index] = updated
                        }
                    )
                    HStack(alignment: .top, spacing: 10) {
                        TextField("When to use this", text: editable.description)
                            .accessibilityLabel("Description")
                            .frame(maxWidth: .infinity)
                        Group {
                            if entry.kind == .text {
                                TextField("Text to paste", text: editable.value, axis: .vertical)
                                    .lineLimit(1...4)
                                    .accessibilityLabel("Value")
                            } else {
                                HStack(spacing: 8) {
                                    if entry.kind == .image, let url = model.assetURL(entry),
                                       let image = ImageThumbnail.shared.load(url) {
                                        Image(nsImage: image).resizable().scaledToFit()
                                            .frame(width: 40, height: 32)
                                    } else {
                                        Image(systemName: entry.kind == .image ? "photo" : "doc")
                                            .frame(width: 40, height: 32)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.assetName ?? "Missing asset").lineLimit(1)
                                        Text("\(entry.kind == .image ? "Image" : "File") · \(ByteCountFormatter.string(fromByteCount: Int64(entry.assetBytes), countStyle: .file))")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 4)
                                    Button("Replace…") { beginImport(entry.kind, replacing: entry.id) }
                                }.accessibilityElement(children: .contain)
                            }
                        }.frame(maxWidth: .infinity)
                        Button { model.onCopy("pin-\(entry.id)") } label: {
                            Image(systemName: "doc.on.clipboard")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Copy saved entry")
                        .help("Copy saved entry")
                        .disabled(!model.pins.contains { $0 == entry && $0.clip != nil })
                        .frame(width: 25, height: 25)
                        Button(role: .destructive) { drafts.removeAll { $0.id == entry.id } } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove saved entry")
                        .help("Remove entry after saving changes")
                        .frame(width: 25, height: 25)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))
                }
                if drafts.isEmpty {
                    ContentUnavailableView("No saved entries", systemImage: "pin", description: Text("Add a value you want to keep available."))
                        .frame(maxWidth: .infinity).padding(.top, 60)
                }
            }.padding(16)
        }
    }

    private func addTextEntry() {
        let id = (drafts.map(\.id).max() ?? -1) + 1
        drafts.append(PinnedEntry(id: id, description: "", value: ""))
        importMessage = ""
    }
    private func beginImport(_ kind: Clip.Kind, replacing id: Int? = nil) {
        guard !importBusy, id != nil || drafts.count < PinnedEntry.maximumCount else { return }
        importKind = kind
        importTargetID = id ?? (drafts.map(\.id).max() ?? -1) + 1
        importMessage = ""
        showImporter = true
    }
}
