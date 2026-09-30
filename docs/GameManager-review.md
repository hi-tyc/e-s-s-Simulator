# `GameManager.swift` 深度代码审查报告

- **审查对象**：`Sources/LateStudySimulator/GameManager.swift`（4169 行，单一类型 `GameManager`）
- **分支**：`freatures/wyq`
- **参考**：`GameModels.swift`、`PrologueModels.swift`、`ContentView.swift`、`ClassroomSceneView.swift`
- **说明**：本报告仅审查，未修改任何文件。

---

## 0. 总体结论

`GameManager` 把「序章状态机 + 第一章状态机 + 学生自由走动 + 教师回合 + 事件分发 + 结局计算 + 回放/复盘 + 音频 + 无障碍 + UserDefaults 持久化」全部塞进一个 4169 行的 `@MainActor final class`。它是典型的**上帝对象**：`@Published` 字段 60+ 个、`private var` 定时器/任务状态 15+ 个，状态之间隐式耦合严重。

从功能正确性看，最严重的问题集中在三处：

1. **状态机在「自由走动 → 回座」与「事件弹窗」之间存在叠加/冲突**（P0-1、P0-2）。
2. **第一章主线的线索推进依赖 `cameraPose` 与 `updateChapterLookDwell`，但 `tickMovement` 在自由走动时提前 `return`，导致某些线索可能被漏掉且步骤无法回退**（P0-3、P1-3）。
3. **重新开始/返回菜单的重置不完整**（`rearLookDwell`、`rearLookRiskApplied`、`isChapterOneGuidePresented`、`chapterLookDwell*` 等未清理），存在跨局脏状态（P0-4）。

下面按严重程度分组。

---

## P0 严重（崩溃 / 数据错误 / 核心玩法失效）

### P0-1 「回座动画」与「教师回合 / 事件弹窗」并发执行，破坏回合推进计数

**位置**：`GameManager.swift:1522-1584`（`returnToSeatFromFreeRoam` / `completeReturnToSeat`），`1951-2051`（`teacherTurn`），`3939`（`recordSnapshot`）

**问题**：`returnToSeatFromFreeRoam` 用 `Task.sleep` 做两段式延迟动画：

```swift
// 1535-1553
returnToSeatTask = Task { @MainActor [weak self] in
    try await Task.sleep(nanoseconds: UInt64(GameManager.returnToSeatResetDelay * 1_000_000_000))
    guard let self, self.isReturningToSeat else { return }
    self.completeReturnToSeat(exitedClassroom: exitedClassroom, reason: reason)   // 内含 teacherTurn()
    ...
}
```

而 `completeReturnToSeat` 末尾直接调用 `teacherTurn()`（1583），`teacherTurn` 内部又会 `currentTurn += 1`、`presentEvent(...)`、`continueAfterEvent()`。

**触发场景**：
- 玩家在自由走动期间**课间自动开始**（`applyTimeProgression` → `beginStudentFreeRoam`，2605），或点了离座事件里的「请求去洗手间」（`go_washroom` → `beginStudentFreeRoam`，3174）。
- 自由活动倒计时到 0，`tickStudentFreeRoam` 触发 `returnToSeatFromFreeRoam`（1516）。
- 在 `returnToSeatResetDelay`（1.08s）到达前的这 1 秒里，玩家仍能操作；如果此时触发了任一 `presentEvent`（例如 `phoneNotification` 是随机事件，3258/2686 等），`gameState` 变成 `.event`。
- 1.08s 后 `completeReturnToSeat` 无条件执行并调用 `teacherTurn()`。若 `teacherTurn` 判定 `discoveryRisk > 92` 等，会**再次 `presentEvent`**，把玩家正在处理的 `.event` 覆盖掉；同时 `currentTurn` 被额外 `+1`。

**后果**：
- 玩家当前事件的选项丢失，`recordSnapshot` 在同一回合被重复记录，回合数与「课间 5 分钟」时间轴错位。
- 因为 `completeReturnToSeat` 没有检查 `gameState == .playing`，它会在 `.event` / `.ending` 状态下继续修改 `player` 与 `classmates`。

**建议修复**：让回座完成回合同样受状态机约束，并在事件期间冻结回座任务：

```swift
private func completeReturnToSeat(exitedClassroom: Bool, reason: String?) {
    // 事件/结束时不要把回座流程插进回合推进
    guard case .playing = gameState else {
        // 仍完成物理落座，但不推进回合
        freeRoam = StudentFreeRoamState()
        cameraPose = .forward
        player.posture = .seated
        clampPlayer()
        return
    }
    ...
}
```

并在 `presentEvent` 里取消/暂停正在进行的回座任务，或把 `teacherTurn()` 从 `completeReturnToSeat` 拆出、由 `tickStudentFreeRoam` 按明确的状态迁移调用。

