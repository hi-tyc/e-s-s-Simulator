# 《这里有光》详细需求设计

> **基于**：`2026-07-20-find-help-resolve-mainline.md` v0.1  
> **版本**：v1.1  
> **日期**：2026-07-20  
> **层级**：系统层详细需求，可直接指导实现
> **已确认范围**：B——一次实现完整六章，保留全部 3D 场景、三灯微游戏、班干部、咨询室与终章
> **实现原则**：完整范围分阶段集成，但任何阶段都不得删减六章最终交付范围

---

## 文档说明

主线稿描述了"发生什么、玩家做什么"（导演层）。  
本文档补充"如何判断、如何存储、如何分支、如何呈现"（系统层）。

**源码映射状态**：已于 2026-07-20 对 `/Users/tyc/Downloads/app-creator/e-s-s-Simulator-upload` 当前源码复核基础声明：现有 `GameManager`、`ClassroomCoordinator`、`CameraPose`、`PlayerAction`、`ActiveEventKind`、`AudioCueKind` 与 `liquidGlassPanel` 均存在；`PlayerAction.drink` 存在，`ActiveEventKind.noteDrop`、`AudioCueKind.bell`、六章叙事状态和 `NarrativeCameraMode` 尚不存在，均属于本文明确新增项。仓库移动或合并后仍须以实际声明为准，不得让 AI 创建同名替代状态源。

每章结构：
1. 章节状态变量定义
2. 每个步骤的详细流程（触发条件 → 执行逻辑 → 完成判定 → 结果写入）
3. 分支规则与兜底逻辑
4. UI/音频要求
5. 与现有代码的映射关系

---

## 全局数据模型

### 主线进度

```swift
enum ChapterID: Int, Codable, CaseIterable {
    case classroom = 1       // 静音的教室
    case mirror    = 2       // 走廊的镜子
    case noteTrace = 3       // 那张纸条
    case stairwell = 4       // 13楼的缝隙
    case counseling = 5      // 有灯亮着的房间
    case epilogue   = 6      // 这里有光
}

struct MainQuestProgress: Codable, Equatable {
    var currentChapter: ChapterID = .classroom
    var currentStep: Int = 1         // 章内步骤编号，1-based
    var completedStepIDs: Set<String> = [] // 使用 "chapter.step"，避免跨章编号冲突
    var activeBeatIDs: Set<String> = []    // 用于恢复与去重，不保存闭包
    var completedBeatIDs: Set<String> = [] // 已执行 Beat，读档后不得重放
}
```

### 关键全局状态

```swift
struct GameNarrativeState: Codable, Equatable {
    // 关卡一累积
    var linCheSuspicion: Double = 0      // 对林澈的关注度 0-100
    var noteFound: Bool = false           // 是否捡到纸条
    var noteContent: String = ""          // 纸条内容（固定文本，非随机）
    var suNianSelfCared: Bool = false     // 跨章结局事实

    // 关卡二累积
    var linCheListenScore: Int = 0       // 有效倾听次数 0-5
    var linCheTrust: LinCheTrust = .neutral

    // 关卡三累积
    var jiangYueLocated: Bool = false    // 是否确认江越位置
    var companionChoice: CompanionID = .none

    // 关卡四累积
    var jiangYueTrustValue: Double = 0   // 0-100，隐性
    var jiangYueActualRisk: RiskLevel = .moderate // 剧情事实，不由玩家得分计算
    var disclosedRisk: RiskDisclosure = .unknown // 玩家当前掌握的信息
    var adultNotified: Bool = false
    var jiangYueWillingToGo: Bool = false
    var jiangYueResolutionPath: JiangYueResolutionPath = .unknown
    var safetyRoute: SafetyRoute = .standardCounseling

    // 关卡五累积
    var privacyProtected: Bool = true    // 是否始终未披露身份、位置或咨询内容
    var supportHandedOff: Bool = false   // 是否完成成人交接

    // 关卡六
    var suNianSharedSelf: Bool = false   // 苏念是否说出了自己的事
}

enum LinCheTrust: String, Codable { case neutral, open, closed }
enum CompanionID: String, Codable { case none, zhouYuAn, xuZhi }
enum RiskLevel: String, Codable { case low, moderate, high, imminent }
enum RiskDisclosure: String, Codable { case unknown, partial, confirmed }
enum JiangYueResolutionPath: String, Codable {
    case unknown, voluntary, adultCameAfterUnclearDisclosure, adultCameAfterLowTrust
}
enum SafetyRoute: String, Codable {
    case standardCounseling, urgentSchoolResponse, emergencyServices
}
enum CounselingEntryMode: String, Codable {
    case standardWaiting, urgentHandoffWaiting, emergencyClosure
}
enum MirrorReturnChoice: String, Codable { case reassure, inviteToShare, stayPresent }
enum LinCheHandoffChoice: String, Codable { case askTogether, stayAvailable, tellAdult }
enum FarewellChoice: String, Codable { case checkIn, findTeacherTogether }
```

### HUD 主线任务组件

```swift
struct QuestHUDItem: Equatable {
    let mainTask: String         // 始终显示，大字，白色
    let currentGoal: String      // 当前目标，醒目
    let hint: String?            // 引导提示，可为空
    let isUrgent: Bool           // 暖红色高亮
}
```

---

## 全局机制：SceneDirector

`SceneDirector` 负责在玩家不操作时推进场景节拍，防止主线卡死。它是由 `GameManager` 持有的内部协作者，不在 SwiftUI `viewDidAppear` 中注册，也不拥有第二份剧情状态。

```swift
struct SceneDirectorBeatDefinition: Identifiable {
    let id: String
    let triggerDelay: TimeInterval
    let fallbackDelay: TimeInterval?
    let conditionID: BeatConditionID? // 可持久化标识，由 GameManager 解释
    let actionID: BeatActionID        // 可持久化标识，由 GameManager 解释
}

struct BeatConditionID: RawRepresentable, Hashable, Codable {
    let rawValue: String
}

struct BeatActionID: RawRepresentable, Hashable, Codable {
    let rawValue: String
}

enum PauseReason: String, Codable, Hashable {
    case event, pauseMenu, appInactive, systemSleep
}

struct QuestStepResult: Codable, Equatable {
    var choiceID: String?
    var flags: Set<String> = []
}
```

生命周期规则：

1. `GameManager.startChapter(_:)` 注册本章 Beat，并以 `chapter.step.beat` 作为全局唯一 ID。
2. `GameManager` 维护 `activePauseReasons: Set<PauseReason>`；进入 `.event`、应用失去活跃状态、系统休眠、打开暂停菜单时分别插入原因。
3. 只有对应来源结束时才移除自己的原因；集合非空就冻结全部 Beat，清空后才从剩余时间继续，不得按原始 delay 重新开始。
4. 章节切换、返回菜单或载入其他存档时取消旧章 Beat。
5. 已执行 Beat ID 写入 `MainQuestProgress.completedBeatIDs`，恢复后不得重复执行。
6. 玩家完成与 fallback 同时到达时，`completeStep` 必须幂等；同一 step 只允许提交一次结果。
7. SceneDirector 只请求 `GameManager` 执行动作，不直接修改 SwiftUI、SCNNode 或 `MainQuestProgress`。
8. `GameManager` 保存剩余时间、当前步骤和纯数据状态；Timer、Task、闭包本身不进入存档。
9. 暂停只冻结会改变剧情结果、NPC路径或交互门禁的受控 Beat/动画；灯管闪烁、风扇等无状态环境循环可继续。恢复后受控动画从检查点和归一化进度重建。

---

## 第一章：静音的教室

### 1.1 章节状态变量

```swift
struct Ch1State: Codable, Equatable {
    var clueCount: Int = 0           // 已收集线索数，目标 2
    var linCheObserved: Bool = false
    var soundObserved: Bool = false
    var selfCaredOnce: Bool = false  // 步骤3：是否自我照顾过一次
    var spokeToLinChe: Bool = false
    var notePicked: Bool = false
}
```

### 1.2 步骤详细流程

---

#### 步骤 1：看向林澈

**当前目标 HUD**：「看看林澈今晚在做什么」  
**提示**：「他坐在你左边」

**触发条件**：章节开始后立即激活。

**判定逻辑**：
```
玩家将 CameraPose 切换为 .left（左侧余光）
  且停留时间 ≥ 2.0 秒
  → 触发聚焦事件
```

**执行逻辑**：
1. 播放内心独白：「林澈今天只翻了一页书。从晚自习开始到现在，一直是同一页。」
2. HUD 线索便签 +1，视觉：便签叠加动效
3. `Ch1State.linCheObserved = true`，`clueCount += 1`（幂等提交只增加一次）
4. `GameNarrativeState.linCheSuspicion += 30`
5. 步骤标记完成，目标淡出

**SceneDirector 兜底**：
- 30 秒未切换左侧视角 → HUD 高亮左侧目标并播放一次不带身份结论的方向字幕。
- 90 秒仍未完成 → 苏念自然向左瞥一眼，提交同一观察结果并进入步骤 2；结果标记 `flags = ["softNoticed"]`，不伪造玩家主动操作。

---

#### 步骤 2：听清右侧声音

**当前目标 HUD**：「听清右侧那道声音」  
**提示**：「右边似乎有什么」

**触发条件**：步骤 1 完成后激活。

**判定逻辑**：
```
玩家将 CameraPose 切换为 .right
  且停留时间 ≥ 2.0 秒
  → 触发聚焦事件
```

**执行逻辑**：
1. 空间音频：从右侧方向播放一声压住的鼻息（`AudioCueKind.crying`，低强度，0.3s）
2. 随即被翻书声（`AudioCueKind.paper`）掩盖
3. HUD 听觉面板短暂显示：「右侧·抽鼻声·被掩盖」
4. 内心独白：「……有人在哭？还是我听错了？」
5. `Ch1State.soundObserved = true`，`clueCount += 1`（幂等提交只增加一次）
6. 步骤完成

**SceneDirector 兜底**：
- 30 秒未转向右侧 → 声音再播放一次并强化方向字幕。
- 90 秒仍未完成 → 苏念被声音吸引而自然偏头，提交 `soundObserved` 与 `flags = ["softNoticed"]`，自动进入步骤 3。

---

#### 步骤 3：自我照顾

**当前目标 HUD**：「先让自己缓一下」  
**提示**：「你可以低头呼吸，或者喝口水」

**触发条件**：步骤 2 完成后激活。第一章使用固定顺序目标，玩家始终只看到一个当前任务。

**判定逻辑（满足其一即通过）**：
```
条件 A：玩家执行 PlayerAction.breathe（深呼吸）
条件 B：玩家执行 PlayerAction.drink（喝水）
条件 C：玩家将 CameraPose 切换为 .desk 并停留 ≥ 3 秒
```

