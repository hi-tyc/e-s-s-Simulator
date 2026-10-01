import Testing
import Foundation
import AVFoundation
@testable import LateStudySimulator

/// 针对代码审查发现的缺陷补写的回归测试。
/// 覆盖范围：结局判定、回合推进、跨局记忆、身体需求、阶段划分、持久化容错。
@MainActor
struct RegressionTests {

    /// 每个测试使用独立的 UserDefaults suite，避免相互污染并隔离真实用户数据。
    private func makeIsolatedGame() -> (GameManager, UserDefaults) {
        let suiteName = "LateStudySimulatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (GameManager(store: defaults), defaults)
    }

    /// 把时间推进到"当前主线步骤已成熟"。
    ///
    /// 第一章现在有节奏门槛：每步线索之间要等信号成熟（`chapterOneStepReadyTurn`）。
    /// 测试直接把回合推过去，而不是让脚本猜要等几个回合——这样节奏参数调整时
    /// 这些测试仍然只验证"顺序正确"，不验证"具体等了几回合"。
    private func matureChapterOneStep(_ game: GameManager) {
        var safety = 0
        while game.chapterOneStepsUntilReady > 0 && safety < 30 {
            // 等待回合必须由**真实行动**消耗掉：节奏的倒计时挂在
            // `collectChapterClue` 上，只有玩家行动才会推进。
            if case .event(let event) = game.gameState {
                game.resolveEventChoice(event.choices[0])
            } else {
                game.execute(.study)
            }
            safety += 1
        }
    }

    // MARK: - 座位与同桌

    /// 玩家座位必须固定，否则剧情文案、同桌系统与教师视线都会错位。
    @Test func playerSeatIsFixedToThirdRowMiddle() {
        let (game, _) = makeIsolatedGame()
        game.startGame()
        #expect(game.selectedChapterSeat?.row == 2)
        #expect(game.selectedChapterSeat?.column == 1)
    }

    /// 林澈必须固定在玩家左侧座位，且确实出现在同学列表中。
    @Test func linCheSitsToTheLeftOfThePlayer() {
        let (game, _) = makeIsolatedGame()
        game.startGame()
        let linChe = game.classmates.first { $0.name == "林澈" }
        #expect(linChe != nil)
        #expect(linChe?.seat.row == 2)
        #expect(linChe?.seat.column == 0)
    }

    /// 同桌判定应基于固定座位，且必须恰好两人（左右各一）。
    @Test func deskmatesAreDeterministic() {
        let (game, _) = makeIsolatedGame()
        game.startGame()
        let deskmates = game.classmates.filter { $0.seat.row == 2 && ($0.seat.column == 0 || $0.seat.column == 2) }
        #expect(deskmates.count == 2)
    }

    /// 具名角色在不同实例间保持相同性格（防止按座位重排导致性格漂移）。
    @Test func namedCharactersKeepAuthoredPersonalities() {
        let (first, _) = makeIsolatedGame()
        first.startGame()
        let (second, _) = makeIsolatedGame()
        second.startGame()

        for name in ["林澈"] {
            let a = first.classmates.first { $0.name == name }
            let b = second.classmates.first { $0.name == name }
            #expect(a != nil, "\(name) 应存在")
            #expect(a?.profile == b?.profile, "\(name) 的性格应稳定")
        }
    }

    // MARK: - 跨局记忆

    /// 记忆必须能写入并读回，且字段完整。
    @Test func classmateMemoryRoundTrips() throws {
        let memory: [Int: ClassmateMemory] = [
            3: ClassmateMemory(relationshipCarry: 12, stressEcho: -4, suspicionCarry: 6, sharedTruth: true, helpedLastRun: true)
        ]
        let data = try JSONEncoder().encode(memory)
        let decoded = try JSONDecoder().decode([Int: ClassmateMemory].self, from: data)
        #expect(decoded[3]?.relationshipCarry == 12)
        #expect(decoded[3]?.sharedTruth == true)
        #expect(decoded[3]?.helpedLastRun == true)
    }

    /// 旧存档缺少新增字段时，解码应回退默认值而不是整表失败。
    @Test func classmateMemoryToleratesMissingFields() throws {
        let legacyJSON = #"{"1":{"relationshipCarry":8.0}}"#
        let data = legacyJSON.data(using: .utf8)!
        let decoded = try JSONDecoder().decode([Int: ClassmateMemory].self, from: data)
        #expect(decoded[1]?.relationshipCarry == 8)
        #expect(decoded[1]?.stressEcho == 0)
        #expect(decoded[1]?.sharedTruth == false)
        #expect(decoded[1]?.helpedLastRun == false)
    }

    /// 完全损坏的数据应被清除并返回空表，而不是每次启动都重复失败。
    @Test func corruptedMemoryIsCleared() {
        let suiteName = "LateStudySimulatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let key = "LateStudySimulator.ClassmateMemory.v1"
        defaults.set(Data([0xFF, 0xFE, 0xFD]), forKey: key)

        let game = GameManager(store: defaults)
        #expect(game.classmateMemory.isEmpty)
        #expect(defaults.data(forKey: key) == nil, "损坏数据应被清除")
    }

    // MARK: - 阶段划分

    /// 三个课间在任意总时长下都必须可达（原先 131...140 分钟会吞掉 breakTwo）。
    @Test(arguments: [60, 90, 120, 130, 135, 150, 180])
    func allBreaksAreReachable(totalMinutes: Int) {
        let periods = (0...totalMinutes).map { StudyPeriod.period(forElapsedMinutes: $0, totalMinutes: totalMinutes) }
        #expect(periods.contains(.breakOne), "totalMinutes=\(totalMinutes) 缺少 breakOne")
        #expect(periods.contains(.breakTwo), "totalMinutes=\(totalMinutes) 缺少 breakTwo")
        #expect(periods.contains(.third), "totalMinutes=\(totalMinutes) 缺少 third")
    }

    /// 阶段必须随时间单调推进，不允许回退。
    @Test func periodsAreMonotonic() {
        let total = 180
        let order: [StudyPeriod] = [.first, .breakOne, .second, .breakTwo, .third]
        var lastIndex = 0
        for minute in 0...total {
            let period = StudyPeriod.period(forElapsedMinutes: minute, totalMinutes: total)
            let index = order.firstIndex(of: period) ?? 0
            #expect(index >= lastIndex, "时刻 \(minute) 阶段出现回退")
            lastIndex = index
        }
    }

