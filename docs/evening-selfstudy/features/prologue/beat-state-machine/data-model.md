# F-05 序章 Beat 状态机 — 数据模型

> 状态：final / accepted

## 新增类型

### PrologueBeatID

```
enum PrologueBeatID: String, Codable, CaseIterable
    case gateArrival       // 段落 0：校门外（受控入场演出）
    case lookDownHall      // 段落 1：看一眼走廊（视角教学）
    case returnToSeat      // 段落 2：走回座位（移动教学）
    case placeWater        // 段落 3：放好水杯（交互教学）
    case studyHallRhythm   // 段落 4：晚自习如何开始（教室演出）
    case noticeLinChe      // 段落 5：看见左边的人（观察教学）
    case settleBreath      // 段落 6：先把自己准备好（自我照顾提示）
    case accessibility     // 段落 7：暂停与辅助（辅助设置教学）
    case bellBeforeClass   // 段落 8：铃响前半秒（演出转正式关卡）
```

约束：Beat ID 在 `NarrativeSave.pendingBeatRemainingTimes` 和 `completedBeatIDs` 中的存储键格式为 `"prologue.{rawValue}"`，保证与六章 Beat ID（`"chapter.step.beat"` 格式）不冲突。

### PrologueState

```
struct PrologueState: Codable, Equatable
    var openingViewed: Bool = false                      // gateArrival/studyHallRhythm 完成后
    var lookTutorialCompleted: Bool = false              // lookDownHall 完成后
    var movementTutorialCompleted: Bool = false          // returnToSeat 完成后
    var interactionTutorialCompleted: Bool = false       // placeWater 完成后
    var accessibilityTutorialAcknowledged: Bool = false  // accessibility 完成后
    var prologueCompleted: Bool = false                  // bellBeforeClass 完成后
```

六个字段均为只写一次（false → true），不可逆。`settleBreath` 和 `noticeLinChe` 节拍的完成不映射到 `PrologueState` 具名字段，仅记录在 `completedBeatIDs` 中。

### PrologueInputMode（运行时枚举，不进存档）

```
enum PrologueInputMode
    case controlledCinematic   // 仅允许暂停和辅助设置
    case lookOnly              // 允许转头 + 暂停
    case moveOnly              // 允许 WASD/路径点移动 + 暂停
    case interactOnly          // 允许靠近热点 + 确认 + 暂停
    case freeObserve           // 允许自由转头，不可移动/交互（段落 4、8）
    case settleAndSettings     // 允许呼吸确认/跳过 + 辅助设置（段落 6、7）
```

## 存档策略

**进入 NarrativeSave 的字段：**

| 数据 | 存储位置 | 说明 |
|---|---|---|
| `PrologueState` 全部字段 | `NarrativeSave.chapterState` → `.prologue(PrologueState)` | 需在 `ChapterRuntimeState` 新增此 case |
| 各 Beat 剩余时间 | `NarrativeSave.pendingBeatRemainingTimes["prologue.*"]` | 格式与六章 Beat 一致 |
| 已完成 Beat ID | `MainQuestProgress.completedBeatIDs` | 前缀 `"prologue."` 区分 |

**不进存档的运行时状态：**
- `PrologueInputMode`：由当前 Beat 阶段确定性推导，恢复时从检查点重建
- SceneDirector Task 本身（Swift Task 引用、闭包）

**存档键：** `LateStudySimulator.NarrativeSave.v1`（与六章共用，不新增 key）

**自动存档时机：** 每段节拍完成后（稳定检查点），与六章步骤存档规则一致。

**新档 skip 判断：** 游戏启动时先读 `NarrativeSave.chapterState`，若为 `.prologue` 且 `prologueCompleted == true`，则主菜单展示"直接从第一章开始"选项。`prologueCompleted` 不需要单独 UserDefaults key。

## 数据一致性约束

- `PrologueState.prologueCompleted` 只能由 `bellBeforeClass` 节拍的 `completePrologueBeat` 写入，禁止提前设置
- 五个教学完成标记相互独立，任意组合均合法（支持中途存档恢复）；未完成的标记不阻止进入第一章，只影响第一章是否显示简短提示
- `GameNarrativeState.suNianSelfCared` 在整个序章期间必须保持初始值 `false`；`settleBreath` 节拍的任意完成路径（主动/兜底）均不得写入此字段
- `ChapterRuntimeState.prologue` case 仅在 `quest.currentChapter` 尚未推进到 `.classroom` 时有效；一旦 `transitionChapter(.classroom)` 提交，`ChapterRuntimeState` 切换为 `.classroom(Ch1State())`，序章状态不再被修改
- 存档迁移器需处理缺少 `.prologue` case 的旧版存档，默认补充 `PrologueState()` 初始值，不覆盖已有六章状态
