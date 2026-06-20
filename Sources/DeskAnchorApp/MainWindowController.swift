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
    private let historyPanelButton = IconButton(
        symbolName: "sidebar.right",
        tooltip: "显示保存历史",
        tint: .controlAccentColor,
        size: 30
    )
    private let historyDirectionView = NSImageView()
    private let historyTable = NSTableView()
    private let windowTable = NSTableView()
    private let emptyHistoryLabel = NSTextField(labelWithString: "还没有保存历史")
    private let snapshotTitleLabel = NSTextField(labelWithString: "选择一条保存历史")
    private let snapshotMetaLabel = NSTextField(labelWithString: "")
    private let editSnapshotTitleButton = IconButton(
        symbolName: "pencil",
        tooltip: "修改保存历史标题",
        tint: .controlAccentColor,
        size: 26
    )
    private let displayArrangementView = DisplayArrangementView()
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
    private var historyBrowserView: NSView?
    private var historyBrowserWidthConstraint: NSLayoutConstraint?
    private var rootStackView: NSStackView?
    private var mainColumnView: NSView?
    private var mainColumnCollapsedWidthConstraint: NSLayoutConstraint?
    private var mainColumnExpandedWidthConstraint: NSLayoutConstraint?
    private var isHistoryVisible = false

    private enum WindowLayoutMetrics {
        static let compactSize = NSSize(width: 394, height: 540)
        static let expandedSize = NSSize(width: 1320, height: 620)
        static let compactMainColumnWidth: CGFloat = expandedMainColumnWidth
        static let expandedMainColumnWidth: CGFloat = 330
        static let historyBrowserWidth: CGFloat = 900
        static let historyListWidth: CGFloat = 430
        static let historyDetailMinWidth: CGFloat = 430
        static let primaryActionWidth: CGFloat = 270
        static let historyTransitionDuration: TimeInterval = 0.24
    }

    init(coordinator: LayoutCoordinator) {
        self.coordinator = coordinator

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: WindowLayoutMetrics.compactSize),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "DeskAnchor"
        window.minSize = WindowLayoutMetrics.compactSize
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
            permissionPill.isEnabled = false
            permissionPill.toolTip = nil
        } else {
            permissionPill.configure(text: "未授权", tint: .systemOrange)
            permissionPill.isEnabled = true
            permissionPill.toolTip = "点击打开辅助功能设置"
        }

        displayPill.configure(text: status.displayCount == 1 ? "单屏" : "\(status.displayCount) 屏", tint: .controlAccentColor)
        displayPill.isEnabled = false
        displayValueLabel.stringValue = "\(status.displayCount) 台显示器已连接"
        statusMessageLabel.stringValue = status.message ?? (status.permissionGranted ? "正在守护你的窗口布局" : "点击“未授权”打开辅助功能设置")
        refreshHistory(selection: .keepCurrent)
    }

    // MARK: - Layout

    private func buildContentView() -> NSView {
        let background = NSVisualEffectView()
        background.material = .underWindowBackground
        background.blendingMode = .behindWindow
        background.state = .active

        let header = buildHeader()
        let statusCard = buildStatusCard()
        let messageToolbar = buildMessageToolbarRow()
        let actions = buildActionsCard()
        let primaryContent = NSStackView(views: [header, statusCard, messageToolbar, actions])
        primaryContent.orientation = .vertical
        primaryContent.alignment = .leading
        primaryContent.spacing = 18
        primaryContent.translatesAutoresizingMaskIntoConstraints = false
        fillWidth(primaryContent)
        primaryContent.setCustomSpacing(30, after: messageToolbar)
        for view in primaryContent.arrangedSubviews {
            view.widthAnchor.constraint(equalTo: primaryContent.widthAnchor).isActive = true
        }

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        let footer = identityFooter()

        let mainColumn = NSStackView(views: [
            primaryContent,
            spacer,
            footer
        ])
        mainColumn.orientation = .vertical
        mainColumn.alignment = .leading
        mainColumn.spacing = 18
        mainColumn.translatesAutoresizingMaskIntoConstraints = false
        mainColumn.setHuggingPriority(.required, for: .horizontal)
        mainColumn.setContentCompressionResistancePriority(.required, for: .horizontal)

        let historyBrowser = buildHistoryBrowser()
        let historyBrowserContainer = ClippingView()
        historyBrowserContainer.translatesAutoresizingMaskIntoConstraints = false
        historyBrowserContainer.isHidden = true
        historyBrowserContainer.addSubview(historyBrowser)
        historyBrowserView = historyBrowserContainer

        let stack = NSStackView(views: [
            mainColumn,
            historyBrowserContainer
        ])
        stack.orientation = .horizontal
        stack.alignment = .top
        stack.distribution = .fill
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setCustomSpacing(0, after: mainColumn)
        rootStackView = stack
        mainColumnView = mainColumn

        mainColumnCollapsedWidthConstraint = mainColumn.widthAnchor.constraint(equalToConstant: WindowLayoutMetrics.compactMainColumnWidth)
        mainColumnExpandedWidthConstraint = mainColumn.widthAnchor.constraint(equalToConstant: WindowLayoutMetrics.expandedMainColumnWidth)
        historyBrowserWidthConstraint = historyBrowserContainer.widthAnchor.constraint(equalToConstant: 0)
        mainColumnCollapsedWidthConstraint?.isActive = true

        background.addSubview(stack)
        NSLayoutConstraint.activate([
            primaryContent.widthAnchor.constraint(equalTo: mainColumn.widthAnchor),
            footer.widthAnchor.constraint(equalTo: mainColumn.widthAnchor),
            stack.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: background.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: background.trailingAnchor, constant: -32),
            stack.topAnchor.constraint(equalTo: background.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -24),
            historyBrowserWidthConstraint!,
            historyBrowser.leadingAnchor.constraint(equalTo: historyBrowserContainer.leadingAnchor),
            historyBrowser.topAnchor.constraint(equalTo: historyBrowserContainer.topAnchor),
            historyBrowser.bottomAnchor.constraint(equalTo: historyBrowserContainer.bottomAnchor),
            historyBrowser.widthAnchor.constraint(equalToConstant: WindowLayoutMetrics.historyBrowserWidth)
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

        let listView = historyScrollView()
        let detailView = snapshotDetailView()
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        let listColumn = NSStackView(views: [header, listView])
        listColumn.orientation = .vertical
        listColumn.alignment = .leading
        listColumn.spacing = 6
        listColumn.translatesAutoresizingMaskIntoConstraints = false

        let browser = NSStackView(views: [listColumn, separator, detailView])
        browser.orientation = .horizontal
        browser.alignment = .top
        browser.distribution = .fill
        browser.spacing = 12
        browser.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            browser.heightAnchor.constraint(greaterThanOrEqualToConstant: 560),
            listColumn.widthAnchor.constraint(equalToConstant: WindowLayoutMetrics.historyListWidth),
            listColumn.heightAnchor.constraint(equalTo: browser.heightAnchor),
            listView.widthAnchor.constraint(equalTo: listColumn.widthAnchor),
            detailView.heightAnchor.constraint(equalTo: browser.heightAnchor),
            detailView.widthAnchor.constraint(greaterThanOrEqualToConstant: WindowLayoutMetrics.historyDetailMinWidth),
            separator.widthAnchor.constraint(equalToConstant: 1),
            separator.heightAnchor.constraint(equalTo: browser.heightAnchor)
        ])

        return browser
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
        permissionPill.target = self
        permissionPill.action = #selector(openPermissionSettings)

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
        statusMessageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [icon, statusMessageLabel])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 7
        row.translatesAutoresizingMaskIntoConstraints = false
        fillWidth(row)
        return row
    }

    private func buildMessageToolbarRow() -> NSView {
        historyPanelButton.target = self
        historyPanelButton.action = #selector(toggleHistory)
        configureHistoryDirectionView(expanded: false, tooltip: "显示保存历史")

        let historyControls = NSStackView(views: [historyPanelButton, historyDirectionView])
        historyControls.orientation = .horizontal
        historyControls.alignment = .centerY
        historyControls.spacing = 6
        historyControls.translatesAutoresizingMaskIntoConstraints = false
        historyControls.setContentHuggingPriority(.required, for: .horizontal)

        let messageRow = buildMessageRow()
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(messageRow)
        container.addSubview(historyControls)
        fillWidth(container)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: 30),
            messageRow.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            messageRow.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            messageRow.trailingAnchor.constraint(lessThanOrEqualTo: historyControls.leadingAnchor, constant: -12),
            historyControls.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            historyControls.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return container
    }

    private func buildActionsCard() -> NSView {
        let saveButton = AccentButton(title: "保存当前布局", style: .primary)
        saveButton.target = self
        saveButton.action = #selector(saveLayout)
        saveButton.symbolName = "square.and.arrow.down.fill"

        let restoreButton = AccentButton(title: "恢复最近布局", style: .secondary)
        restoreButton.target = self
        restoreButton.action = #selector(restoreLayout)
        restoreButton.symbolName = "arrow.uturn.backward"

        let stack = NSStackView(views: [saveButton, restoreButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        fillWidth(stack)
        saveButton.widthAnchor.constraint(equalToConstant: WindowLayoutMetrics.primaryActionWidth).isActive = true
        restoreButton.widthAnchor.constraint(equalToConstant: WindowLayoutMetrics.primaryActionWidth).isActive = true
        return stack
    }

    private func configureHistoryTable() {
        guard historyTable.tableColumns.isEmpty else { return }

        historyTable.headerView = nil
        historyTable.rowHeight = 72
        historyTable.intercellSpacing = .zero
        historyTable.selectionHighlightStyle = .regular
        historyTable.dataSource = self
        historyTable.delegate = self
        historyTable.usesAlternatingRowBackgroundColors = false
        historyTable.backgroundColor = .clear
        historyTable.addTableColumn(tableColumn("history", width: WindowLayoutMetrics.historyListWidth))
    }

    private func configureWindowTable() {
        guard windowTable.tableColumns.isEmpty else { return }

        windowTable.headerView = nil
        windowTable.rowHeight = 40
        windowTable.intercellSpacing = .zero
        windowTable.selectionHighlightStyle = .none
        windowTable.dataSource = self
        windowTable.delegate = self
        windowTable.backgroundColor = .clear
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
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scrollView.documentView = historyTable
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scrollView)
        container.addSubview(emptyHistoryLabel)

        emptyHistoryLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: WindowLayoutMetrics.historyListWidth),
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
        snapshotTitleLabel.maximumNumberOfLines = 1
        snapshotTitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        editSnapshotTitleButton.target = self
        editSnapshotTitleButton.action = #selector(editSelectedSnapshotTitle)
        editSnapshotTitleButton.isEnabled = false

        let titleRow = NSStackView(views: [snapshotTitleLabel, editSnapshotTitleButton])
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 8
        titleRow.translatesAutoresizingMaskIntoConstraints = false
        fillWidth(titleRow)

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
        windowScrollView.drawsBackground = false
        windowScrollView.automaticallyAdjustsContentInsets = false
        windowScrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        windowScrollView.documentView = windowTable
        windowScrollView.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [
            titleRow,
            snapshotMetaLabel,
            displaysTitle,
            displayArrangementView,
            displayArrangementLabel,
            windowsTitle,
            windowScrollView
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = DetailPanelView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: WindowLayoutMetrics.historyDetailMinWidth),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14),
            titleRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            displayArrangementView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            displayArrangementView.heightAnchor.constraint(equalToConstant: 150),
            windowScrollView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            windowScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 320)
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
            editSnapshotTitleButton.isEnabled = false
            displayArrangementView.topology = nil
            displayArrangementLabel.stringValue = ""
            windowTable.reloadData()
            return
        }

        snapshotTitleLabel.stringValue = title(for: snapshot)
        snapshotMetaLabel.stringValue = detailMeta(for: snapshot)
        editSnapshotTitleButton.isEnabled = true
        displayArrangementView.topology = snapshot.topology
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

    nonisolated func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        MainActor.assumeIsolated {
            guard tableView === historyTable, row >= 0, row < history.count else {
                return tableView.rowHeight
            }

            let displayLineCount = max(1, history[row].topology.humanSummary.split(separator: "\n").count)
            let customTitleLineHeight: CGFloat = history[row].customTitle == nil ? 0 : 14
            return max(72, CGFloat(48 + displayLineCount * 15) + customTitleLineHeight)
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
        let summary = countSummary(for: snapshot)
        let displaySummary = snapshot.topology.humanSummary
        let timestamp = dateFormatter.string(from: snapshot.capturedAt)
        let cell = HistoryTableCell(
            title: title(for: snapshot),
            countSummary: snapshot.customTitle == nil ? nil : summary,
            displaySummary: displaySummary,
            timestamp: timestamp
        )
        cell.editButton.tag = row
        cell.editButton.target = self
        cell.editButton.action = #selector(editHistoryItemTitle(_:))
        cell.restoreButton.tag = row
        cell.restoreButton.target = self
        cell.restoreButton.action = #selector(restoreHistoryItem(_:))
        cell.deleteButton.tag = row
        cell.deleteButton.target = self
        cell.deleteButton.action = #selector(deleteHistoryItem(_:))
        return cell
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

    private func title(for snapshot: LayoutSnapshot) -> String {
        snapshot.customTitle ?? countSummary(for: snapshot)
    }

    private func countSummary(for snapshot: LayoutSnapshot) -> String {
        "\(snapshot.topology.displays.count) 台显示器 · \(snapshot.windows.count) 个窗口"
    }

    private func detailMeta(for snapshot: LayoutSnapshot) -> String {
        let timestamp = "保存于 \(dateFormatter.string(from: snapshot.capturedAt))"
        guard snapshot.customTitle != nil else {
            return timestamp
        }
        return "\(countSummary(for: snapshot)) · \(timestamp)"
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

    @objc private func editSelectedSnapshotTitle() {
        guard let snapshot = selectedSnapshot else { return }
        showRenameAlert(for: snapshot)
    }

    @objc private func editHistoryItemTitle(_ sender: NSButton) {
        guard let snapshot = snapshotForHistoryAction(sender) else { return }
        showRenameAlert(for: snapshot)
    }

    @objc private func toggleHistory() {
        let shouldExpand = !isHistoryVisible
        isHistoryVisible = shouldExpand
        updateHistoryButtons(expanded: shouldExpand)

        if shouldExpand {
            prepareHistoryBrowserForExpansion()
        } else {
            window?.minSize = WindowLayoutMetrics.compactSize
        }

        animateHistoryBrowser(expanded: shouldExpand)
    }

    private func updateHistoryButtons(expanded: Bool) {
        let tooltip = expanded ? "隐藏保存历史" : "显示保存历史"
        historyPanelButton.toolTip = tooltip
        configureHistoryDirectionView(expanded: expanded, tooltip: tooltip)
    }

    private func configureHistoryDirectionView(expanded: Bool, tooltip: String) {
        let symbolName = expanded ? "chevron.left" : "chevron.right"
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        historyDirectionView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: tooltip)?
            .withSymbolConfiguration(config)
        historyDirectionView.contentTintColor = .controlAccentColor
        historyDirectionView.toolTip = tooltip
        historyDirectionView.imageScaling = .scaleProportionallyDown
        historyDirectionView.translatesAutoresizingMaskIntoConstraints = false

        if historyDirectionView.constraints.isEmpty {
            NSLayoutConstraint.activate([
                historyDirectionView.widthAnchor.constraint(equalToConstant: 22),
                historyDirectionView.heightAnchor.constraint(equalToConstant: 30)
            ])
        }
    }

    private func prepareHistoryBrowserForExpansion() {
        historyBrowserView?.isHidden = false
        historyBrowserView?.alphaValue = 0
        historyBrowserWidthConstraint?.constant = 0
        if let mainColumnView {
            rootStackView?.setCustomSpacing(0, after: mainColumnView)
        }
        window?.contentView?.layoutSubtreeIfNeeded()
    }

    private func animateHistoryBrowser(expanded: Bool) {
        guard let window else { return }

        let targetSize = expanded ? WindowLayoutMetrics.expandedSize : WindowLayoutMetrics.compactSize
        let targetFrame = windowFrame(for: targetSize)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = WindowLayoutMetrics.historyTransitionDuration
            context.allowsImplicitAnimation = true

            mainColumnCollapsedWidthConstraint?.isActive = !expanded
            mainColumnExpandedWidthConstraint?.isActive = expanded
            historyBrowserWidthConstraint?.constant = expanded ? WindowLayoutMetrics.historyBrowserWidth : 0
            if let mainColumnView {
                rootStackView?.setCustomSpacing(expanded ? 24 : 0, after: mainColumnView)
            }
            historyBrowserView?.alphaValue = expanded ? 1 : 0
            window.contentView?.layoutSubtreeIfNeeded()
            window.animator().setFrame(targetFrame, display: true)
        } completionHandler: { [weak self] in
            guard let self else { return }
            if expanded {
                window.minSize = WindowLayoutMetrics.expandedSize
            } else {
                historyBrowserView?.isHidden = true
                historyBrowserView?.alphaValue = 1
                window.minSize = WindowLayoutMetrics.compactSize
            }
        }
    }

    private func windowFrame(for size: NSSize) -> NSRect {
        guard let window else { return NSRect(origin: .zero, size: size) }

        var frame = window.frame
        let centerX = frame.midX
        let newHeight = size.height
        frame.origin.x = centerX - size.width / 2
        frame.origin.y += frame.height - newHeight
        frame.size = NSSize(width: size.width, height: newHeight)
        return frame
    }

    @objc private func restoreHistoryItem(_ sender: NSButton) {
        guard let snapshot = snapshotForHistoryAction(sender) else { return }
        let capturedAt = dateFormatter.string(from: snapshot.capturedAt)
        confirmAction(
            title: "恢复这条保存历史？",
            message: "将按 \(capturedAt) 保存的布局恢复 \(snapshot.windows.count) 个窗口位置。",
            confirmButton: "恢复",
            style: .informational
        ) { [weak self] in
            guard let self else { return }
            coordinator.restore(snapshot: snapshot)
            refreshHistory(selection: .snapshot(snapshot.capturedAt))
        }
    }

    @objc private func deleteHistoryItem(_ sender: NSButton) {
        guard let snapshot = snapshotForHistoryAction(sender) else { return }
        let capturedAt = dateFormatter.string(from: snapshot.capturedAt)
        confirmAction(
            title: "删除这条保存历史？",
            message: "将删除 \(capturedAt) 保存的布局记录。删除后不能从保存历史中找回。",
            confirmButton: "删除",
            style: .warning
        ) { [weak self] in
            guard let self else { return }
            if coordinator.deleteSnapshot(snapshot) {
                refreshHistory(selection: .keepCurrent)
            }
        }
    }

    @objc private func openPermissionSettings() {
        coordinator.openPermissionSettings()
    }

    private func showRenameAlert(for snapshot: LayoutSnapshot) {
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        textField.stringValue = snapshot.customTitle ?? ""
        textField.placeholderString = countSummary(for: snapshot)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "修改保存历史标题"
        alert.informativeText = "留空会恢复默认标题。"
        alert.accessoryView = textField
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")

        let applyTitleChange: @MainActor () -> Void = { [weak self] in
            guard let self,
                  let updated = coordinator.renameSnapshot(snapshot, to: textField.stringValue) else {
                return
            }
            refreshHistory(selection: .snapshot(updated.capturedAt))
        }

        guard let window else {
            if alert.runModal() == .alertFirstButtonReturn {
                applyTitleChange()
            }
            return
        }

        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            Task { @MainActor in
                applyTitleChange()
            }
        }
    }

    private func snapshotForHistoryAction(_ sender: NSButton) -> LayoutSnapshot? {
        let row = sender.tag
        guard row >= 0, row < history.count else {
            return nil
        }

        historyTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        selectSnapshot(history[row])
        return history[row]
    }

    private func confirmAction(
        title: String,
        message: String,
        confirmButton: String,
        style: NSAlert.Style,
        onConfirm: @escaping @MainActor () -> Void
    ) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirmButton)
        alert.addButton(withTitle: "取消")

        guard let window else {
            if alert.runModal() == .alertFirstButtonReturn {
                onConfirm()
            }
            return
        }

        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            Task { @MainActor in
                onConfirm()
            }
        }
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

