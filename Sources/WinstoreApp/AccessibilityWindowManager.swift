import AppKit
@preconcurrency import ApplicationServices
import WinstoreCore

struct RestoreResult {
    var restored: Int
    var skipped: Int
    var failed: Int

    var summary: String {
        "恢复 \(restored) 个，跳过 \(skipped) 个，失败 \(failed) 个"
    }
}

@MainActor
final class AccessibilityWindowManager {
    private let displayProvider: DisplayTopologyProvider
    private let ownProcessIdentifier: Int32

    init(displayProvider: DisplayTopologyProvider, ownProcessIdentifier: Int32) {
        self.displayProvider = displayProvider
        self.ownProcessIdentifier = ownProcessIdentifier
    }

    func captureWindows() -> [WindowRecord] {
        let topology = displayProvider.currentTopology()
        let records = NSWorkspace.shared.runningApplications.flatMap { app in
            windows(for: app, topology: topology)
        }
        return WindowMatcher.assignOccurrences(records)
    }

    func restore(snapshot: LayoutSnapshot) -> RestoreResult {
        let currentTopology = displayProvider.currentTopology()
        let liveWindows = liveWindowHandles()
        var restored = 0
        var skipped = 0
        var failed = 0

        for record in snapshot.windows where !record.isMinimized {
            guard let handle = liveWindows[record.signature.matchKey] else {
                skipped += 1
                continue
            }

            let savedDisplay = snapshot.topology.displays.first {
                $0.hardwareKey == record.displayHardwareKey
            }
            let currentDisplay = currentTopology.displays.first {
                $0.hardwareKey == record.displayHardwareKey
            } ?? currentTopology.displays.first(where: \.isMain) ?? currentTopology.displays.first

            guard let currentDisplay else {
                failed += 1
                continue
            }

            let target = RestorePlanner.targetFrame(
                savedFrame: record.frame,
                savedDisplay: savedDisplay,
                currentDisplay: currentDisplay
            )

            if move(window: handle.element, to: target) {
                restored += 1
            } else {
                failed += 1
            }
        }

        return RestoreResult(restored: restored, skipped: skipped, failed: failed)
    }

    private func liveWindowHandles() -> [String: WindowHandle] {
        let topology = displayProvider.currentTopology()
        let handles = NSWorkspace.shared.runningApplications.flatMap { app in
            windowHandles(for: app, topology: topology)
        }
        let assigned = WindowMatcher.assignOccurrences(handles.map(\.record))
        var result: [String: WindowHandle] = [:]

        for (index, record) in assigned.enumerated() {
            var handle = handles[index]
            handle.record = record
            result[record.signature.matchKey] = handle
        }

        return result
    }

    private func windows(for app: NSRunningApplication, topology: DisplayTopology) -> [WindowRecord] {
        windowHandles(for: app, topology: topology).map(\.record)
    }

    private func windowHandles(for app: NSRunningApplication, topology: DisplayTopology) -> [WindowHandle] {
        guard app.processIdentifier != ownProcessIdentifier,
              app.activationPolicy == .regular else {
            return []
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let windows = copyAttribute(appElement, kAXWindowsAttribute) as? [AXUIElement] else {
            return []
        }

        return windows.compactMap { element in
            capture(window: element, app: app, topology: topology)
        }
    }

    private func capture(window: AXUIElement, app: NSRunningApplication, topology: DisplayTopology) -> WindowHandle? {
        let role = copyAttribute(window, kAXRoleAttribute) as? String ?? ""
        let subrole = copyAttribute(window, kAXSubroleAttribute) as? String ?? ""

        guard role == kAXWindowRole as String,
              subrole.isEmpty || subrole == kAXStandardWindowSubrole as String else {
            return nil
        }

        let title = copyAttribute(window, kAXTitleAttribute) as? String ?? ""
        let isMinimized = copyAttribute(window, kAXMinimizedAttribute) as? Bool ?? false

        guard let position = copyPointAttribute(window, kAXPositionAttribute),
              let size = copySizeAttribute(window, kAXSizeAttribute),
              size.width >= 80,
              size.height >= 60 else {
            return nil
        }

        let frame = Rect(x: position.x, y: position.y, width: size.width, height: size.height)
        let signature = WindowSignature(
            bundleIdentifier: app.bundleIdentifier ?? "",
            ownerName: app.localizedName ?? "",
            titleFingerprint: WindowMatcher.fingerprint(title: title),
            role: role,
            subrole: subrole,
            occurrence: 0
        )

        let record = WindowRecord(
            signature: signature,
            title: title,
            frame: frame,
            displayHardwareKey: DisplayLocator.displayHardwareKey(for: frame, in: topology),
            isMinimized: isMinimized
        )

        return WindowHandle(element: window, record: record)
    }

    private func move(window: AXUIElement, to frame: Rect) -> Bool {
        var size = CGSize(width: frame.width, height: frame.height)
        var position = CGPoint(x: frame.x, y: frame.y)

        guard let sizeValue = AXValueCreate(.cgSize, &size),
              let positionValue = AXValueCreate(.cgPoint, &position) else {
            return false
        }

        let sizeResult = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        let positionResult = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        return sizeResult == .success && positionResult == .success
    }
}

private struct WindowHandle {
    var element: AXUIElement
    var record: WindowRecord
}

private func copyAttribute(_ element: AXUIElement, _ attribute: String) -> Any? {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    guard result == .success else {
        return nil
    }
    return value
}

private func copyPointAttribute(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
    guard let value = copyAttribute(element, attribute) else {
        return nil
    }

    var point = CGPoint.zero
    guard AXValueGetType(value as! AXValue) == .cgPoint,
          AXValueGetValue(value as! AXValue, .cgPoint, &point) else {
        return nil
    }
    return point
}

private func copySizeAttribute(_ element: AXUIElement, _ attribute: String) -> CGSize? {
    guard let value = copyAttribute(element, attribute) else {
        return nil
    }

    var size = CGSize.zero
    guard AXValueGetType(value as! AXValue) == .cgSize,
          AXValueGetValue(value as! AXValue, .cgSize, &size) else {
        return nil
    }
    return size
}
