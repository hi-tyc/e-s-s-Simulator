# F-10 林澈 NPC 与纸条事件 — 技术设计

> 状态：final / accepted

## 实现方案

林澈 NPC 的行为状态由 `ClassroomCoordinator` 根据 `GameManager` 发布的 `Ch1State` 和 `quest.currentTurn` 单向映射到 SceneKit 节点，不在 Coordinator 内存储独立的剧情状态。林澈的三个行为阶段（idle 翻书停、第 6 回合抬头、铃后路径离开）分别对应三段 `SCNAction` 序列，由 Coordinator 的 `update(game:)` 检查状态条件后一次性 run。

纸条事件通过 `GameManager` 的 `SceneDirector` 在满足触发条件后发出 `ActiveEventKind.noteDrop`，覆盖层由 `ContentView` 响应并展示纸条特写 SwiftUI overlay。overlay 关闭后通过 `completeStep` 幂等写入结果，确保玩家手动关闭和 fallback 回调不重复提交。

对话选择（步骤 4）使用现有 `ActiveEvent` / `EventChoice` 扩展出的 `ChapterDialogue` 结构，选项与结果映射在 `GameManager` 内，不散落在视图层。

## 关键类型与接口

新增或扩展的类型：

```
ActiveEventKind.noteDrop                     // 新增 case，纸条掉落事件
AudioCueKind.bell                            // 新增 case，铃声
AudioCueKind.chair                           // 新增 case，椅子移动声
```

`ClassroomCoordinator` 内部扩展（不暴露为公共接口）：

```
linCheAnimationPhase: LinCheAnimationPhase   // 跟踪当前动画阶段，避免重复 run
runLinCheIdle()                              // 翻书停止 idle，章节开始时调用
runLinCheGlanceDoor()                        // 第 6 回合抬头看门再低头，一次性
runLinCheExitPath(from:to:)                  // 铃后离开路径动画，约 8 秒
```

新增枚举（仅在 Coordinator 内部使用）：

```
enum LinCheAnimationPhase: Int {
    case idle, glancedDoor, exiting, exited
}
```

纸条特写 overlay（SwiftUI）：

```
struct NoteReadOverlay: View                 // 全屏 overlay，手写字体，Liquid Glass 背景
NoteReadOverlay(content: String, tearMarkVisible: Bool, onDismiss: () -> Void)
```

## iPad 适配注意事项

本特性无特定 iPad 约束，遵循全局 `PlatformViewRepresentable` 规范即可。纸条特写 overlay 使用 SwiftUI 布局，自动适配不同屏幕尺寸；手写字体大小使用动态字号而非硬编码，确保大字号下不截断内容。

## 与现有代码的关系

**复用：**
- `ClassroomCoordinator.update(game:)` 单向映射模式，扩展其内部对林澈节点的处理分支
- 现有同学 SCNNode 结构（林澈节点已存在，扩展动画阶段）
- `ActiveEvent` / `EventChoice` 对话机制（步骤 4 对话选择复用此结构，以 `ChapterDialogue` 扩展）
- `SpatialAudioManager` 空间音频系统，新增 `.bell` 和 `.chair` cue
- `liquidGlassPanel` 用于纸条 overlay 背景

**修改：**
- `ActiveEventKind`：新增 `.noteDrop` case
- `AudioCueKind`：新增 `.bell` 和 `.chair` case（设计文档明确标注为待新增）
- `GameManager`：新增步骤 4 对话处理方法、步骤 5 纸条事件触发逻辑、步骤 6 衔接动画分流逻辑

**新增：**
- `NoteReadOverlay` SwiftUI 视图
- `LinCheAnimationPhase` 枚举（Coordinator 内部）
- `linCheGlanceDoorBeat` SceneDirectorBeatDefinition（第 6 回合抬头）
- `noteDropBeat` SceneDirectorBeatDefinition（步骤 5 触发）

## 风险与注意事项

- 林澈节点的动画阶段必须通过 `linCheAnimationPhase` 字段保护，防止 `update(game:)` 每帧重复 run 同一 SCNAction
- 步骤 5 的 `noteDrop` 事件 ID 必须进入 `completedBeatIDs`；若存档恢复时 `Ch1State.notePicked == true`，Coordinator 应直接将纸条 SCNNode 设为不可见（已拾取状态），不重播触发动画
- 步骤 4 对话选项的 `linCheTrust` 写入是一次性操作；第二章读取时此字段已为最终值，不可再被第一章后续逻辑覆盖
- 铃声（`AudioCueKind.bell`）播放时机须在纸条 SCNNode 出现后，避免音效先于视觉提示
- 林澈路径动画（步骤 6）使用 `SCNAction.sequence` 定义离开路径，路径终点在教室门外；若玩家已执行 `leaveSeat` 则触发衔接动画，否则 SceneDirector fallback 在动画结束时自动推进，两条路径都写入同一 stepID，确保幂等
