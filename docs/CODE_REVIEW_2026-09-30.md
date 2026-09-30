# 晚自习模拟器 完整代码审查报告

- **审查日期**：2026-09-30
- **分支**：`freatures/wyq`（HEAD `1e5ce0e`）
- **代码规模**：8 个 Swift 文件，11,293 行
- **审查方式**：6 个并行子代理分模块深度审查 + 实测构建/测试/运行 + 主审交叉验证
- **构建状态**：✅ `swift build` 通过，**0 warning / 0 error**（`-warnings-as-errors` 亦通过）
- **测试状态**：⚠️ 40 个测试，**1 个不稳定失败**（25% 失败率）

---

## 一、执行摘要

| 维度 | 结论 |
|---|---|
| 编译质量 | 优秀。无警告、无 `try!`/`as!`/`fatalError`/`print` 残留、无 TODO、无硬编码绝对路径 |
| 运行时稳定性 | 良好。可正常启动驻留（RSS 148MB，CPU 36%），无崩溃 |
| **游戏逻辑** | **存在 4 个 P0 缺陷**，其中 2 个可导致主线卡死或回合错乱 |
| **性能** | **存在架构级性能问题**：鼠标每移动 1 像素触发 2761 行 body 重建 + 全场景更新 |
| **音频** | 6 个 P0：实时线程数据竞争、采样率硬编码、立体声崩溃风险 |
| **测试覆盖** | 严重不足。695 行测试**零覆盖**结局判定/回合推进/跨局记忆/教师巡逻 |
| 可维护性 | 差。3 个 2000–4000 行的巨型类型；魔数遍布 |

**总计发现**：P0 ×19、P1 ×40、P2 ×41（已去重）。

---

## 二、P0 严重问题（必须优先修复）

### 2.1 【游戏逻辑】随机选座与硬编码 "第三排" 冲突 —— 已实测导致测试 25% 失败率

**位置**：`GameManager.swift:264`、`GameManager.swift:4101-4112`、`ContentView.swift:1224`、`ClassroomSceneView.swift:1531`

```swift
// GameManager.swift:264  —— 座位完全随机
selectedChapterSeat = (row: Int.random(in: 0...4), column: Int.random(in: 1...2))
```

但全项目有 **15+ 处**硬编码 `row == 2`（第三排中间）：

| 位置 | 内容 |
|---|---|
| `ContentView.swift:1224` | 同桌条：`filter { $0.seat.row == 2 && (column == 0 \|\| column == 2) }` |
| `GameManager.swift:1611` | 同桌查找：`$0.seat.row == 2` |
| `GameManager.swift:2534` | 左侧同学哭泣检测：`row == 2 && column == 0` |
| `GameManager.swift:2625, 3008` | `isDeskmate` 判定 |
| `ClassroomSceneView.swift:1267` | `playerGroundedChair` 命名 |
| `ClassroomSceneView.swift:1531` | 教师视线目标硬编码 `(-0.6, _, 1.5)` |
| `GameManager.swift:791, 793, 815` | 剧情文案："你被固定在第三排中间" |

**实测证据**（子代理执行 12 次单元测试）：

```
PASS=9 FAIL=3 (of 12 runs)   # 25% 失败率
MovementAndEventTests.swift:359:
  XCTAssertEqual failed: profile(...) is not equal to nil
```

**根因**：`makeClassmates()` 按**座位推导的 id** 分配姓名与性格（`GameManager.swift:4110-4112`），座位随机化后具名角色（林澈/周予安/江越/陈言/许栀）不一定出现，测试 `first { $0.name == name }` 返回 `nil`。

**同时**：座位选择 UI 是**死代码**（`ContentView.swift:366-421`，`EmptyView()` + 注释块），且 `selectChapterSeat` / `confirmChapterSeatSelection` 两个方法**在 `GameManager` 中根本不存在**——即使恢复注释也无法编译。

**影响**：
- 玩家可能被随机分到第 0/4 排（靠讲台/靠后墙），但同桌系统、线索观察、剧情文案全部假设第三排
- 教师视线锥永远指向固定坐标，玩家"被无视"
- 测试间歇性红灯，掩盖真实回归

