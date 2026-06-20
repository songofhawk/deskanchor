import AppKit
@preconcurrency import ApplicationServices

struct AccessibilityPermissionManager {
    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    func requestTrustPrompt() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func openSystemSettings() {
        SystemSettings.openAccessibilityPrivacy()
    }
}

enum SystemSettings {
    static func openAccessibilityPrivacy() {
        openFirstAvailable([
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security"
        ])
    }

    static func openDisplays() {
        openFirstAvailable([
            "x-apple.systempreferences:com.apple.Displays-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.displays"
        ])
    }

    private static func openFirstAvailable(_ urlStrings: [String]) {
        for urlString in urlStrings {
            guard let url = URL(string: urlString) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}