**执行逻辑**：
1. 播放内心独白：「我也不太好……不是说我有什么大事，就是，有点压着。」
2. `PlayerState.psychicEnergy += 8`（微量恢复，强调"自我照顾有效"）
3. `Ch1State.selfCaredOnce = true`
4. 同一次 step commit 写入 `GameNarrativeState.suNianSelfCared = true`（影响第六章结尾文本）

**此步骤可跳过**：若玩家不操作，90 秒后 SceneDirector 标记步骤完成，但 `selfCaredOnce` 与 `suNianSelfCared` 保持 false，影响第六章独白。

---

#### 步骤 4：跟林澈说一句

**当前目标 HUD**：「下课前，问林澈一句」  
**提示**：「他刚才抬了一下头」

**触发条件**：步骤 3 完成（或超时跳过）后，且已到第 6 回合（`currentTurn >= 6`）激活。

**SceneDirector 节拍**：
- 第 6 回合开始时，林澈 NPC 自动抬头看一眼门口，然后低头——这是给玩家的视觉提示

**玩家操作**：执行 `PlayerAction.talk`，进入对话选择界面

**对话选项**（3选1）：

| 选项 | 文字 | 林澈反应 | 写入状态 |
|---|---|---|---|
| A | 「今晚状态不太好？」 | 「没有，只是有点累。」低头 | `linCheListenScore += 1`，`linCheTrust = .neutral` |
| B | 「你书一页都没翻。」 | 沉默两秒，「……嗯。」 | `linCheListenScore += 2`，`linCheTrust = .open` |
| C | 「要不要帮你看一下今天的题？」 | 「不用，谢谢。」轻微皱眉 | `linCheListenScore += 0`，`linCheTrust = .neutral` |

**执行逻辑**：
1. 播放选中对话动画（林澈微小的头部/肩膀动作，SCNAction）
2. 写入 `GameNarrativeState.linCheListenScore`
3. `Ch1State.spokeToLinChe = true`
4. 内心独白根据结果触发：
   - B 选项成功：「他说'嗯'——不是敷衍，是真的认了。」
   - 其他：「他说没事。也许真的没事。也许不是。」

---

#### 步骤 5：捡起纸条

**当前目标 HUD**：「捡起掉到桌边的纸条」

**触发条件**：`currentTurn >= 8` 或步骤 4 完成后 60 秒，SceneDirector 请求触发 `noteDrop`。该事件使用唯一事件 ID，重复请求必须被忽略。

**SceneDirector 执行**：
1. 播放音效：前排椅子移动声（`AudioCueKind.chair`）
2. 纸条 SCNNode 出现在桌面边缘，轻微抖动
3. 铃声响起（`AudioCueKind.broadcast`，短促）
4. HUD 当前目标更新

**玩家操作**：将 `CameraPose` 切换为 `.desk`，点击纸条热点

**执行逻辑**：
1. 切换为纸条特写视角（全屏 SwiftUI overlay）
2. 显示纸条内容（手写字体）：
   > 「心里很难受，但我不知道找谁说。不知道有没有人想听。」
3. 无署名，角落有蓝格线撕痕（线索预埋，第三章用）
4. `Ch1State.notePicked = true`，`GameNarrativeState.noteFound = true`
5. 内心独白：「这不是传给我的。但我看见了。」
6. HUD 便签出现第三张：「匿名求助纸条」

---

#### 步骤 6：别让林澈一个人离开

**当前目标 HUD**：「别让林澈一个人离开」  
**提示**：「他往门口走了」

**触发条件**：步骤 5 完成后立即激活。

**SceneDirector 节拍**：
- 铃声后 5 秒，林澈 NPC 开始向教室门口移动（SCNAction 路径动画）

**玩家操作**：执行 `PlayerAction.leaveSeat`（起身），或在林澈离开前触发任意移动操作

**判定逻辑**：
```
在林澈 NPC 走出教室门（约 8 秒动画）之前：
  玩家执行 leaveSeat → 触发衔接动画
林澈已走出但玩家未操作：
  SceneDirector 自动推进，苏念起身（叙事：「我不知道为什么，就是跟着走了」）
```

**执行逻辑**：
- 无论玩家是否主动操作，均进入衔接过渡
- 根据 `GameNarrativeState.linCheTrust` 选择对应衔接动画（见主线稿 §5.6）
- 淡出到走廊场景 → 第二章开始

### 1.3 章节结束条件

`Ch1State.notePicked == true` 且走廊衔接动画触发。

**不可卡关保证**：每一步都有独立兜底，不能跨过中间步骤直接把 `currentStep` 改为 5。步骤 1、2 在各自 90 秒后以“苏念自然注意到”提交；步骤 3 在 90 秒后跳过自我照顾；步骤 4 在 90 秒后由林澈先说「我出去一下」并完成最低信息量对话；步骤 5 自动落纸条但保留明确拾取目标；步骤 6 自动起身。另设 10 分钟章节守护 Beat，只检查并触发当前步骤的合法兜底，绝不越级提交。

### 1.4 UI 规格

- **线索便签**：HUD 顶部，最多叠 5 张，每张出现时有纸张翻动音效
- **内心独白**：屏幕下方 1/4 区域，半透明黑底，手写字体，淡入 0.3s 停留 3s 淡出
- **视角聚焦光晕**：停留判定通过时画面边缘极淡暖光 + 摄像机轻微推近（`FOV` -2°，0.5s）

### 1.5 代码映射

| 功能 | 现有代码 | 变更说明 |
|---|---|---|
| 左/右视角停留判定 | `VisionZone.attentionCost` + 回合计数 | 新增 `dwellTimer: TimeInterval` 累计同一区域停留 |
| 林澈 NPC 动作 | `ClassroomCoordinator.update(game:)` | 在现有同学节点映射中新增 `linCheIdleAnimation`（书翻停、抬头、起身路径） |
| 纸条事件 | `ActiveEventKind.phoneNotification` 改造 | 新增 `ActiveEventKind.noteDrop`，触发特写 overlay |
| 铃声 | `SpatialAudioManager` + `AudioCueKind` | 明确新增 `.bell` 与 `bell.wav` 可选资源；缺失时程序化回退，从讲台方向播放 |
| SceneDirector | 无 | 为统一 `SceneDirector` 注册第一章 `SceneDirectorBeatDefinition`，不创建章节级状态源 |


---

## 第二章：走廊的镜子

### 2.1 章节状态变量

```swift
struct Ch2State: Codable, Equatable {
    var currentLight: MirrorLightID? = .draft
    var completedLights: Set<MirrorLightID> = []
    var returnDialogueChoice: MirrorReturnChoice?
    var handoffChoice: LinCheHandoffChoice?
}

enum MirrorLightID: String, Codable, CaseIterable {
    case draft, melody, comparison
}
```

### 2.2 进入条件

从第一章衔接过渡动画结束后自动进入，携带 `linCheTrust` 状态。

**HUD 主线任务**：「试着听懂林澈在害怕什么」

### 2.3 步骤详细流程

---

#### 步骤 1：跟着林澈到镜子前

**当前目标 HUD**：「跟着林澈到镜子前」

**触发条件**：章节开始时立即激活。

**SceneDirector 节拍**：
- 林澈 NPC 在走廊尽头停住，背对玩家
- 环境音：走廊空旷回响，远处教室关门声

**判定逻辑**：
```
玩家（第三人称）移动到镜子前 3 米范围内
  → 步骤完成
```

**SceneDirector 兜底**：玩家 30 秒未移动 → 走廊灯光变暗，只有镜子方向有光，引导移动方向。

---

#### 步骤 2：走进镜子里

**当前目标 HUD**：「走进镜子里」  
**提示**：「靠近任何反光面可以看见另一面」（仅首次提示，一次性）

**判定逻辑**：
```
玩家靠近镜面（距离 ≤ 0.8m）
  → 镜面边缘出现淡金色光晕（与第一章聚焦光晕同款视觉语言）
  → 玩家按确认键
  → 进入镜像空间
```

**进入镜像空间执行逻辑**：
1. 0.8 秒色温翻转过渡（暖黄 → 冷蓝）
2. 对场景 `lightingEnvironment.intensity`、主环境灯 `SCNLight.color` 与 `temperature` 做插值；`SCNLight` 不使用不存在的 `ambientColor`
3. 镜像林澈 NPC 出现（同节点，冷调材质版本）
4. 背景音切换：低频共鸣 120Hz + 钟声混响 1.8s
5. 草稿灯自动出现（点光源，微弱，位于前方 5m）

---

#### 步骤 3：点亮草稿灯（感知闪现 · 描线）

**当前目标 HUD**：「点亮眼前这盏灯」  
**提示**：「灯在前方，靠近它」

**触发条件**：步骤 2 完成后立即激活草稿灯。

**微游戏流程**：
```
玩家走近草稿灯（≤ 1.5m）
  → 全屏 SwiftUI overlay 淡入（0.3s）
  → 显示草稿纸特写：一道被划掉的推导步骤，旁边有虚线路径
  → 玩家用 DragGesture 沿虚线描线（容忍误差 ±15pt）
  → 描过 80% 路径长度 → 微游戏完成
  → overlay 淡出（0.3s），回到 3D 场景
```

**完成执行逻辑**：
1. 草稿灯亮度提升（`SCNLight.intensity`: 50→400，0.5s）
2. 镜像空间墙上「必须全对」文字出现裂缝（粒子效果，小规模）
3. 低频共鸣降低 20%
4. `Ch2State.completedLights.insert(.draft)`
5. `Ch2State.currentLight = .melody`
6. 内心独白：「划掉不是失败。划掉是在找。」
7. 地面出现光路（向旋律灯方向，宽 0.3m 发光地面贴图）

**若玩家描线失败（偏差过大）**：重置虚线，无惩罚，提示文字：「慢一点也没关系」。

---

#### 步骤 4：跟着光去下一处

**当前目标 HUD**：「跟着光去下一处」

**判定逻辑**：
```
玩家沿光路移动，到达旋律灯位置（距离 ≤ 1.5m）
  → 步骤完成
```

**SceneDirector 节拍**：林澈 NPC 自动沿光路走向旋律灯，玩家跟随（不要求紧跟，允许探索）。

---

#### 步骤 5：听完这段旋律（感知闪现 · 旋律接唱）

**当前目标 HUD**：「听完这段旋律」

**微游戏流程**：
```
玩家走近旋律灯（≤ 1.5m）
  → SwiftUI overlay 淡入
  → 波形可视化界面：4个音符依次亮起并播放（AVAudioEngine 程序化音高，约 2 秒）
  → 波形消失，出现 4 个圆形按钮（位置对应 4 个音高）
  → 玩家按正确顺序点击
  → 正确 → 完整旋律响起（约 1 秒）
  → overlay 淡出
```

**顺序错误处理**：重新播放一遍旋律，无惩罚，最多提示 3 次后自动通过（不设门槛）。

