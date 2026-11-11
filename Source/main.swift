import AppKit
import ApplicationServices

private final class DragSession {
    let start: CGPoint
    let screen: NSScreen
    let quartzFrame: CGRect
    let pixelScale: CGFloat
    let name: String
    var rectangle: CGRect
    var target: WindowTarget?
    var released = false

    init(start: CGPoint, screen: NSScreen, quartzFrame: CGRect, name: String) {
        self.start = start
        self.screen = screen
        self.quartzFrame = quartzFrame
        self.pixelScale = screen.backingScaleFactor
        self.name = name
        rectangle = CGRect(origin: start, size: .zero)
    }

    func update(to point: CGPoint) {
        rectangle = SelectionGeometry.rectangle(from: start, to: point)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let stateItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let resultItem = NSMenuItem(title: "⌘+⇧를 누르고 원하는 영역을 드래그하세요", action: nil, keyEquivalent: "")
    private let toggleItem = NSMenuItem(title: "기능 켜기", action: #selector(toggle), keyEquivalent: "")
    private let overlay = SelectionOverlay()
    private var rejectedSizes = RejectedSizeCache()
    private var diagnostics = InteractionDiagnostics()
    private var errorDismissal: DispatchWorkItem?
    private let windowQueue = DispatchQueue(label: "personal.windowsketch.accessibility")
    private var eventTap: CFMachPort?
    private var eventSource: CFRunLoopSource?
    private var permissionTimer: Timer?
    private var requestedEnabled = true
    private var drag: DragSession?
    private var swallowingMouse = false
    private var swallowingEscape = false
    private var applying = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = NSWorkspace.shared.frontmostApplication
        if let screen = NSScreen.screens.first { overlay.prepare(on: screen) }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let image = NSImage(systemSymbolName: "rectangle.dashed", accessibilityDescription: "윈도우스케치")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.setAccessibilityLabel("윈도우스케치")
        statusItem.menu = menu
        menu.delegate = self
        stateItem.isEnabled = false
        resultItem.isEnabled = false
        toggleItem.target = self
        menu.addItem(stateItem)
        menu.addItem(resultItem)
        menu.addItem(.separator())
        menu.addItem(toggleItem)
        addItem("손쉬운 사용 권한 허용…", #selector(requestPermission))
        addItem("사용 방법…", #selector(showHelp))
        menu.addItem(.separator())
        addItem("윈도우스케치 종료", #selector(quit), key: "q")
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(screenWillSleep),
                                                         name: NSWorkspace.screensDidSleepNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(displaysChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        refreshPermission()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refreshPermission()
        }
    }

    private func addItem(_ title: String, _ action: Selector, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    func menuNeedsUpdate(_ menu: NSMenu) { updateMenu() }

    private func updateMenu() {
        let trusted = AXIsProcessTrusted()
        stateItem.title = !trusted ? "상태: 손쉬운 사용 권한 필요" :
            (!requestedEnabled ? "상태: 꺼짐" : (eventTap == nil ? "상태: 입력 감지 연결 필요" : "상태: 켜짐 · ⌘⇧ 드래그"))
        toggleItem.title = requestedEnabled ? "기능 끄기" : "기능 켜기"
        toggleItem.state = requestedEnabled ? .on : .off
        statusItem.button?.toolTip = "윈도우스케치\n\(stateItem.title)\n\(resultItem.title)\n\(diagnostics.summary)"
        statusItem.button?.title = trusted && (!requestedEnabled || eventTap != nil) ? "" : " !"
    }

    private func refreshPermission() {
        if AXIsProcessTrusted() && requestedEnabled {
            if eventTap == nil { startEventTap() }
        } else if eventTap != nil {
            cancelSelection()
            // 이미 가로챈 누름에 대응하는 버튼 해제까지 처리한 뒤 연결을 정리합니다.
            if !swallowingMouse && !swallowingEscape { stopEventTap() }
        }
        updateMenu()
    }

    private func startEventTap() {
        let types: [CGEventType] = [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .keyDown, .keyUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context = context else { return Unmanaged.passUnretained(event) }
            let app = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            return app.handle(type, event: event) ? nil : Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                         options: .defaultTap, eventsOfInterest: mask,
                                         callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            resultItem.title = "입력 감지 연결 실패: 권한을 확인한 뒤 앱을 다시 실행해 주세요."
            return
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            resultItem.title = "입력 감지 연결을 만들 수 없습니다. 앱을 다시 실행해 주세요."
            return
        }
        eventTap = tap
        eventSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func stopEventTap() {
        if let tap = eventTap { CFMachPortInvalidate(tap) }
        if let source = eventSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        eventTap = nil
        eventSource = nil
    }

    private func handle(_ type: CGEventType, event: CGEvent) -> Bool {
        let started = CFAbsoluteTimeGetCurrent()
        defer { diagnostics.recordInput(seconds: CFAbsoluteTimeGetCurrent() - started) }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if type == .tapDisabledByTimeout, requestedEnabled, let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            DispatchQueue.main.async {
                if type == .tapDisabledByTimeout { self.diagnostics.timeoutCount += 1 }
                self.cancelSelection(reason: type == .tapDisabledByTimeout ? "입력 감지 시간 초과" : "입력 감지 중단")
                self.report("입력 감지가 중단되어 선택을 취소했습니다. 다시 드래그해 주세요.", error: true)
            }
            return false
        }
        if type == .keyDown || type == .keyUp {
            let escape = event.getIntegerValueField(.keyboardEventKeycode) == 53
            if type == .keyUp && escape && swallowingEscape {
                swallowingEscape = false
                return true
            }
            if type == .keyDown && escape && (swallowingMouse || drag != nil || swallowingEscape) {
                swallowingEscape = true
                DispatchQueue.main.async {
                    self.cancelSelection(reason: "Esc")
                    self.report("선택을 취소했습니다.")
                }
                return true
            }
            return false
        }
        if type == .leftMouseDragged && swallowingMouse {
            let point = event.location
            DispatchQueue.main.async {
                if let session = self.drag, !session.released {
                    session.update(to: point)
                    self.updateOverlay(session)
                }
            }
            return true
        }
        if type == .leftMouseUp && swallowingMouse {
            swallowingMouse = false
            let point = event.location
            DispatchQueue.main.async {
                self.overlay.hide()
                if let session = self.drag {
                    session.update(to: point)
                    session.released = true
                    if SelectionGeometry.isValid(session.rectangle) {
                        self.finishIfReady(session)
                    } else {
                        self.cancelSelection(reason: "영역 없음")
                        self.report("너비와 높이가 있는 영역을 그려 주세요.", error: true)
                    }
                }
            }
            return true
        }
        let modifierMask: CGEventFlags = [.maskCommand, .maskShift, .maskControl, .maskAlternate]
        guard type == .leftMouseDown, requestedEnabled, eventTap != nil,
              event.flags.intersection(modifierMask) == [.maskCommand, .maskShift] else { return false }
        swallowingMouse = true
        let point = event.location
        let application = NSWorkspace.shared.frontmostApplication
        // 입력 콜백은 가로챌 이벤트만 결정하고 화면 처리는 반환 후 순서대로 실행합니다.
        DispatchQueue.main.async {
            self.cancelSelection(reason: "새 선택 시작")
            guard !self.applying else {
                self.report("이전 창 변경을 처리 중입니다. 잠시 뒤 다시 선택해 주세요.", error: true)
                return
            }
            self.beginSelection(at: point, application: application)
        }
        return true
    }

    private func updateOverlay(_ session: DragSession) {
        let warning = session.target.flatMap { target in
            target.sizeAdvice.warning(for: session.rectangle.size, scale: session.pixelScale) ??
                (rejectedSizes.contains(session.rectangle.size, for: target, scale: session.pixelScale)
                 ? "이 창에서 이전에 거부된 크기입니다 · 놓으면 다시 시도합니다" : nil)
        }
        overlay.update(session.rectangle, warning: warning)
    }

    private func beginSelection(at point: CGPoint, application: NSRunningApplication?) {
        let preparedAt = CFAbsoluteTimeGetCurrent()
        guard let primary = NSScreen.screens.first,
              let screen = NSScreen.screens.first(where: {
                  SelectionGeometry.quartzRect(from: $0.frame, primaryTop: primary.frame.maxY).contains(point)
              }), let application = application ?? NSWorkspace.shared.frontmostApplication else {
            report("대상 화면 또는 앱을 찾을 수 없습니다.", error: true)
            return
        }
        let fullFrame = SelectionGeometry.quartzRect(from: screen.frame, primaryTop: primary.frame.maxY)
        let session = DragSession(start: point, screen: screen, quartzFrame: fullFrame,
                                  name: application.localizedName ?? "선택한 앱")
        drag = session
        overlay.show(on: screen, quartzFrame: fullFrame, name: session.name)
        updateOverlay(session)
        diagnostics.preparationMilliseconds = (CFAbsoluteTimeGetCurrent() - preparedAt) * 1000
        updateMenu()
        loadTarget(for: session, application: application)
    }

    private func loadTarget(for session: DragSession, application: NSRunningApplication, attempt: Int = 0) {
        guard drag === session else { return }
        let started = CFAbsoluteTimeGetCurrent()
        // 응답이 느린 앱 때문에 전역 입력 처리가 멈추지 않도록 별도 큐에서 조회합니다.
        windowQueue.async {
            let result = Result { try WindowController.capture(application: application) }
            DispatchQueue.main.async {
                guard self.drag === session else { return }
                self.diagnostics.lookupMilliseconds = (CFAbsoluteTimeGetCurrent() - started) * 1000
                switch result {
                case .success(let target):
                    session.target = target
                    if !session.released { self.updateOverlay(session) }
                    self.updateMenu()
                    self.finishIfReady(session)
                case .failure(let error):
                    if (error as? WindowFailure)?.axError == .cannotComplete && attempt == 0 {
                        self.diagnostics.retryCount += 1
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                            self.loadTarget(for: session, application: application, attempt: 1)
                        }
                    } else {
                        self.cancelSelection(reason: error.localizedDescription)
                        self.showFailure(error.localizedDescription, for: session)
                    }
                }
            }
        }
    }

    private func finishIfReady(_ session: DragSession) {
        guard drag === session, session.released, let target = session.target else { return }
        drag = nil
        applying = true
        report("\(target.name) 창을 배치하고 있습니다…")
        windowQueue.async {
            let result = Result {
                try WindowController.apply(session.rectangle, to: target, scale: session.pixelScale)
            }
            DispatchQueue.main.async {
                self.applying = false
                switch result {
                case .failure(let error):
                    self.showFailure(error.localizedDescription, for: session)
                case .success(let placement):
                    if placement.sizeChanged {
                        self.rejectedSizes.record(session.rectangle.size, for: target, scale: session.pixelScale)
                    } else {
                        self.rejectedSizes.forget(session.rectangle.size, for: target, scale: session.pixelScale)
                    }
                    if let warning = placement.warning {
                        self.showFailure(warning, for: session, rectangle: placement.frame, warning: true)
                    } else {
                        let size = SelectionGeometry.pixelSizeLabel(placement.frame.size, scale: session.pixelScale)
                        self.report("\(target.name) · \(size) 배치 완료")
                    }
                }
            }
        }
    }

    private func showFailure(_ message: String, for session: DragSession, rectangle: CGRect? = nil, warning: Bool = false) {
        errorDismissal?.cancel()
        overlay.show(on: session.screen, quartzFrame: session.quartzFrame, name: session.name)
        overlay.update(rectangle ?? session.rectangle, error: warning ? nil : message,
                       warning: warning ? message : nil, completed: true)
        report(message.replacingOccurrences(of: "\n", with: " · "), error: !warning)
        let dismissal = DispatchWorkItem { [weak self] in self?.overlay.hide() }
        errorDismissal = dismissal
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: dismissal)
    }

    private func cancelSelection(reason: String = "선택 취소") {
        errorDismissal?.cancel()
        errorDismissal = nil
        if drag != nil { diagnostics.lastCancellation = reason }
        drag = nil
        overlay.hide()
    }

    private func report(_ message: String, error: Bool = false) {
        resultItem.title = message
        if error { NSSound.beep() }
        updateMenu()
    }

    @objc private func toggle() {
        requestedEnabled.toggle()
        cancelSelection()
        refreshPermission()
    }

    @objc private func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func showHelp() {
        let alert = NSAlert()
        alert.messageText = "윈도우스케치 사용 방법"
        alert.informativeText = "1. 손쉬운 사용에서 윈도우스케치를 허용해 주세요.\n2. 이동할 창을 선택해 주세요.\n3. ⌘+⇧를 누르고 원하는 위치에서 왼쪽 버튼으로 드래그하세요.\n4. 버튼을 놓으면 적용되고 Esc를 누르면 취소됩니다.\n\n그린 영역을 그대로 요청합니다. 자동 스냅과 최소 크기 보정은 없습니다. 앱이 요청한 크기를 지원하지 않으면 실제 적용된 크기를 유지하고 요청·실제 크기를 빨간색으로 안내합니다. 이전 배치로 복원하지 않습니다. 앱이 제공하는 제한이나 같은 창의 이전 거부 크기는 드래그 중 빨간색으로 경고합니다. 경고는 크기를 바꾸거나 적용을 막지 않습니다. 나머지는 버튼을 놓은 뒤 지원 여부를 확인합니다.\n\n크기는 시작 화면의 배율을 반영한 px로 표시합니다. 권한을 허용해도 연결되지 않으면 앱을 다시 실행해 주세요."
        alert.addButton(withTitle: "확인")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func displaysChanged() { cancelSelection(reason: "화면 구성 변경") }
    @objc private func screenWillSleep() {
        cancelSelection()
        swallowingMouse = false
        swallowingEscape = false
    }

    @objc private func quit() { NSApp.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        cancelSelection()
        stopEventTap()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }
}

if CommandLine.arguments.contains("--self-test") {
    SelfCheck.run()
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.setActivationPolicy(.accessory)
    app.delegate = delegate
    app.run()
    withExtendedLifetime(delegate) {}
}
