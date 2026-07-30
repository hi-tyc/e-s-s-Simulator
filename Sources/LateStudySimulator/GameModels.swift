import Foundation
import CoreGraphics
import SceneKit

enum GameState: Equatable {
    case menu
    case playing
    case event(ActiveEvent)
    case ending(Ending)
}

enum NarrativePauseReason: String, Hashable {
    case manual
    case settings
    case appInactive
    case microGame
}

enum NarrativeKeyboardCommand: Hashable {
    case previousTarget
    case nextTarget
    case confirm
    case cancel
}

struct NarrativeKeyboardTarget: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let requiresMovement: Bool
}

enum StoryChapter: String {
    case silentClassroom = "关卡一 · 静音的教室"

    var objective: String {
        switch self {
        case .silentClassroom:
            return "在信息不完整的晚自习里，听见异常、确认线索，并跟上独自离开的林澈。"
        }
    }
}

enum ChapterOneStep: Int, CaseIterable, Equatable, Hashable, Codable {
    case observeLinChe
    case locateHiddenSound
    case regulateSelf
    case approachLinChe
    case inspectNote
    case followLinChe
    case completed

    var objective: String {
        switch self {
        case .observeLinChe: return "看看林澈今晚在做什么"
        case .locateHiddenSound: return "听清右侧那道声音"
        case .regulateSelf: return "先让自己缓一下"
        case .approachLinChe: return "下课前，问林澈一句"
        case .inspectNote: return "捡起掉到桌边的纸条"
        case .followLinChe: return "别让林澈一个人离开"
        case .completed: return "第一章完成"
        }
    }

    var guidance: String {
        switch self {
        case .observeLinChe: return "看向左侧，确认那阵停下来的翻书声。"
        case .locateHiddenSound: return "转向右侧，别让翻书声盖住那一下鼻息。"
        case .regulateSelf: return "不用读数值。喝口水，或者先把呼吸放慢。"
        case .approachLinChe: return "铃响前，用一句低压力的话靠近他。"
        case .inspectNote: return "低头看桌面，确认刚才滑落的纸片。"
        case .followLinChe: return "林澈已经走向门口。现在起身跟上。"
        case .completed: return "你带着匿名纸条走进了走廊。"
        }
    }
}

enum LinChePerformancePhase: String, Codable, Equatable {
    case idleStillPage
    case doorGlance
    case packingUp
    case exiting
    case exited
}

struct LinChePerformanceCue: Codable, Equatable {
    var phase: LinChePerformancePhase
    var intensity: Double
    var exitProgress: Double
    var pageStillness: Double
    var doorAttention: Double
    var packingProgress: Double
    var detail: String

    static let initial = LinChePerformanceCue(
        phase: .idleStillPage,
        intensity: 0.42,
        exitProgress: 0,
        pageStillness: 1,
        doorAttention: 0,
        packingProgress: 0,
        detail: "林澈的书停在同一页。"
    )

    var isLeaving: Bool {
        phase == .exiting || phase == .exited
    }

    static func derive(step: ChapterOneStep, noteDropCue: ChapterOneNoteDropCue?) -> LinChePerformanceCue {
        switch step {
        case .observeLinChe:
            return .initial
        case .locateHiddenSound:
            return LinChePerformanceCue(
                phase: .idleStillPage,
                intensity: 0.5,
                exitProgress: 0,
                pageStillness: 1,
                doorAttention: 0.16,
                packingProgress: 0,
                detail: "林澈仍停在同一页，只是肩膀更紧。"
            )
        case .regulateSelf:
            return LinChePerformanceCue(
                phase: .doorGlance,
                intensity: 0.62,
                exitProgress: 0,
                pageStillness: 0.86,
                doorAttention: 0.58,
                packingProgress: 0.12,
                detail: "林澈抬头看了一眼门口，又很快低下去。"
            )
        case .approachLinChe:
            return LinChePerformanceCue(
                phase: .doorGlance,
                intensity: 0.74,
                exitProgress: 0,
                pageStillness: 0.68,
                doorAttention: 0.86,
                packingProgress: 0.32,
                detail: "他把笔收回笔袋，视线避开了你。"
            )
        case .inspectNote:
            let noteIntensity = noteDropCue?.stageIntensity ?? 0.72
            return LinChePerformanceCue(
                phase: .packingUp,
                intensity: max(0.72, noteIntensity),
                exitProgress: 0.18,
                pageStillness: 0.28,
                doorAttention: 0.76,
                packingProgress: 0.78,
                detail: "铃声里，林澈把书合上，椅子向后一挪。"
            )
        case .followLinChe:
            return LinChePerformanceCue(
                phase: .exiting,
                intensity: 0.9,
                exitProgress: noteDropCue?.notePicked == true ? 0.74 : 0.56,
                pageStillness: 0.05,
                doorAttention: 0.92,
                packingProgress: 1,
                detail: "林澈已经离开座位，沿着前门方向走。"
            )
        case .completed:
            return LinChePerformanceCue(
                phase: .exited,
                intensity: 0.52,
                exitProgress: 1,
                pageStillness: 0,
                doorAttention: 0.35,
                packingProgress: 1,
                detail: "林澈的座位空了，纸条的重量留在你口袋里。"
            )
        }
    }
}

struct SpatialAudioObjective: Equatable, Identifiable {
    let step: ChapterOneStep
    let title: String
    let sourceLine: String
    let direction: String
    let targetPose: CameraPose
    let cueKind: AudioCueKind
    let cueIntensity: Double
    let focusProgress: Double
    let locateAction: String
    let confirmAction: String
    let isLocated: Bool

    var id: String { "chapter1.audio.\(step.rawValue)" }

    var progress: Double {
        isLocated ? 1 : max(0.18, focusProgress.clamped(to: 0...0.96))
    }

    var statusLine: String {
        isLocated ? "已定位，继续观察确认。" : "先用视线对准声源，不急着下结论。"
    }

    static func chapterOne(step: ChapterOneStep, isLocated: Bool, focusProgress: Double = 0) -> SpatialAudioObjective? {
        switch step {
        case .observeLinChe:
            return SpatialAudioObjective(
                step: step,
                title: "定位停住的翻书声",
                sourceLine: "左侧同桌位，翻书声停在同一页附近。",
                direction: "左侧近处",
                targetPose: .left,
                cueKind: .paper,
                cueIntensity: 0.46,
                focusProgress: focusProgress,
                locateAction: "看向左侧余光",
                confirmAction: "观察林澈的书页",
                isLocated: isLocated
            )
        case .locateHiddenSound:
            return SpatialAudioObjective(
                step: step,
                title: "定位被压低的鼻息",
                sourceLine: "右侧前排方向，鼻息被翻书声盖住。",
                direction: "右侧近处",
                targetPose: .right,
                cueKind: .crying,
                cueIntensity: 0.54,
                focusProgress: focusProgress,
                locateAction: "转向右侧声源",
                confirmAction: "观察右侧隐藏声音",
                isLocated: isLocated
            )
        case .inspectNote:
            return SpatialAudioObjective(
                step: step,
                title: "定位滑落的纸边",
                sourceLine: "桌面右侧，纸片擦过草稿本边缘。",
                direction: "桌面右侧",
                targetPose: .desk,
                cueKind: .paper,
                cueIntensity: 0.58,
                focusProgress: focusProgress,
                locateAction: "低头看桌面声源",
                confirmAction: "确认匿名纸条",
                isLocated: isLocated
            )
        case .regulateSelf, .approachLinChe, .followLinChe, .completed:
            return nil
        }
    }
}

struct DwellFocusState: Equatable {
    var activePose: CameraPose? = nil
    var dwellAccumulated: TimeInterval = 0
    var triggeredInCurrentStep: Set<CameraPose> = []

    mutating func resetForStep(keeping pose: CameraPose? = nil) {
        activePose = pose
        dwellAccumulated = 0
        triggeredInCurrentStep = []
    }

    mutating func resetForPose(_ pose: CameraPose) {
        if activePose != pose {
            activePose = pose
            dwellAccumulated = 0
        }
    }

    func progress(for pose: CameraPose) -> Double {
        guard activePose == pose,
              let threshold = DwellThreshold.threshold(for: pose),
              threshold > 0 else { return 0 }
        return (dwellAccumulated / threshold).clamped(to: 0...1)
    }
}

struct DwellThreshold {
    static func threshold(for pose: CameraPose) -> TimeInterval? {
        switch pose {
        case .left, .right:
            return 2.0
        case .desk:
            return 3.0
        case .forward:
            return 2.0
        case .board, .rear:
            return nil
        }
    }
}

struct DwellFocusFeedback: Identifiable, Equatable {
    let id = UUID()
    let pose: CameraPose
    let progress: Double
}

struct SeatedPosePressureFeedback: Identifiable, Equatable {
    enum Tone: Equatable {
        case stable
        case risk
        case body
        case connection
    }

    let id = UUID()
    let pose: CameraPose
    let title: String
    let detail: String
    let recommendation: String
    let intensity: Double
    let tone: Tone

    static func derive(
        pose: CameraPose,
        teacherNear: Bool,
        psychicEnergy: Double,
        stress: Double,
        maskCost: Double,
        visualAttention: Double
    ) -> SeatedPosePressureFeedback {
        let depletion = max(0, 100 - psychicEnergy) / 100
        let stressLoad = stress / 100
        let maskLoad = maskCost / 100
        let attentionLoss = max(0, 100 - visualAttention) / 100
        let teacherLoad = teacherNear ? 0.18 : 0

        switch pose {
        case .forward:
            let intensity = (0.16 + maskLoad * 0.28 + stressLoad * 0.12).clamped(to: 0...1)
            return SeatedPosePressureFeedback(
                pose: pose,
                title: "维持普通坐姿",
                detail: "前方视线最安全，但也在持续表演“我没事”。",
                recommendation: intensity > 0.5 ? "面具已经变重，下一步优先用呼吸或低风险连接降压。" : "保持前方可以恢复注意力，等声源更明确再行动。",
                intensity: intensity,
                tone: .stable
            )
        case .desk:
            let intensity = (0.28 + stressLoad * 0.28 + attentionLoss * 0.18 + teacherLoad).clamped(to: 0...1)
            return SeatedPosePressureFeedback(
                pose: pose,
                title: "桌面遮蔽",
                detail: teacherNear ? "低头能藏住手边动作，但老师近处时未知感会迅速放大。" : "桌面近景清楚，讲台和过道信息被切断。",
                recommendation: "停留太久会让身体报警变大，听清声源后尽快确认或收回视线。",
                intensity: intensity,
                tone: .body
            )
        case .board:
            let intensity = (0.34 + maskLoad * 0.24 + depletion * 0.16 + teacherLoad).clamped(to: 0...1)
            return SeatedPosePressureFeedback(
                pose: pose,
                title: "抬头装作认真",
                detail: "这个姿态最像好学生，也最消耗社会面具。",
                recommendation: "抬头适合确认老师位置，但不适合长时间硬撑。",
                intensity: intensity,
                tone: .risk
            )
        case .left:
            let intensity = (0.24 + stressLoad * 0.16 + teacherLoad * 0.8).clamped(to: 0...1)
            return SeatedPosePressureFeedback(
                pose: pose,
                title: "左侧连接",
                detail: "同桌的动作能给你支持，也会让你的真实状态更容易被看见。",
                recommendation: teacherNear ? "老师近处时先短看短收，不要把连接变成公开暴露。" : "可以用低声或纸条建立一点支持网络。",
                intensity: intensity,
                tone: .connection
            )
        case .right:
            let intensity = (0.28 + stressLoad * 0.18 + teacherLoad).clamped(to: 0...1)
            return SeatedPosePressureFeedback(
                pose: pose,
                title: "右侧声源确认",
                detail: "走廊和前排声音在这里叠在一起，确定感需要用暴露风险交换。",
                recommendation: "先听方向，再决定是否继续观察；脚步近时收回前方。",
                intensity: intensity,
                tone: .risk
            )
        case .rear:
            let intensity = (0.62 + stressLoad * 0.2 + attentionLoss * 0.12 + teacherLoad).clamped(to: 0...1)
            return SeatedPosePressureFeedback(
                pose: pose,
                title: "后方高暴露",
                detail: "坐着回头几乎一定会改变别人对你的判断。",
                recommendation: "只有在后门信息很关键时才回头；确认后立刻回到前方。",
                intensity: intensity,
                tone: .risk
            )
        }
    }
}

enum ChapterClueID: String, CaseIterable, Hashable, Codable {
    case linChePage
    case hiddenCrying
    case monitorOverload
    case teacherSigh
    case unsignedNote

