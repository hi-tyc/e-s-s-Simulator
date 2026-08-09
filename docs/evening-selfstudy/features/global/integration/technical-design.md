# F-20 全局集成：转场/音频/无障碍 — 技术设计

> 状态：final / accepted

## 实现方案

### 六章转场三阶段

每次章节切换通过 `GameManager.transitionChapter(from:result:)` 触发，内部分三阶段执行：

1. **prepare**：预载目标章节的 `ScenePresentationState`，激活相邻场景根节点，但不开放热点，`SceneTransition` 枚举值写入 `scenePresentation.transition`。
2. **commit**：以原子事务写入新 `checkpointID`、`chapter`、`cameraMode`、`activeSceneRootID` 并清空 `transition`；自动存档只落在此时间点（commit 前的稳定点或 commit 完成后），绝不落在过渡中间。
3. **cleanup**：移除旧章节点和已完成的 Beat，取消旧章 Task/Timer。

`ClassroomCoordinator.update(game:)` 在每帧检查 `scenePresentation.transition` 是否非 nil，若有则驱动对应的 SceneKit 动画；动画完成回调触发 `cleanup`。

Reduce Motion 响应：`ClassroomCoordinator` 在动画开始前检查 `AccessibilitySettings.reduceMotion`；若为 true，将 `colorTemperatureFlip` 和 `mirrorRipple` 的 SCNAction 替换为 `SCNAction.fadeIn(duration: 0.3)`，`fade` 保持原时长。

### 音频集成

`SpatialAudioManager` 现有架构为程序化优先 + 真实素材可选覆盖，本特性在此基础上：

- 补全缺失的 `AudioCueKind` case（`.bell`、`.noteDrop`、`.crying`、`.chair`）及对应程序化合成实现
- 实现跨场景音频混音切换：`SpatialAudioManager.transitionScene(to:duration:)` 按淡出/淡入序列切换环境音轨，镜像空间进入时叠入专用低频共鸣轨，退出时反向淡出
- 方向字幕开关通过 `AccessibilitySettings.directionalSubtitles` 控制 `SpatialAudioManager` 是否发布字幕事件，全局生效

### 无障碍集成验证

F-07 已实现辅助功能设置面板，本特性做跨章一致性验证和缺口补全：

- 在六章所有 SwiftUI 热点和按钮上补全 `.accessibilityLabel`、`.accessibilityHint`
- VoiceOver 焦点策略：目标切换时用 `AccessibilityFocusState` 将焦点移到新目标的 `MainQuestHUD` 元素
- 键盘导航：确认所有对话选项、资源卡复制按钮、三灯微游戏按钮都在 `focusable()` 链上

### SupportResourceCatalog 审核门禁

自研非商业版本（选 C）：在 `SupportResourceCatalog` 的 `validate()` 方法中，使用 `#if DEBUG` 包裹超期检查，超过 6 个月输出 `#warning`，不影响 Release 打包。

## 关键类型与接口

`SceneTransition: Codable, Equatable` — fade / colorTemperatureFlip / mirrorRipple，已在 detail.md 中定义，本特性确保三种分支在六章中全部覆盖实现

`GameManager.transitionChapter(from: ChapterID, result: QuestStepResult)` — 唯一合法的章节切换入口，内部执行三阶段

`ClassroomCoordinator.beginTransition(_ transition: SceneTransition, reduceMotion: Bool)` — 新增，驱动具体动画

`SpatialAudioManager.transitionScene(to sceneID: String, duration: TimeInterval)` — 新增，跨场景环境音切换

`SpatialAudioManager.setDirectionalSubtitles(_ enabled: Bool)` — 新增，全局字幕开关

`SupportResourceCatalog.validate()` — 在 `#if DEBUG` 下发出 `#warning` 并返回校验结果

`AccessibilitySettings.reduceMotion: Bool` — 复用 F-07 存储，本特性仅读取

## iPad 适配注意事项

本特性无特定 iPad 约束，遵循全局 PlatformViewRepresentable 规范即可。

## 与现有代码的关系

**复用：**
- `SpatialAudioManager.swift`：现有音频引擎，扩展 `transitionScene` 和字幕开关接口
- `ClassroomCoordinator`：现有 SceneKit 单向映射，扩展 `beginTransition` 和 Reduce Motion 响应
- `GameManager`：现有 `transitionChapter` 框架，实现三阶段逻辑
- `liquidGlassPanel` 等 UI 辅助：不变

**修改：**
- `GameModels.swift`（`AudioCueKind`）：新增 `.bell`、`.noteDrop`、`.crying`、`.chair` case
- `GameManager.swift`：在 `transitionChapter` 内实现 prepare/commit/cleanup 三阶段，补充 Beat 取消逻辑
- `SpatialAudioManager.swift`：新增跨场景切换和程序化合成兜底

**新增：**
- `SupportResourceCatalog.swift`（若 F-19 未完成）：资源配置读取 + 审核日期检查
- 无障碍标签补全（散落在各章相关 SwiftUI 文件）

## 风险与注意事项

- 转场 commit 原子性：若 commit 写入一半时应用崩溃，恢复逻辑必须依赖 `lastValid` 槽而非当前槽，需要在所有转场路径上验证
- 音频叠入叠出时机：镜像空间是走廊场景的子节点，进入/退出不是章节切换，需要单独在 `scenePresentation.activeSceneRootID` 变化时触发音频切换，不能只依赖 `transitionChapter`
- Reduce Motion 检查点：动画时长改变不影响 Beat 时间，需确认 SceneDirector 的 `triggerDelay` 不依赖动画回调结束
- VoiceOver 焦点在模态 overlay（微游戏、纸条特写）关闭后的回退目标，需要在 overlay 实现中明确指定
- 全状态组合测试工作量：设计文档列出 16 个必测场景，其中多个需要跨章重建状态，建议使用测试辅助工具直接注入 `NarrativeSave` 而非通过完整通关路径触发
