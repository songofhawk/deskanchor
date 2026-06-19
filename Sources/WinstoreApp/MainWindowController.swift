import AppKit

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
    private let coordinator: LayoutCoordinator

    private let statusMessageLabel = NSTextField(labelWithString: "")
    private let permissionPill = StatusPill()
    private let displayPill = StatusPill()
    private let displayValueLabel = NSTextField(labelWithString: "")
    private let identityLabel = NSTextField(labelWithString: "")
    private let permissionButton = AccentButton(title: "打开辅助功能设置", style: .secondary)

    init(coordinator: LayoutCoordinator) {
        self.coordinator = coordinator

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Winstore"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self
        window.contentView = buildContentView()
        update(status: coordinator.status)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        NSApp.setActivationPolicy(.regular)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func update(status: AppStatus) {
        if status.permissionGranted {
            permissionPill.configure(text: "已授权", tint: .systemGreen)
            permissionButton.isHidden = true
        } else {
            permissionPill.configure(text: "未授权", tint: .systemOrange)
            permissionButton.isHidden = false
        }

        displayPill.configure(text: status.displayCount == 1 ? "单屏" : "\(status.displayCount) 屏", tint: .controlAccentColor)
        displayValueLabel.stringValue = "\(status.displayCount) 台显示器已连接"
        statusMessageLabel.stringValue = status.message ?? "正在守护你的窗口布局"
    }

    // MARK: - Layout

    private func buildContentView() -> NSView {
        let background = NSVisualEffectView()
        background.material = .underWindowBackground
        background.blendingMode = .behindWindow
        background.state = .active

        let stack = NSStackView(views: [
            buildHeader(),
            buildStatusCard(),
            buildMessageRow(),
            buildActionsCard(),
            identityFooter()
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setHuggingPriority(.defaultHigh, for: .vertical)

        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: background.topAnchor, constant: 36),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: background.bottomAnchor, constant: -28)
        ])

        return background
    }

    private func buildHeader() -> NSView {
        let badge = IconBadge(symbolName: "macwindow.on.rectangle")

        let titleLabel = NSTextField(labelWithString: "Winstore")
        titleLabel.font = .systemFont(ofSize: 26, weight: .bold)

        let subtitleLabel = NSTextField(labelWithString: "多显示器窗口布局守护")
        subtitleLabel.font = .systemFont(ofSize: 13, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor

        let textStack = NSStackView(views: [titleLabel, subtitleLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        let header = NSStackView(views: [badge, textStack])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 14
        fillWidth(header)
        return header
    }

    private func buildStatusCard() -> NSView {
        let card = CardView()

        let permissionRow = infoRow(
            symbol: "lock.shield.fill",
            tint: .systemBlue,
            title: "辅助功能权限",
            trailing: permissionPill
        )

        let separator = NSBox()
        separator.boxType = .separator

        let displayRow = infoRow(
            symbol: "display",
            tint: .systemTeal,
            title: "显示器",
            trailing: displayPill
        )

        displayValueLabel.font = .systemFont(ofSize: 12)
        displayValueLabel.textColor = .secondaryLabelColor

        let rows = NSStackView(views: [permissionRow, separator, displayRow, displayValueLabel])
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 12
        rows.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(rows)
        NSLayoutConstraint.activate([
            rows.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            rows.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            rows.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            rows.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            separator.widthAnchor.constraint(equalTo: rows.widthAnchor)
        ])
        fillWidth(card)
        return card
    }

    private func buildMessageRow() -> NSView {
        let icon = NSImageView()
        icon.image = symbol("sparkles", pointSize: 13, weight: .semibold)
        icon.contentTintColor = .controlAccentColor
        icon.setContentHuggingPriority(.required, for: .horizontal)

        statusMessageLabel.font = .systemFont(ofSize: 12.5, weight: .medium)
        statusMessageLabel.textColor = .secondaryLabelColor
        statusMessageLabel.lineBreakMode = .byTruncatingTail
        statusMessageLabel.maximumNumberOfLines = 2

        let row = NSStackView(views: [icon, statusMessageLabel])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 7
        fillWidth(row)
        return row
    }

    private func buildActionsCard() -> NSView {
        let saveButton = AccentButton(title: "保存当前布局", style: .primary)
        saveButton.target = self
        saveButton.action = #selector(saveLayout)
        saveButton.symbolName = "square.and.arrow.down.fill"

        let restoreButton = AccentButton(title: "恢复当前显示器布局", style: .secondary)
        restoreButton.target = self
        restoreButton.action = #selector(restoreLayout)
        restoreButton.symbolName = "arrow.uturn.backward"

        permissionButton.target = self
        permissionButton.action = #selector(openPermissionSettings)
        permissionButton.symbolName = "gearshape.fill"

        let stack = NSStackView(views: [saveButton, restoreButton, permissionButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        fillWidth(stack)
        for view in stack.arrangedSubviews {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return stack
    }

    private func identityFooter() -> NSView {
        identityLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        identityLabel.textColor = .tertiaryLabelColor
        identityLabel.lineBreakMode = .byTruncatingMiddle
        identityLabel.maximumNumberOfLines = 2
        identityLabel.stringValue = appIdentitySummary()
        fillWidth(identityLabel)
        return identityLabel
    }

    // MARK: - Builders

    private func infoRow(symbol name: String, tint: NSColor, title: String, trailing: NSView) -> NSView {
        let icon = NSImageView()
        icon.image = symbol(name, pointSize: 15, weight: .semibold)
        icon.contentTintColor = tint
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 14, weight: .medium)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [icon, titleLabel, spacer, trailing])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        return row
    }

    private func fillWidth(_ view: NSView) {
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    private func symbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
    }

    private func appIdentitySummary() -> String {
        let bundleID = Bundle.main.bundleIdentifier ?? "未知 Bundle ID"
        return "\(bundleID)\n\(Bundle.main.bundlePath)"
    }

    // MARK: - Actions

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

// MARK: - Custom views

/// Rounded "card" surface with a subtle fill and border that follows the system appearance.
private final class CardView: NSView {
    override var wantsUpdateLayer: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    override func updateLayer() {
        layer?.cornerRadius = 14
        layer?.borderWidth = 1
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.55).cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.6).cgColor
    }
}

/// Gradient-filled rounded square holding an SF Symbol — the app's visual anchor.
private final class IconBadge: NSView {
    private let gradient = CAGradientLayer()
    private let imageView = NSImageView()

    init(symbolName: String) {
        super.init(frame: .zero)
        wantsLayer = true

        gradient.colors = [
            NSColor.controlAccentColor.cgColor,
            NSColor.controlAccentColor.blended(withFraction: 0.45, of: .systemPurple)?.cgColor ?? NSColor.systemPurple.cgColor
        ]
        gradient.startPoint = CGPoint(x: 0, y: 1)
        gradient.endPoint = CGPoint(x: 1, y: 0)
        gradient.cornerRadius = 14
        layer?.addSublayer(gradient)

        let config = NSImage.SymbolConfiguration(pointSize: 26, weight: .semibold)
        imageView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        imageView.contentTintColor = .white
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 56),
            heightAnchor.constraint(equalToConstant: 56),
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        gradient.frame = bounds
    }
}

/// Capsule status indicator with a tinted background and matching dot.
private final class StatusPill: NSView {
    override var wantsUpdateLayer: Bool { true }

    private let dot = NSView()
    private let label = NSTextField(labelWithString: "")
    private var tint: NSColor = .systemGreen

    init() {
        super.init(frame: .zero)
        wantsLayer = true

        dot.wantsLayer = true
        dot.translatesAutoresizingMaskIntoConstraints = false

        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(dot)
        addSubview(label)
        setContentHuggingPriority(.required, for: .horizontal)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 24),
            dot.widthAnchor.constraint(equalToConstant: 7),
            dot.heightAnchor.constraint(equalToConstant: 7),
            dot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -11),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func configure(text: String, tint: NSColor) {
        self.tint = tint
        label.stringValue = text
        label.textColor = tint
        needsDisplay = true
        dot.needsDisplay = true
        dot.layer?.backgroundColor = tint.cgColor
        dot.layer?.cornerRadius = 3.5
    }

    override func updateLayer() {
        layer?.cornerRadius = 12
        layer?.backgroundColor = tint.withAlphaComponent(0.14).cgColor
        dot.layer?.cornerRadius = 3.5
        dot.layer?.backgroundColor = tint.cgColor
    }
}