---

### P0-2 事件弹窗期间 `resumeFreeRoamAfterEvent` 会「复活」已结束的离座，造成穿模与双重结算

**位置**：`3046-3063`（`presentEvent` / `pauseFreeRoamForEvent` / `resumeFreeRoamAfterEvent`），`1924-1949`（`continueAfterEvent`）

**问题**：

```swift
// 3051-3063
private func pauseFreeRoamForEvent() {
    guard freeRoam.isActive, freeRoamPausedAt == nil else { return }
    freeRoamPausedAt = Date()
}
private func resumeFreeRoamAfterEvent() {
    guard freeRoam.isActive, let pausedAt = freeRoamPausedAt else { ... }
    freeRoam.endsAt = freeRoam.endsAt.addingTimeInterval(Date().timeIntervalSince(pausedAt))
    freeRoamPausedAt = nil
}
```

`resumeFreeRoamAfterEvent` 只在 `freeRoam.isActive` 时才恢复。但 `.event` 状态下 `tickStudentFreeRoam` 仍被 Timer 驱动（`1165-1169`），其内部 `guard case .playing = gameState else { return }`（1514）——在事件期间直接 return，所以 `remainingSeconds` 会**照常流逝**（`endsAt` 是绝对时间）。

**触发场景**：
- 玩家离座中（`freeRoam.isActive == true`）→ 触发事件（如 `classmateReport`）→ 弹出事件期间 `freeRoamPausedAt` 已记录，但 `remainingSeconds` 因 `gameState != .playing` 而**没有真正暂停**（Timer 直接 return，既没暂停也没检查超时）。
- 玩家思考较久（事件弹窗是模态的，无时间压力）→ 选完选项 → `continueAfterEvent` → `resumeFreeRoamAfterEvent` 把 `endsAt` 往后顺延了「事件耗时」，于是**本应结束的离座被延长**，玩家继续在走廊活动。
- 更糟的是：若事件选择是 `go_washroom`（`shouldContinueAfterChoice = false`，3175），它调用 `beginStudentFreeRoam()`（默认 60s），而**退出事件分支不会调用 `resumeFreeRoamAfterEvent`**；但此时 `freeRoamPausedAt` 仍是旧事件的暂停时间点，后续任何 `continueAfterEvent` 都会用旧 `pausedAt` 去顺延 `endsAt`，得到一个巨大的时间偏移。

**后果**：离座时长不可预测，可能远超设定的 5 分钟（课间）或 60 秒（洗手间）；玩家可能长时间滞留走廊，而 `teacherTurn` 照常以每回合推进，时间轴（`clockText`）与实际活动严重不符。

**建议修复**：暂停逻辑应改为「冻结剩余秒数」而不是「延时 `endsAt`」，并在恢复时无条件清理暂停标记：

```swift
private var pausedRemaining: TimeInterval?

private func pauseFreeRoamForEvent() {
    guard freeRoam.isActive, freeRoamPausedAt == nil else { return }
    freeRoamPausedAt = Date()
    pausedRemaining = max(0, freeRoam.endsAt.timeIntervalSinceNow)
}

private func resumeFreeRoamAfterEvent() {
    defer { freeRoamPausedAt = nil; pausedRemaining = nil }
    guard freeRoam.isActive, let remaining = pausedRemaining else { return }
    freeRoam.endsAt = Date().addingTimeInterval(remaining)
}
```

同时 `go_washroom` 这类「重新开始离座」的分支必须先清空 `freeRoamPausedAt`。

---

### P0-3 第一章线索推进依赖 `cameraPose`，但 `updateChapterLookDwell` 在自由走动时被跳过，步骤可能永久卡死

**位置**：`1083-1112`（`updateChapterLookDwell`），`1096-1107`，`3467-3492`（`collectChapterClue`），`841-848`（`chapterOneAvailableActions`），`ClassroomSceneView.swift:597-617`

**问题**：`tickMovement` 中：

```swift
currentGame?.updateChapterLookDwell(delta: 1.0 / 60.0)   // 602
guard let game = currentGame, game.freeRoam.isActive else { ... return }  // 603
```

`updateChapterLookDwell` 的 guard 也要求 `freeRoam.isActive == false`（1086）。也就是说：**只有坐在座位上时**「持续看向正确方向 2.5 秒」才会推进第一章线索。

而线索推进的关键条件是 `cameraPose`：

```swift
// 1096-1099
(chapterOneStep == .observeLinChe && cameraPose == .left) ||
(chapterOneStep == .locateHiddenSound && cameraPose == .right) ||
(chapterOneStep == .inspectNote && cameraPose == .desk)
```

