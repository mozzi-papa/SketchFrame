import AppKit

struct ScreenRegion: Equatable {
    let id: UInt32
    let frame: CGRect
    let workArea: CGRect
    let scale: CGFloat
}

struct WindowLayoutPlan {
    let rectangle: CGRect
    let screen: ScreenRegion
}

enum WindowLayoutCalculator {
    static func screen(for rectangle: CGRect, screens: [ScreenRegion]) -> ScreenRegion? {
        guard SelectionGeometry.isValid(rectangle) else { return nil }
        let available = screens.filter { SelectionGeometry.isValid($0.frame) }
        var selected: ScreenRegion?
        var largestArea: CGFloat = 0
        for candidate in available {
            let overlap = rectangle.intersection(candidate.frame)
            let area = overlap.isNull ? 0 : overlap.width * overlap.height
            if area > largestArea {
                selected = candidate
                largestArea = area
            }
        }
        if let selected = selected { return selected }
        return available.enumerated().min {
            let left = hypot($0.element.frame.midX - rectangle.midX, $0.element.frame.midY - rectangle.midY)
            let right = hypot($1.element.frame.midX - rectangle.midX, $1.element.frame.midY - rectangle.midY)
            return left == right ? $0.offset < $1.offset : left < right
        }?.element
    }

    static func plan(action: WindowAction, window: CGRect, screens: [ScreenRegion],
                     restoreFrame: CGRect? = nil) throws -> WindowLayoutPlan {
        guard SelectionGeometry.isValid(window) else {
            throw WindowFailure(message: "창의 위치·크기가 올바르지 않습니다.")
        }
        let available = screens.filter {
            SelectionGeometry.isValid($0.frame) && SelectionGeometry.isValid($0.workArea) &&
                $0.scale.isFinite && $0.scale > 0
        }
        guard let current = screen(for: window, screens: available) else {
            throw WindowFailure(message: "배치할 디스플레이를 찾을 수 없습니다.")
        }
        let area = current.workArea
        let splitX = area.minX + floor(area.width * current.scale / 2) / current.scale
        let splitY = area.minY + floor(area.height * current.scale / 2) / current.scale
        var destination = current
        var result: CGRect
        switch action {
        case .drawRegion:
            throw WindowFailure(message: "자유 영역은 드래그로 지정해 주세요.")
        case .leftHalf, .rightHalf:
            let right = action == .rightHalf
            result = horizontalHalf(of: current, right: right)
            // macOS의 픽셀 반올림 차이만 허용해 반복 배치를 판별합니다.
            let differences = [window.minX - result.minX, window.minY - result.minY,
                               window.width - result.width, window.height - result.height]
            if differences.allSatisfy({ abs($0) * current.scale <= 4 }),
               let adjacent = horizontalNeighbor(of: current, right: right, screens: available) {
                destination = adjacent
                result = horizontalHalf(of: adjacent, right: !right)
            }
        case .topHalf:
            result = CGRect(x: area.minX, y: area.minY, width: area.width, height: splitY - area.minY)
        case .bottomHalf:
            result = CGRect(x: area.minX, y: splitY, width: area.width, height: area.maxY - splitY)
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            let right = action == .topRight || action == .bottomRight
            let bottom = action == .bottomLeft || action == .bottomRight
            let x = right ? splitX : area.minX
            let y = bottom ? splitY : area.minY
            result = CGRect(x: x, y: y, width: (right ? area.maxX : splitX) - x,
                            height: (bottom ? area.maxY : splitY) - y)
        case .centerHalf:
            if area.width >= area.height {
                let width = floor(area.width * current.scale / 2) / current.scale
                let offset = floor((area.width - width) * current.scale / 2) / current.scale
                result = CGRect(x: area.minX + offset, y: area.minY, width: width, height: area.height)
            } else {
                let height = floor(area.height * current.scale / 2) / current.scale
                let offset = floor((area.height - height) * current.scale / 2) / current.scale
                result = CGRect(x: area.minX, y: area.minY + offset, width: area.width, height: height)
            }
        case .maximize:
            result = area
        case .almostMaximize:
            let size = CGSize(width: (area.width * 0.9).rounded(), height: (area.height * 0.9).rounded())
            result = CGRect(x: area.minX + ((area.width - size.width) / 2).rounded(),
                            y: area.minY + ((area.height - size.height) / 2).rounded(), width: size.width, height: size.height)
        case .maximizeHeight:
            result = CGRect(x: window.minX, y: area.minY, width: window.width, height: area.height)
        case .smaller, .larger:
            let delta: CGFloat = (action == .smaller ? -60 : 60) / current.scale
            let size = CGSize(width: window.width + delta, height: window.height + delta)
            guard size.width > 0, size.height > 0 else {
                throw WindowFailure(message: "창의 너비와 높이는 0보다 커야 합니다.")
            }
            result = fit(CGRect(x: window.midX - size.width / 2, y: window.midY - size.height / 2,
                                width: size.width, height: size.height), in: area)
        case .center:
            result = CGRect(x: area.midX - window.width / 2, y: area.midY - window.height / 2,
                            width: window.width, height: window.height)
        case .restore:
            guard let original = restoreFrame else {
                throw WindowFailure(message: "복원할 배치가 없습니다.")
            }
            guard SelectionGeometry.isValid(original) else {
                throw WindowFailure(message: "복원할 창의 위치·크기가 올바르지 않습니다.")
            }
            if let originalScreen = screen(for: original, screens: available),
               !original.intersection(originalScreen.frame).isNull,
               original.intersection(originalScreen.frame).width > 0,
               original.intersection(originalScreen.frame).height > 0 {
                destination = originalScreen
                result = original
            } else {
                result = fit(original, in: destination.workArea)
            }
        case .nextDisplay, .previousDisplay:
            guard available.count > 1 else {
                throw WindowFailure(message: "이동할 다른 디스플레이가 없습니다.")
            }
            let ordered = available.enumerated().sorted {
                if $0.element.frame.minX != $1.element.frame.minX { return $0.element.frame.minX < $1.element.frame.minX }
                if $0.element.frame.minY != $1.element.frame.minY { return $0.element.frame.minY < $1.element.frame.minY }
                return $0.offset < $1.offset
            }.map(\.element)
            guard let index = ordered.firstIndex(of: current) else {
                throw WindowFailure(message: "현재 디스플레이를 찾을 수 없습니다.")
            }
            let step = action == .nextDisplay ? 1 : ordered.count - 1
            destination = ordered[(index + step) % ordered.count]
            let target = destination.workArea
            let size = CGSize(width: min(window.width, target.width), height: min(window.height, target.height))
            result = CGRect(x: movedOrigin(window.minX, length: window.width, from: area.minX,
                                          sourceLength: area.width, to: target.minX, targetLength: target.width,
                                          newLength: size.width, scale: current.scale),
                            y: movedOrigin(window.minY, length: window.height, from: area.minY,
                                          sourceLength: area.height, to: target.minY, targetLength: target.height,
                                          newLength: size.height, scale: current.scale),
                            width: size.width, height: size.height)
            result = fit(result, in: target)
        }
        guard SelectionGeometry.isValid(result) else {
            throw WindowFailure(message: "배치할 창의 크기가 올바르지 않습니다.")
        }
        return WindowLayoutPlan(rectangle: result, screen: destination)
    }