**建议修复**：二选一
1. **固定座位**（最小改动，推荐）：`selectedChapterSeat = (row: 2, column: 1)`，与所有硬编码假设一致；
2. **彻底参数化**：座位选择 UI 恢复 + `selectChapterSeat` 补齐 + 将 15 处 `row == 2` 改为 `game.selectedChapterSeat` 派生。

---

### 2.2 【游戏逻辑】回座 Task 取消竞态 —— 取消后仍执行完整回合结算

**位置**：`GameManager.swift:1522-1584`

```swift
returnToSeatTask = Task { @MainActor [weak self] in
    try? await Task.sleep(...)                      // 第一个 sleep
    guard let self, self.isReturningToSeat else { return }
    self.completeReturnToSeat(...)                  // ← 已执行结算（含 teacherTurn）
    do { try await Task.sleep(...) } catch { return }   // ← 此处取消已来不及
    guard self.isReturningToSeat else { return }
    self.isReturningToSeat = false
}
```

`completeReturnToSeat()` 内部会调用 `teacherTurn()`（`GameManager.swift:1583`），后者可能：
- 推进回合
- 触发 `presentEvent()`（弹出事件对话框）
- 增加 `teacher.studentsWarned`

**触发场景**：玩家离座期间在 1.08s 窗口内按 Esc 返回菜单 → `returnToMenuForNewGame()` 取消 Task → 但 `completeReturnToSeat` **已经执行完毕**，导致菜单界面下一个完整回合被结算，甚至弹出事件窗口。

**建议修复**：
```swift
// completeReturnToSeat 起始加守卫
guard !Task.isCancelled, gameState == .playing, isReturningToSeat else { return }
```
并在取消路径显式 `returnToSeatTask = nil`。

---

### 2.3 【游戏逻辑】第一章主线可永久卡死 —— 线索推进与课间自动离座互斥

**位置**：`GameManager.swift:1083-1112`（线索推进）、`GameManager.swift:2605-2610`（课间自动离座）

```swift
// 线索推进要求 freeRoam 非激活
func updateChapterLookDwell(delta: TimeInterval) {
    guard ..., freeRoam.isActive == false else { return }   // ← 关键守卫
    ...
    if chapterLookDwell >= 2.5 { collectChapterClue(for: .observe) }
}
```

```swift
// 课间自动开启自由活动
case .breakOne, .breakTwo:
    if activeRole.isTeacher == false && freeRoam.isActive == false {
        beginStudentFreeRoam(duration: 300, ...)            // ← 5 分钟自由活动
    }
```

**问题**：课间会自动进入 5 分钟自由活动，期间 `freeRoam.isActive == true`，**线索观察进度完全无法累积**。且 `chapterLookDwell` 在 `freeRoam` 激活时不会重置（守卫直接 return），状态残留。

**触发场景**：玩家在课间试图完成 `observeLinChe` / `locateHiddenSound` / `inspectNote` 步骤 → 观察 2.5 秒无效 → 若不主动回座，课间结束后才可能继续。若玩家误以为卡死而反复操作，体验严重受损。

**建议修复**：
- 方案 A：线索推进改由 `chapterLookDwell` 在自由活动期间**继续累积**（移除守卫中对 `freeRoam` 的限制，改为要求 `player.posture == .seated`）；
- 方案 B：课间不自动离座，改为提示"可以按空格离座"；
- 并在 `beginStudentFreeRoam` 时重置 `chapterLookDwell = 0`。

---

### 2.4 【游戏逻辑】新局状态未重置 —— 第一次回头观察零风险

**位置**：`GameManager.swift:111-114`（声明）、`GameManager.swift:254-323`（`startGame` 未重置）

```swift
// 声明
private var chapterLookDwell: TimeInterval = 0
private var chapterLookDwellPose: CameraPose?
private var rearLookDwell: TimeInterval = 0
private var rearLookRiskApplied = false
```

`startGame()` / `returnToMenuForNewGame()` 中**完全没有重置这 4 个字段**。

**触发场景**：上一局结束时 `rearLookRiskApplied == true`，新开一局后玩家第一次回头观察（`cameraPose == .rear`）→ `applyRearLookRiskIfNeeded` 因 `rearLookRiskApplied == false` 守卫失败而不被调用 → **零风险回头**，破坏核心玩法（"坐着回头会显著增加暴露和压力"）。

