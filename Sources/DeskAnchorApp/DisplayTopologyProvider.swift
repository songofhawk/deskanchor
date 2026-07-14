import AppKit
import CoreGraphics
import DeskAnchorCore

@MainActor
final class DisplayTopologyProvider {
    func currentTopology() -> DisplayTopology {
        let screens = NSScreen.screens
        let mainDisplayID = CGMainDisplayID()
        let displays = screens.map { screen in
            let displayID = screen.displayID
            return DisplayDescriptor(
                id: displayID,
                name: screen.localizedName,
                vendor: CGDisplayVendorNumber(displayID),
                model: CGDisplayModelNumber(displayID),
                serial: CGDisplaySerialNumber(displayID),
                bounds: Rect(screen.frame),
                scale: screen.backingScaleFactor,
                isMain: displayID == mainDisplayID
            )
        }

        return DisplayCoordinateSpace.accessibilityTopology(
            fromAppKitTopology: DisplayTopology(displays: displays),
            mainDisplayID: mainDisplayID
        )
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return deviceDescription[key] as? CGDirectDisplayID ?? 0
    }
}
