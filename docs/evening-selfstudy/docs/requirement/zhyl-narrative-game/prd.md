# PRD：《这里有光》叙事冒险游戏

> 状态：final / accepted  
> 版本：v0.1  
> 日期：2026-07-20  
> 需求 ID：zhyl-narrative-game  
> 设计文档来源：`docs/2026-07-20-find-help-resolve-detail.md` v1.1、`docs/2026-07-20-铃响之前_演出主导教学关设计.md` v0.1

---

## 1. 背景与目标

### 1.1 背景

现有代码库实现了一个回合制晚自习压力模拟器（`GameManager` + `ClassroomCoordinator`），以多指标管理和教师 AI 为核心机制。该产品需要被《这里有光》线性叙事冒险游戏完整替代，原有回合制逻辑全部移除，底层基础设施（SwiftUI/SceneKit/AVFoundation 框架、Liquid Glass 样式、`SpatialAudioManager`）继续复用。

### 1.2 产品目标

用游戏形式表达对中学生心理健康的重视。玩家扮演苏念，在一个晚自习的傍晚发现同学江越的心理困境，通过观察、倾听、陪伴和引导成人介入，完成从"注意到"到"交接给可靠的人"的完整过程。

### 1.3 受众与发布范围

自研游戏，非商业发布，不面向公众上架。开发团队自行把控心理干预内容，外部专业机构书面审核不作为构建门禁。

---

## 2. 产品范围

### 2.1 首版完整范围

一次实现完整七个叙事单元（序章 + 六章），按六个实现阶段分阶段集成，任何阶段不得删减最终交付范围：

| 叙事单元 | 标题 | 核心体验 |
|---|---|---|
| 序章 | 《铃响之前》 | 演出主导教学关，约 7.5-9 分钟，建立操作信心 |
| 第一章 | 静音的教室 | 观察林澈、听到声音、自我照顾、捡纸条 |
| 第二章 | 走廊的镜子 | 镜像空间三灯微游戏，理解林澈恐惧 |
| 第三章 | 那张纸条 | 追踪纸条来源，确认江越，选择同伴 |
| 第四章 | 13楼的缝隙 | 找到江越，倾听，确认风险，成人交接 |
| 第五章 | 有灯亮着的房间 | 等候咨询室，保护隐私，偏见应对 |
| 第六章 | 这里有光 | 苏念走进咨询室，支持网络回顾，7种结局 |

### 2.2 不在首版范围内

- `LevelSeed` 随机种子系统
- 更多对话措辞变体
- 班干部在二周目中的额外关系余波

---

## 3. 用户故事与场景

### 3.1 核心用户故事

> 作为玩家，我想通过苏念的视角经历"发现同学困境 → 陪伴倾听 → 引导成人介入"的完整过程，在约 90 分钟内理解：注意到不等于判断，陪伴不等于独自承担，交给可靠的大人是正确的选择。

### 3.2 关键场景

**场景 1（序章）**：玩家第一次进入游戏，通过演出式教学关学习视角转动、短距离移动、物件交互和暂停/辅助设置。每个操作有叙事动机，不操作时最多 12 秒自动完成，无失败判定。

**场景 2（第一章）**：玩家坐在第三排，依次注意到林澈异常（书一页未翻）、听到右侧声音、选择自我照顾方式、与林澈对话、捡起匿名纸条。所有步骤有兜底，90 秒后由苏念自然完成。

**场景 3（第二章）**：玩家进入镜像空间，通过描线（草稿灯）、旋律接唱（旋律灯）、擦除文字（擦痕灯）三个微游戏理解林澈的内心压力，选择对话方式决定关系信任度。

**场景 4（第三-四章）**：玩家追踪纸条线索找到江越，选择同伴，进入楼梯间，通过 10 分钟课间倒计时完成倾听、风险询问和成人交接，分三种安全路线。

**场景 5（第五-六章）**：玩家在咨询室门口等候，处理流言、回复同伴消息、阅读偏见便签，最终走进咨询室说出自己的事，看到支持网络图和求助资源。

---

## 4. 功能需求

### 4.1 叙事状态机与进度管理

- `MainQuestProgress` 管理当前章节和步骤，`GameNarrativeState` 管理跨章叙事事实（信任值、披露状态、同伴选择、结局因子等）。
- `completeStep(_:result:)` 必须幂等；玩家操作与 fallback 同时到达时只提交一次。
- 所有章节转换通过 `transitionChapter(from:result:)` 校验完成门禁，禁止直接修改 `currentChapter`。
- 六章不新增 `GameState` case，章节由 `quest.currentChapter` 表达，`.event` 继续作为覆盖层。

### 4.2 SceneDirector 节拍系统

