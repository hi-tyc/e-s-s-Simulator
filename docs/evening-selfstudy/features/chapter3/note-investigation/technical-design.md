# F-15 纸条调查链 — 技术设计

> 状态：final / accepted

## 实现方案

第三章是从固定座位第一人称切换为引导第三人称（F-13 提供）的第一个实际用章。本特性在此基础上完成五步调查序列：

1. **纸条背面 overlay**：复用第一章纸条特写 overlay（`ActiveEventKind.noteDrop` 已有机制），新增翻面动画和背面内容渲染。触发条件是玩家将 `CameraPose` 切换为 `.desk` 后点击纸条热点。
2. **江越座位热点**：在 `ClassroomCoordinator` 现有同学座位节点映射中，将后排靠窗座位标记为可检查热点，交互后触发桌面特写 overlay（蓝格笔记本）。
3. **双观察并行判定**：步骤 3 包含两个独立观察条件（桌面热点 + 声音方向停留），各自独立触发 `clueCount` 增加；两者均完成才提交步骤。`GameManager` 维护局部计数，防止重复触发。
4. **同伴选择互斥提交**：周予安和许栀各设近距离触发区（≤ 1.5m）+ 交互键。玩家确认后调用 `completeStep("ch3.4", result:)` 并在 `result.choiceID` 中写入选择；`completeStep` 的幂等机制确保先到者生效，后者忽略。
5. **楼梯间入口触发**：玩家与同伴移动到楼梯间入口热点后，`GameManager.transitionChapter` 校验门禁并触发章节转换。

## 关键类型与接口

- `Ch3State: Codable, Equatable` — 章节状态，含 `noteClueFound`、`jiangYueSeatConfirmed`、`jiangYueStatus`
- `JiangYueStatus: String, Codable` — 枚举值 `.unknown / .justLeft / .leftAgo`
- `ClassroomCoordinator` 扩展：`jiangYueSeatHotspot` 节点、`noteBackFaceOverlay` 触发
- `GameManager.completeStep(_:result:)` — 幂等提交，已声明于全局接口契约
- `GameManager.transitionChapter(from:result:)` — 章节转换门禁，F-01 已定义
- `CompanionNPC`（F-14 提供）— 本特性只调用，不实现
- `CompanionFollowBehavior`（F-14 提供）— 同伴跟随，本特性只触发启动

## iPad 适配注意事项

本特性无特定 iPad 约束，遵循全局 PlatformViewRepresentable 规范即可。

## 与现有代码的关系

| 类别 | 内容 |
|---|---|
| 复用 | `CameraPose`（`.desk/.left/.right/.forward`）、`PlayerAction.leaveSeat`、`ClassroomCoordinator.update(game:)` 单向映射模式、`ActiveEventKind` overlay 触发机制 |
| 扩展 | `ClassroomCoordinator`：新增江越座位检查热点节点、背面纸条 overlay 触发；`GameManager`：注册第三章 `SceneDirectorBeatDefinition`，维护步骤 3 双观察计数 |
| 新增 | `Ch3State` 结构体、`JiangYueStatus` 枚举、NoteBackOverlay SwiftUI 视图（若不能与第一章共用则新建）、楼梯间入口节点触发逻辑 |
| 不修改 | `F-13 guidedThirdPerson` 相机模式、`F-14 CompanionFollowBehavior`（仅调用其启动接口） |

## 风险与注意事项

- 步骤 3 两项观察并行时需防止 `clueCount` 重复递增：每个观察 flag（桌面/声音）独立检查，已 true 则跳过计数。
- 同伴选择互斥依赖 `completeStep` 幂等性；若 F-01 实现存在时序漏洞，需在 `GameManager` 层加额外 guard（`companionChoice != .none` 时直接 return）。
- 纸条背面 overlay 与第一章正面 overlay 需共享或统一样式，避免两套独立实现出现视觉不一致。
- 楼梯间入口热点需在 `ClassroomCoordinator` 中与走廊场景根节点保持独立，防止章节切换时节点未清理。
- 第三章相机依赖 F-13，F-13 未完成时本章无法集成验证。