**触发场景**：
- 第一章事件链（`Array.randomElement`：`addBackgroundSignalReaction`，3500）会触发「手机通知」「广播」「后门敲响」等，其中 `turn_to_door` 会把 `teacher.positionIndex = 6`（3257）。
- 更关键：`chapterOneStep == .regulateSelf` 要求 `action == .breathe || action == .drink`（3478）。如果玩家此回合选择 `.leaveSeat`（`execute` 里 `.leaveSeat` 在第一节课属于允许动作，因为 `chapterOneAvailableActions` 只在 `.followLinChe` 之外**过滤掉** `.leaveSeat`，见 843——但 `execute` 本身不校验 `chapterOneAvailableActions`！见 P1-1），会进入自由走动。
- 自由走动期间视角完全由 `rotateStudentView` 控制并写回 `freeRoam.yaw`（1034-1039），`cameraPose` 会随之改变，但**不会触发线索收集**，因为 `updateChapterLookDwell` 被跳过。

**后果**：第一章要求玩家「看向左/右/低头」三步，但只要玩家在步骤间隙离座（课间自动离座更是每节课都会发生，2605），线索窗口就会静默关闭。由于**没有「回到上一步」的机制**，且 `.observeLinChe` 只能通过「向左看 2.5s」或 `execute(.observe)` + `cameraPose == .left`（3471）推进，玩家在 `.followLinChe` 之前可能长时间卡在某个步骤，只能靠随机事件消磨回合，直到 `currentTurn >= maxTurns` 才由 `presentChapterOneDecisionIfNeeded` 强推结局。

**建议修复**：把线索判定从「必须坐着」解耦出来，或在自由走动时也允许累积 `chapterLookDwell`（用 `freeRoam.yaw` 换算 `cameraPose`）：

```swift
func updateChapterLookDwell(delta: TimeInterval) {
    guard activeChapter == .silentClassroom, isPrologueActive == false,
          case .playing = gameState, activeRole.isTeacher == false else { return }
    // 自由走动时用 yaw 推导朝向，而不是直接放弃判定
    let effectivePose = freeRoam.isActive
        ? cameraPoseFromLook(yaw: freeRoam.yaw, pitch: freeRoam.pitch)
        : cameraPose
    ...
}
```

---

### P0-4 重新开始 / 返回菜单时重置字段不完整，产生跨局脏状态

**位置**：`254-323`（`startGame`），`331-367`（`returnToMenuForNewGame`）

**问题**：`startGame` 重置了大量字段，但**遗漏**了以下回合级状态：

| 字段 | 声明位置 | 是否重置 |
|---|---|---|
| `rearLookDwell` | 113 | ❌ |
| `rearLookRiskApplied` | 114 | ❌ |
| `chapterLookDwell` / `chapterLookDwellPose` | 111-112 | ❌ |
| `isChapterOneGuidePresented` | 67 | ❌（反而被强制设为 `true`，262） |
| `isChapterOneSeatSelectionPresented` | 68 | 只在 263 设 `false` |
| `gameGuideExitTimer` / `isGameGuidePresented` | 94 | ❌ |
| `hasCompletedInitialGameGuide` | 97 | ❌（设计上不清，见下） |
| `prologueDwell` | 110 | 仅在 `stopPrologueTimer` 里清（256→395） |
| `rearDoorOpen` / `frontDoorOpen` | 44-45 | ✅（286-287） |

`returnToMenuForNewGame` 同样遗漏 `rearLookDwell`、`rearLookRiskApplied`、`chapterLookDwell`、`isChapterOneGuidePresented`、`gameState` 之外的 `.ending` 缓存等。

**触发场景**：
- 玩家在一局末尾处于「坐着回头」（`cameraPose == .rear`）状态，`rearLookDwell` 已累积到 2.4，`rearLookRiskApplied == true`。
- 结算后点「返回菜单」→ `returnToMenuForNewGame` 没有清 `rearLookDwell`。
- 再开新局：`startGame` 把 `cameraPose = .forward`，但 `rearLookDwell` 仍是 2.4。新局第一帧 `updateChapterLookDwell`（1088）若 `cameraPose != .rear` 会走 else 清零（1092）——**这一条侥幸被兜底**。但 `rearLookRiskApplied` 若为 `true` 而 `rearLookDwell` 未清零（先看后方 0.1s），则 `applyRearLookRiskIfNeeded` 的 guard（1068）因 `rearLookRiskApplied == true` 而不触发，玩家**第一次回头零惩罚**。

**后果**：新局第一次「回头观察」不计风险，破坏核心风险机制；`chapterLookDwellPose` 残留可能导致新局第一次线索判定被错误打断（1101）。

**建议修复**：抽出统一的 `resetTurnScopedState()`，并在 `startGame` / `returnToMenuForNewGame` / `finish` 中调用：

