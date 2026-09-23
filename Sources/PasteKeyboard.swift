import CoreGraphics
import Carbon

struct ShortcutLatch {
    private var down = false
    mutating func press() -> Bool {
        guard !down else { return false }
        down = true
        return true
    }
    mutating func release(vIsDown: Bool = false) { if !vIsDown { down = false } }
}

/// Build the entire balanced chord before changing the clipboard or posting anything.
enum PasteKeyboard {
    static let marker: Int64 = 0x4C415941

    static func physicalVDown() -> Bool {
        CGEventSource.keyState(.hidSystemState, key: CGKeyCode(kVK_ANSI_V))
    }

    static func events(heldFlags: CGEventFlags = CGEventSource.flagsState(.hidSystemState)) -> [CGEvent]? {
        guard let source = CGEventSource(stateID: .privateState) else { return nil }
        let modifiers: [(Int, CGEventFlags)] = [
            (kVK_Shift, .maskShift), (kVK_Option, .maskAlternate),
            (kVK_Control, .maskControl), (kVK_Command, .maskCommand)
        ]
        var steps: [(Int, Bool, CGEventType, CGEventFlags)] = []
        var flags = heldFlags.intersection([.maskShift, .maskAlternate, .maskControl, .maskCommand, .maskAlphaShift])
        // Temporarily neutralise held modifiers only in the verified destination.
        // Never synthesize another V-down when restoring the user's held state.
        for (key, flag) in modifiers where flags.contains(flag) {
            flags.remove(flag)
            steps.append((key, false, .flagsChanged, flags))
        }
        let neutral = flags
        steps += [
            (kVK_Command, true, .flagsChanged, neutral.union(.maskCommand)),
            (kVK_ANSI_V, true, .keyDown, neutral.union(.maskCommand)),
            (kVK_ANSI_V, false, .keyUp, neutral.union(.maskCommand)),
            (kVK_Command, false, .flagsChanged, neutral)
        ]
        for (key, flag) in modifiers where heldFlags.contains(flag) {
            flags.insert(flag)
            steps.append((key, true, .flagsChanged, flags))
        }
        var events: [CGEvent] = []
        for (key, down, type, flags) in steps {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key), keyDown: down) else { return nil }
            event.type = type
            event.flags = flags
            event.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
            event.setIntegerValueField(.eventSourceUserData, value: marker)
            events.append(event)
        }
        return events
    }
}
