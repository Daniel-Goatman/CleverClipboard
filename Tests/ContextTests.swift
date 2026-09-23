import Foundation
import ApplicationServices

@main struct ContextTests {
    static func main() {
        testMarkerAdapter()
        var range = CFRange(location: 3, length: 2)
        let a = AXValueCreate(.cfRange, &range)!
        let b = AXValueCreate(.cfRange, &range)!
        let first = InputTarget.fingerprint(value: "hello", selectionValue: a)
        precondition(first == InputTarget.fingerprint(value: "hello", selectionValue: b))
        range.location = 4
        let changed = AXValueCreate(.cfRange, &range)!
        precondition(first != InputTarget.fingerprint(value: "hello", selectionValue: changed))
        precondition(first != InputTarget.fingerprint(value: "world", selectionValue: a))
        precondition(first != InputTarget.fingerprint(value: "hello", selectionValue: nil))
        let markerA = [UInt8](repeating: 1, count: 8).withUnsafeBufferPointer {
            AXTextMarkerCreate(nil, $0.baseAddress!, $0.count)
        }
        let markerB = [UInt8](repeating: 2, count: 8).withUnsafeBufferPointer {
            AXTextMarkerCreate(nil, $0.baseAddress!, $0.count)
        }
        let markerC = [UInt8](repeating: 3, count: 8).withUnsafeBufferPointer {
            AXTextMarkerCreate(nil, $0.baseAddress!, $0.count)
        }
        let markerRange = AXTextMarkerRangeCreate(nil, markerA, markerB)
        let movedMarkerRange = AXTextMarkerRangeCreate(nil, markerA, markerC)
        precondition(InputTarget.fingerprint(value: "", selectionValue: markerRange)
                     != InputTarget.fingerprint(value: "", selectionValue: movedMarkerRange))
        let sentence = "Reach out to me at my number "
        precondition(axPlainText(NSAttributedString(string: sentence)) == sentence)
        precondition(axPlainText(sentence) == sentence)
        let inline = InsertionContext.make(value: sentence, range: CFRange(location: sentence.utf16.count, length: 0))!
        precondition(inline.before == sentence && inline.after.isEmpty && !inline.isReplacement)
        let middle = "Email me at OLD, thanks 🙂"
        let oldRange = (middle as NSString).range(of: "OLD")
        let replacement = InsertionContext.make(value: middle, range: CFRange(location: oldRange.location, length: oldRange.length))!
        precondition(replacement.before == "Email me at " && replacement.after == ", thanks 🙂")
        precondition(replacement.replacing == "OLD" && replacement.isReplacement)
        let emoji = "🙂 call me at "
        precondition(InsertionContext.make(value: emoji, range: CFRange(location: emoji.utf16.count, length: 0))?.before == emoji)
        precondition(InsertionContext.make(value: emoji, range: CFRange(location: 1, length: 0)) == nil)
        precondition(InsertionContext.make(value: "hello", range: nil) == nil)
        for invalid in [CFRange(location: -1, length: 0), CFRange(location: 8, length: 0),
                        CFRange(location: 2, length: -1), CFRange(location: 2, length: Int.max)] {
            precondition(InsertionContext.make(value: "hello", range: invalid) == nil)
        }
        let long = String(repeating: "界🙂", count: 10000) + sentence
        let capped = InsertionContext.make(value: long, range: CFRange(location: long.utf16.count, length: 0))!
        precondition(capped.before.utf8.count <= 600 && capped.before.hasSuffix(sentence))
        let all = InsertionContext.make(value: long, range: CFRange(location: 0, length: long.utf16.count))!
        precondition(all.before.isEmpty && all.after.isEmpty && all.replacing.utf8.count <= 160 && all.isReplacement)
        print("PASS: caret-adjacent excerpts, replacement boundaries, UTF-16 emoji, invalid/missing ranges and long-document caps")
        let field = ContextField(role: "AXTextArea", subrole: "", identifier: "test", attributes: ["description": "Description"], linkedLabels: [], bounds: [300,300,400,40])
        var evidence = FieldEvidence(app: "Fixture", bundleID: "fixture", windowTitle: "Application", field: field)
        evidence.insertion = inline
        precondition(evidence.needsOCR)
        evidence.field.linkedLabels = ["Cover letter"]
        precondition(!evidence.needsOCR)
        evidence.nearby = (0..<36).map { _ in ContextText(text: String(repeating: "界", count: 160), role: "AXStaticText") }
        evidence.ocr = (0..<24).map { _ in ContextText(text: String(repeating: "字", count: 160), role: "AXStaticText", source: "ocr") }
        let encoded = try! evidence.encoded()
        precondition(encoded.utf8.count <= 5800)
        let decoded = try! JSONDecoder().decode(FieldEvidence.self, from: Data(encoded.utf8))
        precondition(decoded.insertion == inline)
        precondition(decoded.field.linkedLabels == ["Cover letter"])
        precondition(decoded.field.bounds == [300,300,400,40])
        precondition(decoded.ocr.count < 24)
        print("PASS: provenance-preserving context encoding, Unicode size cap, geometry and OCR decision")
        print("PASS: stable AX range fingerprint; changed cursor, selection, value and missing range invalidate target")
    }

    static func testMarkerAdapter() {
        let element = AXUIElementCreateApplication(1)
        func marker(_ index: UInt8) -> AXTextMarker {
            [UInt8](repeating: index, count: 8).withUnsafeBufferPointer {
                AXTextMarkerCreate(nil, $0.baseAddress!, $0.count)
            }
        }
        let first = marker(0), start = marker(1), end = marker(2), last = marker(3)
        let selected = AXTextMarkerRangeCreate(nil, start, end)
        let whole = AXTextMarkerRangeCreate(nil, first, last)
        // Exercise each supported provider shape through the real marker adapter.
        for provider in ["element", "line", "endpoints", "missing"] {
            var reader = AXTextReader(element)
            var askedInvalidAttribute = false
            reader.attribute = { name in
                if name == "AXTextMarkerRange" { askedInvalidAttribute = true }
                if name == "AXSelectedTextMarkerRange" { return selected }
                if provider == "endpoints" && name == "AXStartTextMarker" { return first }
                if provider == "endpoints" && name == "AXEndTextMarker" { return last }
                return nil
            }
            reader.parameter = { name, argument in
                if provider == "element" && name == "AXTextMarkerRangeForUIElement" {
                    precondition(CFEqual(argument, element))
                    return whole
                }
                if provider == "line" && name == "AXLineTextMarkerRangeForTextMarker" { return whole }
                guard name == "AXStringForTextMarkerRange", CFGetTypeID(argument) == AXTextMarkerRangeGetTypeID() else { return nil }
                let span = argument as! AXTextMarkerRange
                let a = AXTextMarkerRangeCopyStartMarker(span), b = AXTextMarkerRangeCopyEndMarker(span)
                if CFEqual(a, first) && CFEqual(b, start) { return "Invoice reference: " as CFString }
                if CFEqual(a, end) && CFEqual(b, last) { return ", thanks" as CFString }
                if CFEqual(a, start) && CFEqual(b, end) { return "old reference" as CFString }
                return nil
            }
            let context = InsertionContext.collectTextMarkers(element, reader: reader)
            precondition(!askedInvalidAttribute)
            if provider == "missing" { precondition(context == nil) }
            else {
                precondition(context?.before == "Invoice reference: ")
                precondition(context?.after == ", thanks")
                precondition(context?.replacing == "old reference" && context?.isReplacement == true)
            }
        }
        print("PASS: real marker adapter queries parameterized element extent, line ranges or endpoints; missing extent does not fabricate context")
    }
}
