import Foundation

public enum DisplayLocator {
    public static func displayHardwareKey(for rect: Rect, in topology: DisplayTopology) -> String? {
        let centerX = rect.x + rect.width / 2
        let centerY = rect.y + rect.height / 2

        if let containing = topology.displays.first(where: { display in
            let bounds = display.bounds
            return centerX >= bounds.x
                && centerX <= bounds.x + bounds.width
                && centerY >= bounds.y
                && centerY <= bounds.y + bounds.height
        }) {
            return containing.hardwareKey
        }

        return topology.displays
            .min { lhs, rhs in
                distanceSquared(from: rect, to: lhs.bounds) < distanceSquared(from: rect, to: rhs.bounds)
            }?
            .hardwareKey
    }

    private static func distanceSquared(from window: Rect, to display: Rect) -> Double {
        let windowCenterX = window.x + window.width / 2
        let windowCenterY = window.y + window.height / 2
        let displayCenterX = display.x + display.width / 2
        let displayCenterY = display.y + display.height / 2
        let dx = windowCenterX - displayCenterX
        let dy = windowCenterY - displayCenterY
        return dx * dx + dy * dy
    }
}
