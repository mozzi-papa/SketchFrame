import AppKit
import ApplicationServices

final class WindowHistory {
    private struct Entry {
        let target: WindowTarget
        var baseline: CGRect
        var lastFrame: CGRect?
    }
    private var entries: [Entry] = []

    func restoreFrame(for target: WindowTarget, scale: CGFloat) -> CGRect? {
        discardTerminatedApplications()
        guard !target.application.isTerminated, SelectionGeometry.isValid(target.originalFrame),
              scale.isFinite, scale > 0,
              let index = entries.firstIndex(where: { Self.sameWindow($0.target, target) }) else { return nil }
        if let lastFrame = entries[index].lastFrame,
           !SelectionGeometry.matches(lastFrame, target.originalFrame, scale: scale) {
            entries[index].baseline = target.originalFrame
            entries[index].lastFrame = target.originalFrame
        }
        return entries[index].baseline
    }

    func record(before: CGRect, after: CGRect?, for target: WindowTarget, scale: CGFloat, restored: Bool = false) {
        discardTerminatedApplications()
        guard !target.application.isTerminated, SelectionGeometry.isValid(before),
              after.map(SelectionGeometry.isValid) ?? true,
              scale.isFinite, scale > 0 else { return }
        let index = entries.firstIndex { Self.sameWindow($0.target, target) }
        let previous = index.map { entries[$0] }
        let baseline = previous.flatMap {
            // shortcut: 키보드 배치 뒤에는 결과를 읽지 않아 외부 이동과 앱의 크기 제한을 구분하지 않습니다.
            ($0.lastFrame.map { SelectionGeometry.matches($0, before, scale: scale) } ?? true) ? $0.baseline : nil
        } ?? before
        if let index = index { entries.remove(at: index) }
        if restored && (after.map { SelectionGeometry.matches($0, baseline, scale: scale) } ?? true) { return }
        entries.append(Entry(target: target, baseline: baseline, lastFrame: after))
        if entries.count > 32 { entries.removeFirst(entries.count - 32) }
    }

    private func discardTerminatedApplications() {
        entries.removeAll { $0.target.application.isTerminated }
    }

    private static func sameWindow(_ lhs: WindowTarget, _ rhs: WindowTarget) -> Bool {
        lhs.application.processIdentifier == rhs.application.processIdentifier && CFEqual(lhs.element, rhs.element)
    }
}
