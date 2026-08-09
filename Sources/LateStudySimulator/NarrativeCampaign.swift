import SwiftUI

enum NarrativeChapter: Int, Codable, CaseIterable, Identifiable, Hashable {
    case classroom = 1
    case mirror
    case noteTrace
    case stairwell
    case counseling
    case epilogue

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .classroom: return "第一章  静音的教室"
        case .mirror: return "第二章  走廊的镜子"
        case .noteTrace: return "第三章  那张纸条"
        case .stairwell: return "第四章  十三楼的缝隙"
        case .counseling: return "第五章  有灯亮着的房间"
        case .epilogue: return "第六章  这里有光"
        }
    }

    var atmosphere: Color {
        switch self {
        case .classroom: return Color(red: 0.12, green: 0.32, blue: 0.46)
        case .mirror: return Color(red: 0.30, green: 0.14, blue: 0.42)
        case .noteTrace: return Color(red: 0.22, green: 0.30, blue: 0.34)
        case .stairwell: return Color(red: 0.42, green: 0.22, blue: 0.16)
        case .counseling: return Color(red: 0.18, green: 0.40, blue: 0.34)
        case .epilogue: return Color(red: 0.53, green: 0.34, blue: 0.17)
        }
    }

    var sceneSubtitle: String {
        switch self {
        case .classroom: return "先听见，再判断"
        case .mirror: return "走廊会把每一次呼吸都放大"
        case .noteTrace: return "沿着纸条回到线索现场"
        case .stairwell: return "把位置说清楚，让成人接手"
        case .counseling: return "灯亮着，等待也有重量"
        case .epilogue: return "支持开始流向更多人"
        }
    }

    var sceneTransition: SceneTransition {
        switch self {
        case .classroom: return .fade
        case .mirror: return .mirrorRipple
        case .noteTrace: return .fade
        case .stairwell: return .colorTemperatureFlip
        case .counseling: return .fade
        case .epilogue: return .colorTemperatureFlip
        }
    }

    var audioSceneID: String {
        switch self {
        case .classroom: return "classroom"
        case .mirror: return "mirror"
        case .noteTrace: return "corridor"
        case .stairwell: return "stairwell"
        case .counseling: return "counseling"
        case .epilogue: return "epilogue"
        }
    }
}

enum SceneTransition: String, Codable, CaseIterable, Hashable {
    case fade
    case colorTemperatureFlip
    case mirrorRipple

    var symbolName: String {
        switch self {
        case .fade: return "circle.dashed"
        case .colorTemperatureFlip: return "sun.max.fill"
        case .mirrorRipple: return "sparkles"
        }
    }
}

enum ScenePresentationPhase: String, Codable, CaseIterable, Hashable {
    case prepare
    case commit
    case cleanup
    case idle
}

struct ScenePresentationState: Codable, Equatable {
    var chapter: NarrativeChapter = .classroom
    var title: String = ""
    var subtitle: String = ""
    var transition: SceneTransition = .fade
    var phase: ScenePresentationPhase = .idle
    var startedAt: Date = .distantPast
    var phaseStartedAt: Date = .distantPast
    var token = UUID()

    var isActive: Bool { phase != .idle }

    func phaseProgress(at date: Date = .now) -> Double {
        guard isActive else { return 0 }
        let elapsed = max(0, date.timeIntervalSince(phaseStartedAt))
        let duration: TimeInterval
        switch phase {
        case .prepare: duration = 0.78
        case .commit: duration = 0.86
        case .cleanup: duration = 0.66
        case .idle: duration = 0
        }
        guard duration > 0 else { return 0 }
        return min(1, elapsed / duration)
    }
}

struct ScenePresentationMotionProfile {
    static func phaseIntensity(
        for presentation: ScenePresentationState,
        reduceMotion: Bool,
        at date: Date = .now
    ) -> Double {
        guard presentation.isActive, reduceMotion == false else { return 0 }

        let progress = presentation.phaseProgress(at: date)
        switch presentation.phase {
        case .prepare:
            return 0.28 + progress * 0.72
        case .commit:
            return 1
        case .cleanup:
            return max(0, 1 - progress)
        case .idle:
            return 0
        }
    }
}

enum NarrativeSaveStoreKeys {
    static let current = "LateStudySimulator.NarrativeSave.v1.current"
    static let lastValid = "LateStudySimulator.NarrativeSave.v1.lastValid"
    static let legacyCampaign = "LateStudySimulator.NarrativeCampaign.v1"
}

enum NarrativeSaveValidationFailure: String, Codable, Equatable {
    case unsupportedSchemaVersion
    case transitionInProgress
    case sceneChapterMismatch
    case invalidMomentIndex
    case explorationChapterMismatch
    case completedCampaignOutsideEpilogue
    case counselingEntryMismatch
    case invalidChapterOneProgress

    var recoveryText: String {
        switch self {
        case .unsupportedSchemaVersion:
            return "存档版本暂不支持"
        case .transitionInProgress:
            return "存档落在转场中间帧"
        case .sceneChapterMismatch:
            return "章节与场景状态不一致"
        case .invalidMomentIndex:
            return "章节步骤索引无效"
        case .explorationChapterMismatch:
            return "探索位置属于另一个章节"
        case .completedCampaignOutsideEpilogue:
            return "完成态没有停在终章"
        case .counselingEntryMismatch:
            return "安全交接路线与咨询室入口不一致"
        case .invalidChapterOneProgress:
            return "第一章进度无效"
        }
    }
}

struct NarrativeChapterOneProgress: Codable, Equatable {
    var isFullNarrativeRun: Bool
    var currentTurn: Int
    var chapterOneStep: ChapterOneStep
    var chapterClues: [ChapterClue]
    var cameraPose: CameraPose
    var player: PlayerState
    var message: String
    var chapterOneDecision: String
    var hasPresentedChapterOneDecision: Bool
    var chapterOneLinCheDialogueCue: ChapterOneLinCheDialogueCue?
    var chapterOneNoteDropCue: ChapterOneNoteDropCue?
    var linChePerformanceCue: LinChePerformanceCue?
    var completedChapterOneBeatIDs: Set<String>?

    var isActive: Bool {
        isFullNarrativeRun && chapterOneStep != .completed
    }

    var checkpointID: String {
        "chapter.1.\(chapterOneStep.rawValue)"
    }
}

struct NarrativeSave: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var saveRevision: Int
    var checkpointID: String
    var campaign: NarrativeCampaign
    var chapterOneProgress: NarrativeChapterOneProgress?
    var accessibilityPreferences: AccessibilityPreferences
    var scenePresentation: ScenePresentationState
    var savedAt: Date

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case saveRevision
        case checkpointID
        case campaign
        case chapterOneProgress
        case accessibilityPreferences
        case scenePresentation
        case savedAt
    }

    init(
        schemaVersion: Int = NarrativeSave.currentSchemaVersion,
        saveRevision: Int,
        checkpointID: String? = nil,
        campaign: NarrativeCampaign,
        chapterOneProgress: NarrativeChapterOneProgress? = nil,
        accessibilityPreferences: AccessibilityPreferences = AccessibilityPreferences(),
        scenePresentation: ScenePresentationState = ScenePresentationState(),
        savedAt: Date = .now
    ) {
        self.schemaVersion = schemaVersion
        self.saveRevision = saveRevision
        self.checkpointID = checkpointID ?? NarrativeSave.checkpointID(for: campaign, chapterOneProgress: chapterOneProgress)
        self.campaign = campaign
        self.chapterOneProgress = chapterOneProgress
        self.accessibilityPreferences = accessibilityPreferences
        self.scenePresentation = NarrativeSave.stableScenePresentation(
            from: scenePresentation,
            campaign: campaign,
            chapterOneProgress: chapterOneProgress
        )
        self.savedAt = savedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        saveRevision = try container.decode(Int.self, forKey: .saveRevision)
        checkpointID = try container.decode(String.self, forKey: .checkpointID)
        campaign = try container.decode(NarrativeCampaign.self, forKey: .campaign)
        chapterOneProgress = try container.decodeIfPresent(NarrativeChapterOneProgress.self, forKey: .chapterOneProgress)
        accessibilityPreferences = try container.decodeIfPresent(AccessibilityPreferences.self, forKey: .accessibilityPreferences) ?? AccessibilityPreferences()
        scenePresentation = try container.decode(ScenePresentationState.self, forKey: .scenePresentation)
        savedAt = try container.decode(Date.self, forKey: .savedAt)
    }

    var validationFailure: NarrativeSaveValidationFailure? {
        if schemaVersion != NarrativeSave.currentSchemaVersion {
            return .unsupportedSchemaVersion
        }
        if scenePresentation.isActive {
            return .transitionInProgress
        }
        if let chapterOneProgress, chapterOneProgress.isActive {
            if chapterOneProgress.currentTurn <= 0 || chapterOneProgress.chapterClues.count > ChapterClueID.allCases.count {
                return .invalidChapterOneProgress
            }
            if campaign.isActive {
                return .sceneChapterMismatch
            }
            if scenePresentation.chapter != .classroom {
                return .sceneChapterMismatch
            }
            return nil
        }
        if campaign.isActive, scenePresentation.chapter != campaign.chapter {
            return .sceneChapterMismatch
        }
        let moments = NarrativeCampaign.moments(for: campaign.chapter)
        if campaign.momentIndex < 0 || campaign.momentIndex >= moments.count {
            return .invalidMomentIndex
        }
        if campaign.isActive, campaign.exploration.chapter != campaign.chapter {
            return .explorationChapterMismatch
        }
        if campaign.isComplete, campaign.chapter != .epilogue {
            return .completedCampaignOutsideEpilogue
        }
        if let handoffEntry = campaign.safetyHandoffState?.entryMode,
           let counselingEntry = campaign.counselingState?.entryMode,
           handoffEntry != counselingEntry {
            return .counselingEntryMismatch
        }
        return nil
    }

    var isValid: Bool { validationFailure == nil }

    static func checkpointID(
        for campaign: NarrativeCampaign,
        chapterOneProgress: NarrativeChapterOneProgress? = nil
    ) -> String {
        if let chapterOneProgress, chapterOneProgress.isActive {
            return chapterOneProgress.checkpointID
        }
        guard campaign.isActive else { return "menu" }
        if campaign.isComplete { return "chapter.6.complete" }
        let momentID = campaign.currentMoment.id
            .replacingOccurrences(of: ".", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        return "chapter.\(campaign.chapter.rawValue).\(momentID)"
    }

    static func stableScenePresentation(
        from scenePresentation: ScenePresentationState,
        campaign: NarrativeCampaign,
        chapterOneProgress: NarrativeChapterOneProgress? = nil
    ) -> ScenePresentationState {
        if let chapterOneProgress, chapterOneProgress.isActive {
            return ScenePresentationState(
                chapter: .classroom,
                title: NarrativeChapter.classroom.title,
                subtitle: chapterOneProgress.chapterOneStep.objective,
                transition: scenePresentation.chapter == .classroom ? scenePresentation.transition : .fade,
                phase: .idle,
                startedAt: .distantPast,
                phaseStartedAt: .distantPast
            )
        }
        guard campaign.isActive else {
            return ScenePresentationState()
        }
        let transition = scenePresentation.chapter == campaign.chapter
            ? scenePresentation.transition
            : campaign.chapter.sceneTransition
        return ScenePresentationState(
            chapter: campaign.chapter,
            title: campaign.chapter.title,
            subtitle: campaign.chapter.sceneSubtitle,
            transition: transition,
            phase: .idle,
            startedAt: .distantPast,
            phaseStartedAt: .distantPast
        )
    }
}

enum NarrativeMiniGame: String, Codable, CaseIterable {
    case trace
    case melody
    case erase

    var requiredInteractions: Int {
        switch self {
        case .trace: return 5
        case .melody: return 4
        case .erase: return 4
        }
    }

    var title: String {
        switch self {
        case .trace: return "草稿灯"
        case .melody: return "旋律灯"
        case .erase: return "擦痕灯"
        }
    }

    var symbolName: String {
        switch self {
        case .trace: return "pencil.line"
        case .melody: return "music.note"
        case .erase: return "eraser.fill"
        }
    }

    var completionRouteTitle: String {
        switch self {
        case .trace: return "让草稿灯把路接到旋律灯"
        case .melody: return "跟着旋律灯走到擦痕灯"
        case .erase: return "让三盏灯一起照回林澈身边"
        }
    }

    var completionRouteDetail: String {
        switch self {
        case .trace: return "第一段光路已经亮起，继续走向下一盏"
        case .melody: return "第二段回声已经接上，继续靠近最后一盏"
        case .erase: return "镜面正在褪色，回到真实的话里"
        }
    }

    var completionRouteSymbolName: String {
        switch self {
        case .trace: return "arrow.triangle.turn.up.right.diamond.fill"
        case .melody: return "waveform.path.ecg"
        case .erase: return "lightbulb.2.fill"
        }
    }
}

struct NarrativeExplorationState: Codable, Equatable {
    var isActive = true
    var chapter: NarrativeChapter = .mirror
    var positionX = 0.0
    var positionZ = 4.7
    var yaw = 0.0
    var pitch = -0.025
    var lastInteractedHotspot = ""
    var interactionCount = 0

    mutating func reset(for chapter: NarrativeChapter) {
        self = NarrativeExplorationState(chapter: chapter)
        switch chapter {
        case .classroom: isActive = false
        case .mirror: positionX = -0.22; positionZ = 4.7; pitch = -0.025
        case .noteTrace: positionX = 0.28; positionZ = 4.85; pitch = -0.08
        case .stairwell: positionX = -0.35; positionZ = 4.85; pitch = -0.1
        case .counseling: positionX = 0.32; positionZ = 3.9; pitch = -0.035
        case .epilogue: positionX = -0.18; positionZ = 4.25; pitch = -0.055
        }
    }

    mutating func move(forward: Double, strafe: Double, deltaTime: Double) {
        guard isActive else { return }
        let inputLength = hypot(forward, strafe)
        guard inputLength > 0 else { return }
        let normalizedForward = inputLength > 1 ? forward / inputLength : forward
        let normalizedStrafe = inputLength > 1 ? strafe / inputLength : strafe
        let speed = 2.2
        let distance = speed * min(0.05, max(0, deltaTime))
        let forwardX = -sin(yaw)
        let forwardZ = -cos(yaw)
        let rightX = cos(yaw)
        let rightZ = -sin(yaw)
        positionX = (positionX + (forwardX * normalizedForward + rightX * normalizedStrafe) * distance).clamped(to: -3.25...3.25)
        positionZ = (positionZ + (forwardZ * normalizedForward + rightZ * normalizedStrafe) * distance).clamped(to: -5.75...5.65)
    }

    mutating func rotate(deltaX: Double, deltaY: Double) {
        guard isActive else { return }
        yaw = (yaw + deltaX * 0.0038).clamped(to: (-Double.pi)...Double.pi)
        pitch = (pitch - deltaY * 0.0024).clamped(to: -0.52...0.3)
    }

    var nearbyHotspot: NarrativeHotspot? {
        nearbyHotspot(in: NarrativeHotspot.all(for: chapter))
    }

    func nearbyHotspot(in hotspots: [NarrativeHotspot]) -> NarrativeHotspot? {
        hotspots.first { hotspot in
            hypot(positionX - hotspot.x, positionZ - hotspot.z) <= hotspot.radius
        }
    }

    mutating func interact() -> NarrativeHotspot? {
        interact(with: NarrativeHotspot.all(for: chapter))
    }

    mutating func interact(with hotspots: [NarrativeHotspot]) -> NarrativeHotspot? {
        guard let hotspot = nearbyHotspot(in: hotspots) else { return nil }
        lastInteractedHotspot = hotspot.id
        interactionCount += 1
        return hotspot
    }
}

enum NoteTraceDepartureClue: String, Codable, CaseIterable {
    case deskTrace
    case doorSound

    var title: String {
        switch self {
        case .deskTrace: return "桌面痕迹"
        case .doorSound: return "门轴声"
        }
    }
}

struct NarrativeHotspot: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let prompt: String
    let x: Double
    let z: Double
    let radius: Double
    let choiceID: String?

    init(id: String, title: String, prompt: String, x: Double, z: Double, radius: Double, choiceID: String? = nil) {
        self.id = id
        self.title = title
        self.prompt = prompt
        self.x = x
        self.z = z
        self.radius = radius
        self.choiceID = choiceID
    }

    static func all(for chapter: NarrativeChapter) -> [NarrativeHotspot] {
        switch chapter {
        case .classroom:
            return []
        case .mirror:
            return [
                NarrativeHotspot(id: "mirror.threshold", title: "镜面边缘", prompt: "镜面把走廊拉得更长。", x: 0, z: -2.1, radius: 1.15),
                NarrativeHotspot(id: "mirror.linche", title: "林澈的影子", prompt: "影子没有跟着他一起呼吸。", x: -0.75, z: -1.15, radius: 0.9)
            ]
        case .noteTrace:
            return [
                NarrativeHotspot(id: "note.table", title: "值日表", prompt: "撕掉的角落和今天的值日顺序对上了。", x: 0, z: -1.45, radius: 1.2),
                NarrativeHotspot(id: "note.deskTrace", title: "江越座位", prompt: "水杯还在桌角，蓝格笔记本停在半行字上。", x: 1.45, z: -0.45, radius: 0.95),
                NarrativeHotspot(id: "note.paperTrail", title: "门轴声", prompt: "楼梯间安全门轻轻回弹，像刚有人离开。", x: -0.2, z: 1.5, radius: 1.0)
            ]
        case .stairwell:
            return [
                NarrativeHotspot(id: "stairs.door", title: "十三楼安全门", prompt: "门后传来一次很轻的回声。", x: 1.85, z: -3.35, radius: 1.05),
                NarrativeHotspot(id: "stairs.landing", title: "楼梯平台", prompt: "有人把书包放在平台边，没有锁。", x: 0.1, z: -1.65, radius: 1.0)
            ]
        case .counseling:
            return [
                NarrativeHotspot(id: "counseling.lamp", title: "门外的灯", prompt: "灯亮着，门上的字提醒你先等候。", x: 2.65, z: -1.35, radius: 0.95),
                NarrativeHotspot(id: "counseling.chairs", title: "三把椅子", prompt: "每一把椅子都给不同的人留了位置。", x: 0, z: -0.65, radius: 1.25)
            ]
        case .epilogue:
            return [
                NarrativeHotspot(id: "epilogue.light", title: "光的中心", prompt: "你终于允许自己也站在被照见的位置。", x: 0, z: -3.65, radius: 1.3),
                NarrativeHotspot(id: "epilogue.network", title: "支持网络", prompt: "同伴、老师、家人和专业支持都在这里。", x: 0, z: -1.45, radius: 1.2)
            ]
        }
    }
}

enum NarrativeRiskLevel: String, Codable, CaseIterable {
    case low
    case moderate
    case high
    case imminent
}

enum NarrativeSafetyRoute: String, Codable, CaseIterable {
    case standardCounseling
    case urgentSchoolResponse
    case emergencyServices

    var displayName: String {
        switch self {
        case .standardCounseling: return "咨询室陪同"
        case .urgentSchoolResponse: return "校内紧急支持"
        case .emergencyServices: return "紧急服务接管"
        }
    }
}

enum NarrativeCounselingEntryMode: String, Codable {
    case standardWaiting
    case urgentHandoffWaiting
    case emergencyClosure
}

enum NarrativeResolutionPath: String, Codable {
    case voluntary
    case adultCameAfterUnclearDisclosure
    case adultCameAfterLowTrust
}

enum NarrativeRumorOutcome: String, Codable {
    case suppressed
    case contained
}

enum NarrativeDialogueResponseKind: String, Codable, CaseIterable {
    case judgmental
    case inspirational
    case advisory
    case listening
    case accompanying
    case silentPresence
    case timeout
}

enum NarrativeDialoguePerformanceBeat: String, Codable, CaseIterable, Identifiable {
    case rupture
    case thinEncouragement
    case practicalAdvice
    case reflectiveListening
    case activeAccompaniment
    case quietPresence
    case patientSilence

    var id: String { rawValue }

    init(response: NarrativeDialogueResponseKind) {
        switch response {
        case .judgmental: self = .rupture
        case .inspirational: self = .thinEncouragement
        case .advisory: self = .practicalAdvice
        case .listening: self = .reflectiveListening
        case .accompanying: self = .activeAccompaniment
        case .silentPresence: self = .quietPresence
        case .timeout: self = .patientSilence
        }
    }

    var title: String {
        switch self {
        case .rupture: return "关系收紧"
        case .thinEncouragement: return "鼓励盖过当下"
        case .practicalAdvice: return "建议太早"
        case .reflectiveListening: return "被复述"
        case .activeAccompaniment: return "有人留下"
        case .quietPresence: return "沉默没有离开"
        case .patientSilence: return "等他说完"
        }
    }

    var detail: String {
        switch self {
        case .rupture: return "江越的身体往回收，现场张力上升。"
        case .thinEncouragement: return "话语看似明亮，但没有承接具体痛感。"
        case .practicalAdvice: return "方法出现太早，安全感没有同步出现。"
        case .reflectiveListening: return "你先确认听见了什么，风险没有被急着解释。"
        case .activeAccompaniment: return "陪伴被说清楚，成人支持也更容易接入。"
        case .quietPresence: return "身体朝向留下来，让沉默成为安全空间。"
        case .patientSilence: return "你没有抢话，江越获得继续说下去的时间。"
        }
    }

    var symbol: String {
        switch self {
        case .rupture: return "xmark.bubble.fill"
        case .thinEncouragement: return "sunrise.fill"
        case .practicalAdvice: return "lightbulb.fill"
        case .reflectiveListening: return "ear.and.waveform"
        case .activeAccompaniment: return "person.2.fill"
        case .quietPresence: return "figure.seated.side"
        case .patientSilence: return "hourglass"
        }
    }

    var supportWeight: Double {
        switch self {
        case .reflectiveListening: return 0.72
        case .activeAccompaniment: return 0.82
        case .quietPresence: return 0.62
        case .patientSilence: return 0.48
        case .practicalAdvice: return 0.24
        case .thinEncouragement: return 0.16
        case .rupture: return 0.04
        }
    }

    var ruptureWeight: Double {
        switch self {
        case .rupture: return 0.88
        case .thinEncouragement: return 0.58
        case .practicalAdvice: return 0.42
        case .patientSilence: return 0.12
        case .reflectiveListening, .activeAccompaniment, .quietPresence: return 0
        }
    }

    var anchorsSafety: Bool {
        switch self {
        case .reflectiveListening, .activeAccompaniment, .quietPresence, .patientSilence:
            return true
        case .rupture, .thinEncouragement, .practicalAdvice:
            return false
        }
    }
}

struct NarrativeJiangEmbodiedCue: Equatable {
    let title: String
    let postureLine: String
    let voiceLine: String
    let boundaryLine: String
    let nextPrompt: String
    let symbol: String

    static func derive(
        beat: NarrativeDialoguePerformanceBeat,
        consecutiveTimeouts: Int = 0
    ) -> NarrativeJiangEmbodiedCue {
        switch beat {
        case .rupture:
            return NarrativeJiangEmbodiedCue(
                title: "他把身体往后收了一点",
                postureLine: "肩膀抬起，脚尖偏向楼梯口。",
                voiceLine: "回答变短，像是在确认这里是否还能待下去。",
                boundaryLine: "先不要追问原因，也不要替他说结论。",
                nextPrompt: "把话退回到听见和陪在这里。",
                symbol: "figure.stand.line.dotted.figure.stand"
            )
        case .thinEncouragement:
            return NarrativeJiangEmbodiedCue(
                title: "明亮的话没有接住他",
                postureLine: "江越没有再靠近，手指还扣着书包带。",
                voiceLine: "他的停顿变长，像是把后半句话吞回去了。",
                boundaryLine: "鼓励可以晚一点出现，先承认此刻很难。",
                nextPrompt: "换成复述或安静陪伴，让他不用立刻好起来。",
                symbol: "sunrise"
            )
        case .practicalAdvice:
            return NarrativeJiangEmbodiedCue(
                title: "方法来得太早",
                postureLine: "他听见了建议，但身体还停在原地。",
                voiceLine: "声音没有放松，像是还在等一句确认。",
                boundaryLine: "暂时别把问题推向解决方案。",
                nextPrompt: "先确认你听懂了他的处境，再谈下一步。",
                symbol: "lightbulb"
            )
        case .reflectiveListening:
            return NarrativeJiangEmbodiedCue(
                title: "他知道自己被听见了",
                postureLine: "肩线慢慢放低，视线没有立刻躲开。",
                voiceLine: "下一句话更完整，不再只剩碎片。",
                boundaryLine: "保持低声、慢节奏，不抢走他的表达权。",
                nextPrompt: "继续复述事实和感受，让成人支持自然接上。",
                symbol: "ear.and.waveform"
            )
        case .activeAccompaniment:
            return NarrativeJiangEmbodiedCue(
                title: "陪伴被说清楚了",
                postureLine: "他没有独自往楼梯口退，身体停在可见范围内。",
                voiceLine: "沉默还在，但不再像完全断开。",
                boundaryLine: "陪在旁边，同时让可靠成人靠近。",
                nextPrompt: "说明你会留下，也会请大人接手。",
                symbol: "person.2.fill"
            )
        case .quietPresence:
            return NarrativeJiangEmbodiedCue(
                title: "沉默被允许存在",
                postureLine: "两个人之间留出距离，压迫感没有继续加重。",
                voiceLine: "没有新的话，但呼吸不再那么急促。",
                boundaryLine: "安静不是放任，成人支持仍然需要到场。",
                nextPrompt: "继续守住空间，不把不说话当成安全。",
                symbol: "figure.seated.side"
            )
        case .patientSilence:
            let prompt = consecutiveTimeouts > 1
                ? "连续沉默后，下一句要更明确地给出可选择的回应。"
                : "等他把这句话说完，再给一个低压力回应。"
            return NarrativeJiangEmbodiedCue(
                title: "你没有急着插话",
                postureLine: "现场没有被推着往前走，江越仍留在平台边。",
                voiceLine: "空白被保留下来，他还有继续说的余地。",
                boundaryLine: "等待不是退出，仍要注意安全边界。",
                nextPrompt: prompt,
                symbol: "hourglass"
            )
        }
    }
}

enum NarrativeRiskAskMethod: String, Codable {
    case none
    case gentle
    case direct
    case deferToAdult
}

enum NarrativeRiskDisclosure: String, Codable {
    case unknown
    case partial
    case confirmed
}

struct NarrativeJiangDialogueState: Codable, Equatable {
    var segmentIndex = 0
    var responseKinds: [NarrativeDialogueResponseKind] = []
    var performanceBeats: [NarrativeDialoguePerformanceBeat] = []
    var consecutiveTimeouts = 0
    var listenPhaseComplete = false
    var educationCardDismissed = false
    var riskAskMethod: NarrativeRiskAskMethod = .none
    var disclosedRisk: NarrativeRiskDisclosure = .unknown

    init(
        segmentIndex: Int = 0,
        responseKinds: [NarrativeDialogueResponseKind] = [],
        performanceBeats: [NarrativeDialoguePerformanceBeat] = [],
        consecutiveTimeouts: Int = 0,
        listenPhaseComplete: Bool = false,
        educationCardDismissed: Bool = false,
        riskAskMethod: NarrativeRiskAskMethod = .none,
        disclosedRisk: NarrativeRiskDisclosure = .unknown
    ) {
        self.segmentIndex = segmentIndex
        self.responseKinds = responseKinds
        self.performanceBeats = performanceBeats.isEmpty
            ? responseKinds.map(NarrativeDialoguePerformanceBeat.init(response:))
            : performanceBeats
        self.consecutiveTimeouts = consecutiveTimeouts
        self.listenPhaseComplete = listenPhaseComplete
        self.educationCardDismissed = educationCardDismissed
        self.riskAskMethod = riskAskMethod
        self.disclosedRisk = disclosedRisk
    }

    private enum CodingKeys: String, CodingKey {
        case segmentIndex
        case responseKinds
        case performanceBeats
        case consecutiveTimeouts
        case listenPhaseComplete
        case educationCardDismissed
        case riskAskMethod
        case disclosedRisk
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let responseKinds = try container.decodeIfPresent([NarrativeDialogueResponseKind].self, forKey: .responseKinds) ?? []
        let performanceBeats = try container.decodeIfPresent([NarrativeDialoguePerformanceBeat].self, forKey: .performanceBeats)
            ?? responseKinds.map(NarrativeDialoguePerformanceBeat.init(response:))
        self.init(
            segmentIndex: try container.decodeIfPresent(Int.self, forKey: .segmentIndex) ?? 0,
            responseKinds: responseKinds,
            performanceBeats: performanceBeats,
            consecutiveTimeouts: try container.decodeIfPresent(Int.self, forKey: .consecutiveTimeouts) ?? 0,
            listenPhaseComplete: try container.decodeIfPresent(Bool.self, forKey: .listenPhaseComplete) ?? false,
            educationCardDismissed: try container.decodeIfPresent(Bool.self, forKey: .educationCardDismissed) ?? false,
            riskAskMethod: try container.decodeIfPresent(NarrativeRiskAskMethod.self, forKey: .riskAskMethod) ?? .none,
            disclosedRisk: try container.decodeIfPresent(NarrativeRiskDisclosure.self, forKey: .disclosedRisk) ?? .unknown
        )
    }
}

