# F-13 引导第三人称移动与热点交互 — 数据模型

> 状态：final / accepted

## 新增类型

### ThirdPersonCameraConfig

```swift
struct ThirdPersonCameraConfig: Codable, Equatable {
    var offset: SIMD3<Float> = SIMD3(0, 1.8, -3.2)  // 角色后上方偏移（米）
    var followSmoothing: Float = 0.08                 // SCNTransaction 时长（秒）
    var occlusionPushDistance: Float = 0.5            // 遮挡时向前推近上限
}
```

Codable：进入配置文件；运行时可由辅助设置覆盖默认值。
不需要 Equatable 强依赖，仅用于判断配置是否需要重新应用。

### HotspotDefinition

```swift
struct HotspotDefinition: Codable, Equatable, Identifiable {
    let id: String                        // 例如 "ch3.jiangYueSeat"
    let worldPosition: SIMD3<Float>       // 热点在场景中的世界坐标
    let activationRadius: Float           // 触发高亮与交互的半径，默认 1.5m
    let actionID: BeatActionID            // 激活后调用的 completeStep 动作标识
    let keyboardFocusLabel: String        // 无障碍朗读文本，如「江越的座位」
    let isOneShot: Bool                   // 确认后是否从 Registry 移除
}
```

Codable：热点定义随章节资源打包，不进入运行时存档。
Equatable：用于 `HotspotRegistry` 的集合去重比较。

### HotspotActivationState

```swift
struct HotspotActivationState: Codable, Equatable {
    var confirmedHotspotIDs: Set<String> = []   // 本章已完成确认的热点 ID
    var currentNearestID: String? = nil          // 运行时：当前最近的高亮热点（不存档）
}
```

`confirmedHotspotIDs` 进入存档；`currentNearestID` 是纯运行时状态，恢复时始终从 `nil` 重建。

## 存档策略

| 字段 | 是否存档 | 存档位置 | 说明 |
|---|---|---|---|
| `ThirdPersonCameraConfig` | 否（运行时常量） | — | 使用代码默认值，不随章节变化 |
| `HotspotDefinition` | 否（随场景资源） | — | 章节开始时由 `HotspotRegistry.register` 重建 |
| `confirmedHotspotIDs` | 是 | `ChapterRuntimeState`（对应章节 case 内） | 防止读档后重复触发已完成热点 |
| `currentNearestID` | 否 | — | 恢复后由下一帧距离检测自动重建 |
| `ScenePresentationState.cameraMode` | 是 | `NarrativeSave.scenePresentation` | 恢复相机模式，由 Coordinator 据此重建相机位置 |

存档 key：沿用 `LateStudySimulator.NarrativeSave.v1`，`confirmedHotspotIDs` 内嵌在对应章节的 `ChapterRuntimeState` case（如 `Ch3State`）中，不单独新增顶层 key。

`NarrativeSave.checkpointID` 必须能映射到当前热点注册集合的正确子集；存档只落在 `completeStep` 完成后（稳定检查点），不在热点高亮的中间帧。

## 数据一致性约束

- `confirmedHotspotIDs` 只增不减：热点一旦确认，即使读档也不撤销，符合 `completeStep` 幂等语义
- `HotspotDefinition.id` 在全章唯一，命名规范为 `"ch{章节编号}.{语义名}"`，不得跨章复用同一 ID
- `ScenePresentationState.cameraMode` 与 `ChapterRuntimeState` case 必须在同一事务快照中提交，不允许先切相机模式、后补章节状态
- 章节切换时 `HotspotRegistry.clearAll()` 在 `prepare` 阶段调用，`commit` 完成后注册新章热点；确保任意时刻只激活当前章热点
