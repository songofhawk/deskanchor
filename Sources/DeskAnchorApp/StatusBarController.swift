import AppKit

@MainActor
final class StatusBarController {
    var showMainWindow: (() -> Void)?

    private let statusItem: NSStatusItem
    private let coordinator: LayoutCoordinator
    private var latestStatus: AppStatus

    init(coordinator: LayoutCoordinator) {
        self.coordinator = coordinator
        self.latestStatus = coordinator.status
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        configureButton()
        rebuildMenu()
    }

    func update(status: AppStatus) {
        latestStatus = status
        configureButton()
        rebuildMenu()
    }

    private func configureButton() {
        guard let button = statusItem.button else {
            return
        }

        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        let candidates = latestStatus.permissionGranted
            ? []
            : ["exclamationmark.macwindow", "exclamationmark.triangle.fill"]
        let image = latestStatus.permissionGranted
            ? DeskAnchorIcon.menuBarIcon(size: 18)
            : candidates
                .lazy
                .compactMap { NSImage(systemSymbolName: $0, accessibilityDescription: "DeskAnchor") }
                .first?
                .withSymbolConfiguration(config)
        image?.isTemplate = false

        if let image {
            button.image = image
            button.imagePosition = .imageOnly
            button.title = ""
            button.contentTintColor = latestStatus.permissionGranted ? nil : .systemOrange
            statusItem.length = NSStatusItem.squareLength
        } else {
            button.image = nil
            button.imagePosition = .noImage
            button.title = "D"
            button.contentTintColor = nil
            statusItem.length = 28
        }
        button.toolTip = latestStatus.message ?? "DeskAnchor"
        button.needsDisplay = true
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let headline = NSMenuItem(title: "DeskAnchor", action: nil, keyEquivalent: "")
        headline.isEnabled = false
        menu.addItem(headline)

        if let message = latestStatus.message {
            let messageItem = NSMenuItem(title: message, action: nil, keyEquivalent: "")
            messageItem.isEnabled = false
            menu.addItem(messageItem)
        }

        let displayItem = NSMenuItem(
            title: "显示器：\(latestStatus.displayCount) 台已连接",
            action: nil,
            keyEquivalent: ""
        )
        displayItem.isEnabled = false
        menu.addItem(displayItem)

        let permissionItem = NSMenuItem(
            title: latestStatus.permissionGranted ? "权限正常" : "需要辅助功能权限",
            action: latestStatus.permissionGranted ? nil : #selector(openPermissionSettings),
            keyEquivalent: ""
        )
        permissionItem.target = self
        permissionItem.isEnabled = !latestStatus.permissionGranted
        menu.addItem(permissionItem)

        menu.addItem(.separator())

        menu.addItem(actionItem("保存当前布局", #selector(saveLayout)))
        menu.addItem(actionItem("恢复当前显示器布局", #selector(restoreLayout)))
        menu.addItem(actionItem(latestStatus.autoRestoreEnabled ? "暂停自动恢复" : "开启自动恢复", #selector(toggleAutoRestore)))

        menu.addItem(.separator())
        menu.addItem(actionItem("显示主界面", #selector(showMainWindowAction)))
        menu.addItem(actionItem("显示器详情...", #selector(showDisplayDetails)))
        menu.addItem(actionItem("打开辅助功能设置...", #selector(openPermissionSettings)))
        menu.addItem(.separator())
        menu.addItem(actionItem("退出", #selector(quit)))

        statusItem.menu = menu
    }

    private func actionItem(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func saveLayout() {
        coordinator.saveCurrentLayout()
    }

    @objc private func restoreLayout() {
        coordinator.restoreCurrentLayout()
    }

    @objc private func toggleAutoRestore() {
        coordinator.toggleAutoRestore()
    }

    @objc private func openPermissionSettings() {
        coordinator.openPermissionSettings()
    }

    @objc private func showDisplayDetails() {
        let alert = NSAlert()
        alert.messageText = "当前显示器"
        alert.informativeText = latestStatus.displaySummary
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    @objc private func showMainWindowAction() {
        showMainWindow?()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
