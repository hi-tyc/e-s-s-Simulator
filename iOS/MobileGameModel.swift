import Foundation
import UIKit

enum MobileGameScreen: Equatable {
    case menu
    case prologue
    case playing
    case ending
}

enum MobilePlayMode: String, CaseIterable, Identifiable {
    case student = "学生视角"
    case teacher = "教师视角"
    var id: Self { self }
    var icon: String { self == .student ? "person.fill" : "person.crop.rectangle.fill" }
}

struct MobileClassmate: Identifiable, Equatable {
    let id: Int
    let name: String
    var state: String
    var stress: Int
    var relationship: Int
}

struct MobileEvent: Identifiable, Equatable {
    let id: UUID
    let title: String
    let body: String
    let choices: [String]
}

struct MobileSnapshot: Identifiable, Equatable {
    let id: Int
    let turn: Int
    let action: String
    let surface: String
    let innerTruth: String
}

enum MobileLookDirection: String, CaseIterable, Identifiable {
    case left = "左侧"
    case front = "前方"
    case right = "右侧"
    case desk = "桌面"
    case rear = "后方"

    var id: Self { self }

    var symbol: String {
        switch self {
        case .left: return "arrow.left"
        case .front: return "arrow.up"
        case .right: return "arrow.right"
        case .desk: return "arrow.down"
        case .rear: return "arrow.uturn.backward"
        }
    }
}

enum MobileAction: String, CaseIterable, Identifiable {
    case observe = "观察"
    case study = "写作业"
    case breathe = "深呼吸"
    case talk = "低声问候"
    case drink = "喝水"
    case note = "查看纸条"
    case leaveSeat = "起身跟上"

    var id: Self { self }

    var symbol: String {
        switch self {
        case .observe: return "eye.fill"
        case .study: return "book.fill"
        case .breathe: return "wind"
        case .talk: return "bubble.left.fill"
        case .drink: return "drop.fill"
        case .note: return "note.text"
        case .leaveSeat: return "figure.walk"
        }
    }
}

private struct HiddenStudentState {
    var energy = 74.0
    var pressure = 31.0
    var focus = 82.0
    var maskCost = 18.0
    var support = 44.0
    var water = 2

    mutating func clamp() {
        energy = energy.clamped(to: 0...100)
        pressure = pressure.clamped(to: 0...100)
        focus = focus.clamped(to: 0...100)
        maskCost = maskCost.clamped(to: 0...100)
        support = support.clamped(to: 0...100)
    }
}

@MainActor
final class MobileGameManager: ObservableObject {
    @Published private(set) var screen: MobileGameScreen = .menu
    @Published private(set) var direction: MobileLookDirection = .front
    @Published private(set) var chapterStep = 0
    @Published private(set) var prologueStep = 0
    @Published private(set) var elapsedMinutes = 0
    @Published private(set) var message = "预备铃刚停。教室里的声音一层层沉下去。"
    @Published private(set) var monologue: String?
    @Published private(set) var discoveredClues: Set<Int> = []
    @Published private(set) var lastAction: MobileAction?
    @Published private(set) var isPaused = false
    @Published var playMode: MobilePlayMode = .student
    @Published var studyHours = 3.0
    @Published var rankingPressure = 70.0
    @Published var patrolFrequency = 65.0
    @Published private(set) var classmates: [MobileClassmate] = []
    @Published private(set) var snapshots: [MobileSnapshot] = []
    @Published private(set) var activeEvent: MobileEvent?
    @Published private(set) var teacherTrust = 34
    @Published private(set) var teacherKPI = 66

    private var state = HiddenStudentState()
    private var actionsTaken = 0
    private var clockTask: Task<Void, Never>?
    private var isActive = true
    private let impact = UIImpactFeedbackGenerator(style: .light)
    private let notification = UINotificationFeedbackGenerator()

    let goals = [
        "看向左侧，留意林澈停住的书页",
        "看向右侧，辨认环境声里的异样",
        "先照顾好自己，让呼吸慢下来",
        "在下课前，用低压力方式问候林澈",
        "低头确认滑到桌边的匿名纸条",
        "起身跟上已经走向门口的林澈"
    ]

    var currentGoal: String {
        goals[min(chapterStep, goals.count - 1)]
    }