    var title: String {
        switch self {
        case .linChePage: return "林澈的书页"
        case .hiddenCrying: return "被藏住的鼻息"
        case .monitorOverload: return "班长的停顿"
        case .teacherSigh: return "方老师的叹气"
        case .unsignedNote: return "不署名纸条"
        }
    }

    var detail: String {
        switch self {
        case .linChePage:
            return "学习委员很久没有翻页，手指反复摸着错题本折角。"
        case .hiddenCrying:
            return "右侧传来一声被翻书声盖住的鼻息，像是有人在藏住情绪。"
        case .monitorOverload:
            return "班长替别人收尾太多事，自己的练习册还空着。"
        case .teacherSigh:
            return "方老师巡视时停顿变长，叹气声比脚步声更明显。"
        case .unsignedNote:
            return "纸条上写着：心里很难受，但我不知道找谁说。"
        }
    }
}

struct ChapterClue: Identifiable, Equatable, Codable {
    let id: ChapterClueID
    let turn: Int
    let title: String
    let detail: String
}

enum ActiveEventKind: Equatable {
    case discovery
    case linCheDialogue
    case noteDrop
    case teacherConcern
    case playerBreakdown
    case classmateCrying(classmateID: Int)
    case supportOffer
    case powerOutage
    case leaveSeatRequest
    case loneliness
    case phoneNotification
    case broadcast
    case knockOnDoor
    case classmateHelpRequest(classmateID: Int)
    case classmateReport(classmateID: Int)
    case memoryTrust(classmateID: Int)
    case memorySuspicion(classmateID: Int)
}

struct ActiveEvent: Equatable {
    let kind: ActiveEventKind
    let title: String
    let body: String
    let choices: [EventChoice]
}

struct EventChoice: Equatable, Identifiable {
    let id: String
    let title: String
    let detail: String
}

enum ChapterOneLinCheTrust: String, Codable, Equatable {
    case open
    case neutral
    case closed

    var campaignTrustSeed: Int {
        switch self {
        case .open: return 3
        case .neutral: return 2
        case .closed: return 1
        }
    }
}

struct ChapterOneLinCheDialogueCue: Codable, Equatable {
    var selectedChoiceID: String
    var trust: ChapterOneLinCheTrust
    var listenScore: Int
    var responseLine: String
    var outcomeLine: String

    static func resolve(choiceID: String) -> ChapterOneLinCheDialogueCue? {
        switch choiceID {
        case "chapter1_linche_listen":
            return ChapterOneLinCheDialogueCue(
                selectedChoiceID: choiceID,
                trust: .open,
                listenScore: 2,
                responseLine: "我听见你刚才停住了。要不要出去透口气？",
                outcomeLine: "林澈没有回答得很快，但他把笔袋扣上时，手没有再躲开你的视线。"
            )
        case "chapter1_linche_wait":
            return ChapterOneLinCheDialogueCue(
                selectedChoiceID: choiceID,
                trust: .neutral,
                listenScore: 1,
                responseLine: "下课后我在走廊等你。不用现在说。",
                outcomeLine: "林澈轻轻点了一下头，像是先把这句话放进口袋。"
            )
        case "chapter1_linche_mask":
            return ChapterOneLinCheDialogueCue(
                selectedChoiceID: choiceID,
                trust: .closed,
                listenScore: 0,
                responseLine: "没事就好。",
                outcomeLine: "林澈说嗯，动作很快。那句话把门关上了一点，但没有把纸条从这一晚里拿走。"
            )
        default:
            return nil
        }
    }
}

struct ChapterOneNoteDropCue: Codable, Equatable {
    static let content = "心里很难受，但我不知道找谁说。不知道有没有人想听。"

    var triggerTurn: Int
    var chairCuePlayed: Bool
    var bellCuePlayed: Bool
    var paperVisible: Bool
    var overlayPresented: Bool
    var overlayDismissed: Bool

    var noteFound: Bool {
        paperVisible || overlayPresented || overlayDismissed
    }

    var notePicked: Bool {
        overlayDismissed
    }

    var stageIntensity: Double {
        if overlayDismissed { return 0.18 }
        if overlayPresented { return 1.0 }
        return paperVisible ? 0.82 : 0
    }
}

enum BreakdownRecoveryStep: String, CaseIterable, Identifiable, Equatable {
    case nameSignal
    case returnToBody
    case acceptSupport

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nameSignal: return "说出报警"
        case .returnToBody: return "回到身体"
        case .acceptSupport: return "接住支持"
        }
    }

    var detail: String {
        switch self {
        case .nameSignal: return "先承认：这是过载信号，不是失败。"
        case .returnToBody: return "用呼吸、触觉和水把注意力带回来。"
        case .acceptSupport: return "把一点点真实状态交给同桌或老师。"
        }
    }

    var symbol: String {
        switch self {
        case .nameSignal: return "exclamationmark.bubble.fill"
        case .returnToBody: return "lungs.fill"
        case .acceptSupport: return "person.2.fill"
        }
    }
}

struct InnerMonologue: Identifiable {
    let id = UUID()
    let turn: Int
    let text: String
    let intensity: Double
}

struct FeaturedMonologue: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let intensity: Double

    static func == (lhs: FeaturedMonologue, rhs: FeaturedMonologue) -> Bool {
        lhs.id == rhs.id
    }
}

enum ViewMode: String, CaseIterable {
    case student = "学生视角"
    case teacher = "教师视角"

    var perspectiveDescription: String {
        switch self {
        case .student: return "固定座位第一视角"
        case .teacher: return "教师移动视角"
        }
    }
}

enum PlayableRole: String, CaseIterable, Identifiable {
    case homeroomTeacher = "班主任"
    case honorStudent = "好学生"
    case regularStudent = "普通学生"
    case counselingPatrolTeacher = "心理巡查老师"

    var id: String { rawValue }

    static var selectableCases: [PlayableRole] {
        [.homeroomTeacher, .honorStudent, .regularStudent]
    }

    var isTeacher: Bool {
        switch self {
        case .homeroomTeacher, .counselingPatrolTeacher:
            return true
        case .honorStudent, .regularStudent:
            return false
        }
    }

    var icon: String {
        switch self {
        case .homeroomTeacher: return "person.text.rectangle.fill"
        case .honorStudent: return "medal.fill"
        case .regularStudent: return "person.fill"
        case .counselingPatrolTeacher: return "heart.text.square.fill"
        }
    }

    var roleType: String {
        isTeacher ? "教师线" : "学生线"
    }

    var shortDescription: String {
        switch self {
        case .homeroomTeacher:
            return "在 KPI、班级秩序和学生真实状态之间做管理选择。"
        case .honorStudent:
            return "完成度高，但面具成本和排名压力更重。"
        case .regularStudent:
            return "压力和支持更均衡，适合体验学生主线。"
        case .counselingPatrolTeacher:
            return "从心理支持角度巡查班级，重点识别求助信号。"
        }
    }

    var fixedDuty: String {
        switch self {
        case .homeroomTeacher:
            return "维持晚自习秩序，完成年级巡视与纪律反馈。"
        case .honorStudent:
            return "保持高完成度和稳定表现，尽量不暴露疲惫。"
        case .regularStudent:
            return "在学习、身体需求、关系和风险之间找到平衡。"
        case .counselingPatrolTeacher:
            return "识别高压学生，提供低声支持，减少公开羞辱。"
        }
    }
}

enum TurnPhase: String {
    case observation = "观察"
    case action = "行动"
    case teacherTurn = "教师巡视"
}

enum StudyPeriod: String, Hashable {
    case first = "第一节"
    case breakOne = "课间一"
    case second = "第二节"
    case breakTwo = "课间二"
    case third = "第三节"

    var displayName: String { rawValue }

    var isBreak: Bool {
        self == .breakOne || self == .breakTwo
    }

    var fatigueMultiplier: Double {
        switch self {
        case .first: return 0.9
        case .breakOne, .breakTwo: return 0.55
        case .second: return 1.0
        case .third: return 1.28
        }
    }

    static func period(forElapsedMinutes minutes: Int, totalMinutes: Int) -> StudyPeriod {
        if totalMinutes <= 70 {
            return minutes < totalMinutes - 10 ? .first : .breakOne
        }

        if minutes < 50 { return .first }
        if minutes < 60 { return .breakOne }
        if totalMinutes <= 130 {
            return minutes < totalMinutes - 10 ? .second : .breakTwo
        }
        if minutes < 110 { return .second }
        if minutes < 120 { return .breakTwo }
        return .third
    }
}

enum CameraPose: String, CaseIterable, Hashable, Codable {
    case forward = "前方"
    case desk = "低头"
    case board = "抬头"
    case left = "左侧"
    case right = "右侧"
    case rear = "后方"

    var angles: SCNVector3 {
        switch self {
        case .forward: return SCNVector3(0, 0, 0)
        case .desk: return SCNVector3(-0.62, 0, 0)
        case .board: return SCNVector3(0.22, 0, 0)
        case .left: return SCNVector3(0, 0.86, 0)
        case .right: return SCNVector3(0, -0.86, 0)
        case .rear: return SCNVector3(0, Float.pi, 0)
        }
    }

    var visionZone: VisionZone {
        switch self {
        case .board: return .upper
        case .forward: return .middle
        case .desk: return .desk
        case .left: return .leftPeripheral
        case .right: return .rightPeripheral
        case .rear: return .rearPeripheral
        }
    }

    var shortcut: Character {
        switch self {
        case .forward: return "w"
        case .desk: return "s"
        case .board: return "e"
        case .left: return "a"
        case .right: return "d"
        case .rear: return "q"
        }
    }
}

enum VisionZone: String {
    case upper = "A区"
    case middle = "B区"
    case desk = "C区"
    case leftPeripheral = "D区"
    case rightPeripheral = "E区"
    case rearPeripheral = "F区"

    var displayName: String {
        switch self {
        case .upper: return "上方远景"
        case .middle: return "中景"
        case .desk: return "桌面近景"
        case .leftPeripheral: return "左侧余光"
        case .rightPeripheral: return "右侧余光"
        case .rearPeripheral: return "后方视野"
        }
    }

    var attentionCost: Double {
        switch self {
        case .upper: return 30
        case .middle: return 10
        case .desk: return 5
        case .leftPeripheral, .rightPeripheral: return 0
        case .rearPeripheral: return 34
        }
    }
}

enum PlayerAction: String, CaseIterable, Identifiable {
    case study = "写作业"
    case phone = "看手机"
    case note = "传纸条"
    case observe = "观察"
    case talk = "同桌"
    case breathe = "深呼吸"
    case window = "看窗外"
    case drink = "喝水"
    case snack = "吃零食"
    case leaveSeat = "举手"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .study: return "book.fill"
        case .phone: return "iphone"
        case .note: return "envelope.fill"
        case .observe: return "eye.fill"
        case .talk: return "person.2.fill"
        case .breathe: return "wind"
        case .window: return "moon.stars.fill"
        case .drink: return "drop.fill"
        case .snack: return "takeoutbag.and.cup.and.straw.fill"
        case .leaveSeat: return "hand.raised.fill"
        }
    }

    var shortcut: Character {
        switch self {
        case .study: return "1"
        case .phone: return "2"
        case .note: return "3"
        case .observe: return "4"
        case .talk: return "5"
        case .breathe: return "6"
        case .window: return "7"
        case .drink: return "8"
        case .snack: return "9"
        case .leaveSeat: return "0"
        }
    }
}

enum PlayerPosture: String, Codable {
    case seated = "坐着"
    case standing = "站起"
}

enum TeacherAction: String, CaseIterable, Identifiable {
    case scanClass = "看全班"
    case observeTarget = "观察学生"
    case publicWarn = "公开提醒"
    case quietWarn = "低声提醒"
    case care = "关心询问"
    case allowBreak = "允许离开"
    case ignore = "选择性放过"
    case rest = "坐下休息"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .scanClass: return "rectangle.3.group.fill"
        case .observeTarget: return "eye.fill"
        case .publicWarn: return "exclamationmark.bubble.fill"
        case .quietWarn: return "bubble.left.fill"
        case .care: return "heart.text.square.fill"
        case .allowBreak: return "figure.walk"
        case .ignore: return "eye.slash.fill"
        case .rest: return "chair.fill"
        }
    }

    var shortcut: Character {
        switch self {
        case .scanClass: return "1"
        case .observeTarget: return "2"
        case .publicWarn: return "3"
        case .quietWarn: return "4"
        case .care: return "5"
        case .allowBreak: return "6"
        case .ignore: return "7"
        case .rest: return "8"
        }
    }
}

struct TeacherTruthObjective: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let action: TeacherAction
    let symbol: String
    let isComplete: Bool
}

