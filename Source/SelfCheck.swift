import AppKit
import ApplicationServices

enum SelfCheck {
    static func run() {
        var count = 0
        func check(_ condition: Bool, _ description: String) {
            guard condition else { fatalError("검사 실패: \(description)") }
            count += 1
        }
        let expected = CGRect(x: 5, y: 5, width: 100, height: 200)
        let corners = [CGPoint(x: 5, y: 5), CGPoint(x: 105, y: 205),
                       CGPoint(x: 5, y: 205), CGPoint(x: 105, y: 5)]
        for (a, b) in [(0, 1), (1, 0), (2, 3), (3, 2)] {
            check(SelectionGeometry.rectangle(from: corners[a], to: corners[b]) == expected, "네 방향 원본 영역")
        }
        for end in [CGPoint(x: 719, y: 449), CGPoint(x: 1439, y: 899), CGPoint(x: -50, y: -20)] {
            let rect = SelectionGeometry.rectangle(from: .zero, to: end)
            check(rect == CGRect(x: min(0, end.x), y: min(0, end.y), width: abs(end.x), height: abs(end.y)),
                  "중앙·가장자리·화면 밖에서도 좌표 보존")
        }
        check(SelectionGeometry.isValid(CGRect(x: 5, y: 5, width: 1, height: 1)), "최소 크기 강제 없음")
        check(!SelectionGeometry.isValid(.zero), "너비나 높이가 없는 영역 거부")
        check(!SelectionGeometry.isValid(CGRect(x: 0, y: 0, width: 0, height: 10)), "선만 그리기 거부")
        check(!SelectionGeometry.isValid(CGRect(x: CGFloat.infinity, y: 0, width: 10, height: 10)), "무한 좌표 거부")
        check(!SelectionGeometry.isValid(CGRect(x: 0, y: 0, width: CGFloat.nan, height: 10)), "잘못된 크기 거부")
        check(SelectionGeometry.pixelSizeLabel(CGSize(width: 529, height: 664), scale: 2) == "1058 × 1328 px", "2배 픽셀 표시")
        check(SelectionGeometry.pixelSizeLabel(CGSize(width: 529, height: 664), scale: 1) == "529 × 664 px", "1배 픽셀 표시")
        check(SelectionGeometry.quartzRect(from: CGRect(x: -800, y: 200, width: 800, height: 600), primaryTop: 900)
              == CGRect(x: -800, y: 100, width: 800, height: 600), "보조 화면 좌표 변환")
        check(SelectionGeometry.matches(expected, expected, scale: 2), "원본 배치 일치")
        check(!SelectionGeometry.matches(expected.offsetBy(dx: 1, dy: 0), expected), "1픽셀 위치 차이 거부")
        check(!SelectionGeometry.matches(expected.insetBy(dx: 0, dy: -1), expected), "크기 차이 거부")
        check(!SelectionGeometry.matches(expected.offsetBy(dx: 0.5, dy: 0), expected, scale: 2), "2배 화면 1픽셀 차이 거부")
        check(SelectionGeometry.matches(expected.offsetBy(dx: 0.1, dy: 0), expected, scale: 2), "동일 렌더링 픽셀 허용")
        check(!SelectionGeometry.matches(.zero, expected), "읽기 실패를 성공으로 판단하지 않음")
        let advice = WindowSizeAdvice(minimum: CGSize(width: 500, height: 300), maximum: CGSize(width: 1200, height: 900))
        check(advice.warning(for: CGSize(width: 499, height: 400), scale: 2)?.contains("최소 1000 × 600 px") == true,
              "최소 너비 사전 안내와 배율")
        check(advice.warning(for: CGSize(width: 600, height: 299), scale: 1) != nil, "최소 높이 사전 안내")
        check(advice.warning(for: CGSize(width: 1201, height: 400), scale: 1)?.contains("최대") == true, "최대 너비 사전 안내")
        check(advice.warning(for: CGSize(width: 600, height: 901), scale: 1) != nil, "최대 높이 사전 안내")
        check(advice.warning(for: CGSize(width: 500, height: 300), scale: 1) == nil, "최소 경계 허용")
        check(advice.warning(for: CGSize(width: 1200, height: 900), scale: 1) == nil, "최대 경계 허용")
        check(WindowSizeAdvice().warning(for: CGSize(width: 10, height: 10), scale: 1) == nil, "모르는 제한 추정 금지")
        let small = CGRect(x: 100, y: 150, width: 34, height: 46)
        let larger = CGRect(x: 100, y: 150, width: 400, height: 300)
        let unknownPlacement = WindowPlacement(requested: small, actual: larger, advice: WindowSizeAdvice(), scale: 2)
        check(unknownPlacement.frame == larger, "크기 불일치에서도 실제 이동 결과 유지")
        check(unknownPlacement.sizeChanged, "크기 불일치 기록")
        check(unknownPlacement.warning?.contains("앱의 크기 제한으로 선택한 영역과 다르게 배치됐습니다.") == true,
              "원인을 모르면 일반 크기 제한 안내")
        check(unknownPlacement.warning?.contains("요청 68 × 92 px · 실제 800 × 600 px") == true, "요청·실제 픽셀 크기 안내")
        let minimumPlacement = WindowPlacement(requested: small, actual: larger,
                                               advice: WindowSizeAdvice(minimum: larger.size), scale: 2)
        check(minimumPlacement.warning?.contains("앱의 최소 크기 제한으로 선택한 영역보다 크게 배치됐습니다.") == true,
              "확인된 최소 크기만 원인으로 안내")
        let unexplained = WindowPlacement(requested: small, actual: larger,
                                         advice: WindowSizeAdvice(minimum: CGSize(width: 200, height: 200)), scale: 2)
        check(unexplained.warning?.contains("최소 크기 제한") == false, "관측값이 최소값과 다르면 원인 추정 금지")
        let exact = WindowPlacement(requested: expected, actual: expected, advice: advice, scale: 2)
        check(exact.warning == nil && !exact.sizeChanged, "정확히 배치되면 경고 없음")
        let shifted = WindowPlacement(requested: expected, actual: expected.offsetBy(dx: 10, dy: 0), advice: advice, scale: 2)
        check(shifted.warning?.contains("위치는 앱이 허용하는 범위로 배치됐습니다.") == true && !shifted.sizeChanged,
              "위치 제한은 크기 제한과 구분")
        let reduced = WindowPlacement(requested: larger, actual: small, advice: advice, scale: 2)
        check(reduced.warning?.contains("최소 크기 제한") == false, "작아진 결과를 최소 크기 제한으로 오인하지 않음")
        check(WindowSizeAdvice.matches(CGSize(width: 100, height: 200), CGSize(width: 100.1, height: 200), scale: 2),
              "실패 기록의 동일 렌더링 픽셀 비교")
        check(!WindowSizeAdvice.matches(CGSize(width: 100, height: 200), CGSize(width: 100.5, height: 200), scale: 2),
              "다른 크기에 실패 기록 전파 금지")
        let own = NSRunningApplication.current
        let target = WindowTarget(element: AXUIElementCreateApplication(own.processIdentifier), application: own,
                                  name: "검사용 대상", originalFrame: expected)
        let other = WindowTarget(element: AXUIElementCreateApplication(0), application: own,
                                 name: "다른 대상", originalFrame: expected)
        var cache = RejectedSizeCache()
        cache.record(expected.size, for: target, scale: 2)
        check(cache.contains(expected.size, for: target, scale: 2), "거부 크기 메모리 기록")
        check(!cache.contains(expected.size, for: other, scale: 2), "다른 창으로 경고 전파 금지")
        check(!cache.contains(CGSize(width: 101, height: 200), for: target, scale: 2), "다른 크기는 재검증")
        cache.forget(expected.size, for: target, scale: 2)
        check(!cache.contains(expected.size, for: target, scale: 2), "성공한 크기의 오래된 경고 삭제")
        cache.record(.zero, for: target, scale: 2)
        check(!cache.contains(.zero, for: target, scale: 2), "잘못된 기록 거부")
        for width in 1...33 { cache.record(CGSize(width: width, height: 200), for: target, scale: 2) }
        check(!cache.contains(CGSize(width: 1, height: 200), for: target, scale: 2), "오래된 기록 제한")
        check(cache.contains(CGSize(width: 33, height: 200), for: target, scale: 2), "최신 기록 유지")
        check(SelectionGeometry.rectangle(from: corners[0], to: corners[1]) == expected, "경고 조회 후에도 원본 영역 유지")
        var diagnostics = InteractionDiagnostics()
        diagnostics.recordInput(seconds: 0.001)
        diagnostics.recordInput(seconds: 0.0005)
        check(diagnostics.maximumInputMilliseconds == 1, "입력 최대 시간")
        check(diagnostics.summary.contains("시간 초과 0"), "시간 초과 진단")
        print("자체 검사 \(count)개 통과")
    }
}