    var clockText: String {
        let total = 18 * 60 + 30 + elapsedMinutes
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    var sensoryStatus: String {
        if state.pressure > 72 { return "呼吸变浅，灯光像贴得更近了" }
        if state.focus < 38 { return "视线开始发散，翻页声忽远忽近" }
        if state.energy < 32 { return "肩膀很沉，笔尖一次次停住" }
        if state.maskCost > 62 { return "维持若无其事正在变得费力" }
        return "呼吸平稳，周围的声音还能分辨"
    }

    var availableActions: [MobileAction] {
        if playMode == .teacher { return [] }
        var actions: [MobileAction] = [.observe, .study, .breathe, .drink]
        if chapterStep >= 3 { actions.append(.talk) }
        if chapterStep >= 4 { actions.append(.note) }
        if chapterStep >= 5 { actions.append(.leaveSeat) }
        return actions
    }

    var availableTeacherActions: [String] {
        ["看全班", "低声提醒", "关心询问", "公开提醒", "选择性放过", "坐下休息"]
    }

    var endingSummary: String {
        if state.support >= 55 {
            return "你没有急着替林澈下结论，只是让她知道今晚不必独自离开。"
        }
        return "你终于跟上了那道身影。纸条的来源仍未确定，但调查从一次不带评判的陪伴开始。"
    }

    func start() {
        state = HiddenStudentState()
        actionsTaken = 0
        chapterStep = 0
        elapsedMinutes = 0
        direction = .front
        message = "预备铃刚停。教室里的声音一层层沉下去。"
        monologue = nil
        discoveredClues = []
        lastAction = nil
        activeEvent = nil
        snapshots = []
        teacherTrust = 34
        teacherKPI = Int(rankingPressure)
        classmates = [
            MobileClassmate(id: 0, name: "林澈", state: "安静翻页", stress: 62, relationship: 54),
            MobileClassmate(id: 1, name: "周予安", state: "核对座位", stress: 38, relationship: 42),
            MobileClassmate(id: 2, name: "许栀", state: "低头写题", stress: 46, relationship: 48),
            MobileClassmate(id: 3, name: "江越", state: "空位", stress: 71, relationship: 36),
            MobileClassmate(id: 4, name: "陈言", state: "看向讲台", stress: 33, relationship: 40)
        ]
        isPaused = false
        isActive = true
        startClock()
        screen = .playing
    }

    func startPrologue() {
        prologueStep = 0
        direction = .front
        message = "教学楼的灯还没有全部亮起来。你先站在门口，听见里面有人翻书。"
        screen = .prologue
    }

    func continuePrologue() {
        guard screen == .prologue else { return }
        prologueStep += 1
        if prologueStep >= 3 {
            start()
        } else {
            let beats = [
                "走廊尽头有人把门掩上。你认出那是晚自习的教室。",
                "你在第三排坐下，把水杯放到手边。铃声快要响了。"
            ]
            message = beats[prologueStep - 1]
        }
    }

    func startTeacherMode() {
        playMode = .teacher
        start()
        message = "你站在讲台边。今晚既要维持秩序，也要辨认真正的求助。"
    }

    func returnToMenu() {
        clockTask?.cancel()
        screen = .menu
        monologue = nil
    }

    func look(_ newDirection: MobileLookDirection) {
        direction = newDirection
        switch newDirection {
        case .left: message = "左边的林澈没有翻页。她的手指压在同一行字上。"
        case .right: message = "右侧空位旁传来一声很轻的吸气，很快被风扇盖住。"
        case .desk: message = "作业纸边缘翘起，桌沿下似乎压着另一张纸。"
        case .rear: message = "班长回头看了一眼，又把要说的话咽了回去。"
        case .front: message = "方老师站在讲台边，揉了揉眉心，没有立刻开口。"
        }
    }

    func perform(_ action: MobileAction) {
        guard screen == .playing else { return }
        guard isPaused == false else { return }
        impact.impactOccurred(intensity: action == .breathe ? 0.55 : 0.3)
        lastAction = action
        actionsTaken += 1
        elapsedMinutes += action == .study ? 8 : 4

        switch action {
        case .observe:
            state.focus -= 5
            state.pressure += direction == .rear ? 8 : 2
            advanceObservationIfMatched()
        case .study:
            state.energy -= 8
            state.focus -= 6
            state.maskCost += 4
            message = "笔尖继续向前，教室恢复了表面的秩序。"
        case .breathe:
            state.pressure -= 18
            state.focus += 13
            state.maskCost -= 8
            state.energy += 5
            message = "你把脚踩实地面。吸气，停一拍，再慢慢呼出去。"
            if chapterStep == 2 { advance(with: "先稳住自己，不等于忽略别人。") }
        case .drink:
            if state.water > 0 {
                state.water -= 1
                state.pressure -= 8
                state.focus += 6
                message = "水不算凉，但吞咽的动作让呼吸重新有了节奏。"
                if chapterStep == 2 { advance(with: "身体被照顾到以后，声音也清楚了一点。") }
            } else {
                message = "杯子已经空了。你把它轻轻放回桌角。"
            }
        case .talk:
            guard chapterStep == 3 else {
                message = "现在还不是开口的时机。先确认自己真正看见了什么。"
                break
            }
            state.support += 18
            state.maskCost -= 6
            state.pressure += 4
            advance(with: "“要不要一起去接点水？”你没有追问，她轻轻点了点头。")
        case .note:
            guard chapterStep == 4, direction == .desk else {
                message = "纸条藏在桌边。先低头，再确认它写了什么。"
                break
            }
            state.pressure += 10
            discoveredClues.insert(4)
            advance(with: "纸上只有一句：别让她一个人走。没有署名。")
        case .leaveSeat:
            guard chapterStep == 5 else { break }
            message = "椅脚轻响。你没有喊住她，只是保持几步距离跟了出去。"
            state.support += 12
            state.clamp()
            notification.notificationOccurred(.success)
            screen = .ending
        }

        state.energy -= 1.5
        state.focus -= 1
        state.pressure += actionsTaken > 7 ? 1.5 : 0.5
        state.clamp()
        recordSnapshot(action: action.rawValue)
        maybeTriggerEvent()
        updateMonologueIfNeeded()
    }

    func resolveEvent(choice: String) {
        guard activeEvent != nil else { return }
        switch choice {
        case "靠近陪伴": state.support += 12; state.pressure -= 8
        case "告诉老师": teacherTrust += 7; teacherKPI += 2
        case "先不打扰": state.pressure += 4
        default: break
        }
        state.clamp()
        message = choice == "靠近陪伴" ? "你把声音压得很低，给她留出可以拒绝的空间。" : "你记下这个信号，决定用自己能承受的方式回应。"
        activeEvent = nil
    }

    func performTeacherAction(_ title: String) {
        guard playMode == .teacher, activeEvent == nil else { return }
        elapsedMinutes += 5
        switch title {
        case "看全班": teacherKPI += 2; message = "你扫过每一排，先看到的是疲惫，不是违规。"
        case "低声提醒": teacherKPI += 1; teacherTrust += 3; message = "你走到桌边，提醒被压在只有两个人听见的音量里。"
        case "关心询问": teacherKPI -= 1; teacherTrust += 10; message = "你没有先问作业，而是问：今晚是不是有点难？"
        case "公开提醒": teacherKPI += 5; teacherTrust -= 8; message = "教室短暂安静下来，但每个人都更用力地藏起了自己。"
        case "选择性放过": teacherKPI -= 2; teacherTrust += 2; message = "你看见了，却决定暂时不把它变成一条纪律记录。"
        default: message = "你在讲台边停了一会儿，让教室重新找到节奏。"
        }
        teacherKPI = min(100, max(0, teacherKPI))
        teacherTrust = min(100, max(0, teacherTrust))
        if teacherKPI > 88 || elapsedMinutes >= Int(studyHours * 60) { screen = .ending }
    }

    func dismissMonologue() {
        monologue = nil
    }

    func setActive(_ active: Bool) {
        isActive = active
        isPaused = screen == .playing && active == false
        if active && screen == .playing { startClock() }
        if active == false { clockTask?.cancel() }
    }

    private func startClock() {
        clockTask?.cancel()
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.isActive, self.screen == .playing, self.isPaused == false else { return }
                    self.elapsedMinutes += 1
                }
            }
        }
    }

    private func advanceObservationIfMatched() {
        if chapterStep == 0, direction == .left {
            discoveredClues.insert(0)
            advance(with: "她不是在发呆。她像是在努力让自己看起来仍然在读。")
        } else if chapterStep == 1, direction == .right {
            discoveredClues.insert(1)
            advance(with: "那不是咳嗽。有人在尽量不让抽泣发出声音。")
        } else {
            message = "你多看了一会儿，但还不能确定这意味着什么。"
        }
    }

    private func advance(with newMessage: String) {
        message = newMessage
        chapterStep = min(chapterStep + 1, goals.count - 1)
    }

    private func updateMonologueIfNeeded() {
        guard monologue == nil else { return }
        if state.pressure > 76 {
            monologue = "我是不是也在努力装作什么都没有发生？"
        } else if state.focus < 34 {
            monologue = "字还在纸上，可我已经读不进去了。"
        } else if state.energy < 30 {
            monologue = "先停一下也可以。我不需要用耗尽自己来证明认真。"
        }
    }

    private func recordSnapshot(action: String) {
        let truth = state.pressure > 65 ? "身体先替你承认了疲惫" : "你仍在努力保持表面的稳定"
        snapshots.append(MobileSnapshot(id: snapshots.count, turn: actionsTaken, action: action, surface: message, innerTruth: truth))
        if snapshots.count > 24 { snapshots.removeFirst() }
    }

    private func maybeTriggerEvent() {
        guard activeEvent == nil, playMode == .student else { return }
        guard actionsTaken > 2, actionsTaken % 4 == 0 else { return }
        if state.pressure > 58 {
            activeEvent = MobileEvent(id: UUID(), title: "纸页边缘的求助", body: "林澈把一小段草稿纸推到你手边，又立刻收回手。她没有看你。", choices: ["靠近陪伴", "告诉老师", "先不打扰"])
        }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
