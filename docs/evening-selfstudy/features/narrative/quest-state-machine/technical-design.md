# F-01 叙事状态机与章节进度 — 技术设计

> 状态：final / accepted

## 实现方案

在现有 `GameManager` 中新增三个存储属性 `quest: MainQuestProgress`、`narrative: GameNarrativeState`、`chapterState: ChapterRuntimeState`，逐步替换回合制属性，不一次性大换血。`GameManager` 实现 `NarrativeQuestManaging` 协议以暴露最小必要接口，内部持有 `SceneDirector`（F-02 实现）和 `QuestCatalog`。

章节转移采用 `prepare → commit → cleanup` 三阶段：`prepare` 预载相邻场景根节点但不开放热点；`commit` 以一次状态事务切换章节、检查点和目标，同时写入自动存档；`cleanup` 移除旧章节点与 Beat。步骤提交通过 `completedStepIDs: Set<String>` 实现幂等——集合中已存在的 stepID 直接 return，不重复写入任何叙事字段。

存档采用 JSON 编解码双槽：每步骤完成后、章节切换前和应用进入后台时均触发快照；完整解码并通过不变量校验后才提升为 `lastValid`；失败时回退 `lastValid` 并提示一次。

## 关键类型与接口

```
enum ChapterID: Int, Codable, CaseIterable
struct MainQuestProgress: Codable, Equatable
struct GameNarrativeState: Codable, Equatable
enum ChapterRuntimeState: Codable, Equatable   // case per chapter, no Any
struct NarrativeSave: Codable                  // schemaVersion, saveRevision, dual-slot管理在 GameManager
struct QuestStepResult: Codable, Equatable
enum PauseReason: String, Codable, Hashable

protocol NarrativeQuestManaging: AnyObject
  var quest: MainQuestProgress { get }
  var narrative: GameNarrativeState { get }
  var activePauseReasons: Set<PauseReason> { get }
  func completeStep(_ stepID: String, result: QuestStepResult)
  func startChapter(_ chapter: ChapterID)
  func addPauseReason(_ reason: PauseReason)
  func removePauseReason(_ reason: PauseReason)
  // transitionChapter 是 GameManager 内部方法，不暴露在协议中；
  // 章节门禁校验和三阶段转场封装在 GameManager 内部实现

// 各章节状态
struct PrologueState: Codable, Equatable
struct Ch1State: Codable, Equatable
struct Ch2State: Codable, Equatable
struct Ch3State: Codable, Equatable
struct Ch4State: Codable, Equatable
struct Ch5State: Codable, Equatable
struct Ch6State: Codable, Equatable
```

章节门禁逻辑集中在 `GameManager` 内部的 `chapterCompletionGate(for:)` 私有方法，返回 `Bool`；`transitionChapter` 调用门禁后再 `commit`，不允许绕过。

## iPad 适配注意事项

本特性无特定 iPad 约束，遵循全局 PlatformViewRepresentable 规范即可。`NarrativeSave` 使用 `UserDefaults`（key `LateStudySimulator.NarrativeSave.v1`），在 iPad 上无需修改路径。

## 与现有代码的关系

| 现有文件 | 变更方式 |
|---|---|
| `GameManager.swift` | 新增 `quest`/`narrative`/`chapterState`/`activePauseReasons` 属性；新增 `completeStep`/`transitionChapter`/`startChapter`/`addPauseReason`/`removePauseReason` 方法；回合制属性（`teacherTurn`、`PlayerState` 多指标）标记 deprecated，阶段 2 之前保留编译但不调用 |
| `GameModels.swift` | 新增本特性全部领域类型（`ChapterID`、`MainQuestProgress`、`GameNarrativeState`、各章 State、`NarrativeSave` 等）；保留 `CameraPose` 基础值、`PlayerAction.breathe/.drink`、`AudioCueKind` 基础值 |
| `LateStudySimulatorApp.swift` | 基本不变；入口继续注入 `GameManager` |
| `ContentView.swift` | 暂不修改；F-03 阶段替换 HUD |
| `ClassroomSceneView.swift` | 暂不修改；F-04 阶段扩展相机模式 |

## 风险与注意事项

- `completeStep` 幂等依赖 `completedStepIDs` Set 的原子写入；Swift `@MainActor` 保证单线程，但需确认 `SceneDirector`（F-02）的 `async Task` 回调也在 MainActor 上调用 `completeStep`
- `schemaVersion` 迁移器在 Phase 0 仅预置框架（v1→v1 空迁移）；后续版本需在合并前追加迁移函数，不得删除旧版本迁移路径
- `ChapterRuntimeState` switch 穷举强制：新增章节或改变枚举 case 时，编译器会暴露所有遗漏分支，防止静默引入错误
- 双槽存档提升时机：`lastValid` 必须在完整解码且校验通过后才写入；提升失败不应抛出 fatal error，只记录日志并保留旧 `lastValid`
- 回合制逻辑与叙事逻辑在 Phase 0-1 期间共存；需避免同名方法或属性冲突，建议在新增方法上加注 `// narrative-layer` 注释标记，Phase 2 之后统一清理
