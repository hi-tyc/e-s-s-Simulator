# F-11 镜像空间场景 — 数据模型

> 状态：final / accepted

## 新增类型

### Ch2State

```swift
struct Ch2State: Codable, Equatable {
    var currentLight: MirrorLightID? = .draft       // 当前激活灯；nil 表示三灯全亮
    var completedLights: Set<MirrorLightID> = []    // 已完成灯集合
    var returnDialogueChoice: MirrorReturnChoice?   // 步骤 7 选择结果
    var handoffChoice: LinCheHandoffChoice?          // 步骤 8 选择结果
}
```

要求：`Codable`、`Equatable`，纳入 `ChapterRuntimeState.mirror(Ch2State)`。

### MirrorLightID

```swift
enum MirrorLightID: String, Codable, CaseIterable {
    case draft      // 草稿灯（感知闪现·描线）
    case melody     // 旋律灯（感知闪现·旋律接唱）
    case comparison // 擦痕灯（感知闪现·擦除比较）
}
```

要求：`Codable`、`CaseIterable`，用于 `completedLights` 集合完成判定（`== Set(MirrorLightID.allCases)`）。

### MirrorReturnChoice / LinCheHandoffChoice（在 GameModels.swift 中已规划）

```swift
enum MirrorReturnChoice: String, Codable {
    case reassure       // 「你不用一直这么撑着。」
    case inviteToShare  // 「我不知道你在经历什么，但我想知道。」
    case stayPresent    // 「……我也不知道说什么，但我在这里。」
}

enum LinCheHandoffChoice: String, Codable {
    case askTogether    // 「我想和你一起去说，可以吗？」
    case stayAvailable  // 「我先不说，但你有事可以找我。」
    case tellAdult      // 「我觉得老师需要知道，就算你不想去。」
}
```

要求：`Codable`，存入 `Ch2State`；同时影响 `GameNarrativeState.linCheTrust`（步骤 8 写入）。

### ColorTemperatureAnimator（运行时，不存档）

```swift
class ColorTemperatureAnimator {
    var normalizedProgress: Double   // 0.0-1.0，由 ScenePresentationState.transition 序列化传递
    // 其余字段为 SCNLight 引用等运行时对象，不进入存档
}
```

## 存档策略

| 字段 | 存入 NarrativeSave | 说明 |
|---|---|---|
| `Ch2State.completedLights` | ✅ via `ChapterRuntimeState.mirror` | 决定光路长度与灯亮状态的唯一依据 |
| `Ch2State.currentLight` | ✅ | 恢复时判断当前激活灯 |
| `Ch2State.returnDialogueChoice` | ✅ | 步骤 7 完成后写入；恢复时不重复弹出 |
| `Ch2State.handoffChoice` | ✅ | 步骤 8 完成后写入 |
| `GameNarrativeState.linCheListenScore` | ✅ | 跨章累计值，步骤 7/8 各增加 |
| `GameNarrativeState.linCheTrust` | ✅ | 步骤 8 写入，决定第三章林澈协作程度 |
| `ColorTemperatureAnimator.normalizedProgress` | 间接 ✅ | 通过 `ScenePresentationState.transition` 序列化归一化进度 |
| `MirrorSceneNodes` SCNNode 引用 | ❌ | 运行时对象，由 Coordinator 按 `completedLights` 确定性重建 |
| 褪色进度（透明度值） | 间接 ✅ | 序列化为 `scenePresentation` 的场景阶段标记，恢复时重建 |

存档 key：`LateStudySimulator.NarrativeSave.v1`（与全局叙事存档共享，独立于 `ClassmateMemory.v1`）。

## 数据一致性约束

- `completedLights` 只增不减：一旦某盏灯写入集合，章节内不得移除（只有章节重置才清空）。
- `currentLight` 必须与 `completedLights` 保持一致：`completedLights` 包含所有三灯时 `currentLight` 必须为 `nil`；若不一致，存档校验失败并恢复 `lastValid`。
- `handoffChoice` 写入时必须同步写入 `GameNarrativeState.linCheTrust`，两者不得在不同事务中提交；使用 `completeStep` 的单次原子提交保证。
- `Ch2State` 只在 `ChapterRuntimeState.mirror` case 中使用，禁止运行时类型转换（`as?`）访问，必须通过 `switch ChapterRuntimeState`。
