import AppKit
import DeskAnchorCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var mainWindowController: MainWindowController?
    private var coordinator: LayoutCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.applicationIconImage = DeskAnchorIcon.appIcon(size: 512)

        do {
            let store = try LayoutStore.defaultStore()
            let preferencesStore = PreferencesStore()
            let displayProvider = DisplayTopologyProvider()
            let windowManager = AccessibilityWindowManager(
                displayProvider: displayProvider,
                ownProcessIdentifier: ProcessInfo.processInfo.processIdentifier
            )
            let coordinator = LayoutCoordinator(
                store: store,
                preferencesStore: preferencesStore,
                displayProvider: displayProvider,
                windowManager: windowManager,
                permissionManager: AccessibilityPermissionManager()
            )
            let statusBarController = StatusBarController(coordinator: coordinator)
            let mainWindowController = MainWindowController(coordinator: coordinator)
            statusBarController.showMainWindow = { [weak mainWindowController] in
                mainWindowController?.show()
            }
            coordinator.statusDidChange = { [weak statusBarController, weak mainWindowController] status in
                statusBarController?.update(status: status)
                mainWindowController?.update(status: status)
            }

            self.coordinator = coordinator
            self.statusBarController = statusBarController
            self.mainWindowController = mainWindowController
            coordinator.start()
            mainWindowController.show()
        } catch {
            NSAlert(error: error).runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            mainWindowController?.show()
        }
        return true
    }
}
