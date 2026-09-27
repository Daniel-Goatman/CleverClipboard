import Foundation

/// Turns captured facts into model evidence. No clipboard values or selection policy live here.
enum DestinationContext {
    typealias Object = [String: Any]
    static let generic: Set<String> = ["", "text", "text field", "text area", "input", "edit", "editor", "rich text editor", "search", "message", "message body", "message content", "email body", "mail body", "reply", "notes", "description", "comment", "write a message", "type here", "enter text", "the focused editable field", "form", "group", "content", "web content", "document", "body", "composer", "cell"]
    private static let browsers: Set<String> = ["com.apple.Safari", "com.google.Chrome", "com.microsoft.edgemac", "org.mozilla.firefox", "com.brave.Browser"]

    static func clean(_ value: Any?, limit: Int = 240) -> String {
        guard let value = value as? String else { return "" }
        return String(value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").prefix(limit))
    }
    static func meaningful(_ value: String) -> Bool {
        !generic.contains(clean(value).lowercased().replacingOccurrences(of: ":+$", with: "", options: .regularExpression))
    }
    static func clip(_ text: String, _ limit: Int, tail: Bool = false) -> String {
        InsertionContext.excerpt(text[...], bytes: limit, suffix: tail)
    }
    private static func box(_ value: Any?) -> [Double]? {
        guard let numbers = value as? [Double], numbers.count == 4,
              numbers.allSatisfy(\.isFinite), numbers[2] > 0, numbers[3] > 0 else { return nil }
        return numbers
    }
    private static func spatialScore(_ target: Any?, _ node: Object, _ barriers: [[Double]]) -> Double? {
        guard let a = box(target), let b = box(node["bounds"]) else { return nil }
        let (x,y,w,h) = (a[0],a[1],a[2],a[3]), (nx,ny,nw,nh) = (b[0],b[1],b[2],b[3])
        let ox = max(0, min(x+w,nx+nw)-max(x,nx)), oy = max(0, min(y+h,ny+nh)-max(y,ny))
        let depth = node["depth"] as? Int ?? 0
        guard ox*oy == 0, depth <= 2 else { return nil }
        let distance: Double, path: [Double]
        if oy/min(h,nh) >= 0.45 && nx+nw <= x && x-nx-nw <= 240 {
            distance = (x-nx-nw)/240
            path = [nx+nw,max(y,ny),x-nx-nw,min(y+h,ny+nh)-max(y,ny)]
        } else if ox/min(w,nw) >= 0.5 && ny+nh <= y && y-ny-nh <= 90 {
            distance = (y-ny-nh)/90+0.08
            path = [max(x,nx),ny+nh,min(x+w,nx+nw)-max(x,nx),y-ny-nh]
        } else if oy/min(h,nh) >= 0.65 && nx >= x+w && nx-x-w <= 100 {
            distance = (nx-x-w)/100+0.2
            path = [x+w,max(y,ny),nx-x-w,min(y+h,ny+nh)-max(y,ny)]
        } else { return nil }
        for raw in barriers {
            if let b = box(raw), min(path[0]+path[2],b[0]+b[2]) > max(path[0],b[0]),
               min(path[1]+path[3],b[1]+b[3]) > max(path[1],b[1]) { return nil }
        }
        return 1-distance*0.5-Double(min(2,depth))*0.08
    }

    static func make(_ context: String) throws -> Object {
        var destination: Object = ["context_version": 3,
            "priority_order": ["insertion", "field", "document", "application"],
            "insertion": ["available": false], "field": Object(), "document": Object(), "application": Object()]
        guard context.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") else {
            destination["document"] = ["unanchored_context": clip(context, 1400)]
            return destination
        }
        guard let raw = try JSONSerialization.jsonObject(with: Data(context.utf8)) as? Object,
              raw["version"] as? Int == 2 else { throw ClipboardError.message("Invalid destination context. Nothing was sent.") }
        let field = raw["field"] as? Object ?? [:], attrs = field["attributes"] as? Object ?? [:]
        let ancestors = raw["ancestors"] as? [Object] ?? [], nearby = raw["nearby"] as? [Object] ?? []
        let ocr = raw["ocr"] as? [Object] ?? [], headings = raw["headings"] as? [Object] ?? []
        let barriers = raw["nearbyInputs"] as? [[Double]] ?? []
        let nodes = nearby+ocr
        var label = "", source = "missing", scope: [String] = [], state = "", help = ""
        var navigation = false, uncertain = true, competing: [String] = []
        if raw["destinationKind"] as? String == "window" {
            var visible: [String] = []
            for node in headings+nodes {
                if node["source"] as? String == "ocr", (node["confidence"] as? Double ?? 0) < 0.65 { continue }
                let text = clean(node["text"], limit: 160)
                if meaningful(text), !visible.contains(text) { visible.append(text) }
            }
            source = "window"
            state = "Window-level paste target; no focused editable field.\nApp: " + clean(raw["app"], limit: 80)
                + "\nWindow: " + clean(raw["windowTitle"], limit: 160)
            if !visible.isEmpty { state += "\nVisible context: " + visible.prefix(12).joined(separator: " | ") }
        } else {
            let linked = (field["linkedLabels"] as? [String] ?? []).map { ("linked_label", clean($0)) }
            let observed = linked + ["title", "description", "placeholder"].map { ($0, clean(attrs[$0])) }
            let direct = observed.first { meaningful($0.1) }
            (source,label) = direct ?? observed.first { !$0.1.isEmpty } ?? ("missing", "")
            if direct == nil {
                var unique: [String: (Double,String,String)] = [:]
                for node in nodes {
                    let text = clean(node["text"], limit: 160)
                    guard meaningful(text), text.count <= 120 else { continue }
                    if node["source"] as? String == "ocr", (node["confidence"] as? Double ?? 0) < 0.65 { continue }
                    guard let score = spatialScore(field["bounds"], node, barriers) else { continue }
                    if unique[text.lowercased()] == nil || score > unique[text.lowercased()]!.0 {
                        unique[text.lowercased()] = (score,text,node["source"] as? String ?? "ax")
                    }
                }
                let ranked = unique.values.sorted { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 > $1.0 }
                if let top = ranked.first, top.0 >= 0.68, ranked.count == 1 || top.0-ranked[1].0 >= 0.12 {
                    label = top.1; source = top.2 + ":spatial_label"
                } else { competing = ranked.prefix(2).map { $0.1 } }
            }
            let identifier = clean(field["identifier"])
            navigation = browsers.contains(raw["bundleID"] as? String ?? "")
                && ancestors.contains { clean($0["role"]) == "AXToolbar" }
                && (identifier.uppercased().contains("ADDRESS_AND_SEARCH")
                    || label.range(of: "\\b(address|smart search|location)\\b", options: [.regularExpression,.caseInsensitive]) != nil)
            for node in ancestors {
                let text = clean(node["text"], limit: 160)
                if meaningful(text), text != label, !scope.contains(text) { scope.append(text) }
            }
            if let b = box(field["bounds"]) {
                let sections: [(Int,Double,String)] = headings.compactMap { node in
                    let text = clean(node["text"], limit: 160)
                    guard let h = box(node["bounds"]), meaningful(text), text != label,
                          h[1]+h[3] <= b[1], h[0] <= b[0]+b[2], h[0]+h[2] >= b[0] else { return nil }
                    return (node["depth"] as? Int ?? 0, b[1]-h[1]-h[3], text)
                }.sorted { $0.0 != $1.0 ? $0.0 < $1.0 : ($0.1 != $1.1 ? $0.1 < $1.1 : $0.2 < $1.2) }
                if let section = sections.first?.2, !scope.contains(section) { scope.insert(section, at: 0) }
            }
            help = clean(attrs["help"], limit: 220)
            uncertain = !meaningful(label) || !competing.isEmpty
            var lines = ["Input: " + (label.isEmpty ? "unavailable" : label)]
            if !scope.isEmpty { lines.append("Section: " + scope.prefix(2).joined(separator: " / ")) }
            if !help.isEmpty { lines.append("Instructions: " + help) }
            if navigation { lines += ["Location: browser toolbar", "Purpose: Enter a website address or search the web.", "Accepted content: URL or search terms."] }
            else if direct == nil && !meaningful(label) { lines.append("App: " + clean(raw["app"], limit: 80)) }
            if !competing.isEmpty { lines.append("Unresolved nearby labels: " + competing.joined(separator: " | ")) }
            if raw["insertion"] as? Object == nil, let b = box(field["bounds"]) {
                var visible: [String] = []
                for node in ocr {
                    guard let n = box(node["bounds"]), (node["confidence"] as? Double ?? 0) >= 0.65,
                          b[0] <= n[0]+n[2]/2, n[0]+n[2]/2 <= b[0]+b[2],
                          b[1] <= n[1]+n[3]/2, n[1]+n[3]/2 <= b[1]+b[3] else { continue }
                    let text = clean(node["text"], limit: 120)
                    if meaningful(text), !visible.contains(text) { visible.append(text) }
                }
                if !visible.isEmpty { lines.append("Visible text in focused editor (caret location unavailable): " + String(visible.suffix(6).joined(separator: " | ").prefix(500))) }
            }
            if uncertain { lines.append("Field purpose: insufficient or ambiguous evidence") }
            state = lines.joined(separator: "\n")
        }
        var document: Object = [:]
        if let insertion = raw["insertion"] as? Object {
            guard let before = insertion["before"] as? String, let after = insertion["after"] as? String,
                  let replacing = insertion["replacing"] as? String, let replacement = insertion["isReplacement"] as? Bool,
                  let origin = insertion["source"] as? String,
                  ["ax_value_and_selected_text_range", "ax_text_marker_range"].contains(origin),
                  before.utf8.count <= 600, after.utf8.count <= 240, replacing.utf8.count <= 160 else {
                throw ClipboardError.message("Invalid destination insertion context. Nothing was sent.")
            }
            let localBefore = clip(before.components(separatedBy: "\n").last ?? "", 300, tail: true)
            let localAfter = clip(after.components(separatedBy: "\n").first ?? "", 160)
            destination["insertion"] = ["available": true, "source": origin, "before": localBefore,
                "after": localAfter, "replacing": replacing, "isReplacement": replacement]
            let earlier = String(before.unicodeScalars.dropLast(localBefore.unicodeScalars.count))
            let later = String(after.unicodeScalars.dropFirst(localAfter.unicodeScalars.count))
            if !earlier.isEmpty { document["earlier_text"] = clip(earlier, 300, tail: true) }
            if !later.isEmpty { document["later_text"] = clip(later, 160) }
        }
        var selectedField: Object = ["label": label, "label_source": source, "instructions": help,
            "ambiguous": !competing.isEmpty, "uncertain": uncertain, "destination_kind": raw["destinationKind"] ?? "editable"]
        if navigation { selectedField["location"] = "browser toolbar"; selectedField["purpose"] = "Enter a website address or search the web." }
        if !scope.isEmpty { document["section"] = clip(scope.prefix(2).joined(separator: " / "), 240) }
        if !state.isEmpty { document["unanchored_context"] = clip(String(state.prefix(1400)), 1000) }
        if raw["budgetExhausted"] as? Bool == true { document["capture_incomplete"] = true }
        destination["field"] = selectedField; destination["document"] = document
        destination["application"] = ["name": clip(raw["app"] as? String ?? "", 100), "window_title": clip(raw["windowTitle"] as? String ?? "", 160)]
        return destination
    }
}
