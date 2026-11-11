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
        sizeChanged = !WindowSizeAdvice.matches(actual.size, requested.size, scale: scale)
        let positionChanged = (actual.minX * scale).rounded() != (requested.minX * scale).rounded() ||
            (actual.minY * scale).rounded() != (requested.minY * scale).rounded()
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
        if positionChanged { messages.append("위치는 앱이 허용하는 범위로 배치됐습니다.") }
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

    static func capture(application app: NSRunningApplication) throws -> WindowTarget {
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
        let window = value as! AXUIElement
        AXUIElementSetMessagingTimeout(window, 0.4)
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
        let original = try readFrame(of: window)
        return WindowTarget(element: window, application: app,
                            name: app.localizedName ?? "선택한 앱", originalFrame: original,
                            sizeAdvice: sizeAdvice(of: window))
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

    static func apply(_ rect: CGRect, to target: WindowTarget, scale: CGFloat) throws -> WindowPlacement {
        guard SelectionGeometry.isValid(rect), !target.application.isTerminated else {
            throw WindowFailure(message: "선택 영역이 올바르지 않거나 대상 앱이 종료되었습니다.")
        }
        // 화면마다 허용 크기가 달라 이동 후 크기를 적용하고 요청한 위치를 다시 지정합니다.
        let move = setPosition(rect.origin, on: target.element)
        guard move == .success else {
            throw WindowFailure(message: "창 이동이 거부되었습니다 (\(move.rawValue)).", axError: move)
        }
        let resize = setSize(rect.size, on: target.element)
        let align = setPosition(rect.origin, on: target.element)
        // shortcut: 비동기 변경을 0.4초 뒤 확인합니다. 더 늦게 바뀌는 앱은 관찰 방식으로 확장합니다.
        Thread.sleep(forTimeInterval: 0.4)
        guard let actual = frame(of: target.element) else {
            throw WindowFailure(message: "변경 결과를 확인할 수 없습니다. 현재 창 상태를 확인해 주세요.")
        }
        let result = WindowPlacement(requested: rect, actual: actual, advice: target.sizeAdvice, scale: scale)
        if result.warning != nil || (resize == .success && align == .success) { return result }
        throw WindowFailure(message: "창 변경 요청 중 오류가 발생했습니다. 현재 창 상태를 확인해 주세요.")
    }
}
