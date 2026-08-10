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

    static let tutorialBeats: [PrologueBeatID] = [
        .lookDownHall, .returnToSeat, .placeWater, .studyHallRhythm,
        .noticeLinChe, .settleBreath, .accessibility, .bellBeforeClass
    ]

    var tutorialStep: Int? {
        Self.tutorialBeats.firstIndex(of: self).map { $0 + 1 }
    }

    var autoAdvanceDuration: TimeInterval? {
        switch self {
        case .gateArrival: return 7
        case .lookDownHall: return nil
        case .returnToSeat: return 50
        case .placeWater: return 20
        case .studyHallRhythm: return 30
        case .noticeLinChe: return 15
        case .settleBreath: return 15
        case .accessibility: return 50
        case .bellBeforeClass: return 7
        }
    }

    var tutorialInstruction: String {
        switch self {
        case .gateArrival:
            return "正在进入教学楼。"
        case .lookDownHall:
            return "现在让我们熟悉如何控制视角。移动鼠标即可控制转动视角，按下 ～ 键即可释放鼠标，再按一次恢复控制。你的鼠标现在是释放状态，需要先按 ～ 获取控制。请环视周围，累计移动视角 5 秒；视角不动时计时会暂停。此步骤不能用 C 跳过。"
        case .returnToSeat:
            return "使用 WASD 进行移动，鼠标控制方向。\n\n按住 Shift 可以侧身行走，碰撞体积更小，但是走得会慢；按住 Control 可以快速奔跑，会增加一点饥饿值。\n\n请走回第三排自己的座位，靠近座位后按 E 入座。完成入座前不能用 C 跳过；暂时不操作也会在倒计时结束后自动继续。"
        case .placeWater:
            return "先把水杯放到桌上，做好晚自习的一切准备。单击 E 键即可完成操作，游戏里的其他交互也都是 E 键。放好后会解锁 C，可以提前结束剩余倒计时。"
        case .studyHallRhythm:
            return "留在座位观察教室。你仍可移动鼠标环顾四周，也可以按 ～ 键暂时释放鼠标。"
        case .noticeLinChe:
            return "向左转动视角，找到林澈并稍作停留。先观察，不需要立刻作出判断。"
        case .settleBreath:
            return "点击“深呼吸”完成一次自我调整，也可以选择先坐一会儿。深呼吸可以有效降低压力和面具成本，恢复注意力，帮助调整状态。完成后会解锁 C。"
        case .accessibility:
            return "你可以调整字幕、声音、动态效果和输入方式。点击“调整体验”即可。你也可以选择不调整，点击“继续”。在之后的游戏中可以随时点击 Esc 键进行调整；确认后会解锁 C。"
        case .bellBeforeClass:
            return "自由观察铃响前的教室。倒计时结束后序章会自动进入第一章。"
        }
    }

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
        case .placeWater: return "看向桌面，按 E 确认"
        case .studyHallRhythm: return "你可以转头、暂停或调整字幕"
        case .noticeLinChe: return "先看见，不急着判断"
        case .settleBreath: return "不想操作也没关系，先坐一会儿"
        case .accessibility: return "字幕、声音、动态效果和输入方式都能调整"
        case .bellBeforeClass: return "预备铃快响了"
        }
    }

    var allowsLook: Bool {
        switch self {
        case .lookDownHall, .returnToSeat, .studyHallRhythm, .noticeLinChe, .bellBeforeClass: return true
        default: return false
        }
    }

    var allowsMovement: Bool { self == .returnToSeat }
    var allowsConfirmation: Bool { self == .placeWater || self == .accessibility }
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
    case tutorial
    case appInactive
}
