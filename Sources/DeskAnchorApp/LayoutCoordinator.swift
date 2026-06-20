import AppKit
import DeskAnchorCore

@MainActor
final class LayoutCoordinator {
    var statusDidChange: ((AppStatus) -> Void)?

    private let store: LayoutStore
    private let preferencesStore: PreferencesStore
    private let displayProvider: DisplayTopologyProvider
    private let windowManager: AccessibilityWindowManager
    private let permissionManager: AccessibilityPermissionManager
    private var permissionRefreshTimer: Timer?
    private var lastPermissionGranted: Bool?
    private var lastTopologyKey: String?
    private var preferences: Preferences

    init(
        store: LayoutStore,
        preferencesStore: PreferencesStore,
        displayProvider: DisplayTopologyProvider,
        windowManager: AccessibilityWindowManager,
        permissionManager: AccessibilityPermissionManager
    ) {
        self.store = store
        self.preferencesStore = preferencesStore
        self.displayProvider = displayProvider
        self.windowManager = windowManager
        self.permissionManager = permissionManager
        self.preferences = preferencesStore.load()
    }

    func start() {
        normalizeStoredLayouts()
        publish(status)
        lastTopologyKey = displayProvider.currentTopology().topologyKey

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        permissionRefreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPermissionStatusIfNeeded()
            }
        }
    }

    var status: AppStatus {
        let topology = displayProvider.currentTopology()
        return AppStatus(
            permissionGranted: permissionManager.isTrusted,
            displaySummary: topology.humanSummary,
            displayCount: topology.displays.count,
            autoRestoreEnabled: preferences.autoRestoreEnabled,
            message: nil
        )
    }

    func layoutHistory() -> [LayoutSnapshot] {
        do {
            return try store.snapshots()
        } catch {
            publish(status.withMessage("读取保存历史失败：\(error.localizedDescription)"))
            return []
        }
    }

    @discardableResult
    func saveCurrentLayout(reason: String = "手动保存") -> LayoutSnapshot? {
        guard permissionManager.isTrusted else {
            publish(status.withMessage("需要辅助功能权限才能保存窗口位置"))
            return nil
        }

        let topology = displayProvider.currentTopology()
        let windows = windowManager.captureWindows()
        let snapshot = LayoutSnapshot(topology: topology, windows: windows)

        do {
            try store.upsert(snapshot)
            publish(status.withMessage("\(reason)：已保存 \(windows.count) 个窗口"))
            return snapshot
        } catch {
            publish(status.withMessage("保存失败：\(error.localizedDescription)"))
            return nil
        }
    }

    func restoreCurrentLayout(reason: String = "手动恢复") {
        guard permissionManager.isTrusted else {
            publish(status.withMessage("需要辅助功能权限才能恢复窗口位置"))
            return
        }

        let topology = displayProvider.currentTopology()

        do {
            guard let snapshot = try store.snapshot(for: topology) else {
                publish(status.withMessage("当前显示器组合还没有保存布局"))
                return
            }

            let result = windowManager.restore(snapshot: snapshot)
            publish(status.withMessage("\(reason)：\(result.summary)"))
        } catch {
            publish(status.withMessage("恢复失败：\(error.localizedDescription)"))
        }
    }

    func restore(snapshot: LayoutSnapshot, reason: String = "保存历史恢复") {
        guard permissionManager.isTrusted else {
            publish(status.withMessage("需要辅助功能权限才能恢复窗口位置"))
            return
        }

        let result = windowManager.restore(snapshot: snapshot)
        publish(status.withMessage("\(reason)：\(result.summary)"))
    }

    func renameSnapshot(_ snapshot: LayoutSnapshot, to title: String?) -> LayoutSnapshot? {
        do {
            guard let updated = try store.rename(snapshot, to: title) else {
                publish(status.withMessage("这条保存历史已经不存在"))
                return nil
            }
            publish(status.withMessage(updated.customTitle == nil ? "已恢复默认标题" : "已修改保存历史标题"))
            return updated
        } catch {
            publish(status.withMessage("修改保存历史标题失败：\(error.localizedDescription)"))
            return nil
        }
    }

    @discardableResult
    func deleteSnapshot(_ snapshot: LayoutSnapshot) -> Bool {
        do {
            guard try store.delete(snapshot) else {
                publish(status.withMessage("这条保存历史已经不存在"))
                return false
            }
            publish(status.withMessage("已删除一条保存历史"))
            return true
        } catch {
            publish(status.withMessage("删除保存历史失败：\(error.localizedDescription)"))
            return false
        }
    }

    func toggleAutoRestore() {
        preferences.autoRestoreEnabled.toggle()
        preferencesStore.save(preferences)
        publish(status.withMessage(preferences.autoRestoreEnabled ? "已开启自动恢复" : "已暂停自动恢复"))
    }

    func openPermissionSettings() {
        permissionManager.requestTrustPrompt()
        permissionManager.openSystemSettings()
    }

    func openDisplaySettings() {
        SystemSettings.openDisplays()
    }

    private func publish(_ newStatus: AppStatus) {
        lastPermissionGranted = newStatus.permissionGranted
        statusDidChange?(newStatus)
    }

    private func refreshPermissionStatusIfNeeded() {
        let currentStatus = status
        guard currentStatus.permissionGranted != lastPermissionGranted else {
            return
        }
        publish(currentStatus)
    }

    private func normalizeStoredLayouts() {
        do {
            try store.normalizeStorage()
        } catch {
            publish(status.withMessage("迁移保存历史失败：\(error.localizedDescription)"))
        }
    }

    @objc private func screenParametersChanged() {
        let currentKey = displayProvider.currentTopology().topologyKey
        guard currentKey != lastTopologyKey else {
            return
        }
        lastTopologyKey = currentKey

        publish(status.withMessage("显示器已变化，等待稳定"))
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.preferences.autoRestoreEnabled {
                    self.restoreCurrentLayout(reason: "显示器重连自动恢复")
                }
            }
        }
    }

    @objc private func workspaceDidWake() {
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.preferences.autoRestoreEnabled else { return }
                self.restoreCurrentLayout(reason: "唤醒后自动恢复")
            }
        }
    }
}

struct AppStatus: Equatable {
    var permissionGranted: Bool
    var displaySummary: String
    var displayCount: Int
    var autoRestoreEnabled: Bool
    var message: String?

    func withMessage(_ message: String) -> AppStatus {
        var copy = self
        copy.message = message
        return copy
    }
}
