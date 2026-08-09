# F-02 SceneDirector 节拍系统 — 数据模型

> 状态：final / accepted

## 新增类型

### SceneDirectorBeatDefinition
```
struct SceneDirectorBeatDefinition: Identifiable
```
| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | `String` | 全局唯一，格式 `chapter.step.beat` |
| `triggerDelay` | `TimeInterval` | 首次触发等待时长（秒）|
| `fallbackDelay` | `TimeInterval?` | 条件未满足时的兜底等待时长；nil 表示无兜底 |
| `conditionID` | `BeatConditionID?` | 可持久化条件标识，由 GameManager 运行时解析；nil 表示无条件触发 |
| `actionID` | `BeatActionID` | 可持久化动作标识，由 GameManager 运行时执行 |

不需要 Codable：Beat 定义本身不进存档，由 QuestCatalog 代码生成。

### BeatConditionID
```
struct BeatConditionID: RawRepresentable, Hashable, Codable
    rawValue: String
```
Codable 要求：进入 `SceneDirectorBeatDefinition.conditionID`，但后者不存档；此处 Codable 仅为满足 Codable 约束传播，实际序列化场景不存在。

### BeatActionID
```
struct BeatActionID: RawRepresentable, Hashable, Codable
    rawValue: String
```
同 `BeatConditionID`。

### PauseReason
```
enum PauseReason: String, Codable, Hashable
    case event          // .event 覆盖层激活
    case pauseMenu      // 暂停菜单打开
    case appInactive    // 应用失去活跃状态
    case systemSleep    // 系统休眠
```
Codable 要求：进入 `NarrativeSave.activePauseReasons`，但恢复时需过滤掉 `.appInactive` 和 `.systemSleep`（见存档策略）。

### QuestStepResult
```
struct QuestStepResult: Codable, Equatable
    choiceID: String?       // 玩家或 fallback 的具名选择，nil 表示无选择
    flags: Set<String>      // 附加标记，例如 "softNoticed"（苏念自动完成的兜底标记）
```
Codable 要求：作为 `completeStep(_:result:)` 参数，写入步骤结果后随 `NarrativeSave` 持久化。

## 存档策略

| 字段 | 归属 | 存档位置 | 说明 |
|---|---|---|---|
| `pendingBeatRemainingTimes` | `NarrativeSave` | `LateStudySimulator.NarrativeSave.v1` | `[Beat ID: TimeInterval]`，记录各 in-flight Beat 剩余时间；Task 本身不存档 |
| `activePauseReasons` | `NarrativeSave` | 同上 | 恢复时移除 `.appInactive` 和 `.systemSleep`，由当前应用状态重新评估 |
| `completedBeatIDs` | `MainQuestProgress` | 同上（通过 F-01 的 `quest` 字段） | 已完成 Beat ID 集合，只增不减 |
| `SceneDirectorBeatDefinition` 列表 | 运行时 | 不存档 | 由 `QuestCatalog` 从代码重建，不依赖存档中的 Beat 定义 |
| `BeatConditionID` / `BeatActionID` 字符串 | 运行时 | 不存档（仅在 Beat 定义中引用，Beat 定义不存档） | — |

存档 key：`LateStudySimulator.NarrativeSave.v1`（与 F-01 共用，不单独分 key）。

## 数据一致性约束

- `completedBeatIDs` 在单局内只增不减；章节重置（`startChapter`）不清空该集合，跨章节 Beat 完成记录全程累积
- `pendingBeatRemainingTimes` 中的 key 在章节切换时必须清空对应章节所有条目，不得保留已取消章节的剩余时间
- 恢复存档时：若 `pendingBeatRemainingTimes` 中某 Beat ID 已存在于 `completedBeatIDs`，则跳过该 Beat 的 Task 重建（Beat 已完成，不得重放）
- `activePauseReasons` 集合恢复后若为 `{.event}`（存档时有事件覆盖层），需同步校验 `GameState` 是否仍为 `.event`；不一致时以当前 `GameState` 为准，不继承存档时的覆盖层状态
- Beat ID 格式 `chapter.step.beat` 中 `chapter` 和 `step` 必须与 `quest.currentChapter` 和 `quest.currentStep` 一致；跨章节 Beat ID 不得在非对应章节内注册
