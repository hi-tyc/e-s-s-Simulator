# F-07 辅助设置面板 — 技术设计

> 状态：final / accepted

## 实现方案

辅助设置面板由两个入口共用同一 SwiftUI 视图：序章段落 7 的首次引导入口（右下角浮现的非遮挡卡片）和暂停菜单中的常驻设置入口。

偏好数据以 `AccessibilityPreferences` 结构体存储在 `GameManager` 中，通过 `@Published` 向视图层暴露。视图层只读取和调用 `GameManager` 的方法修改偏好，不直接写入存档。`AccessibilityPreferences` 随 `NarrativeSave` 一起序列化，保证跨会话持久化。

减少动态效果的初始值通过 `UIAccessibility.isReduceMotionEnabled`（macOS 对应 `NSWorkspace.accessibilityDisplayShouldReduceMotion`）读取系统设置，玩家可覆盖。`SceneDirector` 在执行过渡和 Beat 动画前查询 `GameManager.accessibility.reduceMotion`，决定使用淡入淡出还是完整动画。

设置面板打开时调用 `GameManager.addPauseReason(.pauseMenu)`，关闭时调用 `removePauseReason(.pauseMenu)`，确保 Beat 计时在设置期间冻结，关闭后从剩余时间恢复。

音量控制委托给 `SpatialAudioManager`，面板只持有三个 `Double` 绑定（`dialogueVolume`、`ambientVolume`、`cueVolume`），通过 `GameManager` 的方法同步到音频引擎。

## 关键类型与接口

```
struct AccessibilityPreferences: Codable, Equatable
  var directionalCaptionsEnabled: Bool
  var dialogueVolume: Double      // 0.0-1.0
  var ambientVolume: Double       // 0.0-1.0
  var cueVolume: Double           // 0.0-1.0
  var reduceMotion: Bool
  var keyboardAlternativeInput: Bool
```

```
// GameManager 新增属性与方法
@Published var accessibility: AccessibilityPreferences
func updateAccessibility(_ preferences: AccessibilityPreferences)
func applySystemReduceMotionIfNeeded()   // 初始化时读取系统设置
```

```
struct AccessibilitySettingsPanelView: View
  // 四项控件 + 关闭按钮，使用 liquidGlassPanel
```

```
struct PrologueAccessibilityHintView: View
  // 序章段落 7 的右下角非遮挡提示，点击后弹出 AccessibilitySettingsPanelView
```

```
// SceneDirector 新增读取点
func animationDuration(normal: TimeInterval, fallback: TimeInterval) -> TimeInterval
  // reduceMotion 开启时返回 fallback（0.2-0.4s），否则返回 normal
```

## iPad 适配注意事项

本特性无特定 iPad 约束，遵循全局 PlatformViewRepresentable 规范即可。

## 与现有代码的关系

**复用：**
- `liquidGlassPanel(cornerRadius:tint:)` 和 `ActionButtonStyle`：面板 UI 直接复用，不另建背景
- `SpatialAudioManager`：音量变更通过现有方法同步，不绕过音频引擎
- `GameManager` 的 `activePauseReasons` 机制：设置面板打开/关闭复用现有暂停集合，不新增 Bool 暂停接口

**新增：**
- `AccessibilityPreferences` 结构体（新文件 `AccessibilityPreferences.swift` 或并入 `GameModels.swift`）
- `AccessibilitySettingsPanelView`（`ContentView.swift` 或独立文件）
- `PrologueAccessibilityHintView`（序章专用，轻量卡片）
- `GameManager.accessibility` 存储属性和 `updateAccessibility(_:)` 方法

**修改：**
- `NarrativeSave`：新增 `accessibility: AccessibilityPreferences` 字段
- `PrologueState`：`accessibilityTutorialAcknowledged` 已声明，确认写入逻辑补全
- `SceneDirector`（或过渡执行点）：在 `fade`/`colorTemperatureFlip`/`mirrorRipple` 动画处读取 `reduceMotion`
- `ContentView.swift` 暂停菜单区域：新增设置面板入口按钮

## 风险与注意事项

- macOS 对应的 Reduce Motion API 为 `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`，需在 `@MainActor` 上下文读取，并监听 `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` 以响应系统设置变更
- 音量三通道绑定需确认 `SpatialAudioManager` 已暴露独立的对白/环境/提示音音量接口；若尚未拆分，需先在音频管理器侧新增三通道控制
- 序章首次引导仅需展示一次，依赖 `PrologueState.accessibilityTutorialAcknowledged` 正确写入；多路径（玩家打开/按继续/自动兜底）都必须写入该字段，避免重复出现
- `AccessibilityPreferences` 加入 `NarrativeSave` 时需更新 `schemaVersion` 并编写迁移器，旧存档读取时使用默认值填充
