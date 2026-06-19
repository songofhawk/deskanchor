import AppKit
import DeskAnchorCore

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private let coordinator: LayoutCoordinator

    private let statusMessageLabel = NSTextField(labelWithString: "")
    private let permissionPill = StatusPill()
    private let displayPill = StatusPill()
    private let displayValueLabel = NSTextField(labelWithString: "")
    private let identityLabel = NSTextField(labelWithString: "")
    private let permissionButton = AccentButton(title: "打开辅助功能设置", style: .secondary)
    private let historyTable = NSTableView()
    private let windowTable = NSTableView()
    private let emptyHistoryLabel = NSTextField(labelWithString: "还没有保存历史")
    private let snapshotTitleLabel = NSTextField(labelWithString: "选择一条保存历史")
    private let snapshotMetaLabel = NSTextField(labelWithString: "")
    private let displayArrangementLabel = NSTextField(labelWithString: "")
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }()
    private var history: [LayoutSnapshot] = []
    private var selectedSnapshot: LayoutSnapshot?
    private var selectedWindows: [WindowRecord] = []

    init(coordinator: LayoutCoordinator) {
        self.coordinator = coordinator

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 940, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "DeskAnchor"
        window.minSize = NSSize(width: 980, height: 620)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self
        window.contentView = buildContentView()
        refreshHistory(selection: .first)
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
        refreshHistory(selection: .keepCurrent)
    }

    // MARK: - Layout

    private func buildContentView() -> NSView {
        let background = NSVisualEffectView()
        background.material = .underWindowBackground
        background.blendingMode = .behindWindow
        background.state = .active

        let leftStack = NSStackView(views: [
            buildHeader(),
            buildStatusCard(),
            buildMessageRow(),
            buildActionsCard(),
            identityFooter()
        ])
        leftStack.orientation = .vertical
        leftStack.alignment = .leading
        leftStack.spacing = 18
        leftStack.translatesAutoresizingMaskIntoConstraints = false
        leftStack.setHuggingPriority(.required, for: .vertical)
        leftStack.setContentCompressionResistancePriority(.required, for: .vertical)

        let stack = NSStackView(views: [
            leftStack,
            buildHistoryBrowser()
        ])
        stack.orientation = .horizontal
        stack.alignment = .top
        stack.distribution = .fill
        stack.spacing = 22
        stack.translatesAutoresizingMaskIntoConstraints = false

        leftStack.widthAnchor.constraint(equalToConstant: 330).isActive = true
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

    private func buildHistoryBrowser() -> NSView {
        let titleLabel = NSTextField(labelWithString: "保存历史")
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)

        let subtitleLabel = NSTextField(labelWithString: "按保存时间查看显示器排列和窗口")
        subtitleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor

        let header = NSStackView(views: [titleLabel, subtitleLabel])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 2

        configureHistoryTable()
        configureWindowTable()

        let browser = NSSplitView()
        browser.isVertical = true
        browser.dividerStyle = .thin
        browser.translatesAutoresizingMaskIntoConstraints = false
        browser.addArrangedSubview(historyScrollView())
        browser.addArrangedSubview(snapshotDetailView())

        let container = NSStackView(views: [header, browser])
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 10
        container.translatesAutoresizingMaskIntoConstraints = false
        fillWidth(container)

        NSLayoutConstraint.activate([
            browser.widthAnchor.constraint(equalTo: container.widthAnchor),
            browser.heightAnchor.constraint(greaterThanOrEqualToConstant: 500)
        ])

        return container
    }

    private func buildHeader() -> NSView {
        let badge = IconBadge()

        let titleLabel = NSTextField(labelWithString: "DeskAnchor")
        titleLabel.font = .systemFont(ofSize: 26, weight: .bold)

        let subtitleLabel = NSTextField(labelWithString: "把窗口锚定到每套显示器")
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
        card.heightAnchor.constraint(equalToConstant: 116).isActive = true
        card.setContentHuggingPriority(.required, for: .vertical)
        card.setContentCompressionResistancePriority(.required, for: .vertical)
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

    private func configureHistoryTable() {
        guard historyTable.tableColumns.isEmpty else { return }

        historyTable.headerView = nil
        historyTable.rowHeight = 52
        historyTable.selectionHighlightStyle = .regular
        historyTable.dataSource = self
        historyTable.delegate = self
        historyTable.usesAlternatingRowBackgroundColors = false
        historyTable.addTableColumn(tableColumn("history", width: 210))
    }

    private func configureWindowTable() {
        guard windowTable.tableColumns.isEmpty else { return }

        windowTable.headerView = nil
        windowTable.rowHeight = 44
        windowTable.selectionHighlightStyle = .none
        windowTable.dataSource = self
        windowTable.delegate = self
        windowTable.addTableColumn(tableColumn("window", width: 320))
    }

    private func tableColumn(_ identifier: String, width: CGFloat) -> NSTableColumn {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
        column.width = width
        column.minWidth = width
        column.resizingMask = .autoresizingMask
        return column
    }

    private func historyScrollView() -> NSView {
        emptyHistoryLabel.font = .systemFont(ofSize: 12.5, weight: .medium)
        emptyHistoryLabel.textColor = .secondaryLabelColor
        emptyHistoryLabel.alignment = .center

        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.documentView = historyTable
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scrollView)
        container.addSubview(emptyHistoryLabel)

        emptyHistoryLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: 210),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            emptyHistoryLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            emptyHistoryLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        return container
    }

    private func snapshotDetailView() -> NSView {
        snapshotTitleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        snapshotTitleLabel.lineBreakMode = .byTruncatingTail

        snapshotMetaLabel.font = .systemFont(ofSize: 12, weight: .medium)
        snapshotMetaLabel.textColor = .secondaryLabelColor
        snapshotMetaLabel.maximumNumberOfLines = 2

        displayArrangementLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        displayArrangementLabel.textColor = .secondaryLabelColor
        displayArrangementLabel.maximumNumberOfLines = 6
        displayArrangementLabel.lineBreakMode = .byTruncatingTail

        let displaysTitle = sectionTitle("显示器排列")
        let windowsTitle = sectionTitle("窗口")

        let windowScrollView = NSScrollView()
        windowScrollView.borderType = .noBorder
        windowScrollView.hasVerticalScroller = true
        windowScrollView.documentView = windowTable
        windowScrollView.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [
            snapshotTitleLabel,
            snapshotMetaLabel,
            displaysTitle,
            displayArrangementLabel,
            windowsTitle,
            windowScrollView
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: 300),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            windowScrollView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            windowScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 230)
        ])

        return container
    }

    private func sectionTitle(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .labelColor
        return label
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

    // MARK: - History

    private enum HistorySelection {
        case first
        case keepCurrent
        case snapshot(Date)
    }

    private func refreshHistory(selection: HistorySelection) {
        let selectedID = selectedSnapshot?.capturedAt
        history = coordinator.layoutHistory()
        historyTable.reloadData()
        emptyHistoryLabel.isHidden = !history.isEmpty

        guard !history.isEmpty else {
            selectSnapshot(nil)
            return
        }

        let rowToSelect: Int
        switch selection {
        case .first:
            rowToSelect = 0
        case .snapshot(let capturedAt):
            rowToSelect = history.firstIndex(where: { $0.capturedAt == capturedAt }) ?? 0
        case .keepCurrent:
            if let selectedID,
               let existingRow = history.firstIndex(where: { $0.capturedAt == selectedID }) {
                rowToSelect = existingRow
            } else {
                rowToSelect = max(0, min(historyTable.selectedRow, history.count - 1))
            }
        }

        historyTable.selectRowIndexes(IndexSet(integer: rowToSelect), byExtendingSelection: false)
        selectSnapshot(history[rowToSelect])
    }

    private func selectSnapshot(_ snapshot: LayoutSnapshot?) {
        selectedSnapshot = snapshot
        selectedWindows = snapshot?.windows.sorted { lhs, rhs in
            if lhs.signature.ownerName != rhs.signature.ownerName {
                return lhs.signature.ownerName < rhs.signature.ownerName
            }
            return lhs.title < rhs.title
        } ?? []

        guard let snapshot else {
            snapshotTitleLabel.stringValue = "选择一条保存历史"
            snapshotMetaLabel.stringValue = "保存后会在这里显示屏幕和窗口详情"
            displayArrangementLabel.stringValue = ""
            windowTable.reloadData()
            return
        }

        snapshotTitleLabel.stringValue = dateFormatter.string(from: snapshot.capturedAt)
        snapshotMetaLabel.stringValue = "\(snapshot.topology.displays.count) 台显示器，\(snapshot.windows.count) 个窗口"
        displayArrangementLabel.stringValue = snapshot.topology.humanSummary
        windowTable.reloadData()
    }

    nonisolated func numberOfRows(in tableView: NSTableView) -> Int {
        MainActor.assumeIsolated {
            tableView === historyTable ? history.count : selectedWindows.count
        }
    }

    nonisolated func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        MainActor.assumeIsolated {
            if tableView === historyTable {
                return historyCell(for: row)
            }
            return windowCell(for: row)
        }
    }

    nonisolated func tableViewSelectionDidChange(_ notification: Notification) {
        MainActor.assumeIsolated {
            let row = historyTable.selectedRow
            guard row >= 0, row < history.count else {
                selectSnapshot(nil)
                return
            }
            selectSnapshot(history[row])
        }
    }

    private func historyCell(for row: Int) -> NSView {
        guard row < history.count else { return NSView() }
        let snapshot = history[row]
        let title = dateFormatter.string(from: snapshot.capturedAt)
        let subtitle = "\(snapshot.topology.displays.count) 台显示器 · \(snapshot.windows.count) 个窗口"
        return TwoLineTableCell(title: title, subtitle: subtitle)
    }

    private func windowCell(for row: Int) -> NSView {
        guard row < selectedWindows.count, let snapshot = selectedSnapshot else { return NSView() }
        let record = selectedWindows[row]
        let title = record.title.isEmpty ? record.signature.ownerName : "\(record.signature.ownerName) · \(record.title)"
        let displayName = snapshot.topology.displays.first {
            $0.hardwareKey == record.displayHardwareKey
        }?.name ?? "未知显示器"
        let frame = record.frame.rounded()
        let subtitle = "\(displayName) · x \(Int(frame.x)), y \(Int(frame.y)), \(Int(frame.width))x\(Int(frame.height))"
        return TwoLineTableCell(title: title, subtitle: subtitle)
    }

    // MARK: - Actions

    @objc private func saveLayout() {
        guard let snapshot = coordinator.saveCurrentLayout() else {
            refreshHistory(selection: .keepCurrent)
            return
        }
        refreshHistory(selection: .snapshot(snapshot.capturedAt))
    }

    @objc private func restoreLayout() {
        coordinator.restoreCurrentLayout()
    }

    @objc private func openPermissionSettings() {
        coordinator.openPermissionSettings()
    }
}

// MARK: - Custom views

private final class TwoLineTableCell: NSTableCellView {
    init(title: String, subtitle: String) {
        super.init(frame: .zero)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12.5, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1

        let subtitleLabel = NSTextField(labelWithString: subtitle)
        subtitleLabel.font = .systemFont(ofSize: 11, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.maximumNumberOfLines = 1

        let stack = NSStackView(views: [titleLabel, subtitleLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }
}

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

/// App icon surface used as the app's visual anchor.
private final class IconBadge: NSView {
    private let imageView = NSImageView()

    init() {
        super.init(frame: .zero)

        imageView.image = DeskAnchorIcon.appIcon(size: 112)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 56),
            heightAnchor.constraint(equalToConstant: 56),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }
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
