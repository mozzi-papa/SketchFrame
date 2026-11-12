import AppKit

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let settings: ShortcutSettings
    private let updater: AppUpdater?
    var onCheckUpdates: (() -> Void)?
    var onInstallUpdate: (() -> Void)?
    private let onRecordingChanged: (Bool) -> Void
    private var recorders: [ShortcutRecorderView] = []
    private weak var activeRecorder: ShortcutRecorderView?
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let conflictLabel = NSTextField(wrappingLabelWithString: "")
    private let updateLabel = NSTextField(labelWithString: "")
    private let updateButton = NSButton(title: "업데이트 확인…", target: nil, action: nil)

    init(settings: ShortcutSettings, updater: AppUpdater? = nil, onRecordingChanged: @escaping (Bool) -> Void) {
        self.settings = settings
        self.updater = updater
        self.onRecordingChanged = onRecordingChanged
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 624),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "SketchFrame 설정"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 760, height: 524)
        super.init(window: window)
        window.delegate = self
        buildContent()
        refresh()
        window.center()
    }

    required init?(coder: NSCoder) { nil }

    func refresh() {
        recorders.forEach { $0.refresh() }
        if activeRecorder?.isRecording != true { showMessage(settings.loadWarning) }
        let rectangleIsRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.knollsoft.Rectangle").isEmpty
        conflictLabel.stringValue = rectangleIsRunning
            ? "Rectangle이 실행 중입니다. 같은 단축키가 겹칠 수 있으니 한쪽 설정을 변경해 주세요."
            : "창 배치 단축키는 Command 또는 Control을 포함해 주세요."
        refreshUpdates()
    }

    func refreshUpdates() {
        updateLabel.stringValue = updater?.status ?? "업데이트를 자동으로 확인합니다."
        updateLabel.toolTip = updateLabel.stringValue
        updateButton.title = updater?.installing == true ? "다운로드·검증 중…" :
            updater?.checking == true ? "업데이트 확인 중…" : updater?.available != nil ? "지금 업데이트…" : "업데이트 확인…"
        updateButton.isEnabled = updater != nil && updater?.checking != true && updater?.installing != true
        updateLabel.textColor = updater?.available == nil ? .secondaryLabelColor : .systemBlue
    }

    @objc private func updateAction() {
        cancelRecording()
        if updater?.available != nil { onInstallUpdate?() } else { onCheckUpdates?() }
    }

    func windowWillClose(_ notification: Notification) { cancelRecording() }
    func windowDidResignKey(_ notification: Notification) { cancelRecording() }

    private func cancelRecording() {
        activeRecorder?.cancelRecording()
        activeRecorder = nil
        showMessage(settings.loadWarning)
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }
        let heading = NSTextField(labelWithString: "창 배치 단축키")
        heading.font = .systemFont(ofSize: 17, weight: .semibold)
        let drawRow = makeRow(.drawRegion)
        let separator = NSBox()
        separator.boxType = .separator

        let columns = NSStackView(views: [makeColumn(WindowAction.leftColumn), makeColumn(WindowAction.rightColumn)])
        columns.distribution = .fillEqually
        columns.alignment = .top
        columns.spacing = 32
        columns.translatesAutoresizingMaskIntoConstraints = false
        let document = ShortcutListDocumentView()
        document.addSubview(columns)
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = document
        document.translatesAutoresizingMaskIntoConstraints = false
        let fittingWidth = document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
        fittingWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            document.widthAnchor.constraint(greaterThanOrEqualToConstant: 704), fittingWidth,
            columns.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            columns.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            columns.topAnchor.constraint(equalTo: document.topAnchor, constant: 3),
            columns.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -3)
        ])

        messageLabel.font = .systemFont(ofSize: 11)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.setAccessibilityLabel("단축키 안내")
        conflictLabel.font = .systemFont(ofSize: 11)
        conflictLabel.textColor = .secondaryLabelColor
        let reset = NSButton(title: "전체 기본값 복원", target: self, action: #selector(resetBindings))
        reset.bezelStyle = .rounded
        reset.toolTip = "모든 단축키를 기본값으로 되돌립니다."
        let footer = NSView()
        for view in [conflictLabel, reset] {
            view.translatesAutoresizingMaskIntoConstraints = false
            footer.addSubview(view)
        }
        NSLayoutConstraint.activate([
            footer.heightAnchor.constraint(equalToConstant: 32),
            conflictLabel.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            conflictLabel.trailingAnchor.constraint(equalTo: reset.leadingAnchor, constant: -16),
            conflictLabel.topAnchor.constraint(equalTo: footer.topAnchor),
            conflictLabel.bottomAnchor.constraint(equalTo: footer.bottomAnchor),
            reset.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            reset.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            reset.widthAnchor.constraint(equalToConstant: 136),
            reset.heightAnchor.constraint(equalToConstant: 28)
        ])

        let updateSeparator = NSBox()
        updateSeparator.boxType = .separator
        let version = NSTextField(labelWithString: AppUpdater.versionLabel)
        version.font = .systemFont(ofSize: 11, weight: .medium)
        updateLabel.font = .systemFont(ofSize: 11)
        updateLabel.lineBreakMode = .byTruncatingTail
        updateLabel.setAccessibilityLabel("업데이트 상태")
        updateButton.bezelStyle = .rounded
        updateButton.target = self
        updateButton.action = #selector(updateAction)
        let updateRow = NSView()
        for view in [version, updateLabel, updateButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            updateRow.addSubview(view)
        }
        NSLayoutConstraint.activate([
            updateRow.heightAnchor.constraint(equalToConstant: 40),
            version.leadingAnchor.constraint(equalTo: updateRow.leadingAnchor),
            version.topAnchor.constraint(equalTo: updateRow.topAnchor),
            version.trailingAnchor.constraint(equalTo: updateButton.leadingAnchor, constant: -16),
            version.heightAnchor.constraint(equalToConstant: 16),
            updateLabel.leadingAnchor.constraint(equalTo: version.leadingAnchor),
            updateLabel.trailingAnchor.constraint(equalTo: version.trailingAnchor),
            updateLabel.topAnchor.constraint(equalTo: version.bottomAnchor, constant: 4),
            updateLabel.heightAnchor.constraint(equalToConstant: 16),
            updateButton.trailingAnchor.constraint(equalTo: updateRow.trailingAnchor),
            updateButton.centerYAnchor.constraint(equalTo: updateRow.centerYAnchor),
            updateButton.widthAnchor.constraint(equalToConstant: 136),
            updateButton.heightAnchor.constraint(equalToConstant: 28)
        ])

        for view in [heading, drawRow, separator, scroll, messageLabel, footer, updateSeparator, updateRow] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            heading.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            heading.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            drawRow.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 16),
            drawRow.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            drawRow.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            separator.topAnchor.constraint(equalTo: drawRow.bottomAnchor, constant: 12),
            separator.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: drawRow.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: drawRow.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: messageLabel.topAnchor, constant: -12),
            messageLabel.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            messageLabel.trailingAnchor.constraint(equalTo: drawRow.trailingAnchor),
            messageLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 28),
            messageLabel.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -8),
            footer.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: drawRow.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: updateSeparator.topAnchor, constant: -12),
            updateSeparator.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            updateSeparator.trailingAnchor.constraint(equalTo: drawRow.trailingAnchor),
            updateRow.topAnchor.constraint(equalTo: updateSeparator.bottomAnchor, constant: 12),
            updateRow.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            updateRow.trailingAnchor.constraint(equalTo: drawRow.trailingAnchor),
            updateRow.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16)
        ])
    }

    private func makeColumn(_ actions: [WindowAction]) -> NSStackView {
        let column = NSStackView(views: actions.map(makeRow))
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 4
        for row in column.arrangedSubviews {
            row.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        }
        return column
    }

    private func makeRow(_ action: WindowAction) -> NSView {
        let icon = PlacementThumbnail(action: action)
        let title = NSTextField(labelWithString: action.title)
        title.font = .systemFont(ofSize: 12)
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let recorder = ShortcutRecorderView(action: action, settings: settings)
        recorder.onBegin = { [weak self] recorder in
            self?.activeRecorder?.cancelRecording()
            self?.activeRecorder = recorder
        }
        recorder.onRecordingChanged = { [weak self] recording in self?.onRecordingChanged(recording) }
        recorder.onCommitted = { [weak self] in self?.refresh() }
        recorder.onMessage = { [weak self] message in self?.showMessage(message) }
        recorders.append(recorder)
        let row = NSView()
        for view in [icon, title, recorder] {
            view.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 28),
            icon.heightAnchor.constraint(equalToConstant: 24),
            icon.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            icon.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            title.trailingAnchor.constraint(equalTo: recorder.leadingAnchor, constant: -12),
            title.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            recorder.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            recorder.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            row.heightAnchor.constraint(equalToConstant: 34)
        ])
        return row
    }

    private func showMessage(_ message: String?) {
        messageLabel.stringValue = message ?? "단축키를 선택하여 변경하세요. Escape로 입력을 취소하고 Delete로 해제할 수 있습니다."
        messageLabel.textColor = message == nil || activeRecorder?.isRecording == true ? .secondaryLabelColor : .systemRed
        messageLabel.toolTip = messageLabel.stringValue
    }

    @objc private func resetBindings() {
        cancelRecording()
        settings.reset()
        refresh()
    }
}