enum TeacherLocation: String, CaseIterable, Identifiable {
    case podium = "讲台"
    case leftAisle = "左过道"
    case rightAisle = "右过道"
    case rearDoor = "后门"
    case targetDesk = "目标桌边"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .podium: return "rectangle.fill"
        case .leftAisle, .rightAisle: return "figure.walk"
        case .rearDoor: return "door.left.hand.closed"
        case .targetDesk: return "person.crop.circle.badge.exclamationmark.fill"
        }
    }

    var positionIndex: Int {
        switch self {
        case .podium: return 7
        case .leftAisle: return 6
        case .rightAisle: return 2
        case .rearDoor: return 8
        case .targetDesk: return 3
        }
    }

    static func closest(forPositionIndex index: Int) -> TeacherLocation {
        switch index {
        case 2, 4:
            return .rightAisle
        case 3:
            return .targetDesk
        case 5, 6:
            return .leftAisle
        case 8:
            return .rearDoor
        default:
            return .podium
        }
    }
}

enum TeacherFocusMode: String {
    case wholeClass = "看全班"
    case selectedStudent = "看目标学生"
    case blackboard = "看黑板/记录"
    case rearDoor = "看后门"
}

struct TeacherPatrolReadout: Identifiable, Equatable {
    enum Tone: Equatable {
        case distant
        case approaching
        case close
        case unseen
    }

    let id = UUID()
    let location: TeacherLocation
    let title: String
    let detail: String
    let recommendation: String
    let intensity: Double
    let tone: Tone

    static func derive(
        positionIndex: Int,
        isNearPlayer: Bool,
        institutionalPressure: Double,
        fatigue: Double,
        playerPose: CameraPose,
        playerExposure: Double
    ) -> TeacherPatrolReadout {
        let location = TeacherLocation.closest(forPositionIndex: positionIndex)
        let systemLoad = (institutionalPressure * 0.48 + fatigue * 0.22) / 100
        let exposureLoad = playerExposure / 100
        let poseLoad: Double
        switch playerPose {
        case .forward:
            poseLoad = 0.12
        case .desk:
            poseLoad = isNearPlayer ? 0.42 : 0.22
        case .board:
            poseLoad = 0.28
        case .left, .right:
            poseLoad = isNearPlayer ? 0.38 : 0.24
        case .rear:
            poseLoad = 0.72
        }

        let base = isNearPlayer ? 0.42 : (location == .rearDoor ? 0.36 : 0.18)
        let intensity = (base + systemLoad + exposureLoad * 0.28 + poseLoad * 0.32).clamped(to: 0...1)

        if location == .rearDoor {
            return TeacherPatrolReadout(
                location: location,
                title: "后门无声观察",
                detail: "老师不一定发出脚步声，后方安静本身也可能是压力。",
                recommendation: playerPose == .rear ? "已经确认后方，立刻收回视线会更稳。" : "别只等脚步声；把余光、后门声音和当前动作一起判断。",
                intensity: intensity,
                tone: .unseen
            )
        }

        if isNearPlayer {
            return TeacherPatrolReadout(
                location: location,
                title: "巡视贴近座位",
                detail: "老师进入可观察距离，动作会先被解释成秩序信号。",
                recommendation: playerPose == .forward ? "保持前方和可解释动作，等脚步离开再处理高风险操作。" : "先把视线收回前方，降低被误读成违规的概率。",
                intensity: intensity,
                tone: .close
            )
        }

        if intensity >= 0.54 {
            return TeacherPatrolReadout(
                location: location,
                title: "巡视正在压近",
                detail: "KPI、疲惫和巡视频率让老师更可能提前扫描异常动作。",
                recommendation: "现在适合短动作和恢复，不适合连续低头或回头确认。",
                intensity: intensity,
                tone: .approaching
            )
        }

        return TeacherPatrolReadout(
            location: location,
            title: "巡视暂在远处",
            detail: "老师仍在管理全班，但此刻没有直接压到你的座位。",
            recommendation: "可以趁低风险完成一次观察、呼吸或低声连接。",
            intensity: intensity,
            tone: .distant
        )
    }
}

struct TeacherPatrolPressureStageModel {
    struct Footprint {
        let position: SCNVector3
        let yaw: CGFloat
        let opacity: CGFloat
        let emission: CGFloat
    }

    let isActive: Bool
    let stageOpacity: CGFloat
    let pathBandPosition: SCNVector3
    let pathBandYaw: CGFloat
    let pathBandScale: SCNVector3
    let pathBandOpacity: CGFloat
    let pathBandEmission: CGFloat
    let seatRingScale: SCNVector3
    let seatRingOpacity: CGFloat
    let seatRingEmission: CGFloat
    let footprints: [Footprint]

    static func derive(
        from readout: TeacherPatrolReadout,
        teacherPosition: SCNVector3,
        playerGround: SCNVector3 = SCNVector3(-1.2, 0.04, 1.5)
    ) -> TeacherPatrolPressureStageModel {
        let pressure = CGFloat(readout.intensity.clamped(to: 0...1))
        let active = pressure > 0.18
        let start = SCNVector3(teacherPosition.x, 0.04, teacherPosition.z)
        let dx = playerGround.x - start.x
        let dz = playerGround.z - start.z
        let length = max(0.7, CGFloat(sqrt(dx * dx + dz * dz)))
        let yaw = atan2(dx, dz)
        let footprints = (0..<5).map { index in
            let progress = CGFloat(index + 1) / 6
            let offset: CGFloat = index.isMultiple(of: 2) ? 0.12 : -0.12
            let weight = CGFloat(0.55 - Double(index) * 0.055)
            return Footprint(
                position: SCNVector3(start.x + dx * progress, 0.058, start.z + dz * progress),
                yaw: yaw + offset,
                opacity: 0.16 + pressure * weight,
                emission: 0.14 + pressure * 0.42
            )
        }

        return TeacherPatrolPressureStageModel(
            isActive: active,
            stageOpacity: active ? 0.18 + pressure * 0.72 : 0,
            pathBandPosition: SCNVector3(start.x + dx * 0.5, 0.032, start.z + dz * 0.5),
            pathBandYaw: yaw,
            pathBandScale: SCNVector3(1, 1, Float(length / 2.15)),
            pathBandOpacity: 0.16 + pressure * 0.46,
            pathBandEmission: 0.12 + pressure * 0.64,
            seatRingScale: SCNVector3(1 + Float(pressure) * 0.22, 1 + Float(pressure) * 0.22, 1 + Float(pressure) * 0.22),
            seatRingOpacity: 0.22 + pressure * 0.58,
            seatRingEmission: 0.18 + pressure * 0.7,
            footprints: footprints
        )
    }
}

struct MirrorSpacePressureModel {
    let isActive: Bool
    let pressure: CGFloat
    let dissolve: CGFloat
    let completedLightCount: Int
    let shadowPosition: SCNVector3
    let shadowYaw: CGFloat
    let shadowOpacity: CGFloat
    let shadowScale: SCNVector3
    let breathRingPosition: SCNVector3
    let breathRingScale: SCNVector3
    let breathRingOpacity: CGFloat
    let breathRingEmission: CGFloat
    let mirrorTintEmission: CGFloat
    let crackOpacities: [CGFloat]
    let crackEmissions: [CGFloat]

    static func derive(from campaign: NarrativeCampaign) -> MirrorSpacePressureModel {
        let isMirror = campaign.chapter == .mirror
        let dissolve = CGFloat(campaign.mirrorDissolveProgress.clamped(to: 0...1))
        let games: [NarrativeMiniGame] = [.trace, .melody, .erase]
        let completedLights: Int
        if campaign.isComplete || campaign.chapter.rawValue > NarrativeChapter.mirror.rawValue || campaign.currentMoment.id == "2.listen" {
            completedLights = games.count
        } else {
            completedLights = games.enumerated().reduce(0) { count, item in
                let (index, game) = item
                let wasPassed = campaign.momentIndex > index + 1
                let justCompleted = campaign.currentMoment.miniGame == game && campaign.miniGameCompleted
                return count + (wasPassed || justCompleted ? 1 : 0)
            }
        }

        let activeProgress: CGFloat
        if let miniGame = campaign.currentMoment.miniGame, campaign.miniGameCompleted == false {
            activeProgress = CGFloat(Double(campaign.miniGameProgress) / Double(max(1, miniGame.requiredInteractions))).clamped(to: 0...1)
        } else {
            activeProgress = 0
        }

        let unresolved = CGFloat(1 - Double(completedLights) / Double(games.count))
        let pressure = (0.24 + unresolved * 0.54 + (1 - activeProgress) * 0.14 - dissolve * 0.42).clamped(to: 0...1)
        let connection = (CGFloat(completedLights) / CGFloat(games.count) + dissolve).clamped(to: 0...1)
        let shadowX = -0.78 + Float(connection) * 0.74
        let shadowZ = -1.85 + Float(activeProgress) * 0.28 + Float(dissolve) * 0.62
        let shadowYaw = -0.32 + connection * 0.78
        let shadowOpacity = (0.28 + pressure * 0.48 + connection * 0.22 - dissolve * 0.08).clamped(to: 0...1)
        let ringPower = (0.18 + pressure * 0.22 + connection * 0.48).clamped(to: 0...1)

        return MirrorSpacePressureModel(
            isActive: isMirror,
            pressure: pressure,
            dissolve: dissolve,
            completedLightCount: completedLights,
            shadowPosition: SCNVector3(shadowX, 0, shadowZ),
            shadowYaw: shadowYaw,
            shadowOpacity: isMirror ? shadowOpacity : 0,
            shadowScale: SCNVector3(0.68 + Float(connection) * 0.12, 0.68 + Float(connection) * 0.12, 0.68 + Float(connection) * 0.12),
            breathRingPosition: SCNVector3(shadowX, 0.052, shadowZ + 0.14),
            breathRingScale: SCNVector3(0.72 + Float(ringPower) * 0.78, 0.72 + Float(ringPower) * 0.78, 1),
            breathRingOpacity: isMirror ? 0.18 + ringPower * 0.58 : 0,
            breathRingEmission: 0.14 + ringPower * 0.74,
            mirrorTintEmission: 0.16 + pressure * 0.78 + dissolve * 0.26,
            crackOpacities: (0..<6).map { index in
                let weight = CGFloat(0.92 - Double(index) * 0.07)
                return isMirror ? (0.08 + pressure * weight - dissolve * 0.18).clamped(to: 0...1) : 0
            },
            crackEmissions: (0..<6).map { index in
                let weight = CGFloat(0.64 - Double(index) * 0.045)
                return 0.08 + pressure * weight + dissolve * 0.18
            }
        )
    }
}

struct MirrorReturnDirectorModel {
    let isActive: Bool
    let dissolve: CGFloat
    let title: String
    let detail: String
    let stageOpacity: CGFloat
    let linChePosition: SCNVector3
    let linCheYaw: CGFloat
    let linCheOpacity: CGFloat
    let faceLightPosition: SCNVector3
    let faceLightOpacity: CGFloat
    let faceLightScale: SCNVector3
    let faceLightEmission: CGFloat
    let realityBandPosition: SCNVector3
    let realityBandOpacity: CGFloat
    let realityBandScale: SCNVector3
    let realityBandEmission: CGFloat
    let returnGatePosition: SCNVector3
    let returnGateOpacity: CGFloat
    let returnGateScale: SCNVector3
    let returnGateEmission: CGFloat

    static func derive(from campaign: NarrativeCampaign) -> MirrorReturnDirectorModel {
        let dissolve = CGFloat(campaign.mirrorDissolveProgress.clamped(to: 0...1))
        guard campaign.chapter == .mirror, dissolve > 0 else {
            return inactive
        }

        let intensity = dissolve
        let isDialogue = campaign.currentMoment.id == "2.listen"
        let title = isDialogue ? "回到现实走廊" : "三灯正在把镜面松开"
        let detail = isDialogue
            ? "镜像褪到边缘，林澈转过来，真实的话可以开始。"
            : "第三盏灯点亮后，镜面还没有完全消失，但现实的暖光已经漏进来。"
        let linCheX = -0.52 + Float(intensity) * 0.34
        let linCheZ = -1.62 + Float(intensity) * 0.82
        let faceScale = 0.42 + Float(intensity) * 0.46
        let bandScaleX = 0.86 + Float(intensity) * 1.16
        let gateScale = 0.58 + Float(intensity) * 0.74

        return MirrorReturnDirectorModel(
            isActive: true,
            dissolve: intensity,
            title: title,
            detail: detail,
            stageOpacity: 1 - intensity * 0.42,
            linChePosition: SCNVector3(linCheX, 0, linCheZ),
            linCheYaw: -0.22 + intensity * 1.12,
            linCheOpacity: 0.42 + intensity * 0.42,
            faceLightPosition: SCNVector3(linCheX, 1.18, linCheZ + 0.04),
            faceLightOpacity: 0.18 + intensity * 0.62,
            faceLightScale: SCNVector3(faceScale, faceScale, faceScale),
            faceLightEmission: 0.28 + intensity * 1.18,
            realityBandPosition: SCNVector3(0, 1.48, -3.08),
            realityBandOpacity: 0.12 + intensity * 0.58,
            realityBandScale: SCNVector3(bandScaleX, 1, 1),
            realityBandEmission: 0.34 + intensity * 1.2,
            returnGatePosition: SCNVector3(0, 0.06, -1.28 + Float(intensity) * 0.28),
            returnGateOpacity: 0.16 + intensity * 0.62,
            returnGateScale: SCNVector3(gateScale, gateScale, 1),
            returnGateEmission: 0.3 + intensity * 1.1
        )
    }

