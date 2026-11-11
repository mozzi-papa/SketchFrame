import Foundation

struct InteractionDiagnostics {
    var lastInputMilliseconds = 0.0
    var maximumInputMilliseconds = 0.0
    var preparationMilliseconds = 0.0
    var lookupMilliseconds = 0.0
    var timeoutCount = 0
    var retryCount = 0
    var lastCancellation = "없음"

    mutating func recordInput(seconds: Double) {
        lastInputMilliseconds = seconds * 1000
        maximumInputMilliseconds = max(maximumInputMilliseconds, lastInputMilliseconds)
    }

    var summary: String {
        String(format: "입력 최대 %.2f ms · 화면 준비 %.2f ms · 창 조회 %.2f ms · 시간 초과 %d · 재조회 %d · 취소: %@",
               maximumInputMilliseconds, preparationMilliseconds, lookupMilliseconds,
               timeoutCount, retryCount, lastCancellation)
    }
}
