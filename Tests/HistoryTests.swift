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
        precondition(History.shouldIgnore(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]))
        precondition(History.shouldIgnore(types: ["com.agilebits.onepassword.internal"]))
        precondition(!History.shouldIgnore(types: ["public.utf8-plain-text"]))
        let now = Date()
        let lease = PasteLease(clipboardVersion: 8, createdAt: now)
        precondition(lease.valid(clipboardVersion: 8, now: now.addingTimeInterval(29)))
        precondition(!lease.valid(clipboardVersion: 9, now: now))
        precondition(!lease.valid(clipboardVersion: 8, now: now.addingTimeInterval(30)))
        history.clear()
        precondition(history.items.isEmpty && history.bytes == 0)
        print("PASS: count/byte/item caps, Unicode bytes, dedup, ignore markers, clear, clipboard race and expiry")
    }
}
