import Foundation

struct InputConnectionState {
    let trusted: Bool
    let requestedEnabled: Bool
    let connected: Bool

    var shouldConnect: Bool { trusted && requestedEnabled }
    var title: String {
        if !trusted { return "상태: 손쉬운 사용 권한 필요" }
        if !requestedEnabled { return "상태: 꺼짐" }
        return connected ? "상태: 켜짐 · ⌘⇧ 드래그" : "상태: 입력 감지 연결 필요"
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
               timeoutCount, retryCount, lastCancellation) + "\n배치: " + lastPlacement
    }
}