struct NarrativeDialogueTrustReducer {
    static func apply(_ response: NarrativeDialogueResponseKind, to trust: Int) -> Int {
        let delta: Int
        switch response {
        case .judgmental: delta = -10
        case .inspirational: delta = -5
        case .advisory: delta = 0
        case .listening: delta = 10
        case .accompanying: delta = 8
        case .silentPresence: delta = 5
        case .timeout: delta = 1
        }
        return min(100, max(0, trust + delta))
    }
}

struct NarrativeDisclosureResolver {
    static func resolve(method: NarrativeRiskAskMethod, trust: Int) -> NarrativeRiskDisclosure {
        switch method {
        case .gentle:
            return trust >= 40 ? .partial : .unknown
        case .direct:
            if trust >= 60 { return .confirmed }
            return trust >= 40 ? .partial : .unknown
        case .deferToAdult, .none:
            return .unknown
        }
    }
}

struct NarrativeSafetyHandoffState: Codable, Equatable {
    var authoredRisk: NarrativeRiskLevel = .moderate
    var riskAsked = false
    var adultContactInitiated = false
    var contactMethod = ""
    var safetyHandoffComplete = false
    var route: NarrativeSafetyRoute?
    var entryMode: NarrativeCounselingEntryMode?
    var resolutionPath: NarrativeResolutionPath?
}

struct NarrativeCounselingState: Codable, Equatable {
    var entryMode: NarrativeCounselingEntryMode
    var handoffSceneStarted = false
    var boundaryHeld = true
    var rumorHandled = false
    var rumorOutcome: NarrativeRumorOutcome?
    var companionMessageReplied = false
    var handoffConfirmed = false
    var supportHandedOff = false
}

struct NarrativeWaitingBiasCard: Identifiable, Equatable {
    let id: String
    let title: String
    let line: String
    let symbol: String
}

struct NarrativeSafetyHandoffPolicy {
    static func resolve(_ risk: NarrativeRiskLevel) -> (route: NarrativeSafetyRoute, entryMode: NarrativeCounselingEntryMode) {
        switch risk {
        case .low, .moderate:
            return (.standardCounseling, .standardWaiting)
        case .high:
            return (.urgentSchoolResponse, .urgentHandoffWaiting)
        case .imminent:
            return (.emergencyServices, .emergencyClosure)
        }
    }
}

struct NarrativeCounselingWaitingStatus: Equatable {
    static let maxBiasCards = 2

    let entryTitle: String
    let entryLine: String
    let boundaryLine: String
    let rumorLine: String
    let companionLine: String
    let handoffLine: String
    let supportLine: String?
    let biasCards: [NarrativeWaitingBiasCard]
    let isEmergency: Bool

    init?(campaign: NarrativeCampaign) {
        guard campaign.chapter == .counseling,
              let state = campaign.counselingState else { return nil }
        let carryover = MirrorDialogueCarryoverModel.derive(from: campaign)

        switch state.entryMode {
        case .standardWaiting:
            entryTitle = "咨询室门外等候"
            entryLine = "江越在门内由专业人员接住，苏念坐在门外。"
            isEmergency = false
        case .urgentHandoffWaiting:
            entryTitle = "紧急交接等候区"
            entryLine = "心理老师和方老师轮班确认，学生留在支持室外。"
            isEmergency = false
        case .emergencyClosure:
            entryTitle = "成人确认后的安全收束"
            entryLine = "紧急服务已经接手，江越不再出镜，学生退到安全锚点。"
            isEmergency = true
        }

        boundaryLine = state.entryMode == .emergencyClosure
            ? "不靠近处置现场，保持安全办公室/走廊锚点。"
            : (state.boundaryHeld
                ? "咨询室门不能进入；靠近后会被拉回等候区。"
                : "边界需要重新确认，先回到等候椅。")
        rumorLine = state.entryMode == .emergencyClosure
            ? "方老师已提醒不要在群里讨论，未生成围观流言。"
            : (state.rumorHandled
                ? "路过议论已经被挡在隐私边界外。"
                : "如有路过猜测，只回应边界，不公开任何位置或内容。")
        companionLine = state.companionMessageReplied
            ? "同伴消息已回复：可以一起等，也可以继续找老师。"
            : "林澈的消息还在，回复只传递陪伴和求助路径。"
        handoffLine = state.supportHandedOff
            ? "成人交接已确认，支持已经从学生转给可靠系统。"
            : (state.handoffConfirmed
                ? "成人已确认下一步，等待系统写入支持交接。"
                : "等待成人给出最小必要确认，不进入门内探查。")
        supportLine = carryover.isActive
            ? "\(carryover.title)：\(carryover.supportBiasText)"
            : nil

        biasCards = Array(Self.deriveBiasCards(state: state, privacyProtected: campaign.privacyProtected).prefix(Self.maxBiasCards))
    }

    private static func deriveBiasCards(
        state: NarrativeCounselingState,
        privacyProtected: Bool
    ) -> [NarrativeWaitingBiasCard] {
        guard state.handoffSceneStarted else { return [] }
        var cards = [
            NarrativeWaitingBiasCard(
                id: "bias.quiet",
                title: "偏见便签",
                line: "安静不等于已经没事；门内的专业支持需要时间。",
                symbol: "note.text"
            )
        ]
        if state.rumorHandled || privacyProtected {
            cards.append(NarrativeWaitingBiasCard(
                id: "bias.privacy",
                title: "边界便签",
                line: "不解释别人的处境，不等于不关心。",
                symbol: "lock.shield"
            ))
        }
        return cards
    }
}

struct NarrativeSafetyHandoffBriefing: Equatable {
    struct Step: Identifiable, Equatable {
        enum State: Equatable {
            case complete
            case current
            case pending
        }

        let id: String
        let title: String
        let detail: String
        let state: State
    }

    let contactLine: String
    let adultArrivalLine: String
    let routeTitle: String
    let routeLine: String
    let entryLine: String
    let supportLine: String?
    let studentBoundaryLine: String
    let isHighPriority: Bool
    let teacherReachedJiang: Bool
    let steps: [Step]

    init?(campaign: NarrativeCampaign) {
        guard campaign.currentMoment.id == "4.handoff",
              let handoff = campaign.safetyHandoffState,
              handoff.adultContactInitiated else { return nil }

        let resolved = handoff.route.map { route -> (route: NarrativeSafetyRoute, entryMode: NarrativeCounselingEntryMode) in
            (route, handoff.entryMode ?? NarrativeSafetyHandoffPolicy.resolve(handoff.authoredRisk).entryMode)
        } ?? NarrativeSafetyHandoffPolicy.resolve(handoff.authoredRisk)
        let companion = campaign.companionID.isEmpty ? "同伴" : campaign.companionID
        let method = handoff.contactMethod.isEmpty
            ? (companion == "周予安" ? "电话" : "消息")
            : handoff.contactMethod
        let carryover = MirrorDialogueCarryoverModel.derive(from: campaign)

        contactLine = "\(companion)用\(method)只说明楼层、位置和需要成人到场。"
        teacherReachedJiang = campaign.exploration.lastInteractedHotspot == "handoff.teacher"
        adultArrivalLine = teacherReachedJiang
            ? "方老师已经来到江越所在的平台，可以完成首次接管。"
            : "先走到方老师身边，确认她已经来到江越所在的位置。"
        routeTitle = resolved.route.displayName
        routeLine = Self.routeLine(for: resolved.route)
        entryLine = Self.entryLine(for: resolved.entryMode)
        supportLine = carryover.isActive
            ? (campaign.currentMoment.id == "4.handoff"
                ? carryover.supportBiasText
                : "\(carryover.title)：\(carryover.supportBiasText)")
            : nil
        studentBoundaryLine = "苏念和同伴不评估风险，只陪在可见范围内，把接手交给成人。"
        isHighPriority = resolved.route != .standardCounseling
        let handoffComplete = handoff.safetyHandoffComplete && handoff.route != nil && handoff.entryMode != nil
        steps = [
            Step(id: "contact", title: "联络成人", detail: method, state: .complete),
            Step(
                id: "arrival",
                title: "成人到场",
                detail: teacherReachedJiang ? "平台确认" : "靠近方老师",
                state: teacherReachedJiang ? .complete : .current
            ),
            Step(
                id: "route",
                title: "路线写入",
                detail: resolved.route.displayName,
                state: handoffComplete ? .complete : (teacherReachedJiang ? .current : .pending)
            ),
            Step(
                id: "boundary",
                title: "学生边界",
                detail: "不诊断",
                state: handoffComplete ? .complete : (teacherReachedJiang ? .current : .pending)
            )
        ]
    }

    private static func routeLine(for route: NarrativeSafetyRoute) -> String {
        switch route {
        case .standardCounseling:
            return "按普通咨询陪同处理，先保证有人在场。"
        case .urgentSchoolResponse:
            return "校内紧急支持接手，普通课间节奏让位给安全响应。"
        case .emergencyServices:
            return "紧急服务接管，学生退到安全位置等待成人确认。"
        }
    }

    private static func entryLine(for entryMode: NarrativeCounselingEntryMode) -> String {
        switch entryMode {
        case .standardWaiting:
            return "第五章入口：咨询室门外等候。"
        case .urgentHandoffWaiting:
            return "第五章入口：紧急交接等候区。"
        case .emergencyClosure:
            return "第五章入口：成人确认后的安全收束。"
        }
    }
}

struct NarrativeChoice: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
}

struct NarrativeMoment: Identifiable {
    let id: String
    let title: String
    let goal: String
    let body: String
    let speaker: String
    let choices: [NarrativeChoice]
    let miniGame: NarrativeMiniGame?
}

struct NarrativeChoiceSignal: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let tint: Color
}

struct NarrativeChoiceImpact: Codable, Equatable, Identifiable {
    let id: String
    let sourceMomentID: String
    let choiceTitle: String
    let title: String
    let detail: String
    let signalIDs: [String]
    let symbol: String

    var signals: [NarrativeChoiceSignal] {
        signalIDs.compactMap { NarrativeChoiceSignalModel.signal(for: $0) }
    }
}

enum NarrativeChoiceSignalModel {
    static func signal(for id: String) -> NarrativeChoiceSignal? {
        switch id {
        case "risk":
            return NarrativeChoiceSignal(id: id, title: "风险", symbol: "exclamationmark.triangle.fill", tint: .orange)
        case "adult":
            return NarrativeChoiceSignal(id: id, title: "成人交接", symbol: "person.badge.shield.checkmark.fill", tint: .yellow)
        case "privacy":
            return NarrativeChoiceSignal(id: id, title: "隐私边界", symbol: "lock.fill", tint: .mint)
        case "support":
            return NarrativeChoiceSignal(id: id, title: "支持", symbol: "heart.fill", tint: .mint)
        case "selfCare":
            return NarrativeChoiceSignal(id: id, title: "稳住", symbol: "lungs.fill", tint: .cyan)
        case "investigate":
            return NarrativeChoiceSignal(id: id, title: "线索", symbol: "magnifyingglass", tint: .cyan)
        case "clarify":
            return NarrativeChoiceSignal(id: id, title: "澄清", symbol: "questionmark.bubble.fill", tint: .blue)
        case "observe":
            return NarrativeChoiceSignal(id: id, title: "观察", symbol: "eye.fill", tint: .cyan)
        case "mirror":
            return NarrativeChoiceSignal(id: id, title: "接住", symbol: "sparkle.magnifyingglass", tint: .purple)
        case "route":
            return NarrativeChoiceSignal(id: id, title: "行动", symbol: "figure.walk", tint: .cyan)
        case "safety":
            return NarrativeChoiceSignal(id: id, title: "安全", symbol: "shield.lefthalf.filled", tint: .yellow)
        case "boundary":
            return NarrativeChoiceSignal(id: id, title: "边界", symbol: "lock.fill", tint: .mint)
        default:
            return nil
        }
    }

    static func signals(for choice: NarrativeChoice, moment: NarrativeMoment, campaign: NarrativeCampaign) -> [NarrativeChoiceSignal] {
        var signals: [NarrativeChoiceSignal] = []
        let source = "\(choice.id) \(choice.title) \(choice.detail)".lowercased()

        func append(_ id: String) {
            guard signals.contains(where: { $0.id == id }) == false, signals.count < 3 else { return }
            if let signal = signal(for: id) {
                signals.append(signal)
            }
        }

        if source.contains("judge")
            || source.contains("advise")
            || source.contains("inspire")
            || source.contains("ignore")
            || source.contains("push") {
            append("risk")
        }

        if source.contains("adult")
            || source.contains("teacher")
            || source.contains("handoff")
            || source.contains("contact")
            || source.contains("safety")
            || source.contains("safe")
            || source.contains("shield") {
            append("adult")
        }

        if source.contains("privacy")
            || source.contains("redirect")
            || source.contains("boundary")
            || source.contains("lock")
            || source.contains("保密")
            || source.contains("隐私") {
            append("privacy")
        }

        if source.contains("listen")
            || source.contains("accompany")
            || source.contains("present")
            || source.contains("reassure")
            || source.contains("stay")
            || source.contains("message")
            || source.contains("openquestion")
            || source.contains("invite")
            || source.contains("support")
            || source.contains("陪")
            || source.contains("听") {
            append("support")
        }

        if choice.id == "zhou" || choice.id == "xu" {
            append("support")
        }

        if source.contains("breathe")
            || source.contains("water")
            || source.contains("wait")
            || source.contains("pause")
            || source.contains("silent")
            || source.contains("呼吸")
            || source.contains("等") {
            append("selfCare")
        }

        if source.contains("inspect")
            || source.contains("trace")
            || source.contains("locate")
            || source.contains("note")
            || source.contains("observe")
            || source.contains("melody")
            || source.contains("erase")
            || source.contains("clue")
            || source.contains("线索")
            || source.contains("确认") {
            append("investigate")
        }

        if source.contains("risk") || source.contains("askgentle") {
            append("clarify")
        }

        if signals.isEmpty {
            switch campaign.chapter {
            case .classroom:
                append("observe")
            case .mirror:
                append("mirror")
            case .noteTrace:
                append("route")
            case .stairwell:
                append("safety")
            case .counseling:
                append("boundary")
            case .epilogue:
                append("support")
            }
        }

        return signals
    }

    static func impact(for choice: NarrativeChoice, moment: NarrativeMoment, campaign: NarrativeCampaign) -> NarrativeChoiceImpact {
        let signals = signals(for: choice, moment: moment, campaign: campaign)
        let signalIDs = signals.map(\.id)
        let primary = signals.first?.id ?? "support"
        let title: String
        let detail: String
        switch primary {
        case "risk":
            title = "这句话让空气绷紧了一下"
            detail = "支持线仍在，但对方需要更多空间来重新信任你。"
        case "adult", "safety":
            title = "责任开始交给能负责的人"
            detail = "你把位置和风险说清楚，没有让学生独自承担评估。"
        case "privacy", "boundary":
            title = "边界被稳稳守住"
            detail = "围观和猜测被挡在外面，支持不靠公开隐私换取解释。"
        case "selfCare":
            title = "你也被放进这张网里"
            detail = "短暂停顿让下一步不只是撑过去，而是更稳地继续。"
        case "investigate", "observe", "route", "mirror":
            title = "新的线索接上了前一段"
            detail = "世界没有给诊断，只把下一个可以靠近的位置亮出来。"
        case "clarify":
            title = "含糊的话被轻轻说清"
            detail = "你没有替他补完答案，只把风险和边界放到明处。"
        default:
            title = "支持网络回应了这一步"
            detail = "这不是结局判分，而是下一段关系正在发生变化。"
        }

        let displayChoiceTitle = choice.title.trimmingCharacters(in: CharacterSet(charactersIn: "“”\""))
        return NarrativeChoiceImpact(
            id: "\(moment.id).\(choice.id)",
            sourceMomentID: moment.id,
            choiceTitle: displayChoiceTitle.isEmpty ? choice.title : displayChoiceTitle,
            title: title,
            detail: detail,
            signalIDs: signalIDs,
            symbol: signals.first?.symbol ?? choice.symbol
        )
    }
}

enum NarrativeGuidanceStage: String, Equatable {
    case gentle
    case directorNudge
}

struct NarrativeGuidanceCue: Identifiable, Equatable {
    let id: String
    let momentID: String
    let stage: NarrativeGuidanceStage
    let title: String
    let detail: String
    let elapsedSeconds: Double

    var symbol: String {
        switch stage {
        case .gentle: return "scope"
        case .directorNudge: return "sparkle.magnifyingglass"
        }
    }
}

enum NarrativeCompanionPresenceMode: String, Equatable {
    case following
    case boundary
    case contactingAdult
    case privacyGuard
    case waiting
}

struct NarrativeCompanionPresenceStatus: Equatable {
    let companionID: String
    let mode: NarrativeCompanionPresenceMode
    let title: String
    let detail: String
    let symbol: String
    var navigationLine: String? = nil
    var navigationSymbol: String = "location.north.line.fill"

    var shortRole: String {
        companionID == "周予安" ? "班长" : "同伴"
    }
}

enum NarrativeWorldDirectorCue: String, Codable, Equatable {
    case attention
    case investigation
    case risk
    case privacy
    case safetyResponse
    case support
}

struct NarrativeWorldDirectorSignal: Equatable {
    var ambientTension: Double
    var supportPresence: Double
    var privacyBoundary: Double
    var witnessPressure: Double
    var safetyResponse: Double
    var cue: NarrativeWorldDirectorCue

    static let idle = NarrativeWorldDirectorSignal(
        ambientTension: 0,
        supportPresence: 0,
        privacyBoundary: 0,
        witnessPressure: 0,
        safetyResponse: 0,
        cue: .attention
    )
}

enum NarrativeAmbientActorRole: String, Equatable {
    case bystander
    case messenger
    case boundaryKeeper
    case supportRunner
    case quietWitness
    case facilitator
}

struct NarrativeAmbientActorDirective: Identifiable, Equatable {
    let id: String
    let role: NarrativeAmbientActorRole
    let anchorX: Double
    let anchorZ: Double
    let targetX: Double
    let targetZ: Double
    let intensity: Double
    let line: String
}

enum NarrativeConsequenceEchoKind: String, Equatable {
    case noticed
    case companion
    case riskQuestion
    case privacy
    case selfCare
    case handoff
}

struct NarrativeConsequenceEcho: Identifiable, Equatable {
    let id: String
    let kind: NarrativeConsequenceEchoKind
    let title: String
    let trace: String
    let strength: Double
    let symbol: String
}

struct NarrativeInvestigationStep: Identifiable, Equatable {
    enum State: String, Equatable {
        case complete
        case active
        case locked
    }

    let id: String
    let title: String
    let detail: String
    let symbol: String
    let state: State
}

enum NarrativeEmpathyReplayBeatKind: String, Equatable {
    case observation
    case connection
    case risk
    case handoff
    case boundary
    case selfReflection
}

struct NarrativeEmpathyReplayBeat: Identifiable, Equatable {
    let id: String
    let kind: NarrativeEmpathyReplayBeatKind
    let chapterTitle: String
    let playerTrace: String
    let systemPressure: String
    let supportResponse: String
    let empathyScore: Double
    let tensionScore: Double
    let symbol: String
}

enum NarrativeTruthReplayPerspective: String, Equatable {
    case teacher
    case linChe
    case jiangYue
    case suNian

    var title: String {
        switch self {
        case .teacher: return "教师视角"
        case .linChe: return "林澈视角"
        case .jiangYue: return "江越视角"
        case .suNian: return "苏念视角"
        }
    }
}

struct NarrativeTruthReplayReveal: Identifiable, Equatable {
    let id: String
    let perspective: NarrativeTruthReplayPerspective
    let apparentRead: String
    let hiddenTruth: String
    let repairAction: String
    let revealStrength: Double
    let symbol: String
}

struct NarrativePolicyExperiment: Identifiable, Equatable {
    let id: String
    let title: String
    let premise: String
    let scheduleText: String
    let ruleText: String
    let pressureIndex: Double
    let supportIndex: Double
    let missedSignalRisk: Double
    let outcomeLine: String
    let symbol: String
}

struct NarrativeCampaign: Codable, Equatable {
    var isActive = false
    var isComplete = false
    var chapter: NarrativeChapter = .classroom
    var momentIndex = 0
    var completedMomentIDs: Set<String> = []
    var linCheTrust = 0
    var jiangYueTrust = 0
    var companionID = ""
    var safetyRoute = ""
    var privacyProtected = true
    var selfCared = false
    var sharedSelf = false
    var miniGameProgress = 0
    var miniGameTouchedSlots: Set<Int> = []
    var miniGameHintCount = 0
    var clueCount = 0
    var exploration = NarrativeExplorationState()
    var noteTraceDepartureClues: Set<NoteTraceDepartureClue> = []
    var safetyHandoffState: NarrativeSafetyHandoffState?
    var counselingState: NarrativeCounselingState?
    var jiangDialogueState: NarrativeJiangDialogueState?
    var lastChoiceImpact: NarrativeChoiceImpact?

    private enum CodingKeys: String, CodingKey {
        case isActive
        case isComplete
        case chapter
        case momentIndex
        case completedMomentIDs
        case linCheTrust
        case jiangYueTrust
        case companionID
        case safetyRoute
        case privacyProtected
        case selfCared
        case sharedSelf
        case miniGameProgress
        case miniGameTouchedSlots
        case miniGameHintCount
        case clueCount
        case exploration
        case noteTraceDepartureClues
        case safetyHandoffState
        case counselingState
        case jiangDialogueState
        case lastChoiceImpact
    }

