import AppKit
import ApplicationServices

private final class ShortcutMemoryDefaults: UserDefaults {
    var values: [String: Any] = [:]
    override func data(forKey defaultName: String) -> Data? { values[defaultName] as? Data }
    override func set(_ value: Any?, forKey defaultName: String) { values[defaultName] = value }
    override func removeObject(forKey defaultName: String) { values.removeValue(forKey: defaultName) }
}

private final class UpdateMockProtocol: URLProtocol {
    static var responseData = Data("[]".utf8)
    static var responseStatus = 200
    static var holdResponses = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if Self.holdResponses { return }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.responseStatus, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

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
        check(shifted.warning == nil && !shifted.sizeChanged, "위치만 달라지면 빨간 경고 없음")
        let boundary = CGRect(x: 100.249, y: 200, width: 879, height: 993)
        let rounded = WindowPlacement(requested: boundary, actual: boundary.offsetBy(dx: 0.002, dy: 0), advice: advice, scale: 2)
        check(rounded.warning == nil, "반올림 경계의 미세 위치 차이로 경고하지 않음")
        for scale: CGFloat in [1, 2] {
            let request = CGRect(x: 100, y: 150, width: 1280 / scale, height: 1333 / scale)
            for (widthDelta, heightDelta, shouldWarn): (CGFloat, CGFloat, Bool) in [
                (0, -1, false), (-4, 4, false), (4, -4, false),
                (4.01, 0, true), (0, -4.01, true), (-5, 0, true), (0, 5, true)
            ] {
                let actual = CGRect(origin: request.origin,
                                    size: CGSize(width: request.width + widthDelta / scale,
                                                 height: request.height + heightDelta / scale))
                let placement = WindowPlacement(requested: request, actual: actual, advice: WindowSizeAdvice(), scale: scale)
                check(placement.sizeChanged == shouldWarn && (placement.warning != nil) == shouldWarn,
                      "\(scale)배 화면 가로 \(widthDelta)px·세로 \(heightDelta)px 차이 경고 경계")
                check(placement.frame == actual, "허용 오차 판정에서도 실제 배치 유지")
            }
        }
        check(shifted.frame == expected.offsetBy(dx: 10, dy: 0), "위치 차이가 있어도 실제 배치 유지")
        let reduced = WindowPlacement(requested: larger, actual: small, advice: advice, scale: 2)
        check(reduced.warning?.contains("최소 크기 제한") == false, "작아진 결과를 최소 크기 제한으로 오인하지 않음")
        check(WindowSizeAdvice.matches(CGSize(width: 100, height: 200), CGSize(width: 100.1, height: 200), scale: 2),
              "실패 기록의 동일 렌더링 픽셀 비교")
        check(!WindowSizeAdvice.matches(CGSize(width: 100, height: 200), CGSize(width: 100.5, height: 200), scale: 2),
              "다른 크기에 실패 기록 전파 금지")
        // CLI 검사 프로세스도 살아 있는 앱으로 등록해 복원 기록을 검사합니다.
        NSApplication.shared.setActivationPolicy(.prohibited)
        let own = NSRunningApplication.current
        let reference = FocusedWindowReference(application: own, window: AXUIElementCreateApplication(own.processIdentifier), revision: 7)
        check(reference.isCurrent(application: own, revision: 7), "현재 앱과 창 조회 세대 일치")
        check(!reference.isCurrent(application: own, revision: 8), "창 변경 후 이전 조회 결과 거부")
        check(!reference.isCurrent(application: nil, revision: 7), "대상 앱 미확정 상태 거부")
        let target = WindowTarget(element: AXUIElementCreateApplication(own.processIdentifier), application: own,
                                  name: "검사용 대상", originalFrame: expected)
        let other = WindowTarget(element: AXUIElementCreateApplication(0), application: own,
                                 name: "다른 대상", originalFrame: expected)
        func observedTarget(_ rectangle: CGRect) -> WindowTarget {
            WindowTarget(element: target.element, application: own, name: target.name, originalFrame: rectangle)
        }
        let history = WindowHistory()
        history.record(before: expected, after: nil, for: target, scale: 2)
        check(history.restoreFrame(for: observedTarget(larger), scale: 2) == expected,
              "결과 미검사 키보드 배치에서도 최초 복원 기준 유지")
        history.record(before: larger, after: nil, for: observedTarget(larger), scale: 2)
        check(history.restoreFrame(for: observedTarget(small), scale: 2) == expected,
              "연속 키보드 배치에서 앱의 크기 제한으로 복원 기준을 덮어쓰지 않음")
        check(history.restoreFrame(for: other, scale: 2) == nil, "다른 창의 복원 기록 분리")
        history.record(before: small, after: nil, for: observedTarget(small), scale: 2, restored: true)
        check(history.restoreFrame(for: target, scale: 2) == nil, "키보드 복원 요청 완료 후 기록 해제")
        history.record(before: expected, after: larger, for: target, scale: 2)
        check(history.restoreFrame(for: observedTarget(larger), scale: 2) == expected, "검증된 자유 그리기의 복원 기준 유지")
        check(history.restoreFrame(for: observedTarget(small), scale: 2) == small, "검증된 배치 이후 외부 이동은 복원 기준 갱신")
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
        diagnostics.recordPlacement(requested: boundary, actual: boundary.offsetBy(dx: 0.002, dy: 0), scale: 2)
        check(diagnostics.lastPlacement.contains("100.2490") && diagnostics.lastPlacement.contains("100.2510"), "요청·실제 원본 위치 진단")
        check(diagnostics.lastPlacement.contains("0.0040"), "배율 반영 위치 차이 진단")
        for trusted in [false, true] {
            for requested in [false, true] {
                for connected in [false, true] {
                    let state = InputConnectionState(trusted: trusted, requestedEnabled: requested, connected: connected)
                    check(state.shouldConnect == (trusted && requested), "권한과 사용자 설정에 따른 연결 정책")
                    let expectedTitle = !trusted ? "상태: 손쉬운 사용 권한 필요" :
                        (!requested ? "상태: 꺼짐" : (connected ? "상태: 켜짐 · ⌘⇧ 드래그" : "상태: 입력 감지 연결 필요"))
                    check(state.title == expectedTitle, "실제 연결 상태에 따른 메뉴 표시")
                }
            }
        }
        let preferences = ShortcutMemoryDefaults()
        preferences.values["unrelated"] = "유지"
        let settings = ShortcutSettings(defaults: preferences)
        let controlOption = CGEventFlags([.maskControl, .maskAlternate]).rawValue
        check(WindowAction.allCases.count == 19 && WindowAction.leftColumn.count == 9 && WindowAction.rightColumn.count == 9,
              "스크린샷 18개와 자유 영역 그리기만 포함")
        check(preferences.values[ShortcutSettings.storageKey] == nil, "시작할 때 기본값을 디스크에 쓰지 않음")
        let enabledBindings = WindowAction.allCases.map { settings.binding(for: $0) }.filter { !$0.disabled }
        check(enabledBindings.count == 17, "가운데 절반·거의 최대화는 미지정")
        for action in WindowAction.allCases {
            check(settings.binding(for: action).validationError(for: action) == nil, "기본 단축키 유효성: \(action.title)")
        }
        check(settings.action(for: 123, flags: controlOption) == .leftHalf, "Rectangle 왼쪽 절반 기본키")
        check(settings.action(for: 123, flags: controlOption | CGEventFlags.maskCommand.rawValue) == .previousDisplay,
              "추가 조합키를 구분")
        check(settings.action(for: 123, flags: controlOption | CGEventFlags.maskAlphaShift.rawValue) == .leftHalf,
              "Caps Lock 상태와 무관하게 키 인식")
        let custom = ShortcutBinding(keyCode: 4, modifiers: controlOption)
        check(settings.set(custom, for: .centerHalf) == nil, "사용자 키 등록")
        check(settings.set(custom, for: .almostMaximize) != nil && settings.binding(for: .almostMaximize).disabled,
              "중복 키 거부 후 기존 설정 유지")
        check(ShortcutSettings(defaults: preferences).binding(for: .centerHalf) == custom, "직렬화 후 사용자 키 복원")
        check(settings.set(.unassigned, for: .leftHalf) == nil, "기본 키 해제")
        check(ShortcutSettings(defaults: preferences).binding(for: .leftHalf).disabled, "재시작 후 해제 상태 유지")
        let drag = ShortcutBinding(keyCode: nil, modifiers: controlOption)
        let threeModifiers = controlOption | CGEventFlags.maskShift.rawValue
        var recordedModifiers: UInt64 = 0
        for flags in [CGEventFlags.maskControl.rawValue, controlOption, threeModifiers, controlOption, CGEventFlags.maskControl.rawValue, 0] {
            recordedModifiers = ShortcutRecorderView.modifierCandidate(previous: recordedModifiers, current: flags)
        }
        check(recordedModifiers == threeModifiers, "세 조합키를 놓을 때 두 조합으로 줄어들지 않음")
        let fourModifiers = threeModifiers | CGEventFlags.maskCommand.rawValue
        check(ShortcutRecorderView.modifierCandidate(previous: fourModifiers, current: controlOption) == fourModifiers,
              "네 조합키도 해제 순서와 무관하게 유지")
        check(settings.set(drag, for: .drawRegion) == nil, "자유 드래그 조합 변경")
        check(settings.binding(for: .drawRegion).matchesDrag(flags: controlOption), "변경한 드래그 조합 인식")
        check(settings.set(.unassigned, for: .drawRegion) == nil && !settings.binding(for: .drawRegion).matchesDrag(flags: 0),
              "드래그 해제가 일반 마우스 입력을 가로채지 않음")
        check(settings.set(ShortcutBinding(keyCode: nil, modifiers: CGEventFlags.maskShift.rawValue), for: .drawRegion) != nil,
              "단일 조합키 드래그 거부")
        check(settings.set(ShortcutBinding(keyCode: 0, modifiers: 0), for: .center) != nil, "일반 문자 키 거부")
        check(settings.set(ShortcutBinding(keyCode: 53, modifiers: controlOption), for: .center) != nil, "Escape 예약")
        check(settings.set(ShortcutBinding(keyCode: 12, modifiers: CGEventFlags.maskCommand.rawValue), for: .center) != nil,
              "종료 기본키 예약")
        settings.reset()
        check(preferences.values["unrelated"] as? String == "유지" && preferences.values[ShortcutSettings.storageKey] == nil,
              "초기화는 단축키 설정만 제거")
        check(settings.binding(for: .leftHalf) == WindowAction.leftHalf.defaultBinding, "기본키 복원")
        preferences.values[ShortcutSettings.storageKey] = Data("{\"version\":999,\"overrides\":{}}".utf8)
        check(ShortcutSettings(defaults: preferences).loadWarning != nil, "지원하지 않는 설정 버전 안내")

