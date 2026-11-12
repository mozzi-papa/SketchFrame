import AppKit
import ApplicationServices

struct WindowFailure: LocalizedError {
    let message: String
    var axError: AXError? = nil
    var errorDescription: String? { message }
}

struct WindowSizeAdvice {
    var minimum: CGSize?
    var maximum: CGSize?

    func warning(for size: CGSize, scale: CGFloat) -> String? {
        if let minimum = minimum, size.width < minimum.width || size.height < minimum.height {
            return "해당 크기를 지원하지 않습니다 · 최소 \(SelectionGeometry.pixelSizeLabel(minimum, scale: scale))"
        }
        if let maximum = maximum, size.width > maximum.width || size.height > maximum.height {
            return "해당 크기를 지원하지 않습니다 · 최대 \(SelectionGeometry.pixelSizeLabel(maximum, scale: scale))"
        }
        return nil
    }

    static func matches(_ lhs: CGSize, _ rhs: CGSize, scale: CGFloat) -> Bool {
        SelectionGeometry.matches(CGRect(origin: .zero, size: lhs), CGRect(origin: .zero, size: rhs), scale: scale)
    }
}

struct WindowTarget {
    let element: AXUIElement
    let application: NSRunningApplication
    let name: String
    let originalFrame: CGRect
    var sizeAdvice = WindowSizeAdvice()
}

struct WindowPlacement {
    let frame: CGRect
    let sizeChanged: Bool
    let warning: String?

    init(requested: CGRect, actual: CGRect, advice: WindowSizeAdvice, scale: CGFloat) {
        frame = actual
        // 창 시스템의 반올림을 고려해 가로·세로 각각 4 렌더링 px 이내 차이는 허용합니다.
        let differences = [actual.width - requested.width, actual.height - requested.height]
        sizeChanged = !scale.isFinite || scale <= 0 || differences.contains {
            !$0.isFinite || abs($0 * scale) > 4 + 0.000001
        }
        var messages: [String] = []
        if sizeChanged {
            let minimumExplainsChange = advice.minimum.map {
                (requested.width < $0.width || requested.height < $0.height) &&
                    WindowSizeAdvice.matches(actual.size, CGSize(width: max(requested.width, $0.width),
                                                                 height: max(requested.height, $0.height)), scale: scale)
            } ?? false
            messages.append(minimumExplainsChange
                ? "앱의 최소 크기 제한으로 선택한 영역보다 크게 배치됐습니다."
                : "앱의 크기 제한으로 선택한 영역과 다르게 배치됐습니다.")
        }
        warning = messages.isEmpty ? nil : messages.joined(separator: " ") +
            "\n요청 \(SelectionGeometry.pixelSizeLabel(requested.size, scale: scale)) · 실제 \(SelectionGeometry.pixelSizeLabel(actual.size, scale: scale))"
    }
}

struct RejectedSizeCache {
    private var entries: [(target: WindowTarget, size: CGSize)] = []

    func contains(_ size: CGSize, for target: WindowTarget, scale: CGFloat) -> Bool {
        entries.contains { Self.sameWindow($0.target, target) && WindowSizeAdvice.matches($0.size, size, scale: scale) }
    }

    mutating func forget(_ size: CGSize, for target: WindowTarget, scale: CGFloat) {
        entries.removeAll { Self.sameWindow($0.target, target) && WindowSizeAdvice.matches($0.size, size, scale: scale) }
    }

    mutating func record(_ size: CGSize, for target: WindowTarget, scale: CGFloat) {
        guard SelectionGeometry.isValid(CGRect(origin: .zero, size: size)) else { return }
        forget(size, for: target, scale: scale)
        entries.append((target, size))
        if entries.count > 32 { entries.removeFirst() }
    }

    private static func sameWindow(_ lhs: WindowTarget, _ rhs: WindowTarget) -> Bool {
        lhs.application.processIdentifier == rhs.application.processIdentifier && CFEqual(lhs.element, rhs.element)
    }
}

enum WindowController {
    static func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    static func frame(of window: AXUIElement) -> CGRect? {
        try? readFrame(of: window)
    }

    private static func requiredAttribute(_ name: String, of element: AXUIElement) throws -> CFTypeRef {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        guard error == .success, let value = value else {
            throw WindowFailure(message: "창 정보 조회에 실패했습니다 (\(error.rawValue)).", axError: error)
        }
        return value
    }

