# F-15 纸条调查链

> 状态：final / accepted
> 实现阶段：Phase 4
> 依赖特性：F-09（内心独白与线索便签）、F-13（引导第三人称移动与热点交互）、F-14（同伴 NPC 系统）

## 产品能力描述

玩家以第三人称在教室内自由移动，通过翻看纸条线索、检查江越座位、观察离开迹象，确认纸条来源；再从两位同伴中选择一人同行，共同前往楼梯间，完成"注意到 → 找到 → 不独自行动"的完整调查链，推进主线进入第四章。

## 功能边界

**包含：**
- 纸条背面翻看：蓝格线撕痕 + HB 铅笔印，触发内心独白与线索便签
- 后排江越座位检查：蓝格笔记本特写，确认纸条来源人物
- 离开迹象双观察：桌面热点（水杯/书本）+ 声音方向停留（楼梯间门轴声），任意顺序完成
- 同伴选择：班长周予安（教室门口）/ 许栀（走廊转角），二选一写入全局状态
- 前往楼梯间：同伴跟随，屏幕右下角同伴图标，到达入口触发章节转换

**不包含：**
- 楼梯间内江越对话与信任系统（F-16）
- 同伴 NPC 路径跟随行为本身（F-14 职责）
- 第三人称相机与碰撞/输入系统（F-13 职责）

## 验收标准

- [ ] 纸条背面触发后，`Ch3State.noteClueFound = true`，线索便签增加一张
- [ ] 移动到江越座位并交互后，`Ch3State.jiangYueSeatConfirmed = true` 且 `GameNarrativeState.jiangYueLocated = true` 在同一次 `completeStep` 中写入
- [ ] 步骤 3 两项观察（桌面热点、声音方向）均完成时步骤通过；90 秒仅完成一项时 SceneDirector 自动触发另一项
- [ ] 同伴选择通过唯一一次幂等 `completeStep` 写入 `GameNarrativeState.companionChoice`，不在 `Ch3State` 重复保存；两条路径不得同时提交
- [ ] `companionChoice == .none` 时禁止触发第四章章节转换
- [ ] 同伴跟随期间屏幕右下角显示同伴图标，到达楼梯间入口后图标仍正确渲染
- [ ] 班长和许栀两条选择路径均可独立推进主线，第四章有可感知的场景差异

## 设计约束

- 章节转换必须经 `GameManager.transitionChapter(from:result:)` 校验完成门禁（`jiangYueSeatConfirmed == true && companionChoice != .none`），禁止直接修改 `currentChapter`。
- `completeStep(_:result:)` 必须幂等；玩家操作与 fallback 同时到达时只提交一次结果。
- 第三人称移动、碰撞和鼠标输入全部复用 F-13 的 `guidedThirdPerson` 模式，本特性不另起一套实现。
- 章节软上限 10 分钟；超时后 SceneDirector 每 45 秒强化路径引导，不越级跳步。
- 同伴选择完成后不允许在本章内撤销或更改。
