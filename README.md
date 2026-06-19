# DeskAnchor

DeskAnchor 是一个轻量 macOS 菜单栏常驻应用，用于把常用窗口锚定到不同显示器组合下的位置，并在切换办公桌、家庭工位或便携屏环境时尽可能自动恢复。

## MVP 功能

- 识别当前连接的所有显示器，并保存显示器相对排列。
- 通过辅助功能 API 枚举标准 macOS 应用窗口。
- 自动/手动保存当前窗口位置和尺寸。
- 在已知显示器组合重现时自动恢复窗口位置。
- 菜单栏常驻，不显示 Dock 图标。
- 本地 JSON 持久化，不上传窗口信息。

## 技术边界

macOS 没有公开 API 能保证恢复所有窗口。全屏窗口、跨 Space 窗口、系统保护窗口、部分 Electron/Java/游戏窗口可能无法读取或移动。产品承诺应表述为“尽可能恢复标准 macOS 应用窗口的位置与尺寸”。

## 构建与运行

```bash
swift build
.build/debug/DeskAnchor
```

首次保存或恢复窗口位置前，需要在系统设置中授予辅助功能权限。

## 测试

```bash
swift test
```

## 打包安装包

```bash
scripts/package-app.sh
open .build/package/DeskAnchor-0.1.0.pkg
```

脚本会生成 `.build/DeskAnchor.app` 和 `.build/package/DeskAnchor-0.1.0.pkg`。安装包会把应用安装到 `/Applications/DeskAnchor.app`。

当前脚本使用本地 ad-hoc 签名，适合开发和内部验证。正式发布建议使用 Developer ID 签名、公证后再分发。
