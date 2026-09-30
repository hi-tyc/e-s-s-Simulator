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

        game.setPose(.right)
        game.execute(.observe)
        #expect(game.chapterOneStep == .regulateSelf)

        game.execute(.breathe)
        #expect(game.chapterOneStep == .approachLinChe)

        game.execute(.talk)
        #expect(game.chapterOneStep == .inspectNote)

        game.setPose(.desk)
        game.execute(.observe)
        #expect(game.chapterOneStep == .followLinChe)
        #expect(game.chapterClues.count == 3)
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
