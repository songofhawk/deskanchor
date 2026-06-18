import AppKit
import CoreGraphics
import WinstoreCore

@MainActor
final class DisplayTopologyProvider {
    func currentTopology() -> DisplayTopology {
        let mainDisplayID = NSScreen.main?.displayID
        let displays = NSScreen.screens.map { screen in
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

        return DisplayTopology(displays: displays)
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return deviceDescription[key] as? CGDirectDisplayID ?? 0
    }
}