**建议修复**：在 `startGame()` 与 `returnToMenuForNewGame()` 中统一重置：
```swift
chapterLookDwell = 0
chapterLookDwellPose = nil
rearLookDwell = 0
rearLookRiskApplied = false
```
**建议**：把所有可变的临时状态收进一个 `SessionState` 结构体，重置时整体替换，从根上杜绝遗漏。

---

### 2.5 【游戏逻辑】结局优先级吞掉学生线结局

**位置**：`GameManager.swift:2188-2190`

```swift
if activeRole.isTeacher || teacher.studentsWarned + teacher.studentsHelped > 4 {
    return teacherEnding()
}
```

`studentsWarned + studentsHelped > 4` 的判断在**所有学生线结局之前**，而这两个计数器在 9 处递增（`GameManager.swift:1821, 1836, 1849, 1867, 1994, 2011, 3080, 3135, 3350`）。

**默认参数**：`rankingPressure = 70`、`patrolFrequency = 65`（`GameModels.swift:524-525`）——属于中高压力配置，18 回合内很容易累计 5 次。

**影响**：默认设置下，「社交之夜」「学霸之夜」「普通的一晚」几乎**不可达**，玩家总是拿到教师线结局。

**建议修复**：
```swift
// 教师线结局只应在玩家实际扮演教师时触发
if activeRole.isTeacher {
    return teacherEnding()
}
// 学生线中，教师互动次数作为结局的"修饰"而非"覆盖"
if player.psychicEnergy <= 8 || player.stress >= 96 {
    return ...   // 优先判定玩家的真实状态
}
```
或将阈值从 `> 4` 提高到与 `maxTurns` 成比例（如 `> maxTurns / 3`）。

---

### 2.6 【性能】鼠标每移动 1 像素 → 2761 行 body 重建 + 全场景遍历

**位置**：`ClassroomSceneView.swift:685-687`（鼠标监听）、`GameManager.swift:1030-1033`（写入 `@Published`）、`ContentView.swift:7-99`（巨型 body）

**完整问题链**：

```
NSEvent.addLocalMonitorForEvents(.mouseMoved)
  → ClassroomCoordinator.handleMouseMovement
  → game.studentLookYaw = nextYaw          ← @Published 写入
  → objectWillChange 触发
  → ContentView.body 重新求值（2761 行）
  → ClassroomSceneView.updateNSView
  → coordinator.update(game:) 全量更新（含每帧全树遍历）
```

**量化证据**：
- `GameManager` 有 **71 个 `@Published`**（`grep -c '@Published'`）
- `studentLookYaw` / `studentLookPitch` 是鼠标环视的每帧写入点
- `ContentView.body` 顶层读取 `gameState` / `isPrologueActive` / `featuredMonologue` / `accessibilityPreferences`
- `rendersContinuously = true` + `preferredFramesPerSecond = 60`（`ClassroomSceneView.swift:46-47`）

**影响**：任何 `@Published` 变化都会重建整个 body，包括隐藏的 `menuOverlay`、`accessibilityPanel`、`endingOverlay`（含 12 个面板）。在 3D 渲染同时进行时可感知掉帧。

**建议修复**（按性价比排序）：

1. **拆分订阅范围**（最有效）：把 body 的每个 `if` 分支拆成独立 `View`，各自 `@EnvironmentObject`：
   ```swift
   struct ContentView: View {
       var body: some View {
           ZStack {
               ClassroomSceneView(game: game).ignoresSafeArea()
               OverlayRoot()      // 只读 overlay 相关状态
           }
       }
   }
   ```
2. **分离高频状态**：`studentLookYaw/Pitch` 不放进 `@Published`，改用 `@ObservationIgnored` + 直接传给场景层，或在 `ClassroomCoordinator` 内部维护。

---

### 2.7 【3D】每帧重建 `SCNText` —— 黑板文字闪烁 + 内存抖动

**位置**：`ClassroomSceneView.swift:1703-1707`

