import AppKit
import CoreGraphics
import DeskAnchorCore

@MainActor
final class DisplayTopologyProvider {
    func currentTopology() -> DisplayTopology {
        let screens = NSScreen.screens
        let mainDisplayID = NSScreen.main?.displayID
        let mainBounds = Rect((NSScreen.main ?? screens.first)?.frame ?? .zero)
        let displays = screens.map { screen in
            let displayID = screen.displayID
            let appKitBounds = Rect(screen.frame)
            return DisplayDescriptor(
                id: displayID,
                name: screen.localizedName,
                vendor: CGDisplayVendorNumber(displayID),
                model: CGDisplayModelNumber(displayID),
                serial: CGDisplaySerialNumber(displayID),
                bounds: DisplayCoordinateSpace.accessibilityBounds(
                    fromAppKitBounds: appKitBounds,
                    mainAppKitBounds: mainBounds
                ),
                scale: screen.backingScaleFactor,
                isMain: displayID == mainDisplayID
            )
        }

        return DisplayTopology(displays: displays)
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return deviceDescription[key] as? CGDirectDisplayID ?? 0
    }
}
