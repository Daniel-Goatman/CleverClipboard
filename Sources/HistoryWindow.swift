import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class HistoryWindowModel: ObservableObject {
    @Published var items: [Clip] = []
    @Published var pins: [PinnedEntry] = PinnedEntry.defaults
    @Published var selectedTab = 0
    @Published var message = ""
    @Published var drafts: [PinnedEntry] = []
    @Published private(set) var saveError: String?
    private var editingStarted = false
    var imageURL: (String) -> URL? = { _ in nil }
    var fileURL: (Clip) -> URL? = { _ in nil }
    var onCopy: (String) -> Void = { _ in }
    var onDelete: (String) -> Void = { _ in }
    var onClear: () -> Void = {}
    var onSettings: () -> Void = {}
    var onSavePins: ([PinnedEntry]) -> Bool = { _ in false }
    var assetURL: (PinnedEntry) -> URL? = { _ in nil }
    var onImportAsset: (Int, URL, Clip.Kind, Int, @escaping (Result<PinnedEntry, Error>) -> Void) -> Void =
        { _, _, _, _, _ in }
    var activeEntryCount: Int { pins.filter { $0.clip != nil }.count }
    var ordinaryCandidateCount: Int { max(0, ClipboardSelection.maximumCandidates - activeEntryCount) }
    var candidateCount: Int { min(items.count, ordinaryCandidateCount) + activeEntryCount }
    var hasUnsavedChanges: Bool { editingStarted && drafts != pins }
    func beginEditing() {
        guard !editingStarted else { return }
        drafts = pins; editingStarted = true
    }
    func updatePins(_ newPins: [PinnedEntry]) {
        let wasClean = !hasUnsavedChanges
        pins = newPins
        if wasClean { drafts = newPins }
    }
    @discardableResult func saveDrafts() -> Bool {
        let saved = onSavePins(drafts)
        saveError = saved ? nil : (message.isEmpty ? "Could not save changes. Try again." : message)
        return saved
    }
    func discardDrafts() { drafts = pins; saveError = nil }
}

struct HistoryWindowView: View {
    @ObservedObject var model: HistoryWindowModel
    private var tab: Int { model.selectedTab }
    @State private var selection: String?
    @State private var query = ""
    @State private var confirmClear = false
    @State private var showImporter = false
    @State private var importKind: Clip.Kind = .file
    @State private var importTargetID: Int?
    @State private var importBusy = false
    @State private var importMessage = ""
    @FocusState private var searchFocused: Bool
    private var filtered: [Clip] { model.items.filter { ItemPresentation.matches($0, query: query) } }
    private var selected: Clip? { filtered.first { $0.id == selection } }

