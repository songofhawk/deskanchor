import Foundation

public struct RestorePlanItem: Equatable, Sendable {
    public var saved: WindowRecord
    public var targetFrame: Rect

    public init(saved: WindowRecord, targetFrame: Rect) {
        self.saved = saved
        self.targetFrame = targetFrame
    }
}

public enum RestorePlanner {
    public static func targetFrame(
        savedFrame: Rect,
        savedDisplay: DisplayDescriptor?,
        currentDisplay: DisplayDescriptor
    ) -> Rect {
        guard let savedDisplay else {
            return clamped(savedFrame, to: currentDisplay.bounds)
        }

        let xRatio = safeRatio(savedFrame.x - savedDisplay.bounds.x, savedDisplay.bounds.width)
        let yRatio = safeRatio(savedFrame.y - savedDisplay.bounds.y, savedDisplay.bounds.height)
        let widthRatio = safeRatio(savedFrame.width, savedDisplay.bounds.width)
        let heightRatio = safeRatio(savedFrame.height, savedDisplay.bounds.height)

        let projected = Rect(
            x: currentDisplay.bounds.x + currentDisplay.bounds.width * xRatio,
            y: currentDisplay.bounds.y + currentDisplay.bounds.height * yRatio,
            width: currentDisplay.bounds.width * widthRatio,
            height: currentDisplay.bounds.height * heightRatio
        )

        return clamped(projected, to: currentDisplay.bounds)
    }

    public static func clamped(_ frame: Rect, to bounds: Rect) -> Rect {
        let minWidth = min(max(frame.width, 80), bounds.width)
        let minHeight = min(max(frame.height, 60), bounds.height)
        let maxX = bounds.x + max(bounds.width - minWidth, 0)
        let maxY = bounds.y + max(bounds.height - minHeight, 0)

        return Rect(
            x: min(max(frame.x, bounds.x), maxX),
            y: min(max(frame.y, bounds.y), maxY),
            width: minWidth,
            height: minHeight
        )
    }

    private static func safeRatio(_ value: Double, _ denominator: Double) -> Double {
        guard denominator > 0, value.isFinite else {
            return 0
        }
        return value / denominator
    }
}
