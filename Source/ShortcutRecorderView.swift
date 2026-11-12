import AppKit

final class ShortcutRecorderView: NSView {
    static func modifierCandidate(previous: UInt64, current: UInt64) -> UInt64 {
        current.nonzeroBitCount >= 2 && current.nonzeroBitCount >= previous.nonzeroBitCount ? current : previous
    }
    let action: WindowAction
    var onBegin: ((ShortcutRecorderView) -> Void)?
    var onRecordingChanged: ((Bool) -> Void)?
    var onCommitted: (() -> Void)?
    var onMessage: ((String?) -> Void)?

    private let settings: ShortcutSettings
    private let recordButton = NSButton(title: "", target: nil, action: nil)
    private let clearButton = NSButton()
    private var monitor: Any?
    private var lastModifierCombination: UInt64 = 0
    private(set) var isRecording = false

    init(action: WindowAction, settings: ShortcutSettings) {
        self.action = action
        self.settings = settings
        super.init(frame: .zero)
        recordButton.bezelStyle = .rounded
        recordButton.font = .systemFont(ofSize: 12)
        recordButton.alignment = .center
        recordButton.cell?.lineBreakMode = .byTruncatingMiddle
        recordButton.target = self
        recordButton.action = #selector(beginRecording)
        recordButton.setAccessibilityLabel("\(action.title) 단축키")
        recordButton.toolTip = "선택한 뒤 원하는 단축키를 누르세요. Escape로 취소할 수 있습니다."
        clearButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "단축키 해제")
        clearButton.imageScaling = .scaleProportionallyDown
        clearButton.isBordered = false
        clearButton.contentTintColor = .secondaryLabelColor
        clearButton.target = self
        clearButton.action = #selector(clearBinding)
        clearButton.toolTip = "단축키를 해제합니다."
        clearButton.setAccessibilityLabel("\(action.title) 단축키 해제")
        let stack = NSStackView(views: [recordButton, clearButton])
        stack.spacing = 8
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: action == .drawRegion ? 270 : 160),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            recordButton.widthAnchor.constraint(equalToConstant: action == .drawRegion ? 238 : 128),
            recordButton.heightAnchor.constraint(equalToConstant: 28),
            clearButton.widthAnchor.constraint(equalToConstant: 24),
            clearButton.heightAnchor.constraint(equalToConstant: 24)
        ])
        refresh()
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        if let monitor = monitor { NSEvent.removeMonitor(monitor) }
        if isRecording { onRecordingChanged?(false) }
    }

    func refresh() {
        if !isRecording { recordButton.title = settings.binding(for: action).displayName }
        clearButton.isEnabled = !settings.binding(for: action).disabled || isRecording
    }

    @objc private func beginRecording() {
        if isRecording { cancelRecording(); return }
        guard let window = window, window.isKeyWindow else { return }
        onBegin?(self)
        isRecording = true
        lastModifierCombination = 0
        recordButton.title = action == .drawRegion ? "조합키를 누른 뒤 놓으세요" : "단축키를 누르세요…"
        recordButton.state = .on
        clearButton.isEnabled = true
        onMessage?(action == .drawRegion ? "조합키를 두 개 이상 누른 뒤 모두 놓아 주세요. 왼쪽 드래그는 고정입니다." : "Command 또는 Control을 포함한 단축키를 누르세요. Escape는 취소, Delete는 해제입니다.")
        onRecordingChanged?(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self = self, self.isRecording,
                  let recordingWindow = self.window, recordingWindow.isKeyWindow,
                  NSApp.keyWindow === recordingWindow,
                  event.window == nil || event.window === recordingWindow else { return event }
            return self.handle(event)
        }
        if monitor == nil {
            cancelRecording()
            onMessage?("단축키 입력을 시작하지 못했습니다. 다시 선택해 주세요.")
        }
    }

    func cancelRecording() {
        guard isRecording else { return }
        if let monitor = monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        lastModifierCombination = 0
        recordButton.state = .off
        refresh()
        onRecordingChanged?(false)
    }

    @objc private func clearBinding() {
        onBegin?(self)
        cancelRecording()
        commit(.unassigned)
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        let flags = ShortcutBinding.normalized(UInt64(event.modifierFlags.rawValue))
        if event.type == .keyDown {
            if event.keyCode == 53 {
                cancelRecording()
                onMessage?(nil)
            } else if [51, 117].contains(event.keyCode), flags == 0 {
                clearBinding()
            } else if action == .drawRegion {
                lastModifierCombination = 0
                onMessage?("자유 영역 그리기에는 일반 키를 사용할 수 없습니다. 조합키를 두 개 이상 누른 뒤 모두 놓아 주세요.")
            } else if !event.isARepeat {
                commit(ShortcutBinding(keyCode: event.keyCode, modifiers: flags))
            }
            return nil
        }
        if action == .drawRegion {
            lastModifierCombination = Self.modifierCandidate(previous: lastModifierCombination, current: flags)
            if flags == 0, lastModifierCombination != 0 {
                commit(ShortcutBinding(keyCode: nil, modifiers: lastModifierCombination))
                lastModifierCombination = 0
            }
        }
        return nil
    }

    private func commit(_ binding: ShortcutBinding) {
        if let error = settings.set(binding, for: action) {
            onMessage?(error)
            return
        }
        cancelRecording()
        refresh()
        onMessage?(nil)
        onCommitted?()
    }
}
