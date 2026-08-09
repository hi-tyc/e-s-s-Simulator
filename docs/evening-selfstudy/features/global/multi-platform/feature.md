# F-21 多平台适配基础（iPad 预置）

> 状态：final / accepted
> 实现阶段：Phase 6
> 依赖特性：F-04（叙事相机模式与场景呈现）、F-07（辅助设置面板）、F-19（苏念咨询与支持网络结局）
> 激活条件：macOS 首版交付验收后激活，不得提前分支

## 产品能力描述

在 macOS 首版交付验收后，将《这里有光》的平台绑定层从 AppKit/macOS 专有 API 抽象为跨平台接口，使代码库在 iOS/iPadOS 目标下可编译、可运行，同时不改变 macOS 版本的任何行为或游戏逻辑。这是 iPad 版本的工程预置，不交付任何面向玩家的 iPad 专属功能。

## 功能边界

**包含：**
- `PlatformViewRepresentable` typealias：macOS 展开为 `NSViewRepresentable`，iOS 展开为 `UIViewRepresentable`
- `PlatformShims.swift`：集中管理所有平台 typealias（`PlatformView`、`PlatformGestureRecognizer` 等）
- `ClassroomSceneView` / `ClassroomCoordinator` 中 AppKit 专有调用移入 `#if os(macOS)` 编译块
- iOS 触摸手势路径：`UIPanGestureRecognizer`（视角滑动）和 `UITapGestureRecognizer`（热点点击）作为替代输入
- `ClassroomCoordinator.handleSwipe(direction:)` 统一视角切换入口（macOS 键盘和 iOS 触摸共用）
- `PasteboardBridge`：macOS 调用 `NSPasteboard.general`，iOS 调用 `UIPasteboard.general`，统一第六章复制热线接口
- `Package.swift` platforms 声明扩展至 `.iOS(.v18)`
- `AccessibilityPreferences.keyboardAlternativeInput` 在 iOS 运行时强制为 false，不在设置面板显示

**不包含：**
- iPad 专属游戏设计改动（布局、文案、场景内容）
- App Store / TestFlight 分发配置
- 横竖屏自适应布局（首版 iPad 锁定横屏）
- iPad 分屏 / Stage Manager 支持
- macOS 版本的任何功能变更或退化

## 验收标准

- [ ] `swift build --triple arm64-apple-ios18` 零错误、零警告编译通过
- [ ] macOS 版本功能与引入 F-21 前 bit-for-bit 一致：无行为变更，无视觉回归
- [ ] `PlatformViewRepresentable` 在 macOS 目标下为 `NSViewRepresentable`，在 iOS 下为 `UIViewRepresentable`，两目标编译均无 ambiguous 警告
- [ ] iPad 上触摸左/右滑动切换 `CameraPose`，点击视野内热点触发交互，功能与 macOS 键盘等效
- [ ] `PasteboardBridge.copy(_:)` 在 macOS 写入 `NSPasteboard.general`，在 iOS 写入 `UIPasteboard.general`，两平台分别通过编译验证
- [ ] `GameManager.swift` 和 `GameModels.swift` 中不存在任何 `#if os(macOS)` 或 `#if os(iOS)` 条件编译块

## 设计约束

- 本特性不得修改游戏逻辑、叙事状态或存档结构；所有改动限于平台绑定层（`ClassroomSceneView.swift`、`PlatformShims.swift`）和输入适配层
- 平台条件编译块只允许出现在明确的平台绑定文件中；游戏逻辑文件禁止引入平台分支
- 不引入任何第三方跨平台框架，仅用 Swift 原生条件编译
- macOS 首版未通过验收前本特性处于冻结状态，不得在 macOS 主干上提前添加条件编译
- Liquid Glass `glassEffect` 在 iOS 目标下需 `#available` 保护；若 iOS 最低版本不支持，需提供视觉等价的 fallback，不能崩溃