- `SceneDirector` 是 `GameManager` 的内部协作者，按 `SceneDirectorBeatDefinition` 驱动延迟节拍。
- `activePauseReasons: Set<PauseReason>` 管理多重暂停来源（`.event / .pauseMenu / .appInactive / .systemSleep`）；集合非空时冻结所有受控节拍，集合清空后从剩余时间恢复（不重新计时）。
- 已执行 Beat ID 写入 `completedBeatIDs`，恢复后不得重复执行。
- 每章 Beat 在章节切换、返回菜单或读档时全部取消。

### 4.3 序章《铃响之前》

- 9 段 Beat（`PrologueBeatID`），约 7.5-9 分钟，75% 演出 / 25% 轻操作。
- 每段操作最长等待 12 秒后苏念自动完成，HUD 记录自动兜底，不弹出"操作失败"。
- `PrologueState` 记录四类教学完成情况；未完成不阻止进入第一章。
- 已完成序章的新档可选"直接从第一章开始"。
- 演出不使用全屏 MP4；所有节拍由同一 SceneKit 场景驱动。

### 4.4 第一至六章叙事步骤

> **注意**：本节列出关键功能约束，不是完整步骤规格。完整每章步骤流程（触发条件 → 执行逻辑 → 完成判定 → 结果写入）须与 `docs/2026-07-20-find-help-resolve-detail.md` §第一章至第六章捆绑阅读，两份文档共同构成完整需求。

关键功能约束：

- **视角停留判定**：新增 `dwellTimer` 累计同一区域停留时长，达阈值触发聚焦事件。
- **微游戏 overlay**（第二章）：`MicroGameOverlay` SwiftUI 视图，0.3s 淡入淡出，不使用 UIKit `UIBlurEffect`；三种微游戏均无失败判定，只有"完成"。
- **第三人称相机**（第三-四章）：`guidedThirdPerson` 模式，复用统一输入，新增相机跟随偏移。
- **同伴 NPC**（第三-五章）：`CompanionFollowBehavior` 与玩家保持 1.5m，路径跟随；同伴选择写入 `GameNarrativeState.companionChoice`，不在章节状态复制。
- **信任值系统**（第四章）：`DialogueTrustReducer` 纯函数，结果写回 `GameManager.narrative`，不创建可观察单例；信任值对玩家不可见（无数字、无进度条）。
- **安全路线分流**（第四章）：`jiangYueActualRisk` 是编剧设定的剧情事实，不由信任值计算；三种安全路线（`.standardCounseling / .urgentSchoolResponse / .emergencyServices`）由编剧事实决定，学生不承担临床判断。
- **隐私保护**（第五章）：两种流言回应选项均不披露当事人位置或咨询内容；`privacyProtected` 始终为 true。
- **求助资源**（第六章）：全国统一心理援助热线 `12356`，提供 `NSPasteboard` 复制按钮；资源来自 `SupportResourceCatalog` 本地配置，不硬编码在视图中。

### 4.5 HUD 系统

- 原多指标 HUD 完全替换为 `MainQuestHUD`（主线任务 + 当前目标 + 可选提示）。
- 任何时刻只显示一项当前目标；演出收束控制时 HUD 退为极简但不消失。
- 内心独白：屏幕下方 1/4，半透明黑底，手写字体，淡入 0.3s 停留 3s 淡出。
- 线索便签：HUD 顶部，最多叠 5 张，每张出现时有纸张翻动音效。

### 4.6 存档系统

- 新增 `LateStudySimulator.NarrativeSave.v1` key，独立于现有 `ClassmateMemory.v1`。
- `NarrativeSave` 包含：`quest`、`narrative`、`chapterState`（`ChapterRuntimeState` 枚举封装）、`scenePresentation`、`pendingBeatRemainingTimes`、`activePauseReasons`。
- current / lastValid 双槽；只有完整编解码并通过不变量校验后才提升为 `lastValid`。
- 自动存档时机：每步骤完成后、章节切换前、应用进入后台时；步骤结果和场景检查点必须在同一事务快照中编码。
- 载入时先运行 `schemaVersion` 迁移器，再校验章节一致性；失败时优先恢复 `lastValid`，显示一次非阻塞提示。

### 4.7 无障碍功能

- 所有依赖音频的线索提供可关闭方向字幕；字幕不自动泄露声音来源身份。
- 描线/擦除支持键盘逐段确认和"由苏念慢慢完成"选项。
- 旋律记忆提供视觉节奏辅助和"再听一次"，不以听力作为通关门槛。
- 所有热点可通过键盘焦点导航。
- 对话和教育便签由玩家确认关闭，不以阅读速度作为失败条件。
- 系统 Reduce Motion 开启时，镜面/转场/节点动画改为 0.2-0.4s 淡入淡出。

---

## 5. 非功能需求