    init(model: HistoryWindowModel, initialTab: Int? = nil) {
        self.model = model
        if let initialTab { model.selectedTab = initialTab }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            CarbonDivider()
            // Keep native lists/editors alive: tab changes should not rebuild or decode previews.
            ZStack {
                historyContent.opacity(tab == 0 ? 1 : 0)
                    .allowsHitTesting(tab == 0).accessibilityHidden(tab != 0).disabled(tab != 0)
                pinsContent.opacity(tab == 1 ? 1 : 0)
                    .allowsHitTesting(tab == 1).accessibilityHidden(tab != 1).disabled(tab != 1)
            }.transaction { $0.animation = nil }
            CarbonDivider()
            footer
        }
        .frame(minWidth: 820, minHeight: 560)
        .carbonRoot()
        .onAppear { model.beginEditing(); reconcileSelection() }
        .onChange(of: query) { _, _ in reconcileSelection() }
        .onChange(of: model.items.map(\.id)) { _, _ in reconcileSelection() }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: importKind == .image ? [.image] : [.item]) { result in
            guard case .success(let url) = result, let id = importTargetID else {
                if case .failure(let error) = result { importMessage = error.localizedDescription }
                return
            }
            importBusy = true; importMessage = "Importing…"
            let kind = importKind
            let otherBytes = model.drafts.filter { $0.id != id }.reduce(0) { $0 + $1.assetBytes }
            model.onImportAsset(id, url, kind, otherBytes) { imported in
                importBusy = false
                switch imported {
                case .success(var entry):
                    if let index = model.drafts.firstIndex(where: { $0.id == id }) {
                        entry.description = model.drafts[index].description
                        model.drafts[index] = entry
                    } else { model.drafts.append(entry) }
                    importMessage = "Asset imported · save changes to keep it"
                case .failure(let error): importMessage = error.localizedDescription
                }
            }
        }
        .confirmationDialog("Clear all ordinary clipboard history?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { model.onClear(); selection = nil }
        } message: { Text("Always Available entries will remain.") }
    }

    private var header: some View {
        HStack(spacing: 20) {
            CarbonLogo().frame(width: 40, height: 32)
            Text(AppBrand.name).font(.system(size: 22, weight: .medium))
            Spacer(minLength: 8)
            VStack(spacing: 8) {
                CarbonTabs(selection: $model.selectedTab)
                Text(tab == 1 ? "Saved entries remain available after clearing history." : "Your recent clipboard history.")
                    .font(.system(size: 11)).foregroundStyle(CarbonTheme.secondary).fixedSize(horizontal: true, vertical: false)
            }
            Spacer(minLength: 8)
            Button(action: model.onSettings) { Label("Settings", systemImage: "gearshape") }
                .help("Settings…").accessibilityLabel("Settings")
        }.padding(.horizontal, 24).padding(.vertical, 17)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if tab == 0 {
                Text("\(model.items.count) / 50 · \(ByteCountFormatter.string(fromByteCount: Int64(model.items.reduce(0) { $0 + $1.bytes }), countStyle: .file))")
                    .font(.system(size: 11)).foregroundStyle(CarbonTheme.secondary)
            } else {
                Menu {
                    Button("Text") { addTextEntry() }
                    Button("Image…") { beginImport(.image) }
                    Button("File…") { beginImport(.file) }
                } label: { Label("Add Entry", systemImage: "plus") }
                    .menuStyle(.borderlessButton)
                    .padding(.horizontal, 12).padding(.vertical, 8).background(CarbonControlSurface(selected: true))
                    .modifier(CarbonHover()).fixedSize().disabled(model.drafts.count >= PinnedEntry.maximumCount || importBusy)
                Text("\(model.drafts.count) / 20 · \(ByteCountFormatter.string(fromByteCount: Int64(model.drafts.reduce(0) { $0 + $1.assetBytes }), countStyle: .file)) / 512 MB")
                    .font(.system(size: 11)).foregroundStyle(CarbonTheme.secondary).fixedSize(horizontal: true, vertical: false)
            }
            Spacer(minLength: 8)
            Text(footerMessage).font(.system(size: 11)).foregroundStyle(CarbonTheme.secondary)
                .lineLimit(2).help(footerMessage).accessibilityLabel(footerMessage)
            if tab == 0 {
                Button { confirmClear = true } label: { Label("Clear History", systemImage: "trash") }
                    .disabled(model.items.isEmpty)
            } else {
                Button { if model.saveDrafts() { importMessage = "" } } label: {
                    HStack(spacing: 16) { Text("Save Changes"); Text("⌘S").opacity(0.65) }
                }
                .buttonStyle(CarbonButtonStyle(prominent: true))
                .disabled(!model.hasUnsavedChanges || importBusy)
                .keyboardShortcut("s", modifiers: .command)
            }
        }.padding(18)
    }
    private var footerMessage: String {
        if tab == 1 && !importMessage.isEmpty { return importMessage }
        if tab == 1 && model.hasUnsavedChanges {
            return model.saveError.map { "Unsaved changes · \($0)" } ?? "Unsaved changes"
        }
        return model.message
    }

    private var historyContent: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(CarbonTheme.secondary)
                    TextField("Search clipboard", text: $query).textFieldStyle(.plain)
                        .focused($searchFocused).accessibilityLabel("Search clipboard")
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).modifier(CarbonHover()).accessibilityLabel("Clear search")
                    }
                }.padding(10).carbonCard().padding(14)
                // Native List retains arrow-key selection, focus, and VoiceOver behaviour.
                List(selection: $selection) {
                    ForEach(filtered) { clip in
                        historyRow(clip).tag(clip.id)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }.listStyle(.sidebar).scrollContentBackground(.hidden)
                if filtered.isEmpty && !query.isEmpty {
                    Text("No matching items").foregroundStyle(CarbonTheme.secondary).padding(20)
                }
            }.frame(width: 292)
                .background(Color.black.opacity(0.06))
            Divider().opacity(0.25)
            if let clip = selected {
                historyDetail(clip)
            } else {
                ContentUnavailableView(model.items.isEmpty ? "Your clipboard starts here" : "No item selected",
                                       systemImage: "list.clipboard",
                                       description: Text(model.items.isEmpty ? "Copy text, an image, or a file to add it to history." : "Choose an item to see its contents."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Button("") { searchFocused = true }.keyboardShortcut("f").disabled(tab != 0).hidden())
    }

    private func historyRow(_ clip: Clip) -> some View {
        HStack(spacing: 12) {
            if clip.kind == .image || clip.kind == .file {
                AssetPreview(url: clip.kind == .image ? model.imageURL(clip.id) : model.fileURL(clip),
                             kind: clip.kind, name: clip.fileName, type: clip.fileType)
            } else {
                Image(systemName: ItemPresentation.link(in: clip.text) == nil ? "doc.text" : "link")
                    .font(.system(size: 23, weight: .light)).frame(width: 52, height: 54)

            }
            VStack(alignment: .leading, spacing: 6) {
                Text(clip.preview).font(.system(size: 13, weight: .medium)).lineLimit(2)
                Text(ItemPresentation.label(for: clip) == "Text" ? clip.app : "\(ItemPresentation.label(for: clip)) · \(clip.app)")
                    .font(.system(size: 11)).foregroundStyle(CarbonTheme.secondary).lineLimit(1)
                Text(clip.copiedAt, style: .relative).font(.system(size: 10)).foregroundStyle(CarbonTheme.secondary)
            }
        }.padding(.vertical, 8)
            .accessibilityElement(children: .combine)
    }

    private func historyDetail(_ clip: Clip) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text(ItemPresentation.label(for: clip) == "Text" ? "Clipboard item" : ItemPresentation.label(for: clip)).font(.system(size: 22, weight: .medium))
                    Spacer()
                    Button { model.onCopy(clip.id) } label: { Label("Copy", systemImage: "doc.on.doc") }
                    Button(role: .destructive) { model.onDelete(clip.id) } label: { Label("Delete", systemImage: "trash") }
                }
                if clip.kind == .image, let url = model.imageURL(clip.id), let image = NSImage(contentsOf: url) {
                    Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 280)
                        .frame(maxWidth: .infinity).accessibilityLabel("Copied image")
                } else if clip.kind == .file {
                    AssetPreview(url: model.fileURL(clip), kind: .file, name: clip.fileName, type: clip.fileType, large: true)
                    Text(clip.fileName ?? "File").textSelection(.enabled)
                } else {
                    if let url = ItemPresentation.link(in: clip.text) { LinkPreview(url: url) }
                    Text(clip.text).textSelection(.enabled).lineSpacing(5)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(18).carbonCard()
                }
                VStack(spacing: 12) {
                    metadata("Source", clip.app)
                    CarbonDivider()
                    metadata("Copied", clip.copiedAt.formatted(date: .abbreviated, time: .shortened))
                }
                CarbonDivider()
                DisclosureGroup("Selection excerpt") {
                    VStack(alignment: .leading, spacing: 12) {
                        if let index = model.items.firstIndex(where: { $0.id == clip.id }), index < model.ordinaryCandidateCount {
                            Text(CandidateText.forClip(clip, candidateCount: max(1, model.candidateCount)))
                                .font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(12).carbonCard()
                        } else {
                            Text("This older item is outside the current Smart Paste candidate limit. You can still copy it here.")
                        }
                        Text("Illustrative excerpt; actual selection context may differ. Image pixels and file bytes stay local.")
                            .font(.system(size: 11)).foregroundStyle(CarbonTheme.secondary)
                    }.padding(.top, 12)
                }.foregroundStyle(CarbonTheme.secondary)
            }.padding(24)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func metadata(_ label: String, _ value: String) -> some View {
        HStack { Text(label).foregroundStyle(CarbonTheme.secondary).frame(width: 90, alignment: .leading); Text(value); Spacer() }
    }

    private var pinsContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !model.drafts.isEmpty {
                    HStack(spacing: 20) {
                        Text("Description").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Value").frame(maxWidth: .infinity, alignment: .leading)
                        Color.clear.frame(width: 92, height: 1)
                    }.font(.system(size: 12, weight: .medium)).foregroundStyle(CarbonTheme.secondary).padding(.bottom, 12)
                }
                ForEach($model.drafts) { $entry in
                    savedRow($entry)
                    CarbonDivider().padding(.vertical, 12)
                }
                if model.drafts.isEmpty {
                    ContentUnavailableView("Always within reach", systemImage: "pin",
                                           description: Text("Use Add Entry to save text, an image, or a file. Add a description so Smart Paste knows when to use it."))
                        .frame(maxWidth: .infinity).padding(.top, 60)
                }
            }.padding(24)
        }
    }

    private func savedRow(_ binding: Binding<PinnedEntry>) -> some View {
        let entry = binding.wrappedValue
        return HStack(alignment: .top, spacing: 20) {
            TextField("When to use this", text: binding.description, axis: .vertical)
                .lineLimit(1...4).carbonField().accessibilityLabel("Description")
                .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 10) {
                if entry.kind == .text {
                    TextField("Text to paste", text: binding.value, axis: .vertical)
                        .lineLimit(1...6).carbonField().accessibilityLabel("Value")
                    if let url = ItemPresentation.link(in: entry.value) { LinkPreview(url: url) }

                } else {
                    HStack(alignment: .top, spacing: 8) {
                        Text(entry.assetName ?? "Missing asset").lineLimit(2).textSelection(.enabled)
                            .padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
                        Button("Replace…") { beginImport(entry.kind, replacing: entry.id) }.disabled(importBusy)
                    }
                    HStack(spacing: 12) {
                        AssetPreview(url: model.assetURL(entry), kind: entry.kind, name: entry.assetName, type: entry.assetType, compact: true)
                        HStack(spacing: 5) {
                            Text(entry.kind == .image ? "Image" : ItemPresentation.isPDF(name: entry.assetName, type: entry.assetType) ? "File · PDF" : "File")
                            Text("·")
                            Text(ByteCountFormatter.string(fromByteCount: Int64(entry.assetBytes), countStyle: .file))
                        }.font(.system(size: 11)).foregroundStyle(CarbonTheme.secondary)
                    }
                }
            }.frame(maxWidth: .infinity)
            HStack(spacing: 8) {
                Button { model.onCopy("pin-\(entry.id)") } label: { Image(systemName: "doc.on.doc") }
                    .help("Copy saved entry").accessibilityLabel("Copy saved entry")
                    .disabled(!model.pins.contains { $0 == entry && $0.clip != nil })
                Button(role: .destructive) { model.drafts.removeAll { $0.id == entry.id } } label: { Image(systemName: "trash") }
                    .help("Remove entry after saving changes").accessibilityLabel("Remove saved entry").disabled(importBusy)
            }.frame(width: 92)
        }
    }
    private func reconcileSelection() {
        if !filtered.contains(where: { $0.id == selection }) { selection = filtered.first?.id }
    }
    private func addTextEntry() {
        guard model.drafts.count < PinnedEntry.maximumCount else { return }
        model.drafts.append(PinnedEntry(id: (model.drafts.map(\.id).max() ?? -1) + 1, description: "", value: ""))
        importMessage = ""
    }
    private func beginImport(_ kind: Clip.Kind, replacing id: Int? = nil) {
        guard !importBusy, id != nil || model.drafts.count < PinnedEntry.maximumCount else { return }
        importKind = kind; importTargetID = id ?? (model.drafts.map(\.id).max() ?? -1) + 1
        importMessage = ""; showImporter = true
    }
}