**完成执行逻辑**：
1. 旋律灯全亮
2. 镜像空间暖色人声环境音引入（低混）
3. 压迫性低频再降 30%
4. `Ch2State.completedLights.insert(.melody)`
5. `Ch2State.currentLight = .comparison`
5. 内心独白：「这段旋律他记得。没人要求他记，他就是记得。」
6. 光路延伸至擦痕灯方向

---

#### 步骤 6：别让那些话盖住他（感知闪现 · 擦除比较）

**当前目标 HUD**：「别让那些话盖住他」

**SceneDirector 节拍**：比较文字自动从墙面爬出（SCNAction 透明度动画，0→0.8，3s）；林澈 NPC 停在最深处，肩膀下沉。

**微游戏流程**：
```
玩家走近擦痕灯（≤ 1.5m）
  → SwiftUI overlay 淡入
  → 玻璃镜面特写：浮现多行比较文字（「他比你快」「她比你聪明」……）
  → 玩家用 DragGesture 在玻璃上擦
  → 擦除面积检测（mask 区域计算）
  → 达到 60% 擦除 → 微游戏完成
  → 保留剩余 40%（设计意图：比较不会完全消失）
  → overlay 淡出
```

**完成执行逻辑**：
1. 擦痕灯全亮，三灯全亮 → 镜像空间色调整体向暖偏移（0→20% 暖混）
2. 林澈 NPC 转过身来，面向玩家（第一次正脸）
3. `Ch2State.completedLights.insert(.comparison)`
4. `Ch2State.currentLight = nil`
5. 地面光路消失，镜像世界开始轻微褪色（透明度 1→0.7，10s 渐变）

---

#### 步骤 7：回到他身边，说一句真实的话

**当前目标 HUD**：「回到他身边，说一句真实的话」

**触发条件**：三灯全亮后自动激活。

**场景状态**：镜像世界褪色进行中，现实走廊声音开始渗入（低混 → 逐渐提高）

**对话选项**（3选1）：

| 选项 | 文字 | 适配 linCheTrust | 得分 |
|---|---|---|---|
| A | 「你不用一直这么撑着。」 | 所有状态均有效 | `linCheListenScore += 2` |
| B | 「我不知道你在经历什么，但我想知道。」 | `.open` 时回应更具体 | `linCheListenScore += 3` |
| C | 「……我也不知道说什么，但我在这里。」 | 所有状态均有效 | `linCheListenScore += 1` |

**执行逻辑**：
1. 林澈 NPC 反应动画（肩膀放松幅度取决于得分）
2. 镜像世界全部褪色完毕 → 现实走廊材质恢复
3. `Ch2State.returnDialogueChoice` 写入对应的 `.reassure/.inviteToShare/.stayPresent`
4. `GameNarrativeState.linCheListenScore` 累计写入
5. 自动过渡到步骤 8（现实对话空间）

---

#### 步骤 8：问问他愿不愿意一起找人

**当前目标 HUD**：「问问他愿不愿意一起找人」

**SceneDirector 节拍**：林澈在走廊现实视角中，沉默约 3 秒后开口问：「你会告诉方老师吗？」

**对话选项**（3选1）：

| 选项 | 选项文字 | 写入状态 | 对第三章的影响 |
|---|---|---|---|
| A | 「我想和你一起去说，可以吗？」 | `handoffChoice = .askTogether`，`linCheTrust = .open` | 第三章林澈会协助核实江越线索 |
| B | 「我先不说，但你有事可以找我。」 | `handoffChoice = .stayAvailable`，`linCheTrust = .neutral` | 标准路径 |
| C | 「我觉得老师需要知道，就算你不想去。」 | `handoffChoice = .tellAdult`，`linCheTrust = .closed` | 林澈短暂防御，第三章不主动协作 |

**完成后**：根据选择触发对应内心独白，章节结束，自动进入第三章。

### 2.4 章节结束条件

`Ch2State.completedLights == Set(MirrorLightID.allCases)` 且步骤 8 选择完成。章节提交时只写入跨章需要的 `linCheListenScore` 和 `linCheTrust`；灯状态保留在当前章状态和检查点中。

### 2.5 UI 规格

- **三灯进度**：镜像空间内，三盏灯的状态通过灯光强度和颜色体现，不需要额外 HUD 指示
- **微游戏 overlay**：`SCNView` 上层 SwiftUI `ZStack`，0.3s 淡入淡出，背景使用 `.ultraThinMaterial` 或现有 `liquidGlassPanel`；不得使用 UIKit 的 `UIBlurEffect`
- **镜像空间褪色**：`SCNTransaction` 控制材质透明度，10 秒线性过渡

### 2.6 代码映射

| 功能 | 现有代码 | 变更说明 |
|---|---|---|
| 镜像场景切换 | 无 | 在 `ClassroomCoordinator` 内增加 `MirrorSceneNodes` 节点容器；它不持有剧情状态，只根据 `scenePresentation` 显示/隐藏 |
| 色温过渡 | `SCNLight` | 新增 `ColorTemperatureAnimator` |
| 三个感知闪现 | 无 | 新增 `MicroGameOverlay` SwiftUI 视图 |
| 林澈 NPC 双态 | `ClassroomCoordinator` | 为林澈 SCNNode 新增 `mirrorMaterial` 材质集合 |
| 章节对话系统 | `ActiveEvent`/`EventChoice` | 扩展为 `ChapterDialogue`，支持多轮对话 |


---

## 第三章：那张纸条

### 3.1 章节状态变量

```swift
struct Ch3State: Codable, Equatable {
    var noteClueFound: Bool = false      // 发现蓝格线线索
    var jiangYueSeatConfirmed: Bool = false
    var jiangYueStatus: JiangYueStatus = .unknown
}

enum JiangYueStatus: String, Codable {
    case unknown
    case justLeft    // 水杯在，书没合
    case leftAgo     // 座位冷，不确定
}
```

### 3.2 进入条件

从第二章步骤 8 完成后，苏念返回教室（衔接动画：走廊→教室，约 10 秒）。教室内同学已陆续离开，只剩少数人。

**HUD 主线任务**：「找到写纸条的人」

### 3.3 步骤详细流程

---

#### 步骤 1：看看纸条背面

**当前目标 HUD**：「看看纸条背面的痕迹」  
**提示**：「纸条在你桌上」

**触发条件**：章节开始时立即激活。

**判定逻辑**：
```
玩家将 CameraPose 切换为 .desk
  → 纸条 SCNNode 高亮（边缘光）
  → 玩家点击纸条热点
  → 触发纸条翻面动画
```

**执行逻辑**：
1. 纸条翻面 SwiftUI overlay（同第一章纸条特写）
2. 背面显示：蓝格线撕痕痕迹 + 「HB」字样铅笔印
3. 内心独白：「这是从某本蓝格笔记本上撕下来的。我见过有人用这种本子……」
4. `Ch3State.noteClueFound = true`，线索便签 +1

---

#### 步骤 2：去后排确认

**当前目标 HUD**：「去后排确认江越的座位」  
**提示**：「他坐在靠窗的位置」

**触发条件**：步骤 1 完成。

**判定逻辑**：
```
玩家执行 PlayerAction.leaveSeat（起身）
  → 视角切换为第三人称（教室内移动）
  → 玩家移动到江越座位热点（后排靠窗）
  → 确认交互
```

**执行逻辑**：
1. 桌面特写：同款蓝格笔记本，封面有轻微磨损
2. 内心独白：「是他的本子。纸条是江越写的。」
3. `Ch3State.jiangYueSeatConfirmed = true`
4. `GameNarrativeState.jiangYueLocated = true`
5. 目标更新

---

#### 步骤 3：确认他是不是已经离开

**当前目标 HUD**：「确认他是不是已经离开」

**判定逻辑（两个观察，任意顺序）**：
```
观察 A：玩家点击桌面热点（水杯、书本）
  → 内心独白：「水杯还是满的。书没有合上。他很快就离开的。」
  → 线索 +1

观察 B：玩家切换为 .right 或 .forward 视角，停留 2 秒
  → SceneDirector 播放远处楼梯间门轴声（`AVAudioEnvironmentNode` 后方定位）
  → 内心独白：「……刚才那声，是楼梯间的门吗？」
  → 线索 +1

两个观察均完成 → 步骤完成
```

`Ch3State.jiangYueStatus = .justLeft`

**SceneDirector 兜底**：若玩家 90 秒仅完成一项观察，自动完成另一项并提示：「楼梯间传来短暂的声音。」

---

#### 步骤 4：找一个人一起去

**当前目标 HUD**：「找一个人和你一起去」  
**提示**：「班长在门口，许栀在走廊」

**触发条件**：步骤 3 完成。

**场景**：教室门口可见班长周予安（男生，整理讲台），走廊转角可见许栀（女生，系鞋带）。

**判定逻辑**：
```
玩家走近周予安（≤ 1.5m）并交互 → 选班长
  或
玩家走出教室，走近许栀（≤ 1.5m）并交互 → 选许栀
```

**各选择的立即反应**：

周予安（班长）：
```
「好，我跟你去。」
内心独白：「他不多问，直接跟上来了。有时候这种人反而让人踏实。」
写入：`GameNarrativeState.companionChoice = .zhouYuAn`
影响预告（不对玩家显示）：
  - 第四章步骤 6：方老师联系更快
  - 第四章步骤 2：周予安表达偏直接，可能给江越更多压力
```

许栀（文体委员）：
```
「……他在楼梯间？」停顿，「我跟你去，我不多说话。」
内心独白：「她懂得不说多余的话，这很难。」
写入：`GameNarrativeState.companionChoice = .xuZhi`
影响预告：
  - 第四章步骤 2：江越更容易留下
  - 第四章步骤 6：成人交接需要多一步
```

同行者选择通过一次 `completeStep` 直接写入全局权威字段，不在 `Ch3State` 复制保存。

---

#### 步骤 5：去楼梯间

**当前目标 HUD**：「去楼梯间」

**SceneDirector 节拍**：同行者自动跟随，走廊内环境音变化（人声减少，脚步声更清晰）。

**判定逻辑**：玩家（+同行者）移动到楼梯间入口 → 章节结束动画 → 第四章开始。

### 3.4 章节结束条件

`Ch3State.jiangYueSeatConfirmed && GameNarrativeState.companionChoice != .none` 且到达楼梯间入口。

### 3.5 UI 规格

- 第三章启用第三人称视角（教室内移动）
- 班干部 NPC 有简短的名字标牌（悬停时显示，选择后消失）
- 同行者跟随时，屏幕右下角有小图标显示「同伴：周予安/许栀」

### 3.6 代码映射

