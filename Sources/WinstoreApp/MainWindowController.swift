import AppKit

@MainActor
final class MainWindowController: NSWindowController {
    private let coordinator: LayoutCoordinator
    private let statusLabel = NSTextField(labelWithString: "")
    private let permissionLabel = NSTextField(labelWithString: "")
    private let displayLabel = NSTextField(labelWithString: "")
    private let identityLabel = NSTextField(labelWithString: "")

    init(coordinator: LayoutCoordinator) {
        self.coordinator = coordinator

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 260),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Winstore"
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.contentView = buildContentView()
        update(status: coordinator.status)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func update(status: AppStatus) {
        permissionLabel.stringValue = status.permissionGranted ? "辅助功能权限：已授权" : "辅助功能权限：未授权"
        displayLabel.stringValue = "显示器：\(status.displayCount) 台已连接"
        statusLabel.stringValue = status.message ?? "Winstore 正在运行"
    }

    private func buildContentView() -> NSView {
        let contentView = NSView()

        let titleLabel = NSTextField(labelWithString: "Winstore")
        titleLabel.font = .systemFont(ofSize: 24, weight: .semibold)

        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.textColor = .secondaryLabelColor

        permissionLabel.font = .systemFont(ofSize: 14)
        displayLabel.font = .systemFont(ofSize: 14)
        identityLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        identityLabel.textColor = .secondaryLabelColor
        identityLabel.lineBreakMode = .byTruncatingMiddle
        identityLabel.maximumNumberOfLines = 2
        identityLabel.stringValue = appIdentitySummary()

        let saveButton = NSButton(title: "保存当前布局", target: self, action: #selector(saveLayout))
        let restoreButton = NSButton(title: "恢复当前显示器布局", target: self, action: #selector(restoreLayout))
        let permissionButton = NSButton(title: "打开辅助功能设置", target: self, action: #selector(openPermissionSettings))

        let stack = NSStackView(views: [
            titleLabel,
            statusLabel,
            permissionLabel,
            displayLabel,
            identityLabel,
            saveButton,
            restoreButton,
            permissionButton
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 28)
        ])

        return contentView
    }

    private func appIdentitySummary() -> String {
        let bundleID = Bundle.main.bundleIdentifier ?? "未知 Bundle ID"
        return "\(bundleID)\n\(Bundle.main.bundlePath)"
    }

    @objc private func saveLayout() {
        coordinator.saveCurrentLayout()
    }

    @objc private func restoreLayout() {
        coordinator.restoreCurrentLayout()
    }

    @objc private func openPermissionSettings() {
        coordinator.openPermissionSettings()
    }
}
