# F-08 视角停留判定与聚焦反馈 — 数据模型

> 状态：final / accepted

## 新增类型

### DwellFocusState

```swift
struct DwellFocusState {
    var activePose: CameraPose?             // 当前正在计时的视角
    var dwellAccumulated: TimeInterval      // 已累积的停留时长（秒）
    var triggeredInCurrentStep: Set<CameraPose> // 本步骤已触发过的姿态，防止重复完成
}
```

- 非 `Codable`，不进入存档
- 纯运行时结构，由 `GameManager` 作为 `var dwellFocus: DwellFocusState` 持有
- 步骤切换时调用 `resetDwellFocusForStep()` 将 `dwellAccumulated` 和 `triggeredInCurrentStep` 清空；`activePose` 保留为当前帧的实际姿态

### DwellThreshold

```swift
struct DwellThreshold {
    static let defaults: [CameraPose: TimeInterval] = [
        .left:    2.0,
        .right:   2.0,
        .desk:    3.0,
        .forward: 2.0   // 第三章观察步骤备用
    ]
}
```

- 编译期常量，非 `Codable`，非可观察
- 未配置的 `CameraPose`（如 `.board`）视为不触发停留判定，返回 `nil`

### FocusFeedbackPhase（可选内部状态枚举）

```swift
enum FocusFeedbackPhase: Equatable {
    case idle
    case active(pose: CameraPose)  // 正在播放反馈动画
}
```

- 仅用于协调 ContentView overlay 与 Coordinator FOV 动画的生命周期，防止重叠触发
- 运行时状态，不进入存档

## 存档策略

| 字段 | 存档策略 | 说明 |
|---|---|---|
| `DwellFocusState.activePose` | 不存档 | 读档后从当前帧重新赋值 |
| `DwellFocusState.dwellAccumulated` | 不存档 | 读档后从 0 重新计时 |
| `DwellFocusState.triggeredInCurrentStep` | 不存档 | 依赖 `completeStep` 的幂等性：读档恢复后 stepID 已在 `completedStepIDs` 中，重复抵达阈值也不会二次提交 |
| `DwellThreshold.defaults` | 不存档 | 编译期常量 |
| `focusFeedbackTrigger`（@Published） | 不存档 | 视觉反馈瞬态，读档后无需恢复 |

**存档 key**：本特性不引入新的 UserDefaults key。停留判定的叙事结果（如 `Ch1State.linCheObserved`）由 `completeStep` 写入 `NarrativeSave`（key `LateStudySimulator.NarrativeSave.v1`），已由 F-01 管理。

## 数据一致性约束

- `triggeredInCurrentStep` 必须与 `quest.currentStep` 的生命周期严格绑定：`completeStep` 执行后、`quest.currentStep` 递增时，必须立即调用 `resetDwellFocusForStep()`，不允许跨步骤延迟重置
- 章节切换（`transitionChapter`）时，`DwellFocusState` 整体重置为 `DwellFocusState()`，防止前一章的触发集合污染新章节的第一个步骤
- 停留计时的幂等性保证来自两层：`triggeredInCurrentStep`（运行时防重）和 `completedStepIDs`（存档层防重）；读档恢复后第一层重置但第二层保留，不会造成结果遗失
- `DwellThreshold.defaults` 不得在运行时动态修改；若未来需要关卡配置化，须通过新版本的 `NarrativeSave.schemaVersion` 迁移路径引入，不使用隐式覆盖