```swift
private func resetTurnScopedState() {
    rearLookDwell = 0
    rearLookRiskApplied = false
    chapterLookDwell = 0
    chapterLookDwellPose = nil
    prologueDwell = 0
    pendingSprintHunger = 0
    lastAnomalyMonologueTurn = [:]
}
```

---

## P1 重要（明显 bug 或体验损伤）

### P1-1 `execute(_:)` 不校验 `chapterOneAvailableActions`，玩家可在第一章用被 UI 隐藏的动作绕过主线

**位置**：`841-848`（`chapterOneAvailableActions`），`1631-1792`（`execute`）

**问题**：`chapterOneAvailableActions` 明确把 `.leaveSeat` 和 `.observe` 排除在第一章可用动作之外，`.leaveSeat` 仅在 `.followLinChe` 时追加（844-846）。但 `execute` 完全没有读取这个列表：

```swift
// 1631-1652
func execute(_ action: PlayerAction) {
    guard case .playing = gameState else { return }
    ...
    if chapterOneStep == .followLinChe, action == .leaveSeat {
        completeChapterOne()
        return
    }
    switch action { ... }   // 任何 action 都能进来
```

**触发场景**：只要 UI 或键盘快捷键能把 `.observe` / `.leaveSeat` 派发进来（`ContentView` 的动作按钮通常读 `chapterOneAvailableActions`，但事件分支、键盘绑定、测试入口可能直接调 `execute`），玩家就能在 `.observeLinChe` 阶段直接 `.leaveSeat` → 进入自由走动 → 触发 P0-3 的线索卡死，甚至 `completeChapterOne` 的条件（1648）在非 `.followLinChe` 时不成立，玩家只是白走一趟。

**建议修复**：在 `execute` 开头加白名单校验：

```swift
func execute(_ action: PlayerAction) {
    guard case .playing = gameState else { return }
    guard !isPrologueActive else { ... }
    if activeChapter == .silentClassroom, chapterOneAvailableActions.contains(action) == false {
        message += " 现在还不能做这个动作。"
        return
    }
    ...
}
```

---

### P1-2 崩溃/失败阈值与「支持保护」的数值自相矛盾，结局可能被跳过或重复触发

**位置**：`2109-2171`（`checkCriticalState`），`2183-2259`（`calculateEnding`）

**问题**：

```swift
// 2151-2169
if player.psychicEnergy <= 5 || player.stress >= 96 {
    if player.support > 55 {
        player.psychicEnergy = 24
        player.stress = 62
        ...
        presentEvent(kind: .supportOffer, ...)
    } else {
        finish()
    }
}
```

`supportOffer` 事件本身没有 `hasTriggered*` 守卫，只要再次落入 `psychicEnergy <= 5 || stress >= 96` 且 `support > 55`，就会**无限重复弹出**「支持网络保护」。

**触发场景**：玩家 support 62，反复 `study` 把能量压到 5 以下 → 每次 `checkCriticalState` 都弹支持事件 → 事件里选 `accept_support` 回能量后，下一回合若又压到 5 → 再次弹出。由于 `checkCriticalState` 在 `continueAfterEvent`、`teacherTurn`、`resolveEventChoice` 结束后都会被调用，弹窗会高频复现。

另外，`calculateEnding` 的「崩溃边缘」判定是 `psychicEnergy <= 8 || stress >= 96`（2192），而 `checkCriticalState` 的硬阈值是 `<= 5 || >= 96`。当 `support <= 55` 时直接 `finish()`，`calculateEnding` 会因为属性已被 clamp 而看 `psychicEnergy <= 8`——但如果玩家死于 `stress >= 96`，`calculateEnding` 的第一分支（2206 `helpedClassmate && support >= 58`）又**先于**崩溃判定吗？不，崩溃判定（2192）在社交判定（2206）之前，所以没问题；但**教师线判定在最前面**（2188）：`activeRole.isTeacher || teacher.studentsWarned + teacher.studentsHelped > 4`。这意味着**只要老师提醒/关心总次数 > 4，学生线的所有结局都会被 `teacherEnding()` 覆盖**——见 P1-4。

**建议修复**：给 `supportOffer` 加一次性守卫，并把阈值统一成常量：

```swift
@Published var hasTriggeredSupportOffer = false
...
if !hasTriggeredSupportOffer, player.support > 55 { hasTriggeredSupportOffer = true; presentEvent(...) }
```

---

### P1-3 `teacherTurn` 在第一章会无条件 `currentTurn += 1`，使 `maxTurns` 推进更快，缩短可探索回合

**位置**：`1962-1969`

```swift
if activeChapter == .silentClassroom {
    if currentTurn < maxTurns { currentTurn += 1 }
    currentPhase = .observation
    ...
    return
}
```