```swift
private func updateBlackboard(game: GameManager) {
    blackboardStatusNode.childNodes.forEach { $0.removeFromParentNode() }
    let status = "时间 \(game.clockText)   作业 \(Int(game.player.homework))%   压力 \(Int(game.player.stress))"
    blackboardStatusNode.addChildNode(makeText(status, ...))   // 每帧新建 SCNText + 材质
}
```

`update(game:)` 每帧调用，字符串含 `homework`/`stress`（持续变化）→ 每帧重建 `SCNText`（含字体排版 + 三角剖分）。

**影响**：黑板状态行字距抖动/边缘闪烁；GPU 资源反复上传释放；`rendersContinuously = true` 下是稳定每帧开销。

**建议修复**：
```swift
private var lastBlackboardStatus = ""
private func updateBlackboard(game: GameManager) {
    let status = "..."
    guard status != lastBlackboardStatus else { return }
    lastBlackboardStatus = status
    // 仅在变化时重建
}
```

---

### 2.8 【3D】每帧全场景树遍历 + 命中错误节点

**位置**：`ClassroomSceneView.swift:1760-1771`

```swift
scene.rootNode.enumerateChildNodes { node, _ in
    guard selectedChair == nil, node.geometry != nil else { return }   // ← 条件错误
    if abs(node.position.x - ...) < 0.01 && abs(node.position.z - ...) < 0.01 {
        selectedChair = node
    }
}
selectedChair?.name = "playerGroundedChair"
```

**已交叉验证的真实缺陷**：`makeChair`（`ClassroomSceneView.swift:1407-1419`）生成的椅子**父节点没有 geometry**（只有子节点腿/座板有），所以 `node.geometry != nil` 会命中的是**其他节点**（抽屉挡板等），而非目标椅子。

**影响**：
- 场景约 1000+ 节点，60fps 下每秒 6 万次闭包调用
- `playerGroundedChairVisible` / `playerGroundedChairLegCount`（测试与 UI 依赖）返回值**不可靠**
- 与 `ClassroomSceneView.swift:1267` 的初始命名**冲突**（两个节点可能同名）

**建议修复**：建桌时存字典，直接按座位 key 取：
```swift
private var chairNodesBySeat: [String: SCNNode] = [:]
// makeFurniture 内：chairNodesBySeat["\(row)_\(column)"] = chair
// updateDeskState：chairNodesBySeat.values.forEach { $0.name = nil }
```

---

### 2.9 【3D】门外剪影 Action 永不清理

**位置**：`ClassroomSceneView.swift:446-450`

```swift
root.runAction(.repeatForever(.sequence([delay, walk, .wait(duration: 4), reset])))
```

`makePrologueExterior()` 在 `buildScene()` 无条件挂载，6 个剪影各带 `repeatForever` 动作，序章结束后仍在后台每帧求值。

**建议修复**：在 `lastPrologueActive && !game.isPrologueActive` 变化点调用 `removeAllActions()` 并 `isHidden = true`。

---

### 2.10 【音频】实时渲染线程与主线程数据竞争

**位置**：`SpatialAudioManager.swift:84-119`（渲染回调）vs `:127-141`（主线程）

渲染闭包（音频实时线程）读写 `self.amplitude` / `self.phase` / `self.ambientNoise` / `self.frameCursor`，主线程的 `updateStress` / `updateAmbient` 同时写 `targetAmplitude` 等。

**注意**：`SpatialAudioManager` **无任何 actor 隔离**（`GameManager.swift:101` 直接持有），在当前 Swift 语言模式下编译器不报错，但运行时风险真实存在。

**建议修复**：用 `OSAllocatedUnfairLock` 或 Swift 6 `Synchronization.Mutex` 保护跨线程状态；渲染线程只读原子快照。

---

### 2.11 【音频】采样率硬编码 44.1kHz —— 48kHz 设备音高偏移 8.8%

**位置**：`SpatialAudioManager.swift:80, 86, 108, 109, 173, 183`

```swift
let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
self.phase += 2.0 * .pi * 1.8 / 44_100.0    // ← 硬编码
```

**已实测**：本机 `Resources/AudioCues/*.wav` 全部为 `1ch / 44100Hz / Int16`，与代码一致。但**硬件输出未必是 44.1kHz**（macOS 默认常见 48kHz，蓝牙设备更甚）。

