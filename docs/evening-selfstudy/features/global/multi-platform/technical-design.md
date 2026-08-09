# F-21 多平台适配基础（iPad 预置） — 技术设计

> 状态：final / accepted

## 实现方案

采用"平台绑定层集中隔离"策略：将所有平台专有调用收拢到一组薄包装类型中，游戏逻辑层完全不感知目标平台。整个施工分五步：

**步骤 1 — Package.swift 扩展平台声明**
在现有 `.macOS(.v26)` 旁增加 `.iOS(.v18)`，使 Swift 工具链将 iOS 视为合法编译目标。

**步骤 2 — `PlatformShims.swift` 新增**
用 `#if os(macOS)` / `#if os(iOS)` 定义全局 typealias（`PlatformViewRepresentable`、`PlatformView`、`PlatformGestureRecognizer`），以及 `PasteboardBridge` 静态工具类型。此文件是平台分支的唯一合法容器。

**步骤 3 — `ClassroomSceneView` 协议遵循迁移**
将 `struct ClassroomSceneView: NSViewRepresentable` 改为 `struct ClassroomSceneView: PlatformViewRepresentable`；`makeNSView` / `updateNSView` 移入 `#if os(macOS)` 块，对应增加 `makeUIView` / `updateUIView` 的 iOS 实现（共用 `ClassroomCoordinator`，SceneKit 本身跨平台）。

**步骤 4 — `StudentInputSCNView` 平台化**
macOS 实现保持不变（`NSEvent` 键盘/鼠标处理）。iOS 在同一文件的 `#if os(iOS)` 块中新建触摸手势注册逻辑，将 pan/tap 回调通过 `onCameraSwipe: (SwipeDirection) -> Void` 和 `onHotspotTap: (CGPoint) -> Void` 两个闭包回传给 `ClassroomCoordinator`。`ClassroomCoordinator` 新增 `handleSwipe(direction:)` 和 `handleHotspotTap(at:)` 统一入口，macOS 的键盘路径也改写为调用这两个方法。

**步骤 5 — AppKit 残余扫描清理**
`ContentView.swift` 中若存在 `AppKit` import 或 `NSFont`/`NSColor` 等专有类型，替换为 SwiftUI 等价（`Font`、`Color`）；`NSPasteboard` 的使用点（第六章复制按钮）改为调用 `PasteboardBridge.copy(_:)`。

## 关键类型与接口

- `typealias PlatformViewRepresentable` — `NSViewRepresentable`（macOS）/ `UIViewRepresentable`（iOS）
- `typealias PlatformView` — `NSView`（macOS）/ `UIView`（iOS）
- `typealias PlatformGestureRecognizer` — `NSGestureRecognizer`（macOS）/ `UIGestureRecognizer`（iOS）
- `enum SwipeDirection: Equatable` — `.left / .right / .up / .down`，触摸滑动方向到 `CameraPose` 的映射键
- `struct PasteboardBridge` — `static func copy(_ string: String)` 平台分发复制操作
- `ClassroomCoordinator.handleSwipe(direction: SwipeDirection)` — 统一视角切换入口
- `ClassroomCoordinator.handleHotspotTap(at point: CGPoint)` — iOS 触摸热点命中检测

## iPad 适配注意事项

本特性无来自需求文档的专项 iPad 标注内容。以下为基于现有架构推导的最小适配要求：

- `PlatformViewRepresentable` 是全局规范，所有后续需要 `NSViewRepresentable` 的特性（包括 F-04 新场景）在 iOS 目标下必须遵循此规范，不得绕过
- `SCNView` 本身跨平台；必须将 `SCNView.allowsCameraControl` 显式设为 false，防止 iOS 系统手势接管视角控制，与游戏代码的相机管理产生冲突
- Liquid Glass `glassEffect` 需确认在目标 iOS 版本是否 available；若不可用，`liquidGlassPanel` 辅助器需提供 `#available` fallback（`.ultraThinMaterial` 降级），不能直接崩溃
- `AccessibilityPreferences.keyboardAlternativeInput` 在 iOS 下无意义（触摸天然可用），运行时强制 false，不在设置面板中显示该控件

## 与现有代码的关系

- `ClassroomSceneView.swift`：核心修改目标，协议遵循替换 + `makeNSView`/`updateNSView` 移入条件编译块，`StudentInputSCNView` iOS 路径添加
- `ContentView.swift`：清理 AppKit 直接引用（若存在），确保 SwiftUI 层在两平台均可编译
- 新增 `PlatformShims.swift`：集中存放全部 typealias 和 `PasteboardBridge`，是平台条件编译的唯一入口
- `Package.swift`：新增 iOS 平台声明
- `GameManager.swift`、`GameModels.swift`、`SpatialAudioManager.swift`：不修改，保持零平台条件编译

## 风险与注意事项

- Liquid Glass `glassEffect` 在 iOS 上的实际可用版本未经验证，需在模拟器上确认后决定 fallback 方案
- `SCNView` iOS 版的系统手势（双指旋转、捏合缩放）若未全部禁用，可能与游戏手势识别器冲突
- macOS 首版验收后代码库已积累 Phase 0-6 的全部改动，施工前需完整 diff 核查所有 AppKit 引用点，遗漏点可能导致 iOS 编译报错
- `SpatialAudioManager` 基于 `AVAudioEngine`，该框架在 iOS 上可用但空间音频行为与 macOS 不同（`AVAudioEnvironmentNode` 的 HRTF 支持差异），首版 iPad 预置不处理此差异，留待后续阶段