| 类别 | 要求 |
|---|---|
| 平台 | macOS 26，Liquid Glass API，Swift Package |
| 时长 | 完整通关约 90 分钟（软上限 86 分钟，超时 SceneDirector 加速） |
| 性能 | 场景根节点按章按需激活，任一时刻只激活当前章及相邻根节点 |
| 构建 | `swift build` / `swift run LateStudySimulator`，Command Line Tools 环境 |
| 审核门禁 | 选 C（自研非商业）：资源审核日期检查降级为 `#if DEBUG` 编译警告，不阻塞 Release 打包 |

---

## 6. 验收标准

来源：`docs/2026-07-20-find-help-resolve-detail.md` §验收检查清单。

### 通用（每章）

- [ ] 进入后 3 秒内 HUD 显示当前目标
- [ ] 完成目标后 1 秒内新目标出现
- [ ] 无有效操作 30 秒出现加强引导，90 秒内推进一个受控场景变化
- [ ] 不佳选择后主线不断，有兜底路径
- [ ] 事件弹层、暂停、应用失焦、系统休眠期间叙事计时冻结，恢复后不重复触发 Beat
- [ ] 每步骤完成后自动存档，任意步骤恢复不丢失或重复选择结果
- [ ] 所有步骤可仅用键盘完成；关键音频有方向字幕

### 序章专项

- [ ] 首次进入后 3 秒内出现画面或字幕，不出现黑屏等待
- [ ] 不操作时最多 12 秒完成任一教学节点
- [ ] 四类基础操作（视角/移动/交互/辅助）各有一次自然情境提示
- [ ] 演出暂停后字幕、音频、自动兜底一致冻结；恢复后不跳段
- [ ] 序章结束时直接切为第一章 HUD，不出现加载黑屏

### 第二章专项

- [ ] 三个微游戏（描线/旋律/擦除）均无失败判定，只有"完成"状态
- [ ] 镜像世界允许暂停、退出和读档；恢复后三灯状态、光路和林澈 NPC 位置与微游戏结果一致
- [ ] 步骤 8 的选择结果正确写入 `linCheTrust`（`.open/.neutral/.closed` 三种）
- [ ] `MicroGameOverlay` 背景使用 `.ultraThinMaterial` 或 `liquidGlassPanel`，不使用 `UIBlurEffect`

### 第三章专项

- [ ] 班长和许栀的选择均能独立推进主线，两者影响差异在第四章有可感知的场景差异
- [ ] 缺少同伴状态（`companionChoice == .none`）时不允许进入第四章
- [ ] 同伴跟随时屏幕右下角显示同伴图标；进入楼梯间后图标仍正确显示

### 第四章专项

- [ ] 教育便签在追问前出现，可被玩家主动关闭
- [ ] 信任值对玩家不可见（无数字、无进度条）
- [ ] `.unknown` 不被解释为低风险；成人到场前江越不会被单独留下
- [ ] `.high/.imminent` 取消普通倒计时并进入紧急响应路线

### 第五章专项

- [ ] 咨询室门"不可进入"逻辑有明确视觉提示（camera pull-back 动画）
- [ ] 偏见便签最多触发 2 条，不强制触发；流言回应/不回应两种输入均不泄露咨询位置
- [ ] 三种入口（`.standardWaiting / .urgentHandoffWaiting / .emergencyClosure`）读档恢复后按原路线进行，紧急路线不出现普通告别场景

### 第六章专项

- [ ] 求助资源提供复制按钮，通过 `NSPasteboard` 复制
- [ ] 全国热线显示 `12356`
- [ ] 结局文字不出现"你赢了/失败了"等评判语
- [ ] 心理老师不下诊断、不提供万能建议

---

## 7. 与现有代码的映射关系

| 现有文件 | 处置方式 |
|---|---|
| `GameManager.swift` | 保留框架，删除回合制逻辑（`teacherTurn`、NPC压力矩阵、多指标 `PlayerState`），新增叙事属性和方法 |
| `GameModels.swift` | 保留可复用枚举（`CameraPose` 基础值、`PlayerAction.breathe/.drink`、`AudioCueKind` 基础值），删除回合制模型，新增叙事模型 |
| `ContentView.swift` | 替换 HUD 为 `MainQuestHUD`，保留 `liquidGlassPanel` 等 UI 辅助器 |
| `ClassroomSceneView.swift` | 保留 `ClassroomCoordinator` 框架，逐步扩展场景根节点映射 |
| `SpatialAudioManager.swift` | 直接复用，扩展新 `AudioCueKind` 值 |
| `LateStudySimulatorApp.swift` | 基本不变，入口保持 `GameManager` 注入 |

---

*文档状态：draft，待评审*  
*设计文档版本：`find-help-resolve-detail.md` v1.1 + `铃响之前` v0.1*