| 功能 | 说明 |
|---|---|
| 教室内第三人称移动 | 在 `ClassroomCoordinator` 新增 `.guidedThirdPerson` 相机映射；复用现有 `StudentFreeRoamState`、移动、碰撞和鼠标输入，只新增相机跟随偏移与遮挡处理 |
| 班干部 NPC | 新增 `CompanionNPC`（周予安、许栀），各有 idle 动画和跟随逻辑 |
| 同伴跟随 | `CompanionFollowBehavior`：与玩家保持 1.5m，路径跟随 |


---

## 第四章：13楼的缝隙

### 4.1 章节状态变量

```swift
struct Ch4State: Codable, Equatable {
    var jiangYueFoundAndSeated: Bool = false
    var iceBreakSuccess: Bool = false     // 江越愿意留下
    var listenPhaseComplete: Bool = false
    var riskAskMethod: RiskAskMethod = .none
    var adultContactInitiated: Bool = false
    var safetyHandoffComplete: Bool = false
}

enum RiskAskMethod: String, Codable {
    case none
    case gentle    // 「你说的算了是什么意思？」
    case direct    // 「你有没有想过伤害自己？」
    case deferToAdult // 玩家不继续追问，明确交由成人接手
}
```

### 4.2 进入条件

从第三章楼梯间入口触发，同行者跟随进入。课间时间开始计时（10 分钟倒计时，屏幕右上角极小数字显示，剩余 2 分钟变暖红色）。

**HUD 主线任务**：「让江越知道，他不是一个人」

### 4.3 步骤详细流程

---

#### 步骤 1：在楼梯间找到江越

**当前目标 HUD**：「在楼梯间找到江越」

**SceneDirector 节拍**：
- 楼梯间场景：昏暗，顶灯一盏，角落有光透过窗户
- 江越坐在台阶转角，耳机挂在脖子上，听见脚步声后抬头、想起身

**判定逻辑**：
```
玩家（+同行者）进入楼梯间场景（自动进入）
  → 看见江越（视野内出现 NPC）
  → 写入 `Ch4State.jiangYueFoundAndSeated = true`
  → 自动完成，进入步骤 2
```

**同行者行为**（自动，无需玩家操作）：
- 周予安：停在楼梯入口，不靠近，但可见
- 许栀：退后两步，站在角落，给空间

---

#### 步骤 2：先让他愿意留下来

**当前目标 HUD**：「先让他愿意留下来」  
**提示**：（苏念内心独白，非 HUD）「别急着说纸条的事。」

**触发条件**：步骤 1 完成后，视角切换为第一人称（对话空间）。

**对话选项**（3选1）：

| 选项 | 文字 | 江越反应 | iceBreakScore |
|---|---|---|---|
| A | 「你最近怎么了？」 | 「没什么。」想起身 | 0（防御启动） |
| B | 「我最近也挺累的。」 | 没走，重新坐下，看了她一眼 | +2 |
| C | 「你介意我在这里待一会儿吗？」 | 「……随便。」 | +3（尊重边界） |

**判定逻辑**：
```
iceBreakScore >= 2 → iceBreakSuccess = true，继续步骤 3
iceBreakScore == 0（选 A）：
  → 江越起身要走
  → SceneDirector 触发补救：同行者从侧面说「先别走」
  → 给玩家第二次选择（只剩 B、C 两个选项）
  → 第二次任意选择 → iceBreakSuccess = true（稍低信任）
```

**补救说明**：补救成功后 `jiangYueTrustValue` 基础值降低 10，但主线不断。

---

#### 步骤 3：听他说完

**当前目标 HUD**：「听他说完」  
**提示**：「不急着回应，先听。」

**触发条件**：`iceBreakSuccess == true`。

**江越的四段独白**（自动依次播放，每段间隔约 5 秒）：

```
段落 1：「高中……不太想去了。」
段落 2：「我爸妈说我就是矫情，说别的同学没这些毛病。」
段落 3：「最近睡不着，凌晨两点还在想乱七八糟的事。」
段落 4：「有时候觉得……算了吧。」
```

每段播放后，玩家有 **15 秒**选择一个回应（不选则自动选「沉默倾听」）：

回应类型和信任值影响：

| 回应类型 | 例子 | `jiangYueTrustValue` |
|---|---|---|
| 评判式（🔴） | 「其实你爸妈也是为你好」 | -10 |
| 鸡汤式（🔴） | 「振作一下就好了」 | -5 |
| 建议式（🟡） | 「你试过运动吗？」 | ±0 |
| 倾听式（🟢） | 「听起来你撑了很久了。」 | +10 |
| 陪伴式（🟢） | 「我在听。」 | +8 |
| 安静陪着（主动选项） | 「我先陪你坐一会儿。」 | +5 |
| 超时未选择 | （苏念没有接话，江越继续说） | +1；连续两次超时后显示更明确的操作提示 |

**`listenPhaseComplete`**：四段全部播放后，无论信任值多少，自动标记完成。

`jiangYueTrustValue` 初始值：
- 第一章完成两条明确观察并捡到纸条：+10 基础
- 第二章 `linCheListenScore >= 3`：+5（苏念练习过倾听）
- 第三章选许栀同行：+8；选班长：+3

---

#### 步骤 4：确认「算了吧」是什么意思

**当前目标 HUD**：「确认'算了吧'是什么意思」

**触发条件**：步骤 3 完成，「算了吧」被说出后。

**教育便签**（一次性，在选择前出现，玩家确认后关闭；不得在未读完时按固定 5 秒自动消失）：
```
「直接问'你有没有想过伤害自己'不会给对方植入这个想法。
 研究显示，直接询问不会增加自杀想法或行为。
 问完之后仍需要陪伴、帮助保持安全，并联系可信成人和专业支持。」
```

**对话选项**（3选1）：

| 选项 | 文字 | 方法类型 | 后续效果 |
|---|---|---|---|
| A | 「你说的'算了'……是什么意思？」 | gentle | `jiangYueTrustValue >= 40` 时江越会回答 |
| B | 「我需要直接问你：你有没有想过伤害自己？」 | direct | 信任较高时更可能得到明确披露，但任何回答都不能代表真实风险降低 |
| C | 「如果你现在不想说也可以。我还是想找一个可靠的大人来。」 | deferToAdult | 不继续追问，由成人接手；不得出现“没事”式淡化 |

**江越的回应判定**：

```swift
func jiangYueDisclosure(method: RiskAskMethod, trust: Double) -> RiskDisclosure {
    switch method {
    case .direct where trust >= 60:
        return .confirmed // 「有想过。现在很累。」
    case .gentle where trust >= 40:
        return .partial   // 「有时候不想继续想这些了。」
    default:
        return .unknown   // 只表示苏念没有获得信息
    }
}
```

选择后以一次 step commit 写入 `Ch4State.riskAskMethod` 与 `GameNarrativeState.disclosedRisk`。`jiangYueActualRisk` 是编剧设定的剧情事实，主线默认 `.moderate`，不由信任值、问法或玩家选择计算，也不显示给玩家。

**所有披露状态的共同安全规则**：
- `.unknown`：HUD 更新为「他不想说，但我不能假装没听见。让可靠的大人过来。」
- `.partial/.confirmed`：HUD 更新为「谢谢他愿意说。现在找一个可靠的大人一起承担。」
- 江越在成人到场前不得被单独留下；同行者只负责在附近陪伴和联络，不负责评估风险。
- 玩家不能通过继续刷对话把 `.unknown` 强行变成 `.confirmed`。
- 若编剧状态为 `.high/.imminent`，隐藏课间倒计时并立即进入学校审核过的紧急流程：留在安全区域、移除可见危险因素、联系方老师/心理老师；存在即时人身危险时由成人联动 120/110。该路线不得以普通步行过场处理。

---

#### 步骤 5：告诉他不用一个人扛

**当前目标 HUD**：「告诉他：这件事不用一个人扛」

**触发条件**：`GameNarrativeState.disclosedRisk == .partial || GameNarrativeState.disclosedRisk == .confirmed`。此步骤表达感谢和陪伴，不承担风险评估。

**SceneDirector 节拍**：预备铃响（倒计时剩余约 2 分钟）；同行者收到方老师联系方式（NPC 短暂看手机动作）。

**对话选项**（2选1）：

| 选项 | 文字 | 效果 |
|---|---|---|
| A | 「我想带你去找方老师，一起去好吗？」 | `jiangYueTrustValue >= 50`：写入 `jiangYueWillingToGo = true`、路径 `.voluntary`；< 50：写入 false，步骤 6 由成人过来 |
| B | 「你能不能让我去请方老师来？」 | 任何信任值都有效；江越「……好」；写入 `jiangYueWillingToGo = false` 与 `.adultCameAfterLowTrust` |

两个选项均推进主线，差别是江越是否主动同行（影响第五章开场动画）。选择 B 写入 `jiangYueWillingToGo = false`，由成人来到现场。若披露为 `.unknown`，直接进入步骤 6，并在成人联系成功时写入路径 `.adultCameAfterUnclearDisclosure`；已披露但拒绝同行时写入 `.adultCameAfterLowTrust`。

---

#### 步骤 6：让可靠的大人接手

**当前目标 HUD**：「让可靠的大人接手」

**同行者行为**（根据选择自动触发）：

进入本步骤时先写入 `Ch4State.adultContactInitiated = true`。该字段表示已经发出联系请求，不表示成人已经到场。

选班长（周予安）：
- 直接拨打方老师电话，方老师 30 秒内到达楼梯间
- 优点：速度快；代价：江越可能稍感「被安排」

选许栀（许栀）：
- 发消息并说明需要方老师到楼梯间；许栀留在远处维持空间
- 优点：空间感更好；代价：到达提示更克制，不由学生带江越去办公室

成人必须来到江越所在位置完成首次接管，不能要求未成年人在接管前承担转运责任。

**安全路线由编剧风险事实决定，与信任分无关**：

| `jiangYueActualRisk` | 写入 `safetyRoute` | 第五章入口模式 |
|---|---|---|
| `.low/.moderate` | `.standardCounseling` | `.standardWaiting` |
| `.high` | `.urgentSchoolResponse` | `.urgentHandoffWaiting` |
| `.imminent` | `.emergencyServices` | `.emergencyClosure` |

成人到场后，以一次原子提交写入 `adultNotified`、`safetyRoute`、对应入口模式和路径事实。若此前是 `.unknown`，路径固定为 `.adultCameAfterUnclearDisclosure`；否则保留 `.voluntary` 或 `.adultCameAfterLowTrust`。任何路线不得让默认值 `.standardCounseling` 代替实际决策结果。

**方老师到达/等候时的台词**（自动播放，玩家只需「在场」）：
> 「江越，我听说你最近有些辛苦。我们能说说吗？」（不提「谁告诉我的」）

**玩家操作**：无需对话选择，仅需「在场」——玩家保持原位或向前走均可。

