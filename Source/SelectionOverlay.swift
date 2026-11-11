import AppKit

final class SelectionView: NSView {
    override var isFlipped: Bool { true }
    var selection = CGRect.zero
    var applicationName = ""
    var pixelScale: CGFloat = 1
    var errorMessage: String?
    var warningMessage: String?
    var completed = false
    private let labelFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)

    override func accessibilityFrame() -> NSRect {
        guard let window = window else { return .zero }
        return window.convertToScreen(convert(selection, to: nil))
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.06).setFill()
        bounds.fill()
        let hasWarning = errorMessage != nil || warningMessage != nil
        let color = hasWarning ? NSColor.systemRed : NSColor.systemBlue
        color.withAlphaComponent(0.19).setFill()
        selection.fill()
        if selection.width > 2 && selection.height > 2 {
            color.setStroke()
            let outline = NSBezierPath(rect: selection.insetBy(dx: 1, dy: 1))
            outline.lineWidth = 2
            outline.stroke()
        }

        let detail = errorMessage ?? "\(warningMessage ?? "놓은 뒤 지원 여부를 확인합니다")\(completed ? "" : " · Esc 취소")"
        let text = completed ? "\(applicationName) · \(detail)" :
            "\(applicationName) · \(SelectionGeometry.pixelSizeLabel(selection.size, scale: pixelScale)) · \(detail)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: NSColor.white
        ]
        let textSize = (text as NSString).boundingRect(with: CGSize(width: bounds.width - 40, height: .greatestFiniteMagnitude),
                                                     options: .usesLineFragmentOrigin, attributes: attributes).size
        let width = min(ceil(textSize.width) + 24, bounds.width - 16)
        let height = ceil(textSize.height) + 12
        let label = CGRect(x: min(max(selection.minX, 8), bounds.width - width - 8),
                           y: min(max(selection.minY - height - 8, 8), bounds.height - height - 8),
                           width: width, height: height)
        (hasWarning ? NSColor.systemRed : NSColor.black.withAlphaComponent(0.82)).setFill()
        NSBezierPath(roundedRect: label, xRadius: 7, yRadius: 7).fill()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        var labelAttributes = attributes
        labelAttributes[.paragraphStyle] = paragraph
        (text as NSString).draw(in: label.insetBy(dx: 12, dy: 6), withAttributes: labelAttributes)
    }
}

final class SelectionOverlay {
    private var panel: NSPanel?
    private var view: SelectionView?
    private var screenOrigin = CGPoint.zero

    func prepare(on screen: NSScreen) {
        guard panel == nil else { return }
        let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.setFrame(screen.frame, display: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.group)
        view.setAccessibilityLabel("선택 영역 미리보기")
        panel.contentView = view
        self.view = view
        self.panel = panel
        let sample = CGRect(x: 0, y: 0, width: 2, height: 2)
        if let bitmap = view.bitmapImageRepForCachingDisplay(in: sample) {
            view.cacheDisplay(in: sample, to: bitmap)
        }
    }

    func show(on screen: NSScreen, quartzFrame: CGRect, name: String) {
        prepare(on: screen)
        panel?.setFrame(screen.frame, display: false)
        view?.frame = CGRect(origin: .zero, size: screen.frame.size)
        view?.applicationName = name
        view?.pixelScale = screen.backingScaleFactor
        screenOrigin = quartzFrame.origin
        panel?.orderFrontRegardless()
    }

    func update(_ rectangle: CGRect, error: String? = nil, warning: String? = nil, completed: Bool = false) {
        view?.errorMessage = error
        view?.warningMessage = warning
        view?.completed = completed
        let size = SelectionGeometry.pixelSizeLabel(rectangle.size, scale: view?.pixelScale ?? 1)
        let detail = error.map { "오류: " + $0 } ?? warning.map { "경고: " + $0 } ?? "놓은 뒤 지원 여부를 확인합니다"
        view?.setAccessibilityValue("\(size) · 자유 그리기 · \(detail)")
        view?.selection = rectangle.offsetBy(dx: -screenOrigin.x, dy: -screenOrigin.y)
        view?.needsDisplay = true
    }

    func hide() {
        panel?.orderOut(nil)
    }
}
