# F-17 安全路线分流与成人交接 — 技术设计

> 状态：final / accepted

## 实现方案

F-17 的核心是一次**安全策略决策 + 原子状态提交**。`SafetyHandoffPolicy` 读取编剧设定的 `jiangYueActualRisk`（不读信任值），返回对应的 `SafetyRoute` 和 `CounselingEntryMode`；决策结果与 `adultNotified`、`jiangYueResolutionPath` 一并通过 `GameManager.completeStep` 的 `QuestStepResult.flags` 携带，在方老师到场时一次性写入 `GameNarrativeState` 与 `Ch4State`。

同伴行为由 `companionChoice` 驱动：班长触发快速电话联络，许栀发送消息并保持距离。两条路径最终都推进到方老师到场，差异体现在 NPC 动画和到场时间的 SceneDirector Beat 延迟上，不影响路线判定逻辑。

步骤 7 是三条路线的受限跟随段：SceneDirector 按 `safetyRoute` 注册不同的 Beat 序列，玩家只能在标记范围内移动，30 秒不动时苏念自动跟上。章节完成门禁检查 `adultContactInitiated && safetyHandoffComplete` 通过后，`GameManager.transitionChapter(from:result:)` 先持久化状态快照，再切换到第五章。

高危/即时危险路线进入步骤 6 时，SceneDirector 取消普通课间倒计时 Beat，插入 `SafetyResponseBeat` 优先级序列（优先级高于普通剧情 Beat）。该序列的具体台词和响应步骤以外部资源文件接入，构建时检查文件存在性。

## 关键类型与接口

```
SafetyHandoffPolicy.resolve(risk: RiskLevel) -> (SafetyRoute, CounselingEntryMode)
TeacherArrivalSequence.start(companion: CompanionID, route: SafetyRoute)
Ch4FallbackDirector.triggerCompanionContact()  // 倒计时归零时调用
GameManager.completeStep("ch4.step6", result:)  // 携带原子写入 flags
GameManager.transitionChapter(from: .stairwell, result:)
```

新增枚举/结构体（完整定义在 `GameModels.swift`，已在全局数据模型中声明）：
- `SafetyRoute`（已在全局模型定义，本特性实现其消费逻辑）
- `CounselingEntryMode`（已在全局模型定义）
- `JiangYueResolutionPath`（已在全局模型定义）
- `Ch4State.adultContactInitiated: Bool`
- `Ch4State.safetyHandoffComplete: Bool`

## iPad 适配注意事项

本特性无特定 iPad 约束，遵循全局 PlatformViewRepresentable 规范即可。

## 与现有代码的关系

**复用：**
- `GameManager.completeStep(_:result:)` 幂等提交机制（F-01 实现）
- `SceneDirector` Beat 注册与暂停集合（F-02 实现）
- `CompanionFollowBehavior` NPC 跟随（F-14 实现）
- `GameNarrativeState.jiangYueActualRisk`（F-01 数据模型）
- `GameNarrativeState.disclosedRisk`、`jiangYueTrustValue`（F-16 写入，本特性只读）
- `CountdownTimer`（F-16 实现，本特性在高危路线时取消）

**新增：**
- `SafetyHandoffPolicy`：纯函数，不持有状态，不引入可观察单例
- `TeacherArrivalSequence`：SceneDirector 请求执行的 Beat 动作集合（移动路径 + 台词 overlay）
- `Ch4FallbackDirector`：监听倒计时剩余时间，触发自动联络兜底

**修改：**
- `GameManager`：新增 `ch4AdultHandoffCompleted` 检查点判断，在 `completeStep("ch4.step6")` 后写入 `adultNotified` 和 `safetyRoute`
- `ClassroomCoordinator`：新增方老师到场路径动画节点映射（楼梯间入口 → 江越位置）

**不修改：**
- `SafetyRoute` / `CounselingEntryMode` / `JiangYueResolutionPath` 枚举定义——已在全局模型声明

## 风险与注意事项

- 原子提交要求：步骤 6 的 `completeStep` 必须在一次调用中携带 `adultNotified`、`safetyRoute`、`CounselingEntryMode`、`resolutionPath` 全部 flags；拆成多次提交会导致存档中间态不一致
- 高危/即时危险路线的安全响应脚本文件缺失时须在构建期给出明确错误，不得以默认普通路线静默替代
- `jiangYueActualRisk` 主线默认 `.moderate`，测试时须覆盖 `.high` 和 `.imminent` 路径；若测试环境无法注入编剧值，需在 `DEBUG` 模式暴露覆盖接口
- 方老师到达动画（`TeacherArrivalSequence`）与 Beat 倒计时并发：需确认 Beat 触发后动画结束前不接受第二次 `completeStep`（利用已有幂等门禁）
- 第五章入口模式与 `safetyRoute` 必须在章节转换前一致，读档时 `NarrativeSave` 校验需覆盖该不变量
