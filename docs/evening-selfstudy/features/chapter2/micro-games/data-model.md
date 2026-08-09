# F-12 三灯微游戏 — 数据模型

> 状态：final / accepted

## 新增类型

### MicroGameID（新增枚举）

```swift
enum MicroGameID: String, Codable, CaseIterable {
    case draft       // 草稿灯·描线
    case melody      // 旋律灯·接唱
    case comparison  // 擦痕灯·擦除
}
// 与 Ch2State 中的 MirrorLightID（F-11 定义）一一对应，
// MirrorLightID.draft/.melody/.comparison 是场景标识，
// MicroGameID 是 overlay 控制标识，两者独立声明以职责分离。
```

### 运行时状态（不进存档，不 Codable）

```swift
// DraftLineMicroGame 内部持有，overlay 关闭时丢弃
struct DraftLineGameState {
    var tracedRatio: CGFloat = 0     // 已描路径比例 0.0-1.0
    var isComplete: Bool = false
}

// MelodyMicroGame 内部持有
struct MelodyGameState {
    var attemptCount: Int = 0        // 已重播次数
    var isAutoPass: Bool = false     // ≥3 次后自动通过
    var isComplete: Bool = false
}

// EraseMicroGame 内部持有
struct EraseGameState {
    var erasedRatio: CGFloat = 0     // 已擦面积比例 0.0-1.0
    var isComplete: Bool = false
}
```

### PauseReason 追加（修改现有枚举）

```swift
// 追加到现有 PauseReason
case microGame   // MicroGameOverlay 可见时插入，关闭时移除
```

### Ch2State 相关字段（由 F-11 定义，本特性写入）

```swift
// F-11 定义的 Ch2State 中，本特性负责写入的字段：
var currentLight: MirrorLightID? = .draft    // 当前待激活灯；三灯完成后为 nil
var completedLights: Set<MirrorLightID> = [] // 已完成灯集合，只增不减
```

### GameManager 运行时属性（不进存档）

```swift
@Published var activeMicroGame: MicroGameID?  // nil 表示 overlay 关闭
```

## 存档策略

| 字段 | 存档位置 | 存档时机 |
|---|---|---|
| `Ch2State.completedLights` | `NarrativeSave.chapterState → .mirror(Ch2State)` | 每灯完成后随步骤 commit 写入，与其他步骤结果原子提交 |
| `Ch2State.currentLight` | 同上 | 同上 |
| `activeMicroGame` | 不存档（运行时） | 读档后 overlay 始终以关闭状态恢复 |
| `DraftLineGameState` 等 | 不存档（运行时） | 读档后若当前灯未完成，玩家重新走近可再次触发 overlay；描线/擦除进度不恢复 |

存档使用全局 key `LateStudySimulator.NarrativeSave.v1`，无独立 key。

## 数据一致性约束

- `completedLights` 只增不减：任何路径（玩家完成、超时兜底、"由苏念完成"）均不得将已完成灯从集合中移除。
- `currentLight` 必须与 `completedLights` 一致：其值应为 `MirrorLightID.allCases` 中第一个不在 `completedLights` 中的元素，或三灯全亮后为 `nil`。存档校验时若两字段矛盾，视为损坏，回退至 `lastValid` 存档槽。
- `GameNarrativeState.linCheTrust` 由步骤 8 对话写入，不由微游戏直接写入；微游戏通过步骤 7 对话间接影响 `linCheListenScore`，进而影响步骤 8 的 NPC 回应差异，但不决定 `linCheTrust` 枚举值。
- 微游戏运行时状态（`DraftLineGameState` 等）不进入 `NarrativeSave`，无版本迁移负担。
- `PauseReason.microGame` 不持久化：读档时先清除 `.appInactive` / `.systemSleep`，同样清除 `.microGame`（overlay 关闭恢复）；用户暂停和事件覆盖按产品规则恢复。
