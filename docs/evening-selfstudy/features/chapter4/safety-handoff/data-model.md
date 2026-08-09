# F-17 安全路线分流与成人交接 — 数据模型

> 状态：final / accepted

## 新增类型

以下类型已在全局数据模型（`GameModels.swift`）声明，F-17 负责其消费逻辑实现，不重复定义。

### Ch4State（扩展字段）

```swift
struct Ch4State: Codable, Equatable {
    // F-16 已声明：jiangYueFoundAndSeated, iceBreakSuccess,
    //              listenPhaseComplete, riskAskMethod
    var adultContactInitiated: Bool = false   // 已发出联络请求（≠ 成人已到场）
    var safetyHandoffComplete: Bool = false   // 成人明确说出接手后写入
}
```

Codable + Equatable 要求：继承 `Ch4State` 已有约束。`adultContactInitiated` 初始值 false，写入后不回滚；`safetyHandoffComplete` 是章节完成门禁字段之一。

### SafetyRoute（全局模型，本特性写入）

```swift
enum SafetyRoute: String, Codable {
    case standardCounseling      // 普通咨询路线
    case urgentSchoolResponse    // 校内紧急响应
    case emergencyServices       // 紧急服务（120/110）
}
```

### CounselingEntryMode（全局模型，本特性写入）

```swift
enum CounselingEntryMode: String, Codable {
    case standardWaiting         // 标准等候（咨询室外）
    case urgentHandoffWaiting    // 紧急等候（支持室外）
    case emergencyClosure        // 应急收束（安全锚点）
}
```

### JiangYueResolutionPath（全局模型，本特性完成写入）

```swift
enum JiangYueResolutionPath: String, Codable {
    case unknown
    case voluntary                          // 江越主动同行
    case adultCameAfterUnclearDisclosure    // disclosedRisk == .unknown 时
    case adultCameAfterLowTrust             // 已披露但拒绝同行
}
```

### SafetyHandoffPolicy（新增，纯函数类型）

```swift
struct SafetyHandoffPolicy {
    static func resolve(risk: RiskLevel) -> (route: SafetyRoute, entryMode: CounselingEntryMode)
}
```

不持有状态，不 Codable，不需要 Equatable。

## 存档策略

| 字段 | 存档位置 | 说明 |
|---|---|---|
| `Ch4State.adultContactInitiated` | `NarrativeSave.chapterState` → `.stairwell(Ch4State)` | 步骤 6 开始时写入，存档后恢复不重复联络 |
| `Ch4State.safetyHandoffComplete` | 同上 | 章节完成门禁，必须持久化 |
| `GameNarrativeState.adultNotified` | `NarrativeSave.narrative` | 跨章事实，第五章读取 |
| `GameNarrativeState.safetyRoute` | `NarrativeSave.narrative` | 跨章路线事实，第五章入口依赖 |
| `GameNarrativeState.jiangYueWillingToGo` | `NarrativeSave.narrative` | 步骤 5 选择结果，影响第五章开场动画 |
| `GameNarrativeState.jiangYueResolutionPath` | `NarrativeSave.narrative` | 第六章结局选择依赖 |

运行时不存档：
- `TeacherArrivalSequence` 的动画进度、Timer、Task
- `CountdownTimer` 状态（高危路线已取消）
- `Ch4FallbackDirector` 内部监听器

存档 key：`LateStudySimulator.NarrativeSave.v1`（与全局存档共享，通过 `ChapterRuntimeState.stairwell(Ch4State)` case 访问本特性字段）。

## 数据一致性约束

1. **`safetyRoute` 写入后不可更改**：`SafetyHandoffPolicy.resolve` 只在步骤 6 `completeStep` 时调用一次；此后禁止任何代码重新赋值 `GameNarrativeState.safetyRoute`。
2. **`safetyRoute` 与 `CounselingEntryMode` 必须一一对应**：`.standardCounseling` → `.standardWaiting`，`.urgentSchoolResponse` → `.urgentHandoffWaiting`，`.emergencyServices` → `.emergencyClosure`。第五章进入时读档若二者不一致，恢复到最后有效检查点，不得默认落入普通路线。
3. **`adultContactInitiated` 先于 `safetyHandoffComplete`**：`safetyHandoffComplete = true` 的前提是 `adultContactInitiated == true`；存档校验须覆盖此顺序约束。
4. **`jiangYueResolutionPath` 不为 `.unknown` 时 `adultNotified` 必须为 true**：路径确定意味着成人已接管，二者联动由同一 `completeStep` 原子写入保证。