**问题**：第一章的结局推进依赖 `currentTurn >= maxTurns` 且 `presentChapterOneDecisionIfNeeded()`（2043、1925）。由于 `.silentClassroom` 分支每小时回合都 +1，而事件（`presentEvent`）本身也会走 `continueAfterEvent` 再 +1，**同一回合里可能 +2**：

- `execute(.study)` → `updateClassmates` → `teacherTurn()`（1963 `+1`）。
- 若 `updateClassmates` 触发了事件（如 `phoneNotification`），`gameState = .event`。但 `execute` 在 1785-1788 已经 `return`，**不会**再调 `teacherTurn`，所以这条路径安全。
- 但 `completeReturnToSeat`（1583）调 `teacherTurn` 后又可能在 `returnToSeatTask` 的第二次 `Task.sleep` 期间被其它 tick 触发 → 双增。

**触发场景**：课间自动离座（2605）→ 玩家走动 → 倒计时结束 → `completeReturnToSeat` → `teacherTurn` `+1`；若此时恰好又在处理事件，`continueAfterEvent` 再 `+1`。回合数比预期多消耗，玩家被更早推向章末决策，压缩了「三步观察」的窗口。

**建议修复**：让 `teacherTurn` 只负责教师行为，回合推进集中在 `advanceTurn()` 单一出口，并加「本回合是否已推进」守卫。

---

### P1-4 结局判定优先级与文案命名误导：老师计数 > 4 会吞掉所有学生结局

**位置**：`2183-2259`

```swift
if activeRole.isTeacher || teacher.studentsWarned + teacher.studentsHelped > 4 {
    return teacherEnding()
}
```

**问题**：
1. `teacher.studentsWarned/Helped` 是**全班级别**的计数器，玩家（学生线）自己无法降低它；但 `teacherTurn` 的「被发现」（1993-1994）会 `teacher.studentsWarned += 1`，`explain_tired` 会 `studentsHelped += 1`（3080）。一名被频繁发现的学生，**必然**会触发 `teacherEnding()`，即使他整局都在努力走社交/学霸路线。
2. `teacherEnding()` 的标题判定用 `teacher.studentsHelped >= teacher.studentsWarned`（2294）——若相等取「教师理解」。但学生线根本不该看到这个结局文案。

**触发场景**：学生在高 `rankingPressure`（默认 70）+ 高 `patrolFrequency`（默认 65）下，`teacherTurn` 的 `discoveryRisk > 92` 分支会在一次被发现时把 `studentsWarned = 1`（1994）；再触发两次「老师关心」（2011、3080）就凑够 5，之后无论玩家多努力，结局一律显示「教师理解 / 制度压力传导」。

**后果**：学生线 4 种结局中至少 3 种在高默认参数下**几乎不可达**（只有 `helpedClassmate && support >= 58` 的「社交之夜」偶尔抢在老师计数前）。

**建议修复**：学生线不应因 `studentsWarned` 转入教师结局；改为只在 `activeRole.isTeacher` 时走 `teacherEnding()`，学生线用 `player.teacherWarnings` 做文案修饰：

```swift
if activeRole.isTeacher { return teacherEnding() }
```

---

### P1-5 「摸鱼大师」结局要求 `exposure > 70`，但 `finish()` 前 `exposure` 极难维持

**位置**：`2234-2246`

**问题**：`exposure` 在 `clampPlayer` 里被压到 0...100（4055），很多动作会**降低** exposure（`accept_warning` -14、`stop_and_reset` -18、`hide_from_memory_suspicion` -16、`sit_back_down` -12 等）。而结局判定顺序里 `exposure > 70` 排在「学霸之夜」之后，且 `calculateEnding` 只在 `finish()` 时调用一次。

**触发场景**：玩家想走「摸鱼大师」路线，需要全程 exposure 高位。但每次 `teacherTurn` 的 `discoveryRisk > 92` 会**强制**把 `exposure = 42`（1995），一次就把玩家从 >70 打到 42，导致该结局几乎不可达（除非玩家全程不被发现，那又拿不到高 exposure）。

**建议修复**：把「被发现」改为 `exposure = max(42, player.exposure)` 或改用衰减而非硬重置，避免结局条件被单点抹除：

```swift
player.exposure = max(42, min(100, player.exposure))
```

---

### P1-6 `prologueState.prologueCompleted` 与 `startPrologue(resume:)` 的布尔逻辑写反/冗余

**位置**：`233-252`

```swift
if resume == false || prologueState.prologueCompleted {
    prologueState = PrologueState()
}
```

**问题**：`startExperience` 在 `forcePrologue || prologueCompleted == false` 时调 `startPrologue(resume: false)`（142-145）；`finishPrologue` 会置 `prologueCompleted = true`（644）。于是：
- 首次进入：`prologueCompleted == false` → `startPrologue(resume: false)` → 条件 `resume == false` 为真 → 重置为全新 `PrologueState()`。✅
- 已完成序章后从菜单点「进入序章」：`startExperience(forcePrologue: true)` → `startPrologue(resume: false)` → 因为 `resume == false` 仍然重置。✅（这是设计意图：菜单进入是重放）