    private static func readFrame(of window: AXUIElement) throws -> CGRect {
        let position = try requiredAttribute(kAXPositionAttribute, of: window)
        let size = try requiredAttribute(kAXSizeAttribute, of: window)
        guard CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else {
            throw WindowFailure(message: "창의 위치·크기 정보 형식이 올바르지 않습니다.")
        }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions),
              point.x.isFinite, point.y.isFinite,
              dimensions.width.isFinite, dimensions.height.isFinite,
              dimensions.width > 0, dimensions.height > 0 else {
            throw WindowFailure(message: "창의 위치·크기를 읽을 수 없습니다.")
        }
        return CGRect(origin: point, size: dimensions)
    }

    private static func sizeAdvice(of window: AXUIElement) -> WindowSizeAdvice {
        var attributes: CFArray?
        guard AXUIElementCopyAttributeNames(window, &attributes) == .success,
              let names = attributes as? [String] else { return WindowSizeAdvice() }
        func read(_ candidates: [String]) -> CGSize? {
            for name in candidates where names.contains(name) {
                guard let value = attribute(name, of: window), CFGetTypeID(value) == AXValueGetTypeID() else { continue }
                var size = CGSize.zero
                if AXValueGetValue(value as! AXValue, .cgSize, &size),
                   SelectionGeometry.isValid(CGRect(origin: .zero, size: size)) { return size }
            }
            return nil
        }
        return WindowSizeAdvice(minimum: read(["AXMinSize", "AXMinimumSize"]),
                                maximum: read(["AXMaxSize", "AXMaximumSize"]))
    }

    static func focusedWindow(application app: NSRunningApplication) throws -> AXUIElement {
        guard AXIsProcessTrusted() else {
            throw WindowFailure(message: "손쉬운 사용 권한을 먼저 허용해 주세요.")
        }
        guard !app.isTerminated,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            throw WindowFailure(message: "이동할 앱의 창을 먼저 선택해 주세요.")
        }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.4)
        let value = try requiredAttribute(kAXFocusedWindowAttribute, of: element)
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
            throw WindowFailure(message: "현재 앱에서 조절할 창을 찾을 수 없습니다.")
        }
        return value as! AXUIElement
    }

    static func confirmFocusedWindow(_ window: AXUIElement, application app: NSRunningApplication) throws {
        guard CFEqual(window, try focusedWindow(application: app)) else {
            throw WindowFailure(message: "대상 창이 바뀌어 선택을 취소했습니다. 창을 선택한 뒤 다시 그려 주세요.")
        }
    }

    static func capture(application app: NSRunningApplication, window: AXUIElement, inspectSize: Bool = true) throws -> WindowTarget {
        try confirmFocusedWindow(window, application: app)
        AXUIElementSetMessagingTimeout(window, 0.4)
        if inspectSize {
            guard attribute("AXFullScreen", of: window) as? Bool != true else {
                throw WindowFailure(message: "전체 화면 모드를 해제한 뒤 사용해 주세요.")
            }
            for key in [kAXPositionAttribute, kAXSizeAttribute] {
                var settable = DarwinBoolean(false)
                let error = AXUIElementIsAttributeSettable(window, key as CFString, &settable)
                guard error == .success, settable.boolValue else {
                    throw WindowFailure(message: "이 창은 위치 또는 크기 변경을 지원하지 않습니다.", axError: error)
                }
            }
        }
        let original = try readFrame(of: window)
        return WindowTarget(element: window, application: app,
                            name: app.localizedName ?? "선택한 앱", originalFrame: original,
                            sizeAdvice: inspectSize ? sizeAdvice(of: window) : WindowSizeAdvice())
    }

    private static func setPosition(_ point: CGPoint, on window: AXUIElement) -> AXError {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return .failure }
        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
    }

    private static func setSize(_ size: CGSize, on window: AXUIElement) -> AXError {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return .failure }
        return AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
    }

    private static func requestFrame(_ rect: CGRect, to target: WindowTarget) throws -> (resize: AXError, align: AXError) {
        guard SelectionGeometry.isValid(rect), !target.application.isTerminated else {
            throw WindowFailure(message: "선택 영역이 올바르지 않거나 대상 앱이 종료되었습니다.")
        }
        try confirmFocusedWindow(target.element, application: target.application)
        // 화면마다 허용 크기가 달라 이동 후 크기를 적용하고 요청한 위치를 다시 지정합니다.
        let move = setPosition(rect.origin, on: target.element)
        guard move == .success else {
            throw WindowFailure(message: "창 이동이 거부되었습니다 (\(move.rawValue)).", axError: move)
        }
        let resize = setSize(rect.size, on: target.element)
        let align = setPosition(rect.origin, on: target.element)
        return (resize, align)
    }

    static func applyWithoutSizeCheck(_ rect: CGRect, to target: WindowTarget) throws {
        let errors = try requestFrame(rect, to: target)
        guard errors.resize == .success, errors.align == .success else {
            throw WindowFailure(message: "창 변경 요청 중 오류가 발생했습니다. 현재 창 상태를 확인해 주세요.")
        }
    }

    static func apply(_ rect: CGRect, to target: WindowTarget, scale: CGFloat) throws -> WindowPlacement {
        let errors = try requestFrame(rect, to: target)
        // shortcut: 비동기 변경을 0.4초 뒤 확인합니다. 더 늦게 바뀌는 앱은 관찰 방식으로 확장합니다.
        Thread.sleep(forTimeInterval: 0.4)
        guard let actual = frame(of: target.element) else {
            throw WindowFailure(message: "변경 결과를 확인할 수 없습니다. 현재 창 상태를 확인해 주세요.")
        }
        let result = WindowPlacement(requested: rect, actual: actual, advice: target.sizeAdvice, scale: scale)
        if result.warning != nil || (errors.resize == .success && errors.align == .success) { return result }
        throw WindowFailure(message: "창 변경 요청 중 오류가 발생했습니다. 현재 창 상태를 확인해 주세요.")
    }
}