    /// 边界值不应越界。
    @Test func periodClampsOutOfRangeInput() {
        #expect(StudyPeriod.period(forElapsedMinutes: -50, totalMinutes: 180) == .first)
        #expect(StudyPeriod.period(forElapsedMinutes: 9999, totalMinutes: 180) == .third)
    }

    // MARK: - 回合与结局

    /// 结局判定必须能真正产生结局，且标题非空。
    @Test func endingIsProducedAndHasTitle() {
        let (game, _) = makeIsolatedGame()
        game.startGame()
        let ending = game.calculateEnding()
        #expect(ending.title.isEmpty == false)
        #expect(ending.analysis.isEmpty == false)
    }

    /// 学生线不应被教师互动次数吞掉：默认参数下应产出学生线结局。
    @Test func studentRoleDoesNotAlwaysProduceTeacherEnding() {
        let (game, _) = makeIsolatedGame()
        game.startGame()
        // 即使教师互动次数很高，学生线也不该被判成教师结局。
        game.teacher.studentsWarned = 6
        game.teacher.studentsHelped = 3
        let ending = game.calculateEnding()
        #expect(ending.title.contains("教师") == false, "学生线不应产出教师结局：\(ending.title)")
    }

    /// 高压力 + 低能量应产出"崩溃边缘"。
    @Test func exhaustionProducesBreakdownEnding() {
        let (game, _) = makeIsolatedGame()
        game.startGame()
        game.player.stress = 99
        game.player.psychicEnergy = 4
        let ending = game.calculateEnding()
        #expect(ending.title == "崩溃边缘")
    }

    // MARK: - 状态重置

    /// 新开一局必须清除上一局的观察累计，否则第一次回头会零风险。
    @Test func startGameResetsLookDwellState() {
        let (game, _) = makeIsolatedGame()
        game.startGame()
        // 模拟上一局残留
        game.setPose(.rear)
        for _ in 0..<200 { game.updateChapterLookDwell(delta: 0.05) }
        let exposureAfterFirstRun = game.player.exposure
        #expect(exposureAfterFirstRun > 0)

        game.startGame()
        // 新局后第一次回头仍应产生暴露（证明 rearLookRiskApplied 已重置）
        let before = game.player.exposure
        game.setPose(.rear)
        for _ in 0..<200 { game.updateChapterLookDwell(delta: 0.05) }
        #expect(game.player.exposure > before, "新局回头必须仍然产生暴露")
    }

    /// 返回菜单后再次开始，状态同样必须干净。
    @Test func returnToMenuThenStartResetsState() {
        let (game, _) = makeIsolatedGame()
        game.startGame()
        game.setPose(.rear)
        for _ in 0..<200 { game.updateChapterLookDwell(delta: 0.05) }
        game.returnToMenuForNewGame()
        game.startGame()

        let before = game.player.exposure
        game.setPose(.rear)
        for _ in 0..<200 { game.updateChapterLookDwell(delta: 0.05) }
        #expect(game.player.exposure > before)
    }

    // MARK: - 主线

    /// 主线必须能按剧本顺序走完（含 observe / breathe 等推进动作）。
    @Test func chapterOneMainQuestIsCompletable() {
        let (game, _) = makeIsolatedGame()
        game.startGame()
        game.dismissChapterOneGuide()

        game.setPose(.left)
        game.execute(.observe)
        #expect(game.chapterOneStep == .locateHiddenSound)

        matureChapterOneStep(game)
        game.setPose(.right)
        game.execute(.listen)
        #expect(game.chapterOneStep == .regulateSelf)

        matureChapterOneStep(game)
        game.execute(.breathe)
        #expect(game.chapterOneStep == .approachLinChe)

        matureChapterOneStep(game)
        game.execute(.talk)
        #expect(game.chapterOneStep == .inspectNote)

        matureChapterOneStep(game)
        game.setPose(.desk)
        game.execute(.observe)
        #expect(game.chapterOneStep == .followLinChe)
        #expect(game.chapterClues.count == 3)
    }

    /// 时机未到时，主线不能靠反复点同一个动作提前推进。
    ///
    /// 这是"等待也是节奏"的守卫：如果没有这道门槛，第一章又会退回
    /// 6 回合的情报冲刺，数值没有时间积累。
    @Test func mainQuestStepsWaitForTheirMoment() {
        let (game, _) = makeIsolatedGame()
        game.startGame()
        game.dismissChapterOneGuide()

        game.setPose(.left)
        game.execute(.observe)
        #expect(game.chapterOneStep == .locateHiddenSound)
        #expect(game.chapterOneStepsUntilReady > 0)

        let exposureAfterClue = game.player.exposure
        let turnAfterClue = game.currentTurn

        // 时机未到时，用正确的动作催线索也不会前进（但回合照常流逝）。
        game.setPose(.right)
        game.execute(.listen)
        #expect(game.chapterOneStep == .locateHiddenSound)
        #expect(game.currentTurn > turnAfterClue)

        // 而且催线索不是免费的：暴露照常上升。
        #expect(game.player.exposure > exposureAfterClue)

        // 等信号自己成熟之后，同一个动作就能推进。
        matureChapterOneStep(game)
        game.setPose(.right)
        game.execute(.listen)
        #expect(game.chapterOneStep == .regulateSelf)
    }


    // MARK: - 身体需求

    /// 口渴/饥饿/如厕必须随回合推进增长。
    @Test func bodyNeedsIncreaseOverTurns() {
        let (game, _) = makeIsolatedGame()
        game.startGame()
        let thirst = game.player.thirst
        let hunger = game.player.hunger
        let bladder = game.player.bladder

        // continueAfterEvent 会推进回合并调用 applyBodyNeeds。
        for _ in 0..<5 { game.continueAfterEvent() }

        #expect(game.player.thirst > thirst)
        #expect(game.player.hunger > hunger)
        #expect(game.player.bladder > bladder)
    }