private final class HistoryTableCell: NSTableCellView {
    let editButton = IconButton(
        symbolName: "pencil",
        tooltip: "修改保存历史标题",
        tint: .controlAccentColor
    )
    let restoreButton = IconButton(
        symbolName: "arrow.uturn.backward",
        tooltip: "恢复这条保存历史",
        tint: .controlAccentColor
    )
    let deleteButton = IconButton(
        symbolName: "trash",
        tooltip: "删除这条保存历史",
        tint: .systemRed
    )

    init(title: String, countSummary: String?, displaySummary: String, timestamp: String) {
        super.init(frame: .zero)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .bold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1

        let countLabel = NSTextField(labelWithString: countSummary ?? "")
        countLabel.font = .systemFont(ofSize: 11, weight: .medium)
        countLabel.textColor = .secondaryLabelColor
        countLabel.lineBreakMode = .byTruncatingTail
        countLabel.maximumNumberOfLines = 1
        countLabel.isHidden = countSummary == nil

        let displaysLabel = NSTextField(labelWithString: displaySummary)
        displaysLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        displaysLabel.textColor = .secondaryLabelColor
        displaysLabel.lineBreakMode = .byTruncatingTail
        displaysLabel.maximumNumberOfLines = max(1, displaySummary.split(separator: "\n").count)

        let timestampLabel = NSTextField(labelWithString: timestamp)
        timestampLabel.font = .systemFont(ofSize: 10, weight: .regular)
        timestampLabel.textColor = .tertiaryLabelColor
        timestampLabel.lineBreakMode = .byTruncatingTail
        timestampLabel.maximumNumberOfLines = 1

        let textStack = NSStackView(views: [titleLabel, countLabel, displaysLabel, timestampLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let buttonStack = NSStackView(views: [editButton, restoreButton, deleteButton])
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.spacing = 4
        buttonStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(textStack)
        addSubview(buttonStack)
        NSLayoutConstraint.activate([
            textStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: buttonStack.leadingAnchor, constant: -8),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            buttonStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            buttonStack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }
}

private final class DisplayArrangementView: NSView {
    var topology: DisplayTopology? {
        didSet {
            needsDisplay = true
        }
    }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let backgroundPath = NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8)
        NSColor.controlBackgroundColor.withAlphaComponent(0.42).setFill()
        backgroundPath.fill()
        NSColor.separatorColor.withAlphaComponent(0.5).setStroke()
        backgroundPath.lineWidth = 1
        backgroundPath.stroke()

        guard let displays = topology?.displays, !displays.isEmpty else {
            drawEmptyState()
            return
        }

        let drawingRect = bounds.insetBy(dx: 16, dy: 14)
        guard drawingRect.width > 1, drawingRect.height > 1 else { return }

        let minX = displays.map(\.bounds.x).min() ?? 0
        let maxX = displays.map(\.bounds.maxX).max() ?? 0
        let minY = displays.map(\.bounds.y).min() ?? 0
        let maxY = displays.map(\.bounds.maxY).max() ?? 0
        let topologyWidth = max(maxX - minX, 1)
        let topologyHeight = max(maxY - minY, 1)
        let scale = min(
            Double(drawingRect.width) / topologyWidth,
            Double(drawingRect.height) / topologyHeight
        )
        let contentWidth = CGFloat(topologyWidth * scale)
        let contentHeight = CGFloat(topologyHeight * scale)
        let origin = NSPoint(
            x: drawingRect.midX - contentWidth / 2,
            y: drawingRect.midY - contentHeight / 2
        )

        for (index, display) in displays.enumerated() {
            let rect = display.bounds
            let displayRect = NSRect(
                x: origin.x + CGFloat((rect.x - minX) * scale),
                y: origin.y + CGFloat((rect.y - minY) * scale),
                width: max(CGFloat(rect.width * scale), 22),
                height: max(CGFloat(rect.height * scale), 16)
            )
            drawDisplay(display, index: index + 1, in: displayRect)
        }
    }

    private func drawDisplay(_ display: DisplayDescriptor, index: Int, in rect: NSRect) {
        let fill = display.isMain
            ? NSColor.controlAccentColor.withAlphaComponent(0.22)
            : NSColor.secondaryLabelColor.withAlphaComponent(0.12)
        let stroke = display.isMain ? NSColor.controlAccentColor : NSColor.separatorColor
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)

        fill.setFill()
        path.fill()
        stroke.setStroke()
        path.lineWidth = display.isMain ? 2 : 1
        path.stroke()

        let title = display.isMain ? "\(index) 主屏" : "\(index)"
        let subtitle = "\(Int(display.bounds.width))x\(Int(display.bounds.height))"
        let label = rect.width >= 92 && rect.height >= 44 ? "\(title)\n\(subtitle)" : title
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let fontSize: CGFloat = rect.height >= 44 ? 11 : 10
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: display.isMain ? .semibold : .medium),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        let textRect = rect.insetBy(dx: 4, dy: max(2, (rect.height - (rect.height >= 44 ? 30 : 12)) / 2))
        (label as NSString).draw(in: textRect, withAttributes: attributes)
    }

    private func drawEmptyState() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph
        ]
        ("未选择保存历史" as NSString).draw(
            in: bounds.insetBy(dx: 12, dy: bounds.height / 2 - 8),
            withAttributes: attributes
        )
    }
}

