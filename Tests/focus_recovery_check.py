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
'''


def run():
    source = (ROOT / 'Source/WindowController.swift').read_text()
    marker = 'final class FocusedWindowTracker {'
    prefix, tracker = source.split(marker, 1)
    # 검증 복사본에서만 접근 제한을 열어 알림 누락 상태를 재현합니다.
    source = prefix + marker + tracker.replace('private ', '')
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
