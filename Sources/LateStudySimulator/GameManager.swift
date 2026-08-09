import AppKit
import Combine
import Foundation
import SceneKit

private struct FreeRoamRect {
    let minX: Double
    let maxX: Double
    let minZ: Double
    let maxZ: Double

    func contains(x: Double, z: Double, radius: Double = 0) -> Bool {
        x >= minX + radius && x <= maxX - radius && z >= minZ + radius && z <= maxZ - radius
    }

    func intersectsCircle(x: Double, z: Double, radius: Double) -> Bool {
        let nearestX = x.clamped(to: minX...maxX)
        let nearestZ = z.clamped(to: minZ...maxZ)
        let dx = x - nearestX
        let dz = z - nearestZ
        return dx * dx + dz * dz < radius * radius
    }
}

struct PlaytestRouteTranscriptEntry: Identifiable, Equatable {
    let id: Int
    let step: Int
    let actor: String
    let input: String
    let beforeState: String
    let afterState: String
    let friction: String
    let feedback: String

    var hasFriction: Bool {
        friction != "无明显摩擦"
    }

    var hasSensoryPeerFeedback: Bool {
        feedback.contains("同学声场")
    }

    var hasChoiceImpactFeedback: Bool {
        feedback.contains("选择回响")
    }

    var hasSpatialNavigationFeedback: Bool {
        feedback.contains("空间导航")
    }

    var hasCompanionNavigationFeedback: Bool {
        feedback.contains("同伴低语")
    }

    var feedbackSegments: [String] {
        feedback
            .split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }

    var sensoryPeerFeedback: String? {
        feedbackSegments.first { $0.hasPrefix("同学声场") }
    }

    var choiceImpactFeedback: String? {
        feedbackSegments.first { $0.hasPrefix("选择回响") }
    }

    var spatialNavigationFeedback: String? {
        feedbackSegments.first { $0.hasPrefix("空间导航") }
    }

    var companionNavigationFeedback: String? {
        feedbackSegments.first { $0.hasPrefix("同伴低语") }
    }

    var supportingFeedback: String? {
        feedbackSegments.first {
            $0.hasPrefix("同学声场") == false
                && $0.hasPrefix("选择回响") == false
                && $0.hasPrefix("空间导航") == false
                && $0.hasPrefix("同伴低语") == false
        }
    }
}

@MainActor
final class GameManager: ObservableObject {
    @Published var gameState: GameState = .menu
    @Published var currentTurn: Int = 0
    @Published var maxTurns: Int = 18
    @Published var settings = InstitutionSettings()
    @Published var selectedRole: PlayableRole = .regularStudent
    @Published var activeRole: PlayableRole = .regularStudent
    @Published var currentPhase: TurnPhase = .observation
    @Published var player = PlayerState()
    @Published var teacher = TeacherState()
    @Published var cameraPose: CameraPose = .forward
    @Published var studentLookYaw: Double = 0
    @Published var studentLookPitch: Double = 0
    @Published var mouseLookCaptured: Bool = false
    @Published var mouseLookEnabled: Bool = true
    @Published var freeRoam = StudentFreeRoamState()
    @Published var isReturningToSeat: Bool = false
    @Published var returnToSeatStartedAt: Date = .distantPast
    @Published var frontDoorOpen: Bool = false
    @Published var rearDoorOpen: Bool = false
    @Published var playerLockerOpen: Bool = false
    @Published var viewMode: ViewMode = .student
    @Published var selectedTeacherTargetID: Int?
    @Published var message: String = "晚自习开始。教室里的笔尖声和风扇声混在一起。"
    @Published var classmates: [Classmate] = []
    @Published var eventLog: [EventLogEntry] = []
    @Published var audioCues: [AudioCue] = []
    @Published private(set) var directionalSubtitleEvents: [DirectionalSubtitleEvent] = []
    @Published private(set) var sensoryPeerCue: SensoryPeerCue?
    @Published var replay: [TurnSnapshot] = []
    @Published var selectedReplayIndex: Int = 0
    @Published var peripheralLeft: Double = 0
    @Published var peripheralRight: Double = 0.25
    @Published var classroomLightLevel: Double = 1.0
    @Published var triggeredPeriods: Set<StudyPeriod> = []
    @Published var leaveSeatUsedPeriods: Set<StudyPeriod> = []
    @Published var monologues: [InnerMonologue] = []
    @Published var featuredMonologue: FeaturedMonologue?
    @Published var activeChapter: StoryChapter = .silentClassroom
    @Published var chapterOneStep: ChapterOneStep = .observeLinChe
    @Published var chapterClues: [ChapterClue] = []
    @Published private(set) var chapterOneLocatedAudioSteps: Set<ChapterOneStep> = []
    @Published private(set) var chapterOneDwellFocus = DwellFocusState()
    @Published private(set) var focusFeedbackTrigger: DwellFocusFeedback?
    @Published private(set) var seatedPosePressureFeedback: SeatedPosePressureFeedback?
    @Published private(set) var teacherPatrolReadout: TeacherPatrolReadout?
    @Published private(set) var chapterOneLinCheDialogueCue: ChapterOneLinCheDialogueCue?
    @Published private(set) var chapterOneNoteDropCue: ChapterOneNoteDropCue?
    @Published private(set) var linChePerformanceCue: LinChePerformanceCue = .initial
    @Published var hasPresentedChapterOneDecision: Bool = false
    @Published var chapterOneDecision: String = ""
    @Published var hasTriggeredLoneliness: Bool = false
    @Published var hasTriggeredPhoneNotification: Bool = false
    @Published var hasTriggeredBroadcast: Bool = false
    @Published var hasTriggeredKnockOnDoor: Bool = false
    @Published var hasTriggeredPlayerBreakdown: Bool = false
    @Published var hasTriggeredClassmateHelpRequest: Bool = false
    @Published var hasTriggeredClassmateReport: Bool = false
    @Published var hasTriggeredMemoryTrust: Bool = false
    @Published var hasTriggeredMemorySuspicion: Bool = false
    @Published private(set) var activeBreakdownRecoverySteps: [BreakdownRecoveryStep] = []
    @Published private(set) var completedBreakdownRecoverySteps: Set<BreakdownRecoveryStep> = []
    @Published private(set) var breakdownRecoverySummary = ""

    var chapterOneLinCheTrust: ChapterOneLinCheTrust {
        chapterOneLinCheDialogueCue?.trust ?? .neutral
    }

    var chapterOneLinCheListenScore: Int {
        chapterOneLinCheDialogueCue?.listenScore ?? 0
    }
    @Published var classmateMemory: [Int: ClassmateMemory] = [:]
    @Published var audioAssetStatus: AudioAssetStatus
    @Published var isPrologueActive = false
    @Published var prologueState = PrologueState()
    @Published var prologueBeatElapsed: TimeInterval = 0
    @Published var prologueLookExplorationElapsed: TimeInterval = 0
    @Published var prologueActionReady = false
    @Published var prologueSeatNearby = false
    @Published var isPrologueTutorialPresented = false
    @Published var isChapterOneTransitionPresented = false
    @Published private(set) var prologuePauseReasons: Set<ProloguePauseReason> = []
    @Published var accessibilityPreferences = AccessibilityPreferences()
    @Published var isAccessibilityPanelPresented = false
    @Published var prologuePerformancePhase = 0
    @Published var isGameGuidePresented = false
    @Published var menuGuideCountdown = 5
    @Published var gameGuideExitCountdown = 0
    @Published private(set) var hasCompletedInitialGameGuide = false
    @Published var narrativeCampaign = NarrativeCampaign()
    private(set) var narrativeBoundaryDwellSeconds = 0.0
    private(set) var narrativeBoundaryPullbackCount = 0
    private(set) var narrativeMomentElapsedSeconds = 0.0
    @Published private(set) var narrativeGuidanceCue: NarrativeGuidanceCue?
    @Published private(set) var narrativePauseReasons: Set<NarrativePauseReason> = []
    @Published private(set) var activeNarrativeMicroGame: NarrativeMiniGame?
    @Published private(set) var lastNarrativeMicroGameFeedback: MirrorMicroGameInputFeedbackModel?
    @Published private(set) var isFullNarrativeRun = false
    @Published var isDeveloperPanelPresented = false
    @Published private(set) var developerPlaytestStatus = "尚未运行"
    @Published private(set) var developerPlaytestLog: [String] = []
    @Published private(set) var playtestRouteTranscript: [PlaytestRouteTranscriptEntry] = []
    @Published private(set) var isAutonomousPlayEnabled = false
    @Published private(set) var autonomousPlayStatus = "待命"
    @Published private(set) var autonomousPlayLastDecision = "尚未接管"
    @Published private(set) var autonomousPlayStepCount = 0
    @Published private(set) var narrativeKeyboardFocusIndex = 0
    @Published private(set) var narrativeKeyboardStatus = "键盘目标待命"
    @Published private(set) var scenePresentation = ScenePresentationState()
    @Published private(set) var narrativeSaveRecoveryNotice: String?
    @Published private(set) var teacherTruthRunSummary = "教师真相二周目尚未解锁"
    @Published private(set) var isTeacherTruthRunActive = false
    @Published private(set) var teacherTruthRunCompleted = false
    @Published private(set) var completedTeacherTruthObjectiveIDs: Set<String> = []

    var prologuePaused: Bool { prologuePauseReasons.isEmpty == false }
    var narrativePaused: Bool { narrativePauseReasons.isEmpty == false }
    var shouldShowNarrativePauseOverlay: Bool {
        narrativePauseReasons.subtracting([.microGame]).isEmpty == false
    }
    var shouldUseMinimalNarrativeHUD: Bool {
        isFullNarrativeRun && narrativeCampaign.isActive == false && scenePresentation.isActive
    }
    var isBreakdownRecoveryActive: Bool {
        activeBreakdownRecoverySteps.isEmpty == false && completedBreakdownRecoverySteps.count < activeBreakdownRecoverySteps.count
    }

    var currentBreakdownRecoveryStep: BreakdownRecoveryStep? {
        activeBreakdownRecoverySteps.first { completedBreakdownRecoverySteps.contains($0) == false }
    }
    var teacherTruthObjectives: [TeacherTruthObjective] {
        [
            TeacherTruthObjective(
                id: "truth.scan",
                title: "先看全班",
                detail: "理解秩序压力，不急着锁定一个学生。",
                action: .scanClass,
                symbol: "rectangle.3.group.fill",
                isComplete: completedTeacherTruthObjectiveIDs.contains("truth.scan")
            ),
            TeacherTruthObjective(
                id: "truth.observe",
                title: "观察目标",
                detail: "把表面异常和隐藏原因分开。",
                action: .observeTarget,
                symbol: "eye.fill",
                isComplete: completedTeacherTruthObjectiveIDs.contains("truth.observe")
            ),
            TeacherTruthObjective(
                id: "truth.care",
                title: "低声关心",
                detail: "用不公开审判的方式确认学生状态。",
                action: .care,
                symbol: "heart.text.square.fill",
                isComplete: completedTeacherTruthObjectiveIDs.contains("truth.care")
            ),
            TeacherTruthObjective(
                id: "truth.release",
                title: "给出出口",
                detail: "允许短暂离开，把支持变成实际安排。",
                action: .allowBreak,
                symbol: "figure.walk",
                isComplete: completedTeacherTruthObjectiveIDs.contains("truth.release")
            )
        ]
    }
    var currentTeacherTruthObjective: TeacherTruthObjective? {
        teacherTruthObjectives.first { $0.isComplete == false }
    }

    let audio = SpatialAudioManager()
    private let storage: UserDefaults
    private let shouldStartAudioEngine = NSClassFromString("XCTestCase") == nil
    private let memoryStoreKey = "LateStudySimulator.ClassmateMemory.v1"
    private let prologueStoreKey = "LateStudySimulator.Prologue.v1"
    private let accessibilityStoreKey = "LateStudySimulator.Accessibility.v1"
    private lazy var supportResourceCatalog = SupportResourceCatalog.bundledOrFallback()
    private lazy var supportResourceValidation: SupportResourceCatalog.Validation = {
        #if DEBUG
        let validation = supportResourceCatalog.validate(buildPolicy: .debug)
        if validation.hasExpiredResources {
            NSLog("SupportResourceCatalog has expired entries: \(validation.expiredResources.map(\.displayName).joined(separator: ", "))")
        }
        return validation
        #else
        let validation = supportResourceCatalog.validate(buildPolicy: .release)
        precondition(validation.allowsReleaseBuild, "SupportResourceCatalog requires review")
        return validation
        #endif
    }()
    private var prologueTimer: Timer?
    private var menuGuideTimer: Timer?
    private var gameGuideExitTimer: Timer?
    private var prologueDwell: TimeInterval = 0
    private var freeRoamTimer: Timer?
    private var freeRoamPausedAt: Date?
    private var returnToSeatTask: Task<Void, Never>?
    private var pendingSprintHunger: Double = 0
    private var lastAnomalyMonologueTurn: [String: Int] = [:]
    private var monologueDismissTask: Task<Void, Never>?
    private var focusFeedbackClearTask: Task<Void, Never>?
    private var developerAutoplayTask: Task<Void, Never>?
    private var autonomousPlayTask: Task<Void, Never>?
    private var pendingPlaytestChoiceImpactFeedback: String?
    private var lastCompanionNavigationWhisperAudioKey = ""
    private var lastSensoryPeerCueSignature = ""
    private var lastSeatedPosePressureCueSignature = ""
    private var lastTeacherPatrolReadoutCueSignature = ""
    private var completedChapterOneBeatIDs: Set<String> = []
    private var scenePresentationTask: Task<Void, Never>?
    private var narrativeSaveRevision = 0
    private var developerExploredChapters: Set<NarrativeChapter> = []
    private var timedNarrativeMomentID = ""
    private let normalFreeRoamPlayerRadius = 0.19
    private let sidewaysFreeRoamPlayerRadius = 0.115
    private let scenePresentationPrepareDuration: Duration = .milliseconds(760)
    private let scenePresentationCommitDuration: Duration = .milliseconds(860)
    private let scenePresentationCleanupDuration: Duration = .milliseconds(660)
    static let returnToSeatResetDelay: TimeInterval = 1.08
    static let returnToSeatTotalDuration: TimeInterval = 1.8

    init(userDefaults storage: UserDefaults = .standard) {
        self.storage = storage
        audioAssetStatus = audio.assetStatus
        classmateMemory = loadClassmateMemory()
        loadPrologueProgress()
        let narrativeLoad = loadNarrativeSave()
        accessibilityPreferences = narrativeLoad.accessibilityPreferences
        audio.setVolumes(
            dialogue: accessibilityPreferences.dialogueVolume,
            ambience: accessibilityPreferences.ambienceVolume,
            cues: accessibilityPreferences.cueVolume
        )
        narrativeCampaign = narrativeLoad.campaign
        activeNarrativeMicroGame = nil
        scenePresentation = narrativeLoad.scenePresentation
        narrativeSaveRevision = narrativeLoad.revision
        narrativeSaveRecoveryNotice = narrativeLoad.notice
        if let chapterOneProgress = narrativeLoad.chapterOneProgress {
            restoreChapterOneProgress(chapterOneProgress)
        }
        let arguments = ProcessInfo.processInfo.arguments
        isDeveloperPanelPresented = arguments.contains("--developer-tools")
        if arguments.contains("--autoplay-campaign") {
            hasCompletedInitialGameGuide = true
            DispatchQueue.main.async { [weak self] in
                self?.mouseLookEnabled = false
                self?.startDeveloperAutoplay()
            }
        } else if arguments.contains("--narrative-demo") {
            hasCompletedInitialGameGuide = true
            DispatchQueue.main.async { [weak self] in
                self?.startFullNarrativeCampaign()
                self?.mouseLookEnabled = false
            }
        } else {
            restoreNarrativeSessionIfNeeded()
        }
        if narrativeLoad.needsMigrationWrite {
            saveNarrativeCampaign()
        }
        _ = supportResourceValidation
    }

    func startExperience(forcePrologue: Bool = false) {
        if forcePrologue || prologueState.prologueCompleted == false {
            // Entering from the menu is an authored replay, so always include the
            // exterior arrival instead of silently resuming inside the building.
            startPrologue(resume: false)
        } else {
            startFullNarrativeCampaign()
        }
    }

    var isMenuEntryLocked: Bool { hasCompletedInitialGameGuide == false }

    func beginInitialGameGuideIfNeeded() {
        guard hasCompletedInitialGameGuide == false,
              isGameGuidePresented == false,
              menuGuideTimer == nil else { return }
        guard case .menu = gameState else {
            hasCompletedInitialGameGuide = true
            return
        }
        menuGuideCountdown = 0
        presentGameGuide(isInitialPresentation: true)
    }

    func advanceMenuGuideCountdown() {
        guard hasCompletedInitialGameGuide == false, isGameGuidePresented == false else { return }
        menuGuideCountdown = max(0, menuGuideCountdown - 1)
        if menuGuideCountdown == 0 {
            menuGuideTimer?.invalidate()
            menuGuideTimer = nil
            presentGameGuide(isInitialPresentation: true)
        }
    }

