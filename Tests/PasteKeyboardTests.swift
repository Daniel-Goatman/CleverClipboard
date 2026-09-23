import Foundation
import CoreGraphics
import Carbon

@main struct PasteKeyboardTests {
    static func main() {
        var latch = ShortcutLatch()
        precondition(latch.press())
        for _ in 0..<10 { precondition(!latch.press(), "Repeat must not start another request") }
        latch.release()
        precondition(latch.press(), "A new press after release must still work")
        latch.release(); latch.release()
        precondition(latch.press())

        guard let events = PasteKeyboard.events(heldFlags: []) else { fatalError("Could not build event sequence") }
        precondition(events.count == 4)
        precondition(events.map(\.type) == [.flagsChanged, .keyDown, .keyUp, .flagsChanged])
        precondition(events.map { $0.getIntegerValueField(.keyboardEventKeycode) } == [55, 9, 9, 55])
        precondition(events.map(\.flags) == [.maskCommand, .maskCommand, .maskCommand, []])
        precondition(events.allSatisfy { $0.getIntegerValueField(.keyboardEventAutorepeat) == 0 })
        precondition(events.allSatisfy { $0.getIntegerValueField(.eventSourceUserData) == PasteKeyboard.marker })
        // A destination tracking command state must see one paste key-down and finish released.
        var command = false
        var vDown = false
        var pasteCount = 0
        for event in events {
            command = event.flags.contains(.maskCommand)
            if event.type == .keyDown {
                precondition(!vDown)
                vDown = true
                if command { pasteCount += 1 }
            } else if event.type == .keyUp { vDown = false }
        }
        precondition(pasteCount == 1 && !command && !vDown)
        latch.release(vIsDown: true)
        precondition(!latch.press(), "Modifier release or synthetic key-up must not rearm held V")
        latch.release(vIsDown: false)
        precondition(latch.press(), "V release rearms even when modifiers stay down")
        // Exercise every modifier combination. Only one V down/up is emitted;
        // Shift/Option/Control cannot leak into paste, then physical flags return.
        let masks: [CGEventFlags] = [.maskCommand, .maskShift, .maskAlternate, .maskControl, .maskAlphaShift]
        for bits in 0..<32 {
            var held = CGEventFlags()
            for i in 0..<5 where bits & (1 << i) != 0 { held.insert(masks[i]) }
            let chord = PasteKeyboard.events(heldFlags: held)!
            let keys = chord.filter { $0.type == .keyDown || $0.type == .keyUp }
            precondition(keys.count == 2 && keys[0].type == .keyDown && keys[1].type == .keyUp)
            precondition(keys.allSatisfy { $0.getIntegerValueField(.keyboardEventKeycode) == 9 })
            precondition(keys.allSatisfy { $0.flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl]) == .maskCommand })
            precondition(chord.last!.flags == held)
            precondition(chord.allSatisfy { $0.getIntegerValueField(.keyboardEventAutorepeat) == 0 })
        }
        print("PASS: one paste across 32 held-modifier states, flag restoration, physical V rearming")
    }
}
