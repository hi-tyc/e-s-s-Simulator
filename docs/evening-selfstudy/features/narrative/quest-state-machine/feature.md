# F-01 叙事状态机与章节进度

> 状态：final / accepted
> 实现阶段：Phase 0
> 依赖特性：无

## 产品能力描述

为《这里有光》提供可信的叙事进度管理底座：追踪玩家所在章节与步骤、记录跨章叙事事实（信任值、披露状态、同伴选择、结局因子等），并通过严格的章节门禁与幂等步骤提交保证游戏状态始终一致、可存档、可恢复。

## 功能边界

**包含：**
- `MainQuestProgress`：当前章节、步骤编号、已完成步骤 ID 集合、活跃/已完成 Beat ID
- `GameNarrativeState`：序章至第六章的全部跨章叙事事实字段
- 六章具名章节状态（`Ch1State` 至 `Ch6State`）和 `PrologueState`
- `ChapterRuntimeState` 枚举封装（禁止 `Any` 类型）
- `NarrativeSave` 双槽存档（`current` / `lastValid`）及 `schemaVersion` 迁移器框架
- `GameManager.completeStep(_:result:)` 幂等门禁
- `GameManager.transitionChapter(from:result:)` 合法转移校验
- `activePauseReasons: Set<PauseReason>` 多重暂停集合接口（状态存储部分）
- `NarrativeQuestManaging` 协议定义

**不包含：**
- SceneDirector Beat 调度与计时逻辑（F-02）
- MainQuestHUD 视图层（F-03）
- 叙事相机模式与场景呈现（F-04）
- 任何章节专属的游戏内容（步骤逻辑、NPC、微游戏）
- 音频扩展（F-20 集成阶段）

## 验收标准

- [ ] `completeStep(_:result:)` 对同一 stepID 的重复调用只写入一次结果；玩家操作与 fallback 同帧到达时不产生双重提交
- [ ] 所有章节转换必须经过 `transitionChapter(from:result:)` 并通过完成门禁检查；直接修改 `currentChapter` 的调用在编译阶段无法通过（属性为 `private(set)` 或协议封装）
- [ ] `NarrativeSave` 完整编解码后通过不变量校验才提升为 `lastValid`；当前槽损坏时自动回退 `lastValid` 并显示一次非阻塞提示
- [ ] `activePauseReasons` 集合非空时，叙事相关计时冻结；单一暂停来源恢复只移除自身，不影响其他来源
- [ ] 六章不新增 `GameState` case；当前章节和步骤仅由 `quest.currentChapter` / `quest.currentStep` 表达
- [ ] 存档 key `LateStudySimulator.NarrativeSave.v1` 独立于现有 `ClassmateMemory.v1`，不互相覆盖
- [ ] `ChapterRuntimeState` 的 `switch` 分支覆盖全部 case，编译器强制穷举（无 `default` 兜底）

## 设计约束

- `GameManager` 是**唯一可信状态源**，不得另建 `NarrativeStateManager.shared` 或第二个 `GameManager`
- `safetyRoute` 一旦写入不可更改（第四章原子提交后锁定）
- 协议 `NarrativeQuestManaging` 仅描述接口契约，`GameManager` 直接实现；不得把协议示例复制成独立实现类
- `NarrativeSave` 中不保存 `Timer`、`Task`、闭包或 `SCNNode` 引用
- 载入存档时先运行 `schemaVersion` 迁移器，再校验 `quest.currentChapter`、`chapterState` case 与 `scenePresentation.chapter` 三者一致性；未知新版本不得猜测解码