**影响**：48kHz 设备上心跳频率 1.8Hz → 1.96Hz，风扇 58Hz → 63Hz，**所有程序化音频音高偏移约 8.8%**。

**建议修复**：
```swift
let hwRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
let format = AVAudioFormat(standardFormatWithSampleRate: hwRate, channels: 1)!
// 所有 44_100.0 替换为 hwRate
```

---

### 2.12 【音频】立体声素材连接 `AVAudioEnvironmentNode` 会崩溃

**位置**：`SpatialAudioManager.swift:287`

```swift
engine.connect(player, to: outputNode(for: kind), format: file.processingFormat)
```

`AVAudioEnvironmentNode` **只接受单声道输入**（Spatial Mixer 硬性要求）。若开发者在 `Resources/AudioCues/` 放入立体声素材（README 未强制 mono），`connect` 会抛 ObjC 异常 → **进程崩溃**。

**建议修复**：连接前强制降混为单声道：
```swift
let monoFormat = AVAudioFormat(standardFormatWithSampleRate: file.processingFormat.sampleRate, channels: 1)!
engine.connect(player, to: outputNode(for: kind), format: monoFormat)
```

---

### 2.13 【音频】音量未钳制 —— 削波爆音

**位置**：`SpatialAudioManager.swift:159-162`、`257-260`

```swift
func playWarning() { targetAmplitude = max(targetAmplitude, 0.12) }
loopPlayers["ceiling_fan"]?.volume = targetFanAmount * 0.22 * ambienceVolume
```

`playWarning()` 把振幅从 ≤0.08 直接抬到 0.12；`targetFanAmount` 未走 `clamped`。第三节课 + 警告音 + 风扇叠加可超过 1.0 → 数字削波。

**建议修复**：集中钳制 + `mainMixerNode.outputVolume` 设安全上限（如 0.85）。

---

### 2.14 【音频】渲染线程调用系统 RNG

**位置**：`SpatialAudioManager.swift:111, 389-411`

```swift
let penScratch = Float.random(in: -1...1) * self.ambientNoise * 0.055
```

`Float.random(in:)` 走 `arc4random_buf`（系统调用），在音频实时线程上属明确违规，可能导致 dropout。

**建议修复**：自实现 xorshift PRNG（纯算术、无系统调用）。

---

### 2.15 【音频】`mData!` 强制解包可能崩溃

**位置**：`SpatialAudioManager.swift:90, 116, 188`

```swift
let pointer = buffer.mData!.assumingMemoryBound(to: Float.self)
```

`mData` 为 `nil` 时（格式异常）在音频线程直接崩溃。

**建议修复**：`guard let mData = buffer.mData else { return noErr }`

---

### 2.16 【数据】`Codable` 解码失败静默吞错 —— 跨局记忆/进度/设置全量丢失

**位置**：`GameManager.swift:4036, 717-719, 721-723`；`GameModels.swift:707-713`

```swift
return (try? JSONDecoder().decode([Int: ClassmateMemory].self, from: data)) ?? [:]
```

字段增删后整表解码失败 → 静默回退到空/默认值。**玩家跨局记忆、序章进度、无障碍设置会无声丢失**。

**建议修复**：显式实现容错解码（`decodeIfPresent` + 默认值），并把 `try?` 替换为 `do/catch` + 日志 + 清除坏数据。键名已有 `.v1` 版本位，但**无任何迁移代码读取版本号**。

---

### 2.17 【数据】带 `UUID()` 的类型实现 `Equatable` 语义错误

**位置**：`GameModels.swift:561-613, 127-142`

```swift
struct EndingStory: Equatable, Identifiable { let id = UUID(); ... }
```

`Ending` 聚合了 6 个 UUID 数组，导致**内容相同的两个 `Ending` 永不相等**。这直接迫使测试作者只能写 `guard case .ending = ...` 的弱断言。

**影响**：UI 侧若用 `Ending` 做 `onChange`/diff 会**每次都触发刷新**；测试无法精确断言结局。

**建议修复**：`Equatable` 比较业务字段而非 `id`。

---

