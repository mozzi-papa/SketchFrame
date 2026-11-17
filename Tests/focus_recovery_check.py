"""실제 창을 조작하지 않고 활성 창 캐시 무효화와 대기 작업 취소를 검사합니다."""
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
HARNESS = '''import AppKit
import ApplicationServices
NSApplication.shared.setActivationPolicy(.prohibited)
let app = NSRunningApplication.current
let queue = DispatchQueue(label: "SketchFrame.focus-recovery-check")
queue.suspend()
var changes = 0
let tracker = FocusedWindowTracker(queue: queue) { changes += 1 }
let reference = FocusedWindowReference(application: app, window: AXUIElementCreateApplication(app.processIdentifier), revision: 7)
tracker.application = app
tracker.revision = 7
tracker.cached = reference
precondition(tracker.reference(for: app) != nil)
tracker.invalidate(reference)
precondition(!tracker.isReady && tracker.revision == 8 && changes == 1)
precondition(!tracker.isCurrent(reference))
let fresh = FocusedWindowReference(application: app, window: reference.window, revision: 8)
tracker.cached = fresh
tracker.invalidate(reference)
precondition(tracker.isCurrent(fresh) && changes == 1)
tracker.stop()
precondition(!tracker.isReady && !tracker.loading && !tracker.installing)
var cancelledBodyRan = false
let cancelled = DispatchWorkItem { cancelledBodyRan = true }
queue.async(execute: cancelled)
cancelled.cancel()
queue.resume()
queue.sync {}
precondition(!cancelledBodyRan)
print("PASS: 오래된 창 정보 폐기·재조회 예약·이전 오류의 새 창 정보 보호·대기 작업 취소")

enum KeyboardFixture {
    static var active = true
    static var cancelled = false
    static var lookupFailures = 0
    static var captureFailures = 0
    static var error = AXError.noValue
    static var lookups = 0
    static var captures = 0
    static var retries = 0
    static var seenWindows: [AXUIElement] = []
    static func reset() {
        active = true; cancelled = false; lookupFailures = 0; captureFailures = 0
        error = .noValue; lookups = 0; captures = 0; retries = 0; seenWindows = []
    }
}
extension WindowController {
    static func focusedWindow(application: NSRunningApplication) throws -> AXUIElement {
        precondition(application.processIdentifier == app.processIdentifier)
        KeyboardFixture.lookups += 1
        if KeyboardFixture.lookups <= KeyboardFixture.lookupFailures {
            throw WindowFailure(message: "검증용 일시적 창 조회 실패", axError: KeyboardFixture.error)
        }
        return reference.window
    }
    static func capture(application: NSRunningApplication, window: AXUIElement, inspectSize: Bool = true) throws -> WindowTarget {
        precondition(!inspectSize, "키보드에서 크기 제한을 검사했습니다.")
        KeyboardFixture.captures += 1
        KeyboardFixture.seenWindows.append(window)
        if KeyboardFixture.captures <= KeyboardFixture.captureFailures {
            throw WindowFailure(message: "검증용 일시적 창 정보 실패", axError: KeyboardFixture.error)
        }
        return WindowTarget(element: window, application: application, name: "검증용 창", originalFrame: .zero)
    }
}
func keyboardTarget(_ window: AXUIElement? = nil, cancelOnRetry: Bool = false, switchOnRetry: Bool = false) throws -> WindowTarget {
    try WindowController.captureForKeyboard(application: app, window: window,
        isCancelled: { KeyboardFixture.cancelled }) { _ in
        KeyboardFixture.retries += 1
        if cancelOnRetry { KeyboardFixture.cancelled = true }
        if switchOnRetry { KeyboardFixture.active = false }
    }
}
func rejectsKeyboard(_ operation: () throws -> WindowTarget) {
    do { _ = try operation(); fatalError("실행하면 안 되는 단축키 요청을 허용했습니다.") }
    catch {}
}
KeyboardFixture.reset()
_ = try keyboardTarget()
precondition(KeyboardFixture.lookups == 1 && KeyboardFixture.captures == 1 && KeyboardFixture.retries == 0)
KeyboardFixture.reset()
KeyboardFixture.lookupFailures = 1
_ = try keyboardTarget()
precondition(KeyboardFixture.lookups == 2 && KeyboardFixture.captures == 1 && KeyboardFixture.retries == 1)
KeyboardFixture.reset()
KeyboardFixture.captureFailures = 1
KeyboardFixture.error = .cannotComplete
_ = try keyboardTarget()
precondition(KeyboardFixture.lookups == 1 && KeyboardFixture.captures == 2)
precondition(KeyboardFixture.seenWindows.allSatisfy { CFEqual($0, reference.window) })
KeyboardFixture.reset()
_ = try keyboardTarget(reference.window)
precondition(KeyboardFixture.lookups == 0 && KeyboardFixture.captures == 1)
for code: AXError in [.attributeUnsupported, .invalidUIElement] {
    KeyboardFixture.reset()
    KeyboardFixture.error = code
    KeyboardFixture.captureFailures = 1
    rejectsKeyboard { try keyboardTarget(reference.window) }
    precondition(KeyboardFixture.lookups == 0 && KeyboardFixture.retries == 0)
}
KeyboardFixture.reset()
KeyboardFixture.lookupFailures = 10
rejectsKeyboard { try keyboardTarget() }
precondition(KeyboardFixture.lookups == 3 && KeyboardFixture.retries == 2)
for switchApp in [false, true] {
    KeyboardFixture.reset()
    KeyboardFixture.lookupFailures = 1
    rejectsKeyboard { try keyboardTarget(cancelOnRetry: !switchApp, switchOnRetry: switchApp) }
    precondition(KeyboardFixture.lookups == 1 && KeyboardFixture.captures == 0)
}
KeyboardFixture.reset()
KeyboardFixture.cancelled = true
rejectsKeyboard { try keyboardTarget() }
precondition(KeyboardFixture.lookups == 0)
print("PASS: 창 추적 미준비의 첫 키 조회·일시 오류 복구·동일 창 유지·재시도 상한·앱/세션 변경 취소·크기 검사 생략")
'''


def run():
    source = (ROOT / 'Source/WindowController.swift').read_text()
    marker = 'final class FocusedWindowTracker {'
    prefix, tracker = source.split(marker, 1)
    # 검증 복사본에서만 접근 제한을 열어 알림 누락 상태를 재현합니다.
    source = prefix + marker + tracker.replace('private ', '')
    # 원래 키보드 조회·재시도 코드를 실행하고 외부 AX 응답만 모의 처리합니다.
    source = source.replace('static func focusedWindow(', 'static func realFocusedWindow(')
    source = source.replace('static func capture(', 'static func realCapture(')
    source = source.replace('guard !isCancelled(), app.isActive, !app.isTerminated else',
                            'guard !isCancelled(), KeyboardFixture.active, !app.isTerminated else')
    with tempfile.TemporaryDirectory(prefix='SketchFrame-focus-check-') as directory:
        work = Path(directory)
        (work / 'WindowController.swift').write_text(source)
        (work / 'main.swift').write_text(HARNESS)
        subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', str(ROOT / 'Source/Geometry.swift'),
                        str(work / 'WindowController.swift'), str(work / 'main.swift'),
                        '-o', str(work / 'Check'), '-target', 'arm64-apple-macos13.0',
                        '-framework', 'AppKit', '-framework', 'ApplicationServices',
                        '-module-cache-path', str(work / 'swift-cache'), '-O'], check=True)
        subprocess.run([str(work / 'Check')], check=True)


if __name__ == '__main__':
    run()