`GameNarrativeState.adultNotified = true`。成人明确说出「接下来由我们来处理，你们不用自己扛」后，写入 `Ch4State.safetyHandoffComplete = true`。成人到场后由经专业审核的脚本决定普通支持或紧急响应；学生角色不执行临床判断。

---

#### 步骤 7：跟着大人的安排走

**当前目标 HUD**：普通路线为「跟方老师走到咨询室门口」；高风险路线为「留在这里，等老师确认安排」；即时危险路线为「退到安全位置，听老师安排」。

**SceneDirector 节拍与完成点**：

| `safetyRoute` | 自动场景 | 玩家受限目标 | 完成后第五章模式 |
|---|---|---|---|
| `.standardCounseling` | 方老师与江越并排前往咨询室，苏念跟随 | 沿单一路径跟随；30 秒不动时苏念自动跟上 | `.standardWaiting` |
| `.urgentSchoolResponse` | 方老师留在现场，心理老师/校方值班人员到场，江越由成人陪同 | 只能留在标记安全区域，不得追问或单独带离 | `.urgentHandoffWaiting` |
| `.emergencyServices` | 成人启动学校紧急流程并负责联络监护人与 120/110；画面不展示处置细节 | 后退到安全办公室/走廊锚点，等待成人说出交接确认 | `.emergencyClosure` |

三条路线都必须先持久化 `safetyRoute` 与对应 `CounselingEntryMode`，再提交章节转换；不得先切场景、后补状态。

### 4.4 章节结束条件

`Ch4State.adultContactInitiated == true && Ch4State.safetyHandoffComplete == true`，且 `safetyRoute` 已映射为第五章入口模式。普通路线还需到达咨询室门口；高风险/即时危险路线以成人明确接管并启动相应流程作为完成点。

**不可卡关保证**：
- 步骤 2 最多两次机会后自动通过
- 步骤 4 选 C（逃避）→ 兜底路径，方老师仍会出现
- 倒计时归零但主线未到步骤 6 → SceneDirector 自动触发：许栀/班长联系方老师

### 4.5 UI 规格

- **信任值**：对玩家不可见，仅通过江越的表情/肩膀/声音体现
- **倒计时**：屏幕右上角极小数字（字号 11pt，透明度 60%），剩余 2 分钟时颜色从白→暖橙（非红色，避免恐慌感）
- **教育便签**：出现在选择框上方，独立卡片，由玩家确认关闭；可暂停，不按固定阅读时间消失
- **风险等级**：不在 UI 上显示任何「危险」标签，仅通过江越反应和方老师态度传递

### 4.6 代码映射

| 功能 | 说明 |
|---|---|
| 倒计时系统 | `CountdownTimer(duration: 600)`，SwiftUI overlay |
| 信任值系统 | `DialogueTrustReducer` 纯函数，结果写回 `GameManager.narrative`；不创建可观察单例 |
| 江越对话状态机 | `JiangYueDialogueStateMachine`，4段 + 响应 + 追问 |
| 披露状态 | `DisclosureResolver.resolve(method:trust:)`，只决定玩家获得多少信息，不输出真实风险 |
| 安全响应 | `SafetyHandoffPolicy` 读取编剧风险事实和成人接管状态；策略文本必须经专业审核 |
| 方老师介入动画 | `TeacherArrivalSequence`：移动路径 + 台词 overlay |
| 兜底路径切换 | `Ch4FallbackDirector`：信任不足时接管步骤推进 |


---

## 第五章：有灯亮着的房间

### 5.1 章节状态变量

```swift
struct Ch5State: Codable, Equatable {
    var entryMode: CounselingEntryMode = .standardWaiting
    var handoffSceneStarted: Bool = false
    var jiangYueEntered: Bool = false    // 仅标准等候路线使用
    var boundaryHeld: Bool = true        // 是否保持了「不偷听」边界
    var rumorHandled: Bool = false       // 是否处理了流言
    var rumorOutcome: RumorOutcome = .unknown
    var companionMessageReplied: Bool = false
    var jiangYueExited: Bool = false     // 仅标准等候路线使用
    var handoffConfirmed: Bool = false   // 三种路线共用完成门禁
    var farewellChoice: FarewellChoice?
}

enum RumorOutcome: String, Codable {
    case unknown
    case suppressed     // 成功压下，班级氛围稳定
    case contained      // 部分控制，后续有余波
}
```

### 5.2 进入条件

第四章完成安全交接后自动进入，并从已持久化的 `safetyRoute` 唯一映射 `entryMode`。若二者不一致，读档校验拒绝继续并恢复最后有效检查点，不得默认落入普通咨询路线。

**HUD 主线任务**：「把支持留在他身边」

### 5.3 步骤详细流程

---

#### 步骤 1：看清大人怎样接手

**当前目标 HUD**：「确认现在由谁陪着他」

**SceneDirector 分流**：
- `.standardWaiting`：咨询室门虚掩，心理老师接待，方老师留在门外。
- `.urgentHandoffWaiting`：安静支持室外，方老师与心理老师明确轮班陪同和下一步校内安排；不表现具体评估内容。
- `.emergencyClosure`：安全办公室/走廊锚点，方老师确认紧急服务已接手或正在到场、江越始终由成人陪同；江越不再出镜，不展示转运细节。

**判定逻辑**：
```
标准路线中江越进入场景后：
  若 jiangYueTrustValue >= 50（自愿同行）：
    → 江越主动推开门，心理老师说「进来吧。」
  若 jiangYueTrustValue < 50（不情愿）：
    → 方老师轻声说「一起进去坐一下就好了。」
    → 江越停顿 3 秒，然后进去
```

标准路线写入 `jiangYueEntered = true`；另两条路线在成人说出“接下来由我们陪着他”后完成。三条路线都写入 `handoffSceneStarted = true`。

---

#### 步骤 2：把接下来的空间留给大人

**当前目标 HUD**：「把里面的时间留给他」  
**提示**：「不用追进去，留在指定位置就好」

**判定逻辑**：
```
标准路线门合上后：
  玩家若尝试走近门口（≤ 0.5m 且停留 ≥ 3s）：
    → 内心独白：「这里面是他的时间，不是我的。」
    → 轻微视角推开（camera pull-back 动画，0.3s）
    → 边界维持，boundaryHeld 不变

玩家走向等候椅（距离 ≤ 2m）：
    → 自动坐下，视角切换为固定等候视角（类第一章固定座位）
    → 步骤 2 完成

高风险路线：玩家走到支持室外等候锚点即完成；靠近门时同样触发边界提示。即时危险路线：玩家保持在安全办公室外标记区 5 秒即完成，不提供靠近、偷听或追随热点。
```

**标准/高风险等候区固定视角内容**：
- 正前方：咨询室关着的门
- 左侧：一排书架（可点击查阅 2 本，触发科普便签）
- 右侧：走廊，偶尔有同学路过

---

#### 步骤 3：别让这里变成围观的地方

**当前目标 HUD**：「别让门口变成围观的地方」

**触发条件**：标准/高风险路线坐下约 1 分钟后，SceneDirector 自动触发流言事件；即时危险路线不生成围观 NPC，改为方老师提醒「先别在群里讨论刚才的事」。

**场景**：两名同学（NPC 陈言 + 另一同学）路过，小声议论。玩家在等候视角能用余光感知（右侧边缘亮起低强度光晕）。

**对话选项**（2选1，时间窗口 20 秒，超时自动选 B）：

| 选项 | 文字 | 后果 |
|---|---|---|
| A | 「方老师在处理一件事，不用担心。」（平静，不透露信息） | `rumorOutcome = .suppressed`，两名同学离开，不再议论 |
| B | （不回应，低头）| `rumorOutcome = .contained`，议论持续几秒后自行散去 |

**若同行者（班长）在场**：
- 周予安（班长）会在玩家选择前主动说「各自去忙吧」，给玩家减轻一步压力
- 若玩家仍不操作，周予安自动完成

`Ch5State.rumorHandled = true`

两种结果均不披露身份或咨询事实，因此保持 `GameNarrativeState.privacyProtected = true`；`rumorOutcome` 只记录班级是否仍有模糊议论。

---

#### 步骤 4：告诉同伴事情已有人处理

**当前目标 HUD**：「告诉同伴：现在已有大人在处理」

**触发条件**：步骤 3 完成后约 30 秒，同行者发来消息（HUD 通知，非手机震动——此处苏念在等候区，无手机）。

**消息内容**（根据同行者）：
- 周予安：「方老师那边怎么说？班里有几个人在问江越去哪了。」
- 许栀：「江越还在里面吗？你要不要先回去，我来等？」

**玩家回复选项**（2选1）：

| 选项 | 文字 | 隐私保护 | 效果 |
|---|---|---|---|
| A | 「有老师在跟进了，谢谢你今天。」 | ✅ | `companionMessageReplied = true`，支持网络稳定 |
| B | 「方老师已经在处理了，具体情况等他自己愿意说。」 | ✅ | 同上，并且周予安/许栀会主动压下班内询问 |

**注**：两个选项都不披露当事人位置、咨询状态或谈话内容。游戏不把泄露隐私设计成供玩家试错的娱乐分支。

---

#### 步骤 5：等大人确认下一步

**当前目标 HUD**：「等门打开」

**执行逻辑**：
1. 标准路线等候约 3 分钟；高风险路线约 90 秒后由心理老师出来确认持续陪同；即时危险路线约 30 秒后由方老师确认紧急交接正在进行。
2. **可选互动**（不影响主线）：
   - 点击书架上的书 → 科普便签触发（见下方偏见碎片设计）
   - 切换 CameraPose 到 `.desk` → 苏念低头，玩家可选「写一句感受」（可选项，不强制）
3. SceneDirector：等候期间环境音渐弱。高风险/即时危险路线不以“门打开、江越状态变好”作为反馈，只由成人给出最小必要确认。

**偏见碎片系统**（在等候期间触发，最多 2 条）：

SceneDirector 在路过 NPC 的余光区域低声说出偏见语句。玩家用 `observe` 行动「注意到」后，触发反驳选项 + 科普便签：

| 偏见语句 | 便签内容（精简版） |
|---|---|
| 「去心理室的人都有病吧」 | 「心理困扰就像感冒，任何人都可能有。去咨询不是有病，是在照顾自己。」 |
| 「说出来有什么用，不会变好的」 | 「说出来不保证问题马上消失，但可能帮助别人理解你正在经历什么，也让支持有机会开始。」 |

---

#### 步骤 6：确认他接下来不会一个人

**当前目标 HUD**：「确认他接下来不会一个人」

**触发条件**：标准路线为门打开、江越在成人陪同下出来；高风险/即时危险路线为负责成人向苏念确认“他现在有人陪，后续由我们处理”。

**SceneDirector 节拍**：
- 心理老师对方老师说几句（听不清内容，只知道有安排）
- 方老师点头，看向苏念：「今天谢谢你。」

