# DeskAnchor 分发记录

更新：2026-09-09。范围：Apple 官方咨询、GitHub Releases、Homebrew；不包含官网。

## 渠道状态

| 渠道 | 状态与依赖 |
| --- | --- |
| GitHub Releases | 0.1.2 预发布准备中；通用二进制，ad-hoc 签名，尚未 Developer ID 签名或公证。不能标为正式版。 |
| 自有 Homebrew tap | 准备 `songofhawk/homebrew-tap` 的 `deskanchor@beta`，固定版本与 SHA-256。安装包的 Gatekeeper 限制不会因使用 Homebrew 消失。 |
| Homebrew 官方 cask | 暂不提交。当前包未通过 Gatekeeper；正式签名、公证及公共发行后再按收录规则评估。 |
| Mac App Store | 尚无准入批准。官方咨询被 Apple Developer Agreement 页面阻挡，待账户所有者接受协议并确认账号后继续提交。 |
| Setapp | 暂不申请。官方要求成熟、稳定产品，技术审核和 SDK 集成；当前是早期未公证预发布，先完成正式发行及恢复稳定性验证。 |

## 打包

```bash
swift build
scripts/package-app.sh
```

默认输出 `dist/DeskAnchor-0.1.2.dmg`、同名 `.sha256` 文件和 `.build/DeskAnchor.app`。打包脚本分别编译 arm64、x86_64，再用 lipo 合并为 universal；最低 macOS 13。无签名身份时生成明确标注的 ad-hoc 开发包。保持现有 bundle ID `dev.local.deskanchor`，避免额外改变用户已有辅助功能授权身份。

不覆盖仓库中历史包的构建命令：

```bash
DESKANCHOR_DIST_DIR="$PWD/.build/distribution" scripts/package-app.sh
```

正式发行前，完成 Apple Developer Program 会员开通、安装 Developer ID Application 证书及私钥，并使用 `xcrun notarytool store-credentials` 在本机钥匙串配置公证 profile。不要把密码、私钥或凭据提交到 Git。

```bash
DESKANCHOR_VERSION=0.1.3 \
DESKANCHOR_SIGN_IDENTITY='Developer ID Application: <证书中的准确名称>' \
DESKANCHOR_NOTARY_PROFILE='<本机钥匙串 profile 名称>' \
DESKANCHOR_DIST_DIR="$PWD/.build/distribution" \
scripts/package-app.sh
```

此路径会启用 Hardened Runtime 与时间戳，公证并 staple App，再构建、签名、公证并 staple DMG；任何步骤失败立即停止。App 和 DMG 的 Gatekeeper 检查通过后才发布正式版。该在线路径当前因无证书尚未执行验收，不能将脚本存在视作公证成功。已发布版本和 SHA-256 必须保持不变，正式包使用新版本号。

## 发布与验收

1. 确认待发布提交和工作区，运行 `swift build`、`scripts/package-app.sh`。
2. 检查 Info.plist 的版本、最低系统版本，`lipo -archs` 同时包含 arm64/x86_64，`codesign --verify --deep --strict`、`hdiutil verify` 成功。
3. 使用 `gh release create` 创建草稿，指定准确提交、版本标签、DMG 与 SHA-256，使用 `--notes-file` 提供说明。未公证包必须带 `--prerelease`，说明用途和 Gatekeeper 限制。
4. 核对附件后发布；重新下载公开资产并比对 SHA-256，确认下载地址真实可用。
5. 自有 tap 的 `Casks/deskanchor@beta.rb` 固定 URL、版本和实际 DMG SHA-256，声明 macOS 13、辅助功能需求和未公证限制。不得移除 quarantine、禁用 Gatekeeper，或自动删除用户布局数据。
6. `brew fetch --cask` 核验下载；安装测试使用隔离目录并保留系统隔离属性。单纯安装或签名校验通过不等于 Gatekeeper、首次启动或窗口恢复验收。
7. 正式签名、公证包可增设 `deskanchor` 稳定 cask，再独立考虑 Homebrew 官方收录。

## Apple 咨询证据

本机控制变量实验使用相同生产窗口管理代码、相同探针可执行文件。两者辅助功能授权均为 true。非沙盒成功读取、移动、缩放一个同步实现 `setAccessibilityFrame` 的专用目标；沙盒 AX 读取为 -25204，系统记录 `deny(1) mach-lookup com.apple.axserver (per-pid)`。CGWindow 的备用读取不能替代用于恢复的 AX handle。

该实验只证明这一明确支持同步 AX 修改的目标在当前实现下受沙盒限制，不证明所有普通窗口恢复通过，也不是 App Review 决定。普通 AppKit 目标曾出现动画/恢复时序问题，需另行验证。

原始材料已复制到本工作区忽略目录 `.build/apple-inquiry-evidence/`；对外咨询只提供最小技术摘要，不提交账户信息、完整系统日志或本机个人路径。咨询正文在该目录 `inquiry-en.txt`；真正提交后必须记录工单或确认页面，不能把草稿视为已提交。

## 官方依据

- [Apple App Review Guidelines 2.4.5](https://developer.apple.com/app-store/review/guidelines/#hardware-compatibility)：Mac App Store 沙盒和自包含要求。
- [Apple Code-level Support](https://developer.apple.com/support/technical/)：支持申请、英文技术描述与最小复现要求。
- [Apple 软件公证文档](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)：商店外公证流程。
- [Homebrew Acceptable Casks](https://docs.brew.sh/Acceptable-Casks)：架构与系统声明、Gatekeeper、可核验上游下载等要求。
- [Homebrew 自有 tap](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap)：独立维护仓库与安装方式。
- [Setapp 开发者入口](https://setapp.com/developers)：产品筛选、技术审核与 SDK 集成。
