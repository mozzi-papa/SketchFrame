import AppKit

final class FixtureDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: CGRect(x: 140, y: 180, width: 900, height: 480),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "윈도우스케치 검증용 창"
        window.minSize = CGSize(width: 799, height: 300)
        window.delegate = self
        window.isReleasedWhenClosed = false
        let label = NSTextField(labelWithString: "자유 그리기·크기 지원 안내·취소·복원 검증용 창입니다.")
        label.frame = CGRect(x: 24, y: 120, width: 650, height: 30)
        window.contentView?.addSubview(label)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = FixtureDelegate()
app.setActivationPolicy(.regular)
app.delegate = delegate
app.run()
withExtendedLifetime(delegate) {}