/// Full-width pill button with an SF Symbol and a primary/secondary style.
private final class AccentButton: NSButton {
    enum Style {
        case primary
        case secondary
    }

    var symbolName: String? {
        didSet { applySymbol() }
    }

    private let style: Style
    private var tracking: NSTrackingArea?
    private var hovering = false {
        didSet { needsDisplay = true }
    }

    override var wantsUpdateLayer: Bool { true }

    init(title: String, style: Style) {
        self.style = style
        super.init(frame: .zero)
        self.title = title
        wantsLayer = true
        isBordered = false
        bezelStyle = .regularSquare
        font = .systemFont(ofSize: 13.5, weight: .semibold)
        imagePosition = .imageLeading
        imageHugsTitle = true
        focusRingType = .none
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 38).isActive = true
        applySymbol()
        applyTitleColor()
    }

    required init?(coder: NSCoder) { nil }

    private func applySymbol() {
        guard let symbolName else { image = nil; return }
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        contentTintColor = style == .primary ? .white : .controlAccentColor
    }

    private func applyTitleColor() {
        let color: NSColor = style == .primary ? .white : .controlAccentColor
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .foregroundColor: color,
                .font: font ?? .systemFont(ofSize: 13.5, weight: .semibold)
            ]
        )
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func updateLayer() {
        layer?.cornerRadius = 10
        let accent = NSColor.controlAccentColor
        switch style {
        case .primary:
            let base = hovering ? accent.blended(withFraction: 0.12, of: .black) ?? accent : accent
            layer?.backgroundColor = base.cgColor
            layer?.borderWidth = 0
        case .secondary:
            layer?.backgroundColor = accent.withAlphaComponent(hovering ? 0.16 : 0.10).cgColor
            layer?.borderWidth = 1
            layer?.borderColor = accent.withAlphaComponent(0.30).cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTitleColor()
        applySymbol()
    }
}