private final class ShortcutListDocumentView: NSView {
    override var isFlipped: Bool { true }
}

private final class PlacementThumbnail: NSView {
    private let action: WindowAction
    init(action: WindowAction) {
        self.action = action
        super.init(frame: .zero)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let screen = NSRect(x: 2.5, y: 4.5, width: 23, height: 16)
        NSColor.tertiaryLabelColor.setStroke()
        let outline = NSBezierPath(roundedRect: screen, xRadius: 2, yRadius: 2)
        outline.lineWidth = 1
        outline.stroke()
        let interior = screen.insetBy(dx: 2, dy: 2)
        var region = interior
        switch action {
        case .leftHalf: region.size.width /= 2
        case .rightHalf: region.origin.x += interior.width / 2; region.size.width /= 2
        case .centerHalf: region.origin.x += interior.width / 4; region.size.width /= 2
        case .topHalf: region.origin.y += interior.height / 2; region.size.height /= 2
        case .bottomHalf: region.size.height /= 2
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            region.size = NSSize(width: interior.width / 2, height: interior.height / 2)
            if action == .topLeft || action == .topRight { region.origin.y += interior.height / 2 }
            if action == .topRight || action == .bottomRight { region.origin.x += interior.width / 2 }
        case .almostMaximize: region = interior.insetBy(dx: 2, dy: 1)
        case .maximizeHeight: region = interior.insetBy(dx: 5, dy: 0)
        case .smaller, .center, .restore: region = interior.insetBy(dx: 5, dy: 3)
        case .larger: region = interior.insetBy(dx: 2, dy: 1)
        case .drawRegion: region = NSRect(x: 7, y: 7, width: 12, height: 9)
        case .nextDisplay, .previousDisplay:
            let direction: CGFloat = action == .nextDisplay ? 1 : -1
            let arrow = NSBezierPath()
            arrow.move(to: NSPoint(x: 14 - 6 * direction, y: 12.5))
            arrow.line(to: NSPoint(x: 14 + 6 * direction, y: 12.5))
            arrow.move(to: NSPoint(x: 14 + 2 * direction, y: 16))
            arrow.line(to: NSPoint(x: 14 + 6 * direction, y: 12.5))
            arrow.line(to: NSPoint(x: 14 + 2 * direction, y: 9))
            NSColor.labelColor.setStroke()
            arrow.lineWidth = 1.3
            arrow.stroke()
            return
        case .maximize: break
        }
        NSColor.secondaryLabelColor.setFill()
        NSBezierPath(roundedRect: region, xRadius: 0.5, yRadius: 0.5).fill()
    }
}