但 `restartPrologueTutorial()`（661-665）也是 `startPrologue(resume: false)` 然后手动 `completePrologueBeat(.gateArrival, source: .performance)`。这里 `completePrologueBeat` 要求 `prologueState.completedBeats.contains(beat) == false`（573）——重置后成立，✅。

看起来逻辑闭环，但 `resume == true` 分支（从游戏内恢复）在**代码里从未被调用**（全仓库只有 `startExperience` 传 `resume: false`）。这是死代码 + 误导性 API。

**建议修复**：删除 `resume` 参数，或明确注释其用途并补上真正的「中断恢复」调用点。

---

### P1-7 `highestRiskClassmate` / `selectedTeacherTargetID` 依赖 `max` 闭包比较，语义易错

**位置**：`291`、`3023-3025`、`929-932`

```swift
selectedTeacherTargetID = classmates.max { lhs, rhs in lhs.stress < rhs.stress }?.id  // 291
var highestRiskClassmate: Classmate? {
    classmates.max { lhs, rhs in lhs.stress < rhs.stress }  // 3024
}
```

`max(by:)` 返回「按给定谓词为 large 的元素」，此处 `lhs.stress < rhs.stress` 表示 rhs 更大 → 返回 stress 最大者。**语义正确**，但 `gameState` 在 `.menu` 时 `classmates` 为空 → 返回 nil，调用方都有 `??` 兜底（930、2965、3713）。可接受，但 `selectedTeacherTarget` 在 `classmates` 非空时会 fallback 到 `highestRiskClassmate`，UI 里 `isTeacher` 场景下首回合 `selectedTeacherTargetID` 由 291 初始化，逻辑一致。

**风险点**：`teacherTargetCandidates` 的 `sorted` 用了 `teacherTargetScore`，但 `prefix(8).map { $0 }` 是冗余（939-940）。可简化为 `Array(sorted.prefix(8))`。

---

### P1-8 随机数直接用于关键判定，无法复现，且用 `Double.random` 而非可控 RNG

**位置**：`264`、`1953`、`2009`、`2083`、`2091`、`2535-2536`、`2626`、`2655`、`2657`、`2727`、`2872`、`2927`、`2950`、`2977`、`3003`、`3500`、`4114-4115`、`4151-4160`

**问题**：`GameManager` 是 `ObservableObject`，但所有随机都直接用全局 `Double.random(in:)` / `Int.random(in:)` / `.randomElement()`。这意味着：
- 无法做固定种子的回归测试（`Tests/` 里无法确定性复现某局）。
- 「回放」（`replay`）只记录结果，不能真正重演（因为事件选择本身也不可复现）。

**触发场景**：任何依赖随机的平衡调参、Bug 复现、玩家「这一局不公平」的申诉，都无法定位。

**建议修复**：注入一个 `RandomNumberGenerator`（默认 `SystemRandomNumberGenerator`，测试传种子 RNG），把随机调用统一收敛到 `rng.next(...)`：

```swift
private var rng: RandomNumberGenerator = SystemRandomNumberGenerator()
// 使用 Double.random(in: 0...1, using: &rng)
```

同时对 `makeClassmates` 的性格抽取做可配置种子，否则同一「制度参数」的两局体验方差过大（见 P2-2）。

---

## P2 一般（健壮性 / 可维护性）

### P2-1 单一巨型类型职责过载，建议拆分子状态机

**位置**：整个文件

`GameManager` 同时扮演：序章状态机、第一章状态机、自由走动物理、教师 AI、事件分发、结局计算、复盘生成、音频调度、无障碍、持久化。建议按职责拆分：

- `PrologueCoordinator`（`233-726` 的序章部分）
- `FreeRoamController`（`1135-1554`）
- `ChapterOneDirector`（`841-848`、`3467-3548`）
- `EndingCalculator`（`2183-2530`、`3666-3937`）
- `EventDirector`（`2622-3005`、`3046-3405`）
- `PersistenceStore`（`695-726`、`4007-4048`）
- `GameManager` 只保留 `@Published` 与协调调用

---

### P2-2 `makeClassmates` 随机性格方差过大，难度不可控

**位置**：`4134-4162`

```swift
func value(_ base: Double, spread: Double) -> Double {
    (base + Double.random(in: (-spread / 2)...(spread / 2))).clamped(to: 5...95)
}
```

