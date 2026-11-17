import AppKit

struct InteractionSessionState {
    static let locked = Notification.Name("com.apple.screenIsLocked")
    static let unlocked = Notification.Name("com.apple.screenIsUnlocked")
    private var sleeping = false
    private var screenLocked = false
    private var inactive = false
    private(set) var revision: UInt64 = 0

    var available: Bool { !sleeping && !screenLocked && !inactive }
    var waitingForUnlock: Bool { screenLocked && !sleeping && !inactive }

    mutating func receive(_ name: Notification.Name) {
        switch name {
        case NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification: sleeping = true
        case NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification: sleeping = false
        case Self.locked: screenLocked = true
        case Self.unlocked: screenLocked = false
        case NSWorkspace.sessionDidResignActiveNotification: inactive = true
        case NSWorkspace.sessionDidBecomeActiveNotification: inactive = false
        default: return
        }
        revision &+= 1
    }
}

struct InputConnectionState {
    let trusted: Bool
    let drawEnabled: Bool
    let connected: Bool
    var sessionAvailable = true

    var shouldConnect: Bool { trusted && sessionAvailable }
    var keyboardEnabled: Bool { shouldConnect && connected }
    var drawingEnabled: Bool { keyboardEnabled && drawEnabled }
    var title: String {
        if !trusted { return "상태: 손쉬운 사용 권한 필요" }
        if !sessionAvailable { return "상태: 화면 잠금·절전 중" }
        return connected ? "키보드 배치: 사용 가능" : "상태: 입력 감지 연결 필요"
    }
}

struct InteractionDiagnostics {
    var lastInputMilliseconds = 0.0
    var maximumInputMilliseconds = 0.0
    var preparationMilliseconds = 0.0
    var lookupMilliseconds = 0.0
    var timeoutCount = 0
    var retryCount = 0
    var lastCancellation = "없음"
    var lastPlacement = "아직 없음"
    private(set) var recoveryStartedAt: TimeInterval?
    private(set) var recoveryMilliseconds: Double?
    private(set) var recoveryReason = "없음"
    private(set) var keyboardEvents: [String] = []

    mutating func recordKeyboard(_ message: String, at date: Date = Date()) {
        let time = DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .medium)
        keyboardEvents.append("\(time) · \(message)")
        if keyboardEvents.count > 8 { keyboardEvents.removeFirst(keyboardEvents.count - 8) }
    }

    mutating func beginRecovery(_ reason: String, at time: TimeInterval = Date.timeIntervalSinceReferenceDate) {
        recoveryReason = reason
        recoveryStartedAt = time
        recoveryMilliseconds = nil
    }

    mutating func finishRecovery(at time: TimeInterval = Date.timeIntervalSinceReferenceDate) {
        guard let started = recoveryStartedAt else { return }
        recoveryMilliseconds = max(0, time - started) * 1000
        recoveryStartedAt = nil
    }

    mutating func recordPlacement(requested: CGRect, actual: CGRect, scale: CGFloat) {
        lastPlacement = String(format: "논리 좌표 요청 (%.4f, %.4f, %.4f, %.4f) · 실제 (%.4f, %.4f, %.4f, %.4f) · 위치 차이 (%.4f, %.4f) px",
                               requested.minX, requested.minY, requested.width, requested.height,
                               actual.minX, actual.minY, actual.width, actual.height,
                               (actual.minX - requested.minX) * scale, (actual.minY - requested.minY) * scale)
    }

    mutating func recordInput(seconds: Double) {
        lastInputMilliseconds = seconds * 1000
        maximumInputMilliseconds = max(maximumInputMilliseconds, lastInputMilliseconds)
    }

    var summary: String {
        String(format: "입력 최대 %.2f ms · 화면 준비 %.2f ms · 창 조회 %.2f ms · 시간 초과 %d · 재조회 %d · 취소: %@",
               maximumInputMilliseconds, preparationMilliseconds, lookupMilliseconds,
               timeoutCount, retryCount, lastCancellation) + "\n배치: " + lastPlacement +
            "\n복구: \(recoveryReason) · " + (recoveryMilliseconds.map { String(format: "%.2f ms", $0) } ??
                                           (recoveryStartedAt == nil ? "대기" : "복구 중")) +
            (keyboardEvents.isEmpty ? "" : "\n최근 단축키:\n" + keyboardEvents.joined(separator: "\n"))
    }
}