    private static func horizontalHalf(of screen: ScreenRegion, right: Bool) -> CGRect {
        let area = screen.workArea
        let split = area.minX + floor(area.width * screen.scale / 2) / screen.scale
        return CGRect(x: right ? split : area.minX, y: area.minY,
                      width: right ? area.maxX - split : split - area.minX, height: area.height)
    }

    private static func horizontalNeighbor(of current: ScreenRegion, right: Bool,
                                           screens: [ScreenRegion]) -> ScreenRegion? {
        let frame = current.frame
        return screens.filter { candidate in
            candidate.id != current.id &&
                min(frame.maxY, candidate.frame.maxY) > max(frame.minY, candidate.frame.minY) &&
                (right ? candidate.frame.minX >= frame.maxX : candidate.frame.maxX <= frame.minX)
        }.min { left, rightCandidate in
            let leftGap = right ? left.frame.minX - frame.maxX : frame.minX - left.frame.maxX
            let rightGap = right ? rightCandidate.frame.minX - frame.maxX : frame.minX - rightCandidate.frame.maxX
            if leftGap != rightGap { return leftGap < rightGap }
            let leftOffset = abs(left.frame.midY - frame.midY)
            let rightOffset = abs(rightCandidate.frame.midY - frame.midY)
            return leftOffset == rightOffset ? left.id < rightCandidate.id : leftOffset < rightOffset
        }
    }

    private static func fit(_ rectangle: CGRect, in area: CGRect) -> CGRect {
        let width = min(rectangle.width, area.width)
        let height = min(rectangle.height, area.height)
        return CGRect(x: min(max(rectangle.minX, area.minX), area.maxX - width),
                      y: min(max(rectangle.minY, area.minY), area.maxY - height), width: width, height: height)
    }

    private static func movedOrigin(_ origin: CGFloat, length: CGFloat, from source: CGFloat,
                                    sourceLength: CGFloat, to destination: CGFloat, targetLength: CGFloat,
                                    newLength: CGFloat, scale: CGFloat) -> CGFloat {
        let leading = abs(origin - source) <= 0.5 / scale
        let trailing = abs(origin + length - source - sourceLength) <= 0.5 / scale
        if leading && !trailing { return destination }
        if trailing && !leading { return destination + targetLength - newLength }
        let relativeCenter = (origin + length / 2 - source) / sourceLength
        return destination + relativeCenter * targetLength - newLength / 2
    }
}
