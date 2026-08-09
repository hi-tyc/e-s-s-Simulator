# F-09 内心独白与线索便签 — 技术设计

> 状态：final / accepted

## 实现方案

F-03 已为 `GameManager` 提供 `presentMonologue(_:)` 和 `appendClueCard(_:)` 方法，以及对应的 `@Published` 属性。F-09 的核心工作是**在 `GameManager` 的章节步骤完成逻辑中，按规则调用这两个方法**，并在独白计时上与 `activePauseReasons` 正确联动。

### 内容定义方式

第一章和第三章的独白/便签文本以静态常量（`MonologueCatalog.ch1`、`ClueCatalog.ch1`）集中定义，不散落在步骤回调闭包中。每条独白通过具名 `let` 语句绑定到步骤 ID（如 `"ch1.step1.linCheObserved"`），便于测试和去重检查。

### 独白计时与暂停联动

`GameManager` 的 `presentMonologue` 启动一个 `Task`，在内部按 0.3s + 3s + 0.3s 三段调度 SwiftUI `@Published` 变更。暂停联动通过在 `Task` 内部轮询 `activePauseReasons.isEmpty`（最小 poll 间隔 0.05s，仅在暂停期间）实现冻结：Task 不保存进存档，恢复时若独白 `pendingMonologue` 仍不为 nil，由 `GameManager` 在移除最后一个 pause reason 后重新启动剩余时间的 Task（剩余时间存为非 Codable 运行态属性）。

### 便签上限守护

`appendClueCard` 内部检查 `clueCards.count < 5`，超出时打印 debug 警告并静默返回，不 crash。每次 append 后向 `SpatialAudioManager` 请求播放 `AudioCueKind.paper`。

### 防重入

`presentMonologue` 检查 `completedMonologueIDs`（`Set<String>`，章节切换时清空）；若传入 ID 已存在则直接返回，不重复播放。`appendClueCard` 同样检查 `clueCards` 的 `id` 集合去重。

## 关键类型与接口

调用方使用 F-03 已定义接口，F-09 新增以下内容目录类型和运行态属性：

```
enum MonologueCatalog {
  static let ch1: [String: InnerMonologueItem]  // key = stepID
  static let ch3Step1: InnerMonologueItem
}

enum ClueCatalog {
  static let ch1Step1: ClueCard   // 「林澈今晚一直看着同一页」
  static let ch1Step2: ClueCard   // 「右侧传来被掩盖的声音」
  static let ch1Step5: ClueCard   // 「匿名求助纸条」
  static let ch3Step1: ClueCard   // 「纸条来自蓝格笔记本」
}

// GameManager 新增运行态属性（非 Codable）
private var completedMonologueIDs: Set<String>      // 章节切换时清空
private var monologueRemainingTime: TimeInterval?   // 当前独白剩余秒数
```

步骤完成调用示例（在 `GameManager` 内部）：
```
// 第一章步骤 1 完成后
presentMonologue(MonologueCatalog.ch1["ch1.step1.linCheObserved"]!)
appendClueCard(ClueCatalog.ch1Step1)
```

## iPad 适配注意事项

本特性无特定 iPad 约束，遵循全局 PlatformViewRepresentable 规范即可。独白区域定位使用 `alignment: .bottom` + `padding(.bottom, UIScreen.main.bounds.height * 0.25)` 等比例偏移，在大屏上自然适配，不需要额外断点。

## 与现有代码的关系

**复用：**
- `InnerMonologueView`、`ClueCardStack`、`InnerMonologueItem`、`ClueCard`（F-03 定义，直接使用）
- `GameManager.presentMonologue`、`appendClueCard`（F-03 定义，本特性填充调用时机）
- `SpatialAudioManager`：便签音效通过 `AudioCueKind.paper` 调用，F-09 不直接访问 `AVAudioEngine`

**新增：**
- `MonologueCatalog.swift`：第一章和第三章步骤 1 的独白常量集
- `ClueCatalog.swift`：第一章和第三章步骤 1 的便签常量集
- `GameManager` 内部新增两个非 Codable 运行态属性：`completedMonologueIDs`、`monologueRemainingTime`

**修改：**
- `GameManager.swift`：在 `completeStep` 对应的第一章步骤分支中插入 `presentMonologue` / `appendClueCard` 调用；在 `startChapter` 中清空 `completedMonologueIDs`

## 风险与注意事项

- 若步骤 fallback 与玩家操作同帧命中（F-01 的幂等提交保证），`completeStep` 只被调用一次，独白和便签不重复——但需确认 F-03 的 `presentMonologue` 也做了 ID 去重，不能只依赖调用处
- 独白 Task 与 `activePauseReasons` 的轮询方案在暂停频繁切换时（如连续失焦-聚焦）需确保不并发启动多个 Task；建议用 `monologueTask` 属性保持唯一引用并在重启前 cancel
- 手写字体资源需在 `Package.swift` 的 `resources` 中声明；若字体文件缺失，`UIFont(name:size:)` 返回 nil，须在 `InnerMonologueView` 内有明确 fallback（F-03 实现范围，F-09 须在验收时确认）
- 第三章步骤 1 的独白/便签内容须与 F-15（纸条调查链）协调，避免两个特性对同一步骤触发重复便签
