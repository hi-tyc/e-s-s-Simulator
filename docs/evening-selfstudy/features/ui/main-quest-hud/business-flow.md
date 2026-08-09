# F-03 主线任务 HUD — 业务流程

> 状态：final / accepted

## 主流程

HUD 是纯展示层，业务驱动方向为：GameManager 状态变化 → ContentView 订阅 → 传入 HUD 组件渲染。

```
GameManager.completeStep(stepID:result:)
  │
  ├─ 更新 quest.currentStep
  ├─ 计算新的 QuestHUDItem（查步骤目标表）
  ├─ 赋值 currentHUDItem  ──── @Published → ContentView 刷新
  │                                  └─ MainQuestHUD(item: currentHUDItem)
  │                                       └─ 目标文字 .id(item.currentGoal)
  │                                            └─ SwiftUI identity transition 触发动画
  │
  ├─ 若有独白 → presentMonologue(item)
  │     └─ pendingMonologue = item  ──── @Published → InnerMonologueView 淡入
  │           async after 3.3s → pendingMonologue = nil → 淡出
  │
  └─ 若有线索 → appendClueCard(card)
        └─ clueCards.append(card)  ──── @Published → ClueCardStack 插入动画
              └─ SpatialAudioManager.play(.paper) 纸张翻动音效
```

目标切换动画序列：
1. `withAnimation(.easeInOut(duration: 0.3))` 包裹 `currentHUDItem` 赋值
2. SwiftUI 检测到 `currentGoal` 字符串变化 → `.id` 不同 → 触发 removal + insertion
3. 旧目标：`.opacity` removal（0.3s）
4. 新目标：`.move(edge: .bottom).combined(with: .opacity)` insertion（0.3s）

## 边界与兜底

| 场景 | 处理方式 |
|---|---|
| 演出收束控制（SceneDirector 受控 Beat 期间） | `GameManager` 设置 `hudMode = .minimal`，`MainQuestHUD` 隐藏主任务和目标文字，只保留暂停/字幕入口按钮；不消失为空白 |
| `activePauseReasons` 非空（事件弹层/暂停菜单/失焦） | HUD 继续显示当前内容；`pendingMonologue` 的 3.3s 计时冻结，恢复后继续剩余时间 |
| 存档恢复 | `currentHUDItem` 由 `quest.currentChapter + currentStep` 重新计算，无需从存档读取；`clueCards` 从 `completedStepIDs` 和 `chapterState` 重建，`pendingMonologue` 不恢复 |
| 同一独白 id 重复触发 | `presentMonologue` 前检查去重集合，重复 id 直接丢弃，不重新计时 |
| `clueCards` 已满 5 张 | `appendClueCard` 检查上限，第 6 张丢弃（设计上六章总线索不超过上限） |
| Reduce Motion 开启 | 目标切换改为 0.2-0.4s 淡入淡出，transition 去掉 `.move` 保留 `.opacity`；独白淡入时长同步缩短 |
| VoiceOver 焦点 | 步骤完成后 `AccessibilityFocusState` 移至新目标文字；线索便签出现时发送 `UIAccessibility.post(.announcement)` 播报标题 |

## 与其他特性的交互点

| 时机 | 调用方向 | 对端特性 |
|---|---|---|
| F-03 提升 `liquidGlassPanel` 为模块共享 | F-03 修改 → 其他特性直接受益（不破坏现有调用） | F-05/F-07/F-09/F-12 等所有 UI 特性 |
| F-09（内心独白与线索便签）实现具体触发逻辑 | F-09 调用 `GameManager.presentMonologue` / `appendClueCard` | F-09 依赖 F-03 提供的接口和组件 |
| F-19（苏念咨询与结局）展示主线完成反馈 | 第五章步骤 6 完成时 `currentHUDItem.mainTask` 变为「主线完成」 | F-19 依赖 F-03 的 HUD 组件渲染结局文字替换 |
| 第四章倒计时剩余 2 分钟 / 进入紧急路线 | `GameManager` 设置 `currentHUDItem.isUrgent = true` | F-16/F-17 触发状态变化，F-03 负责渲染暖橙色高亮 |