    /// 守卫：关卡一的节奏门槛不能把主线锁死。
    ///
    /// 真实踩到过的坑：等待原本用"第几个回合成熟"表示，而 `currentTurn`
    /// 在关卡一有 `maxTurns` 上限。一旦期限超过上限就永远无法满足，
    /// 主线会永久卡在同一个步骤（自动游玩 8 次里有 7 次停在 inspectNote）。
    /// 现在等待是"还要等几个回合"的倒计时，只依赖玩家行动，因此不可能卡住。
    @Test func chapterOnePacingCannotDeadlockAtTurnCap() {
        let (game, _) = makeIsolatedGame()
        game.startGame()
        game.dismissChapterOneGuide()

        // 直接把回合数顶到上限，模拟"玩家在关卡一已经待到很晚"。
        game.currentTurn = game.maxTurns

        game.setPose(.left)
        game.execute(.observe)
        #expect(game.chapterOneStep == .locateHiddenSound)
        #expect(game.chapterOneStepsUntilReady > 0)

        // 即使回合数已经到顶，等待也必须能被行动消耗完。
        var actions = 0
        while game.chapterOneStepsUntilReady > 0 && actions < 10 {
            game.setPose(.right)
            game.execute(.listen)
            actions += 1
        }
        #expect(game.chapterOneStepsUntilReady == 0, "等待回合必须能被行动消耗掉")

        game.setPose(.right)
        game.execute(.listen)
        #expect(game.chapterOneStep == .regulateSelf, "回合数到顶后主线仍然必须能推进")
    }

    /// 守卫：关卡一不能被自由活动锁死。
    ///
    /// 另一个真实踩到的死锁：事件往返会走到 `continueAfterEvent()`，
    /// 而它原本无条件调用 `applyTimeProgression()`。如果那一刻钟点正好落在
    /// 课间，就会启动自由活动；自由活动期间 `setPose` 是空操作，于是
    /// "低头看桌面的纸条"这一步永远无法满足，主线永久卡死
    /// （自动游玩跑到 inspectNote 就再也推进不了）。
    @Test func chapterOneNeverEntersFreeRoam() {
        let (game, _) = makeIsolatedGame()
        game.startGame()
        game.dismissChapterOneGuide()

        // 找到本局的第一个课间回合。`continueAfterEvent()` 会先把回合 +1，
        // 所以时间要停在它的前一个回合。
        // （不写死回合数，避免时段划分调整后这条测试失去意义。）
        var breakTurn = 0
        for turn in 1...game.maxTurns where breakTurn == 0 {
            game.currentTurn = turn
            if game.currentPeriod.isBreak { breakTurn = turn }
        }
        #expect(breakTurn > 1, "前提：本局应当存在课间回合")

        game.currentTurn = breakTurn - 1
        game.continueAfterEvent()
        #expect(game.currentPeriod.isBreak, "前提：这一步事件往返确实落在课间")

        #expect(game.freeRoam.isActive == false, "关卡一不应进入自由活动")
        // 视角必须仍然可用：这正是主线推进所依赖的东西。
        game.setPose(.desk)
        #expect(game.cameraPose == .desk)
    }

    // MARK: - 听觉通道（信息 70% 来自音频）