### 2.18 【数据】`StudyPeriod.period(...)` 阈值分支重叠，课间不可达

**位置**：`GameModels.swift:245-258`

```swift
if totalMinutes <= 70 { return minutes < totalMinutes - 10 ? .first : .breakOne }
if minutes < 50 { return .first }
if minutes < 60 { return .breakOne }
if totalMinutes <= 130 { return minutes < totalMinutes - 10 ? .second : .breakTwo }   // ← 问题
if minutes < 110 { return .second }
if minutes < 120 { return .breakTwo }
return .third
```

**问题**：`totalMinutes` 在 131–140 区间时 `.breakTwo` **永远不可达**（被 110/120 分支截断）。`studyHours = 2.5`（totalMinutes = 150）时第二节后的课间被吞掉。

**影响**：`applyBodyNeeds` 与 `leaveSeat` 依赖 `isBreak`，玩家的如厕需求在特定配置下无处释放。

**建议修复**：用显式阶段表替代隐式阈值链，并补参数化测试（`studyHours ∈ {1.0, 1.5, 2.0, 2.5, 3.0}` × 全区间）。

---

### 2.19 【UI】辅助功能偏好绑定直写磁盘 + 拖动抖动

**位置**：`ContentView.swift:740-752`、`:92-94`

`Toggle`/`Slider` 直接绑定 `accessibilityPreferences` 子字段，`.onChange` 每次变化都 `JSONEncoder().encode` + 写盘（`GameManager.swift:703`）。拖动灵敏度滑块时**连续触发写盘**，且可能因回写导致滑块抖动。

**建议修复**：绑定本地 `@State` 草稿，`onChange` 防抖后提交。

---

## 三、重要问题（P1 摘要）

### 3.1 游戏逻辑（P1）

| # | 问题 | 位置 |
|---|---|---|
| 1 | `execute` 不校验 `chapterOneAvailableActions`，可绕过主线 | `GameManager.swift:1631-1652` vs `841-848` |
| 2 | `supportOffer` 事件无一次性守卫，可无限复现 | `GameManager.swift:2151-2169` |
| 3 | 自由活动期间离座时长被无限延长（顺延 `endsAt` 而非冻结） | `GameManager.swift:3046-3063` |
| 4 | `finish()` 未清理定时器/Task | `GameManager.swift:2173-2181` |
| 5 | `commitClassmateMemory` 空结果整盘抹除跨局记忆 | `GameManager.swift:4007-4047` |
| 6 | 全部随机数用全局 `Double.random`，不可重现、无法种子回归 | 全项目 |

### 3.2 UI（P1）

| # | 问题 | 位置 |
|---|---|---|
| 1 | `Coupling`：`ForEach` 用 `UUID()` id，每回合全删全建 | `ContentView.swift:1300, 1409, 1467` |
| 2 | body 路径内联 `filter`/`sort`/`max`，结算页 O(n log n) 每帧重算 | `ContentView.swift:2410-2424` |
| 3 | `reduceMotion` 开关**几乎未生效**（回座 60fps 全屏动效仍播放） | `ContentView.swift:1874, 91, 328, 594` |
| 4 | 固定宽度 + 中文长文本溢出无 `lineLimit` | `ContentView.swift:1279, 818, 1422, 592` |
| 5 | 键盘快捷键大面积重叠（裸单键 vs SCNView keyDown 竞争） | `ContentView.swift:1666, 1682, 1818` |
| 6 | 禁用态无视觉降级（用户以为卡死） | `ContentView.swift:134, 2722` |
| 7 | **53 行死代码**（座位选择注释块） | `ContentView.swift:366-421` |
| 8 | 动画挂在根 ZStack，误伤无关子视图 | `ContentView.swift:91` |
| 9 | 全屏遮罩吞掉 3D 拖拽环视且无提示 | `ContentView.swift:1327-1332` |

### 3.3 3D 场景（P1）

