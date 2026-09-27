import AppKit

@main struct CarbonTests {
    static func main() {
        precondition(ItemPresentation.link(in: "https://example.com/project")?.host == "example.com")
        precondition(ItemPresentation.link(in: "  https://example.com/path?a=1\n") != nil)
        for text in ["Hi Alex, please visit https://example.com", "hello@example.com", "mailto:hello@example.com", "file:///tmp/a.pdf", "javascript:alert(1)", "https://user:password@example.com", "https://", "Hi Alex, thanks for your time."] {
            precondition(ItemPresentation.link(in: text) == nil, "Prose and unsupported URLs must remain plain text")
        }
        precondition(ItemPresentation.isPDF(name: "BRIEF.PDF", type: nil))
        precondition(!ItemPresentation.isPDF(name: "brief.pdf.txt", type: nil))
        precondition(ItemPresentation.isPDF(name: "asset", type: "com.adobe.pdf"))
        let clip = Clip(id: "a", text: "Hi Alex, thanks for your time.", app: "Mail", copiedAt: Date())
        precondition(ItemPresentation.label(for: clip) == "Text", "Mail source cannot turn prose into an email widget")
        precondition(ItemPresentation.matches(clip, query: "ALEX"))
        precondition(ItemPresentation.matches(clip, query: "mail"))
        precondition(!ItemPresentation.matches(clip, query: "nomatch"))
        let model = HistoryWindowModel()
        let original = PinnedEntry(id: 0, description: "Original", value: "Hello")
        model.updatePins([original]); model.beginEditing()
        precondition(!model.hasUnsavedChanges)
        model.drafts[0].description = "Edited"
        model.updatePins([original])
        precondition(model.drafts[0].description == "Edited", "Status refresh must not replace an unsaved draft")
        model.onSavePins = { _ in false }
        precondition(!model.saveDrafts() && model.hasUnsavedChanges, "Failed save preserves the editable draft")
        model.onSavePins = { [weak model] entries in model?.updatePins(entries); return true }
        precondition(model.saveDrafts())
        precondition(!model.hasUnsavedChanges && model.pins[0].description == "Edited")
        model.drafts.removeAll()
        precondition(model.hasUnsavedChanges && model.pins.count == 1, "Remove is not persisted until Save Changes")
        model.discardDrafts()
        precondition(model.drafts == model.pins && !model.hasUnsavedChanges)
        print("PASS Carbon: local URL detection, no email inference, PDF types, search, draft refresh/save/failure/discard")
    }
}