    func presentGameGuide(isInitialPresentation: Bool = false) {
        isGameGuidePresented = true
        gameGuideExitTimer?.invalidate()
        gameGuideExitTimer = nil
        gameGuideExitCountdown = 0
        guard gameGuideExitCountdown > 0 else { return }
        gameGuideExitTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.advanceGameGuideExitCountdown() }
        }
    }

    func advanceGameGuideExitCountdown() {
        gameGuideExitCountdown = max(0, gameGuideExitCountdown - 1)
        if gameGuideExitCountdown == 0 {
            gameGuideExitTimer?.invalidate()
            gameGuideExitTimer = nil
        }
    }

    func dismissGameGuide() {
        guard isGameGuidePresented, gameGuideExitCountdown == 0 else { return }
        isGameGuidePresented = false
        hasCompletedInitialGameGuide = true
    }

    func startPrologue(resume: Bool = false) {
        startGame()
        isPrologueActive = true
        currentTurn = 0
        chapterClues = []
        chapterOneLocatedAudioSteps = []
        chapterOneDwellFocus = DwellFocusState()
        clearFocusFeedback()
        featuredMonologue = nil
        monologues = []
        gameState = .playing
        player.posture = .standing
        freeRoam = StudentFreeRoamState()
        prologuePauseReasons = []
        isPrologueTutorialPresented = false
        isChapterOneTransitionPresented = false
        isAccessibilityPanelPresented = false
        if resume == false || prologueState.prologueCompleted {
            prologueState = PrologueState()
        }
        beginPrologueBeat(prologueState.currentBeat)
        startPrologueTimer()
    }

    func startGame() {
        clearScenePresentation()
        isFullNarrativeRun = false
        narrativeCampaign.isActive = false
        isTeacherTruthRunActive = false
        teacherTruthRunCompleted = false
        completedTeacherTruthObjectiveIDs = []
        stopPrologueTimer()
        isPrologueActive = false
        prologuePauseReasons = []
        narrativePauseReasons = []
        activeNarrativeMicroGame = nil
        currentTurn = 1
        maxTurns = settings.maxTurns
        activeChapter = .silentClassroom
        chapterOneStep = .observeLinChe
        currentPhase = .observation
        selectedRole = .regularStudent
        activeRole = .regularStudent
        player = PlayerState()
        configurePlayerForSelectedRole()
        teacher = makeTeacherState(for: activeRole)
        cameraPose = .forward
        studentLookYaw = 0
        studentLookPitch = 0
        mouseLookEnabled = true
        mouseLookCaptured = false
        returnToSeatTask?.cancel()
        returnToSeatTask = nil
        isReturningToSeat = false
        returnToSeatStartedAt = .distantPast
        pendingSprintHunger = 0
        freeRoamTimer?.invalidate()
        freeRoamTimer = nil
        freeRoamPausedAt = nil
        freeRoam = StudentFreeRoamState()
        frontDoorOpen = false
        rearDoorOpen = false
        playerLockerOpen = false
        viewMode = activeRole.isTeacher ? .teacher : .student
        classmates = makeClassmates()
        selectedTeacherTargetID = classmates.max { lhs, rhs in lhs.stress < rhs.stress }?.id
        teacher.classRisk = estimatedClassRisk
        eventLog = []
        audioCues = []
        directionalSubtitleEvents = []
        sensoryPeerCue = nil
        lastSensoryPeerCueSignature = ""
        seatedPosePressureFeedback = nil
        lastSeatedPosePressureCueSignature = ""
        teacherPatrolReadout = nil
        lastTeacherPatrolReadoutCueSignature = ""
        chapterOneLinCheDialogueCue = nil
        chapterOneNoteDropCue = nil
        linChePerformanceCue = .initial
        completedChapterOneBeatIDs = []
        replay = []
        selectedReplayIndex = 0
        pendingPlaytestChoiceImpactFeedback = nil
        lastCompanionNavigationWhisperAudioKey = ""
        classroomLightLevel = 1.0
        triggeredPeriods = []
        leaveSeatUsedPeriods = []
        monologues = []
        featuredMonologue = nil
        monologueDismissTask?.cancel()
        chapterClues = []
        chapterOneLocatedAudioSteps = []
        chapterOneDwellFocus = DwellFocusState(activePose: cameraPose)
        clearFocusFeedback()
        chapterOneStep = .observeLinChe
        hasPresentedChapterOneDecision = false
        chapterOneDecision = ""
        lastAnomalyMonologueTurn = [:]
        hasTriggeredLoneliness = false
        hasTriggeredPhoneNotification = false
        hasTriggeredBroadcast = false
        hasTriggeredKnockOnDoor = false
        hasTriggeredPlayerBreakdown = false
        hasTriggeredClassmateHelpRequest = false
        hasTriggeredClassmateReport = false
        hasTriggeredMemoryTrust = false
        hasTriggeredMemorySuspicion = false
        activeBreakdownRecoverySteps = []
        completedBreakdownRecoverySteps = []
        breakdownRecoverySummary = ""
        gameState = .playing
        let memoryText = classmateMemory.isEmpty ? "" : " 有 \(classmateMemory.count) 个同学还带着上一晚的关系余波。"
        message = chapterOpeningMessage(memoryText: memoryText)
        addMonologue(chapterOpeningMonologue, intensity: 0.56)
        if shouldStartAudioEngine { audio.start() }
        transitionAudioScene(to: .classroom)
        updatePerception()
    }

    var currentSpatialAudioObjective: SpatialAudioObjective? {
        guard activeChapter == .silentClassroom,
              activeRole.isTeacher == false,
              hasPresentedChapterOneDecision == false else { return nil }
        return SpatialAudioObjective.chapterOne(
            step: chapterOneStep,
            isLocated: chapterOneLocatedAudioSteps.contains(chapterOneStep),
            focusProgress: chapterOneDwellFocus.progress(for: cameraPose)
        )
    }

    func startFullNarrativeCampaign() {
        startGame()
        narrativeCampaign.start()
        isFullNarrativeRun = false
        activeNarrativeMicroGame = nil
        narrativeBoundaryDwellSeconds = 0
        narrativeBoundaryPullbackCount = 0
        narrativeMomentElapsedSeconds = 0
        timedNarrativeMomentID = ""
        activeRole = .regularStudent
        viewMode = .student
        player.posture = .seated
        mouseLookEnabled = false
        message = narrativeCampaign.currentMoment.goal
        transitionAudioScene(to: .classroom)
        saveNarrativeCampaign()
        presentScenePresentation(for: .classroom, subtitle: activeChapter.objective)
    }

    func startTeacherTruthRunFromEpilogue() {
        guard narrativeCampaign.isComplete else { return }

        let completedCampaign = narrativeCampaign
        let reveals = completedCampaign.truthReplayReveals
        let revealStrength = reveals.isEmpty
            ? 0.5
            : reveals.map(\.revealStrength).reduce(0, +) / Double(reveals.count)
        let routeText = completedCampaign.safetyHandoffState?.route?.displayName
            ?? (completedCampaign.safetyRoute.isEmpty ? "咨询室支持" : completedCampaign.safetyRoute)
        let companionText = completedCampaign.companionID.isEmpty ? "没有稳定同伴" : completedCampaign.companionID

        startGame()
        selectedRole = .homeroomTeacher
        activeRole = .homeroomTeacher
        isTeacherTruthRunActive = true
        teacherTruthRunCompleted = false
        completedTeacherTruthObjectiveIDs = []
        maxTurns = 8
        configurePlayerForSelectedRole()
        teacher = makeTeacherState(for: .homeroomTeacher)
        teacher.empathy = min(100, 46 + revealStrength * 42 + (completedCampaign.sharedSelf ? 6 : 0))
        teacher.studentTrust = min(100, 34 + Double(completedCampaign.clueCount) * 5 + (completedCampaign.privacyProtected ? 8 : 0))
        teacher.counselingCapacity = min(100, 28 + (completedCampaign.safetyHandoffState?.safetyHandoffComplete == true ? 22 : 0))
        teacher.misreadRisk = max(8, 48 - revealStrength * 26)
        teacher.classRisk = estimatedClassRisk
        viewMode = .teacher
        isFullNarrativeRun = false
        narrativeCampaign.isActive = false
        narrativeCampaign.isComplete = false
        selectedTeacherTargetID = highestRiskClassmate?.id ?? classmates.first?.id
        teacherTruthRunSummary = "真相二周目：\(companionText) · \(routeText) · 揭示 \(Int(revealStrength * 100))"
        message = "教师真相二周目开始。现在你站在讲台和过道之间，看见同一晚的表面秩序，也带着苏念线留下的隐藏真相。"
        addMonologue("原来很多“异常动作”不是反抗，而是在压力里发出的低声求救。", intensity: 0.74)
        updatePerception()
    }

    func advanceNarrative(_ choiceID: String) {
        guard narrativePaused == false,
              narrativeCampaign.isActive,
              narrativeCampaign.isComplete == false else { return }
        guard narrativeCampaign.explorationReady else {
            message = "先在这个空间里找到一个值得停下来的位置。"
            return
        }
        guard narrativeCampaign.currentMomentActionReady else {
            message = narrativeCampaign.currentMomentActionPrompt ?? "先确认当前空间里的关键位置。"
            return
        }
        let beforeChapter = narrativeCampaign.chapter
        applyNarrativeChoice(choiceID)
        if narrativeCampaign.isComplete {
            clearScenePresentation()
        } else if narrativeCampaign.chapter != beforeChapter {
            presentScenePresentation(for: narrativeCampaign.chapter)
        }
        syncNarrativeAudioDynamics()
        message = narrativeCampaign.isComplete
            ? "你走过了这一晚。支持没有结束，只是从一个人变成了更多人。"
            : narrativeCampaign.currentMoment.goal
        saveNarrativeCampaign()
    }

    private func applyNarrativeChoice(_ choiceID: String) {
        let beforeImpactID = narrativeCampaign.lastChoiceImpact?.id
        narrativeCampaign.choose(choiceID)
        publishMirrorDialogueConsequenceIfNeeded(choiceID: choiceID)
        guard let impact = narrativeCampaign.activeChoiceImpact,
              impact.id != beforeImpactID else { return }
        audio.playNarrativeImpact(impact, chapter: narrativeCampaign.chapter)
        if let impactEvent = audio.lastNarrativeImpactAudioEvent {
            pendingPlaytestChoiceImpactFeedback = playtestChoiceImpactFeedback(for: impactEvent)
        }
    }

    private func publishMirrorDialogueConsequenceIfNeeded(choiceID: String) {
        let consequence = MirrorDialogueConsequenceModel.derive(from: narrativeCampaign)
        guard consequence.isActive,
              consequence.choiceID == choiceID else { return }
        developerPlaytestLog.append("MIRROR_DIALOGUE \(choiceID) \(consequence.trustDeltaText) total=\(narrativeCampaign.linCheTrust) bias=\(consequence.supportBiasText)")
        addAudioCue(.whisper, direction: "林澈回应", intensity: choiceID == "invite" ? 0.46 : 0.38, note: consequence.detail)
    }

    func progressNarrativeMiniGame() {
        guard narrativeCanAcceptMicroGameInput,
              narrativeCampaign.isActive,
              narrativeCampaign.isComplete == false else { return }
        guard let miniGame = narrativeCampaign.currentMoment.miniGame else { return }
        let beforeProgress = narrativeCampaign.miniGameProgress
        let beforeTouchedSlots = narrativeCampaign.miniGameTouchedSlots
        let beforeHintCount = narrativeCampaign.miniGameHintCount
        narrativeCampaign.progressMiniGame()
        publishNarrativeMicroGameInputFeedback(
            miniGame: miniGame,
            slot: beforeProgress,
            beforeProgress: beforeProgress,
            beforeTouchedSlots: beforeTouchedSlots,
            beforeHintCount: beforeHintCount
        )
        closeNarrativeMicroGameIfComplete()
        saveNarrativeCampaign()
    }

    func completeNarrativeMiniGameAccessibly() {
        guard narrativeCanAcceptMicroGameInput,
              narrativeCampaign.isActive,
              narrativeCampaign.isComplete == false else { return }
        guard let miniGame = narrativeCampaign.currentMoment.miniGame else { return }
        narrativeCampaign.completeMiniGameAccessibly()
        lastNarrativeMicroGameFeedback = MirrorMicroGameInputFeedbackModel.accessibleCompletion(from: narrativeCampaign, miniGame: miniGame)
        developerPlaytestLog.append("MICRO_INPUT \(miniGame.rawValue) accessible progress=\(narrativeCampaign.miniGameProgress)/\(miniGame.requiredInteractions)")
        closeNarrativeMicroGameIfComplete()
        saveNarrativeCampaign()
    }

    func performNarrativeMiniGameAction(_ slot: Int) {
        guard narrativeCanAcceptMicroGameInput,
              narrativeCampaign.isActive,
              narrativeCampaign.isComplete == false else { return }
        let beforeProgress = narrativeCampaign.miniGameProgress
        let beforeTouchedSlots = narrativeCampaign.miniGameTouchedSlots
        let beforeHintCount = narrativeCampaign.miniGameHintCount
        let beforeCompleted = narrativeCampaign.miniGameCompleted
        narrativeCampaign.performMiniGameAction(slot)
        if let miniGame = narrativeCampaign.currentMoment.miniGame {
            publishNarrativeMicroGameInputFeedback(
                miniGame: miniGame,
                slot: slot,
                beforeProgress: beforeProgress,
                beforeTouchedSlots: beforeTouchedSlots,
                beforeHintCount: beforeHintCount
            )
        }
        publishNarrativeMicroGameStepCueIfNeeded(
            slot: slot,
            beforeProgress: beforeProgress,
            beforeTouchedSlots: beforeTouchedSlots,
            beforeCompleted: beforeCompleted
        )
        closeNarrativeMicroGameIfComplete()
        saveNarrativeCampaign()
    }

    func recordNarrativeMicroGameRecoveryAttempt(slot: Int = -1) {
        guard narrativeCanAcceptMicroGameInput,
              narrativeCampaign.isActive,
              narrativeCampaign.isComplete == false,
              let miniGame = narrativeCampaign.currentMoment.miniGame,
              narrativeCampaign.miniGameCompleted == false else { return }
        publishNarrativeMicroGameInputFeedback(
            miniGame: miniGame,
            slot: slot,
            beforeProgress: narrativeCampaign.miniGameProgress,
            beforeTouchedSlots: narrativeCampaign.miniGameTouchedSlots,
            beforeHintCount: narrativeCampaign.miniGameHintCount
        )
        saveNarrativeCampaign()
    }

    func replayNarrativeMiniGameCue() {
        guard narrativeCanAcceptMicroGameInput,
              narrativeCampaign.isActive,
              narrativeCampaign.currentMoment.miniGame == .melody,
              narrativeCampaign.miniGameCompleted == false else { return }
        let beforeProgress = narrativeCampaign.miniGameProgress
        let beforeTouchedSlots = narrativeCampaign.miniGameTouchedSlots
        let beforeHintCount = narrativeCampaign.miniGameHintCount
        narrativeCampaign.replayMiniGameCue()
        publishNarrativeMicroGameInputFeedback(
            miniGame: .melody,
            slot: -1,
            beforeProgress: beforeProgress,
            beforeTouchedSlots: beforeTouchedSlots,
            beforeHintCount: beforeHintCount
        )
        publishNarrativeMelodyPlaybackCue(reason: "replay")
        closeNarrativeMicroGameIfComplete()
        if narrativeCampaign.miniGameCompleted == false {
            message = "旋律重新响了一遍。听不清也没关系，提示会慢慢接住你。"
        }
        saveNarrativeCampaign()
    }

    var narrativeCanAcceptMicroGameInput: Bool {
        narrativePauseReasons.subtracting([.microGame]).isEmpty
    }

    func presentNarrativeMicroGame(_ miniGame: NarrativeMiniGame) {
        guard narrativePauseReasons.subtracting([.microGame]).isEmpty,
              narrativeCampaign.isActive,
              narrativeCampaign.isComplete == false,
              narrativeCampaign.currentMoment.miniGame == miniGame,
              narrativeCampaign.miniGameCompleted == false else { return }
        activeNarrativeMicroGame = miniGame
        narrativePauseReasons.insert(.microGame)
        lastNarrativeMicroGameFeedback = MirrorMicroGameInputFeedbackModel.ready(from: narrativeCampaign, miniGame: miniGame)
        message = "感知闪现开始。先把这一盏灯完成，剧情会在你回来后继续。"
        developerPlaytestLog.append("MICRO_PORTAL enter \(miniGame.rawValue) progress=\(narrativeCampaign.miniGameProgress)/\(miniGame.requiredInteractions)")
        if miniGame == .melody {
            publishNarrativeMelodyPlaybackCue(reason: "enter")
        }
    }

    func dismissNarrativeMicroGame() {
        let dismissedMicroGame = activeNarrativeMicroGame
        activeNarrativeMicroGame = nil
        narrativePauseReasons.remove(.microGame)
        if let dismissedMicroGame,
           narrativeCampaign.miniGameCompleted == false {
            addAudioCue(.paper, direction: dismissedMicroGame.title, intensity: 0.22, note: "感知闪现被轻轻放下；这不是失败，进度会留在灯里。")
            message = "你先离开了\(dismissedMicroGame.title)。这不是失败，回到这盏灯时可以继续。"
            developerPlaytestLog.append("MICRO_PORTAL dismiss \(dismissedMicroGame.rawValue) progress=\(narrativeCampaign.miniGameProgress)/\(dismissedMicroGame.requiredInteractions)")
        }
    }

    private func closeNarrativeMicroGameIfComplete() {
        guard let completedMicroGame = activeNarrativeMicroGame,
              narrativeCampaign.miniGameCompleted else { return }
        activeNarrativeMicroGame = nil
        narrativePauseReasons.remove(.microGame)
        publishNarrativeMicroGameCompletionCue(completedMicroGame)
        addMonologue(narrativeMicroGameCompletionMonologue(completedMicroGame), intensity: 0.62)
        message = narrativeMicroGameCompletionMessage(completedMicroGame)
        developerPlaytestLog.append("MICRO_PORTAL return \(completedMicroGame.rawValue) complete")
    }

    private func publishNarrativeMicroGameInputFeedback(
        miniGame: NarrativeMiniGame,
        slot: Int,
        beforeProgress: Int,
        beforeTouchedSlots: Set<Int>,
        beforeHintCount: Int
    ) {
        guard narrativeCampaign.chapter == .mirror else { return }
        let feedback = MirrorMicroGameInputFeedbackModel.action(
            miniGame: miniGame,
            slot: slot,
            beforeProgress: beforeProgress,
            afterProgress: narrativeCampaign.miniGameProgress,
            beforeTouchedCount: beforeTouchedSlots.count,
            afterTouchedCount: narrativeCampaign.miniGameTouchedSlots.count,
            beforeHintCount: beforeHintCount,
            afterHintCount: narrativeCampaign.miniGameHintCount,
            completed: narrativeCampaign.miniGameCompleted
        )
        lastNarrativeMicroGameFeedback = feedback
        developerPlaytestLog.append("MICRO_INPUT \(miniGame.rawValue) \(feedback.tone.rawValue) slot=\(slot) progress=\(narrativeCampaign.miniGameProgress)/\(miniGame.requiredInteractions)")
        if miniGame == .melody {
            let melody = MirrorMelodyPlaybackModel.derive(from: narrativeCampaign)
            let next = melody.nextPadIndex.map { MirrorMelodyPlaybackModel.labels[$0] } ?? "完成"
            developerPlaytestLog.append("MELODY_RHYTHM \(feedback.tone.rawValue) next=\(next) hints=\(melody.hintCount) sequence=\(melody.sequenceText)")
        }

        if feedback.isRecovery {
            message = feedback.detail
            addAudioCue(.lights, direction: "镜面\(miniGame.title)", intensity: 0.2, note: feedback.detail)
        }
    }

    private func publishNarrativeMelodyPlaybackCue(reason: String) {
        let melody = MirrorMelodyPlaybackModel.derive(from: narrativeCampaign)
        guard melody.isActive else { return }
        addAudioCue(
            .lights,
            direction: "镜面旋律灯",
            intensity: reason == "replay" ? 0.38 : 0.34,
            note: "四拍程序化旋律：\(melody.sequenceText)（\(melody.frequencyText)）。"
        )
        developerPlaytestLog.append("MELODY_PLAYBACK \(reason) sequence=\(melody.sequenceText) frequencies=\(melody.frequencyText)")
    }

    private func publishNarrativeMicroGameStepCueIfNeeded(slot: Int, beforeProgress: Int, beforeTouchedSlots: Set<Int>, beforeCompleted: Bool) {
        guard narrativeCampaign.chapter == .mirror,
              let miniGame = narrativeCampaign.currentMoment.miniGame,
              beforeCompleted == false else { return }
        let didAdvance = narrativeCampaign.miniGameProgress > beforeProgress
            || narrativeCampaign.miniGameTouchedSlots.count > beforeTouchedSlots.count
        guard didAdvance else { return }
        let echo = MirrorMicroGameEchoModel.derive(from: narrativeCampaign)
        let intensity = min(0.5, 0.24 + Double(echo.ratio) * 0.22)
        addAudioCue(.lights, direction: "镜面\(miniGame.title)", intensity: intensity, note: echo.detail)
        developerPlaytestLog.append("MICRO_ECHO \(miniGame.rawValue) slot=\(slot) progress=\(echo.completedSteps)/\(echo.requiredSteps)")
        if narrativeCampaign.miniGameCompleted == false {
            message = echo.detail
        }
    }

    private func publishNarrativeMicroGameCompletionCue(_ miniGame: NarrativeMiniGame) {
        let direction: String
        let note: String
        switch miniGame {
        case .trace:
            direction = "镜面草稿灯"
            note = "草稿线终于接上，第一段光路沿地面亮起来。"
        case .melody:
            direction = "镜面旋律灯"
            note = "四拍旋律被接住，第二盏灯把回声推向下一段路。"
        case .erase:
            direction = "镜面擦痕灯"
            note = "比较的话被擦到只剩边缘，第三盏灯亮起但没有把痕迹清空。"
        }
        addAudioCue(.lights, direction: direction, intensity: 0.52, note: note)
    }

    private func narrativeMicroGameCompletionMessage(_ miniGame: NarrativeMiniGame) -> String {
        switch miniGame {
        case .trace:
            return "草稿灯亮了。线不需要完美，只要能继续往前。"
        case .melody:
            return "旋律灯亮了。听不清的地方，也可以被慢慢接住。"
        case .erase:
            return "擦痕灯亮了。比较的话退到边缘，但苏念没有假装它们从没存在过。"
        }
    }

    private func narrativeMicroGameCompletionMonologue(_ miniGame: NarrativeMiniGame) -> String {
        switch miniGame {
        case .trace:
            return "原来有些线不是为了画直，是为了让我知道它还可以继续。"
        case .melody:
            return "我可以听不清，也可以停下来再听一次；被接住不是失败。"
        case .erase:
            return "那些比较没有完全消失，但它们终于不再盖住林澈自己的声音。"
        }
    }

    func dismissNarrativeRiskEducationCard() {
        guard narrativePaused == false,
              narrativeCampaign.shouldPresentRiskEducationCard else { return }
        narrativeCampaign.dismissRiskEducationCard()
        message = "可以直接而温和地确认风险。问清楚不会把念头塞进一个人脑中。"
        developerPlaytestLog.append("EDUCATION 4.risk dismissed")
        saveNarrativeCampaign()
        objectWillChange.send()
    }

    func moveNarrativeExploration(forward: Double, strafe: Double, deltaTime: Double) {
        guard case .playing = gameState,
              narrativePaused == false,
              narrativeCampaign.isActive,
              narrativeCampaign.isComplete == false else { return }
        narrativeCampaign.exploration.move(forward: forward, strafe: strafe, deltaTime: deltaTime)
        publishCompanionNavigationWhisperIfNeeded()
    }

    var narrativeBoundaryDwellProgress: Double {
        min(1, narrativeBoundaryDwellSeconds / 3)
    }

    func tickNarrativeExploration(deltaTime: Double) {
        guard case .playing = gameState,
              narrativeCampaign.isActive,
              narrativeCampaign.isComplete == false else {
            narrativeBoundaryDwellSeconds = 0
            return
        }
        guard narrativePaused == false else { return }
        updateNarrativeFallbackClock(deltaTime: deltaTime)
        guard narrativeCampaign.chapter == .counseling else {
            narrativeBoundaryDwellSeconds = 0
            return
        }

        narrativeCampaign.exploration.positionZ = max(-2.3, narrativeCampaign.exploration.positionZ)
        guard narrativeCampaign.counselingState?.entryMode != .emergencyClosure else {
            narrativeBoundaryDwellSeconds = 0
            return
        }

        let distanceToDoor = hypot(
            narrativeCampaign.exploration.positionX,
            narrativeCampaign.exploration.positionZ + 2.3
        )
        guard distanceToDoor <= 0.62 else {
            narrativeBoundaryDwellSeconds = 0
            return
        }

        narrativeBoundaryDwellSeconds += max(0, min(0.1, deltaTime))
        guard narrativeBoundaryDwellSeconds >= 3 else { return }
        narrativeBoundaryDwellSeconds = 0
        narrativeBoundaryPullbackCount += 1
        narrativeCampaign.exploration.positionX *= 0.5
        narrativeCampaign.exploration.positionZ = -1.2
        narrativeCampaign.counselingState?.boundaryHeld = true
        message = "门内正在会谈。你退回等候区，把不进入也当成陪伴的一部分。"
        addAudioCue(.footstep, direction: "咨询室门外", intensity: 0.3, note: "脚步退回等候区，门内的谈话仍然保持私密。")
        developerPlaytestLog.append("BOUNDARY counseling.pullback")
        saveNarrativeCampaign()
        objectWillChange.send()
    }

    var chapterOneDwellProgress: Double {
        guard let objective = currentSpatialAudioObjective,
              cameraPose == objective.targetPose else { return 0 }
        return chapterOneDwellFocus.progress(for: objective.targetPose)
    }

    func tickChapterOneDwell(deltaTime: TimeInterval) {
        guard case .playing = gameState,
              isPrologueActive == false,
              narrativeCampaign.isActive == false,
              narrativePaused == false,
              activeChapter == .silentClassroom,
              activeRole.isTeacher == false,
              freeRoam.isActive == false,
              isReturningToSeat == false else {
            seatedPosePressureFeedback = nil
            teacherPatrolReadout = nil
            return
        }

        let clampedDelta = max(0, min(0.1, deltaTime))
        applySeatedPosePressure(deltaTime: clampedDelta)

        guard hasPresentedChapterOneDecision == false,
              let objective = currentSpatialAudioObjective,
              chapterOneLocatedAudioSteps.contains(objective.step) == false else {
            return
        }

        let pose = cameraPose
        chapterOneDwellFocus.resetForPose(pose)
        guard pose == objective.targetPose,
              chapterOneDwellFocus.triggeredInCurrentStep.contains(pose) == false,
              let threshold = DwellThreshold.threshold(for: pose) else { return }

        chapterOneDwellFocus.dwellAccumulated += clampedDelta
        guard chapterOneDwellFocus.dwellAccumulated >= threshold else { return }

        chapterOneDwellFocus.triggeredInCurrentStep.insert(pose)
        markCurrentSpatialAudioTargetIfMatched()
    }

    private func applySeatedPosePressure(deltaTime: TimeInterval) {
        guard deltaTime > 0 else { return }
        let pose = cameraPose
        let feedback = SeatedPosePressureFeedback.derive(
            pose: pose,
            teacherNear: teacher.isNearPlayer,
            psychicEnergy: player.psychicEnergy,
            stress: player.stress,
            maskCost: player.maskCost,
            visualAttention: player.visualAttention
        )
        seatedPosePressureFeedback = feedback

        switch pose {
        case .forward:
            recoverAttention(2.2 * deltaTime)
            player.psychicEnergy += 0.9 * deltaTime
            player.maskCost += 0.35 * deltaTime
            player.stress = max(0, player.stress - 0.8 * deltaTime)
            player.exposure = max(0, player.exposure - 0.55 * deltaTime)
        case .desk:
            player.psychicEnergy -= 0.65 * deltaTime
            player.visualAttention = max(0, player.visualAttention - 1.15 * deltaTime)
            player.stress += (teacher.isNearPlayer ? 4.2 : 1.65) * deltaTime
            player.exposure = max(0, player.exposure - 2.2 * deltaTime)
            player.maskCost += (teacher.isNearPlayer ? 0.75 : 0.35) * deltaTime
        case .board:
            player.psychicEnergy -= 2.4 * deltaTime
            player.visualAttention = max(0, player.visualAttention - 1.8 * deltaTime)
            player.maskCost += 2.35 * deltaTime
            player.exposure += (teacher.isNearPlayer ? 3.8 : 2.1) * deltaTime
            player.stress += (teacher.isNearPlayer ? 2.2 : 0.8) * deltaTime
        case .left:
            player.psychicEnergy -= 0.8 * deltaTime
            player.visualAttention = max(0, player.visualAttention - 0.55 * deltaTime)
            player.exposure += (teacher.isNearPlayer ? 2.4 : 1.05) * deltaTime
            player.maskCost = max(0, player.maskCost - 0.7 * deltaTime)
            player.support += 0.35 * deltaTime
        case .right:
            player.psychicEnergy -= 0.95 * deltaTime
            player.visualAttention = max(0, player.visualAttention - 0.8 * deltaTime)
            player.exposure += (teacher.isNearPlayer ? 2.8 : 1.25) * deltaTime
            player.stress += (teacher.isNearPlayer ? 1.65 : 0.55) * deltaTime
        case .rear:
            player.psychicEnergy -= 2.8 * deltaTime
            player.visualAttention = max(0, player.visualAttention - 3.2 * deltaTime)
            player.exposure += (teacher.isNearPlayer ? 9.0 : 6.2) * deltaTime
            player.stress += (teacher.isNearPlayer ? 4.2 : 2.8) * deltaTime
            player.maskCost += 1.7 * deltaTime
        }

        updateFocusQuality()
        updateTeacherPatrolReadout()
        clampPlayer()
        maybePublishSeatedPosePressureCue(feedback)
    }

    private func updateTeacherPatrolReadout() {
        teacher.location = TeacherLocation.closest(forPositionIndex: teacher.positionIndex)
        let readout = TeacherPatrolReadout.derive(
            positionIndex: teacher.positionIndex,
            isNearPlayer: teacher.isNearPlayer,
            institutionalPressure: teacher.institutionalPressure,
            fatigue: teacher.fatigue,
            playerPose: cameraPose,
            playerExposure: player.exposure
        )
        teacherPatrolReadout = readout
        maybePublishTeacherPatrolCue(readout)
    }

    private func maybePublishSeatedPosePressureCue(_ feedback: SeatedPosePressureFeedback) {
        guard feedback.intensity >= 0.58 else { return }
        let bucket = Int(chapterOneDwellFocus.dwellAccumulated.rounded(.down))
        guard bucket >= 1 else { return }
        let signature = "\(chapterOneStep.rawValue)-\(feedback.pose.rawValue)-\(bucket)"
        guard signature != lastSeatedPosePressureCueSignature else { return }
        lastSeatedPosePressureCueSignature = signature

        switch feedback.tone {
        case .body:
            addAudioCue(.heartbeat, direction: "颅内", intensity: min(0.82, feedback.intensity), note: feedback.detail)
        case .risk:
            addAudioCue(.chair, direction: feedback.pose == .rear ? "座位下方" : "桌边", intensity: min(0.78, feedback.intensity), note: feedback.recommendation)
        case .connection:
            addAudioCue(.whisper, direction: feedback.pose == .left ? "左侧近处" : "右侧近处", intensity: min(0.62, feedback.intensity), note: feedback.recommendation)
        case .stable:
            addAudioCue(.teacherSigh, direction: "讲台前方", intensity: min(0.56, feedback.intensity), note: feedback.detail)
        }
    }

    private func maybePublishTeacherPatrolCue(_ readout: TeacherPatrolReadout) {
        guard readout.intensity >= 0.62 else { return }
        let bucket = Int(chapterOneDwellFocus.dwellAccumulated.rounded(.down))
        guard bucket >= 1 else { return }
        let signature = "\(chapterOneStep.rawValue)-\(readout.location.rawValue)-\(readout.tone)-\(bucket)"
        guard signature != lastTeacherPatrolReadoutCueSignature else { return }
        lastTeacherPatrolReadoutCueSignature = signature

        switch readout.tone {
        case .close:
            addAudioCue(.footstep, direction: "右侧极近", intensity: min(0.9, readout.intensity), note: readout.recommendation)
            player.stress += cameraPose == .forward ? 0.6 : 1.4
        case .unseen:
            addAudioCue(.knock, direction: "后方左侧", intensity: min(0.72, readout.intensity), note: readout.detail)
            player.stress += cameraPose == .rear ? 0.5 : 1.1
        case .approaching:
            addAudioCue(.teacherCough, direction: readout.location.rawValue, intensity: min(0.72, readout.intensity), note: readout.detail)
            player.stress += 0.8
        case .distant:
            break
        }
        clampPlayer()
    }

    func advanceChapterOneDwell(by seconds: TimeInterval) {
        var remaining = max(0, seconds)
        while remaining > 0 {
            let delta = min(0.1, remaining)
            tickChapterOneDwell(deltaTime: delta)
            remaining -= delta
        }
    }

    func completeCurrentSpatialAudioDwellIfPossible() {
        guard let objective = currentSpatialAudioObjective,
              cameraPose == objective.targetPose,
              chapterOneLocatedAudioSteps.contains(objective.step) == false,
              let threshold = DwellThreshold.threshold(for: objective.targetPose) else { return }
        let remaining = max(0, threshold - chapterOneDwellFocus.dwellAccumulated)
        advanceChapterOneDwell(by: remaining + 0.01)
    }

    private func publishFocusFeedback(for pose: CameraPose) {
        let feedback = DwellFocusFeedback(pose: pose, progress: chapterOneDwellFocus.progress(for: pose))
        focusFeedbackTrigger = feedback
        focusFeedbackClearTask?.cancel()
        let duration: Duration = accessibilityPreferences.reduceMotion ? .milliseconds(360) : .milliseconds(820)
        focusFeedbackClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            guard self?.focusFeedbackTrigger?.id == feedback.id else { return }
            self?.focusFeedbackTrigger = nil
        }
    }

    private func clearFocusFeedback() {
        focusFeedbackClearTask?.cancel()
        focusFeedbackClearTask = nil
        focusFeedbackTrigger = nil
    }

    private func updateNarrativeFallbackClock(deltaTime: Double) {
        let momentID = narrativeCampaign.currentMoment.id
        if timedNarrativeMomentID != momentID {
            timedNarrativeMomentID = momentID
            narrativeMomentElapsedSeconds = 0
            narrativeGuidanceCue = nil
        }
        narrativeMomentElapsedSeconds += max(0, min(0.1, deltaTime))
        updateNarrativeStallGuidance()

        let fallback: (after: Double, choiceID: String, message: String)?
        switch momentID {
        case "3.companion" where narrativeCampaign.companionID.isEmpty:
            fallback = (90, "zhou", "你迟迟没有开口。苏念走向班长，周予安点头跟了上来。")
        case let id where id.hasPrefix("4.listen."):
            fallback = nil
        case "4.risk":
            fallback = (15, "adultNow", "信息仍不完整，但这不妨碍先让可靠成人到场。")
        case "4.contact" where narrativeCampaign.safetyHandoffState?.adultContactInitiated != true:
            fallback = (30, "contactAdult", "同伴主动发出联络，说明楼层、位置和需要成人到场。")
        case "5.rumor" where narrativeCampaign.counselingState?.rumorHandled != true:
            fallback = narrativeCampaign.counselingState?.entryMode == .emergencyClosure
                ? (0.1, "redirect", "方老师提醒大家不要在群里讨论刚才的事，没有生成围观和猜测。")
                : (20, "redirect", "你没有回应猜测。议论自行散去，没有任何隐私被泄露。")
        case "5.message" where narrativeCampaign.counselingState?.companionMessageReplied != true:
            fallback = (900, "message", "等候被压缩到必要信息：可以一起等，也可以继续找老师。")
        default:
            fallback = nil
        }
        if momentID.hasPrefix("4.listen."), narrativeMomentElapsedSeconds >= 15 {
            let before = narrativeCampaign.currentMoment.id
            guard narrativeCampaign.timeoutJiangDialogue() else { return }
            narrativeMomentElapsedSeconds = 0
            timedNarrativeMomentID = narrativeCampaign.currentMoment.id
            narrativeGuidanceCue = nil
            let repeatedTimeouts = narrativeCampaign.jiangDialogueState?.consecutiveTimeouts ?? 0
            message = repeatedTimeouts >= 2
                ? "沉默也是一种在场。你也可以选择复述、陪伴，或继续安静地听。"
                : "你没有急着填满沉默。江越慢慢把下一句话说完。"
            developerPlaytestLog.append("FALLBACK \(before) -> timeout")
            syncNarrativeAudioDynamics()
            saveNarrativeCampaign()
            objectWillChange.send()
            return
        }
        guard let fallback, narrativeMomentElapsedSeconds >= fallback.after else { return }

        let before = narrativeCampaign.currentMoment.id
        narrativeCampaign.choose(fallback.choiceID)
        guard narrativeCampaign.currentMoment.id != before || narrativeCampaign.isComplete else { return }
        narrativeMomentElapsedSeconds = 0
        timedNarrativeMomentID = narrativeCampaign.isComplete ? "" : narrativeCampaign.currentMoment.id
        narrativeGuidanceCue = nil
        message = fallback.message
        developerPlaytestLog.append("FALLBACK \(before) -> \(fallback.choiceID)")
        addAudioCue(.footstep, direction: "剧情兜底", intensity: 0.22, note: fallback.message)
        syncNarrativeAudioDynamics()
        saveNarrativeCampaign()
        objectWillChange.send()
    }

    private func updateNarrativeStallGuidance() {
        guard narrativeCampaign.isActive, narrativeCampaign.isComplete == false else {
            narrativeGuidanceCue = nil
            return
        }

        if narrativeMomentElapsedSeconds >= 90,
           narrativeGuidanceCue?.stage != .directorNudge {
            let detail = performNarrativeDirectorNudge()
            narrativeGuidanceCue = NarrativeGuidanceCue(
                id: "\(narrativeCampaign.currentMoment.id).director.\(Int(narrativeMomentElapsedSeconds))",
                momentID: narrativeCampaign.currentMoment.id,
                stage: .directorNudge,
                title: "苏念把下一步变得更清楚",
                detail: detail,
                elapsedSeconds: narrativeMomentElapsedSeconds
            )
            developerPlaytestLog.append("GUIDE_NUDGE \(narrativeCampaign.currentMoment.id)")
            objectWillChange.send()
            return
        }

        if narrativeMomentElapsedSeconds >= 30,
           narrativeGuidanceCue == nil {
            narrativeGuidanceCue = NarrativeGuidanceCue(
                id: "\(narrativeCampaign.currentMoment.id).gentle",
                momentID: narrativeCampaign.currentMoment.id,
                stage: .gentle,
                title: "先找一个不会伤人的下一步",
                detail: narrativeGuidanceDetail(),
                elapsedSeconds: narrativeMomentElapsedSeconds
            )
            developerPlaytestLog.append("GUIDE_HINT \(narrativeCampaign.currentMoment.id)")
            objectWillChange.send()
        }
    }

    private func narrativeGuidanceDetail() -> String {
        if narrativeCampaign.shouldPresentRiskEducationCard {
            return "先读完安全提示，再继续问清楚；这一步不是诊断，是确认不会把人单独留下。"
        }
        if narrativeCampaign.explorationReady == false,
           let hotspot = NarrativeHotspot.all(for: narrativeCampaign.chapter).first {
            return "空间里已经有线索：慢慢靠近「\(hotspot.title)」，不用急着解释它。"
        }
        if let hotspot = narrativeCampaign.requiredInteractionHotspots.first {
            return "这一步需要身体先到场：靠近「\(hotspot.title)」，确认后再推进。"
        }
        if narrativeCampaign.currentMomentActionReady == false,
           let hotspot = narrativeCampaign.interactionHotspots.first(where: { $0.id == "handoff.teacher" }) {
            return "先走到「\(hotspot.title)」身边，让可靠的大人真的来到现场。"
        }
        if narrativeCampaign.currentMoment.miniGame != nil,
           narrativeCampaign.miniGameCompleted == false {
            return "这个微互动没有失败判定；你可以完成下一格，也可以让苏念慢慢做。"
        }
        if narrativeCampaign.currentMoment.choices.isEmpty == false {
            return "选择不需要完美。优先保护安全、隐私和边界，主线不会因为不佳选择断掉。"
        }
        return "先听见，再判断。停一下也算正在参与。"
    }

    @discardableResult
    private func performNarrativeDirectorNudge() -> String {
        if narrativeCampaign.shouldPresentRiskEducationCard {
            message = "安全便签还在这里。苏念把目光停在“不会单独留下”那一句上。"
            addAudioCue(.paper, direction: "安全便签", intensity: 0.26, note: "便签被轻轻按住，提醒玩家先确认安全提示。")
            return "安全提示被重新强调，下一步是主动关闭便签。"
        }

        if narrativeCampaign.currentMomentActionReady == false,
           let hotspot = narrativeCampaign.requiredInteractionHotspots.first {
            moveNarrativeExplorationToward(hotspot, steps: 14)
            message = "苏念把脚步转向「\(hotspot.title)」。这不是解谜捷径，是让判断先落到看得见的线索上。"
            addAudioCue(.footstep, direction: hotspot.title, intensity: 0.32, note: hotspot.prompt)
            return "镜头和脚步转向「\(hotspot.title)」，当前调查热点更容易被确认。"
        }

        if narrativeCampaign.currentMomentActionReady == false,
           let hotspot = narrativeCampaign.interactionHotspots.first(where: { $0.id == "handoff.teacher" }) {
            moveNarrativeExplorationToward(hotspot, steps: 14)
            message = "方老师已经到场。苏念把脚步转向她，把接手这件事交还给大人。"
            addAudioCue(.footstep, direction: hotspot.title, intensity: 0.32, note: "脚步朝可靠成人靠近。")
            return "镜头和脚步转向「\(hotspot.title)」，成人交接热点更容易被确认。"
        }

        if narrativeCampaign.explorationReady == false,
           let hotspot = NarrativeHotspot.all(for: narrativeCampaign.chapter).first {
            moveNarrativeExplorationToward(hotspot, steps: 14)
            message = "苏念没有替你判断答案，只是把身体转向最值得停下来的地方。"
            addAudioCue(narrativeCampaign.chapter == .mirror ? .lights : .footstep, direction: hotspot.title, intensity: 0.3, note: "空间线索被轻轻推到前景。")
            return "空间方向被推到前景：继续靠近「\(hotspot.title)」。"
        }

        if let miniGame = narrativeCampaign.currentMoment.miniGame,
           narrativeCampaign.miniGameCompleted == false {
            let slot: Int
            switch miniGame {
            case .trace:
                slot = narrativeCampaign.miniGameProgress
            case .melody:
                slot = [1, 3, 0, 2][narrativeCampaign.miniGameProgress]
            case .erase:
                slot = [5, 2, 0, 4, 1, 3][narrativeCampaign.miniGameProgress]
            }
            performNarrativeMiniGameAction(slot)
            message = "苏念慢慢完成了一小步。你可以继续，也可以停下来重新看清目标。"
            addAudioCue(.paper, direction: narrativeCampaign.currentMoment.title, intensity: 0.24, note: "微互动自动推进一格，不制造失败。")
            return "微互动自动完成了第 \(slot + 1) 个节点，没有失败惩罚。"
        }

        message = "这里没有标准答案。苏念把选择留在屏幕上，也把呼吸放慢一点。"
        addAudioCue(.heartbeat, direction: narrativeCampaign.currentMoment.title, intensity: 0.2, note: "停滞引导没有代替玩家做剧情判断。")
        return "没有替你选择，只强化当前目标和可选回应。"
    }

    private func moveNarrativeExplorationToward(_ hotspot: NarrativeHotspot, steps: Int) {
        let dx = hotspot.x - narrativeCampaign.exploration.positionX
        let dz = hotspot.z - narrativeCampaign.exploration.positionZ
        narrativeCampaign.exploration.yaw = atan2(-dx, -dz)
        for _ in 0..<steps {
            moveNarrativeExploration(forward: 1, strafe: 0, deltaTime: 0.05)
        }
    }

    func rotateNarrativeExploration(deltaX: Double, deltaY: Double) {
        guard case .playing = gameState,
              narrativePaused == false,
              narrativeCampaign.isActive,
              narrativeCampaign.isComplete == false else { return }
        narrativeCampaign.exploration.rotate(deltaX: deltaX, deltaY: deltaY)
    }

    var nearbyNarrativeHotspot: NarrativeHotspot? {
        guard narrativeCampaign.isActive, narrativeCampaign.isComplete == false else { return nil }
        return narrativeCampaign.nearbyHotspot
    }

    @discardableResult
    func interactNarrativeHotspot() -> Bool {
        guard narrativePaused == false,
              narrativeCampaign.isActive,
              narrativeCampaign.isComplete == false,
              let hotspot = narrativeCampaign.exploration.interact(with: narrativeCampaign.interactionHotspots) else { return false }
        narrativeCampaign.recordNoteTraceDepartureClue(for: hotspot.id)
        var didPresentMicroGame = false
        if let choiceID = hotspot.choiceID {
            if let miniGame = narrativeCampaign.currentMoment.miniGame,
               narrativeCampaign.miniGameCompleted == false,
               narrativeCampaign.currentMoment.choices.contains(where: { $0.id == choiceID }) {
                presentNarrativeMicroGame(miniGame)
                didPresentMicroGame = activeNarrativeMicroGame == miniGame
            } else {
                applyNarrativeChoice(choiceID)
            }
        }
        syncNarrativeAudioDynamics()
        if didPresentMicroGame == false {
            message = hotspot.prompt
        }
        addAudioCue(
            narrativeCampaign.chapter == .mirror ? .lights : .footstep,
            direction: hotspot.title,
            intensity: 0.48,
            note: hotspot.prompt
        )
        publishCompanionNavigationWhisperIfNeeded()
        let isStoryAction = hotspot.choiceID != nil || hotspot.id == "handoff.teacher"
        let logKind = isStoryAction == false
            ? "EXPLORE"
            : hotspot.id.hasPrefix("companion.") ? "COMPANION" : "ACTION"
        developerPlaytestLog.append("\(logKind) \(hotspot.id)")
        saveNarrativeCampaign()
        objectWillChange.send()
        return true
    }

    var narrativeKeyboardTargets: [NarrativeKeyboardTarget] {
        keyboardNarrativeTargets().map(\.summary)
    }

    var focusedNarrativeKeyboardTarget: NarrativeKeyboardTarget? {
        let targets = narrativeKeyboardTargets
        guard targets.isEmpty == false else { return nil }
        return targets[min(narrativeKeyboardFocusIndex, targets.count - 1)]
    }

    @discardableResult
    func performNarrativeKeyboardCommand(_ command: NarrativeKeyboardCommand) -> Bool {
        guard accessibilityPreferences.keyboardAlternativeInput else {
            narrativeKeyboardStatus = "键盘替代输入已关闭"
            return false
        }
        if command == .cancel {
            if narrativePaused { resumeNarrativeFromPause() }
            else if hasContinuableNarrativeSave { openNarrativePauseMenu() }
            return true
        }
        guard narrativePauseReasons.subtracting([.microGame]).isEmpty else {
            narrativeKeyboardStatus = "旅程暂停中"
            return false
        }

        var targets = keyboardNarrativeTargets()
        guard targets.isEmpty == false else {
            narrativeKeyboardFocusIndex = 0
            narrativeKeyboardStatus = "当前没有可用键盘目标"
            return false
        }
        narrativeKeyboardFocusIndex = min(max(0, narrativeKeyboardFocusIndex), targets.count - 1)

        switch command {
        case .previousTarget:
            narrativeKeyboardFocusIndex = (narrativeKeyboardFocusIndex + targets.count - 1) % targets.count
            narrativeKeyboardStatus = "聚焦 \(targets[narrativeKeyboardFocusIndex].summary.title)"
            return true
        case .nextTarget:
            narrativeKeyboardFocusIndex = (narrativeKeyboardFocusIndex + 1) % targets.count
            narrativeKeyboardStatus = "聚焦 \(targets[narrativeKeyboardFocusIndex].summary.title)"
            return true
        case .confirm:
            let target = targets[narrativeKeyboardFocusIndex]
            let handled = performKeyboardNarrativeTarget(target)
            targets = keyboardNarrativeTargets()
            narrativeKeyboardFocusIndex = min(max(0, narrativeKeyboardFocusIndex), max(0, targets.count - 1))
            return handled
        case .cancel:
            return false
        }
    }

    private enum KeyboardNarrativeTarget {
        case chapterOneAction(id: String, title: String, detail: String, pose: CameraPose?, action: PlayerAction)
        case dismissRiskEducation
        case eventChoice(EventChoice)
        case hotspot(NarrativeHotspot)
        case miniGameSlot(id: String, title: String, detail: String, slot: Int)
        case choice(NarrativeChoice)

        var summary: NarrativeKeyboardTarget {
            switch self {
            case .chapterOneAction(let id, let title, let detail, _, _):
                return NarrativeKeyboardTarget(id: id, title: title, detail: detail, symbol: "keyboard.fill", requiresMovement: false)
            case .dismissRiskEducation:
                return NarrativeKeyboardTarget(id: "risk.education.dismiss", title: "关闭安全提示", detail: "先确认问清风险的边界", symbol: "checkmark.shield.fill", requiresMovement: false)
            case .eventChoice(let choice):
                return NarrativeKeyboardTarget(id: choice.id, title: choice.title, detail: choice.detail, symbol: "text.bubble.fill", requiresMovement: false)
            case .hotspot(let hotspot):
                return NarrativeKeyboardTarget(id: hotspot.id, title: hotspot.title, detail: hotspot.prompt, symbol: "scope", requiresMovement: true)
            case .miniGameSlot(let id, let title, let detail, _):
                return NarrativeKeyboardTarget(id: id, title: title, detail: detail, symbol: "hand.tap.fill", requiresMovement: false)
            case .choice(let choice):
                return NarrativeKeyboardTarget(id: choice.id, title: choice.title, detail: choice.detail, symbol: choice.symbol, requiresMovement: false)
            }
        }
    }

    private func keyboardNarrativeTargets() -> [KeyboardNarrativeTarget] {
        if case .event(let event) = gameState {
            return event.choices.map(KeyboardNarrativeTarget.eventChoice)
        }
        if let activeNarrativeMicroGame,
           narrativeCampaign.currentMoment.miniGame == activeNarrativeMicroGame,
           narrativeCampaign.miniGameCompleted == false {
            return [keyboardMiniGameTarget(for: activeNarrativeMicroGame)]
        }
        if isFullNarrativeRun, narrativeCampaign.isActive == false {
            return keyboardChapterOneTargets()
        }
        guard narrativeCampaign.isActive, narrativeCampaign.isComplete == false else { return [] }
        if narrativeCampaign.shouldPresentRiskEducationCard {
            return [.dismissRiskEducation]
        }
        if narrativeCampaign.currentMomentActionReady == false {
            let requiredHotspots = narrativeCampaign.requiredInteractionHotspots
            if requiredHotspots.isEmpty == false {
                return requiredHotspots.map(KeyboardNarrativeTarget.hotspot)
            }
            return narrativeCampaign.interactionHotspots
                    .filter { $0.id == "handoff.teacher" }
                    .map(KeyboardNarrativeTarget.hotspot)
        }
        let choiceIDs = Set(narrativeCampaign.currentMoment.choices.map(\.id))
        let storyHotspots = narrativeCampaign.interactionHotspots.filter { hotspot in
            guard let choiceID = hotspot.choiceID else {
                return narrativeCampaign.explorationReady == false
            }
            return choiceIDs.contains(choiceID)
        }
        if storyHotspots.isEmpty == false {
            return storyHotspots.map(KeyboardNarrativeTarget.hotspot)
        }
        if narrativeCampaign.explorationReady == false {
            return narrativeCampaign.interactionHotspots.map(KeyboardNarrativeTarget.hotspot)
        }
        if let miniGame = narrativeCampaign.currentMoment.miniGame,
           narrativeCampaign.miniGameCompleted == false {
            return [keyboardMiniGameTarget(for: miniGame)]
        }
        return narrativeCampaign.currentMoment.choices.map(KeyboardNarrativeTarget.choice)
    }

    private func keyboardChapterOneTargets() -> [KeyboardNarrativeTarget] {
        guard isFullNarrativeRun, chapterOneStep != .completed else { return [] }
        switch chapterOneStep {
        case .observeLinChe:
            return [.chapterOneAction(id: "chapter1.observeLinChe", title: "看向林澈", detail: chapterOneStep.guidance, pose: .left, action: .observe)]
        case .locateHiddenSound:
            return [.chapterOneAction(id: "chapter1.locateHiddenSound", title: "听清右侧声音", detail: chapterOneStep.guidance, pose: .right, action: .observe)]
        case .regulateSelf:
            return [.chapterOneAction(id: "chapter1.regulateSelf", title: "放慢呼吸", detail: chapterOneStep.guidance, pose: nil, action: .breathe)]
        case .approachLinChe:
            return [.chapterOneAction(id: "chapter1.approachLinChe", title: "低声问候", detail: chapterOneStep.guidance, pose: nil, action: .talk)]
        case .inspectNote:
            return [.chapterOneAction(id: "chapter1.inspectNote", title: "低头确认纸条", detail: chapterOneStep.guidance, pose: .desk, action: .observe)]
        case .followLinChe:
            return [.chapterOneAction(id: "chapter1.followLinChe", title: "起身跟上", detail: chapterOneStep.guidance, pose: nil, action: .leaveSeat)]
        case .completed:
            return []
        }
    }

    private func keyboardMiniGameTarget(for miniGame: NarrativeMiniGame) -> KeyboardNarrativeTarget {
        let slot: Int
        let title: String
        switch miniGame {
        case .trace:
            slot = narrativeCampaign.miniGameProgress
            title = "描过第 \(slot + 1) 个光点"
        case .melody:
            let melody = [1, 3, 0, 2]
            slot = melody[min(narrativeCampaign.miniGameProgress, melody.count - 1)]
            title = "接住下一段旋律"
        case .erase:
            slot = (0..<6).first { narrativeCampaign.miniGameTouchedSlots.contains($0) == false } ?? 0
            title = "擦开第 \(slot + 1) 处痕迹"
        }
        return .miniGameSlot(
            id: "minigame.\(miniGame.rawValue).\(slot)",
            title: title,
            detail: "键盘替代输入会执行下一步所需动作，不把听力或精细拖拽当作通关门槛。",
            slot: slot
        )
    }

    @discardableResult
    private func performKeyboardNarrativeTarget(_ target: KeyboardNarrativeTarget) -> Bool {
        switch target {
        case .chapterOneAction(_, let title, _, let pose, let action):
            if let pose {
                setPose(pose)
                completeCurrentSpatialAudioDwellIfPossible()
            }
            execute(action)
            narrativeKeyboardStatus = "执行 \(title)"
            return true
        case .dismissRiskEducation:
            dismissNarrativeRiskEducationCard()
            narrativeKeyboardStatus = "安全提示已关闭"
            return true
        case .eventChoice(let choice):
            resolveEventChoice(choice)
            narrativeKeyboardStatus = "选择 \(choice.title)"
            return true
        case .hotspot(let hotspot):
            return performKeyboardHotspotTarget(hotspot)
        case .miniGameSlot(_, let title, _, let slot):
            performNarrativeMiniGameAction(slot)
            narrativeKeyboardStatus = "执行 \(title)"
            return true
        case .choice(let choice):
            advanceNarrative(choice.id)
            narrativeKeyboardStatus = "选择 \(choice.title)"
            return true
        }
    }

    @discardableResult
    private func performKeyboardHotspotTarget(_ hotspot: NarrativeHotspot) -> Bool {
        var remaining = hypot(
            hotspot.x - narrativeCampaign.exploration.positionX,
            hotspot.z - narrativeCampaign.exploration.positionZ
        )
        if remaining > hotspot.radius {
            narrativeCampaign.exploration.yaw = atan2(
                -(hotspot.x - narrativeCampaign.exploration.positionX),
                -(hotspot.z - narrativeCampaign.exploration.positionZ)
            )
            narrativeCampaign.exploration.positionX = hotspot.x
            narrativeCampaign.exploration.positionZ = hotspot.z
            remaining = 0
        }
        guard remaining <= hotspot.radius,
              let interacted = narrativeCampaign.exploration.interact(with: [hotspot]) else {
            narrativeKeyboardStatus = "靠近 \(hotspot.title) · \(String(format: "%.1f", max(0, remaining - hotspot.radius)))m"
            return true
        }
        narrativeCampaign.recordNoteTraceDepartureClue(for: interacted.id)
        if let choiceID = interacted.choiceID {
            if let miniGame = narrativeCampaign.currentMoment.miniGame,
               narrativeCampaign.miniGameCompleted == false,
               narrativeCampaign.currentMoment.choices.contains(where: { $0.id == choiceID }) {
                presentNarrativeMicroGame(miniGame)
            } else {
                applyNarrativeChoice(choiceID)
            }
        }
        message = interacted.prompt
        addAudioCue(
            narrativeCampaign.chapter == .mirror ? .lights : .footstep,
            direction: interacted.title,
            intensity: 0.48,
            note: interacted.prompt
        )
        let logKind = interacted.choiceID == nil ? "KEYBOARD_HOTSPOT" : "KEYBOARD_ACTION"
        developerPlaytestLog.append("\(logKind) \(interacted.id)")
        narrativeKeyboardStatus = "确认 \(interacted.title)"
        saveNarrativeCampaign()
        objectWillChange.send()
        return true
    }

    var developerStateSummary: String {
        if isFullNarrativeRun {
            return "第一章 / \(chapterOneStep.rawValue) / 线索 \(chapterClues.count)"
        }
        if narrativeCampaign.isActive {
            let moment = narrativeCampaign.currentMoment
            return "第 \(narrativeCampaign.chapter.rawValue) 章 / \(moment.id) / 互动 \(narrativeCampaign.miniGameProgress)"
        }
        return "\(gameState)"
    }

    private var playtestRouteStateSummary: String {
        if isFullNarrativeRun {
            return "第一章 \(chapterOneStep.rawValue) · 线索 \(chapterClues.count) · 视角 \(cameraPose.rawValue)"
        }
        if narrativeCampaign.isActive {
            let moment = narrativeCampaign.currentMoment
            let exploration = narrativeCampaign.exploration
            return "第 \(narrativeCampaign.chapter.rawValue) 章 \(moment.id) · x \(String(format: "%.1f", exploration.positionX)) z \(String(format: "%.1f", exploration.positionZ)) · 探索 \(narrativeCampaign.explorationReady ? "就绪" : "未就绪") · 动作 \(narrativeCampaign.currentMomentActionReady ? "就绪" : "锁定")"
        }
        return "\(gameState)"
    }

    private var playtestFrictionSummary: String {
        var notes: [String] = []
        if narrativePaused { notes.append("叙事暂停") }
        if narrativeCampaign.shouldPresentRiskEducationCard { notes.append("风险确认卡阻挡推进") }
        if narrativeCampaign.isActive && narrativeCampaign.isComplete == false {
            if narrativeCampaign.explorationReady == false { notes.append("空间探索门槛未完成") }
            if narrativeCampaign.currentMomentActionReady == false { notes.append("成人到场门槛未完成") }
            if let miniGame = narrativeCampaign.currentMoment.miniGame, narrativeCampaign.miniGameCompleted == false {
                notes.append("微互动 \(miniGame.rawValue) 未完成")
            }
            if narrativeCampaign.currentMoment.choices.isEmpty && narrativeCampaign.currentMoment.miniGame == nil {
                notes.append("当前剧情没有可选回应")
            }
        }
        if isFullNarrativeRun && narrativeCampaign.isActive == false {
            notes.append("第一章物理视角链路")
            if let objective = currentSpatialAudioObjective, objective.isLocated == false {
                notes.append("声源定位门槛未完成")
            }
        }
        return notes.isEmpty ? "无明显摩擦" : notes.joined(separator: " / ")
    }

    private func playtestFeedbackSummary() -> String {
        var notes: [String] = []
        if scenePresentation.phase != .idle {
            notes.append("场景 \(scenePresentation.chapter.title) \(scenePresentation.phase.rawValue)")
        }
        if let objective = currentSpatialAudioObjective {
            notes.append("声源目标 \(objective.direction)：\(objective.statusLine)")
        }
        if let navigationCue = ChapterThreeNavigationCue.derive(from: narrativeCampaign) {
            let pulseText = "\(Int((navigationCue.pulseIntensity * 100).rounded()))"
            notes.append("空间导航 \(navigationCue.headingText) · \(navigationCue.distanceBand) · 脉冲 \(pulseText)")
        }
        let mirrorNavigationCue = MirrorLightNavigationCue.derive(from: narrativeCampaign)
        if mirrorNavigationCue.isActive {
            let rangeText = "\(Int((mirrorNavigationCue.progressToRange * 100).rounded()))"
            notes.append("镜像导航 \(mirrorNavigationCue.title) · \(String(format: "%.1fm", mirrorNavigationCue.distance)) · 进圈 \(rangeText)")
        }
        let mirrorEcho = MirrorMicroGameEchoModel.derive(from: narrativeCampaign)
        if mirrorEcho.isActive, mirrorEcho.completedSteps > 0 {
            notes.append("微光回响 \(mirrorEcho.title) · \(mirrorEcho.completedSteps)/\(mirrorEcho.requiredSteps)")
        }
        if let inputFeedback = lastNarrativeMicroGameFeedback,
           inputFeedback.miniGame == narrativeCampaign.currentMoment.miniGame {
            notes.append("微互动手感 \(inputFeedback.title) · \(inputFeedback.progressText)")
        }
        let melodyPlayback = MirrorMelodyPlaybackModel.derive(from: narrativeCampaign)
        if melodyPlayback.isActive {
            let next = melodyPlayback.nextPadIndex.map { MirrorMelodyPlaybackModel.labels[$0] } ?? "完成"
            notes.append("旋律节拍 下一拍 \(next) · \(melodyPlayback.frequencyText)")
        }
        let mirrorReturnDirector = MirrorReturnDirectorModel.derive(from: narrativeCampaign)
        if mirrorReturnDirector.isActive {
            notes.append("镜面回归导演 \(mirrorReturnDirector.title) · 褪色 \(Int((mirrorReturnDirector.dissolve * 100).rounded()))")
        }
        let mirrorDialogue = MirrorDialogueConsequenceModel.derive(from: narrativeCampaign)
        if mirrorDialogue.isActive {
            notes.append("林澈后果 \(mirrorDialogue.title) · \(mirrorDialogue.trustDeltaText) · \(mirrorDialogue.supportBiasText)")
        }
        let mirrorCarryover = MirrorDialogueCarryoverModel.derive(from: narrativeCampaign)
        if mirrorCarryover.isActive {
            let carryoverChapter: String
            switch narrativeCampaign.chapter {
            case .noteTrace:
                carryoverChapter = "第三章"
            case .stairwell:
                carryoverChapter = "第四章"
            case .counseling:
                carryoverChapter = "第五章"
            default:
                carryoverChapter = "跨章"
            }
            notes.append("\(carryoverChapter)余波 \(mirrorCarryover.title) · \(mirrorCarryover.supportBiasText)")
        }
        if let handoffBriefing = NarrativeSafetyHandoffBriefing(campaign: narrativeCampaign),
           let supportLine = handoffBriefing.supportLine {
            notes.append("交接余波 \(supportLine)")
        }
        let mirrorPerformance = MirrorMicroGamePerformanceModel.derive(from: narrativeCampaign, activeMiniGame: activeNarrativeMicroGame)
        if mirrorPerformance.isOverlayActive {
            notes.append("镜面闪现 \(mirrorPerformance.title) · 进行中")
        } else if mirrorPerformance.isReturnPulseActive {
            notes.append("镜面回归 \(mirrorPerformance.title)")
        }
        if let companionLine = narrativeCampaign.companionPresenceStatus?.navigationLine {
            notes.append("同伴低语 \(companionLine)")
        }
        if let impactFeedback = pendingPlaytestChoiceImpactFeedback {
            notes.append(impactFeedback)
            pendingPlaytestChoiceImpactFeedback = nil
        }
        if let peerCue = sensoryPeerCue {
            notes.append("同学声场 \(peerCue.classmateName)@\(peerCue.direction)：\(peerCue.lowPressureAction)")
        }
        if let cue = audioCues.first {
            notes.append("音频 \(cue.kind.rawValue)@\(cue.direction)")
        }
        if message.isEmpty == false {
            notes.append("提示 \(message)")
        }
        if notes.isEmpty {
            return "视听反馈待触发"
        }
        return notes.joined(separator: " / ")
    }

    private func playtestChoiceImpactFeedback(for event: NarrativeImpactAudioEvent) -> String {
        let toneText: String
        switch event.tone {
        case .risk:
            toneText = "风险压近"
        case .support:
            toneText = "支持靠近"
        case .privacy:
            toneText = "边界落下"
        case .safety:
            toneText = "成人接手"
        case .investigate:
            toneText = "线索接上"
        }
        let intensityText = "\(Int((event.intensity * 100).rounded()))"
        return "选择回响 \(toneText) · \(event.cueKind.rawValue) · 强度 \(intensityText)"
    }

    private func recordPlaytestRoute(
        actor: String,
        input: String,
        beforeState: String,
        friction: String
    ) {
        let nextID = (playtestRouteTranscript.last?.id ?? 0) + 1
        let feedback = playtestFeedbackSummary()
        let entry = PlaytestRouteTranscriptEntry(
            id: nextID,
            step: nextID,
            actor: actor,
            input: input,
            beforeState: beforeState,
            afterState: playtestRouteStateSummary,
            friction: friction,
            feedback: feedback
        )
        playtestRouteTranscript.append(entry)
        if playtestRouteTranscript.count > 120 {
            playtestRouteTranscript.removeFirst(playtestRouteTranscript.count - 120)
        }
    }

    func developerJump(to chapter: NarrativeChapter, momentIndex: Int = 0) {
        let beforeState = playtestRouteStateSummary
        let friction = playtestFrictionSummary
        developerAutoplayTask?.cancel()
        developerExploredChapters = []
        narrativeBoundaryDwellSeconds = 0
        narrativeBoundaryPullbackCount = 0
        narrativeMomentElapsedSeconds = 0
        timedNarrativeMomentID = ""
        activeNarrativeMicroGame = nil
        if chapter == .classroom {
            startFullNarrativeCampaign()
            developerPlaytestStatus = "已跳转到可玩第一章"
            recordPlaytestRoute(actor: "开发者", input: "跳转可玩第一章", beforeState: beforeState, friction: friction)
            return
        }
        startGame()
        narrativeCampaign.startAfterPlayableChapterOne()
        narrativeCampaign.chapter = chapter
        if chapter.rawValue >= NarrativeChapter.stairwell.rawValue {
            narrativeCampaign.companionID = "周予安"
        }
        if chapter.rawValue >= NarrativeChapter.counseling.rawValue {
            narrativeCampaign.safetyHandoffState = NarrativeSafetyHandoffState(
                authoredRisk: .moderate,
                riskAsked: true,
                adultContactInitiated: true,
                contactMethod: "电话",
                safetyHandoffComplete: true,
                route: .standardCounseling,
                entryMode: .standardWaiting,
                resolutionPath: .voluntary
            )
            narrativeCampaign.safetyRoute = NarrativeSafetyRoute.standardCounseling.displayName
        }
        narrativeCampaign.prepareRuntimeStateForCurrentChapter()
        narrativeCampaign.exploration.reset(for: chapter)
        let moments = NarrativeCampaign.moments(for: chapter)
        narrativeCampaign.momentIndex = min(max(0, momentIndex), moments.count - 1)
        narrativeCampaign.miniGameProgress = 0
        narrativeCampaign.miniGameTouchedSlots = []
        narrativeCampaign.miniGameHintCount = 0
        gameState = .playing
        mouseLookEnabled = false
        presentScenePresentation(for: chapter)
        syncNarrativeAudioDynamics()
        developerPlaytestStatus = "已跳转到 \(chapter.title)"
        developerPlaytestLog.append("JUMP \(narrativeCampaign.currentMoment.id)")
        recordPlaytestRoute(actor: "开发者", input: "跳转 \(chapter.title)", beforeState: beforeState, friction: friction)
        saveNarrativeCampaign()
    }

    func developerAdvanceOneStep() {
        guard narrativeCampaign.isActive, narrativeCampaign.isComplete == false else { return }
        let beforeState = playtestRouteStateSummary
        let friction = playtestFrictionSummary
        if narrativeCampaign.shouldPresentRiskEducationCard {
            dismissNarrativeRiskEducationCard()
            recordPlaytestRoute(actor: "开发者自动游玩", input: "关闭风险确认卡", beforeState: beforeState, friction: friction)
            return
        }
        let moment = narrativeCampaign.currentMoment
        if let miniGame = moment.miniGame,
           narrativeCampaign.miniGameCompleted == false,
           narrativeCampaign.currentMomentActionReady {
            let slot: Int
            switch miniGame {
            case .trace, .erase:
                slot = narrativeCampaign.miniGameProgress
            case .melody:
                slot = [1, 3, 0, 2][narrativeCampaign.miniGameProgress]
            }
            performNarrativeMiniGameAction(slot)
            developerPlaytestLog.append("INPUT \(moment.id) slot=\(slot)")
            recordPlaytestRoute(actor: "开发者自动游玩", input: "微互动 \(moment.id) slot \(slot)", beforeState: beforeState, friction: friction)
            return
        }
        let validChoiceIDs = Set(narrativeCampaign.currentMoment.choices.map(\.id))
        if narrativeCampaign.currentMomentActionReady == false,
           let hotspot = narrativeCampaign.requiredInteractionHotspots.first {
            developerMoveTowardNarrativeHotspot(hotspot)
            recordPlaytestRoute(actor: "开发者自动游玩", input: "靠近必需热点 \(hotspot.id)", beforeState: beforeState, friction: friction)
            return
        }
        if narrativeCampaign.currentMomentActionReady == false,
           let hotspot = narrativeCampaign.interactionHotspots.first(where: { $0.id == "handoff.teacher" }) {
            developerMoveTowardNarrativeHotspot(hotspot)
            recordPlaytestRoute(actor: "开发者自动游玩", input: "靠近成人交接热点 \(hotspot.id)", beforeState: beforeState, friction: friction)
            return
        }
        if let hotspot = narrativeCampaign.interactionHotspots.first(where: {
            guard let choiceID = $0.choiceID else { return false }
            return validChoiceIDs.contains(choiceID)
        }) {
            developerMoveTowardNarrativeHotspot(hotspot)
            recordPlaytestRoute(actor: "开发者自动游玩", input: "靠近剧情热点 \(hotspot.id)", beforeState: beforeState, friction: friction)
            return
        }
        if developerExploredChapters.contains(narrativeCampaign.chapter) == false,
           let hotspot = NarrativeHotspot.all(for: narrativeCampaign.chapter).first {
            let exploration = narrativeCampaign.exploration
            if hypot(exploration.positionX - hotspot.x, exploration.positionZ - hotspot.z) <= hotspot.radius {
                if interactNarrativeHotspot() {
                    developerExploredChapters.insert(narrativeCampaign.chapter)
                }
                recordPlaytestRoute(actor: "开发者自动游玩", input: "确认探索热点 \(hotspot.id)", beforeState: beforeState, friction: friction)
                return
            }
            let dx = hotspot.x - exploration.positionX
            let dz = hotspot.z - exploration.positionZ
            narrativeCampaign.exploration.yaw = atan2(-dx, -dz)
            for _ in 0..<8 {
                moveNarrativeExploration(forward: 1, strafe: 0, deltaTime: 0.05)
            }
            developerPlaytestLog.append("MOVE ch\(narrativeCampaign.chapter.rawValue) x=\(String(format: "%.1f", narrativeCampaign.exploration.positionX)) z=\(String(format: "%.1f", narrativeCampaign.exploration.positionZ))")
            recordPlaytestRoute(actor: "开发者自动游玩", input: "走向探索热点 \(hotspot.id)", beforeState: beforeState, friction: friction)
            return
        }
        if let miniGame = moment.miniGame, narrativeCampaign.miniGameCompleted == false {
            let slot: Int
            switch miniGame {
            case .trace, .erase:
                slot = narrativeCampaign.miniGameProgress
            case .melody:
                slot = [1, 3, 0, 2][narrativeCampaign.miniGameProgress]
            }
            performNarrativeMiniGameAction(slot)
            developerPlaytestLog.append("INPUT \(moment.id) slot=\(slot)")
            recordPlaytestRoute(actor: "开发者自动游玩", input: "微互动 \(moment.id) slot \(slot)", beforeState: beforeState, friction: friction)
        } else if let choice = moment.choices.first {
            advanceNarrative(choice.id)
            developerPlaytestLog.append("ADVANCE \(moment.id) -> \(choice.id)")
            recordPlaytestRoute(actor: "开发者自动游玩", input: "选择 \(choice.id)", beforeState: beforeState, friction: friction)
        }
    }

    private func developerMoveTowardNarrativeHotspot(_ hotspot: NarrativeHotspot) {
        let exploration = narrativeCampaign.exploration
        if hypot(exploration.positionX - hotspot.x, exploration.positionZ - hotspot.z) <= hotspot.radius {
            _ = interactNarrativeHotspot()
            return
        }
        let dx = hotspot.x - exploration.positionX
        let dz = hotspot.z - exploration.positionZ
        narrativeCampaign.exploration.yaw = atan2(-dx, -dz)
        for _ in 0..<8 {
            moveNarrativeExploration(forward: 1, strafe: 0, deltaTime: 0.05)
        }
        developerPlaytestLog.append("MOVE action=\(hotspot.id) x=\(String(format: "%.1f", narrativeCampaign.exploration.positionX)) z=\(String(format: "%.1f", narrativeCampaign.exploration.positionZ))")
    }

    func startDeveloperAutoplay(stepDelay: Duration = .milliseconds(420)) {
        developerAutoplayTask?.cancel()
        developerPlaytestLog = []
        playtestRouteTranscript = []
        developerExploredChapters = []
        developerPlaytestStatus = "运行中"
        isDeveloperPanelPresented = true
        developerAutoplayTask = Task { @MainActor [weak self] in
            guard let self else { return }
            startFullNarrativeCampaign()
            mouseLookEnabled = false
            developerPlaytestLog.append("START streamlined six-chapter narrative")
            while narrativeCampaign.isActive && narrativeCampaign.isComplete == false {
                guard Task.isCancelled == false else { return }
                developerAdvanceOneStep()
                try? await Task.sleep(for: stepDelay)
            }
            guard Task.isCancelled == false else { return }
            developerPlaytestStatus = narrativeCampaign.isComplete ? "通过：六章完成" : "中止"
            developerPlaytestLog.append("END complete=\(narrativeCampaign.isComplete)")
            developerAutoplayTask = nil
        }
    }

    private func resolveDeveloperAutoplayEventIfNeeded() {
        guard case .event(let event) = gameState,
              let choice = autonomousChoice(for: event) else { return }
        developerPlaytestLog.append("EVENT \(event.title) -> \(choice.title)")
        resolveEventChoice(choice)
    }

    func stopDeveloperAutoplay() {
        developerAutoplayTask?.cancel()
        developerAutoplayTask = nil
        if developerPlaytestStatus == "运行中" { developerPlaytestStatus = "已停止" }
    }

    var autonomousPlaySummary: String {
        "\(autonomousPlayStatus) · \(autonomousPlayLastDecision)"
    }

    var currentSensorySoundscape: SensorySoundscape {
        SensorySoundscape.derive(
            from: audioCues,
            teacherNear: teacher.isNearPlayer,
            allowsWhispering: settings.allowsWhispering
        )
    }

    private var currentSensoryPeerCueForDecision: SensoryPeerCue? {
        sensoryPeerCue ?? SensoryPeerCue.derive(
            from: currentSensorySoundscape,
            classmates: classmates,
            playerSupport: player.support,
            allowsWhispering: settings.allowsWhispering
        )
    }

    func toggleAutonomousPlay() {
        if isAutonomousPlayEnabled {
            stopAutonomousPlay(reason: "玩家接管")
        } else {
            startAutonomousPlay()
        }
    }

    func startAutonomousPlay(stepDelay: Duration = .milliseconds(620)) {
        autonomousPlayTask?.cancel()
        autonomousPlayStepCount = 0
        playtestRouteTranscript = []
        isAutonomousPlayEnabled = true
        autonomousPlayStatus = "自主游玩中"
        autonomousPlayLastDecision = "准备进入苏念路线"
        mouseLookEnabled = false
        if case .menu = gameState {
            startFullNarrativeCampaign()
        }
        autonomousPlayTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while self.isAutonomousPlayEnabled && Task.isCancelled == false {
                if let reason = self.autonomousPlayCompletionReason {
                    self.stopAutonomousPlay(reason: reason)
                    return
                }
                let didAct = self.autonomousPlayOneStep()
                if didAct == false {
                    self.stopAutonomousPlay(reason: "等待玩家接管")
                    return
                }
                try? await Task.sleep(for: stepDelay)
            }
        }
    }

    func stopAutonomousPlay(reason: String = "已停止") {
        autonomousPlayTask?.cancel()
        autonomousPlayTask = nil
        isAutonomousPlayEnabled = false
        autonomousPlayStatus = reason
        mouseLookEnabled = true
    }

    @discardableResult
    func autonomousPlayOneStep() -> Bool {
        let beforeState = playtestRouteStateSummary
        let friction = playtestFrictionSummary
        func finish(_ didAct: Bool) -> Bool {
            recordPlaytestRoute(actor: "自主游玩", input: autonomousPlayLastDecision, beforeState: beforeState, friction: friction)
            return didAct
        }

        if let reason = autonomousPlayCompletionReason {
            recordAutonomousDecision(reason)
            if isAutonomousPlayEnabled {
                stopAutonomousPlay(reason: reason)
            }
            return finish(false)
        }

        autonomousPlayStepCount += 1
        if featuredMonologue != nil {
            dismissFeaturedMonologue()
            recordAutonomousDecision("收起内心独白，继续观察")
            return finish(true)
        }

        if case .menu = gameState {
            startFullNarrativeCampaign()
            mouseLookEnabled = false
            recordAutonomousDecision("从第一章开始完整路线")
            return finish(true)
        }

        if case .event(let event) = gameState {
            guard let choice = autonomousChoice(for: event) else {
                recordAutonomousDecision("事件等待人工选择")
                return finish(false)
            }
            recordAutonomousDecision("事件选择：\(choice.title)")
            resolveEventChoice(choice)
            return finish(true)
        }

        guard case .playing = gameState else {
            recordAutonomousDecision("当前状态无法自动推进")
            return finish(false)
        }

        if isPrologueActive {
            return finish(autonomousPlayPrologueStep())
        }
        if narrativeCampaign.isActive {
            return finish(autonomousPlayNarrativeStep())
        }
        if activeChapter == .silentClassroom, activeRole.isTeacher == false {
            return finish(autonomousPlayChapterOneStep())
        }

        recordAutonomousDecision("没有可用的自主路线")
        return finish(false)
    }

    private var autonomousPlayCompletionReason: String? {
        if narrativeCampaign.isActive && narrativeCampaign.isComplete {
            return "通过：六章完成"
        }
        if case .ending = gameState {
            return "到达结算"
        }
        return nil
    }

    private func recordAutonomousDecision(_ decision: String) {
        autonomousPlayStatus = isAutonomousPlayEnabled ? "自主游玩中" : "单步自主"
        autonomousPlayLastDecision = decision
    }

    @discardableResult
    private func autonomousPlayPrologueStep() -> Bool {
        let beat = prologueCurrentBeat
        switch beat {
        case .settleBreath:
            recordAutonomousDecision("序章：先把呼吸放慢")
            execute(.breathe)
        case .accessibility:
            recordAutonomousDecision("序章：确认体验设置")
            acknowledgeAccessibilityTutorial(openSettings: false)
        default:
            recordAutonomousDecision("序章：推进 \(beat.currentGoal)")
            completePrologueBeat(beat, source: .fallback)
        }
        return true
    }

    @discardableResult
    private func autonomousPlayChapterOneStep() -> Bool {
        let soundscape = currentSensorySoundscape
        let peerCue = currentSensoryPeerCueForDecision
        let shouldDeescalateForPeerWarning = chapterOneStep == .approachLinChe || chapterOneStep == .inspectNote || chapterOneStep == .followLinChe
        let isDeskExposure = chapterOneStep == .inspectNote && cameraPose == .desk
        let soundscapeAlreadyExplainsExposure = soundscape.riskPressure > 0.72 && soundscape.supportSignal < 0.36 && isDeskExposure == false
        let currentLocalizationTargetPose: CameraPose?
        switch chapterOneStep {
        case .observeLinChe:
            currentLocalizationTargetPose = .left
        case .locateHiddenSound:
            currentLocalizationTargetPose = .right
        case .inspectNote:
            currentLocalizationTargetPose = .desk
        case .regulateSelf, .approachLinChe, .followLinChe, .completed:
            currentLocalizationTargetPose = nil
        }
        let isActivelyLocalizingCurrentObjective = currentLocalizationTargetPose == cameraPose
            && chapterOneLocatedAudioSteps.contains(chapterOneStep) == false
        if let peerCue,
           peerCue.tone == .warning,
           shouldDeescalateForPeerWarning,
           cameraPose != .forward,
           soundscapeAlreadyExplainsExposure == false,
           isActivelyLocalizingCurrentObjective == false {
            sensoryPeerCue = peerCue
            recordAutonomousDecision("听见\(peerCue.classmateName)提醒，先把视线收回前方")
            setPose(.forward)
            return true
        }
        if let peerCue, peerCue.tone == .body, chapterOneStep != .followLinChe, player.psychicEnergy < 82 {
            sensoryPeerCue = peerCue
            recordAutonomousDecision("听见\(peerCue.classmateName)注意到身体状态，先稳定呼吸")
            execute(.breathe)
            return true
        }
        if soundscape.riskPressure > 0.72,
           soundscape.supportSignal < 0.36,
           cameraPose != .forward,
           isActivelyLocalizingCurrentObjective == false,
           chapterOneStep != .locateHiddenSound {
            recordAutonomousDecision("声场风险压近，先收回正面")
            setPose(.forward)
            return true
        }
        if soundscape.bodyAlarm > 0.58, player.psychicEnergy < 72 {
            recordAutonomousDecision("身体声音变大，先把呼吸放慢")
            execute(.breathe)
            return true
        }

        if player.stress > 78 || player.visualAttention < 18 || player.psychicEnergy < 18 {
            recordAutonomousDecision("苏念先稳定自己")
            execute(.breathe)
            return true
        }

        switch chapterOneStep {
        case .observeLinChe:
            if cameraPose != .left {
                recordAutonomousDecision("看向左侧，确认林澈")
                setPose(.left)
            } else if chapterOneLocatedAudioSteps.contains(.observeLinChe) == false {
                recordAutonomousDecision("停在左侧，听清翻书声")
                completeCurrentSpatialAudioDwellIfPossible()
            } else {
                recordAutonomousDecision("观察林澈的书页")
                execute(.observe)
            }
        case .locateHiddenSound:
            if cameraPose != .right {
                recordAutonomousDecision("转向右侧，听见鼻息")
                setPose(.right)
            } else if chapterOneLocatedAudioSteps.contains(.locateHiddenSound) == false {
                recordAutonomousDecision("停在右侧，听清鼻息方向")
                completeCurrentSpatialAudioDwellIfPossible()
            } else {
                recordAutonomousDecision("观察右侧隐藏声音")
                execute(.observe)
            }
        case .regulateSelf:
            if player.thirst > 42 && player.waterCup >= 25 {
                recordAutonomousDecision("喝水稳定身体")
                execute(.drink)
            } else {
                recordAutonomousDecision("深呼吸稳定身体")
                execute(.breathe)
            }
        case .approachLinChe:
            if let peerCue, peerCue.tone == .support {
                sensoryPeerCue = peerCue
                let action: PlayerAction = settings.allowsWhispering ? .talk : .note
                recordAutonomousDecision("顺着\(peerCue.classmateName)的支援信号，\(action == .talk ? "低声问候林澈" : "用纸条靠近林澈")")
                execute(action)
            } else {
                recordAutonomousDecision("低声问候林澈")
                execute(.talk)
            }
        case .inspectNote:
            if cameraPose != .desk {
                recordAutonomousDecision("低头确认纸条")
                setPose(.desk)
            } else if chapterOneLocatedAudioSteps.contains(.inspectNote) == false {
                recordAutonomousDecision("停在桌面，听清纸边位置")
                completeCurrentSpatialAudioDwellIfPossible()
            } else {
                recordAutonomousDecision("观察桌边纸条")
                execute(.observe)
            }
        case .followLinChe:
            recordAutonomousDecision("起身跟上林澈")
            execute(.leaveSeat)
        case .completed:
            recordAutonomousDecision("第一章已完成")
            return false
        }
        return true
    }

    @discardableResult
    private func autonomousPlayNarrativeStep() -> Bool {
        guard narrativeCampaign.isComplete == false else {
            recordAutonomousDecision("六章路线完成")
            return false
        }
        if narrativeCampaign.shouldPresentRiskEducationCard {
            recordAutonomousDecision("阅读并收起风险确认卡")
            dismissNarrativeRiskEducationCard()
            return true
        }

        let moment = narrativeCampaign.currentMoment
        let validChoiceIDs = Set(moment.choices.map(\.id))
        let preferredChoiceID = autonomousNarrativeChoiceID(for: moment)

        if narrativeCampaign.currentMomentActionReady == false {
            let requiredHotspots = narrativeCampaign.requiredInteractionHotspots
            if let preferredChoiceID,
               let hotspot = requiredHotspots.first(where: { $0.choiceID == preferredChoiceID }) {
                return autonomousMoveTowardNarrativeHotspot(hotspot)
            }
            if let hotspot = requiredHotspots.first {
                return autonomousMoveTowardNarrativeHotspot(hotspot)
            }
        }

        if narrativeCampaign.currentMomentActionReady == false,
           let hotspot = narrativeCampaign.interactionHotspots.first(where: { $0.id == "handoff.teacher" }) {
            return autonomousMoveTowardNarrativeHotspot(hotspot)
        }

        if let miniGame = moment.miniGame,
           narrativeCampaign.miniGameCompleted == false,
           narrativeCampaign.currentMomentActionReady {
            let slot: Int
            switch miniGame {
            case .trace:
                slot = narrativeCampaign.miniGameProgress
            case .melody:
                slot = [1, 3, 0, 2][narrativeCampaign.miniGameProgress]
            case .erase:
                slot = [5, 2, 0, 4, 1, 3][narrativeCampaign.miniGameProgress]
            }
            recordAutonomousDecision("微互动 \(moment.title)：节点 \(slot)")
            performNarrativeMiniGameAction(slot)
            return true
        }

        if let preferredChoiceID,
           let hotspot = narrativeCampaign.interactionHotspots.first(where: { $0.choiceID == preferredChoiceID }) {
            return autonomousMoveTowardNarrativeHotspot(hotspot)
        }

        if let hotspot = narrativeCampaign.interactionHotspots.first(where: {
            guard let choiceID = $0.choiceID else { return false }
            return validChoiceIDs.contains(choiceID)
        }) {
            return autonomousMoveTowardNarrativeHotspot(hotspot)
        }

        if narrativeCampaign.explorationReady == false,
           let hotspot = NarrativeHotspot.all(for: narrativeCampaign.chapter).first {
            return autonomousMoveTowardNarrativeHotspot(hotspot)
        }

        if let miniGame = moment.miniGame, narrativeCampaign.miniGameCompleted == false {
            let slot: Int
            switch miniGame {
            case .trace:
                slot = narrativeCampaign.miniGameProgress
            case .melody:
                slot = [1, 3, 0, 2][narrativeCampaign.miniGameProgress]
            case .erase:
                slot = [5, 2, 0, 4, 1, 3][narrativeCampaign.miniGameProgress]
            }
            recordAutonomousDecision("微互动 \(moment.title)：节点 \(slot)")
            performNarrativeMiniGameAction(slot)
            return true
        }

        guard let choiceID = preferredChoiceID ?? moment.choices.first?.id else {
            recordAutonomousDecision("当前剧情没有可选回应")
            return false
        }
        recordAutonomousDecision("剧情选择：\(choiceID)")
        advanceNarrative(choiceID)
        return true
    }

    @discardableResult
    private func autonomousMoveTowardNarrativeHotspot(_ hotspot: NarrativeHotspot) -> Bool {
        let exploration = narrativeCampaign.exploration
        if hypot(exploration.positionX - hotspot.x, exploration.positionZ - hotspot.z) <= hotspot.radius {
            recordAutonomousDecision("确认热点：\(hotspot.title)")
            _ = interactNarrativeHotspot()
            if let choiceID = hotspot.choiceID {
                autonomousPlayLastDecision = "热点选择：\(choiceID)"
            }
            return true
        }

        let dx = hotspot.x - exploration.positionX
        let dz = hotspot.z - exploration.positionZ
        narrativeCampaign.exploration.yaw = atan2(-dx, -dz)
        for _ in 0..<10 {
            moveNarrativeExploration(forward: 1, strafe: 0, deltaTime: 0.05)
        }
        recordAutonomousDecision("走向热点：\(hotspot.title)")
        return true
    }

    private func autonomousNarrativeChoiceID(for moment: NarrativeMoment) -> String? {
        if moment.id.hasPrefix("4.listen.0") { return "dialogue.listen" }
        if moment.id.hasPrefix("4.listen.1") { return "dialogue.accompany" }
        if moment.id.hasPrefix("4.listen.2") { return "dialogue.listen" }
        if moment.id.hasPrefix("4.listen.3") { return "dialogue.accompany" }

        switch moment.id {
        case "1.regulate":
            return player.thirst > 42 && player.waterCup >= 25 ? "water" : "breathe"
        case "1.ask":
            return "stay"
        case "2.listen":
            return "invite"
        case "3.companion":
            return "xu"
        case "4.risk":
            return "askSafety"
        case "4.contact":
            return "contactAdult"
        case "4.handoff":
            return "followAdultPlan"
        case "5.rumor":
            return "privacy"
        case "5.message":
            return "message"
        case "6.share":
            return "share"
        default:
            return moment.choices.first?.id
        }
    }

    private func autonomousChoice(for event: ActiveEvent) -> EventChoice? {
        let preferredIDs: [String]
        switch event.kind {
        case .linCheDialogue:
            preferredIDs = ["chapter1_linche_listen", "chapter1_linche_wait", "chapter1_linche_mask"]
        case .noteDrop:
            preferredIDs = ["chapter1_read_note"]
        case .discovery:
            preferredIDs = ["explain_tired", "accept_warning", "stay_silent"]
        case .teacherConcern:
            preferredIDs = ["thank_teacher", "take_break", "refuse_care"]
        case .playerBreakdown:
            preferredIDs = ["breathe_now", "ask_deskmate", "push_through"]
        case .classmateCrying:
            preferredIDs = ["pass_tissue", "comfort_classmate", "tell_teacher"]
        case .supportOffer:
            preferredIDs = ["accept_support", "smile_only", "reject_support"]
        case .powerOutage:
            preferredIDs = ["rest_eyes", "look_around", "check_phone_dark"]
        case .leaveSeatRequest:
            preferredIDs = ["go_washroom", "stretch_only", "sit_back_down"]
        case .loneliness:
            preferredIDs = ["loneliness_breathe", "loneliness_note", "loneliness_mask"]
        case .phoneNotification:
            preferredIDs = ["ignore_notification", "ask_mate_cover", "read_notification"]
        case .broadcast:
            preferredIDs = ["breathe_broadcast", "sit_straight_broadcast", "observe_broadcast"]
        case .knockOnDoor:
            preferredIDs = ["listen_knock", "ignore_knock", "turn_to_door"]
        case .classmateHelpRequest:
            preferredIDs = ["quiet_help_classmate", "share_breath_classmate", "chapter1_wait", "chapter1_teacher"]
        case .classmateReport:
            preferredIDs = ["admit_to_reporter", "stop_and_reset", "pressure_reporter"]
        case .memoryTrust:
            preferredIDs = ["return_memory_trust", "accept_memory_trust", "avoid_memory_trust"]
        case .memorySuspicion:
            preferredIDs = ["repair_memory_suspicion", "hide_from_memory_suspicion", "challenge_memory_suspicion"]
        }
        for id in preferredIDs {
            if let choice = event.choices.first(where: { $0.id == id }) {
                return choice
            }
        }
        return event.choices.first
    }

    private struct NarrativeLoadOutcome {
        let campaign: NarrativeCampaign
        let chapterOneProgress: NarrativeChapterOneProgress?
        let accessibilityPreferences: AccessibilityPreferences
        let scenePresentation: ScenePresentationState
        let revision: Int
        let notice: String?
        let needsMigrationWrite: Bool
    }

    private func saveNarrativeCampaign() {
        let candidate = NarrativeSave(
            saveRevision: narrativeSaveRevision + 1,
            campaign: narrativeCampaign,
            chapterOneProgress: makeChapterOneProgressSnapshot(),
            accessibilityPreferences: accessibilityPreferences,
            scenePresentation: scenePresentation
        )
        guard candidate.validationFailure == nil,
              let data = try? JSONEncoder().encode(candidate),
              let roundTrip = try? JSONDecoder().decode(NarrativeSave.self, from: data),
              roundTrip.validationFailure == nil else {
            if let failure = candidate.validationFailure {
                developerPlaytestLog.append("SAVE_BLOCKED \(failure.rawValue)")
            }
            return
        }

        storage.set(data, forKey: NarrativeSaveStoreKeys.current)
        storage.set(data, forKey: NarrativeSaveStoreKeys.lastValid)
        narrativeSaveRevision = candidate.saveRevision

        if let legacyData = try? JSONEncoder().encode(narrativeCampaign) {
            storage.set(legacyData, forKey: NarrativeSaveStoreKeys.legacyCampaign)
        }
    }

    private func loadNarrativeSave() -> NarrativeLoadOutcome {
        let currentDecode = loadNarrativeSaveSlot(forKey: NarrativeSaveStoreKeys.current)
        if case .valid(let save) = currentDecode {
            return NarrativeLoadOutcome(
                campaign: save.campaign,
                chapterOneProgress: save.chapterOneProgress,
                accessibilityPreferences: save.accessibilityPreferences,
                scenePresentation: save.scenePresentation,
                revision: save.saveRevision,
                notice: nil,
                needsMigrationWrite: false
            )
        }

        let lastValidDecode = loadNarrativeSaveSlot(forKey: NarrativeSaveStoreKeys.lastValid)
        if case .valid(let save) = lastValidDecode {
            let reason = currentDecode.failureText ?? "当前槽缺失"
            return NarrativeLoadOutcome(
                campaign: save.campaign,
                chapterOneProgress: save.chapterOneProgress,
                accessibilityPreferences: save.accessibilityPreferences,
                scenePresentation: save.scenePresentation,
                revision: save.saveRevision,
                notice: "已从稳定检查点 \(save.checkpointID) 恢复：\(reason)",
                needsMigrationWrite: false
            )
        }

        if let data = storage.data(forKey: NarrativeSaveStoreKeys.legacyCampaign),
           let legacy = try? JSONDecoder().decode(NarrativeCampaign.self, from: data) {
            let save = NarrativeSave(saveRevision: 0, campaign: legacy, accessibilityPreferences: accessibilityPreferences)
            return NarrativeLoadOutcome(
                campaign: save.campaign,
                chapterOneProgress: save.chapterOneProgress,
                accessibilityPreferences: accessibilityPreferences,
                scenePresentation: save.scenePresentation,
                revision: 0,
                notice: "已迁移旧版叙事存档到双槽检查点",
                needsMigrationWrite: true
            )
        }

        return NarrativeLoadOutcome(
            campaign: NarrativeCampaign(),
            chapterOneProgress: nil,
            accessibilityPreferences: accessibilityPreferences,
            scenePresentation: ScenePresentationState(),
            revision: 0,
            notice: nil,
            needsMigrationWrite: false
        )
    }

    private enum NarrativeSaveSlotDecode {
        case missing
        case invalidData
        case invalidSave(NarrativeSaveValidationFailure)
        case valid(NarrativeSave)

        var failureText: String? {
            switch self {
            case .missing:
                return nil
            case .invalidData:
                return "当前槽无法解码"
            case .invalidSave(let failure):
                return failure.recoveryText
            case .valid:
                return nil
            }
        }
    }

    private func loadNarrativeSaveSlot(forKey key: String) -> NarrativeSaveSlotDecode {
        guard let data = storage.data(forKey: key) else {
            return .missing
        }
        guard let save = try? JSONDecoder().decode(NarrativeSave.self, from: data) else {
            return .invalidData
        }
        if let failure = save.validationFailure {
            return .invalidSave(failure)
        }
        return .valid(save)
    }

    private func restoreNarrativeSessionIfNeeded() {
        if isFullNarrativeRun, narrativeCampaign.isActive == false {
            gameState = .playing
            activeRole = .regularStudent
            viewMode = .student
            mouseLookEnabled = true
            transitionAudioScene(to: .classroom)
            message = narrativeSaveRecoveryNotice ?? message
            developerPlaytestLog.append("SAVE_RESTORE \(NarrativeSave.checkpointID(for: narrativeCampaign, chapterOneProgress: makeChapterOneProgressSnapshot()))")
            return
        }
        guard narrativeCampaign.isActive else { return }
        gameState = .playing
        isFullNarrativeRun = false
        activeRole = .regularStudent
        viewMode = .student
        player.posture = .seated
        mouseLookEnabled = false
        transitionAudioScene(to: narrativeCampaign.chapter)
        message = narrativeSaveRecoveryNotice ?? (
            narrativeCampaign.isComplete
                ? "你走过了这一晚。支持没有结束，只是从一个人变成了更多人。"
                : narrativeCampaign.currentMoment.goal
        )
        if let notice = narrativeSaveRecoveryNotice {
            developerPlaytestLog.append("SAVE_RECOVERY \(notice)")
        } else {
            developerPlaytestLog.append("SAVE_RESTORE \(NarrativeSave.checkpointID(for: narrativeCampaign))")
        }
    }

    private func makeChapterOneProgressSnapshot() -> NarrativeChapterOneProgress? {
        guard isFullNarrativeRun, narrativeCampaign.isActive == false else { return nil }
        return NarrativeChapterOneProgress(
            isFullNarrativeRun: isFullNarrativeRun,
            currentTurn: currentTurn,
            chapterOneStep: chapterOneStep,
            chapterClues: chapterClues,
            cameraPose: cameraPose,
            player: player,
            message: message,
            chapterOneDecision: chapterOneDecision,
            hasPresentedChapterOneDecision: hasPresentedChapterOneDecision,
            chapterOneLinCheDialogueCue: chapterOneLinCheDialogueCue,
            chapterOneNoteDropCue: chapterOneNoteDropCue,
            linChePerformanceCue: linChePerformanceCue,
            completedChapterOneBeatIDs: completedChapterOneBeatIDs
        )
    }

    private func restoreChapterOneProgress(_ progress: NarrativeChapterOneProgress) {
        guard progress.isActive else { return }
        isFullNarrativeRun = true
        isPrologueActive = false
        prologuePauseReasons = []
        gameState = .playing
        currentTurn = max(1, progress.currentTurn)
        activeChapter = .silentClassroom
        chapterOneStep = progress.chapterOneStep
        chapterClues = progress.chapterClues
        chapterOneLocatedAudioSteps = Set(progress.chapterClues.compactMap(Self.locatedAudioStep(for:)))
        cameraPose = progress.cameraPose
        player = progress.player
        player.posture = .seated
        activeRole = .regularStudent
        selectedRole = .regularStudent
        viewMode = .student
        hasPresentedChapterOneDecision = progress.hasPresentedChapterOneDecision
        chapterOneDecision = progress.chapterOneDecision
        chapterOneLinCheDialogueCue = progress.chapterOneLinCheDialogueCue
        chapterOneNoteDropCue = progress.chapterOneNoteDropCue
        linChePerformanceCue = progress.linChePerformanceCue ?? LinChePerformanceCue.derive(
            step: progress.chapterOneStep,
            noteDropCue: progress.chapterOneNoteDropCue
        )
        completedChapterOneBeatIDs = progress.completedChapterOneBeatIDs ?? []
        narrativeCampaign = NarrativeCampaign()
        activeNarrativeMicroGame = nil
        narrativeBoundaryDwellSeconds = 0
        narrativeBoundaryPullbackCount = 0
        narrativeMomentElapsedSeconds = 0
        timedNarrativeMomentID = ""
        seatedPosePressureFeedback = nil
        lastSeatedPosePressureCueSignature = ""
        teacherPatrolReadout = nil
        lastTeacherPatrolReadoutCueSignature = ""
        mouseLookEnabled = true
        mouseLookCaptured = false
        message = narrativeSaveRecoveryNotice ?? progress.message
        transitionAudioScene(to: .classroom)
    }

    private func presentScenePresentation(for chapter: NarrativeChapter, subtitle: String? = nil) {
        scenePresentationTask?.cancel()
        let now = Date()
        let next = ScenePresentationState(
            chapter: chapter,
            title: chapter.title,
            subtitle: subtitle ?? chapter.sceneSubtitle,
            transition: chapter.sceneTransition,
            phase: .prepare,
            startedAt: now,
            phaseStartedAt: now
        )
        scenePresentation = next
        transitionAudioScene(to: chapter)
        let token = next.token
        scenePresentationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.scenePresentationPrepareDuration)
            guard Task.isCancelled == false, self.scenePresentation.token == token else { return }
            self.scenePresentation.phase = .commit
            self.scenePresentation.phaseStartedAt = .now

            try? await Task.sleep(for: self.scenePresentationCommitDuration)
            guard Task.isCancelled == false, self.scenePresentation.token == token else { return }
            self.scenePresentation.phase = .cleanup
            self.scenePresentation.phaseStartedAt = .now

            try? await Task.sleep(for: self.scenePresentationCleanupDuration)
            guard Task.isCancelled == false, self.scenePresentation.token == token else { return }
            self.clearScenePresentation()
        }
    }

    private func clearScenePresentation() {
        scenePresentationTask?.cancel()
        scenePresentationTask = nil
        scenePresentation = ScenePresentationState()
    }

    private func transitionAudioScene(to chapter: NarrativeChapter) {
        let duration = accessibilityPreferences.reduceMotion ? 0.3 : 1.8
        audio.transitionScene(to: chapter.audioSceneID, duration: duration)
        syncNarrativeAudioDynamics()
    }

    private func syncNarrativeAudioDynamics() {
        audio.updateNarrativeDynamics(NarrativeAudioDynamics.derive(from: narrativeCampaign))
    }

    var hasContinuableNarrativeSave: Bool {
        isFullNarrativeRun || narrativeCampaign.isActive
    }

    var narrativeSaveTitle: String {
        if isFullNarrativeRun {
            return "第一章 · \(chapterOneStep.objective)"
        }
        if narrativeCampaign.isActive {
            return narrativeCampaign.isComplete ? "第六章 · 已完成" : narrativeCampaign.chapter.title
        }
        return "暂无旅程存档"
    }

    var narrativeSaveDetail: String {
        if let notice = narrativeSaveRecoveryNotice {
            return notice
        }
        if isFullNarrativeRun {
            let clueText = chapterClues.isEmpty ? "还没有记录线索" : "已记录 \(chapterClues.count) 条线索"
            return "\(clueText) · \(chapterOneStep.guidance)"
        }
        if narrativeCampaign.isActive {
            if narrativeCampaign.isComplete {
                return "旅程已经完成，可以回看终章支持网络。"
            }
            return "\(narrativeCampaign.progressText) · \(narrativeCampaign.currentMoment.goal)"
        }
        return "从序章或完整六章叙事开始后，这里会显示最近的稳定检查点。"
    }

    func continueNarrativeSaveFromMenu() {
        guard hasContinuableNarrativeSave else { return }
        narrativePauseReasons.removeAll()
        activeNarrativeMicroGame = nil
        gameState = .playing
        if isFullNarrativeRun {
            activeRole = .regularStudent
            viewMode = .student
            player.posture = .seated
            mouseLookEnabled = true
            transitionAudioScene(to: .classroom)
            message = narrativeSaveRecoveryNotice ?? narrativeSaveDetail
            return
        }
        isFullNarrativeRun = false
        activeRole = .regularStudent
        viewMode = .student
        player.posture = .seated
        mouseLookEnabled = false
        transitionAudioScene(to: narrativeCampaign.chapter)
        message = narrativeSaveRecoveryNotice ?? (
            narrativeCampaign.isComplete
                ? "你走过了这一晚。支持没有结束，只是从一个人变成了更多人。"
                : narrativeCampaign.currentMoment.goal
        )
    }

    func pauseNarrativeToMenu() {
        guard hasContinuableNarrativeSave else {
            returnToMenuForNewGame()
            return
        }
        saveNarrativeCampaign()
        narrativePauseReasons.removeAll()
        activeNarrativeMicroGame = nil
        clearScenePresentation()
        stopPrologueTimer()
        isPrologueActive = false
        prologuePauseReasons = []
        narrativePauseReasons = []
        activeNarrativeMicroGame = nil
        freeRoamTimer?.invalidate()
        freeRoamTimer = nil
        returnToSeatTask?.cancel()
        returnToSeatTask = nil
        isReturningToSeat = false
        returnToSeatStartedAt = .distantPast
        pendingSprintHunger = 0
        activeNarrativeMicroGame = nil
        narrativePauseReasons = []
        freeRoamPausedAt = nil
        freeRoam = StudentFreeRoamState()
        gameState = .menu
        currentPhase = .observation
        mouseLookCaptured = false
        mouseLookEnabled = true
        message = "已回到主菜单。旅程保留在最近的稳定检查点。"
    }

    func returnToMenuForNewGame() {
        if isAutonomousPlayEnabled {
            stopAutonomousPlay(reason: "返回菜单")
        }
        clearScenePresentation()
        stopPrologueTimer()
        isPrologueActive = false
        prologuePauseReasons = []
        freeRoamTimer?.invalidate()
        freeRoamTimer = nil
        returnToSeatTask?.cancel()
        returnToSeatTask = nil
        isReturningToSeat = false
        returnToSeatStartedAt = .distantPast
        pendingSprintHunger = 0
        freeRoamPausedAt = nil
        freeRoam = StudentFreeRoamState()
        audio.stop()
        gameState = .menu
        currentPhase = .observation
        currentTurn = 0
        cameraPose = .forward
        studentLookYaw = 0
        studentLookPitch = 0
        mouseLookEnabled = true
        mouseLookCaptured = false
        viewMode = .student
        eventLog = []
        audioCues = []
        directionalSubtitleEvents = []
        monologues = []
        featuredMonologue = nil
        monologueDismissTask?.cancel()
        chapterClues = []
        hasPresentedChapterOneDecision = false
        chapterOneDecision = ""
        lastAnomalyMonologueTurn = [:]
        activeBreakdownRecoverySteps = []
        completedBreakdownRecoverySteps = []
        breakdownRecoverySummary = ""
        replay = []
        selectedReplayIndex = 0
        message = "请选择角色和制度参数，开始新的一晚。"
        isFullNarrativeRun = false
        narrativeCampaign.isActive = false
        isTeacherTruthRunActive = false
        saveNarrativeCampaign()
    }

    var prologueCurrentBeat: PrologueBeatID { prologueState.currentBeat }

    var prologueAutoAdvanceSecondsRemaining: Int? {
        guard let duration = prologueCurrentBeat.autoAdvanceDuration,
              prologueCurrentBeat != .gateArrival else { return nil }
        return max(0, Int(ceil(duration - prologueBeatElapsed)))
    }

    var canCompleteCurrentPrologueEarly: Bool {
        isPrologueActive && isPrologueTutorialPresented == false && prologuePaused == false
            && prologueCurrentBeat != .lookDownHall
            && prologueCurrentBeat.autoAdvanceDuration != nil
            && prologueCurrentBeat != .gateArrival
            && prologueActionReady
    }

    private func startPrologueTimer() {
        prologueTimer?.invalidate()
        prologueTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickPrologue(delta: 0.1) }
        }
    }

    private func stopPrologueTimer() {
        prologueTimer?.invalidate()
        prologueTimer = nil
        prologueDwell = 0
    }

    func tickPrologue(delta: TimeInterval) {
        guard isPrologueActive, prologuePaused == false, gameState == .playing else { return }
        prologueBeatElapsed += delta
        let beat = prologueState.currentBeat
        if beat == .studyHallRhythm { updateStudyHallPerformance() }
        if let duration = beat.autoAdvanceDuration, prologueBeatElapsed >= duration {
            let source: PrologueCompletionSource = (beat == .gateArrival || beat == .studyHallRhythm || beat == .bellBeforeClass)
                ? .performance
                : .fallback
            completePrologueBeat(beat, source: source)
        }
    }

    private func updateStudyHallPerformance() {
        let nextPhase: Int
        switch prologueBeatElapsed {
        case ..<6: nextPhase = 0
        case ..<12: nextPhase = 1
        case ..<19: nextPhase = 2
        case ..<26: nextPhase = 3
        default: nextPhase = 4
        }
        guard nextPhase != prologuePerformancePhase else { return }
        prologuePerformancePhase = nextPhase
        switch nextPhase {
        case 1:
            teacher.positionIndex = 0
            message = "方老师把手机扣在讲台边，确认最后一排的座位。她没有说话，只在名单上停了一下。"
            addAudioCue(.paper, direction: "讲台前方", intensity: 0.32, note: "名单翻过一页。")
        case 2:
            frontDoorOpen = false
            message = "周予安核对完座位，把门轻轻带上。许栀弯腰捡起一支笔，递回旁边。"
            addAudioCue(.knock, direction: "前门", intensity: 0.34, note: "门轴声和一句很轻的“给你”。")
        case 3:
            message = "有人写题，有人趴了一下又坐直。耳机被收进抽屉，咳嗽声压得很低。"
            addAudioCue(.chair, direction: "教室四周", intensity: 0.38, note: "椅子、抽屉和笔尖构成晚自习开始前的声音。")
        case 4:
            message = "苏念从左到右扫过教室，没有在任何人身上停太久。林澈在左边坐下，把书翻到其中一页。"
            addAudioCue(.paper, direction: "左侧近处", intensity: 0.3, note: "纸张摩擦后，环境声重新占满教室。")
        default:
            break
        }
    }

    func updatePrologueDwell(delta: TimeInterval) {
        guard isPrologueActive, prologuePaused == false else { return }
        let beat = prologueState.currentBeat
        let matches = beat == .noticeLinChe && (cameraPose == .left || studentLookYaw > 0.42)
        prologueDwell = matches ? prologueDwell + delta : 0
        if matches && prologueDwell >= 1.0 {
            prologueActionReady = true
            message = "你已经认真看见了林澈的状态。按 C 可以提前结束这一步。"
        }
    }

    func updatePrologueLookExploration(isMoving: Bool, delta: TimeInterval) {
        guard isPrologueActive, prologuePaused == false,
              prologueCurrentBeat == .lookDownHall, isMoving else { return }
        prologueLookExplorationElapsed = min(5, prologueLookExplorationElapsed + delta)
        if prologueLookExplorationElapsed >= 5 {
            completePrologueBeat(.lookDownHall, source: .player)
        }
    }

    func completeCurrentPrologueEarly() {
        guard canCompleteCurrentPrologueEarly else { return }
        completePrologueBeat(prologueCurrentBeat, source: .player)
    }

    func confirmPrologueInteraction() {
        guard isPrologueActive, prologuePaused == false else { return }
        switch prologueState.currentBeat {
        case .placeWater:
            prologueActionReady = true
            message = "水杯已经放在手边。按 C 可以提前结束这一步，也可以继续留在这里。"
        case .accessibility:
            acknowledgeAccessibilityTutorial(openSettings: false)
        case .settleBreath:
            prologueActionReady = true
            message = "你完成了一次自我调整。按 C 可以提前结束这一步。"
        case .returnToSeat:
            confirmPrologueSeat()
        default:
            break
        }
    }

    @discardableResult
    func confirmPrologueSeat() -> Bool {
        guard isPrologueActive, prologuePaused == false,
              prologueCurrentBeat == .returnToSeat, freeRoam.isActive else { return false }
        guard hypot(freeRoam.positionX - (-0.6), freeRoam.positionZ - 1.65) <= 0.72 else {
            message = "还没有到自己的座位附近。"
            return false
        }
        freeRoam = StudentFreeRoamState()
        player.posture = .seated
        studentLookYaw = 0
        studentLookPitch = 0
        cameraPose = .forward
        prologueActionReady = true
        message = "你已经坐回自己的位置。按 C 可以提前结束这一步。"
        return true
    }

    func acknowledgeSettleBreathWithoutAction() {
        guard isPrologueActive, prologueState.currentBeat == .settleBreath else { return }
        prologueActionReady = true
        message = "你决定先安静地坐一会儿。按 C 可以提前结束这一步。"
    }

    func presentCurrentPrologueTutorial() {
        guard isPrologueActive, prologueCurrentBeat.tutorialStep != nil else { return }
        isPrologueTutorialPresented = true
        prologuePauseReasons.insert(.tutorial)
    }

    func dismissCurrentPrologueTutorial() {
        guard isPrologueTutorialPresented else { return }
        isPrologueTutorialPresented = false
        prologuePauseReasons.remove(.tutorial)
    }

    func toggleCurrentPrologueTutorial() {
        guard isPrologueActive, prologueCurrentBeat.tutorialStep != nil else { return }
        if isPrologueTutorialPresented == false {
            presentCurrentPrologueTutorial()
        }
    }

    func acknowledgeAccessibilityTutorial(openSettings: Bool) {
        guard isPrologueActive, prologueState.currentBeat == .accessibility else { return }
        if openSettings {
            isAccessibilityPanelPresented = true
            prologuePauseReasons.insert(.settings)
        } else {
            prologueState.accessibilityTutorialAcknowledged = true
            prologueActionReady = true
            message = "你已经确认了辅助设置。按 C 可以提前结束这一步。"
        }
    }

    func openAccessibilityPanel() {
        isAccessibilityPanelPresented = true
        if isPrologueActive {
            prologuePauseReasons.insert(.settings)
        } else if case .playing = gameState, isFullNarrativeRun || narrativeCampaign.isActive {
            narrativePauseReasons.insert(.settings)
        }
    }

    func closeAccessibilityPanel() {
        isAccessibilityPanelPresented = false
        prologuePauseReasons.remove(.settings)
        narrativePauseReasons.remove(.settings)
        saveAccessibilityPreferences()
        applyAccessibilityPreferences()
        if isPrologueActive, prologueState.currentBeat == .accessibility {
            prologueState.accessibilityTutorialAcknowledged = true
            prologueActionReady = true
            message = "辅助设置已确认。按 C 可以提前结束这一步。"
        }
    }

    func openNarrativePauseMenu() {
        guard hasContinuableNarrativeSave else { return }
        if isAutonomousPlayEnabled {
            stopAutonomousPlay(reason: "暂停叙事")
        }
        saveNarrativeCampaign()
        narrativePauseReasons.insert(.manual)
        isAccessibilityPanelPresented = false
        message = "叙事已暂停。设置、字幕和音量可以在这里调整。"
    }

    func resumeNarrativeFromPause() {
        narrativePauseReasons.remove(.manual)
    }

    func setProloguePaused(_ paused: Bool) {
        guard isPrologueActive else { return }
        if paused { prologuePauseReasons.insert(.manual) }
        else { prologuePauseReasons.remove(.manual) }
    }

    func setApplicationActive(_ active: Bool) {
        if active == false, hasContinuableNarrativeSave {
            saveNarrativeCampaign()
        }
        if isPrologueActive {
            if active { prologuePauseReasons.remove(.appInactive) }
            else { prologuePauseReasons.insert(.appInactive) }
        }
        if active {
            narrativePauseReasons.remove(.appInactive)
        } else if case .playing = gameState, hasContinuableNarrativeSave {
            narrativePauseReasons.insert(.appInactive)
        }
    }

    func completePrologueBeat(_ beat: PrologueBeatID, source: PrologueCompletionSource) {
        guard isPrologueActive, prologueState.currentBeat == beat,
              prologueState.completedBeats.contains(beat) == false else { return }
        prologueState.completedBeats.insert(beat)
        prologueState.lastBeatEcho = PrologueBeatEcho(beat: beat, source: source)
        switch beat {
        case .gateArrival:
            prologueState.openingViewed = true
        case .lookDownHall:
            prologueState.lookTutorialCompleted = source == .player
        case .returnToSeat:
            prologueState.movementTutorialCompleted = source == .player
            freeRoam = StudentFreeRoamState()
            player.posture = .seated
        case .placeWater:
            prologueState.interactionTutorialCompleted = source == .player
        case .accessibility:
            prologueState.accessibilityTutorialAcknowledged = source == .player
        default:
            break
        }

        guard let index = PrologueBeatID.allCases.firstIndex(of: beat),
              index + 1 < PrologueBeatID.allCases.count else {
            finishPrologue()
            return
        }
        let next = PrologueBeatID.allCases[index + 1]
        prologueState.currentBeat = next
        savePrologueProgress()
        beginPrologueBeat(next)
    }

    private func beginPrologueBeat(_ beat: PrologueBeatID) {
        prologueState.currentBeat = beat
        prologueBeatElapsed = 0
        prologueLookExplorationElapsed = 0
        prologueActionReady = false
        prologueSeatNearby = false
        prologueDwell = 0
        prologuePerformancePhase = 0
        cameraPose = .forward
        studentLookYaw = 0
        studentLookPitch = 0
        message = prologueMessage(for: beat)
        isPrologueTutorialPresented = false
        prologuePauseReasons.remove(.tutorial)
        switch beat {
        case .lookDownHall:
            // Step one teaches capture explicitly, so confirmation leaves the
            // cursor released until the player presses the physical ~ key.
            mouseLookEnabled = false
        case .returnToSeat:
            mouseLookEnabled = true
            let now = Date()
            freeRoam = StudentFreeRoamState(isActive: true, positionX: 3.25, positionZ: 1.65, yaw: .pi / 2, pitch: 0, startedAt: now, endsAt: .distantFuture, hasExitedClassroom: false, isSideways: false, isSprinting: false, frontDoorOpen: true, rearDoorOpen: false)
            player.posture = .standing
        case .placeWater, .studyHallRhythm, .noticeLinChe, .settleBreath, .accessibility, .bellBeforeClass:
            freeRoam = StudentFreeRoamState()
            player.posture = .seated
        default:
            break
        }
        if beat == .studyHallRhythm || beat == .bellBeforeClass {
            prologueActionReady = true
        }
        addPrologueAudio(for: beat)
        if beat.tutorialStep != nil {
            presentCurrentPrologueTutorial()
        }
    }

    private func finishPrologue() {
        stopPrologueTimer()
        clearScenePresentation()
        prologueState.prologueCompleted = true
        prologueState.completedBeats.insert(.bellBeforeClass)
        savePrologueProgress()
        startFullNarrativeCampaign()
        message = "预备铃的余音还在。晚自习开始了。"
        isChapterOneTransitionPresented = true
    }

    func enterChapterOneAfterPrologue() {
        isChapterOneTransitionPresented = false
    }

    func restartPrologueTutorial() {
        startPrologue(resume: false)
        // Re-enter at step 1 without replaying the seven-second exterior arrival.
        completePrologueBeat(.gateArrival, source: .performance)
    }

    private func prologueMessage(for beat: PrologueBeatID) -> String {
        switch beat {
        case .gateArrival: return "晚自习开始前，楼里总有一小段时间。大家在找座位，也在把白天没收好的东西先藏起来。"
        case .lookDownHall: return "走廊尽头，方老师正在和班长确认值日安排。"
        case .returnToSeat: return "教室门已经打开。先回到第三排。"
        case .placeWater: return "水放在手边。等会儿如果脑子很乱，至少不用再找它。"
        case .studyHallRhythm: return "门轴、翻页和椅子声一点点退下去，教室正在变得安静。"
        case .noticeLinChe: return "有时候你先看见的，只是一个人比平常安静。"
        case .settleBreath: return "自我照顾不是额外任务。你也在这间教室里。"
        case .accessibility: return "你可以随时暂停，调整字幕、声音、动态效果和输入方式。"
        case .bellBeforeClass: return "铃响以后，大家都会开始做自己的事。也许我也是。"
        }
    }

    private func addPrologueAudio(for beat: PrologueBeatID) {
        switch beat {
        case .gateArrival: addAudioCue(.footstep, direction: "楼道远处", intensity: 0.38, note: "学生进入教学楼的脚步声。")
        case .lookDownHall: addAudioCue(.whisper, direction: "走廊尽头", intensity: 0.3, note: "老师与班长在确认值日安排。")
        case .returnToSeat: addAudioCue(.footstep, direction: "第三排", intensity: 0.38, note: "回到座位的短距离脚步。")
        case .placeWater: addAudioCue(.paper, direction: "桌面", intensity: 0.24, note: "水杯轻轻碰到桌面。")
        case .studyHallRhythm: addAudioCue(.chair, direction: "教室四周", intensity: 0.4, note: "同学们陆续坐好。")
        case .noticeLinChe: addAudioCue(.paper, direction: "左侧近处", intensity: 0.3, note: "林澈把书翻到其中一页。")
        case .settleBreath: addAudioCue(.heartbeat, direction: "颅内", intensity: 0.22, note: "呼吸慢慢稳定下来。")
        case .accessibility: break
        case .bellBeforeClass: addAudioCue(.broadcast, direction: "走廊远处", intensity: 0.58, note: "预备铃从走廊传来。")
        }
    }

    private func savePrologueProgress() {
        guard shouldStartAudioEngine else { return }
        guard let data = try? JSONEncoder().encode(prologueState) else { return }
        storage.set(data, forKey: prologueStoreKey)
    }

    private func saveAccessibilityPreferences() {
        guard shouldStartAudioEngine else { return }
        guard let data = try? JSONEncoder().encode(accessibilityPreferences) else { return }
        storage.set(data, forKey: accessibilityStoreKey)
        if hasContinuableNarrativeSave {
            saveNarrativeCampaign()
        }
    }

    func applyAccessibilityPreferences() {
        audio.setMixVolumes(
            dialogue: accessibilityPreferences.dialogueVolume,
            ambience: accessibilityPreferences.ambienceVolume,
            cues: accessibilityPreferences.cueVolume
        )
        if accessibilityPreferences.directionalSubtitles == false {
            directionalSubtitleEvents = []
        }
        saveAccessibilityPreferences()
    }

    func updateAccessibilityPreferences(_ update: (inout AccessibilityPreferences) -> Void) {
        update(&accessibilityPreferences)
        applyAccessibilityPreferences()
    }

    private func loadPrologueProgress() {
        if let data = storage.data(forKey: prologueStoreKey),
           let saved = try? JSONDecoder().decode(PrologueState.self, from: data) {
            prologueState = saved
        }
        if let data = storage.data(forKey: accessibilityStoreKey),
           let saved = try? JSONDecoder().decode(AccessibilityPreferences.self, from: data) {
            accessibilityPreferences = saved
            applyAccessibilityPreferences()
        }
    }

    private func configurePlayerForSelectedRole() {
        player.stress += settings.rankingPressure * 0.08
        switch activeRole {
        case .honorStudent:
            player.psychicEnergy = 68
            player.maskCost = 38
            player.support = 30
            player.stress += 10
            player.exposure = 12
            player.homework = 18
            player.visualAttention = 90
        case .regularStudent:
            player.psychicEnergy = 74
            player.maskCost = 22
            player.support = 42
            player.stress += 2
            player.exposure = 18
            player.homework = 4
            player.visualAttention = 84
        case .homeroomTeacher, .counselingPatrolTeacher:
            player.psychicEnergy = 82
            player.maskCost = 12
            player.support = 50
            player.stress = max(18, settings.rankingPressure * 0.04)
            player.exposure = 8
            player.homework = 0
            player.thirst = 14
            player.hunger = 18
            player.bladder = 12
            player.waterCup = 100
            player.visualAttention = 88
        }
        clampPlayer()
    }

    private func makeTeacherState(for role: PlayableRole) -> TeacherState {
        switch role {
        case .homeroomTeacher:
            return TeacherState(
                kpiPressure: settings.rankingPressure + 8,
                fatigue: 46,
                empathy: 40,
                studentTrust: 30,
                counselingCapacity: 22
            )
        case .counselingPatrolTeacher:
            return TeacherState(
                kpiPressure: max(18, settings.rankingPressure * 0.42),
                fatigue: 30,
                empathy: 72,
                studentTrust: 58,
                counselingCapacity: 76
            )
        case .honorStudent, .regularStudent:
            return TeacherState(kpiPressure: settings.rankingPressure)
        }
    }

    private var roleOpeningLine: String {
        switch activeRole {
        case .homeroomTeacher:
            return "你今晚不是坐在座位里，而是站在全班前面：要保住秩序，也要尽量别错过真正撑不住的人。"
        case .honorStudent:
            return "你被固定在第三排中间的位置，别人默认你应该稳定、认真、不会出错。"
        case .regularStudent:
            return "你被固定在第三排中间的位置，只能靠观察和声音判断局势。"
        case .counselingPatrolTeacher:
            return "你从心理支持角度巡查教室，任务不是抓违规，而是在秩序里找到能被接住的求助信号。"
        }
    }

    private var roleOpeningMonologue: String {
        switch activeRole {
        case .homeroomTeacher:
            return "今晚不能只看安静不安静，我得判断哪些沉默是真的稳定。"
        case .honorStudent:
            return "大家都觉得我没问题，所以我更不能看起来有问题。"
        case .regularStudent:
            return "今晚要撑过去。不是表现得正常就等于真的不累。"
        case .counselingPatrolTeacher:
            return "我不能只等学生崩溃后再出现，真正难的是提前看见。"
        }
    }

    private func chapterOpeningMessage(memoryText: String) -> String {
        switch activeChapter {
        case .silentClassroom:
            return "18:30，\(activeChapter.rawValue)开始。你坐在第三排，班长还在收作业，林澈替人讲完最后一道题，后排椅子轻轻擦过地面。\(roleOpeningLine)\(memoryText)"
        }
    }

    private var chapterOpeningMonologue: String {
        switch activeChapter {
        case .silentClassroom:
            if activeRole.isTeacher {
                return "安静只是表面。我今晚要判断，哪些沉默是真正在学习，哪些沉默是在求救。"
            }
            return "我只能看一个方向。错过什么不是失败，但看见了就不能当作没发生。"
        }
    }

    var chapterObjectiveText: String {
        activeChapter.objective
    }

    var chapterProgressText: String {
        chapterOneStep.guidance
    }

    var chapterCurrentObjective: String {
        chapterOneStep.objective
    }

    var chapterOneAvailableActions: [PlayerAction] {
        guard chapterOneStep != .completed else { return [] }
        var actions = PlayerAction.allCases.filter { $0 != .leaveSeat }
        if chapterOneStep == .followLinChe {
            actions.append(.leaveSeat)
        }
        return actions
    }

    func restartWithCurrentSettings() {
        startGame()
    }

    func clearClassmateMemory() {
        classmateMemory = [:]
        storage.removeObject(forKey: memoryStoreKey)
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
        viewMode = activeRole.isTeacher ? .teacher : .student
        message = activeRole.isTeacher
            ? "教师模式固定为班主任视角。你需要通过位置、目标学生和干预方式理解全班。"
            : "学生模式固定为学生视角。教师视角会留到结算回放中理解。"
    }

    func setTeacherLocation(_ location: TeacherLocation) {
        guard case .playing = gameState, activeRole.isTeacher else { return }
        teacher.location = location
        teacher.positionIndex = location.positionIndex
        teacher.isNearPlayer = location == .targetDesk || location == .rightAisle
        teacher.focusMode = location == .rearDoor ? .rearDoor : (location == .podium ? .wholeClass : .selectedStudent)
        teacher.fatigue += location == .targetDesk ? 3 : 2
        teacher.classOrder = min(100, teacher.classOrder + (location == .podium ? 4 : 2))
        teacher.misreadRisk += location == .rearDoor ? 4 : 1
        clampTeacher()
        message = "你移动到\(location.rawValue)。位置改变后，看到的信息也改变：\(teacherFocusDescription)。"
        addAudioCue(location == .rearDoor ? .knock : .footstep, direction: location == .rearDoor ? "后方左侧" : "过道移动", intensity: 0.68, note: "教师位置变化会改变学生对风险的判断。")
    }

    func selectTeacherTarget(_ classmateID: Int) {
        guard case .playing = gameState, activeRole.isTeacher else { return }
        selectedTeacherTargetID = classmateID
        teacher.focusMode = .selectedStudent
        teacher.misreadRisk = max(0, teacher.misreadRisk - 3)
        if let target = selectedTeacherTarget {
            message = "你把注意力放到\(target.name)身上。表面状态：\(target.state.rawValue)，可能原因：\(target.riskReason)。"
        }
    }

    var selectedTeacherTarget: Classmate? {
        guard let selectedTeacherTargetID else { return highestRiskClassmate }
        return classmates.first { $0.id == selectedTeacherTargetID } ?? highestRiskClassmate
    }

    var teacherTargetCandidates: [Classmate] {
        classmates
            .sorted { lhs, rhs in
                teacherTargetScore(lhs) > teacherTargetScore(rhs)
            }
            .prefix(8)
            .map { $0 }
    }

    private func teacherTargetScore(_ classmate: Classmate) -> Double {
        classmate.stress
            + classmate.suspicionOfPlayer * 0.4
            + (classmate.state == .crying ? 40 : 0)
            + (classmate.state == .usingPhone ? 18 : 0)
            + (classmate.state == .sleeping ? 12 : 0)
            + classmate.profile.anxiety * 0.18
    }

    var teacherFocusDescription: String {
        switch teacher.focusMode {
        case .wholeClass:
            return "你能看见全班秩序，但很难判断某个学生的真实原因。"
        case .selectedStudent:
            let target = selectedTeacherTarget?.name ?? "目标学生"
            return "你正在观察\(target)，能获得更细信息，也可能让 TA 更紧张。"
        case .blackboard:
            return "你低头看记录和 KPI，制度压力会变得更具体。"
        case .rearDoor:
            return "你从后门观察，表面秩序更稳定，但学生的不确定压力会上升。"
        }
    }

    var estimatedClassRisk: Double {
        guard !classmates.isEmpty else { return teacher.classRisk }
        let averageStress = classmates.reduce(0) { $0 + $1.stress } / Double(classmates.count)
        let cryingLoad = Double(classmates.filter { $0.state == .crying }.count) * 16
        let phoneLoad = Double(classmates.filter { $0.state == .usingPhone }.count) * 5
        let trustBuffer = teacher.studentTrust * 0.12
        return (averageStress * 0.72 + cryingLoad + phoneLoad + teacher.institutionalPressure * 0.18 - trustBuffer).clamped(to: 0...100)
    }

    func setPose(_ pose: CameraPose) {
        guard case .playing = gameState else { return }
        guard narrativePaused == false else { return }
        if isPrologueActive && prologueState.currentBeat.allowsLook == false { return }
        guard activeRole.isTeacher == false, freeRoam.isActive == false else { return }
        let previousPose = cameraPose
        cameraPose = pose
        if isPrologueActive {
            return
        }

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
        case .rear:
            spendAttention(for: pose.visionZone, multiplier: teacher.isNearPlayer ? 1.25 : 1)
            player.exposure += teacher.isNearPlayer ? 32 : 22
            player.stress += teacher.isNearPlayer ? 10 : 6
            player.maskCost += 3
            message = "你坐着回头看向后方。这个动作能确认身后的风险，但在晚自习里非常显眼。"
            addAudioCue(.chair, direction: "座位下方", intensity: teacher.isNearPlayer ? 0.74 : 0.5, note: "坐着回头会带动椅子和肩膀，比余光更容易暴露。")
        case .forward:
            recoverAttention(10)
            player.psychicEnergy = min(100, player.psychicEnergy + 1.5)
            message = "你把视线收回前方，试着让自己看起来普通。"
        }

        applyTurnStrain(from: previousPose, to: pose)
        chapterOneDwellFocus.resetForPose(pose)
        clampPlayer()
        maybeAddAnomalyMonologue()
        updatePerception()
    }

    func rotateStudentView(deltaX: Double, deltaY: Double) {
        guard case .playing = gameState, activeRole.isTeacher == false, isReturningToSeat == false else { return }
        if isPrologueActive && prologuePaused { return }
        if isPrologueActive && prologueState.currentBeat.allowsLook == false { return }
        let previousPose = cameraPose
        let sensitivity = 0.006
        let nextYaw = normalizedAngle(studentLookYaw - deltaX * sensitivity)
        let nextPitch = (studentLookPitch - deltaY * sensitivity).clamped(to: -0.72...0.48)
        studentLookYaw = nextYaw
        studentLookPitch = nextPitch
        if freeRoam.isActive {
            var nextFreeRoam = freeRoam
            nextFreeRoam.yaw = nextYaw
            nextFreeRoam.pitch = nextPitch
            freeRoam = nextFreeRoam
        }
        let nextPose = cameraPoseFromLook(yaw: nextYaw, pitch: nextPitch)
        guard nextPose != previousPose else { return }
        cameraPose = nextPose
        if isPrologueActive {
            return
        }
        applyRearLookRiskIfNeeded(previousPose: previousPose)
        chapterOneDwellFocus.resetForPose(nextPose)
        if freeRoam.isActive == false {
            updatePerception()
        }
    }

    private func cameraPoseFromLook(yaw: Double, pitch: Double) -> CameraPose {
        if abs(yaw) > 2.35 {
            return .rear
        } else if pitch < -0.38 {
            return .desk
        } else if pitch > 0.25 {
            return .board
        } else if yaw > 0.42 {
            return .left
        } else if yaw < -0.42 {
            return .right
        } else {
            return .forward
        }
    }

    private func applyRearLookRiskIfNeeded(previousPose: CameraPose) {
        guard freeRoam.isActive == false, player.posture == .seated, previousPose != .rear, cameraPose == .rear else {
            return
        }
        spendAttention(for: .rearPeripheral, multiplier: teacher.isNearPlayer ? 1.25 : 1)
        player.exposure += teacher.isNearPlayer ? 32 : 22
        player.stress += teacher.isNearPlayer ? 10 : 6
        player.maskCost += 3
        message = teacher.isNearPlayer
            ? "你坐着回头看向后方，动作非常显眼。老师在近处时，这几乎等于把自己从普通状态里拎出来。"
            : "你坐着回头看向后方。你获得了确定信息，但这个动作在安静教室里很难不被注意。"
        addAudioCue(.chair, direction: "座位下方", intensity: teacher.isNearPlayer ? 0.74 : 0.5, note: "坐着回头会带动椅子和肩膀，比余光更容易暴露。")
        clampPlayer()
    }

    func setMouseLookEnabled(_ enabled: Bool) {
        guard activeRole.isTeacher == false else { return }
        mouseLookEnabled = enabled
        mouseLookCaptured = false
    }

    func recenterStudentView() {
        guard case .playing = gameState, activeRole.isTeacher == false, freeRoam.isActive == false, isReturningToSeat == false else { return }
        studentLookYaw = 0
        studentLookPitch = 0
        cameraPose = .forward
        updatePerception()
    }

    private func normalizedAngle(_ angle: Double) -> Double {
        var value = angle
        while value > .pi { value -= .pi * 2 }
        while value < -.pi { value += .pi * 2 }
        return value
    }

    private func beginStudentFreeRoam(duration: TimeInterval = 60, openingMessage: String? = nil) {
        guard activeRole.isTeacher == false else { return }
        freeRoamTimer?.invalidate()
        freeRoamPausedAt = nil
        returnToSeatTask?.cancel()
        returnToSeatTask = nil
        isReturningToSeat = false
        returnToSeatStartedAt = .distantPast
        pendingSprintHunger = 0
        let now = Date()
        studentLookYaw = 0
        studentLookPitch = 0
        freeRoam = StudentFreeRoamState(
            isActive: true,
            positionX: -1.2,
            positionZ: 1.65,
            yaw: 0,
            pitch: 0,
            startedAt: now,
            endsAt: now.addingTimeInterval(duration),
            hasExitedClassroom: false,
            isSideways: false,
            isSprinting: false,
            frontDoorOpen: frontDoorOpen,
            rearDoorOpen: rearDoorOpen
        )
        player.posture = .standing
        gameState = .playing
        message = openingMessage ?? "老师点头同意。你获得 \(Int(duration)) 秒离座活动时间，移动鼠标调整方向，使用 WASD 行走；靠近前后门时可以开门或关门。"
        addAudioCue(.chair, direction: "座位到过道", intensity: 0.56, note: "获批离座后，椅子声从违规风险变成了被允许的移动声。")
        freeRoamTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickStudentFreeRoam()
            }
        }
    }

    func moveStudentFreeRoam(forward: Double, strafe: Double, deltaTime: Double) {
        guard case .playing = gameState, freeRoam.isActive, activeRole.isTeacher == false, isReturningToSeat == false else { return }
        if isPrologueActive && prologuePaused { return }
        if isPrologueActive && prologueState.currentBeat.allowsMovement == false { return }
        let baseSpeed = freeRoam.hasExitedClassroom ? 1.7 : 1.45
        let postureSpeed = freeRoam.isSideways ? baseSpeed * 0.58 : baseSpeed
        let speed = freeRoam.isSprinting ? postureSpeed * 1.7 : postureSpeed
        let yaw = freeRoam.yaw
        let distance = speed * deltaTime
        let inputLength = hypot(forward, strafe)
        let normalizedForward = inputLength > 1 ? forward / inputLength : forward
        let normalizedStrafe = inputLength > 1 ? strafe / inputLength : strafe
        let forwardX = -sin(yaw)
        let forwardZ = -cos(yaw)
        let rightX = cos(yaw)
        let rightZ = -sin(yaw)
        let nextX = freeRoam.positionX + (forwardX * normalizedForward + rightX * normalizedStrafe) * distance
        let nextZ = freeRoam.positionZ + (forwardZ * normalizedForward + rightZ * normalizedStrafe) * distance
        let resolved = resolvedFreeRoamPosition(fromX: freeRoam.positionX, fromZ: freeRoam.positionZ, toX: nextX, toZ: nextZ)
        let actualDistance = hypot(resolved.x - freeRoam.positionX, resolved.z - freeRoam.positionZ)
        var nextFreeRoam = freeRoam
        nextFreeRoam.positionX = resolved.x
        nextFreeRoam.positionZ = resolved.z
        if resolved.x > 4.08 {
            nextFreeRoam.hasExitedClassroom = true
            player.stress = max(0, player.stress - 0.05)
        }
        freeRoam = nextFreeRoam
        if isPrologueActive, prologueState.currentBeat == .returnToSeat {
            let wasNearby = prologueSeatNearby
            prologueSeatNearby = hypot(nextFreeRoam.positionX - (-0.6), nextFreeRoam.positionZ - 1.65) <= 0.72
            if prologueSeatNearby && wasNearby == false {
                message = "你已经靠近自己的座位。按 E 入座。"
            }
        }
        if nextFreeRoam.isSprinting && actualDistance > 0 {
            pendingSprintHunger += actualDistance * 0.18
            if pendingSprintHunger >= 0.25 {
                flushSprintHunger()
            }
        }
    }

    var nearbyStudentDoor: StudentDoor? {
        guard case .playing = gameState, freeRoam.isActive, activeRole.isTeacher == false else { return nil }
        return StudentDoor.allCases
            .map { door in
                let dx = freeRoam.positionX - door.centerX
                let dz = freeRoam.positionZ - door.centerZ
                return (door: door, distance: sqrt(dx * dx + dz * dz))
            }
            .filter { $0.distance <= 1.05 }
            .min { $0.distance < $1.distance }?
            .door
    }

    func isStudentDoorOpen(_ door: StudentDoor) -> Bool {
        switch door {
        case .front: return frontDoorOpen
        case .rear: return rearDoorOpen
        }
    }

    @discardableResult
    func interactWithNearbyDoor() -> Bool {
        guard let door = nearbyStudentDoor else { return false }
        let willOpen = isStudentDoorOpen(door) == false
        let didPushPlayer = willOpen ? false : pushPlayerOutOfDoorwayBeforeClosing(door)
        switch door {
        case .front:
            frontDoorOpen = willOpen
            freeRoam.frontDoorOpen = willOpen
        case .rear:
            rearDoorOpen = willOpen
            freeRoam.rearDoorOpen = willOpen
        }

        if willOpen {
            player.exposure += 1.5
            message = "你轻轻打开\(door.rawValue)。门缝让走廊变得可达，但门轴声也会让你更显眼。"
            addAudioCue(.knock, direction: door.rawValue, intensity: 0.36, note: "\(door.rawValue)打开，声音短促但在安静教室里仍然明显。")
        } else {
            player.exposure += 0.8
            message = didPushPlayer
                ? "你站在\(door.rawValue)门洞里带上门，身体被迫退到门的一侧。通道被重新挡住。"
                : "你把\(door.rawValue)带上。通道被重新挡住，脚步声也暂时被教室墙面收回。"
            addAudioCue(.knock, direction: door.rawValue, intensity: 0.24, note: "\(door.rawValue)关闭，动作比开门更轻，但仍有一点门锁声。")
        }
        clampPlayer()
        objectWillChange.send()
        return true
    }

    var isNearPlayerLocker: Bool {
        guard case .playing = gameState, freeRoam.isActive, activeRole.isTeacher == false else { return false }
        let dx = freeRoam.positionX - 6.22
        let dz = freeRoam.positionZ - (-3.9)
        return sqrt(dx * dx + dz * dz) <= 0.9
    }

    func togglePlayerLocker() {
        guard isNearPlayerLocker else { return }
        playerLockerOpen.toggle()
        player.exposure += playerLockerOpen ? 0.8 : 0.3
        message = playerLockerOpen
            ? "你打开自己的储物柜。里面暂时只是一片阴影，之后可以在这里选择取走物品。"
            : "你把储物柜合上，金属门发出很轻的一声。"
        addAudioCue(.knock, direction: "走廊储物柜", intensity: playerLockerOpen ? 0.3 : 0.22, note: "储物柜门声比教室门轻，但在走廊里仍然清楚。")
        clampPlayer()
        objectWillChange.send()
    }

    var isNearWaterDispenser: Bool {
        guard case .playing = gameState, freeRoam.isActive, activeRole.isTeacher == false else { return false }
        let dx = freeRoam.positionX - 6.2
        let dz = freeRoam.positionZ - 3.9
        return sqrt(dx * dx + dz * dz) <= 0.95
    }

    func refillWaterCup() {
        guard isNearWaterDispenser else { return }
        player.waterCup = 100
        player.exposure += currentPeriod.isBreak ? 0.2 : 1.2
        spendFreeRoamSeconds(10)
        message = "你在饮水机旁把水杯接满，消耗 10 秒。杯里的水回到 100，之后可以在座位上继续喝。"
        addAudioCue(.knock, direction: "走廊饮水机", intensity: 0.2, note: "水流声很轻，课间会被走廊声盖住。")
        clampPlayer()
        objectWillChange.send()
    }

    var isNearRestroom: Bool {
        guard case .playing = gameState, freeRoam.isActive, activeRole.isTeacher == false else { return false }
        let dx = freeRoam.positionX - 7.02
        let dz = freeRoam.positionZ - 6.12
        return sqrt(dx * dx + dz * dz) <= 0.48
    }

    func useRestroom() {
        guard isNearRestroom else { return }
        player.bladder = 0
        player.stress = max(0, player.stress - 8)
        player.psychicEnergy = min(100, player.psychicEnergy + 4)
        spendFreeRoamSeconds(10)
        freeRoam.hasExitedClassroom = true
        message = "你进入洗手间并靠近马桶后才完成如厕，过程消耗 10 秒。如厕需求归零，身体终于不用继续和注意力抢位置。"
        addAudioCue(.footstep, direction: "洗手间门口", intensity: 0.24, note: "洗手间里的脚步被墙面削弱，离开教室后的声音边界变远。")
        addMonologue("不是我矫情，是身体真的需要被允许处理。", intensity: 0.42)
        clampPlayer()
        objectWillChange.send()
    }

    private func spendFreeRoamSeconds(_ seconds: TimeInterval) {
        let remaining = max(0, freeRoam.endsAt.timeIntervalSinceNow - seconds)
        freeRoam.endsAt = Date().addingTimeInterval(remaining)
    }

    private func pushPlayerOutOfDoorwayBeforeClosing(_ door: StudentDoor) -> Bool {
        let radius = currentFreeRoamPlayerRadius
        let overlapsDoorDepth = abs(freeRoam.positionZ - door.centerZ) <= 0.5 + radius
        let overlapsDoorWidth = freeRoam.positionX >= 3.9 - radius && freeRoam.positionX <= 4.52 + radius
        guard overlapsDoorDepth && overlapsDoorWidth else { return false }

        let pushToCorridor = freeRoam.positionX >= 4.18
        let clearX = pushToCorridor
            ? 4.52 + radius + 0.04
            : 3.9 - radius - 0.04
        let clampedZ = freeRoam.positionZ.clamped(to: (door.centerZ - 0.34)...(door.centerZ + 0.34))
        freeRoam.positionX = clearX
        freeRoam.positionZ = clampedZ
        if pushToCorridor {
            freeRoam.hasExitedClassroom = true
        }
        return true
    }

    private func resolvedFreeRoamPosition(fromX: Double, fromZ: Double, toX: Double, toZ: Double) -> (x: Double, z: Double) {
        if isFreeRoamPositionValid(x: toX, z: toZ) {
            return (toX, toZ)
        }
        if isFreeRoamPositionValid(x: toX, z: fromZ) {
            return (toX, fromZ)
        }
        if isFreeRoamPositionValid(x: fromX, z: toZ) {
            return (fromX, toZ)
        }
        return (fromX, fromZ)
    }

    private func isFreeRoamPositionValid(x: Double, z: Double) -> Bool {
        let radius = currentFreeRoamPlayerRadius
        guard freeRoamWalkableRegions.contains(where: { $0.contains(x: x, z: z, radius: radius) }) else {
            return false
        }
        return freeRoamObstacles.contains { $0.intersectsCircle(x: x, z: z, radius: radius) } == false
    }

    private var currentFreeRoamPlayerRadius: Double {
        freeRoam.isSideways ? sidewaysFreeRoamPlayerRadius : normalFreeRoamPlayerRadius
    }

    func setFreeRoamSideways(_ isSideways: Bool) {
        guard freeRoam.isActive, activeRole.isTeacher == false else { return }
        guard isReturningToSeat == false || isSideways == false else { return }
        guard freeRoam.isSideways != isSideways else { return }
        freeRoam.isSideways = isSideways
        if isSideways {
            player.exposure += 1.2
            message = "你把身体侧过来，步子变慢，但更容易从桌椅缝隙里通过。"
        } else {
            message = "你恢复正身行走，速度更快，但通过窄缝会更困难。"
        }
        clampPlayer()
    }

    func setFreeRoamSprinting(_ isSprinting: Bool) {
        guard freeRoam.isActive, activeRole.isTeacher == false else { return }
        guard isReturningToSeat == false || isSprinting == false else { return }
        guard freeRoam.isSprinting != isSprinting else { return }
        freeRoam.isSprinting = isSprinting
        if isSprinting {
            message = "你加快脚步开始疾跑。移动更快，但身体会更快感到饥饿。"
        } else {
            flushSprintHunger()
            message = "你放慢脚步，恢复普通行走速度。"
        }
    }

    func clearFreeRoamMovementModifiers() {
        guard freeRoam.isActive else { return }
        if freeRoam.isSprinting {
            flushSprintHunger()
        }
        freeRoam.isSprinting = false
        freeRoam.isSideways = false
    }

    private func flushSprintHunger() {
        guard pendingSprintHunger > 0 else { return }
        player.hunger = min(100, player.hunger + pendingSprintHunger)
        pendingSprintHunger = 0
    }

    private var freeRoamWalkableRegions: [FreeRoamRect] {
        [
            FreeRoamRect(minX: -3.55, maxX: 3.72, minZ: -5.55, maxZ: 5.55),
            FreeRoamRect(minX: 3.35, maxX: 6.22, minZ: -11.35, maxZ: 8.18),
            FreeRoamRect(minX: 2.22, maxX: 4.02, minZ: -10.2, maxZ: -8.5),
            FreeRoamRect(minX: 5.72, maxX: 7.2, minZ: 5.32, maxZ: 6.38)
        ]
    }

    private var freeRoamObstacles: [FreeRoamRect] {
        var obstacles: [FreeRoamRect] = []

        for row in 0..<5 {
            for column in 0..<4 {
                let x = Double(column) * 1.2 - 2.4
                let deskZ = Double(row) * 1.45 - 2.25
                let chairZ = deskZ + 0.55
                obstacles.append(expandedObstacle(centerX: x, centerZ: deskZ, width: 0.70, length: 0.50))
                obstacles.append(expandedObstacle(centerX: x, centerZ: chairZ, width: 0.48, length: 0.42))
            }
        }

        obstacles.append(expandedObstacle(centerX: 0, centerZ: -4.7, width: 2.02, length: 0.98))
        obstacles.append(expandedObstacle(centerX: 0, centerZ: -5.94, width: 4.35, length: 0.12))
        obstacles.append(expandedObstacle(centerX: 4.0, centerZ: -5.56, width: 0.16, length: 0.88))
        obstacles.append(expandedObstacle(centerX: 4.0, centerZ: -3.34, width: 0.16, length: 1.68))
        obstacles.append(expandedObstacle(centerX: 4.0, centerZ: -1.78, width: 0.16, length: 1.46))
        obstacles.append(expandedObstacle(centerX: 4.0, centerZ: 3.02, width: 0.16, length: 2.08))
        obstacles.append(expandedObstacle(centerX: 4.0, centerZ: 0.85, width: 0.16, length: 5.4))
        obstacles.append(expandedObstacle(centerX: 4.0, centerZ: 5.61, width: 0.16, length: 0.8))

        obstacles.append(contentsOf: doorLeafObstacles(for: .front))
        obstacles.append(contentsOf: doorLeafObstacles(for: .rear))

        obstacles.append(expandedObstacle(centerX: 3.88, centerZ: -7.25, width: 0.36, length: 3.86))
        obstacles.append(expandedObstacle(centerX: 3.88, centerZ: 7.25, width: 0.36, length: 3.86))
        obstacles.append(expandedObstacle(centerX: 5.25, centerZ: -11.48, width: 2.72, length: 0.24))
        obstacles.append(expandedObstacle(centerX: 2.18, centerZ: -9.35, width: 0.08, length: 2.2))
        obstacles.append(expandedObstacle(centerX: 3.12, centerZ: -10.42, width: 1.86, length: 0.08))
        obstacles.append(expandedObstacle(centerX: 3.12, centerZ: -8.28, width: 1.86, length: 0.08))
        obstacles.append(expandedObstacle(centerX: 6.98, centerZ: 5.3, width: 0.46, length: 0.12))
        obstacles.append(expandedObstacle(centerX: 6.98, centerZ: 6.4, width: 0.46, length: 0.12))

        for lockerZ in [-7.55, -6.85, -5.2, -4.55, -3.9, -3.25, 6.75, 7.45] {
            obstacles.append(expandedObstacle(centerX: 6.55, centerZ: lockerZ, width: 0.5, length: 0.42))
        }

        let teacherPosition = teacherFreeRoamPosition
        obstacles.append(expandedObstacle(centerX: teacherPosition.x, centerZ: teacherPosition.z, width: 0.66, length: 0.62))

        return obstacles
    }

    private func doorLeafObstacles(for door: StudentDoor) -> [FreeRoamRect] {
        if isStudentDoorOpen(door) {
            return [
                expandedObstacle(centerX: 4.31, centerZ: door.centerZ - 0.43, width: 0.37, length: 0.08),
                expandedObstacle(centerX: 4.31, centerZ: door.centerZ + 0.43, width: 0.37, length: 0.08)
            ]
        }
        return [
            expandedObstacle(centerX: 4.02, centerZ: door.centerZ - 0.19, width: 0.08, length: 0.37),
            expandedObstacle(centerX: 4.02, centerZ: door.centerZ + 0.19, width: 0.08, length: 0.37)
        ]
    }

    func isDoorBlockingFreeRoamPosition(_ door: StudentDoor, x: Double, z: Double) -> Bool {
        doorLeafObstacles(for: door).contains { $0.intersectsCircle(x: x, z: z, radius: currentFreeRoamPlayerRadius) }
    }

    var teacherFreeRoamPosition: (x: Double, z: Double) {
        let path: [(x: Double, z: Double)] = [
            (-2.7, -4.25), (2.6, -3.2), (2.6, -1.2),
            (1.2, 0.45), (0.2, 1.55), (-2.2, 0.4),
            (-2.8, -1.4), (0, -4.35), (-3.45, 4.25)
        ]
        return path[min(max(teacher.positionIndex, 0), path.count - 1)]
    }

    func isTeacherBlockingFreeRoamPosition(x: Double, z: Double) -> Bool {
        let position = teacherFreeRoamPosition
        let obstacle = expandedObstacle(centerX: position.x, centerZ: position.z, width: 0.66, length: 0.62)
        return obstacle.intersectsCircle(x: x, z: z, radius: currentFreeRoamPlayerRadius)
    }

    private func expandedObstacle(centerX: Double, centerZ: Double, width: Double, length: Double) -> FreeRoamRect {
        FreeRoamRect(
            minX: centerX - width / 2,
            maxX: centerX + width / 2,
            minZ: centerZ - length / 2,
            maxZ: centerZ + length / 2
        )
    }

    private func tickStudentFreeRoam() {
        guard freeRoam.isActive else {
            freeRoamTimer?.invalidate()
            freeRoamTimer = nil
            return
        }
        guard case .playing = gameState else { return }
        if freeRoam.remainingSeconds <= 0 {
            returnToSeatFromFreeRoam(reason: "时间到了，你回到座位。走廊里的空气留在身后，晚自习重新包围过来。")
        } else {
            objectWillChange.send()
        }
    }

    func returnToSeatFromFreeRoam(reason: String? = nil) {
        guard freeRoam.isActive, isReturningToSeat == false else { return }
        let exitedClassroom = freeRoam.hasExitedClassroom
        freeRoamTimer?.invalidate()
        freeRoamTimer = nil
        freeRoamPausedAt = nil
        flushSprintHunger()
        clearFreeRoamMovementModifiers()
        isReturningToSeat = true
        returnToSeatStartedAt = Date()
        message = reason ?? "你转身沿原路回座。脚步声逐渐靠近教室，视野在短暂闭合后重新落回桌面。"
        addAudioCue(.footstep, direction: freeRoam.hasExitedClassroom ? "走廊到教室" : "座位过道", intensity: 0.46, note: "回座的脚步由远及近，在闭眼的瞬间与教室环境声重新重合。")
        returnToSeatTask?.cancel()
        returnToSeatTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(GameManager.returnToSeatResetDelay * 1_000_000_000))
            } catch {
                return
            }
            guard let self, self.isReturningToSeat else { return }
            self.completeReturnToSeat(exitedClassroom: exitedClassroom, reason: reason)
            do {
                let revealDuration = GameManager.returnToSeatTotalDuration - GameManager.returnToSeatResetDelay
                try await Task.sleep(nanoseconds: UInt64(revealDuration * 1_000_000_000))
            } catch {
                return
            }
            guard self.isReturningToSeat else { return }
            self.isReturningToSeat = false
            self.returnToSeatStartedAt = .distantPast
            self.returnToSeatTask = nil
        }
    }

    private func completeReturnToSeat(exitedClassroom: Bool, reason: String?) {
        freeRoam = StudentFreeRoamState()
        studentLookYaw = 0
        studentLookPitch = 0
        cameraPose = .forward
        player.posture = .seated
        addAudioCue(.chair, direction: "座位下方", intensity: 0.38, note: "椅子轻响标记了回座动作真正完成。")

        if exitedClassroom {
            player.psychicEnergy += 16
            recoverAttention(18)
            player.homework = max(0, player.homework - 5)
            player.exposure = max(0, player.exposure - 8)
            player.stress = max(0, player.stress - 18)
            addMonologue("离开教室几十秒，我才知道自己刚才一直在憋着。", intensity: 0.58)
            message = reason ?? "你提前回到座位。短暂走出教室没有解决所有压力，但身体明显松了一点。"
        } else {
            player.psychicEnergy += 7
            recoverAttention(10)
            player.stress = max(0, player.stress - 6)
            player.exposure += 3
            message = reason ?? "你提前回到座位。你没有真正走出教室，但站起来活动让身体从僵硬里退出来一点。"
        }

        clampPlayer()
        updateClassmates(after: nil)
        recordSnapshot(actionLabel: exitedClassroom ? "离座活动" : "短暂站起")
        teacherTurn()
    }

    #if DEBUG
    func completeReturnToSeatCoverForTesting() {
        guard freeRoam.isActive, isReturningToSeat else { return }
        let exitedClassroom = freeRoam.hasExitedClassroom
        returnToSeatTask?.cancel()
        returnToSeatTask = nil
        completeReturnToSeat(exitedClassroom: exitedClassroom, reason: nil)
    }

    func finishReturnToSeatRevealForTesting() {
        guard isReturningToSeat else { return }
        returnToSeatTask?.cancel()
        returnToSeatTask = nil
        isReturningToSeat = false
        returnToSeatStartedAt = .distantPast
    }
    #endif

    private func applyTurnStrain(from previous: CameraPose, to next: CameraPose) {
        guard previous != next else { return }
        let isSideTurn = next == .left || next == .right
        let isVerticalTurn = next == .board || next == .desk
        let isRearTurn = next == .rear
        guard isSideTurn || isVerticalTurn || isRearTurn else { return }

        let strain = player.stress * 0.35 + max(0, 38 - player.visualAttention) + (teacher.isNearPlayer ? 18 : 0) + (isRearTurn ? 18 : 0)
        guard strain > 52 else { return }

        let stressDelta = min(isRearTurn ? 10 : 7, strain / 18)
        player.stress += stressDelta
        player.maskCost += isRearTurn ? 4 : (isSideTurn ? 2 : 1)
        player.visualAttention = max(0, player.visualAttention - min(isRearTurn ? 10 : 6, strain / 20))
        if isRearTurn {
            message += " 回头确认带来的确定感很贵：身体要转，椅子会响，老师和同学都更容易注意到你。"
        } else {
            message += isSideTurn
                ? " 你转头时明显慢了一拍，脖子僵硬像是在提醒你：确认信息也有代价。"
                : " 视线上下切换时有短暂迟滞，身体比意识更早感到紧张。"
        }
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
        guard narrativePaused == false else { return }
        guard narrativeCampaign.isActive == false else { return }
        if activeRole.isTeacher {
            executeTeacherAction(.scanClass)
            return
        }
        currentPhase = .action

        if isPrologueActive {
            if prologueState.currentBeat == .settleBreath, action == .breathe {
                addAudioCue(.heartbeat, direction: "颅内", intensity: 0.2, note: "呼吸慢下来，教室的声音重新有了边界。")
                prologueActionReady = true
                message = "呼吸慢了下来。按 C 可以提前结束这一步，也可以继续感受片刻。"
            }
            return
        }

        if chapterOneStep == .followLinChe, action == .leaveSeat {
            completeChapterOne()
            return
        }

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
        case .drink:
            if player.waterCup >= 25 {
                player.thirst = max(0, player.thirst - 20)
                player.waterCup = max(0, player.waterCup - 25)
                player.psychicEnergy += 3
                player.stress = max(0, player.stress - 3)
                player.exposure += teacher.isNearPlayer ? 3 : 0.8
                message = "你低头喝了一口水。喉咙没有刚才那么紧，注意力也慢慢回到教室。"
                addAudioCue(.paper, direction: "桌面近处", intensity: 0.18, note: "杯子碰到桌面的声音很轻，但老师很近时仍会被注意到。")
            } else {
                player.stress += 2
                message = "你摸到水杯，里面已经不够一口了。需要课间或离座时去饮水机补水。"
                addMonologue("连喝水都要算时机，身体需求也变成了计划题。", intensity: 0.38)
            }
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
            if currentPeriod.isBreak {
                beginStudentFreeRoam(
                    duration: 300,
                    openingMessage: "\(clockText)，课间开始。你可以自由活动 5 分钟，去走廊、饮水机、洗手间，或经过一班前方的门厅看向户外。"
                )
                return
            }
            guard leaveSeatUsedPeriods.contains(currentPeriod) == false else {
                player.stress += 4
                player.maskCost += 2
                message = "这一节课你已经举手离座过一次了。再举手会变得非常显眼，只能等课间或下一节。"
                addMonologue("规则不是只限制动作，也限制我什么时候能处理身体。", intensity: 0.48)
                break
            }
            leaveSeatUsedPeriods.insert(currentPeriod)
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
        collectChapterClue(for: action)
        maybeAddAnomalyMonologue()
        if case .event = gameState {
            recordSnapshot(actionLabel: action.rawValue)
            saveFullNarrativeChapterOneIfNeeded()
            return
        }
        updateClassmates(after: action)
        recordSnapshot(actionLabel: action.rawValue)
        teacherTurn()
        saveFullNarrativeChapterOneIfNeeded()
    }

    func executeTeacherAction(_ action: TeacherAction) {
        guard case .playing = gameState else { return }
        currentPhase = .teacherTurn
        let target = selectedTeacherTarget

        switch action {
        case .scanClass:
            teacher.focusMode = .wholeClass
            teacher.fatigue += 3
            teacher.classOrder = min(100, teacher.classOrder + 4)
            teacher.classRisk = estimatedClassRisk
            teacher.misreadRisk = max(0, teacher.misreadRisk - 4)
            message = "你没有盯住某一个人，而是扫过全班。表面秩序 \(Int(teacher.classOrder))，真实风险约 \(Int(teacher.classRisk))。"
            addAudioCue(.paper, direction: "教室四周", intensity: 0.36, note: "全班视角能降低误判，但需要持续消耗教师注意力。")
        case .observeTarget:
            teacher.focusMode = .selectedStudent
            teacher.fatigue += 4
            teacher.misreadRisk = max(0, teacher.misreadRisk - 8)
            teacher.classRisk = estimatedClassRisk
            if let target {
                raiseClassmateStress(id: target.id, delta: 3)
                message = "你观察\(target.name)：表面是\(target.state.rawValue)，可能原因是\(target.riskReason)。更细的信息降低误判，也让 TA 感到被盯住。"
            } else {
                message = "你试着观察具体学生，但没有锁定目标。"
            }
            addAudioCue(.teacherCough, direction: teacher.location == .rearDoor ? "后方左侧" : "过道近处", intensity: 0.38, note: "教师的停顿会成为学生判断风险的线索。")
        case .publicWarn:
            teacher.studentsWarned += 1
            player.teacherWarnings += 1
            teacher.kpiPressure = max(0, teacher.kpiPressure - 8)
            teacher.fatigue += 4
            teacher.classOrder = min(100, teacher.classOrder + 15)
            teacher.studentTrust = max(0, teacher.studentTrust - 8)
            teacher.misreadRisk = min(100, teacher.misreadRisk + 5)
            if let target {
                raiseClassmateStress(id: target.id, delta: 12)
                message = "你公开提醒了\(target.name)。表面秩序快速恢复，但学生信任下降，目标学生压力明显上升。"
            } else {
                message = "你公开提醒全班。它很有效，也很粗糙。"
            }
            addAudioCue(.chair, direction: "讲台前方", intensity: 0.62, note: "提醒后的椅子轻响，比回答更诚实。")
        case .quietWarn:
            teacher.studentsWarned += 1
            teacher.kpiPressure = max(0, teacher.kpiPressure - 3)
            teacher.fatigue += 3
            teacher.classOrder = min(100, teacher.classOrder + 7)
            teacher.studentTrust = max(0, teacher.studentTrust - 2)
            if let target {
                raiseClassmateStress(id: target.id, delta: 4)
                message = "你走近\(target.name)，压低声音提醒。秩序回升得较慢，但没有把 TA 推到全班面前。"
            } else {
                message = "你低声提醒附近学生，把干预控制在小范围。"
            }
            addAudioCue(.whisper, direction: "过道近处", intensity: 0.42, note: "低声提醒降低公开羞辱，但管理效果也更慢。")
        case .care:
            teacher.studentsHelped += 1
            teacher.empathy += 3
            teacher.fatigue += 5
            teacher.studentTrust = min(100, teacher.studentTrust + 10)
            teacher.counselingCapacity = max(0, teacher.counselingCapacity - 12)
            teacher.kpiPressure += 3
            teacher.classRisk = max(0, teacher.classRisk - 8)
            player.teacherCareMoments += 1
            if let target {
                lowerClassmateStress(id: target.id, delta: 16)
                message = "你低声问\(target.name)：是不是需要缓一下？这会消耗时间和咨询容量，但能真实降低风险。"
            } else {
                player.psychicEnergy += 9
                player.stress = max(0, player.stress - 10)
                message = "你没有批评，只是问了句还好吗。权力第一次没有变成压力。"
            }
            addAudioCue(.whisper, direction: "过道近处", intensity: 0.38, note: "关心必须压低声音，才不会变成公开审判。")
        case .allowBreak:
            teacher.studentsHelped += 1
            teacher.fatigue += 4
            teacher.kpiPressure += 6
            teacher.classOrder = max(0, teacher.classOrder - 4)
            teacher.studentTrust = min(100, teacher.studentTrust + 8)
            teacher.counselingCapacity = max(0, teacher.counselingCapacity - 8)
            if let target {
                lowerClassmateStress(id: target.id, delta: 24)
                message = "你允许\(target.name)离开教室几分钟。班级管理风险上升，但这给了一个学生真实出口。"
            } else {
                message = "你允许一个明显不适的学生短暂离开。"
            }
            addAudioCue(.chair, direction: "过道到后门", intensity: 0.52, note: "允许离开会制造可见动作，也可能避免一次更大的崩溃。")
        case .ignore:
            teacher.kpiPressure += 6
            teacher.classOrder = max(0, teacher.classOrder - 4)
            teacher.studentTrust = min(100, teacher.studentTrust + 6)
            teacher.classRisk = max(0, teacher.classRisk - 3)
            teacher.fatigue = max(0, teacher.fatigue - 2)
            if let target {
                lowerClassmateStress(id: target.id, delta: 3)
                message = "你选择放过\(target.name)的小动作。学生信任回升，但 KPI 风险和表面秩序压力也回来了。"
            } else {
                lowerClassmateStress(delta: 2)
                message = "你选择放过一些小动作。你保护了恢复空间，也承担了被问责的风险。"
            }
            addAudioCue(.paper, direction: "教室四周", intensity: 0.3, note: "环境声回来了，说明紧张被暂时放低。")
        case .rest:
            teacher.focusMode = .blackboard
            teacher.location = .podium
            teacher.positionIndex = TeacherLocation.podium.positionIndex
            teacher.fatigue = max(0, teacher.fatigue - 14)
            teacher.counselingCapacity = min(100, teacher.counselingCapacity + 8)
            teacher.kpiPressure += 4
            teacher.classOrder = max(0, teacher.classOrder - 3)
            message = "你坐回讲台休息并看了一眼记录。疲惫下降，但巡视覆盖和表面秩序会变弱。"
            addAudioCue(.chair, direction: "讲台", intensity: 0.42, note: "椅子声暴露了老师的疲惫。")
        }

        teacher.classRisk = estimatedClassRisk
        clampTeacher()
        clampPlayer()
        updateClassmates(after: nil)
        recordSnapshot(actionLabel: "教师-\(action.rawValue)")
        if advanceTeacherTruthRunIfNeeded(after: action) {
            return
        }
        if currentTurn >= maxTurns {
            finish()
        } else {
            currentTurn += 1
            currentPhase = .observation
            updatePerception()
            applyTimeProgression()
            clampPlayer()
            maybeAddAnomalyMonologue()
            checkCriticalState()
        }
    }

    @discardableResult
    private func advanceTeacherTruthRunIfNeeded(after action: TeacherAction) -> Bool {
        guard isTeacherTruthRunActive else { return false }
        guard let objective = currentTeacherTruthObjective else {
            teacherTruthRunCompleted = true
            isTeacherTruthRunActive = false
            finish()
            return true
        }

        if action == objective.action {
            completedTeacherTruthObjectiveIDs.insert(objective.id)
            teacherTruthRunSummary = "真相二周目：\(completedTeacherTruthObjectiveIDs.count) / \(teacherTruthObjectives.count) · \(objective.title)"
            message += " 目标完成：\(objective.title)。"
            addAudioCue(.paper, direction: "讲台记录", intensity: 0.32, note: "教师把一次误读修正写进记录。")
        } else {
            teacher.fatigue += 1
            teacher.misreadRisk = min(100, teacher.misreadRisk + 2)
            message += " 当前真相目标仍是：\(objective.title)。"
        }

        if completedTeacherTruthObjectiveIDs.count >= teacherTruthObjectives.count {
            teacherTruthRunCompleted = true
            isTeacherTruthRunActive = false
            teacherTruthRunSummary = "真相二周目完成：看见、确认、关心、给出口"
            message = "教师真相二周目完成。你没有解决一切，但这一次，管理动作真的绕开了误读，给出了出口。"
            teacher.studentsHelped = max(teacher.studentsHelped, 2)
            teacher.empathy = min(100, teacher.empathy + 8)
            teacher.studentTrust = min(100, teacher.studentTrust + 8)
            finish()
            return true
        }

        return false
    }

    func continueAfterEvent() {
        if currentTurn >= maxTurns {
            if presentChapterOneDecisionIfNeeded() {
                return
            }
            finish()
            return
        }

        currentTurn += 1
        currentPhase = .observation
        gameState = .playing
        resumeFreeRoamAfterEvent()
        player.psychicEnergy = min(100, player.psychicEnergy + 4 + player.support / 30)
        recoverAttention(20)
        player.maskCost += 2
        player.stress += player.maskCost > 80 ? 8 : 2
        applyBodyNeeds()
        updateClassmates(after: nil)
        recordSnapshot(actionLabel: "事件后继续")
        updatePerception()
        applyTimeProgression()
        clampPlayer()
        maybeAddAnomalyMonologue()
        checkCriticalState()
    }

    private func beginBreakdownRecoverySequence() {
        activeBreakdownRecoverySteps = BreakdownRecoveryStep.allCases
        completedBreakdownRecoverySteps = []
        breakdownRecoverySummary = "0 / \(activeBreakdownRecoverySteps.count) · 先承认报警，再慢慢回来"
        presentBreakdownRecoveryStepEvent()
    }

    private func presentBreakdownRecoveryStepEvent() {
        guard let step = currentBreakdownRecoveryStep else { return }
        var choices = [EventChoice(
            id: "breakdown_\(step.rawValue)",
            title: step.title,
            detail: step.detail
        )]
        if completedBreakdownRecoverySteps.isEmpty {
            choices.append(EventChoice(id: "push_through", title: "继续硬撑", detail: "短期维持秩序，崩溃风险上升"))
        }
        presentEvent(
            kind: .playerBreakdown,
            title: "崩溃恢复 · \(step.title)",
            body: "你的角色感到不堪重负。这不是失败，这是信号。现在先完成一个很小的恢复动作，再决定下一步。",
            choices: choices
        )
    }

    private func advanceBreakdownRecovery(step: BreakdownRecoveryStep) {
        guard currentBreakdownRecoveryStep == step else { return }
        completedBreakdownRecoverySteps.insert(step)

        switch step {
        case .nameSignal:
            player.stress = max(0, player.stress - 10)
            player.maskCost = max(0, player.maskCost - 6)
            player.exposure = max(0, player.exposure - 4)
            addMonologue("这不是我不够努力，是身体在报警。先把它叫出来。", intensity: 0.72)
            addAudioCue(.heartbeat, direction: "胸口", intensity: 0.72, note: "心跳仍在，但已经从噪声变成了信号。")
            message = "你先承认这是过载信号。它没有立刻消失，但不再只像失败。"
        case .returnToBody:
            player.psychicEnergy += 18
            recoverAttention(24)
            player.stress = max(0, player.stress - 16)
            player.thirst = max(0, player.thirst - 8)
            player.waterCup = max(0, player.waterCup - 6)
            addMonologue("我摸到杯壁，听见自己的呼吸。教室还在，但我也还在。", intensity: 0.48)
            addAudioCue(.heartbeat, direction: "颅内到胸口", intensity: 0.48, note: "心跳声退后，灯管和纸页声重新回来。")
            message = "你用呼吸和触觉把注意力带回身体。问题还在，但报警音量降下去了。"
        case .acceptSupport:
            player.support += 16
            player.maskCost = max(0, player.maskCost - 12)
            player.exposure += settings.allowsWhispering ? 3 : 7
            teacher.empathy += 3
            improveDeskmates(delta: 12, stressRelief: 6)
            player.helpedClassmate = true
            addMonologue("我不用把整晚解释清楚，只要让一个人知道我刚才很难受。", intensity: 0.42)
            addAudioCue(.paper, direction: "左侧近处", intensity: 0.4, note: "同桌把草稿纸往你这边推近一点。")
            message = "你把一点真实状态交给同桌。支持网络没有解决一切，但它接住了这一下。"
        }

        breakdownRecoverySummary = "\(completedBreakdownRecoverySteps.count) / \(activeBreakdownRecoverySteps.count) · \(step.title)"
        clampPlayer()
        clampTeacher()
        recordSnapshot(actionLabel: step.title)
        updatePerception()

        if completedBreakdownRecoverySteps.count >= activeBreakdownRecoverySteps.count {
            breakdownRecoverySummary = "恢复完成：报警被看见，身体回来了，支持接上了"
            continueAfterEvent()
        } else {
            presentBreakdownRecoveryStepEvent()
        }
    }

    private func teacherTurn() {
        currentPhase = .teacherTurn
        let patrolStep = settings.patrolFrequency > 72 ? Int.random(in: 2...3) : Int.random(in: 1...2)
        teacher.positionIndex = (teacher.positionIndex + patrolStep) % 8
        teacher.isNearPlayer = [2, 3, 4].contains(teacher.positionIndex)
        teacher.location = TeacherLocation.closest(forPositionIndex: teacher.positionIndex)
        teacher.fatigue = min(100, teacher.fatigue + (1.4 + settings.patrolFrequency / 60) * currentPeriod.fatigueMultiplier)

        let pressure = teacher.kpiPressure * 0.22 + teacher.fatigue * 0.16 + settings.patrolFrequency * 0.08 - teacher.empathy * 0.12
        let discoveryRisk = player.exposure + pressure + (cameraPose == .desk ? 8 : 0) + (player.visualAttention < 18 ? 8 : 0)
        maybeAddTeacherStateCue(pressure: pressure)

        if activeChapter == .silentClassroom {
            if currentTurn < maxTurns { currentTurn += 1 }
            currentPhase = .observation
            updatePerception()
            clampPlayer()
            maybeAddAnomalyMonologue()
            return
        }

        if shouldFakePatrol(pressure: pressure, discoveryRisk: discoveryRisk) {
            teacher.positionIndex = max(0, teacher.positionIndex - 1)
            teacher.isNearPlayer = false
            teacher.location = TeacherLocation.closest(forPositionIndex: teacher.positionIndex)
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
            teacher.location = .rearDoor
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
        } else if !hasTriggeredPlayerBreakdown && player.breakdownRisk > 58 {
            hasTriggeredPlayerBreakdown = true
            appendEvent(title: "崩溃信号", detail: "心理能量、面具成本和暴露风险叠加到了危险区。")
            beginBreakdownRecoverySequence()
            addAudioCue(.heartbeat, direction: "颅内", intensity: 1.0, note: "外界声音退后，心跳和耳鸣占据中心。")
            audio.playWarning()
        } else {
            if currentTurn >= maxTurns, presentChapterOneDecisionIfNeeded() {
                clampPlayer()
                return
            }
            continueAfterEvent()
        }

        clampPlayer()
    }

    @discardableResult
    private func presentChapterOneDecisionIfNeeded() -> Bool {
        guard activeChapter == .silentClassroom,
              activeRole.isTeacher == false,
              hasPresentedChapterOneDecision == false else {
            return false
        }

        hasPresentedChapterOneDecision = true
        collectChapterClue(.unsignedNote, messageSuffix: "那张不署名纸条最终还是被你看见了。")
        presentEvent(
            kind: .classmateHelpRequest(classmateID: highestRiskClassmate?.id ?? 0),
            title: "关卡一结束：不署名纸条",
            body: "下课前，纸条压在你的草稿纸下面。你已经记录了 \(chapterClues.count) 条线索，但仍然不知道全部真相。现在要决定：这件事由谁一起承担。",
            choices: [
                EventChoice(id: "chapter1_teacher", title: "交给方老师", detail: "最快进入成人支持路径，也可能让当事人感到被曝光"),
                EventChoice(id: "chapter1_monitor", title: "找可靠班干部共同判断", detail: "形成同伴协作链，但会把责任分给另一个学生"),
                EventChoice(id: "chapter1_tomorrow", title: "明天再确认", detail: "尊重边界，但可能错过今晚的信息窗口"),
                EventChoice(id: "chapter1_wait", title: "下课后在走廊等一等", detail: "保留当事人的主动性，也承担独自等待的不确定")
            ]
        )
        return true
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
        if activeChapter == .silentClassroom {
            maybeAddAnomalyMonologue()
            return
        }
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
        clearScenePresentation()
        gameState = .ending(calculateEnding())
        audio.stop()
    }

    private func calculateEnding() -> Ending {
        if activeChapter == .silentClassroom, hasPresentedChapterOneDecision {
            return chapterOneEnding()
        }

        if activeRole.isTeacher || teacher.studentsWarned + teacher.studentsHelped > 4 {
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

    private func chapterOneEnding() -> Ending {
        let clueTitles = chapterClues.map(\.title).joined(separator: "、")
        let decision = chapterOneDecision.isEmpty ? "暂未决定" : chapterOneDecision
        let supportLine = "纸条仍然没有署名。下一章先跟随林澈进入走廊，纸条来源将在之后继续确认。"

        return Ending(
            title: "关卡一完成：静音的教室",
            body: "你没有看见全部真相，但已经发现了 \(chapterClues.count) 条值得被认真对待的信号：\(clueTitles.isEmpty ? "暂无明确线索" : clueTitles)。",
            reflection: "你的章末行动是：\(decision)。\(supportLine)",
            story: EndingStory(
                title: "关卡复盘：看见不是审判",
                body: "这一关的目标不是猜出谁一定有问题，而是在有限视野里承认异常值得被记录。遗漏不是失败，强行拯救也不是答案；重要的是找到能一起承担的人。",
                prompt: "回想这一关：哪个信号最早出现？你当时是选择确认、等待，还是继续完成自己的事？"
            ),
            empathyReflections: [
                EmpathyReflection(role: "苏念", icon: "person.fill", text: "你是心理委员，但不是专业咨询师。你能做的是看见、记录、陪在附近，并在风险升高时找到成人或同伴支持。"),
                EmpathyReflection(role: "同学", icon: "person.2.fill", text: "班级里的每个人都可能是线索来源，也可能正在被责任压着。协作不是把问题甩给别人，而是让支持链更稳。"),
                EmpathyReflection(role: "方老师", icon: "graduationcap.fill", text: "老师也只能从表面动作判断。你提供具体线索，而不是只说“有人不对劲”，会让成人支持更容易开始。")
            ],
            relationshipEchoes: relationshipEchoes(),
            analysis: [
                EndingMetric(title: "可靠线索", value: "\(chapterClues.count)", note: "来自实际观察，而不是状态数值或系统判断"),
                EndingMetric(title: "章末行动", value: decision, note: "第一章固定进入走廊主线，不设置安全性错误分支"),
                EndingMetric(title: "支持方式", value: player.helpedClassmate ? "已有连接" : "尚未外显", note: "低声询问、纸条和共同判断都会改变后续关系")
            ],
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
        let peaks = estimatedAnxietyPeaks
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
        let bodyNeed = Int(player.highestBodyNeed)
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
        let anxiousPeaks = estimatedAnxietyPeaks
        let energySpent = Int((100 - player.psychicEnergy).clamped(to: 0...100))
        let maskLoad = Int(player.maskCost)
        let supportBuffer = Int(player.support)
        let classRisk = classmates.filter { $0.stress > 76 || $0.state == .crying }.count

        return [
            EndingMetric(title: "焦虑峰值", value: "\(anxiousPeaks)", note: "按整晚连续高负荷片段估算"),
            EndingMetric(title: "心理消耗", value: "\(energySpent)", note: "今晚从能量池中消耗的近似值"),
            EndingMetric(title: "面具负荷", value: "\(maskLoad)", note: "维持好学生形象的心理成本"),
            EndingMetric(title: "支持缓冲", value: "\(supportBuffer)", note: "关系越强，崩溃阈值越高"),
            EndingMetric(title: "身体需求", value: "\(Int(player.highestBodyNeed))", note: "口渴、饥饿和如厕需求会抢走注意力"),
            EndingMetric(title: "班级风险", value: "\(classRisk)", note: "仍处于高压力或崩溃边缘的同学"),
            EndingMetric(title: "记忆延续", value: "\(classmateMemory.count)", note: "重开后仍会影响关系、压力余波和怀疑"),
            EndingMetric(title: "结束时间", value: clockText, note: currentPeriod.displayName),
            EndingMetric(title: "制度设置", value: "\(Int(settings.studyHours * 60))分", note: "\(settings.allowsWhispering ? "允许交流" : "禁止交流") · 排名 \(Int(settings.rankingPressure))")
        ] + extra
    }

    private func endingComparisons() -> [EndingComparison] {
        let anxiousPeaks = Double(estimatedAnxietyPeaks)
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
        supportResourceCatalog.resources
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
        player.thirst += currentPeriod.isBreak ? 2.0 : 3.6 * currentPeriod.fatigueMultiplier
        player.hunger += currentPeriod.isBreak ? 2.5 : 4.2 * currentPeriod.fatigueMultiplier
        player.bladder += currentPeriod.isBreak ? 1.8 : 3.1 * currentPeriod.fatigueMultiplier
        if player.thirst > 72 {
            player.stress += 2.2
            player.visualAttention = max(0, player.visualAttention - 1.8)
            if Double.random(in: 0...1) < 0.24 {
                addAudioCue(.heartbeat, direction: "喉咙", intensity: min(0.85, player.thirst / 120), note: "口渴会让注意力变得粗糙，越想忽略越明显。")
                addMonologue("嗓子开始发干，我才想起水杯也有容量。", intensity: 0.46)
            }
        }
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
            if activeRole.isTeacher == false && freeRoam.isActive == false {
                beginStudentFreeRoam(
                    duration: 300,
                    openingMessage: "\(clockText)，\(period.displayName)。课间自动开始，你可以自由活动 5 分钟；去接水、上厕所，或到一班前方左转门厅看向户外。"
                )
            }
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

        applySensoryPeerCue(after: action)

        // 第一章保留性格驱动的同学状态变化，但不让旧版随机事件抢占线索主线。
        if activeChapter == .silentClassroom { return }

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

    private func applySensoryPeerCue(after action: PlayerAction?) {
        let cue = SensoryPeerCue.derive(
            from: currentSensorySoundscape,
            classmates: classmates,
            playerSupport: player.support,
            allowsWhispering: settings.allowsWhispering
        )
        sensoryPeerCue = cue
        guard let cue else { return }

        if let index = classmates.firstIndex(where: { $0.id == cue.classmateID }) {
            switch cue.tone {
            case .support:
                classmates[index].state = .offeringHelp
                classmates[index].relationship = (classmates[index].relationship + 3).clamped(to: 0...100)
                classmates[index].hasSharedTruth = true
            case .warning:
                classmates[index].state = .lookingAtPlayer
                classmates[index].suspicionOfPlayer = max(0, classmates[index].suspicionOfPlayer - 4)
            case .body:
                classmates[index].state = .offeringHelp
                classmates[index].stress = max(0, classmates[index].stress - 3)
            case .institution:
                classmates[index].state = .anxious
            }
        }

        let signature = "\(currentTurn)-\(cue.id)-\(action?.rawValue ?? "none")"
        guard signature != lastSensoryPeerCueSignature else { return }
        lastSensoryPeerCueSignature = signature
        appendEvent(title: cue.eventTitle, detail: cue.eventDetail)
        if message.contains(cue.spokenLine) == false {
            message += " \(cue.classmateName)\(cue.spokenLine)"
        }
        addAudioCue(cue.audioKind, direction: cue.direction, intensity: cue.audioIntensity, note: cue.lowPressureAction)
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
        let roleLine = activeRole == .counselingPatrolTeacher
            ? "咨询容量 \(Int(teacher.counselingCapacity))，学生信任 \(Int(teacher.studentTrust))"
            : "KPI压力 \(Int(teacher.kpiPressure))，学生信任 \(Int(teacher.studentTrust))"
        return "教师视角：你作为\(activeRole.rawValue)在\(place)，\(mood)，\(roleLine)，同理心 \(Int(teacher.empathy))。你看见 \(suspicious) 个学生不太对劲，最担心的是\(riskName)：\(riskReason)。你也无法同时照顾所有人。"
    }

    private func appendEvent(title: String, detail: String) {
        eventLog.insert(EventLogEntry(turn: currentTurn, title: title, detail: detail), at: 0)
        if eventLog.count > 6 {
            eventLog.removeLast()
        }
    }

    func presentEvent(kind: ActiveEventKind, title: String, body: String, choices: [EventChoice]) {
        pauseFreeRoamForEvent()
        gameState = .event(ActiveEvent(kind: kind, title: title, body: body, choices: choices))
    }

    private func pauseFreeRoamForEvent() {
        guard freeRoam.isActive, freeRoamPausedAt == nil else { return }
        freeRoamPausedAt = Date()
    }

    private func resumeFreeRoamAfterEvent() {
        guard freeRoam.isActive, let pausedAt = freeRoamPausedAt else {
            freeRoamPausedAt = nil
            return
        }
        freeRoam.endsAt = freeRoam.endsAt.addingTimeInterval(Date().timeIntervalSince(pausedAt))
        freeRoamPausedAt = nil
    }

    func resolveEventChoice(_ choice: EventChoice) {
        guard case .event(let event) = gameState else { return }
        var shouldContinueAfterChoice = true
        var shouldFinishAfterChoice = false

        if event.kind == .playerBreakdown,
           let step = BreakdownRecoveryStep.allCases.first(where: { choice.id == "breakdown_\($0.rawValue)" }) {
            if activeBreakdownRecoverySteps.isEmpty {
                activeBreakdownRecoverySteps = BreakdownRecoveryStep.allCases
                completedBreakdownRecoverySteps = []
                breakdownRecoverySummary = "0 / \(activeBreakdownRecoverySteps.count) · 先承认报警，再慢慢回来"
            }
            advanceBreakdownRecovery(step: step)
            return
        }

        switch choice.id {
        case let id where id.hasPrefix("chapter1_linche_"):
            resolveChapterOneLinCheDialogue(choice)
            return
        case "chapter1_read_note":
            confirmChapterOneNotePickup(source: .overlay)
            message = "你没有在教室里追问，只把这张纸条当作一个需要被认真对待的信号。"
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
            player.exposure += 4
            player.maskCost = max(0, player.maskCost - 2)
            beginStudentFreeRoam()
            shouldContinueAfterChoice = false
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
        case "chapter1_teacher":
            chapterOneDecision = "交给方老师"
            teacher.studentsHelped += 1
            teacher.empathy += 2
            player.support += 8
            player.maskCost += 4
            addMonologue("我不是把责任推走，是承认这件事不能只靠一个学生扛。", intensity: 0.58)
            message = "你把纸条交给方老师。她没有立刻追问是谁写的，只先问你还记得哪些细节。下一关会从成人支持链开始。"
            shouldContinueAfterChoice = false
            shouldFinishAfterChoice = true
        case "chapter1_monitor":
            chapterOneDecision = "找可靠班干部共同判断"
            player.support += 12
            player.psychicEnergy -= 4
            player.maskCost += 3
            addMonologue("找人一起判断，比一个人猜答案更踏实，也更沉。", intensity: 0.52)
            message = "你找到一个可靠班干部共同判断。事情没有解决，但支持链多了一个节点。下一关会出现协作行动。"
            shouldContinueAfterChoice = false
            shouldFinishAfterChoice = true
        case "chapter1_tomorrow":
            chapterOneDecision = "明天再确认"
            player.exposure = max(0, player.exposure - 8)
            player.stress += 6
            player.maskCost += 6
            addMonologue("我把纸条收好，可它今晚不会因为被收好就变轻。", intensity: 0.66)
            message = "你决定明天再确认。这个选择保留了边界，也留下了不确定。下一关可用信息会更少。"
            shouldContinueAfterChoice = false
            shouldFinishAfterChoice = true
        case "chapter1_wait":
            chapterOneDecision = "下课后在走廊等一等"
            player.support += 5
            player.stress += 4
            player.exposure += 4
            addMonologue("我不能替那个人说话，但我可以让走廊里多一个愿意等的人。", intensity: 0.56)
            message = "你决定下课后在走廊等一等。不追问、不围堵，只留下一个可以开口的位置。下一关会从走廊等待开始。"
            shouldContinueAfterChoice = false
            shouldFinishAfterChoice = true
        default:
            message = "你让这个瞬间过去了。"
        }

        clampPlayer()
        clampTeacher()
        maybeAddAnomalyMonologue()
        if shouldFinishAfterChoice {
            recordSnapshot(actionLabel: choice.title)
            finish()
            return
        }
        if shouldContinueAfterChoice == false {
            recordSnapshot(actionLabel: choice.title)
            updatePerception()
            return
        }
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
        publishDirectionalSubtitle(for: cue)
        audio.updateListener(position: listenerPosition, orientation: listenerOrientation)
        audio.playCue(kind: kind, intensity: cue.intensity, position: spatialPosition(for: direction))
    }

    private func publishDirectionalSubtitle(for cue: AudioCue) {
        guard accessibilityPreferences.directionalSubtitles else { return }
        directionalSubtitleEvents.insert(
            DirectionalSubtitleEvent(
                turn: cue.turn,
                kind: cue.kind,
                direction: cue.direction,
                intensity: cue.intensity,
                note: cue.note
            ),
            at: 0
        )
        if directionalSubtitleEvents.count > 5 {
            directionalSubtitleEvents.removeLast()
        }
    }

    private func publishCompanionNavigationWhisperIfNeeded() {
        guard let status = narrativeCampaign.companionPresenceStatus,
              status.mode == .following,
              let navigationLine = status.navigationLine,
              navigationLine.isEmpty == false else {
            lastCompanionNavigationWhisperAudioKey = ""
            return
        }
        let cue = ChapterThreeNavigationCue.derive(from: narrativeCampaign)
        let audioKey = [
            narrativeCampaign.currentMoment.id,
            cue?.targetID ?? "",
            navigationLine
        ].joined(separator: "|")
        guard audioKey != lastCompanionNavigationWhisperAudioKey else { return }
        lastCompanionNavigationWhisperAudioKey = audioKey
        let direction = status.companionID == "周予安" ? "左侧同伴" : "右侧同伴"
        let intensity = 0.36 + (cue?.pulseIntensity ?? 0.42) * 0.28
        addAudioCue(
            .whisper,
            direction: direction,
            intensity: intensity,
            note: navigationLine
        )
    }

    private func addMonologue(_ text: String, intensity: Double) {
        monologues.insert(InnerMonologue(turn: currentTurn, text: text, intensity: intensity.clamped(to: 0...1)), at: 0)
        if monologues.count > 5 {
            monologues.removeLast()
        }
        guard activeRole.isTeacher == false, intensity >= 0.48 else { return }
        let presentation = FeaturedMonologue(text: text, intensity: intensity.clamped(to: 0...1))
        featuredMonologue = presentation
        monologueDismissTask?.cancel()
        monologueDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(intensity >= 0.75 ? 5.2 : 4.0))
            guard Task.isCancelled == false, self?.featuredMonologue?.id == presentation.id else { return }
            self?.featuredMonologue = nil
        }
    }

    func dismissFeaturedMonologue() {
        monologueDismissTask?.cancel()
        featuredMonologue = nil
    }

    private func collectChapterClue(for action: PlayerAction) {
        guard activeChapter == .silentClassroom, activeRole.isTeacher == false, hasPresentedChapterOneDecision == false else { return }

        switch chapterOneStep {
        case .observeLinChe where action == .observe && cameraPose == .left:
            guard isFullNarrativeRun == false || chapterOneLocatedAudioSteps.contains(.observeLinChe) else {
                message += " 你还只是看向左边，先听清翻书声停在哪里。"
                return
            }
            collectChapterClue(.linChePage, messageSuffix: "林澈的书停在同一页太久了，笔尖也没有动。")
            advanceChapterOne(to: .locateHiddenSound, cue: "右侧传来一声很轻的鼻息，又被翻书声盖住。")
        case .locateHiddenSound where action == .observe && cameraPose == .right:
            guard isFullNarrativeRun == false || chapterOneLocatedAudioSteps.contains(.locateHiddenSound) else {
                message += " 你还没有把那一下鼻息和方向对上。"
                return
            }
            collectChapterClue(.hiddenCrying, messageSuffix: "那不是椅子声。有人在努力把情绪压回去。")
            advanceChapterOne(to: .regulateSelf, cue: "方老师的脚步靠近，视线开始有一点散。")
            addBackgroundSignalReaction()
        case .regulateSelf where action == .breathe || action == .drink:
            addMonologue("我也在这间教室里。先让自己缓一下，才听得清别人。", intensity: 0.64)
            advanceChapterOne(to: .approachLinChe, cue: "林澈抬头看了一眼门口，开始把笔收回笔袋。")
        case .approachLinChe where action == .talk || action == .note:
            if isFullNarrativeRun {
                presentChapterOneLinCheDialogueIfNeeded()
            } else {
                player.helpedClassmate = true
                addMonologue("他说没事，可那句话落得太快了，像是早就练习过。", intensity: 0.62)
                addAudioCue(.paper, direction: "桌面右侧", intensity: 0.58, note: "前排同学起身时，一张折过的纸滑到桌边。")
                advanceChapterOne(to: .inspectNote, cue: "铃声响起，一张纸从桌边滑了下来。")
            }
        case .inspectNote where (action == .observe && cameraPose == .desk) || action == .note:
            guard isFullNarrativeRun == false || chapterOneLocatedAudioSteps.contains(.inspectNote) || action == .note else {
                message += " 纸边刚才响在桌面右侧，先把声源和纸片对上。"
                return
            }
            if isFullNarrativeRun {
                confirmChapterOneNotePickup(source: .player)
            } else {
                collectChapterClue(.unsignedNote, messageSuffix: "纸条没有署名：心里很难受，但我不知道找谁说。")
                advanceChapterOne(to: .followLinChe, cue: "你再抬头时，林澈已经走到教室门口。")
            }
        default:
            message += " 这还不能确认当前目标。"
        }
    }

    private enum ChapterOneNotePickupSource {
        case player
        case overlay
        case fallback
    }

    private func presentChapterOneLinCheDialogueIfNeeded() {
        guard chapterOneStep == .approachLinChe else { return }
        if chapterOneLinCheDialogueCue != nil {
            triggerChapterOneNoteDropIfNeeded(presentOverlay: isFullNarrativeRun)
            advanceChapterOne(to: .inspectNote, cue: "铃声响起，一张纸从桌边滑了下来。")
            return
        }
        presentEvent(
            kind: .linCheDialogue,
            title: "林澈说：没事",
            body: "他回答得太快了。你只有很短的一句话可以说，最好不要把他逼到全班视线里。",
            choices: [
                EventChoice(
                    id: "chapter1_linche_listen",
                    title: "“要不要出去透口气？”",
                    detail: "听见异常，也给他保留不开口的空间"
                ),
                EventChoice(
                    id: "chapter1_linche_wait",
                    title: "“下课后我在走廊等你。”",
                    detail: "不立刻追问，只留下稍后可以开口的位置"
                ),
                EventChoice(
                    id: "chapter1_linche_mask",
                    title: "“没事就好。”",
                    detail: "降低当下暴露，但也把门关上了一点"
                )
            ]
        )
    }

    private func resolveChapterOneLinCheDialogue(_ choice: EventChoice) {
        guard let cue = ChapterOneLinCheDialogueCue.resolve(choiceID: choice.id),
              chapterOneStep == .approachLinChe else {
            continueAfterEvent()
            return
        }
        if chapterOneLinCheDialogueCue == nil {
            chapterOneLinCheDialogueCue = cue
            completedChapterOneBeatIDs.insert("chapter1.linCheDialogue")
            player.helpedClassmate = cue.listenScore > 0
            player.support += Double(4 + cue.listenScore * 4)
            player.maskCost = max(0, player.maskCost - Double(cue.listenScore * 3))
            addMonologue("他说没事，可那句话落得太快了，像是早就练习过。", intensity: 0.62)
            appendEvent(title: "林澈回应", detail: "\(cue.responseLine) \(cue.outcomeLine)")
            addAudioCue(
                cue.trust == .closed ? .paper : .whisper,
                direction: "左侧同桌",
                intensity: 0.38 + Double(cue.listenScore) * 0.12,
                note: cue.outcomeLine
            )
        }

        let shouldPresentNoteOverlay = isFullNarrativeRun
        triggerChapterOneNoteDropIfNeeded(presentOverlay: shouldPresentNoteOverlay)
        advanceChapterOne(to: .inspectNote, cue: "\(cue.outcomeLine) 铃声响起，一张纸从桌边滑了下来。")
        clampPlayer()
        recordSnapshot(actionLabel: choice.title)
        saveFullNarrativeChapterOneIfNeeded()
        if shouldPresentNoteOverlay {
            return
        }
        gameState = .playing
        resumeFreeRoamAfterEvent()
    }

    private func triggerChapterOneNoteDropIfNeeded(presentOverlay: Bool) {
        let beatID = "chapter1.noteDrop"
        guard completedChapterOneBeatIDs.contains(beatID) == false,
              chapterClues.contains(where: { $0.id == .unsignedNote }) == false else {
            return
        }
        completedChapterOneBeatIDs.insert(beatID)
        chapterOneNoteDropCue = ChapterOneNoteDropCue(
            triggerTurn: currentTurn,
            chairCuePlayed: true,
            bellCuePlayed: true,
            paperVisible: true,
            overlayPresented: presentOverlay,
            overlayDismissed: false
        )
        updateChapterOneLinChePerformance()
        addAudioCue(.chair, direction: "前排到桌边", intensity: 0.62, note: "前排椅子擦过地面，纸边顺着桌角滑近。")
        addAudioCue(.bell, direction: "走廊远处", intensity: 0.72, note: "下课铃盖住了一瞬间的纸张摩擦。")
        appendEvent(title: "纸条滑落", detail: ChapterOneNoteDropCue.content)

        if presentOverlay {
            presentEvent(
                kind: .noteDrop,
                title: "不署名纸条",
                body: ChapterOneNoteDropCue.content,
                choices: [
                    EventChoice(
                        id: "chapter1_read_note",
                        title: "把纸条收好",
                        detail: "确认你看见了，但不在这里追问是谁写的"
                    )
                ]
            )
        }
    }

    private func confirmChapterOneNotePickup(source: ChapterOneNotePickupSource) {
        triggerChapterOneNoteDropIfNeeded(presentOverlay: false)
        chapterOneNoteDropCue?.paperVisible = false
        chapterOneNoteDropCue?.overlayDismissed = true
        updateChapterOneLinChePerformance()
        collectChapterClue(.unsignedNote, messageSuffix: "纸条没有署名：心里很难受，但我不知道找谁说。")
        let cue: String
        switch source {
        case .player:
            cue = "你再抬头时，林澈已经走到教室门口。"
        case .overlay:
            cue = "你把纸条收进口袋。铃声退下去时，林澈已经站起身。"
        case .fallback:
            cue = "纸条滑到桌边更亮的位置。你终于看清了那行字。"
        }
        advanceChapterOne(to: .followLinChe, cue: cue)
    }

    private func advanceChapterOne(to step: ChapterOneStep, cue: String) {
        chapterOneStep = step
        chapterOneDwellFocus.resetForStep(keeping: cameraPose)
        message = cue
        switch step {
        case .approachLinChe:
            completedChapterOneBeatIDs.insert("chapter1.linCheGlanceDoor")
        case .followLinChe, .completed:
            completedChapterOneBeatIDs.insert("chapter1.linCheExitPath")
        default:
            break
        }
        updateChapterOneLinChePerformance()
        if let objective = currentSpatialAudioObjective {
            addAudioCue(
                objective.cueKind,
                direction: objective.direction,
                intensity: max(0.28, objective.cueIntensity - 0.12),
                note: objective.sourceLine
            )
        }
        saveFullNarrativeChapterOneIfNeeded()
    }

    private func updateChapterOneLinChePerformance() {
        linChePerformanceCue = LinChePerformanceCue.derive(
            step: chapterOneStep,
            noteDropCue: chapterOneNoteDropCue
        )
    }

    private func markCurrentSpatialAudioTargetIfMatched() {
        guard let objective = currentSpatialAudioObjective,
              cameraPose == objective.targetPose,
              chapterOneLocatedAudioSteps.contains(objective.step) == false else { return }
        chapterOneLocatedAudioSteps.insert(objective.step)
        addAudioCue(
            objective.cueKind,
            direction: objective.direction,
            intensity: objective.cueIntensity,
            note: "\(objective.sourceLine) \(objective.confirmAction)。"
        )
        appendEvent(title: objective.title, detail: "\(objective.direction)：\(objective.sourceLine)")
        message += " \(objective.statusLine)"
        publishFocusFeedback(for: objective.targetPose)
    }

    private static func locatedAudioStep(for clue: ChapterClue) -> ChapterOneStep? {
        switch clue.id {
        case .linChePage:
            return .observeLinChe
        case .hiddenCrying:
            return .locateHiddenSound
        case .unsignedNote:
            return .inspectNote
        case .monitorOverload, .teacherSigh:
            return nil
        }
    }

    private func saveFullNarrativeChapterOneIfNeeded() {
        guard isFullNarrativeRun, narrativeCampaign.isActive == false else { return }
        saveNarrativeCampaign()
    }

    private func addBackgroundSignalReaction() {
        guard let classmate = classmates.filter({ $0.id > 4 }).randomElement() else { return }
        let reaction = "\(classmate.name)\(classmate.profile.signalReaction)。"
        message += " \(reaction)"
        appendEvent(title: "班级反应", detail: reaction)
    }

    private func completeChapterOne() {
        chapterOneStep = .completed
        hasPresentedChapterOneDecision = true
        chapterOneDecision = "跟随林澈进入走廊"
        player.posture = .standing
        completedChapterOneBeatIDs.insert("chapter1.linCheExitPath")
        updateChapterOneLinChePerformance()
        addAudioCue(.chair, direction: "桌边", intensity: 0.66, note: "你起身时椅子轻响，林澈的脚步正越过前门。")
        addMonologue("纸条还不知道是谁写的。但林澈现在不该一个人走。", intensity: 0.78)
        message = "你把纸条收进口袋，起身跟上林澈。教室的声音留在身后，走廊尽头的镜子亮着。"
        recordSnapshot(actionLabel: "跟上林澈")
        if isFullNarrativeRun {
            narrativeCampaign.startAfterPlayableChapterOne(linCheTrust: chapterOneLinCheTrust.campaignTrustSeed)
            isFullNarrativeRun = false
            gameState = .playing
            message = narrativeCampaign.currentMoment.goal
            presentScenePresentation(for: narrativeCampaign.chapter)
            saveNarrativeCampaign()
            return
        }
        finish()
    }

    private func collectChapterClue(_ id: ChapterClueID, messageSuffix: String) {
        guard chapterClues.contains(where: { $0.id == id }) == false else { return }
        guard chapterClues.count < 5 else { return }
        chapterClues.append(ChapterClue(id: id, turn: currentTurn, title: id.title, detail: id.detail))
        appendEvent(title: "线索：\(id.title)", detail: id.detail)
        message += " \(messageSuffix)"
        addMonologue(chapterClueMonologue(for: id), intensity: id == .unsignedNote ? 0.72 : 0.48)
        addAudioCue(id == .teacherSigh ? .teacherSigh : .paper, direction: clueAudioDirection(for: id), intensity: id == .unsignedNote ? 0.56 : 0.34, note: id.detail)
    }

    private func chapterClueMonologue(for clue: ChapterClueID) -> String {
        switch clue {
        case .linChePage:
            return "他看起来一直很稳，可稳不等于没事。"
        case .hiddenCrying:
            return "那道声音很轻。藏得住，不代表它不值得被听见。"
        case .monitorOverload:
            return "班干部也会被责任压住，只是他们更习惯把累藏起来。"
        case .teacherSigh:
            return "老师也在压力里。她能不能看见我们，也取决于她还剩多少力气。"
        case .unsignedNote:
            return "这张纸条不是给我的，却落到了我这里。也许它是在找一个能一起承担的人。"
        }
    }

    private func clueAudioDirection(for clue: ChapterClueID) -> String {
        switch clue {
        case .linChePage: return "左侧近处"
        case .hiddenCrying: return "右侧近处"
        case .monitorOverload: return "后方左侧"
        case .teacherSigh: return "讲台前方"
        case .unsignedNote: return "桌面"
        }
    }

    func maybeAddAnomalyMonologue() {
        guard activeRole.isTeacher == false else { return }
        if player.psychicEnergy <= 24 {
            addAnomalyMonologue(key: "energy", text: "眼前的字开始黏在一起。我可能不是懒，是需要先停一下。", intensity: 0.82)
        }
        if player.stress >= 78 {
            addAnomalyMonologue(key: "stress", text: "身体一直绷着，连风扇声都像催促。也许我需要先把呼吸放慢。", intensity: 0.78)
        }
        if player.maskCost >= 72 {
            addAnomalyMonologue(key: "mask", text: "我把表情摆得太久了，久到快分不清自己是不是真的没事。", intensity: 0.76)
        }
        if player.exposure >= 74 {
            addAnomalyMonologue(key: "exposure", text: "我好像太显眼了。现在最需要的不是再确认一次，而是先收回动作。", intensity: 0.72)
        }
        if player.visualAttention <= 18 {
            addAnomalyMonologue(key: "attention", text: "视线开始散，声音反而变近。可能该换一个低消耗动作。", intensity: 0.7)
        }
        if player.thirst >= 76 {
            addAnomalyMonologue(key: "thirst", text: "喉咙干得让我读不进题。身体需求不会因为晚自习安静就消失。", intensity: 0.68)
        }
        if player.hunger >= 80 {
            addAnomalyMonologue(key: "hunger", text: "胃里空得发紧。注意力不是只靠意志力撑出来的。", intensity: 0.68)
        }
        if player.bladder >= 82 {
            addAnomalyMonologue(key: "bladder", text: "我一直在忍，忍到连题目都只剩下背景。可能该找一个合法出口。", intensity: 0.72)
        }
    }

    private func addAnomalyMonologue(key: String, text: String, intensity: Double) {
        let previousTurn = lastAnomalyMonologueTurn[key] ?? -99
        guard currentTurn - previousTurn >= 3 else { return }
        lastAnomalyMonologueTurn[key] = currentTurn
        addMonologue(text, intensity: intensity)
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
        return SCNVector3(-1.2, player.posture == .standing ? 1.58 : 1.18, 1.5)
    }

    private var listenerOrientation: SCNVector3 {
        viewMode == .teacher ? SCNVector3(-0.12, 0, 0) : cameraPose.angles
    }

    private func spatialPosition(for direction: String) -> SCNVector3 {
        let base = listenerPosition
        let hasLeft = direction.contains("左")
        let hasRight = direction.contains("右")
        let hasFront = direction.contains("前")
        let hasRear = direction.contains("后")
        if direction.contains("颅内") {
            return base
        }
        if direction.contains("头顶") {
            return SCNVector3(base.x, base.y + 1.2, base.z)
        }
        if direction.contains("桌面") || direction.contains("桌边") {
            return SCNVector3(base.x + 0.25, 0.78, base.z - 0.12)
        }
        if direction.contains("同伴") {
            if hasLeft {
                return SCNVector3(base.x - 0.62, 1.08, base.z + 0.08)
            }
            if hasRight {
                return SCNVector3(base.x + 0.62, 1.08, base.z + 0.08)
            }
            return SCNVector3(base.x, 1.08, base.z + 0.22)
        }
        if direction.contains("讲台") {
            return SCNVector3(0, 1.2, -4.4)
        }
        if direction.contains("过道") {
            return SCNVector3(1.6, 1.0, base.z - 1.2)
        }
        if direction.contains("窗外") {
            return SCNVector3(-4.1, 1.45, 1.2)
        }
        if hasLeft && hasFront {
            return SCNVector3(base.x - 1.05, 1.0, base.z - 1.45)
        }
        if hasRight && hasFront {
            return SCNVector3(base.x + 1.05, 1.0, base.z - 1.45)
        }
        if hasLeft && hasRear {
            return SCNVector3(base.x - 1.05, 1.0, base.z + 1.35)
        }
        if hasRight && hasRear {
            return SCNVector3(base.x + 1.05, 1.0, base.z + 1.35)
        }
        if hasFront {
            return SCNVector3(base.x, 1.05, base.z - 1.55)
        }
        if hasRear {
            return SCNVector3(-3.95, 1.2, 4.25)
        }
        if hasLeft {
            return SCNVector3(base.x - (direction.contains("极近") ? 0.35 : 0.95), 1.0, base.z - 0.25)
        }
        if hasRight {
            return SCNVector3(base.x + (direction.contains("极近") ? 0.35 : 0.95), 1.0, base.z - 0.25)
        }
        if direction.contains("四周") {
            return SCNVector3(0, 1.2, 0)
        }
        return SCNVector3(base.x, base.y, base.z - 0.8)
    }

    #if DEBUG
    func debugSpatialPositionForAudioCueDirection(_ direction: String) -> SCNVector3 {
        spatialPosition(for: direction)
    }
    #endif

    func selectReplay(offset: Int) {
        guard !replay.isEmpty else { return }
        selectedReplayIndex = (selectedReplayIndex + offset).clamped(to: 0...(replay.count - 1))
    }

    var selectedReplay: TurnSnapshot? {
        guard replay.indices.contains(selectedReplayIndex) else { return nil }
        return replay[selectedReplayIndex]
    }

    var estimatedAnxietyPeaks: Int {
        guard replay.isEmpty == false else {
            let currentLoad = anxietyLoad(
                energy: player.psychicEnergy,
                stress: player.stress,
                exposure: player.exposure,
                support: player.support,
                bodyNeed: player.highestBodyNeed,
                maskCost: player.maskCost
            )
            return max(1, currentLoad >= 70 ? 1 : Int(ceil(player.stress / 35)))
        }

        var count = 0
        var isInsidePeak = false
        for snapshot in replay {
            let load = anxietyLoad(
                energy: snapshot.energy,
                stress: snapshot.stress,
                exposure: snapshot.exposure,
                support: snapshot.support,
                bodyNeed: snapshot.bodyNeed,
                maskCost: snapshot.maskCost
            )
            let entersPeak = load >= 70 || snapshot.stress >= 74
            let exitsPeak = load < 58 && snapshot.stress < 64

            if entersPeak && !isInsidePeak {
                count += 1
                isInsidePeak = true
            }
            if isInsidePeak && exitsPeak {
                isInsidePeak = false
            }
        }

        return max(1, count)
    }

    var teacherPostgameReflection: TeacherPostgameReflection {
        let riskStudents = classmates.filter { $0.stress > 76 || $0.state == .crying }.count
        let observedIssues = classmates.filter { $0.state == .usingPhone || $0.state == .sleeping || $0.state == .crying }.count
        let managementLoad = (settings.rankingPressure * 0.42 + settings.patrolFrequency * 0.32 + teacher.fatigue * 0.26).clamped(to: 0...100)
        let peakStress = replay.map(\.stress).max() ?? player.stress
        let lowestEnergy = replay.map(\.energy).min() ?? player.psychicEnergy
        let highExposureTurns = replay.filter { $0.exposure > 58 }.count
        let actionText = replay.map(\.actionLabel).joined(separator: "、")
        let riskiestName = highestRiskClassmate?.name ?? "那个状态最紧的学生"
        let riskiestReason = highestRiskClassmate?.riskReason ?? "风险原因不清楚"
        func timeText(_ ratio: Double) -> String {
            let minutes = Int(Double(settings.totalMinutes) * ratio)
            let total = 18 * 60 + 30 + minutes
            return String(format: "%02d:%02d", total / 60, total % 60)
        }
        let monologue: String

        if teacher.studentsWarned > teacher.studentsHelped && teacher.institutionalPressure > 62 {
            monologue = "我今晚确实让教室安静了，可安静不等于安全。KPI 像一只手推着我去提醒、去巡视，却没有给我足够时间判断每个动作背后是挑衅、疲惫，还是求救。"
        } else if teacher.studentsHelped >= max(1, teacher.studentsWarned) {
            monologue = "我没有把每一次异常都当成纪律问题。低声问一句会多花时间，也会让我承担管理风险，但有些学生真正需要的不是更响的提醒，而是一个可以缓一下的出口。"
        } else if teacher.fatigue > 72 {
            monologue = "到后半段我也累了。疲惫会让判断变窄，看见小动作时更容易先想到扣分和问责，而不是这个学生为什么撑不住。"
        } else {
            monologue = "这间教室表面上很普通，但每个学生都在用不同方式撑住自己。教师视角能看见秩序，也应该提醒我：秩序之外还有真实状态。"
        }

        let middleText: String
        if highExposureTurns > 0 {
            middleText = "中段开始，我看到你有几次动作不太稳：可能是低头、桌面小动作，或者视线突然离开作业。站在讲台上，我无法知道那是想偷懒、想休息，还是身体已经撑不住。我只能先按“可能影响全班”的方式处理。"
        } else if lowestEnergy < 28 {
            middleText = "中段时，教室看起来很安静，但你的能量已经明显下去了。问题是，老师最容易看见的是动作，不是能量；一个太安静的学生，反而可能被我漏掉。"
        } else {
            middleText = "中段时，我一直在看全班节奏：谁停笔了，谁在抬头，谁因为紧张开始反复翻书。你们看到的是老师在走动，我看到的是一整间教室的风险在同时变化。"
        }

        let lateText: String
        if teacher.fatigue > 70 {
            lateText = "后半段我也开始疲惫。老师累的时候，判断会变短：更容易先维持秩序，更难蹲下来问一句“你是不是不舒服”。这不是借口，但确实是今晚管理质量下降的原因。"
        } else if teacher.studentsHelped > teacher.studentsWarned {
            lateText = "后半段我尽量把声音压低，因为公开批评会让一个学生更难说真话。关心也有风险：时间被占用、其他学生会看见、班级秩序可能松动，但有时这比多一次提醒更重要。"
        } else {
            lateText = "后半段我仍然要盯住纪律，因为一个班不是只有一个学生。只要有手机光、椅子声或低语扩散，整间教室的注意力都会被拉走，最后被追责的通常也是老师。"
        }

        let segments = [
            TeacherMonologueSegment(
                time: timeText(0),
                title: "开场：先保住整间教室",
                text: "晚自习刚开始，我先看的不是某一个人，而是全班有没有进入状态。今天 KPI 是 \(Int(settings.rankingPressure))，巡视要求 \(Int(settings.patrolFrequency))。如果一开始就松，后面很难收回来。"
            ),
            TeacherMonologueSegment(
                time: timeText(0.36),
                title: "中段：我只能从表面判断",
                text: middleText
            ),
            TeacherMonologueSegment(
                time: timeText(0.72),
                title: "后段：疲惫会压缩同理心",
                text: lateText
            ),
            TeacherMonologueSegment(
                time: clockText,
                title: "结束：我也带着不确定离开",
                text: "这一晚结束时，我记得提醒了 \(teacher.studentsWarned) 次，关心了 \(teacher.studentsHelped) 次，也可能错过了 \(riskStudents) 个真正需要帮助的学生。最让我不安的是 \(riskiestName)：\(riskiestReason)。老师并不是总能知道答案，很多时候只能在不完整的信息里做选择。"
            )
        ]

        let analysis = [
            TeacherAnalysisPoint(
                title: "老师先承担的是班级责任",
                detail: "站在老师这边看，第一任务不是判断某个学生是不是难受，而是保证二十个人还能继续学习。秩序一旦散掉，老师会被问责，全班也会受影响。",
                icon: "person.3.fill"
            ),
            TeacherAnalysisPoint(
                title: "KPI 会让判断变窄",
                detail: "排名压力 \(Int(settings.rankingPressure))、巡视要求 \(Int(settings.patrolFrequency)) 会把老师推向更快、更硬的管理动作。提醒学生不一定是老师冷漠，有时是系统给老师留下的最短路径。",
                icon: "chart.bar.fill"
            ),
            TeacherAnalysisPoint(
                title: "老师看到的是表面证据",
                detail: "学生知道自己是累、饿、焦虑或想喘口气，但老师通常只看到低头、停笔、手机光、椅子声。误读不一定来自恶意，而是信息天然不对称。",
                icon: "eye.fill"
            ),
            TeacherAnalysisPoint(
                title: "关心也有现实成本",
                detail: "低声关心一个学生需要时间、空间和班级信任。老师担心被其他学生理解成偏心，也担心一对一处理时顾不上全班。",
                icon: "heart.text.square.fill"
            ),
            TeacherAnalysisPoint(
                title: "疲惫会消耗耐心",
                detail: "教师疲惫 \(Int(teacher.fatigue)) 时，同理心不会消失，但会变得更难调用。学生理解这一点，不是替粗暴管理开脱，而是看见老师也在压力系统里。",
                icon: "battery.25percent"
            ),
            TeacherAnalysisPoint(
                title: "更好的沟通需要双方降低成本",
                detail: "如果学生能用低风险方式表达“我需要缓一下”，老师就更容易把管理从抓纪律转向给出口；如果制度允许短暂恢复，老师也不用每次都靠提醒维持秩序。",
                icon: "bubble.left.and.bubble.right.fill"
            )
        ]

        let studentTakeaway: String
        if actionText.contains("说自己太累") || actionText.contains("低声道谢") || actionText.contains("请求") {
            studentTakeaway = "这局里你曾经把真实状态露出一点点，所以老师更有机会理解你。理解老师的难处，不是要求学生忍耐一切，而是让你知道：清楚、低风险地表达需要，会让老师更容易站到你这边。"
        } else if teacher.studentsWarned > teacher.studentsHelped {
            studentTakeaway = "今晚你可能感到老师一直在管、在盯、在提醒。但从老师这边看，她也在被 KPI、全班秩序和问责压力推着走。理解这一点，能帮助你把“老师针对我”改写成“我需要找到更容易被理解的求助方式”。"
        } else {
            studentTakeaway = "老师并不是天然站在学生对面。她也需要线索、时间和制度空间，才能把一个异常动作理解成求助。学生理解老师的难处，能让沟通从对抗变成共同降压。"
        }

        return TeacherPostgameReflection(
            monologue: monologue,
            segments: segments,
            analysis: analysis,
            studentTakeaway: studentTakeaway,
            metrics: [
                EndingMetric(title: "今日KPI", value: "\(Int(settings.rankingPressure))", note: "排名和纪律考核压力"),
                EndingMetric(title: "巡视要求", value: "\(Int(settings.patrolFrequency))", note: "越高越容易制造位置压力"),
                EndingMetric(title: "管理负荷", value: "\(Int(managementLoad))", note: "由 KPI、巡视和疲惫估算"),
                EndingMetric(title: "教师疲惫", value: "\(Int(teacher.fatigue))", note: "疲惫会提高误读概率"),
                EndingMetric(title: "同理心", value: "\(Int(teacher.empathy))", note: "越高越可能转向关心"),
                EndingMetric(title: "提醒/关心", value: "\(teacher.studentsWarned)/\(teacher.studentsHelped)", note: "前者维持秩序，后者提供支持"),
                EndingMetric(title: "可见异常", value: "\(observedIssues)", note: "手机、困倦、崩溃等表面信号"),
                EndingMetric(title: "高风险学生", value: "\(riskStudents)", note: "压力过高或已经外显"),
                EndingMetric(title: "压力峰值", value: "\(Int(peakStress))", note: "老师只能通过外显动作间接感知"),
                EndingMetric(title: "高暴露回合", value: "\(highExposureTurns)", note: "老师最容易注意到的表面异常")
            ]
        )
    }

    var mechanicExplanations: [MechanicExplanation] {
        let currentAnxietyLoad = anxietyLoad(
            energy: player.psychicEnergy,
            stress: player.stress,
            exposure: player.exposure,
            support: player.support,
            bodyNeed: player.highestBodyNeed,
            maskCost: player.maskCost
        )
        return [
            MechanicExplanation(
                title: "焦虑峰值",
                formula: "压力 + 身体需求×0.25 + 暴露×0.20 + 能量缺口×0.35 + 面具×0.15 - 支持×0.20 ≥ 70",
                note: "系统按整晚回放统计连续高负荷片段，低于 58 后才允许记为下一次峰值。当前负荷约 \(Int(currentAnxietyLoad))，本局估算 \(estimatedAnxietyPeaks) 次。"
            ),
            MechanicExplanation(
                title: "崩溃预警",
                formula: "压力 + 面具×0.45 + 暴露×0.25 - 心理能量 - 支持×0.18 > 58",
                note: "当前崩溃风险约 \(Int(player.breakdownRisk))。预警一局只触发一次，避免玩家被同一种高压状态反复打断。"
            ),
            MechanicExplanation(
                title: "失控与保护",
                formula: "心理能量 ≤ 5 或 压力 ≥ 96",
                note: "达到硬阈值时，如果支持网络高于 55，会先触发支持网络保护；否则直接进入结局。"
            ),
            MechanicExplanation(
                title: "同学焦虑",
                formula: "同学压力 > 76 为焦虑，> 92 为崩溃",
                note: "同学压力会受排名压力、巡视、个人焦虑基线、面具强度、是否允许交流和玩家互动影响。"
            )
        ]
    }

    var performanceReview: PerformanceReview {
        let actionText = replay.map(\.actionLabel).joined(separator: " ")
        let peakStress = replay.map(\.stress).max() ?? player.stress
        let lowestEnergy = replay.map(\.energy).min() ?? player.psychicEnergy
        let highestBodyNeed = replay.map(\.bodyNeed).max() ?? player.highestBodyNeed
        var strengths: [ReviewPoint] = []
        var improvements: [ReviewPoint] = []

        if actionText.contains("深呼吸") || actionText.contains("看窗外") || actionText.contains("洗") || actionText.contains("休息") {
            strengths.append(ReviewPoint(title: "使用了恢复动作", detail: "你没有只用硬撑解决压力，至少有一次让身体先降下来。", icon: "wind"))
        }
        if player.helpedClassmate || actionText.contains("同桌") || actionText.contains("求助") {
            strengths.append(ReviewPoint(title: "建立过连接", detail: "你让支持网络进入了这一晚。连接会降低崩溃阈值附近的孤立感。", icon: "person.2.fill"))
        }
        if player.homework >= 60 {
            strengths.append(ReviewPoint(title: "完成了学习目标", detail: "在压力存在的情况下仍推进了作业，说明角色并不是“不努力”。", icon: "book.fill"))
        }
        if player.exposure < 55 {
            strengths.append(ReviewPoint(title: "风险控制较稳", detail: "暴露值没有长期停在高位，说明你在观察、行动和收手之间做过权衡。", icon: "eye.slash.fill"))
        }
        if highestBodyNeed < 72 {
            strengths.append(ReviewPoint(title: "身体需求未完全失控", detail: "口渴、饥饿和如厕需求没有压过全部注意力，身体报警保持在可处理范围。", icon: "figure.core.training"))
        }
        if strengths.isEmpty {
            strengths.append(ReviewPoint(title: "撑到了复盘时刻", detail: "即使过程很乱，你仍然留下了可回看的数据和选择。复盘本身就是改善入口。", icon: "checkmark.circle.fill"))
        }

        if player.maskCost > 66 {
            improvements.append(ReviewPoint(title: "面具负荷偏高", detail: "为了显得正常消耗了太多能量。下次可以更早用低风险方式求助或短暂恢复。", icon: "theatermasks.fill"))
        }
        if peakStress > 78 {
            improvements.append(ReviewPoint(title: "压力峰值过高", detail: "压力曾经进入危险区。连续写作业或高暴露动作之间需要插入恢复动作。", icon: "waveform.path.ecg"))
        }
        if player.support < 34 {
            improvements.append(ReviewPoint(title: "支持网络太薄", detail: "支持低时，同样的压力更容易变成孤独感。一次纸条或低声确认就能改变阈值。", icon: "link"))
        }
        if player.exposure > 68 {
            improvements.append(ReviewPoint(title: "暴露风险偏高", detail: "手机、纸条、零食和回头确认会叠加风险。高风险后要及时切回低暴露动作。", icon: "exclamationmark.triangle.fill"))
        }
        if highestBodyNeed > 78 {
            improvements.append(ReviewPoint(title: "身体需求被拖太久", detail: "口渴、饥饿或如厕需求会抢走注意力。下次可以更早喝水、补水、吃零食、举手或课间恢复。", icon: "figure.stand"))
        }
        if lowestEnergy < 20 {
            improvements.append(ReviewPoint(title: "能量见底后仍在硬撑", detail: "低能量会放大同样的压力。能量低于 25 时，优先恢复比继续加速更有效。", icon: "battery.25percent"))
        }
        if player.homework < 35 && player.exposure > 45 {
            improvements.append(ReviewPoint(title: "恢复方式成本偏高", detail: "你获得了一些逃离感，但作业进度和暴露风险的交换不太划算。", icon: "iphone"))
        }
        if improvements.isEmpty {
            improvements.append(ReviewPoint(title: "节奏比较平衡", detail: "本局没有明显单项失控。后续可以尝试更高排名压力或不同交流规则，看系统如何变化。", icon: "slider.horizontal.3"))
        }

        let encouragement: String
        if player.stress >= 90 || player.psychicEnergy <= 12 {
            encouragement = "这不是“做得差”，而是系统把你推到了过载边缘。真正有价值的是识别最早的报警信号，而不是责怪最后的失控。"
        } else if player.helpedClassmate || player.support >= 55 {
            encouragement = "你没有把晚自习只玩成个人生存。能在压力里保留一点连接，是这一局最重要的进步。"
        } else if player.homework >= 70 {
            encouragement = "你完成了很多任务，但结算也提醒你：结果好不代表代价低。下次可以试着让完成度和恢复空间同时存在。"
        } else {
            encouragement = "这一晚没有标准答案。你做的每个选择都在学习、身体、关系和风险之间交换，复盘能帮你找到更低成本的下一次。"
        }

        return PerformanceReview(strengths: strengths, improvements: improvements, encouragement: encouragement)
    }

    private func anxietyLoad(energy: Double, stress: Double, exposure: Double, support: Double, bodyNeed: Double, maskCost: Double) -> Double {
        (stress + bodyNeed * 0.25 + exposure * 0.20 + (100 - energy) * 0.35 + maskCost * 0.15 - support * 0.20)
            .clamped(to: 0...120)
    }

    private func recordSnapshot(actionLabel: String) {
        let visible = visibleSceneDescription(actionLabel: actionLabel)
        let truth = innerTruthDescription(actionLabel: actionLabel)
        let teacherView = teacherInterpretationDescription()
        let metrics = "能量 \(Int(player.psychicEnergy)) · 压力 \(Int(player.stress)) · 面具 \(Int(player.maskCost)) · 支持 \(Int(player.support)) · 暴露 \(Int(player.exposure)) · 口渴 \(Int(player.thirst)) · 饥饿 \(Int(player.hunger)) · 如厕 \(Int(player.bladder)) · 杯水 \(Int(player.waterCup))"
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
            bodyNeed: player.highestBodyNeed
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
        guard let data = storage.data(forKey: memoryStoreKey) else {
            return [:]
        }
        return (try? JSONDecoder().decode([Int: ClassmateMemory].self, from: data)) ?? [:]
    }

    private func saveClassmateMemory() {
        if classmateMemory.isEmpty {
            storage.removeObject(forKey: memoryStoreKey)
            return
        }
        guard let data = try? JSONEncoder().encode(classmateMemory) else {
            return
        }
        storage.set(data, forKey: memoryStoreKey)
    }

    private func clampPlayer() {
        player.psychicEnergy = player.psychicEnergy.clamped(to: 0...100)
        player.maskCost = player.maskCost.clamped(to: 0...100)
        player.support = player.support.clamped(to: 0...100)
        player.stress = player.stress.clamped(to: 0...100)
        player.exposure = player.exposure.clamped(to: 0...100)
        player.homework = player.homework.clamped(to: 0...100)
        player.thirst = player.thirst.clamped(to: 0...100)
        player.hunger = player.hunger.clamped(to: 0...100)
        player.bladder = player.bladder.clamped(to: 0...100)
        player.waterCup = player.waterCup.clamped(to: 0...100)
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
        teacher.studentTrust = teacher.studentTrust.clamped(to: 0...100)
        teacher.counselingCapacity = teacher.counselingCapacity.clamped(to: 0...100)
        teacher.classOrder = teacher.classOrder.clamped(to: 0...100)
        teacher.classRisk = teacher.classRisk.clamped(to: 0...100)
        teacher.misreadRisk = teacher.misreadRisk.clamped(to: 0...100)
    }

    private func makeClassmates() -> [Classmate] {
        let names = ["林澈", "周予安", "江越", "陈言", "许栀", "何屿", "唐宁", "沈星", "顾言", "叶舟", "韩夏", "白辰", "陆遥", "秦一", "苏禾", "姜南", "程川", "宋也", "黎昕"]
        var result: [Classmate] = []
        var id = 0
        for row in 0..<5 {
            for column in 0..<4 {
                if row == 2 && column == 1 { continue }
                let name = names[id % names.count]
                let isDeskmate = row == 2 && (column == 0 || column == 2)
                let profile = classmateProfile(id: id)
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

    private func classmateProfile(id: Int) -> ClassmateProfile {
        switch id {
        case 0: // 林澈：学习委员，完美主义和高面具强度固定
            return ClassmateProfile(cooperation: 72, orderliness: 91, rebelliousness: 12, empathy: 66, anxiety: 78, maskStrength: 92)
        case 1: // 周予安：班长，可靠但容易过度承担
            return ClassmateProfile(cooperation: 90, orderliness: 86, rebelliousness: 10, empathy: 70, anxiety: 58, maskStrength: 76)
        case 2: // 江越：危机主线当事人，回避且认为自己是负担
            return ClassmateProfile(cooperation: 34, orderliness: 62, rebelliousness: 24, empathy: 74, anxiety: 91, maskStrength: 84)
        case 3: // 陈言：纪律委员，守序且容易把关心变成控制
            return ClassmateProfile(cooperation: 62, orderliness: 94, rebelliousness: 8, empathy: 42, anxiety: 46, maskStrength: 70)
        case 4: // 许栀：文体委员，擅长低压力接近
            return ClassmateProfile(cooperation: 84, orderliness: 42, rebelliousness: 54, empathy: 88, anxiety: 32, maskStrength: 48)
        default:
            break
        }

        // 普通同学每局重新抽取性格。同一套事件规则会因此产生不同反应。
        func value(_ base: Double, spread: Double) -> Double {
            (base + Double.random(in: (-spread / 2)...(spread / 2))).clamped(to: 5...95)
        }
        return ClassmateProfile(
            cooperation: value(54, spread: 70),
            orderliness: value(56, spread: 76),
            rebelliousness: value(44, spread: 72),
            empathy: value(52, spread: 78),
            anxiety: value(42, spread: 82),
            maskStrength: value(56, spread: 74)
        )
    }
}

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