    private static var inactive: MirrorReturnDirectorModel {
        MirrorReturnDirectorModel(
            isActive: false,
            dissolve: 0,
            title: "",
            detail: "",
            stageOpacity: 1,
            linChePosition: SCNVector3Zero,
            linCheYaw: 0,
            linCheOpacity: 0,
            faceLightPosition: SCNVector3Zero,
            faceLightOpacity: 0,
            faceLightScale: SCNVector3(1, 1, 1),
            faceLightEmission: 0,
            realityBandPosition: SCNVector3Zero,
            realityBandOpacity: 0,
            realityBandScale: SCNVector3(1, 1, 1),
            realityBandEmission: 0,
            returnGatePosition: SCNVector3Zero,
            returnGateOpacity: 0,
            returnGateScale: SCNVector3(1, 1, 1),
            returnGateEmission: 0
        )
    }
}

struct MirrorDialogueConsequenceModel: Equatable {
    let isActive: Bool
    let choiceID: String
    let title: String
    let detail: String
    let trustDeltaText: String
    let trustTotalText: String
    let nextChapterHint: String
    let supportBiasText: String
    let symbol: String

    static func derive(from campaign: NarrativeCampaign) -> MirrorDialogueConsequenceModel {
        guard let impact = campaign.activeChoiceImpact,
              impact.sourceMomentID == "2.listen",
              let choiceID = impact.id.split(separator: ".").last.map(String.init) else {
            return inactive
        }

        let trustDelta: Int
        let title: String
        let detail: String
        let next: String
        let bias: String
        let symbol: String
        switch choiceID {
        case "invite":
            trustDelta = 2
            title = "支持网络被明确邀请"
            detail = "林澈没有被要求立刻解释清楚；可靠的大人被放进下一步。"
            next = "第三章会更早把成人支持当成可选路径，而不是学生独自承担。"
            bias = "成人交接 + 支持靠近"
            symbol = "person.3.fill"
        case "present":
            trustDelta = 1
            title = "沉默没有变成离开"
            detail = "你没有急着解决，只把身体留在他身边，让下一句话有空间出现。"
            next = "第三章会强化同伴陪伴与低压力靠近。"
            bias = "在场陪伴 + 压力下降"
            symbol = "figure.stand"
        case "reassure":
            trustDelta = 1
            title = "负担被轻轻分走"
            detail = "这句话没有许诺奇迹，但把“一个人扛完”改成了可以被看见。"
            next = "第三章会保留林澈更愿意继续同行的信任基础。"
            bias = "信任 + 支持靠近"
            symbol = "heart.fill"
        default:
            return inactive
        }

        return MirrorDialogueConsequenceModel(
            isActive: true,
            choiceID: choiceID,
            title: title,
            detail: detail,
            trustDeltaText: "林澈信任 +\(trustDelta)",
            trustTotalText: "当前 \(campaign.linCheTrust)",
            nextChapterHint: next,
            supportBiasText: bias,
            symbol: symbol
        )
    }

    private static var inactive: MirrorDialogueConsequenceModel {
        MirrorDialogueConsequenceModel(
            isActive: false,
            choiceID: "",
            title: "",
            detail: "",
            trustDeltaText: "",
            trustTotalText: "",
            nextChapterHint: "",
            supportBiasText: "",
            symbol: ""
        )
    }
}

struct MirrorDialogueCarryoverModel: Equatable {
    let isActive: Bool
    let choiceID: String
    let title: String
    let detail: String
    let companionHint: String
    let supportBiasText: String
    let symbol: String

    static func derive(from campaign: NarrativeCampaign) -> MirrorDialogueCarryoverModel {
        guard [.noteTrace, .stairwell, .counseling].contains(campaign.chapter),
              let impact = campaign.activeChoiceImpact,
              impact.sourceMomentID == "2.listen",
              let choiceID = impact.id.split(separator: ".").last.map(String.init) else {
            return inactive
        }

        switch choiceID {
        case "invite":
            return MirrorDialogueCarryoverModel(
                isActive: true,
                choiceID: choiceID,
                title: campaign.chapter == .noteTrace ? "可靠的大人被带进下一章" : campaign.chapter == .stairwell ? "可靠的大人已经走到楼梯间" : "可靠的大人已经等在门外",
                detail: campaign.chapter == .noteTrace
                    ? "林澈那句没有停在镜子里，第三章的同伴会更像一起把人送到支持里。"
                    : campaign.chapter == .stairwell
                        ? "上一章把“找可靠的大人”说出口后，这一章的成人交接就不再像突然发生。"
                        : "支持已经接到等候区，不再只是镜子里的回声。",
                companionHint: campaign.chapter == .noteTrace
                    ? "先找线索，不再把“自己扛住”当成默认答案。"
                    : campaign.chapter == .stairwell
                        ? "先把位置说清楚，再把接手交给成人。"
                        : "先等在门外，让专业支持完成下一步。",
                supportBiasText: campaign.chapter == .noteTrace
                    ? "同伴更主动地转向成人支持"
                    : campaign.chapter == .stairwell
                        ? "第四章更早把成人支持当成默认路线"
                        : "第五章把支持延续到等候区",
                symbol: "person.3.fill"
            )
        case "present":
            return MirrorDialogueCarryoverModel(
                isActive: true,
                choiceID: choiceID,
                title: campaign.chapter == .noteTrace ? "先站在旁边" : campaign.chapter == .stairwell ? "先把身边留给支持" : "门外安静地等一会儿",
                detail: campaign.chapter == .noteTrace
                    ? "你没有把第三章提前变成结论，同伴会更稳地陪着找线索。"
                    : campaign.chapter == .stairwell
                        ? "这一章更需要把空间留给成人和江越，陪伴不抢话。"
                        : "等候不是空转，是把支持交给能真正接手的人。",
                companionHint: campaign.chapter == .noteTrace
                    ? "先把线索接上，再决定怎么向前。"
                    : campaign.chapter == .stairwell
                        ? "先确认到场，再站稳边界。"
                        : "先把等待守住，再继续下一步。",
                supportBiasText: campaign.chapter == .noteTrace
                    ? "同伴以低压陪伴推进"
                    : campaign.chapter == .stairwell
                        ? "楼梯间里把空间让给成人接手"
                        : "等候区里把边界守住",
                symbol: "figure.stand"
            )
        case "reassure":
            return MirrorDialogueCarryoverModel(
                isActive: true,
                choiceID: choiceID,
                title: campaign.chapter == .noteTrace ? "有人接住了那句" : campaign.chapter == .stairwell ? "那句安抚继续往前走" : "安抚停在门外也还在",
                detail: campaign.chapter == .noteTrace
                    ? "林澈愿意继续往前走，第三章的靠近会更柔和。"
                    : campaign.chapter == .stairwell
                        ? "那句安抚不会替代成人交接，但会让楼梯间的脚步不那么硬。"
                        : "等候区里，前一章的安抚变成了更安静的守候。",
                companionHint: campaign.chapter == .noteTrace
                    ? "先稳住，再继续确认纸条和离开迹象。"
                    : campaign.chapter == .stairwell
                        ? "先稳住，再把风险交给大人。"
                        : "先稳住，再把等待交给时间。",
                supportBiasText: campaign.chapter == .noteTrace
                    ? "同伴更平稳地继续同行"
                    : campaign.chapter == .stairwell
                        ? "楼梯间的脚步更平稳"
                        : "等候区的呼吸更平稳",
                symbol: "heart.fill"
            )
        default:
            return inactive
        }
    }

    private static var inactive: MirrorDialogueCarryoverModel {
        MirrorDialogueCarryoverModel(
            isActive: false,
            choiceID: "",
            title: "",
            detail: "",
            companionHint: "",
            supportBiasText: "",
            symbol: ""
        )
    }
}

struct MirrorLightNavigationCue {
    let isActive: Bool
    let light: NarrativeMiniGame?
    let hotspotID: String
    let title: String
    let detail: String
    let distance: Double
    let progressToRange: Double
    let playerPosition: SCNVector3
    let targetPosition: SCNVector3
    let pathPosition: SCNVector3
    let pathYaw: CGFloat
    let pathScale: SCNVector3
    let pathOpacity: CGFloat
    let pathEmission: CGFloat
    let targetRingScale: SCNVector3
    let targetRingOpacity: CGFloat
    let targetRingEmission: CGFloat

    static func derive(from campaign: NarrativeCampaign) -> MirrorLightNavigationCue {
        guard campaign.chapter == .mirror,
              let miniGame = campaign.currentMoment.miniGame,
              campaign.miniGameCompleted == false else {
            return MirrorLightNavigationCue.inactive
        }

        let hotspot = mirrorLightHotspot(for: miniGame)
        let player = SCNVector3(Float(campaign.exploration.positionX), 0.055, Float(campaign.exploration.positionZ))
        let target = SCNVector3(Float(hotspot.x), 0.06, Float(hotspot.z))
        let dx = hotspot.x - campaign.exploration.positionX
        let dz = hotspot.z - campaign.exploration.positionZ
        let distance = hypot(dx, dz)
        let targetRadius = hotspot.radius
        let progress = (1 - ((distance - targetRadius) / 3.2)).clamped(to: 0...1)
        let length = max(0.28, distance)
        let yaw = CGFloat(atan2(dx, dz))
        let pressure = MirrorSpacePressureModel.derive(from: campaign).pressure
        let activeProgress = CGFloat(progress)
        let playerHasArrived = distance <= targetRadius
        let title = playerHasArrived ? "确认\(miniGame.title)" : "走向\(miniGame.title)"
        let detail = playerHasArrived
            ? "距离足够近了，按确认键进入这盏灯。"
            : "镜面地面的光路正在把你带向下一盏灯。"

        return MirrorLightNavigationCue(
            isActive: true,
            light: miniGame,
            hotspotID: hotspot.id,
            title: title,
            detail: detail,
            distance: distance,
            progressToRange: progress,
            playerPosition: player,
            targetPosition: target,
            pathPosition: SCNVector3(Float((campaign.exploration.positionX + hotspot.x) * 0.5), 0.048, Float((campaign.exploration.positionZ + hotspot.z) * 0.5)),
            pathYaw: yaw,
            pathScale: SCNVector3(1, 1, Float(length / 2.15)),
            pathOpacity: 0.16 + activeProgress * 0.46 + pressure * 0.12,
            pathEmission: 0.24 + activeProgress * 0.84 + pressure * 0.28,
            targetRingScale: SCNVector3(0.86 + Float(activeProgress) * 0.5, 0.86 + Float(activeProgress) * 0.5, 1),
            targetRingOpacity: playerHasArrived ? 0.78 : 0.28 + activeProgress * 0.42,
            targetRingEmission: playerHasArrived ? 1.28 : 0.34 + activeProgress * 0.86
        )
    }

    private static var inactive: MirrorLightNavigationCue {
        MirrorLightNavigationCue(
            isActive: false,
            light: nil,
            hotspotID: "",
            title: "",
            detail: "",
            distance: 0,
            progressToRange: 0,
            playerPosition: SCNVector3Zero,
            targetPosition: SCNVector3Zero,
            pathPosition: SCNVector3Zero,
            pathYaw: 0,
            pathScale: SCNVector3(1, 1, 1),
            pathOpacity: 0,
            pathEmission: 0,
            targetRingScale: SCNVector3(1, 1, 1),
            targetRingOpacity: 0,
            targetRingEmission: 0
        )
    }

