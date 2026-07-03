import AppKit
import Combine
import Foundation
import SceneKit

@MainActor
final class GameManager: ObservableObject {
    @Published var gameState: GameState = .menu
    @Published var currentTurn: Int = 0
    @Published var maxTurns: Int = 18
    @Published var settings = InstitutionSettings()
    @Published var currentPhase: TurnPhase = .observation
    @Published var player = PlayerState()
    @Published var teacher = TeacherState()
    @Published var cameraPose: CameraPose = .forward
    @Published var viewMode: ViewMode = .student
    @Published var message: String = "晚自习开始。教室里的笔尖声和风扇声混在一起。"
    @Published var classmates: [Classmate] = []
    @Published var eventLog: [EventLogEntry] = []
    @Published var audioCues: [AudioCue] = []
    @Published var replay: [TurnSnapshot] = []
    @Published var selectedReplayIndex: Int = 0
    @Published var peripheralLeft: Double = 0
    @Published var peripheralRight: Double = 0.25
    @Published var classroomLightLevel: Double = 1.0
    @Published var triggeredPeriods: Set<StudyPeriod> = []
    @Published var monologues: [InnerMonologue] = []
    @Published var hasTriggeredLoneliness: Bool = false
    @Published var hasTriggeredPhoneNotification: Bool = false
    @Published var hasTriggeredBroadcast: Bool = false
    @Published var hasTriggeredKnockOnDoor: Bool = false
    @Published var hasTriggeredClassmateHelpRequest: Bool = false
    @Published var hasTriggeredClassmateReport: Bool = false
    @Published var hasTriggeredMemoryTrust: Bool = false
    @Published var hasTriggeredMemorySuspicion: Bool = false
    @Published var classmateMemory: [Int: ClassmateMemory] = [:]
    @Published var audioAssetStatus: AudioAssetStatus

    let audio = SpatialAudioManager()
    private let memoryStoreKey = "LateStudySimulator.ClassmateMemory.v1"

    init() {
        audioAssetStatus = audio.assetStatus
        classmateMemory = loadClassmateMemory()
    }

    func startGame() {
        currentTurn = 1
        maxTurns = settings.maxTurns
        currentPhase = .observation
        player = PlayerState()
        player.stress += settings.rankingPressure * 0.08
        teacher = TeacherState(kpiPressure: settings.rankingPressure)
        cameraPose = .forward
        viewMode = .student
        classmates = makeClassmates()
        eventLog = []
        audioCues = []
        replay = []
        selectedReplayIndex = 0
        classroomLightLevel = 1.0
        triggeredPeriods = []
        monologues = []
        hasTriggeredLoneliness = false
        hasTriggeredPhoneNotification = false
        hasTriggeredBroadcast = false
        hasTriggeredKnockOnDoor = false
        hasTriggeredClassmateHelpRequest = false
        hasTriggeredClassmateReport = false
        hasTriggeredMemoryTrust = false
        hasTriggeredMemorySuspicion = false
        gameState = .playing
        let memoryText = classmateMemory.isEmpty ? "" : " 有 \(classmateMemory.count) 个同学还带着上一晚的关系余波。"
        message = "18:30，晚自习开始。制度参数：\(settings.description)。你被固定在第三排中间的位置，只能靠观察和声音判断局势。\(memoryText)"
        addMonologue("今晚要撑过去。不是表现得正常就等于真的不累。", intensity: 0.42)
        audio.start()
        updatePerception()
    }

    func restartWithCurrentSettings() {
        startGame()
    }

    func clearClassmateMemory() {
        classmateMemory = [:]
        UserDefaults.standard.removeObject(forKey: memoryStoreKey)
        message = "同学记忆已清除。下一次晚自习会从新的关系基线开始。"
    }

    func refreshAudioAssetStatus() {
        audioAssetStatus = audio.assetStatus
        message = "音频素材已刷新：\(audioAssetStatus.summary)，\(audioAssetStatus.missingSummary)。"
    }

