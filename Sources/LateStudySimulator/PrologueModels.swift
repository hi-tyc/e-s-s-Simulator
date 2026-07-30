import Foundation

enum PrologueBeatID: String, Codable, CaseIterable {
    case gateArrival
    case lookDownHall
    case returnToSeat
    case placeWater
    case studyHallRhythm
    case noticeLinChe
    case settleBreath
    case accessibility
    case bellBeforeClass

    var mainTask: String { "熟悉晚自习开始前的教室" }

    var currentGoal: String {
        switch self {
        case .gateArrival: return "走进教学楼"
        case .lookDownHall: return "看向走廊尽头"
        case .returnToSeat: return "回到第三排座位"
        case .placeWater: return "把水杯放到桌上"
        case .studyHallRhythm: return "留在座位，听教室安静下来"
        case .noticeLinChe: return "看看左边的林澈"
        case .settleBreath: return "试着深呼吸一次"
        case .accessibility: return "确认你可以随时调整体验"
        case .bellBeforeClass: return "等待晚自习开始"
        }
    }

    var hint: String? {
        switch self {
        case .gateArrival: return "脚步会带你进入教学楼"
        case .lookDownHall: return "移动鼠标或使用视角键"
        case .returnToSeat: return "使用 WASD，或等待苏念自己走回去"
        case .placeWater: return "看向桌面，按空格确认"
        case .studyHallRhythm: return "你可以转头、暂停或调整字幕"
        case .noticeLinChe: return "先看见，不急着判断"
        case .settleBreath: return "不想操作也没关系，先坐一会儿"
        case .accessibility: return "字幕、声音、动态效果和输入方式都能调整"
        case .bellBeforeClass: return "预备铃快响了"
        }
    }

    var allowsLook: Bool {
        switch self {
        case .lookDownHall, .studyHallRhythm, .noticeLinChe, .bellBeforeClass: return true
        default: return false
        }
    }

    var allowsMovement: Bool { self == .returnToSeat }
    var allowsConfirmation: Bool { self == .placeWater || self == .accessibility }
}

struct PrologueBeatEcho: Codable, Equatable {
    var beat: PrologueBeatID
    var source: PrologueCompletionSource

    var title: String {
        switch (beat, source) {
        case (.lookDownHall, .fallback):
            return "你注意到了走廊里的动静"
        case (.lookDownHall, .player):
            return "视线落到了走廊尽头"
        case (.lookDownHall, .performance):
            return "走廊尽头被看见了"
        case (.gateArrival, _):
            return "你走进了教学楼"
        case (.returnToSeat, .fallback):
            return "苏念回到了第三排"
        case (.returnToSeat, .player):
            return "你回到了第三排座位"
        case (.returnToSeat, .performance):
            return "第三排座位接住了视角"
        case (.placeWater, _):
            return "水杯放在手边"
        case (.studyHallRhythm, _):
            return "教室慢慢安静下来"
        case (.noticeLinChe, .fallback):
            return "你看见了林澈的安静"
        case (.noticeLinChe, .player):
            return "你注意到了左侧的林澈"
        case (.noticeLinChe, .performance):
            return "左侧的安静被看见了"
        case (.settleBreath, .fallback):
            return "你先坐了一会儿"
        case (.settleBreath, .player):
            return "呼吸慢慢稳下来"
        case (.settleBreath, .performance):
            return "呼吸留在原处"
        case (.accessibility, _):
            return "体验设置已确认"
        case (.bellBeforeClass, _):
            return "晚自习开始了"
        }
    }