    private static func mirrorLightHotspot(for miniGame: NarrativeMiniGame) -> NarrativeHotspot {
        switch miniGame {
        case .trace:
            return NarrativeHotspot(id: "mirror.light.trace", title: "草稿灯", prompt: "", x: -1.18, z: -2.42, radius: 1.15, choiceID: "playTrace")
        case .melody:
            return NarrativeHotspot(id: "mirror.light.melody", title: "旋律灯", prompt: "", x: 0, z: -2.42, radius: 1.15, choiceID: "playMelody")
        case .erase:
            return NarrativeHotspot(id: "mirror.light.erase", title: "擦痕灯", prompt: "", x: 1.18, z: -2.42, radius: 1.15, choiceID: "playErase")
        }
    }
}

struct MirrorMicroGameEchoModel {
    let isActive: Bool
    let miniGame: NarrativeMiniGame?
    let completedSteps: Int
    let requiredSteps: Int
    let ratio: CGFloat
    let title: String
    let detail: String
    let echoOpacities: [CGFloat]
    let echoScales: [SCNVector3]
    let currentLightIndex: Int

    static func derive(from campaign: NarrativeCampaign) -> MirrorMicroGameEchoModel {
        guard campaign.chapter == .mirror,
              let miniGame = campaign.currentMoment.miniGame else {
            return inactive
        }
        let required = miniGame.requiredInteractions
        let completed = min(required, campaign.miniGameProgress)
        let ratio = CGFloat(Double(completed) / Double(max(1, required))).clamped(to: 0...1)
        let lightIndex: Int
        switch miniGame {
        case .trace: lightIndex = 0
        case .melody: lightIndex = 1
        case .erase: lightIndex = 2
        }

        let detail: String
        switch miniGame {
        case .trace:
            detail = completed == 0 ? "断线还没有接上。" : "第 \(completed) 段线已经在镜面里亮了一下。"
        case .melody:
            detail = completed == 0 ? "四拍旋律还在等你回应。" : "第 \(completed) 拍被接住，回声没有变成失败。"
        case .erase:
            detail = completed == 0 ? "比较的话仍贴在镜面上。" : "\(completed) 句比较退到边缘，还保留必要的痕迹。"
        }

        return MirrorMicroGameEchoModel(
            isActive: true,
            miniGame: miniGame,
            completedSteps: completed,
            requiredSteps: required,
            ratio: ratio,
            title: "\(miniGame.title)回响",
            detail: detail,
            echoOpacities: (0..<6).map { index in
                guard index < required else { return 0 }
                if index < completed { return 0.36 + ratio * 0.42 }
                if index == completed, completed < required { return 0.18 + ratio * 0.22 }
                return 0.06
            },
            echoScales: (0..<6).map { index in
                let active = index < completed ? 0.38 + ratio * 0.34 : 0.22
                return SCNVector3(Float(active), Float(active), Float(active))
            },
            currentLightIndex: lightIndex
        )
    }

    private static var inactive: MirrorMicroGameEchoModel {
        MirrorMicroGameEchoModel(
            isActive: false,
            miniGame: nil,
            completedSteps: 0,
            requiredSteps: 0,
            ratio: 0,
            title: "",
            detail: "",
            echoOpacities: Array(repeating: 0, count: 6),
            echoScales: Array(repeating: SCNVector3(0.2, 0.2, 0.2), count: 6),
            currentLightIndex: 0
        )
    }
}

struct MirrorMicroGamePerformanceModel {
    let isActive: Bool
    let miniGame: NarrativeMiniGame?
    let isOverlayActive: Bool
    let isReturnPulseActive: Bool
    let activeLightIndex: Int
    let title: String
    let detail: String
    let portalPosition: SCNVector3
    let portalScale: SCNVector3
    let portalOpacity: CGFloat
    let portalEmission: CGFloat
    let beamPosition: SCNVector3
    let beamScale: SCNVector3
    let beamOpacity: CGFloat
    let returnPulsePosition: SCNVector3
    let returnPulseScale: SCNVector3
    let returnPulseOpacity: CGFloat
    let returnPulseEmission: CGFloat

    static func derive(from campaign: NarrativeCampaign, activeMiniGame: NarrativeMiniGame?) -> MirrorMicroGamePerformanceModel {
        guard campaign.chapter == .mirror,
              let momentMiniGame = campaign.currentMoment.miniGame else {
            return inactive
        }

        let miniGame = activeMiniGame ?? momentMiniGame
        let lightIndex = lightIndex(for: miniGame)
        let progressRatio = CGFloat(Double(campaign.miniGameProgress) / Double(max(1, miniGame.requiredInteractions))).clamped(to: 0...1)
        let position = lightPosition(for: lightIndex)

        if activeMiniGame == miniGame, campaign.miniGameCompleted == false {
            let scale = 1.06 + Float(progressRatio) * 0.34
            return MirrorMicroGamePerformanceModel(
                isActive: true,
                miniGame: miniGame,
                isOverlayActive: true,
                isReturnPulseActive: false,
                activeLightIndex: lightIndex,
                title: "进入\(miniGame.title)",
                detail: "镜面把视角收进这盏灯，小游戏进度会直接回写到舞台。",
                portalPosition: position,
                portalScale: SCNVector3(scale, scale, 1),
                portalOpacity: 0.64 + progressRatio * 0.24,
                portalEmission: 0.82 + progressRatio * 0.58,
                beamPosition: SCNVector3(position.x * 0.5, 1.28, -2.78),
                beamScale: SCNVector3(0.28 + Float(abs(position.x)) * 0.36, 1, 1.08 + Float(progressRatio) * 0.24),
                beamOpacity: 0.34 + progressRatio * 0.26,
                returnPulsePosition: position,
                returnPulseScale: SCNVector3(0.72, 0.72, 1),
                returnPulseOpacity: 0,
                returnPulseEmission: 0
            )
        }

        if campaign.miniGameCompleted {
            return MirrorMicroGamePerformanceModel(
                isActive: true,
                miniGame: miniGame,
                isOverlayActive: false,
                isReturnPulseActive: true,
                activeLightIndex: lightIndex,
                title: "\(miniGame.title)归位",
                detail: "完成的光从小游戏回到镜面，下一段路保持点亮。",
                portalPosition: position,
                portalScale: SCNVector3(0.92, 0.92, 1),
                portalOpacity: 0.28,
                portalEmission: 0.46,
                beamPosition: SCNVector3(position.x * 0.5, 1.28, -2.78),
                beamScale: SCNVector3(0.2 + Float(abs(position.x)) * 0.28, 1, 0.92),
                beamOpacity: 0.14,
                returnPulsePosition: SCNVector3(position.x, position.y - 0.04, position.z + 0.03),
                returnPulseScale: SCNVector3(1.22, 1.22, 1),
                returnPulseOpacity: 0.68,
                returnPulseEmission: 1.12
            )
        }

        return inactive
    }

    private static var inactive: MirrorMicroGamePerformanceModel {
        MirrorMicroGamePerformanceModel(
            isActive: false,
            miniGame: nil,
            isOverlayActive: false,
            isReturnPulseActive: false,
            activeLightIndex: 0,
            title: "",
            detail: "",
            portalPosition: SCNVector3Zero,
            portalScale: SCNVector3(1, 1, 1),
            portalOpacity: 0,
            portalEmission: 0,
            beamPosition: SCNVector3Zero,
            beamScale: SCNVector3(1, 1, 1),
            beamOpacity: 0,
            returnPulsePosition: SCNVector3Zero,
            returnPulseScale: SCNVector3(1, 1, 1),
            returnPulseOpacity: 0,
            returnPulseEmission: 0
        )
    }

    private static func lightIndex(for miniGame: NarrativeMiniGame) -> Int {
        switch miniGame {
        case .trace: return 0
        case .melody: return 1
        case .erase: return 2
        }
    }

    private static func lightPosition(for index: Int) -> SCNVector3 {
        let positions = [
            SCNVector3(-1.18, 2.18, -2.37),
            SCNVector3(0, 2.36, -2.37),
            SCNVector3(1.18, 2.18, -2.37)
        ]
        return positions[min(max(index, 0), positions.count - 1)]
    }
}

struct MirrorMicroGameInputFeedbackModel: Equatable {
    enum Tone: String, Equatable {
        case ready
        case caught
        case recover
        case completed

        var symbolName: String {
            switch self {
            case .ready: return "scope"
            case .caught: return "sparkle"
            case .recover: return "arrow.counterclockwise"
            case .completed: return "checkmark.seal.fill"
            }
        }
    }

    let miniGame: NarrativeMiniGame
    let tone: Tone
    let title: String
    let detail: String
    let targetText: String
    let progressText: String
    let recoveryText: String
    let ratio: Double
    let toleranceText: String
    let accessibilityText: String

    var isRecovery: Bool { tone == .recover }

    static func ready(from campaign: NarrativeCampaign, miniGame: NarrativeMiniGame) -> MirrorMicroGameInputFeedbackModel {
        let completed = min(campaign.miniGameProgress, miniGame.requiredInteractions)
        return MirrorMicroGameInputFeedbackModel(
            miniGame: miniGame,
            tone: .ready,
            title: readyTitle(for: miniGame),
            detail: readyDetail(for: miniGame, progress: completed),
            targetText: targetText(for: miniGame, campaign: campaign),
            progressText: progressText(for: miniGame, completed: completed, touchedCount: campaign.miniGameTouchedSlots.count),
            recoveryText: recoveryText(for: miniGame, hintCount: campaign.miniGameHintCount),
            ratio: Double(completed) / Double(max(1, miniGame.requiredInteractions)),
            toleranceText: toleranceText(for: miniGame),
            accessibilityText: accessibilityText(for: miniGame)
        )
    }

    static func action(
        miniGame: NarrativeMiniGame,
        slot: Int,
        beforeProgress: Int,
        afterProgress: Int,
        beforeTouchedCount: Int,
        afterTouchedCount: Int,
        beforeHintCount: Int,
        afterHintCount: Int,
        completed: Bool
    ) -> MirrorMicroGameInputFeedbackModel {
        let advanced = afterProgress > beforeProgress || afterTouchedCount > beforeTouchedCount
        let tone: Tone = completed ? .completed : (advanced ? .caught : .recover)
        let title: String
        let detail: String
        switch miniGame {
        case .trace:
            title = completed ? "草稿线接上" : (advanced ? "第 \(afterProgress) 段被接住" : "描线偏离了光路")
            detail = advanced
                ? "这一段已经写进草稿灯；下一段会从当前光点继续。"
                : "离目标线超过 15pt 时只重置当次尝试，已接住的线不会丢。"
        case .melody:
            title = completed ? "旋律被接住" : (advanced ? "第 \(afterProgress) 拍正确" : "旋律重新播放")
            detail = advanced
                ? "这一拍被确认；继续按听到的顺序回应。"
                : (afterHintCount >= 3 ? "提示次数已满，旋律灯会自动通过，不把听力当门槛。" : "顺序不对时只重放旋律，不记录失败。")
        case .erase:
            title = completed ? "擦痕退到边缘" : (advanced ? "第 \(afterTouchedCount) 句被擦开" : (slot < 0 ? "没有擦到句子" : "这句已经擦过"))
            detail = advanced
                ? "比较的话正在退后；目标是 60%，不会把剩余 40% 清空。"
                : (slot < 0 ? "空白处不会扣分，靠近还亮着的比较句再擦一次。" : "重复擦同一句不会扣分，换一处还亮着的痕迹继续。")
        }

        return MirrorMicroGameInputFeedbackModel(
            miniGame: miniGame,
            tone: tone,
            title: title,
            detail: detail,
            targetText: targetText(for: miniGame, progress: afterProgress, touchedCount: afterTouchedCount),
            progressText: progressText(for: miniGame, completed: min(afterProgress, miniGame.requiredInteractions), touchedCount: afterTouchedCount),
            recoveryText: recoveryText(for: miniGame, hintCount: afterHintCount),
            ratio: Double(min(afterProgress, miniGame.requiredInteractions)) / Double(max(1, miniGame.requiredInteractions)),
            toleranceText: toleranceText(for: miniGame),
            accessibilityText: accessibilityText(for: miniGame)
        )
    }

    static func accessibleCompletion(from campaign: NarrativeCampaign, miniGame: NarrativeMiniGame) -> MirrorMicroGameInputFeedbackModel {
        MirrorMicroGameInputFeedbackModel(
            miniGame: miniGame,
            tone: .completed,
            title: "\(miniGame.title)由苏念慢慢完成",
            detail: "辅助完成走同一条通关路径，只省掉精细拖拽或听觉判断。",
            targetText: "已完成",
            progressText: progressText(for: miniGame, completed: miniGame.requiredInteractions, touchedCount: campaign.miniGameTouchedSlots.count),
            recoveryText: recoveryText(for: miniGame, hintCount: campaign.miniGameHintCount),
            ratio: 1,
            toleranceText: toleranceText(for: miniGame),
            accessibilityText: accessibilityText(for: miniGame)
        )
    }