    init(
        isActive: Bool = false,
        isComplete: Bool = false,
        chapter: NarrativeChapter = .classroom,
        momentIndex: Int = 0,
        completedMomentIDs: Set<String> = [],
        linCheTrust: Int = 0,
        jiangYueTrust: Int = 0,
        companionID: String = "",
        safetyRoute: String = "",
        privacyProtected: Bool = true,
        selfCared: Bool = false,
        sharedSelf: Bool = false,
        miniGameProgress: Int = 0,
        miniGameTouchedSlots: Set<Int> = [],
        miniGameHintCount: Int = 0,
        clueCount: Int = 0,
        exploration: NarrativeExplorationState = NarrativeExplorationState(),
        noteTraceDepartureClues: Set<NoteTraceDepartureClue> = [],
        safetyHandoffState: NarrativeSafetyHandoffState? = nil,
        counselingState: NarrativeCounselingState? = nil,
        jiangDialogueState: NarrativeJiangDialogueState? = nil,
        lastChoiceImpact: NarrativeChoiceImpact? = nil
    ) {
        self.isActive = isActive
        self.isComplete = isComplete
        self.chapter = chapter
        self.momentIndex = momentIndex
        self.completedMomentIDs = completedMomentIDs
        self.linCheTrust = linCheTrust
        self.jiangYueTrust = jiangYueTrust
        self.companionID = companionID
        self.safetyRoute = safetyRoute
        self.privacyProtected = privacyProtected
        self.selfCared = selfCared
        self.sharedSelf = sharedSelf
        self.miniGameProgress = miniGameProgress
        self.miniGameTouchedSlots = miniGameTouchedSlots
        self.miniGameHintCount = miniGameHintCount
        self.clueCount = clueCount
        self.exploration = exploration
        self.noteTraceDepartureClues = noteTraceDepartureClues
        self.safetyHandoffState = safetyHandoffState
        self.counselingState = counselingState
        self.jiangDialogueState = jiangDialogueState
        self.lastChoiceImpact = lastChoiceImpact
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        isComplete = try container.decode(Bool.self, forKey: .isComplete)
        chapter = try container.decode(NarrativeChapter.self, forKey: .chapter)
        momentIndex = try container.decode(Int.self, forKey: .momentIndex)
        completedMomentIDs = try container.decode(Set<String>.self, forKey: .completedMomentIDs)
        linCheTrust = try container.decode(Int.self, forKey: .linCheTrust)
        jiangYueTrust = try container.decode(Int.self, forKey: .jiangYueTrust)
        companionID = try container.decode(String.self, forKey: .companionID)
        safetyRoute = try container.decode(String.self, forKey: .safetyRoute)
        privacyProtected = try container.decode(Bool.self, forKey: .privacyProtected)
        selfCared = try container.decode(Bool.self, forKey: .selfCared)
        sharedSelf = try container.decode(Bool.self, forKey: .sharedSelf)
        miniGameProgress = try container.decode(Int.self, forKey: .miniGameProgress)
        miniGameTouchedSlots = try container.decode(Set<Int>.self, forKey: .miniGameTouchedSlots)
        miniGameHintCount = try container.decode(Int.self, forKey: .miniGameHintCount)
        clueCount = try container.decode(Int.self, forKey: .clueCount)
        exploration = try container.decode(NarrativeExplorationState.self, forKey: .exploration)
        noteTraceDepartureClues = try container.decodeIfPresent(Set<NoteTraceDepartureClue>.self, forKey: .noteTraceDepartureClues) ?? []
        safetyHandoffState = try container.decodeIfPresent(NarrativeSafetyHandoffState.self, forKey: .safetyHandoffState)
        counselingState = try container.decodeIfPresent(NarrativeCounselingState.self, forKey: .counselingState)
        jiangDialogueState = try container.decodeIfPresent(NarrativeJiangDialogueState.self, forKey: .jiangDialogueState)
        lastChoiceImpact = try container.decodeIfPresent(NarrativeChoiceImpact.self, forKey: .lastChoiceImpact)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isActive, forKey: .isActive)
        try container.encode(isComplete, forKey: .isComplete)
        try container.encode(chapter, forKey: .chapter)
        try container.encode(momentIndex, forKey: .momentIndex)
        try container.encode(completedMomentIDs, forKey: .completedMomentIDs)
        try container.encode(linCheTrust, forKey: .linCheTrust)
        try container.encode(jiangYueTrust, forKey: .jiangYueTrust)
        try container.encode(companionID, forKey: .companionID)
        try container.encode(safetyRoute, forKey: .safetyRoute)
        try container.encode(privacyProtected, forKey: .privacyProtected)
        try container.encode(selfCared, forKey: .selfCared)
        try container.encode(sharedSelf, forKey: .sharedSelf)
        try container.encode(miniGameProgress, forKey: .miniGameProgress)
        try container.encode(miniGameTouchedSlots, forKey: .miniGameTouchedSlots)
        try container.encode(miniGameHintCount, forKey: .miniGameHintCount)
        try container.encode(clueCount, forKey: .clueCount)
        try container.encode(exploration, forKey: .exploration)
        try container.encode(noteTraceDepartureClues, forKey: .noteTraceDepartureClues)
        try container.encodeIfPresent(safetyHandoffState, forKey: .safetyHandoffState)
        try container.encodeIfPresent(counselingState, forKey: .counselingState)
        try container.encodeIfPresent(jiangDialogueState, forKey: .jiangDialogueState)
        try container.encodeIfPresent(lastChoiceImpact, forKey: .lastChoiceImpact)
    }

    var currentMoment: NarrativeMoment {
        let moments = NarrativeCampaign.moments(for: chapter)
        let moment = moments[min(momentIndex, moments.count - 1)]
        if moment.id == "4.listen" {
            return NarrativeCampaign.jiangDialogueMoment(segment: jiangDialogueState?.segmentIndex ?? 0)
        }
        return moment
    }

    var activeChoiceImpact: NarrativeChoiceImpact? {
        guard let impact = lastChoiceImpact,
              isComplete == false,
              currentMoment.id != impact.sourceMomentID else { return nil }
        return impact
    }

    var progressText: String {
        "第 \(chapter.rawValue) / 6 章 · \(momentIndex + 1) / \(NarrativeCampaign.moments(for: chapter).count)"
    }

    var routeMarkers: [NarrativeRouteMarker] {
        NarrativeChapter.allCases.map { routeMarker(for: $0) }
    }

    private func routeMarker(for markerChapter: NarrativeChapter) -> NarrativeRouteMarker {
        let state: NarrativeRouteMarker.State
        if isComplete || markerChapter.rawValue < chapter.rawValue {
            state = .completed
        } else if markerChapter == chapter {
            state = .current
        } else {
            state = .upcoming
        }

        let statusLine: String
        let signalStrength: Double
        switch markerChapter {
        case .classroom:
            statusLine = clueCount > 0 ? "\(clueCount) 条线索被看见" : "等待第一条线索"
            signalStrength = min(1, max(0.18, Double(clueCount) / 5.0))
        case .mirror:
            if selfCared {
                statusLine = "苏念停下来照顾自己"
                signalStrength = 0.86
            } else if mirrorDissolveProgress >= 1 {
                statusLine = "镜面已经停下"
                signalStrength = 0.92
            } else if mirrorDissolveProgress > 0 {
                statusLine = "镜面正在褪色"
                signalStrength = 0.82
            } else {
                statusLine = "镜面还在放大压力"
                signalStrength = 0.36
            }
        case .noteTrace:
            statusLine = companionID.isEmpty ? "还没有同行者" : "\(companionID)加入同行"
            signalStrength = companionID.isEmpty ? 0.28 : 0.82
        case .stairwell:
            if let route = safetyHandoffState?.route {
                statusLine = route.displayName
                signalStrength = route == .emergencyServices ? 1 : route == .urgentSchoolResponse ? 0.9 : 0.72
            } else {
                statusLine = safetyRoute.isEmpty ? "安全路线未确认" : safetyRoute
                signalStrength = safetyRoute.isEmpty ? 0.32 : 0.62
            }
        case .counseling:
            statusLine = privacyProtected ? "隐私边界被守住" : "隐私仍需照顾"
            signalStrength = privacyProtected ? 0.84 : 0.38
        case .epilogue:
            statusLine = sharedSelf ? "苏念也被放进支持网络" : "下次也可以"
            signalStrength = sharedSelf ? 0.88 : 0.48
        }

        return NarrativeRouteMarker(
            chapter: markerChapter,
            state: state,
            statusLine: statusLine,
            signalStrength: signalStrength
        )
    }

    var explorationReady: Bool {
        chapter == .classroom || exploration.interactionCount > 0
    }

    var currentMomentActionReady: Bool {
        if currentMoment.id == "3.locate" {
            return noteTraceDepartureClues == Set(NoteTraceDepartureClue.allCases)
        }
        let requiredHotspots = requiredHotspotIDsForCurrentMoment
        if requiredHotspots.isEmpty == false {
            return requiredHotspots.contains(exploration.lastInteractedHotspot)
        }
        if currentMoment.id == "4.handoff" {
            return exploration.lastInteractedHotspot == "handoff.teacher"
        }
        if currentMoment.id == "4.risk" {
            return jiangDialogueState?.educationCardDismissed == true
        }
        return true
    }

    var requiredHotspotIDsForCurrentMoment: Set<String> {
        switch currentMoment.id {
        case "2.trace":
            return ["mirror.light.trace"]
        case "2.melody":
            return ["mirror.light.melody"]
        case "2.erase":
            return ["mirror.light.erase"]
        case "3.note":
            return ["note.table"]
        case "3.locate":
            return noteTracePendingDepartureHotspotIDs
        case "3.companion":
            return companionID.isEmpty ? ["companion.zhou", "companion.xu"] : []
        case "3.door":
            return ["note.paperTrail"]
        default:
            return []
        }
    }

    var currentMomentActionPrompt: String? {
        if currentMoment.id == "3.companion" {
            return "先靠近周予安或许栀，确认谁和苏念同行"
        }
        if currentMoment.id == "3.locate" {
            let missing = NoteTraceDepartureClue.allCases
                .filter { noteTraceDepartureClues.contains($0) == false }
                .map(\.title)
                .joined(separator: "、")
            return missing.isEmpty ? nil : "先确认离开迹象：\(missing)"
        }
        if let miniGame = currentMoment.miniGame {
            return "先沿着镜面光路靠近「\(miniGame.title)」，再开始这一盏灯的微互动"
        }
        if currentMoment.id == "3.door" {
            return "先走到纸片痕迹延伸的入口，确认再进入楼梯间"
        }
        if let target = requiredInteractionHotspots.first {
            return "先靠近「\(target.title)」并确认线索"
        }
        if currentMoment.id == "4.handoff" {
            return "先走到方老师身边确认成人已经接手"
        }
        return nil
    }

    var requiredInteractionHotspots: [NarrativeHotspot] {
        let requiredIDs = requiredHotspotIDsForCurrentMoment
        guard requiredIDs.isEmpty == false else { return [] }
        return interactionHotspots.filter { requiredIDs.contains($0.id) }
    }

    var noteTraceDepartureProgressText: String {
        "\(noteTraceDepartureClues.count)/\(NoteTraceDepartureClue.allCases.count)"
    }

    private var noteTracePendingDepartureHotspotIDs: Set<String> {
        var ids = Set<String>()
        if noteTraceDepartureClues.contains(.deskTrace) == false {
            ids.insert("note.deskTrace")
        }
        if noteTraceDepartureClues.contains(.doorSound) == false {
            ids.insert("note.paperTrail")
        }
        return ids
    }

    mutating func recordNoteTraceDepartureClue(for hotspotID: String) {
        guard currentMoment.id == "3.locate" else { return }
        switch hotspotID {
        case "note.deskTrace":
            noteTraceDepartureClues.insert(.deskTrace)
        case "note.paperTrail":
            noteTraceDepartureClues.insert(.doorSound)
        default:
            break
        }
    }

    var chapterThreeInvestigationSteps: [NarrativeInvestigationStep] {
        guard chapter == .noteTrace || chapter.rawValue > NarrativeChapter.noteTrace.rawValue || isComplete else { return [] }
        return [
            NarrativeInvestigationStep(
                id: "note.back",
                title: "纸条背面",
                detail: "值日表撕角",
                symbol: "doc.text.magnifyingglass",
                state: investigationState(momentID: "3.note", hotspotID: "note.table")
            ),
            NarrativeInvestigationStep(
                id: "note.trail",
                title: "离开迹象",
                detail: "桌面 + 门声",
                symbol: "rectangle.and.text.magnifyingglass",
                state: departureInvestigationState
            ),
            NarrativeInvestigationStep(
                id: "note.companion",
                title: "不独自行动",
                detail: companionID.isEmpty ? "选择同伴" : companionID,
                symbol: "person.2.fill",
                state: companionID.isEmpty
                    ? (currentMoment.id == "3.companion" ? .active : .locked)
                    : .complete
            ),
            NarrativeInvestigationStep(
                id: "note.door",
                title: "楼梯入口",
                detail: "一起靠近",
                symbol: "door.left.hand.open",
                state: investigationState(momentID: "3.door", hotspotID: "note.paperTrail")
            )
        ]
    }

    private func investigationState(momentID: String, hotspotID: String) -> NarrativeInvestigationStep.State {
        if isComplete || chapter.rawValue > NarrativeChapter.noteTrace.rawValue || completedMomentIDs.contains(momentID) {
            return .complete
        }
        if currentMoment.id == momentID {
            return exploration.lastInteractedHotspot == hotspotID ? .complete : .active
        }
        return .locked
    }

    private var departureInvestigationState: NarrativeInvestigationStep.State {
        if isComplete || chapter.rawValue > NarrativeChapter.noteTrace.rawValue || completedMomentIDs.contains("3.locate") {
            return .complete
        }
        if currentMoment.id == "3.locate" {
            return noteTraceDepartureClues == Set(NoteTraceDepartureClue.allCases) ? .complete : .active
        }
        return .locked
    }

    var shouldPresentRiskEducationCard: Bool {
        currentMoment.id == "4.risk" && jiangDialogueState?.educationCardDismissed != true
    }

    var currentJiangDialoguePerformanceBeat: NarrativeDialoguePerformanceBeat? {
        jiangDialogueState?.performanceBeats.last
    }

    var companionPresenceStatus: NarrativeCompanionPresenceStatus? {
        guard companionID.isEmpty == false,
              [.noteTrace, .stairwell, .counseling].contains(chapter) else { return nil }

        let usesPhone = companionID == "周予安"
        let carryover = MirrorDialogueCarryoverModel.derive(from: self)
        switch chapter {
        case .noteTrace:
            return NarrativeCompanionPresenceStatus(
                companionID: companionID,
                mode: .following,
                title: "\(companionID)跟在半步外",
                detail: currentMoment.id == "3.companion"
                    ? "选择后会一起靠近，不让苏念独自判断。"
                    : carryover.isActive
                        ? "\(carryover.title) · \(carryover.companionHint)"
                        : "沿着纸条找线索时，\(companionID)保持可见距离。",
                symbol: "figure.2.and.child.holdinghands",
                navigationLine: companionNavigationLine
            )
        case .stairwell:
            let supportContinuity = carryover.isActive ? carryover.supportBiasText : nil
            let contactDetail = (usesPhone
                ? "只说明楼层、位置和需要成人到场。"
                : "只发出位置和需要成人到场的信息。")
                + (supportContinuity.map { " · \($0)" } ?? "")
            let boundaryDetail = (safetyHandoffState?.adultContactInitiated == true
                ? "成人到场后，\(companionID)退到能看见门口的位置。"
                : "同伴不评估风险，只维持空间和联络边界。")
                + (supportContinuity.map { " · \($0)" } ?? "")
            if currentMoment.id == "4.contact", safetyHandoffState?.adultContactInitiated != true {
                return NarrativeCompanionPresenceStatus(
                    companionID: companionID,
                    mode: .contactingAdult,
                    title: usesPhone ? "周予安准备拨电话" : "许栀准备发消息",
                    detail: contactDetail,
                    symbol: usesPhone ? "phone.arrow.up.right.fill" : "message.badge.filled.fill"
                )
            }
            return NarrativeCompanionPresenceStatus(
                companionID: companionID,
                mode: .boundary,
                title: usesPhone ? "周予安守在入口" : "许栀退到角落",
                detail: boundaryDetail,
                symbol: "shield.lefthalf.filled"
            )
        case .counseling:
            let supportContinuity = carryover.isActive ? " · \(carryover.supportBiasText)" : ""
            if currentMoment.id == "5.rumor", counselingState?.rumorHandled != true {
                return NarrativeCompanionPresenceStatus(
                    companionID: companionID,
                    mode: .privacyGuard,
                    title: companionID == "周予安" ? "周予安先站起来" : "许栀挡住猜测",
                    detail: "同伴把围观挡在门外，不说出江越的位置或内容。\(supportContinuity)",
                    symbol: "lock.shield.fill"
                )
            }
            return NarrativeCompanionPresenceStatus(
                companionID: companionID,
                mode: .waiting,
                title: "\(companionID)还在等候区",
                detail: (counselingState?.companionMessageReplied == true
                    ? "消息已经回给林澈，支持网络没有断。"
                    : "等待也是把支持交给可靠空间的一部分。")
                    + supportContinuity,
                symbol: "person.2.wave.2.fill"
            )
        default:
            return nil
        }
    }

    private var companionNavigationLine: String? {
        guard chapter == .noteTrace,
              companionID.isEmpty == false,
              currentMoment.id != "3.companion",
              let hotspot = requiredInteractionHotspots.first else { return nil }
        let dx = hotspot.x - exploration.positionX
        let dz = hotspot.z - exploration.positionZ
        let distance = hypot(dx, dz)
        let roundedDistance = (distance * 10).rounded() / 10
        if distance <= hotspot.radius {
            return "\(companionID)低声确认：就在这里，先按 E 确认。"
        }
        let direction: String
        if abs(dx) > abs(dz) {
            direction = dx > 0 ? "右侧" : "左侧"
        } else {
            direction = dz > 0 ? "前方" : "后方"
        }
        return "\(companionID)压低声音：\(hotspot.title)在\(direction)，还差 \(roundedDistance)m。"
    }

    var jiangDialoguePerformanceSupport: Double {
        guard let beats = jiangDialogueState?.performanceBeats, beats.isEmpty == false else { return 0 }
        let total = beats.map(\.supportWeight).reduce(0, +)
        return min(1, total / Double(beats.count))
    }

    var jiangDialoguePerformanceRupture: Double {
        guard let beats = jiangDialogueState?.performanceBeats, beats.isEmpty == false else { return 0 }
        let total = beats.map(\.ruptureWeight).reduce(0, +)
        return min(1, total / Double(beats.count))
    }

    var interactionHotspots: [NarrativeHotspot] {
        var hotspots = NarrativeHotspot.all(for: chapter)
        if currentMoment.id == "3.companion", companionID.isEmpty {
            hotspots.append(contentsOf: [
                NarrativeHotspot(
                    id: "companion.zhou",
                    title: "周予安",
                    prompt: "周予安点点头：好，我跟你去。",
                    x: -1.8,
                    z: 0.25,
                    radius: 1.5,
                    choiceID: "zhou"
                ),
                NarrativeHotspot(
                    id: "companion.xu",
                    title: "许栀",
                    prompt: "许栀把声音放轻：我跟你去，我不多说话。",
                    x: 1.8,
                    z: 0.25,
                    radius: 1.5,
                    choiceID: "xu"
                )
            ])
        }
        if currentMoment.id == "4.contact", safetyHandoffState?.adultContactInitiated != true {
            let isZhou = companionID == "周予安"
            hotspots.append(NarrativeHotspot(
                id: isZhou ? "handoff.zhouCall" : "handoff.xuMessage",
                title: isZhou ? "请周予安打电话" : "请许栀发消息",
                prompt: isZhou
                    ? "周予安复述了楼层和位置，没有转述江越说过的话。"
                    : "许栀只发出位置和需要成人到场的信息，然后退开一步。",
                x: isZhou ? -2.25 : 2.75,
                z: isZhou ? 3.45 : -0.35,
                radius: 1.5,
                choiceID: "contactAdult"
            ))
        }
        if currentMoment.id == "4.handoff" {
            hotspots.append(NarrativeHotspot(
                id: "handoff.teacher",
                title: "方老师",
                prompt: "方老师来到江越所在的平台，先明确说：接下来由大人接手。",
                x: -1.15,
                z: 0.1,
                radius: 1.45
            ))
        }
        if currentMoment.id == "5.rumor", counselingState?.rumorHandled != true,
           counselingState?.entryMode != .emergencyClosure {
            hotspots.append(NarrativeHotspot(
                id: "counseling.rumor",
                title: "走廊里的议论",
                prompt: companionID == "周予安"
                    ? "周予安先站起来：各自去忙吧，别在这里猜。"
                    : "你把谈话挡在门外，没有说出任何人的位置或情况。",
                x: -2.45,
                z: 1.35,
                radius: 1.35,
                choiceID: "privacy"
            ))
        }
        if currentMoment.id == "5.message", counselingState?.companionMessageReplied != true {
            hotspots.append(NarrativeHotspot(
                id: "counseling.phone",
                title: "林澈的消息",
                prompt: "你只回复了可以一起等待和找老师，没有透露江越的情况。",
                x: 0,
                z: 0.45,
                radius: 1.25,
                choiceID: "message"
            ))
        }
        if let miniGame = currentMoment.miniGame, miniGameCompleted == false {
            hotspots.append(mirrorLightHotspot(for: miniGame))
        }
        return hotspots.sorted { lhs, rhs in
            let lhsPriority = lhs.choiceID == nil ? 1 : 0
            let rhsPriority = rhs.choiceID == nil ? 1 : 0
            return lhsPriority < rhsPriority
        }
    }

    private func mirrorLightHotspot(for miniGame: NarrativeMiniGame) -> NarrativeHotspot {
        switch miniGame {
        case .trace:
            return NarrativeHotspot(
                id: "mirror.light.trace",
                title: "草稿灯",
                prompt: "草稿灯在镜面左侧轻轻闪烁，等你把第一段线接起来。",
                x: -1.18,
                z: -2.42,
                radius: 1.15,
                choiceID: "playTrace"
            )
        case .melody:
            return NarrativeHotspot(
                id: "mirror.light.melody",
                title: "旋律灯",
                prompt: "旋律灯把风扇声折成四拍，等你靠近以后再回应。",
                x: 0,
                z: -2.42,
                radius: 1.15,
                choiceID: "playMelody"
            )
        case .erase:
            return NarrativeHotspot(
                id: "mirror.light.erase",
                title: "擦痕灯",
                prompt: "擦痕灯浮出那些比较的话，靠近以后再慢慢擦掉。",
                x: 1.18,
                z: -2.42,
                radius: 1.15,
                choiceID: "playErase"
            )
        }
    }

    var nearbyHotspot: NarrativeHotspot? {
        exploration.nearbyHotspot(in: interactionHotspots)
    }

    var worldDirectorSignal: NarrativeWorldDirectorSignal {
        guard isActive else { return .idle }
        let momentID = currentMoment.id

        func impacted(_ signal: NarrativeWorldDirectorSignal) -> NarrativeWorldDirectorSignal {
            guard let impact = activeChoiceImpact else { return signal }
            let signalIDs = Set(impact.signalIDs)
            var ambientTension = signal.ambientTension
            var supportPresence = signal.supportPresence
            var privacyBoundary = signal.privacyBoundary
            var witnessPressure = signal.witnessPressure
            var safetyResponse = signal.safetyResponse
            var cue = signal.cue

            if signalIDs.contains("risk") {
                ambientTension += 0.18
                witnessPressure += 0.12
                cue = .risk
            }
            if signalIDs.contains("support") {
                supportPresence += 0.16
                if signalIDs.contains("risk") == false { cue = .support }
            }
            if signalIDs.contains("selfCare") {
                ambientTension -= 0.08
                supportPresence += 0.08
                if signalIDs.contains("risk") == false { cue = .support }
            }
            if signalIDs.contains("privacy") || signalIDs.contains("boundary") {
                privacyBoundary += 0.18
                cue = .privacy
            }
            if signalIDs.contains("adult") || signalIDs.contains("safety") {
                safetyResponse += 0.22
                privacyBoundary += 0.08
                cue = .safetyResponse
            }
            if signalIDs.contains("investigate") || signalIDs.contains("observe") || signalIDs.contains("route") || signalIDs.contains("mirror") {
                ambientTension += 0.04
                witnessPressure += 0.06
                if signalIDs.contains("risk") == false { cue = .investigation }
            }

            return NarrativeWorldDirectorSignal(
                ambientTension: ambientTension.clamped(to: 0...1),
                supportPresence: supportPresence.clamped(to: 0...1),
                privacyBoundary: privacyBoundary.clamped(to: 0...1),
                witnessPressure: witnessPressure.clamped(to: 0...1),
                safetyResponse: safetyResponse.clamped(to: 0...1),
                cue: cue
            )
        }

        switch chapter {
        case .classroom:
            return impacted(NarrativeWorldDirectorSignal(
                ambientTension: 0.22 + Double(momentIndex) * 0.045,
                supportPresence: selfCared ? 0.36 : 0.14,
                privacyBoundary: 0.18,
                witnessPressure: momentID == "1.listen" ? 0.34 : 0.22,
                safetyResponse: 0,
                cue: momentID == "1.note" ? .investigation : .attention
            ))
        case .mirror:
            let completedLightStrength = min(0.34, Double(miniGameProgress) * 0.055)
            let dissolve = mirrorDissolveProgress
            return impacted(NarrativeWorldDirectorSignal(
                ambientTension: max(0.22, 0.46 + completedLightStrength - dissolve * 0.28),
                supportPresence: min(0.78, 0.16 + Double(linCheTrust) * 0.18 + (momentID == "2.listen" ? 0.22 : 0) + dissolve * 0.16),
                privacyBoundary: 0.24,
                witnessPressure: 0.08,
                safetyResponse: 0,
                cue: dissolve > 0.66 || momentID == "2.listen" ? .support : .investigation
            ))
        case .noteTrace:
            return impacted(NarrativeWorldDirectorSignal(
                ambientTension: momentID == "3.locate" || momentID == "3.door" ? 0.58 : 0.38,
                supportPresence: companionID.isEmpty ? 0.18 : 0.62,
                privacyBoundary: companionID.isEmpty ? 0.22 : 0.34,
                witnessPressure: momentID == "3.companion" ? 0.42 : 0.24,
                safetyResponse: 0,
                cue: companionID.isEmpty ? .investigation : .support
            ))
        case .stairwell:
            let riskWeight: Double
            switch safetyHandoffState?.authoredRisk ?? .moderate {
            case .low: riskWeight = 0.38
            case .moderate: riskWeight = 0.55
            case .high: riskWeight = 0.76
            case .imminent: riskWeight = 0.92
            }
            let adultCalled = safetyHandoffState?.adultContactInitiated == true
            let handoffComplete = safetyHandoffState?.safetyHandoffComplete == true
            let trustRelief = min(0.24, Double(jiangYueTrust) / 260)
            return impacted(NarrativeWorldDirectorSignal(
                ambientTension: max(0.28, riskWeight + 0.18 - trustRelief - (handoffComplete ? 0.34 : adultCalled ? 0.16 : 0)),
                supportPresence: min(0.94, (companionID.isEmpty ? 0.12 : 0.42) + (adultCalled ? 0.22 : 0) + (handoffComplete ? 0.24 : 0)),
                privacyBoundary: adultCalled ? 0.72 : 0.38,
                witnessPressure: 0.1,
                safetyResponse: adultCalled ? (handoffComplete ? 0.88 : 0.58) : 0,
                cue: adultCalled ? .safetyResponse : .risk
            ))
        case .counseling:
            let emergency = counselingState?.entryMode == .emergencyClosure
            let rumorActive = momentID == "5.rumor"
                && counselingState?.rumorHandled != true
                && emergency == false
            let handedOff = counselingState?.supportHandedOff == true
            return impacted(NarrativeWorldDirectorSignal(
                ambientTension: emergency ? 0.54 : rumorActive ? 0.64 : 0.32,
                supportPresence: min(0.92, 0.46 + (counselingState?.handoffConfirmed == true ? 0.18 : 0) + (handedOff ? 0.2 : 0)),
                privacyBoundary: rumorActive ? 0.96 : 0.78,
                witnessPressure: rumorActive ? 0.84 : 0.16,
                safetyResponse: emergency ? 0.92 : counselingState?.entryMode == .urgentHandoffWaiting ? 0.7 : 0.44,
                cue: rumorActive ? .privacy : handedOff ? .support : .safetyResponse
            ))
        case .epilogue:
            return impacted(NarrativeWorldDirectorSignal(
                ambientTension: 0.16,
                supportPresence: sharedSelf ? 0.98 : 0.86,
                privacyBoundary: 0.48,
                witnessPressure: 0.2,
                safetyResponse: 0.62,
                cue: .support
            ))
        }
    }

    var ambientActorDirectives: [NarrativeAmbientActorDirective] {
        guard isActive else { return [] }
        let momentID = currentMoment.id

        switch chapter {
        case .classroom:
            return [
                NarrativeAmbientActorDirective(
                    id: "classroom.monitor.pause",
                    role: .quietWitness,
                    anchorX: -2.4,
                    anchorZ: 0.2,
                    targetX: -1.65,
                    targetZ: -0.35,
                    intensity: momentID == "1.listen" ? 0.58 : 0.34,
                    line: "班长停了一秒，还是没有回头。"
                )
            ]
        case .mirror:
            let dissolve = mirrorDissolveProgress
            return [
                NarrativeAmbientActorDirective(
                    id: "mirror.linche.echo",
                    role: momentID == "2.listen" ? .quietWitness : .bystander,
                    anchorX: -1.1,
                    anchorZ: -1.8,
                    targetX: -0.55,
                    targetZ: -2.65,
                    intensity: dissolve > 0 ? 0.74 + dissolve * 0.18 : min(0.8, 0.3 + Double(miniGameProgress) * 0.08),
                    line: dissolve > 0
                        ? "林澈的影子转过来，和真实的呼吸对齐。"
                        : "林澈的影子慢慢和呼吸对上。"
                )
            ]
        case .noteTrace:
            return [
                NarrativeAmbientActorDirective(
                    id: "note.monitor.list",
                    role: .quietWitness,
                    anchorX: -2.4,
                    anchorZ: 0.9,
                    targetX: -0.55,
                    targetZ: -1.32,
                    intensity: momentID == "3.note" ? 0.72 : 0.46,
                    line: "有人把值日表重新压平。"
                ),
                NarrativeAmbientActorDirective(
                    id: companionID.isEmpty ? "note.waiting.companions" : "note.chosen.companion",
                    role: companionID.isEmpty ? .bystander : .boundaryKeeper,
                    anchorX: companionID == "许栀" ? 1.8 : -1.8,
                    anchorZ: 0.25,
                    targetX: exploration.positionX,
                    targetZ: exploration.positionZ + 1.25,
                    intensity: companionID.isEmpty ? 0.36 : 0.68,
                    line: companionID.isEmpty ? "两个可靠的人都还在等你开口。" : "\(companionID)和你保持半步距离。"
                )
            ]
        case .stairwell:
            let adultCalled = safetyHandoffState?.adultContactInitiated == true
            let handoffComplete = safetyHandoffState?.safetyHandoffComplete == true
            var directives = [
                NarrativeAmbientActorDirective(
                    id: "stairs.boundary.companion",
                    role: adultCalled ? .boundaryKeeper : .messenger,
                    anchorX: companionID == "许栀" ? 2.75 : -2.25,
                    anchorZ: companionID == "许栀" ? -0.35 : 3.45,
                    targetX: adultCalled ? (companionID == "许栀" ? 2.45 : -1.95) : (companionID == "许栀" ? 2.75 : -2.25),
                    targetZ: adultCalled ? (companionID == "许栀" ? -0.8 : 2.9) : (companionID == "许栀" ? -0.35 : 3.45),
                    intensity: adultCalled ? 0.76 : 0.54,
                    line: adultCalled ? "\(companionID)退到能看见门口的位置。" : "\(companionID)准备只说明位置和需要成人到场。"
                )
            ]
            if adultCalled {
                directives.append(NarrativeAmbientActorDirective(
                    id: handoffComplete ? "stairs.teacher.handoff" : "stairs.teacher.arriving",
                    role: handoffComplete ? .facilitator : .supportRunner,
                    anchorX: -2.8,
                    anchorZ: 4.6,
                    targetX: -1.15,
                    targetZ: 0.1,
                    intensity: handoffComplete ? 0.92 : 0.7,
                    line: "方老师沿着楼梯平台放慢脚步。"
                ))
            }
            return directives
        case .counseling:
            let emergency = counselingState?.entryMode == .emergencyClosure
            let rumorActive = momentID == "5.rumor"
                && counselingState?.rumorHandled != true
                && emergency == false
            let handedOff = counselingState?.supportHandedOff == true
            if rumorActive {
                return [
                    NarrativeAmbientActorDirective(
                        id: "counseling.rumor.left",
                        role: .bystander,
                        anchorX: -3.1,
                        anchorZ: 2.4,
                        targetX: -2.45,
                        targetZ: 1.35,
                        intensity: 0.84,
                        line: "路过同学把声音压低，却还停在门外。"
                    ),
                    NarrativeAmbientActorDirective(
                        id: "counseling.rumor.right",
                        role: .bystander,
                        anchorX: -2.95,
                        anchorZ: 3.2,
                        targetX: -1.8,
                        targetZ: 1.72,
                        intensity: 0.72,
                        line: "第二个人犹豫着靠近，又看见了边界线。"
                    ),
                    NarrativeAmbientActorDirective(
                        id: "counseling.privacy.companion",
                        role: .boundaryKeeper,
                        anchorX: companionID == "许栀" ? 1.45 : -1.45,
                        anchorZ: -0.65,
                        targetX: -0.95,
                        targetZ: 0.08,
                        intensity: 0.88,
                        line: "\(companionID.isEmpty ? "同伴" : companionID)先站起来，把猜测挡在门外。"
                    )
                ]
            }
            if handedOff {
                return [
                    NarrativeAmbientActorDirective(
                        id: "counseling.teacher.confirm",
                        role: .facilitator,
                        anchorX: 2.4,
                        anchorZ: -2.8,
                        targetX: 1.25,
                        targetZ: -2.1,
                        intensity: 0.82,
                        line: "成人确认交接已经完成。"
                    ),
                    NarrativeAmbientActorDirective(
                        id: "counseling.quiet.wait",
                        role: .quietWitness,
                        anchorX: -1.45,
                        anchorZ: -0.65,
                        targetX: -0.8,
                        targetZ: -0.82,
                        intensity: 0.5,
                        line: "等候区终于重新安静下来。"
                    )
                ]
            }
            return [
                NarrativeAmbientActorDirective(
                    id: emergency ? "counseling.safety.office" : "counseling.waiting.lamp",
                    role: emergency ? .supportRunner : .quietWitness,
                    anchorX: 2.65,
                    anchorZ: -1.35,
                    targetX: 2.1,
                    targetZ: -1.75,
                    intensity: emergency ? 0.78 : 0.42,
                    line: emergency ? "走廊尽头有人接起校内应急电话。" : "灯亮着，门外的人都把声音放轻。"
                )
            ]
        case .epilogue:
            return [
                NarrativeAmbientActorDirective(
                    id: "epilogue.support.circle",
                    role: .facilitator,
                    anchorX: -1.8,
                    anchorZ: -1.8,
                    targetX: -0.7,
                    targetZ: -1.45,
                    intensity: sharedSelf ? 0.92 : 0.74,
                    line: "支持网络从一个点连成一圈。"
                ),
                NarrativeAmbientActorDirective(
                    id: "epilogue.peer.light",
                    role: .quietWitness,
                    anchorX: 1.8,
                    anchorZ: -1.8,
                    targetX: 0.7,
                    targetZ: -1.45,
                    intensity: 0.68,
                    line: "有人站在光外，也被照见。"
                )
            ]
        }
    }

    var consequenceEchoes: [NarrativeConsequenceEcho] {
        guard isActive || isComplete else { return [] }
        var echoes: [NarrativeConsequenceEcho] = []

        echoes.append(NarrativeConsequenceEcho(
            id: "echo.noticed",
            kind: .noticed,
            title: "看见不是诊断",
            trace: clueCount > 0 ? "你带着 \(clueCount) 条线索走到后面，而不是替任何人下结论。" : "你仍在学习先观察，再开口。",
            strength: min(1, 0.28 + Double(max(0, clueCount)) / 7.0),
            symbol: "eye"
        ))

        if companionID.isEmpty == false {
            echoes.append(NarrativeConsequenceEcho(
                id: "echo.companion.\(companionID)",
                kind: .companion,
                title: "不是一个人承担",
                trace: "\(companionID)的在场让楼梯间和等候区都多了一道边界。",
                strength: 0.78,
                symbol: "person.2.fill"
            ))
        } else {
            echoes.append(NarrativeConsequenceEcho(
                id: "echo.companion.none",
                kind: .companion,
                title: "同伴仍未接上",
                trace: "这条支持线还没有稳定形成，后续更需要成人接手。",
                strength: 0.34,
                symbol: "person.crop.circle.badge.questionmark"
            ))
        }

        let riskTrace: (String, Double, String)
        switch jiangDialogueState?.riskAskMethod {
        case .direct:
            riskTrace = ("你直接问清安全风险，没有把含糊的话当成没事。", 0.92, "shield.lefthalf.filled")
        case .gentle:
            riskTrace = ("你先温和确认含义，再把风险交给可靠的大人。", 0.76, "bubble.left.and.text.bubble.right")
        case .deferToAdult:
            riskTrace = ("信息不完整时，你没有硬撑，而是先让成人到场。", 0.68, "person.badge.shield.checkmark.fill")
        case .some(.none), nil:
            riskTrace = ("风险没有被学生单独评估，成人接手成为关键。", 0.48, "shield")
        }
        echoes.append(NarrativeConsequenceEcho(
            id: "echo.risk.\(jiangDialogueState?.riskAskMethod.rawValue ?? "none")",
            kind: .riskQuestion,
            title: "安全被说清楚",
            trace: riskTrace.0,
            strength: riskTrace.1,
            symbol: riskTrace.2
        ))

        let rumorOutcome = counselingState?.rumorOutcome
        echoes.append(NarrativeConsequenceEcho(
            id: "echo.privacy.\(rumorOutcome?.rawValue ?? "held")",
            kind: .privacy,
            title: "隐私没有被拿来交换解释",
            trace: rumorOutcome == .suppressed
                ? "你把猜测挡在门外，让江越不用被路过的人重新讲述。"
                : "你把关注拉回边界，没有公开任何人的位置或谈话。",
            strength: privacyProtected ? 0.9 : 0.42,
            symbol: "lock.fill"
        ))

        echoes.append(NarrativeConsequenceEcho(
            id: selfCared ? "echo.selfcare.present" : "echo.selfcare.missing",
            kind: .selfCare,
            title: selfCared ? "你也被放进支持网络" : "自我照顾仍在提醒你",
            trace: selfCared
                ? "那一次停下来喝水或呼吸，后来变成你愿意坐下来的理由。"
                : "你一路照顾别人，但终章仍会提醒你也需要被接住。",
            strength: selfCared ? 0.86 : 0.46,
            symbol: selfCared ? "heart.text.square.fill" : "heart"
        ))

        if let route = safetyHandoffState?.route {
            echoes.append(NarrativeConsequenceEcho(
                id: "echo.handoff.\(route.rawValue)",
                kind: .handoff,
                title: "责任被交到能负责的人手里",
                trace: "安全路线进入「\(route.displayName)」，学生不再独自承担评估。",
                strength: route == .standardCounseling ? 0.76 : route == .urgentSchoolResponse ? 0.9 : 1,
                symbol: "figure.walk.motion"
            ))
        }

        return echoes
    }

    var empathyReplayBeats: [NarrativeEmpathyReplayBeat] {
        guard isActive || isComplete else { return [] }

        let clueStrength = min(1, Double(max(0, clueCount)) / 5.0)
        let listenResponses = jiangDialogueState?.responseKinds.filter {
            [.listening, .accompanying, .silentPresence].contains($0)
        }.count ?? 0
        let hurtfulResponses = jiangDialogueState?.responseKinds.filter {
            [.judgmental, .inspirational, .advisory].contains($0)
        }.count ?? 0
        let listeningScore = min(1, 0.24 + Double(listenResponses) * 0.18 - Double(hurtfulResponses) * 0.08)

        let riskScore: Double
        let riskTrace: String
        switch jiangDialogueState?.riskAskMethod {
        case .direct:
            riskScore = 0.95
            riskTrace = "直接确认是否安全"
        case .gentle:
            riskScore = 0.78
            riskTrace = "先温和确认含义"
        case .deferToAdult:
            riskScore = 0.7
            riskTrace = "不硬撑，先让成人到场"
        case .some(.none), nil:
            riskScore = 0.44
            riskTrace = "风险没有被学生说清"
        }

        let handoffScore: Double
        let handoffResponse: String
        switch safetyHandoffState?.route {
        case .emergencyServices:
            handoffScore = 1
            handoffResponse = "紧急服务接管，学生退出评估位"
        case .urgentSchoolResponse:
            handoffScore = 0.9
            handoffResponse = "校内紧急支持接手现场"
        case .standardCounseling:
            handoffScore = 0.74
            handoffResponse = "咨询室陪同成为下一步"
        case nil:
            handoffScore = 0.36
            handoffResponse = "成人交接仍未稳定落地"
        }

        let privacyScore = privacyProtected ? 0.88 : 0.32
        let selfScore = sharedSelf ? 0.9 : (selfCared ? 0.68 : 0.42)

        return [
            NarrativeEmpathyReplayBeat(
                id: "replay.observe",
                kind: .observation,
                chapterTitle: "第一章 · 看见",
                playerTrace: clueCount > 0 ? "记录 \(clueCount) 条线索，没有替纸条猜作者" : "还停在模糊的担心里",
                systemPressure: "教室把异常压进翻书声和座位秩序",
                supportResponse: clueCount > 0 ? "苏念开始用证据靠近他人" : "支持网络尚未成形",
                empathyScore: max(0.28, clueStrength),
                tensionScore: 0.42,
                symbol: "eye"
            ),
            NarrativeEmpathyReplayBeat(
                id: "replay.connect",
                kind: .connection,
                chapterTitle: "第二、三章 · 连接",
                playerTrace: companionID.isEmpty ? "独自追踪纸条" : "邀请 \(companionID) 一起靠近",
                systemPressure: "未知会诱导学生把自己放进英雄位置",
                supportResponse: companionID.isEmpty ? "成人接手会变得更关键" : "同伴成为边界和见证",
                empathyScore: companionID.isEmpty ? 0.38 : 0.78,
                tensionScore: companionID.isEmpty ? 0.68 : 0.46,
                symbol: "person.2.fill"
            ),
            NarrativeEmpathyReplayBeat(
                id: "replay.risk",
                kind: .risk,
                chapterTitle: "第四章 · 风险",
                playerTrace: "\(riskTrace)，倾听回应 \(listenResponses) 次",
                systemPressure: "楼梯间让学生误以为必须立刻解决一切",
                supportResponse: "风险事实进入成人交接，而不是同伴诊断",
                empathyScore: min(1, (riskScore + listeningScore) / 2),
                tensionScore: 0.92,
                symbol: "shield.lefthalf.filled"
            ),
            NarrativeEmpathyReplayBeat(
                id: "replay.handoff",
                kind: .handoff,
                chapterTitle: "第四、五章 · 交接",
                playerTrace: safetyHandoffState?.contactMethod.isEmpty == false ? "用\(safetyHandoffState?.contactMethod ?? "联络")只说明位置和需要成人" : "还没有稳定联络成人",
                systemPressure: "责任边界如果不清，会落回学生身上",
                supportResponse: handoffResponse,
                empathyScore: handoffScore,
                tensionScore: safetyHandoffState?.route == .emergencyServices ? 1 : 0.74,
                symbol: "figure.walk.motion"
            ),
            NarrativeEmpathyReplayBeat(
                id: "replay.boundary",
                kind: .boundary,
                chapterTitle: "第五章 · 边界",
                playerTrace: counselingState?.rumorOutcome == .suppressed ? "把猜测挡在门外" : "把关注拉回安静和边界",
                systemPressure: "围观会把被照顾的人重新推回叙事中心",
                supportResponse: privacyProtected ? "隐私被保护，等待变得可承受" : "边界仍需要有人继续守住",
                empathyScore: privacyScore,
                tensionScore: privacyProtected ? 0.38 : 0.72,
                symbol: "lock.fill"
            ),
            NarrativeEmpathyReplayBeat(
                id: "replay.self",
                kind: .selfReflection,
                chapterTitle: "第六章 · 自己",
                playerTrace: sharedSelf ? "苏念也把疲惫说出口" : (selfCared ? "苏念至少给自己留过一次停顿" : "苏念还习惯只照顾别人"),
                systemPressure: "帮助者也会被消耗，只是常常更安静",
                supportResponse: sharedSelf ? "支持网络把苏念也放进去" : "门仍然开着，下次也可以",
                empathyScore: selfScore,
                tensionScore: selfCared ? 0.34 : 0.58,
                symbol: sharedSelf ? "heart.text.square.fill" : "heart"
            )
        ]
    }

    var truthReplayReveals: [NarrativeTruthReplayReveal] {
        guard isActive || isComplete else { return [] }

        let noticedStrength = min(1, 0.28 + Double(max(0, clueCount)) / 6.0)
        let helpfulResponses = jiangDialogueState?.responseKinds.filter {
            [.listening, .accompanying, .silentPresence].contains($0)
        }.count ?? 0
        let disclosureStrength: Double
        switch jiangDialogueState?.disclosedRisk {
        case .confirmed:
            disclosureStrength = 0.94
        case .partial:
            disclosureStrength = 0.74
        case .unknown, nil:
            disclosureStrength = 0.48
        }
        let handoffStrength: Double
        switch safetyHandoffState?.route {
        case .emergencyServices: handoffStrength = 1
        case .urgentSchoolResponse: handoffStrength = 0.9
        case .standardCounseling: handoffStrength = 0.74
        case nil: handoffStrength = 0.36
        }

        return [
            NarrativeTruthReplayReveal(
                id: "truth.teacher",
                perspective: .teacher,
                apparentRead: "表面看起来只是晚自习里的纸条、走动和停顿。",
                hiddenTruth: clueCount > 0
                    ? "这些动作背后有 \(clueCount) 条求助线索，不是纪律问题本身。"
                    : "异常还没有被稳定看见，最容易被误读成普通分心。",
                repairAction: safetyHandoffState?.adultContactInitiated == true
                    ? "成人只接收位置和安全事实，开始承担责任。"
                    : "下一步仍需要可靠成人进入现场。",
                revealStrength: max(noticedStrength, handoffStrength * 0.78),
                symbol: "person.crop.rectangle.badge.magnifyingglass"
            ),
            NarrativeTruthReplayReveal(
                id: "truth.linche",
                perspective: .linChe,
                apparentRead: "林澈像是在逃离教室，也像不愿解释纸条。",
                hiddenTruth: "他真正需要的是有人不急着追问，也不替纸条下结论。",
                repairAction: companionID.isEmpty
                    ? "支持线还缺一个同伴见证。"
                    : "\(companionID)加入后，追踪不再像单人冒险。",
                revealStrength: companionID.isEmpty ? 0.46 : 0.82,
                symbol: "rectangle.inset.filled.and.person.filled"
            ),
            NarrativeTruthReplayReveal(
                id: "truth.jiangyue",
                perspective: .jiangYue,
                apparentRead: "江越的含糊表达很容易被听成矫情、拖延或不配合。",
                hiddenTruth: helpfulResponses > 0
                    ? "他在 \(helpfulResponses) 次被接住的回应后，才有空间把风险说近一点。"
                    : "他几乎没有得到足够安全的倾听空间。",
                repairAction: safetyHandoffState?.route == nil
                    ? "风险仍需要交给成人评估。"
                    : "风险进入「\(safetyHandoffState?.route?.displayName ?? "成人支持")」，不是由学生诊断。",
                revealStrength: min(1, (disclosureStrength + handoffStrength) / 2),
                symbol: "ear.badge.checkmark"
            ),
            NarrativeTruthReplayReveal(
                id: "truth.sunian",
                perspective: .suNian,
                apparentRead: "苏念像是那个一直在照顾别人的人。",
                hiddenTruth: sharedSelf
                    ? "她也把自己的疲惫放进会谈里，支持网络终于不是单向流动。"
                    : "她仍可能把自己的疲惫放到最后，像这不值得被看见。",
                repairAction: selfCared
                    ? "自我照护不再只是提示，而是进入结局事实。"
                    : "终章会继续提醒：帮助者也需要被接住。",
                revealStrength: sharedSelf ? 0.92 : (selfCared ? 0.68 : 0.42),
                symbol: sharedSelf ? "heart.text.square.fill" : "heart"
            )
        ]
    }

    var policyExperiments: [NarrativePolicyExperiment] {
        guard isActive || isComplete else { return [] }

        return [
            policyExperiment(
                id: "policy.protected-whisper",
                title: "允许低声求助",
                premise: "晚自习缩短到 90 分钟，保留安静，但允许低声确认状态。",
                studyMinutes: 90,
                allowsWhispering: true,
                rankingPressure: 34,
                patrolFrequency: 36,
                symbol: "bubble.left.and.text.bubble.right.fill"
            ),
            policyExperiment(
                id: "policy.strict-patrol",
                title: "强化排名巡视",
                premise: "三小时满负荷，禁止交流，排名压力和巡视频率同时上调。",
                studyMinutes: 180,
                allowsWhispering: false,
                rankingPressure: 86,
                patrolFrequency: 88,
                symbol: "eye.trianglebadge.exclamationmark.fill"
            ),
            policyExperiment(
                id: "policy.counseling-duty",
                title: "咨询室值班",
                premise: "保留晚自习，但降低排名权重，并让咨询室成为当晚可见出口。",
                studyMinutes: 150,
                allowsWhispering: true,
                rankingPressure: 48,
                patrolFrequency: 46,
                symbol: "person.badge.shield.checkmark.fill"
            )
        ]
    }

    private func policyExperiment(
        id: String,
        title: String,
        premise: String,
        studyMinutes: Double,
        allowsWhispering: Bool,
        rankingPressure: Double,
        patrolFrequency: Double,
        symbol: String
    ) -> NarrativePolicyExperiment {
        let routeStrength: Double
        switch safetyHandoffState?.route {
        case .emergencyServices:
            routeStrength = 1
        case .urgentSchoolResponse:
            routeStrength = 0.88
        case .standardCounseling:
            routeStrength = 0.68
        case nil:
            routeStrength = safetyRoute.isEmpty ? 0.36 : 0.58
        }

        let clueStrength = min(1, Double(max(0, clueCount)) / 5.0)
        let companionStrength = companionID.isEmpty ? 0.18 : 0.74
        let listenResponses = Double(jiangDialogueState?.responseKinds.filter {
            [.listening, .accompanying, .silentPresence].contains($0)
        }.count ?? 0)
        let listeningStrength = min(1, 0.22 + listenResponses * 0.16)
        let minuteLoad = min(1, max(0, (studyMinutes - 60) / 120))

        let pressureIndex = (
            0.22
            + minuteLoad * 0.18
            + rankingPressure / 100 * 0.23
            + patrolFrequency / 100 * 0.19
            + (allowsWhispering ? -0.08 : 0.09)
            + (selfCared ? -0.035 : 0.035)
            + (privacyProtected ? -0.025 : 0.055)
            - routeStrength * 0.045
        ).clamped(to: 0.08...0.98)

        let supportIndex = (
            0.20
            + (allowsWhispering ? 0.17 : -0.05)
            + routeStrength * 0.23
            + companionStrength * 0.18
            + listeningStrength * 0.13
            + (selfCared ? 0.08 : 0.02)
            - rankingPressure / 100 * 0.09
        ).clamped(to: 0.06...0.98)

        let missedSignalRisk = (
            0.60
            + pressureIndex * 0.24
            + (allowsWhispering ? -0.11 : 0.08)
            + (patrolFrequency > 72 ? 0.065 : -0.015)
            - supportIndex * 0.30
            - clueStrength * 0.12
            - routeStrength * 0.11
        ).clamped(to: 0.04...0.96)

        let outcomeLine: String
        if missedSignalRisk < 0.30 {
            outcomeLine = "更多异常会进入支持网络，而不是被解释成纪律问题。"
        } else if pressureIndex > 0.70 {
            outcomeLine = "表面秩序更强，但学生更可能把求助藏回去。"
        } else {
            outcomeLine = "压力仍在，但责任边界比原教室更清楚。"
        }

        return NarrativePolicyExperiment(
            id: id,
            title: title,
            premise: premise,
            scheduleText: "\(Int(studyMinutes)) 分钟 · 排名 \(Int(rankingPressure)) · 巡视 \(Int(patrolFrequency))",
            ruleText: allowsWhispering ? "允许低声确认" : "禁止交流",
            pressureIndex: pressureIndex,
            supportIndex: supportIndex,
            missedSignalRisk: missedSignalRisk,
            outcomeLine: outcomeLine,
            symbol: symbol
        )
    }

    static func moments(for chapter: NarrativeChapter) -> [NarrativeMoment] {
        switch chapter {
        case .classroom:
            return [
                NarrativeMoment(id: "1.observe", title: "同一页", goal: "看看林澈今晚在做什么", body: "左边的错题本停在同一页很久。林澈的指尖压着折角，像在等一个不会来的下课铃。", speaker: "苏念", choices: [NarrativeChoice(id: "notice", title: "先看一眼", detail: "不急着解释，只把这个细节记住", symbol: "eye")], miniGame: nil),
                NarrativeMoment(id: "1.listen", title: "被翻书声盖住", goal: "听清右侧那道声音", body: "翻书声里有一次短促的抽气。你不确定是谁，也不需要立刻给它命名。", speaker: "苏念", choices: [NarrativeChoice(id: "listen", title: "停下来听", detail: "让环境声慢一点", symbol: "ear")], miniGame: nil),
                NarrativeMoment(id: "1.regulate", title: "先让自己缓一下", goal: "选择一种自我照顾", body: "你也在这间教室里。把自己稳定下来，不是把别人的事推开。", speaker: "苏念", choices: [NarrativeChoice(id: "breathe", title: "慢慢呼吸", detail: "把注意力放回身体", symbol: "lungs.fill"), NarrativeChoice(id: "water", title: "喝一口水", detail: "给自己一个短暂停顿", symbol: "cup.and.saucer.fill")], miniGame: nil),
                NarrativeMoment(id: "1.ask", title: "一句低压力的话", goal: "在下课前靠近林澈", body: "林澈抬头，又很快低下去。你不需要逼他解释，只要给他一个能停下来的位置。", speaker: "苏念", choices: [NarrativeChoice(id: "openQuestion", title: "“要不要一起去走廊透口气？”", detail: "给选择，不追问", symbol: "bubble.left.and.bubble.right"), NarrativeChoice(id: "stay", title: "“我在这儿。”", detail: "把陪伴说得很轻", symbol: "person.2.fill")], miniGame: nil),
                NarrativeMoment(id: "1.note", title: "不署名纸条", goal: "确认落在桌边的纸条", body: "纸条上写着：心里很难受，但我不知道找谁说。署名处是一片空白。", speaker: "苏念", choices: [NarrativeChoice(id: "takeNote", title: "把纸条收好", detail: "不替它猜作者", symbol: "doc.text.fill")], miniGame: nil),
                NarrativeMoment(id: "1.follow", title: "走向门口", goal: "别让林澈一个人离开", body: "铃声切开教室。林澈背着包先走出去，走廊尽头那面镜子反着冷光。", speaker: "苏念", choices: [NarrativeChoice(id: "follow", title: "跟上林澈", detail: "下一章：走廊的镜子", symbol: "figure.walk")], miniGame: nil)
            ]
        case .mirror:
            return [
                NarrativeMoment(id: "2.enter", title: "镜面里的人", goal: "走进走廊尽头的镜像", body: "镜子没有照出另一个你，而是把走廊拉得更长。林澈站在里面，像在听某种只有他听得见的回声。", speaker: "林澈", choices: [NarrativeChoice(id: "enterMirror", title: "靠近镜面", detail: "不把恐惧当成谜题", symbol: "rectangle.inset.filled.and.person.filled")], miniGame: nil),
                NarrativeMoment(id: "2.trace", title: "草稿灯", goal: "让一条线回到它该去的地方", body: "第一盏灯在闪。把零散的笔迹接起来，不需要画得漂亮，只要让它能继续往前。", speaker: "苏念", choices: [NarrativeChoice(id: "playTrace", title: "开始描线", detail: "按顺序点亮六个节点", symbol: "pencil.line")], miniGame: .trace),
                NarrativeMoment(id: "2.melody", title: "旋律灯", goal: "听见并回应一段节奏", body: "第二盏灯把风扇声变成四拍节奏。你可以重复它，也可以让苏念慢慢完成。", speaker: "林澈", choices: [NarrativeChoice(id: "playMelody", title: "接住节奏", detail: "按亮四个音符", symbol: "music.note")], miniGame: .melody),
                NarrativeMoment(id: "2.erase", title: "擦痕灯", goal: "把不属于他的句子擦掉", body: "第三盏灯上浮出一行又一行“你应该没事”。你不必说服任何人，只要把这些话擦掉。", speaker: "苏念", choices: [NarrativeChoice(id: "playErase", title: "擦掉它们", detail: "点掉六个词片", symbol: "eraser.fill")], miniGame: .erase),
                NarrativeMoment(id: "2.listen", title: "没有标准答案", goal: "选择怎样回应林澈", body: "林澈说：我不是想消失，我只是很累。镜子里的走廊终于停下来。", speaker: "林澈", choices: [NarrativeChoice(id: "reassure", title: "“你不用一个人把它扛完。”", detail: "给他空间和时间", symbol: "heart.fill"), NarrativeChoice(id: "invite", title: "“要不要一起找可靠的大人？”", detail: "把支持交给更多人", symbol: "person.3.fill"), NarrativeChoice(id: "present", title: "先陪他站一会儿", detail: "不急着解决", symbol: "figure.stand")], miniGame: nil)
            ]
        case .noteTrace:
            return [
                NarrativeMoment(id: "3.note", title: "纸条的折痕", goal: "沿着纸条找回线索", body: "纸条角落有一小段被撕掉的班级值日表。林澈说，他在楼梯口见过江越。", speaker: "林澈", choices: [NarrativeChoice(id: "inspectFold", title: "对照值日表", detail: "确认线索，而不是确认结论", symbol: "doc.on.doc")], miniGame: nil),
                NarrativeMoment(id: "3.locate", title: "空着的位置", goal: "确认江越在哪里", body: "走廊的窗户开着一条缝。远处传来楼梯门的回弹声，江越的座位一直是空的。", speaker: "苏念", choices: [NarrativeChoice(id: "locateJiang", title: "去楼梯间看看", detail: "先通知同伴，不独自判断", symbol: "location.magnifyingglass")], miniGame: nil),
                NarrativeMoment(id: "3.companion", title: "一起走", goal: "选择一位可靠同伴", body: "在这种时候，陪伴不是一个人扮演英雄。你想找谁一起去？", speaker: "苏念", choices: [NarrativeChoice(id: "zhou", title: "找周予安", detail: "他做事稳，愿意先听", symbol: "person.fill"), NarrativeChoice(id: "xu", title: "找许栀", detail: "她能留意到别人没说出的部分", symbol: "person.fill")], miniGame: nil),
                NarrativeMoment(id: "3.door", title: "十三楼的门", goal: "到达楼梯间", body: "你们在安全门前停下。门后没有戏剧化的答案，只有一个需要慢慢靠近的人。", speaker: "苏念", choices: [NarrativeChoice(id: "openDoor", title: "轻轻推开门", detail: "下一章：十三楼的缝隙", symbol: "door.left.hand.open")], miniGame: nil)
            ]
        case .stairwell:
            return [
                NarrativeMoment(id: "4.arrive", title: "楼梯间", goal: "先让江越知道你们来了", body: "江越坐在平台上，背对着门。你看见他，不能代表你已经知道发生了什么。", speaker: "苏念", choices: [NarrativeChoice(id: "announce", title: "“江越，我们在这儿。”", detail: "先报出自己的位置", symbol: "speaker.wave.2.fill")], miniGame: nil),
                NarrativeMoment(id: "4.listen", title: "先听，再问", goal: "给江越说话的空间", body: "他断断续续地说起睡不着、害怕明天、害怕被当成麻烦。你们没有打断。", speaker: "江越", choices: [NarrativeChoice(id: "listenJiang", title: "保持安静地听", detail: "不急着评价或承诺", symbol: "ear.and.waveform")], miniGame: nil),
                NarrativeMoment(id: "4.risk", title: "把安全说清楚", goal: "用直接但温和的话确认风险", body: "关心不是猜测。你可以直接问他现在是否安全，并告诉他不会被一个人留下。", speaker: "苏念", choices: [NarrativeChoice(id: "askGentle", title: "“你说的‘算了’，具体是什么意思？”", detail: "温和确认，不替他补完答案", symbol: "bubble.left.and.text.bubble.right"), NarrativeChoice(id: "askSafety", title: "“你现在有没有伤害自己的打算？”", detail: "清楚地问，不诱导也不评判", symbol: "shield.lefthalf.filled"), NarrativeChoice(id: "adultNow", title: "“你不用先解释清楚。”", detail: "信息不完整也要让可靠成人到场", symbol: "person.badge.shield.checkmark.fill")], miniGame: nil),
                NarrativeMoment(id: "4.contact", title: "把位置说清楚", goal: "走到同伴身边，请他联系方老师", body: "联络只需要说明楼层、位置和需要成人到场。江越说过什么，不需要在电话或消息里转述。", speaker: "苏念", choices: [NarrativeChoice(id: "contactAdult", title: "请同伴联系方老师", detail: "也可以走近同伴按 E 完成联络", symbol: "phone.arrow.up.right.fill")], miniGame: nil),
                NarrativeMoment(id: "4.handoff", title: "可靠的大人", goal: "等方老师来到江越身边并明确接手", body: "方老师来到平台，而不是让你们单独转运江越。风险路线由成人依据既定安全事实执行，不由学生选择诊断。", speaker: "方老师", choices: [NarrativeChoice(id: "followAdultPlan", title: "跟随成人安排", detail: "陪到指定位置，不承担评估职责", symbol: "figure.walk.motion"), NarrativeChoice(id: "holdSafeSpace", title: "退到安全位置等候", detail: "让成人完成现场接管", symbol: "shield.checkered")], miniGame: nil)
            ]
        case .counseling:
            return [
                NarrativeMoment(id: "5.wait", title: "门外有灯", goal: "在咨询室外等候", body: "门上写着“正在会谈”。灯光很暖，走廊很安静。等待不是被晾在一边，而是让专业支持有空间发生。", speaker: "苏念", choices: [NarrativeChoice(id: "wait", title: "坐下来等一会儿", detail: "让身体从紧绷里退出来", symbol: "chair.lounge.fill")], miniGame: nil),
                NarrativeMoment(id: "5.rumor", title: "没有人需要被解释", goal: "回应路过同学的猜测", body: "有人问：江越怎么了？你知道答案不该被你替他公开。", speaker: "苏念", choices: [NarrativeChoice(id: "privacy", title: "“他正在被照顾，我们别猜。”", detail: "保护隐私，也不制造谣言", symbol: "lock.fill"), NarrativeChoice(id: "redirect", title: "“现在最重要的是让他安静。”", detail: "把关注放回边界", symbol: "arrow.uturn.forward")], miniGame: nil),
                NarrativeMoment(id: "5.message", title: "仍然在这里", goal: "给林澈留一句话", body: "林澈发来消息：我不知道能做什么。你不需要教他当专家，只需要把支持网络递给他。", speaker: "苏念", choices: [NarrativeChoice(id: "message", title: "“我们可以一起等，也可以找老师。”", detail: "支持不必完美", symbol: "message.fill")], miniGame: nil)
            ]
        case .epilogue:
            return [
                NarrativeMoment(id: "6.enter", title: "这里有光", goal: "走进咨询室", body: "心理老师给你留了一把椅子。她没有问你为什么没有更早发现，而是问：这一晚对你来说怎么样？", speaker: "心理老师", choices: [NarrativeChoice(id: "enter", title: "坐下来", detail: "允许自己也被照顾", symbol: "door.left.hand.open")], miniGame: nil),
                NarrativeMoment(id: "6.share", title: "说出自己的事", goal: "决定要不要分享一点感受", body: "你想起自己在教室里那次短促的呼吸。支持别人不等于不需要支持。", speaker: "苏念", choices: [NarrativeChoice(id: "share", title: "“其实我也常常觉得很累。”", detail: "把真实交给可靠的人", symbol: "heart.text.square.fill"), NarrativeChoice(id: "pause", title: "“我还想再想一想。”", detail: "保留自己的节奏", symbol: "hourglass")], miniGame: nil),
                NarrativeMoment(id: "6.network", title: "支持网络", goal: "记住可以求助的人和地方", body: "灯没有替谁解决一切，但它照出了下一步：同伴、老师、心理支持、家人，以及愿意再次开口的你。", speaker: "苏念", choices: [NarrativeChoice(id: "finish", title: "把这束光带出去", detail: "完成旅程", symbol: "sun.max.fill")], miniGame: nil)
            ]
        }
    }

    static func jiangDialogueMoment(segment: Int) -> NarrativeMoment {
        let segments: [(title: String, goal: String, body: String, choices: [NarrativeChoice])] = [
            (
                "凌晨还醒着",
                "听完这句话，再决定如何回应",
                "我最近每天两三点还醒着。第二天坐在教室里，所有声音都像隔着一层东西。",
                [
                    NarrativeChoice(id: "dialogue.listen", title: "“听起来你已经很久没有真正休息了。”", detail: "复述感受，不抢着解释", symbol: "ear.and.waveform"),
                    NarrativeChoice(id: "dialogue.advise", title: "“你应该早点睡，别再看手机。”", detail: "立刻给出建议", symbol: "lightbulb.fill"),
                    NarrativeChoice(id: "dialogue.silent", title: "安静地留在原地", detail: "让沉默不等于离开", symbol: "ellipsis")
                ]
            ),
            (
                "明天还是会来",
                "不要把害怕缩成一句加油",
                "最难受的不是今天。是我知道明天醒来以后，这些事还会一件不落地回来。",
                [
                    NarrativeChoice(id: "dialogue.accompany", title: "“至少这一会儿，你不用一个人等明天。”", detail: "承诺眼前能做到的陪伴", symbol: "person.2.fill"),
                    NarrativeChoice(id: "dialogue.inspire", title: "“再坚持一下，总会过去的。”", detail: "用鼓励盖过当下", symbol: "sunrise.fill"),
                    NarrativeChoice(id: "dialogue.listen", title: "“你最怕明天哪一部分？”", detail: "允许他决定说多少", symbol: "bubble.left")
                ]
            ),
            (
                "不想成为麻烦",
                "让求助不再等于拖累别人",
                "我试过开口。但每次看见别人也很累，我就觉得自己又给人添了一件麻烦。",
                [
                    NarrativeChoice(id: "dialogue.listen", title: "“你现在说这些，不是在给我添麻烦。”", detail: "确认他的存在可以被承接", symbol: "heart.text.square"),
                    NarrativeChoice(id: "dialogue.judge", title: "“你想太多了，大家没那么在意。”", detail: "否定他的感受", symbol: "xmark.bubble"),
                    NarrativeChoice(id: "dialogue.silent", title: "把身体转向他，继续听", detail: "用姿态保持在场", symbol: "figure.seated.side")
                ]
            ),
            (
                "那句‘算了’",
                "听清含糊的话，但不替学生做风险判断",
                "有时候我会想，干脆算了。然后我又怕别人听见，怕他们觉得我在演。",
                [
                    NarrativeChoice(id: "dialogue.accompany", title: "“我听见了。今晚我们不会把你一个人留在这里。”", detail: "明确陪伴，同时准备成人支持", symbol: "person.3.fill"),
                    NarrativeChoice(id: "dialogue.listen", title: "“谢谢你把这句话告诉我们。”", detail: "接住披露，不承诺保密到底", symbol: "ear.badge.checkmark"),
                    NarrativeChoice(id: "dialogue.advise", title: "“先别想这些，出去走走就好了。”", detail: "过早转移话题", symbol: "arrow.turn.up.right")
                ]
            )
        ]
        let item = segments[min(max(0, segment), segments.count - 1)]
        return NarrativeMoment(
            id: "4.listen.\(min(max(0, segment), segments.count - 1))",
            title: item.title,
            goal: item.goal,
            body: item.body,
            speaker: "江越",
            choices: item.choices,
            miniGame: nil
        )
    }

    mutating func start() {
        self = NarrativeCampaign(isActive: true)
        exploration.reset(for: .classroom)
    }

    mutating func startAfterPlayableChapterOne(linCheTrust seedTrust: Int = 1) {
        self = NarrativeCampaign(isActive: true, chapter: .mirror)
        completedMomentIDs = Set(NarrativeCampaign.moments(for: .classroom).map(\.id))
        linCheTrust = seedTrust.clamped(to: 0...100)
        selfCared = true
        exploration.reset(for: .mirror)
    }

    mutating func choose(_ choiceID: String) {
        guard isActive, isComplete == false, miniGameCompleted else { return }
        // A saved or delayed UI event must not be able to advance a different moment.
        let momentBeforeChoice = currentMoment
        guard let selectedChoice = momentBeforeChoice.choices.first(where: { $0.id == choiceID }) else { return }
        guard canApplyChoice(choiceID) else { return }
        lastChoiceImpact = NarrativeChoiceSignalModel.impact(
            for: selectedChoice,
            moment: momentBeforeChoice,
            campaign: self
        )
        completedMomentIDs.insert(momentBeforeChoice.id)
        if momentBeforeChoice.id.hasPrefix("4.listen.") {
            respondToJiangDialogue(choiceID: choiceID)
            return
        }
        switch choiceID {
        case "breathe", "water": selfCared = true
        case "openQuestion", "stay": linCheTrust += 1
        case "reassure", "invite", "present": linCheTrust += choiceID == "invite" ? 2 : 1
        case "zhou": companionID = "周予安"
        case "xu": companionID = "许栀"
        case "listenJiang": jiangYueTrust += 2
        case "askGentle":
            ensureJiangDialogueState()
            jiangDialogueState?.riskAskMethod = .gentle
            jiangDialogueState?.disclosedRisk = NarrativeDisclosureResolver.resolve(method: .gentle, trust: jiangYueTrust)
        case "askSafety":
            jiangYueTrust += 2
            ensureSafetyHandoffState()
            safetyHandoffState?.riskAsked = true
            ensureJiangDialogueState()
            jiangDialogueState?.riskAskMethod = .direct
            jiangDialogueState?.disclosedRisk = NarrativeDisclosureResolver.resolve(method: .direct, trust: jiangYueTrust)
        case "adultNow":
            jiangYueTrust += 1
            ensureSafetyHandoffState()
            safetyHandoffState?.riskAsked = false
            ensureJiangDialogueState()
            jiangDialogueState?.riskAskMethod = .deferToAdult
            jiangDialogueState?.disclosedRisk = .unknown
        case "contactAdult":
            ensureSafetyHandoffState()
            if var handoff = safetyHandoffState {
                handoff.adultContactInitiated = true
                handoff.contactMethod = companionID == "周予安" ? "电话" : "消息"
                handoff.resolutionPath = handoff.riskAsked
                    ? .voluntary
                    : .adultCameAfterUnclearDisclosure
                safetyHandoffState = handoff
            }
        case "followAdultPlan", "holdSafeSpace":
            completeSafetyHandoff()
        case "wait":
            ensureCounselingState()
            counselingState?.handoffSceneStarted = true
        case "privacy":
            ensureCounselingState()
            counselingState?.rumorHandled = true
            counselingState?.rumorOutcome = .suppressed
            privacyProtected = true
        case "redirect":
            ensureCounselingState()
            counselingState?.rumorHandled = true
            counselingState?.rumorOutcome = .contained
            privacyProtected = true
        case "message":
            ensureCounselingState()
            counselingState?.companionMessageReplied = true
            counselingState?.handoffConfirmed = true
            counselingState?.supportHandedOff = true
        case "share": sharedSelf = true
        default: break
        }
        advance()
    }

    mutating func dismissRiskEducationCard() {
        guard currentMoment.id == "4.risk" else { return }
        ensureJiangDialogueState()
        jiangDialogueState?.educationCardDismissed = true
    }

    mutating func timeoutJiangDialogue() -> Bool {
        guard currentMoment.id.hasPrefix("4.listen.") else { return false }
        completedMomentIDs.insert(currentMoment.id)
        respondToJiangDialogue(kind: .timeout)
        return true
    }

    private mutating func respondToJiangDialogue(choiceID: String) {
        let kind: NarrativeDialogueResponseKind
        switch choiceID {
        case "dialogue.listen": kind = .listening
        case "dialogue.accompany": kind = .accompanying
        case "dialogue.silent": kind = .silentPresence
        case "dialogue.advise": kind = .advisory
        case "dialogue.inspire": kind = .inspirational
        case "dialogue.judge": kind = .judgmental
        default: return
        }
        respondToJiangDialogue(kind: kind)
    }

    private mutating func respondToJiangDialogue(kind: NarrativeDialogueResponseKind) {
        ensureJiangDialogueState()
        guard var dialogue = jiangDialogueState, dialogue.listenPhaseComplete == false else { return }
        dialogue.responseKinds.append(kind)
        dialogue.performanceBeats.append(NarrativeDialoguePerformanceBeat(response: kind))
        dialogue.consecutiveTimeouts = kind == .timeout ? dialogue.consecutiveTimeouts + 1 : 0
        jiangYueTrust = NarrativeDialogueTrustReducer.apply(kind, to: jiangYueTrust)
        if dialogue.segmentIndex < 3 {
            dialogue.segmentIndex += 1
            jiangDialogueState = dialogue
        } else {
            dialogue.listenPhaseComplete = true
            jiangDialogueState = dialogue
            advance()
        }
    }

    mutating func advance() {
        let moments = NarrativeCampaign.moments(for: chapter)
        if momentIndex + 1 < moments.count {
            momentIndex += 1
            miniGameProgress = 0
            miniGameTouchedSlots = []
            miniGameHintCount = 0
            return
        }
        if let next = NarrativeChapter(rawValue: chapter.rawValue + 1) {
            guard canLeaveCurrentChapter else { return }
            chapter = next
            momentIndex = 0
            miniGameProgress = 0
            miniGameTouchedSlots = []
            miniGameHintCount = 0
            exploration.reset(for: chapter)
            prepareRuntimeStateForCurrentChapter()
        } else {
            isComplete = true
        }
    }

    mutating func prepareRuntimeStateForCurrentChapter() {
        if chapter == .stairwell {
            ensureSafetyHandoffState()
            ensureJiangDialogueState()
        } else if chapter == .counseling {
            ensureCounselingState()
        }
    }

    private var canLeaveCurrentChapter: Bool {
        switch chapter {
        case .noteTrace:
            return companionID.isEmpty == false
        case .stairwell:
            return safetyHandoffState?.adultContactInitiated == true
                && safetyHandoffState?.safetyHandoffComplete == true
                && safetyHandoffState?.route != nil
                && safetyHandoffState?.entryMode != nil
        case .counseling:
            return counselingState?.rumorHandled == true
                && counselingState?.companionMessageReplied == true
                && counselingState?.handoffConfirmed == true
                && counselingState?.supportHandedOff == true
        default:
            return true
        }
    }

    private func canApplyChoice(_ choiceID: String) -> Bool {
        switch choiceID {
        case "locateJiang":
            return noteTraceDepartureClues == Set(NoteTraceDepartureClue.allCases)
        case "askGentle", "askSafety", "adultNow":
            return jiangDialogueState?.educationCardDismissed == true
        case "contactAdult":
            return companionID.isEmpty == false && safetyHandoffState?.adultContactInitiated != true
        case "followAdultPlan", "holdSafeSpace":
            return safetyHandoffState?.adultContactInitiated == true
                && safetyHandoffState?.safetyHandoffComplete != true
                && currentMomentActionReady
        case "privacy", "redirect":
            return counselingState?.rumorHandled != true
        case "message":
            return counselingState?.companionMessageReplied != true
        default:
            return true
        }
    }

    private mutating func ensureSafetyHandoffState() {
        if safetyHandoffState == nil {
            safetyHandoffState = NarrativeSafetyHandoffState()
        }
    }

    private mutating func ensureJiangDialogueState() {
        if jiangDialogueState == nil {
            jiangDialogueState = NarrativeJiangDialogueState()
        }
    }

    private mutating func completeSafetyHandoff() {
        ensureSafetyHandoffState()
        guard var handoff = safetyHandoffState,
              handoff.adultContactInitiated,
              handoff.safetyHandoffComplete == false else { return }
        let resolved = NarrativeSafetyHandoffPolicy.resolve(handoff.authoredRisk)
        handoff.route = resolved.route
        handoff.entryMode = resolved.entryMode
        handoff.safetyHandoffComplete = true
        handoff.resolutionPath = handoff.resolutionPath ?? .adultCameAfterLowTrust
        safetyHandoffState = handoff
        safetyRoute = resolved.route.displayName
    }

    private mutating func ensureCounselingState() {
        if counselingState == nil {
            let entryMode = safetyHandoffState?.entryMode ?? .standardWaiting
            counselingState = NarrativeCounselingState(entryMode: entryMode)
        }
    }

    mutating func progressMiniGame() {
        guard let miniGame = currentMoment.miniGame else { return }
        let required = miniGame.requiredInteractions
        miniGameProgress = min(required, miniGameProgress + 1)
    }

    mutating func completeMiniGameAccessibly() {
        guard let miniGame = currentMoment.miniGame, miniGameCompleted == false else { return }
        switch miniGame {
        case .trace, .melody:
            miniGameProgress = miniGame.requiredInteractions
        case .erase:
            for slot in 0..<6 where miniGameTouchedSlots.count < miniGame.requiredInteractions {
                miniGameTouchedSlots.insert(slot)
            }
            miniGameProgress = miniGameTouchedSlots.count
        }
    }

    mutating func performMiniGameAction(_ slot: Int) {
        guard let miniGame = currentMoment.miniGame, miniGameCompleted == false else { return }
        switch miniGame {
        case .trace:
            guard slot == miniGameProgress else { return }
            miniGameProgress += 1
        case .melody:
            let melody = [1, 3, 0, 2]
            guard slot >= 0, slot < melody.count else { return }
            if melody[miniGameProgress] == slot {
                miniGameProgress += 1
            } else {
                miniGameProgress = 0
                miniGameHintCount += 1
                if miniGameHintCount >= 3 {
                    miniGameProgress = miniGame.requiredInteractions
                }
            }
        case .erase:
            guard (0..<6).contains(slot) else { return }
            guard miniGameTouchedSlots.insert(slot).inserted else { return }
            miniGameProgress = miniGameTouchedSlots.count
        }
    }

    mutating func replayMiniGameCue() {
        guard currentMoment.miniGame == .melody, miniGameCompleted == false else { return }
        miniGameHintCount += 1
        if miniGameHintCount >= 3 {
            miniGameProgress = NarrativeMiniGame.melody.requiredInteractions
        }
    }

    var miniGameCompleted: Bool {
        guard let miniGame = currentMoment.miniGame else { return true }
        return miniGameProgress >= miniGame.requiredInteractions
    }

    var mirrorDissolveProgress: Double {
        if isComplete || chapter.rawValue > NarrativeChapter.mirror.rawValue { return 1 }
        guard chapter == .mirror else { return 0 }
        if currentMoment.id == "2.listen" { return 1 }
        if currentMoment.miniGame == .erase, miniGameCompleted { return 0.72 }
        return 0
    }
}

