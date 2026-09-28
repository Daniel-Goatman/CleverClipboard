import Foundation

@main struct HistoryTests {
    static func main() {
        var history = History()
        for i in 0..<70 { history.add("entry \(i)", app: "Test") }
        precondition(history.items.count == 50)
        precondition(history.items.first?.text == "entry 69")
        precondition(history.items.last?.text == "entry 20")
        history.add("entry 30", app: "Test")
        precondition(history.items.count == 50 && history.items.first?.text == "entry 30")
        precondition(!history.add(String(repeating: "💡", count: 70_000), app: "Test"))
        precondition(!history.add(" \n\t", app: "Test"))
        history.clear()
        for i in 0..<50 { history.add(String(repeating: "x", count: 256 * 1024 - 4) + "\(i)", app: "Test") }
        precondition(history.bytes <= History.maximumBytes)
        precondition(history.items.count == 50)
        for _ in 0..<7 { precondition(history.addImage(id: UUID().uuidString, dataCount: 20 * 1024 * 1024, type: "public.png", app: "Screenshot")) }
        precondition(history.bytes <= History.maximumBytes && history.items.count == 6)
        var race = History()
        precondition(race.addImage(id: "same", dataCount: 100, type: "public.png", app: "Fixture"))
        let oldRevision = race.items[0].imageRevision!
        precondition(race.items[0].ocrStatus == .pending && race.items[0].candidateText == "Image OCR pending")
        let ready = OCRResult(status: .ready, blocks: [OCRBlock(text: "Total $12", confidence: 0.4,
            x: 0.7, y: 0.8, width: 0.2, height: 0.1)], truncated: false)
        precondition(race.delete(id: "same"))
        precondition(!race.updateOCR(id: "same", imageRevision: oldRevision, result: ready))
        precondition(race.addImage(id: "same", dataCount: 101, type: "public.png", app: "Fixture"))
        var resumed = History()
        resumed.restore(race.items)
        precondition(resumed.items[0].ocrStatus == .failed && resumed.items[0].candidateText == "Image OCR failed")
        precondition(!race.updateOCR(id: "same", imageRevision: oldRevision, result: ready))
        precondition(race.items[0].ocrStatus == .pending && race.items[0].ocrBlocks.isEmpty)
        let newRevision = race.items[0].imageRevision!
        precondition(race.updateOCR(id: "same", imageRevision: newRevision, result: ready))
        precondition(race.items[0].ocrStatus == .ready && race.items[0].candidateText.contains("confidence 0.40"))
        precondition(!race.updateOCR(id: "same", imageRevision: newRevision, result: ready))
        let encoded = try! JSONEncoder().encode(race.items[0])
        let decoded = try! JSONDecoder().decode(Clip.self, from: encoded)
        precondition(decoded.ocrBlocks == ready.blocks && decoded.imageRevision == newRevision)
        let legacy = #"{"id":"old","text":"","app":"Fixture","copiedAt":0,"kind":"image","imageBytes":12,"ocrText":"Old total"}"#
        let old = try! JSONDecoder().decode(Clip.self, from: Data(legacy.utf8))
        precondition(old.ocrStatus == .unknown && old.candidateText.contains("legacy"))
        precondition(History.shouldIgnore(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]))
        precondition(History.shouldIgnore(types: ["com.agilebits.onepassword.internal"]))
        precondition(!History.shouldIgnore(types: ["public.utf8-plain-text"]))
        let copied = Date()
        var foreground = CopyForegroundGate()
        foreground.observePoll(pid: 101)
        precondition(foreground.allows(eventAt: 10.0, callbackAt: 10.05, pid: 101))
        precondition(!foreground.allows(eventAt: 10.0, callbackAt: 10.05, pid: 202),
                     "A switch before the asynchronous callback must be unknown")
        foreground.activated(at: 10.03)
        precondition(!foreground.allows(eventAt: 10.0, callbackAt: 10.05, pid: 101),
                     "A recorded activation during callback delivery must be unknown")
        foreground.observePoll(pid: 202)
        precondition(foreground.allows(eventAt: 10.1, callbackAt: 10.15, pid: 202))
        // A switch after the callback and before the pasteboard poll does not
        // erase the already observed source app.
        foreground.activated(at: 10.2)
        precondition(foreground.allows(eventAt: 10.1, callbackAt: 10.15, pid: 202))
        precondition(!foreground.allows(eventAt: 10.1, callbackAt: 10.25, pid: 202))
        func observed(_ app: String, _ bundle: String, _ label: String?, _ selection: String?) -> CopyObservation {
            CopyObservation(app: app, bundleID: bundle, at: copied, pasteboardChange: 10,
                            windowTitle: "Quarterly report", fieldLabel: label,
                            fieldIdentifier: label.map { "field-" + $0 }, selectedText: selection)
        }
        func source(_ observation: CopyObservation?, _ payload: String = "1200",
                    _ declared: String? = nil, _ delay: TimeInterval = 0.2) -> ClipProvenance {
            ClipProvenance.resolve(observation: observation, changedAt: copied.addingTimeInterval(delay),
                changeCount: 11, foreground: "Mail", declaredSource: declared, payload: payload)
        }
        let safari = source(observed("Safari", "com.apple.Safari", "Revenue", "1200"))
        precondition(safari.sourceApp == "Safari" && safari.foregroundAtPoll == "Mail")
        precondition(safari.fieldLabel == "Revenue" && safari.association == "keyboard_copy")
        let observedAfterWrite = ClipProvenance.resolve(
            observation: CopyObservation(app: "Safari", bundleID: "com.apple.Safari", at: copied,
                pasteboardChange: 11, windowTitle: "Quarterly report", fieldLabel: "Revenue",
                fieldIdentifier: "field-Revenue",
                selectedText: "1200"), changedAt: copied.addingTimeInterval(0.2),
            changeCount: 11, foreground: "Mail", declaredSource: nil, payload: "1200")
        precondition(observedAfterWrite.sourceApp == "Safari")
        precondition(source(nil).sourceApp == nil) // Menu or background copy.
        precondition(source(observed("Safari", "com.apple.Safari", nil, nil), "1200", nil, 1.2).sourceApp == nil)
        precondition(source(observed("Safari", "com.apple.Safari", "Revenue", "1200"),
                            "1200", "com.apple.Mail").sourceApp == nil)
        precondition(source(observed("Safari", "com.apple.Safari", "Revenue", "1200"),
                            "different").fieldLabel == nil)
        precondition(source(observed("Safari", "com.apple.Safari", "Revenue", nil)).fieldLabel == nil)
        precondition(source(observed("Safari", "com.apple.Safari", "Revenue", "1200"),
                            "1200", "com.apple.Safari").fieldLabel == "Revenue")
        let restoredCopy = ClipProvenance.ownWrite(original: safari)
        precondition(restoredCopy.writer == "CleverClipboard" && restoredCopy.sourceApp == "Safari")
        precondition(restoredCopy.fieldLabel == nil && restoredCopy.association == "own_write")
        var occurrences = History()
        precondition(occurrences.add("1200", app: "Safari", provenance: safari))
        let firstOccurrenceID = occurrences.items[0].id
        precondition(occurrences.add("1200", app: "Safari", provenance: safari))
        precondition(occurrences.items.count == 1 && occurrences.items[0].id == firstOccurrenceID)
        // A second provider field can have the same visible label.
        let sameLabel = ClipProvenance(sourceApp: safari.sourceApp, sourceBundleID: safari.sourceBundleID,
            writer: nil, foregroundAtPoll: "Mail", association: "keyboard_copy",
            windowTitle: safari.windowTitle, fieldLabel: safari.fieldLabel,
            fieldIdentifier: "another-revenue-field", declaredSource: nil)
        occurrences.add("1200", app: "Safari", provenance: sameLabel)
        precondition(occurrences.items.count == 2)
        let noIdentifier = ClipProvenance(sourceApp: safari.sourceApp,
            sourceBundleID: safari.sourceBundleID, writer: nil, foregroundAtPoll: "Mail",
            association: "keyboard_copy", windowTitle: safari.windowTitle,
            fieldLabel: safari.fieldLabel, fieldIdentifier: nil, declaredSource: nil)
        occurrences.add("1200", app: "Safari", provenance: noIdentifier)
        occurrences.add("1200", app: "Safari", provenance: noIdentifier)
        precondition(occurrences.items.count == 4)
        let deposit = source(observed("Safari", "com.apple.Safari", "Deposit", "1200"))
        occurrences.add("1200", app: "Safari", provenance: deposit)
        precondition(occurrences.items.count == 5)
        let notes = source(observed("Notes", "com.apple.Notes", "Revenue", "1200"))
        occurrences.add("1200", app: "Notes", provenance: notes)
        occurrences.add("1200", app: "Unknown source", provenance: source(nil))
        occurrences.add("1200", app: "Unknown source", provenance: source(nil))
        precondition(occurrences.items.count == 8)
        let grouped = ClipboardSelection.candidates(history: occurrences, pins: [])
        precondition(grouped.count == 1)
        precondition(grouped[0].candidateSourceContext?.contains("Revenue") == true)
        precondition(grouped[0].candidateSourceContext?.contains("Deposit") == true)
        let now = Date()
        let lease = PasteLease(clipboardVersion: 8, createdAt: now)
        precondition(lease.valid(clipboardVersion: 8, now: now.addingTimeInterval(29)))
        precondition(!lease.valid(clipboardVersion: 9, now: now))
        precondition(!lease.valid(clipboardVersion: 8, now: now.addingTimeInterval(30)))
        history.clear()
        precondition(history.items.isEmpty && history.bytes == 0)
        print("PASS: history caps, OCR states and revisions, legacy decode, clipboard race and expiry")
    }
}