`spread` 都在 70~82，即基础值上下浮动 35~41 点。`anxiety` 基础 42 → 可能抽到 5 或 83。而 `classmateProfile` 只对 `id 0...4`（林澈等）固定，其余 15+ 个同学每局完全随机，导致：
- 某局全是高 `orderliness`（易举报），某局全是高 `empathy`（易掩护），玩家体验方差极大。
- 结局判定里 `support >= 58` 的达成难度随抽签剧烈波动（P1-4 的社交结局）。

**建议修复**：降低 `spread`（如 24~32），或把 `anxiety` 等关键字段做成「全局分布 + 个体扰动」以保证整班画像稳定。

---

### P2-3 魔数遍布，缺乏集中常量表

**位置**：`264`（座位 `0...4/1...2`）、`489`（座位半径 `0.72`）、`1195`（`4.08` 出教室阈值）、`1414-1464`（走行区域/障碍）、`2145-2169`（阈值 5/96/24/62）、`2535-2536`（视野随机区间）、`3570-3585`（异常独白阈值 24/78/72/74/18/76/80/82）、`4051-4062`（clamp 范围）

例如同一概念 `0.72` 在 489 与 1202 重复出现，`4.08` 与 `pushPlayerOutOfDoorwayBeforeClosing` 的 `4.18`（1334）语义相关却分离。建议抽出 `GameBalance` 枚举集中管理。

---

### P2-4 `isChapterOneSeatSelectionPresented`、`isChapterOneGuidePresented` 等 UI 标志与 ContentView 脱节

**位置**：`67-70`；`ContentView.swift:366-421`（`chapterOneSeatSelectionOverlay` 整体被 `EmptyView()` + 块注释禁用）

**问题**：
- `isChapterOneSeatSelectionPresented` 在 GameManager 里被设为 `false`（263），但从未被置 `true`，也从未在任何视图中被消费 → **死标志**（seat 选择功能在分支上被注释掉）。
- `selectedChapterSeat` 仍由 `Int.random(in: 0...4)` / `Int.random(in: 1...2)` 生成（264），而 `makeClassmates` 用 `selectedChapterSeat ?? (row: 2, column: 1)`（4104）来挖空玩家座位。随机座位会导致 `column - 1` 可能为 0 或 `column + 1` 可能为 3 —— 需确认不越界：`1...2` 时 `column-1 ∈ 0...1`、`column+1 ∈ 2...3`，安全；但 `row ∈ 0...4` 时 `isLinCheSeat` 的列可能落在 `column == 0` 且 `row` 为 0/4 的边缘行，校园场景里 `ClassroomSceneView.swift:297` 也用同一 fallback，需保持三处一致（目前三处都写死 `(row: 2, column: 1)`，容易漏改）。

**建议修复**：删除死标志，或把座位选择流程完整接回；把 `(row: 2, column: 1)` 抽成常量 `GameManager.defaultPlayerSeat`。

---

### P2-5 `appendEvent` / `addAudioCue` / `addMonologue` 都把 `insert(at: 0)` + `removeLast()` 手写一遍，且容量魔数不同

**位置**：`3039-3044`（6）、`3436-3444`（5）、`3446-3460`（5）

三处逻辑相同、容量不同，属于重复代码。建议抽成泛型 `push(_ item: into: &list, cap:)` 或 `Array` 扩展。

另：`addAudioCue`（3443）每次都 `audio.playCue`，即使 `gameState == .menu` 或处于静音/无关场景；`previewAudioCue`（875）也会调它，但没校验 `activeRole`，可能给学生线播教师提示音。

---

### P2-6 `elapsedMinutes` 与 `currentPeriod` 在 `maxTurns == 0` / `totalMinutes <= 70` 时的边界

**位置**：`2572-2587`、`GameModels.swift:245-258`

```swift
var elapsedMinutes: Int {
    guard maxTurns > 0 else { return 0 }   // 2573，安全
    let cappedDuration = min(settings.totalMinutes, 150)
    return max(0, min(cappedDuration, Int(Double(max(0, currentTurn - 1)) / Double(maxTurns) * Double(cappedDuration))))
}
```

`Int(...)` 对浮点截断，`maxTurns` 由 `InstitutionSettings.maxTurns = max(6, Int(studyHours * 6))`（527）保证 ≥6，安全。

但 `StudyPeriod.period(forElapsedMinutes:)`：当 `totalMinutes <= 70` 时（即 `studyHours <= 1.17`），`minutes < totalMinutes - 10 ? .first : .breakOne`——`totalMinutes` 被 `elapsedMinutes` 的 `min(settings.totalMinutes, 150)` 与 `period` 里传参一致，安全。但 `studyHours` 若为 1.0 → `totalMinutes = max(60, 60) = 60` → `minutes < 50` 第一节，否则 `.breakOne`（**永远到不了第二节/第三节**），这个「短局只有一节+课间」的行为未在 UI 提示，玩家会困惑。

**建议修复**：在设置面板显示「本局将包含的节次」，或在 `period` 里对短局做更清晰的均分。

