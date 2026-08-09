# F-15 纸条调查链 — 数据模型

> 状态：final / accepted

## 新增类型

### Ch3State

```swift
struct Ch3State: Codable, Equatable {
    var noteClueFound: Bool = false           // 已翻看纸条背面，发现蓝格线线索
    var jiangYueSeatConfirmed: Bool = false   // 已确认江越座位与蓝格本
    var jiangYueStatus: JiangYueStatus = .unknown  // 离开迹象推断
}
```

要求：`Codable`（进入存档）、`Equatable`（支持 SceneKit 状态差分更新）。

### JiangYueStatus

```swift
enum JiangYueStatus: String, Codable {
    case unknown     // 初始，尚未观察
    case justLeft    // 水杯满、书未合：刚离开不久
    case leftAgo     // 座位温度低（兜底路径，当前主线默认为 justLeft）
}
```

要求：`String` RawValue 以保证存档可读性和迁移稳定性；`Codable`。

### 无需新增

`JiangYueStatus` 之外的枚举（`CompanionID`、`JiangYueLocated` 为 Bool）均已在 `GameNarrativeState`（全局数据模型，F-01 定义）中存在，本特性直接写入，不重复定义。

## 存档策略

| 字段 | 存档位置 | 说明 |
|---|---|---|
| `Ch3State`（整体） | `NarrativeSave.chapterState` → `ChapterRuntimeState.noteTrace(Ch3State)` | 每步完成后随步骤结果原子写入 |
| `GameNarrativeState.jiangYueLocated` | `NarrativeSave.narrative` | 跨章事实，第四章用于初始化江越状态 |
| `GameNarrativeState.companionChoice` | `NarrativeSave.narrative` | 跨章事实，第四-五章用于场景分支和 NPC 行为差异 |
| 近距离触发状态（同伴候选是否被感知）| 运行时，不存档 | 恢复后由 Coordinator 依检查点重建 |
| 同伴跟随动画进度 | 运行时，不存档 | 恢复后按 `companionChoice` 确定性重建初始跟随位置 |

存档 key：`LateStudySimulator.NarrativeSave.v1`（已有，不新增 key）。

步骤结果与章节状态必须在同一事务快照中编码；禁止先提交步骤再异步补 `chapterState`。

## 数据一致性约束

- `companionChoice` 一旦写入非 `.none` 值，本章内不可更改；`GameManager` 在已有值时对后续 `completeStep("ch3.4")` 直接 return。
- `Ch3State.jiangYueSeatConfirmed` 与 `GameNarrativeState.jiangYueLocated` 必须在同一次 `completeStep` 中同时写入；不允许 `jiangYueSeatConfirmed == true` 而 `jiangYueLocated == false`。
- 第四章入口门禁不变量：`Ch3State.jiangYueSeatConfirmed == true && GameNarrativeState.companionChoice != .none`；违反时 `transitionChapter` 拒绝并记录校验失败日志。
- 存档加载时 `ChapterRuntimeState` 的 case 必须与 `quest.currentChapter` 对应（`.noteTrace` ↔ `.classroom = 3`）；不一致时拒绝加载，回退 `lastValid`。
