import Foundation
import SceneKit

enum GameState: Equatable {
    case menu
    case playing
    case event(ActiveEvent)
    case ending(Ending)
}

enum ActiveEventKind: Equatable {
    case discovery
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

struct InnerMonologue: Identifiable {
    let id = UUID()
    let turn: Int
    let text: String
    let intensity: Double
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

enum CameraPose: String, CaseIterable {
    case forward = "前方"
    case desk = "低头"
    case board = "抬头"
    case left = "左侧"
    case right = "右侧"

    var angles: SCNVector3 {
        switch self {
        case .forward: return SCNVector3(0, 0, 0)
        case .desk: return SCNVector3(-0.62, 0, 0)
        case .board: return SCNVector3(0.22, 0, 0)
        case .left: return SCNVector3(0, 0.86, 0)
        case .right: return SCNVector3(0, -0.86, 0)
        }
    }

    var visionZone: VisionZone {
        switch self {
        case .board: return .upper
        case .forward: return .middle
        case .desk: return .desk
        case .left: return .leftPeripheral
        case .right: return .rightPeripheral
        }
    }

    var shortcut: Character {
        switch self {
        case .forward: return "w"
        case .desk: return "s"
        case .board: return "e"
        case .left: return "a"
        case .right: return "d"
        }
    }
}

enum VisionZone: String {
    case upper = "A区"
    case middle = "B区"
    case desk = "C区"
    case leftPeripheral = "D区"
    case rightPeripheral = "E区"

    var displayName: String {
        switch self {
        case .upper: return "上方远景"
        case .middle: return "中景"
        case .desk: return "桌面近景"
        case .leftPeripheral: return "左侧余光"
        case .rightPeripheral: return "右侧余光"
        }
    }

    var attentionCost: Double {
        switch self {
        case .upper: return 30
        case .middle: return 10
        case .desk: return 5
        case .leftPeripheral, .rightPeripheral: return 0
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
        case .snack: return "8"
        case .leaveSeat: return "9"
        }
    }
}

enum PlayerPosture: String {
    case seated = "坐着"
    case standing = "站起"
}

enum TeacherAction: String, CaseIterable, Identifiable {
    case patrol = "巡视"
    case warn = "提醒"
    case ignore = "选择性放过"
    case care = "关心"
    case rest = "坐下休息"
    case rearDoorObserve = "后门观察"
    case fakePatrol = "假巡视"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .patrol: return "figure.walk"
        case .warn: return "exclamationmark.bubble.fill"
        case .ignore: return "eye.slash.fill"
        case .care: return "heart.text.square.fill"
        case .rest: return "chair.fill"
        case .rearDoorObserve: return "door.left.hand.closed"
        case .fakePatrol: return "shoeprints.fill"
        }
    }

    var shortcut: Character {
        switch self {
        case .patrol: return "1"
        case .warn: return "2"
        case .ignore: return "3"
        case .care: return "4"
        case .rest: return "5"
        case .rearDoorObserve: return "6"
        case .fakePatrol: return "7"
        }
    }
}

struct PlayerState {
    var psychicEnergy: Double = 72
    var maskCost: Double = 24
    var support: Double = 38
    var stress: Double = 30
    var exposure: Double = 18
    var visualAttention: Double = 86
    var focusQuality: Double = 1
    var posture: PlayerPosture = .seated
    var homework: Double = 0
    var hunger: Double = 28
    var bladder: Double = 18
    var helpedClassmate: Bool = false
    var teacherWarnings: Int = 0
    var teacherCareMoments: Int = 0

    var breakdownRisk: Double {
        max(0, stress + maskCost * 0.45 + exposure * 0.25 - psychicEnergy - support * 0.18)
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

struct SupportResource: Equatable, Identifiable {
    let id = UUID()
    let title: String
    let detail: String
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
    case knock = "敲门"
    case stomach = "肚子"
    case wrapper = "包装纸"
    case teacherCough = "咳嗽"
    case teacherSigh = "叹气"
}

struct AudioCue: Identifiable {
    let id = UUID()
    let turn: Int
    let kind: AudioCueKind
    let direction: String
    let intensity: Double
    let note: String
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
