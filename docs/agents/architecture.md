# 架构设计

## 技术路线

- Swift Package Manager
- Swift + AppKit 菜单栏应用
- CoreGraphics / NSScreen 获取显示器拓扑
- Accessibility API 枚举和移动窗口
- JSON 本地持久化
- Swift Testing 覆盖纯逻辑

## 模块

```text
Sources/DeskAnchorCore
├── DisplayLayout.swift
├── DisplayLocator.swift
├── Geometry.swift
├── LayoutStore.swift
├── Preferences.swift
├── RestorePlanner.swift
└── WindowLayout.swift

Sources/DeskAnchorApp
├── AccessibilityWindowManager.swift
├── AppDelegate.swift
├── DisplayTopologyProvider.swift
├── LayoutCoordinator.swift
├── PermissionManager.swift
├── StatusBarController.swift
└── main.swift
```

## 数据模型

`DisplayTopology.topologyKey` 包含显示器硬件签名和相对坐标。`WindowSignature` 使用 bundle id、应用名、窗口标题指纹、AX role/subrole 和 occurrence 形成匹配键。

窗口没有长期稳定 ID，所以恢复策略必须保守。匹配不到的窗口跳过，不移动额外窗口。

## 触发策略

- 默认 20 秒低频自动保存。
- 显示器参数变化后等待 2 秒，再尝试自动恢复。
- 唤醒后等待 2 秒，再尝试自动恢复。
- 退出前保存一次。

## 发布方案

当前仓库提供 SwiftPM 构建与本地 `.app` 打包脚本。正式发布建议：

- 非沙盒 Developer ID Application 签名。
- Hardened Runtime。
- Notarization。
- DMG 分发。

Mac App Store 沙盒路线与“管理其他 App 窗口”的目标冲突，不建议作为首版发布路径。
