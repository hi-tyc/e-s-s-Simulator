# F-02 SceneDirector 节拍系统

> 状态：final / accepted
> 实现阶段：Phase 0
> 依赖特性：F-01（叙事状态机与章节进度）

## 产品能力描述

SceneDirector 是叙事推进的"隐形导演"：当玩家不操作时，它按预设延迟自动触发兜底 Beat，防止主线卡死；当游戏进入事件、暂停、失焦或系统休眠时，它冻结所有受控节拍并在恢复后从剩余时间继续，保证计时语义跨会话一致。读档恢复后，已完成 Beat 不会重复执行，确保叙事事实的幂等性。

## 功能边界

**包含：**
- `SceneDirectorBeatDefinition` 的注册、调度与取消
- `activePauseReasons: Set<PauseReason>` 多重暂停来源管理（非空冻结、清空恢复）
- 从剩余时间恢复（而非重新计时）
- Beat 完成后写入 `completedBeatIDs`，防止重复执行
- 章节切换、返回菜单、读档时取消当前章全部 Beat
- 通过 `BeatActionID` 向 GameManager 请求执行动作（不自行修改状态）

**不包含：**
- 直接修改 `SCNNode`、SwiftUI 视图或 `MainQuestProgress`
- 存储 Timer / Task 引用或闭包进入存档
- 具体章节 Beat 定义（属于各章节特性 F-05/F-10/F-16 等）
- 环境循环音效（灯管嗡声、风扇底噪等无状态循环不受暂停控制）

## 验收标准

- [ ] 事件弹层（`.event`）、暂停菜单（`.pauseMenu`）、应用失焦（`.appInactive`）、系统休眠（`.systemSleep`）分别插入 `activePauseReasons`，集合非空时全部受控 Beat 停止计时，集合清空后从剩余时间继续，不以原始 delay 重新开始
- [ ] `activePauseReasons` 中各原因只由对应来源移除；其中一个来源恢复不得误解冻其他来源
- [ ] 玩家操作与 fallback Beat 在同一帧触发时，`completeStep` 只执行一次（幂等），不产生重复 Beat 或重复状态写入
- [ ] 已执行 Beat ID 写入 `completedBeatIDs` 后，读档恢复时不再重放该 Beat
- [ ] 章节切换、返回主菜单或载入其他存档时，旧章节所有 in-flight Beat Task 全部取消
- [ ] `pendingBeatRemainingTimes` 在每步骤完成后、章节切换前与应用进入后台时随 `NarrativeSave` 一同持久化；恢复后 Beat 使用保存的剩余时间而非原始 `triggerDelay`

## 设计约束

- SceneDirector 是 GameManager 的**内部协作者**，不得在 `viewDidAppear` 中注册，不得持有第二份叙事状态，不得创建独立 ObservableObject 单例
- 暂停接口必须使用集合语义（`addPauseReason` / `removePauseReason`），禁止用单个 `Bool` 覆盖其他来源的暂停状态
- Timer / Task / 闭包本身不进入 `NarrativeSave`；存档只保存 `[String: TimeInterval]` 类型的剩余时间映射
- Beat ID 格式约定为 `chapter.step.beat`，保证跨章全局唯一
- 第四章高危/紧急路线进入后，安全响应 Beat 必须优先于普通剧情 Beat，并取消普通倒计时