    private static func readyTitle(for miniGame: NarrativeMiniGame) -> String {
        switch miniGame {
        case .trace: return "沿光点慢慢描"
        case .melody: return "听见四拍再回应"
        case .erase: return "擦到 60% 就够"
        }
    }

    private static func readyDetail(for miniGame: NarrativeMiniGame, progress: Int) -> String {
        switch miniGame {
        case .trace: return progress == 0 ? "靠近下一段线，偏了也只是重试当段。" : "从已亮的光点继续描，不需要完美直线。"
        case .melody: return "错误只会重播旋律，三次提示后会自动接住。"
        case .erase: return "拖过句子或逐项确认；剩下的话会保留在边缘。"
        }
    }

    private static func targetText(for miniGame: NarrativeMiniGame, campaign: NarrativeCampaign) -> String {
        targetText(for: miniGame, progress: campaign.miniGameProgress, touchedCount: campaign.miniGameTouchedSlots.count)
    }

    private static func targetText(for miniGame: NarrativeMiniGame, progress: Int, touchedCount: Int) -> String {
        switch miniGame {
        case .trace: return "目标：第 \(min(progress + 1, miniGame.requiredInteractions)) 段线"
        case .melody:
            let sequence = ["风", "灯", "笔", "夜"]
            return "目标：第 \(min(progress + 1, sequence.count)) 拍 \(sequence[min(progress, sequence.count - 1)])"
        case .erase: return "目标：再擦 \(max(0, miniGame.requiredInteractions - touchedCount)) 句"
        }
    }

    private static func progressText(for miniGame: NarrativeMiniGame, completed: Int, touchedCount: Int) -> String {
        switch miniGame {
        case .trace: return "覆盖 \(Int((Double(completed) / Double(miniGame.requiredInteractions) * 100).rounded()))% / 80%"
        case .melody: return "\(completed) / \(miniGame.requiredInteractions) 拍"
        case .erase: return "\(touchedCount) / 6 句，目标 \(miniGame.requiredInteractions) 句"
        }
    }

    private static func recoveryText(for miniGame: NarrativeMiniGame, hintCount: Int) -> String {
        switch miniGame {
        case .trace: return "容错 ±15pt；偏离只重试当前段。"
        case .melody: return "提示 \(hintCount)/3；满三次自动通过。"
        case .erase: return "保留 40%；重复擦不会惩罚。"
        }
    }

    private static func toleranceText(for miniGame: NarrativeMiniGame) -> String {
        switch miniGame {
        case .trace: return "±15pt"
        case .melody: return "3 次提示"
        case .erase: return "60% 阈值"
        }
    }

    private static func accessibilityText(for miniGame: NarrativeMiniGame) -> String {
        switch miniGame {
        case .trace: return "键盘可逐段确认。"
        case .melody: return "可重播，也可由苏念完成。"
        case .erase: return "键盘可逐句擦除。"
        }
    }
}

struct MirrorMelodyPlaybackModel: Equatable {
    struct Pad: Equatable, Identifiable {
        let id: Int
        let label: String
        let frequency: Double
        let sequenceOrder: Int?
        let isPlayed: Bool
        let isNext: Bool
        let caption: String
    }

    static let sequence = [1, 3, 0, 2]
    static let labels = ["风", "灯", "笔", "夜"]
    static let frequencies = [330.0, 392.0, 440.0, 523.0]

    let isActive: Bool
    let completedBeats: Int
    let nextPadIndex: Int?
    let hintCount: Int
    let isAutoPassArmed: Bool
    let sequenceText: String
    let frequencyText: String
    let statusText: String
    let pads: [Pad]

    static func derive(from campaign: NarrativeCampaign) -> MirrorMelodyPlaybackModel {
        guard campaign.chapter == .mirror,
              campaign.currentMoment.miniGame == .melody else {
            return inactive
        }
        let completed = min(campaign.miniGameProgress, sequence.count)
        let playedPads = Set(sequence.prefix(completed))
        let next = completed < sequence.count ? sequence[completed] : nil
        let hintCount = campaign.miniGameHintCount
        let sequenceLabels = sequence.map { labels[$0] }
        let pads = labels.indices.map { index in
            let order = sequence.firstIndex(of: index).map { $0 + 1 }
            let frequency = frequencies[index]
            let caption: String
            if playedPads.contains(index) {
                caption = "已接住"
            } else if next == index {
                caption = "下一拍"
            } else if let order {
                caption = "第 \(order) 拍"
            } else {
                caption = "\(Int(frequency))Hz"
            }
            return Pad(
                id: index,
                label: labels[index],
                frequency: frequency,
                sequenceOrder: order,
                isPlayed: playedPads.contains(index),
                isNext: next == index,
                caption: caption
            )
        }

        let status: String
        if completed >= sequence.count {
            status = "四拍都被接住。"
        } else if hintCount >= 3 {
            status = "提示已满，旋律灯会自动接住。"
        } else if hintCount > 0 {
            status = "第 \(hintCount) 次重放后，从\(labels[next ?? 0])继续。"
        } else {
            status = "听见灯、夜、风、笔，再按顺序回应。"
        }

        return MirrorMelodyPlaybackModel(
            isActive: true,
            completedBeats: completed,
            nextPadIndex: next,
            hintCount: hintCount,
            isAutoPassArmed: hintCount >= 2 && completed < sequence.count,
            sequenceText: sequenceLabels.joined(separator: " · "),
            frequencyText: sequence.map { "\(Int(frequencies[$0]))Hz" }.joined(separator: " / "),
            statusText: status,
            pads: pads
        )
    }

    private static var inactive: MirrorMelodyPlaybackModel {
        MirrorMelodyPlaybackModel(
            isActive: false,
            completedBeats: 0,
            nextPadIndex: nil,
            hintCount: 0,
            isAutoPassArmed: false,
            sequenceText: "",
            frequencyText: "",
            statusText: "",
            pads: []
        )
    }
}

struct MirrorTraceGestureAssessment: Equatable {
    static let hitTolerance: CGFloat = 15
    static let sampleCount = 5
    static let requiredCoverage: Double = 0.8

    let isHit: Bool
    let segment: Int
    let sampleIndex: Int?
    let distance: CGFloat
    let projectedRatio: Double
    let coverageRatio: Double
    let shouldCommitSegment: Bool

    static func assess(
        location: CGPoint,
        segment: Int,
        points: [CGPoint],
        coveredSamples: Set<Int>,
        tolerance: CGFloat = hitTolerance
    ) -> MirrorTraceGestureAssessment {
        guard segment >= 0,
              segment + 1 < points.count else {
            return MirrorTraceGestureAssessment(
                isHit: false,
                segment: segment,
                sampleIndex: nil,
                distance: .infinity,
                projectedRatio: 0,
                coverageRatio: Double(coveredSamples.count) / Double(sampleCount),
                shouldCommitSegment: false
            )
        }

        let projection = projectionInfo(for: location, from: points[segment], to: points[segment + 1])
        let isHit = projection.distance <= tolerance
        let sample = min(sampleCount - 1, max(0, Int((projection.ratio * Double(sampleCount)).rounded(.down))))
        var samples = coveredSamples
        if isHit {
            samples.insert(sample)
        }
        let coverage = Double(samples.count) / Double(sampleCount)

        return MirrorTraceGestureAssessment(
            isHit: isHit,
            segment: segment,
            sampleIndex: isHit ? sample : nil,
            distance: projection.distance,
            projectedRatio: projection.ratio,
            coverageRatio: coverage,
            shouldCommitSegment: isHit && coverage >= requiredCoverage
        )
    }

    private static func projectionInfo(for location: CGPoint, from start: CGPoint, to end: CGPoint) -> (distance: CGFloat, ratio: Double) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return (hypot(location.x - start.x, location.y - start.y), 0)
        }
        let rawProjection = (((location.x - start.x) * dx) + ((location.y - start.y) * dy)) / lengthSquared
        let clampedProjection = min(1, max(0, rawProjection))
        let nearest = CGPoint(x: start.x + clampedProjection * dx, y: start.y + clampedProjection * dy)
        return (hypot(location.x - nearest.x, location.y - nearest.y), Double(clampedProjection))
    }
}

struct MirrorEraseGestureAssessment: Equatable {
    static let hitRadius: CGFloat = 66
    static let targetCoverage: Double = 0.60

    let isHit: Bool
    let slot: Int?
    let distance: CGFloat
    let touchedCount: Int
    let coverageRatio: Double
    let shouldCommitErase: Bool

    static func assess(location: CGPoint, anchors: [CGPoint], touchedSlots: Set<Int>, radius: CGFloat = hitRadius) -> MirrorEraseGestureAssessment {
        guard let candidate = anchors.indices.min(by: { lhs, rhs in
            distance(from: anchors[lhs], to: location) < distance(from: anchors[rhs], to: location)
        }) else {
            return MirrorEraseGestureAssessment(isHit: false, slot: nil, distance: .infinity, touchedCount: touchedSlots.count, coverageRatio: 0, shouldCommitErase: false)
        }

        let candidateDistance = distance(from: anchors[candidate], to: location)
        let isHit = candidateDistance <= radius
        let nextTouchedCount = (touchedSlots.contains(candidate) || isHit == false)
            ? touchedSlots.count
            : touchedSlots.count + 1
        let coverage = Double(nextTouchedCount) / Double(max(1, anchors.count))

        return MirrorEraseGestureAssessment(
            isHit: isHit,
            slot: isHit ? candidate : nil,
            distance: candidateDistance,
            touchedCount: nextTouchedCount,
            coverageRatio: coverage,
            shouldCommitErase: isHit && touchedSlots.contains(candidate) == false
        )
    }

    private static func distance(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }
}

struct PlayerState: Codable, Equatable {
    var psychicEnergy: Double = 72
    var maskCost: Double = 24
    var support: Double = 38
    var stress: Double = 30
    var exposure: Double = 18
    var visualAttention: Double = 86
    var focusQuality: Double = 1
    var posture: PlayerPosture = .seated
    var homework: Double = 0
    var thirst: Double = 20
    var hunger: Double = 28
    var bladder: Double = 18
    var waterCup: Double = 100
    var helpedClassmate: Bool = false
    var teacherWarnings: Int = 0
    var teacherCareMoments: Int = 0

    var breakdownRisk: Double {
        max(0, stress + maskCost * 0.45 + exposure * 0.25 - psychicEnergy - support * 0.18)
    }

    var highestBodyNeed: Double {
        max(thirst, hunger, bladder)
    }
}

struct StudentFreeRoamState {
    var isActive: Bool = false
    var positionX: Double = -0.6
    var positionZ: Double = 1.65
    var yaw: Double = 0
    var pitch: Double = 0
    var startedAt: Date = .distantPast
    var endsAt: Date = .distantPast
    var hasExitedClassroom: Bool = false
    var isSideways: Bool = false
    var isSprinting: Bool = false
    var frontDoorOpen: Bool = false
    var rearDoorOpen: Bool = false

    var remainingSeconds: Int {
        guard isActive else { return 0 }
        return max(0, Int(ceil(endsAt.timeIntervalSinceNow)))
    }
}

enum StudentDoor: String, CaseIterable, Identifiable {
    case front = "前门"
    case rear = "后门"

    var id: String { rawValue }

    var centerX: Double { 4.0 }

    var centerZ: Double {
        switch self {
        case .front: return -4.65
        case .rear: return 4.65
        }
    }
}

struct InstitutionSettings: Equatable {
    var studyHours: Double = 3
    var allowsWhispering: Bool = false
    var rankingPressure: Double = 70
    var patrolFrequency: Double = 65

    var maxTurns: Int {
        max(6, Int(studyHours * 6))
    }

    var totalMinutes: Int {
        max(60, Int(studyHours * 60))
    }

    var description: String {
        let whisper = allowsWhispering ? "可低声交流" : "禁止交流"
        return "\(String(format: "%.1f", studyHours))小时 · \(whisper) · 排名压力 \(Int(rankingPressure)) · 巡视频率 \(Int(patrolFrequency))"
    }
}

struct TeacherState {
    var kpiPressure: Double = 66
    var fatigue: Double = 44
    var empathy: Double = 42
    var studentTrust: Double = 34
    var counselingCapacity: Double = 36
    var classOrder: Double = 62
    var classRisk: Double = 34
    var misreadRisk: Double = 24
    var location: TeacherLocation = .podium
    var focusMode: TeacherFocusMode = .wholeClass
    var positionIndex: Int = 0
    var isNearPlayer: Bool = false
    var studentsWarned: Int = 0
    var studentsHelped: Int = 0
    var institutionalPressure: Double {
        (kpiPressure * 0.58 + fatigue * 0.42 - empathy * 0.25).clamped(to: 0...100)
    }
}

