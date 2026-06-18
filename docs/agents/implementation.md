# 程序员实现记录

## 实现原则

- 核心逻辑不依赖 AppKit，保持可测试。
- 与 macOS 私有行为相关的代码集中在 `WinstoreApp`。
- 恢复窗口前先计算目标 frame，并强制约束到当前显示器 bounds 内。
- 任何无法可靠匹配或无法移动的窗口都跳过，不做猜测式破坏。

## 当前实现

- `WinstoreCore` 提供显示器、窗口、存储、恢复规划模型。
- `WinstoreApp` 提供菜单栏、权限、显示器枚举、窗口 AX 读写和协调逻辑。
- JSON 数据写入 `~/Library/Application Support/Winstore/layouts.json`。
- 偏好设置写入 `UserDefaults`。

## 待强化

- `NSScreen.visibleFrame` 应纳入恢复约束，避开 Dock 和菜单栏。
- 增加恢复前 `beforeRestore` 快照。
- 增加同 App 多窗口低置信度保护。
- 增加正式设置窗口和布局管理。
- 增加签名、公证、登录项启动。
