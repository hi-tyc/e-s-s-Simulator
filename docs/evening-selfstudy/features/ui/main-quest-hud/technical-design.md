# F-03 主线任务 HUD — 技术设计

> 状态：final / accepted

## 实现方案

`MainQuestHUD` 是纯展示 SwiftUI 视图，接收两个值类型参数：`MainQuestProgress`（当前章节和步骤，用于驱动动画 ID）和 `QuestHUDItem`（当前显示内容）。`GameManager` 通过 `@Published var currentHUDItem: QuestHUDItem` 发布，`ContentView` 订阅并传入 HUD。

目标切换动画使用 `.id(currentHUDItem.currentGoal)` 触发 SwiftUI identity transition，配合 `.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity)` 实现旧目标淡出、新目标从下方滑入。外层用 `withAnimation(.easeInOut(duration: 0.3))` 包裹 HUDItem 变更赋值。

内心独白作为独立 `InnerMonologueView` 组件，接收 `InnerMonologueItem?`（nil 表示不显示）。`GameManager` 在步骤完成时赋值并异步 3.3s 后清空（0.3 淡入 + 3s 停留 + 淡出，由 SwiftUI `.transition(.opacity)` + `withAnimation` 驱动）。

线索便签层 `ClueCardStack` 维护一个 `[ClueCard]`（上限 5 条），每次 append 时触发插入动画并请求 `SpatialAudioManager` 播放纸张翻动音效。

`liquidGlassPanel(cornerRadius:tint:)` 和 `ActionButtonStyle` 当前在 `ContentView.swift` 底部私有扩展。实现本特性时须将其提升为 `LiquidGlassExtensions.swift` 模块内 `internal extension View`，所有现有调用处无需改动。

## 关键类型与接口

```
struct QuestHUDItem: Equatable
  - mainTask: String
  - currentGoal: String
  - hint: String?
  - isUrgent: Bool

struct InnerMonologueItem: Equatable
  - text: String
  - id: String   // 去重用，防止相同文字重复播放

struct ClueCard: Identifiable, Equatable
  - id: String
  - title: String
  - detail: String?

struct MainQuestHUD: View
  init(progress: MainQuestProgress, item: QuestHUDItem)

struct InnerMonologueView: View
  init(item: InnerMonologueItem?)

struct ClueCardStack: View
  init(cards: [ClueCard])

// GameManager 新增发布属性
@Published var currentHUDItem: QuestHUDItem
@Published var pendingMonologue: InnerMonologueItem?
@Published var clueCards: [ClueCard]

// GameManager 新增方法
func presentMonologue(_ item: InnerMonologueItem)
func appendClueCard(_ card: ClueCard)
```

## iPad 适配注意事项

本特性无特定 iPad 约束，遵循全局 PlatformViewRepresentable 规范即可。HUD 宽度上限 220pt 为硬编码设计值，在大屏上不需要扩宽，保持左侧固定即可。

## 与现有代码的关系

**复用：**
- `liquidGlassPanel(cornerRadius:tint:)` 和 `ActionButtonStyle`：从 `ContentView.swift` 私有扩展提升为模块共享，不修改实现
- `SpatialAudioManager`：调用现有音效播放接口，新增 `AudioCueKind.paper`（纸张翻动）
- `ContentView.swift`：替换原多指标 HUD 区域为 `MainQuestHUD`，保留其余结构

**新增：**
- `MainQuestHUD.swift`：主任务 + 当前目标 + 提示的 SwiftUI 视图
- `InnerMonologueView.swift`：独白组件
- `ClueCardStack.swift`：线索便签层组件
- `LiquidGlassExtensions.swift`：提升后的共享 UI 辅助

**修改：**
- `GameManager.swift`：新增 `currentHUDItem`、`pendingMonologue`、`clueCards` 三个 `@Published` 属性及配套方法；原多指标 HUD 发布属性在此阶段保留但可以开始逐步删除

## 风险与注意事项

- `liquidGlassPanel` 提升必须在 `MainQuestHUD.swift` 创建前完成，否则文件拆分后编译失败
- `InnerMonologueView` 的 3.3s 定时器在 `activePauseReasons` 非空时须冻结计时，恢复后继续剩余时间，不重新开始
- `ClueCard.id` 需全局唯一（建议用 `chapter.step.序号` 格式），否则 `ForEach` 动画错位
- `MainQuestHUD` 宽度固定 220pt 最大值，在小字号系统设置下不会引发截断；若动态字号开启，须用 `.minimumScaleFactor` 保底而非固定高度裁剪
- VoiceOver 访问顺序需通过 `.accessibilitySortPriority` 明确，SwiftUI ZStack 默认顺序可能与视觉顺序不一致
