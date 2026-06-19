import CoreGraphics
import Foundation

public struct Rect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(_ rect: CGRect) {
        self.init(
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.size.width,
            height: rect.size.height
        )
    }

    public var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    public var maxX: Double {
        x + width
    }

    public var maxY: Double {
        y + height
    }

    public var centerX: Double {
        x + width / 2
    }

    public var centerY: Double {
        y + height / 2
    }

    public func containsCenter(of rect: Rect) -> Bool {
        let centerX = rect.centerX
        let centerY = rect.centerY
        return centerX >= x
            && centerX <= maxX
            && centerY >= y
            && centerY <= maxY
    }

    public func rounded(rule: FloatingPointRoundingRule = .toNearestOrAwayFromZero) -> Rect {
        Rect(
            x: x.rounded(rule),
            y: y.rounded(rule),
            width: width.rounded(rule),
            height: height.rounded(rule)
        )
    }
}
