# F-07 辅助设置面板 — 数据模型

> 状态：final / accepted

## 新增类型

### AccessibilityPreferences

```swift
struct AccessibilityPreferences: Codable, Equatable {
    var directionalCaptionsEnabled: Bool = true   // 方向字幕开关，默认开启
    var dialogueVolume: Double = 0.7              // 对白音量 0.0-1.0
    var ambientVolume: Double = 0.7               // 环境音量 0.0-1.0
    var cueVolume: Double = 0.7                   // 提示音量 0.0-1.0
    var reduceMotion: Bool                        // 初始值跟随系统，玩家可覆盖
    var keyboardAlternativeInput: Bool = true     // 键盘替代鼠标拖动输入，默认开启
}
```

要求：`Codable`、`Equatable`。不需要 `Hashable`（不用于集合键）。

`reduceMotion` 的初始化不在声明处写默认值，由 `GameManager.applySystemReduceMotionIfNeeded()` 在初始化时从系统读取并赋值。

## 存档策略

| 字段 | 进入 NarrativeSave | 说明 |
|---|---|---|
| `AccessibilityPreferences`（整体） | 是，作为 `NarrativeSave.accessibility` | 跨会话持久化，玩家期望偏好在重启后保留 |
| `PrologueState.accessibilityTutorialAcknowledged` | 是，作为 `PrologueState` 的一部分 | 决定是否再次展示首次引导 |

运行时状态（不存档）：
- 设置面板当前是否打开（由 `activePauseReasons.contains(.pauseMenu)` 表达，已在 `NarrativeSave` 中）
- 系统检测到的原始 `isReduceMotionEnabled` 值（运行时读取，不存档）

存档 key：`LateStudySimulator.NarrativeSave.v1`（已有 key，`AccessibilityPreferences` 作为 `NarrativeSave` 的新字段随同写入）。

`NarrativeSave` 引入 `AccessibilityPreferences` 字段时需将 `schemaVersion` 递增，并在迁移器中对旧版本用结构体默认值填充。

## 数据一致性约束

- `dialogueVolume`、`ambientVolume`、`cueVolume` 值域为 `[0.0, 1.0]`；写入前通过 `clamp(0, 1)` 校验，解码后同样校验，超出范围静默修正为边界值。
- `AccessibilityPreferences` 的修改只通过 `GameManager.updateAccessibility(_:)` 提交，不允许视图直接对 `GameManager.accessibility` 赋值；此方法同时触发音频引擎同步和动画配置更新。
- `reduceMotion` 初始化后，系统设置变更（`NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`）只更新运行时的"系统建议值"参考，不自动覆盖玩家已手动修改的偏好；仅在玩家从未手动设置过时跟随系统变化。此区分通过 `hasUserOverriddenReduceMotion: Bool`（运行时属性，不存档）实现。
- `PrologueState.accessibilityTutorialAcknowledged` 一旦写为 `true` 后不可回写为 `false`（幂等写入）；后续游玩中修改辅助设置不会重置该标记。