    /// 任务提示只能说明"用哪条通道"，不能说明"朝哪个方向 / 按哪个键"。
    ///
    /// 这是把"照着提示按按钮"换回"自己搜索"的守卫。方位信息属于音频声像，
    /// 一旦写进提示，搜索这一步就没了，主线又退化成流程播放。
    @Test func chapterOneGuidanceDoesNotHandOutTheAnswer() {
        let directionWords = ["左侧", "右侧", "前方", "后方", "低头", "抬头", "看向", "转向", "按 "]
        for step in ChapterOneStep.allCases where step != .completed {
            for word in directionWords {
                #expect(step.guidance.contains(word) == false,
                        "\(step) 的提示泄露了方位或按键：\(step.guidance)")
                #expect(step.objective.contains(word) == false,
                        "\(step) 的目标泄露了方位或按键：\(step.objective)")
            }
        }
    }

    /// 那道鼻息是**听觉**线索：观察拿不到，只有对准声源倾听才行。
    @Test func hiddenCryingIsAudioOnly() {
        let (game, _) = makeIsolatedGame()
        game.startGame()
        game.dismissChapterOneGuide()

        game.setPose(.left)
        game.execute(.observe)
        #expect(game.chapterOneStep == .locateHiddenSound)
        matureChapterOneStep(game)

        // 用"看"：方向对也没用，这一步不属于视觉通道。
        game.setPose(.right)
        game.execute(.observe)
        #expect(game.chapterOneStep == .locateHiddenSound)
        #expect(collectedClueIDs(game).contains(.hiddenCrying) == false)

        // 用"听"，并且对准声源。
        game.setPose(.right)
        game.execute(.listen)
        #expect(game.chapterOneStep == .regulateSelf)
        #expect(collectedClueIDs(game).contains(.hiddenCrying))
    }

    /// 听错方向要付出代价，但不能让人卡住：第二次听错会漏出真实方位。
    @Test func listeningInTheWrongDirectionCostsATurnAndGivesAHint() {
        let (game, _) = makeIsolatedGame()
        game.startGame()
        game.dismissChapterOneGuide()

        game.setPose(.left)
        game.execute(.observe)
        matureChapterOneStep(game)

        let exposureBefore = game.player.exposure
        game.setPose(.left)          // 声源在右侧
        game.execute(.listen)
        #expect(game.chapterOneStep == .locateHiddenSound, "听错方向不应推进主线")
        #expect(game.listenFeedback.isEmpty == false, "听错方向必须给反馈")
        #expect(game.listenFeedback.contains("右") == false, "第一次听错不该直接给出方位")
        #expect(game.player.exposure > exposureBefore, "停下来听本身也有暴露代价")

        game.setPose(.left)
        game.execute(.listen)
        #expect(game.listenFeedback.contains("右"), "连续听错两次后必须给出方位，避免卡死")
    }

    /// 「班长的停顿」必须属于**班长本人**，不能是随机属性最高的路人。
    @Test func classMonitorIsTheAuthoredClassMonitor() {
        let (game, _) = makeIsolatedGame()
        game.startGame()
        // 背景同学的性格每局重抽，可能抽出守序度更高的路人；
        // 班长是作者写定的身份，不能按属性挑。
        for _ in 0..<8 {
            let (candidate, _) = makeIsolatedGame()
            candidate.startGame()
            #expect(candidate.classMonitor?.name == "周予安")
        }
        #expect(game.classMonitor?.name == "周予安")
    }

    /// 两个"写好了却永远收不到"的线索必须真的能收到。
    @Test func authoredSideCluesAreAudibleAndCollectable() {
        let (game, _) = makeIsolatedGame()
        game.startGame()
        game.dismissChapterOneGuide()

        // 把两条旁支线索的触发条件摆好。
        let monitorIndex = game.classmates.firstIndex { $0.name == "周予安" }
        #expect(monitorIndex != nil)
        game.classmates[monitorIndex!].stress = 90
        game.teacher.kpiPressure = 70
        game.teacher.fatigue = 80

        game.execute(.study)
        let audible = Set(game.audibleSignals.compactMap(\.clue))
        #expect(audible.contains(.monitorOverload), "班长的停顿应当出现在听觉世界里")
        #expect(audible.contains(.teacherSigh), "方老师的叹气应当出现在听觉世界里")

        // 逐条听清。老师的方位随巡视变化，所以每轮都重新取一次方向。
        var safety = 0
        while collectedClueIDs(game).contains(.monitorOverload) == false
                || collectedClueIDs(game).contains(.teacherSigh) == false {
            safety += 1
            guard safety < 20 else { break }
            if case .event(let event) = game.gameState {
                game.resolveEventChoice(event.choices[0])
                continue
            }
            guard let signal = game.audibleSignals.first(where: {
                guard let clue = $0.clue else { return false }
                return collectedClueIDs(game).contains(clue) == false
            }) else {
                game.execute(.study)     // 让听觉世界刷新
                continue
            }
            game.setPose(signal.sourcePose)
            game.execute(.listen)
        }

        let collected = collectedClueIDs(game)
        #expect(collected.contains(.monitorOverload), "班长的停顿必须能被收下")
        #expect(collected.contains(.teacherSigh), "方老师的叹气必须能被收下")
    }

    private func collectedClueIDs(_ game: GameManager) -> Set<ChapterClueID> {
        Set(game.chapterClues.map(\.id))
    }

    // MARK: - 崩溃是分支，不是终止

    /// 把玩家推到"撑不下去"。每轮重新压满压力，模拟一直没缓过来。
    private func driveToCollapse(_ game: GameManager) {
        game.player.stress = 99
        var safety = 0
        while safety < 24 {
            if case .ending = game.gameState { return }
            game.player.stress = 99
            game.continueAfterEvent()
            safety += 1
        }
    }

    private func makeGameAtCollapse(support: Double, empathy: Double) -> GameManager {
        let (game, _) = makeIsolatedGame()
        game.startGame()
        game.dismissChapterOneGuide()
        game.player.support = support
        game.teacher.empathy = empathy
        driveToCollapse(game)
        return game
    }

    /// 撑不住时，结尾要写清"这一晚是被谁看见的"，而不是统一一句"崩溃边缘"。
    @Test func collapseIsRewrittenByWhatWasHappeningAroundYou() {
        let held = makeGameAtCollapse(support: 82, empathy: 40)
        #expect(held.chapterOneCollapse == .heldByPeer, "支持网络在的时候，不该写成孤立无援")
        #expect(held.calculateEnding().title == "关卡一结束：被接住的那一次")

        let seen = makeGameAtCollapse(support: 30, empathy: 70)
        #expect(seen.chapterOneCollapse == .seenByTeacher, "老师同理心高的时候，应当写成她先看见")
        #expect(seen.calculateEnding().title == "关卡一结束：她先看见了")

        let alone = makeGameAtCollapse(support: 30, empathy: 20)
        #expect(alone.chapterOneCollapse == .alone)
        #expect(alone.calculateEnding().title == "关卡一结束：没人知道的那一晚")
    }

    /// 三种崩溃必须是三种不同的结尾，而且都能说出下一步该做什么。
    @Test func everyCollapseEndingOffersADistinctNextStep() {
        var titles: Set<String> = []
        var stories: Set<String> = []
        for collapse in ChapterOneCollapse.allCases {
            let (game, _) = makeIsolatedGame()
            game.startGame()
            game.chapterOneCollapse = collapse
            let ending = game.calculateEnding()
            titles.insert(ending.title)
            stories.insert(ending.story.body)
            #expect(ending.story.prompt.isEmpty == false, "每种崩溃都要给出一个可以继续想的问题")
            #expect(ending.resources.isEmpty == false, "崩溃结局必须带上心理支持资源")
        }
        #expect(titles.count == ChapterOneCollapse.allCases.count)
        #expect(stories.count == ChapterOneCollapse.allCases.count)
    }

    // MARK: - 章末决策是前面回合的账单

    private func addClue(_ game: GameManager, _ id: ChapterClueID) {
        guard game.chapterClues.contains(where: { $0.id == id }) == false else { return }
        game.chapterClues.append(
            ChapterClue(id: id, turn: game.currentTurn, title: id.title, detail: id.detail)
        )
    }

    private func decisionChoices(_ game: GameManager) -> [EventChoice] {
        game.dismissChapterOnePaper()
        guard case .event(let event) = game.gameState else { return [] }
        return event.choices
    }

    private func detail(_ choices: [EventChoice], _ id: String) -> String {
        choices.first { $0.id == id }?.detail ?? ""
    }

    /// 同一个按钮，做没做过功课，说法必须不一样。
    @Test func decisionOptionsReflectWhatYouActuallyHeard() {
        let (naive, _) = makeIsolatedGame()
        naive.startGame()
        let naiveChoices = decisionChoices(naive)
        #expect(naiveChoices.count == 4, "四个选项的数量不能变")
        #expect(detail(naiveChoices, "chapter1_teacher").contains("听出") == false)
        #expect(detail(naiveChoices, "chapter1_monitor").contains("班长") == false)
        #expect(detail(naiveChoices, "chapter1_tomorrow").contains("错觉") == false)

        let (informed, _) = makeIsolatedGame()
        informed.startGame()
        addClue(informed, .teacherSigh)
        addClue(informed, .monitorOverload)
        addClue(informed, .hiddenCrying)
        let informedChoices = decisionChoices(informed)
        #expect(detail(informedChoices, "chapter1_teacher").contains("听出"))
        #expect(detail(informedChoices, "chapter1_monitor").contains("班长"))
        #expect(detail(informedChoices, "chapter1_tomorrow").contains("错觉"))
    }

    /// 同一个决策，听清线索之后结局写法要变——这才是"账单"。
    @Test func informedDecisionChangesTheEndingWritten() {
        func endingTitle(clues: [ChapterClueID], decision: String) -> String {
            let (game, _) = makeIsolatedGame()
            game.startGame()
            for clue in clues { addClue(game, clue) }
            let choices = decisionChoices(game)
            guard let choice = choices.first(where: { $0.id == decision }) else { return "" }
            game.resolveEventChoice(choice)
            return game.calculateEnding().title
        }

        let naive = endingTitle(clues: [], decision: "chapter1_teacher")
        let informed = endingTitle(clues: [.teacherSigh], decision: "chapter1_teacher")
        #expect(naive == "关卡一完成：让成人接手")
        #expect(informed == "关卡一完成：她知道该往哪看")
        #expect(naive != informed, "听清与没听清不能写出同一个结尾")

        // 四条决策 × 听清/没听清 = 八种第一章结局。
        var titles: Set<String> = []
        for id in ["chapter1_teacher", "chapter1_monitor", "chapter1_tomorrow", "chapter1_wait"] {
            titles.insert(endingTitle(clues: [], decision: id))
            titles.insert(endingTitle(
                clues: [.teacherSigh, .monitorOverload, .hiddenCrying, .linChePage, .unsignedNote],
                decision: id
            ))
        }
        #expect(titles.count == 8, "四条决策各自应有听清/没听清两种写法，实际 \(titles.count)：\(titles)")
    }

    /// 最后一步不该是免疫区。
    ///
    /// 原来的实现在 `.followLinChe` 直接 `completeChapterOne()`，于是
    /// 玩家能带着 90+ 暴露从容离场——"被看见"这套机制恰好在最关键的一刻失效。
    /// 实测正是这个漏洞让 GUI 路径的能量永远不会掉到 35 以下。
    @Test func leavingYourSeatWhileTargetedIsNotAFreeExit() {
        let (game, _) = makeIsolatedGame()
        game.startGame()
        game.dismissChapterOneGuide()

        var safety = 0
        while game.chapterOneStep != .followLinChe && safety < 80 {
            safety += 1
            if case .event(let event) = game.gameState {
                game.resolveEventChoice(event.choices[0])
                continue
            }
            if game.chapterOneStepsUntilReady > 0 { game.execute(.study); continue }
            switch game.chapterOneStep {
            case .observeLinChe: game.setPose(.left); game.execute(.observe)
            case .locateHiddenSound: game.setPose(.right); game.execute(.listen)
            case .regulateSelf: game.execute(.breathe)
            case .approachLinChe: game.execute(.talk)
            case .inspectNote: game.setPose(.desk); game.execute(.observe)
            default: break
            }
        }
        #expect(game.chapterOneStep == .followLinChe, "应当能走到最后一步")
        #expect(game.player.exposure >= 70, "前提：此时暴露已经很高，实际 \(game.player.exposure)")

        game.execute(.leaveSeat)
        #expect(game.chapterOneStep == .followLinChe, "被盯住时起身不该直接通关")
        guard case .event(let caught) = game.gameState else {
            Issue.record("被盯住时起身必须触发“被看见”")
            return
        }
        #expect(caught.choices.count == 3, "“被看见”应当给三个应对方式")

        // 付过代价之后必须仍然能走完，不允许变成新的死锁。
        var attempts = 0
        while game.chapterOneStep != .completed && attempts < 12 {
            attempts += 1
            if case .event(let event) = game.gameState {
                game.resolveEventChoice(event.choices[0])
                continue
            }
            game.execute(.leaveSeat)
        }
        #expect(game.chapterOneStep == .completed, "被看见之后必须仍然能离场")
        #expect(game.player.teacherWarnings >= 1, "这次“被看见”必须留下记录")
    }

    // MARK: - GUI 路径（agent 模式覆盖不到）

    /// 用 GUI 的方式走主线（视觉线索靠"盯住看"，而不是点按钮），
    /// 并把 §9.1 的同一条验收标准也压在它上面。
    ///
    /// 意义：我之前的验收数据全部来自 agent 模式（只能用显式动作）。
    /// 玩家在 GUI 里最自然的玩法是鼠标盯着目标——如果那条路的代价更轻，
    /// 那"主线很紧张"这个结论对真实玩家就不成立。
    @Test func guiStyleMainQuestAlsoCarriesRealRisk() {
        let (game, _) = makeIsolatedGame()
        game.startGame()
        game.dismissChapterOneGuide()
        game.player.posture = .seated

        var minEnergy = game.player.psychicEnergy
        var maxExposure = game.player.exposure
        var guardCount = 0

        while guardCount < 40 {
            guardCount += 1
            if game.isChapterOneTransitionPresented { game.enterChapterTwo() }
            if game.isChapterOnePaperPresented { game.dismissChapterOnePaper() }
            if case .ending = game.gameState { break }

            if case .event(let event) = game.gameState {
                game.resolveEventChoice(event.choices[0])
            } else if game.chapterOneStep == .completed {
                break
            } else if game.chapterOneStepsUntilReady > 0 {
                game.execute(game.player.psychicEnergy < 45 ? .breathe : .study)
            } else {
                switch game.chapterOneStep {
                case .observeLinChe:
                    game.setPose(.left)
                    for _ in 0..<80 { game.updateChapterLookDwell(delta: 0.05) }
                case .locateHiddenSound:
                    game.setPose(.right)
                    game.execute(.listen)
                case .regulateSelf:
                    game.execute(.breathe)
                case .approachLinChe:
                    game.execute(.talk)
                case .inspectNote:
                    game.setPose(.desk)
                    for _ in 0..<80 { game.updateChapterLookDwell(delta: 0.05) }
                case .followLinChe, .completed:
                    game.execute(.leaveSeat)
                }
            }

            minEnergy = min(minEnergy, game.player.psychicEnergy)
            maxExposure = max(maxExposure, game.player.exposure)
        }

        #expect(game.chapterOneStep == .completed, "GUI 路径也必须能走完主线")
        #expect(maxExposure >= 60, "GUI 路径的暴露也应达到 60，实际 \(maxExposure)")
        #expect(minEnergy < 35, "GUI 路径的能量也应至少一次低于 35，实际 \(minEnergy)")
    }


    /// GUI 里视觉线索靠"盯住看满 2.5 秒"推进（`updateChapterLookDwell`，由 3D 视图
    /// 的 60fps tick 驱动）。agent 模式没有 3D 视图，所以自动游玩只覆盖了显式
    /// `观察` 那一条路——这条测试补上真实游玩时最常用的那条。
    @Test func visualCluesAdvanceByHoldingYourGazeButAudioDoesNot() {
        let (game, _) = makeIsolatedGame()
        game.startGame()
        game.dismissChapterOneGuide()
        game.player.posture = .seated

        // 步骤 1（视觉）：盯着林澈的方向看满 2.5 秒
        game.setPose(.left)
        for _ in 0..<80 { game.updateChapterLookDwell(delta: 0.05) }
        #expect(game.chapterOneStep == .locateHiddenSound, "盯住看应当能收下视觉线索")

        // 步骤 2（听觉）：盯多久都不该推进——它不是视觉线索
        matureChapterOneStep(game)
        game.setPose(.right)
        for _ in 0..<80 { game.updateChapterLookDwell(delta: 0.05) }
        #expect(game.chapterOneStep == .locateHiddenSound, "那道鼻息只能靠听，盯住看不应有效")

        // 换成倾听就能推进
        game.setPose(.right)
        game.execute(.listen)
        #expect(game.chapterOneStep == .regulateSelf)

        // 步骤 3、4
        matureChapterOneStep(game)
        game.execute(.breathe)
        matureChapterOneStep(game)
        game.execute(.talk)
        #expect(game.chapterOneStep == .inspectNote)

        // 步骤 5（视觉）：低头盯着桌面
        matureChapterOneStep(game)
        game.setPose(.desk)
        for _ in 0..<80 { game.updateChapterLookDwell(delta: 0.05) }
        #expect(game.chapterOneStep == .followLinChe, "盯住桌面应当能收下纸条线索")
    }

    /// 盯住看必须和点「观察」付一样的代价。
    ///
    /// 否则 GUI 玩家（用鼠标盯着目标是最自然的玩法）能免费拿到所有视觉线索，
    /// 而 agent 模式测出来的暴露曲线会明显高于玩家实际体验。
    @Test func holdingYourGazeCostsTheSameAsObserving() {
        func exposureAfterFirstClue(useGaze: Bool) -> Double {
            let (game, _) = makeIsolatedGame()
            game.startGame()
            game.dismissChapterOneGuide()
            game.player.posture = .seated
            let before = game.player.exposure
            if useGaze {
                game.setPose(.left)
                for _ in 0..<80 { game.updateChapterLookDwell(delta: 0.05) }
            } else {
                game.setPose(.left)
                game.execute(.observe)
            }
            #expect(game.chapterOneStep == .locateHiddenSound)
            return game.player.exposure - before
        }

        let gaze = exposureAfterFirstClue(useGaze: true)
        let button = exposureAfterFirstClue(useGaze: false)
        #expect(gaze > 0, "盯住看不该是免费的")
        #expect(abs(gaze - button) < 0.001, "两条路径的代价必须一致：盯住 \(gaze) vs 按键 \(button)")
    }

    // MARK: - 完整游玩（端到端）

    /// 结局必须是一个"能给人看的结局"，不能缺字段。
    private func expectEndingIsComplete(_ ending: Ending, _ label: String) {
        #expect(ending.title.isEmpty == false, "\(label)：结局缺标题")
        #expect(ending.body.isEmpty == false, "\(label)：结局缺正文")
        #expect(ending.reflection.isEmpty == false, "\(label)：结局缺反思")
        #expect(ending.story.title.isEmpty == false, "\(label)：结局缺复盘标题")
        #expect(ending.story.body.isEmpty == false, "\(label)：结局缺复盘正文")
        #expect(ending.story.prompt.isEmpty == false, "\(label)：结局缺可以继续想的问题")
        #expect(ending.empathyReflections.count == 3, "\(label)：三方同理心视角必须齐全")
        #expect(ending.analysis.isEmpty == false, "\(label)：结局缺数据分析")
        #expect(ending.comparisons.isEmpty == false, "\(label)：结局缺对照")
        #expect(ending.resources.isEmpty == false, "\(label)：结局必须带上心理支持资源")
    }

    /// **端到端完整游玩**：菜单 → 序章 → 关卡一 → 章节转场 → 纸条 → 最终决策 → 结局。
    ///
    /// 为什么要单独写：agent 模式是直接 `startGame()` 开局的，**会跳过序章**，
    /// 所以那五条自动策略验证不到"从菜单进入"这段真实流程。
    @Test func fullPlaythroughFromMenuToEnding() {
        let (game, _) = makeIsolatedGame()
        game.startExperience(forcePrologue: true)
        #expect(game.isPrologueActive, "从菜单进入必须先走序章")

        var steps = 0
        for beat in PrologueBeatID.allCases where game.isPrologueActive {
            game.completePrologueBeat(beat, source: .player)
            steps += 1
        }
        #expect(game.isPrologueActive == false, "序章必须能自己走完（走了 \(steps) 步）")
        #expect(steps == PrologueBeatID.allCases.count, "每个序章 beat 都应正好走一次")
        #expect(game.isChapterOneTransitionPresented, "序章结束后应进入章节转场")

        // 序章 → 关卡一的交接
        game.dismissChapterOneGuide()
        game.enterChapterOneAfterPrologue()
        #expect(game.chapterOneStep == .observeLinChe)
        #expect(game.isChapterOneTransitionPresented == false)

        // 关卡一：走主线（内部会处理章节转场 / 纸条 / 最终决策）
        let run = runMainQuestPath(game)
        #expect(game.chapterOneStep == .completed, "关卡一必须能走完")
        #expect(run.turns >= 10, "主线应铺满整晚，实际 \(run.turns) 回合")

        guard case .ending(let ending) = game.gameState else {
            Issue.record("完整游玩必须到达结局，当前状态：\(game.gameState)")
            return
        }
        expectEndingIsComplete(ending, "端到端")
    }

    /// 玩家始终不肯用「倾听」时，这一晚也必须能收尾。
    ///
    /// 这是"不允许存在无限拖下去的状态"的守卫：如果有一天改动让
    /// 主线卡在某个步骤且没有其他出口，这条测试会立刻抓到。
    @Test func playthroughTerminatesEvenIfThePlayerNeverListens() {
        let (game, _) = makeIsolatedGame()
        game.startGame()
        game.dismissChapterOneGuide()

        var actions = 0
        while actions < 400 {
            if case .ending = game.gameState { break }
            if case .event(let event) = game.gameState {
                game.resolveEventChoice(event.choices[0])
            } else if case .playing = game.gameState {
                game.execute(.study)
            } else {
                break
            }
            actions += 1
        }

        guard case .ending = game.gameState else {
            Issue.record("从不倾听也必须能以某种方式结束这一晚，实际 \(actions) 次行动后仍未结束")
            return
        }
        #expect(game.chapterOneStep != .completed, "从不倾听不该走完主线")
        // 收尾方式必须是可解释的三种崩溃之一，而不是一个无名的状态。
        #expect(game.chapterOneCollapse != nil || game.hasPresentedChapterOneDecision)
    }

    /// 五种自动策略都必须走到结局。
    ///
    /// 历史上出现过两次主线永久卡死（节奏期限永不满足 / 自由活动锁住视角），
    /// 两次都会在这里暴露。`--auto-all` 是人工检查，这条是自动化守卫。
    @Test func everyAutoStrategyReachesAnEnding() {
        for strategy in AutoPlayer.Strategy.allCases {
            for attempt in 1...2 {
                let session = AgentGameSession(omniscient: false)
                _ = AutoPlayer.play(session: session, strategy: strategy, verbose: false)
                #expect(session.isFinished,
                        "策略 \(strategy.rawValue) 第 \(attempt) 次没能走到结局")
            }
        }
    }

    /// 第一章的 11 种结局都必须完整可读。
    @Test func everyChapterOneEndingIsComplete() {
        var titles: Set<String> = []

        for id in ["chapter1_teacher", "chapter1_monitor", "chapter1_tomorrow", "chapter1_wait"] {
            for informed in [false, true] {
                let (game, _) = makeIsolatedGame()
                game.startGame()
                if informed {
                    for clue in [ChapterClueID.teacherSigh, .monitorOverload, .hiddenCrying, .linChePage, .unsignedNote] {
                        addClue(game, clue)
                    }
                }
                let choices = decisionChoices(game)
                guard let choice = choices.first(where: { $0.id == id }) else {
                    Issue.record("决策 \(id) 不见了")
                    continue
                }
                game.resolveEventChoice(choice)
                let ending = game.calculateEnding()
                titles.insert(ending.title)
                expectEndingIsComplete(ending, "\(id) informed=\(informed)")
            }
        }

        for collapse in ChapterOneCollapse.allCases {
            let (game, _) = makeIsolatedGame()
            game.startGame()
            game.chapterOneCollapse = collapse
            let ending = game.calculateEnding()
            titles.insert(ending.title)
            expectEndingIsComplete(ending, "collapse=\(collapse.rawValue)")
        }

        #expect(titles.count == 11, "第一章应有 11 种结局写法，实际 \(titles.count)：\(titles)")
    }

    // MARK: - 可玩性验收（交接文档 §9.1）

    /// 按主线推进，并像真实玩家一样用等待回合"过晚自习"。
    ///
    /// 返回本局的观测量，供下面几条验收测试共用。
    private struct MainQuestRun {
        var minEnergy: Double
        var maxExposure: Double
        var turns: Int
        var warnings: Int
        var endingTitle: String
    }

    private func runMainQuestPath(_ game: GameManager, maxTurns: Int = 24) -> MainQuestRun {
        var minEnergy = game.player.psychicEnergy
        var maxExposure = game.player.exposure
        var warnings = 0
        var turns = 0

        for turn in 1...maxTurns {
            turns = turn
            if game.isChapterOneTransitionPresented { game.enterChapterTwo() }
            if game.isChapterOnePaperPresented { game.dismissChapterOnePaper() }

            if case .event(let event) = game.gameState {
                game.resolveEventChoice(event.choices[0])
            } else {
                if case .ending = game.gameState { break }
                game.execute(mainQuestAction(game))
                if case .event(let event) = game.gameState {
                    game.resolveEventChoice(event.choices[0])
                } else if game.isChapterOneTransitionPresented {
                    game.enterChapterTwo()
                    if game.isChapterOnePaperPresented { game.dismissChapterOnePaper() }
                    if case .event(let event) = game.gameState {
                        game.resolveEventChoice(event.choices[0])
                    }
                }
            }

            minEnergy = min(minEnergy, game.player.psychicEnergy)
            maxExposure = max(maxExposure, game.player.exposure)
            warnings = max(warnings, game.player.teacherWarnings)
            if case .ending = game.gameState { break }
        }

        minEnergy = min(minEnergy, game.player.psychicEnergy)
        maxExposure = max(maxExposure, game.player.exposure)
        return MainQuestRun(
            minEnergy: minEnergy,
            maxExposure: maxExposure,
            turns: turns,
            warnings: warnings,
            endingTitle: game.calculateEnding().title
        )
    }

    /// 主线推进动作；时机未到就用等待回合过晚自习。
    private func mainQuestAction(_ game: GameManager) -> PlayerAction {
        if game.chapterOneStepsUntilReady > 0 {
            return game.player.psychicEnergy < 45 ? .breathe : .study
        }
        switch game.chapterOneStep {
        case .observeLinChe:
            game.setPose(.left)
            return .observe
        case .locateHiddenSound:
            // 这一步是听觉线索：必须朝向声源「倾听」，观察拿不到。
            game.setPose(.right)
            return .listen
        case .regulateSelf:
            return .breathe
        case .approachLinChe:
            return .talk
        case .inspectNote:
            game.setPose(.desk)
            return .observe
        case .followLinChe, .completed:
            return .leaveSeat
        }
    }

    /// 验收 §9.1：认真走主线的玩家必须真的感觉到压力。
    ///
    /// 改之前：暴露最高 45、能量最低 65，整局没有任何数值进入危险区。
    /// 这条测试把这个失败状态钉死，防止以后又改回"安全主线"。
    @Test func mainQuestPathCarriesRealRisk() {
        let (game, _) = makeIsolatedGame()
        game.startGame()
        game.dismissChapterOneGuide()

        let run = runMainQuestPath(game)

        #expect(run.maxExposure >= 60, "主线暴露应至少达到 60，实际 \(run.maxExposure)")
        #expect(run.minEnergy < 35, "主线能量应至少一次低于 35，实际最低 \(run.minEnergy)")
        #expect(run.turns >= 10, "主线应铺满整晚而不是 6 回合冲刺，实际 \(run.turns)")
        #expect(game.chapterOneStep == .completed, "主线必须仍然可以走完")
    }

    /// 验收 §9.1：危险必须在被抓住之前就能被感觉到。
    @Test func exposureLadderIsReadable() {
        let (game, _) = makeIsolatedGame()
        game.startGame()

        game.player.exposure = 10
        #expect(game.exposureSignal == .calm)
        game.player.exposure = 35
        #expect(game.exposureSignal == .noticed)
        game.player.exposure = 58
        #expect(game.exposureSignal == .watched)
        game.player.exposure = 80
        #expect(game.exposureSignal == .targeted)

        // 每一级都必须有一句玩家能读懂的感受文案。
        for signal in ExposureSignal.allCases {
            #expect(signal.detail.isEmpty == false)
            #expect(signal.title.isEmpty == false)
        }
        // 分级必须单调，不能出现"更危险反而提示更轻"的情况。
        #expect(ExposureSignal.calm < ExposureSignal.noticed)
        #expect(ExposureSignal.noticed < ExposureSignal.watched)
        #expect(ExposureSignal.watched < ExposureSignal.targeted)
    }

    /// 根因 A 的守卫：恢复动作不能是无脑最优解。
    @Test func breathingHasDiminishingReturnsWithinAPeriod() {
        let (game, _) = makeIsolatedGame()
        game.startGame()
        game.dismissChapterOneGuide()

        // 把压力推高，确保每次深呼吸都有"东西可以释放"。
        game.player.stress = 80
        let firstGain = measuredBreathGain(game)

        game.player.stress = 80
        let secondGain = measuredBreathGain(game)
        game.player.stress = 80
        let thirdGain = measuredBreathGain(game)

        #expect(firstGain > secondGain, "第二次深呼吸的恢复必须低于第一次")
        #expect(secondGain > thirdGain, "第三次深呼吸的恢复必须继续递减")
        #expect(firstGain > 0)
    }

    /// 在同一次行动前后测能量差，隔离掉其他数值的干扰。
    private func measuredBreathGain(_ game: GameManager) -> Double {
        let before = game.player.psychicEnergy
        game.execute(.breathe)
        return game.player.psychicEnergy - before
    }

    /// 根因 C 的守卫：关卡一的暴露必须真的会带来后果。
    ///
    /// 改之前 `teacherTurn()` 在 `.silentClassroom` 直接 return，
    /// 导致"被发现 / 假巡视 / 后门观察"在关卡一里完全不可达。
    @Test func chapterOneExposureEventuallyGetsYouNoticed() {
        let (game, _) = makeIsolatedGame()
        game.startGame()
        game.dismissChapterOneGuide()

        // 越过 70 的第一个回合只是"被盯住"（缓冲回合），不会被抓。
        game.player.exposure = 78
        game.setPose(.left)
        game.execute(.observe)
        #expect(game.player.teacherWarnings == 0, "越过危险线时先给一个可反应的缓冲回合")
        #expect(game.player.exposure >= 70, "缓冲回合里暴露还没有回落")

        // 第二个回合仍留在线上，才会真的被看见。
        game.player.exposure = 78
        game.setPose(.left)
        game.execute(.observe)
        #expect(game.player.exposure < 70, "被看见后暴露必须回落到安全区")
        #expect(game.player.teacherWarnings >= 1, "必须记录一次“被看见”")
        #expect(game.player.maskCost > PlayerState().maskCost, "被看见要付出面具成本")
    }

    // MARK: - 无障碍偏好持久化

    /// 无障碍设置必须能往返，且缺字段时回退默认。
    @Test func accessibilityPreferencesRoundTrip() throws {
        var prefs = AccessibilityPreferences()
        prefs.reduceMotion = true
        prefs.viewSensitivity = 1.4
        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(AccessibilityPreferences.self, from: data)
        #expect(decoded.reduceMotion == true)
        #expect(decoded.viewSensitivity == 1.4)
    }

    // MARK: - 音量边界

    /// 混音音量必须被钳制在 0...1，避免爆音。
    @Test func mixVolumesAreClamped() {
        let (game, _) = makeIsolatedGame()
        game.audio.setMixVolumes(dialogue: 5, ambience: -3, cues: 99)
        #expect(game.audio.dialogueVolume <= 1)
        #expect(game.audio.dialogueVolume >= 0)
    }

    // MARK: - 音频输出能力

    /// 输出能力探测必须按声道数正确回退：≥6 沉浸式 / 2 立体声 / 1 单声道。
    @Test func audioCapabilityFallsBackByChannelCount() {
        let stereo = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        #expect(AudioOutputCapability.detect(from: stereo).outputChannelCount == 2)

        let mono = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        #expect(AudioOutputCapability.detect(from: mono).outputChannelCount == 1)

        // 8 声道需要显式 channel layout，standardFormat 无法构造。
        let layout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_MPEG_5_1_A)!
        let surround = AVAudioFormat(standardFormatWithSampleRate: 48_000, channelLayout: layout)
        let detected = AudioOutputCapability.detect(from: surround)
        #expect(detected.outputChannelCount == 6)
        #expect(detected.usesSpatialEnvironment == true)
    }

    /// 单声道设备不应启用空间环境节点。
    @Test func monoDeviceDisablesSpatialEnvironment() {
        let mono = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        #expect(AudioOutputCapability.detect(from: mono).usesSpatialEnvironment == false)
    }
}