struct NarrativeRouteMarker: Identifiable, Equatable {
    enum State: String, Equatable {
        case completed
        case current
        case upcoming
    }

    let chapter: NarrativeChapter
    let state: State
    let statusLine: String
    let signalStrength: Double

    var id: NarrativeChapter { chapter }
}

struct NarrativeRouteRailView: View {
    let campaign: NarrativeCampaign

    private var markers: [NarrativeRouteMarker] {
        campaign.routeMarkers
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.cyan)
                Text("章节路线")
                    .font(.system(size: 12, weight: .bold))
                Spacer()
                Text("\(campaign.chapter.rawValue) / \(NarrativeChapter.allCases.count)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.56))
            }

            GeometryReader { proxy in
                let width = proxy.size.width
                let markerCount = max(1, markers.count)
                let railInset = min(CGFloat(58), width * 0.08)
                let railWidth = max(1, width - railInset * 2)
                let step = markerCount > 1 ? railWidth / CGFloat(markerCount - 1) : 0
                ZStack(alignment: .topLeading) {
                    Capsule()
                        .fill(.white.opacity(0.10))
                        .frame(width: railWidth, height: 4)
                        .offset(x: railInset, y: 17)
                    Capsule()
                        .fill(campaign.chapter.atmosphere.opacity(0.78))
                        .frame(
                            width: railWidth * CGFloat(routeCompletionFraction.clamped(to: 0...1)),
                            height: 4
                        )
                        .offset(x: railInset, y: 17)

                    ForEach(Array(markers.enumerated()), id: \.element.id) { index, marker in
                        NarrativeRouteMarkerView(marker: marker, tint: campaign.chapter.atmosphere)
                            .frame(width: min(138, max(96, step + 24)), height: 78, alignment: .top)
                            .position(x: railInset + CGFloat(index) * step, y: 38)
                    }
                }
            }
            .frame(height: 82)
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(routeAccessibilityLabel)
    }

    private var routeCompletionFraction: Double {
        if campaign.isComplete { return 1 }
        let chapterBase = Double(max(0, campaign.chapter.rawValue - 1))
        let momentCount = max(1, NarrativeCampaign.moments(for: campaign.chapter).count)
        let momentProgress = Double(campaign.momentIndex) / Double(momentCount)
        return (chapterBase + momentProgress) / Double(max(1, NarrativeChapter.allCases.count - 1))
    }

    private var routeAccessibilityLabel: String {
        let current = markers.first { $0.state == .current }
        return "章节路线，当前 \(current?.chapter.title ?? campaign.chapter.title)，\(current?.statusLine ?? campaign.progressText)"
    }
}

