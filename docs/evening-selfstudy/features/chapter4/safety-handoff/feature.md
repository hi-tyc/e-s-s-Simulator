# F-17 安全路线分流与成人交接

> 状态：final / accepted
> 实现阶段：Phase 5
> 依赖特性：F-16（江越对话与信任系统）

## 产品能力描述

玩家完成倾听和风险追问后，通过同伴联络让方老师到达江越所在位置，由编剧预设的风险事实（而非玩家信任分）决定三种安全路线（普通咨询 / 校内紧急响应 / 紧急服务），并以一次原子提交完成成人交接，将第五章入口模式持久化，确保学生角色不承担临床判断责任。

## 功能边界

**包含：**
- 第四章步骤 5-7：告知江越不用独自承担、同伴联络成人、成人到场后路线分流、玩家跟随安排
- `SafetyRoute` 三条路线的判定逻辑（由 `jiangYueActualRisk` 编剧事实决定）
- `JiangYueResolutionPath` 的写入（voluntary / adultCameAfterLowTrust / adultCameAfterUnclearDisclosure）
- 方老师到场动画与台词（`TeacherArrivalSequence`）
- 原子状态提交：`adultNotified`、`safetyRoute`、`CounselingEntryMode`、`resolutionPath` 同一事务
- 同伴行为差异（班长拨打电话 vs 许栀发消息）
- 步骤 7 三条路线的玩家受限目标与完成点
- 兜底逻辑（倒计时归零时 SceneDirector 触发同伴自动联络）
- 高危/即时危险路线下取消普通倒计时并进入专项响应

**不包含：**
- 步骤 1-4（找到江越、破冰、倾听、风险追问）——属于 F-16
- 第五章等候区内容（F-18）
- `jiangYueActualRisk` 的编剧赋值——是全局叙事事实，不在本特性计算
- 信任值计算（`DialogueTrustReducer`）——属于 F-16
- 披露状态解析（`DisclosureResolver`）——属于 F-16

## 验收标准

- [ ] 安全路线由 `jiangYueActualRisk` 决定，与信任值、追问方式、玩家选择无关；`safetyRoute` 不得保留默认值 `.standardCounseling` 作为实际决策结果
- [ ] `adultNotified`、`safetyRoute`、对应 `CounselingEntryMode`、`jiangYueResolutionPath` 在方老师到场后以一次幂等 `completeStep` 原子写入，不允许分批提交
- [ ] 三种路线（标准 / 紧急校内 / 紧急服务）均可独立推进至章节完成；`.high/.imminent` 路线取消普通倒计时并进入专项 Beat 序列
- [ ] 成人必须来到江越所在位置完成首次接管，不得要求学生在接管前单独转运江越
- [ ] 倒计时归零但步骤仍在 5 之前时，SceneDirector 自动触发同伴联络，主线不断
- [ ] 章节结束前先持久化 `safetyRoute` 与 `CounselingEntryMode`，再触发 `transitionChapter`；不允许先切场景后补状态
- [ ] 两种同伴（班长 / 许栀）路径均正确执行，到达速度与空间感有可感知差异
- [ ] 方老师台词不提"谁告诉我的"，不泄露追问内容；学生角色不执行临床判断

## 设计约束

- `jiangYueActualRisk` 是编剧常量，主线默认 `.moderate`，禁止在运行时由任何玩家行为重新计算
- 任何路线不得把 `disclosedRisk == .unknown` 解读为安全；成人到场前江越不得被单独留下
- 高危/即时危险路线的方老师台词和响应流程须经专业审核，以资源文件接入，不硬编码在状态机
- `safetyRoute` 写入后不可在当局内更改（不变量）
- 步骤结果和场景检查点必须在同一事务快照中编码，自动存档落点仅在 `commit` 前的稳定检查点或 `commit` 完成后
