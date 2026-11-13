import AppKit
import ApplicationServices

private final class DragSession {
    let start: CGPoint
    let screen: NSScreen
    let quartzFrame: CGRect
    let pixelScale: CGFloat
    let name: String
    let reference: FocusedWindowReference
    var rectangle: CGRect
    var target: WindowTarget?
    var released = false

    init(start: CGPoint, screen: NSScreen, quartzFrame: CGRect, reference: FocusedWindowReference) {
        self.start = start
        self.screen = screen
        self.quartzFrame = quartzFrame
        self.pixelScale = screen.backingScaleFactor
        self.reference = reference
        self.name = reference.application.localizedName ?? "선택한 앱"
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
    private let shortcuts = ShortcutSettings()
    private let history = WindowHistory()
    private let updater = AppUpdater()
    private let updateItem = NSMenuItem(title: "새 버전으로 업데이트…", action: #selector(installUpdate), keyEquivalent: "")
    private let checkUpdateItem = NSMenuItem(title: "업데이트 확인…", action: #selector(checkForUpdates), keyEquivalent: "")
    private let versionItem = NSMenuItem(title: AppUpdater.versionLabel, action: nil, keyEquivalent: "")
    private var updateReadyToInstall = false
    private var settingsWindow: SettingsWindowController?
    private var recordingShortcuts = false
    private var swallowedKeys = Set<UInt16>()
    private var rejectedSizes = RejectedSizeCache()
    private var diagnostics = InteractionDiagnostics()
    private var errorDismissal: DispatchWorkItem?
    private let windowQueue = DispatchQueue(label: "personal.windowsketch.accessibility")
    private lazy var focusTracker = FocusedWindowTracker(queue: windowQueue) { [weak self] in
        self?.targetFocusChanged()
    }
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
        let image = NSImage(named: NSImage.Name("StatusBarIconTemplate")) ?? NSImage(systemSymbolName: "rectangle.dashed", accessibilityDescription: "SketchFrame")
        image?.size = NSSize(width: 18, height: 18)
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.setAccessibilityLabel("SketchFrame")
        statusItem.menu = menu
        menu.delegate = self
        menu.autoenablesItems = false
        versionItem.isEnabled = false
        updateItem.target = self
        updateItem.isHidden = true
        checkUpdateItem.target = self
        menu.addItem(versionItem)
        menu.addItem(updateItem)
        stateItem.isEnabled = false
        resultItem.isEnabled = false
        toggleItem.target = self
        menu.addItem(stateItem)
        menu.addItem(resultItem)
        menu.addItem(.separator())
        menu.addItem(toggleItem)
        addItem("설정…", #selector(showSettings), key: ",")
        addItem("손쉬운 사용 권한 허용…", #selector(requestPermission))
        addItem("사용 방법…", #selector(showHelp))
        menu.addItem(checkUpdateItem)
        menu.addItem(.separator())
        addItem("SketchFrame 종료", #selector(quit), key: "q")
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(screenWillSleep),
                                                         name: NSWorkspace.screensDidSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activeApplicationChanged),
                                                         name: NSWorkspace.didActivateApplicationNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(displaysChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        shortcuts.onChange = { [weak self] in
            self?.cancelSelection(reason: "단축키 변경")
            self?.report("단축키 설정을 적용했습니다.")
        }
        resultItem.title = shortcuts.loadWarning ?? "설정에서 창 배치 단축키와 자유 드래그 조합을 변경할 수 있습니다."
        refreshPermission()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refreshPermission()
        }
        updater.onChange = { [weak self] in
            self?.updateMenu()
            self?.settingsWindow?.refreshUpdates()
        }
        updater.onManualResult = { [weak self] result in
            switch result {
            case .success(let candidate) where candidate != nil: self?.installUpdate()
            case .success: self?.showInformation("업데이트 확인", updaterMessage: self?.updater.status ?? "")
            case .failure(let error): self?.showInformation("업데이트 확인 실패", updaterMessage: error.localizedDescription)
            }
        }
        if CommandLine.arguments.contains("--check-input-recovery") { checkInputRecovery() }
        else { updater.start() }
    }

    private func addItem(_ title: String, _ action: Selector, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    func menuNeedsUpdate(_ menu: NSMenu) { updateMenu() }

    private var inputState: InputConnectionState {
        let connected = eventTap.map { CFMachPortIsValid($0) && CGEvent.tapIsEnabled(tap: $0) } ?? false
        return InputConnectionState(trusted: AXIsProcessTrusted(), requestedEnabled: requestedEnabled, connected: connected)
    }

    private func updateMenu() {
        let state = inputState
        stateItem.title = state.title
        if state.shouldConnect && state.connected {
            let binding = shortcuts.binding(for: .drawRegion)
            stateItem.title = recordingShortcuts ? "상태: 단축키 기록 중" :
                "상태: 켜짐 · \(binding.disabled ? "창 배치 단축키" : binding.displayName)"
        }
        updateItem.isHidden = updater.available == nil
        updateItem.title = "새 버전 \(updater.available?.version ?? "")으로 업데이트…"
        updateItem.isEnabled = !updater.installing && !updater.checking
        checkUpdateItem.title = updater.checking ? "업데이트 확인 중…" : "업데이트 확인…"
        checkUpdateItem.isEnabled = !updater.checking && !updater.installing
        toggleItem.title = requestedEnabled ? "기능 끄기" : "기능 켜기"
        toggleItem.state = requestedEnabled ? .on : .off
        statusItem.button?.toolTip = "\(AppUpdater.versionLabel)\n\(updater.status)\n\(stateItem.title)\n\(resultItem.title)\n\(diagnostics.summary)"
        statusItem.button?.title = state.trusted && (!requestedEnabled || state.connected) ? "" : " !"
    }

    private func refreshPermission() {
        let state = inputState
        if state.shouldConnect {
            if !state.connected {
                if let tap = eventTap, CFMachPortIsValid(tap) { CGEvent.tapEnable(tap: tap, enable: true) }
                if !inputState.connected {
                    stopEventTap()
                    startEventTap()
                }
            }
            focusTracker.watch(NSWorkspace.shared.frontmostApplication)
        } else {
            focusTracker.watch(nil)
            if eventTap != nil {
                cancelSelection()
                // 연결이 살아 있으면 이미 가로챈 누름에 대응하는 해제까지 소비합니다.
                if !state.connected || (!swallowingMouse && !swallowingEscape && swallowedKeys.isEmpty) {
                    swallowingMouse = false
                    swallowingEscape = false
                    swallowedKeys.removeAll()
                    stopEventTap()
                }
            }
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

    private func checkInputRecovery() {
        guard inputState.connected, let tap = eventTap, let event = CGEvent(source: nil) else {
            fatalError("입력 복구 검사에는 손쉬운 사용 권한과 활성 연결이 필요합니다.")
        }
        CGEvent.tapEnable(tap: tap, enable: false)
        precondition(!inputState.connected && inputState.title == "상태: 입력 감지 연결 필요")
        _ = handle(.tapDisabledByUserInput, event: event)
        DispatchQueue.main.async {
            precondition(self.inputState.connected, "입력 중단 콜백 복구 실패")
            self.swallowingMouse = true
            self.swallowingEscape = true
            self.updateCapturedInput(mousePressed: true, escapePressed: true)
            precondition(self.swallowingMouse && self.swallowingEscape, "누르는 중인 입력 해제 누락")
            self.updateCapturedInput(mousePressed: false, escapePressed: false)
            precondition(!self.swallowingMouse && !self.swallowingEscape, "놓친 입력 해제 상태 정리 실패")
            guard let tap = self.eventTap else { fatalError("입력 연결 없음") }
            CGEvent.tapEnable(tap: tap, enable: false)
            self.refreshPermission()
            precondition(self.inputState.connected, "주기 검사 경로의 연결 복구 실패")
            self.requestedEnabled = false
            self.refreshPermission()
            precondition(!self.inputState.connected && self.eventTap == nil, "사용자 끄기 무시")
            self.requestedEnabled = true
            self.refreshPermission()
            precondition(self.inputState.connected, "다시 켜기 실패")
            print("입력 중단 표시·콜백 복구·입력 해제 유지·놓친 해제 정리·주기 검사 복구·끄기·다시 켜기 검사 통과")
            NSApp.terminate(nil)
        }
    }

    private func updateCapturedInput(mousePressed: Bool, escapePressed: Bool) {
        swallowingMouse = swallowingMouse && mousePressed
        swallowingEscape = swallowingEscape && escapePressed
    }

    private func handle(_ type: CGEventType, event: CGEvent) -> Bool {
        let started = CFAbsoluteTimeGetCurrent()
        defer { diagnostics.recordInput(seconds: CFAbsoluteTimeGetCurrent() - started) }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            DispatchQueue.main.async {
                if type == .tapDisabledByTimeout { self.diagnostics.timeoutCount += 1 }
                self.cancelSelection(reason: type == .tapDisabledByTimeout ? "입력 감지 시간 초과" : "입력 감지 중단")
                // 누르는 중인 입력만 해제까지 소비하고, 중단 중 이미 놓은 입력은 정리합니다.
                self.updateCapturedInput(mousePressed: CGEventSource.buttonState(.combinedSessionState, button: .left),
                                         escapePressed: CGEventSource.keyState(.combinedSessionState, key: 53))
                self.swallowedKeys = self.swallowedKeys.filter { CGEventSource.keyState(.combinedSessionState, key: $0) }
                self.refreshPermission()
                self.report(self.inputState.connected
                    ? "입력 연결을 복구하고 선택을 취소했습니다. 다시 드래그해 주세요."
                    : "입력 감지가 중단되었습니다. 권한과 연결 상태를 확인해 주세요.", error: true)
            }
            return false
        }
        if type == .keyDown || type == .keyUp {
            let key = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            if type == .keyUp && swallowedKeys.remove(key) != nil { return true }
            if type == .keyDown && swallowedKeys.contains(key) { return true }
            let escape = key == 53
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
            if type == .keyDown, requestedEnabled, !recordingShortcuts, !swallowingMouse,
               event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
               NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier,
               let action = shortcuts.action(for: key, flags: event.flags.rawValue) {
                let reference = focusTracker.reference(for: NSWorkspace.shared.frontmostApplication)
                swallowedKeys.insert(key)
                DispatchQueue.main.async {
                    guard let reference = reference, self.focusTracker.isCurrent(reference) else {
                        self.report(self.focusTracker.message, error: true)
                        return
                    }
                    self.performAction(action, reference: reference)
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
        guard type == .leftMouseDown, requestedEnabled, eventTap != nil, !recordingShortcuts,
              shortcuts.binding(for: .drawRegion).matchesDrag(flags: event.flags.rawValue) else { return false }
        swallowingMouse = true
        let point = event.location
        let application = NSWorkspace.shared.frontmostApplication
        let reference = focusTracker.reference(for: application)
        // 입력 콜백은 가로챌 이벤트만 결정하고 화면 처리는 반환 후 순서대로 실행합니다.
        DispatchQueue.main.async {
            self.cancelSelection(reason: "새 선택 시작")
            guard !self.applying else {
                self.report("이전 창 변경을 처리 중입니다. 잠시 뒤 다시 선택해 주세요.", error: true)
                return
            }
            guard let reference = reference, self.focusTracker.isCurrent(reference) else {
                self.focusTracker.watch(NSWorkspace.shared.frontmostApplication)
                self.report(self.focusTracker.message, error: true)
                return
            }
            self.beginSelection(at: point, reference: reference)
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

    private func beginSelection(at point: CGPoint, reference: FocusedWindowReference) {
        let preparedAt = CFAbsoluteTimeGetCurrent()
        guard let primary = NSScreen.screens.first,
              let screen = NSScreen.screens.first(where: {
                  SelectionGeometry.quartzRect(from: $0.frame, primaryTop: primary.frame.maxY).contains(point)
              }) else {
            report("대상 화면 또는 앱을 찾을 수 없습니다.", error: true)
            return
        }
        let fullFrame = SelectionGeometry.quartzRect(from: screen.frame, primaryTop: primary.frame.maxY)
        let session = DragSession(start: point, screen: screen, quartzFrame: fullFrame,
                                  reference: reference)
        drag = session
        overlay.show(on: screen, quartzFrame: fullFrame, name: session.name)
        updateOverlay(session)
        diagnostics.preparationMilliseconds = (CFAbsoluteTimeGetCurrent() - preparedAt) * 1000
        updateMenu()
        loadTarget(for: session)
    }

    private func loadTarget(for session: DragSession, attempt: Int = 0) {
        guard drag === session, focusTracker.isCurrent(session.reference) else { return }
        let started = CFAbsoluteTimeGetCurrent()
        // 응답이 느린 앱 때문에 전역 입력 처리가 멈추지 않도록 별도 큐에서 조회합니다.
        windowQueue.async {
            let result = Result {
                try WindowController.capture(application: session.reference.application, window: session.reference.window)
            }
            DispatchQueue.main.async {
                guard self.drag === session, self.focusTracker.isCurrent(session.reference) else { return }
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
                            self.loadTarget(for: session, attempt: 1)
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
        guard focusTracker.isCurrent(session.reference) else {
            targetFocusChanged()
            return
        }
        drag = nil
        applying = true
        report("\(target.name) 창을 배치하고 있습니다…")
        windowQueue.async {
            let result = Result {
                let placement = try WindowController.apply(session.rectangle, to: target, scale: session.pixelScale)
                self.history.record(before: target.originalFrame, after: placement.frame, for: target, scale: session.pixelScale)
                return placement
            }
            DispatchQueue.main.async {
                self.applying = false
                switch result {
                case .failure(let error):
                    self.showFailure(error.localizedDescription, for: session)
                case .success(let placement):
                    self.diagnostics.recordPlacement(requested: session.rectangle, actual: placement.frame, scale: session.pixelScale)
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
        showNotice(message, name: session.name, on: session.screen, quartzFrame: session.quartzFrame,
                   rectangle: rectangle ?? session.rectangle, warning: warning)
    }

    private func showNotice(_ message: String, name: String, on screen: NSScreen, quartzFrame: CGRect,
                            rectangle: CGRect, warning: Bool) {
        errorDismissal?.cancel()
        overlay.show(on: screen, quartzFrame: quartzFrame, name: name)
        overlay.update(rectangle, error: warning ? nil : message,
                       warning: warning ? message : nil, completed: true)
        report(message.replacingOccurrences(of: "\n", with: " · "), error: !warning)
        let dismissal = DispatchWorkItem { [weak self] in self?.overlay.hide() }
        errorDismissal = dismissal
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: dismissal)
    }

    private func screenRegions() -> [ScreenRegion] {
        guard let primary = NSScreen.screens.first else { return [] }
        return NSScreen.screens.compactMap { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return ScreenRegion(id: id.uint32Value,
                                frame: SelectionGeometry.quartzRect(from: screen.frame, primaryTop: primary.frame.maxY),
                                workArea: SelectionGeometry.quartzRect(from: screen.visibleFrame, primaryTop: primary.frame.maxY),
                                scale: screen.backingScaleFactor)
        }
    }

    private func performAction(_ action: WindowAction, reference: FocusedWindowReference) {
        guard requestedEnabled, !recordingShortcuts, !applying, !swallowingMouse else {
            report("이전 창 변경을 처리 중입니다. 잠시 뒤 다시 실행해 주세요.")
            return
        }
        guard focusTracker.isCurrent(reference) else { targetFocusChanged(); return }
        cancelSelection(reason: "창 배치 단축키")
        applying = true
        let screens = screenRegions()
        report("\(action.title) 배치를 적용하고 있습니다…")
        windowQueue.async {
            let result = Result { () -> (WindowTarget, WindowLayoutPlan) in
                let target = try WindowController.capture(application: reference.application, window: reference.window, inspectSize: false)
                let sourceScale = WindowLayoutCalculator.screen(for: target.originalFrame, screens: screens)?.scale ?? 1
                let restore = action == .restore ? self.history.restoreFrame(for: target, scale: sourceScale) : nil
                let plan = try WindowLayoutCalculator.plan(action: action, window: target.originalFrame, screens: screens, restoreFrame: restore)
                try WindowController.applyWithoutSizeCheck(plan.rectangle, to: target)
                self.history.record(before: target.originalFrame, after: nil, for: target,
                                    scale: plan.screen.scale, restored: action == .restore)
                return (target, plan)
            }
            DispatchQueue.main.async {
                self.applying = false
                switch result {
                case .failure(let error): self.report(error.localizedDescription, error: true)
                case .success(let (target, plan)):
                    self.diagnostics.lastPlacement = "키보드 배치 요청 · 결과 검사 생략"
                    let size = SelectionGeometry.pixelSizeLabel(plan.rectangle.size, scale: plan.screen.scale)
                    self.report("\(target.name) · \(action.title) · 배치 요청 완료 (\(size))")
                }
            }
        }
    }

    @objc private func showSettings() {
        cancelSelection(reason: "설정 열기")
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(settings: shortcuts, updater: updater) { [weak self] recording in
                self?.recordingShortcuts = recording
                if recording { self?.cancelSelection(reason: "단축키 기록") }
                self?.updateMenu()
            }
        }
        settingsWindow?.onCheckUpdates = { [weak self] in self?.checkForUpdates() }
        settingsWindow?.onInstallUpdate = { [weak self] in self?.installUpdate() }
        settingsWindow?.refresh()
        settingsWindow?.showWindow(nil)
        settingsWindow?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func cancelSelection(reason: String = "선택 취소") {
        errorDismissal?.cancel()
        errorDismissal = nil
        if drag != nil { diagnostics.lastCancellation = reason }
        drag = nil
        overlay.hide()
    }

    private func targetFocusChanged() {
        guard drag != nil else { return }
        cancelSelection(reason: "대상 창 변경")
        report("대상 창이 바뀌어 선택을 취소했습니다. 다시 그려 주세요.")
    }

    @objc private func activeApplicationChanged() {
        focusTracker.watch(inputState.shouldConnect ? NSWorkspace.shared.frontmostApplication : nil)
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
        alert.messageText = "SketchFrame 사용 방법"
        let draw = shortcuts.binding(for: .drawRegion)
        let dragHint = draw.disabled ? "자유 영역 그리기가 해제되어 있습니다. 설정에서 단축키를 지정해 주세요." : "현재 자유 영역 그리기: \(draw.displayName)"
        alert.informativeText = "\(dragHint)\n\n1. 손쉬운 사용에서 SketchFrame를 허용해 주세요.\n2. 이동할 창을 선택해 주세요.\n3. 설정한 조합키를 누르고 원하는 위치에서 왼쪽 버튼으로 드래그하세요.\n4. 버튼을 놓으면 적용되고 Esc를 누르면 취소됩니다.\n\n그린 영역을 그대로 요청합니다. 자동 스냅과 최소 크기 보정은 없습니다. 앱이 요청한 크기를 지원하지 않으면 실제 적용된 크기를 유지하고 요청·실제 크기를 빨간색으로 안내합니다. 이전 배치로 복원하지 않습니다. 앱이 제공하는 제한이나 같은 창의 이전 거부 크기는 드래그 중 빨간색으로 경고합니다. 경고는 크기를 바꾸거나 적용을 막지 않습니다. 나머지는 버튼을 놓은 뒤 지원 여부를 확인합니다.\n\n크기는 시작 화면의 배율을 반영한 px로 표시합니다. 권한을 허용해도 연결되지 않으면 앱을 다시 실행해 주세요."
        alert.addButton(withTitle: "확인")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func showInformation(_ title: String, updaterMessage: String) {
        menu.cancelTracking()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = updaterMessage
        alert.addButton(withTitle: "확인")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func checkForUpdates() { updater.check(manual: true) }

    @objc private func installUpdate() {
        guard let candidate = updater.available, !updater.installing else { return }
        guard !applying, !swallowingMouse, !recordingShortcuts else {
            showInformation("현재 작업을 마쳐 주세요", updaterMessage: "창 배치나 단축키 입력을 마친 뒤 업데이트해 주세요.")
            return
        }
        menu.cancelTracking()
        let alert = NSAlert()
        alert.messageText = "SketchFrame \(candidate.version) 업데이트"
        alert.informativeText = "현재 버전: \(AppUpdater.version) (빌드 \(AppUpdater.build))\n\n새 버전을 다운로드하고 확인한 뒤 앱을 교체합니다. 완료되면 자동으로 다시 실행됩니다. 단축키 설정은 유지됩니다."
        alert.addButton(withTitle: "지금 업데이트")
        alert.addButton(withTitle: "나중에")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        updater.prepareInstallation(candidate) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error): self.showInformation("업데이트 준비 실패", updaterMessage: error.localizedDescription)
            case .success(let prepared):
                do {
                    try prepared.launch(oldPID: ProcessInfo.processInfo.processIdentifier)
                    self.updateReadyToInstall = true
                    self.cancelSelection(reason: "업데이트 설치")
                    NSApp.terminate(nil)
                } catch {
                    prepared.cleanUp()
                    self.updater.installationFailed(error)
                    self.showInformation("업데이트 설치 실패", updaterMessage: error.localizedDescription)
                }
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if updater.installing && !updateReadyToInstall {
            showInformation("업데이트 준비 중입니다", updaterMessage: "다운로드와 검증이 끝날 때까지 기다려 주세요.")
            return .terminateCancel
        }
        return .terminateNow
    }

    @objc private func displaysChanged() { cancelSelection(reason: "화면 구성 변경") }
    @objc private func screenWillSleep() {
        cancelSelection()
        swallowingMouse = false
        swallowingEscape = false
        focusTracker.watch(nil)
    }

    @objc private func quit() { NSApp.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) {
        updater.stop()
        permissionTimer?.invalidate()
        cancelSelection()
        stopEventTap()
        focusTracker.stop()
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