    func openExternalAudioDirectory() {
        guard let root = audio.externalAudioDirectory else { return }
        let cueDirectory = root.appendingPathComponent("AudioCues", isDirectory: true)
        let loopDirectory = root.appendingPathComponent("AudioLoops", isDirectory: true)
        try? FileManager.default.createDirectory(at: cueDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: loopDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(root)
        refreshAudioAssetStatus()
    }

    func previewAudioCue(_ kind: AudioCueKind) {
        audio.start()
        let direction: String
        let intensity: Double
        switch kind {
        case .footstep:
            direction = "右前方"
            intensity = 0.86
        case .heartbeat:
            direction = "颅内"
            intensity = 0.9
        case .paper:
            direction = "左侧近处"
            intensity = 0.56
        default:
            direction = "桌面"
            intensity = 0.6
        }
        addAudioCue(kind, direction: direction, intensity: intensity, note: "试听音频：用于检查真实素材或程序化回退的方向与响度。")
        refreshAudioAssetStatus()
    }

    func toggleViewMode() {
        guard case .playing = gameState else { return }
        viewMode = viewMode == .student ? .teacher : .student
        if viewMode == .teacher {
            message = teacherPerspective()
        } else {
            message = "你回到自己的座位。刚才看到的不是答案，只是另一个被制度推着走的人。"
            addMonologue("回到座位的一瞬间，固定感也回来了。", intensity: 0.5)
        }
    }

    func setPose(_ pose: CameraPose) {
        guard case .playing = gameState else { return }
        let previousPose = cameraPose
        cameraPose = pose

        switch pose {
        case .board:
            spendAttention(for: pose.visionZone, multiplier: teacher.isNearPlayer ? 1.2 : 1)
            player.exposure += 4
            player.maskCost += 2
            message = "你抬头看向讲台。看起来很认真，但维持这个姿态也很累。"
        case .desk:
            spendAttention(for: pose.visionZone, multiplier: 1)
            player.exposure = max(0, player.exposure - 6)
            player.stress += teacher.isNearPlayer ? 6 : 2
            message = "你低头看着桌面，老师的位置变得不确定。"
            addAudioCue(.chair, direction: "桌边", intensity: 0.32, note: "抽屉缝隙轻轻打开，桌面近景变得清楚，但中景信息被切断。")
            addAudioCue(.heartbeat, direction: "颅内", intensity: player.stress / 100, note: "低头后，你更依赖脚步和心跳判断风险。")
        case .left:
            spendAttention(for: pose.visionZone, multiplier: 1)
            player.exposure += 3
            message = "左侧余光里，同桌的手指停在作业本边缘，像是想说什么。"
            handleEyeContact(column: 0)
        case .right:
            spendAttention(for: pose.visionZone, multiplier: 1)
            player.exposure += 3
            message = "右侧走廊有脚步声靠近，具体是谁还看不清。"
            handleEyeContact(column: 2)
            addAudioCue(.footstep, direction: "右前方", intensity: teacher.isNearPlayer ? 0.9 : 0.45, note: "脚步声从走廊方向传来。")
        case .forward:
            recoverAttention(10)
            player.psychicEnergy = min(100, player.psychicEnergy + 1.5)
            message = "你把视线收回前方，试着让自己看起来普通。"
        }

        applyTurnStrain(from: previousPose, to: pose)
        clampPlayer()
        updatePerception()
    }

    private func applyTurnStrain(from previous: CameraPose, to next: CameraPose) {
        guard previous != next else { return }
        let isSideTurn = next == .left || next == .right
        let isVerticalTurn = next == .board || next == .desk
        guard isSideTurn || isVerticalTurn else { return }

        let strain = player.stress * 0.35 + max(0, 38 - player.visualAttention) + (teacher.isNearPlayer ? 18 : 0)
        guard strain > 52 else { return }

        let stressDelta = min(7, strain / 18)
        player.stress += stressDelta
        player.maskCost += isSideTurn ? 2 : 1
        player.visualAttention = max(0, player.visualAttention - min(6, strain / 20))
        message += isSideTurn
            ? " 你转头时明显慢了一拍，脖子僵硬像是在提醒你：确认信息也有代价。"
            : " 视线上下切换时有短暂迟滞，身体比意识更早感到紧张。"
        addAudioCue(.heartbeat, direction: "颅内", intensity: min(1, strain / 100), note: "高压下转动视线会变慢，感官管理本身也会消耗心理能量。")
    }

    private func handleEyeContact(column: Int) {
        guard let index = classmates.firstIndex(where: { $0.seat.row == 2 && $0.seat.column == column }) else {
            return
        }
        classmates[index].state = .lookingAtPlayer
        classmates[index].relationship = (classmates[index].relationship + 5).clamped(to: 0...100)
        classmates[index].suspicionOfPlayer = max(0, classmates[index].suspicionOfPlayer - 4)
        player.maskCost = max(0, player.maskCost - 2)
        player.support = (player.support + classmates[index].profile.empathy / 60).clamped(to: 0...100)
        if classmates[index].profile.orderliness > 74 && player.exposure > 45 {
            classmates[index].suspicionOfPlayer += 10
            player.stress += 3
            message += " \(classmates[index].name)也看见了你的小动作，眼神里有一点紧张。"
        } else if classmates[index].profile.empathy > 66 {
            message += " 你们短暂对视，\(classmates[index].name)眨了眨眼，像是在确认你还撑得住。"
            addMonologue("被看见的一秒钟，没有那么可怕。", intensity: 0.32)
        } else {
            message += " 你们对视了一下，很快又各自低头。"
        }
    }

    func execute(_ action: PlayerAction) {
        guard case .playing = gameState else { return }
        if viewMode == .teacher {
            executeTeacherAction(.patrol)
            return
        }
        currentPhase = .action

        switch action {
        case .study:
            spendAttention(for: .desk, multiplier: 0.8)
            player.homework += 12
            player.psychicEnergy -= 11
            player.maskCost += 4
            player.stress += 5
            player.exposure = max(0, player.exposure - 4)
            message = "你写完了一小段题。进度变高了，注意力也明显被掏空。"
            addMonologue("我不是不想学，是注意力像被一点点磨掉。", intensity: 0.58)
            addAudioCue(.paper, direction: "桌面", intensity: 0.34, note: "笔尖划过纸面，声音很近。")
        case .phone:
            spendAttention(for: .desk, multiplier: 0.6)
            player.psychicEnergy += 7
            player.maskCost += 14
            player.exposure += teacher.isNearPlayer ? 35 : 18
            player.stress += teacher.isNearPlayer ? 16 : 5
            message = teacher.isNearPlayer ? "手机屏幕刚亮，脚步声就在旁边停下。" : "屏幕蓝光让你短暂脱离了教室，也让风险迅速上升。"
            addMonologue("只是看一眼消息，好像就能从这里逃出去几秒。", intensity: teacher.isNearPlayer ? 0.82 : 0.6)
            addAudioCue(.chair, direction: "桌面偏右", intensity: teacher.isNearPlayer ? 0.58 : 0.34, note: "手机从抽屉边缘滑出来，细小摩擦声也会暴露你。")
            addAudioCue(.phone, direction: "桌面偏右", intensity: teacher.isNearPlayer ? 0.92 : 0.58, note: "手机震动在安静教室里被放大。")
        case .note:
            spendAttention(for: .leftPeripheral, multiplier: 1)
            player.support += 10
            player.psychicEnergy -= 4
            player.maskCost += 7
            player.exposure += settings.allowsWhispering ? 3 : (teacher.isNearPlayer ? 18 : 8)
            message = "纸条被同桌接住。不是所有连接都需要大声说出来。"
            addMonologue("原来一句写在纸上的话，也能让我没那么孤单。", intensity: 0.45)
            improveDeskmates(delta: 9, stressRelief: 4)
            addAudioCue(.chair, direction: "桌边", intensity: 0.26, note: "你借着抽屉边缘遮住手势，隐蔽也会制造一点声音。")
            addAudioCue(.paper, direction: "左侧近处", intensity: 0.52, note: "纸张摩擦声提醒你：连接也有风险。")
        case .observe:
            spendAttention(for: cameraPose.visionZone, multiplier: 0.7)
            player.psychicEnergy -= 4
            player.stress = max(0, player.stress - 3)
            player.exposure += 2
            message = viewMode == .teacher ? teacherPerspective() : "你观察老师的移动节奏：鞋跟声、粉笔声、停顿，都变成了信息。"
            addMonologue("我一直在算风险，可是没人知道这也很累。", intensity: 0.52)
        case .talk:
            spendAttention(for: .leftPeripheral, multiplier: 1)
            player.support += 14
            player.psychicEnergy += 5
            player.maskCost = max(0, player.maskCost - 7)
            player.exposure += settings.allowsWhispering ? 2 : (teacher.isNearPlayer ? 16 : 7)
            player.helpedClassmate = true
            message = "你低声问同桌还好吗。面具松了一点，关系也真实了一点。"
            addMonologue("声音很小，但它证明我不是一个人在这间教室里。", intensity: 0.38)
            improveDeskmates(delta: 16, stressRelief: 12)
            addAudioCue(.whisper, direction: "左侧近处", intensity: 0.44, note: "低语比文字更真实，也更容易被发现。")
        case .breathe:
            recoverAttention(18)
            player.psychicEnergy += 17
            player.stress = max(0, player.stress - 16)
            player.maskCost = max(0, player.maskCost - 3)
            player.exposure = max(0, player.exposure - 4)
            message = "你做了几次缓慢呼吸。问题还在，但身体先回到此刻。"
            addMonologue("先把呼吸找回来，题目可以等一秒。", intensity: 0.3)
            addAudioCue(.heartbeat, direction: "颅内", intensity: 0.28, note: "心跳慢下来一点，听觉边界重新清晰。")
        case .window:
            spendAttention(for: .leftPeripheral, multiplier: 0.5)
            player.psychicEnergy += 9
            player.stress = max(0, player.stress - 7)
            player.exposure += 5
            message = "窗外的路灯和远处车声给了你几秒钟的认知脱离。"
            addMonologue("窗外还有路灯和车声，不只是这间教室。", intensity: 0.34)
            addAudioCue(.whisper, direction: "左窗外", intensity: 0.26, note: "远处车声提示教室外还有另一个世界。")
        case .snack:
            spendAttention(for: .desk, multiplier: 0.5)
            player.hunger = max(0, player.hunger - 28)
            player.psychicEnergy += 8
            player.stress = max(0, player.stress - 5)
            player.exposure += teacher.isNearPlayer ? 18 : 8
            player.maskCost += 4
            message = "你把零食包装压在书页下面打开。饥饿退了一点，包装纸声也把风险带了出来。"
            addMonologue("原来不是我不专心，是身体也在晚自习里熬着。", intensity: 0.42)
            addAudioCue(.chair, direction: "桌边", intensity: 0.28, note: "抽屉只开了一条缝，却足够让身体需求变成风险。")
            addAudioCue(.wrapper, direction: "桌面偏右", intensity: teacher.isNearPlayer ? 0.78 : 0.48, note: "包装纸声比你想象中更脆，像一次小型违规。")
        case .leaveSeat:
            player.exposure += 18
            player.maskCost += 4
            player.posture = .standing
            addMonologue("站起来的一瞬间，我才发现自己坐得有多僵。", intensity: 0.68)
            let bodyNeedLine = player.bladder > 62
                ? "如厕需求已经压过了“保持普通”的表演。"
                : "固定座位的牢笼被抬高了，但所有视线也更容易落到你身上。"
            presentEvent(
                kind: .leaveSeatRequest,
                title: "举手离座",
                body: "你慢慢站起来，椅子腿在地面上擦出很轻的一声。\(bodyNeedLine)",
                choices: [
                    EventChoice(id: "go_washroom", title: "请求去洗手间", detail: "短暂脱离教室，恢复能量，作业停滞"),
                    EventChoice(id: "stretch_only", title: "站起伸展", detail: "恢复注意力，但暴露风险上升"),
                    EventChoice(id: "sit_back_down", title: "又坐下", detail: "风险降低，但压力留下")
                ]
            )
            addAudioCue(.chair, direction: "桌边", intensity: 0.7, note: "站起时的椅子声让你瞬间成为声源。")
        }

        applyBodyNeeds()
        clampPlayer()
        if case .event = gameState {
            recordSnapshot(actionLabel: action.rawValue)
            return
        }
        updateClassmates(after: action)
        recordSnapshot(actionLabel: action.rawValue)
        teacherTurn()
    }

    func executeTeacherAction(_ action: TeacherAction) {
        guard case .playing = gameState else { return }
        currentPhase = .teacherTurn
        let target = highestRiskClassmate

        switch action {
        case .patrol:
            teacher.positionIndex = (teacher.positionIndex + 2) % 8
            teacher.fatigue += 4
            teacher.kpiPressure = max(0, teacher.kpiPressure - 2)
            player.exposure += cameraPose == .desk ? 8 : 3
            message = "你沿着过道走了一圈。纪律看起来更稳定，但几个学生明显更紧绷了。"
            addAudioCue(.footstep, direction: "过道移动", intensity: 0.86, note: "脚步声成为全班的压力信号。")
        case .warn:
            teacher.studentsWarned += 1
            player.teacherWarnings += 1
            teacher.kpiPressure = max(0, teacher.kpiPressure - 5)
            teacher.fatigue += 3
            if let target {
                raiseClassmateStress(id: target.id, delta: 10)
                message = "你提醒了\(target.name)。表面上秩序恢复了，但你不知道这句话压在了什么上面。"
            } else {
                message = "你提醒全班安静。声音不大，但教室立刻变硬了。"
            }
            addAudioCue(.chair, direction: "讲台前方", intensity: 0.62, note: "提醒后的椅子轻响，比回答更诚实。")
        case .ignore:
            teacher.kpiPressure += 5
            teacher.fatigue = max(0, teacher.fatigue - 3)
            player.exposure = max(0, player.exposure - 10)
            lowerClassmateStress(delta: 3)
            message = "你选择性放过了一些小动作。你保护了几个学生，也承担了被问责的风险。"
            addAudioCue(.paper, direction: "教室四周", intensity: 0.3, note: "环境声回来了，说明紧张被暂时放低。")
        case .care:
            teacher.studentsHelped += 1
            teacher.empathy += 2
            teacher.fatigue += 5
            player.teacherCareMoments += 1
            if let target {
                lowerClassmateStress(id: target.id, delta: 20)
                message = "你走到\(target.name)身边，低声问：需要出去缓一下吗？这消耗时间，但也许避免了一次崩溃。"
            } else {
                player.psychicEnergy += 9
                player.stress = max(0, player.stress - 10)
                message = "你没有批评，只是问了句还好吗。权力第一次没有变成压力。"
            }
            addAudioCue(.whisper, direction: "过道近处", intensity: 0.38, note: "关心必须压低声音，才不会变成公开审判。")
        case .rest:
            teacher.fatigue = max(0, teacher.fatigue - 12)
            teacher.kpiPressure += 3
            player.exposure = max(0, player.exposure - 4)
            message = "你坐回讲台揉了揉太阳穴。你也是这个系统里会累的人。"
            addAudioCue(.chair, direction: "讲台", intensity: 0.42, note: "椅子声暴露了老师的疲惫。")
        case .rearDoorObserve:
            teacher.positionIndex = 8
            teacher.fatigue += 6
            teacher.kpiPressure = max(0, teacher.kpiPressure - 4)
            teacher.isNearPlayer = false
            let suspicious = player.exposure + player.maskCost * 0.25 + (cameraPose == .desk ? 8 : 0)
            if suspicious > 62 {
                player.stress += 12
                player.exposure += 8
                teacher.studentsWarned += 1
                message = "你从后门无声观察。学生没有听见脚步，但几个小动作在你眼里变得很明显。"
            } else {
                player.stress += 4
                lowerClassmateStress(delta: 2)
                message = "你站在后门观察了一会儿。没有立刻提醒，教室里的紧张以一种无声方式扩散。"
            }
            addAudioCue(.knock, direction: "后方左侧", intensity: 0.3, note: "不是敲门，而是门口很轻的衣料和呼吸声。")
        case .fakePatrol:
            teacher.positionIndex = max(0, teacher.positionIndex - 1)
            teacher.fatigue += 2
            teacher.kpiPressure = max(0, teacher.kpiPressure - 3)
            player.stress += 8
            player.exposure += cameraPose == .desk ? 6 : 2
            lowerClassmateStress(delta: 1)
            message = "你故意制造了一段脚步声，又停在远处。纪律短暂收紧，但学生无法确认你到底在哪里。"
            addAudioCue(.footstep, direction: "右前方", intensity: 0.92, note: "脚步声逼近后突然停住，这种不确定性本身就是压力。")
        }

        clampTeacher()
        clampPlayer()
        updateClassmates(after: nil)
        recordSnapshot(actionLabel: "教师-\(action.rawValue)")
        if currentTurn >= maxTurns {
            finish()
        } else {
            currentTurn += 1
            currentPhase = .observation
            updatePerception()
            applyTimeProgression()
            checkCriticalState()
        }
    }

    func continueAfterEvent() {
        if currentTurn >= maxTurns {
            finish()
            return
        }

        currentTurn += 1
        currentPhase = .observation
        gameState = .playing
        player.psychicEnergy = min(100, player.psychicEnergy + 4 + player.support / 30)
        recoverAttention(20)
        player.maskCost += 2
        player.stress += player.maskCost > 80 ? 8 : 2
        applyBodyNeeds()
        updateClassmates(after: nil)
        recordSnapshot(actionLabel: "事件后继续")
        updatePerception()
        applyTimeProgression()
        checkCriticalState()
    }

    private func teacherTurn() {
        currentPhase = .teacherTurn
        let patrolStep = settings.patrolFrequency > 72 ? Int.random(in: 2...3) : Int.random(in: 1...2)
        teacher.positionIndex = (teacher.positionIndex + patrolStep) % 8
        teacher.isNearPlayer = [2, 3, 4].contains(teacher.positionIndex)
        teacher.fatigue = min(100, teacher.fatigue + (1.4 + settings.patrolFrequency / 60) * currentPeriod.fatigueMultiplier)

        let pressure = teacher.kpiPressure * 0.22 + teacher.fatigue * 0.16 + settings.patrolFrequency * 0.08 - teacher.empathy * 0.12
        let discoveryRisk = player.exposure + pressure + (cameraPose == .desk ? 8 : 0) + (player.visualAttention < 18 ? 8 : 0)
        maybeAddTeacherStateCue(pressure: pressure)

        if shouldFakePatrol(pressure: pressure, discoveryRisk: discoveryRisk) {
            teacher.positionIndex = max(0, teacher.positionIndex - 1)
            teacher.isNearPlayer = false
            teacher.fatigue += 2
            player.stress += 6
            player.exposure += cameraPose == .desk ? 5 : 1
            appendEvent(title: "假巡视", detail: "脚步声接近后停住，老师并没有真正走到你身边。")
            message = "脚步声从右前方靠近，又在看不见的位置停住。你不知道老师是不是真的在看你。"
            addAudioCue(.footstep, direction: "右前方", intensity: 0.88, note: "脚步声制造了风险预期，但位置并不确定。")
            continueAfterEvent()
        } else if shouldRearDoorObserve(pressure: pressure, discoveryRisk: discoveryRisk) {
            teacher.positionIndex = 8
            teacher.isNearPlayer = false
            teacher.fatigue += 4
            player.stress += 7
            appendEvent(title: "后门观察", detail: "老师没有制造脚步声，而是从后门看了一会儿。")
            message = "你没有听见脚步声，却感觉后方安静得不自然。无声观察比巡视更难判断。"
            addAudioCue(.knock, direction: "后方左侧", intensity: 0.22, note: "后门附近只有很轻的布料摩擦声，像有人站住了。")
            continueAfterEvent()
        } else if discoveryRisk > 92 {
            player.stress += 18
            player.maskCost += 8
            player.teacherWarnings += 1
            teacher.studentsWarned += 1
            player.exposure = 42
            appendEvent(title: "被发现", detail: "老师选择了提醒而不是羞辱。制度压力仍然传导到了你身上。")
            presentEvent(
                kind: .discovery,
                title: "被发现",
                body: "老师的视线停在你身上。她没有立刻批评，只说：先把手机收起来，别把自己逼到完全失控。",
                choices: [
                    EventChoice(id: "accept_warning", title: "收起手机", detail: "压力下降，面具成本上升"),
                    EventChoice(id: "explain_tired", title: "说自己太累", detail: "暴露真实状态，可能换来理解"),
                    EventChoice(id: "stay_silent", title: "沉默点头", detail: "风险最低，但心理负担保留")
                ]
            )
            addAudioCue(.footstep, direction: "右侧极近", intensity: 1.0, note: "脚步声停下，比批评更早抵达。")
            audio.playWarning()
        } else if teacher.empathy > 56 && player.psychicEnergy < 24 && Double.random(in: 0...1) < 0.42 {
            player.teacherCareMoments += 1
            teacher.studentsHelped += 1
            player.psychicEnergy += 10
            player.stress = max(0, player.stress - 12)
            appendEvent(title: "老师关心", detail: "她注意到你的疲惫。管理不是只有惩罚，也可以是看见。")
            presentEvent(
                kind: .teacherConcern,
                title: "老师关心",
                body: "老师走近，但声音压得很低：你看起来很累，要不要先去洗把脸？你第一次意识到老师也在做选择。",
                choices: [
                    EventChoice(id: "take_break", title: "去洗把脸", detail: "恢复能量，作业进度停滞"),
                    EventChoice(id: "thank_teacher", title: "低声道谢", detail: "支持感提高，暴露风险较低"),
                    EventChoice(id: "refuse_care", title: "说没事", detail: "维持面具，错过一次支持")
                ]
            )
            addAudioCue(.whisper, direction: "前方近处", intensity: 0.5, note: "老师的低声关心没有穿透全班。")
            audio.playWarning()
        } else if player.breakdownRisk > 58 {
            appendEvent(title: "崩溃信号", detail: "心理能量、面具成本和暴露风险叠加到了危险区。")
            presentEvent(
                kind: .playerBreakdown,
                title: "崩溃信号",
                body: "你的角色感到不堪重负。这不是失败，这是信号。短暂停下、说话或求助，都是有效行动。",
                choices: [
                    EventChoice(id: "breathe_now", title: "深呼吸", detail: "恢复注意力和心理能量"),
                    EventChoice(id: "ask_deskmate", title: "向同桌求助", detail: "依赖支持网络，暴露一点真实状态"),
                    EventChoice(id: "push_through", title: "继续硬撑", detail: "短期维持秩序，崩溃风险上升")
                ]
            )
            addAudioCue(.heartbeat, direction: "颅内", intensity: 1.0, note: "外界声音退后，心跳和耳鸣占据中心。")
            audio.playWarning()
        } else {
            continueAfterEvent()
        }

        clampPlayer()
    }

    private func shouldRearDoorObserve(pressure: Double, discoveryRisk: Double) -> Bool {
        guard currentPeriod.isBreak == false, teacher.kpiPressure > 64, teacher.fatigue < 86 else {
            return false
        }
        if teacher.positionIndex == 8 { return false }
        let chance = min(0.28, 0.06 + pressure / 480 + discoveryRisk / 700)
        return Double.random(in: 0...1) < chance
    }

    private func shouldFakePatrol(pressure: Double, discoveryRisk: Double) -> Bool {
        guard currentPeriod.isBreak == false, settings.patrolFrequency > 54, teacher.fatigue < 80 else {
            return false
        }
        let chance = min(0.24, 0.05 + pressure / 560 + discoveryRisk / 850)
        return Double.random(in: 0...1) < chance
    }

    private func maybeAddTeacherStateCue(pressure: Double) {
        guard currentPeriod.isBreak == false else { return }
        let fatigueChance = max(0, (teacher.fatigue - 42) / 240)
        let pressureChance = max(0, (pressure - 28) / 320)
        let roll = Double.random(in: 0...1)

        if teacher.fatigue > 68 && roll < fatigueChance {
            addAudioCue(.teacherSigh, direction: teacher.positionIndex == 8 ? "后方左侧" : "讲台前方", intensity: min(0.82, teacher.fatigue / 100), note: "老师的叹气暴露了疲惫：制度压力也在消耗她。")
            teacher.empathy = min(100, teacher.empathy + 0.6)
        } else if pressure > 36 && roll < fatigueChance + pressureChance {
            addAudioCue(.teacherCough, direction: teacher.isNearPlayer ? "右侧极近" : "讲台前方", intensity: min(0.78, pressure / 70), note: "老师咳嗽声让位置和状态同时变成线索。")
            player.stress += teacher.isNearPlayer ? 2 : 0.8
        }
    }

    private func checkCriticalState() {
        if let crying = classmates.first(where: { $0.state == .crying }), player.helpedClassmate == false {
            appendEvent(title: "\(crying.name)崩溃", detail: "同桌的肩膀在抖。你可以选择靠近，也可以继续假装没看见。")
            presentEvent(
                kind: .classmateCrying(classmateID: crying.id),
                title: "\(crying.name)崩溃",
                body: "左侧传来很轻的抽泣声。\(crying.name)把脸埋进臂弯里。教室坐满了人，但没有人敢发出声音。",
                choices: [
                    EventChoice(id: "comfort_classmate", title: "低声安慰", detail: "关系和支持大幅上升，暴露风险上升"),
                    EventChoice(id: "pass_tissue", title: "递纸巾", detail: "小动作支持，风险较低"),
                    EventChoice(id: "tell_teacher", title: "告诉老师", detail: "可能获得帮助，也可能伤害信任"),
                    EventChoice(id: "pretend_ignore", title: "假装没看见", detail: "风险最低，但支持网络受损")
                ]
            )
            addAudioCue(.crying, direction: "左侧近处", intensity: 0.78, note: "抽泣声很轻，但它改变了这一晚的重心。")
            audio.playWarning()
            return
        }

        if !hasTriggeredLoneliness && player.support < 25 && player.stress > 52 {
            hasTriggeredLoneliness = true
            appendEvent(title: "孤独感袭来", detail: "支持网络过低时，坐满人的教室也会变成孤岛。")
            addMonologue("教室里坐满了人，但我好像离每个人都很远。", intensity: 0.84)
            presentEvent(
                kind: .loneliness,
                title: "孤独感袭来",
                body: "教室里坐满了人，但你感到异常孤独。孤独感是压力的信号，不是软弱的表现。你可以先让身体降下来，也可以用很小的方式留下真实感受。",
                choices: [
                    EventChoice(id: "loneliness_breathe", title: "深呼吸", detail: "恢复能量和注意力，压力下降"),
                    EventChoice(id: "loneliness_note", title: "写下没递出的纸条", detail: "承认感受，支持感小幅回升"),
                    EventChoice(id: "loneliness_mask", title: "装作没事", detail: "短期维持秩序，面具成本上升")
                ]
            )
            addAudioCue(.heartbeat, direction: "颅内", intensity: 0.86, note: "孤独感出现时，身体声音会盖过教室里的其他人。")
            audio.playWarning()
            return
        }

        if player.psychicEnergy <= 5 || player.stress >= 96 {
            if player.support > 55 {
                player.psychicEnergy = 24
                player.stress = 62
                appendEvent(title: "支持网络保护", detail: "同桌的主动关心把你从崩溃边缘拉回来了。")
                presentEvent(
                    kind: .supportOffer,
                    title: "支持网络保护",
                    body: "同桌注意到你不对劲，轻轻推来一张纸：要不要先喘口气？支持网络在崩溃前接住了你。",
                    choices: [
                        EventChoice(id: "accept_support", title: "接受帮助", detail: "能量恢复，面具成本下降"),
                        EventChoice(id: "smile_only", title: "只笑一下", detail: "保持距离，少量恢复"),
                        EventChoice(id: "reject_support", title: "推回纸条", detail: "维持面具，关系受损")
                    ]
                )
                addAudioCue(.paper, direction: "左侧近处", intensity: 0.58, note: "一张纸的摩擦声成了求助入口。")
            } else {
                finish()
            }
        }
    }

    private func finish() {
        if replay.isEmpty {
            recordSnapshot(actionLabel: "结束")
        }
        commitClassmateMemory()
        selectedReplayIndex = max(0, replay.count - 1)
        gameState = .ending(calculateEnding())
        audio.stop()
    }

    private func calculateEnding() -> Ending {
        if viewMode == .teacher || teacher.studentsWarned + teacher.studentsHelped > 4 {
            return teacherEnding()
        }

        if player.psychicEnergy <= 8 || player.stress >= 96 {
            return Ending(
                title: "崩溃边缘",
                body: "这不是失败。这是信号：你的角色需要休息，需要说话，需要被看见。",
                reflection: "如果你或你认识的人正在经历类似感受，求助不是软弱，而是有效行动。",
                story: endingStory(kind: .breakdown),
                empathyReflections: empathyReflections(kind: .breakdown),
                relationshipEchoes: relationshipEchoes(),
                analysis: endingMetrics(),
                comparisons: endingComparisons(),
                resources: supportResources()
            )
        }

        if player.helpedClassmate && player.support >= 58 {
            return Ending(
                title: "社交之夜",
                body: "你没有完成最多作业，但你帮助同桌度过了一次焦虑峰值。这很重要。",
                reflection: "支持网络提高恢复速度，也提高崩溃阈值。",
                story: endingStory(kind: .social),
                empathyReflections: empathyReflections(kind: .social),
                relationshipEchoes: relationshipEchoes(),
                analysis: endingMetrics(),
                comparisons: endingComparisons(),
                resources: supportResources()
            )
        }

        if player.homework >= 85 && player.maskCost > 68 {
            return Ending(
                title: "学霸之夜",
                body: "你完成了大部分任务，也付出了明显的面具成本。",
                reflection: "效率不是唯一指标。你今晚有没有注意到自己累到什么程度？",
                story: endingStory(kind: .academic),
                empathyReflections: empathyReflections(kind: .academic),
                relationshipEchoes: relationshipEchoes(),
                analysis: endingMetrics(),
                comparisons: endingComparisons(),
                resources: supportResources()
            )
        }

        if player.exposure > 70 {
            return Ending(
                title: "摸鱼大师",
                body: "你成功逃离了一部分制度压力，但逃避本身也在消耗你。",
                reflection: "短暂休息可以恢复能量，长期高风险躲避会推高压力。",
                story: endingStory(kind: .escape),
                empathyReflections: empathyReflections(kind: .escape),
                relationshipEchoes: relationshipEchoes(),
                analysis: endingMetrics(),
                comparisons: endingComparisons(),
                resources: supportResources()
            )
        }

        return Ending(
            title: "普通的一晚",
            body: "你在学习、观察、休息和连接之间摇摆，没有标准答案，只有后果。",
            reflection: "今晚你经历了 \(Int(player.stress / 24 + 1)) 次焦虑峰值。老师提醒 \(teacher.studentsWarned) 次，关心 \(teacher.studentsHelped) 次。",
            story: endingStory(kind: .ordinary),
            empathyReflections: empathyReflections(kind: .ordinary),
            relationshipEchoes: relationshipEchoes(),
            analysis: endingMetrics(),
            comparisons: endingComparisons(),
            resources: supportResources()
        )
    }

    private func teacherEnding() -> Ending {
        let protected = teacher.studentsHelped + Int(classmates.filter { $0.state != .crying && $0.stress < 72 }.count / 5)
        let missed = classmates.filter { $0.stress > 82 || $0.state == .crying }.count
        let title = teacher.studentsHelped >= teacher.studentsWarned ? "教师理解" : "制度压力传导"
        let body = teacher.studentsHelped >= teacher.studentsWarned
            ? "你今晚选择性执法了。你保护了 \(protected) 个学生，但仍可能错过 \(missed) 个真正需要帮助的人。"
            : "你维持住了表面的纪律，但提醒和巡逻也把压力传给了学生。管理不是只有秩序，也包括看见。"
        return Ending(
            title: title,
            body: body,
            reflection: "教师也是系统中的人。疲惫、KPI 和同理心会共同决定一次管理行为的后果。",
            story: endingStory(kind: .teacher),
            empathyReflections: empathyReflections(kind: .teacher),
            relationshipEchoes: relationshipEchoes(),
            analysis: endingMetrics(extra: [
                EndingMetric(title: "保护学生", value: "\(protected)", note: "通过关心、选择性放过或降低压力产生"),
                EndingMetric(title: "可能错过", value: "\(missed)", note: "高压力或崩溃状态学生数量")
            ]),
            comparisons: endingComparisons(),
            resources: supportResources()
        )
    }

    private enum EndingStoryKind {
        case breakdown
        case social
        case academic
        case escape
        case ordinary
        case teacher
    }

    private func endingStory(kind: EndingStoryKind) -> EndingStory {
        let peaks = Int(max(1, ceil(player.stress / 24)))
        let time = clockText
        switch kind {
        case .breakdown:
            return EndingStory(
                title: "访谈片段：那不是突然发生的",
                body: "有个学生说，最难受的不是最后哭出来，而是前面很长一段时间都在装没事。灯很亮，教室很安静，他却只能听见自己的心跳。后来他才明白，崩溃不是性格差，而是身体一直在发求救信号。",
                prompt: "回看今晚：第 \(peaks) 次焦虑峰值之前，哪个信号最早出现？"
            )
        case .social:
            return EndingStory(
                title: "访谈片段：有人看见我",
                body: "一个同桌回忆，真正帮到他的不是大道理，而是一张纸巾、一次很小声的询问。那一刻他没有立刻变好，但他知道自己不是独自坐在压力里。",
                prompt: "今晚你付出的连接成本，换来了什么保护？"
            )
        case .academic:
            return EndingStory(
                title: "访谈片段：成绩很好的人也会累",
                body: "有人说，最难承认的是：作业完成得越多，越不好意思说自己撑不住。别人只看到进度，看不到维持完美需要消耗多少面具。",
                prompt: "如果只看完成度，你会漏掉哪些身体和情绪信息？"
            )
        case .escape:
            return EndingStory(
                title: "访谈片段：我只是想离开几分钟",
                body: "有学生说，看手机、看窗外、去洗手间并不总是偷懒。有时那是他们能想到的唯一自救方式。问题不在于休息本身，而在于休息只能偷偷发生。",
                prompt: "如果教室允许合法休息，今晚的风险会怎么变？"
            )
        case .ordinary:
            return EndingStory(
                title: "访谈片段：普通也值得被记录",
                body: "很多晚自习没有戏剧性事件。没有人哭，没有人被骂，也没有人真正被看见。可压力就是在这些普通夜晚里慢慢累积的。",
                prompt: "\(time) 结束时，你最想让别人理解这一晚的哪一部分？"
            )
        case .teacher:
            return EndingStory(
                title: "访谈片段：老师也在系统里",
                body: "一位老师说，他后来才意识到，管理纪律时最难的不是发现违规，而是判断一个动作背后到底是挑衅、疲惫，还是求救。班级秩序会给老师压力，学生的沉默也会。",
                prompt: "从教师视角看，哪一次提醒其实可以变成一次关心？"
            )
        }
    }

    private func empathyReflections(kind: EndingStoryKind) -> [EmpathyReflection] {
        let classRisk = classmates.filter { $0.stress > 76 || $0.state == .crying }.count
        let teacherLoad = teacher.fatigue + teacher.kpiPressure - teacher.empathy * 0.35
        let bodyNeed = Int(max(player.hunger, player.bladder))
        let studentText: String
        let teacherText: String
        let familyText: String

        switch kind {
        case .breakdown:
            studentText = "这不是意志力不够，而是能量、压力、身体需求同时越界。最早的信号比最后的崩溃更值得被看见。"
            teacherText = "当一个学生突然失控时，前面通常已经有很多小动作、沉默和回避。提醒纪律之前，可以先判断是不是求救。"
            familyText = "如果孩子只说“没事”，可以少追问成绩，多问今天最累的时刻在哪里。可谈论的空间比一次说教更重要。"
        case .social:
            studentText = "你把一部分能量给了同桌，也从关系里拿回一点支撑。支持不是解决全部问题，而是让人撑过一个峰值。"
            teacherText = "班级里的互相照顾不是纪律松动的反面。被允许的低声支持，可能减少更大的情绪风险。"
            familyText = "孩子愿意关心别人，也需要被关心。不要只看作业完成量，也要看他今晚承担了多少情绪劳动。"
        case .academic:
            studentText = "完成度很高不代表状态很好。面具负荷 \(Int(player.maskCost)) 时，优秀也可能是在透支。"
            teacherText = "最安静、最会完成任务的学生也可能风险很高。只按成绩筛查，会漏掉很多压力。"
            familyText = "如果只奖励结果，孩子会更难承认疲惫。可以同时问“完成了多少”和“你付出了什么代价”。"
        case .escape:
            studentText = "看手机、看窗外或想离开座位，可能是你在寻找短暂恢复。真正的问题是恢复只能偷偷发生。"
            teacherText = "违规动作不一定等于挑衅。给出合法休息选项，可能比连续抓违规更能降低班级风险。"
            familyText = "当孩子总想逃离学习场景时，先理解他在逃离什么：困、饿、焦虑、孤独，还是无法开口的压力。"
        case .ordinary:
            studentText = "普通一晚也会累积压力。身体需求峰值 \(bodyNeed)，支持 \(Int(player.support))，这些细节比“有没有出事”更接近真相。"
            teacherText = "没有明显事件不等于班级安全。今晚仍有 \(classRisk) 个学生处在较高风险里，沉默需要被主动观察。"
            familyText = "很多问题不会以大事件出现，而是藏在普通夜晚后的沉默、拖延和疲惫里。稳定倾听比快速判断更有用。"
        case .teacher:
            studentText = "从教师视角看完后，再回到座位，会发现每个“异常动作”背后都有一种未被说出的理由。"
            teacherText = "今晚的教师负荷约为 \(Int(teacherLoad.clamped(to: 0...100)))。制度压力真实存在，但它不能替代对学生处境的判断。"
            familyText = "家长看到的不只是孩子和老师的冲突，也是一套压力系统。沟通目标应从追责转向共同降低风险。"
        }

        return [
            EmpathyReflection(role: "学生", icon: "person.fill", text: studentText),
            EmpathyReflection(role: "教师", icon: "graduationcap.fill", text: teacherText),
            EmpathyReflection(role: "家长", icon: "house.fill", text: familyText)
        ]
    }

    private func relationshipEchoes() -> [RelationshipEcho] {
        let remembered = classmates
            .filter { classmate in
                classmate.hasSharedTruth
                    || classmate.relationship > 58
                    || classmate.relationship < 24
                    || classmate.suspicionOfPlayer > 28
                    || classmate.stress > 78
                    || classmate.state == .crying
            }
            .sorted { lhs, rhs in
                relationshipEchoScore(lhs) > relationshipEchoScore(rhs)
            }

        return remembered.prefix(4).map { classmate in
            RelationshipEcho(
                name: classmate.name,
                title: relationshipEchoTitle(for: classmate),
                text: relationshipEchoText(for: classmate)
            )
        }
    }

    private func relationshipEchoScore(_ classmate: Classmate) -> Double {
        abs(classmate.relationship - 35)
            + classmate.stress * 0.28
            + classmate.suspicionOfPlayer * 0.5
            + (classmate.hasSharedTruth ? 24 : 0)
            + (classmate.state == .crying ? 20 : 0)
    }

    private func relationshipEchoTitle(for classmate: Classmate) -> String {
        if classmate.state == .crying { return "未结束的求救" }
        if classmate.hasSharedTruth && classmate.relationship > 58 { return "被接住的真话" }
        if classmate.suspicionOfPlayer > 38 { return "没有消失的怀疑" }
        if classmate.relationship < 24 { return "变远的位置" }
        if classmate.stress > 78 { return "压力余波" }
        return "关系余温"
    }

    private func relationshipEchoText(for classmate: Classmate) -> String {
        if classmate.state == .crying {
            return "\(classmate.name)今晚的崩溃不会因为下课自动清零。下一次见到你时，TA 仍可能带着这段压力余波。"
        }
        if classmate.hasSharedTruth && classmate.relationship > 58 {
            return "\(classmate.name)记得你接住过一次真实状态。下一局开始时，这段信任会让求助和掩护更容易发生。"
        }
        if classmate.suspicionOfPlayer > 38 {
            return "\(classmate.name)记得你的异常动作。下一次晚自习，TA 可能更早注意你，也更容易把风险传给老师。"
        }
        if classmate.relationship < 24 {
            return "\(classmate.name)和你的距离变远了。沉默也会成为记忆，降低之后建立支持的可能。"
        }
        if classmate.stress > 78 {
            return "\(classmate.name)没有明显出事，但压力还留在身体里。下一次开始时，TA 的阈值会更低。"
        }
        return "\(classmate.name)和你的关系留下了一点余温。它不保证安全，但会改变下一次眼神和纸条的含义。"
    }

    private func endingMetrics(extra: [EndingMetric] = []) -> [EndingMetric] {
        let anxiousPeaks = Int(max(1, ceil(player.stress / 24)))
        let energySpent = Int((100 - player.psychicEnergy).clamped(to: 0...100))
        let maskLoad = Int(player.maskCost)
        let supportBuffer = Int(player.support)
        let classRisk = classmates.filter { $0.stress > 76 || $0.state == .crying }.count

        return [
            EndingMetric(title: "焦虑峰值", value: "\(anxiousPeaks)", note: "由压力、暴露和心理能量共同估算"),
            EndingMetric(title: "心理消耗", value: "\(energySpent)", note: "今晚从能量池中消耗的近似值"),
            EndingMetric(title: "面具负荷", value: "\(maskLoad)", note: "维持好学生形象的心理成本"),
            EndingMetric(title: "支持缓冲", value: "\(supportBuffer)", note: "关系越强，崩溃阈值越高"),
            EndingMetric(title: "身体需求", value: "\(Int(max(player.hunger, player.bladder)))", note: "饥饿和如厕需求会抢走注意力"),
            EndingMetric(title: "班级风险", value: "\(classRisk)", note: "仍处于高压力或崩溃边缘的同学"),
            EndingMetric(title: "记忆延续", value: "\(classmateMemory.count)", note: "重开后仍会影响关系、压力余波和怀疑"),
            EndingMetric(title: "结束时间", value: clockText, note: currentPeriod.displayName),
            EndingMetric(title: "制度设置", value: "\(Int(settings.studyHours * 60))分", note: "\(settings.allowsWhispering ? "允许交流" : "禁止交流") · 排名 \(Int(settings.rankingPressure))")
        ] + extra
    }

    private func endingComparisons() -> [EndingComparison] {
        let anxiousPeaks = Double(max(1, ceil(player.stress / 24)))
        let referencePeaks = 5.2
        let shorterStudy = max(1.0, settings.studyHours - 1)
        let shorterEstimate = max(1.0, anxiousPeaks - (settings.studyHours - shorterStudy) * 1.1 - (settings.allowsWhispering ? 0.2 : 0.6))
        let noRankingEstimate = max(1.0, anxiousPeaks - settings.rankingPressure / 45)
        let whisperEstimate = max(1.0, anxiousPeaks - (settings.allowsWhispering ? 0 : 0.7))

        return [
            EndingComparison(
                title: "焦虑峰值对照",
                playerValue: "\(String(format: "%.1f", anxiousPeaks)) 次",
                referenceValue: "参考平均 5.2 次",
                note: anxiousPeaks > referencePeaks ? "今晚高于参考值，说明角色处在较密集的压力波动里。" : "今晚低于参考值，但低并不等于没有压力。"
            ),
            EndingComparison(
                title: "少一小时晚自习",
                playerValue: "\(String(format: "%.1f", shorterEstimate)) 次估算",
                referenceValue: "\(Int(shorterStudy * 60)) 分钟",
                note: "缩短时长通常降低疲劳累积，但也可能压缩作业时间。"
            ),
            EndingComparison(
                title: "取消排名压力",
                playerValue: "\(String(format: "%.1f", noRankingEstimate)) 次估算",
                referenceValue: "排名 0",
                note: "排名压力越低，守序同学和教师 KPI 传导越弱。"
            ),
            EndingComparison(
                title: "允许低声交流",
                playerValue: "\(String(format: "%.1f", whisperEstimate)) 次估算",
                referenceValue: "允许交流",
                note: "合法交流会降低求助成本，也会改变暴露风险。"
            )
        ]
    }

    private func supportResources() -> [SupportResource] {
        [
            SupportResource(title: "中国心理援助热线", detail: "400-161-9995"),
            SupportResource(title: "北京 24 小时心理援助热线", detail: "010-82951332"),
            SupportResource(title: "上海心理援助热线", detail: "021-12320-5"),
            SupportResource(title: "学校心理咨询中心", detail: "如果你在学校，可以优先联系班主任、校医或心理老师。")
        ]
    }

    private func updatePerception() {
        let near = teacher.isNearPlayer ? 0.85 : 0.25
        let cryingLeft = classmates.contains { ($0.seat.row == 2 && $0.seat.column == 0) && $0.state == .crying }
        peripheralLeft = cameraPose == .left ? 0.1 : max(cryingLeft ? 0.75 : 0, Double.random(in: 0.1...0.45))
        peripheralRight = max(near, cameraPose == .right ? 0.12 : Double.random(in: 0.2...0.65))
        audio.updateStress(energy: player.psychicEnergy, stress: player.stress, teacherNear: teacher.isNearPlayer, support: player.support, classroomNoise: classroomNoise)
        audio.updateAmbient(classroomNoise: classroomNoise, period: currentPeriod, lightLevel: classroomLightLevel, elapsedMinutes: elapsedMinutes)
    }

    private func applyBodyNeeds() {
        player.hunger += currentPeriod.isBreak ? 2.5 : 4.2 * currentPeriod.fatigueMultiplier
        player.bladder += currentPeriod.isBreak ? 1.8 : 3.1 * currentPeriod.fatigueMultiplier
        if player.hunger > 78 {
            player.stress += 3
            player.focusQuality = min(player.focusQuality, 0.82)
            if Double.random(in: 0...1) < 0.28 {
                addAudioCue(.stomach, direction: "颅内", intensity: min(1, player.hunger / 100), note: "饥饿不是意志力问题，它会直接抢走注意力。")
                addMonologue("肚子叫的时候，我才想起身体也在上晚自习。", intensity: 0.54)
            }
        }
        if player.bladder > 72 {
            player.stress += 2.5
            player.visualAttention = max(0, player.visualAttention - 2.5)
            if Double.random(in: 0...1) < 0.24 {
                addAudioCue(.chair, direction: "座位下方", intensity: min(0.9, player.bladder / 120), note: "身体需求会让坐姿变得不稳定，固定座位本身成为压力。")
                addMonologue("我开始计算什么时候举手比较不显眼。", intensity: 0.5)
            }
        }
        clampPlayer()
    }

    var elapsedMinutes: Int {
        guard maxTurns > 0 else { return 0 }
        return max(0, min(settings.totalMinutes, Int(Double(max(0, currentTurn - 1)) / Double(maxTurns) * Double(settings.totalMinutes))))
    }

    var clockText: String {
        let startHour = 18
        let startMinute = 30
        let total = startHour * 60 + startMinute + elapsedMinutes
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    var currentPeriod: StudyPeriod {
        StudyPeriod.period(forElapsedMinutes: elapsedMinutes, totalMinutes: settings.totalMinutes)
    }

    private func applyTimeProgression() {
        let period = currentPeriod
        guard triggeredPeriods.contains(period) == false else { return }
        triggeredPeriods.insert(period)

        switch period {
        case .breakOne, .breakTwo:
            player.psychicEnergy = min(100, player.psychicEnergy + 10)
            recoverAttention(15)
            player.maskCost = max(0, player.maskCost - (settings.allowsWhispering ? 10 : 4))
            player.stress = max(0, player.stress - 6)
            player.bladder = max(0, player.bladder - 18)
            appendEvent(title: period.displayName, detail: "短暂休息让教室的紧绷松开一点。")
            addAudioCue(.chair, direction: "教室四周", intensity: 0.48, note: "课间椅子声和低语短暂盖过了纪律。")
            message = "\(clockText)，\(period.displayName)。所有人都像终于被允许呼吸了一下。"
        case .third:
            player.stress += 8
            teacher.fatigue += 8
            appendEvent(title: "第三节", detail: "疲惫上来，吊扇声成为新的环境底噪。")
            addAudioCue(.lights, direction: "头顶", intensity: 0.42, note: "第三节吊扇和灯管声混在一起，掩盖了一些小动作。")
            addAudioCue(.teacherSigh, direction: "讲台前方", intensity: 0.5, note: "第三节老师也明显疲惫了，管理压力不只压在学生身上。")
            message = "\(clockText)，第三节开始。吊扇声变明显，人的反应也慢下来。"
        case .first, .second:
            appendEvent(title: period.displayName, detail: "\(clockText) 进入\(period.displayName)，制度节奏重新收紧。")
        }
    }

    private func updateClassmates(after action: PlayerAction?) {
        for index in classmates.indices {
            var classmate = classmates[index]
            let isDeskmate = classmate.seat.row == 2 && (classmate.seat.column == 0 || classmate.seat.column == 2)
            let stressDrift = Double.random(in: -2...5) + (teacher.isNearPlayer ? 1.5 : 0)
            let rankingDrift = settings.rankingPressure / 80
            let whisperRelief = settings.allowsWhispering ? -1.2 : 0
            let periodDrift = currentPeriod.isBreak ? -2.4 : currentPeriod.fatigueMultiplier
            let anxietyDrift = (classmate.profile.anxiety - 50) / 36
            let maskRelief = (classmate.profile.maskStrength - 50) / 60
            let orderPressure = settings.rankingPressure > 60 ? (classmate.profile.orderliness - 50) / 55 : 0
            classmate.stress = (classmate.stress + stressDrift + rankingDrift + whisperRelief + periodDrift + anxietyDrift + orderPressure - maskRelief).clamped(to: 0...100)

            if isDeskmate && action == .talk {
                classmate.relationship = (classmate.relationship + 14).clamped(to: 0...100)
                classmate.stress = max(0, classmate.stress - 12)
                classmate.hasSharedTruth = true
            }

            if isDeskmate && action == .phone {
                applyDeskmateReactionToPhone(&classmate)
            }

            if isDeskmate && action == .phone && (classmate.state == .covering || classmate.state == .usingPhone || classmate.state == .anxious) {
                classmates[index] = classmate
                continue
            } else if isDeskmate && player.psychicEnergy < 28 && classmate.relationship > 58 && classmate.profile.empathy > 46 {
                classmate.state = .offeringHelp
                player.support = (player.support + 5).clamped(to: 0...100)
            } else if classmate.stress > 92 {
                classmate.state = .crying
            } else if classmate.stress > 76 {
                classmate.state = .anxious
            } else if Double.random(in: 0...1) < 0.04 + classmate.profile.rebelliousness / 1_200 {
                classmate.state = .usingPhone
            } else if Double.random(in: 0...1) < 0.04 + (100 - classmate.profile.maskStrength) / 1_400 {
                classmate.state = .sleeping
            } else if isDeskmate && classmate.relationship > 64 && action == .phone && classmate.state != .usingPhone {
                classmate.state = .covering
                player.exposure = max(0, player.exposure - 9)
            } else {
                classmate.state = .studying
            }

            classmates[index] = classmate
        }

        if currentTurn == 10 && classroomLightLevel > 0.9 && Double.random(in: 0...1) < 0.34 {
            classroomLightLevel = 0.32
            appendEvent(title: "短暂停电", detail: "灯管灭下去的一瞬间，手机屏幕和窗外路灯突然变得刺眼。")
            presentEvent(
                kind: .powerOutage,
                title: "短暂停电",
                body: "教室灯管忽然灭了一秒。没有人说话，但每个人都抬了一下头。黑暗让压力短暂显形。",
                choices: [
                    EventChoice(id: "look_around", title: "观察四周", detail: "获得班级状态，消耗注意力"),
                    EventChoice(id: "rest_eyes", title: "闭眼休息", detail: "恢复注意力，错过信息"),
                    EventChoice(id: "check_phone_dark", title: "看手机消息", detail: "短暂恢复，暴露风险上升")
                ]
            )
            addAudioCue(.lights, direction: "头顶", intensity: 0.9, note: "灯管嗡鸣突然断掉，安静变得可见。")
        } else if shouldTriggerPhoneNotification(action: action) {
            hasTriggeredPhoneNotification = true
            appendEvent(title: "手机通知", detail: "一条消息在桌面偏右震动。连接欲望和暴露风险同时出现。")
            addMonologue("有人在外面找我。那一秒，教室好像裂开了一条缝。", intensity: 0.66)
            presentEvent(
                kind: .phoneNotification,
                title: "手机通知",
                body: "桌面偏右传来一声短促震动。你不知道是谁发来的，但那一点蓝光像是在提醒你：教室外还有另一个世界。",
                choices: [
                    EventChoice(id: "read_notification", title: "快速看一眼", detail: "恢复能量，暴露和面具成本上升"),
                    EventChoice(id: "ignore_notification", title: "扣住手机", detail: "风险下降，但错过连接"),
                    EventChoice(id: "ask_mate_cover", title: "让同桌掩护", detail: "依赖支持网络，关系可能加深")
                ]
            )
            addAudioCue(.phone, direction: "桌面偏右", intensity: teacher.isNearPlayer ? 0.9 : 0.68, note: "消息提示音很短，却足够让注意力离开作业。")
        } else if shouldTriggerBroadcast() {
            hasTriggeredBroadcast = true
            teacher.kpiPressure += 8
            appendEvent(title: "广播通知", detail: "年级广播把制度压力重新推回每个教室。")
            presentEvent(
                kind: .broadcast,
                title: "广播通知",
                body: "讲台上方的广播忽然响起：请各班保持晚自习纪律，值班老师加强巡视。声音不大，却让整间教室同时绷紧。",
                choices: [
                    EventChoice(id: "sit_straight_broadcast", title: "坐直装认真", detail: "暴露下降，面具成本上升"),
                    EventChoice(id: "observe_broadcast", title: "观察全班反应", detail: "获得信息，消耗注意力"),
                    EventChoice(id: "breathe_broadcast", title: "低头呼吸", detail: "压力下降，但错过部分信息")
                ]
            )
            addAudioCue(.broadcast, direction: "讲台前方", intensity: 0.82, note: "广播是制度声音，不属于某个人，却会改变所有人的动作。")
        } else if shouldTriggerKnockOnDoor() {
            hasTriggeredKnockOnDoor = true
            teacher.fatigue += 3
            appendEvent(title: "后门敲响", detail: "后方门口传来两下敲门声，所有人都在猜是谁。")
            presentEvent(
                kind: .knockOnDoor,
                title: "后门敲响",
                body: "后门方向传来两下很轻的敲门声。没有人立刻说话，你只能从椅子停顿、老师抬头和同学余光里判断发生了什么。",
                choices: [
                    EventChoice(id: "listen_knock", title: "只听声音", detail: "获得线索，压力小幅上升"),
                    EventChoice(id: "turn_to_door", title: "回头确认", detail: "获得确定信息，暴露和注意力消耗上升"),
                    EventChoice(id: "ignore_knock", title: "继续写题", detail: "维持秩序，但不确定感保留")
                ]
            )
            addAudioCue(.knock, direction: "后方左侧", intensity: 0.74, note: "后门敲门声很轻，但不确定性让它变得很响。")
        } else if let memoryMate = memoryTrustCandidate() {
            hasTriggeredMemoryTrust = true
            appendEvent(title: "\(memoryMate.name)记得你", detail: "上一晚留下的信任让求助来得更早。")
            presentEvent(
                kind: .memoryTrust(classmateID: memoryMate.id),
                title: "\(memoryMate.name)递来纸条",
                body: memoryTrustBody(for: memoryMate),
                choices: [
                    EventChoice(id: "accept_memory_trust", title: "收下纸条", detail: "支持上升，关系延续"),
                    EventChoice(id: "return_memory_trust", title: "写一句谢谢", detail: "加深信任，暴露小幅上升"),
                    EventChoice(id: "avoid_memory_trust", title: "假装没看见", detail: "切断余温，面具成本上升")
                ]
            )
            addAudioCue(.paper, direction: memoryMate.seat.column <= 1 ? "左侧近处" : "右侧近处", intensity: 0.46, note: "这张纸条不是随机事件，而是上一晚留下的关系回声。")
        } else if let suspiciousMate = memorySuspicionCandidate() {
            hasTriggeredMemorySuspicion = true
            appendEvent(title: "\(suspiciousMate.name)提前注意", detail: "上一晚的怀疑让同学更早看向你。")
            presentEvent(
                kind: .memorySuspicion(classmateID: suspiciousMate.id),
                title: "\(suspiciousMate.name)在观察你",
                body: memorySuspicionBody(for: suspiciousMate),
                choices: [
                    EventChoice(id: "repair_memory_suspicion", title: "低声解释", detail: "修复关系，暴露真实状态"),
                    EventChoice(id: "hide_from_memory_suspicion", title: "收起所有动作", detail: "短期安全，面具成本上升"),
                    EventChoice(id: "challenge_memory_suspicion", title: "回看过去", detail: "压制对方，关系明显受损")
                ]
            )
            addAudioCue(.whisper, direction: suspiciousMate.seat.column <= 1 ? "左侧近处" : "右侧近处", intensity: 0.5, note: "怀疑也会跨过一晚，变成提前出现的听觉压力。")
        } else if let request = classmateHelpRequestCandidate() {
            hasTriggeredClassmateHelpRequest = true
            appendEvent(title: "\(request.name)求助", detail: "\(request.name)没有明说，只把草稿纸推近了一点。")
            presentEvent(
                kind: .classmateHelpRequest(classmateID: request.id),
                title: "\(request.name)的求助",
                body: helpRequestBody(for: request),
                choices: [
                    EventChoice(id: "quiet_help_classmate", title: "低声回应", detail: "建立支持，暴露小幅上升"),
                    EventChoice(id: "share_breath_classmate", title: "一起呼吸", detail: "降低双方压力，进度放慢"),
                    EventChoice(id: "ignore_help_classmate", title: "装作没看见", detail: "维持安全，关系和支持下降")
                ]
            )
            addAudioCue(.paper, direction: request.seat.column <= 1 ? "左侧近处" : "右侧近处", intensity: 0.5, note: "纸边轻轻碰到桌面，求助被压成了几乎听不见的声音。")
        } else if let reporter = classmateReportCandidate() {
            hasTriggeredClassmateReport = true
            appendEvent(title: "\(reporter.name)犹豫举报", detail: "\(reporter.name)在守纪律和不伤害同学之间摇摆。")
            presentEvent(
                kind: .classmateReport(classmateID: reporter.id),
                title: "\(reporter.name)看向老师",
                body: reportBody(for: reporter),
                choices: [
                    EventChoice(id: "admit_to_reporter", title: "承认自己太累", detail: "降低举报风险，暴露真实状态"),
                    EventChoice(id: "pressure_reporter", title: "让他别说", detail: "暂时压住风险，关系受损"),
                    EventChoice(id: "stop_and_reset", title: "立刻收手", detail: "暴露下降，面具成本上升")
                ]
            )
            addAudioCue(.whisper, direction: reporter.seat.column <= 1 ? "左侧近处" : "右侧近处", intensity: 0.52, note: "同学的犹豫也有声音：笔尖停住，视线转向讲台。")
        } else if classroomLightLevel < 1.0 {
            classroomLightLevel = min(1.0, classroomLightLevel + 0.18)
        }
    }

    private func applyDeskmateReactionToPhone(_ classmate: inout Classmate) {
        classmate.suspicionOfPlayer = (classmate.suspicionOfPlayer + 14 + player.exposure / 8).clamped(to: 0...100)

        if classmate.profile.empathy > 68 && player.psychicEnergy < 48 {
            classmate.state = .covering
            classmate.relationship = (classmate.relationship + 8).clamped(to: 0...100)
            classmate.hasSharedTruth = true
            player.exposure = max(0, player.exposure - 14)
            player.support = (player.support + 5).clamped(to: 0...100)
            appendEvent(title: "\(classmate.name)掩护", detail: "\(classmate.name)没有举报，而是用练习册遮住了你的手机。")
            addAudioCue(.paper, direction: "左侧近处", intensity: 0.42, note: "同桌挪动练习册的声音很轻，但替你挡住了一部分视线。")
        } else if classmate.profile.rebelliousness > 72 {
            classmate.state = .usingPhone
            classmate.relationship = (classmate.relationship + 6).clamped(to: 0...100)
            classmate.stress += 4
            player.exposure += 4
            appendEvent(title: "\(classmate.name)跟风", detail: "你的手机亮起后，\(classmate.name)也低头看了一眼屏幕。")
            addAudioCue(.phone, direction: "左侧近处", intensity: 0.5, note: "旁边也亮起一小块蓝光，违规变成了互相确认。")
        } else if classmate.profile.orderliness > 76 && classmate.suspicionOfPlayer > 34 {
            classmate.state = .anxious
            classmate.relationship = max(0, classmate.relationship - 8)
            player.exposure += 16
            player.stress += 8
            teacher.kpiPressure = max(0, teacher.kpiPressure - 4)
            appendEvent(title: "\(classmate.name)举报", detail: "守序的同桌犹豫后看向老师，你的违规从私人风险变成公开风险。")
            addAudioCue(.whisper, direction: "左侧近处", intensity: 0.56, note: "一句很小的提醒，足够把老师的注意力引过来。")
        } else if classmate.profile.cooperation > 66 {
            classmate.state = .covering
            classmate.relationship = (classmate.relationship + 3).clamped(to: 0...100)
            player.exposure = max(0, player.exposure - 6)
            appendEvent(title: "\(classmate.name)眼神提醒", detail: "\(classmate.name)看了你一眼，又看向讲台，提醒你风险正在靠近。")
        }
    }

    private func shouldTriggerPhoneNotification(action: PlayerAction?) -> Bool {
        guard !hasTriggeredPhoneNotification, currentTurn >= 4, currentTurn <= max(5, maxTurns - 3), currentPeriod.isBreak == false else {
            return false
        }
        if action == .phone { return false }
        let socialNeed = (100 - player.support) * 0.006 + player.stress * 0.004
        let chance = min(0.42, 0.12 + socialNeed)
        return Double.random(in: 0...1) < chance
    }

    private func shouldTriggerBroadcast() -> Bool {
        guard !hasTriggeredBroadcast, currentTurn >= max(5, maxTurns / 2), currentPeriod.isBreak == false else {
            return false
        }
        let institutionalPressure = settings.rankingPressure * 0.004 + teacher.fatigue * 0.002
        return Double.random(in: 0...1) < min(0.36, 0.12 + institutionalPressure)
    }

    private func shouldTriggerKnockOnDoor() -> Bool {
        guard !hasTriggeredKnockOnDoor, currentTurn >= 5, currentTurn <= maxTurns - 1, currentPeriod.isBreak == false else {
            return false
        }
        let uncertainty = player.exposure * 0.003 + teacher.institutionalPressure * 0.002
        return Double.random(in: 0...1) < min(0.32, 0.1 + uncertainty)
    }

    private func helpRequestBody(for classmate: Classmate) -> String {
        let name = classmate.name
        if classmate.profile.anxiety > 70 {
            return "\(name)把橡皮擦在同一行来回推，草稿纸边缘写着：我心跳有点快。高焦虑的人求助时常常不是说“救救我”，而是先确认旁边的人会不会嘲笑。"
        }
        if classmate.profile.maskStrength < 38 {
            return "\(name)一直想把表情摆回正常，但手指已经压皱了纸角。纸上只有一句：我装不下去了。你能感觉到这不是闲聊，而是面具开始破裂。"
        }
        if classmate.profile.empathy > 72 {
            return "\(name)先看了看你的状态，像是担心打扰你，然后才把纸推过来：你如果也很累，我们可以一起慢一点。求助和关心在同一个动作里。"
        }
        if classmate.profile.rebelliousness > 72 {
            return "\(name)平时看起来不太服管，这次却把字写得很小：我不想再坐着了。叛逆有时不是挑衅，而是最后一点自救方式。"
        }
        return "\(name)的笔停了很久，草稿纸边缘写着一行很小的字：我有点撑不住。你能感觉到这不是闲聊，而是一次很小心的求助。"
    }

    private func reportBody(for classmate: Classmate) -> String {
        let name = classmate.name
        if classmate.profile.orderliness > 78 {
            return "\(name)的作业本边缘对得很齐，视线却一直从你桌面滑向讲台。对 TA 来说，守纪律不是告密，而是唯一知道的安全方式。"
        }
        if classmate.profile.anxiety > 68 {
            return "\(name)不是想伤害你，只是你的动作让 TA 也紧张起来。TA 的笔尖停在半空，像是在等一个能让教室重新确定下来的信号。"
        }
        if classmate.profile.empathy > 58 {
            return "\(name)已经注意到你，但迟迟没有看向老师。TA 在风险、同情和自保之间摇摆，你们都被同一套规则推着走。"
        }
        return "\(name)已经注意到你的动作。他很守序，也很紧张，视线在你、作业本和讲台之间来回。你意识到：同学也可能成为制度压力的一部分。"
    }

    private func memoryTrustBody(for classmate: Classmate) -> String {
        let name = classmate.name
        if classmate.profile.empathy > 72 {
            return "\(name)没有重新确认你是不是可靠的人，而是直接把纸条推到你手边：今天如果撑不住，可以先告诉我。高同理心让上一晚的信任更早变成行动。"
        }
        if classmate.profile.anxiety > 68 {
            return "\(name)递纸条时手还有点抖：昨天你没有笑我，今天我也会帮你看着点。被接住过的人，会更小心地接住别人。"
        }
        if classmate.profile.maskStrength < 38 {
            return "\(name)把纸条压在作业本下面推过来：别又一个人装没事。上一晚的真话没有消失，只是换成了更隐蔽的提醒。"
        }
        return "\(name)没有重新确认你是不是可靠的人，而是直接把纸条推到你手边：今天如果撑不住，可以先告诉我。你意识到，上一晚没有完全过去。"
    }

    private func memorySuspicionBody(for classmate: Classmate) -> String {
        let name = classmate.name
        if classmate.profile.orderliness > 76 {
            return "\(name)今天很早就注意到你的桌面，作业本已经往讲台方向挪了一点。守序的人会记住不确定性，并提前把自己放到制度那一边。"
        }
        if classmate.profile.anxiety > 68 {
            return "\(name)不是一直盯着你，而是每次你动一下，TA 的肩膀都会紧一下。上一晚的怀疑变成了 TA 自己的焦虑。"
        }
        if classmate.profile.empathy > 58 {
            return "\(name)在观察你，但没有立刻举报。TA 可能还想理解你，只是不知道理解和纵容之间该怎么分。"
        }
        return "\(name)今天很早就注意到你的桌面。TA 没有立刻举报，只是把作业本往讲台方向挪了一点。上一晚的怀疑还在。"
    }

    private func memoryTrustCandidate() -> Classmate? {
        guard !hasTriggeredMemoryTrust, currentTurn >= 3, currentPeriod.isBreak == false else {
            return nil
        }
        let candidates = classmates
            .filter { classmate in
                classmate.hasSharedTruth
                    && classmate.relationship > 54
                    && classmate.suspicionOfPlayer < 30
                    && classmate.state != .crying
            }
            .sorted { lhs, rhs in
                lhs.relationship + lhs.profile.empathy * 0.3 > rhs.relationship + rhs.profile.empathy * 0.3
            }

        guard let candidate = candidates.first else { return nil }
        let chance = min(0.48, 0.14 + candidate.relationship / 420 + player.stress / 700)
        return Double.random(in: 0...1) < chance ? candidate : nil
    }

    private func memorySuspicionCandidate() -> Classmate? {
        guard !hasTriggeredMemorySuspicion, currentTurn >= 3, currentPeriod.isBreak == false else {
            return nil
        }
        guard player.exposure > 24 || player.maskCost > 42 || cameraPose == .desk else {
            return nil
        }

        let candidates = classmates
            .filter { classmate in
                classmate.suspicionOfPlayer > 18
                    && classmate.relationship < 62
                    && classmate.state != .crying
            }
            .sorted { lhs, rhs in
                lhs.suspicionOfPlayer + lhs.profile.orderliness * 0.25 > rhs.suspicionOfPlayer + rhs.profile.orderliness * 0.25
            }

        guard let candidate = candidates.first else { return nil }
        let chance = min(0.44, 0.12 + candidate.suspicionOfPlayer / 130 + player.exposure / 520)
        return Double.random(in: 0...1) < chance ? candidate : nil
    }

    private func classmateHelpRequestCandidate() -> Classmate? {
        guard !hasTriggeredClassmateHelpRequest, currentTurn >= 4, currentPeriod.isBreak == false else {
            return nil
        }
        guard player.support >= 34 || settings.allowsWhispering else {
            return nil
        }

        let candidates = classmates
            .filter { classmate in
                classmate.stress > 66
                    && classmate.state != .crying
                    && classmate.profile.empathy > 44
                    && classmate.relationship > 40
                    && classmate.profile.orderliness < 82
            }
            .sorted { lhs, rhs in
                let lhsScore = lhs.stress + lhs.relationship * 0.35 + lhs.profile.empathy * 0.25 - lhs.profile.maskStrength * 0.18
                let rhsScore = rhs.stress + rhs.relationship * 0.35 + rhs.profile.empathy * 0.25 - rhs.profile.maskStrength * 0.18
                return lhsScore > rhsScore
            }

        guard let candidate = candidates.first else { return nil }
        let chance = min(0.38, 0.08 + candidate.stress / 420 + player.support / 620 + (settings.allowsWhispering ? 0.06 : 0))
        return Double.random(in: 0...1) < chance ? candidate : nil
    }

    private func classmateReportCandidate() -> Classmate? {
        guard !hasTriggeredClassmateReport, currentTurn >= 5, currentPeriod.isBreak == false else {
            return nil
        }
        guard player.exposure > 46 || player.maskCost > 58 else {
            return nil
        }

        let candidates = classmates
            .filter { classmate in
                classmate.profile.orderliness > 64
                    && classmate.relationship < 66
                    && classmate.state != .crying
                    && classmate.profile.empathy < 76
            }
            .sorted { lhs, rhs in
                let lhsScore = lhs.profile.orderliness + lhs.stress * 0.45 + lhs.suspicionOfPlayer * 0.7 - lhs.relationship * 0.35
                let rhsScore = rhs.profile.orderliness + rhs.stress * 0.45 + rhs.suspicionOfPlayer * 0.7 - rhs.relationship * 0.35
                return lhsScore > rhsScore
            }

        guard let candidate = candidates.first else { return nil }
        let chance = min(0.34, 0.06 + player.exposure / 360 + teacher.institutionalPressure / 520 + candidate.profile.orderliness / 1_000)
        return Double.random(in: 0...1) < chance ? candidate : nil
    }

    private func improveDeskmates(delta: Double, stressRelief: Double) {
        for index in classmates.indices where classmates[index].seat.row == 2 && (classmates[index].seat.column == 0 || classmates[index].seat.column == 2) {
            classmates[index].relationship = (classmates[index].relationship + delta).clamped(to: 0...100)
            classmates[index].stress = max(0, classmates[index].stress - stressRelief)
            classmates[index].hasSharedTruth = true
        }
    }

    var classroomNoise: Double {
        classmates.reduce(0) { partial, classmate in
            partial + (classmate.state == .usingPhone ? 0.08 : 0)
                + (classmate.state == .anxious ? 0.06 : 0)
                + (classmate.state == .crying ? 0.18 : 0)
        }.clamped(to: 0...1)
    }

    var highestRiskClassmate: Classmate? {
        classmates.max { lhs, rhs in lhs.stress < rhs.stress }
    }

    func teacherPerspective() -> String {
        let suspicious = classmates.filter { $0.state == .usingPhone || $0.state == .sleeping || $0.state == .crying }.count
        let riskName = highestRiskClassmate?.name ?? "某个学生"
        let riskReason = highestRiskClassmate?.riskReason ?? "原因不明"
        let mood = teacher.fatigue > 70 ? "极度疲惫" : (teacher.fatigue > 45 ? "有些疲惫" : "还能维持")
        let place = teacher.positionIndex == 8 ? "后门" : "讲台/过道"
        return "教师视角：你在\(place)，\(mood)，KPI压力 \(Int(teacher.kpiPressure))，同理心 \(Int(teacher.empathy))。你看见 \(suspicious) 个学生不太对劲，最担心的是\(riskName)：\(riskReason)。你也无法同时照顾所有人。"
    }

    private func appendEvent(title: String, detail: String) {
        eventLog.insert(EventLogEntry(turn: currentTurn, title: title, detail: detail), at: 0)
        if eventLog.count > 6 {
            eventLog.removeLast()
        }
    }

    private func presentEvent(kind: ActiveEventKind, title: String, body: String, choices: [EventChoice]) {
        gameState = .event(ActiveEvent(kind: kind, title: title, body: body, choices: choices))
    }

    func resolveEventChoice(_ choice: EventChoice) {
        guard case .event(let event) = gameState else { return }

        switch choice.id {
        case "accept_warning":
            player.stress = max(0, player.stress - 8)
            player.maskCost += 6
            player.exposure = max(0, player.exposure - 14)
            message = "你收起手机。表面恢复正常，但“好学生”的壳又重了一点。"
        case "explain_tired":
            player.maskCost = max(0, player.maskCost - 12)
            player.support += 5
            teacher.empathy += 4
            teacher.studentsHelped += 1
            message = "你小声说自己真的有点撑不住。老师沉默了半秒，选择把声音压低。"
        case "stay_silent":
            player.stress += 6
            player.exposure = max(0, player.exposure - 8)
            message = "你点头，没有解释。风险过去了，身体还停在刚才。"
        case "take_break":
            player.psychicEnergy += 18
            recoverAttention(18)
            player.homework = max(0, player.homework - 4)
            player.stress = max(0, player.stress - 15)
            player.bladder = max(0, player.bladder - 14)
            message = "你去洗了把脸。进度慢了一点，但你重新感觉到自己还在呼吸。"
        case "thank_teacher":
            player.support += 8
            player.maskCost = max(0, player.maskCost - 6)
            teacher.empathy += 3
            message = "你低声说了谢谢。这个词很轻，但让权力关系松动了一点。"
        case "refuse_care":
            player.maskCost += 10
            player.stress += 6
            message = "你说没事。老师走开后，你意识到自己又把真实感受压回去了。"
        case "breathe_now":
            player.psychicEnergy += 16
            recoverAttention(22)
            player.stress = max(0, player.stress - 18)
            message = "你跟着自己的呼吸数了四拍。问题没有消失，但你回到身体里。"
        case "ask_deskmate":
            player.support += 16
            player.maskCost = max(0, player.maskCost - 10)
            player.exposure += 5
            player.helpedClassmate = true
            improveDeskmates(delta: 14, stressRelief: 8)
            message = "你向同桌求助。被看见很危险，也很有用。"
        case "push_through":
            player.homework += 8
            player.psychicEnergy -= 15
            player.stress += 18
            player.maskCost += 8
            message = "你继续硬撑。作业多了一点，身体的报警声也更响了。"
        case "comfort_classmate":
            applyClassmateSupport(from: event, relationshipDelta: 24, stressRelief: 30)
            player.support += 18
            player.exposure += 14
            player.helpedClassmate = true
            message = "你低声问：要不要出去一下？同桌没有回答，但肩膀慢慢停住了。"
        case "pass_tissue":
            applyClassmateSupport(from: event, relationshipDelta: 14, stressRelief: 18)
            player.support += 10
            player.exposure += 6
            player.helpedClassmate = true
            addAudioCue(.paper, direction: "左侧近处", intensity: 0.48, note: "纸巾划过桌面，声音很小。")
            message = "你递过去一张纸巾，没有说话。沉默有时也是支持。"
        case "tell_teacher":
            applyClassmateSupport(from: event, relationshipDelta: -12, stressRelief: 24)
            teacher.studentsHelped += 1
            teacher.empathy += 2
            player.exposure += 8
            message = "你告诉了老师。同桌得到了帮助，但你们之间的信任变复杂了。"
        case "pretend_ignore":
            applyClassmateSupport(from: event, relationshipDelta: -18, stressRelief: -4)
            player.maskCost += 10
            player.support = max(0, player.support - 10)
            message = "你假装没看见。教室继续安静，但这种安静开始变得刺耳。"
        case "accept_support":
            player.psychicEnergy += 18
            player.support += 12
            player.maskCost = max(0, player.maskCost - 12)
            message = "你接受了纸条。支持网络不是解决一切，但它让崩溃不再只属于你一个人。"
        case "smile_only":
            player.psychicEnergy += 7
            player.support += 4
            message = "你只笑了一下。同桌明白了一点，但距离仍然在。"
        case "reject_support":
            player.maskCost += 8
            player.support = max(0, player.support - 12)
            message = "你把纸条推回去。面具保住了，连接断了一截。"
        case "look_around":
            spendAttention(for: .middle, multiplier: 1.2)
            player.exposure += 4
            message = "你趁黑暗观察四周。几个屏幕亮起，也有人迅速低下头。"
        case "rest_eyes":
            recoverAttention(22)
            player.psychicEnergy += 6
            message = "你闭上眼睛。黑暗给了你一个短暂合法的休息理由。"
        case "check_phone_dark":
            player.psychicEnergy += 8
            player.exposure += 16
            player.maskCost += 8
            addAudioCue(.phone, direction: "桌面偏右", intensity: 0.72, note: "黑暗里的手机声更明显。")
            message = "你借着停电看了一眼手机。那一秒很自由，也很危险。"
        case "go_washroom":
            player.posture = .seated
            player.psychicEnergy += 20
            recoverAttention(18)
            player.homework = max(0, player.homework - 5)
            player.exposure = max(0, player.exposure - 10)
            player.stress = max(0, player.stress - 16)
            player.bladder = max(0, player.bladder - 78)
            addAudioCue(.chair, direction: "桌边到后门", intensity: 0.52, note: "离开座位会制造声音，也给身体一个合法出口。")
            message = "你被允许离开几分钟。走廊的空气不自由，但身体终于不用继续忍着。"
        case "stretch_only":
            player.posture = .standing
            recoverAttention(14)
            player.stress = max(0, player.stress - 4)
            player.bladder = max(0, player.bladder - 4)
            player.exposure += 10
            message = "你只是站起来伸展了一下。身体舒展开，视线也暴露出来。"
        case "sit_back_down":
            player.posture = .seated
            player.exposure = max(0, player.exposure - 12)
            player.stress += 4
            player.bladder += 4
            message = "你又坐下了。没有人说什么，但你知道自己刚才差点离开。"
        case "loneliness_breathe":
            player.psychicEnergy += 10
            recoverAttention(14)
            player.stress = max(0, player.stress - 12)
            player.maskCost = max(0, player.maskCost - 4)
            addMonologue("孤独没有立刻消失，但我先把自己从报警里拉回来。", intensity: 0.36)
            message = "你没有强迫自己立刻变好，只是把呼吸放慢。孤独感被承认后，压力松开了一点。"
        case "loneliness_note":
            player.support += 6
            player.maskCost = max(0, player.maskCost - 6)
            player.exposure += 3
            addMonologue("这张纸不会递出去，但至少有一个地方知道我刚才很难受。", intensity: 0.44)
            message = "你在草稿纸角落写下一句不会递出的真话。它没有改变教室，却让你不再完全吞下它。"
        case "loneliness_mask":
            player.maskCost += 8
            player.stress += 8
            player.exposure = max(0, player.exposure - 5)
            addMonologue("我又把表情摆回去了，可身体知道这不是没事。", intensity: 0.78)
            message = "你把表情收回普通的样子。外面看起来安全了，里面却更重了一点。"
        case "read_notification":
            player.psychicEnergy += 9
            player.support += 4
            player.maskCost += 9
            player.exposure += teacher.isNearPlayer ? 24 : 12
            player.stress += teacher.isNearPlayer ? 9 : 3
            addMonologue("只是几秒钟，我就想起自己不只属于这张课桌。", intensity: 0.58)
            message = "你快速看了一眼消息。连接感回来一点，风险也在同一秒靠近。"
        case "ignore_notification":
            player.exposure = max(0, player.exposure - 8)
            player.maskCost += 5
            player.stress += 4
            addMonologue("我把手机扣住了，也把想被找见的那部分扣住了。", intensity: 0.62)
            message = "你把手机扣住。教室表面没有变化，但你知道自己刚刚放弃了一次连接。"
        case "ask_mate_cover":
            player.support += 10
            player.exposure += settings.allowsWhispering ? 3 : 9
            player.maskCost = max(0, player.maskCost - 4)
            improveDeskmates(delta: 12, stressRelief: 4)
            addMonologue("我把风险交给了另一个人一点点，也因此没那么孤单。", intensity: 0.44)
            message = "同桌把练习册往你这边挪了一点。掩护不是解决问题，但它让风险不再只由你一个人承担。"
        case "sit_straight_broadcast":
            player.exposure = max(0, player.exposure - 10)
            player.maskCost += 8
            player.stress += 5
            teacher.kpiPressure = max(0, teacher.kpiPressure - 3)
            addMonologue("广播一响，我的背就先替我做了选择。", intensity: 0.55)
            message = "你坐直，笔尖重新落回纸面。秩序恢复了，身体却更僵。"
        case "observe_broadcast":
            spendAttention(for: .middle, multiplier: 1.1)
            player.exposure += 5
            teacher.fatigue += 3
            message = "你观察到几个人同时低头，老师也看了一眼门口。广播改变了整间教室的节奏。"
        case "breathe_broadcast":
            recoverAttention(10)
            player.stress = max(0, player.stress - 9)
            player.exposure = max(0, player.exposure - 3)
            addMonologue("制度的声音还在，但我的呼吸可以先慢一点。", intensity: 0.34)
            message = "你低头呼吸，让广播从身体里穿过去。它仍然存在，但没有完全占据你。"
        case "listen_knock":
            spendAttention(for: .rightPeripheral, multiplier: 0.7)
            player.stress += 4
            teacher.empathy += 1
            addMonologue("我没有回头，只能靠声音猜门口是谁。", intensity: 0.5)
            message = "你没有回头，只听见老师的椅子轻轻响了一下。信息不完整，身体先紧了起来。"
        case "turn_to_door":
            spendAttention(for: .rightPeripheral, multiplier: 1.4)
            player.exposure += 12
            player.stress += 3
            teacher.positionIndex = 6
            addMonologue("我想确认危险在哪里，哪怕这个动作本身也会变成危险。", intensity: 0.6)
            message = "你回头看向后门，只看到门外一个影子很快离开。确定感回来一点，暴露也上来了。"
        case "ignore_knock":
            player.maskCost += 5
            player.stress += 5
            player.exposure = max(0, player.exposure - 4)
            addMonologue("我继续写题，但那两下声音还停在背后。", intensity: 0.56)
            message = "你继续写题，像什么都没听见。不确定感没有消失，只是被压进了笔尖声里。"
        case "quiet_help_classmate":
            applyClassmateSupport(from: event, relationshipDelta: 18, stressRelief: 22)
            player.support += 12
            player.exposure += settings.allowsWhispering ? 4 : 10
            player.psychicEnergy -= 5
            player.helpedClassmate = true
            addMonologue("我没有解决他的全部问题，只是让他知道这句话被接住了。", intensity: 0.42)
            message = "你低声回应了一句。求助没有变成事故，而是变成了一小段连接。"
        case "share_breath_classmate":
            applyClassmateSupport(from: event, relationshipDelta: 12, stressRelief: 18)
            player.support += 8
            player.stress = max(0, player.stress - 7)
            recoverAttention(8)
            player.homework = max(0, player.homework - 3)
            player.helpedClassmate = true
            addAudioCue(.heartbeat, direction: "左侧近处", intensity: 0.36, note: "两个人一起把呼吸放慢，心跳不再只属于一个人。")
            message = "你没有说大道理，只把呼吸节奏放慢给他看。进度慢了一点，但压力也慢了下来。"
        case "ignore_help_classmate":
            applyClassmateSupport(from: event, relationshipDelta: -16, stressRelief: -8)
            player.maskCost += 8
            player.support = max(0, player.support - 8)
            addMonologue("我看见了那行字，也决定假装没看见。", intensity: 0.7)
            message = "你把视线移回作业。安全感保住了一点，教室里的孤独也重了一点。"
        case "admit_to_reporter":
            applyClassmateSupport(from: event, relationshipDelta: 10, stressRelief: 8)
            player.maskCost = max(0, player.maskCost - 8)
            player.exposure = max(0, player.exposure - 10)
            player.support += 5
            addMonologue("我说我真的有点累。承认这句话，比收起动作更难。", intensity: 0.5)
            message = "你小声承认自己撑得很紧。对方没有立刻看向老师，守序和理解之间出现了一点缝隙。"
        case "pressure_reporter":
            applyClassmateSupport(from: event, relationshipDelta: -22, stressRelief: -6)
            player.exposure = max(0, player.exposure - 6)
            player.stress += 9
            player.support = max(0, player.support - 7)
            addMonologue("我把他的犹豫压了回去，也把关系压坏了一点。", intensity: 0.62)
            message = "你让他别说。风险暂时退下去，但旁边的位置变得更远。"
        case "stop_and_reset":
            player.exposure = max(0, player.exposure - 18)
            player.maskCost += 7
            player.stress += 3
            applyClassmateSupport(from: event, relationshipDelta: -4, stressRelief: 4)
            message = "你立刻收手，把自己摆回普通学生的样子。表面安全了，面具又重了一层。"
        case "accept_memory_trust":
            applyClassmateSupport(from: event, relationshipDelta: 12, stressRelief: 10)
            player.support += 12
            player.maskCost = max(0, player.maskCost - 6)
            addMonologue("原来有些支持不是从零开始的。", intensity: 0.38)
            message = "你收下纸条。上一晚留下的信任没有解决压力，但让求助成本低了一点。"
        case "return_memory_trust":
            applyClassmateSupport(from: event, relationshipDelta: 18, stressRelief: 12)
            player.support += 10
            player.exposure += settings.allowsWhispering ? 2 : 6
            player.helpedClassmate = true
            addAudioCue(.paper, direction: "左侧近处", intensity: 0.42, note: "两张纸条之间形成了跨过一晚的支持网络。")
            message = "你写了一句谢谢推回去。关系不是剧情奖励，而是下一次更容易开口的条件。"
        case "avoid_memory_trust":
            applyClassmateSupport(from: event, relationshipDelta: -14, stressRelief: -4)
            player.maskCost += 9
            player.support = max(0, player.support - 8)
            addMonologue("我知道他记得我，但我今天不想被任何人看见。", intensity: 0.64)
            message = "你假装没看见。信任没有立刻消失，但它变得更小心。"
        case "repair_memory_suspicion":
            applyClassmateSupport(from: event, relationshipDelta: 14, stressRelief: 6)
            player.exposure = max(0, player.exposure - 8)
            player.maskCost = max(0, player.maskCost - 5)
            player.support += 4
            addMonologue("解释不是辩解，只是把一个动作背后的疲惫说出来一点。", intensity: 0.48)
            message = "你低声解释自己昨晚只是太累。对方没有完全相信，但怀疑开始松动。"
        case "hide_from_memory_suspicion":
            player.exposure = max(0, player.exposure - 16)
            player.maskCost += 10
            player.stress += 5
            applyClassmateSupport(from: event, relationshipDelta: -2, stressRelief: 2)
            message = "你把所有小动作都收起来。风险降了，身体却更像被固定在座位上。"
        case "challenge_memory_suspicion":
            applyClassmateSupport(from: event, relationshipDelta: -20, stressRelief: -8)
            player.exposure += 8
            player.stress += 8
            player.support = max(0, player.support - 10)
            addMonologue("我不想再被他看着，可我也知道这句话会留下新的记忆。", intensity: 0.68)
            message = "你回看过去。对方移开视线，但这段关系更难回到普通。"
        default:
            message = "你让这个瞬间过去了。"
        }

        clampPlayer()
        clampTeacher()
        updateClassmates(after: nil)
        recordSnapshot(actionLabel: choice.title)
        continueAfterEvent()
    }

    private func applyClassmateSupport(from event: ActiveEvent, relationshipDelta: Double, stressRelief: Double) {
        guard let classmateID = classmateID(from: event.kind),
              let index = classmates.firstIndex(where: { $0.id == classmateID }) else {
            return
        }
        classmates[index].relationship = (classmates[index].relationship + relationshipDelta).clamped(to: 0...100)
        classmates[index].stress = (classmates[index].stress - stressRelief).clamped(to: 0...100)
        classmates[index].hasSharedTruth = relationshipDelta > 0
        classmates[index].suspicionOfPlayer = relationshipDelta > 0
            ? max(0, classmates[index].suspicionOfPlayer - 12)
            : (classmates[index].suspicionOfPlayer + 14).clamped(to: 0...100)
        if classmates[index].stress < 76 {
            classmates[index].state = relationshipDelta > 0 ? .offeringHelp : .studying
        }
    }

    private func classmateID(from kind: ActiveEventKind) -> Int? {
        switch kind {
        case .classmateCrying(let classmateID),
             .classmateHelpRequest(let classmateID),
             .classmateReport(let classmateID),
             .memoryTrust(let classmateID),
             .memorySuspicion(let classmateID):
            return classmateID
        default:
            return nil
        }
    }

    private func addAudioCue(_ kind: AudioCueKind, direction: String, intensity: Double, note: String) {
        let cue = AudioCue(turn: currentTurn, kind: kind, direction: direction, intensity: intensity.clamped(to: 0...1), note: note)
        audioCues.insert(cue, at: 0)
        if audioCues.count > 5 {
            audioCues.removeLast()
        }
        audio.updateListener(position: listenerPosition, orientation: listenerOrientation)
        audio.playCue(kind: kind, intensity: cue.intensity, position: spatialPosition(for: direction))
    }

    private func addMonologue(_ text: String, intensity: Double) {
        monologues.insert(InnerMonologue(turn: currentTurn, text: text, intensity: intensity.clamped(to: 0...1)), at: 0)
        if monologues.count > 5 {
            monologues.removeLast()
        }
    }

    private func panValue(for direction: String) -> Double {
        if direction.contains("左") { return -0.8 }
        if direction.contains("右") { return 0.8 }
        if direction.contains("前") || direction.contains("讲台") { return 0.0 }
        if direction.contains("桌面") { return 0.2 }
        return 0
    }

    private var listenerPosition: SCNVector3 {
        if viewMode == .teacher {
            let path: [SCNVector3] = [
                SCNVector3(-2.7, 1.48, -4.07), SCNVector3(2.6, 1.48, -3.02),
                SCNVector3(2.6, 1.48, -1.02), SCNVector3(1.2, 1.48, 0.63),
                SCNVector3(0.2, 1.48, 1.73), SCNVector3(-2.2, 1.48, 0.58),
                SCNVector3(-2.8, 1.48, -1.22), SCNVector3(0, 1.48, -4.17),
                SCNVector3(-3.45, 1.48, 4.43)
            ]
            return path[min(teacher.positionIndex, path.count - 1)]
        }
        return SCNVector3(-0.6, player.posture == .standing ? 1.58 : 1.18, 1.5)
    }

    private var listenerOrientation: SCNVector3 {
        viewMode == .teacher ? SCNVector3(-0.12, 0, 0) : cameraPose.angles
    }

    private func spatialPosition(for direction: String) -> SCNVector3 {
        let base = listenerPosition
        if direction.contains("颅内") {
            return base
        }
        if direction.contains("头顶") {
            return SCNVector3(base.x, base.y + 1.2, base.z)
        }
        if direction.contains("桌面") || direction.contains("桌边") {
            return SCNVector3(base.x + 0.25, 0.78, base.z - 0.12)
        }
        if direction.contains("讲台") || direction.contains("前方") {
            return SCNVector3(0, 1.2, -4.4)
        }
        if direction.contains("过道") {
            return SCNVector3(1.6, 1.0, base.z - 1.2)
        }
        if direction.contains("窗外") {
            return SCNVector3(-4.1, 1.45, 1.2)
        }
        if direction.contains("后") {
            return SCNVector3(-3.95, 1.2, 4.25)
        }
        if direction.contains("左") {
            return SCNVector3(base.x - (direction.contains("极近") ? 0.35 : 0.95), 1.0, base.z - 0.25)
        }
        if direction.contains("右") {
            return SCNVector3(base.x + (direction.contains("极近") ? 0.35 : 0.95), 1.0, base.z - 0.25)
        }
        if direction.contains("四周") {
            return SCNVector3(0, 1.2, 0)
        }
        return SCNVector3(base.x, base.y, base.z - 0.8)
    }

    func selectReplay(offset: Int) {
        guard !replay.isEmpty else { return }
        selectedReplayIndex = (selectedReplayIndex + offset).clamped(to: 0...(replay.count - 1))
    }

    var selectedReplay: TurnSnapshot? {
        guard replay.indices.contains(selectedReplayIndex) else { return nil }
        return replay[selectedReplayIndex]
    }

    private func recordSnapshot(actionLabel: String) {
        let visible = visibleSceneDescription(actionLabel: actionLabel)
        let truth = innerTruthDescription(actionLabel: actionLabel)
        let teacherView = teacherInterpretationDescription()
        let metrics = "能量 \(Int(player.psychicEnergy)) · 压力 \(Int(player.stress)) · 面具 \(Int(player.maskCost)) · 支持 \(Int(player.support)) · 暴露 \(Int(player.exposure)) · 饥饿 \(Int(player.hunger)) · 如厕 \(Int(player.bladder))"
        replay.append(TurnSnapshot(
            turn: currentTurn,
            actionLabel: actionLabel,
            visibleScene: visible,
            innerTruth: truth,
            teacherInterpretation: teacherView,
            metrics: metrics,
            energy: player.psychicEnergy,
            stress: player.stress,
            maskCost: player.maskCost,
            support: player.support,
            exposure: player.exposure,
            bodyNeed: max(player.hunger, player.bladder)
        ))
        if replay.count > maxTurns + 4 {
            replay.removeFirst()
        }
    }

    private func visibleSceneDescription(actionLabel: String) -> String {
        let risky = highestRiskClassmate
        let riskText = risky.map { "\($0.name)看起来\($0.state.rawValue)，原因可能是\($0.riskReason)" } ?? "大部分学生低头写题"
        return "表面：第 \(currentTurn) 回合，\(actionLabel)。\(riskText)，老师在\(teacher.isNearPlayer ? "过道附近" : "讲台或远处")，教室仍然安静。"
    }

    private func innerTruthDescription(actionLabel: String) -> String {
        if player.breakdownRisk > 55 {
            return "真相：你并不是故意对抗晚自习，而是心理能量和面具成本已经接近失控。\(actionLabel)只是你寻找出口的一种方式。"
        }
        if let crying = classmates.first(where: { $0.state == .crying }) {
            return "真相：\(crying.name)不是不认真，可能正在经历一次焦虑峰值。没人出声不代表没人需要帮助。"
        }
        if player.helpedClassmate {
            return "真相：一次低声询问改变了这一晚的支持网络。完成作业之外，你也完成了一次连接。"
        }
        return "真相：你在维持好学生形象、完成任务和保护自己之间不断切换。没有一个选择是零成本的。"
    }

    private func teacherInterpretationDescription() -> String {
        let suspicious = classmates.filter { $0.state == .usingPhone || $0.state == .sleeping || $0.state == .crying }.count
        if teacher.institutionalPressure > 65 {
            return "教师误读：在高 KPI 和疲惫下，\(suspicious) 个异常动作很容易被解释成纪律问题，而不是求助信号。"
        }
        return "教师理解：如果停下来多看几秒，异常动作背后可能是疲惫、家庭压力或同伴支持，而不只是违规。"
    }

    private func raiseClassmateStress(id: Int, delta: Double) {
        guard let index = classmates.firstIndex(where: { $0.id == id }) else { return }
        classmates[index].stress = (classmates[index].stress + delta).clamped(to: 0...100)
    }

    private func lowerClassmateStress(id: Int, delta: Double) {
        guard let index = classmates.firstIndex(where: { $0.id == id }) else { return }
        classmates[index].stress = max(0, classmates[index].stress - delta)
        classmates[index].relationship = (classmates[index].relationship + delta / 3).clamped(to: 0...100)
    }

    private func lowerClassmateStress(delta: Double) {
        for index in classmates.indices {
            classmates[index].stress = max(0, classmates[index].stress - delta)
        }
    }

    private func commitClassmateMemory() {
        var nextMemory: [Int: ClassmateMemory] = [:]
        for classmate in classmates {
            let relationshipDelta = classmate.relationship - 35
            let stressEcho = (classmate.stress - 50) * 0.28
            let suspicionEcho = classmate.suspicionOfPlayer * 0.45
            let shouldRemember = abs(relationshipDelta) > 8
                || abs(stressEcho) > 5
                || suspicionEcho > 10
                || classmate.hasSharedTruth
                || classmate.state == .crying

            guard shouldRemember else { continue }
            nextMemory[classmate.id] = ClassmateMemory(
                relationshipCarry: relationshipDelta.clamped(to: -22...28),
                stressEcho: stressEcho.clamped(to: -12...18),
                suspicionCarry: suspicionEcho.clamped(to: 0...34),
                sharedTruth: classmate.hasSharedTruth,
                helpedLastRun: classmate.relationship > 58 && classmate.stress < 72
            )
        }
        classmateMemory = nextMemory
        saveClassmateMemory()
    }

    private func loadClassmateMemory() -> [Int: ClassmateMemory] {
        guard let data = UserDefaults.standard.data(forKey: memoryStoreKey) else {
            return [:]
        }
        return (try? JSONDecoder().decode([Int: ClassmateMemory].self, from: data)) ?? [:]
    }

    private func saveClassmateMemory() {
        if classmateMemory.isEmpty {
            UserDefaults.standard.removeObject(forKey: memoryStoreKey)
            return
        }
        guard let data = try? JSONEncoder().encode(classmateMemory) else {
            return
        }
        UserDefaults.standard.set(data, forKey: memoryStoreKey)
    }

    private func clampPlayer() {
        player.psychicEnergy = player.psychicEnergy.clamped(to: 0...100)
        player.maskCost = player.maskCost.clamped(to: 0...100)
        player.support = player.support.clamped(to: 0...100)
        player.stress = player.stress.clamped(to: 0...100)
        player.exposure = player.exposure.clamped(to: 0...100)
        player.homework = player.homework.clamped(to: 0...100)
        player.hunger = player.hunger.clamped(to: 0...100)
        player.bladder = player.bladder.clamped(to: 0...100)
        player.visualAttention = player.visualAttention.clamped(to: 0...100)
        player.focusQuality = (player.visualAttention / 100).clamped(to: 0.18...1)
    }

    private func spendAttention(for zone: VisionZone, multiplier: Double) {
        let amount = zone.attentionCost * multiplier
        guard amount > 0 else {
            updateFocusQuality()
            return
        }
        player.visualAttention = max(0, player.visualAttention - amount)
        updateFocusQuality()
        if player.visualAttention < 18 {
            player.stress = min(100, player.stress + 5)
            message += " 你的视野开始发散，中心也不再稳定。"
            addAudioCue(.heartbeat, direction: "颅内", intensity: 0.82, note: "注意力耗尽时，视觉退后，身体声音变大。")
        }
    }

    private func recoverAttention(_ amount: Double) {
        player.visualAttention = min(100, player.visualAttention + amount)
        updateFocusQuality()
    }

    private func updateFocusQuality() {
        player.focusQuality = (player.visualAttention / 100).clamped(to: 0.18...1)
    }

    private func clampTeacher() {
        teacher.kpiPressure = teacher.kpiPressure.clamped(to: 0...100)
        teacher.fatigue = teacher.fatigue.clamped(to: 0...100)
        teacher.empathy = teacher.empathy.clamped(to: 0...100)
    }

    private func makeClassmates() -> [Classmate] {
        let names = ["林澈", "周雨", "陈默", "许安", "赵晴", "何屿", "唐宁", "沈星", "顾言", "叶舟", "韩夏", "白辰", "陆遥", "秦一", "苏禾", "姜南", "程川", "宋也", "黎昕"]
        var result: [Classmate] = []
        var id = 0
        for row in 0..<5 {
            for column in 0..<4 {
                if row == 2 && column == 1 { continue }
                let name = names[id % names.count]
                let isDeskmate = row == 2 && (column == 0 || column == 2)
                let profile = classmateProfile(seed: id)
                let memory = classmateMemory[id]
                let baseRelationship = isDeskmate ? 42 : Double.random(in: 10...45)
                let baseStress = isDeskmate ? Double.random(in: 54...86) + profile.anxiety / 12 : Double.random(in: 20...85) + profile.anxiety / 18
                result.append(Classmate(
                    id: id,
                    name: name,
                    seat: (row, column),
                    profile: profile,
                    support: Double.random(in: 16...70),
                    stress: (baseStress + (memory?.stressEcho ?? 0)).clamped(to: 8...100),
                    state: memory?.helpedLastRun == true ? .offeringHelp : .studying,
                    relationship: (baseRelationship + (memory?.relationshipCarry ?? 0)).clamped(to: 0...100),
                    hasSharedTruth: memory?.sharedTruth ?? false,
                    suspicionOfPlayer: memory?.suspicionCarry ?? 0
                ))
                id += 1
            }
        }
        return result
    }

    private func classmateProfile(seed: Int) -> ClassmateProfile {
        func value(_ offset: Int, base: Double, spread: Double) -> Double {
            let raw = Double((seed * 37 + offset * 53) % 101) / 100
            return (base + (raw - 0.5) * spread).clamped(to: 5...95)
        }
        return ClassmateProfile(
            cooperation: value(1, base: 54, spread: 70),
            orderliness: value(2, base: 56, spread: 76),
            rebelliousness: value(3, base: 44, spread: 72),
            empathy: value(4, base: 52, spread: 78),
            anxiety: value(5, base: 42, spread: 82),
            maskStrength: value(6, base: 56, spread: 74)
        )
    }
}

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
