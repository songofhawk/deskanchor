import Foundation

public enum DisplayLocator {
    public static func displayHardwareKey(for rect: Rect, in topology: DisplayTopology) -> String? {
        if let containing = topology.displays.first(where: { display in
            display.bounds.containsCenter(of: rect)
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
        let windowCenterX = window.centerX
        let windowCenterY = window.centerY
        let displayCenterX = display.centerX
        let displayCenterY = display.centerY
        let dx = windowCenterX - displayCenterX
        let dy = windowCenterY - displayCenterY
        return dx * dx + dy * dy
    }
}
