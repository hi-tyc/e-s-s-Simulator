# F-06 校门/走廊新场景与入场演出 — 数据模型

> 状态：final / accepted

## 新增类型

### `CinematicCameraSequence`

```
struct CinematicCameraSequence: Equatable {
    let anchors: [CameraAnchor]  // 按时间序排列
}

struct CameraAnchor: Equatable {
    let position: SIMD3<Float>
    let eulerAngles: SIMD3<Float>
    let fieldOfView: Float
    let duration: TimeInterval   // 该锚点保持或过渡到下一锚点的时长
}
```

不需要 `Codable`：序列是编译期常量，不进入存档；只有"当前演出进度"（Beat 剩余时间）以 `pendingBeatRemainingTimes` 保存，恢复时从剩余时间重建播放位置。

### `GateArrivalSequence`

`CinematicCameraSequence` 的具体实例（静态常量），包含段落 0 的全部相机锚点（校门广角 → 走廊窗边 → 时间表特写 → 苏念进楼）。不是独立类型，只是命名常量。

### `CorridorLookTargetZone`

```
struct CorridorLookTargetZone: Equatable {
    let minYaw: Float      // 走廊尽头方向的水平角范围
    let maxYaw: Float
    let requiredDwellSeconds: TimeInterval  // 本特性内联值 1.0 秒
}
```

只在 `GameManager` 内部使用，不进入存档。

## 存档策略

本特性不新增 `NarrativeSave` 字段。入场演出的进度由以下现有字段覆盖：

| 需持久化的信息 | 存档位置 | 说明 |
|---|---|---|
| `gateArrival` Beat 是否已完成 | `MainQuestProgress.completedBeatIDs` | 值为 `"prologue.gateArrival"`，读档后不重放 |
| `lookDownHall` Beat 是否已完成 | `MainQuestProgress.completedBeatIDs` | 值为 `"prologue.lookDownHall"` |
| `gateArrival` Beat 剩余演出时间 | `NarrativeSave.pendingBeatRemainingTimes` | key 同 Beat ID，恢复后从剩余时间继续演出 |
| `lookDownHall` 停留计时 | 不存档 | 运行时状态；读档后重置为 0，玩家重新操作或等 12 秒兜底 |
| 当前激活场景根 | `ScenePresentationState.activeSceneRootID` | 值为 `"gateExterior"` 或 `"corridor"` |
| 视角教学是否已完成 | `PrologueState.lookTutorialCompleted` | 已在 F-05 定义的 `PrologueState` 字段 |

`PrologueState` 字段（`openingViewed`、`lookTutorialCompleted` 等）通过 `NarrativeSave.chapterState`（`ChapterRuntimeState.prologue(PrologueState)` 假设 F-05 已新增该 case）持久化，采用存档 key `LateStudySimulator.NarrativeSave.v1`，独立于 `ClassmateMemory.v1`。

## 数据一致性约束

- `ScenePresentationState.activeSceneRootID == "corridor"` 时，`MainQuestProgress.completedBeatIDs` 必须包含 `"prologue.gateArrival"`；若违反则读档校验拒绝继续，恢复到 `lastValid` 或从校门外重建
- `lookTutorialCompleted == true` 当且仅当 `"prologue.lookDownHall"` 在 `completedBeatIDs` 中；两者必须在同一次 `completeStep` 幂等提交中写入，不允许分开提交
- 章节切换（序章 → 第一章）前，`activeSceneRootID` 必须已切换为 `"classroom"`，`gateExterior` 和 `corridor` 根节点已在 `cleanup` 阶段卸载，不允许先切章节、后补场景状态
