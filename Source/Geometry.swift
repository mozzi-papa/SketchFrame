import AppKit

enum SelectionGeometry {
    static func pixelSizeLabel(_ size: CGSize, scale: CGFloat) -> String {
        "\(Int((size.width * scale).rounded())) × \(Int((size.height * scale).rounded())) px"
    }

    static func quartzRect(from appKitRect: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(x: appKitRect.minX, y: primaryTop - appKitRect.maxY,
               width: appKitRect.width, height: appKitRect.height)
    }

    static func rectangle(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    static func isValid(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite &&
        rect.width.isFinite && rect.height.isFinite && rect.width > 0 && rect.height > 0
    }

    static func matches(_ actual: CGRect, _ requested: CGRect, scale: CGFloat = 1) -> Bool {
        guard isValid(actual), isValid(requested), scale.isFinite, scale > 0 else { return false }
        return zip([actual.minX, actual.minY, actual.width, actual.height],
                   [requested.minX, requested.minY, requested.width, requested.height]).allSatisfy {
            ($0 * scale).rounded() == ($1 * scale).rounded()
        }
    }
}