struct Ending: Equatable {
    let title: String
    let body: String
    let reflection: String
    let story: EndingStory
    let empathyReflections: [EmpathyReflection]
    let relationshipEchoes: [RelationshipEcho]
    let analysis: [EndingMetric]
    let comparisons: [EndingComparison]
    let resources: [SupportResource]
}

struct EndingStory: Equatable, Identifiable {
    let id = UUID()
    let title: String
    let body: String
    let prompt: String
}

struct EmpathyReflection: Equatable, Identifiable {
    let id = UUID()
    let role: String
    let icon: String
    let text: String
}

struct RelationshipEcho: Equatable, Identifiable {
    let id = UUID()
    let name: String
    let title: String
    let text: String
}

struct EndingMetric: Equatable, Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let note: String
}

struct EndingComparison: Equatable, Identifiable {
    let id = UUID()
    let title: String
    let playerValue: String
    let referenceValue: String
    let note: String
}

struct SupportResource: Codable, Equatable, Identifiable {
    let id: String
    let region: String
    let displayName: String
    let number: String?
    let detail: String
    let url: String?
    let reviewedAt: Date
    let sourceURL: String
    let sourceTitle: String

    var title: String { displayName }

    var copyText: String {
        if let number, number.isEmpty == false {
            return number
        }
        if let url, url.isEmpty == false {
            return url
        }
        return "\(displayName)：\(detail)"
    }

    var reviewedAtText: String {
        Self.dateFormatter.string(from: reviewedAt)
    }

    init(
        id: String,
        region: String,
        displayName: String,
        number: String?,
        detail: String,
        url: String?,
        reviewedAt: Date,
        sourceURL: String,
        sourceTitle: String
    ) {
        self.id = id
        self.region = region
        self.displayName = displayName
        self.number = number
        self.detail = detail
        self.url = url
        self.reviewedAt = reviewedAt
        self.sourceURL = sourceURL
        self.sourceTitle = sourceTitle
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case region
        case displayName
        case number
        case detail
        case url
        case reviewedAt
        case sourceURL
        case sourceTitle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        region = try container.decode(String.self, forKey: .region)
        displayName = try container.decode(String.self, forKey: .displayName)
        number = try container.decodeIfPresent(String.self, forKey: .number)
        detail = try container.decode(String.self, forKey: .detail)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        let reviewedAtText = try container.decode(String.self, forKey: .reviewedAt)
        guard let reviewedAt = Self.dateFormatter.date(from: reviewedAtText) else {
            throw DecodingError.dataCorruptedError(
                forKey: .reviewedAt,
                in: container,
                debugDescription: "Expected reviewedAt in yyyy-MM-dd format"
            )
        }
        self.reviewedAt = reviewedAt
        sourceURL = try container.decode(String.self, forKey: .sourceURL)
        sourceTitle = try container.decode(String.self, forKey: .sourceTitle)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(region, forKey: .region)
        try container.encode(displayName, forKey: .displayName)
        try container.encodeIfPresent(number, forKey: .number)
        try container.encode(detail, forKey: .detail)
        try container.encodeIfPresent(url, forKey: .url)
        try container.encode(Self.dateFormatter.string(from: reviewedAt), forKey: .reviewedAt)
        try container.encode(sourceURL, forKey: .sourceURL)
        try container.encode(sourceTitle, forKey: .sourceTitle)
    }

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

struct TeacherPostgameReflection: Equatable {
    let monologue: String
    let segments: [TeacherMonologueSegment]
    let analysis: [TeacherAnalysisPoint]
    let studentTakeaway: String
    let metrics: [EndingMetric]
}

struct TeacherMonologueSegment: Equatable, Identifiable {
    let id = UUID()
    let time: String
    let title: String
    let text: String
}

struct TeacherAnalysisPoint: Equatable, Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let icon: String
}

struct MechanicExplanation: Equatable, Identifiable {
    let id = UUID()
    let title: String
    let formula: String
    let note: String
}

struct ReviewPoint: Equatable, Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let icon: String
}

struct PerformanceReview: Equatable {
    let strengths: [ReviewPoint]
    let improvements: [ReviewPoint]
    let encouragement: String
}

struct Classmate: Identifiable {
    let id: Int
    let name: String
    let seat: (row: Int, column: Int)
    let profile: ClassmateProfile
    var support: Double
    var stress: Double
    var state: ClassmateState
    var relationship: Double
    var hasSharedTruth: Bool
    var suspicionOfPlayer: Double = 0

    var riskReason: String {
        if state == .crying { return "情绪已外显" }
        if profile.anxiety > 70 && stress > 72 { return "高焦虑基线" }
        if profile.maskStrength < 36 && stress > 68 { return "面具维持弱" }
        if profile.orderliness > 76 && stress > 64 { return "过度守序" }
        if relationship > 62 && stress > 66 { return "会关注你" }
        if profile.rebelliousness > 74 && state == .usingPhone { return "叛逆诱发违规" }
        return profile.traitLabel
    }
}

struct ClassmateProfile: Equatable {
    let cooperation: Double
    let orderliness: Double
    let rebelliousness: Double
    let empathy: Double
    let anxiety: Double
    let maskStrength: Double

    var traitLabel: String {
        if empathy > 72 { return "高同理心" }
        if anxiety > 68 { return "易焦虑" }
        if orderliness > 72 { return "守序" }
        if rebelliousness > 72 { return "叛逆" }
        if maskStrength < 38 { return "面具薄" }
        return "普通"
    }

    var signalReaction: String {
        if empathy > 72 { return "停下笔，朝声音的方向看了一眼，又很快移开视线" }
        if anxiety > 68 { return "肩膀明显僵了一下，翻页的动作变得更快" }
        if orderliness > 72 { return "把头压得更低，像是不确定自己是否应该介入" }
        if rebelliousness > 72 { return "没有继续装作没听见，直接回头确认了一眼" }
        if maskStrength < 38 { return "手里的笔停住了，自己的呼吸也乱了一拍" }
        return "短暂停了一下，又继续写题"
    }
}

struct ClassmateMemory: Equatable, Codable {
    var relationshipCarry: Double
    var stressEcho: Double
    var suspicionCarry: Double
    var sharedTruth: Bool
    var helpedLastRun: Bool
}

enum ClassmateState: String {
    case studying = "写题"
    case anxious = "焦虑"
    case usingPhone = "手机"
    case sleeping = "困倦"
    case lookingAtPlayer = "看你"
    case offeringHelp = "关心你"
    case crying = "崩溃"
    case covering = "掩护"
}

struct EventLogEntry: Identifiable {
    let id = UUID()
    let turn: Int
    let title: String
    let detail: String
}

struct TurnSnapshot: Identifiable {
    let id = UUID()
    let turn: Int
    let actionLabel: String
    let visibleScene: String
    let innerTruth: String
    let teacherInterpretation: String
    let metrics: String
    let energy: Double
    let stress: Double
    let maskCost: Double
    let support: Double
    let exposure: Double
    let bodyNeed: Double
}

enum AudioCueKind: String, CaseIterable {
    case footstep = "脚步"
    case paper = "纸张"
    case phone = "手机"
    case whisper = "低语"
    case chair = "椅子"
    case crying = "抽泣"
    case lights = "灯管"
    case heartbeat = "心跳"
    case broadcast = "广播"
    case bell = "铃声"
    case knock = "敲门"
    case stomach = "肚子"
    case wrapper = "包装纸"
    case teacherCough = "咳嗽"
    case teacherSigh = "叹气"
}

struct AudioCue: Identifiable {
    let id = UUID()
    let createdAt = Date()
    let turn: Int
    let kind: AudioCueKind
    let direction: String
    let intensity: Double
    let note: String

    var bearingText: String {
        if direction.contains("颅内") { return "内在" }
        if direction.contains("头顶") { return "头顶" }
        if direction.contains("四周") { return "环绕" }
        if direction.contains("讲台") { return "前方" }
        if direction.contains("桌面") || direction.contains("桌边") || direction.contains("座位") { return "桌边" }

        let lateral: String
        if direction.contains("左") {
            lateral = "左"
        } else if direction.contains("右") {
            lateral = "右"
        } else {
            lateral = ""
        }

        let depth: String
        if direction.contains("前") {
            depth = "前方"
        } else if direction.contains("后") {
            depth = "后方"
        } else {
            depth = ""
        }

        if lateral.isEmpty == false, depth.isEmpty == false {
            return lateral + depth
        }
        if lateral.isEmpty == false {
            return "\(lateral)侧"
        }
        if depth.isEmpty == false {
            return depth
        }
        if direction.contains("过道") { return "右前方" }
        if direction.contains("窗外") { return "左侧" }
        return "前方"
    }

    var distanceBand: String {
        if direction.contains("颅内") { return "身体内" }
        if direction.contains("极近") || direction.contains("同伴") || direction.contains("同桌") || direction.contains("近处")
            || direction.contains("桌面") || direction.contains("桌边") || direction.contains("座位") {
            return "近侧"
        }
        if direction.contains("远") || direction.contains("讲台") || direction.contains("窗外") || direction.contains("走廊") || direction.contains("后门") {
            return "远处"
        }
        if intensity >= 0.76 { return "压近" }
        if intensity <= 0.28 { return "很远" }
        return "中距"
    }

    var spatialReadout: String {
        "\(bearingText) · \(distanceBand)"
    }

    var tacticalSignalText: String {
        switch kind {
        case .footstep, .knock, .phone, .wrapper:
            return "风险"
        case .chair:
            return intensity >= 0.56 ? "暴露" : "姿态"
        case .whisper, .paper, .crying:
            return "支持"
        case .heartbeat, .stomach:
            return "身体"
        case .teacherCough, .teacherSigh, .broadcast:
            return "制度"
        case .lights, .bell:
            return "环境"
        }
    }

    var radarAngleRadians: Double {
        if direction.contains("颅内") || direction.contains("头顶") { return -.pi / 2 }
        if direction.contains("桌面") || direction.contains("桌边") || direction.contains("座位") { return -.pi / 5 }
        if direction.contains("过道") { return -.pi / 8 }
        if direction.contains("讲台") { return -.pi / 2 }
        if direction.contains("窗外") { return .pi }

        let hasLeft = direction.contains("左")
        let hasRight = direction.contains("右")
        let hasFront = direction.contains("前")
        let hasRear = direction.contains("后")

        if hasLeft && hasFront { return -.pi * 3 / 4 }
        if hasRight && hasFront { return -.pi / 4 }
        if hasLeft && hasRear { return .pi * 3 / 4 }
        if hasRight && hasRear { return .pi / 4 }
        if hasRear { return .pi / 2 }
        if hasLeft { return .pi }
        if hasRight { return 0 }
        if hasFront { return -.pi / 2 }
        return -.pi / 2
    }
}

struct DirectionalSubtitleEvent: Identifiable, Equatable {
    let id = UUID()
    let createdAt = Date()
    let turn: Int
    let kind: AudioCueKind
    let direction: String
    let intensity: Double
    let note: String

    var caption: String {
        "[\(direction)：\(kind.rawValue)]"
    }

    var accessibilitySummary: String {
        "\(kind.rawValue)，方向 \(direction)，\(note)"
    }
}

struct SensorySoundscape: Equatable {
    let cueCount: Int
    let dominantKind: AudioCueKind?
    let dominantDirection: String
    let averageIntensity: Double
    let riskPressure: Double
    let supportSignal: Double
    let bodyAlarm: Double
    let institutionalPressure: Double

    static let quiet = SensorySoundscape(
        cueCount: 0,
        dominantKind: nil,
        dominantDirection: "环境底噪",
        averageIntensity: 0,
        riskPressure: 0,
        supportSignal: 0,
        bodyAlarm: 0,
        institutionalPressure: 0
    )

