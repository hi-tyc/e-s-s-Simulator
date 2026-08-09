# F-18 咨询室等候与隐私保护

> 状态：final / accepted
> 实现阶段：Phase 5
> 依赖特性：F-01（叙事状态机）、F-14（同伴 NPC 系统）、F-17（安全路线分流）

## 产品能力描述

玩家在第五章《有灯亮着的房间》中，以等候者身份陪伴江越进入专业支持流程。通过三种入口模式（标准等候、紧急交接等候、应急收束）体验"成人接手后学生的正确位置"，并在等候期间处理流言、回复同伴、对抗偏见便签，最终完成成人交接确认，推进主线进入第六章。

## 功能边界

**包含：**
- 从 `safetyRoute` 唯一映射 `CounselingEntryMode` 并驱动三条差异化场景路线
- 标准路线：咨询室门虚掩接待、等候区固定视角、江越进入门合上的"不可进入"逻辑与 camera pull-back 动画
- 高风险路线：支持室外等候锚点、心理老师轮班确认台词、不展示评估内容
- 即时危险路线：安全办公室/走廊锚点、方老师确认紧急服务接手、江越不再出镜
- 流言事件：NPC 路过议论 → 20 秒选项窗口（回应 / 不回应），两种结果均不泄露隐私
- 偏见便签系统：等候期间最多触发 2 条，不强制触发，左侧滑入卡片
- 同伴消息回复：HUD 通知 + 2 条选项，均保持隐私保护
- 成人交接确认与"主线完成"HUD 反馈
- 标准路线专属：江越告别选项（checkIn / findTeacherTogether）
- `GameNarrativeState.supportHandedOff`、`privacyProtected` 写入

**不包含：**
- 第六章苏念走进咨询室（F-19 职责）
- 同伴 NPC 跟随行为（F-14 职责）
- 安全路线分流本身（F-17 职责）
- 江越在高风险/即时危险路线的后续心理状态展示
- 咨询室内心理老师对话（第六章 F-19）

## 验收标准

- [ ] 三种入口（`.standardWaiting / .urgentHandoffWaiting / .emergencyClosure`）从 `safetyRoute` 唯一映射，读档恢复后按原路线进行，不默认落入 `.standardWaiting`
- [ ] 咨询室门"不可进入"逻辑有明确视觉提示：玩家靠近门 ≤0.5m 且停留 ≥3s 时触发 camera pull-back 动画（0.3s），`boundaryHeld` 保持 `true`
- [ ] 流言回应与不回应两种输入均不泄露当事人位置或咨询内容；`privacyProtected` 始终为 `true`
- [ ] 偏见便签最多触发 2 条，不强制触发；出现后 5 秒或玩家点击后消失
- [ ] 同伴消息两个回复选项均保持隐私，`companionMessageReplied` 幂等写入
- [ ] 三条路线均在成人确认后以同一次幂等 `completeStep` 写入 `handoffConfirmed = true` 和 `GameNarrativeState.supportHandedOff = true`
- [ ] 即时危险路线不出现普通告别场景，不让苏念再次接触江越
- [ ] 章节软上限 15 分钟：标准路线超时压缩等候事件；高风险/即时危险路线按成人确认 Beat 收束

## 设计约束

- `entryMode` 必须在章节入口校验与 `safetyRoute` 一致；不一致时读档恢复 `lastValid`，不得默认降级为 `standardWaiting`
- `privacyProtected` 在本章始终为 `true`，不提供泄露隐私的对话选项（游戏不把隐私泄露设计为可试错的娱乐分支）
- 高风险/即时危险路线不以"门打开、江越状态变好"作为反馈，只由成人给出最小必要确认
- `handoffConfirmed` 与 `supportHandedOff` 必须在同一事务快照中原子提交，不允许先切场景再补状态
- 等候区视角固定（`waitingSeated` 相机模式），不可 `leaveSeat`；可切换 `.left/.right/.board/.desk`
- 偏见便签、流言选项、书架科普卡复用 `InnerMonologue` 触发逻辑和 `liquidGlassPanel` 样式，不另建渲染层