**江越的状态（仅标准路线）**：没有戏剧性变化。表情稍轻，走路时肩膀没那么紧绷。另两条路线不让苏念再次接触江越，也不通过外观暗示风险已经解除。

**玩家选项**（2选1）：

| 选项 | 文字 | 结果 |
|---|---|---|
| A | 「你还好吗？」 | 仅标准路线；江越：「……好一点了。」停顿，「谢谢。」；写入 `.checkIn` |
| B | 「先回去。需要的时候，我们可以一起找老师。」 | 仅标准路线；江越轻轻点头；写入 `.findTeacherTogether` |

高风险/即时危险路线不显示这组选项；玩家按确认键回应方老师「我知道了」，完成的是交接确认，不是假定危机已解决。

两种均完成主任务。

标准路线选择完成后写入 `farewellChoice` 与 `jiangYueExited = true`；三条路线都在成人确认后写入 `handoffConfirmed = true` 和 `GameNarrativeState.supportHandedOff = true`。这些字段与 HUD 完成反馈由同一次幂等 step commit 提交。

**完成反馈**（主线 HUD 更新）：

```
主线完成
现在已经有可靠的大人在接手。
```

停留 3 秒后显示第二行较小文字：

```
接下来未必立刻变轻松，
但不再只由学生承担。
```

`GameNarrativeState.supportHandedOff = true`（由上述 step commit 写入，此处不重复提交）

### 5.4 章节结束条件

`Ch5State.handoffConfirmed == true` 且 `GameNarrativeState.supportHandedOff == true`。`jiangYueExited` 只用于标准路线表现，不是全局门禁。

自动触发第六章入口：苏念独自走向走廊的大镜子。

### 5.5 UI 规格

- 等候区视角：固定坐姿，可切换 left/right/board/desk，不可 leaveSeat
- 「主线完成」反馈：非弹框，是 HUD 区域文字平滑替换，字体略大，保持 8 秒后收起
- 偏见便签：左侧滑入，不覆盖中央视野，5 秒或玩家点击后消失

### 5.6 代码映射

| 功能 | 说明 |
|---|---|
| 等候区固定视角 | 复用第一章 `CameraPose` 固定座位逻辑，场景换为等候区 |
| 流言事件 | `RumorEventDirector`：NPC 路过 + 对话气泡 + 选项 |
| 偏见便签 | `BiasCardSystem`：左侧滑入卡片，复用第一章 `InnerMonologue` 触发逻辑 |
| 主线完成反馈 | `QuestCompleteHUD`：SwiftUI 文字替换动画 |


---

## 第六章：这里有光

### 6.1 章节状态变量

```swift
struct Ch6State: Codable, Equatable {
    var mirrorApproached: Bool = false
    var counselingEntered: Bool = false
    var chosenTopicIDs: [String] = []
    var networkViewed: Bool = false
    var resourceConfirmed: Bool = false
}
```

### 6.2 进入条件

第五章主线完成后，苏念独自走向走廊大镜子（约 15 秒过渡动画）。

**HUD 主线任务**：「别忘了你自己」

### 6.3 步骤详细流程

---

#### 步骤 1：走到镜子前

**当前目标 HUD**：「走到那面镜子前」

**SceneDirector 节拍**：
- 走廊安静，只有远处空调声
- 镜子里映出疲惫的苏念——肩膀微低，头发稍乱

**判定逻辑**：玩家走近镜面（≤ 1m）→ 写入 `Ch6State.mirrorApproached = true` → 镜面边缘出现淡金色光晕（同第二章进入镜像的视觉语言，但这次没有冷色调变换）。

**文字出现**（屏幕中央，手写字体）：「你也可以走进去。」

---

#### 步骤 2：走进咨询室

**当前目标 HUD**：「走进咨询室」

**判定逻辑**：
```
玩家按确认键（靠近镜面时）
  → 镜面轻微涟漪动画（非第二章的色温翻转，而是柔和波纹）
  → 场景切换为咨询室内部
  → 门没有关严，心理老师抬头
```

**心理老师台词**（自动播放，不可跳过）：
> 「进来吧。你不需要先证明自己够严重。想从哪里说都可以。」

随后必须播放经专业人员与学校审核的保密边界脚本，至少清楚说明：谈话通常会被尊重和保护；如果涉及苏念或他人正在面临严重、即时的安全风险，老师需要联系能够保护她的人，并尽量提前告诉她会联系谁。该脚本是 Release 必需资源，不是可选对白；未配置审核版本时 Release 构建失败。

`Ch6State.counselingEntered = true`

---

#### 步骤 3：说一件自己的事

**当前目标 HUD**：「决定今天想说多少」

**对话选项**：玩家可以先选择「今天先坐一会儿」，也可以选择 1-2 个主题；每个主题只能选择一次。选择第一个主题后出现「继续说一件」与「先到这里」两个明确命令。

| 主题 | 苏念说 | 老师回应类型 | 影响 |
|---|---|---|---|
| 父母关系 | 「我爸妈最近关系不太好，我不知道怎么办。」 | 倾听式 | `suNianSharedSelf = true` |
| 学业疲惫 | 「我有时候感觉很累，但说不清楚为什么。」 | 倾听式 | `suNianSharedSelf = true` |
| 害怕帮不好 | 「我不知道今天我做的事有没有真的帮到他。」 | 确认式（「你做到了你能做的。」） | `suNianSharedSelf = true` |
| 只是想说说 | 「我就是……想说一下。没别的事。」 | 倾听式 | `suNianSharedSelf = true` |
| 今天先坐一会儿 | 「我现在还不知道怎么说。」 | 确认边界：「可以。坐一会儿也可以。」 | `suNianSharedSelf = false` |

**老师回应类型定义**：
- 倾听式：「嗯。然后呢？」「这让你感觉怎么样？」
- 确认式：「你今天做的事，不是每个人都做得到的。你愿意来这里，也需要勇气。」

**完成条件**：玩家选择「今天先坐一会儿」，或至少选择 1 个主题后选择「先到这里」，或完成 2 个主题。每次选择主题时以具名 ID 追加到 `Ch6State.chosenTopicIDs`，先检查去重与最多 2 项；只有实际表达主题时设置 `suNianSharedSelf = true`。老师不给诊断或万能建议，但可以说明保密边界、确认感受并邀请后续支持。

---

#### 步骤 4：看看今天留下的支持

**当前目标 HUD**：「看看今天留下的支持」

**触发条件**：步骤 3 完成后，老师按学校配置说「如果还想来，可以在开放时间过来，或者按这个方式预约。」苏念走出咨询室，画面淡出。不得承诺未配置的“随时可用”。

**执行逻辑**：切换为支持网络回顾界面（SwiftUI 全屏 overlay，风格类手写笔记）。

**支持网络图结构**：

```
苏念
├── 林澈（关系强度：由 linCheListenScore 决定）
│     状态文字：「你帮他看见了自己」或「你在他身边待了一会儿」
├── 江越（今天建立的连接）
│     状态文字：「今天他知道有人注意到了他」
├── 周予安/许栀（本局协作者）
│     状态文字：「今天你没有一个人扛」
├── 方老师（成人支持）
│     状态文字：「他知道班里的情况了」
└── 心理老师（今天刚建立的连接）
      状态文字：「这里有灯亮着」
```

节点逐一点亮（500ms 间隔，从苏念向外扩散），每个节点有柔和光晕。

玩家点击任意节点 → 展开一段两行文字（本局选择的具体痕迹），不强制全部查看。

`Ch6State.networkViewed = true`

---

#### 步骤 5：记住下一次可以去哪里

**当前目标 HUD**：「记住下一次可以去哪里」

**触发条件**：玩家关闭支持网络界面（或查看 10 秒后自动继续）。

**执行逻辑**：
1. 支持网络界面收起，切换为结局卡片（全屏，深色背景，暖色文字）
2. 结局文字（根据全局选择选择版本，见 §6.4）
3. 结局文字停留约 5 秒后，出现「真实求助资源」卡片

**求助资源卡片**（固定内容，不随机）：
```
如果你或你认识的人需要帮助：

全国统一心理援助热线
12356
服务时间以所在地接听安排为准

如存在正在发生的人身危险
请立即联系现场可信成人，并拨打 120 或 110

学校心理咨询室
开放时间和预约方式以学校实际信息为准
```

资源来源与更新规则：
- `12356` 依据国家卫生健康委《关于应用“12356”全国统一心理援助热线电话号码的通知》（国卫医政函〔2024〕259号）。
- 热线、学校资源和服务时间不得散落硬编码在 View 中；统一由 `SupportResourceCatalog` 读取带 `reviewedAt`、`region`、`sourceURL` 的本地配置。
- 发布构建前必须检查资源审核日期；超过 6 个月未复核时阻止 Release 打包，但不阻止 Debug 构建。

玩家点击「确认」→ `Ch6State.resourceConfirmed = true` → 游戏结束，回到主菜单（解锁内容）。

### 6.4 多结局文字

根据关键选择组合，结局文字在语气和细节上有差异。`EndingSelector` 必须按下列顺序命中第一条主结局，再叠加自我照顾附注，避免多个条件同时满足时结果不确定：

| 触发条件 | 结局名 | 核心文字 |
|---|---|---|
| 1. `safetyRoute == .emergencyServices` | 「已经有人接手」 | 「你没有负责解决一切。你做的是让可靠的大人及时接住接下来的事。」 |
| 2. `safetyRoute == .urgentSchoolResponse` | 「把事情交出去」 | 「陪伴不是独自承担。今天，接下来的重量已经交给能够负责的大人。」 |
| 3. `jiangYueResolutionPath == .voluntary && suNianSharedSelf` | 「今天不一样了」 | 「有些改变从开口开始。不管是他，还是你。」 |
| 4. `jiangYueResolutionPath == .adultCameAfterUnclearDisclosure` | 「不知道，也要行动」 | 「他没有把一切说清楚。你没有把沉默当成没事，而是找来了能够接手的人。」 |
| 5. `jiangYueResolutionPath == .adultCameAfterLowTrust` | 「你做了你能做的」 | 「不是每一次尝试都能立刻得到回应。但今天，责任不再只落在学生身上。」 |
| 6. `suNianSharedSelf == false` | 「下次也可以」 | 「今天你先坐了一会儿。门没有关上，你可以按自己的速度再来。」 |
| 7. 其余已完成普通路线 | 「这里有光」 | 「有人发现，有人开口，也有人接手。支持不是一个人的任务。」 |
| 附注：`suNianSelfCared == false` | 在上述任一主结局后追加 | 「记得照顾自己。帮助别人的人，自己也需要被接住。」 |

### 6.5 章节结束条件

`Ch6State.resourceConfirmed == true`

### 6.6 UI 规格