| # | 问题 | 位置 |
|---|---|---|
| 1 | 无材质/几何体复用（上千次 `new SCNMaterial`）→ 启动卡顿 | `ClassroomSceneView.swift:2050-2079` |
| 2 | **时钟时针角度公式错误**（18:30 指向 6 点整，偏差 15°+） | `ClassroomSceneView.swift:1694-1701` |
| 3 | **教师视线硬编码座位坐标**，换座后明显穿帮 | `ClassroomSceneView.swift:1531` |
| 4 | 视锥 `.add` 混合 + 不写深度 → 穿透叠加；与判定区不一致 | `ClassroomSceneView.swift:2079-2089` |
| 5 | FOV/景深/暗角**无插值**（事件瞬间对焦抽搐）；暗角无上界（可达 2.8，夜间全黑） | `ClassroomSceneView.swift:228-236` |
| 6 | 门/柜每帧触发隐式动画 → 门叶抖动 | `ClassroomSceneView.swift:1222-1257` |
| 7 | 60fps Timer 回调内 `Task { @MainActor }` → 每秒 60 个 Task | `ClassroomSceneView.swift:151-155` |
| 8 | dwell 累积用硬编码 `1/60`，与真实时间脱钩 | `ClassroomSceneView.swift:597-617` |

### 3.4 音频/并发（P1）

| # | 问题 | 位置 |
|---|---|---|
| 1 | 每次 cue 都 `attach`/`detach` 节点（运行中）→ 爆音/卡死风险 | `SpatialAudioManager.swift:201-236` |
| 2 | `AVAudioSourceNode` 永不自动回收（12 槽位易满） | `SpatialAudioManager.swift:178-208` |
| 3 | `stop()` 未 `engine.reset()`；`AVAudioSourceNode.reset()` 是无效调用 | `SpatialAudioManager.swift:215-236` |
| 4 | `NSSound.beep()` 绕过音量控制，违反无障碍设置 | `SpatialAudioManager.swift:160, 211` |
| 5 | 读路径上带写副作用（`createDirectory`），每次扫盘 108 次 | `SpatialAudioManager.swift:333` |
| 6 | 素材可解码性未校验，`assetStatus` 误报"可用" | `SpatialAudioManager.swift:240-245` |
| 7 | `ClassroomCoordinator` **无 `deinit`**，监听器依赖 `dismantleNSView` | `ClassroomSceneView.swift:800-815` |

### 3.5 测试（P1）

| # | 问题 | 位置 |
|---|---|---|
| 1 | 测试依赖真实墙钟 `Task.sleep` / `Thread.sleep` → 必然 flaky | `MovementAndEventTests.swift:573-592` |
| 2 | 断言过弱（只断"非空"/三选一关键词） | `MovementAndEventTests.swift:386-399` |
| 3 | helper 手改内部状态，绕过真实初始化路径 | `MovementAndEventTests.swift:667-694` |
| 4 | `UserDefaults.standard` 未隔离，测试间互相污染 | `GameManager.swift:128` |
| 5 | `PrologueBeatID.allCases` 顺序是隐式契约，无断言校验 | `PrologueModels.swift:16-19` |

---

## 四、测试覆盖缺口（关键）

`MovementAndEventTests.swift`（695 行 / 40 个测试）**零覆盖**以下核心路径：

| # | 关键路径 | 生产者位置 | 风险 |
|---|---|---|---|
| 1 | `calculateEnding()` 全部 6 个结局分支 | `GameManager.swift:2183-2259` | **P0** |
| 2 | `finish()` + `commitClassmateMemory()` 持久化 | `:2173-2181, 4007-4047` | **P0** |
| 3 | 跨局记忆生效（`finish` → 新实例 → `startGame`） | `:128, 4113-4126` | **P0** |
| 4 | `continueAfterEvent()` 回合推进与 `maxTurns` 边界 | `:1924-1949` | **P0** |
| 5 | `teacherTurn()` 巡逻/被发现/假巡视/后门观察 | `:1951-2048` | **P0** |
| 6 | `applyBodyNeeds()` 口渴/饥饿/如厕累积 | `:2541-2570` | **P0** |
| 7 | `checkCriticalState()` 同学崩溃/孤独/支持保护 | `:2109-2171` | **P0** |
| 8 | `resolveEventChoice(_:)` 全部分支 | `:3065+` | **P0** |
| 9 | `executeTeacherAction(_:)` 8 个教师动作 | `:1794+` | **P0** |
| 10 | `StudyPeriod.period(...)` 阈值边界 | `GameModels.swift:245-258` | **P0** |
| 11 | `PrologueState`/`AccessibilityPreferences` Codable 往返 | `GameModels.swift:101-120` | **P0** |
| 12 | `ClassmateMemory` Codable 往返 | `GameModels.swift:707-713` | **P0** |

