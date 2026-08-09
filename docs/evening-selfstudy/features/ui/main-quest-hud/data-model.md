# F-03 主线任务 HUD — 数据模型

> 状态：final / accepted

## 新增类型

### QuestHUDItem
```
struct QuestHUDItem: Equatable {
    let mainTask: String      // 主线任务名，章节内不变，11pt/白色50%
    let currentGoal: String   // 当前步骤目标，随步骤变化，14pt semibold
    let hint: String?         // 引导提示，可空，11pt/白色40%
    let isUrgent: Bool        // true 时目标文字变暖橙色
}
```
- 不需要 `Codable`（纯运行时展示，由 `GameManager` 从 `quest` 实时计算）
- 需要 `Equatable`（SwiftUI 动画 diff 依赖相等判断）

### InnerMonologueItem
```
struct InnerMonologueItem: Equatable {
    let id: String      // "chapter.step.index"，去重防重播
    let text: String    // 显示文字，手写字体
}
```
- 不需要 `Codable`（触发即消费，不进存档）
- 需要 `Equatable`（SwiftUI `.transition` identity diff）

### ClueCard
```
struct ClueCard: Identifiable, Equatable {
    let id: String      // "chapter.step.clue"，全局唯一
    let title: String   // 便签标题，如"匿名求助纸条"
    let detail: String? // 可选补充文字
}
```
- 不需要 `Codable`（通过 `NarrativeSave` 中章节状态间接重建，见存档策略）
- 需要 `Identifiable`（`ForEach` 动画依赖 id）

## 存档策略

| 字段 | 是否存档 | 说明 |
|---|---|---|
| `currentHUDItem` | 否 | 运行时由 `quest.currentChapter + quest.currentStep` 查表计算，恢复时重新计算即可 |
| `pendingMonologue` | 否 | 触发即消费，恢复时不重播；已读过的独白通过 `completedBeatIDs` 隐式去重 |
| `clueCards` | 间接存档 | 不单独存档；恢复时由 `NarrativeSave.quest.completedStepIDs` 和 `chapterState` 重建。例如 `Ch1State.notePicked == true` → 重建「匿名求助纸条」便签 |

存档 key 属于 F-01 范畴（`LateStudySimulator.NarrativeSave.v1`），F-03 不新增 UserDefaults key。

## 数据一致性约束

- `clueCards` 上限 5 条，由 `appendClueCard` 方法在 append 前检查；超出时忽略（设计上六章总线索不超过 5 条，不需要溢出处理）
- `ClueCard.id` 在整个游戏生命周期内唯一，不因读档重建而改变，格式约定为 `"\(chapter.rawValue).\(stepID).clue\(index)"`
- `InnerMonologueItem.id` 同一个 id 在同一局内只触发一次；`GameManager.presentMonologue` 在触发前检查 `completedBeatIDs` 或专用已播集合
- `QuestHUDItem.isUrgent` 仅在第四章倒计时剩余 2 分钟或进入紧急路线时为 `true`，其余章节始终为 `false`；由 `GameManager` 根据 `Ch4State` 和 `safetyRoute` 计算，不由 HUD 组件自行判断