- **支持网络图**：SwiftUI Canvas，节点为圆形，连线为虚线，点亮动画 `withAnimation(.spring(duration: 0.5))`
- **结局卡片**：深色背景（`Color(white: 0.08)`），文字白色，行间距 1.6，无装饰元素，专注文字
- **求助资源卡片**：同结局卡片风格，热线号码字号略大（16pt）；提供明确的复制按钮和 `NSPasteboard` 实现，不依赖移动端长按手势

### 6.7 代码映射

| 功能 | 说明 |
|---|---|
| 支持网络图 | 新增 `SupportNetworkView: View`，从 `GameNarrativeState` 读取节点强度 |
| 结局选择逻辑 | `EndingSelector.select(state: GameNarrativeState) -> EndingType`，纯函数 |
| 求助资源 | `SupportResourceCatalog` + `SupportResourceView`，使用 `NSPasteboard` 复制并校验审核日期 |
| 心理老师对话 | `CounselorDialogueSystem`：多主题独立回应，不依赖信任值 |


---

## 全局系统详细设计

### A. SceneDirector 与唯一状态源

`GameManager` 继续作为唯一可信状态源。`SceneDirector` 是 `GameManager` 的内部协作者，只保存计时运行态；`ContentView` 和 `ClassroomCoordinator` 只消费 `GameManager` 发布的纯数据。

以下是接口契约，不要求另建一套实现类；现有 `GameManager` 直接实现该协议并保留实际存储属性：

```swift
@MainActor
protocol NarrativeQuestManaging: AnyObject {
    var quest: MainQuestProgress { get }
    var narrative: GameNarrativeState { get }
    var scenePresentation: ScenePresentationState { get }
    var activePauseReasons: Set<PauseReason> { get }

    func completeStep(_ stepID: String, result: QuestStepResult)
    func startChapter(_ chapter: ChapterID)
    func addPauseReason(_ reason: PauseReason)
    func removePauseReason(_ reason: PauseReason)
}
```

现有 `GameManager` 内部持有唯一的 `SceneDirector` 和 `QuestCatalog`。不得把协议示例复制成第二个 `GameManager`，也不得使用 `Bool` 暂停接口覆盖其他来源的暂停。

现有 `GameState` 继续表达 `.menu/.playing/.event/.ending`；六章不扩展成六个新的 `GameState` case。当前章节与步骤由 `quest` 表达，`.event` 只作为覆盖层暂停当前章节，关闭后回到同一步骤。

必须满足：
- `completeStep` 幂等；玩家操作与 fallback 同时命中时只写入一次。
- `.event`、暂停菜单、应用失焦、系统休眠分别维护集合项；`activePauseReasons` 非空时冻结叙事时间，单一来源恢复不得误解冻其他来源。
- 章节切换、返回菜单、读档时取消旧章 Task/Timer。
- SceneKit 节点只由 `ClassroomCoordinator.update(game:)` 单向映射；导演不得直接持有节点。
- 恢复存档时按 `activeBeatIDs` 和已完成 ID 重建计时器，不保存闭包或 Timer。
- 第四章进入高危/紧急路线后，安全响应 Beat 优先于普通剧情 Beat，并取消普通倒计时。

### B. MainQuestHUD 组件

```swift
struct MainQuestHUD: View {
    let progress: MainQuestProgress
    let currentHUDItem: QuestHUDItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 主线任务（常驻）
            Text(currentHUDItem.mainTask)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.5))

            // 当前目标（醒目）
            Text(currentHUDItem.currentGoal)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(currentHUDItem.isUrgent ? .orange : .white)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .opacity
                ))

            // 引导提示（可选）
            if let hint = currentHUDItem.hint {
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .liquidGlassPanel(cornerRadius: 8)
        .frame(maxWidth: 220, alignment: .leading)
        // 固定在屏幕左侧中部
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .centerLeft)
        .padding(.leading, 16)
    }
}
```

**目标切换动画**：目标文字用 `withAnimation(.easeInOut(duration: 0.3))` 切换，旧目标淡出后新目标从下方滑入。

### C. 章节间状态传递与存档

不得创建 `NarrativeStateManager.shared`。章节状态使用具名枚举封装并由 `GameManager` 持有，禁止 `Any`：

```swift
enum ChapterRuntimeState: Codable, Equatable {
    case classroom(Ch1State)
    case mirror(Ch2State)
    case noteTrace(Ch3State)
    case stairwell(Ch4State)
    case counseling(Ch5State)
    case epilogue(Ch6State)
}

struct NarrativeSave: Codable {
    let schemaVersion: Int
    let saveRevision: Int
    var checkpointID: String
    var quest: MainQuestProgress
    var narrative: GameNarrativeState
    var chapterState: ChapterRuntimeState
    var scenePresentation: ScenePresentationState
    var pendingBeatRemainingTimes: [String: TimeInterval]
    var activePauseReasons: Set<PauseReason>
}
```

- 自动存档时机：每个步骤完成后、章节切换前、应用进入后台时。步骤结果、章节状态、场景检查点和 Beat 剩余时间必须在同一事务快照中编码；不允许先写奖励再异步补场景。
- 存档采用独立 key `LateStudySimulator.NarrativeSave.v1`，不得覆盖现有 `ClassmateMemory.v1`。
- 同时保留 `current` 与 `lastValid` 两个槽。只有完整编码、解码回读并通过不变量校验后，才把新快照提升为 `lastValid`。
- 载入时先按 `schemaVersion` 运行显式迁移器，再校验 `quest.currentChapter`、`chapterState` case、`scenePresentation.chapter`、入口模式和安全路线相互一致；未知的新版本不得猜测解码。
- 解码、迁移或校验失败时保留跨局同学记忆，优先恢复 `lastValid`；若也不可用，才从当前章合法入口重建，并显示一次非阻塞提示。
- `checkpointID` 必须映射到可重建的场景锚点、NPC阶段、相机模式和互动热点集合。SCNNode、动画闭包、Timer 不进入存档，由 Coordinator 依据检查点确定性重建。
- 恢复时不沿用保存瞬间的 `.appInactive/.systemSleep`；先移除生命周期暂停项，再根据当前应用状态重新添加。用户暂停和事件覆盖状态按产品规则恢复。
- 章节状态提交采用 `switch ChapterRuntimeState`，不得使用运行时类型转换。

### D. 时长控制

各章设置**软上限时长**，超时后 SceneDirector 加速推进（非强制跳过，而是提高自动触发频率）：

| 章节 | 软上限 | 超时行为 |
|---|---|---|
| 第一章 | 15 分钟 | 各步骤 30 秒强化目标、90 秒执行本步骤合法兜底；章节守护 Beat 不越级跳步 |
| 第二章 | 18 分钟 | 单个微游戏两次提示后提供“由苏念完成”按钮，不自动伪造玩家输入 |
| 第三章 | 10 分钟 | 45 秒未找到热点时显示明确路径光和相机引导 |
| 第四章 | 18 分钟 | 普通路线自动联系方老师；紧急路线立即取消倒计时并接管 |
| 第五章 | 15 分钟 | 标准路线压缩等候事件；高风险/即时危险路线按成人确认 Beat 收束，不等待咨询室门或江越再次出现 |
| 第六章 | 10 分钟 | 支持网络图自动展示，但求助资源必须由玩家确认 |

软上限合计 86 分钟，符合完整体验不超过约 90 分钟的目标。

### E. 六章场景与相机架构

完整六章继续使用现有 `ClassroomCoordinator`，逐步扩展其场景映射职责，不在首版重命名该类型，也不创建六个互相拥有状态的 Coordinator。场景资源按章分组，任一时刻只激活当前章根节点及转场所需的相邻根节点。

```swift
enum NarrativeCameraMode: Codable, Equatable {
    case seatedFirstPerson
    case freeRoamFirstPerson
    case guidedThirdPerson
    case dialogueFirstPerson
    case mirrorFirstPerson
    case waitingSeated
}

struct ScenePresentationState: Codable, Equatable {
    var chapter: ChapterID = .classroom
    var cameraMode: NarrativeCameraMode = .seatedFirstPerson
    var activeSceneRootID: String = "classroom"
    var transition: SceneTransition?
    var objectiveTargetID: String?
}

enum SceneTransition: Codable, Equatable {
    case fade(duration: TimeInterval)
    case colorTemperatureFlip(duration: TimeInterval)
    case mirrorRipple(duration: TimeInterval)
}
```

- 第一章沿用现有固定座位第一人称和 270° 坐姿视角限制。
- 第二、三、四章的行走统一使用 WASD、确认键 `E`、鼠标视角；第三人称只改变相机跟随方式，不再实现另一套碰撞与输入系统。
- 对话时冻结位移但不冻结环境动画和受控 SceneDirector Beat。
- 镜像空间作为走廊场景中的独立节点根，通过可见性、灯光和材质切换实现；不得复制整个 `SCNScene`。
- 等候区复用固定坐姿控制，但使用独立相机锚点和受限视角配置。
- SwiftUI 只展示 HUD、对话和微游戏 overlay；所有 SCNNode 创建、显示和动画仍归 SceneKit Coordinator。
- `liquidGlassPanel` 当前为 `ContentView.swift` 私有扩展；若 `MainQuestHUD` 拆到新文件，必须先将其提升为模块内共享 View modifier，不能复制样式实现。

转场采用 `prepare → commit → cleanup` 三阶段：`prepare` 预载相邻场景根但不开放热点；`commit` 以一次状态事务切换章节、检查点、相机和目标；`cleanup` 再移除旧章节点与 Beat。自动存档只落在 `commit` 前的稳定检查点或 `commit` 完成后的新检查点，不保存半透明、半移动的中间帧。若应用在转场中失焦或终止，恢复到最近稳定检查点并确定性重放转场；不得同时激活两章热点。

### F. 主线合法状态转换

| 当前章 | 完成门禁 | 唯一正常下一章 | 允许的安全兜底 |
|---|---|---|---|
| 第一章 | 纸条已拾取，跟随过场已触发 | 第二章 | 超时由苏念自动起身，不跳章 |
| 第二章 | 三灯完成，对话选择已记录 | 第三章 | 微游戏可选择“由苏念完成”，不跳过关系结果 |
| 第三章 | 纸条来源确认，同伴已选择，到达楼梯间 | 第四章 | 路径提示增强，不允许缺少同伴状态进入第四章 |
| 第四章 | 成人已通知且安全交接完成 | 第五章 | 未披露仍走成人接管；高危/紧急路线走专用交接 |
| 第五章 | 成人交接已确认；标准路线可另记录江越离开 | 第六章 | 流言未处理只改变余波；高风险/紧急路线不等待江越再次出镜 |
| 第六章 | 求助资源已展示并确认 | 主菜单/解锁内容 | 支持网络可自动展示，资源确认不可静默跳过 |

