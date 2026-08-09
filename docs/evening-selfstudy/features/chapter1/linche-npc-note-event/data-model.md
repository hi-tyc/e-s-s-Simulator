# F-10 林澈 NPC 与纸条事件 — 数据模型

> 状态：final / accepted

## 新增类型

### LinCheAnimationPhase（Coordinator 内部枚举，不进存档）

```swift
enum LinCheAnimationPhase: Int {
    case idle        // 翻书停止，等待玩家观察
    case glancedDoor // 第 6 回合抬头看门口已完成
    case exiting     // 铃后路径动画进行中
    case exited      // 已离开教室门口
}
```

- 仅在 `ClassroomCoordinator` 内部维护，不序列化
- 用于防止 `update(game:)` 每帧重复触发同一 SCNAction

### NoteReadOverlayModel（传参用，不 Codable）

```swift
struct NoteReadOverlayModel {
    let content: String         // 固定文本，不随机
    let tearMarkVisible: Bool   // 蓝格线撕痕是否可见（第三章线索预埋，第一章为 true）
}
```

- 作为视图参数传入 `NoteReadOverlay`，不进存档

### ActiveEventKind 扩展

```swift
// 新增 case（现有 enum 扩展）
case noteDrop  // 纸条掉落，触发特写 overlay
```

### AudioCueKind 扩展

```swift
// 新增 case（现有 enum 扩展）
case bell   // 铃声，从讲台方向播放；缺少资源时程序化回退
case chair  // 椅子移动声，用于 noteDrop 前的空间定位音效
```

## 存档策略

**进入 NarrativeSave（通过 Ch1State 和 GameNarrativeState）：**

| 字段 | 所属结构 | 说明 |
|---|---|---|
| `Ch1State.linCheObserved` | `chapterState` | 步骤 1 完成标记 |
| `Ch1State.spokeToLinChe` | `chapterState` | 步骤 4 完成标记 |
| `Ch1State.notePicked` | `chapterState` | 步骤 5 完成标记 |
| `Ch1State.clueCount` | `chapterState` | 当前线索数（用于 HUD 便签恢复） |
| `GameNarrativeState.linCheSuspicion` | `narrative` | 跨章关注度值 |
| `GameNarrativeState.linCheTrust` | `narrative` | 跨章信任结果（步骤 4 写入后锁定） |
| `GameNarrativeState.linCheListenScore` | `narrative` | 跨章倾听分（步骤 4 累加） |
| `GameNarrativeState.noteFound` | `narrative` | 纸条是否存在（影响后续章节叙事） |
| `MainQuestProgress.completedBeatIDs` | `quest` | 包含 `noteDrop` 和 `linCheGlanceDoor` 的去重 ID |

**仅运行时状态，不进存档：**

- `LinCheAnimationPhase`（Coordinator 内部，恢复时由 `Ch1State` 重建）
- `linCheNode` SCNNode 引用
- `NoteReadOverlayModel`（视图参数，关闭后即丢弃）
- 纸条 SCNNode 可见性（由 `Ch1State.notePicked` 恢复时确定性重建）

**存档 key：** `LateStudySimulator.NarrativeSave.v1`（与全局存档共享，不新增独立 key）

## 数据一致性约束

- `GameNarrativeState.linCheTrust` 在步骤 4 的 `completeStep` 提交时原子写入，写入后第一章内不再修改；第二章读取此值时视为只读事实
- `Ch1State.notePicked` 为 `true` 时，`GameNarrativeState.noteFound` 必须同为 `true`；两者在同一次 `completeStep` 提交，不允许分两次提交造成中间不一致状态
- `completedBeatIDs` 一旦写入 `noteDrop`，`ActiveEventKind.noteDrop` 的任何后续触发请求都被静默忽略，不产生音效、动画或 overlay
- `linCheSuspicion` 值域为 0-100，步骤 1 写入 +30；若存档恢复时值已为 30，不得在恢复步骤 1 时再次追加
- `linCheListenScore` 第一章步骤 4 写入 0/1/2，第二章步骤 7/8 继续累加；第一章不得在步骤 4 以外的路径写入该字段
