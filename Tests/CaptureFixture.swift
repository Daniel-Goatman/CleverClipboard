import AppKit
import WebKit

final class CaptureFixtureDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    var window: NSWindow!
    var web: WKWebView?
    let sample = "Earlier context belongs to another task.\nSynthetic reference:  for this request."

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 180, y: 180, width: 720, height: 360),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Jev Capture Fixture — synthetic text only"
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if CommandLine.arguments.contains("--native") {
            let text = NSTextView(frame: window.contentView!.bounds)
            text.autoresizingMask = [.width, .height]
            text.isRichText = false
            text.font = .systemFont(ofSize: 20)
            text.string = sample
            text.setSelectedRange(NSRange(location: (sample as NSString).range(of: " for this request.").location, length: 0))
            window.contentView = text
            window.makeFirstResponder(text)
        } else {
            let view = WKWebView(frame: window.contentView!.bounds)
            view.autoresizingMask = [.width, .height]
            view.navigationDelegate = self
            window.contentView = view
            web = view
            view.loadHTMLString("<html><body style='font:20px system-ui'><div id='editor' contenteditable='true' style='white-space:pre-wrap;min-height:200px'>\(sample)</div></body></html>", baseURL: nil)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(webView)
        webView.evaluateJavaScript("""
            const editor = document.getElementById('editor');
            editor.focus();
            const range = document.createRange();
            range.setStart(editor.firstChild, editor.textContent.indexOf(' for this request.'));
            range.collapse(true);
            const selection = window.getSelection();
            selection.removeAllRanges(); selection.addRange(range);
            [editor.textContent.length, selection.anchorOffset, document.hasFocus()];
            """) { result, error in
                let report = "frame=\(webView.frame) result=\(String(describing: result)) error=\(String(describing: error))"
                try? report.write(toFile: "/tmp/jev-fixture-state.txt", atomically: true, encoding: .utf8)
            }
    }
}

let application = NSApplication.shared
let delegate = CaptureFixtureDelegate()
application.setActivationPolicy(.regular)
application.delegate = delegate
withExtendedLifetime(delegate) { application.run() }