**测试卫生**：无 `XCTSkip`、无注释掉的测试、无 `#if` 排除——问题在**覆盖面窄**（40 个测试中 22 个集中在序章/自由漫游/视角）。

---

## 五、工程与仓库问题

| # | 问题 | 说明 |
|---|---|---|
| 1 | `Resources/Characters/` 是**空目录** | `Package.swift` 未声明该资源；`git ls-files` 中无文件 |
| 2 | 座位选择 API 不存在 | `selectChapterSeat`/`confirmChapterSeatSelection` 在 `GameManager` 中未定义 |
| 3 | `makeGlasses()` 死代码 | `ClassroomSceneView.swift:2236-2242`，无调用点 |
| 4 | `updatePlayerLocker` 重复重载 | `ClassroomSceneView.swift:1245-1249` |
| 5 | `isChapterOneSeatSelectionPresented` 死标志 | `GameManager.swift:68`，恒为 false |
| 6 | `.gitignore` 未排除 `.codex/` | 本地工具配置已入库 |

**值得肯定**：
- 无 `try!`/`as!`/`fatalError`/`precondition`/`assert`/`print` 残留
- 无 TODO/FIXME/HACK
- 无硬编码绝对路径
- 32 处数组下标**全部有 guard/indices 保护**，无越界隐患
- 4 个 `UserDefaults` key 命名前缀统一、带版本号、无碰撞

---

## 六、优先级修复路线图

### 第一阶段：止血（1–2 天）

| 优先级 | 问题 | 工作量 |
|---|---|---|
| 1 | **固定随机座位**（2.1）—— 同时修复测试 25% 失败率 | 1 行 |
| 2 | 回座 Task 取消守卫（2.2） | 2 行 |
| 3 | `startGame` 状态重置（2.4） | 5 行 |
| 4 | 结局优先级修正（2.5） | 3 行 |
| 5 | 黑板文本去重（2.7） | 3 行 |
| 6 | `chairNodesBySeat` 字典（2.8） | ~20 行 |
| 7 | 门外剪影 Action 清理（2.9） | ~5 行 |

### 第二阶段：核心重构（3–5 天）

| 优先级 | 问题 | 工作量 |
|---|---|---|
| 8 | 拆分 `ContentView` 订阅范围（2.6） | 2 天 |
| 9 | 音频线程安全 + 采样率 + 钳制（2.10–2.15） | 2 天 |
| 10 | `Codable` 容错解码（2.16） | 半天 |
| 11 | 课间线索推进互斥（2.3） | 半天 |

### 第三阶段：质量提升（1 周+）

- `Equatable` 语义修正（2.17）→ 解锁结局测试
- `StudyPeriod` 参数化 + 测试（2.18）
- 补测试：结局/回合/记忆/巡逻（覆盖缺口表 12 项）
- `ClassroomSceneView` 材质缓存 + 插值（3.3）
- `reduceMotion` 全面接入（3.2）

---

## 七、方法论说明

- **6 个并行子代理**分别负责：GameManager 状态机 / ContentView UI / ClassroomSceneView 3D / SpatialAudioManager + 并发 / GameModels + 测试 / 实测验证
- **主审交叉验证**：对代理的关键结论进行了独立复核，**纠正了 1 处误判**（代理称"摸鱼大师结局不可达"，实测发现 `exposure +=` 有 36 处增量，"摸鱼大师"**确实可达**）
- **实测证据**：`swift build`（0 warning）、`swift test`（1 失败 / 40）、运行探测（RSS 148MB / CPU 36%）、12 次重复测试（25% 失败率）
- **本报告未修改任何源码**；GameManager 子代理另行生成了 `docs/GameManager-review.md` 详细版

---

*报告生成：2026-09-30 ｜ 分支 `freatures/wyq` @ `1e5ce0e`*