struct NarrativeSupportWeatherView: View {
    let campaign: NarrativeCampaign

    private var nodes: [SupportNetworkNode] {
        SupportNetworkModel.nodes(for: campaign).sorted {
            if $0.strength == $1.strength {
                return $0.id < $1.id
            }
            return $0.strength > $1.strength
        }
    }

    private var leadNode: SupportNetworkNode {
        nodes.first ?? SupportNetworkModel.nodes(for: campaign)[0]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.cyan)
                Text("支持天气")
                    .font(.system(size: 12, weight: .bold))
                Spacer()
                Text("当前最稳 \(leadNode.title)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            HStack(alignment: .top, spacing: 8) {
                ForEach(Array(nodes.prefix(3).enumerated()), id: \.element.id) { index, node in
                    supportWeatherCard(node: node, rank: index + 1)
                }
            }
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("支持天气，当前最稳 \(leadNode.title)")
    }

    private func supportWeatherCard(node: SupportNetworkNode, rank: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Circle()
                    .fill(node.tint.opacity(0.88))
                    .frame(width: 7, height: 7)
                Text(node.title)
                    .font(.system(size: 11, weight: .bold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(rank)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.10))
                    Capsule()
                        .fill(node.tint.opacity(0.82))
                        .frame(width: max(12, proxy.size.width * node.strength))
                }
            }
            .frame(height: 4)

            Text(node.detail)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.68))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .topLeading)
        .background(node.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(node.tint.opacity(0.22), lineWidth: 1)
        )
    }
}

private struct NarrativeRouteMarkerView: View {
    let marker: NarrativeRouteMarker
    let tint: Color

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(markerColor.opacity(marker.state == .current ? 0.34 : 0.18))
                Circle()
                    .stroke(.white.opacity(marker.state == .current ? 0.52 : 0.20), lineWidth: marker.state == .current ? 1.4 : 1)
                Image(systemName: markerSymbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(marker.state == .upcoming ? .white.opacity(0.44) : .white.opacity(0.9))
            }
            .frame(width: marker.state == .current ? 28 : 24, height: marker.state == .current ? 28 : 24)

            Text("第\(marker.chapter.rawValue)章")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(marker.state == .current ? .white.opacity(0.9) : .white.opacity(0.58))
                .lineLimit(1)

            Text(marker.statusLine)
                .font(.system(size: 8.2, weight: .medium))
                .foregroundStyle(.white.opacity(marker.state == .upcoming ? 0.42 : 0.66))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var markerColor: Color {
        switch marker.state {
        case .completed:
            return .mint
        case .current:
            return tint
        case .upcoming:
            return .white
        }
    }

    private var markerSymbol: String {
        switch marker.state {
        case .completed:
            return "checkmark"
        case .current:
            return "location.fill"
        case .upcoming:
            return "circle"
        }
    }
}

enum NarrativeIntegrationRouteProfile: String, CaseIterable, Identifiable {
    case standardProtected
    case urgentProtected
    case emergencyClosure
    case lowTrustContained

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standardProtected:
            return "标准隐私线"
        case .urgentProtected:
            return "校内紧急线"
        case .emergencyClosure:
            return "紧急接管线"
        case .lowTrustContained:
            return "低信任收束线"
        }
    }

    var shortCode: String {
        switch self {
        case .standardProtected: return "STD"
        case .urgentProtected: return "URG"
        case .emergencyClosure: return "EMS"
        case .lowTrustContained: return "LOW"
        }
    }

    var authoredRisk: NarrativeRiskLevel {
        switch self {
        case .standardProtected:
            return .moderate
        case .urgentProtected:
            return .high
        case .emergencyClosure:
            return .imminent
        case .lowTrustContained:
            return .low
        }
    }

    var route: NarrativeSafetyRoute {
        switch self {
        case .standardProtected, .lowTrustContained:
            return .standardCounseling
        case .urgentProtected:
            return .urgentSchoolResponse
        case .emergencyClosure:
            return .emergencyServices
        }
    }

    var entryMode: NarrativeCounselingEntryMode {
        switch self {
        case .standardProtected, .lowTrustContained:
            return .standardWaiting
        case .urgentProtected:
            return .urgentHandoffWaiting
        case .emergencyClosure:
            return .emergencyClosure
        }
    }

    var resolutionPath: NarrativeResolutionPath {
        switch self {
        case .standardProtected, .urgentProtected, .emergencyClosure:
            return .voluntary
        case .lowTrustContained:
            return .adultCameAfterLowTrust
        }
    }

    var privacyProtected: Bool {
        switch self {
        case .lowTrustContained:
            return false
        case .standardProtected, .urgentProtected, .emergencyClosure:
            return true
        }
    }

    var riskAskMethod: NarrativeRiskAskMethod {
        switch self {
        case .standardProtected:
            return .gentle
        case .urgentProtected, .emergencyClosure:
            return .direct
        case .lowTrustContained:
            return .deferToAdult
        }
    }

    var expectedAudioSceneID: String {
        switch self {
        case .standardProtected, .urgentProtected, .lowTrustContained:
            return "counseling"
        case .emergencyClosure:
            return "epilogue"
        }
    }
}

struct NarrativeIntegrationMatrixCase: Identifiable, Equatable {
    let profile: NarrativeIntegrationRouteProfile
    let companionID: String
    let sharedSelf: Bool

    var id: String {
        "\(profile.rawValue).\(companionID).\(sharedSelf ? "shared" : "quiet")"
    }

    var title: String {
        "\(profile.title) · \(companionID)"
    }

    var selfStateLine: String {
        sharedSelf ? "苏念开口" : "苏念保留节奏"
    }
}

struct NarrativeIntegrationMatrixResult: Identifiable, Equatable {
    let matrixCase: NarrativeIntegrationMatrixCase
    let campaign: NarrativeCampaign
    let endingType: EndingType
    let audioSceneID: String
    let routeMarkerCount: Int
    let consequenceEchoIDs: [String]
    let missingStateLines: [String]

    var id: String { matrixCase.id }
    var companionPreserved: Bool { campaign.companionID == matrixCase.companionID }
    var sharedSelfPreserved: Bool { campaign.sharedSelf == matrixCase.sharedSelf }
    var uniqueConsequenceEchoes: Bool { Set(consequenceEchoIDs).count == consequenceEchoIDs.count }
    var routeMarkersComplete: Bool { routeMarkerCount == NarrativeChapter.allCases.count }
    var audioProfileResolved: Bool { audioSceneID == matrixCase.profile.expectedAudioSceneID }

    var isPassing: Bool {
        companionPreserved
            && sharedSelfPreserved
            && uniqueConsequenceEchoes
            && routeMarkersComplete
            && audioProfileResolved
            && missingStateLines.isEmpty
    }

    var stateSummary: String {
        [
            matrixCase.companionID,
            matrixCase.sharedSelf ? "分享" : "未分享",
            campaign.privacyProtected ? "隐私" : "收束",
            endingType.title
        ].joined(separator: " · ")
    }
}

enum NarrativeIntegrationMatrix {
    static let companions = ["周予安", "许栀"]

    static var requiredCases: [NarrativeIntegrationMatrixCase] {
        NarrativeIntegrationRouteProfile.allCases.flatMap { profile in
            companions.flatMap { companion in
                [true, false].map { sharedSelf in
                    NarrativeIntegrationMatrixCase(
                        profile: profile,
                        companionID: companion,
                        sharedSelf: sharedSelf
                    )
                }
            }
        }
    }

    static var results: [NarrativeIntegrationMatrixResult] {
        requiredCases.map(evaluate)
    }

    static var passingCount: Int {
        results.filter(\.isPassing).count
    }

    static func evaluate(_ matrixCase: NarrativeIntegrationMatrixCase) -> NarrativeIntegrationMatrixResult {
        let campaign = campaign(for: matrixCase)
        let audioScene = AudioSceneMix.profile(for: matrixCase.profile.expectedAudioSceneID)
        var missing: [String] = []

        if campaign.safetyHandoffState?.route != matrixCase.profile.route {
            missing.append("安全路线")
        }
        if campaign.safetyHandoffState?.resolutionPath != matrixCase.profile.resolutionPath {
            missing.append("交接结论")
        }
        if campaign.privacyProtected != matrixCase.profile.privacyProtected {
            missing.append("隐私状态")
        }
        if campaign.counselingState == nil {
            missing.append("咨询室状态")
        }
        if campaign.jiangDialogueState?.riskAskMethod != matrixCase.profile.riskAskMethod {
            missing.append("风险提问")
        }

        return NarrativeIntegrationMatrixResult(
            matrixCase: matrixCase,
            campaign: campaign,
            endingType: EndingSelector.select(campaign: campaign),
            audioSceneID: audioScene.sceneID,
            routeMarkerCount: campaign.routeMarkers.count,
            consequenceEchoIDs: campaign.consequenceEchoes.map(\.id),
            missingStateLines: missing
        )
    }

    static func campaign(for matrixCase: NarrativeIntegrationMatrixCase) -> NarrativeCampaign {
        let profile = matrixCase.profile
        var campaign = NarrativeCampaign(isActive: true, isComplete: true, chapter: .epilogue, momentIndex: 0)
        campaign.clueCount = profile == .lowTrustContained ? 3 : 5
        campaign.linCheTrust = profile == .lowTrustContained ? 42 : 72
        campaign.jiangYueTrust = profile == .lowTrustContained ? 38 : 76
        campaign.companionID = matrixCase.companionID
        campaign.selfCared = true
        campaign.sharedSelf = matrixCase.sharedSelf
        campaign.privacyProtected = profile.privacyProtected
        campaign.safetyRoute = profile.route.displayName
        campaign.completedMomentIDs = Set(NarrativeChapter.allCases.flatMap { chapter in
            NarrativeCampaign.moments(for: chapter).map(\.id)
        })
        campaign.safetyHandoffState = NarrativeSafetyHandoffState(
            authoredRisk: profile.authoredRisk,
            riskAsked: true,
            adultContactInitiated: true,
            contactMethod: matrixCase.companionID == "周予安" ? "电话" : "消息",
            safetyHandoffComplete: true,
            route: profile.route,
            entryMode: profile.entryMode,
            resolutionPath: profile.resolutionPath
        )
        campaign.counselingState = NarrativeCounselingState(
            entryMode: profile.entryMode,
            handoffSceneStarted: true,
            boundaryHeld: profile.privacyProtected,
            rumorHandled: true,
            rumorOutcome: profile.privacyProtected ? .suppressed : .contained,
            companionMessageReplied: true,
            handoffConfirmed: true,
            supportHandedOff: true
        )
        campaign.jiangDialogueState = NarrativeJiangDialogueState(
            segmentIndex: 3,
            responseKinds: [.listening, .accompanying, .silentPresence],
            listenPhaseComplete: true,
            educationCardDismissed: true,
            riskAskMethod: profile.riskAskMethod,
            disclosedRisk: profile == .lowTrustContained ? .partial : .confirmed
        )
        return campaign
    }
}