禁止从任意章节直接把 `currentChapter` 加一。所有转移必须通过 `GameManager.transitionChapter(from:result:)` 校验完成门禁，并记录一次快照。

### G. 无障碍与替代输入

- 所有依赖音频的线索必须提供可关闭的方向字幕，但字幕不得自动泄露声音来源身份。
- 描线支持鼠标、触控板和键盘沿路径逐段确认；运动能力受限时可选择“由苏念慢慢完成”。
- 旋律记忆提供视觉节奏辅助和“再听一次”，不能以听力作为通关门槛。
- 擦除互动支持拖动、按住空格自动缓慢擦除两种方式。
- 所有热点均可通过键盘焦点导航，不能只依赖鼠标悬停。
- 对话和教育便签停留时间由玩家确认，不以阅读速度作为失败条件。
- 主线 HUD、字幕、便签与对话应支持系统辅助功能标签和动态字号；文本不得遮挡目标或前后内容。

### H. AI 开发执行边界

AI 实现时必须遵循以下顺序，但最终交付范围仍是完整六章：

1. 先实现可测试的主线数据模型、转移门禁、暂停/恢复和存档。
2. 再实现 SceneDirector 与 MainQuestHUD，使用测试场景验证幂等和时间冻结。
3. 接入第一章，确认现有回合制事件与实时 Beat 不竞态。
4. 接入走廊/楼梯间/咨询室场景根和统一输入，再完成第二至第五章。
5. 最后接入终章、资源目录、完整状态组合测试和发布审核门禁。

不得一次生成并替换整个 `GameManager.swift` 或 `ClassroomSceneView.swift`。每一阶段必须保持 `swift build` 和已有测试通过，并新增对应状态机测试后才进入下一阶段。

---

## 验收检查清单

以下每一项对应主线稿 §13 的验收问题：

### 每章通用检查

- [ ] 玩家进入后 **3 秒内** HUD 显示当前目标
- [ ] 完成当前目标后 **1 秒内** 新目标出现
- [ ] 玩家无有效操作 30 秒时出现加强引导，90 秒内至少推进一个受控场景变化
- [ ] 玩家做出「不佳」选择后，主线不断，有兜底路径
- [ ] 章节结束时有明确的「我刚才完成了什么」信息
- [ ] 事件弹层、暂停、应用失焦和系统休眠期间叙事计时冻结，恢复后不重复触发 Beat
- [ ] 每一步完成后自动存档，从该章任一步骤恢复均不丢失或重复选择结果
- [ ] 所有步骤都可仅用键盘完成；关键音频有方向字幕，关键视觉有文字/声音替代

### 第一章专项

- [ ] 林澈观察、右侧声音、自我照顾按 HUD 单目标顺序推进
- [ ] 纸条事件不可被玩家操作跳过（只能提前触发，不能不触发）
- [ ] 步骤 3（自我照顾）未完成时保持 `GameNarrativeState.suNianSelfCared == false`，第六章结尾追加提示

### 第二章专项

- [ ] 三个微游戏均无失败判定（只有「完成」和「未完成」）
- [ ] 镜像世界允许暂停、退出和读档；恢复后灯、光路、林澈位置与微游戏结果一致
- [ ] 步骤 8 的选择结果正确写入 `linCheTrust`

### 第三章专项

- [ ] 班长和许栀的选择均能推进主线
- [ ] 两者影响差异在第四、五章中有可感知的场景差异

### 第四章专项

- [ ] 教育便签在追问前出现，且可被玩家主动关闭
- [ ] 信任值对玩家不可见（无数字、无进度条）
- [ ] 兜底路径（方老师介入）在任何信任状态下均可触发
- [ ] 「风险」相关文字不出现在 UI 上
- [ ] 信任值只影响披露，不改变 `jiangYueActualRisk`
- [ ] `.unknown` 不得被解释为低风险；成人到场前江越不会被单独留下
- [ ] `.high/.imminent` 取消普通倒计时并进入经专业审核的紧急响应路线

### 第五章专项

- [ ] 咨询室门「不可进入」逻辑在视觉上有明确提示（camera pull-back）
- [ ] 偏见便签不超过 2 条，不强制触发

### 第六章专项

- [ ] 求助资源提供明确复制按钮，并通过 `NSPasteboard` 复制
- [ ] 全国热线显示 `12356`；学校资源来自可更新配置并带审核日期
- [ ] 结局文字不出现「你赢了/失败了」等评判语
- [ ] 心理老师不下诊断、不提供万能建议；可以说明保密边界、确认感受并邀请后续支持

---

## 完整六章实施顺序

以下是依赖顺序，不是范围裁剪。阶段 0-5 全部完成才算 B 方案交付完成。

### 阶段 0：可测试底座

1. `MainQuestProgress`、`GameNarrativeState`、六章具名状态和 `NarrativeSave`
2. `GameManager.completeStep` 幂等门禁与章节合法转移
3. SceneDirector 暂停、恢复、取消、存档重建
4. `MainQuestHUD` 单一目标显示与无障碍标签
5. SceneKit 场景根、统一输入和 `NarrativeCameraMode`

### 阶段 1：第一章教室链

6. 第一章信号侦测、自我照顾、纸条事件
7. 第一章兜底、存档恢复和转入走廊的检查点测试

### 阶段 2：第二章镜像体验

8. 镜像节点根、色温/音频过渡、线性光路
9. 草稿灯、旋律灯、擦痕灯及替代输入
10. 林澈信任结果和转入第三章的检查点测试

### 阶段 3：第三章调查链

11. 蓝格线索、班干部二选一、同行状态
12. 两名班干部的行为差异、路径引导和转入楼梯间测试

### 阶段 4：第四、五章安全交接

13. 江越对话、披露状态、成人接管与三种安全路线分流
14. 标准等候、紧急交接等候、应急收束三种入口及隐私事件
15. 心理专业审核文本以资源文件接入，不硬编码在状态机

### 阶段 5：第六章与完整交付

16. 苏念咨询、支持网络图、多结局和 `SupportResourceCatalog`
17. 六章转场、全流程音频混音、字幕与辅助功能
18. 全状态组合测试、完整通关测试、专业复核和 Release 资源日期门禁

### 后续增强（不阻塞完整六章首版）

19. `LevelSeed` 随机种子系统
20. 更多对话措辞变体
21. 班干部在二周目中的额外关系余波

## 必测状态矩阵

| 场景 | 输入条件 | 必须验证的结果 |
|---|---|---|
| 玩家操作与 fallback 同时发生 | 同一帧完成当前步骤 | 只提交一次结果，只启动一个下一 Beat |
| fallback 提交与自动存档同帧 | 第一章步骤 1-4 各一次 | step 结果与场景检查点原子一致，恢复后不重复 fallback |
| 事件弹层覆盖导演计时 | 任意章触发 `.event` | 剩余时间冻结，关闭后继续，不跳步 |
| 多重暂停交错 | 先失焦，再开事件/暂停菜单，按不同顺序恢复 | 只移除对应原因；集合清空前 Beat 始终冻结 |
| 应用失焦后恢复 | 每章各一个步骤 | NPC、灯光、任务和剩余时间一致 |
| 任意步骤读档 | 六章每章至少两个存档点 | 不重复奖励、不重复台词、不丢失同伴和披露状态 |
| 旧版/损坏存档 | 可迁移旧 schema、截断 JSON、未知新 schema | 正确迁移或回退 `lastValid`，不拼接不一致章节状态 |
| 林澈三种结尾选择 | open/neutral/closed | 第三章协作表现不同，但主线均可完成 |
| 班长/许栀二选一 | 两条路径 | 第四、五章至少各有一处可感知差异 |
| 江越披露 unknown/partial/confirmed | 三种披露 | 全部完成成人交接，unknown 不被判为安全 |
| 编剧风险 moderate/high/imminent | 三档事实 | 普通与紧急路线正确分流，学生不承担临床判断 |
| 三种第五章入口读档 | standard/urgent/emergency 各在入口和完成前存档 | 场景、成人台词和门禁按原路线恢复；紧急路线不出现普通告别 |
| 多结局条件重叠 | 紧急路线+自我表达、普通路线+未表达等组合 | 按 §6.4 固定优先级命中唯一主结局，再独立追加自我照顾附注 |
| 流言回应/不回应 | 两种输入 | 只改变班级余波，不泄露咨询位置，不阻断终章 |
| 音频/鼠标不可用 | 开启替代输入 | 字幕、键盘和自动辅助均可完整通关 |
| VoiceOver 与键盘焦点 | 六章 HUD、对话、三灯、资源卡 | 朗读顺序符合视觉顺序，焦点不进入隐藏场景，操作后落到新目标 |
| 大字号/窗口缩放 | 系统辅助字号、最小支持窗口与全屏 | HUD 和按钮文字不截断、不遮挡，不改变固定互动区域尺寸 |
| 减少动态效果 | 系统 Reduce Motion 开启 | 镜面/转场/节点动画改淡入或即时状态，完成判定和时长不变 |
| 求助资源过期 | `reviewedAt` 超过 6 个月 | Debug 提示，Release 构建门禁失败 |

## 交给 AI 开发前的最终门禁

- [ ] 本文档中所有 Swift 片段经编译型 spike 验证，不再作为未经验证的伪代码直接复制
- [ ] 开发分支开始时再次复核本文涉及的 `GameManager`、`ClassroomCoordinator`、`CameraPose`、`PlayerAction`、`ActiveEventKind` 和 Liquid Glass 辅助接口；不匹配处先更新映射再实现
- [ ] 心理危机、未成年人转介、保密边界、紧急响应和咨询师台词获得具备资质人员书面复核
- [ ] 学校确认实际咨询入口、开放时间、预约方式和校内联系人，不使用通用占位承诺
- [ ] `12356` 及其他发布地区资源在 Release 前完成日期化复核
- [ ] 六章所需 3D 场景、角色、动画、字体和音频资产具有明确来源与授权记录
- [ ] 每个实施阶段结束时 `swift build`、`swift test` 和对应章节可玩通关均通过

---

*文档版本：v1.1*  
*状态：完整六章范围已确认；待心理专业审核与开发计划拆分*  
*本文件中所有涉及自伤风险、未成年人转介、保密原则、心理干预的具体文本，进入制作前须经具备资质的心理健康专业人士与实际学校审核。*

### 审核依据（发布前仍须复核最新版）

- 国家卫生健康委：《关于应用“12356”全国统一心理援助热线电话号码的通知》，https://www.gov.cn/zhengce/zhengceku/202412/content_6994470.htm
- NIMH：5 Action Steps to Help Someone Having Thoughts of Suicide，https://www.nimh.nih.gov/health/publications/5-action-steps-to-help-someone-having-thoughts-of-suicide
- WHO：Suicide fact sheet，https://www.who.int/news-room/fact-sheets/detail/suicide
