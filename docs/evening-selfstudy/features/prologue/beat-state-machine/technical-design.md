# F-05 序章 Beat 状态机 — 技术设计

> 状态：final / accepted

## 实现方案

`GameManager.startPrologue()` 被调用时，向 F-02 SceneDirector 注册 9 条 `SceneDirectorBeatDefinition`，节拍 ID 格式为 `prologue.{PrologueBeatID.rawValue}`。每条定义携带：

- `triggerDelay`：前一段演出结束后自动开始的延迟（gateArrival 为 0s，其余按段落间隔）
- `fallbackDelay`：教学段 12 秒，观察/呼吸段 10 秒；纯演出段（gateArrival、studyHallRhythm、bellBeforeClass）无 fallback，演出完成时由 SceneDirector 直接派发完成动作
- `conditionID`：可选，教学段检测玩家输入类型（视角/移动/交互）是否符合当前教学目标
- `actionID`：映射到 GameManager 内部的演出调度和输入模式切换

每段节拍执行路径统一汇聚到 `completePrologueBeat(_ beatID: PrologueBeatID, flags: Set<String>)`：
- 玩家在窗口内完成操作 → 直接调用，`flags` 为空
- 超时兜底 → 同一接口，`flags = ["autoCompleted"]`
- 纯演出自然结束 → 同一接口，`flags = ["cinematic"]`
- 若 `completedBeatIDs.contains(beatID.rawValue)` 则立即返回（幂等）

每段节拍结束后创建稳定检查点；读档只恢复到段落开头或下一段入口，不恢复到镜头转场的中间帧。

序章全部完成后，`GameManager.transitionChapter` 切换到 `.classroom`，Chapter 1 HUD 在同一帧内替换序章 HUD。

## 关键类型与接口

```
enum PrologueBeatID: String, Codable, CaseIterable
    case gateArrival, lookDownHall, returnToSeat, placeWater
    case studyHallRhythm, noticeLinChe, settleBreath
    case accessibility, bellBeforeClass

struct PrologueState: Codable, Equatable
    openingViewed: Bool = false
    lookTutorialCompleted: Bool = false
    movementTutorialCompleted: Bool = false
    interactionTutorialCompleted: Bool = false
    accessibilityTutorialAcknowledged: Bool = false
    prologueCompleted: Bool = false

enum PrologueInputMode           // 运行时状态，不进存档
    case controlledCinematic     // 仅暂停和设置
    case lookOnly                // 转头 + 暂停
    case moveOnly                // WASD/路径点 + 暂停
    case interactOnly            // 靠近 + 确认 + 暂停
    case freeObserve             // 转头 + 暂停，不可移动/交互
    case settleAndSettings       // 确认/跳过 + 设置

// GameManager 上的公开接口
func startPrologue()
func completePrologueBeat(_ beatID: PrologueBeatID, flags: Set<String>)   // 幂等
var activePrologueInputMode: PrologueInputMode                            // @Published
```

## iPad 适配注意事项

本特性无特定 iPad 约束，遵循全局 PlatformViewRepresentable 规范即可。`PrologueState` 与 Beat 调度逻辑完全平台无关；触摸输入（点击路径点、点击热点）作为 WASD 和确认键的替代输入，由 F-07 辅助设置面板统一管理，F-05 只发布 `activePrologueInputMode`，不处理具体手势识别。

## 与现有代码的关系

**复用：**
- F-02 SceneDirector 的 `SceneDirectorBeatDefinition`、`BeatConditionID`、`BeatActionID`、`activePauseReasons` 集合，直接驱动序章 9 段节拍
- F-01 的 `NarrativeSave.pendingBeatRemainingTimes` 存储序章剩余计时
- F-04 的 `NarrativeCameraMode`（序章用到 `.seatedFirstPerson` 和 `.freeRoamFirstPerson`）

**修改：**
- `GameManager.swift`：新增 `startPrologue()`、`completePrologueBeat(_:flags:)`、`activePrologueInputMode` 属性
- `GameModels.swift`（或叙事模型文件）：`ChapterRuntimeState` 新增 `.prologue(PrologueState)` case

**新增：**
- `PrologueBeatID` 枚举（建议放在 `GameModels.swift` 叙事模型区）
- `PrologueState` 结构体（同上）
- `PrologueInputMode` 枚举（运行时，可放在 `GameManager.swift` 私有区）
- 9 条序章 `SceneDirectorBeatDefinition` 定义（`QuestCatalog` 序章段）

## 风险与注意事项

- 12s/10s fallback 依赖 Swift `async Task` 协作式调度，主线程繁忙时可能偏移数帧；±0.5 秒容差可接受，不得以精确帧为前提设计演出衔接
- `bellBeforeClass` 节拍完成后 HUD 切换须与 `transitionChapter(.classroom)` 同帧，不得产生可见的空白 HUD 或黑屏
- `settleBreath` 节拍的兜底路径（安静坐好）和主动路径（呼吸键/跳过）都必须明确 NOT 写入 `GameNarrativeState.suNianSelfCared`，需在 `completePrologueBeat` 实现处添加断言或注释
- 已完成序章的玩家选择"直接从第一章开始"时，`PrologueState` 中所有教学完成标记应视为已知，第一章不再重复弹出基础教学提示，需在 `startChapter(.classroom)` 时检查
- `ChapterRuntimeState.prologue` case 需在存档迁移器中处理（schema v1 新增 case），旧版不含序章存档加载时默认 `PrologueState()` 初始值