private final class IconButton: NSButton {
    private let tint: NSColor
    private let iconSize: CGFloat
    private var tracking: NSTrackingArea?
    private var hovering = false {
        didSet { needsDisplay = true }
    }

    override var wantsUpdateLayer: Bool { true }

    init(symbolName: String, tooltip: String, tint: NSColor, size: CGFloat = 26) {
        self.tint = tint
        self.iconSize = size
        super.init(frame: .zero)

        toolTip = tooltip
        contentTintColor = tint
        wantsLayer = true
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .imageOnly
        focusRingType = .none
        translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size),
            heightAnchor.constraint(equalToConstant: size)
        ])
        updateSymbol(symbolName, tooltip: tooltip)
    }

    required init?(coder: NSCoder) { nil }

    func updateSymbol(_ symbolName: String, tooltip: String? = nil) {
        let config = NSImage.SymbolConfiguration(pointSize: iconSize <= 26 ? 12 : 13, weight: .semibold)
        image = NSImage(systemSymbolName: symbolName, accessibilityDescription: tooltip)?
            .withSymbolConfiguration(config)
        if let tooltip {
            toolTip = tooltip
        }
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
        layer?.cornerRadius = 7
        layer?.masksToBounds = false
        layer?.backgroundColor = tint.withAlphaComponent(hovering ? 0.16 : 0.08).cgColor
    }
}

private final class DetailPanelView: NSView {
    override var wantsUpdateLayer: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    override func updateLayer() {
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.72).cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
    }
}

private final class ClippingView: NSView {
    override var wantsDefaultClipping: Bool { true }
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
private final class StatusPill: NSControl {
    override var wantsUpdateLayer: Bool { true }

    private let dot = NSView()
    private let label = NSTextField(labelWithString: "")
    private var tint: NSColor = .systemGreen
    private var tracking: NSTrackingArea?
    private var hovering = false {
        didSet { needsDisplay = true }
    }

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
        let alpha = isEnabled && hovering ? 0.22 : 0.14
        layer?.backgroundColor = tint.withAlphaComponent(alpha).cgColor
        dot.layer?.cornerRadius = 3.5
        dot.layer?.backgroundColor = tint.cgColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        hovering = true
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
    }

    override func mouseUp(with event: NSEvent) {
        guard isEnabled,
              bounds.contains(convert(event.locationInWindow, from: nil)),
              let action else {
            return
        }
        NSApp.sendAction(action, to: target, from: self)
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
