# F-01 叙事状态机与章节进度 — 数据模型

> 状态：final / accepted

## 新增类型

### 枚举

```
ChapterID: Int, Codable, CaseIterable
  .classroom=1  .mirror=2  .noteTrace=3
  .stairwell=4  .counseling=5  .epilogue=6

PauseReason: String, Codable, Hashable
  .event  .pauseMenu  .appInactive  .systemSleep  .microGame
  注：.microGame 在微游戏 overlay 激活时插入（F-12），读档时按 .appInactive 同规则清除

LinCheTrust: String, Codable       — neutral / open / closed
CompanionID: String, Codable       — none / zhouYuAn / xuZhi
RiskLevel: String, Codable         — low / moderate / high / imminent
RiskDisclosure: String, Codable    — unknown / partial / confirmed
JiangYueResolutionPath: String, Codable
SafetyRoute: String, Codable
CounselingEntryMode: String, Codable

ChapterRuntimeState: Codable, Equatable
  case prologue(PrologueState)
  case classroom(Ch1State)
  case mirror(Ch2State)
  case noteTrace(Ch3State)
  case stairwell(Ch4State)
  case counseling(Ch5State)
  case epilogue(Ch6State)
```

### 结构体

**MainQuestProgress**: Codable, Equatable
- `currentChapter: ChapterID` — private(set)，只通过 transitionChapter 修改
- `currentStep: Int` — 章内步骤编号，1-based
- `completedStepIDs: Set<String>` — 格式 "chapter.step"，避免跨章冲突
- `activeBeatIDs: Set<String>` — 恢复与去重用，不保存闭包
- `completedBeatIDs: Set<String>` — 已执行 Beat，读档后不重放

**GameNarrativeState**: Codable, Equatable
- 第一章：`linCheSuspicion: Double`、`noteFound: Bool`、`noteContent: String`、`suNianSelfCared: Bool`
- 第二章：`linCheListenScore: Int`、`linCheTrust: LinCheTrust`
- 第三章：`jiangYueLocated: Bool`、`companionChoice: CompanionID`
- 第四章：`jiangYueTrustValue: Double`、`jiangYueActualRisk: RiskLevel`、`disclosedRisk: RiskDisclosure`、`adultNotified: Bool`、`jiangYueWillingToGo: Bool`、`jiangYueResolutionPath: JiangYueResolutionPath`、`safetyRoute: SafetyRoute`
- 第五章：`privacyProtected: Bool`（始终 true）、`supportHandedOff: Bool`
- 第六章：`suNianSharedSelf: Bool`

**PrologueState**: Codable, Equatable
- `openingViewed / lookTutorialCompleted / movementTutorialCompleted`
- `interactionTutorialCompleted / accessibilityTutorialAcknowledged / prologueCompleted: Bool`

**Ch1State–Ch6State**: Codable, Equatable（各章步骤完成标记，详见详细设计文档 §第一章-第六章）

**QuestStepResult**: Codable, Equatable
- `choiceID: String?`
- `flags: Set<String>`

**NarrativeSave**: Codable
- `schemaVersion: Int`（当前 v1）
- `saveRevision: Int`（单调递增，用于双槽版本比对）
- `checkpointID: String`（可映射到确定性场景锚点）
- `quest: MainQuestProgress`
- `narrative: GameNarrativeState`
- `chapterState: ChapterRuntimeState`
- `scenePresentation: ScenePresentationState`（F-04 定义，此处引用）
- `pendingBeatRemainingTimes: [String: TimeInterval]`
- `activePauseReasons: Set<PauseReason>`

## 存档策略

**存档 key**：`LateStudySimulator.NarrativeSave.v1`（独立于 `ClassmateMemory.v1`，不互相覆盖）

**进入 NarrativeSave 的字段**：`quest`、`narrative`、`chapterState`、`scenePresentation`、`pendingBeatRemainingTimes`、`activePauseReasons`

**不进入存档的运行时状态**：`Timer`、`Task`、闭包、`SCNNode` 引用、正在播放的 `AVAudioPlayer` 实例；这些均由 `ClassroomCoordinator` 依据 `checkpointID` 确定性重建

**自动存档时机**：
1. 每个步骤的 `completeStep` 调用完成后
2. `transitionChapter` 的 `commit` 阶段完成后
3. 应用进入后台（`applicationWillResignActive`）时

**双槽管理**：完整编码 → 解码回读 → 通过不变量校验 → 提升为 `lastValid`；任一步失败保留旧 `lastValid`。读档优先 `current`，失败则尝试 `lastValid`，再失败则从当前章合法入口重建。

**载入时的处理顺序**：
1. 读取 `schemaVersion` 并运行迁移器（v1→v1 为空迁移，框架预置）
2. 校验 `quest.currentChapter`、`chapterState` case、`scenePresentation.chapter`、`safetyRoute` 与 `CounselingEntryMode` 相互一致
3. 移除 `activePauseReasons` 中的生命周期暂停项（`.appInactive/.systemSleep`），按当前应用状态重新添加
4. 校验失败时显示一次非阻塞提示

## 数据一致性约束

- `safetyRoute` 与 `CounselingEntryMode` 在第四章步骤 7 以原子提交写入，写入后不可单独修改其中一个
- `companionChoice` 只写入 `GameNarrativeState`，不在 `Ch3State` 中复制；`Ch4State` 读取全局字段
- `jiangYueActualRisk` 是编剧设定的剧情事实，不由信任值或玩家选择计算，写入后不可通过对话刷新
- `privacyProtected` 字段始终为 `true`；游戏不设计泄露隐私作为可试错分支，不需要运行时更新
- `completedStepIDs` 中的 stepID 格式为 `"chapterId.stepNumber"`（如 `"1.3"`），跨章步骤编号天然不冲突
- `checkpointID` 必须映射到可确定性重建的场景锚点；不可用自由文本或时间戳作为检查点标识