    static func derive(
        from cues: [AudioCue],
        teacherNear: Bool,
        allowsWhispering: Bool
    ) -> SensorySoundscape {
        let recent = Array(cues.prefix(5))
        guard recent.isEmpty == false else { return .quiet }

        let dominant = recent.max { lhs, rhs in lhs.intensity < rhs.intensity }
        let average = recent.map(\.intensity).reduce(0, +) / Double(recent.count)
        var risk = teacherNear ? 0.24 : 0
        var support = 0.0
        var body = 0.0
        var institution = 0.0

        for cue in recent {
            let weight = cue.intensity.clamped(to: 0...1)
            switch cue.kind {
            case .footstep, .knock, .phone, .wrapper:
                risk += weight * 0.34
            case .chair:
                risk += weight * 0.18
                body += weight * 0.16
            case .crying:
                risk += weight * 0.22
                support += weight * 0.34
            case .paper:
                support += weight * 0.22
            case .whisper:
                support += weight * (allowsWhispering ? 0.28 : 0.16)
                risk += weight * (allowsWhispering ? 0.08 : 0.22)
            case .heartbeat, .stomach:
                body += weight * 0.38
            case .broadcast, .bell, .teacherCough, .teacherSigh:
                institution += weight * 0.34
                risk += weight * 0.16
            case .lights:
                institution += weight * 0.18
            }
        }

        return SensorySoundscape(
            cueCount: recent.count,
            dominantKind: dominant?.kind,
            dominantDirection: dominant?.direction ?? "环境底噪",
            averageIntensity: average.clamped(to: 0...1),
            riskPressure: risk.clamped(to: 0...1),
            supportSignal: support.clamped(to: 0...1),
            bodyAlarm: body.clamped(to: 0...1),
            institutionalPressure: institution.clamped(to: 0...1)
        )
    }

    var title: String {
        if cueCount == 0 { return "声场安静" }
        if riskPressure >= 0.62 { return "风险声源压近" }
        if bodyAlarm >= 0.52 { return "身体声音盖过环境" }
        if supportSignal >= 0.44 { return "支持信号可接住" }
        if institutionalPressure >= 0.48 { return "制度声音抬高" }
        return "声场可读"
    }

    var subtitle: String {
        if let dominantKind {
            return "\(dominantDirection) · \(dominantKind.rawValue) · 平均强度 \(Int((averageIntensity * 100).rounded()))%"
        }
        return "没有突出的方向声源"
    }

    var recommendation: String {
        if riskPressure >= 0.62 {
            return "先降低暴露，等脚步或门声位置稳定后再行动。"
        }
        if bodyAlarm >= 0.52 {
            return "先处理呼吸、饥饿或如厕压力，别把报警误当成失败。"
        }
        if supportSignal >= 0.44 {
            return "纸张、低语或抽泣正在给出连接入口，可以用低压力方式回应。"
        }
        if institutionalPressure >= 0.48 {
            return "广播、铃声或老师疲惫会抬高全班压力，动作要短、轻、可解释。"
        }
        return "保持听觉边界，优先做低消耗观察或恢复。"
    }
}

struct SensoryCameraPressure: Equatable {
    let blur: Double
    let vignette: Double
    let desaturation: Double

    static let neutral = SensoryCameraPressure(blur: 0, vignette: 0, desaturation: 0)

    static func derive(from soundscape: SensorySoundscape) -> SensoryCameraPressure {
        let risk = soundscape.riskPressure
        let body = soundscape.bodyAlarm
        let institution = soundscape.institutionalPressure
        let support = soundscape.supportSignal
        let overload = max(risk * 0.72, body * 0.62, institution * 0.36)
        let recovery = min(0.28, support * 0.22)
        let pressure = max(0, overload - recovery).clamped(to: 0...1)
        return SensoryCameraPressure(
            blur: pressure * 1.65 + body * 0.36,
            vignette: pressure * 0.44 + risk * 0.12,
            desaturation: max(0, pressure * 0.16 - support * 0.04)
        )
    }
}

struct SensoryClassroomGroupReaction: Equatable {
    let pressure: Double
    let support: Double
    let bodyAlarm: Double
    let compression: Double
    let opacityDrop: Double
    let glowIntensity: Double
    let leanZ: Double
    let supportDominant: Bool

    static let quiet = SensoryClassroomGroupReaction(
        pressure: 0,
        support: 0,
        bodyAlarm: 0,
        compression: 0,
        opacityDrop: 0,
        glowIntensity: 0,
        leanZ: 0,
        supportDominant: false
    )

    static func derive(from soundscape: SensorySoundscape) -> SensoryClassroomGroupReaction {
        let pressure = max(soundscape.riskPressure, soundscape.institutionalPressure * 0.72).clamped(to: 0...1)
        let support = soundscape.supportSignal.clamped(to: 0...1)
        let bodyAlarm = soundscape.bodyAlarm.clamped(to: 0...1)
        let dominant = max(pressure, support)
        let pressureBias = max(0, pressure - support * 0.45)
        let supportBias = max(0, support - pressure * 0.32)

        return SensoryClassroomGroupReaction(
            pressure: pressure,
            support: support,
            bodyAlarm: bodyAlarm,
            compression: (pressureBias * 0.72 + bodyAlarm * 0.24).clamped(to: 0...1),
            opacityDrop: (pressureBias * 0.16 + bodyAlarm * 0.06 - supportBias * 0.08).clamped(to: -0.08...0.22),
            glowIntensity: (0.08 + dominant * 0.76 + bodyAlarm * 0.18).clamped(to: 0...1.08),
            leanZ: (pressureBias * 0.05 - supportBias * 0.035).clamped(to: -0.05...0.075),
            supportDominant: supportBias > pressureBias
        )
    }

    var isActive: Bool {
        pressure > 0.08 || support > 0.08 || bodyAlarm > 0.08
    }
}

struct SensoryPeerCue: Equatable, Identifiable {
    enum Tone: String, Equatable {
        case warning
        case support
        case body
        case institution
    }

    let id: String
    let classmateID: Int
    let classmateName: String
    let direction: String
    let tone: Tone
    let surfaceSignal: String
    let spokenLine: String
    let lowPressureAction: String
    let audioKind: AudioCueKind
    let audioIntensity: Double

    var eventTitle: String {
        switch tone {
        case .warning:
            return "\(classmateName)压低声音提醒"
        case .support:
            return "\(classmateName)给出连接入口"
        case .body:
            return "\(classmateName)注意到你的状态"
        case .institution:
            return "\(classmateName)跟着全班绷紧"
        }
    }

    var eventDetail: String {
        "\(direction)：\(surfaceSignal) \(spokenLine)"
    }

    static func derive(
        from soundscape: SensorySoundscape,
        classmates: [Classmate],
        playerSupport: Double,
        allowsWhispering: Bool
    ) -> SensoryPeerCue? {
        let reaction = SensoryClassroomGroupReaction.derive(from: soundscape)
        guard reaction.isActive else { return nil }
        let eligible = classmates.filter { $0.state != .sleeping }
        guard eligible.isEmpty == false else { return nil }

        if reaction.supportDominant || soundscape.supportSignal >= 0.44 {
            let mate = eligible.max { lhs, rhs in
                peerSupportScore(lhs, playerSupport: playerSupport) < peerSupportScore(rhs, playerSupport: playerSupport)
            } ?? eligible[0]
            return SensoryPeerCue(
                id: "support-\(mate.id)-\(soundscape.dominantKind?.rawValue ?? "ambient")",
                classmateID: mate.id,
                classmateName: mate.name,
                direction: peerDirection(for: mate),
                tone: .support,
                surfaceSignal: mate.profile.signalReaction,
                spokenLine: allowsWhispering ? "低声问：要不要我帮你看一下？" : "把纸角往你这边推了一点，像是在问你还好吗。",
                lowPressureAction: allowsWhispering ? "可以用一句很短的低声回应。" : "可以用纸条回应，别让动作变大。",
                audioKind: allowsWhispering ? .whisper : .paper,
                audioIntensity: (0.38 + soundscape.supportSignal * 0.32).clamped(to: 0.28...0.72)
            )
        }

        if soundscape.bodyAlarm >= 0.52 {
            let mate = eligible.max { lhs, rhs in
                let lhsScore = lhs.profile.empathy + lhs.profile.anxiety * 0.35 + lhs.relationship * 0.2
                let rhsScore = rhs.profile.empathy + rhs.profile.anxiety * 0.35 + rhs.relationship * 0.2
                return lhsScore < rhsScore
            } ?? eligible[0]
            return SensoryPeerCue(
                id: "body-\(mate.id)-\(soundscape.dominantKind?.rawValue ?? "ambient")",
                classmateID: mate.id,
                classmateName: mate.name,
                direction: peerDirection(for: mate),
                tone: .body,
                surfaceSignal: mate.profile.signalReaction,
                spokenLine: "没有直接看你，只把水杯往桌边挪近了一点。",
                lowPressureAction: "先呼吸或喝水，让身体报警声降下来。",
                audioKind: .paper,
                audioIntensity: (0.34 + soundscape.bodyAlarm * 0.28).clamped(to: 0.28...0.68)
            )
        }

        if soundscape.riskPressure >= 0.62 {
            let mate = eligible.max { lhs, rhs in
                peerWarningScore(lhs) < peerWarningScore(rhs)
            } ?? eligible[0]
            return SensoryPeerCue(
                id: "warning-\(mate.id)-\(soundscape.dominantKind?.rawValue ?? "ambient")",
                classmateID: mate.id,
                classmateName: mate.name,
                direction: peerDirection(for: mate),
                tone: .warning,
                surfaceSignal: mate.profile.signalReaction,
                spokenLine: "几乎不动嘴唇地说：先别动，脚步在旁边。",
                lowPressureAction: "把视线收回前方，等脚步声位置稳定。",
                audioKind: .whisper,
                audioIntensity: (0.36 + soundscape.riskPressure * 0.34).clamped(to: 0.32...0.78)
            )
        }

        if soundscape.institutionalPressure >= 0.48 {
            let mate = eligible.max { lhs, rhs in
                let lhsScore = lhs.profile.orderliness + lhs.stress * 0.28
                let rhsScore = rhs.profile.orderliness + rhs.stress * 0.28
                return lhsScore < rhsScore
            } ?? eligible[0]
            return SensoryPeerCue(
                id: "institution-\(mate.id)-\(soundscape.dominantKind?.rawValue ?? "ambient")",
                classmateID: mate.id,
                classmateName: mate.name,
                direction: peerDirection(for: mate),
                tone: .institution,
                surfaceSignal: mate.profile.signalReaction,
                spokenLine: "把作业本往中间收了收，全班都在等广播过去。",
                lowPressureAction: "只做短、轻、能解释的动作。",
                audioKind: .paper,
                audioIntensity: (0.32 + soundscape.institutionalPressure * 0.28).clamped(to: 0.26...0.66)
            )
        }

        return nil
    }

    private static func peerDirection(for classmate: Classmate) -> String {
        if classmate.seat.row == 2, classmate.seat.column == 0 { return "左侧同桌" }
        if classmate.seat.row == 2, classmate.seat.column == 2 { return "右侧同桌" }
        if classmate.seat.row < 2 { return classmate.seat.column <= 1 ? "前方左侧" : "前方右侧" }
        if classmate.seat.row > 2 { return classmate.seat.column <= 1 ? "后方左侧" : "后方右侧" }
        return classmate.seat.column <= 1 ? "左侧近处" : "右侧近处"
    }

    private static func peerSupportScore(_ classmate: Classmate, playerSupport: Double) -> Double {
        let deskmateBonus = classmate.seat.row == 2 && (classmate.seat.column == 0 || classmate.seat.column == 2) ? 22.0 : 0
        return classmate.profile.empathy * 0.9
            + classmate.relationship * 0.62
            + classmate.support * 0.24
            + playerSupport * 0.12
            + deskmateBonus
            - classmate.stress * 0.12
    }

    private static func peerWarningScore(_ classmate: Classmate) -> Double {
        classmate.profile.orderliness * 0.48
            + classmate.profile.anxiety * 0.42
            + classmate.stress * 0.38
            + classmate.relationship * 0.12
    }
}

struct AudioAssetStatus {
    let cueAvailable: Int
    let cueTotal: Int
    let loopAvailable: Int
    let loopTotal: Int
    let missingCues: [String]
    let missingLoops: [String]

    var summary: String {
        "短音 \(cueAvailable)/\(cueTotal) · 环境 \(loopAvailable)/\(loopTotal)"
    }

    var missingTotal: Int {
        (cueTotal - cueAvailable) + (loopTotal - loopAvailable)
    }

    var missingSummary: String {
        missingTotal == 0 ? "素材完整" : "缺 \(missingTotal)"
    }

    var missingDetail: String {
        guard missingTotal > 0 else { return "真实音频素材已完整接入。" }
        let cueText = missingCues.isEmpty ? "" : "短音缺失：\(missingCues.joined(separator: ", "))"
        let loopText = missingLoops.isEmpty ? "" : "环境缺失：\(missingLoops.joined(separator: ", "))"
        return [cueText, loopText].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    var hasAnyRealAsset: Bool {
        cueAvailable + loopAvailable > 0
    }
}
