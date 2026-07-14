import Foundation

public enum DisplayCoordinateSpace {
    public static func accessibilityBounds(fromAppKitBounds bounds: Rect, mainAppKitBounds: Rect) -> Rect {
        Rect(
            x: bounds.x,
            y: mainAppKitBounds.maxY - bounds.maxY,
            width: bounds.width,
            height: bounds.height
        )
    }

    public static func accessibilityTopology(fromAppKitTopology topology: DisplayTopology) -> DisplayTopology {
        guard let mainDisplay = topology.displays.first(where: \.isMain) ?? topology.displays.first else {
            return topology
        }

        return DisplayTopology(
            capturedAt: topology.capturedAt,
            displays: topology.displays.map { display in
                var copy = display
                copy.bounds = accessibilityBounds(
                    fromAppKitBounds: display.bounds,
                    mainAppKitBounds: mainDisplay.bounds
                )
                return copy
            }
        )
    }

    public static func accessibilityTopology(
        fromAppKitTopology topology: DisplayTopology,
        mainDisplayID: UInt32
    ) -> DisplayTopology {
        guard let mainDisplay = topology.displays.first(where: { $0.id == mainDisplayID }) else {
            return accessibilityTopology(fromAppKitTopology: topology)
        }

        return DisplayTopology(
            capturedAt: topology.capturedAt,
            displays: topology.displays.map { display in
                var copy = display
                copy.bounds = accessibilityBounds(
                    fromAppKitBounds: display.bounds,
                    mainAppKitBounds: mainDisplay.bounds
                )
                copy.isMain = display.id == mainDisplayID
                return copy
            }
        )
    }
}