struct NarrativeIntegrationMatrixView: View {
    let results: [NarrativeIntegrationMatrixResult]
    var compact = false

    private var passCount: Int { results.filter(\.isPassing).count }
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: compact ? 5 : 8), count: compact ? 4 : 4)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 14) {
            header
            LazyVGrid(columns: columns, alignment: .leading, spacing: compact ? 5 : 8) {
                ForEach(results) { result in
                    MatrixCell(result: result, compact: compact)
                }
            }
        }
        .padding(compact ? 8 : 14)
        .foregroundStyle(.white)
        .background(.black.opacity(compact ? 0.18 : 0.46), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.14), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("全状态矩阵，\(passCount) / \(results.count) 组通过")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: passCount == results.count ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: compact ? 11 : 15, weight: .bold))
                .foregroundStyle(passCount == results.count ? .mint : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("全状态矩阵")
                    .font(.system(size: compact ? 11 : 17, weight: .bold))
                if compact == false {
                    Text("路线 × 同伴 × 苏念披露，验证状态不丢失")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                }
            }
            Spacer()
            Text("\(passCount)/\(results.count)")
                .font(.system(size: compact ? 10 : 15, weight: .bold, design: .monospaced))
                .foregroundStyle(passCount == results.count ? .mint : .orange)
        }
    }
}

private struct MatrixCell: View {
    let result: NarrativeIntegrationMatrixResult
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 7) {
            HStack(spacing: 5) {
                Circle()
                    .fill(result.isPassing ? .mint : .orange)
                    .frame(width: compact ? 6 : 8, height: compact ? 6 : 8)
                Text(result.matrixCase.profile.shortCode)
                    .font(.system(size: compact ? 8 : 10, weight: .bold, design: .monospaced))
                Spacer(minLength: 2)
                Image(systemName: result.endingType.symbol)
                    .font(.system(size: compact ? 8 : 10, weight: .bold))
                    .foregroundStyle(result.endingType.accent)
            }

            Text(compact ? result.matrixCase.companionID : result.matrixCase.title)
                .font(.system(size: compact ? 8 : 11, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            if compact == false {
                Text(result.stateSummary)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(compact ? 5 : 9)
        .frame(maxWidth: .infinity, minHeight: compact ? 42 : 74, alignment: .topLeading)
        .background(cellTint, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(result.isPassing ? 0.12 : 0.3), lineWidth: 1))
    }

    private var cellTint: Color {
        result.isPassing ? result.endingType.accent.opacity(compact ? 0.10 : 0.16) : .orange.opacity(0.2)
    }
}

struct NarrativeCampaignDossierChapter: Identifiable, Equatable {
    let chapter: NarrativeChapter
    let title: String
    let routeLine: String
    let evidenceLine: String
    let signalStrength: Double
    let symbol: String

    var id: NarrativeChapter { chapter }
}

struct NarrativeCampaignDossier: Equatable {
    let endingType: EndingType
    let routeSignature: String
    let chapterCards: [NarrativeCampaignDossierChapter]
    let verificationSignals: [String]
    let unresolvedWarnings: [String]
    let supportContinuity: Double
    let uniqueEchoCount: Int
    let echoCount: Int

    var completedChapterCount: Int {
        chapterCards.filter { $0.signalStrength >= 0.5 }.count
    }

    var isCoherent: Bool {
        chapterCards.count == NarrativeChapter.allCases.count
            && uniqueEchoCount == echoCount
            && unresolvedWarnings.isEmpty
    }

    static func make(for campaign: NarrativeCampaign) -> NarrativeCampaignDossier {
        let markers = campaign.routeMarkers
        let echoes = campaign.consequenceEchoes
        let uniqueEchoCount = Set(echoes.map(\.id)).count
        let ending = EndingSelector.select(campaign: campaign)
        let chapterCards = NarrativeChapter.allCases.map { chapter in
            chapterCard(for: chapter, campaign: campaign, markers: markers)
        }
        let averageMarker = markers.isEmpty ? 0 : markers.map(\.signalStrength).reduce(0, +) / Double(markers.count)
        let averageEcho = echoes.isEmpty ? 0 : echoes.map(\.strength).reduce(0, +) / Double(echoes.count)
        let continuity = ((averageMarker * 0.62) + (averageEcho * 0.38)).clamped(to: 0...1)
        var warnings: [String] = []

        if campaign.companionID.isEmpty {
            warnings.append("同伴线未接入")
        }
        if campaign.safetyHandoffState?.safetyHandoffComplete != true {
            warnings.append("安全交接未闭合")
        }
        if uniqueEchoCount != echoes.count {
            warnings.append("回声重复")
        }
        if campaign.privacyProtected == false {
            warnings.append("隐私仍需照顾")
        }

        return NarrativeCampaignDossier(
            endingType: ending,
            routeSignature: [
                ending.title,
                campaign.safetyRoute.isEmpty ? "咨询室支持" : campaign.safetyRoute,
                campaign.companionID.isEmpty ? "未选择同伴" : campaign.companionID,
                campaign.sharedSelf ? "苏念开口" : "苏念保留节奏"
            ].joined(separator: " / "),
            chapterCards: chapterCards,
            verificationSignals: verificationSignals(for: campaign, echoCount: echoes.count),
            unresolvedWarnings: warnings,
            supportContinuity: continuity,
            uniqueEchoCount: uniqueEchoCount,
            echoCount: echoes.count
        )
    }

    private static func chapterCard(
        for chapter: NarrativeChapter,
        campaign: NarrativeCampaign,
        markers: [NarrativeRouteMarker]
    ) -> NarrativeCampaignDossierChapter {
        let marker = markers.first { $0.chapter == chapter }
        let markerStrength = marker?.signalStrength ?? 0.2
        let routeLine: String
        let evidenceLine: String
        let symbol: String

        switch chapter {
        case .classroom:
            routeLine = campaign.clueCount > 0 ? "\(campaign.clueCount) 条线索进入后续判断" : "等待第一条线索"
            evidenceLine = "没有替任何人诊断，先把可见事实带到后面。"
            symbol = "eye.fill"
        case .mirror:
            routeLine = campaign.selfCared ? "苏念完成一次自我照顾" : "自我照顾仍在提醒"
            evidenceLine = campaign.selfCared ? "压力没有只被推向别人，玩家也照顾了自己。" : "终章需要继续提醒帮助者也要被接住。"
            symbol = campaign.selfCared ? "heart.text.square.fill" : "heart"
        case .noteTrace:
            routeLine = campaign.companionID.isEmpty ? "同伴线未接入" : "\(campaign.companionID) 成为见证与边界"
            evidenceLine = campaign.companionID.isEmpty ? "后续更依赖成人支持闭合。" : "纸条追踪不再是单人判断。"
            symbol = "person.2.fill"
        case .stairwell:
            routeLine = campaign.safetyRoute.isEmpty ? "安全路线未命名" : campaign.safetyRoute
            evidenceLine = campaign.safetyHandoffState?.adultContactInitiated == true ? "成人到场，风险评估从学生手里交出去。" : "仍需把成人支持接入现场。"
            symbol = "shield.lefthalf.filled"
        case .counseling:
            routeLine = campaign.privacyProtected ? "隐私边界被守住" : "隐私被收束但仍需照顾"
            evidenceLine = campaign.counselingState?.rumorHandled == true ? "围观与猜测被挡在门外。" : "咨询室外仍有未处理压力。"
            symbol = "lock.shield.fill"
        case .epilogue:
            routeLine = campaign.sharedSelf ? "苏念也被放进支持网络" : "苏念保留自己的节奏"
            evidenceLine = "\(EndingSelector.select(campaign: campaign).title) 成为这次通关的终章标题。"
            symbol = EndingSelector.select(campaign: campaign).symbol
        }

        return NarrativeCampaignDossierChapter(
            chapter: chapter,
            title: chapter.title,
            routeLine: routeLine,
            evidenceLine: evidenceLine,
            signalStrength: markerStrength,
            symbol: symbol
        )
    }

    private static func verificationSignals(for campaign: NarrativeCampaign, echoCount: Int) -> [String] {
        [
            "章节 \(NarrativeChapter.allCases.count)/\(NarrativeChapter.allCases.count)",
            "回声 \(echoCount)",
            campaign.safetyHandoffState?.safetyHandoffComplete == true ? "交接闭合" : "交接待确认",
            campaign.privacyProtected ? "隐私保护" : "隐私收束"
        ]
    }
}

struct CampaignDossierView: View {
    let dossier: NarrativeCampaignDossier
    var compact = false

    init(campaign: NarrativeCampaign, compact: Bool = false) {
        dossier = NarrativeCampaignDossier.make(for: campaign)
        self.compact = compact
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: compact ? 7 : 10), count: compact ? 3 : 2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 9 : 13) {
            header
            LazyVGrid(columns: columns, alignment: .leading, spacing: compact ? 7 : 10) {
                ForEach(dossier.chapterCards) { card in
                    CampaignDossierChapterCell(card: card, compact: compact, accent: dossier.endingType.accent)
                }
            }
            if compact == false {
                signalStrip
            }
        }
        .padding(compact ? 11 : 15)
        .foregroundStyle(.white)
        .background(.black.opacity(compact ? 0.22 : 0.36), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.14), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("战役档案，\(dossier.completedChapterCount) 个章节信号，结局 \(dossier.endingType.title)")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 8) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.stack.badge.person.crop.fill")
                    .font(.system(size: compact ? 11 : 14, weight: .bold))
                    .foregroundStyle(dossier.endingType.accent)
                Text("战役档案")
                    .font(.system(size: compact ? 12 : 16, weight: .bold))
                Spacer()
                Text("\(dossier.completedChapterCount)/\(dossier.chapterCards.count)")
                    .font(.system(size: compact ? 10 : 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(dossier.isCoherent ? .mint : .orange)
            }

            Text(dossier.routeSignature)
                .font(.system(size: compact ? 9.5 : 11.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.66))
                .lineLimit(compact ? 1 : 2)
                .minimumScaleFactor(0.78)
        }
    }

    private var signalStrip: some View {
        HStack(spacing: 8) {
            ForEach(dossier.verificationSignals, id: \.self) { signal in
                Text(signal)
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(.white.opacity(0.78))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.07), in: Capsule())
            }
            Spacer(minLength: 0)
            Text("\(Int((dossier.supportContinuity * 100).rounded()))% 连续")
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .foregroundStyle(.mint.opacity(0.82))
        }
    }
}

private struct CampaignDossierChapterCell: View {
    let card: NarrativeCampaignDossierChapter
    let compact: Bool
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 7) {
            HStack(spacing: 6) {
                Image(systemName: card.symbol)
                    .font(.system(size: compact ? 9 : 12, weight: .bold))
                    .foregroundStyle(accent.opacity(0.88))
                    .frame(width: compact ? 12 : 16)
                Text("第\(card.chapter.rawValue)章")
                    .font(.system(size: compact ? 8.5 : 10.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.58))
                Spacer(minLength: 0)
                Circle()
                    .fill(signalColor)
                    .frame(width: compact ? 5 : 7, height: compact ? 5 : 7)
            }

            Text(card.routeLine)
                .font(.system(size: compact ? 9.2 : 12, weight: .bold))
                .lineLimit(compact ? 1 : 2)
                .minimumScaleFactor(0.76)

            if compact == false {
                Text(card.evidenceLine)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(compact ? 7 : 10)
        .frame(maxWidth: .infinity, minHeight: compact ? 54 : 86, alignment: .topLeading)
        .background(accent.opacity(0.08 + card.signalStrength * 0.06), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.10 + card.signalStrength * 0.08), lineWidth: 1))
    }

    private var signalColor: Color {
        card.signalStrength >= 0.72 ? .mint : (card.signalStrength >= 0.5 ? .cyan : .orange)
    }
}

enum AutonomousRouteIntent: String, CaseIterable, Identifiable {
    case supportiveXu
    case directZhou
    case adultFirst
    case quietSelf

    var id: String { rawValue }

    var title: String {
        switch self {
        case .supportiveXu:
            return "许栀支持线"
        case .directZhou:
            return "周予安直问线"
        case .adultFirst:
            return "成人优先线"
        case .quietSelf:
            return "苏念保留线"
        }
    }

    var companionChoiceID: String {
        switch self {
        case .directZhou:
            return "zhou"
        case .supportiveXu, .adultFirst, .quietSelf:
            return "xu"
        }
    }

    var riskChoiceID: String {
        switch self {
        case .adultFirst:
            return "adultNow"
        case .supportiveXu:
            return "askGentle"
        case .directZhou, .quietSelf:
            return "askSafety"
        }
    }

    var privacyChoiceID: String {
        switch self {
        case .adultFirst:
            return "redirect"
        case .supportiveXu, .directZhou, .quietSelf:
            return "privacy"
        }
    }

    var shareChoiceID: String {
        switch self {
        case .quietSelf:
            return "pause"
        case .supportiveXu, .directZhou, .adultFirst:
            return "share"
        }
    }

    var listeningPattern: [String] {
        switch self {
        case .supportiveXu:
            return ["dialogue.listen", "dialogue.accompany", "dialogue.silent", "dialogue.listen"]
        case .directZhou:
            return ["dialogue.listen", "dialogue.accompany", "dialogue.listen", "dialogue.accompany"]
        case .adultFirst:
            return ["dialogue.silent", "dialogue.listen", "dialogue.listen", "dialogue.accompany"]
        case .quietSelf:
            return ["dialogue.listen", "dialogue.listen", "dialogue.silent", "dialogue.listen"]
        }
    }
}

struct AutonomousRouteAuditResult: Identifiable, Equatable {
    let intent: AutonomousRouteIntent
    let campaign: NarrativeCampaign
    let stepCount: Int
    let decisionTrace: [String]
    let warnings: [String]

    var id: String { intent.rawValue }
    var endingType: EndingType { EndingSelector.select(campaign: campaign) }
    var isPassing: Bool { campaign.isComplete && warnings.isEmpty }
    var companionID: String { campaign.companionID }
    var sharedSelf: Bool { campaign.sharedSelf }
    var routeName: String { campaign.safetyRoute.isEmpty ? "未命名路线" : campaign.safetyRoute }
}

enum AutonomousRouteAuditor {
    static func runAll(maxSteps: Int = 180) -> [AutonomousRouteAuditResult] {
        AutonomousRouteIntent.allCases.map { run(intent: $0, maxSteps: maxSteps) }
    }

    static func run(intent: AutonomousRouteIntent, maxSteps: Int = 180) -> AutonomousRouteAuditResult {
        var campaign = NarrativeCampaign(isActive: true, chapter: .mirror)
        campaign.completedMomentIDs = Set(NarrativeCampaign.moments(for: .classroom).map(\.id))
        campaign.clueCount = 3
        campaign.linCheTrust = 2
        campaign.selfCared = true
        campaign.exploration.reset(for: .mirror)
        var trace: [String] = []

        for _ in 0..<maxSteps where campaign.isComplete == false {
            let before = campaign.currentMoment.id
            if campaign.shouldPresentRiskEducationCard {
                campaign.dismissRiskEducationCard()
                trace.append("\(before):dismissRiskCard")
                continue
            }
            if let miniGame = campaign.currentMoment.miniGame, campaign.miniGameCompleted == false {
                completeMiniGame(miniGame, campaign: &campaign)
                trace.append("\(before):miniGame")
                continue
            }
            if campaign.currentMoment.id == "4.handoff" {
                campaign.exploration.lastInteractedHotspot = "handoff.teacher"
            }
            if campaign.currentMoment.id == "3.locate" {
                campaign.recordNoteTraceDepartureClue(for: "note.deskTrace")
                campaign.recordNoteTraceDepartureClue(for: "note.paperTrail")
                trace.append("\(before):departureClues")
            }
            guard let choiceID = choiceID(for: campaign.currentMoment, intent: intent) else {
                trace.append("\(before):blocked")
                break
            }
            campaign.choose(choiceID)
            trace.append("\(before):\(choiceID)")
        }

        return AutonomousRouteAuditResult(
            intent: intent,
            campaign: campaign,
            stepCount: trace.count,
            decisionTrace: trace,
            warnings: warnings(for: campaign, intent: intent, trace: trace)
        )
    }

    private static func choiceID(for moment: NarrativeMoment, intent: AutonomousRouteIntent) -> String? {
        if moment.id.hasPrefix("4.listen.") {
            let segment = Int(moment.id.split(separator: ".").last ?? "0") ?? 0
            return intent.listeningPattern[min(segment, intent.listeningPattern.count - 1)]
        }

        switch moment.id {
        case "1.regulate":
            return "breathe"
        case "1.ask":
            return "stay"
        case "2.listen":
            return intent == .adultFirst ? "present" : "invite"
        case "3.companion":
            return intent.companionChoiceID
        case "4.risk":
            return intent.riskChoiceID
        case "4.contact":
            return "contactAdult"
        case "4.handoff":
            return intent == .adultFirst ? "holdSafeSpace" : "followAdultPlan"
        case "5.rumor":
            return intent.privacyChoiceID
        case "5.message":
            return "message"
        case "6.share":
            return intent.shareChoiceID
        default:
            return moment.choices.first?.id
        }
    }

    private static func completeMiniGame(_ miniGame: NarrativeMiniGame, campaign: inout NarrativeCampaign) {
        switch miniGame {
        case .trace:
            for slot in 0..<NarrativeMiniGame.trace.requiredInteractions { campaign.performMiniGameAction(slot) }
        case .melody:
            for slot in [1, 3, 0, 2] { campaign.performMiniGameAction(slot) }
        case .erase:
            for slot in [5, 2, 0, 4, 1, 3] { campaign.performMiniGameAction(slot) }
        }
    }

    private static func warnings(for campaign: NarrativeCampaign, intent: AutonomousRouteIntent, trace: [String]) -> [String] {
        var warnings: [String] = []
        if campaign.isComplete == false {
            warnings.append("未完成")
        }
        if campaign.companionID.isEmpty {
            warnings.append("同伴丢失")
        }
        if campaign.sharedSelf != (intent.shareChoiceID == "share") {
            warnings.append("披露状态丢失")
        }
        if Set(campaign.consequenceEchoes.map(\.id)).count != campaign.consequenceEchoes.count {
            warnings.append("回声重复")
        }
        if campaign.safetyHandoffState?.safetyHandoffComplete != true {
            warnings.append("交接未闭合")
        }
        if trace.count > 120 {
            warnings.append("步骤过长")
        }
        return warnings
    }
}

struct AutonomousRouteAuditView: View {
    let results: [AutonomousRouteAuditResult]
    var compact = false

    private var passCount: Int { results.filter(\.isPassing).count }
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: compact ? 6 : 8), count: 2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            HStack(spacing: 8) {
                Image(systemName: passCount == results.count ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: compact ? 11 : 14, weight: .bold))
                    .foregroundStyle(passCount == results.count ? .mint : .orange)
                Text("自主游玩路线审计")
                    .font(.system(size: compact ? 11 : 16, weight: .bold))
                Spacer()
                Text("\(passCount)/\(results.count)")
                    .font(.system(size: compact ? 10 : 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(passCount == results.count ? .mint : .orange)
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: compact ? 6 : 8) {
                ForEach(results) { result in
                    AutonomousRouteAuditCell(result: result, compact: compact)
                }
            }
        }
        .padding(compact ? 8 : 14)
        .foregroundStyle(.white)
        .background(.black.opacity(compact ? 0.22 : 0.42), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.14), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("自主游玩路线审计，\(passCount) / \(results.count) 条通过")
    }
}

private struct AutonomousRouteAuditCell: View {
    let result: AutonomousRouteAuditResult
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 7) {
            HStack(spacing: 6) {
                Circle()
                    .fill(result.isPassing ? .mint : .orange)
                    .frame(width: compact ? 5 : 7, height: compact ? 5 : 7)
                Text(result.intent.title)
                    .font(.system(size: compact ? 9 : 12, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Image(systemName: result.endingType.symbol)
                    .font(.system(size: compact ? 8 : 11, weight: .bold))
                    .foregroundStyle(result.endingType.accent)
            }

            Text("\(result.endingType.title) / \(result.routeName)")
                .font(.system(size: compact ? 8.5 : 10.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.76))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            HStack(spacing: 7) {
                Label(result.companionID, systemImage: "person.2.fill")
                Label(result.sharedSelf ? "分享" : "保留", systemImage: result.sharedSelf ? "heart.text.square.fill" : "hourglass")
                Text("\(result.stepCount) 步")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
            }
            .font(.system(size: compact ? 8 : 9.5, weight: .medium))
            .foregroundStyle(.white.opacity(0.58))
            .lineLimit(1)
        }
        .padding(compact ? 6 : 10)
        .frame(maxWidth: .infinity, minHeight: compact ? 58 : 88, alignment: .topLeading)
        .background(result.endingType.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(result.isPassing ? 0.12 : 0.28), lineWidth: 1))
    }
}

struct JiangDialogueEmbodiedCueView: View {
    static let maxWidth: CGFloat = 620
    static let minimumHeight: CGFloat = 154

    let cue: NarrativeJiangEmbodiedCue

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .center, spacing: 9) {
                Image(systemName: cue.symbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white.opacity(0.84))
                    .frame(width: 22, height: 22)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.14), lineWidth: 1))
                VStack(alignment: .leading, spacing: 2) {
                    Text("江越的状态")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.56))
                    Text(cue.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white.opacity(0.94))
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 7) {
                embodiedLine("肩膀", cue.postureLine, symbol: "figure.stand")
                embodiedLine("声音", cue.voiceLine, symbol: "waveform")
                embodiedLine("边界", cue.boundaryLine, symbol: "shield.lefthalf.filled")
            }

            Text(cue.nextPrompt)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: Self.maxWidth, minHeight: Self.minimumHeight, alignment: .topLeading)
        .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.16), lineWidth: 1))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(.white.opacity(0.24))
                .frame(width: 2)
                .padding(.vertical, 11)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("江越的状态，\(cue.title)。肩膀，\(cue.postureLine)声音，\(cue.voiceLine)边界，\(cue.boundaryLine)\(cue.nextPrompt)")
    }

    private func embodiedLine(_ title: String, _ text: String, symbol: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.62))
                .frame(width: 15)
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.52))
                .frame(width: 30, alignment: .leading)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(2)
                .minimumScaleFactor(0.78)
        }
    }
}

struct SafetyHandoffBriefingView: View {
    static let maxWidth: CGFloat = 620
    static let minimumHeight: CGFloat = 226

    let briefing: NarrativeSafetyHandoffBriefing

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 9) {
                Image(systemName: briefing.isHighPriority ? "cross.case.fill" : "person.badge.shield.checkmark.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(accent.opacity(0.92))
                    .frame(width: 24, height: 24)
                    .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(accent.opacity(0.24), lineWidth: 1))
                VStack(alignment: .leading, spacing: 2) {
                    Text("成人交接")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.56))
                    Text(briefing.teacherReachedJiang ? "接管位置已确认" : "先确认方老师到场")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white.opacity(0.94))
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                }
                Spacer(minLength: 0)
                Text(briefing.routeTitle)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(accent.opacity(0.92))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(accent.opacity(0.22), lineWidth: 1))
            }

            VStack(alignment: .leading, spacing: 7) {
                handoffLine("联络", briefing.contactLine, symbol: "phone.arrow.up.right.fill")
                handoffLine("到场", briefing.adultArrivalLine, symbol: "figure.walk.arrival")
                handoffLine("路线", briefing.routeLine, symbol: "arrow.triangle.branch")
                handoffLine("入口", briefing.entryLine, symbol: "door.left.hand.open")
                if let supportLine = briefing.supportLine {
                    handoffLine("余波", supportLine, symbol: "sparkles")
                }
            }

            HStack(spacing: 7) {
                ForEach(briefing.steps) { step in
                    handoffStep(step)
                }
            }

            Text(briefing.studentBoundaryLine)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: Self.maxWidth, minHeight: Self.minimumHeight, alignment: .topLeading)
        .background(.black.opacity(0.30), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(accent.opacity(0.20), lineWidth: 1))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(accent.opacity(0.72))
                .frame(width: 2)
                .padding(.vertical, 11)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("成人交接，\(briefing.teacherReachedJiang ? "接管位置已确认" : "先确认方老师到场")，\(briefing.routeTitle)。\(briefing.contactLine)\(briefing.adultArrivalLine)\(briefing.routeLine)\(briefing.entryLine)\(briefing.supportLine ?? "")\(briefing.studentBoundaryLine)")
    }

    private var accent: Color {
        briefing.isHighPriority ? .orange : .mint
    }

    private func handoffLine(_ title: String, _ text: String, symbol: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(accent.opacity(0.78))
                .frame(width: 15)
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.52))
                .frame(width: 30, alignment: .leading)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(2)
                .minimumScaleFactor(0.78)
        }
    }

    private func handoffStep(_ step: NarrativeSafetyHandoffBriefing.Step) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: stepIcon(for: step.state))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(stepForeground(for: step.state))
                Text(step.title)
                    .font(.system(size: 9.4, weight: .bold))
                    .foregroundStyle(stepForeground(for: step.state))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Text(step.detail)
                .font(.system(size: 8.8, weight: .semibold))
                .foregroundStyle(.white.opacity(step.state == .pending ? 0.38 : 0.62))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
        .background(stepBackground(for: step.state), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(stepStroke(for: step.state), lineWidth: 1))
    }

    private func stepIcon(for state: NarrativeSafetyHandoffBriefing.Step.State) -> String {
        switch state {
        case .complete: return "checkmark.circle.fill"
        case .current: return "scope"
        case .pending: return "circle.dotted"
        }
    }

    private func stepForeground(for state: NarrativeSafetyHandoffBriefing.Step.State) -> Color {
        switch state {
        case .complete: return .mint.opacity(0.92)
        case .current: return accent.opacity(0.92)
        case .pending: return .white.opacity(0.42)
        }
    }

    private func stepBackground(for state: NarrativeSafetyHandoffBriefing.Step.State) -> Color {
        switch state {
        case .complete: return Color.mint.opacity(0.13)
        case .current: return accent.opacity(0.13)
        case .pending: return Color.white.opacity(0.055)
        }
    }

    private func stepStroke(for state: NarrativeSafetyHandoffBriefing.Step.State) -> Color {
        switch state {
        case .complete: return Color.mint.opacity(0.26)
        case .current: return accent.opacity(0.26)
        case .pending: return Color.white.opacity(0.08)
        }
    }
}

struct CounselingWaitingStatusView: View {
    static let maxWidth: CGFloat = 620
    static let minimumHeight: CGFloat = 206

    let status: NarrativeCounselingWaitingStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 9) {
                Image(systemName: status.isEmergency ? "cross.case.fill" : "lamp.desk.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(accent.opacity(0.92))
                    .frame(width: 24, height: 24)
                    .background(accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(accent.opacity(0.24), lineWidth: 1))
                VStack(alignment: .leading, spacing: 2) {
                    Text("等候区")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.56))
                    Text(status.entryTitle)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white.opacity(0.94))
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                }
                Spacer(minLength: 0)
                Text(status.isEmergency ? "安全收束" : "隐私边界")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(accent.opacity(0.92))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(accent.opacity(0.22), lineWidth: 1))
            }

            Text(status.entryLine)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 7) {
                waitingLine("门", status.boundaryLine, symbol: "door.left.hand.closed")
                waitingLine("流言", status.rumorLine, symbol: "text.bubble")
                waitingLine("消息", status.companionLine, symbol: "message.fill")
                waitingLine("交接", status.handoffLine, symbol: "person.badge.shield.checkmark.fill")
                if let supportLine = status.supportLine {
                    waitingLine("余波", supportLine, symbol: "sparkles")
                }
            }

            if status.biasCards.isEmpty == false {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(status.biasCards) { card in
                        biasCard(card)
                    }
                }
            }
        }
        .padding(13)
        .frame(maxWidth: Self.maxWidth, minHeight: Self.minimumHeight, alignment: .topLeading)
        .background(.black.opacity(0.30), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(accent.opacity(0.20), lineWidth: 1))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(accent.opacity(0.68))
                .frame(width: 2)
                .padding(.vertical, 11)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("等候区，\(status.entryTitle)。\(status.entryLine)\(status.boundaryLine)\(status.rumorLine)\(status.companionLine)\(status.handoffLine)\(status.supportLine ?? "")")
    }

    private var accent: Color {
        status.isEmergency ? .orange : .mint
    }

    private func waitingLine(_ title: String, _ text: String, symbol: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(accent.opacity(0.76))
                .frame(width: 15)
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.52))
                .frame(width: 30, alignment: .leading)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(2)
                .minimumScaleFactor(0.78)
        }
    }

    private func biasCard(_ card: NarrativeWaitingBiasCard) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: card.symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.black.opacity(0.58))
                .frame(width: 14)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(card.title)
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.black.opacity(0.62))
                Text(card.line)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.78))
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
        .background(Color(red: 1.0, green: 0.89, blue: 0.46), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(.black.opacity(0.12), lineWidth: 1))
    }
}