    var detail: String {
        switch (beat, source) {
        case (.lookDownHall, .fallback):
            return "苏念自然转头，走廊尽头的低声交代被你接住。"
        case (.lookDownHall, .player):
            return "方老师和班长的低声交代被你接住。"
        case (.lookDownHall, .performance):
            return "走廊尽头的低声交代进入了苏念的视野。"
        case (.gateArrival, _):
            return "球场声音留在身后，楼道灯把人群收进来。"
        case (.returnToSeat, .fallback):
            return "没有操作失败，脚步还是把你带回自己的位置。"
        case (.returnToSeat, .player):
            return "走廊退到身后，座位重新成为你的视角锚点。"
        case (.returnToSeat, .performance):
            return "镜头收回第三排，晚自习的距离重新成立。"
        case (.placeWater, _):
            return "等会儿脑子很乱时，至少不用再找它。"
        case (.studyHallRhythm, _):
            return "翻页、椅子和门轴的声音一点点沉下去。"
        case (.noticeLinChe, .fallback):
            return "这只是看见，不是判断。"
        case (.noticeLinChe, .player):
            return "你先记住他的停顿，不急着解释。"
        case (.noticeLinChe, .performance):
            return "镜头没有停留太久，只把异常留给后面的章节。"
        case (.settleBreath, .fallback):
            return "苏念没有把沉默当成错误。"
        case (.settleBreath, .player):
            return "这一口气不改变世界，但让你还在这里。"
        case (.settleBreath, .performance):
            return "呼吸没有变成任务，只在座位上落下来。"
        case (.accessibility, _):
            return "字幕、声音、动态效果和输入方式会跟随存档。"
        case (.bellBeforeClass, _):
            return "预备铃之后，第一章目标在同一帧接管。"
        }
    }

    var symbol: String {
        switch beat {
        case .gateArrival: return "door.left.hand.open"
        case .lookDownHall: return "eye"
        case .returnToSeat: return "figure.walk.arrival"
        case .placeWater: return "drop.fill"
        case .studyHallRhythm: return "waveform"
        case .noticeLinChe: return "person.crop.circle"
        case .settleBreath: return "wind"
        case .accessibility: return "accessibility"
        case .bellBeforeClass: return "bell.fill"
        }
    }
}

struct PrologueLookTargetSignal: Equatable {
    var isVisible: Bool
    var isHighlighted: Bool
    var opacity: Double
    var scale: Double
    var emissionIntensity: Double
    var lightIntensity: Double
    var labelOpacity: Double

    init(
        isPrologueActive: Bool,
        currentBeat: PrologueBeatID,
        lastBeatEcho: PrologueBeatEcho?,
        cameraPose: CameraPose,
        studentLookYaw: Double
    ) {
        let isLookBeat = currentBeat == .lookDownHall
        let wasConfirmed = lastBeatEcho?.beat == .lookDownHall
        let isAimedAtHall = cameraPose == .right || abs(studentLookYaw) > 0.42
        isVisible = isPrologueActive && (isLookBeat || wasConfirmed)
        isHighlighted = isAimedAtHall || wasConfirmed
        opacity = isVisible ? (isHighlighted ? 0.96 : 0.42) : 0
        scale = isHighlighted ? 1.12 : 0.92
        emissionIntensity = isHighlighted ? 1.15 : 0.42
        lightIntensity = isHighlighted ? 210 : 80
        labelOpacity = isHighlighted ? 0.92 : 0.58
    }
}

struct PrologueGateArrivalSignal: Equatable {
    static let duration: Double = 55
    static let stepCount = 7

    var isVisible: Bool
    var progress: Double
    var litStepCount: Int
    var entranceGlow: Double
    var studentZ: Double

    init(isPrologueActive: Bool, currentBeat: PrologueBeatID, elapsed: Double) {
        isVisible = isPrologueActive && currentBeat == .gateArrival
        progress = isVisible ? (elapsed / Self.duration).clamped(to: 0...1) : 0
        litStepCount = isVisible ? min(Self.stepCount, max(1, Int((progress * Double(Self.stepCount)).rounded(.up)))) : 0
        entranceGlow = isVisible ? (0.18 + progress * 0.82) : 0
        studentZ = 15.55 + (6.72 - 15.55) * progress
    }
}

struct PrologueState: Codable, Equatable {
    var openingViewed = false
    var lookTutorialCompleted = false
    var movementTutorialCompleted = false
    var interactionTutorialCompleted = false
    var accessibilityTutorialAcknowledged = false
    var prologueCompleted = false
    var completedBeats: Set<PrologueBeatID> = []
    var currentBeat: PrologueBeatID = .gateArrival
    var lastBeatEcho: PrologueBeatEcho?
}

struct AccessibilityPreferences: Codable, Equatable {
    var directionalSubtitles = true
    var dialogueVolume = 0.7
    var ambienceVolume = 0.7
    var cueVolume = 0.7
    var reduceMotion = false
    var keyboardAlternativeInput = true
}

enum PrologueCompletionSource: String, Codable {
    case player
    case fallback
    case performance
}

enum ProloguePauseReason: String, Hashable {
    case manual
    case settings
    case appInactive
}
