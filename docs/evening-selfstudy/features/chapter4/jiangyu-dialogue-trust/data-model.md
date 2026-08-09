# F-16 江越对话与信任系统 — 数据模型

> 状态：final / accepted

## 新增类型

### Ch4State（章节运行时状态）

```swift
struct Ch4State: Codable, Equatable {
    var jiangYueFoundAndSeated: Bool = false
    var iceBreakSuccess: Bool = false
    var listenPhaseComplete: Bool = false
    var riskAskMethod: RiskAskMethod = .none
    var adultContactInitiated: Bool = false
    var safetyHandoffComplete: Bool = false
}
```

Codable + Equatable。全部字段进入存档。

### RiskAskMethod

```swift
enum RiskAskMethod: String, Codable {
    case none
    case gentle        // 「你说的算了是什么意思？」
    case direct        // 「你有没有想过伤害自己？」
    case deferToAdult  // 明确交由成人接手
}
```

Codable。作为 `Ch4State.riskAskMethod` 字段存档。

### DialogueResponseKind（运行时枚举，不存档）

```swift
enum DialogueResponseKind {
    case judgmental        // 评判式，信任 -10
    case inspirational     // 鸡汤式，信任 -5
    case advisory          // 建议式，信任 ±0
    case listening         // 倾听式，信任 +10
    case accompanying      // 陪伴式，信任 +8
    case silentPresence    // 主动安静陪伴，信任 +5
    case timeout           // 超时未选择，信任 +1
}
```

运行时状态，不进入存档。信任值增量由 `DialogueTrustReducer` 计算后写回 `GameNarrativeState.jiangYueTrustValue`。

### GameNarrativeState 第四章相关字段（追加到全局状态）

以下字段已在全局 `GameNarrativeState` 中声明，本特性负责写入：

```swift
// 第四章写入
var jiangYueTrustValue: Double = 0          // 0-100，隐性，不对玩家展示
var jiangYueActualRisk: RiskLevel = .moderate // 编剧事实，固定值，不由逻辑计算
var disclosedRisk: RiskDisclosure = .unknown  // 玩家当前掌握的信息
var adultNotified: Bool = false
var jiangYueWillingToGo: Bool = false
var jiangYueResolutionPath: JiangYueResolutionPath = .unknown
var safetyRoute: SafetyRoute = .standardCounseling
```

### 依赖的已有枚举（GameModels 中声明）

```swift
enum RiskLevel: String, Codable { case low, moderate, high, imminent }
enum RiskDisclosure: String, Codable { case unknown, partial, confirmed }
enum JiangYueResolutionPath: String, Codable {
    case unknown, voluntary, adultCameAfterUnclearDisclosure, adultCameAfterLowTrust
}
enum SafetyRoute: String, Codable {
    case standardCounseling, urgentSchoolResponse, emergencyServices
}
enum CounselingEntryMode: String, Codable {
    case standardWaiting, urgentHandoffWaiting, emergencyClosure
}
```

## 存档策略

存档 key：`LateStudySimulator.NarrativeSave.v1`（与其他章节共用，独立于 `ClassmateMemory.v1`）

### 进入 NarrativeSave 的字段

| 字段 | 所在结构 | 存档位置 |
|---|---|---|
| `jiangYueFoundAndSeated` | Ch4State | `chapterState: .stairwell(Ch4State)` |
| `iceBreakSuccess` | Ch4State | 同上 |
| `listenPhaseComplete` | Ch4State | 同上 |
| `riskAskMethod` | Ch4State | 同上 |
| `adultContactInitiated` | Ch4State | 同上 |
| `safetyHandoffComplete` | Ch4State | 同上 |
| `jiangYueTrustValue` | GameNarrativeState | `narrative` |
| `jiangYueActualRisk` | GameNarrativeState | `narrative` |
| `disclosedRisk` | GameNarrativeState | `narrative` |
| `adultNotified` | GameNarrativeState | `narrative` |
| `jiangYueWillingToGo` | GameNarrativeState | `narrative` |
| `jiangYueResolutionPath` | GameNarrativeState | `narrative` |
| `safetyRoute` | GameNarrativeState | `narrative` |

### 不存档的运行时状态

- `CountdownTimer`（`Task` / `Timer`，重建时从 `pendingBeatRemainingTimes` 恢复剩余时间）
- `JiangYueDialogueStateMachine` 的内部 `Task`/闭包
- `DialogueResponseKind`（即时计算，不需要持久化）
- 江越 NPC 的 SCNNode 动画状态（由 `ClassroomCoordinator` 依据 `Ch4State` 和 `scenePresentation` 确定性重建）

### 自动存档时机

- 步骤 2（破冰）完成后
- 步骤 3 每段独白响应后（`listenPhaseComplete` 为 false 时，信任值和当前段落索引写入）
- 步骤 4（追问）选择后，`riskAskMethod` + `disclosedRisk` 同一事务写入
- 步骤 6（成人接管）完成后：`adultNotified`、`safetyRoute`、`CounselingEntryMode`、`safetyHandoffComplete` 原子写入

## 数据一致性约束

- `safetyRoute` 写入后不可更改：一旦成人到场并确认路线，不允许降级回 `.standardCounseling`
- `jiangYueActualRisk` 不可由玩家行为覆盖：该字段只能由编剧配置初始化，`DialogueTrustReducer` 和 `DisclosureResolver` 不得写入它
- `safetyRoute` 与 `CounselingEntryMode` 必须一致：读档校验时两者映射关系须通过以下不变量检查：
  - `.standardCounseling` ↔ `.standardWaiting`
  - `.urgentSchoolResponse` ↔ `.urgentHandoffWaiting`
  - `.emergencyServices` ↔ `.emergencyClosure`
  - 不一致时恢复 `lastValid` 并显示非阻塞提示
- `adultNotified = true` 后 `jiangYueResolutionPath` 不得保持 `.unknown`：成人到场时必须同步写入对应路径
- `disclosedRisk == .unknown` 时 `HUD` 不得显示任何暗示风险已排除的文字