struct NarrativeCampaignView: View {
    @ObservedObject var game: GameManager
    private static let supportResources = SupportResourceCatalog.bundledOrFallback().resources

    private var campaign: NarrativeCampaign { game.narrativeCampaign }
    private var moment: NarrativeMoment { campaign.currentMoment }
    private var endingType: EndingType { EndingSelector.select(campaign: campaign) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.16)
                .ignoresSafeArea()

            if campaign.isComplete {
                completionView
            } else {
                GeometryReader { proxy in
                    VStack(spacing: 18) {
                        header
                        Spacer(minLength: 8)
                        HStack {
                            if proxy.size.width >= 900 {
                                Spacer(minLength: proxy.size.width * 0.32)
                            }
                            momentCard
                                .frame(maxWidth: narrativeCardWidth(for: proxy.size.width))
                        }
                        Spacer(minLength: 8)
                        footer
                    }
                    .padding(28)
                }
            }

            if let status = campaign.companionPresenceStatus {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Group {
                            if campaign.currentMoment.choices.count > 1 {
                                CompanionStatusCompactIcon(status: status, tint: campaign.chapter.atmosphere)
                            } else {
                                CompanionStatusIcon(status: status, tint: campaign.chapter.atmosphere)
                            }
                        }
                        .padding(.trailing, 28)
                        .padding(.bottom, 86)
                    }
                }
                .allowsHitTesting(false)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .foregroundStyle(.white)
        .transition(.opacity)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(campaign.chapter.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                    Text(moment.goal)
                        .font(.system(size: 28, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 10) {
                    if campaign.companionID.isEmpty == false {
                        Label(campaign.companionID, systemImage: "person.crop.circle.badge.checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white.opacity(0.82))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 7))
                    }
                    Text(campaign.progressText)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.68))
                    if campaign.currentMoment.id.hasPrefix("4.listen.") {
                        Text("倾听 \((campaign.jiangDialogueState?.segmentIndex ?? 0) + 1) / 4 · 每段 15 秒")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.64))
                    }
                    Button { game.openNarrativePauseMenu() } label: {
                        Image(systemName: "pause.fill")
                            .frame(width: 30, height: 28)
                    }
                    .buttonStyle(SegmentButtonStyle(isSelected: false))
                    .help("暂停")
                }
            }
            ProgressView(value: overallProgress)
                .tint(campaign.chapter.atmosphere)
        }
        .padding(14)
        .narrativeGlassPanel(cornerRadius: 12, tint: campaign.chapter.atmosphere.opacity(0.35))
    }

    private var overallProgress: Double {
        let chapterBase = Double(campaign.chapter.rawValue - 1)
        let momentCount = max(1, NarrativeCampaign.moments(for: campaign.chapter).count)
        let chapterProgress = Double(campaign.momentIndex) / Double(momentCount)
        return ((chapterBase + chapterProgress) / Double(NarrativeChapter.allCases.count)).clamped(to: 0...1)
    }

    private func narrativeCardWidth(for availableWidth: CGFloat) -> CGFloat {
        guard availableWidth >= 900 else { return 760 }
        // The mirror is the chapter's first playable object. Keep its full silhouette
        // visible on the left instead of obscuring it with a generic dialogue panel.
        if campaign.chapter == .mirror {
            return 460
        }
        return 640
    }

    private var momentCard: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .firstTextBaseline) {
                Text(moment.speaker)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(campaign.chapter.atmosphere.opacity(0.85))
                Rectangle().fill(.white.opacity(0.22)).frame(height: 1)
            }
            Text(moment.title)
                .font(.system(size: 34, weight: .bold))
            Text(moment.body)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineSpacing(7)
                .fixedSize(horizontal: false, vertical: true)

            let mirrorConsequence = MirrorDialogueConsequenceModel.derive(from: campaign)
            if let impact = campaign.activeChoiceImpact,
               shouldShowChoiceImpact(impact),
               mirrorConsequence.isActive == false {
                NarrativeChoiceImpactBannerView(impact: impact, tint: campaign.chapter.atmosphere)
            }

            if mirrorConsequence.isActive {
                MirrorDialogueConsequenceView(consequence: mirrorConsequence, tint: campaign.chapter.atmosphere)
            }

            if campaign.chapter == .mirror {
                MirrorLightProgressView(campaign: campaign)
            }

            if let miniGame = moment.miniGame {
                miniGamePanel(miniGame)
            }

            if campaign.shouldPresentRiskEducationCard {
                riskEducationCard
            }

            if let cue = game.narrativeGuidanceCue,
               cue.momentID == moment.id {
                narrativeGuidanceCard(cue)
            }

            if campaign.currentMoment.id.hasPrefix("4.listen."),
               let beat = campaign.currentJiangDialoguePerformanceBeat {
                JiangDialogueEmbodiedCueView(
                    cue: NarrativeJiangEmbodiedCue.derive(
                        beat: beat,
                        consecutiveTimeouts: campaign.jiangDialogueState?.consecutiveTimeouts ?? 0
                    )
                )
            }

            if let briefing = NarrativeSafetyHandoffBriefing(campaign: campaign) {
                SafetyHandoffBriefingView(briefing: briefing)
            }

            if let waitingStatus = NarrativeCounselingWaitingStatus(campaign: campaign) {
                CounselingWaitingStatusView(status: waitingStatus)
            }

            VStack(spacing: 10) {
                ForEach(moment.choices) { choice in
                    let presentation = choicePresentation(for: choice)
                    Button {
                        game.advanceNarrative(choice.id)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: presentation.symbol)
                                .font(.system(size: 18, weight: .semibold))
                                .frame(width: 26)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(presentation.title).font(.system(size: 16, weight: .bold))
                                Text(presentation.detail).font(.system(size: 12)).foregroundStyle(.white.opacity(0.68))
                                NarrativeChoiceSignalPreviewView(
                                    signals: NarrativeChoiceSignalModel.signals(
                                        for: choice,
                                        moment: moment,
                                        campaign: campaign
                                    )
                                )
                                .padding(.top, 3)
                            }
                            Spacer()
                            Image(systemName: campaign.miniGameCompleted && moment.miniGame != nil ? "sparkle.magnifyingglass" : "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(.white.opacity(0.45))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(NarrativeChoiceStyle(tint: campaign.chapter.atmosphere))
                    .disabled(
                        campaign.explorationReady == false
                            || campaign.currentMomentActionReady == false
                            || (moment.miniGame != nil && campaign.miniGameCompleted == false)
                    )
                }
            }
        }
        .padding(30)
        .frame(maxWidth: 760)
        .narrativeGlassPanel(cornerRadius: 14, tint: .black.opacity(0.34))
    }

    private var riskEducationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("确认安全，不是替人诊断", systemImage: "cross.case.fill")
                .font(.system(size: 15, weight: .bold))
            Text("直接而温和地询问是否有伤害自己的打算，不会制造这种念头。信息不完整也不能被解释成安全；可靠成人仍然需要到场。")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.82))
                .lineSpacing(4)
            Button {
                game.dismissNarrativeRiskEducationCard()
            } label: {
                Label("我明白了", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
            }
            .buttonStyle(NarrativeChoiceStyle(tint: campaign.chapter.atmosphere))
        }
        .padding(16)
        .background(.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.2), lineWidth: 1))
    }

    private func narrativeGuidanceCard(_ cue: NarrativeGuidanceCue) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: cue.symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(cue.stage == .directorNudge ? .mint : .cyan)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(cue.title)
                        .font(.system(size: 13, weight: .bold))
                    Text("\(Int(cue.elapsedSeconds))s")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.52))
                }
                Text(cue.detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke((cue.stage == .directorNudge ? Color.mint : Color.cyan).opacity(0.22), lineWidth: 1)
        )
    }

    private func miniGamePanel(_ miniGame: NarrativeMiniGame) -> some View {
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(miniGame == .trace ? "草稿灯" : miniGame == .melody ? "旋律灯" : "擦痕灯", systemImage: miniGame == .trace ? "pencil.line" : miniGame == .melody ? "music.note" : "eraser.fill")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Text(miniGameStatus(miniGame))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Text(miniGameSummary(miniGame))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
            Button {
                game.presentNarrativeMicroGame(miniGame)
            } label: {
                Label(campaign.miniGameCompleted ? "光路已接上" : "进入感知闪现", systemImage: campaign.miniGameCompleted ? "checkmark.circle.fill" : "sparkles")
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
            }
            .buttonStyle(NarrativeChoiceStyle(tint: campaign.chapter.atmosphere))
            .disabled(campaign.miniGameCompleted)
            if campaign.miniGameCompleted {
                Label("\(miniGame.title)已经回应。按下方继续动作，让镜像空间把下一段路亮出来。", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.74))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 10))
    }

    private func choicePresentation(for choice: NarrativeChoice) -> (title: String, detail: String, symbol: String) {
        guard let miniGame = moment.miniGame, campaign.miniGameCompleted else {
            return (choice.title, choice.detail, choice.symbol)
        }
        return (miniGame.completionRouteTitle, miniGame.completionRouteDetail, miniGame.completionRouteSymbolName)
    }

    private func shouldShowChoiceImpact(_ impact: NarrativeChoiceImpact) -> Bool {
        NarrativeChapter.allCases
            .flatMap(NarrativeCampaign.moments(for:))
            .first(where: { $0.id == impact.sourceMomentID })?
            .choices.count ?? 0 > 1
    }

    private func miniGameSummary(_ miniGame: NarrativeMiniGame) -> String {
        switch miniGame {
        case .trace:
            return "离开剧情卡片，沿着六个断点把草稿灯接回去。偏离不会失败，只会等你重新对准。"
        case .melody:
            return "听见四拍后按顺序回应。按错只会重放，三次提示后苏念可以慢慢接住。"
        case .erase:
            return "擦掉贴在他身上的判断，留下不能完全被擦掉的那一部分。"
        }
    }

    private func miniGameStatus(_ miniGame: NarrativeMiniGame) -> String {
        let required = miniGame.requiredInteractions
        return campaign.miniGameCompleted ? "已点亮" : "\(campaign.miniGameProgress) / \(required)"
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)
            if let target = game.focusedNarrativeKeyboardTarget,
               target.requiresMovement || campaign.explorationReady == false || campaign.currentMomentActionReady == false {
                Button {
                    _ = game.performNarrativeKeyboardCommand(.confirm)
                } label: {
                    Label(target.title, systemImage: target.symbol)
                        .font(.system(size: 13, weight: .bold))
                        .frame(minWidth: 180, minHeight: 34)
                }
                .buttonStyle(SegmentButtonStyle(isSelected: true))
                .help(target.detail)
            }
            if let hotspot = campaign.nearbyHotspot {
                Button { game.interactNarrativeHotspot() } label: {
                    Label(hotspot.title, systemImage: "dot.radiowaves.left.and.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .buttonStyle(SegmentButtonStyle(isSelected: true))
                .help("调查附近线索")
            }
            if campaign.companionID.isEmpty == false {
                Label(campaign.companionID, systemImage: "person.2.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .narrativeGlassPanel(cornerRadius: 10, tint: .black.opacity(0.26))
    }

    private func keyboardTargetChip(_ target: NarrativeKeyboardTarget, compact: Bool = false) -> some View {
        let tint = target.requiresMovement ? Color.mint : Color.cyan
        return Label(target.title, systemImage: target.symbol)
            .font(.system(size: compact ? 11 : 12, weight: .bold))
            .foregroundStyle(.white.opacity(0.9))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .padding(.horizontal, compact ? 9 : 10)
            .frame(minWidth: compact ? 118 : 132, minHeight: compact ? 30 : 32)
            .background(tint.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(tint.opacity(0.78), lineWidth: 1))
            .shadow(color: tint.opacity(0.18), radius: 8, x: 0, y: 0)
            .accessibilityLabel("当前键盘目标，\(target.title)")
            .help("Tab 切换目标，Enter/空格确认")
    }

    private var completionView: some View {
        GeometryReader { proxy in
            let panelWidth = min(980, max(720, proxy.size.width - 80))
            let usesWideLayout = panelWidth >= 900
            ZStack {
                if usesWideLayout {
                    let height = min(760, proxy.size.height - 48)
                    let contentScale = height < 748 ? 0.76 : 0.78
                    completionWideContent(width: (panelWidth - 56) / contentScale, pinsActionsToBottom: false)
                        .padding(28 / contentScale)
                        .scaleEffect(contentScale, anchor: .top)
                        .frame(width: panelWidth, height: height, alignment: .top)
                        .narrativeGlassPanel(cornerRadius: 16, tint: campaign.chapter.atmosphere.opacity(0.45))
                } else {
                    ScrollView(.vertical, showsIndicators: true) {
                        completionNarrowContent(width: min(716, panelWidth - 64))
                            .padding(32)
                    }
                    .frame(width: panelWidth, height: min(720, proxy.size.height - 48))
                    .narrativeGlassPanel(cornerRadius: 16, tint: campaign.chapter.atmosphere.opacity(0.45))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func completionWideContent(width: CGFloat, pinsActionsToBottom: Bool) -> some View {
        VStack(spacing: 16) {
            completionHeader
            HStack(alignment: .top, spacing: 14) {
                SupportNetworkView(campaign: campaign, canvasHeight: 116, compact: true)
                    .frame(width: width * 0.58)
                CampaignDossierView(campaign: campaign, compact: true)
                    .frame(width: width * 0.42 - 14)
            }
            HStack(alignment: .top, spacing: 14) {
                EmpathyReplayView(campaign: campaign)
                    .frame(width: width * 0.58)
                TruthReplayView(campaign: campaign)
                    .frame(width: width * 0.42 - 14)
            }
            HStack(alignment: .top, spacing: 14) {
                endingSummaryCard
                .frame(width: width * 0.36)
                PolicyExperimentLabView(campaign: campaign)
                    .frame(width: width * 0.32 - 7)
                SupportResourceCompactStripView(resources: Self.supportResources)
                    .frame(width: width * 0.32 - 7)
            }
            if pinsActionsToBottom {
                Spacer(minLength: 0)
            }
            completionActions
        }
        .frame(width: width, alignment: .top)
    }

    private func completionNarrowContent(width: CGFloat) -> some View {
        VStack(spacing: 18) {
            completionHeader
            SupportNetworkView(campaign: campaign)
            CampaignDossierView(campaign: campaign)
            EmpathyReplayView(campaign: campaign)
            TruthReplayView(campaign: campaign)
            endingSummaryCard
            EndingRouteSpectrumView(campaign: campaign)
            PolicyExperimentLabView(campaign: campaign)
            SupportResourceView(resources: Self.supportResources)
            completionActions
        }
        .frame(width: width, alignment: .leading)
    }

    private var completionHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("第六章完成")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.72))
                Text(endingType.title)
                    .font(.system(size: 38, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text(campaign.progressText)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.62))
        }
    }

    private var endingSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(endingType.body)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white.opacity(0.88))
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)

            if EndingSelector.needsSelfCareReminder(campaign: campaign) {
                Text("记得照顾自己。帮助别人的人，自己也需要被接住。")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.cyan.opacity(0.88))
                    .padding(.top, 2)
            }

            FlowLayout(spacing: 8) {
                completionStatusChip(
                    "安全交接：\(campaign.safetyRoute.isEmpty ? "咨询室支持" : campaign.safetyRoute)",
                    systemImage: "shield.fill"
                )
                completionStatusChip(
                    campaign.privacyProtected ? "隐私已保护" : "隐私仍需照顾",
                    systemImage: "lock.fill"
                )
                completionStatusChip(
                    campaign.sharedSelf ? "苏念也说出了自己的疲惫" : "苏念给自己保留了节奏",
                    systemImage: "person.crop.circle.badge.checkmark"
                )
            }
        }
        .padding(16)
        .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func completionStatusChip(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.8))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(.white.opacity(0.08), in: Capsule())
    }

    private var completionActions: some View {
        HStack(spacing: 10) {
            Button { game.startTeacherTruthRunFromEpilogue() } label: {
                Label("进入教师真相二周目", systemImage: "person.text.rectangle.fill")
                    .frame(width: 220, height: 42)
            }
            .buttonStyle(.plain)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .background(.mint.opacity(0.24), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.white.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: .mint.opacity(0.18), radius: 12, x: 0, y: 0)

            Button { game.returnToMenuForNewGame() } label: {
                Label("确认并返回主菜单", systemImage: "checkmark.circle.fill")
                    .frame(width: 220, height: 42)
            }
            .buttonStyle(.plain)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .background(.cyan.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.white.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: .cyan.opacity(0.20), radius: 12, x: 0, y: 0)
        }
    }
}

struct MicroGameOverlayView: View {
    @ObservedObject var game: GameManager
    let miniGame: NarrativeMiniGame
    @State private var traceCoveredSamples: Set<Int> = []
    @State private var traceDragCoverage = 0.0
    @State private var traceMissFeedbackArmed = true
    @State private var eraseDragTrail: [CGPoint] = []
    @State private var eraseMissFeedbackArmed = true

    private var campaign: NarrativeCampaign { game.narrativeCampaign }
    private var required: Int { miniGame.requiredInteractions }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.44))
                .ignoresSafeArea()
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                header
                activeGameSurface
                footer
            }
            .padding(24)
            .frame(width: 760)
            .narrativeGlassPanel(cornerRadius: 14, tint: campaign.chapter.atmosphere.opacity(0.38))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(campaign.chapter.atmosphere.opacity(0.34), lineWidth: 1))
            .shadow(color: campaign.chapter.atmosphere.opacity(0.26), radius: 28, x: 0, y: 0)
        }
        .foregroundStyle(.white)
        .transition(.opacity)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Label(miniGame.title, systemImage: miniGame.symbolName)
                    .font(.system(size: 18, weight: .bold))
                Spacer()
                Text("\(min(campaign.miniGameProgress, required)) / \(required)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.68))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule()
                        .fill(campaign.chapter.atmosphere.opacity(0.88))
                        .frame(width: geo.size.width * progressRatio)
                }
            }
            .frame(height: 7)
            if echoModel.isActive {
                HStack(spacing: 8) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.cyan.opacity(0.82))
                        .frame(width: 15)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(echoModel.title)
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(.white.opacity(0.82))
                        Text(echoModel.detail)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.58))
                            .lineLimit(2)
                    }
                    Spacer()
                    Text("\(echoModel.completedSteps)/\(echoModel.requiredSteps)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.52))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 7))
            }
            inputFeedbackPanel
        }
    }

    private var echoModel: MirrorMicroGameEchoModel {
        MirrorMicroGameEchoModel.derive(from: campaign)
    }

    private var inputFeedbackModel: MirrorMicroGameInputFeedbackModel {
        if let feedback = game.lastNarrativeMicroGameFeedback,
           feedback.miniGame == miniGame {
            return feedback
        }
        return MirrorMicroGameInputFeedbackModel.ready(from: campaign, miniGame: miniGame)
    }

    private var inputFeedbackPanel: some View {
        let feedback = inputFeedbackModel
        return HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(inputFeedbackTint.opacity(0.18))
                Image(systemName: feedback.tone.symbolName)
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(inputFeedbackTint.opacity(0.92))
            }
            .frame(width: 30, height: 30)
            .overlay(Circle().stroke(inputFeedbackTint.opacity(0.28), lineWidth: 1))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(feedback.title)
                        .font(.system(size: 11.5, weight: .black))
                        .foregroundStyle(.white.opacity(0.88))
                    Text(feedback.targetText)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(inputFeedbackTint.opacity(0.82))
                        .lineLimit(1)
                }
                Text(feedback.detail)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.60))
                    .lineLimit(2)
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 4) {
                Text(feedback.progressText)
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.74))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(feedback.toleranceText)
                    Text(feedback.accessibilityText)
                }
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.46))
                .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(inputFeedbackTint.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(inputFeedbackTint.opacity(0.16), lineWidth: 1))
    }

    private var inputFeedbackTint: Color {
        switch inputFeedbackModel.tone {
        case .ready:
            return campaign.chapter.atmosphere
        case .caught:
            return .cyan
        case .recover:
            return .orange
        case .completed:
            return .mint
        }
    }

    @ViewBuilder
    private var activeGameSurface: some View {
        switch miniGame {
        case .trace:
            traceSurface
        case .melody:
            melodySurface
        case .erase:
            eraseSurface
        }
    }

    private var traceSurface: some View {
        VStack(spacing: 12) {
            GeometryReader { proxy in
                let points = tracePoints(in: proxy.size)
                ZStack {
                    Path { path in
                        guard let first = points.first else { return }
                        path.move(to: first)
                        for point in points.dropFirst() { path.addLine(to: point) }
                    }
                    .stroke(.white.opacity(0.18), style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [6, 8]))

                    Path { path in
                        guard campaign.miniGameProgress > 0 else { return }
                        path.move(to: points[0])
                        for point in points[1..<min(campaign.miniGameProgress + 1, points.count)] {
                            path.addLine(to: point)
                        }
                    }
                    .stroke(campaign.chapter.atmosphere, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                    .shadow(color: campaign.chapter.atmosphere.opacity(0.7), radius: 10, x: 0, y: 0)

                    if traceDragCoverage > 0,
                       campaign.miniGameCompleted == false,
                       campaign.miniGameProgress + 1 < points.count {
                        Path { path in
                            let start = points[campaign.miniGameProgress]
                            let end = traceInterpolatedPoint(from: start, to: points[campaign.miniGameProgress + 1], ratio: traceDragCoverage)
                            path.move(to: start)
                            path.addLine(to: end)
                        }
                        .stroke(.cyan.opacity(0.86), style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                        .shadow(color: .cyan.opacity(0.7), radius: 10, x: 0, y: 0)
                    }

                    ForEach(points.indices, id: \.self) { index in
                        Circle()
                            .fill(index <= campaign.miniGameProgress ? campaign.chapter.atmosphere : .white.opacity(index == campaign.miniGameProgress + 1 ? 0.5 : 0.22))
                            .frame(width: index == campaign.miniGameProgress + 1 ? 24 : 18, height: index == campaign.miniGameProgress + 1 ? 24 : 18)
                            .overlay(Circle().stroke(.white.opacity(0.66), lineWidth: 1))
                            .position(points[index])
                    }
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    handleTraceDrag(location: value.location, points: points)
                }.onEnded { _ in
                    resetTraceDragAttempt()
                })
            }
            .frame(height: game.accessibilityPreferences.keyboardAlternativeInput && campaign.miniGameCompleted == false ? 208 : 260)

            if game.accessibilityPreferences.keyboardAlternativeInput && campaign.miniGameCompleted == false {
                HStack(spacing: 10) {
                    Label("键盘段 \(min(campaign.miniGameProgress + 1, required)) / \(required)", systemImage: "keyboard")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button { game.performNarrativeMiniGameAction(campaign.miniGameProgress) } label: {
                        Label("确认下一段", systemImage: "checkmark.circle.fill")
                            .frame(width: 138, height: 38)
                    }
                    .buttonStyle(NarrativeChoiceStyle(tint: campaign.chapter.atmosphere))
                    .disabled(game.narrativeCanAcceptMicroGameInput == false)
                }

                Button { game.completeNarrativeMiniGameAccessibly() } label: {
                    Label("由苏念慢慢描到 80%", systemImage: "hand.raised.fill")
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                }
                .buttonStyle(NarrativeChoiceStyle(tint: .mint))
                .disabled(game.narrativeCanAcceptMicroGameInput == false)
            }
        }
        .frame(height: 260)
        .accessibilityLabel("草稿灯描线，沿断点拖动")
    }

    private var melodySurface: some View {
        let melody = MirrorMelodyPlaybackModel.derive(from: campaign)
        return VStack(spacing: 14) {
            if melody.isActive {
                melodySequenceRail(melody)
            }

            HStack(spacing: 12) {
                ForEach(melody.pads.isEmpty ? MirrorMelodyPlaybackModel.derive(from: campaign).pads : melody.pads) { pad in
                    Button { game.performNarrativeMiniGameAction(pad.id) } label: {
                        VStack(spacing: 8) {
                            Image(systemName: pad.isNext ? "music.note.list" : "music.note")
                                .font(.system(size: 26, weight: .bold))
                            Text(pad.label)
                                .font(.system(size: 15, weight: .bold))
                            Text(pad.caption)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white.opacity(0.56))
                        }
                        .frame(maxWidth: .infinity, minHeight: 88)
                    }
                    .buttonStyle(MelodyPadStyle(tint: campaign.chapter.atmosphere, isLit: pad.isPlayed, isNext: pad.isNext))
                    .disabled(game.narrativeCanAcceptMicroGameInput == false || campaign.miniGameCompleted)
                }
            }

            Button { game.replayNarrativeMiniGameCue() } label: {
                Label("再听一次", systemImage: "speaker.wave.2.fill")
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
            }
            .buttonStyle(NarrativeChoiceStyle(tint: campaign.chapter.atmosphere))
            .disabled(game.narrativeCanAcceptMicroGameInput == false || campaign.miniGameCompleted)

            if campaign.miniGameHintCount >= 2 && campaign.miniGameCompleted == false {
                Button { game.completeNarrativeMiniGameAccessibly() } label: {
                    Label("由苏念慢慢接住这盏灯", systemImage: "hand.raised.fill")
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                }
                .buttonStyle(NarrativeChoiceStyle(tint: .mint))
            }

            Text(campaign.miniGameHintCount >= 2 ? "提示已经出现；听不清也可以慢慢完成。" : melody.statusText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.66))
        }
    }

    private func melodySequenceRail(_ melody: MirrorMelodyPlaybackModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("四拍播放", systemImage: "waveform")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(.white.opacity(0.78))
                Spacer()
                Text(melody.frequencyText)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.50))
            }

            HStack(spacing: 8) {
                ForEach(Array(MirrorMelodyPlaybackModel.sequence.enumerated()), id: \.offset) { order, padIndex in
                    let label = MirrorMelodyPlaybackModel.labels[padIndex]
                    let frequency = MirrorMelodyPlaybackModel.frequencies[padIndex]
                    HStack(spacing: 6) {
                        Text("\(order + 1)")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .foregroundStyle(.black.opacity(0.62))
                            .frame(width: 16, height: 16)
                            .background(.white.opacity(order < melody.completedBeats ? 0.82 : 0.44), in: Circle())
                        VStack(alignment: .leading, spacing: 1) {
                            Text(label)
                                .font(.system(size: 11, weight: .black))
                            Text("\(Int(frequency))Hz")
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.50))
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(order < melody.completedBeats ? .white.opacity(0.18) : (order == melody.completedBeats ? .cyan.opacity(0.16) : .white.opacity(0.07)), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(order == melody.completedBeats ? .cyan.opacity(0.42) : .white.opacity(0.12), lineWidth: 1))
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
    }

    private var eraseSurface: some View {
        let words = ["你应该没事", "别太敏感", "忍一忍", "别麻烦别人", "大家都一样", "很快就过去"]
        return VStack(alignment: .leading, spacing: 14) {
            GeometryReader { proxy in
                let anchors = eraseAnchors(in: proxy.size)
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.black.opacity(0.24))
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(.white.opacity(0.14), lineWidth: 1)

                    ForEach(0..<7, id: \.self) { line in
                        Path { path in
                            let y = CGFloat(line) * proxy.size.height / 6
                            path.move(to: CGPoint(x: 18, y: y + 8))
                            path.addLine(to: CGPoint(x: proxy.size.width - 18, y: y - 12))
                        }
                        .stroke(.white.opacity(0.06), lineWidth: 1)
                    }

                    eraseScratchTrail

                    ForEach(words.indices, id: \.self) { index in
                        eraseWordButton(words[index], index: index)
                            .position(anchors[index])
                    }
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    handleEraseDrag(location: value.location, anchors: anchors)
                }.onEnded { _ in
                    eraseMissFeedbackArmed = true
                })
            }
            .frame(height: 210)
            .accessibilityLabel("擦痕灯擦除比较，拖过句子或用键盘逐项确认")

            HStack(spacing: 10) {
                Label("拖过句子，或用 Tab 与确认键逐段擦除", systemImage: "hand.draw.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                Spacer()
                Text("目标 60%，保留 40%")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.78))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.09), in: Capsule())
            }

            if game.accessibilityPreferences.keyboardAlternativeInput && campaign.miniGameCompleted == false {
                HStack(spacing: 10) {
                    Label("键盘擦除 \(campaign.miniGameTouchedSlots.count) / \(required)", systemImage: "keyboard")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        if let slot = nextEraseKeyboardSlot {
                            game.performNarrativeMiniGameAction(slot)
                        }
                    } label: {
                        Label("擦下一句", systemImage: "eraser.line.dashed")
                            .frame(width: 128, height: 38)
                    }
                    .buttonStyle(NarrativeChoiceStyle(tint: campaign.chapter.atmosphere))
                    .disabled(game.narrativeCanAcceptMicroGameInput == false || nextEraseKeyboardSlot == nil)
                }

                Button { game.completeNarrativeMiniGameAccessibly() } label: {
                    Label("由苏念慢慢擦到 60%", systemImage: "hand.raised.fill")
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                }
                .buttonStyle(NarrativeChoiceStyle(tint: .mint))
                .disabled(game.narrativeCanAcceptMicroGameInput == false)
            }

            Text("擦掉四句就够了；剩下的话还会留在镜面边缘，因为比较不会靠一次选择完全消失。")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.66))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func handleTraceDrag(location: CGPoint, points: [CGPoint]) {
        guard game.narrativeCanAcceptMicroGameInput,
              campaign.miniGameCompleted == false else { return }
        let segment = campaign.miniGameProgress
        let assessment = MirrorTraceGestureAssessment.assess(
            location: location,
            segment: segment,
            points: points,
            coveredSamples: traceCoveredSamples
        )
        guard assessment.isHit else {
            if traceMissFeedbackArmed {
                traceMissFeedbackArmed = false
                traceCoveredSamples = []
                traceDragCoverage = 0
                game.recordNarrativeMicroGameRecoveryAttempt(slot: segment)
            }
            return
        }

        traceMissFeedbackArmed = true
        if let sample = assessment.sampleIndex {
            traceCoveredSamples.insert(sample)
        }
        traceDragCoverage = Double(traceCoveredSamples.count) / Double(MirrorTraceGestureAssessment.sampleCount)
        if traceDragCoverage >= MirrorTraceGestureAssessment.requiredCoverage {
            game.performNarrativeMiniGameAction(segment)
            resetTraceDragAttempt()
        }
    }

    private func resetTraceDragAttempt() {
        traceCoveredSamples = []
        traceDragCoverage = 0
        traceMissFeedbackArmed = true
    }

    private func handleEraseDrag(location: CGPoint, anchors: [CGPoint]) {
        guard game.narrativeCanAcceptMicroGameInput,
              campaign.miniGameCompleted == false else { return }
        appendEraseTrailPoint(location)
        let assessment = MirrorEraseGestureAssessment.assess(
            location: location,
            anchors: anchors,
            touchedSlots: campaign.miniGameTouchedSlots
        )
        if assessment.shouldCommitErase, let slot = assessment.slot {
            eraseMissFeedbackArmed = true
            game.performNarrativeMiniGameAction(slot)
        } else if assessment.isHit == false, eraseMissFeedbackArmed {
            eraseMissFeedbackArmed = false
            game.recordNarrativeMicroGameRecoveryAttempt(slot: -1)
        }
    }

    private func traceInterpolatedPoint(from start: CGPoint, to end: CGPoint, ratio: Double) -> CGPoint {
        let clamped = CGFloat(ratio.clamped(to: 0...1))
        return CGPoint(
            x: start.x + (end.x - start.x) * clamped,
            y: start.y + (end.y - start.y) * clamped
        )
    }

    private func eraseWordButton(_ word: String, index: Int) -> some View {
        Button { game.performNarrativeMiniGameAction(index) } label: {
            Text(word)
                .font(.system(size: 16, weight: .semibold))
                .strikethrough(campaign.miniGameTouchedSlots.contains(index), color: .white.opacity(0.75))
                .opacity(campaign.miniGameTouchedSlots.contains(index) ? 0.26 : 1)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
        }
        .buttonStyle(EraseWordStyle(isErased: campaign.miniGameTouchedSlots.contains(index)))
        .disabled(game.narrativeCanAcceptMicroGameInput == false || campaign.miniGameTouchedSlots.contains(index) || campaign.miniGameCompleted)
        .help(campaign.miniGameTouchedSlots.contains(index) ? "已经擦过" : "擦掉这一句比较")
    }
    private var eraseScratchTrail: some View {
        ZStack {
            Path { path in
                guard let first = eraseDragTrail.first else { return }
                path.move(to: first)
                for point in eraseDragTrail.dropFirst() {
                    path.addLine(to: point)
                }
            }
            .stroke(.white.opacity(0.20), style: StrokeStyle(lineWidth: 24, lineCap: .round, lineJoin: .round))
            .blendMode(.screen)

            Path { path in
                guard let first = eraseDragTrail.first else { return }
                path.move(to: first)
                for point in eraseDragTrail.dropFirst() {
                    path.addLine(to: point)
                }
            }
            .stroke(campaign.chapter.atmosphere.opacity(0.22), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
        }
        .allowsHitTesting(false)
    }

    private func appendEraseTrailPoint(_ point: CGPoint) {
        guard eraseDragTrail.last?.distance(to: point) ?? 999 > 5 else { return }
        eraseDragTrail.append(point)
        if eraseDragTrail.count > 96 {
            eraseDragTrail.removeFirst(eraseDragTrail.count - 96)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Image(systemName: campaign.miniGameCompleted ? "checkmark.circle.fill" : "sparkles")
                .foregroundStyle(campaign.miniGameCompleted ? .mint : campaign.chapter.atmosphere)
            Text(campaign.miniGameCompleted ? "灯已经点亮，回到镜面路线。" : "剧情暂时停住，只保留这一盏灯的操作。")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
            Spacer()
            Button { game.dismissNarrativeMicroGame() } label: {
                Image(systemName: "xmark")
                    .frame(width: 32, height: 30)
            }
            .buttonStyle(SegmentButtonStyle(isSelected: false))
            .help("离开微游戏")
        }
    }

    private var progressRatio: Double {
        guard required > 0 else { return 1 }
        return (Double(campaign.miniGameProgress) / Double(required)).clamped(to: 0...1)
    }

    private var nextEraseKeyboardSlot: Int? {
        (0..<6).first { campaign.miniGameTouchedSlots.contains($0) == false }
    }

    private func tracePoints(in size: CGSize) -> [CGPoint] {
        [CGPoint(x: size.width * 0.10, y: size.height * 0.68),
         CGPoint(x: size.width * 0.24, y: size.height * 0.30),
         CGPoint(x: size.width * 0.42, y: size.height * 0.56),
         CGPoint(x: size.width * 0.56, y: size.height * 0.22),
         CGPoint(x: size.width * 0.73, y: size.height * 0.64),
         CGPoint(x: size.width * 0.90, y: size.height * 0.38)]
    }

    private func eraseAnchors(in size: CGSize) -> [CGPoint] {
        [
            CGPoint(x: size.width * 0.18, y: size.height * 0.30),
            CGPoint(x: size.width * 0.50, y: size.height * 0.24),
            CGPoint(x: size.width * 0.80, y: size.height * 0.34),
            CGPoint(x: size.width * 0.24, y: size.height * 0.68),
            CGPoint(x: size.width * 0.55, y: size.height * 0.74),
            CGPoint(x: size.width * 0.82, y: size.height * 0.66)
        ]
    }

    private func traceSegmentHit(for location: CGPoint, in points: [CGPoint]) -> Int? {
        let segment = campaign.miniGameProgress
        guard segment >= 0,
              segment < miniGame.requiredInteractions,
              segment + 1 < points.count else { return nil }
        let distance = location.distance(toSegmentFrom: points[segment], to: points[segment + 1])
        return distance <= 15 ? segment : nil
    }
}

