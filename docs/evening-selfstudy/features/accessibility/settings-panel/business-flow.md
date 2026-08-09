# F-07 辅助设置面板 — 业务流程

> 状态：final / accepted

## 主流程

辅助设置面板有两条触发路径，共用同一面板视图：

**路径 A：序章段落 7 首次引导**

```
SceneDirector 推进至 PrologueBeatID.accessibility
  → PrologueAccessibilityHintView 从右下角淡入（0.3s）
  → 玩家选择：
      ├─ 打开设置 → GameManager.addPauseReason(.pauseMenu)
      │              → AccessibilitySettingsPanelView 呈现
      │              → 玩家修改任意控件 → 立即生效
      │              → 玩家关闭面板 → GameManager.removePauseReason(.pauseMenu)
      │              → PrologueAccessibilityHintView 消失
      │              → PrologueState.accessibilityTutorialAcknowledged = true（幂等）
      │              → Beat 完成，进入 PrologueBeatID.bellBeforeClass
      └─ 按"继续" → PrologueState.accessibilityTutorialAcknowledged = true（幂等）
                    → Beat 完成，进入 PrologueBeatID.bellBeforeClass
```

**路径 B：游戏任意时刻（暂停菜单）**

```
玩家按暂停键
  → GameManager.addPauseReason(.pauseMenu)
  → 暂停菜单呈现（包含设置入口）
  → 玩家点击"辅助设置"
  → AccessibilitySettingsPanelView 呈现
  → 修改控件 → 立即生效
  → 关闭面板 → 返回暂停菜单
  → 玩家按继续 → GameManager.removePauseReason(.pauseMenu)
  → Beat 剩余时间从冻结点继续，不重置
```

**控件修改内部流程（共用）：**

```
玩家调整任意控件值
  → ContentView 调用 GameManager.updateAccessibility(_:)
  → GameManager 更新 accessibility 属性（触发 @Published）
  → 同步分发：
      ├─ SpatialAudioManager 更新三通道音量
      ├─ SceneDirector 读取 reduceMotion（按需，下次动画时生效）
      └─ 方向字幕层读取 directionalCaptionsEnabled（立即显示/隐藏）
  → 自动存档触发（每次偏好修改后写入 NarrativeSave）
```

## 边界与兜底

- **序章段落 7 自动兜底**：玩家 12 秒未操作时，`SceneDirector` 自动完成该 Beat，写入 `accessibilityTutorialAcknowledged = true`，`PrologueAccessibilityHintView` 淡出，不视为"已打开设置"。
- **设置面板打开时应用失焦**：`activePauseReasons` 已包含 `.pauseMenu`，再插入 `.appInactive` 不产生冲突；两个原因都移除后 Beat 才恢复，不会因应用回到前台而误解冻。
- **存档解码失败时的偏好恢复**：`NarrativeSave` 解码失败回退 `lastValid` 时，`AccessibilityPreferences` 随之恢复；若 `lastValid` 也不含该字段（旧版存档），迁移器填入结构体默认值，不阻塞游戏启动。
- **系统 Reduce Motion 在游戏运行中变更**：监听 `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`；若玩家未手动覆盖（`hasUserOverriddenReduceMotion == false`），自动跟随更新；否则只在下次玩家主动修改时才同步系统建议值作为参考。
- **音量同步失败**：若 `SpatialAudioManager` 在音频引擎未初始化时收到音量更新，静默忽略；引擎初始化完成后在 `GameManager.startChapter(_:)` 调用时重新同步当前 `AccessibilityPreferences`。

## 与其他特性的交互点

| 时机 | 本特性调用 / 被调用 |
|---|---|
| SceneDirector 执行 `PrologueBeatID.accessibility` | 本特性的 `PrologueAccessibilityHintView` 被呈现 |
| 暂停菜单打开/关闭 | 复用 F-02 的 `activePauseReasons` 机制，插入/移除 `.pauseMenu` |
| 场景过渡（F-04 叙事相机与场景呈现） | SceneDirector 在 `SceneTransition.fade`/`colorTemperatureFlip`/`mirrorRipple` 执行前读取 `reduceMotion` |
| 第二章微游戏（F-12 三灯微游戏） | 键盘替代输入标志由本特性提供；微游戏查询 `accessibility.keyboardAlternativeInput` 决定是否启用逐段键盘确认 |
| 所有章节音频线索 | 方向字幕开关状态由本特性持有；音频事件系统读取 `directionalCaptionsEnabled` 决定是否显示字幕 |
| 存档系统（F-04） | `AccessibilityPreferences` 嵌入 `NarrativeSave`，随每次步骤完成、章节切换和进入后台触发的自动存档一起写入 |