        let primaryRegion = ScreenRegion(id: 1, frame: CGRect(x: 0, y: 0, width: 1001.5, height: 800),
                                         workArea: CGRect(x: 0, y: 24, width: 1001.5, height: 776), scale: 2)
        let leftRegion = ScreenRegion(id: 2, frame: CGRect(x: -800, y: 0, width: 800, height: 1000),
                                      workArea: CGRect(x: -800, y: 24, width: 800, height: 976), scale: 1)
        let topRegion = ScreenRegion(id: 3, frame: CGRect(x: 0, y: -900, width: 1000, height: 900),
                                     workArea: CGRect(x: 0, y: -880, width: 1000, height: 880), scale: 2)
        let current = CGRect(x: 120, y: 100, width: 400, height: 250)
        let leftPlan = try! WindowLayoutCalculator.plan(action: .leftHalf, window: current, screens: [primaryRegion])
        let rightPlan = try! WindowLayoutCalculator.plan(action: .rightHalf, window: current, screens: [primaryRegion])
        check(leftPlan.rectangle.maxX == rightPlan.rectangle.minX && leftPlan.rectangle.union(rightPlan.rectangle) == primaryRegion.workArea,
              "홀수 픽셀 화면 반쪽 분할에 틈 없음")
        let rightRegion = ScreenRegion(id: 4, frame: CGRect(x: 1001.5, y: 200, width: 1201, height: 900),
                                       workArea: CGRect(x: 1001.5, y: 224, width: 1171, height: 876), scale: 1)
        let horizontalScreens = [rightRegion, topRegion, primaryRegion, leftRegion]
        let rightScreenLeft = try! WindowLayoutCalculator.plan(action: .leftHalf, window: rightRegion.workArea, screens: [rightRegion])
        let rightScreenRight = try! WindowLayoutCalculator.plan(action: .rightHalf, window: rightRegion.workArea, screens: [rightRegion])
        let hopRight = try! WindowLayoutCalculator.plan(action: .rightHalf, window: rightPlan.rectangle, screens: horizontalScreens)
        check(hopRight.screen.id == rightRegion.id && hopRight.rectangle == rightScreenLeft.rectangle,
              "오른쪽 절반 반복은 높이·배율이 다른 오른쪽 화면의 왼쪽 절반으로")
        let continueRight = try! WindowLayoutCalculator.plan(action: .rightHalf, window: hopRight.rectangle, screens: horizontalScreens)
        check(continueRight.rectangle == rightScreenRight.rectangle && continueRight.screen.id == rightRegion.id,
              "옆 화면 왼쪽 절반에서 다시 누르면 같은 화면 오른쪽 절반으로")
        let stayRight = try! WindowLayoutCalculator.plan(action: .rightHalf, window: continueRight.rectangle, screens: horizontalScreens)
        check(stayRight.rectangle == continueRight.rectangle && stayRight.screen.id == rightRegion.id,
              "마지막 오른쪽 화면에서는 순환 없이 유지")
        let hopBack = try! WindowLayoutCalculator.plan(action: .leftHalf, window: hopRight.rectangle, screens: horizontalScreens)
        check(hopBack.screen.id == primaryRegion.id && hopBack.rectangle == rightPlan.rectangle,
              "왼쪽 절반 반복은 왼쪽 화면의 오른쪽 절반으로")
        let leftScreenRight = try! WindowLayoutCalculator.plan(action: .rightHalf, window: leftRegion.workArea, screens: [leftRegion])
        let hopLeft = try! WindowLayoutCalculator.plan(action: .leftHalf, window: leftPlan.rectangle, screens: horizontalScreens)
        check(hopLeft.screen.id == leftRegion.id && hopLeft.rectangle == leftScreenRight.rectangle,
              "음수 좌표의 왼쪽 화면으로 이동")
        let continueLeft = try! WindowLayoutCalculator.plan(action: .leftHalf, window: hopLeft.rectangle, screens: horizontalScreens)
        let stayLeft = try! WindowLayoutCalculator.plan(action: .leftHalf, window: continueLeft.rectangle, screens: horizontalScreens)
        check(stayLeft.rectangle == continueLeft.rectangle && stayLeft.screen.id == leftRegion.id,
              "마지막 왼쪽 화면에서는 순환 없이 유지")
        check(try! WindowLayoutCalculator.plan(action: .rightHalf, window: current, screens: horizontalScreens).rectangle == rightPlan.rectangle,
              "반쪽에 있지 않은 창은 먼저 현재 화면에 배치")
        check(try! WindowLayoutCalculator.plan(action: .rightHalf, window: rightPlan.rectangle, screens: [primaryRegion, topRegion]).screen.id == primaryRegion.id,
              "위아래로만 배치된 화면으로 좌우 이동하지 않음")
        check(try! WindowLayoutCalculator.plan(action: .leftHalf, window: leftPlan.rectangle, screens: [primaryRegion]).rectangle == leftPlan.rectangle,
              "단일 화면에서 같은 절반 반복 유지")
        check(try! WindowLayoutCalculator.plan(action: .rightHalf, window: rightPlan.rectangle.offsetBy(dx: 1, dy: -1),
                                              screens: horizontalScreens).screen.id == rightRegion.id,
              "2배 화면의 작은 픽셀 반올림 차이 허용")
        check(try! WindowLayoutCalculator.plan(action: .rightHalf, window: rightPlan.rectangle.offsetBy(dx: 3, dy: 0),
                                              screens: horizontalScreens).screen.id == primaryRegion.id,
              "반올림 범위 밖의 수동 이동은 현재 화면에 다시 배치")
        let farRight = ScreenRegion(id: 5, frame: rightRegion.frame.offsetBy(dx: 1500, dy: 0),
                                    workArea: rightRegion.workArea.offsetBy(dx: 1500, dy: 0), scale: 1)
        check(try! WindowLayoutCalculator.plan(action: .rightHalf, window: rightPlan.rectangle,
                                              screens: [farRight, primaryRegion, rightRegion]).screen.id == rightRegion.id,
              "화면 목록 순서와 무관하게 가까운 옆 화면 선택")
        let diagonal = ScreenRegion(id: 6, frame: CGRect(x: 1001.5, y: 800, width: 1000, height: 800),
                                    workArea: CGRect(x: 1001.5, y: 824, width: 1000, height: 776), scale: 1)
        check(try! WindowLayoutCalculator.plan(action: .rightHalf, window: rightPlan.rectangle,
                                              screens: [primaryRegion, diagonal]).screen.id == primaryRegion.id,
              "모서리만 닿는 대각선 화면은 좌우 이동에서 제외")
        for action in WindowAction.leftColumn + WindowAction.rightColumn where ![.restore, .nextDisplay, .previousDisplay].contains(action) {
            let plan = try? WindowLayoutCalculator.plan(action: action, window: current, screens: [primaryRegion])
            check(plan.map { SelectionGeometry.isValid($0.rectangle) } == true, "배치 계산: \(action.title)")
        }
        let heightPlan = try! WindowLayoutCalculator.plan(action: .maximizeHeight, window: current, screens: [primaryRegion])
        check(heightPlan.rectangle.minX == current.minX && heightPlan.rectangle.width == current.width && heightPlan.rectangle.height == 776,
              "높이 최대화는 너비·가로 위치 유지")
        let smallerPlan = try! WindowLayoutCalculator.plan(action: .smaller, window: current, screens: [primaryRegion])
        check(smallerPlan.rectangle.width == 370 && smallerPlan.rectangle.height == 220 && smallerPlan.rectangle.midX == current.midX,
              "크기 증감 60 렌더링 픽셀과 중심 유지")
        let centerPlan = try! WindowLayoutCalculator.plan(action: .center, window: current, screens: [primaryRegion])
        check(centerPlan.rectangle.size == current.size, "가운데 배치는 크기 유지")
        let nextPlan = try! WindowLayoutCalculator.plan(action: .nextDisplay, window: current, screens: [primaryRegion, leftRegion, topRegion])
        check(nextPlan.screen.id == 2 && leftRegion.workArea.contains(nextPlan.rectangle), "화면 순환과 음수 원점 배치")
        let previousPlan = try! WindowLayoutCalculator.plan(action: .previousDisplay, window: current, screens: [primaryRegion, leftRegion, topRegion])
        check(previousPlan.screen.id == 3, "세로 배치 이전 화면 선택")
        check((try? WindowLayoutCalculator.plan(action: .nextDisplay, window: current, screens: [primaryRegion])) == nil,
              "단일 화면 이동은 안내")
        check((try? WindowLayoutCalculator.plan(action: .restore, window: current, screens: [primaryRegion])) == nil,
              "복원 기록 없는 경우 안내")
        let restoredPlan = try! WindowLayoutCalculator.plan(action: .restore, window: current, screens: [primaryRegion],
                                                          restoreFrame: CGRect(x: -2000, y: -1000, width: 500, height: 300))
        check(primaryRegion.workArea.contains(restoredPlan.rectangle), "분리된 화면의 복원은 현재 화면 안으로")
        let spanning = CGRect(x: primaryRegion.frame.minX - 100, y: primaryRegion.frame.minY + 100,
                              width: primaryRegion.frame.width + 200, height: 400)
        check(try! WindowLayoutCalculator.plan(action: .restore, window: current, screens: [primaryRegion],
                                              restoreFrame: spanning).rectangle == spanning,
              "연결된 화면과 겹치는 원래 배치는 보정 없이 복원")
        check(AppVersion("1.10.0")! > AppVersion("1.9.9")!, "업데이트 버전은 숫자로 비교")
        for invalid in ["1.2", "1.2.3-beta", "1..3", "1.2.3.4", "-1.2.3", "1.2. 3", "999999999999999999999.0.0"] {
            check(AppVersion(invalid) == nil, "잘못된 업데이트 버전 거부: \(invalid)")
        }
        func release(_ tag: String, draft: Bool = false, prerelease: Bool = false, checksum: Bool = true, hostileURL: Bool = false) -> UpdateRelease {
            let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let candidate = UpdateCandidate(version: version, tag: tag)
            var assets = [UpdateRelease.Asset(name: candidate.archiveName,
                                             browser_download_url: hostileURL ? "https://example.com/evil.zip" : candidate.downloadURL.absoluteString)]
            if checksum { assets.append(UpdateRelease.Asset(name: candidate.archiveName + ".sha256", browser_download_url: candidate.checksumURL.absoluteString)) }
            return UpdateRelease(tag_name: tag, draft: draft, prerelease: prerelease, assets: assets)
        }
        let releaseCases = [release("v9.0.0"), release("v10.0.0", draft: true), release("v11.0.0", prerelease: true),
                            release("v12.0.0", checksum: false), release("v13.0.0", hostileURL: true), release("vv14.0.0")]
        check(UpdateCandidate.latest(in: releaseCases)?.version == "9.0.0", "정식 태그·ZIP·체크섬·정확한 주소 후보만 선택")
        check(UpdateCandidate.latest(in: []) == nil, "릴리스가 없으면 정상 빈 결과")
        check((try? AppUpdater.parse(Data("[]".utf8), statusCode: 200)) == nil, "빈 릴리스 응답 허용")
        for (data, code) in [(Data("[]".utf8), 403), (Data("{}".utf8), 200), (Data("[]".utf8), 500)] {
            do { _ = try AppUpdater.parse(data, statusCode: code); check(false, "잘못된 업데이트 응답 거부") }
            catch { check(true, "잘못된 업데이트 응답 거부") }
        }
        let digest = String(repeating: "a", count: 64)
        check((try? UpdateInstaller.verifyChecksum(digest + "  update.zip", actual: digest.uppercased())) != nil,
              "SHA-256 체크섬의 대소문자 허용")
        do { try UpdateInstaller.verifyChecksum("invalid", actual: digest); check(false, "체크섬 오류 거부") }
        catch { check(true, "체크섬 오류 거부") }
        let safeDetails = "-rwxr-xr-x  2.0 unx 100 b- defN 01-Jan-26 00:00 SketchFrame.app/Contents/MacOS/WindowSketch\n"
        check((try? UpdateInstaller.validateArchive(entries: "SketchFrame.app/Contents/MacOS/WindowSketch\n", details: safeDetails)) != nil,
              "정상 업데이트 압축 경로 허용")
        for paths in ["/tmp/SketchFrame.app/x", "SketchFrame.app/../../evil", "Other.app/x", "SketchFrame.app/./x"] {
            do { try UpdateInstaller.validateArchive(entries: paths, details: safeDetails); check(false, "압축 경로 이탈 거부") }
            catch { check(true, "압축 경로 이탈 거부") }
        }
        for details in [safeDetails.replacingOccurrences(of: "-rwx", with: "lrwx"),
                        safeDetails.replacingOccurrences(of: "100 b-", with: "999999999 b-")] {
            do { try UpdateInstaller.validateArchive(entries: "SketchFrame.app/x", details: details); check(false, "압축 링크·과도한 크기 거부") }
            catch { check(true, "압축 링크·과도한 크기 거부") }
        }
        let mockConfig = URLSessionConfiguration.ephemeral
        mockConfig.protocolClasses = [UpdateMockProtocol.self]
        let updater = AppUpdater(session: URLSession(configuration: mockConfig))
        let mockRelease = """
        [{"tag_name":"v9.0.0","draft":false,"prerelease":false,"assets":[
        {"name":"sketchframe-9.0.0-arm64.zip","browser_download_url":"https://github.com/mozzi-papa/SketchFrame/releases/download/v9.0.0/sketchframe-9.0.0-arm64.zip"},
        {"name":"sketchframe-9.0.0-arm64.zip.sha256","browser_download_url":"https://github.com/mozzi-papa/SketchFrame/releases/download/v9.0.0/sketchframe-9.0.0-arm64.zip.sha256"}]}]
        """
        UpdateMockProtocol.responseData = Data(mockRelease.utf8)
        var manualCompleted = false
        updater.onManualResult = { _ in manualCompleted = true }
        updater.check(manual: true)
        let deadline = Date().addingTimeInterval(3)
        while !manualCompleted && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        check(manualCompleted && !updater.checking && updater.available?.version == "9.0.0", "수동 업데이트 비동기 확인과 새 버전 알림 상태")
        UpdateMockProtocol.holdResponses = true
        updater.check()
        check(updater.checking, "설치 확인창 중 자동 조회 진행 상태")
        var preparationCompleted = false
        updater.prepareInstallation(UpdateCandidate(version: "0.1.0", tag: "v0.1.0")) { result in
            if case .failure = result { preparationCompleted = true }
        }
        let preparationDeadline = Date().addingTimeInterval(3)
        while !preparationCompleted && Date() < preparationDeadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        check(preparationCompleted && !updater.checking && !updater.installing && updater.status.contains("설치 준비 실패"),
              "확인한 후보로 설치를 시도하고 취소된 자동 조회는 설치 상태를 덮어쓰지 않음")
        UpdateMockProtocol.holdResponses = false
        UpdateMockProtocol.responseData = Data("[]".utf8)
        manualCompleted = false
        updater.check(manual: true)
        let emptyDeadline = Date().addingTimeInterval(3)
        while !manualCompleted && Date() < emptyDeadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        check(manualCompleted && updater.available == nil && updater.status.contains("없습니다"), "빈 릴리스 안내와 지난 후보 해제")
        updater.stop()
        print("자체 검사 \(count)개 통과")
    }
}