private struct NarrativeChoiceStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(tint.opacity(configuration.isPressed ? 0.55 : 0.34), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(configuration.isPressed ? 0.42 : 0.18), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

private struct NarrativeChoiceSignalPreviewView: View {
    let signals: [NarrativeChoiceSignal]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(signals) { signal in
                NarrativeChoiceSignalChip(signal: signal)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("选择信号：\(signals.map(\.title).joined(separator: "，"))")
    }
}

private struct NarrativeChoiceSignalChip: View {
    let signal: NarrativeChoiceSignal

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: signal.symbol)
                .font(.system(size: 8.5, weight: .bold))
            Text(signal.title)
                .font(.system(size: 9.5, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .foregroundStyle(.white.opacity(0.86))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .frame(minHeight: 18)
        .background(signal.tint.opacity(0.20), in: Capsule())
        .overlay(Capsule().stroke(signal.tint.opacity(0.38), lineWidth: 1))
    }
}

private struct NarrativeChoiceImpactBannerView: View {
    let impact: NarrativeChoiceImpact
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.22))
                Image(systemName: impact.symbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white.opacity(0.90))
            }
            .frame(width: 34, height: 34)
            .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("刚才的选择")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(tint.opacity(0.82))
                    Text("“\(impact.choiceTitle)”")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.50))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                Text(impact.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                Text(impact.detail)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)

                NarrativeChoiceSignalPreviewView(signals: impact.signals)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(.white.opacity(0.14), lineWidth: 1))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(tint.opacity(0.56))
                .frame(width: 2)
                .padding(.vertical, 10)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("刚才的选择，\(impact.choiceTitle)。\(impact.title)。\(impact.detail)")
    }
}

private struct MirrorDialogueConsequenceView: View {
    let consequence: MirrorDialogueConsequenceModel
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(tint.opacity(0.18))
                Image(systemName: consequence.symbol)
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(width: 36, height: 36)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.16), lineWidth: 1))

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text("林澈回应")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(tint.opacity(0.84))
                    Text(consequence.trustDeltaText)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.56))
                    Text(consequence.trustTotalText)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.42))
                }

                Text(consequence.title)
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)

                Text(consequence.detail)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)

                HStack(spacing: 8) {
                    Label(consequence.supportBiasText, systemImage: "point.3.connected.trianglepath.dotted")
                    Spacer(minLength: 6)
                    Text(consequence.nextChapterHint)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.56))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(tint.opacity(0.18), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(consequence.title)。\(consequence.detail)。\(consequence.trustDeltaText)。\(consequence.nextChapterHint)")
    }
}

struct CompanionStatusCompactIcon: View {
    let status: NarrativeCompanionPresenceStatus
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.50))
            Circle()
                .fill(tint.opacity(0.22))
                .padding(6)
            Image(systemName: status.symbol)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(.white.opacity(0.92))
        }
        .overlay(alignment: .topTrailing) {
            Text(status.shortRole)
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(.black.opacity(0.70))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(tint.opacity(0.92), in: Capsule())
                .offset(x: 8, y: -5)
        }
        .frame(width: 54, height: 54)
        .overlay(Circle().stroke(.white.opacity(0.22), lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 10, y: 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("同伴\(status.companionID)，\(status.shortRole)。\(status.detail)")
    }
}

struct CompanionStatusIcon: View {
    let status: NarrativeCompanionPresenceStatus
    let tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.28))
                Image(systemName: status.symbol)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white.opacity(0.92))
            }
            .frame(width: 42, height: 42)
            .overlay(Circle().stroke(.white.opacity(0.22), lineWidth: 1))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(status.companionID)
                        .font(.system(size: 12, weight: .bold))
                    Text(status.shortRole)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.52))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.white.opacity(0.08), in: Capsule())
                }
                Text(status.title)
                    .font(.system(size: 11, weight: .bold))
                    .lineLimit(1)
                Text(status.detail)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(2)
                if let navigationLine = status.navigationLine {
                    Label(navigationLine, systemImage: status.navigationSymbol)
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(tint.opacity(0.86))
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 278, alignment: .leading)
        .frame(minHeight: 66, alignment: .leading)
        .narrativeGlassPanel(cornerRadius: 8, tint: .black.opacity(0.34))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(0.22), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(status.companionID)，\(status.title)。\(status.detail)。\(status.navigationLine ?? "")")
    }
}

struct ChapterThreeNavigationCue: Equatable {
    let targetID: String
    let targetTitle: String
    let distanceText: String
    let headingText: String
    let compassSymbol: String
    let distanceBand: String
    let statusText: String
    let isInRange: Bool
    let proximity: Double
    let pulseIntensity: Double

    static func derive(from campaign: NarrativeCampaign) -> ChapterThreeNavigationCue? {
        guard campaign.chapter == .noteTrace,
              campaign.isComplete == false,
              let hotspot = campaign.requiredInteractionHotspots.first else { return nil }

        let dx = hotspot.x - campaign.exploration.positionX
        let dz = hotspot.z - campaign.exploration.positionZ
        let distance = hypot(dx, dz)
        let roundedDistance = (distance * 10).rounded() / 10
        let isInRange = distance <= hotspot.radius
        let outsideDistance = max(0, distance - hotspot.radius)
        let proximity = isInRange ? 1 : max(0, min(1, 1 - outsideDistance / 4))
        let direction = directionPrompt(dx: dx, dz: dz, isInRange: isInRange)
        let distanceBand: String
        if isInRange {
            distanceBand = "确认范围"
        } else if outsideDistance > 2.6 {
            distanceBand = "远距"
        } else if outsideDistance > 1.2 {
            distanceBand = "中距"
        } else {
            distanceBand = "近距"
        }
        let pulseIntensity = isInRange ? 1 : (0.22 + proximity * 0.68).clamped(to: 0.22...0.9)

        return ChapterThreeNavigationCue(
            targetID: hotspot.id,
            targetTitle: hotspot.title,
            distanceText: "\(roundedDistance)m",
            headingText: direction.text,
            compassSymbol: direction.symbol,
            distanceBand: distanceBand,
            statusText: isInRange ? "已进入确认范围 · 按 E 互动" : "距目标 \(roundedDistance)m · 继续靠近",
            isInRange: isInRange,
            proximity: proximity,
            pulseIntensity: pulseIntensity
        )
    }

    private static func directionPrompt(dx: Double, dz: Double, isInRange: Bool) -> (text: String, symbol: String) {
        guard isInRange == false else { return ("目标就在身边", "scope") }

        let lateral = abs(dx) > 0.35 ? (dx > 0 ? "右" : "左") : ""
        let depth = abs(dz) > 0.35 ? (dz > 0 ? "前方" : "后方") : ""
        switch (lateral, depth) {
        case ("右", "前方"):
            return ("向右前方靠近", "arrow.up.right.circle.fill")
        case ("左", "前方"):
            return ("向左前方靠近", "arrow.up.left.circle.fill")
        case ("右", "后方"):
            return ("向右后方靠近", "arrow.down.right.circle.fill")
        case ("左", "后方"):
            return ("向左后方靠近", "arrow.down.left.circle.fill")
        case ("右", _):
            return ("向右侧靠近", "arrow.right.circle.fill")
        case ("左", _):
            return ("向左侧靠近", "arrow.left.circle.fill")
        case (_, "前方"):
            return ("向前方靠近", "arrow.up.circle.fill")
        case (_, "后方"):
            return ("向后方靠近", "arrow.down.circle.fill")
        default:
            return ("慢慢微调位置", "location.circle.fill")
        }
    }
}

struct ChapterThreeInvestigationView: View {
    let campaign: NarrativeCampaign

    private var steps: [NarrativeInvestigationStep] {
        campaign.chapterThreeInvestigationSteps
    }

    private var navigationCue: ChapterThreeNavigationCue? {
        ChapterThreeNavigationCue.derive(from: campaign)
    }

    private var carryoverCue: MirrorDialogueCarryoverModel? {
        let cue = MirrorDialogueCarryoverModel.derive(from: campaign)
        return cue.isActive ? cue : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.mint.opacity(0.9))
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text("纸条调查链")
                        .font(.system(size: 13, weight: .bold))
                    Text(summaryText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Text("\(steps.filter { $0.state == .complete }.count)/\(steps.count)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.68))
            }

            if let carryoverCue {
                carryoverRow(carryoverCue)
            }

            HStack(spacing: 8) {
                ForEach(steps) { step in
                    investigationStep(step)
                }
            }

            if shouldShowDepartureClues {
                departureClueRow
            }

            if let navigationCue {
                navigationRow(navigationCue)
            }
        }
        .padding(13)
        .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(.mint.opacity(0.18), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("纸条调查链，\(summaryText)，\(navigationCue?.statusText ?? "")，\(carryoverCue?.title ?? "")，已确认 \(steps.filter { $0.state == .complete }.count) 项")
    }

    private func investigationStep(_ step: NarrativeInvestigationStep) -> some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(fill(for: step.state))
                    .frame(height: 42)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(stroke(for: step.state), lineWidth: 1))
                    .shadow(color: glow(for: step.state), radius: step.state == .active ? 10 : 0, x: 0, y: 0)
                Image(systemName: icon(for: step))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(iconColor(for: step.state))
            }
            Text(step.title)
                .font(.system(size: 9.5, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Text(caption(for: step))
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(.white.opacity(step.state == .locked ? 0.42 : 0.66))
                .lineLimit(1)
                .minimumScaleFactor(0.74)
        }
        .frame(maxWidth: .infinity, minHeight: 82)
    }

    private var shouldShowDepartureClues: Bool {
        campaign.currentMoment.id == "3.locate"
            || campaign.noteTraceDepartureClues.isEmpty == false
    }

    private var departureClueRow: some View {
        HStack(spacing: 8) {
            Label("离开迹象 \(campaign.noteTraceDepartureProgressText)", systemImage: "figure.walk")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(.white.opacity(0.74))
                .frame(width: 108, alignment: .leading)

            departureClueChip(.deskTrace)
            departureClueChip(.doorSound)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(0.1), lineWidth: 1))
    }

    private func departureClueChip(_ clue: NoteTraceDepartureClue) -> some View {
        let isComplete = campaign.noteTraceDepartureClues.contains(clue)
        return HStack(spacing: 5) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle.dotted")
                .font(.system(size: 10, weight: .bold))
            Text(clue.title)
                .font(.system(size: 9.5, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(isComplete ? Color.black.opacity(0.82) : Color.white.opacity(0.58))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(isComplete ? Color.mint.opacity(0.72) : Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(isComplete ? Color.white.opacity(0.36) : Color.white.opacity(0.1), lineWidth: 1))
    }

    private func navigationRow(_ cue: ChapterThreeNavigationCue) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                Image(systemName: cue.compassSymbol)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(cue.isInRange ? .mint.opacity(0.95) : .cyan.opacity(0.9))
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text("当前空间目标：\(cue.targetTitle)")
                        .font(.system(size: 11.5, weight: .bold))
                    Text("\(cue.headingText) · \(cue.distanceBand) · \(cue.statusText)")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.66))
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(cue.distanceText)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                    Text("脉冲 \(Int((cue.pulseIntensity * 100).rounded()))")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundStyle((cue.isInRange ? Color.mint : Color.cyan).opacity(0.76))
                }
                .foregroundStyle(cue.isInRange ? .mint.opacity(0.92) : .white.opacity(0.72))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.white.opacity(cue.isInRange ? 0.13 : 0.08), in: RoundedRectangle(cornerRadius: 6))
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.1))
                    Capsule()
                        .fill((cue.isInRange ? Color.mint : Color.cyan).opacity(0.64))
                        .frame(width: max(8, proxy.size.width * cue.pulseIntensity))
                }
            }
            .frame(height: 5)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke((cue.isInRange ? Color.mint : Color.cyan).opacity(0.18), lineWidth: 1))
    }

    private func carryoverRow(_ cue: MirrorDialogueCarryoverModel) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(.white.opacity(0.06))
                Image(systemName: cue.symbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.88))
            }
            .frame(width: 30, height: 30)
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(0.12), lineWidth: 1))

            VStack(alignment: .leading, spacing: 3) {
                Text(cue.title)
                    .font(.system(size: 11.5, weight: .bold))
                Text(cue.detail)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.64))
                    .fixedSize(horizontal: false, vertical: true)
                Text(cue.supportBiasText)
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.mint.opacity(0.88))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(.mint.opacity(0.14), lineWidth: 1))
    }

    private var summaryText: String {
        if steps.allSatisfy({ $0.state == .complete }) {
            return "线索、同行者和入口都已确认。"
        }
        if let active = steps.first(where: { $0.state == .active }) {
            return "下一步：靠近「\(active.title)」。"
        }
        return "沿着纸条慢慢确认，不替任何人下结论。"
    }

    private func icon(for step: NarrativeInvestigationStep) -> String {
        step.state == .complete ? "checkmark" : step.symbol
    }

    private func caption(for step: NarrativeInvestigationStep) -> String {
        switch step.state {
        case .complete: return "已确认"
        case .active: return step.detail
        case .locked: return "待解锁"
        }
    }

    private func fill(for state: NarrativeInvestigationStep.State) -> Color {
        switch state {
        case .complete: return Color.mint.opacity(0.74)
        case .active: return Color.cyan.opacity(0.28)
        case .locked: return Color.white.opacity(0.08)
        }
    }

    private func stroke(for state: NarrativeInvestigationStep.State) -> Color {
        switch state {
        case .complete: return Color.white.opacity(0.48)
        case .active: return Color.cyan.opacity(0.62)
        case .locked: return Color.white.opacity(0.14)
        }
    }

    private func iconColor(for state: NarrativeInvestigationStep.State) -> Color {
        switch state {
        case .complete: return Color.black.opacity(0.84)
        case .active: return Color.white.opacity(0.92)
        case .locked: return Color.white.opacity(0.38)
        }
    }

    private func glow(for state: NarrativeInvestigationStep.State) -> Color {
        state == .active ? Color.cyan.opacity(0.24) : .clear
    }
}

struct MirrorLightProgressView: View {
    let campaign: NarrativeCampaign

    private let stages: [(game: NarrativeMiniGame, title: String, subtitle: String, symbol: String)] = [
        (.trace, "草稿灯", "把线接回去", "pencil.line"),
        (.melody, "旋律灯", "接住四拍", "music.note"),
        (.erase, "擦痕灯", "擦掉标签", "eraser.fill")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "lightbulb.2.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.yellow.opacity(0.9))
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text("镜像三灯")
                        .font(.system(size: 13, weight: .bold))
                    Text(summaryText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                }
                Spacer()
                Text("\(completedCount)/3")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.68))
            }

            HStack(spacing: 8) {
                ForEach(Array(stages.enumerated()), id: \.offset) { index, stage in
                    lightStage(stage, index: index)
                    if index < stages.count - 1 {
                        Capsule()
                            .fill(index < completedCount ? Color.yellow.opacity(0.68) : Color.white.opacity(0.14))
                            .frame(width: 30, height: 4)
                    }
                }
            }

            if navigationCue.isActive {
                navigationCueRow(navigationCue)
            }
        }
        .padding(13)
        .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(.yellow.opacity(0.18), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("镜像三灯，\(summaryText)，已点亮 \(completedCount) 盏")
    }

    private func lightStage(_ stage: (game: NarrativeMiniGame, title: String, subtitle: String, symbol: String), index: Int) -> some View {
        let status = status(for: stage.game, index: index)
        return VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(status.fill)
                    .frame(width: 46, height: 46)
                    .shadow(color: status.glow, radius: status.isActive || status.isComplete ? 12 : 0, x: 0, y: 0)
                Image(systemName: status.symbolOverride ?? stage.symbol)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(status.icon)
            }
            .overlay(Circle().stroke(status.stroke, lineWidth: 1))

            Text(stage.title)
                .font(.system(size: 10, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(status.caption.isEmpty ? stage.subtitle : status.caption)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(.white.opacity(status.isUpcoming ? 0.42 : 0.66))
                .lineLimit(1)
                .minimumScaleFactor(0.74)
        }
        .frame(width: 70)
    }

    private func navigationCueRow(_ cue: MirrorLightNavigationCue) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: cue.distance <= 1.15 ? "checkmark.circle.fill" : "location.north.line.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(cue.distance <= 1.15 ? .green.opacity(0.92) : .cyan.opacity(0.86))
                    .frame(width: 16)
                Text(cue.title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.88))
                Spacer()
                Text(String(format: "%.1fm", cue.distance))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.58))
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule()
                        .fill(LinearGradient(colors: [.cyan.opacity(0.78), .yellow.opacity(0.72)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, proxy.size.width * cue.progressToRange))
                }
            }
            .frame(height: 5)
            Text(cue.detail)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.58))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(9)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(.cyan.opacity(0.16), lineWidth: 1))
    }

    private var completedCount: Int {
        stages.enumerated().filter { index, stage in
            status(for: stage.game, index: index).isComplete
        }.count
    }

    private var navigationCue: MirrorLightNavigationCue {
        MirrorLightNavigationCue.derive(from: campaign)
    }

    private var summaryText: String {
        if campaign.mirrorDissolveProgress >= 1 {
            return "三盏灯都亮了，镜面停下来。"
        }
        if campaign.mirrorDissolveProgress > 0 {
            return "三盏灯都亮了，镜面正在褪色。"
        }
        if let current = campaign.currentMoment.miniGame {
            let required = current.requiredInteractions
            return "\(title(for: current)) \(min(campaign.miniGameProgress, required)) / \(required)"
        }
        return "先靠近镜面，再逐盏点亮。"
    }

    private func status(for game: NarrativeMiniGame, index: Int) -> LightStageStatus {
        let momentIndex = 1 + index
        let isPast = campaign.chapter.rawValue > NarrativeChapter.mirror.rawValue
            || campaign.isComplete
            || campaign.momentIndex > momentIndex
        let isCurrent = campaign.chapter == .mirror && campaign.currentMoment.miniGame == game
        let isComplete = isPast || (isCurrent && campaign.miniGameCompleted)
        let isActive = isCurrent && campaign.miniGameCompleted == false

        if isComplete {
            return LightStageStatus(
                fill: Color.yellow.opacity(0.82),
                stroke: Color.white.opacity(0.58),
                icon: Color.black.opacity(0.86),
                glow: Color.yellow.opacity(0.34),
                caption: "已点亮",
                symbolOverride: "checkmark",
                isComplete: true,
                isActive: false,
                isUpcoming: false
            )
        }
        if isActive {
            return LightStageStatus(
                fill: Color.cyan.opacity(0.32),
                stroke: Color.cyan.opacity(0.62),
                icon: Color.white.opacity(0.92),
                glow: Color.cyan.opacity(0.28),
                caption: "进行中",
                symbolOverride: nil,
                isComplete: false,
                isActive: true,
                isUpcoming: false
            )
        }
        return LightStageStatus(
            fill: Color.white.opacity(0.09),
            stroke: Color.white.opacity(0.16),
            icon: Color.white.opacity(0.42),
            glow: .clear,
            caption: "",
            symbolOverride: nil,
            isComplete: false,
            isActive: false,
            isUpcoming: true
        )
    }

    private func title(for game: NarrativeMiniGame) -> String {
        stages.first { $0.game == game }?.title ?? game.rawValue
    }

    private struct LightStageStatus {
        let fill: Color
        let stroke: Color
        let icon: Color
        let glow: Color
        let caption: String
        let symbolOverride: String?
        let isComplete: Bool
        let isActive: Bool
        let isUpcoming: Bool
    }
}

private struct MelodyPadStyle: ButtonStyle {
    let tint: Color
    let isLit: Bool
    let isNext: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(isLit ? tint.opacity(0.82) : (isNext ? .cyan.opacity(0.24) : .white.opacity(configuration.isPressed ? 0.24 : 0.12)), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(isNext ? .cyan.opacity(0.72) : .white.opacity(isLit ? 0.62 : 0.18), lineWidth: isNext ? 1.4 : 1))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct EraseWordStyle: ButtonStyle {
    let isErased: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white.opacity(isErased ? 0.25 : 0.9))
            .background(.white.opacity(configuration.isPressed ? 0.18 : 0.10), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.13), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 420
        var cursor = CGPoint.zero
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if cursor.x > 0, cursor.x + size.width > width {
                cursor.x = 0
                cursor.y += rowHeight + spacing
                rowHeight = 0
            }
            cursor.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: cursor.y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var cursor = bounds.origin
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if cursor.x > bounds.minX, cursor.x + size.width > bounds.maxX {
                cursor.x = bounds.minX
                cursor.y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: cursor, proposal: ProposedViewSize(size))
            cursor.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }

    func distance(toSegmentFrom start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return distance(to: start) }
        let projection = (((x - start.x) * dx) + ((y - start.y) * dy)) / lengthSquared
        let clampedProjection = min(1, max(0, projection))
        let nearest = CGPoint(x: start.x + clampedProjection * dx, y: start.y + clampedProjection * dy)
        return distance(to: nearest)
    }
}

private extension View {
    func narrativeGlassPanel(cornerRadius: CGFloat, tint: Color) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.black.opacity(0.54))
        )
        .background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(tint)
        )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            )
    }
}