---

### P2-7 `handleEyeContact` 硬编码「第三排」（`row == 2`），与可选座位冲突

**位置**：`1610-1613`

```swift
guard let index = classmates.firstIndex(where: { $0.seat.row == 2 && $0.seat.column == column }) else { return }
```

玩家座位若被 `selectedChapterSeat` 随机成 `row != 2`（264 允许 0...4），则「看向左右」时将**永远找不到同桌**，`handleEyeContact` 静默 return，`maskCost` / `support` 的眼接触收益全部失效。同理 `updateClassmates` 里的 `isDeskmate` 用 `classmate.seat.row == 2`（2625）也写死「第三排」。

**触发场景**：任何一次 `selectedChapterSeat.row != 2` 的新局——而 264 有 4/5 概率抽到非 2 行。

**建议修复**：统一以 `selectedChapterSeat` 为基准：

```swift
private var playerSeatRow: Int { (selectedChapterSeat ?? (row: 2, column: 1)).row }
// 1611: $0.seat.row == playerSeatRow && ...
```

---

### P2-8 `finish()` 后 `session` 相关定时器未全部停止

**位置**：`2173-2181`

```swift
private func finish() {
    if replay.isEmpty { recordSnapshot(actionLabel: "结束") }
    commitClassmateMemory()
    selectedReplayIndex = max(0, replay.count - 1)
    gameState = .ending(calculateEnding())
    audio.stop()
}
```

`finish` 没有 `freeRoamTimer?.invalidate()`（虽然 `returnToSeatFromFreeRoam` 通常会先清）、没有 `stopPrologueTimer()`、没有取消 `returnToSeatTask` / `monologueDismissTask`、没有清 `freeRoamPausedAt`。若在离座或回座动画中直接 `finish()`（例如支持网络的 `else { finish() }`，2168），`freeRoam.isActive` 仍为 `true`，`freeRoamTimer` 仍在跑，`tickStudentFreeRoam` 会因 `guard case .playing = gameState` 而 return（1514），但 Timer 常驻直到下次 `beginStudentFreeRoam`/`returnToMenuForNewGame`。属于资源泄漏与潜在二次触发。

**建议修复**：

```swift
private func finish() {
    freeRoamTimer?.invalidate(); freeRoamTimer = nil
    returnToSeatTask?.cancel(); returnToSeatTask = nil
    isReturningToSeat = false
    stopPrologueTimer()
    monologueDismissTask?.cancel()
    freeRoamPausedAt = nil
    ...
}
```

---

### P2-9 `commitClassmateMemory` 在 `classmateMemory` 为空与 UserDefaults 清理之间的不一致

**位置**：`4007-4048`、`854-858`

`commitClassmateMemory` 会重建 `classmateMemory`（只保留满足 `shouldRemember` 的同学），但 `makeClassmates` 只用 `classmateMemory[id]` 里的 `stressEcho / relationshipCarry / suspicionCarry / sharedTruth / helpedLastRun`（4113-4126）。若某局全班都「平淡」，`nextMemory` 为空 → `saveClassmateMemory` 会 `removeObject`（4040-4042）→ **上一局积累的记忆被整局抹除**，而不是逐条衰减。跨局记忆应当是「衰减 + 保留」，这里变成了「全有或全无」。

**建议修复**：空结果时不清盘，或对每条记忆做 `×0.6` 衰减后再落盘。

---

### P2-10 命名误导与注释缺失

- `learned`/`state` 类字段：`isChapterOneGuidePresented`（67）实际语义是「章首教学卡是否已展示」，但从不置 `false` 之外的复位，易误解为「引导是否正在进行」。
- `roleOpeningLine` / `roleOpeningMonologue`（786-810）对 `counselingPatrolTeacher` 有分支，但该角色不在 `PlayableRole.selectableCases`（164-166）里，玩家**永远选不到**，属于不可达代码或隐藏角色。
- `estimatedAnxietyPeaks`（3666-3703）在 `replay.isEmpty` 时用 `player.stress / 35` 估算，与 `anxietyLoad >= 70` 的口径不一致，导致结算前一帧与结算后数字跳变。

---

## 附：优先修复建议顺序

| 优先级 | 条目 | 影响 |
|---|---|---|
| 1 | P0-1、P0-2 | 回合/时间轴错乱，离座时长失控 |
| 2 | P0-4 | 新局第一次回头免惩罚 |
| 3 | P0-3、P1-1 | 第一章主线可卡死 |
| 4 | P1-4、P1-5 | 学生线多数结局不可达 |
| 5 | P1-2、P1-3 | 弹窗重复、回合双增 |
| 6 | P2-7、P2-9 | 座位相关功能静默失效、记忆全盘丢失 |

---

**报告结束**（未修改任何源码）。
