# F-02 SceneDirector 节拍系统 — 技术设计

> 状态：final / accepted

## 实现方案

SceneDirector 作为 GameManager 的私有内部协作者存在，不对外暴露为独立类型。每个 Beat 由一个 Swift `async Task` 承载：Task 启动后先等待 `triggerDelay`（或读档恢复的剩余时间），到期后由 GameManager 通过 `BeatConditionID` 解析是否满足触发条件，满足则派发 `BeatActionID` 对应的动作；不满足但存在 `fallbackDelay` 时继续等待，再无条件派发兜底动作。

暂停机制通过 `activePauseReasons: Set<PauseReason>` 实现：Task 内部以协作式检查点轮询集合状态，非空时记录剩余时间并挂起，集合清空后从保存的剩余时间继续——不重新从原始 `triggerDelay` 计时。这保证多重暂停来源（例如同时失焦与打开暂停菜单）可以独立插入/移除，互不干扰。

Beat 定义（`SceneDirectorBeatDefinition`）在运行时由章节 Beat 目录（`QuestCatalog`）提供，本身不进存档。`GameManager` 在存档时只记录 `[Beat ID → 剩余 TimeInterval]`，恢复时重建 Task 并注入保存的剩余时间。

章节切换、返回菜单或读档时，GameManager 统一取消当前章节所有 Task，清空对应 `pendingBeatRemainingTimes` 条目。

## 关键类型与接口

```
struct SceneDirectorBeatDefinition: Identifiable
    id: String                          // 格式 "chapter.step.beat"
    triggerDelay: TimeInterval
    fallbackDelay: TimeInterval?
    conditionID: BeatConditionID?
    actionID: BeatActionID

struct BeatConditionID: RawRepresentable, Hashable, Codable
    rawValue: String

struct BeatActionID: RawRepresentable, Hashable, Codable
    rawValue: String

enum PauseReason: String, Codable, Hashable
    case event, pauseMenu, appInactive, systemSleep

struct QuestStepResult: Codable, Equatable
    choiceID: String?
    flags: Set<String>

@MainActor protocol NarrativeQuestManaging: AnyObject
    var quest: MainQuestProgress { get }
    var narrative: GameNarrativeState { get }
    var scenePresentation: ScenePresentationState { get }
    var activePauseReasons: Set<PauseReason> { get }
    func completeStep(_ stepID: String, result: QuestStepResult)
    func startChapter(_ chapter: ChapterID)
    func addPauseReason(_ reason: PauseReason)
    func removePauseReason(_ reason: PauseReason)
```

内部方法（不暴露给外部）：
```
func scheduleBeat(_ definition: SceneDirectorBeatDefinition, remainingTime: TimeInterval?)
func cancelAllBeats()
func dispatchBeatAction(_ actionID: BeatActionID)
func evaluateBeatCondition(_ conditionID: BeatConditionID) -> Bool
```

## iPad 适配注意事项

本特性无特定 iPad 约束，遵循全局 PlatformViewRepresentable 规范即可。SceneDirector 不持有任何平台相关视图引用，所有节拍动作通过 GameManager 间接作用于场景。

## 与现有代码的关系

**复用：**
- `GameManager` ObservableObject 框架与 `@MainActor` 标注
- `GameState` 中的 `.event` 状态继续作为覆盖层，SceneDirector 在此期间插入 `.event` 暂停原因

**修改：**
- `GameManager.swift`：新增 `activePauseReasons`、`addPauseReason`、`removePauseReason`、`startChapter`、`completeStep`（幂等版本）属性和方法；移除原有回合制 `execute(_:)`、`teacherTurn()` 等方法（按阶段分批移除）

**新增：**
- `SceneDirectorBeatDefinition`、`BeatConditionID`、`BeatActionID`、`PauseReason`、`QuestStepResult` 类型声明（建议集中写入 `GameModels.swift` 叙事模型区）
- SceneDirector 内部调度逻辑（private，位于 GameManager 内或单独文件内作为 internal 协作类）
- `NarrativeQuestManaging` 协议（供测试 mock 使用）

## 风险与注意事项

- Swift `async Task` 的协作式调度不保证纳秒级精度；触发延迟可能因主线程繁忙而偏移数帧，需对 12 秒 / 30 秒 / 90 秒兜底设计容差（±0.5 秒以内可接受）
- 玩家操作与 fallback Beat 同帧到达时，`completeStep` 必须通过 ID 去重而非依赖 Task 取消顺序
- `activePauseReasons` 的 `add/remove` 调用须全部在 `@MainActor` 上执行，不得从后台线程直接修改；跨线程的应用生命周期通知需通过 `Task { @MainActor in ... }` 派发
- 恢复存档时，`.appInactive` 和 `.systemSleep` 不应从存档直接恢复，而是根据当前应用状态重新评估；否则可能导致游戏一直冻结
- 第四章高危路线的安全响应 Beat 需要强制取消同章普通倒计时 Beat（通过具名 Task 取消，不得仅依赖优先级）