struct FocusedWindowReference {
    let application: NSRunningApplication
    let window: AXUIElement
    let revision: UInt64

    func isCurrent(application: NSRunningApplication?, revision: UInt64) -> Bool {
        application?.processIdentifier == self.application.processIdentifier && self.revision == revision
    }
}

final class FocusedWindowTracker {
    private let queue: DispatchQueue
    private let onChange: () -> Void
    private var application: NSRunningApplication?
    private var observer: AXObserver?
    private var revision: UInt64 = 0
    private var cached: FocusedWindowReference?
    private var installing = false
    private var loading = false
    private(set) var message = "대상 창을 확인 중입니다. 잠시 뒤 다시 그려 주세요."

    init(queue: DispatchQueue, onChange: @escaping () -> Void) {
        self.queue = queue
        self.onChange = onChange
    }

    func reference(for app: NSRunningApplication?) -> FocusedWindowReference? {
        guard let cached = cached, !cached.application.isTerminated,
              cached.isCurrent(application: app, revision: revision) else { return nil }
        return cached
    }

    func isCurrent(_ reference: FocusedWindowReference) -> Bool {
        reference.isCurrent(application: application, revision: revision) && cached != nil
    }

    func watch(_ app: NSRunningApplication?) {
        if application?.processIdentifier == app?.processIdentifier {
            if app == nil || installing { return }
            if observer != nil {
                if cached == nil && !loading { focusChanged() }
                return
            }
        }
        stop()
        guard let app = app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        application = app
        installing = true
        let expected = revision
        queue.async {
            var created: AXObserver?
            let callback: AXObserverCallback = { observer, _, _, context in
                guard let context = context else { return }
                let tracker = Unmanaged<FocusedWindowTracker>.fromOpaque(context).takeUnretainedValue()
                guard let current = tracker.observer, CFEqual(current, observer) else { return }
                tracker.focusChanged()
            }
            let creation = AXObserverCreate(app.processIdentifier, callback, &created)
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.4)
            let registration = created.map {
                AXObserverAddNotification($0, element, kAXFocusedWindowChangedNotification as CFString,
                                          Unmanaged.passUnretained(self).toOpaque())
            } ?? creation
            DispatchQueue.main.async {
                guard self.revision == expected, self.application?.processIdentifier == app.processIdentifier else { return }
                self.installing = false
                guard creation == .success, registration == .success, let observer = created else {
                    self.message = "이 앱의 창 변경을 확인할 수 없습니다. 다른 창에서 다시 시도해 주세요."
                    return
                }
                self.observer = observer
                CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
                self.focusChanged()
            }
        }
    }

    private func focusChanged() {
        revision &+= 1
        cached = nil
        message = "대상 창을 확인 중입니다. 잠시 뒤 다시 그려 주세요."
        onChange()
        guard let app = application else { return }
        loadWindow(app, revision: revision)
    }

    private func loadWindow(_ app: NSRunningApplication, revision expected: UInt64, attempt: Int = 0) {
        loading = true
        queue.async {
            let result = Result { try WindowController.focusedWindow(application: app) }
            DispatchQueue.main.async {
                guard self.revision == expected, self.application?.processIdentifier == app.processIdentifier else { return }
                switch result {
                case .success(let window):
                    self.loading = false
                    self.cached = FocusedWindowReference(application: app, window: window, revision: expected)
                case .failure(let error):
                    if (error as? WindowFailure)?.axError == .cannotComplete && attempt == 0 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                            guard self.revision == expected else { return }
                            self.loadWindow(app, revision: expected, attempt: 1)
                        }
                    } else {
                        self.loading = false
                        self.message = "대상 창을 확인할 수 없습니다. 창을 선택한 뒤 다시 시도해 주세요."
                    }
                }
            }
        }
    }

    func stop() {
        revision &+= 1
        cached = nil
        application = nil
        if let observer = observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        installing = false
        loading = false
        onChange()
    }
}
