# F-18 咨询室等候与隐私保护 — 数据模型

> 状态：final / accepted

## 新增类型

### `Ch5State`

章节级运行时状态，由 `ChapterRuntimeState.counseling(Ch5State)` 封装后进入存档。

```
struct Ch5State: Codable, Equatable {
    var entryMode: CounselingEntryMode = .standardWaiting
    var handoffSceneStarted: Bool = false
    var jiangYueEntered: Bool = false      // 仅标准路线使用
    var boundaryHeld: Bool = true          // 是否保持了「不偷听」边界
    var rumorHandled: Bool = false
    var rumorOutcome: RumorOutcome = .unknown
    var companionMessageReplied: Bool = false
    var jiangYueExited: Bool = false       // 仅标准路线使用
    var handoffConfirmed: Bool = false     // 三条路线共用完成门禁
    var farewellChoice: FarewellChoice?    // 仅标准路线使用
}
```

### `RumorOutcome`

```
enum RumorOutcome: String, Codable {
    case unknown      // 初始值，事件未触发
    case suppressed   // 玩家主动回应，两名 NPC 离开
    case contained    // 不回应或超时，议论自行散去
}
```

### 已在全局模型定义、本特性使用的类型

以下类型在 `GameModels.swift` 的全局声明中，F-18 只使用，不重复定义：

```
enum CounselingEntryMode: String, Codable {
    case standardWaiting, urgentHandoffWaiting, emergencyClosure
}

enum FarewellChoice: String, Codable {
    case checkIn, findTeacherTogether
}
```

`GameNarrativeState` 中由本章写入的字段：

```
var privacyProtected: Bool = true    // 始终为 true，本章任何分支不允许设为 false
var supportHandedOff: Bool = false   // 成人交接完成，与 handoffConfirmed 同一事务写入
```

## 存档策略

| 字段 | 存档位置 | 说明 |
|---|---|---|
| `Ch5State`（全部字段） | `NarrativeSave.chapterState`（`ChapterRuntimeState.counseling`） | 随章节存档；`entryMode` 一旦写入不可在本章内变更 |
| `GameNarrativeState.privacyProtected` | `NarrativeSave.narrative` | 全局叙事存档 |
| `GameNarrativeState.supportHandedOff` | `NarrativeSave.narrative` | 与 `handoffConfirmed` 原子写入 |
| `ScenePresentationState.cameraMode`（`.waitingSeated`） | `NarrativeSave.scenePresentation` | 恢复时确定性重建等候区相机锚点 |
| SCNNode 位置、NPC 路径、pull-back 动画 | 不存档 | 由 `ClassroomCoordinator` 依据 `checkpointID` 确定性重建 |

存档 key：`LateStudySimulator.NarrativeSave.v1`（与全局共用，不新增独立 key）

自动存档时机：
- 步骤 1 完成（`handoffSceneStarted = true`）后
- 步骤 3 完成（`rumorHandled = true`）后
- 步骤 4 完成（`companionMessageReplied = true`）后
- 步骤 6 完成（`handoffConfirmed = true`）后（章节转换前）

## 数据一致性约束

- `entryMode` 与 `GameNarrativeState.safetyRoute` 必须对应一致；读档时章节一致性校验拒绝两者不匹配的存档，恢复 `lastValid`
- `handoffConfirmed` 与 `supportHandedOff` 在同一次幂等 `completeStep` 中写入，不允许分两次提交
- `privacyProtected` 在本章始终为 `true`；若写入 `false` 视为非法状态，校验器应拒绝此存档
- 即时危险路线（`.emergencyClosure`）中 `jiangYueEntered`、`jiangYueExited`、`farewellChoice` 保持默认值，不参与完成门禁
- `rumorOutcome` 由 SceneDirector 超时路径或玩家选择路径写入，不由两者同时写入（`completeStep` 幂等保证）
- `farewellChoice` 仅当 `entryMode == .standardWaiting` 时有意义；其他路线保持 `nil`，第六章不读取此值
