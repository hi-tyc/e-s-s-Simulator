import AppKit
import SceneKit
import XCTest
import SwiftUI
@testable import LateStudySimulator

@MainActor
final class MovementAndEventTests: XCTestCase {
    func testPrologueStartsBeforeChapterOneAndUsesNamedFirstBeat() {
        let game = GameManager()

        game.startPrologue(resume: false)

        XCTAssertTrue(game.isPrologueActive)
        XCTAssertEqual(game.prologueCurrentBeat, .gateArrival)
        XCTAssertEqual(game.prologueCurrentBeat.currentGoal, "走进教学楼")
        XCTAssertTrue(game.player.posture == .standing)
    }

    func testPrologueBeatCompletionIsIdempotent() {
        let game = GameManager()
        game.startPrologue(resume: false)

        game.completePrologueBeat(.gateArrival, source: .performance)
        XCTAssertEqual(game.prologueCurrentBeat, .lookDownHall)
        game.completePrologueBeat(.gateArrival, source: .fallback)

        XCTAssertEqual(game.prologueCurrentBeat, .lookDownHall)
        XCTAssertEqual(game.prologueState.completedBeats, [.gateArrival])
    }

    func testPrologueFallbackFreezesWhileAnyPauseReasonRemains() {
        let game = GameManager()
        game.startPrologue(resume: false)
        game.completePrologueBeat(.gateArrival, source: .performance)
        game.setProloguePaused(true)
        game.setApplicationActive(false)

        game.tickPrologue(delta: 20)
        XCTAssertEqual(game.prologueCurrentBeat, .lookDownHall)

        game.setProloguePaused(false)
        game.tickPrologue(delta: 20)
        XCTAssertEqual(game.prologueCurrentBeat, .lookDownHall)

        game.setApplicationActive(true)
        game.tickPrologue(delta: 12)
        XCTAssertEqual(game.prologueCurrentBeat, .returnToSeat)
        XCTAssertTrue(game.prologueState.lookTutorialCompleted)
    }

    func testPrologueFallbackStillMarksBasicTutorialAsCompleted() {
        let game = GameManager()
        game.startPrologue(resume: false)
        game.completePrologueBeat(.gateArrival, source: .performance)

        game.tickPrologue(delta: 12)
        XCTAssertTrue(game.prologueState.lookTutorialCompleted)
        game.tickPrologue(delta: 12)
        XCTAssertTrue(game.prologueState.movementTutorialCompleted)
        game.tickPrologue(delta: 12)
        XCTAssertTrue(game.prologueState.interactionTutorialCompleted)
    }

    func testPrologueLookFallbackPublishesPersistentHallEcho() throws {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.startPrologue(resume: false)
        game.completePrologueBeat(.gateArrival, source: .performance)

        game.tickPrologue(delta: 12)

        XCTAssertEqual(game.prologueCurrentBeat, .returnToSeat)
        let echo = try XCTUnwrap(game.prologueState.lastBeatEcho)
        XCTAssertEqual(echo.beat, .lookDownHall)
        XCTAssertEqual(echo.source, .fallback)
        XCTAssertEqual(echo.title, "你注意到了走廊里的动静")
        XCTAssertTrue(echo.detail.contains("自然转头"))

        let data = try JSONEncoder().encode(game.prologueState)
        let restored = try JSONDecoder().decode(PrologueState.self, from: data)
        XCTAssertEqual(restored.lastBeatEcho, echo)
    }

    func testPrologueBeatEchoViewRendersVisibleFeedback() throws {
        let echo = PrologueBeatEcho(beat: .lookDownHall, source: .fallback)
        let renderer = ImageRenderer(content: ZStack {
            Color.black
            PrologueBeatEchoView(echo: echo)
                .padding(12)
                .frame(width: 270, alignment: .leading)
        }
        .frame(width: 320, height: 120))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 320, height: 120)

        guard let image = renderer.nsImage else {
            XCTFail("PrologueBeatEchoView did not render")
            return
        }
        let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        var visibleSamples = 0
        var brightSamples = 0
        for y in stride(from: 8, to: bitmap.pixelsHigh, by: 8) {
            for x in stride(from: 8, to: bitmap.pixelsWide, by: 8) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                if luminance > 0.018 { visibleSamples += 1 }
                if luminance > 0.32 { brightSamples += 1 }
            }
        }
        XCTAssertGreaterThan(visibleSamples, 38)
        XCTAssertGreaterThan(brightSamples, 3)

        if let path = ProcessInfo.processInfo.environment["CAPTURE_PROLOGUE_BEAT_ECHO_VIEW"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: path))
        }
    }

    func testProloguePerformanceAdvancesPublicSceneInformation() {
        let game = GameManager()
        game.startPrologue(resume: false)

        game.tickPrologue(delta: 8)

        XCTAssertTrue(game.message.contains("球场"))
        XCTAssertEqual(game.audioCues.first?.direction, "身后远处")
    }

    func testLinCheOccupiesSeatToPlayerLeft() {
        let game = GameManager()
        game.startGame()

        let linChe = game.classmates.first { $0.name == "林澈" }
        XCTAssertEqual(linChe?.seat.row, 2)
        XCTAssertEqual(linChe?.seat.column, 0)
    }

    func testFullNarrativeCampaignPublishesChapterOneIntroPresentation() {
        let game = GameManager()

        game.startFullNarrativeCampaign()

        XCTAssertTrue(game.scenePresentation.isActive)
        XCTAssertEqual(game.scenePresentation.chapter, .classroom)
        XCTAssertEqual(game.scenePresentation.title, NarrativeChapter.classroom.title)
        XCTAssertEqual(game.scenePresentation.subtitle, StoryChapter.silentClassroom.objective)
        XCTAssertEqual(game.scenePresentation.transition, .fade)
        XCTAssertEqual(game.scenePresentation.phase, .prepare)
    }

    func testNarrativeSaveStoresOnlyStableScenePresentationDuringActiveTransition() throws {
        let defaults = isolatedUserDefaults()
        let game = GameManager(userDefaults: defaults)

        game.developerJump(to: .mirror)

        let data = try XCTUnwrap(defaults.data(forKey: NarrativeSaveStoreKeys.current))
        let save = try JSONDecoder().decode(NarrativeSave.self, from: data)
        XCTAssertNil(save.validationFailure)
        XCTAssertEqual(save.campaign.chapter, .mirror)
        XCTAssertEqual(save.scenePresentation.chapter, .mirror)
        XCTAssertEqual(save.scenePresentation.transition, .mirrorRipple)
        XCTAssertEqual(save.scenePresentation.phase, .idle)
        XCTAssertFalse(save.scenePresentation.isActive)
        XCTAssertTrue(save.checkpointID.hasPrefix("chapter.2."))
        XCTAssertNotNil(defaults.data(forKey: NarrativeSaveStoreKeys.lastValid))
    }

    func testNarrativeSaveFallsBackToLastValidWhenCurrentSlotIsCorrupt() throws {
        let defaults = isolatedUserDefaults()
        let firstRun = GameManager(userDefaults: defaults)
        firstRun.developerJump(to: .noteTrace, momentIndex: 2)
        let lastValidData = try XCTUnwrap(defaults.data(forKey: NarrativeSaveStoreKeys.lastValid))

        defaults.set(Data("not-json".utf8), forKey: NarrativeSaveStoreKeys.current)
        defaults.set(lastValidData, forKey: NarrativeSaveStoreKeys.lastValid)

        let restored = GameManager(userDefaults: defaults)

        XCTAssertEqual(restored.narrativeCampaign.chapter, .noteTrace)
        XCTAssertEqual(restored.narrativeCampaign.currentMoment.id, "3.companion")
        XCTAssertEqual(restored.gameState, .playing)
        XCTAssertTrue(restored.narrativeSaveRecoveryNotice?.contains("稳定检查点") == true)
        XCTAssertTrue(restored.narrativeSaveRecoveryNotice?.contains("无法解码") == true)
    }

    func testNarrativeSaveRejectsTransitionMidFrameAndUsesLastStableCheckpoint() throws {
        let defaults = isolatedUserDefaults()
        var stableCampaign = NarrativeCampaign()
        stableCampaign.startAfterPlayableChapterOne()
        var stableSave = NarrativeSave(saveRevision: 12, campaign: stableCampaign)
        XCTAssertNil(stableSave.validationFailure)
        defaults.set(try JSONEncoder().encode(stableSave), forKey: NarrativeSaveStoreKeys.lastValid)

        stableCampaign.chapter = .stairwell
        stableCampaign.prepareRuntimeStateForCurrentChapter()
        stableCampaign.exploration.reset(for: .stairwell)
        stableSave = NarrativeSave(saveRevision: 13, campaign: stableCampaign)
        stableSave.scenePresentation.phase = .prepare
        stableSave.scenePresentation.phaseStartedAt = .now
        defaults.set(try JSONEncoder().encode(stableSave), forKey: NarrativeSaveStoreKeys.current)

        let restored = GameManager(userDefaults: defaults)

        XCTAssertEqual(restored.narrativeCampaign.chapter, .mirror)
        XCTAssertEqual(restored.scenePresentation.phase, .idle)
        XCTAssertTrue(restored.narrativeSaveRecoveryNotice?.contains("转场中间帧") == true)
    }

    func testLegacyNarrativeCampaignSaveMigratesIntoDoubleSlotSave() throws {
        let defaults = isolatedUserDefaults()
        var legacy = NarrativeCampaign()
        legacy.startAfterPlayableChapterOne()
        legacy.chapter = .counseling
        legacy.prepareRuntimeStateForCurrentChapter()
        legacy.exploration.reset(for: .counseling)
        defaults.set(try JSONEncoder().encode(legacy), forKey: NarrativeSaveStoreKeys.legacyCampaign)

        let restored = GameManager(userDefaults: defaults)

        XCTAssertEqual(restored.narrativeCampaign.chapter, .counseling)
        XCTAssertTrue(restored.narrativeSaveRecoveryNotice?.contains("迁移旧版") == true)
        let currentData = try XCTUnwrap(defaults.data(forKey: NarrativeSaveStoreKeys.current))
        let currentSave = try JSONDecoder().decode(NarrativeSave.self, from: currentData)
        XCTAssertEqual(currentSave.campaign.chapter, .counseling)
        XCTAssertNil(currentSave.validationFailure)
    }

    func testDeveloperJumpUsesChapterSpecificScenePresentationStyle() {
        let game = GameManager()

        game.developerJump(to: .mirror)

        XCTAssertTrue(game.scenePresentation.isActive)
        XCTAssertEqual(game.scenePresentation.chapter, .mirror)
        XCTAssertEqual(game.scenePresentation.subtitle, NarrativeChapter.mirror.sceneSubtitle)
        XCTAssertEqual(game.scenePresentation.transition, .mirrorRipple)
        XCTAssertEqual(game.scenePresentation.phase, .prepare)
    }

    func testScenePresentationContractsFullNarrativeHUDToMinimalControls() {
        let game = GameManager(userDefaults: isolatedUserDefaults())

        game.startFullNarrativeCampaign()

        XCTAssertTrue(game.scenePresentation.isActive)
        XCTAssertTrue(game.shouldUseMinimalNarrativeHUD)
        XCTAssertFalse(game.chapterCurrentObjective.isEmpty)

        game.narrativeCampaign.isActive = true

        XCTAssertFalse(game.shouldUseMinimalNarrativeHUD)
    }

    func testScenePresentationCardRendersVisibleChapterIntro() throws {
        let presentation = ScenePresentationState(
            chapter: .mirror,
            title: NarrativeChapter.mirror.title,
            subtitle: NarrativeChapter.mirror.sceneSubtitle,
            transition: .mirrorRipple,
            phase: .prepare,
            startedAt: .now,
            phaseStartedAt: .now
        )
        let renderer = ImageRenderer(content: ZStack {
            Color.black
            ContentView.ScenePresentationCardView(
                presentation: presentation,
                presence: 0.86,
                phaseProgress: 0.54,
                maxWidth: 680,
                bottomInset: 68,
                classmates: [
                    Classmate(
                        id: 1,
                        name: "林澈",
                        seat: (row: 2, column: 0),
                        profile: ClassmateProfile(
                            cooperation: 78,
                            orderliness: 44,
                            rebelliousness: 26,
                            empathy: 86,
                            anxiety: 34,
                            maskStrength: 48
                        ),
                        support: 74,
                        stress: 38,
                        state: .studying,
                        relationship: 72,
                        hasSharedTruth: true,
                        suspicionOfPlayer: 8
                    )
                ],
                playerSupport: 58
            )
        }
        .frame(width: 960, height: 540))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 960, height: 540)

        guard let image = renderer.nsImage else {
            XCTFail("ScenePresentationCardView did not render")
            return
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        var minimum = 1.0
        var maximum = 0.0
        var visibleSamples = 0
        for y in stride(from: 8, to: bitmap.pixelsHigh, by: 24) {
            for x in stride(from: 8, to: bitmap.pixelsWide, by: 24) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                minimum = min(minimum, luminance)
                maximum = max(maximum, luminance)
                if luminance > 0.012 { visibleSamples += 1 }
            }
        }
        XCTAssertGreaterThan(visibleSamples, 80)
        XCTAssertGreaterThan(maximum - minimum, 0.14)

        if let path = ProcessInfo.processInfo.environment["CAPTURE_SCENE_PRESENTATION_CARD"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }
    }

    func testReduceMotionSuppressesScenePresentationCameraMotion() throws {
        let date = Date(timeIntervalSinceReferenceDate: 10_000)
        let presentation = ScenePresentationState(
            chapter: .mirror,
            title: NarrativeChapter.mirror.title,
            subtitle: NarrativeChapter.mirror.sceneSubtitle,
            transition: .mirrorRipple,
            phase: .prepare,
            startedAt: date,
            phaseStartedAt: date
        )
        let animatedIntensity = ScenePresentationMotionProfile.phaseIntensity(
            for: presentation,
            reduceMotion: false,
            at: date.addingTimeInterval(0.38)
        )
        let reducedIntensity = ScenePresentationMotionProfile.phaseIntensity(
            for: presentation,
            reduceMotion: true,
            at: date.addingTimeInterval(0.38)
        )

        XCTAssertGreaterThan(animatedIntensity, 0.5)
        XCTAssertEqual(reducedIntensity, 0)
    }

    func testSupportResourceCatalogLoadsPrimaryHotlineAndValidation() throws {
        let catalog = try SupportResourceCatalog.load()

        XCTAssertEqual(catalog.resources.count, 3)
        XCTAssertEqual(catalog.primaryHotline?.number, "12356")
        XCTAssertEqual(catalog.primaryHotline?.displayName, "全国统一心理援助热线")
        XCTAssertFalse(catalog.validate(on: SupportResource.dateFormatter.date(from: "2026-07-23")!, buildPolicy: .debug).hasExpiredResources)

        let staleResource = SupportResource(
            id: "stale",
            region: "中国大陆",
            displayName: "过期资源",
            number: "0000",
            detail: "测试用过期项",
            url: nil,
            reviewedAt: SupportResource.dateFormatter.date(from: "2025-01-01")!,
            sourceURL: "local://stale",
            sourceTitle: "测试来源"
        )
        let validation = SupportResourceCatalog(resources: [staleResource]).validate(on: SupportResource.dateFormatter.date(from: "2026-07-23")!, buildPolicy: .debug)
        XCTAssertTrue(validation.hasExpiredResources)
        XCTAssertEqual(validation.expiredResources.first?.id, "stale")
    }

    func testAudioSceneProfilesSwitchAcrossNarrativeSpaces() {
        let audio = SpatialAudioManager()

        audio.transitionScene(to: NarrativeChapter.classroom.audioSceneID)
        let classroom = audio.targetSceneMix
        audio.transitionScene(to: NarrativeChapter.mirror.audioSceneID)
        let mirror = audio.targetSceneMix
        audio.transitionScene(to: NarrativeChapter.counseling.audioSceneID)
        let counseling = audio.targetSceneMix

        XCTAssertEqual(classroom.sceneID, "classroom")
        XCTAssertEqual(mirror.sceneID, "mirror")
        XCTAssertEqual(counseling.sceneID, "counseling")
        XCTAssertGreaterThan(mirror.mirrorResonance, classroom.mirrorResonance)
        XCTAssertGreaterThan(mirror.mirrorResonance, counseling.mirrorResonance)
        XCTAssertLessThan(counseling.outsideAmount, mirror.outsideAmount)
        XCTAssertLessThan(counseling.reverbLevel, mirror.reverbLevel)
    }

    func testDirectionalSubtitleEventsRespectGlobalToggle() {
        let game = GameManager(userDefaults: isolatedUserDefaults())

        game.startPrologue(resume: false)
        game.tickPrologue(delta: 8)
        XCTAssertEqual(game.directionalSubtitleEvents.first?.kind, .footstep)
        XCTAssertTrue(game.directionalSubtitleEvents.first?.caption.contains("身后远处") == true)

        game.updateAccessibilityPreferences { $0.directionalSubtitles = false }
        XCTAssertTrue(game.directionalSubtitleEvents.isEmpty)
        let audioCueCountAfterDisable = game.audioCues.count

        game.tickPrologue(delta: 18)
        XCTAssertGreaterThan(game.audioCues.count, audioCueCountAfterDisable)
        XCTAssertTrue(game.directionalSubtitleEvents.isEmpty)

        game.updateAccessibilityPreferences { $0.directionalSubtitles = true }
        game.tickPrologue(delta: 17)
        XCTAssertEqual(game.directionalSubtitleEvents.first?.kind, .broadcast)
        XCTAssertTrue(game.directionalSubtitleEvents.first?.accessibilitySummary.contains("楼道深处") == true)
    }

    func testNarrativeAudioDynamicsShapeEffectiveMixWithoutChangingBaseSceneProfile() {
        let audio = SpatialAudioManager()
        audio.transitionScene(to: NarrativeChapter.stairwell.audioSceneID)
        let base = audio.targetSceneMix

        audio.updateNarrativeDynamics(NarrativeAudioDynamics(
            riskPulse: 0.86,
            supportWarmth: 0.12,
            privacyDamping: 0.05,
            ruptureTension: 0.74,
            choiceImpactPulse: 0.7
        ))
        let tense = audio.effectiveTargetSceneMix

        audio.updateNarrativeDynamics(NarrativeAudioDynamics(
            riskPulse: 0.22,
            supportWarmth: 0.88,
            privacyDamping: 0.72,
            ruptureTension: 0.0,
            choiceImpactPulse: 0.18
        ))
        let protected = audio.effectiveTargetSceneMix

        XCTAssertEqual(audio.targetSceneMix, base)
        XCTAssertEqual(tense.sceneID, "stairwell")
        XCTAssertGreaterThan(tense.ambientNoise, base.ambientNoise)
        XCTAssertGreaterThan(tense.mirrorResonance, base.mirrorResonance)
        XCTAssertGreaterThan(tense.reverbLevel, base.reverbLevel)
        XCTAssertLessThan(protected.ambientNoise, tense.ambientNoise)
        XCTAssertLessThan(protected.reverbLevel, tense.reverbLevel)
        XCTAssertGreaterThan(protected.outsideAmount, base.outsideAmount)
    }

    func testNarrativeChoiceImpactShapesAudioDynamicsAndEffectiveMix() {
        var supportiveCampaign = NarrativeCampaign(isActive: true, chapter: .stairwell, momentIndex: 1)
        supportiveCampaign.companionID = "周予安"
        supportiveCampaign.choose("dialogue.listen")

        var ruptureCampaign = NarrativeCampaign(isActive: true, chapter: .stairwell, momentIndex: 1)
        ruptureCampaign.companionID = "周予安"
        ruptureCampaign.choose("dialogue.advise")

        let supportive = NarrativeAudioDynamics.derive(from: supportiveCampaign)
        let rupture = NarrativeAudioDynamics.derive(from: ruptureCampaign)

        XCTAssertGreaterThan(rupture.choiceImpactPulse, supportive.choiceImpactPulse)
        XCTAssertGreaterThan(rupture.riskPulse, supportive.riskPulse)
        XCTAssertGreaterThan(supportive.supportWarmth, rupture.supportWarmth)

        let audio = SpatialAudioManager()
        audio.transitionScene(to: NarrativeChapter.stairwell.audioSceneID)
        audio.updateNarrativeDynamics(supportive)
        let supportiveMix = audio.effectiveTargetSceneMix
        audio.updateNarrativeDynamics(rupture)
        let ruptureMix = audio.effectiveTargetSceneMix

        XCTAssertGreaterThan(ruptureMix.ambientNoise, supportiveMix.ambientNoise)
        XCTAssertGreaterThan(ruptureMix.mirrorResonance, supportiveMix.mirrorResonance)
        XCTAssertGreaterThan(ruptureMix.reverbLevel, supportiveMix.reverbLevel)
        XCTAssertEqual(audio.targetSceneMix.sceneID, "stairwell")
    }

    func testNarrativeChoiceImpactPublishesSpatialAudioEvent() throws {
        let supportiveGame = GameManager(userDefaults: isolatedUserDefaults())
        supportiveGame.developerJump(to: .stairwell, momentIndex: 1)
        supportiveGame.narrativeCampaign.exploration.positionX = 0.1
        supportiveGame.narrativeCampaign.exploration.positionZ = -1.65
        XCTAssertTrue(supportiveGame.interactNarrativeHotspot())
        supportiveGame.advanceNarrative("dialogue.listen")
        let supportiveEvent = try XCTUnwrap(supportiveGame.audio.lastNarrativeImpactAudioEvent)

        let ruptureGame = GameManager(userDefaults: isolatedUserDefaults())
        ruptureGame.developerJump(to: .stairwell, momentIndex: 1)
        ruptureGame.narrativeCampaign.exploration.positionX = 0.1
        ruptureGame.narrativeCampaign.exploration.positionZ = -1.65
        XCTAssertTrue(ruptureGame.interactNarrativeHotspot())
        ruptureGame.advanceNarrative("dialogue.advise")
        let ruptureEvent = try XCTUnwrap(ruptureGame.audio.lastNarrativeImpactAudioEvent)

        XCTAssertEqual(supportiveEvent.id, "4.listen.0.dialogue.listen")
        XCTAssertEqual(supportiveEvent.tone, .support)
        XCTAssertEqual(supportiveEvent.cueKind, .whisper)
        XCTAssertLessThan(supportiveEvent.intensity, ruptureEvent.intensity)
        XCTAssertLessThan(supportiveEvent.positionX, ruptureEvent.positionX)

        XCTAssertEqual(ruptureEvent.id, "4.listen.0.dialogue.advise")
        XCTAssertEqual(ruptureEvent.tone, .risk)
        XCTAssertEqual(ruptureEvent.cueKind, .heartbeat)
        XCTAssertGreaterThan(ruptureEvent.intensity, 0.8)
    }

    func testInvalidNarrativeChoiceDoesNotPublishImpactAudioEvent() {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.developerJump(to: .stairwell, momentIndex: 1)
        game.narrativeCampaign.exploration.positionX = 0.1
        game.narrativeCampaign.exploration.positionZ = -1.65
        XCTAssertTrue(game.interactNarrativeHotspot())

        game.advanceNarrative("dialogue.fabricated")

        XCTAssertNil(game.audio.lastNarrativeImpactAudioEvent)
        XCTAssertEqual(game.narrativeCampaign.currentMoment.id, "4.listen.0")
    }

    func testNarrativeChapterTransitionsDriveAudioSceneMix() {
        let game = GameManager(userDefaults: isolatedUserDefaults())

        game.startFullNarrativeCampaign()
        XCTAssertEqual(game.audio.activeSceneID, "classroom")

        game.developerJump(to: .mirror)
        XCTAssertEqual(game.audio.activeSceneID, "mirror")
        XCTAssertEqual(game.audio.targetSceneMix.sceneID, "mirror")
        XCTAssertGreaterThan(game.audio.targetSceneMix.mirrorResonance, 0.9)

        game.developerJump(to: .noteTrace)
        XCTAssertEqual(game.audio.activeSceneID, "corridor")
        XCTAssertEqual(game.audio.targetSceneMix.sceneID, "corridor")

        game.developerJump(to: .counseling)
        XCTAssertEqual(game.audio.activeSceneID, "counseling")
        XCTAssertEqual(game.audio.targetSceneMix.mirrorResonance, 0)
    }

    func testNarrativeStateSynchronizesDynamicAudioMix() {
        let game = GameManager(userDefaults: isolatedUserDefaults())

        game.developerJump(to: .stairwell, momentIndex: 1)
        game.narrativeCampaign.exploration.positionX = 0.1
        game.narrativeCampaign.exploration.positionZ = -1.65
        XCTAssertTrue(game.interactNarrativeHotspot())
        let idleMix = game.audio.effectiveTargetSceneMix
        game.advanceNarrative("dialogue.advise")
        let ruptureMix = game.audio.effectiveTargetSceneMix
        XCTAssertGreaterThan(game.audio.targetNarrativeDynamics.ruptureTension, 0.3)
        XCTAssertGreaterThan(ruptureMix.ambientNoise, idleMix.ambientNoise)
        XCTAssertGreaterThan(ruptureMix.mirrorResonance, idleMix.mirrorResonance)

        game.developerJump(to: .counseling, momentIndex: 1)
        game.narrativeCampaign.exploration.positionX = 0
        game.narrativeCampaign.exploration.positionZ = -0.65
        XCTAssertTrue(game.interactNarrativeHotspot())
        let rumorMix = game.audio.effectiveTargetSceneMix
        game.advanceNarrative("privacy")
        let protectedMix = game.audio.effectiveTargetSceneMix
        XCTAssertGreaterThan(game.audio.targetNarrativeDynamics.privacyDamping, 0.4)
        XCTAssertLessThan(protectedMix.ambientNoise, rumorMix.ambientNoise)
        XCTAssertLessThan(protectedMix.reverbLevel, rumorMix.reverbLevel)
    }

    func testSupportResourceViewRendersVisibleResources() throws {
        let catalog = try SupportResourceCatalog.load()
        let renderer = ImageRenderer(content: ZStack {
            Color.black
            SupportResourceView(resources: catalog.resources)
                .frame(width: 900, height: 460)
                .padding(24)
        }
        .frame(width: 960, height: 540))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 960, height: 540)

        guard let image = renderer.nsImage else {
            XCTFail("SupportResourceView did not render")
            return
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        var minimum = 1.0
        var maximum = 0.0
        var visibleSamples = 0
        for y in stride(from: 8, to: bitmap.pixelsHigh, by: 24) {
            for x in stride(from: 8, to: bitmap.pixelsWide, by: 24) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                minimum = min(minimum, luminance)
                maximum = max(maximum, luminance)
                if luminance > 0.05 { visibleSamples += 1 }
            }
        }
        XCTAssertGreaterThan(visibleSamples, 80)
        XCTAssertGreaterThan(maximum - minimum, 0.12)

        if let path = ProcessInfo.processInfo.environment["CAPTURE_SUPPORT_RESOURCE_VIEW"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }
    }

    func testPasteboardBridgeCopiesSupportResourceText() throws {
        let originalHandler = PasteboardBridge.copyHandler
        defer {
            PasteboardBridge.copyHandler = originalHandler
        }
        var copiedText: String?
        PasteboardBridge.copyHandler = { text in
            copiedText = text
            return true
        }

        XCTAssertTrue(PasteboardBridge.copy("12356"))
        XCTAssertEqual(copiedText, "12356")
        XCTAssertEqual(PasteboardBridge.lastCopiedText, "12356")
    }

    func testSupportNetworkViewRendersVisibleCompletionState() throws {
        var campaign = NarrativeCampaign(isActive: true, isComplete: true, chapter: .epilogue)
        campaign.clueCount = 5
        campaign.companionID = "许栀"
        campaign.linCheTrust = 18
        campaign.safetyRoute = NarrativeSafetyRoute.urgentSchoolResponse.displayName
        campaign.selfCared = true
        campaign.sharedSelf = true
        campaign.safetyHandoffState = NarrativeSafetyHandoffState(
            authoredRisk: .high,
            riskAsked: true,
            adultContactInitiated: true,
            contactMethod: "消息",
            safetyHandoffComplete: true,
            route: .urgentSchoolResponse,
            entryMode: .urgentHandoffWaiting,
            resolutionPath: .voluntary
        )

        let renderer = ImageRenderer(content: ZStack {
            Color.black
            SupportNetworkView(campaign: campaign)
                .frame(width: 900, height: 420)
                .padding(24)
        }
        .frame(width: 960, height: 540))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 960, height: 540)

        guard let image = renderer.nsImage else {
            XCTFail("SupportNetworkView did not render")
            return
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        var minimum = 1.0
        var maximum = 0.0
        var visibleSamples = 0
        for y in stride(from: 8, to: bitmap.pixelsHigh, by: 24) {
            for x in stride(from: 8, to: bitmap.pixelsWide, by: 24) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                minimum = min(minimum, luminance)
                maximum = max(maximum, luminance)
                if luminance > 0.05 { visibleSamples += 1 }
            }
        }
        XCTAssertGreaterThan(visibleSamples, 90)
        XCTAssertGreaterThan(maximum - minimum, 0.12)

        if let path = ProcessInfo.processInfo.environment["CAPTURE_SUPPORT_NETWORK_VIEW"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }
    }

    func testEndingRouteSpectrumViewRendersSevenRouteRecap() throws {
        var campaign = NarrativeCampaign(isActive: true, isComplete: true, chapter: .epilogue)
        campaign.clueCount = 4
        campaign.companionID = "周予安"
        campaign.linCheTrust = 16
        campaign.selfCared = false
        campaign.sharedSelf = true
        campaign.privacyProtected = true
        campaign.safetyRoute = NarrativeSafetyRoute.standardCounseling.displayName
        campaign.safetyHandoffState = NarrativeSafetyHandoffState(
            authoredRisk: .moderate,
            riskAsked: true,
            adultContactInitiated: true,
            contactMethod: "消息",
            safetyHandoffComplete: true,
            route: .standardCounseling,
            entryMode: .standardWaiting,
            resolutionPath: .voluntary
        )

        let renderer = ImageRenderer(content: ZStack {
            Color.black
            EndingRouteSpectrumView(campaign: campaign)
                .frame(width: 660)
                .padding(24)
        }
        .frame(width: 720, height: 640))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 720, height: 640)

        guard let image = renderer.nsImage else {
            XCTFail("EndingRouteSpectrumView did not render")
            return
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        var minimum = 1.0
        var maximum = 0.0
        var visibleSamples = 0
        for y in stride(from: 10, to: bitmap.pixelsHigh, by: 22) {
            for x in stride(from: 10, to: bitmap.pixelsWide, by: 22) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                minimum = min(minimum, luminance)
                maximum = max(maximum, luminance)
                if luminance > 0.045 { visibleSamples += 1 }
            }
        }
        XCTAssertGreaterThan(visibleSamples, 110)
        XCTAssertGreaterThan(maximum - minimum, 0.14)

        if let path = ProcessInfo.processInfo.environment["CAPTURE_ENDING_SPECTRUM_VIEW"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }
    }

    func testSupportNetworkNodesExposeSequentialInteractiveTraceLines() {
        var campaign = NarrativeCampaign(isActive: true, isComplete: true, chapter: .epilogue)
        campaign.clueCount = 5
        campaign.companionID = "周予安"
        campaign.selfCared = true
        campaign.sharedSelf = false
        campaign.safetyRoute = NarrativeSafetyRoute.urgentSchoolResponse.displayName
        campaign.jiangDialogueState = NarrativeJiangDialogueState(
            segmentIndex: 3,
            responseKinds: [.listening, .accompanying, .silentPresence],
            consecutiveTimeouts: 0,
            listenPhaseComplete: true,
            educationCardDismissed: true,
            riskAskMethod: .direct,
            disclosedRisk: .confirmed
        )
        campaign.safetyHandoffState = NarrativeSafetyHandoffState(
            authoredRisk: .high,
            riskAsked: true,
            adultContactInitiated: true,
            contactMethod: "电话",
            safetyHandoffComplete: true,
            route: .urgentSchoolResponse,
            entryMode: .urgentHandoffWaiting,
            resolutionPath: .voluntary
        )

        let nodes = SupportNetworkModel.nodes(for: campaign)

        XCTAssertEqual(nodes.map(\.id), ["see", "companion", "trust", "handoff", "selfcare"])
        XCTAssertEqual(nodes.map(\.activationDelay), [0, 0.5, 1.0, 1.5, 2.0])
        XCTAssertTrue(nodes.allSatisfy { $0.traceLines.count == 2 })
        XCTAssertTrue(nodes[1].traceLines[0].contains("周予安"))
        XCTAssertEqual(nodes[2].title, "倾听")
        XCTAssertTrue(nodes[2].traceLines[0].contains("江越对话"))
        XCTAssertFalse(nodes[2].traceLines.joined(separator: " ").contains { character in
            character.unicodeScalars.contains { scalar in
                scalar.value >= 48 && scalar.value <= 57
            }
        })
        for forbidden in ["信任", "进度", "承接", "收紧", "%"] {
            XCTAssertFalse(nodes[2].traceLines.joined(separator: " ").contains(forbidden))
        }
        XCTAssertTrue(nodes[3].traceLines[0].contains("校内紧急支持"))
        XCTAssertTrue(nodes[4].traceLines[1].contains("今天先坐一会儿"))
    }

    func testSupportNetworkNodesEchoMirrorDialogueChoiceIntoEndingTrace() {
        var campaign = NarrativeCampaign(isActive: true, chapter: .mirror, momentIndex: 4, linCheTrust: 3)
        campaign.choose("invite")
        campaign.isComplete = true
        campaign.chapter = .epilogue
        campaign.clueCount = 5
        campaign.companionID = "许栀"
        campaign.safetyRoute = NarrativeSafetyRoute.standardCounseling.displayName
        campaign.jiangDialogueState = NarrativeJiangDialogueState(
            segmentIndex: 3,
            responseKinds: [.listening, .accompanying],
            consecutiveTimeouts: 0,
            listenPhaseComplete: true,
            educationCardDismissed: true,
            riskAskMethod: .gentle,
            disclosedRisk: .unclear
        )

        let nodes = SupportNetworkModel.nodes(for: campaign)
        let trustNode = nodes.first { $0.id == "trust" }

        XCTAssertNotNil(trustNode)
        XCTAssertTrue(trustNode?.detail.contains("可靠的大人") == true)
        XCTAssertTrue(trustNode?.traceLines[0].contains("镜中痕迹") == true)
        XCTAssertTrue(trustNode?.traceLines[0].contains("可靠的大人") == true)
        XCTAssertTrue(trustNode?.traceLines[1].contains("江越对话") == true)
        for forbidden in ["赢了", "失败了", "诊断", "信任 3"] {
            XCTAssertFalse((trustNode?.traceLines.joined(separator: " ") ?? "").contains(forbidden))
        }
    }

    func testEmpathyReplayViewRendersVisibleSystemicRecap() throws {
        var campaign = NarrativeCampaign(isActive: true, isComplete: true, chapter: .epilogue)
        campaign.clueCount = 5
        campaign.companionID = "周予安"
        campaign.selfCared = true
        campaign.sharedSelf = true
        campaign.privacyProtected = true
        campaign.jiangDialogueState = NarrativeJiangDialogueState(
            segmentIndex: 3,
            responseKinds: [.listening, .accompanying, .silentPresence, .listening],
            consecutiveTimeouts: 0,
            listenPhaseComplete: true,
            educationCardDismissed: true,
            riskAskMethod: .direct,
            disclosedRisk: .confirmed
        )
        campaign.safetyHandoffState = NarrativeSafetyHandoffState(
            authoredRisk: .high,
            riskAsked: true,
            adultContactInitiated: true,
            contactMethod: "电话",
            safetyHandoffComplete: true,
            route: .urgentSchoolResponse,
            entryMode: .urgentHandoffWaiting,
            resolutionPath: .voluntary
        )
        campaign.counselingState = NarrativeCounselingState(
            entryMode: .urgentHandoffWaiting,
            handoffSceneStarted: true,
            boundaryHeld: true,
            rumorHandled: true,
            rumorOutcome: .suppressed,
            companionMessageReplied: true,
            handoffConfirmed: true,
            supportHandedOff: true
        )

        let renderer = ImageRenderer(content: ZStack {
            Color.black
            EmpathyReplayView(campaign: campaign)
                .frame(width: 960, height: 150)
                .padding(24)
        }
        .frame(width: 1020, height: 220))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 1020, height: 220)

        guard let image = renderer.nsImage else {
            XCTFail("EmpathyReplayView did not render")
            return
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        var minimum = 1.0
        var maximum = 0.0
        var visibleSamples = 0
        for y in stride(from: 8, to: bitmap.pixelsHigh, by: 18) {
            for x in stride(from: 8, to: bitmap.pixelsWide, by: 18) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                minimum = min(minimum, luminance)
                maximum = max(maximum, luminance)
                if luminance > 0.05 { visibleSamples += 1 }
            }
        }
        XCTAssertGreaterThan(visibleSamples, 120)
        XCTAssertGreaterThan(maximum - minimum, 0.10)

        if let path = ProcessInfo.processInfo.environment["CAPTURE_EMPATHY_REPLAY_VIEW"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }
    }

    func testTruthReplayViewRendersVisibleDualPerspectiveReveal() throws {
        var campaign = NarrativeCampaign(isActive: true, isComplete: true, chapter: .epilogue)
        campaign.clueCount = 5
        campaign.companionID = "许栀"
        campaign.selfCared = true
        campaign.sharedSelf = true
        campaign.jiangDialogueState = NarrativeJiangDialogueState(
            segmentIndex: 3,
            responseKinds: [.listening, .accompanying, .silentPresence, .listening],
            consecutiveTimeouts: 0,
            listenPhaseComplete: true,
            educationCardDismissed: true,
            riskAskMethod: .direct,
            disclosedRisk: .confirmed
        )
        campaign.safetyHandoffState = NarrativeSafetyHandoffState(
            authoredRisk: .high,
            riskAsked: true,
            adultContactInitiated: true,
            contactMethod: "消息",
            safetyHandoffComplete: true,
            route: .urgentSchoolResponse,
            entryMode: .urgentHandoffWaiting,
            resolutionPath: .voluntary
        )

        let renderer = ImageRenderer(content: ZStack {
            Color.black
            TruthReplayView(campaign: campaign)
                .frame(width: 620, height: 280)
                .padding(24)
        }
        .frame(width: 700, height: 360))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 700, height: 360)

        guard let image = renderer.nsImage else {
            XCTFail("TruthReplayView did not render")
            return
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        var minimum = 1.0
        var maximum = 0.0
        var visibleSamples = 0
        for y in stride(from: 8, to: bitmap.pixelsHigh, by: 18) {
            for x in stride(from: 8, to: bitmap.pixelsWide, by: 18) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                minimum = min(minimum, luminance)
                maximum = max(maximum, luminance)
                if luminance > 0.05 { visibleSamples += 1 }
            }
        }
        XCTAssertGreaterThan(visibleSamples, 110)
        XCTAssertGreaterThan(maximum - minimum, 0.10)

        if let path = ProcessInfo.processInfo.environment["CAPTURE_TRUTH_REPLAY_VIEW"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }
    }

    func testNarrativeCompletionViewRendersEndingNetworkAndResources() throws {
        let game = GameManager()
        var campaign = NarrativeCampaign(isActive: true, isComplete: true, chapter: .epilogue)
        campaign.clueCount = 5
        campaign.companionID = "许栀"
        campaign.linCheTrust = 18
        campaign.safetyRoute = NarrativeSafetyRoute.standardCounseling.displayName
        campaign.privacyProtected = true
        campaign.selfCared = true
        campaign.sharedSelf = true
        campaign.safetyHandoffState = NarrativeSafetyHandoffState(
            authoredRisk: .moderate,
            riskAsked: true,
            adultContactInitiated: true,
            contactMethod: "消息",
            safetyHandoffComplete: true,
            route: .standardCounseling,
            entryMode: .standardWaiting,
            resolutionPath: .voluntary
        )
        campaign.counselingState = NarrativeCounselingState(
            entryMode: .standardWaiting,
            handoffSceneStarted: true,
            boundaryHeld: true,
            rumorHandled: true,
            rumorOutcome: .contained,
            companionMessageReplied: true,
            handoffConfirmed: true,
            supportHandedOff: true
        )
        game.narrativeCampaign = campaign

        let renderer = ImageRenderer(content: ZStack {
            Color.black
            NarrativeCampaignView(game: game)
                .frame(width: 1120, height: 820)
        }
        .frame(width: 1120, height: 820))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 1120, height: 820)

        guard let image = renderer.nsImage else {
            XCTFail("NarrativeCampaign completion view did not render")
            return
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        var minimum = 1.0
        var maximum = 0.0
        var visibleSamples = 0
        for y in stride(from: 8, to: bitmap.pixelsHigh, by: 24) {
            for x in stride(from: 8, to: bitmap.pixelsWide, by: 24) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                minimum = min(minimum, luminance)
                maximum = max(maximum, luminance)
                if luminance > 0.05 { visibleSamples += 1 }
            }
        }
        XCTAssertGreaterThan(visibleSamples, 45)
        XCTAssertGreaterThan(maximum - minimum, 0.12)

        if let path = ProcessInfo.processInfo.environment["CAPTURE_COMPLETION_VIEW"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }
    }

    func testNarrativeCompletionViewRendersTeacherTruthRunUnlock() throws {
        let game = GameManager()
        var campaign = NarrativeCampaign(isActive: true, isComplete: true, chapter: .epilogue)
        campaign.clueCount = 5
        campaign.companionID = "周予安"
        campaign.safetyRoute = NarrativeSafetyRoute.urgentSchoolResponse.displayName
        campaign.privacyProtected = true
        campaign.selfCared = true
        campaign.sharedSelf = true
        campaign.jiangDialogueState = NarrativeJiangDialogueState(
            segmentIndex: 3,
            responseKinds: [.listening, .accompanying, .silentPresence, .listening],
            consecutiveTimeouts: 0,
            listenPhaseComplete: true,
            educationCardDismissed: true,
            riskAskMethod: .direct,
            disclosedRisk: .confirmed
        )
        campaign.safetyHandoffState = NarrativeSafetyHandoffState(
            authoredRisk: .high,
            riskAsked: true,
            adultContactInitiated: true,
            contactMethod: "电话",
            safetyHandoffComplete: true,
            route: .urgentSchoolResponse,
            entryMode: .urgentHandoffWaiting,
            resolutionPath: .voluntary
        )
        game.narrativeCampaign = campaign

        let renderer = ImageRenderer(content: ZStack {
            Color.black
            NarrativeCampaignView(game: game)
                .frame(width: 1120, height: 820)
        }
        .frame(width: 1120, height: 820))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 1120, height: 820)

        guard let image = renderer.nsImage else {
            XCTFail("NarrativeCampaign completion truth unlock view did not render")
            return
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        var visibleSamples = 0
        var cyanOrMintSamples = 0
        for y in stride(from: 8, to: bitmap.pixelsHigh, by: 24) {
            for x in stride(from: 8, to: bitmap.pixelsWide, by: 24) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                if luminance > 0.05 { visibleSamples += 1 }
                if color.greenComponent > 0.23, color.blueComponent > 0.18, color.redComponent < 0.28 {
                    cyanOrMintSamples += 1
                }
            }
        }
        XCTAssertGreaterThan(visibleSamples, 160)
        XCTAssertGreaterThan(cyanOrMintSamples, 8)

        if let path = ProcessInfo.processInfo.environment["CAPTURE_TEACHER_TRUTH_UNLOCK_VIEW"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }
    }

    func testNarrativeCampaignViewRendersSupportWeatherInPlayableHeader() throws {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.developerJump(to: .stairwell, momentIndex: 1)
        game.narrativeCampaign.companionID = "周予安"
        game.narrativeCampaign.clueCount = 4
        game.narrativeCampaign.selfCared = true
        game.narrativeCampaign.sharedSelf = true

        let renderer = ImageRenderer(content: NarrativeCampaignView(game: game)
            .frame(width: 980, height: 620))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 980, height: 620)

        guard let image = renderer.nsImage else {
            return XCTFail("NarrativeCampaignView did not render support weather")
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        var visibleSamples = 0
        var cyanOrMintSamples = 0
        var textLikeSamples = 0
        for y in stride(from: 12, to: bitmap.pixelsHigh, by: 26) {
            for x in stride(from: 12, to: bitmap.pixelsWide, by: 26) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                if luminance > 0.03 { visibleSamples += 1 }
                if color.greenComponent > color.redComponent + 0.06,
                   color.blueComponent > color.redComponent + 0.04 {
                    cyanOrMintSamples += 1
                }
                if luminance > 0.42,
                   abs(color.redComponent - color.greenComponent) < 0.08,
                   abs(color.greenComponent - color.blueComponent) < 0.08 {
                    textLikeSamples += 1
                }
            }
        }

        XCTAssertGreaterThan(visibleSamples, 120)
        XCTAssertGreaterThan(cyanOrMintSamples, 6)
        XCTAssertGreaterThan(textLikeSamples, 18)

        if let path = ProcessInfo.processInfo.environment["CAPTURE_NARRATIVE_SUPPORT_WEATHER_VIEW"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }
    }

    func testWaterCupInteractionBeatActivatesAfterReturningToSeat() {
        let game = GameManager()
        game.startPrologue(resume: false)
        game.completePrologueBeat(.gateArrival, source: .performance)
        game.completePrologueBeat(.lookDownHall, source: .player)
        game.completePrologueBeat(.returnToSeat, source: .player)

        XCTAssertEqual(game.prologueCurrentBeat, .placeWater)
        XCTAssertEqual(game.player.posture, .seated)
        XCTAssertFalse(game.freeRoam.isActive)
        XCTAssertFalse(game.prologueState.interactionTutorialCompleted)
        XCTAssertEqual(game.player.waterCup, 100)
    }

    func testPrologueGateRendersANonBlankLayeredFrame() throws {
        let game = GameManager()
        game.startPrologue(resume: false)
        game.tickPrologue(delta: 24)
        let coordinator = ClassroomCoordinator()
        coordinator.update(game: game)

        let image = coordinator.renderSnapshot(size: CGSize(width: 960, height: 600))
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        var minimum = 1.0
        var maximum = 0.0
        var visibleSamples = 0
        for y in stride(from: 8, to: bitmap.pixelsHigh, by: 24) {
            for x in stride(from: 8, to: bitmap.pixelsWide, by: 24) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                minimum = min(minimum, luminance)
                maximum = max(maximum, luminance)
                if luminance > 0.025 { visibleSamples += 1 }
            }
        }
        XCTAssertGreaterThan(visibleSamples, 100)
        XCTAssertGreaterThan(maximum - minimum, 0.18)

        if let path = ProcessInfo.processInfo.environment["CAPTURE_PROLOGUE_FRAME"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: path))
        }
    }

    func testPrologueCorridorLookTargetLightsThreeDimensionalTarget() throws {
        let resting = PrologueLookTargetSignal(
            isPrologueActive: true,
            currentBeat: .lookDownHall,
            lastBeatEcho: PrologueBeatEcho(beat: .gateArrival, source: .performance),
            cameraPose: .forward,
            studentLookYaw: 0
        )
        let aimed = PrologueLookTargetSignal(
            isPrologueActive: true,
            currentBeat: .lookDownHall,
            lastBeatEcho: PrologueBeatEcho(beat: .gateArrival, source: .performance),
            cameraPose: .right,
            studentLookYaw: 0.62
        )
        let confirmed = PrologueLookTargetSignal(
            isPrologueActive: true,
            currentBeat: .returnToSeat,
            lastBeatEcho: PrologueBeatEcho(beat: .lookDownHall, source: .player),
            cameraPose: .forward,
            studentLookYaw: 0
        )
        let hidden = PrologueLookTargetSignal(
            isPrologueActive: true,
            currentBeat: .placeWater,
            lastBeatEcho: PrologueBeatEcho(beat: .returnToSeat, source: .player),
            cameraPose: .forward,
            studentLookYaw: 0
        )

        XCTAssertTrue(resting.isVisible)
        XCTAssertFalse(resting.isHighlighted)
        XCTAssertGreaterThan(resting.opacity, 0.35)
        XCTAssertTrue(aimed.isHighlighted)
        XCTAssertGreaterThan(aimed.opacity, resting.opacity)
        XCTAssertGreaterThan(aimed.emissionIntensity, resting.emissionIntensity)
        XCTAssertTrue(confirmed.isVisible)
        XCTAssertTrue(confirmed.isHighlighted)
        XCTAssertGreaterThan(confirmed.opacity, 0.8)
        XCTAssertFalse(hidden.isVisible)
        XCTAssertEqual(hidden.opacity, 0)
    }

    func testPrologueGateArrivalSignalTracksControlledEntrancePath() {
        let start = PrologueGateArrivalSignal(isPrologueActive: true, currentBeat: .gateArrival, elapsed: 0)
        let middle = PrologueGateArrivalSignal(isPrologueActive: true, currentBeat: .gateArrival, elapsed: 27.5)
        let end = PrologueGateArrivalSignal(isPrologueActive: true, currentBeat: .gateArrival, elapsed: 55)
        let hidden = PrologueGateArrivalSignal(isPrologueActive: true, currentBeat: .lookDownHall, elapsed: 55)

        XCTAssertTrue(start.isVisible)
        XCTAssertEqual(start.progress, 0, accuracy: 0.0001)
        XCTAssertEqual(start.litStepCount, 1)
        XCTAssertGreaterThan(middle.litStepCount, start.litStepCount)
        XCTAssertGreaterThan(middle.entranceGlow, start.entranceGlow)
        XCTAssertLessThan(middle.studentZ, start.studentZ)
        XCTAssertEqual(end.progress, 1, accuracy: 0.0001)
        XCTAssertEqual(end.litStepCount, PrologueGateArrivalSignal.stepCount)
        XCTAssertLessThan(end.studentZ, middle.studentZ)
        XCTAssertFalse(hidden.isVisible)
        XCTAssertEqual(hidden.litStepCount, 0)
    }

    func testPrologueAccessibilitySettingsHintPausesAndResumesBeat() {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.startPrologue(resume: false)
        for beat in [
            PrologueBeatID.gateArrival,
            .lookDownHall,
            .returnToSeat,
            .placeWater,
            .studyHallRhythm,
            .noticeLinChe,
            .settleBreath
        ] {
            game.completePrologueBeat(beat, source: .player)
        }
        XCTAssertEqual(game.prologueCurrentBeat, .accessibility)

        game.acknowledgeAccessibilityTutorial(openSettings: true)
        XCTAssertTrue(game.isAccessibilityPanelPresented)
        XCTAssertTrue(game.prologuePaused)
        XCTAssertTrue(game.prologuePauseReasons.contains(.settings))

        game.tickPrologue(delta: 20)
        XCTAssertEqual(game.prologueCurrentBeat, .accessibility)

        game.updateAccessibilityPreferences {
            $0.directionalSubtitles = false
            $0.reduceMotion = true
            $0.keyboardAlternativeInput = false
        }
        game.closeAccessibilityPanel()

        XCTAssertFalse(game.isAccessibilityPanelPresented)
        XCTAssertFalse(game.prologuePaused)
        XCTAssertTrue(game.prologueState.accessibilityTutorialAcknowledged)
        XCTAssertEqual(game.prologueCurrentBeat, .bellBeforeClass)
        XCTAssertTrue(game.accessibilityPreferences.reduceMotion)
        XCTAssertFalse(game.accessibilityPreferences.directionalSubtitles)
    }

    func testPrologueAccessibilityContinueAcknowledgesWithoutOpeningSettings() {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.startPrologue(resume: false)
        for beat in [
            PrologueBeatID.gateArrival,
            .lookDownHall,
            .returnToSeat,
            .placeWater,
            .studyHallRhythm,
            .noticeLinChe,
            .settleBreath
        ] {
            game.completePrologueBeat(beat, source: .player)
        }
        XCTAssertEqual(game.prologueCurrentBeat, .accessibility)

        game.acknowledgeAccessibilityTutorial(openSettings: false)

        XCTAssertFalse(game.isAccessibilityPanelPresented)
        XCTAssertFalse(game.prologuePaused)
        XCTAssertTrue(game.prologueState.accessibilityTutorialAcknowledged)
        XCTAssertEqual(game.prologueCurrentBeat, .bellBeforeClass)
    }

    func testPrologueAccessibilityHintViewRendersBottomRightStyleCard() throws {
        let renderer = ImageRenderer(content: ZStack(alignment: .bottomTrailing) {
            Color(red: 0.04, green: 0.06, blue: 0.08)
            PrologueAccessibilityHintView(onOpenSettings: {}, onContinue: {})
                .padding(18)
        }
        .frame(width: 720, height: 420))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 720, height: 420)

        guard let image = renderer.nsImage else {
            XCTFail("PrologueAccessibilityHintView did not render")
            return
        }
        let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        if let path = ProcessInfo.processInfo.environment["CAPTURE_PROLOGUE_ACCESSIBILITY_HINT_VIEW"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }

        var bottomRightVisibleSamples = 0
        var textLikeSamples = 0
        var mintSamples = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                if x > bitmap.pixelsWide - 330, y > bitmap.pixelsHigh - 180, luminance > 0.045 {
                    bottomRightVisibleSamples += 1
                }
                if x < bitmap.pixelsWide - 350, y < bitmap.pixelsHigh - 210, luminance > 0.12 {
                    textLikeSamples += 1
                }
                if color.greenComponent > 0.34, color.blueComponent > 0.22, color.redComponent < 0.28 {
                    mintSamples += 1
                }
            }
        }
        XCTAssertGreaterThan(bottomRightVisibleSamples, 1_200)
        XCTAssertLessThan(textLikeSamples, 260)
        XCTAssertGreaterThan(mintSamples, 14)
    }

    func testSceneKitPrologueLookTargetSnapshotShowsVisibleHallBeacon() throws {
        guard let path = ProcessInfo.processInfo.environment["CAPTURE_PROLOGUE_LOOK_TARGET_VIEW"] else {
            throw XCTSkip("Set CAPTURE_PROLOGUE_LOOK_TARGET_VIEW to render the prologue hallway target evidence snapshot.")
        }
        let game = GameManager()
        let coordinator = ClassroomCoordinator()
        game.startPrologue(resume: false)
        game.completePrologueBeat(.gateArrival, source: .performance)
        game.cameraPose = .right
        game.studentLookYaw = 0.62
        coordinator.update(game: game)

        let image = coordinator.renderSnapshot(size: CGSize(width: 960, height: 600))
        let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        var visibleSamples = 0
        var mintSamples = 0
        for y in stride(from: 8, to: bitmap.pixelsHigh, by: 18) {
            for x in stride(from: 8, to: bitmap.pixelsWide, by: 18) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                if luminance > 0.035 { visibleSamples += 1 }
                if color.greenComponent > 0.45, color.blueComponent > 0.26, color.redComponent < 0.5 {
                    mintSamples += 1
                }
            }
        }
        XCTAssertGreaterThan(visibleSamples, 140)
        XCTAssertGreaterThan(mintSamples, 5)

        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url)
    }

    func testSceneKitPrologueGateArrivalSnapshotShowsEntrancePath() throws {
        guard let path = ProcessInfo.processInfo.environment["CAPTURE_PROLOGUE_GATE_PATH_VIEW"] else {
            throw XCTSkip("Set CAPTURE_PROLOGUE_GATE_PATH_VIEW to render the prologue gate-arrival evidence snapshot.")
        }
        let game = GameManager()
        let coordinator = ClassroomCoordinator()
        game.startPrologue(resume: false)
        game.tickPrologue(delta: 34)
        coordinator.update(game: game)

        XCTAssertFalse(coordinator.prologueGateArrivalHidden)
        XCTAssertGreaterThan(coordinator.prologueGateArrivalLitStepCount, 3)
        XCTAssertGreaterThan(coordinator.prologueGateArrivalEntranceOpacity, 0.55)
        XCTAssertLessThan(try XCTUnwrap(coordinator.prologueGateArrivalStudentZ), 11.0)

        let image = coordinator.renderSnapshot(size: CGSize(width: 960, height: 600))
        let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        var visibleSamples = 0
        var warmSamples = 0
        for y in stride(from: 8, to: bitmap.pixelsHigh, by: 18) {
            for x in stride(from: 8, to: bitmap.pixelsWide, by: 18) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                if luminance > 0.035 { visibleSamples += 1 }
                if color.redComponent > 0.34,
                   color.greenComponent > 0.16,
                   color.redComponent > color.blueComponent * 0.72 {
                    warmSamples += 1
                }
            }
        }
        XCTAssertGreaterThan(visibleSamples, 150)
        XCTAssertGreaterThan(warmSamples, 8)

        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url)
    }

    func testPhotorealFurnitureAndHDRILightingArePackaged() {
        let coordinator = ClassroomCoordinator()

        XCTAssertTrue(coordinator.photorealFurnitureLoaded)
        XCTAssertTrue(coordinator.hdriLightingLoaded)
    }

    func testPrologueKeyFramesRemainVisuallyDistinct() throws {
        let game = GameManager()
        game.startPrologue(resume: false)
        let coordinator = ClassroomCoordinator()
        var images: [(String, NSImage)] = []

        func capture(_ name: String) {
            coordinator.update(game: game)
            images.append((name, coordinator.renderSnapshot(size: CGSize(width: 960, height: 600))))
        }

        game.tickPrologue(delta: 24)
        capture("01-gate")
        game.completePrologueBeat(.gateArrival, source: .performance)
        capture("02-hall")
        game.completePrologueBeat(.lookDownHall, source: .player)
        game.completePrologueBeat(.returnToSeat, source: .player)
        capture("03-water")
        game.completePrologueBeat(.placeWater, source: .player)
        game.tickPrologue(delta: 108)
        capture("04-rhythm")
        game.completePrologueBeat(.studyHallRhythm, source: .performance)
        game.studentLookYaw = 0.72
        game.cameraPose = .left
        capture("05-linche")

        let encoded = try images.map { name, image -> (String, Data) in
            let tiff = try XCTUnwrap(image.tiffRepresentation)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
            return (name, try XCTUnwrap(bitmap.representation(using: .png, properties: [:])))
        }
        XCTAssertEqual(Set(encoded.map { $0.1.hashValue }).count, encoded.count)

        if let directory = ProcessInfo.processInfo.environment["CAPTURE_PROLOGUE_DIR"] {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            for (name, data) in encoded {
                try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
            }
        }
    }

    func testNarrativeStateMachineRendersFiveDistinctChapterStages() throws {
        let game = GameManager()
        let coordinator = ClassroomCoordinator()
        var renderedFrames: [Data] = []

        for chapter in NarrativeChapter.allCases where chapter != .classroom {
            game.developerJump(to: chapter)
            coordinator.update(game: game)

            XCTAssertTrue(coordinator.narrativeStageVisible)
            XCTAssertEqual(coordinator.activeNarrativeStageName, "narrativeStage_\(chapter.rawValue)")

            let focus = try XCTUnwrap(coordinator.projectedNarrativeFocusPosition(size: CGSize(width: 960, height: 600)))
            XCTAssertTrue((160...800).contains(focus.x), "\(chapter.title) focus x: \(focus.x)")
            XCTAssertTrue((90...510).contains(focus.y), "\(chapter.title) focus y: \(focus.y)")
            XCTAssertTrue((0...1).contains(focus.z), "\(chapter.title) focus depth: \(focus.z)")

            let image = coordinator.renderSnapshot(size: CGSize(width: 960, height: 600))
            let tiff = try XCTUnwrap(image.tiffRepresentation)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            XCTAssertGreaterThan(png.count, 20_000, "\(chapter.title) should render a populated 3D frame")
            renderedFrames.append(png)
            if let directory = ProcessInfo.processInfo.environment["CAPTURE_NARRATIVE_DIR"] {
                try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
                let file = URL(fileURLWithPath: directory).appendingPathComponent("chapter-\(chapter.rawValue).png")
                try png.write(to: file)
            }
        }

        XCTAssertEqual(Set(renderedFrames.map(\.hashValue)).count, 5)

        game.returnToMenuForNewGame()
        coordinator.update(game: game)
        XCTAssertFalse(coordinator.narrativeStageVisible)
    }

    func testNarrativeMiniGameProgressChangesTheThreeDimensionalStage() throws {
        let game = GameManager()
        let coordinator = ClassroomCoordinator()
        game.developerJump(to: .mirror, momentIndex: 1)
        coordinator.update(game: game)
        let initialScale = try XCTUnwrap(coordinator.activeNarrativeFocusScale)

        for slot in 0..<4 {
            game.performNarrativeMiniGameAction(slot)
        }
        coordinator.update(game: game)

        XCTAssertGreaterThan(try XCTUnwrap(coordinator.activeNarrativeFocusScale), initialScale)
        XCTAssertEqual(game.narrativeCampaign.miniGameProgress, 4)
    }

    func testMirrorMiniGamesLightTheThreeDimensionalRouteRig() throws {
        let game = GameManager()
        let coordinator = ClassroomCoordinator()
        game.developerJump(to: .mirror, momentIndex: 1)
        coordinator.update(game: game)

        let traceOpacities = coordinator.mirrorRouteLightOpacities
        let traceEmissions = coordinator.mirrorRouteLightEmissionIntensities
        XCTAssertEqual(traceOpacities.count, 3)
        XCTAssertEqual(traceEmissions.count, 3)
        XCTAssertGreaterThan(traceOpacities[0], traceOpacities[2])
        XCTAssertGreaterThan(traceEmissions[0], traceEmissions[2])

        for slot in 0..<NarrativeMiniGame.trace.requiredInteractions {
            game.performNarrativeMiniGameAction(slot)
        }
        XCTAssertTrue(game.narrativeCampaign.miniGameCompleted)
        game.narrativeCampaign.choose("playTrace")
        game.narrativeCampaign.miniGameProgress = 2
        coordinator.update(game: game)

        let melodyOpacities = coordinator.mirrorRouteLightOpacities
        let melodyEmissions = coordinator.mirrorRouteLightEmissionIntensities
        let bridges = coordinator.mirrorRouteBridgeOpacities
        XCTAssertEqual(game.narrativeCampaign.currentMoment.miniGame, .melody)
        XCTAssertGreaterThan(melodyOpacities[0], traceOpacities[0])
        XCTAssertGreaterThan(melodyOpacities[1], melodyOpacities[2])
        XCTAssertGreaterThan(melodyEmissions[1], traceEmissions[1])
        XCTAssertEqual(bridges.count, 2)
        XCTAssertGreaterThan(bridges[0], bridges[1])

        if let path = ProcessInfo.processInfo.environment["CAPTURE_MIRROR_STAGE_LIGHTS_VIEW"] {
            let image = coordinator.renderSnapshot(size: CGSize(width: 960, height: 600))
            let tiff = try XCTUnwrap(image.tiffRepresentation)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try FileManager.default.createDirectory(at: URL(fileURLWithPath: path).deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: URL(fileURLWithPath: path))
            XCTAssertGreaterThan(png.count, 20_000)
        }
    }

    func testMirrorSpacePressureModelTurnsThreeLightsIntoConnection() {
        var campaign = NarrativeCampaign(isActive: true, chapter: .mirror, momentIndex: 1)
        campaign.miniGameProgress = 0
        let firstLamp = MirrorSpacePressureModel.derive(from: campaign)

        campaign.momentIndex = 3
        campaign.miniGameProgress = NarrativeMiniGame.erase.requiredInteractions
        let thirdLamp = MirrorSpacePressureModel.derive(from: campaign)

        campaign.choose("playErase")
        let dialogue = MirrorSpacePressureModel.derive(from: campaign)

        XCTAssertEqual(firstLamp.completedLightCount, 0)
        XCTAssertEqual(thirdLamp.completedLightCount, 3)
        XCTAssertGreaterThan(firstLamp.pressure, thirdLamp.pressure)
        XCTAssertGreaterThan(firstLamp.crackOpacities[0], thirdLamp.crackOpacities[0])
        XCTAssertGreaterThan(thirdLamp.shadowPosition.x, firstLamp.shadowPosition.x)
        XCTAssertGreaterThan(dialogue.dissolve, thirdLamp.dissolve)
        XCTAssertGreaterThan(dialogue.shadowYaw, firstLamp.shadowYaw)
    }

    func testMirrorReturnDirectorModelTurnsLinCheTowardRealityAfterThreeLights() {
        var campaign = NarrativeCampaign(isActive: true, chapter: .mirror, momentIndex: 1)
        let inactive = MirrorReturnDirectorModel.derive(from: campaign)

        campaign.momentIndex = 3
        campaign.miniGameProgress = NarrativeMiniGame.erase.requiredInteractions
        let thirdLamp = MirrorReturnDirectorModel.derive(from: campaign)

        campaign.choose("playErase")
        let dialogue = MirrorReturnDirectorModel.derive(from: campaign)

        XCTAssertFalse(inactive.isActive)
        XCTAssertTrue(thirdLamp.isActive)
        XCTAssertEqual(thirdLamp.dissolve, 0.72, accuracy: 0.001)
        XCTAssertGreaterThan(thirdLamp.linCheYaw, 0.5)
        XCTAssertGreaterThan(thirdLamp.faceLightOpacity, 0.55)
        XCTAssertGreaterThan(dialogue.dissolve, thirdLamp.dissolve)
        XCTAssertGreaterThan(dialogue.realityBandOpacity, thirdLamp.realityBandOpacity)
        XCTAssertLessThan(dialogue.stageOpacity, thirdLamp.stageOpacity)
        XCTAssertTrue(dialogue.detail.contains("林澈转过来"))
    }

    func testMirrorDialogueConsequenceModelExplainsListenChoicesAndTrust() {
        var inviteCampaign = NarrativeCampaign(isActive: true, chapter: .mirror, momentIndex: 4, linCheTrust: 3)
        inviteCampaign.choose("invite")
        let invite = MirrorDialogueConsequenceModel.derive(from: inviteCampaign)

        var presentCampaign = NarrativeCampaign(isActive: true, chapter: .mirror, momentIndex: 4, linCheTrust: 3)
        presentCampaign.choose("present")
        let present = MirrorDialogueConsequenceModel.derive(from: presentCampaign)

        var reassureCampaign = NarrativeCampaign(isActive: true, chapter: .mirror, momentIndex: 4, linCheTrust: 3)
        reassureCampaign.choose("reassure")
        let reassure = MirrorDialogueConsequenceModel.derive(from: reassureCampaign)

        XCTAssertTrue(invite.isActive)
        XCTAssertEqual(invite.choiceID, "invite")
        XCTAssertTrue(invite.trustDeltaText.contains("+2"))
        XCTAssertTrue(invite.trustTotalText.contains("5"))
        XCTAssertTrue(invite.supportBiasText.contains("成人交接"))
        XCTAssertTrue(invite.nextChapterHint.contains("成人支持"))
        XCTAssertTrue(present.supportBiasText.contains("在场陪伴"))
        XCTAssertTrue(reassure.title.contains("负担"))
    }

    func testMirrorDialogueCarryoverModelPersistsIntoChapterThreeSupportState() {
        var campaign = NarrativeCampaign(isActive: true, chapter: .mirror, momentIndex: 4, linCheTrust: 3)
        campaign.choose("invite")

        let carryover = MirrorDialogueCarryoverModel.derive(from: campaign)

        XCTAssertEqual(campaign.chapter, .noteTrace)
        XCTAssertTrue(carryover.isActive)
        XCTAssertEqual(carryover.choiceID, "invite")
        XCTAssertTrue(carryover.title.contains("可靠的大人"))
        XCTAssertTrue(carryover.supportBiasText.contains("成人支持"))
        XCTAssertTrue(carryover.companionHint.contains("自己扛住"))
    }

    func testMirrorDialogueCarryoverModelExtendsIntoStairwellAndCounselingSupportState() {
        var campaign = NarrativeCampaign(isActive: true, chapter: .mirror, momentIndex: 4, linCheTrust: 3)
        campaign.choose("invite")
        campaign.companionID = "周予安"

        campaign.chapter = .stairwell
        campaign.momentIndex = 3
        var carryover = MirrorDialogueCarryoverModel.derive(from: campaign)
        var companion = campaign.companionPresenceStatus

        XCTAssertTrue(carryover.isActive)
        XCTAssertEqual(carryover.choiceID, "invite")
        XCTAssertTrue(carryover.title.contains("楼梯间"))
        XCTAssertTrue(carryover.supportBiasText.contains("第四章"))
        XCTAssertTrue(companion?.detail.contains("成人支持") == true)

        campaign.safetyHandoffState = NarrativeSafetyHandoffState(
            authoredRisk: .high,
            riskAsked: true,
            adultContactInitiated: true,
            contactMethod: "电话",
            safetyHandoffComplete: false,
            route: nil,
            entryMode: nil,
            resolutionPath: .adultCameAfterUnclearDisclosure
        )
        campaign.momentIndex = 4
        companion = campaign.companionPresenceStatus
        XCTAssertTrue(companion?.detail.contains("成人支持") == true)

        campaign.chapter = .counseling
        campaign.momentIndex = 0
        carryover = MirrorDialogueCarryoverModel.derive(from: campaign)

        XCTAssertTrue(carryover.isActive)
        XCTAssertTrue(carryover.title.contains("门外"))
        XCTAssertTrue(carryover.supportBiasText.contains("第五章"))
        XCTAssertTrue(carryover.companionHint.contains("专业支持"))
    }

    func testMirrorListenChoicePublishesDialogueConsequenceFeedback() {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.developerJump(to: .mirror, momentIndex: 4)
        game.dismissFeaturedMonologue()
        game.narrativeCampaign.exploration.interactionCount = 1
        let beforeTrust = game.narrativeCampaign.linCheTrust

        game.advanceNarrative("invite")

        let consequence = MirrorDialogueConsequenceModel.derive(from: game.narrativeCampaign)
        XCTAssertEqual(game.narrativeCampaign.chapter, .noteTrace)
        XCTAssertEqual(game.narrativeCampaign.linCheTrust, beforeTrust + 2)
        XCTAssertTrue(consequence.isActive)
        XCTAssertEqual(consequence.choiceID, "invite")
        XCTAssertTrue(game.developerPlaytestLog.contains { $0.contains("MIRROR_DIALOGUE invite") })
        XCTAssertTrue(game.audioCues.contains {
            $0.kind == .whisper &&
            $0.direction == "林澈回应" &&
            $0.note.contains("可靠的大人")
        })
    }

    func testChapterThreeInvestigationViewRendersMirrorDialogueCarryover() throws {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.developerJump(to: .mirror, momentIndex: 4)
        game.dismissFeaturedMonologue()
        game.narrativeCampaign.exploration.interactionCount = 1
        game.advanceNarrative("invite")

        let carryover = MirrorDialogueCarryoverModel.derive(from: game.narrativeCampaign)
        XCTAssertTrue(carryover.isActive)
        XCTAssertTrue(carryover.title.contains("可靠的大人"))

        let renderer = ImageRenderer(content: NarrativeCampaignView(game: game)
            .frame(width: 980, height: 920))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 980, height: 920)

        guard let image = renderer.nsImage else {
            return XCTFail("NarrativeCampaignView did not render chapter three carryover")
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        var visibleSamples = 0
        var textLikeSamples = 0
        var mintSamples = 0
        var maximum = 0.0
        var minimum = 1.0
        for y in stride(from: 12, to: bitmap.pixelsHigh, by: 18) {
            for x in stride(from: 12, to: bitmap.pixelsWide, by: 18) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                minimum = min(minimum, luminance)
                maximum = max(maximum, luminance)
                if luminance > 0.035 { visibleSamples += 1 }
                if color.redComponent > 0.72, color.greenComponent > 0.72, color.blueComponent > 0.72 { textLikeSamples += 1 }
                if color.greenComponent > 0.36, color.blueComponent > 0.22, color.redComponent < 0.34 { mintSamples += 1 }
            }
        }

        XCTAssertGreaterThan(visibleSamples, 170)
        XCTAssertGreaterThan(textLikeSamples, 18)
        XCTAssertGreaterThan(mintSamples, 14)
        XCTAssertGreaterThan(maximum - minimum, 0.16)

        if let path = ProcessInfo.processInfo.environment["CAPTURE_CHAPTER_THREE_CARRYOVER_VIEW"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }
    }

    func testMirrorLightNavigationCueGuidesPlayerToCurrentLamp() {
        var campaign = NarrativeCampaign(isActive: true, chapter: .mirror, momentIndex: 1)
        campaign.exploration.positionX = -0.22
        campaign.exploration.positionZ = 4.7
        let farTrace = MirrorLightNavigationCue.derive(from: campaign)

        campaign.exploration.positionX = -1.18
        campaign.exploration.positionZ = -2.05
        let nearTrace = MirrorLightNavigationCue.derive(from: campaign)

        campaign.momentIndex = 2
        campaign.exploration.positionX = 0
        campaign.exploration.positionZ = -2.05
        let melody = MirrorLightNavigationCue.derive(from: campaign)

        XCTAssertTrue(farTrace.isActive)
        XCTAssertEqual(farTrace.hotspotID, "mirror.light.trace")
        XCTAssertEqual(melody.hotspotID, "mirror.light.melody")
        XCTAssertGreaterThan(farTrace.distance, nearTrace.distance)
        XCTAssertGreaterThan(nearTrace.progressToRange, farTrace.progressToRange)
        XCTAssertGreaterThan(nearTrace.targetRingOpacity, farTrace.targetRingOpacity)
        XCTAssertTrue(nearTrace.title.contains("确认"))

        campaign.miniGameProgress = NarrativeMiniGame.melody.requiredInteractions
        XCTAssertFalse(MirrorLightNavigationCue.derive(from: campaign).isActive)
    }

    func testMirrorPressureRigMapsLinCheShadowAndCracksIntoScene() throws {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        let coordinator = ClassroomCoordinator()
        game.developerJump(to: .mirror, momentIndex: 1)
        coordinator.update(game: game)
        let initialCracks = coordinator.mirrorPressureCrackOpacities
        let initialShadow = try XCTUnwrap(coordinator.mirrorLinCheShadowPosition)
        let initialYaw = try XCTUnwrap(coordinator.mirrorLinCheShadowYaw)
        let initialBreath = try XCTUnwrap(coordinator.mirrorBreathRingOpacity)

        game.narrativeCampaign.momentIndex = 3
        for slot in 0..<NarrativeMiniGame.erase.requiredInteractions {
            game.performNarrativeMiniGameAction(slot)
        }
        coordinator.update(game: game)

        let resolvedCracks = coordinator.mirrorPressureCrackOpacities
        let resolvedShadow = try XCTUnwrap(coordinator.mirrorLinCheShadowPosition)
        let resolvedYaw = try XCTUnwrap(coordinator.mirrorLinCheShadowYaw)
        let resolvedBreath = try XCTUnwrap(coordinator.mirrorBreathRingOpacity)

        XCTAssertEqual(initialCracks.count, 6)
        XCTAssertEqual(resolvedCracks.count, 6)
        XCTAssertGreaterThan(initialCracks[0], resolvedCracks[0])
        XCTAssertGreaterThan(resolvedShadow.x, initialShadow.x)
        XCTAssertGreaterThan(resolvedShadow.z, initialShadow.z)
        XCTAssertGreaterThan(resolvedYaw, initialYaw)
        XCTAssertGreaterThan(resolvedBreath, initialBreath)
    }

    func testMirrorReturnDirectorRigLightsRealityBandAndFaceTurn() throws {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        let coordinator = ClassroomCoordinator()
        game.developerJump(to: .mirror, momentIndex: 1)
        coordinator.update(game: game)
        XCTAssertEqual(try XCTUnwrap(coordinator.mirrorReturnGateOpacity), 0)
        XCTAssertEqual(try XCTUnwrap(coordinator.mirrorRealityReturnBandOpacity), 0)
        XCTAssertEqual(try XCTUnwrap(coordinator.mirrorLinCheFaceLightOpacity), 0)
        let initialYaw = try XCTUnwrap(coordinator.mirrorLinCheShadowYaw)

        game.narrativeCampaign.momentIndex = 3
        for slot in 0..<NarrativeMiniGame.erase.requiredInteractions {
            game.performNarrativeMiniGameAction(slot)
        }
        coordinator.update(game: game)
        let thirdGate = try XCTUnwrap(coordinator.mirrorReturnGateOpacity)
        let thirdBand = try XCTUnwrap(coordinator.mirrorRealityReturnBandOpacity)
        let thirdFace = try XCTUnwrap(coordinator.mirrorLinCheFaceLightOpacity)
        let thirdYaw = try XCTUnwrap(coordinator.mirrorLinCheShadowYaw)

        game.narrativeCampaign.choose("playErase")
        coordinator.update(game: game)
        let dialogueGate = try XCTUnwrap(coordinator.mirrorReturnGateOpacity)
        let dialogueBand = try XCTUnwrap(coordinator.mirrorRealityReturnBandOpacity)
        let dialogueFace = try XCTUnwrap(coordinator.mirrorLinCheFaceLightOpacity)

        XCTAssertGreaterThan(thirdGate, 0.55)
        XCTAssertGreaterThan(thirdBand, 0.45)
        XCTAssertGreaterThan(thirdFace, 0.55)
        XCTAssertGreaterThan(thirdYaw, initialYaw)
        XCTAssertGreaterThan(dialogueGate, thirdGate)
        XCTAssertGreaterThan(dialogueBand, thirdBand)
        XCTAssertGreaterThan(dialogueFace, thirdFace)

        if let path = ProcessInfo.processInfo.environment["CAPTURE_MIRROR_RETURN_DIRECTOR_VIEW"] {
            let image = coordinator.renderSnapshot(size: CGSize(width: 960, height: 600))
            let tiff = try XCTUnwrap(image.tiffRepresentation)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try FileManager.default.createDirectory(at: URL(fileURLWithPath: path).deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: URL(fileURLWithPath: path))
            XCTAssertGreaterThan(png.count, 20_000)
        }
    }

    func testMirrorNavigationRigBrightensAsPlayerApproachesLamp() throws {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        let coordinator = ClassroomCoordinator()
        game.developerJump(to: .mirror, momentIndex: 1)
        game.narrativeCampaign.exploration.positionX = -0.22
        game.narrativeCampaign.exploration.positionZ = 4.7
        coordinator.update(game: game)
        let farPath = try XCTUnwrap(coordinator.mirrorNavigationPathOpacity)
        let farRing = try XCTUnwrap(coordinator.mirrorNavigationTargetRingOpacity)
        let farScale = try XCTUnwrap(coordinator.mirrorNavigationPathScale)

        game.narrativeCampaign.exploration.positionX = -1.18
        game.narrativeCampaign.exploration.positionZ = -2.05
        coordinator.update(game: game)
        let nearPath = try XCTUnwrap(coordinator.mirrorNavigationPathOpacity)
        let nearRing = try XCTUnwrap(coordinator.mirrorNavigationTargetRingOpacity)
        let nearScale = try XCTUnwrap(coordinator.mirrorNavigationPathScale)

        XCTAssertGreaterThan(nearPath, farPath)
        XCTAssertGreaterThan(nearRing, farRing)
        XCTAssertLessThan(nearScale.z, farScale.z)

        for slot in 0..<NarrativeMiniGame.trace.requiredInteractions {
            game.performNarrativeMiniGameAction(slot)
        }
        coordinator.update(game: game)
        XCTAssertEqual(coordinator.mirrorNavigationPathOpacity, 0)
        XCTAssertEqual(coordinator.mirrorNavigationTargetRingOpacity, 0)
    }

    func testMirrorMicroGameEchoModelTracksEveryInteractionStep() {
        var campaign = NarrativeCampaign(isActive: true, chapter: .mirror, momentIndex: 1)
        let empty = MirrorMicroGameEchoModel.derive(from: campaign)

        campaign.performMiniGameAction(0)
        campaign.performMiniGameAction(1)
        let traced = MirrorMicroGameEchoModel.derive(from: campaign)

        campaign.momentIndex = 3
        campaign.miniGameProgress = 0
        campaign.miniGameTouchedSlots = []
        campaign.performMiniGameAction(5)
        campaign.performMiniGameAction(2)
        let erased = MirrorMicroGameEchoModel.derive(from: campaign)

        XCTAssertTrue(empty.isActive)
        XCTAssertEqual(empty.completedSteps, 0)
        XCTAssertEqual(traced.completedSteps, 2)
        XCTAssertGreaterThan(traced.ratio, empty.ratio)
        XCTAssertGreaterThan(traced.echoOpacities[0], empty.echoOpacities[0])
        XCTAssertTrue(traced.detail.contains("第 2 段线"))
        XCTAssertEqual(erased.currentLightIndex, 2)
        XCTAssertEqual(erased.completedSteps, 2)
        XCTAssertTrue(erased.detail.contains("2 句比较"))
    }

    func testMirrorMicroGamePerformanceModelTracksOverlayAndReturn() {
        var campaign = NarrativeCampaign(isActive: true, chapter: .mirror, momentIndex: 1)
        let idle = MirrorMicroGamePerformanceModel.derive(from: campaign, activeMiniGame: nil)

        let opened = MirrorMicroGamePerformanceModel.derive(from: campaign, activeMiniGame: .trace)
        campaign.performMiniGameAction(0)
        campaign.performMiniGameAction(1)
        let progressed = MirrorMicroGamePerformanceModel.derive(from: campaign, activeMiniGame: .trace)

        for slot in 2..<NarrativeMiniGame.trace.requiredInteractions {
            campaign.performMiniGameAction(slot)
        }
        let returned = MirrorMicroGamePerformanceModel.derive(from: campaign, activeMiniGame: nil)

        XCTAssertFalse(idle.isActive)
        XCTAssertTrue(opened.isOverlayActive)
        XCTAssertEqual(opened.activeLightIndex, 0)
        XCTAssertTrue(opened.title.contains("进入草稿灯"))
        XCTAssertGreaterThan(progressed.portalOpacity, opened.portalOpacity)
        XCTAssertGreaterThan(progressed.beamOpacity, opened.beamOpacity)
        XCTAssertTrue(returned.isReturnPulseActive)
        XCTAssertGreaterThan(returned.returnPulseOpacity, opened.returnPulseOpacity)
        XCTAssertTrue(returned.detail.contains("回到镜面"))
    }

    func testMirrorMicroGameInputFeedbackExplainsRecoveryWithoutFailure() {
        var campaign = NarrativeCampaign(isActive: true, chapter: .mirror, momentIndex: 2)
        let ready = MirrorMicroGameInputFeedbackModel.ready(from: campaign, miniGame: .melody)

        let beforeProgress = campaign.miniGameProgress
        let beforeHints = campaign.miniGameHintCount
        campaign.performMiniGameAction(0)
        let wrong = MirrorMicroGameInputFeedbackModel.action(
            miniGame: .melody,
            slot: 0,
            beforeProgress: beforeProgress,
            afterProgress: campaign.miniGameProgress,
            beforeTouchedCount: 0,
            afterTouchedCount: 0,
            beforeHintCount: beforeHints,
            afterHintCount: campaign.miniGameHintCount,
            completed: campaign.miniGameCompleted
        )

        campaign.performMiniGameAction(1)
        let caught = MirrorMicroGameInputFeedbackModel.action(
            miniGame: .melody,
            slot: 1,
            beforeProgress: 0,
            afterProgress: campaign.miniGameProgress,
            beforeTouchedCount: 0,
            afterTouchedCount: 0,
            beforeHintCount: campaign.miniGameHintCount,
            afterHintCount: campaign.miniGameHintCount,
            completed: campaign.miniGameCompleted
        )

        XCTAssertEqual(ready.tone, .ready)
        XCTAssertEqual(wrong.tone, .recover)
        XCTAssertTrue(wrong.detail.contains("不记录失败"))
        XCTAssertTrue(wrong.recoveryText.contains("1/3"))
        XCTAssertEqual(caught.tone, .caught)
        XCTAssertTrue(caught.targetText.contains("第 2 拍"))
    }

    func testMirrorTraceGestureAssessmentRequiresEightyPercentCoverageWithinTolerance() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)]
        var samples: Set<Int> = []
        for x in [2, 22, 42] {
            let assessment = MirrorTraceGestureAssessment.assess(
                location: CGPoint(x: CGFloat(x), y: 6),
                segment: 0,
                points: points,
                coveredSamples: samples
            )
            XCTAssertTrue(assessment.isHit)
            if let sample = assessment.sampleIndex {
                samples.insert(sample)
            }
            XCTAssertFalse(assessment.shouldCommitSegment)
        }

        let fourth = MirrorTraceGestureAssessment.assess(
            location: CGPoint(x: 68, y: 4),
            segment: 0,
            points: points,
            coveredSamples: samples
        )
        if let sample = fourth.sampleIndex {
            samples.insert(sample)
        }
        let covered = MirrorTraceGestureAssessment.assess(
            location: CGPoint(x: 88, y: 5),
            segment: 0,
            points: points,
            coveredSamples: samples
        )
        let miss = MirrorTraceGestureAssessment.assess(
            location: CGPoint(x: 40, y: 24),
            segment: 0,
            points: points,
            coveredSamples: []
        )

        XCTAssertTrue(fourth.shouldCommitSegment)
        XCTAssertTrue(covered.shouldCommitSegment)
        XCTAssertEqual(covered.coverageRatio, 1, accuracy: 0.001)
        XCTAssertFalse(miss.isHit)
        XCTAssertGreaterThan(miss.distance, MirrorTraceGestureAssessment.hitTolerance)
    }

    func testMirrorEraseGestureAssessmentUsesSixtyPercentCoverageAndBlankRecovery() {
        let anchors = (0..<6).map { CGPoint(x: CGFloat($0) * 50, y: 0) }
        let first = MirrorEraseGestureAssessment.assess(
            location: CGPoint(x: 2, y: 4),
            anchors: anchors,
            touchedSlots: []
        )
        let repeated = MirrorEraseGestureAssessment.assess(
            location: CGPoint(x: 2, y: 4),
            anchors: anchors,
            touchedSlots: [0]
        )
        let fourth = MirrorEraseGestureAssessment.assess(
            location: CGPoint(x: 152, y: 0),
            anchors: anchors,
            touchedSlots: [0, 1, 2]
        )
        let blank = MirrorEraseGestureAssessment.assess(
            location: CGPoint(x: 600, y: 220),
            anchors: anchors,
            touchedSlots: [0, 1]
        )

        XCTAssertTrue(first.shouldCommitErase)
        XCTAssertEqual(first.slot, 0)
        XCTAssertFalse(repeated.shouldCommitErase)
        XCTAssertEqual(fourth.touchedCount, 4)
        XCTAssertGreaterThanOrEqual(fourth.coverageRatio, MirrorEraseGestureAssessment.targetCoverage)
        XCTAssertFalse(blank.isHit)
        XCTAssertNil(blank.slot)
    }

    func testMirrorMelodyPlaybackModelUsesSequenceOrderAndFrequencies() {
        var campaign = NarrativeCampaign(isActive: true, chapter: .mirror, momentIndex: 2)
        let ready = MirrorMelodyPlaybackModel.derive(from: campaign)

        campaign.performMiniGameAction(1)
        let progressed = MirrorMelodyPlaybackModel.derive(from: campaign)

        XCTAssertTrue(ready.isActive)
        XCTAssertEqual(ready.sequenceText, "灯 · 夜 · 风 · 笔")
        XCTAssertEqual(ready.frequencyText, "392Hz / 523Hz / 330Hz / 440Hz")
        XCTAssertEqual(ready.nextPadIndex, 1)
        XCTAssertTrue(ready.pads.first { $0.id == 1 }?.isNext == true)
        XCTAssertFalse(ready.pads.first { $0.id == 0 }?.isPlayed == true)
        XCTAssertEqual(progressed.completedBeats, 1)
        XCTAssertEqual(progressed.nextPadIndex, 3)
        XCTAssertTrue(progressed.pads.first { $0.id == 1 }?.isPlayed == true)
        XCTAssertTrue(progressed.pads.first { $0.id == 3 }?.isNext == true)
    }

    func testMirrorMicroEchoNodesLightUpWithOverlayProgress() throws {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        let coordinator = ClassroomCoordinator()
        game.developerJump(to: .mirror, momentIndex: 1)
        coordinator.update(game: game)
        let initial = coordinator.mirrorMicroEchoOpacities

        game.performNarrativeMiniGameAction(0)
        game.performNarrativeMiniGameAction(1)
        coordinator.update(game: game)
        let progressed = coordinator.mirrorMicroEchoOpacities
        let tracePositions = coordinator.mirrorMicroEchoPositions

        game.narrativeCampaign.momentIndex = 3
        game.narrativeCampaign.miniGameProgress = 0
        game.narrativeCampaign.miniGameTouchedSlots = []
        game.performNarrativeMiniGameAction(5)
        coordinator.update(game: game)
        let erasePositions = coordinator.mirrorMicroEchoPositions

        XCTAssertEqual(initial.count, 6)
        XCTAssertEqual(progressed.count, 6)
        XCTAssertGreaterThan(progressed[0], initial[0])
        XCTAssertGreaterThan(progressed[1], initial[1])
        XCTAssertGreaterThan(erasePositions[0].x, tracePositions[0].x)
    }

    func testMirrorMicroPortalStageFollowsActiveOverlayAndReturn() throws {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        let coordinator = ClassroomCoordinator()
        game.developerJump(to: .mirror, momentIndex: 1)
        coordinator.update(game: game)
        XCTAssertEqual(try XCTUnwrap(coordinator.mirrorMicroPortalOpacity), 0)
        XCTAssertEqual(try XCTUnwrap(coordinator.mirrorMicroPortalBeamOpacity), 0)
        XCTAssertEqual(try XCTUnwrap(coordinator.mirrorMicroReturnPulseOpacity), 0)

        game.presentNarrativeMicroGame(.trace)
        coordinator.update(game: game)
        let openPortal = try XCTUnwrap(coordinator.mirrorMicroPortalOpacity)
        let openBeam = try XCTUnwrap(coordinator.mirrorMicroPortalBeamOpacity)
        let openPulse = try XCTUnwrap(coordinator.mirrorMicroReturnPulseOpacity)
        let tracePosition = try XCTUnwrap(coordinator.mirrorMicroPortalPosition)

        for slot in 0..<NarrativeMiniGame.trace.requiredInteractions {
            game.performNarrativeMiniGameAction(slot)
        }
        coordinator.update(game: game)
        let returnPortal = try XCTUnwrap(coordinator.mirrorMicroPortalOpacity)
        let returnBeam = try XCTUnwrap(coordinator.mirrorMicroPortalBeamOpacity)
        let returnPulse = try XCTUnwrap(coordinator.mirrorMicroReturnPulseOpacity)

        XCTAssertGreaterThan(openPortal, 0.6)
        XCTAssertGreaterThan(openBeam, 0.3)
        XCTAssertEqual(openPulse, 0)
        XCTAssertEqual(tracePosition.x, -1.18, accuracy: 0.01)
        if let path = ProcessInfo.processInfo.environment["CAPTURE_MIRROR_MICRO_PORTAL_VIEW"] {
            let image = coordinator.renderSnapshot(size: CGSize(width: 960, height: 600))
            let tiff = try XCTUnwrap(image.tiffRepresentation)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try FileManager.default.createDirectory(at: URL(fileURLWithPath: path).deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: URL(fileURLWithPath: path))
            XCTAssertGreaterThan(png.count, 20_000)
        }
        XCTAssertLessThan(returnPortal, openPortal)
        XCTAssertLessThan(returnBeam, openBeam)
        XCTAssertGreaterThan(returnPulse, 0.6)
        XCTAssertNil(game.activeNarrativeMicroGame)
    }

    func testMirrorMicroGameStepPublishesAudioCueAndPlaytestEcho() {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.developerJump(to: .mirror, momentIndex: 1)
        game.audioCues = []

        game.performNarrativeMiniGameAction(0)

        XCTAssertEqual(game.audioCues.first?.kind, .lights)
        XCTAssertEqual(game.audioCues.first?.direction, "镜面草稿灯")
        XCTAssertTrue(game.audioCues.first?.note.contains("第 1 段线") == true)
        XCTAssertTrue(game.message.contains("第 1 段线"))
        XCTAssertTrue(game.developerPlaytestLog.contains { $0.contains("MICRO_ECHO trace slot=0 progress=1/5") })
    }

    func testMirrorDissolveProgressSoftensTheThreeDimensionalStageAfterThirdLamp() throws {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        let coordinator = ClassroomCoordinator()
        game.developerJump(to: .mirror, momentIndex: 3)
        coordinator.update(game: game)
        let initialOpacity = try XCTUnwrap(coordinator.mirrorNarrativeStageOpacity)

        for slot in 0..<NarrativeMiniGame.erase.requiredInteractions {
            game.performNarrativeMiniGameAction(slot)
        }
        XCTAssertEqual(game.narrativeCampaign.mirrorDissolveProgress, 0.72, accuracy: 0.001)
        coordinator.update(game: game)
        let thirdLampOpacity = try XCTUnwrap(coordinator.mirrorNarrativeStageOpacity)

        game.narrativeCampaign.choose("playErase")
        XCTAssertEqual(game.narrativeCampaign.currentMoment.id, "2.listen")
        XCTAssertEqual(game.narrativeCampaign.mirrorDissolveProgress, 1, accuracy: 0.001)
        coordinator.update(game: game)
        let dialogueOpacity = try XCTUnwrap(coordinator.mirrorNarrativeStageOpacity)

        XCTAssertLessThan(thirdLampOpacity, initialOpacity)
        XCTAssertLessThan(dialogueOpacity, thirdLampOpacity)
    }

    func testMelodyMiniGameReplayPublishesSpatialAudioCue() {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.developerJump(to: .mirror, momentIndex: 2)
        game.presentNarrativeMicroGame(.melody)
        game.audioCues = []

        game.replayNarrativeMiniGameCue()

        XCTAssertEqual(game.audioCues.first?.kind, .lights)
        XCTAssertEqual(game.audioCues.first?.direction, "镜面旋律灯")
        XCTAssertTrue(game.audioCues.first?.note.contains("四拍程序化旋律") == true)
        XCTAssertTrue(game.audioCues.first?.note.contains("392Hz / 523Hz / 330Hz / 440Hz") == true)
        XCTAssertEqual(game.narrativeCampaign.miniGameHintCount, 1)
        XCTAssertTrue(game.developerPlaytestLog.contains { $0.contains("MELODY_PLAYBACK replay sequence=灯 · 夜 · 风 · 笔") })
    }

    func testMicroGameInputFeedbackRecordsWrongMelodyAsRecovery() {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.developerJump(to: .mirror, momentIndex: 2)
        game.presentNarrativeMicroGame(.melody)
        game.audioCues = []

        game.performNarrativeMiniGameAction(0)

        XCTAssertEqual(game.narrativeCampaign.miniGameProgress, 0)
        XCTAssertEqual(game.narrativeCampaign.miniGameHintCount, 1)
        XCTAssertEqual(game.lastNarrativeMicroGameFeedback?.tone, .recover)
        XCTAssertTrue(game.lastNarrativeMicroGameFeedback?.detail.contains("不记录失败") == true)
        XCTAssertTrue(game.message.contains("不记录失败"))
        XCTAssertTrue(game.developerPlaytestLog.contains { $0.contains("MICRO_INPUT melody recover slot=0") })
        XCTAssertTrue(game.developerPlaytestLog.contains { $0.contains("MELODY_RHYTHM recover next=灯 hints=1") })

        game.performNarrativeMiniGameAction(1)

        XCTAssertEqual(game.narrativeCampaign.miniGameProgress, 1)
        XCTAssertEqual(game.lastNarrativeMicroGameFeedback?.tone, .caught)
        XCTAssertTrue(game.developerPlaytestLog.contains { $0.contains("MICRO_INPUT melody caught slot=1") })
        XCTAssertTrue(game.developerPlaytestLog.contains { $0.contains("MELODY_RHYTHM caught next=夜 hints=1") })
    }

    func testMicroGameDragRecoveryAttemptDoesNotAdvanceOrCloseOverlay() {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.developerJump(to: .mirror, momentIndex: 1)
        game.presentNarrativeMicroGame(.trace)
        game.audioCues = []

        game.recordNarrativeMicroGameRecoveryAttempt(slot: 0)

        XCTAssertEqual(game.narrativeCampaign.miniGameProgress, 0)
        XCTAssertEqual(game.activeNarrativeMicroGame, .trace)
        XCTAssertEqual(game.lastNarrativeMicroGameFeedback?.tone, .recover)
        XCTAssertTrue(game.lastNarrativeMicroGameFeedback?.detail.contains("不会丢") == true)
        XCTAssertTrue(game.message.contains("不会丢"))
        XCTAssertEqual(game.audioCues.first?.kind, .lights)
        XCTAssertTrue(game.developerPlaytestLog.contains { $0.contains("MICRO_INPUT trace recover slot=0") })
    }

    func testMiniGameCompletionPublishesLampSpatialAudioCues() {
        let traceGame = GameManager(userDefaults: isolatedUserDefaults())
        traceGame.developerJump(to: .mirror, momentIndex: 1)
        traceGame.presentNarrativeMicroGame(.trace)
        traceGame.audioCues = []
        for slot in 0..<NarrativeMiniGame.trace.requiredInteractions {
            traceGame.performNarrativeMiniGameAction(slot)
        }
        XCTAssertNil(traceGame.activeNarrativeMicroGame)
        XCTAssertEqual(traceGame.audioCues.first?.direction, "镜面草稿灯")
        XCTAssertTrue(traceGame.audioCues.first?.note.contains("第一段光路") == true)
        XCTAssertTrue(traceGame.message.contains("草稿灯亮了"))
        XCTAssertTrue(traceGame.featuredMonologue?.text.contains("还可以继续") == true)
        XCTAssertTrue(traceGame.developerPlaytestLog.contains { $0.contains("MICRO_PORTAL return trace") })

        let melodyGame = GameManager(userDefaults: isolatedUserDefaults())
        melodyGame.developerJump(to: .mirror, momentIndex: 2)
        melodyGame.presentNarrativeMicroGame(.melody)
        melodyGame.audioCues = []
        for slot in [1, 3, 0, 2] {
            melodyGame.performNarrativeMiniGameAction(slot)
        }
        XCTAssertNil(melodyGame.activeNarrativeMicroGame)
        XCTAssertEqual(melodyGame.audioCues.first?.direction, "镜面旋律灯")
        XCTAssertTrue(melodyGame.audioCues.first?.note.contains("第二盏灯") == true)
        XCTAssertTrue(melodyGame.message.contains("旋律灯亮了"))
        XCTAssertTrue(melodyGame.featuredMonologue?.text.contains("被接住不是失败") == true)

        let eraseGame = GameManager(userDefaults: isolatedUserDefaults())
        eraseGame.developerJump(to: .mirror, momentIndex: 3)
        eraseGame.presentNarrativeMicroGame(.erase)
        eraseGame.audioCues = []
        for slot in 0..<NarrativeMiniGame.erase.requiredInteractions {
            eraseGame.performNarrativeMiniGameAction(slot)
        }
        XCTAssertNil(eraseGame.activeNarrativeMicroGame)
        XCTAssertEqual(eraseGame.audioCues.first?.direction, "镜面擦痕灯")
        XCTAssertTrue(eraseGame.audioCues.first?.note.contains("没有把痕迹清空") == true)
        XCTAssertTrue(eraseGame.message.contains("擦痕灯亮了"))
        XCTAssertTrue(eraseGame.featuredMonologue?.text.contains("林澈自己的声音") == true)
    }

    func testMirrorLightProgressViewRendersThreeLightRouteState() throws {
        var campaign = NarrativeCampaign(isActive: true, chapter: .mirror, momentIndex: 2)
        campaign.miniGameProgress = 2

        let renderer = ImageRenderer(content: ZStack {
            Color.black
            MirrorLightProgressView(campaign: campaign)
                .padding(18)
                .frame(width: 520)
        }
        .frame(width: 620, height: 220))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 620, height: 220)

        guard let image = renderer.nsImage else {
            XCTFail("MirrorLightProgressView did not render")
            return
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        var minimum = 1.0
        var maximum = 0.0
        var visibleSamples = 0
        var litSamples = 0
        var cyanSamples = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                minimum = min(minimum, luminance)
                maximum = max(maximum, luminance)
                if luminance > 0.04 { visibleSamples += 1 }
                if color.redComponent > 0.55, color.greenComponent > 0.45, color.blueComponent < 0.35 {
                    litSamples += 1
                }
                if color.blueComponent > color.redComponent + 0.08, color.greenComponent > color.redComponent + 0.04 {
                    cyanSamples += 1
                }
            }
        }

        if let path = ProcessInfo.processInfo.environment["CAPTURE_MIRROR_LIGHT_PROGRESS_VIEW"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }

        XCTAssertEqual(campaign.currentMoment.miniGame, .melody)
        XCTAssertGreaterThan(visibleSamples, 5_000)
        XCTAssertGreaterThan(litSamples, 300)
        XCTAssertGreaterThan(cyanSamples, 180)
        XCTAssertGreaterThan(maximum - minimum, 0.16)
    }

    func testNarrativeMicroGameOverlayPausesStoryButAllowsGameInput() {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.developerJump(to: .mirror, momentIndex: 1)

        XCTAssertEqual(game.narrativeCampaign.currentMoment.miniGame, .trace)
        XCTAssertFalse(game.narrativePaused)

        game.presentNarrativeMicroGame(.trace)

        XCTAssertEqual(game.activeNarrativeMicroGame, .trace)
        XCTAssertTrue(game.narrativePauseReasons.contains(.microGame))
        XCTAssertFalse(game.shouldShowNarrativePauseOverlay)

        game.advanceNarrative(game.narrativeCampaign.currentMoment.choices[0].id)
        XCTAssertEqual(game.narrativeCampaign.currentMoment.miniGame, .trace)

        for slot in 0..<NarrativeMiniGame.trace.requiredInteractions {
            game.performNarrativeMiniGameAction(slot)
        }

        XCTAssertTrue(game.narrativeCampaign.miniGameCompleted)
        XCTAssertNil(game.activeNarrativeMicroGame)
        XCTAssertFalse(game.narrativePauseReasons.contains(.microGame))
        XCTAssertFalse(game.narrativePaused)
    }

    func testMirrorMiniGameRequiresNearbyLightHotspotBeforeOverlayOpens() {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.developerJump(to: .mirror, momentIndex: 1)
        game.narrativeCampaign.exploration.interactionCount = 1
        game.narrativeCampaign.exploration.lastInteractedHotspot = "mirror.threshold"

        game.advanceNarrative("playTrace")

        XCTAssertNil(game.activeNarrativeMicroGame)
        XCTAssertEqual(game.narrativeCampaign.currentMoment.id, "2.trace")
        XCTAssertFalse(game.narrativeCampaign.currentMomentActionReady)
        XCTAssertTrue(game.message.contains("草稿灯"))

        game.narrativeCampaign.exploration.positionX = -1.18
        game.narrativeCampaign.exploration.positionZ = -2.42
        XCTAssertEqual(game.nearbyNarrativeHotspot?.id, "mirror.light.trace")

        XCTAssertTrue(game.interactNarrativeHotspot())

        XCTAssertEqual(game.activeNarrativeMicroGame, .trace)
        XCTAssertTrue(game.narrativePauseReasons.contains(.microGame))
        XCTAssertEqual(game.narrativeCampaign.exploration.lastInteractedHotspot, "mirror.light.trace")
        XCTAssertTrue(game.narrativeCampaign.currentMomentActionReady)
        XCTAssertEqual(game.narrativeCampaign.currentMoment.id, "2.trace")

        for slot in 0..<NarrativeMiniGame.trace.requiredInteractions {
            game.performNarrativeMiniGameAction(slot)
        }
        XCTAssertNil(game.activeNarrativeMicroGame)
        game.advanceNarrative("playTrace")
        XCTAssertEqual(game.narrativeCampaign.currentMoment.id, "2.melody")
    }

    func testDismissingIncompleteMicroGameKeepsProgressWithoutFailure() {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.developerJump(to: .mirror, momentIndex: 1)
        game.presentNarrativeMicroGame(.trace)
        game.performNarrativeMiniGameAction(0)

        game.dismissNarrativeMicroGame()

        XCTAssertNil(game.activeNarrativeMicroGame)
        XCTAssertFalse(game.narrativePauseReasons.contains(.microGame))
        XCTAssertFalse(game.narrativeCampaign.miniGameCompleted)
        XCTAssertEqual(game.narrativeCampaign.miniGameProgress, 1)
        XCTAssertTrue(game.message.contains("这不是失败"))
        XCTAssertEqual(game.audioCues.first?.direction, NarrativeMiniGame.trace.title)
        XCTAssertTrue(game.audioCues.first?.note.contains("进度会留在灯里") == true)
    }

    func testKeyboardAlternativeMicroGameControlsAdvanceStepwiseWithoutAutopass() {
        let traceGame = GameManager(userDefaults: isolatedUserDefaults())
        traceGame.updateAccessibilityPreferences { $0.keyboardAlternativeInput = true }
        traceGame.developerJump(to: .mirror, momentIndex: 1)
        traceGame.presentNarrativeMicroGame(.trace)

        traceGame.performNarrativeMiniGameAction(traceGame.narrativeCampaign.miniGameProgress)

        XCTAssertEqual(traceGame.narrativeCampaign.miniGameProgress, 1)
        XCTAssertFalse(traceGame.narrativeCampaign.miniGameCompleted)
        XCTAssertEqual(traceGame.activeNarrativeMicroGame, .trace)

        while traceGame.activeNarrativeMicroGame != nil {
            traceGame.performNarrativeMiniGameAction(traceGame.narrativeCampaign.miniGameProgress)
        }
        XCTAssertTrue(traceGame.narrativeCampaign.miniGameCompleted)
        XCTAssertNil(traceGame.activeNarrativeMicroGame)

        let eraseGame = GameManager(userDefaults: isolatedUserDefaults())
        eraseGame.updateAccessibilityPreferences { $0.keyboardAlternativeInput = true }
        eraseGame.developerJump(to: .mirror, momentIndex: 3)
        eraseGame.presentNarrativeMicroGame(.erase)

        for slot in 0..<NarrativeMiniGame.erase.requiredInteractions {
            eraseGame.performNarrativeMiniGameAction(slot)
            if slot < NarrativeMiniGame.erase.requiredInteractions - 1 {
                XCTAssertFalse(eraseGame.narrativeCampaign.miniGameCompleted)
                XCTAssertEqual(eraseGame.activeNarrativeMicroGame, .erase)
            }
        }

        XCTAssertTrue(eraseGame.narrativeCampaign.miniGameCompleted)
        XCTAssertEqual(eraseGame.narrativeCampaign.miniGameTouchedSlots, Set(0..<NarrativeMiniGame.erase.requiredInteractions))
        XCTAssertNil(eraseGame.activeNarrativeMicroGame)
    }

    func testMicroGameOverlayViewRendersTraceInteractionSurface() throws {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.developerJump(to: .mirror, momentIndex: 1)
        game.presentNarrativeMicroGame(.trace)
        game.performNarrativeMiniGameAction(0)
        game.performNarrativeMiniGameAction(1)

        let renderer = ImageRenderer(content: ZStack {
            Color.black
            MicroGameOverlayView(game: game, miniGame: .trace)
                .frame(width: 900, height: 620)
        }
        .frame(width: 940, height: 660))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 940, height: 660)

        guard let image = renderer.nsImage else {
            XCTFail("MicroGameOverlayView did not render")
            return
        }
        let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        var visibleSamples = 0
        var purpleSamples = 0
        var textSamples = 0
        var minLum = 1.0
        var maxLum = 0.0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                minLum = min(minLum, luminance)
                maxLum = max(maxLum, luminance)
                if luminance > 0.035 { visibleSamples += 1 }
                if color.redComponent > 0.22,
                   color.blueComponent > 0.24,
                   color.greenComponent < color.blueComponent - 0.04 {
                    purpleSamples += 1
                }
                if luminance > 0.52,
                   abs(color.redComponent - color.greenComponent) < 0.12,
                   abs(color.greenComponent - color.blueComponent) < 0.12 {
                    textSamples += 1
                }
            }
        }

        if let path = ProcessInfo.processInfo.environment["CAPTURE_MICRO_GAME_OVERLAY_VIEW"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }

        XCTAssertEqual(game.activeNarrativeMicroGame, .trace)
        XCTAssertGreaterThan(visibleSamples, 18_000)
        XCTAssertGreaterThan(purpleSamples, 1_000)
        XCTAssertGreaterThan(textSamples, 80)
        XCTAssertGreaterThan(maxLum - minLum, 0.16)
    }

    func testMicroGameOverlayKeyboardAlternativeRendersStepwiseControls() throws {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.updateAccessibilityPreferences { $0.keyboardAlternativeInput = true }
        game.developerJump(to: .mirror, momentIndex: 1)
        game.presentNarrativeMicroGame(.trace)
        game.performNarrativeMiniGameAction(0)

        let renderer = ImageRenderer(content: ZStack {
            Color.black
            MicroGameOverlayView(game: game, miniGame: .trace)
                .frame(width: 900, height: 620)
        }
        .frame(width: 940, height: 660))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 940, height: 660)

        guard let image = renderer.nsImage else {
            XCTFail("MicroGameOverlayView keyboard alternative did not render")
            return
        }
        let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        var visibleSamples = 0
        var mintSamples = 0
        var brightSamples = 0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                if luminance > 0.035 { visibleSamples += 1 }
                if color.greenComponent > 0.34,
                   color.blueComponent > 0.22,
                   color.redComponent < 0.28 {
                    mintSamples += 1
                }
                if luminance > 0.48 { brightSamples += 1 }
            }
        }

        if let path = ProcessInfo.processInfo.environment["CAPTURE_MICRO_GAME_KEYBOARD_VIEW"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }

        XCTAssertEqual(game.accessibilityPreferences.keyboardAlternativeInput, true)
        XCTAssertEqual(game.activeNarrativeMicroGame, .trace)
        XCTAssertGreaterThan(visibleSamples, 18_000)
        XCTAssertGreaterThan(mintSamples, 250)
        XCTAssertGreaterThan(brightSamples, 160)
    }

    func testMelodyMicroGameOverlayRendersSequenceRailAndNextPad() throws {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.developerJump(to: .mirror, momentIndex: 2)
        game.presentNarrativeMicroGame(.melody)
        game.performNarrativeMiniGameAction(1)

        let renderer = ImageRenderer(content: ZStack {
            Color.black
            MicroGameOverlayView(game: game, miniGame: .melody)
                .frame(width: 900, height: 620)
        }
        .frame(width: 940, height: 660))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 940, height: 660)

        guard let image = renderer.nsImage else {
            XCTFail("Melody MicroGameOverlayView did not render")
            return
        }
        let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        var visibleSamples = 0
        var cyanSamples = 0
        var brightSamples = 0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                if luminance > 0.035 { visibleSamples += 1 }
                if color.blueComponent > 0.32,
                   color.greenComponent > 0.26,
                   color.redComponent < 0.24 {
                    cyanSamples += 1
                }
                if luminance > 0.48 { brightSamples += 1 }
            }
        }

        if let path = ProcessInfo.processInfo.environment["CAPTURE_MELODY_MICRO_GAME_VIEW"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }

        let melody = MirrorMelodyPlaybackModel.derive(from: game.narrativeCampaign)
        XCTAssertEqual(melody.nextPadIndex, 3)
        XCTAssertEqual(melody.sequenceText, "灯 · 夜 · 风 · 笔")
        XCTAssertGreaterThan(visibleSamples, 18_000)
        XCTAssertGreaterThan(cyanSamples, 300)
        XCTAssertGreaterThan(brightSamples, 160)
    }

    func testNarrativeExplorationMovesTheRenderedFirstPersonCamera() {
        let game = GameManager()
        let coordinator = ClassroomCoordinator()
        game.developerJump(to: .mirror)
        coordinator.update(game: game)
        let initial = coordinator.narrativeCameraPosition

        game.moveNarrativeExploration(forward: 1, strafe: 0, deltaTime: 0.05)
        coordinator.update(game: game)

        XCTAssertEqual(coordinator.narrativeCameraPosition.x, initial.x, accuracy: 0.0001)
        XCTAssertLessThan(coordinator.narrativeCameraPosition.z, initial.z)
    }

    func testPrologueCompletesThroughSingleLegalBeatChain() {
        let game = GameManager()
        game.startPrologue(resume: false)

        for beat in PrologueBeatID.allCases {
            XCTAssertEqual(game.prologueCurrentBeat, beat)
            game.completePrologueBeat(beat, source: .player)
        }

        XCTAssertFalse(game.isPrologueActive)
        XCTAssertTrue(game.prologueState.prologueCompleted)
        XCTAssertEqual(game.chapterOneStep, .observeLinChe)
        guard case .playing = game.gameState else {
            return XCTFail("The prologue should hand off directly to chapter one")
        }
    }

    func testPrologueHandoffPreservesTheSameClassroomCast() {
        let game = GameManager()
        game.startPrologue(resume: false)
        let castBeforeBell = game.classmates.map { ($0.name, $0.seat.row, $0.seat.column, $0.profile) }

        for beat in PrologueBeatID.allCases {
            game.completePrologueBeat(beat, source: .player)
        }
        let castAfterBell = game.classmates.map { ($0.name, $0.seat.row, $0.seat.column, $0.profile) }

        XCTAssertEqual(castAfterBell.count, castBeforeBell.count)
        for (before, after) in zip(castBeforeBell, castAfterBell) {
            XCTAssertEqual(before.0, after.0)
            XCTAssertEqual(before.1, after.1)
            XCTAssertEqual(before.2, after.2)
            XCTAssertEqual(before.3, after.3)
        }
    }

    func testPrologueOnlyAllowsLookDuringAuthoredLookBeats() {
        let game = GameManager()
        game.startPrologue(resume: false)

        game.rotateStudentView(deltaX: -100, deltaY: 0)
        XCTAssertEqual(game.studentLookYaw, 0)

        game.completePrologueBeat(.gateArrival, source: .performance)
        game.rotateStudentView(deltaX: -100, deltaY: 0)
        XCTAssertNotEqual(game.studentLookYaw, 0)
    }

    func testMouseCaptureShortcutUsesPhysicalKeyAcrossInputMethods() {
        XCTAssertTrue(ClassroomCoordinator.isMouseLookToggle(keyCode: 50, characters: nil))
        XCTAssertTrue(ClassroomCoordinator.isMouseLookToggle(keyCode: 50, characters: "§"))
        XCTAssertTrue(ClassroomCoordinator.isMouseLookToggle(keyCode: 0, characters: "~"))
        XCTAssertTrue(ClassroomCoordinator.isMouseLookToggle(keyCode: 0, characters: "～"))
        XCTAssertFalse(ClassroomCoordinator.isMouseLookToggle(keyCode: 13, characters: "w"))
    }

    func testChapterOneAlwaysStartsAsSuNianStudentPath() {
        let game = GameManager()
        game.selectedRole = .homeroomTeacher

        game.startGame()

        XCTAssertEqual(game.activeRole, .regularStudent)
        XCTAssertEqual(game.activeChapter, .silentClassroom)
    }

    func testTeacherTruthRunStartsPlayableTeacherPerspectiveFromCompletedNarrative() {
        let game = GameManager()
        var campaign = NarrativeCampaign(isActive: true, isComplete: true, chapter: .epilogue)
        campaign.clueCount = 5
        campaign.companionID = "周予安"
        campaign.privacyProtected = true
        campaign.selfCared = true
        campaign.sharedSelf = true
        campaign.jiangDialogueState = NarrativeJiangDialogueState(
            segmentIndex: 3,
            responseKinds: [.listening, .accompanying, .silentPresence, .listening],
            consecutiveTimeouts: 0,
            listenPhaseComplete: true,
            educationCardDismissed: true,
            riskAskMethod: .direct,
            disclosedRisk: .confirmed
        )
        campaign.safetyHandoffState = NarrativeSafetyHandoffState(
            authoredRisk: .high,
            riskAsked: true,
            adultContactInitiated: true,
            contactMethod: "电话",
            safetyHandoffComplete: true,
            route: .urgentSchoolResponse,
            entryMode: .urgentHandoffWaiting,
            resolutionPath: .voluntary
        )
        game.narrativeCampaign = campaign

        game.startTeacherTruthRunFromEpilogue()

        XCTAssertEqual(game.gameState, .playing)
        XCTAssertEqual(game.selectedRole, .homeroomTeacher)
        XCTAssertEqual(game.activeRole, .homeroomTeacher)
        XCTAssertEqual(game.viewMode, .teacher)
        XCTAssertFalse(game.narrativeCampaign.isActive)
        XCTAssertFalse(game.isFullNarrativeRun)
        XCTAssertGreaterThan(game.teacher.empathy, 80)
        XCTAssertLessThan(game.teacher.misreadRisk, 28)
        XCTAssertTrue(game.teacherTruthRunSummary.contains("周予安"))
        XCTAssertTrue(game.message.contains("教师真相二周目"))
    }

    func testTeacherTruthRunCompletesObjectiveChainIntoTeacherEnding() {
        let game = GameManager()
        var campaign = NarrativeCampaign(isActive: true, isComplete: true, chapter: .epilogue)
        campaign.clueCount = 5
        campaign.companionID = "许栀"
        campaign.privacyProtected = true
        campaign.selfCared = true
        campaign.sharedSelf = true
        campaign.jiangDialogueState = NarrativeJiangDialogueState(
            segmentIndex: 3,
            responseKinds: [.listening, .accompanying, .silentPresence, .listening],
            consecutiveTimeouts: 0,
            listenPhaseComplete: true,
            educationCardDismissed: true,
            riskAskMethod: .direct,
            disclosedRisk: .confirmed
        )
        campaign.safetyHandoffState = NarrativeSafetyHandoffState(
            authoredRisk: .high,
            riskAsked: true,
            adultContactInitiated: true,
            contactMethod: "消息",
            safetyHandoffComplete: true,
            route: .urgentSchoolResponse,
            entryMode: .urgentHandoffWaiting,
            resolutionPath: .voluntary
        )
        game.narrativeCampaign = campaign
        game.startTeacherTruthRunFromEpilogue()

        XCTAssertEqual(game.currentTeacherTruthObjective?.action, .scanClass)
        game.executeTeacherAction(.scanClass)
        XCTAssertEqual(game.currentTeacherTruthObjective?.action, .observeTarget)
        game.executeTeacherAction(.observeTarget)
        XCTAssertEqual(game.currentTeacherTruthObjective?.action, .care)
        game.executeTeacherAction(.care)
        XCTAssertEqual(game.currentTeacherTruthObjective?.action, .allowBreak)
        game.executeTeacherAction(.allowBreak)

        XCTAssertTrue(game.teacherTruthRunCompleted)
        XCTAssertFalse(game.isTeacherTruthRunActive)
        XCTAssertEqual(game.completedTeacherTruthObjectiveIDs.count, 4)
        XCTAssertGreaterThanOrEqual(game.replay.count, 4)
        if case .ending(let ending) = game.gameState {
            XCTAssertEqual(ending.title, "教师理解")
            XCTAssertTrue(ending.body.contains("保护"))
        } else {
            XCTFail("Teacher truth run should finish into an ending")
        }
    }

    func testTeacherTruthRunHudRendersObjectiveChain() throws {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        var campaign = NarrativeCampaign(isActive: true, isComplete: true, chapter: .epilogue)
        campaign.clueCount = 5
        campaign.companionID = "周予安"
        campaign.privacyProtected = true
        campaign.selfCared = true
        campaign.sharedSelf = true
        campaign.jiangDialogueState = NarrativeJiangDialogueState(
            segmentIndex: 3,
            responseKinds: [.listening, .accompanying, .silentPresence, .listening],
            consecutiveTimeouts: 0,
            listenPhaseComplete: true,
            educationCardDismissed: true,
            riskAskMethod: .direct,
            disclosedRisk: .confirmed
        )
        campaign.safetyHandoffState = NarrativeSafetyHandoffState(
            authoredRisk: .high,
            riskAsked: true,
            adultContactInitiated: true,
            contactMethod: "电话",
            safetyHandoffComplete: true,
            route: .urgentSchoolResponse,
            entryMode: .urgentHandoffWaiting,
            resolutionPath: .voluntary
        )
        game.narrativeCampaign = campaign
        game.startTeacherTruthRunFromEpilogue()

        let renderer = ImageRenderer(content: ZStack {
            Color.black
            TeacherTruthRoutePanel(
                summary: game.teacherTruthRunSummary,
                objectives: game.teacherTruthObjectives
            )
            .padding(24)
            .background(.black.opacity(0.46), in: RoundedRectangle(cornerRadius: 8))
            .frame(width: 520, height: 180)
        }
        .frame(width: 620, height: 260))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 620, height: 260)

        guard let image = renderer.nsImage else {
            XCTFail("Teacher truth run HUD did not render")
            return
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        var minimum = 1.0
        var maximum = 0.0
        var visibleSamples = 0
        for y in stride(from: 8, to: bitmap.pixelsHigh, by: 24) {
            for x in stride(from: 8, to: bitmap.pixelsWide, by: 24) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                minimum = min(minimum, luminance)
                maximum = max(maximum, luminance)
                if luminance > 0.05 { visibleSamples += 1 }
            }
        }
        XCTAssertGreaterThan(visibleSamples, 28)
        XCTAssertGreaterThan(maximum - minimum, 0.10)

        if let path = ProcessInfo.processInfo.environment["CAPTURE_TEACHER_TRUTH_ROUTE_VIEW"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }
    }

    func testPolicyExperimentLabRendersInstitutionalWhatIfs() throws {
        var campaign = NarrativeCampaign(isActive: true, isComplete: true, chapter: .epilogue)
        campaign.clueCount = 5
        campaign.companionID = "许栀"
        campaign.privacyProtected = true
        campaign.selfCared = true
        campaign.sharedSelf = true
        campaign.jiangDialogueState = NarrativeJiangDialogueState(
            segmentIndex: 3,
            responseKinds: [.listening, .accompanying, .silentPresence, .listening],
            consecutiveTimeouts: 0,
            listenPhaseComplete: true,
            educationCardDismissed: true,
            riskAskMethod: .direct,
            disclosedRisk: .confirmed
        )
        campaign.safetyHandoffState = NarrativeSafetyHandoffState(
            authoredRisk: .high,
            riskAsked: true,
            adultContactInitiated: true,
            contactMethod: "电话",
            safetyHandoffComplete: true,
            route: .urgentSchoolResponse,
            entryMode: .urgentHandoffWaiting,
            resolutionPath: .voluntary
        )

        let renderer = ImageRenderer(content: ZStack {
            Color.black
            PolicyExperimentLabView(campaign: campaign)
                .padding(24)
                .background(.black.opacity(0.46), in: RoundedRectangle(cornerRadius: 8))
                .frame(width: 720, height: 230)
        }
        .frame(width: 780, height: 300))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 780, height: 300)

        guard let image = renderer.nsImage else {
            XCTFail("Policy experiment lab did not render")
            return
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        var minimum = 1.0
        var maximum = 0.0
        var visibleSamples = 0
        for y in stride(from: 8, to: bitmap.pixelsHigh, by: 24) {
            for x in stride(from: 8, to: bitmap.pixelsWide, by: 24) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                minimum = min(minimum, luminance)
                maximum = max(maximum, luminance)
                if luminance > 0.05 { visibleSamples += 1 }
            }
        }
        XCTAssertGreaterThan(visibleSamples, 42)
        XCTAssertGreaterThan(maximum - minimum, 0.10)

        if let path = ProcessInfo.processInfo.environment["CAPTURE_POLICY_EXPERIMENT_VIEW"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
           try png.write(to: url)
        }
    }

    func testBreakdownRecoverySequenceRequiresThreePlayableSteps() {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.startGame()
        game.player.stress = 92
        game.player.maskCost = 88
        game.player.exposure = 54
        game.player.psychicEnergy = 18
        game.player.support = 18
        let initialRisk = game.player.breakdownRisk

        game.presentEvent(
            kind: .playerBreakdown,
            title: "崩溃信号",
            body: "测试恢复序列",
            choices: [EventChoice(id: "breakdown_nameSignal", title: "说出报警", detail: "先承认信号")]
        )

        XCTAssertFalse(game.isBreakdownRecoveryActive)
        game.resolveEventChoice(EventChoice(id: "breakdown_nameSignal", title: "说出报警", detail: "先承认信号"))
        XCTAssertTrue(game.isBreakdownRecoveryActive)
        XCTAssertEqual(game.currentBreakdownRecoveryStep, .returnToBody)
        XCTAssertEqual(game.completedBreakdownRecoverySteps, [.nameSignal])

        game.resolveEventChoice(EventChoice(id: "breakdown_returnToBody", title: "回到身体", detail: "稳定身体"))
        XCTAssertEqual(game.currentBreakdownRecoveryStep, .acceptSupport)
        XCTAssertTrue(game.completedBreakdownRecoverySteps.contains(.returnToBody))

        game.resolveEventChoice(EventChoice(id: "breakdown_acceptSupport", title: "接住支持", detail: "交给支持网络"))

        XCTAssertFalse(game.isBreakdownRecoveryActive)
        XCTAssertTrue(game.breakdownRecoverySummary.contains("恢复完成"))
        XCTAssertGreaterThanOrEqual(game.replay.count, 3)
        XCTAssertLessThan(game.player.breakdownRisk, initialRisk)
        XCTAssertEqual(game.gameState, .playing)
    }

    func testBreakdownRecoveryPanelRendersVisibleStepChain() throws {
        let renderer = ImageRenderer(content: ZStack {
            Color.black
            BreakdownRecoveryPanel(
                summary: "1 / 3 · 说出报警",
                steps: BreakdownRecoveryStep.allCases,
                completed: [.nameSignal],
                current: .returnToBody
            )
            .padding(24)
            .background(.black.opacity(0.46), in: RoundedRectangle(cornerRadius: 8))
            .frame(width: 680, height: 170)
        }
        .frame(width: 740, height: 230))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 740, height: 230)

        guard let image = renderer.nsImage else {
            XCTFail("Breakdown recovery panel did not render")
            return
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        var minimum = 1.0
        var maximum = 0.0
        var visibleSamples = 0
        for y in stride(from: 8, to: bitmap.pixelsHigh, by: 24) {
            for x in stride(from: 8, to: bitmap.pixelsWide, by: 24) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                minimum = min(minimum, luminance)
                maximum = max(maximum, luminance)
                if luminance > 0.05 { visibleSamples += 1 }
            }
        }
        XCTAssertGreaterThan(visibleSamples, 34)
        XCTAssertGreaterThan(maximum - minimum, 0.10)

        if let path = ProcessInfo.processInfo.environment["CAPTURE_BREAKDOWN_RECOVERY_VIEW"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }
    }

    func testBreakdownRecoveryStageFeedbackReleasesVignetteAndAddsSupportSignals() throws {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        let coordinator = ClassroomCoordinator()
        game.startGame()
        game.player.stress = 92
        game.player.maskCost = 88
        game.player.exposure = 54
        game.player.psychicEnergy = 18
        game.player.support = 18

        game.presentEvent(
            kind: .playerBreakdown,
            title: "崩溃信号",
            body: "测试场景反馈",
            choices: [EventChoice(id: "breakdown_nameSignal", title: "说出报警", detail: "先承认信号")]
        )
        game.resolveEventChoice(EventChoice(id: "breakdown_nameSignal", title: "说出报警", detail: "先承认信号"))
        coordinator.update(game: game)

        let initialHeartbeat = coordinator.breakdownHeartbeatOpacity
        let stepOneImage = coordinator.renderSnapshot(size: CGSize(width: 960, height: 600))
        let stepOneTiff = try XCTUnwrap(stepOneImage.tiffRepresentation)
        let stepOneBitmap = try XCTUnwrap(NSBitmapImageRep(data: stepOneTiff))
        let stepOneData = try XCTUnwrap(stepOneBitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(initialHeartbeat, 0.55)

        game.resolveEventChoice(EventChoice(id: "breakdown_returnToBody", title: "回到身体", detail: "稳定身体"))
        coordinator.update(game: game)
        let bodyHeartbeat = coordinator.breakdownHeartbeatOpacity
        let bodyHalo = coordinator.breakdownCupHaloOpacity
        XCTAssertLessThan(bodyHeartbeat, initialHeartbeat)
        XCTAssertGreaterThan(bodyHalo, 0.22)

        game.resolveEventChoice(EventChoice(id: "breakdown_acceptSupport", title: "接住支持", detail: "交给支持网络"))
        coordinator.update(game: game)
        let supportNote = coordinator.breakdownSupportNoteOpacity
        XCTAssertGreaterThan(supportNote, 0.7)
        let stepThreeImage = coordinator.renderSnapshot(size: CGSize(width: 960, height: 600))
        let stepThreeTiff = try XCTUnwrap(stepThreeImage.tiffRepresentation)
        let stepThreeBitmap = try XCTUnwrap(NSBitmapImageRep(data: stepThreeTiff))
        let stepThreePng = try XCTUnwrap(stepThreeBitmap.representation(using: .png, properties: [:]))
        XCTAssertNotEqual(stepOneData, stepThreePng)

        if let path = ProcessInfo.processInfo.environment["CAPTURE_BREAKDOWN_RECOVERY_STAGE_VIEW"] {
            let tiff = try XCTUnwrap(stepThreeImage.tiffRepresentation)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try FileManager.default.createDirectory(atPath: URL(fileURLWithPath: path).deletingLastPathComponent().path, withIntermediateDirectories: true)
            try png.write(to: URL(fileURLWithPath: path))
            XCTAssertGreaterThan(png.count, 20_000)
        }
    }

    func testNamedCharactersKeepAuthoredPersonalities() {
        let firstRun = GameManager()
        firstRun.startGame()
        let secondRun = GameManager()
        secondRun.startGame()

        for name in ["林澈", "周予安", "江越", "陈言", "许栀"] {
            let first = firstRun.classmates.first { $0.name == name }
            let second = secondRun.classmates.first { $0.name == name }
            XCTAssertNotNil(first)
            XCTAssertEqual(first?.profile, second?.profile)
        }
    }

    func testBackgroundCharactersRerollPersonalitiesBetweenRuns() {
        let firstRun = GameManager()
        firstRun.startGame()
        let secondRun = GameManager()
        secondRun.startGame()

        let fixedNames = Set(["林澈", "周予安", "江越", "陈言", "许栀"])
        let firstProfiles = firstRun.classmates.filter { !fixedNames.contains($0.name) }.map(\.profile)
        let secondProfiles = secondRun.classmates.filter { !fixedNames.contains($0.name) }.map(\.profile)
        XCTAssertNotEqual(firstProfiles, secondProfiles)
    }

    func testOpeningMonologueUsesFeaturedPresentation() {
        let game = GameManager()
        game.startGame()

        XCTAssertNotNil(game.featuredMonologue)
        XCTAssertEqual(game.featuredMonologue?.text, game.monologues.first?.text)

        game.dismissFeaturedMonologue()
        XCTAssertNil(game.featuredMonologue)
    }

    func testSevereHiddenStateTriggersSubjectiveMonologueWithoutNumbers() {
        let game = GameManager()
        game.startGame()
        game.dismissFeaturedMonologue()
        game.player.stress = 90

        game.maybeAddAnomalyMonologue()

        let text = game.featuredMonologue?.text ?? ""
        XCTAssertFalse(text.isEmpty)
        XCTAssertFalse(text.contains("90"))
        XCTAssertFalse(text.contains("压力值"))
        XCTAssertTrue(text.contains("身体") || text.contains("感觉") || text.contains("呼吸"))
    }

    func testDifferentPersonalitiesDescribeDifferentReactionsToSameSignal() {
        let empathetic = ClassmateProfile(cooperation: 60, orderliness: 40, rebelliousness: 20, empathy: 90, anxiety: 30, maskStrength: 60)
        let orderly = ClassmateProfile(cooperation: 60, orderliness: 90, rebelliousness: 20, empathy: 40, anxiety: 30, maskStrength: 60)
        let rebellious = ClassmateProfile(cooperation: 60, orderliness: 30, rebelliousness: 90, empathy: 40, anxiety: 30, maskStrength: 60)

        XCTAssertNotEqual(empathetic.signalReaction, orderly.signalReaction)
        XCTAssertNotEqual(orderly.signalReaction, rebellious.signalReaction)
        XCTAssertNotEqual(empathetic.signalReaction, rebellious.signalReaction)
    }

    func testLookingAloneDoesNotCollectAClue() {
        let game = GameManager()
        game.startGame()

        game.setPose(.left)

        XCTAssertEqual(game.chapterOneStep, .observeLinChe)
        XCTAssertTrue(game.chapterClues.isEmpty)
    }

    func testWrongObservationDirectionDoesNotAdvanceMainQuest() {
        let game = GameManager()
        game.startGame()
        game.setPose(.right)

        game.execute(.observe)

        XCTAssertEqual(game.chapterOneStep, .observeLinChe)
        XCTAssertTrue(game.chapterClues.isEmpty)
    }

    func testChapterOneMainQuestCompletesInAuthoredOrder() {
        let game = GameManager()
        game.startGame()

        localizeChapterOneSound(game, pose: .left)
        game.execute(.observe)
        XCTAssertEqual(game.chapterOneStep, .locateHiddenSound)
        XCTAssertEqual(game.chapterClues.map(\.id), [.linChePage])

        localizeChapterOneSound(game, pose: .right)
        game.execute(.observe)
        XCTAssertEqual(game.chapterOneStep, .regulateSelf)
        XCTAssertEqual(game.chapterClues.map(\.id), [.linChePage, .hiddenCrying])

        game.execute(.breathe)
        XCTAssertEqual(game.chapterOneStep, .approachLinChe)

        game.execute(.talk)
        chooseLinCheDialogue(game)
        XCTAssertEqual(game.chapterOneStep, .inspectNote)

        localizeChapterOneSound(game, pose: .desk)
        game.execute(.observe)
        XCTAssertEqual(game.chapterOneStep, .followLinChe)
        XCTAssertEqual(game.chapterClues.map(\.id), [.linChePage, .hiddenCrying, .unsignedNote])
        XCTAssertTrue(game.chapterOneAvailableActions.contains(.breathe))
        XCTAssertTrue(game.chapterOneAvailableActions.contains(.drink))
        XCTAssertTrue(game.chapterOneAvailableActions.contains(.window))
        XCTAssertTrue(game.chapterOneAvailableActions.contains(.leaveSeat))

        game.execute(.leaveSeat)
        XCTAssertEqual(game.chapterOneStep, .completed)
        XCTAssertEqual(game.chapterOneDecision, "跟随林澈进入走廊")
        guard case .ending = game.gameState else {
            return XCTFail("Following Lin Che should finish chapter one")
        }
    }

    func testChapterOneLinCheDialogueChoicesWriteTrustAndListenScoreOnce() throws {
        let cases: [(String, ChapterOneLinCheTrust, Int)] = [
            ("chapter1_linche_listen", .open, 2),
            ("chapter1_linche_wait", .neutral, 1),
            ("chapter1_linche_mask", .closed, 0)
        ]

        for (choiceID, expectedTrust, expectedScore) in cases {
            let game = GameManager(userDefaults: isolatedUserDefaults())
            game.startGame()
            localizeChapterOneSound(game, pose: .left)
            game.execute(.observe)
            localizeChapterOneSound(game, pose: .right)
            game.execute(.observe)
            game.execute(.breathe)

            game.execute(.talk)
            chooseLinCheDialogue(game, choiceID: choiceID)

            XCTAssertEqual(game.chapterOneStep, .inspectNote)
            XCTAssertEqual(game.chapterOneLinCheDialogueCue?.selectedChoiceID, choiceID)
            XCTAssertEqual(game.chapterOneLinCheTrust, expectedTrust)
            XCTAssertEqual(game.chapterOneLinCheListenScore, expectedScore)
            XCTAssertEqual(game.chapterOneNoteDropCue?.paperVisible, true)
            XCTAssertTrue(game.eventLog.contains { $0.title == "林澈回应" })
        }

        let fullRun = GameManager(userDefaults: isolatedUserDefaults())
        fullRun.startFullNarrativeCampaign()
        localizeChapterOneSound(fullRun, pose: .left)
        fullRun.execute(.observe)
        localizeChapterOneSound(fullRun, pose: .right)
        fullRun.execute(.observe)
        fullRun.execute(.breathe)
        fullRun.execute(.talk)
        chooseLinCheDialogue(fullRun, choiceID: "chapter1_linche_mask")
        guard case .event(let noteEvent) = fullRun.gameState else {
            return XCTFail("Expected note event after Lin Che dialogue")
        }
        fullRun.resolveEventChoice(try XCTUnwrap(noteEvent.choices.first))
        fullRun.execute(.leaveSeat)

        XCTAssertTrue(fullRun.narrativeCampaign.isActive)
        XCTAssertEqual(fullRun.narrativeCampaign.chapter, .mirror)
        XCTAssertEqual(fullRun.narrativeCampaign.linCheTrust, ChapterOneLinCheTrust.closed.campaignTrustSeed)
    }

    func testChapterOneNoteDropCueTriggersOverlayChairBellAndPickup() throws {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.startFullNarrativeCampaign()

        localizeChapterOneSound(game, pose: .left)
        game.execute(.observe)
        localizeChapterOneSound(game, pose: .right)
        game.execute(.observe)
        game.execute(.breathe)

        game.execute(.talk)
        chooseLinCheDialogue(game)

        let cue = try XCTUnwrap(game.chapterOneNoteDropCue)
        XCTAssertTrue(cue.paperVisible)
        XCTAssertTrue(cue.overlayPresented)
        XCTAssertFalse(cue.overlayDismissed)
        XCTAssertEqual(game.chapterOneStep, .inspectNote)
        XCTAssertTrue(game.audioCues.contains { $0.kind == .chair && $0.note.contains("纸边") })
        XCTAssertTrue(game.audioCues.contains { $0.kind == .bell && $0.note.contains("铃") })
        guard case .event(let event) = game.gameState else {
            return XCTFail("Full narrative note drop should open the note overlay event")
        }
        XCTAssertEqual(event.kind, .noteDrop)
        XCTAssertEqual(event.body, ChapterOneNoteDropCue.content)
        XCTAssertEqual(event.choices.map(\.id), ["chapter1_read_note"])

        game.resolveEventChoice(try XCTUnwrap(event.choices.first))

        XCTAssertEqual(game.chapterOneStep, .followLinChe)
        XCTAssertEqual(game.chapterClues.map(\.id), [.linChePage, .hiddenCrying, .unsignedNote])
        XCTAssertEqual(game.chapterOneNoteDropCue?.notePicked, true)
        XCTAssertEqual(game.chapterOneNoteDropCue?.paperVisible, false)
        XCTAssertTrue(game.message.contains("纸条") || game.featuredMonologue?.text.contains("纸条") == true)
    }

    func testChapterOneNoteDropStageShowsDeskPaper() throws {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        let coordinator = ClassroomCoordinator()
        game.startFullNarrativeCampaign()
        localizeChapterOneSound(game, pose: .left)
        game.execute(.observe)
        localizeChapterOneSound(game, pose: .right)
        game.execute(.observe)
        game.execute(.breathe)
        game.setPose(.desk)
        game.execute(.talk)
        chooseLinCheDialogue(game)

        coordinator.update(game: game)

        XCTAssertGreaterThan(coordinator.chapterOneNotePaperOpacity, 0.82)
        XCTAssertGreaterThan(coordinator.chapterOneNotePaperEmission, 0.4)
    }

    func testChapterOneNoteDropStageSnapshotShowsUnsignedNotePaper() throws {
        guard let path = ProcessInfo.processInfo.environment["CAPTURE_CHAPTER_ONE_NOTE_DROP_STAGE_VIEW"] else {
            throw XCTSkip("Set CAPTURE_CHAPTER_ONE_NOTE_DROP_STAGE_VIEW to render the chapter-one note-drop evidence snapshot.")
        }
        let game = GameManager(userDefaults: isolatedUserDefaults())
        let coordinator = ClassroomCoordinator()
        game.startFullNarrativeCampaign()
        localizeChapterOneSound(game, pose: .left)
        game.execute(.observe)
        localizeChapterOneSound(game, pose: .right)
        game.execute(.observe)
        game.execute(.breathe)
        game.setPose(.desk)
        game.execute(.talk)
        chooseLinCheDialogue(game)
        coordinator.update(game: game)

        let image = coordinator.renderSnapshot(size: CGSize(width: 960, height: 600))
        let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        var visibleSamples = 0
        var paperSamples = 0
        var blueLineSamples = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                if luminance > 0.05 { visibleSamples += 1 }
                if color.redComponent > 0.72,
                   color.greenComponent > 0.72,
                   color.blueComponent > 0.58,
                   abs(color.redComponent - color.greenComponent) < 0.16 {
                    paperSamples += 1
                }
                if color.blueComponent > 0.42,
                   color.redComponent < color.blueComponent - 0.12,
                   color.greenComponent < color.blueComponent + 0.08 {
                    blueLineSamples += 1
                }
            }
        }

        if let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }

        XCTAssertGreaterThan(visibleSamples, 5_000)
        XCTAssertGreaterThan(paperSamples, 700)
        XCTAssertGreaterThan(blueLineSamples, 60)
    }

    func testLinChePerformanceCueMovesFromStillPageToExitAfterNotePickup() throws {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.startFullNarrativeCampaign()

        XCTAssertEqual(game.linChePerformanceCue.phase, .idleStillPage)
        XCTAssertGreaterThan(game.linChePerformanceCue.pageStillness, 0.9)

        localizeChapterOneSound(game, pose: .left)
        game.execute(.observe)
        localizeChapterOneSound(game, pose: .right)
        game.execute(.observe)
        game.execute(.breathe)

        XCTAssertEqual(game.chapterOneStep, .approachLinChe)
        XCTAssertEqual(game.linChePerformanceCue.phase, .doorGlance)
        XCTAssertGreaterThan(game.linChePerformanceCue.doorAttention, 0.8)
        XCTAssertGreaterThan(game.linChePerformanceCue.packingProgress, 0.25)

        game.execute(.talk)
        chooseLinCheDialogue(game)
        XCTAssertEqual(game.chapterOneStep, .inspectNote)
        XCTAssertEqual(game.linChePerformanceCue.phase, .packingUp)
        XCTAssertGreaterThan(game.linChePerformanceCue.packingProgress, 0.7)

        guard case .event(let event) = game.gameState else {
            return XCTFail("The note drop should be awaiting confirmation before Lin Che fully exits")
        }
        game.resolveEventChoice(try XCTUnwrap(event.choices.first))

        XCTAssertEqual(game.chapterOneStep, .followLinChe)
        XCTAssertEqual(game.linChePerformanceCue.phase, .exiting)
        XCTAssertGreaterThan(game.linChePerformanceCue.exitProgress, 0.7)
        XCTAssertLessThan(game.linChePerformanceCue.pageStillness, 0.1)
    }

    func testLinChePerformanceStageShowsGlancePackingAndExitPath() throws {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        let coordinator = ClassroomCoordinator()
        game.startFullNarrativeCampaign()
        coordinator.update(game: game)
        let seatedPosition = try XCTUnwrap(coordinator.linChePerformancePosition)
        let seatedPaperOpacity = try XCTUnwrap(coordinator.linChePerformancePaperOpacity)

        localizeChapterOneSound(game, pose: .left)
        game.execute(.observe)
        localizeChapterOneSound(game, pose: .right)
        game.execute(.observe)
        game.execute(.breathe)
        coordinator.update(game: game)

        XCTAssertLessThan(try XCTUnwrap(coordinator.linChePerformanceHeadYaw), -0.45)

        game.execute(.talk)
        chooseLinCheDialogue(game)
        guard case .event(let event) = game.gameState else {
            return XCTFail("The note drop should be awaiting confirmation before Lin Che exits")
        }
        game.resolveEventChoice(try XCTUnwrap(event.choices.first))
        coordinator.update(game: game)

        let exitingPosition = try XCTUnwrap(coordinator.linChePerformancePosition)
        XCTAssertLessThan(exitingPosition.z, seatedPosition.z - 1.2)
        XCTAssertGreaterThan(try XCTUnwrap(coordinator.linChePerformanceBagOpacity), 0.8)
        XCTAssertGreaterThan(try XCTUnwrap(coordinator.linChePerformanceExitTraceOpacity), 0.45)
        XCTAssertLessThan(try XCTUnwrap(coordinator.linChePerformancePaperOpacity), seatedPaperOpacity)
    }

    func testLinChePerformanceSnapshotShowsExitPath() throws {
        guard let path = ProcessInfo.processInfo.environment["CAPTURE_LINCHE_EXIT_STAGE_VIEW"] else {
            throw XCTSkip("Set CAPTURE_LINCHE_EXIT_STAGE_VIEW to render the Lin Che exit evidence snapshot.")
        }
        let game = GameManager(userDefaults: isolatedUserDefaults())
        let coordinator = ClassroomCoordinator()
        game.startFullNarrativeCampaign()
        localizeChapterOneSound(game, pose: .left)
        game.execute(.observe)
        localizeChapterOneSound(game, pose: .right)
        game.execute(.observe)
        game.execute(.breathe)
        game.execute(.talk)
        chooseLinCheDialogue(game)
        guard case .event(let event) = game.gameState else {
            return XCTFail("The note drop should be awaiting confirmation before Lin Che exits")
        }
        game.resolveEventChoice(try XCTUnwrap(event.choices.first))
        coordinator.update(game: game)

        let image = coordinator.renderSnapshot(size: CGSize(width: 960, height: 600))
        let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        var orangePathSamples = 0
        var blueGlanceSamples = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.redComponent > 0.72,
                   color.greenComponent > 0.24,
                   color.greenComponent < 0.72,
                   color.blueComponent < 0.36 {
                    orangePathSamples += 1
                }
                if color.blueComponent > 0.58,
                   color.greenComponent > 0.36,
                   color.redComponent < 0.5 {
                    blueGlanceSamples += 1
                }
            }
        }

        if let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }

        XCTAssertGreaterThan(orangePathSamples, 160)
        XCTAssertGreaterThan(blueGlanceSamples, 80)
    }

    func testChapterClueStackRendersFiveVisibleStickyNotes() throws {
        let clues = ChapterClueID.allCases.enumerated().map { index, id in
            ChapterClue(id: id, turn: index + 1, title: id.title, detail: id.detail)
        } + [
            ChapterClue(id: .unsignedNote, turn: 6, title: "额外便签", detail: "超过五张后不应扩展可见层。")
        ]

        XCTAssertEqual(ChapterClueStackView.maxVisibleClues, 5)
        XCTAssertEqual(Array(clues.prefix(ChapterClueStackView.maxVisibleClues)).count, 5)

        let renderer = ImageRenderer(content: ZStack {
            Color.black
            ChapterClueStackView(clues: clues)
                .padding(18)
        }
        .frame(width: 340, height: 220))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 340, height: 220)

        guard let image = renderer.nsImage else {
            XCTFail("ChapterClueStackView did not render")
            return
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        var minimum = 1.0
        var maximum = 0.0
        var visibleSamples = 0
        var stickySamples = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                minimum = min(minimum, luminance)
                maximum = max(maximum, luminance)
                if luminance > 0.05 { visibleSamples += 1 }
                let strongest = max(color.redComponent, color.greenComponent, color.blueComponent)
                let weakest = min(color.redComponent, color.greenComponent, color.blueComponent)
                if luminance > 0.34, strongest - weakest > 0.08 {
                    stickySamples += 1
                }
            }
        }

        if let path = ProcessInfo.processInfo.environment["CAPTURE_CHAPTER_CLUE_STACK_VIEW"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }

        XCTAssertGreaterThan(visibleSamples, 8_000)
        XCTAssertGreaterThan(stickySamples, 4_000)
        XCTAssertGreaterThan(maximum - minimum, 0.22)
    }

    func testFullCampaignPlaysChapterOneBeforeEnteringMirrorChapter() {
        let game = GameManager()
        game.startFullNarrativeCampaign()

        XCTAssertTrue(game.isFullNarrativeRun)
        XCTAssertFalse(game.narrativeCampaign.isActive)
        XCTAssertEqual(game.chapterOneStep, .observeLinChe)

        localizeChapterOneSound(game, pose: .left)
        game.execute(.observe)
        localizeChapterOneSound(game, pose: .right)
        game.execute(.observe)
        game.execute(.breathe)
        game.execute(.talk)
        chooseLinCheDialogue(game)
        if case .event(let event) = game.gameState {
            guard let choice = event.choices.first else {
                return XCTFail("Expected note pickup choice")
            }
            game.resolveEventChoice(choice)
        }
        game.execute(.leaveSeat)

        XCTAssertFalse(game.isFullNarrativeRun)
        XCTAssertTrue(game.narrativeCampaign.isActive)
        XCTAssertEqual(game.narrativeCampaign.chapter, .mirror)
        XCTAssertEqual(game.narrativeCampaign.currentMoment.id, "2.enter")
        XCTAssertEqual(game.gameState, .playing)
    }

    func testFullNarrativeChapterOneRestoresFromSavedClueCheckpoint() {
        let defaults = isolatedUserDefaults()
        let firstRun = GameManager(userDefaults: defaults)
        firstRun.startFullNarrativeCampaign()

        localizeChapterOneSound(firstRun, pose: .left)
        firstRun.execute(.observe)

        let restored = GameManager(userDefaults: defaults)

        XCTAssertTrue(restored.isFullNarrativeRun)
        XCTAssertFalse(restored.narrativeCampaign.isActive)
        XCTAssertEqual(restored.gameState, .playing)
        XCTAssertEqual(restored.chapterOneStep, .locateHiddenSound)
        XCTAssertEqual(restored.chapterClues.map(\.id), [.linChePage])
        XCTAssertEqual(restored.cameraPose, .left)
        XCTAssertEqual(restored.scenePresentation.chapter, .classroom)
        XCTAssertEqual(restored.scenePresentation.phase, .idle)
        XCTAssertTrue(restored.developerPlaytestLog.contains { $0.contains("chapter.1.") })

        localizeChapterOneSound(restored, pose: .right)
        restored.execute(.observe)
        restored.execute(.breathe)
        restored.execute(.talk)
        chooseLinCheDialogue(restored)
        if case .event(let event) = restored.gameState {
            guard let choice = event.choices.first else {
                return XCTFail("Expected note pickup choice")
            }
            restored.resolveEventChoice(choice)
        }
        restored.execute(.leaveSeat)

        XCTAssertFalse(restored.isFullNarrativeRun)
        XCTAssertTrue(restored.narrativeCampaign.isActive)
        XCTAssertEqual(restored.narrativeCampaign.chapter, .mirror)
        XCTAssertEqual(restored.narrativeCampaign.currentMoment.id, "2.enter")
    }

    func testPauseNarrativeToMenuPreservesCheckpointAndContinues() {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.startFullNarrativeCampaign()
        localizeChapterOneSound(game, pose: .left)
        game.execute(.observe)

        game.pauseNarrativeToMenu()

        XCTAssertEqual(game.gameState, .menu)
        XCTAssertTrue(game.hasContinuableNarrativeSave)
        XCTAssertTrue(game.narrativeSaveTitle.contains("第一章"))
        XCTAssertTrue(game.narrativeSaveDetail.contains("已记录 1 条线索"))

        game.continueNarrativeSaveFromMenu()

        XCTAssertEqual(game.gameState, .playing)
        XCTAssertTrue(game.isFullNarrativeRun)
        XCTAssertEqual(game.chapterOneStep, .locateHiddenSound)
        XCTAssertEqual(game.chapterClues.map(\.id), [.linChePage])
    }

    func testNarrativePauseMenuFreezesChapterOneInputAndResumesExactCheckpoint() {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.startFullNarrativeCampaign()
        localizeChapterOneSound(game, pose: .left)
        game.execute(.observe)

        game.openNarrativePauseMenu()
        XCTAssertTrue(game.narrativePaused)
        XCTAssertTrue(game.narrativePauseReasons.contains(.manual))

        game.setPose(.right)
        game.execute(.observe)
        XCTAssertEqual(game.chapterOneStep, .locateHiddenSound)
        XCTAssertEqual(game.cameraPose, .left)
        XCTAssertEqual(game.chapterClues.map(\.id), [.linChePage])

        game.resumeNarrativeFromPause()
        XCTAssertFalse(game.narrativePaused)
        localizeChapterOneSound(game, pose: .right)
        game.execute(.observe)
        XCTAssertEqual(game.chapterOneStep, .regulateSelf)
        XCTAssertEqual(game.chapterClues.map(\.id), [.linChePage, .hiddenCrying])
    }

    func testNarrativeAppInactiveFreezesFallbackClockUntilFocusReturns() {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.developerJump(to: .noteTrace, momentIndex: 2)

        game.setApplicationActive(false)
        for _ in 0..<920 {
            game.tickNarrativeExploration(deltaTime: 0.1)
        }

        XCTAssertEqual(game.narrativeCampaign.currentMoment.id, "3.companion")
        XCTAssertTrue(game.narrativeCampaign.companionID.isEmpty)
        XCTAssertTrue(game.narrativePauseReasons.contains(.appInactive))

        game.setApplicationActive(true)
        for _ in 0..<920 {
            game.tickNarrativeExploration(deltaTime: 0.1)
        }

        XCTAssertEqual(game.narrativeCampaign.companionID, "周予安")
        XCTAssertEqual(game.narrativeCampaign.currentMoment.id, "3.door")
    }

    func testNarrativeSavePersistsAccessibilityPreferencesInsideCheckpoint() throws {
        let defaults = isolatedUserDefaults()
        let game = GameManager(userDefaults: defaults)
        game.startFullNarrativeCampaign()

        game.updateAccessibilityPreferences {
            $0.directionalSubtitles = false
            $0.dialogueVolume = 0.25
            $0.ambienceVolume = 0.4
            $0.cueVolume = 0.55
            $0.reduceMotion = true
            $0.keyboardAlternativeInput = false
        }

        let data = try XCTUnwrap(defaults.data(forKey: NarrativeSaveStoreKeys.current))
        let save = try JSONDecoder().decode(NarrativeSave.self, from: data)
        XCTAssertFalse(save.accessibilityPreferences.directionalSubtitles)
        XCTAssertEqual(save.accessibilityPreferences.dialogueVolume, 0.25, accuracy: 0.001)
        XCTAssertTrue(save.accessibilityPreferences.reduceMotion)
        XCTAssertFalse(save.accessibilityPreferences.keyboardAlternativeInput)

        let restored = GameManager(userDefaults: defaults)
        XCTAssertEqual(restored.accessibilityPreferences, save.accessibilityPreferences)
        XCTAssertEqual(restored.audio.targetSceneMix.sceneID, "classroom")
    }

    func testNarrativePauseMenuRendersVisibleResumeAndSettingsActions() throws {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.startFullNarrativeCampaign()
        localizeChapterOneSound(game, pose: .left)
        game.execute(.observe)
        game.openNarrativePauseMenu()

        let renderer = ImageRenderer(content: ZStack {
            Color.black
            ContentView()
                .environmentObject(game)
                .frame(width: 1100, height: 720)
        }
        .frame(width: 1100, height: 720))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 1100, height: 720)

        guard let image = renderer.nsImage else {
            XCTFail("ContentView pause menu did not render")
            return
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        var minimum = 1.0
        var maximum = 0.0
        var visibleSamples = 0
        for y in stride(from: 8, to: bitmap.pixelsHigh, by: 24) {
            for x in stride(from: 8, to: bitmap.pixelsWide, by: 24) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                minimum = min(minimum, luminance)
                maximum = max(maximum, luminance)
                if luminance > 0.05 { visibleSamples += 1 }
            }
        }
        XCTAssertGreaterThan(visibleSamples, 180)
        XCTAssertGreaterThan(maximum - minimum, 0.14)

        if let path = ProcessInfo.processInfo.environment["CAPTURE_NARRATIVE_PAUSE_VIEW"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }
    }

    func testNarrativeMinimalHUDControlsRenderPauseAndCaptionEntrypoints() throws {
        let renderer = ImageRenderer(content: ZStack {
            Color.black
            NarrativeMinimalHUDControls(
                captionsEnabled: true,
                onToggleCaptions: {},
                onPause: {}
            )
            .padding(20)
        }
        .frame(width: 220, height: 120))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 220, height: 120)

        guard let image = renderer.nsImage else {
            XCTFail("NarrativeMinimalHUDControls did not render")
            return
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        var minimum = 1.0
        var maximum = 0.0
        var visibleSamples = 0
        var blueSamples = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                minimum = min(minimum, luminance)
                maximum = max(maximum, luminance)
                if luminance > 0.04 { visibleSamples += 1 }
                if color.blueComponent > color.redComponent + 0.08, color.blueComponent > color.greenComponent + 0.02 {
                    blueSamples += 1
                }
            }
        }

        if let path = ProcessInfo.processInfo.environment["CAPTURE_MINIMAL_NARRATIVE_HUD"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }

        XCTAssertGreaterThan(visibleSamples, 900)
        XCTAssertGreaterThan(blueSamples, 35)
        XCTAssertGreaterThan(maximum - minimum, 0.10)
    }

    func testMainQuestHUDRendersAcceptedGoalHierarchyAndUrgency() throws {
        XCTAssertEqual(MainQuestHUD.width, 220)
        XCTAssertEqual(MainQuestHUD.questFontSize, 11)
        XCTAssertEqual(MainQuestHUD.currentGoalFontSize, 14)
        XCTAssertEqual(MainQuestHUD.animationDuration(reduceMotion: false), 0.3, accuracy: 0.001)
        XCTAssertEqual(MainQuestHUD.animationDuration(reduceMotion: true), 0.2, accuracy: 0.001)

        let renderer = ImageRenderer(content: ZStack {
            Color.black
            HStack(spacing: 18) {
                MainQuestHUD(
                    item: MainQuestHUDItem(
                        quest: "第一章  静音的教室",
                        currentGoal: "看看林澈今晚在做什么",
                        hint: "看向左侧，确认那阵停下来的翻书声。",
                        isUrgent: false
                    ),
                    reduceMotion: false
                )
                MainQuestHUD(
                    item: MainQuestHUDItem(
                        quest: "第一章  静音的教室",
                        currentGoal: "别让林澈一个人离开",
                        hint: "林澈已经走向门口。现在起身跟上。",
                        isUrgent: true
                    ),
                    reduceMotion: true
                )
            }
            .padding(18)
        }
        .frame(width: 520, height: 190))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 520, height: 190)

        guard let image = renderer.nsImage else {
            XCTFail("MainQuestHUD did not render")
            return
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        var minimum = 1.0
        var maximum = 0.0
        var visibleSamples = 0
        var cyanSamples = 0
        var orangeSamples = 0
        var textLikeSamples = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                minimum = min(minimum, luminance)
                maximum = max(maximum, luminance)
                if luminance > 0.04 { visibleSamples += 1 }
                if color.blueComponent > color.redComponent + 0.08, color.greenComponent > color.redComponent + 0.04 {
                    cyanSamples += 1
                }
                if color.redComponent > 0.42, color.greenComponent > 0.18, color.blueComponent < 0.30, color.redComponent > color.blueComponent + 0.16 {
                    orangeSamples += 1
                }
                if luminance > 0.44,
                   abs(color.redComponent - color.greenComponent) < 0.08,
                   abs(color.greenComponent - color.blueComponent) < 0.08 {
                    textLikeSamples += 1
                }
            }
        }

        if let path = ProcessInfo.processInfo.environment["CAPTURE_MAIN_QUEST_HUD"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }

        XCTAssertGreaterThan(visibleSamples, 6_000)
        XCTAssertGreaterThan(cyanSamples, 40)
        XCTAssertGreaterThan(orangeSamples, 120)
        XCTAssertGreaterThan(textLikeSamples, 220)
        XCTAssertGreaterThan(maximum - minimum, 0.14)
    }

    func testContentViewRendersPlayableSupportWeatherStrip() throws {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.startFullNarrativeCampaign()
        game.narrativeCampaign.isActive = false
        game.featuredMonologue = nil
        game.player.support = 58
        game.classmates = [
            Classmate(
                id: 1,
                name: "林澈",
                seat: (row: 2, column: 0),
                profile: ClassmateProfile(
                    cooperation: 78,
                    orderliness: 44,
                    rebelliousness: 26,
                    empathy: 86,
                    anxiety: 34,
                    maskStrength: 48
                ),
                support: 74,
                stress: 38,
                state: .studying,
                relationship: 72,
                hasSharedTruth: true,
                suspicionOfPlayer: 8
            ),
            Classmate(
                id: 2,
                name: "周予安",
                seat: (row: 2, column: 2),
                profile: ClassmateProfile(
                    cooperation: 42,
                    orderliness: 56,
                    rebelliousness: 18,
                    empathy: 52,
                    anxiety: 64,
                    maskStrength: 62
                ),
                support: 44,
                stress: 52,
                state: .anxious,
                relationship: 47,
                hasSharedTruth: false,
                suspicionOfPlayer: 14
            ),
            Classmate(
                id: 3,
                name: "江越",
                seat: (row: 1, column: 1),
                profile: ClassmateProfile(
                    cooperation: 35,
                    orderliness: 64,
                    rebelliousness: 22,
                    empathy: 48,
                    anxiety: 46,
                    maskStrength: 57
                ),
                support: 28,
                stress: 60,
                state: .studying,
                relationship: 21,
                hasSharedTruth: false,
                suspicionOfPlayer: 36
            )
        ]

        let renderer = ImageRenderer(content: ZStack {
            Color.black
            ContentView()
                .environmentObject(game)
                .frame(width: 1080, height: 720)
        }
        .frame(width: 1080, height: 720))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 1080, height: 720)

        guard let image = renderer.nsImage else {
            XCTFail("ContentView did not render playable support weather strip")
            return
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        var visibleSamples = 0
        var cyanOrMintSamples = 0
        var purpleOrOrangeSamples = 0
        for y in stride(from: 12, to: min(bitmap.pixelsHigh, 340), by: 20) {
            for x in stride(from: max(12, bitmap.pixelsWide - 260), to: bitmap.pixelsWide - 12, by: 18) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                if luminance > 0.03 { visibleSamples += 1 }
                if color.blueComponent > color.redComponent + 0.06,
                   color.greenComponent > color.redComponent + 0.04 {
                    cyanOrMintSamples += 1
                }
                if (color.redComponent > color.blueComponent + 0.06 && color.redComponent > color.greenComponent + 0.04)
                    || (color.redComponent > 0.35 && color.blueComponent > color.redComponent + 0.02) {
                    purpleOrOrangeSamples += 1
                }
            }
        }

        XCTAssertGreaterThan(visibleSamples, 100)
        XCTAssertGreaterThan(cyanOrMintSamples, 1)
        XCTAssertGreaterThan(purpleOrOrangeSamples, 1)

        if let path = ProcessInfo.processInfo.environment["CAPTURE_CONTENTVIEW_SUPPORT_WEATHER_STRIP"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }
    }

    func testFeaturedMonologueRendersBottomQuarterWithoutCoveringQuestHUD() throws {
        XCTAssertEqual(FeaturedMonologueView.minimumPanelHeight, 190)

        let monologue = FeaturedMonologue(
            text: "我也在这间教室里。先让自己缓一下，才听得清别人。",
            intensity: 0.72
        )
        let renderer = ImageRenderer(content: ZStack {
            Color(red: 0.05, green: 0.09, blue: 0.14)
            MainQuestHUD(
                item: MainQuestHUDItem(
                    quest: "第一章  静音的教室",
                    currentGoal: "先让自己缓一下",
                    hint: "不用读数值。喝口水，或者先把呼吸放慢。",
                    isUrgent: false
                ),
                reduceMotion: false
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.leading, 16)

            FeaturedMonologueView(monologue: monologue, onDismiss: {})
        }
        .frame(width: 900, height: 520))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 900, height: 520)

        guard let image = renderer.nsImage else {
            XCTFail("FeaturedMonologueView did not render")
            return
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        var questRegionVisibleSamples = 0
        var bottomPanelSamples = 0
        var topBackgroundSamples = 0
        var textSamples = 0
        var cyanSamples = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                if x < 260, y > 145, y < 330, luminance > 0.04 {
                    questRegionVisibleSamples += 1
                }
                if y > bitmap.pixelsHigh - 190, luminance > 0.015, luminance < 0.22 {
                    bottomPanelSamples += 1
                }
                if y < 160, color.blueComponent > color.redComponent + 0.05, color.blueComponent > color.greenComponent + 0.02 {
                    topBackgroundSamples += 1
                }
                if luminance > 0.44,
                   abs(color.redComponent - color.greenComponent) < 0.08,
                   abs(color.greenComponent - color.blueComponent) < 0.08 {
                    textSamples += 1
                }
                if color.blueComponent > color.redComponent + 0.08, color.greenComponent > color.redComponent + 0.04 {
                    cyanSamples += 1
                }
            }
        }

        if let path = ProcessInfo.processInfo.environment["CAPTURE_FEATURED_MONOLOGUE_VIEW"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }

        XCTAssertGreaterThan(questRegionVisibleSamples, 1_500)
        XCTAssertGreaterThan(bottomPanelSamples, 80_000)
        XCTAssertGreaterThan(topBackgroundSamples, 40_000)
        XCTAssertGreaterThan(textSamples, 250)
        XCTAssertGreaterThan(cyanSamples, 30)
    }

    func testKeyboardAlternativeInputFocusesAndApproachesSpatialHotspots() {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.developerJump(to: .mirror)
        game.updateAccessibilityPreferences { $0.keyboardAlternativeInput = true }

        XCTAssertEqual(game.focusedNarrativeKeyboardTarget?.id, "mirror.threshold")
        XCTAssertTrue(game.focusedNarrativeKeyboardTarget?.requiresMovement == true)
        XCTAssertTrue(game.performNarrativeKeyboardCommand(.nextTarget))
        XCTAssertEqual(game.focusedNarrativeKeyboardTarget?.id, "mirror.linche")
        XCTAssertTrue(game.performNarrativeKeyboardCommand(.previousTarget))
        XCTAssertEqual(game.focusedNarrativeKeyboardTarget?.id, "mirror.threshold")

        var previousDistance = hypot(
            game.narrativeCampaign.exploration.positionX,
            game.narrativeCampaign.exploration.positionZ + 2.1
        )
        for _ in 0..<80 where game.narrativeCampaign.explorationReady == false {
            XCTAssertTrue(game.performNarrativeKeyboardCommand(.confirm))
            let distance = hypot(
                game.narrativeCampaign.exploration.positionX,
                game.narrativeCampaign.exploration.positionZ + 2.1
            )
            XCTAssertLessThanOrEqual(distance, previousDistance + 0.001)
            previousDistance = distance
        }

        XCTAssertTrue(game.narrativeCampaign.explorationReady)
        XCTAssertEqual(game.narrativeCampaign.exploration.lastInteractedHotspot, "mirror.threshold")
        XCTAssertTrue(game.developerPlaytestLog.contains("KEYBOARD_HOTSPOT mirror.threshold"))
    }

    func testKeyboardAlternativeInputCanCompleteFullNarrativeRoute() {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.updateAccessibilityPreferences { $0.keyboardAlternativeInput = true }
        game.startFullNarrativeCampaign()

        var trace: [String] = []
        for _ in 0..<520 {
            guard let target = game.focusedNarrativeKeyboardTarget else {
                trace.append("NO_TARGET \(game.developerStateSummary)")
                break
            }
            trace.append("\(target.id) :: \(game.developerStateSummary)")
            XCTAssertTrue(game.performNarrativeKeyboardCommand(.confirm), trace.suffix(12).joined(separator: " | "))
            if game.narrativeCampaign.isComplete { break }
        }

        XCTAssertTrue(game.narrativeCampaign.isComplete, trace.suffix(20).joined(separator: " | "))
        XCTAssertEqual(game.chapterOneStep, .completed)
        XCTAssertEqual(game.narrativeCampaign.chapter, .epilogue)
        XCTAssertFalse(game.narrativeCampaign.companionID.isEmpty)
        XCTAssertTrue(game.narrativeCampaign.privacyProtected)
        XCTAssertTrue(game.narrativeCampaign.sharedSelf)
        XCTAssertTrue(trace.contains { $0.contains("risk.education.dismiss") })
        XCTAssertTrue(trace.contains { $0.contains("minigame.melody") })
    }

    func testKeyboardAlternativeTargetChipRendersInNarrativeView() throws {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.updateAccessibilityPreferences { $0.keyboardAlternativeInput = true }
        game.developerJump(to: .mirror)

        let renderer = ImageRenderer(content: ZStack {
            Color.black
            NarrativeCampaignView(game: game)
                .frame(width: 1100, height: 720)
        }
        .frame(width: 1100, height: 720))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 1100, height: 720)

        guard let image = renderer.nsImage else {
            XCTFail("Narrative keyboard target view did not render")
            return
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        var minimum = 1.0
        var maximum = 0.0
        var visibleSamples = 0
        var mintSamples = 0
        for y in stride(from: 8, to: bitmap.pixelsHigh, by: 20) {
            for x in stride(from: 8, to: bitmap.pixelsWide, by: 20) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                minimum = min(minimum, luminance)
                maximum = max(maximum, luminance)
                if luminance > 0.04 { visibleSamples += 1 }
                if color.greenComponent > 0.35, color.greenComponent > color.redComponent + 0.08 {
                    mintSamples += 1
                }
            }
        }

        if let path = ProcessInfo.processInfo.environment["CAPTURE_KEYBOARD_TARGET_VIEW"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }

        XCTAssertGreaterThan(visibleSamples, 40)
        XCTAssertGreaterThan(maximum - minimum, 0.08)
        XCTAssertGreaterThan(mintSamples, 1)
    }

    func testMenuRendersVisibleContinuableSaveCard() throws {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.startFullNarrativeCampaign()
        localizeChapterOneSound(game, pose: .left)
        game.execute(.observe)
        game.pauseNarrativeToMenu()

        let renderer = ImageRenderer(content: ZStack {
            Color.black
            ContentView()
                .environmentObject(game)
                .frame(width: 1100, height: 720)
        }
        .frame(width: 1100, height: 720))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 1100, height: 720)

        guard let image = renderer.nsImage else {
            XCTFail("ContentView menu did not render")
            return
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        var minimum = 1.0
        var maximum = 0.0
        var visibleSamples = 0
        for y in stride(from: 8, to: bitmap.pixelsHigh, by: 24) {
            for x in stride(from: 8, to: bitmap.pixelsWide, by: 24) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                minimum = min(minimum, luminance)
                maximum = max(maximum, luminance)
                if luminance > 0.05 { visibleSamples += 1 }
            }
        }
        XCTAssertGreaterThan(visibleSamples, 180)
        XCTAssertGreaterThan(maximum - minimum, 0.14)

        if let path = ProcessInfo.processInfo.environment["CAPTURE_SAVE_MENU_VIEW"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }
    }

    func testDirectionalSubtitleStripRendersOnlyPublishedSubtitleEvents() throws {
        let events = [
            DirectionalSubtitleEvent(
                turn: 1,
                kind: .paper,
                direction: "左侧近处",
                intensity: 0.76,
                note: "纸张声从左侧靠近，提示玩家先观察。"
            ),
            DirectionalSubtitleEvent(
                turn: 1,
                kind: .footstep,
                direction: "右前方",
                intensity: 0.62,
                note: "脚步在右前方停下。"
            )
        ]

        let renderer = ImageRenderer(content: ZStack {
            Color.black
            DirectionalSubtitleStripView(events: events, captionsEnabled: true)
                .padding(14)
                .frame(width: 260, alignment: .leading)
                .background(.black.opacity(0.46), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.14), lineWidth: 1))
                .padding(24)
        }
        .frame(width: 360, height: 180))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 360, height: 180)

        guard let image = renderer.nsImage else {
            XCTFail("Directional subtitle strip did not render")
            return
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        var minimum = 1.0
        var maximum = 0.0
        var visibleSamples = 0
        var cyanSamples = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                minimum = min(minimum, luminance)
                maximum = max(maximum, luminance)
                if luminance > 0.04 { visibleSamples += 1 }
                if color.blueComponent > color.redComponent + 0.08, color.greenComponent > color.redComponent + 0.04 {
                    cyanSamples += 1
                }
            }
        }

        if let path = ProcessInfo.processInfo.environment["CAPTURE_DIRECTIONAL_SUBTITLE_VIEW"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }

        XCTAssertEqual(events.first?.kind, .paper)
        XCTAssertGreaterThan(visibleSamples, 2_000)
        XCTAssertGreaterThan(cyanSamples, 120)
        XCTAssertGreaterThan(maximum - minimum, 0.12)
    }

    func testSensorySoundscapeDerivesRiskSupportAndBodyPressure() {
        let cues = [
            AudioCue(turn: 3, kind: .footstep, direction: "右侧极近", intensity: 0.9, note: "脚步声停下。"),
            AudioCue(turn: 3, kind: .wrapper, direction: "桌面偏右", intensity: 0.72, note: "包装纸声很脆。"),
            AudioCue(turn: 3, kind: .heartbeat, direction: "颅内", intensity: 0.68, note: "心跳变大。"),
            AudioCue(turn: 3, kind: .paper, direction: "左侧近处", intensity: 0.48, note: "纸条滑近。")
        ]

        let soundscape = SensorySoundscape.derive(
            from: cues,
            teacherNear: true,
            allowsWhispering: false
        )

        XCTAssertEqual(soundscape.cueCount, 4)
        XCTAssertEqual(soundscape.dominantKind, .footstep)
        XCTAssertEqual(soundscape.dominantDirection, "右侧极近")
        XCTAssertGreaterThan(soundscape.riskPressure, 0.72)
        XCTAssertGreaterThan(soundscape.bodyAlarm, 0.22)
        XCTAssertGreaterThan(soundscape.supportSignal, 0.09)
        XCTAssertGreaterThan(soundscape.riskPressure, soundscape.supportSignal)
        XCTAssertEqual(soundscape.title, "风险声源压近")
        XCTAssertTrue(soundscape.recommendation.contains("降低暴露"))
    }

    func testAudioCueSpatialReadoutExtractsBearingAndDistanceBand() {
        let rightFront = AudioCue(turn: 2, kind: .footstep, direction: "右前方", intensity: 0.66, note: "脚步在右前方停下。")
        XCTAssertEqual(rightFront.bearingText, "右前方")
        XCTAssertEqual(rightFront.distanceBand, "中距")
        XCTAssertEqual(rightFront.spatialReadout, "右前方 · 中距")
        XCTAssertEqual(rightFront.radarAngleRadians, -.pi / 4, accuracy: 0.001)

        let leftRear = AudioCue(turn: 2, kind: .knock, direction: "左后方远处", intensity: 0.38, note: "后门附近有轻响。")
        XCTAssertEqual(leftRear.bearingText, "左后方")
        XCTAssertEqual(leftRear.distanceBand, "远处")
        XCTAssertEqual(leftRear.radarAngleRadians, .pi * 3 / 4, accuracy: 0.001)

        let companion = AudioCue(turn: 2, kind: .whisper, direction: "右侧同伴", intensity: 0.5, note: "许栀压低声音提醒。")
        XCTAssertEqual(companion.bearingText, "右侧")
        XCTAssertEqual(companion.distanceBand, "近侧")
        XCTAssertEqual(companion.radarAngleRadians, 0, accuracy: 0.001)

        let body = AudioCue(turn: 2, kind: .heartbeat, direction: "颅内", intensity: 0.62, note: "心跳变大。")
        XCTAssertEqual(body.spatialReadout, "内在 · 身体内")
        XCTAssertEqual(body.radarAngleRadians, -.pi / 2, accuracy: 0.001)
    }

    func testAudioCueReadoutViewRendersSpatialReadout() throws {
        let cue = AudioCue(
            turn: 7,
            kind: .whisper,
            direction: "右侧同伴",
            intensity: 0.58,
            note: "许栀压低声音：门轴声在右前方，还差 2.3m。"
        )
        XCTAssertEqual(cue.spatialReadout, "右侧 · 近侧")

        let renderer = ImageRenderer(content: ZStack {
            Color.black
            AudioCueReadoutView(cue: cue, compact: false)
                .frame(width: 360)
                .padding(22)
        }
        .frame(width: 430, height: 170))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 430, height: 170)

        guard let image = renderer.nsImage else {
            XCTFail("AudioCueReadoutView did not render")
            return
        }
        let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        var visibleSamples = 0
        var cyanSamples = 0
        var maximum = 0.0
        var minimum = 1.0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                minimum = min(minimum, luminance)
                maximum = max(maximum, luminance)
                if luminance > 0.04 { visibleSamples += 1 }
                if color.blueComponent > color.redComponent + 0.08, color.greenComponent > color.redComponent + 0.04 {
                    cyanSamples += 1
                }
            }
        }

        if let path = ProcessInfo.processInfo.environment["CAPTURE_AUDIO_CUE_READOUT_VIEW"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }

        XCTAssertGreaterThan(visibleSamples, 1_600)
        XCTAssertGreaterThan(cyanSamples, 70)
        XCTAssertGreaterThan(maximum - minimum, 0.12)
    }

    func testSoundRadarViewRendersEightDirectionCues() throws {
        let cues = [
            AudioCue(turn: 8, kind: .footstep, direction: "右前方", intensity: 0.82, note: "脚步从右前方靠近。"),
            AudioCue(turn: 8, kind: .knock, direction: "左后方远处", intensity: 0.64, note: "后门附近有轻响。"),
            AudioCue(turn: 8, kind: .whisper, direction: "右侧同伴", intensity: 0.56, note: "许栀压低声音提醒。"),
            AudioCue(turn: 8, kind: .heartbeat, direction: "颅内", intensity: 0.48, note: "心跳变大。")
        ]

        let renderer = ImageRenderer(content: ZStack {
            Color.black
            SoundRadarView(cues: cues)
                .frame(width: 150, height: 150)
                .padding(22)
        }
        .frame(width: 220, height: 220))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 220, height: 220)

        guard let image = renderer.nsImage else {
            XCTFail("SoundRadarView did not render")
            return
        }
        let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        var visibleSamples = 0
        var orangeSamples = 0
        var cyanSamples = 0
        var redSamples = 0
        var maximum = 0.0
        var minimum = 1.0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                minimum = min(minimum, luminance)
                maximum = max(maximum, luminance)
                if luminance > 0.04 { visibleSamples += 1 }
                if color.redComponent > 0.45, color.greenComponent > 0.18, color.blueComponent < 0.22 { orangeSamples += 1 }
                if color.blueComponent > color.redComponent + 0.08, color.greenComponent > color.redComponent + 0.04 { cyanSamples += 1 }
                if color.redComponent > color.greenComponent + 0.12, color.redComponent > color.blueComponent + 0.12 { redSamples += 1 }
            }
        }

        if let path = ProcessInfo.processInfo.environment["CAPTURE_SOUND_RADAR_VIEW"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }

        XCTAssertGreaterThan(visibleSamples, 600)
        XCTAssertGreaterThan(orangeSamples, 20)
        XCTAssertGreaterThan(cyanSamples, 12)
        XCTAssertGreaterThan(redSamples, 12)
        XCTAssertGreaterThan(maximum - minimum, 0.1)
    }

    func testSensorySoundscapeViewRendersAudibleSituationMeters() throws {
        let soundscape = SensorySoundscape(
            cueCount: 5,
            dominantKind: .footstep,
            dominantDirection: "右侧极近",
            averageIntensity: 0.72,
            riskPressure: 0.86,
            supportSignal: 0.34,
            bodyAlarm: 0.46,
            institutionalPressure: 0.28
        )

        let renderer = ImageRenderer(content: ZStack {
            Color.black
            SensorySoundscapeView(soundscape: soundscape, compact: false)
                .padding(18)
                .frame(width: 560)
        }
        .frame(width: 640, height: 240))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 640, height: 240)

        guard let image = renderer.nsImage else {
            XCTFail("SensorySoundscapeView did not render")
            return
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        var minimum = 1.0
        var maximum = 0.0
        var visibleSamples = 0
        var orangeSamples = 0
        var meterSamples = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                minimum = min(minimum, luminance)
                maximum = max(maximum, luminance)
                if luminance > 0.04 { visibleSamples += 1 }
                if color.redComponent > 0.38, color.greenComponent > 0.18, color.blueComponent < 0.24, color.redComponent > color.blueComponent + 0.18 {
                    orangeSamples += 1
                }
                if color.greenComponent > 0.38, color.blueComponent > 0.28, color.redComponent < 0.55 {
                    meterSamples += 1
                }
            }
        }

        if let path = ProcessInfo.processInfo.environment["CAPTURE_SENSORY_SOUNDSCAPE_VIEW"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }

        XCTAssertGreaterThan(visibleSamples, 6_000)
        XCTAssertGreaterThan(orangeSamples, 260)
        XCTAssertGreaterThan(meterSamples, 120)
        XCTAssertGreaterThan(maximum - minimum, 0.14)
    }

    func testSeatedPosePressureAccumulatesDuringChapterOneDwell() {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.startGame()
        game.teacher.isNearPlayer = true
        let startingEnergy = game.player.psychicEnergy
        let startingStress = game.player.stress
        let startingExposure = game.player.exposure
        let startingAttention = game.player.visualAttention

        game.setPose(.desk)
        game.advanceChapterOneDwell(by: 1.2)

        XCTAssertEqual(game.chapterOneStep, .observeLinChe)
        XCTAssertFalse(game.chapterOneLocatedAudioSteps.contains(.observeLinChe))
        XCTAssertEqual(game.seatedPosePressureFeedback?.pose, .desk)
        XCTAssertEqual(game.seatedPosePressureFeedback?.tone, .body)
        XCTAssertLessThan(game.player.psychicEnergy, startingEnergy)
        XCTAssertLessThan(game.player.visualAttention, startingAttention)
        XCTAssertGreaterThan(game.player.stress, startingStress)
        XCTAssertLessThan(game.player.exposure, startingExposure)
        XCTAssertTrue(game.audioCues.contains { $0.kind == .heartbeat && $0.note.contains("低头") })

        game.setPose(.forward)
        game.advanceChapterOneDwell(by: 0.8)

        XCTAssertEqual(game.seatedPosePressureFeedback?.pose, .forward)
        XCTAssertEqual(game.seatedPosePressureFeedback?.tone, .stable)
        XCTAssertGreaterThan(game.player.visualAttention, startingAttention - 4)
    }

    func testSeatedPosePressureViewRendersCurrentPostureCost() throws {
        let feedback = SeatedPosePressureFeedback.derive(
            pose: .rear,
            teacherNear: true,
            psychicEnergy: 42,
            stress: 72,
            maskCost: 64,
            visualAttention: 31
        )

        let renderer = ImageRenderer(content: ZStack {
            Color.black
            SeatedPosePressureView(feedback: feedback, compact: false)
                .padding(18)
                .frame(width: 560)
        }
        .frame(width: 640, height: 220))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 640, height: 220)

        guard let image = renderer.nsImage else {
            XCTFail("SeatedPosePressureView did not render")
            return
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        var minimum = 1.0
        var maximum = 0.0
        var visibleSamples = 0
        var orangeSamples = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                minimum = min(minimum, luminance)
                maximum = max(maximum, luminance)
                if luminance > 0.04 { visibleSamples += 1 }
                if color.redComponent > 0.38,
                   color.greenComponent > 0.16,
                   color.blueComponent < 0.24,
                   color.redComponent > color.blueComponent + 0.18 {
                    orangeSamples += 1
                }
            }
        }

        if let path = ProcessInfo.processInfo.environment["CAPTURE_SEATED_POSE_PRESSURE_VIEW"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }

        XCTAssertEqual(feedback.tone, .risk)
        XCTAssertGreaterThan(feedback.intensity, 0.8)
        XCTAssertGreaterThan(visibleSamples, 5_000)
        XCTAssertGreaterThan(orangeSamples, 220)
        XCTAssertGreaterThan(maximum - minimum, 0.14)
    }

    func testTeacherPatrolReadoutCouplesNearTeacherWithCurrentPose() throws {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.startGame()
        game.teacher.positionIndex = TeacherLocation.targetDesk.positionIndex
        game.teacher.location = .targetDesk
        game.teacher.isNearPlayer = true
        game.teacher.fatigue = 78
        game.teacher.kpiPressure = 82

        game.setPose(.left)
        game.advanceChapterOneDwell(by: 1.2)

        let readout = try XCTUnwrap(game.teacherPatrolReadout)
        XCTAssertEqual(readout.tone, .close)
        XCTAssertEqual(readout.location, .targetDesk)
        XCTAssertGreaterThan(readout.intensity, 0.74)
        XCTAssertTrue(readout.recommendation.contains("前方"))
        XCTAssertTrue(game.audioCues.contains { $0.kind == .footstep && $0.note.contains("前方") })
        XCTAssertGreaterThan(game.player.stress, 30)
    }

    func testTeacherPatrolReadoutViewRendersPatrolPressure() throws {
        let readout = TeacherPatrolReadout.derive(
            positionIndex: TeacherLocation.targetDesk.positionIndex,
            isNearPlayer: true,
            institutionalPressure: 82,
            fatigue: 76,
            playerPose: .desk,
            playerExposure: 58
        )

        let renderer = ImageRenderer(content: ZStack {
            Color.black
            TeacherPatrolReadoutView(readout: readout, compact: false)
                .padding(18)
                .frame(width: 560)
        }
        .frame(width: 640, height: 220))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 640, height: 220)

        guard let image = renderer.nsImage else {
            XCTFail("TeacherPatrolReadoutView did not render")
            return
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        var minimum = 1.0
        var maximum = 0.0
        var visibleSamples = 0
        var orangeSamples = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                minimum = min(minimum, luminance)
                maximum = max(maximum, luminance)
                if luminance > 0.04 { visibleSamples += 1 }
                if color.redComponent > 0.38,
                   color.greenComponent > 0.16,
                   color.blueComponent < 0.24,
                   color.redComponent > color.blueComponent + 0.18 {
                    orangeSamples += 1
                }
            }
        }

        if let path = ProcessInfo.processInfo.environment["CAPTURE_TEACHER_PATROL_READOUT_VIEW"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }

        XCTAssertEqual(readout.tone, .close)
        XCTAssertEqual(readout.location, .targetDesk)
        XCTAssertGreaterThan(readout.intensity, 0.8)
        XCTAssertGreaterThan(visibleSamples, 5_000)
        XCTAssertGreaterThan(orangeSamples, 220)
        XCTAssertGreaterThan(maximum - minimum, 0.14)
    }

    func testTeacherPatrolPressureStageMapsReadoutIntoSceneKitPath() throws {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.startGame()
        game.teacher.positionIndex = TeacherLocation.targetDesk.positionIndex
        game.teacher.location = .targetDesk
        game.teacher.isNearPlayer = true
        game.teacher.fatigue = 78
        game.teacher.kpiPressure = 82

        game.setPose(.left)
        game.advanceChapterOneDwell(by: 1.2)

        let readout = try XCTUnwrap(game.teacherPatrolReadout)
        let model = TeacherPatrolPressureStageModel.derive(
            from: readout,
            teacherPosition: SCNVector3(1.2, 0.05, 0.45)
        )
        let footprintOpacities = model.footprints.map(\.opacity)

        XCTAssertTrue(model.isActive)
        XCTAssertGreaterThan(model.stageOpacity, 0.65)
        XCTAssertGreaterThan(model.pathBandEmission, 0.5)
        XCTAssertGreaterThan(model.seatRingOpacity, 0.55)
        XCTAssertEqual(footprintOpacities.count, 5)
        XCTAssertGreaterThan(footprintOpacities.max() ?? 0, 0.5)
        XCTAssertLessThan(footprintOpacities.last ?? 1, footprintOpacities.first ?? 0)
        XCTAssertLessThan(model.pathBandPosition.z, 1.5)
        XCTAssertGreaterThan(model.pathBandPosition.z, -4.3)
        XCTAssertEqual(model.pathBandPosition.x, 0, accuracy: 0.001)
    }

    func testTeacherPatrolPressureStageSnapshotShowsVisiblePath() throws {
        guard let path = ProcessInfo.processInfo.environment["CAPTURE_TEACHER_PATROL_STAGE_VIEW"] else {
            throw XCTSkip("Set CAPTURE_TEACHER_PATROL_STAGE_VIEW to render the teacher-patrol pressure evidence snapshot.")
        }
        let game = GameManager(userDefaults: isolatedUserDefaults())
        let coordinator = ClassroomCoordinator()
        game.startGame()
        game.teacher.positionIndex = TeacherLocation.targetDesk.positionIndex
        game.teacher.location = .targetDesk
        game.teacher.isNearPlayer = true
        game.teacher.fatigue = 78
        game.teacher.kpiPressure = 82

        game.setPose(.left)
        game.advanceChapterOneDwell(by: 1.2)
        coordinator.update(game: game)

        let image = coordinator.renderSnapshot(size: CGSize(width: 960, height: 600))
        let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        var visibleSamples = 0
        var pressureSamples = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                if luminance > 0.05 { visibleSamples += 1 }
                if color.redComponent > 0.48,
                   color.greenComponent > 0.18,
                   color.blueComponent < 0.26,
                   color.redComponent > color.greenComponent + 0.12,
                   color.redComponent > color.blueComponent + 0.24 {
                    pressureSamples += 1
                }
            }
        }

        if let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }

        XCTAssertGreaterThan(coordinator.teacherPatrolPressureOpacity, 0.65)
        XCTAssertGreaterThan(visibleSamples, 5_000)
        XCTAssertGreaterThan(pressureSamples, 450)
    }

    func testChapterOneCluesRequireSpatialAudioLocalizationBeforeConfirmation() {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.startGame()

        XCTAssertEqual(game.currentSpatialAudioObjective?.targetPose, .left)
        XCTAssertFalse(game.chapterOneLocatedAudioSteps.contains(.observeLinChe))

        game.cameraPose = .left
        game.execute(.observe)

        XCTAssertEqual(game.chapterOneStep, .observeLinChe)
        XCTAssertTrue(game.chapterClues.isEmpty)
        XCTAssertTrue(game.message.contains("先听清"))

        game.setPose(.left)
        game.advanceChapterOneDwell(by: 1.0)

        XCTAssertFalse(game.chapterOneLocatedAudioSteps.contains(.observeLinChe))
        XCTAssertEqual(game.chapterOneDwellProgress, 0.5, accuracy: 0.001)

        game.advanceChapterOneDwell(by: 1.1)

        XCTAssertTrue(game.chapterOneLocatedAudioSteps.contains(.observeLinChe))
        XCTAssertNotNil(game.focusFeedbackTrigger)
        XCTAssertEqual(game.currentSpatialAudioObjective?.direction, "左侧近处")
        XCTAssertTrue(game.audioCues.contains { $0.direction == "左侧近处" && $0.kind == .paper })
        XCTAssertTrue(game.eventLog.contains { $0.title == "定位停住的翻书声" })

        game.execute(.observe)

        XCTAssertEqual(game.chapterOneStep, .locateHiddenSound)
        XCTAssertEqual(game.chapterClues.map(\.id), [.linChePage])
        XCTAssertEqual(game.currentSpatialAudioObjective?.targetPose, .right)

        localizeChapterOneSound(game, pose: .right)
        XCTAssertTrue(game.chapterOneLocatedAudioSteps.contains(.locateHiddenSound))
        game.execute(.observe)
        game.execute(.breathe)
        game.execute(.talk)
        chooseLinCheDialogue(game)
        if case .event = game.gameState {
            game.continueAfterEvent()
        }

        XCTAssertEqual(game.chapterOneStep, .inspectNote)
        game.setPose(.desk)
        game.execute(.observe)
        XCTAssertEqual(game.chapterOneStep, .inspectNote)
        XCTAssertEqual(game.chapterClues.map(\.id), [.linChePage, .hiddenCrying])

        game.setPose(.forward)
        localizeChapterOneSound(game, pose: .desk)
        XCTAssertTrue(game.chapterOneLocatedAudioSteps.contains(.inspectNote))
        game.execute(.observe)
        XCTAssertEqual(game.chapterOneStep, .followLinChe)
        XCTAssertEqual(game.chapterClues.map(\.id), [.linChePage, .hiddenCrying, .unsignedNote])
    }

    func testChapterOneDwellResetsOnPoseChangeAndFreezesDuringPause() {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.startFullNarrativeCampaign()

        game.setPose(.left)
        game.advanceChapterOneDwell(by: 1.2)
        XCTAssertFalse(game.chapterOneLocatedAudioSteps.contains(.observeLinChe))
        XCTAssertGreaterThan(game.chapterOneDwellProgress, 0.55)

        game.setPose(.forward)
        game.setPose(.left)
        XCTAssertEqual(game.chapterOneDwellProgress, 0, accuracy: 0.001)
        game.advanceChapterOneDwell(by: 1.2)
        XCTAssertFalse(game.chapterOneLocatedAudioSteps.contains(.observeLinChe))

        game.openNarrativePauseMenu()
        game.advanceChapterOneDwell(by: 2.0)
        XCTAssertFalse(game.chapterOneLocatedAudioSteps.contains(.observeLinChe))
        XCTAssertEqual(game.chapterOneDwellProgress, 0.6, accuracy: 0.001)

        game.resumeNarrativeFromPause()
        game.advanceChapterOneDwell(by: 0.9)
        XCTAssertTrue(game.chapterOneLocatedAudioSteps.contains(.observeLinChe))
        XCTAssertNotNil(game.focusFeedbackTrigger)
    }

    func testAudioSourceStageTracksObjectivesAndFallbackCues() throws {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        let coordinator = ClassroomCoordinator()
        game.startGame()
        coordinator.update(game: game)

        let leftPosition = try XCTUnwrap(coordinator.soundSourceStagePosition)
        let initialEmission = coordinator.soundSourceStageCoreEmission
        XCTAssertLessThan(leftPosition.x, -2)
        XCTAssertGreaterThan(coordinator.soundSourceStageOpacity, 0.45)
        XCTAssertEqual(coordinator.soundSourceStageRingOpacities.count, 2)
        XCTAssertGreaterThan(initialEmission, 0.8)

        game.setPose(.left)
        game.advanceChapterOneDwell(by: 1.0)
        coordinator.update(game: game)

        let partialEmission = coordinator.soundSourceStageCoreEmission
        XCTAssertFalse(game.chapterOneLocatedAudioSteps.contains(.observeLinChe))
        XCTAssertGreaterThan(partialEmission, initialEmission)
        XCTAssertLessThan(partialEmission, 1.55)

        game.advanceChapterOneDwell(by: 1.1)
        coordinator.update(game: game)

        let locatedEmission = coordinator.soundSourceStageCoreEmission
        XCTAssertTrue(game.chapterOneLocatedAudioSteps.contains(.observeLinChe))
        XCTAssertGreaterThan(locatedEmission, partialEmission)
        XCTAssertGreaterThan(coordinator.soundSourceStageOpacity, 0.75)

        game.execute(.observe)
        coordinator.update(game: game)

        let rightPosition = try XCTUnwrap(coordinator.soundSourceStagePosition)
        XCTAssertEqual(game.chapterOneStep, .locateHiddenSound)
        XCTAssertGreaterThan(rightPosition.x, 2)
        XCTAssertLessThan(coordinator.soundSourceStageCoreEmission, locatedEmission)

        localizeChapterOneSound(game, pose: .right)
        coordinator.update(game: game)

        XCTAssertTrue(game.chapterOneLocatedAudioSteps.contains(.locateHiddenSound))
        XCTAssertGreaterThan(coordinator.soundSourceStageCoreEmission, 1.5)

        game.chapterOneStep = .regulateSelf
        game.audioCues = [
            AudioCue(turn: 2, kind: .knock, direction: "后门方向", intensity: 0.82, note: "后门传来很轻的敲击。")
        ]

        coordinator.update(game: game)

        let position = try XCTUnwrap(coordinator.soundSourceStagePosition)
        XCTAssertLessThan(position.x, -2)
        XCTAssertGreaterThan(position.z, 4)
        XCTAssertGreaterThan(coordinator.soundSourceStageOpacity, 0.7)
        XCTAssertGreaterThan(coordinator.soundSourceStageCoreEmission, 1.2)
    }

    func testSoundSourceStageSnapshotShowsLocalizedCueBeacon() throws {
        guard let path = ProcessInfo.processInfo.environment["CAPTURE_SOUND_SOURCE_STAGE_VIEW"] else {
            throw XCTSkip("Set CAPTURE_SOUND_SOURCE_STAGE_VIEW to render the SceneKit sound-source evidence snapshot.")
        }
        let game = GameManager(userDefaults: isolatedUserDefaults())
        let coordinator = ClassroomCoordinator()
        game.startGame()
        localizeChapterOneSound(game, pose: .left)
        coordinator.update(game: game)

        let image = coordinator.renderSnapshot(size: CGSize(width: 960, height: 600))
        let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        var visibleSamples = 0
        var beaconSamples = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                if luminance > 0.05 { visibleSamples += 1 }
                if color.greenComponent > 0.52,
                   color.blueComponent > 0.34,
                   color.redComponent < color.greenComponent - 0.18 {
                    beaconSamples += 1
                }
            }
        }

        if let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }

        XCTAssertGreaterThan(visibleSamples, 20_000)
        XCTAssertGreaterThan(beaconSamples, 260)
    }

    func testSpatialAudioObjectiveViewRendersCurrentDirectionAndProgress() throws {
        let objective = try XCTUnwrap(SpatialAudioObjective.chapterOne(step: .locateHiddenSound, isLocated: false, focusProgress: 0.62))

        let renderer = ImageRenderer(content: ZStack {
            Color.black
            SpatialAudioObjectiveView(objective: objective, compact: false)
                .padding(18)
                .frame(width: 560)
        }
        .frame(width: 640, height: 210))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 640, height: 210)

        guard let image = renderer.nsImage else {
            XCTFail("SpatialAudioObjectiveView did not render")
            return
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        var minimum = 1.0
        var maximum = 0.0
        var visibleSamples = 0
        var cyanSamples = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                minimum = min(minimum, luminance)
                maximum = max(maximum, luminance)
                if luminance > 0.04 { visibleSamples += 1 }
                if color.blueComponent > color.redComponent + 0.1,
                   color.greenComponent > color.redComponent + 0.06,
                   color.blueComponent > 0.24 {
                    cyanSamples += 1
                }
            }
        }

        if let path = ProcessInfo.processInfo.environment["CAPTURE_SPATIAL_AUDIO_OBJECTIVE_VIEW"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }

        XCTAssertEqual(objective.direction, "右侧近处")
        XCTAssertEqual(objective.targetPose, .right)
        XCTAssertFalse(objective.isLocated)
        XCTAssertEqual(objective.progress, 0.62, accuracy: 0.001)
        XCTAssertGreaterThan(visibleSamples, 5_000)
        XCTAssertGreaterThan(cyanSamples, 120)
        XCTAssertGreaterThan(maximum - minimum, 0.14)
    }

    func testFocusFeedbackOverlayRendersWarmEdgeCue() throws {
        let feedback = DwellFocusFeedback(pose: .left, progress: 1)
        let renderer = ImageRenderer(content: ZStack {
            Color.black
            FocusFeedbackOverlay(feedback: feedback, reduceMotion: true, initiallyVisible: true)
        }
        .frame(width: 640, height: 360))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 640, height: 360)

        guard let image = renderer.nsImage else {
            XCTFail("FocusFeedbackOverlay did not render")
            return
        }
        let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        var edgeSamples = 0
        var coolEdgeSamples = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard x < 40 || x > bitmap.pixelsWide - 40 || y < 40 || y > bitmap.pixelsHigh - 40,
                      let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                if luminance > 0.03 { edgeSamples += 1 }
                if luminance > 0.012,
                   color.blueComponent + color.greenComponent > color.redComponent * 2.4,
                   color.blueComponent > color.redComponent + 0.01 {
                    coolEdgeSamples += 1
                }
            }
        }

        if let path = ProcessInfo.processInfo.environment["CAPTURE_DWELL_FOCUS_FEEDBACK_VIEW"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }

        XCTAssertGreaterThan(edgeSamples, 2_000)
        XCTAssertGreaterThan(coolEdgeSamples, 1_200)
    }

    func testAutonomousPlayUsesSoundscapeToLowerExposureBeforeActing() {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.startGame()
        game.featuredMonologue = nil
        game.chapterOneStep = .inspectNote
        game.cameraPose = .rear
        game.teacher.isNearPlayer = true
        game.audioCues = [
            AudioCue(turn: 1, kind: .footstep, direction: "右侧极近", intensity: 0.96, note: "脚步声停下。"),
            AudioCue(turn: 1, kind: .wrapper, direction: "桌面偏右", intensity: 0.82, note: "包装纸声被放大。")
        ]

        XCTAssertGreaterThan(game.currentSensorySoundscape.riskPressure, 0.72)
        XCTAssertTrue(game.autonomousPlayOneStep())
        XCTAssertEqual(game.cameraPose, .forward)
        XCTAssertTrue(game.autonomousPlayLastDecision.contains("声场风险"))
    }

    func testAutonomousPlayUsesPeerCueToChooseLowPressureLinCheApproach() {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.startGame()
        game.dismissFeaturedMonologue()
        game.settings.allowsWhispering = true
        game.chapterOneStep = .approachLinChe
        game.audioCues = [
            AudioCue(turn: 4, kind: .paper, direction: "左侧同桌", intensity: 0.94, note: "纸条被轻轻推近。"),
            AudioCue(turn: 4, kind: .whisper, direction: "左侧同桌", intensity: 0.86, note: "有人低声提醒。"),
            AudioCue(turn: 4, kind: .crying, direction: "前排", intensity: 0.52, note: "抽泣声被同伴接住。")
        ]

        XCTAssertTrue(game.autonomousPlayOneStep())

        XCTAssertEqual(game.chapterOneStep, .approachLinChe)
        XCTAssertEqual(game.sensoryPeerCue?.tone, .support)
        XCTAssertTrue(game.autonomousPlayLastDecision.contains("支援信号"))
        XCTAssertTrue(game.playtestRouteTranscript.last?.input.contains("支援信号") == true)
        XCTAssertTrue(game.playtestRouteTranscript.last?.feedback.contains("同学声场") == true)

        XCTAssertTrue(game.autonomousPlayOneStep())
        XCTAssertEqual(game.chapterOneStep, .inspectNote)
    }

    func testAutonomousPlayUsesPeerWarningBeforeExposedDeskAction() {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.startGame()
        game.dismissFeaturedMonologue()
        game.chapterOneStep = .inspectNote
        game.cameraPose = .desk
        game.completeCurrentSpatialAudioDwellIfPossible()
        game.teacher.isNearPlayer = true
        game.audioCues = [
            AudioCue(turn: 5, kind: .footstep, direction: "右侧极近", intensity: 0.96, note: "脚步声停在桌边。"),
            AudioCue(turn: 5, kind: .wrapper, direction: "桌面偏右", intensity: 0.88, note: "包装纸声被放大。")
        ]

        XCTAssertTrue(game.autonomousPlayOneStep())

        XCTAssertEqual(game.chapterOneStep, .inspectNote)
        XCTAssertEqual(game.cameraPose, .forward)
        XCTAssertEqual(game.sensoryPeerCue?.tone, .warning)
        XCTAssertTrue(game.autonomousPlayLastDecision.contains("提醒"))
        XCTAssertTrue(game.playtestRouteTranscript.last?.feedback.contains("同学声场") == true)
    }

    func testSensorySoundscapeShapesFirstPersonCameraPressure() {
        let quiet = SensoryCameraPressure.derive(from: .quiet)
        let risk = SensoryCameraPressure.derive(from: SensorySoundscape(
            cueCount: 2,
            dominantKind: .footstep,
            dominantDirection: "右侧极近",
            averageIntensity: 0.9,
            riskPressure: 0.92,
            supportSignal: 0.06,
            bodyAlarm: 0.24,
            institutionalPressure: 0.18
        ))
        let supported = SensoryCameraPressure.derive(from: SensorySoundscape(
            cueCount: 2,
            dominantKind: .paper,
            dominantDirection: "左侧近处",
            averageIntensity: 0.62,
            riskPressure: 0.34,
            supportSignal: 0.74,
            bodyAlarm: 0.12,
            institutionalPressure: 0.1
        ))

        XCTAssertEqual(quiet, .neutral)
        XCTAssertGreaterThan(risk.vignette, quiet.vignette + 0.34)
        XCTAssertGreaterThan(risk.blur, quiet.blur + 1.0)
        XCTAssertGreaterThan(risk.desaturation, quiet.desaturation + 0.08)
        XCTAssertLessThan(supported.vignette, risk.vignette)
        XCTAssertLessThan(supported.blur, risk.blur)
    }

    func testSensorySoundscapeShapesClassroomGroupReaction() {
        let riskSoundscape = SensorySoundscape.derive(
            from: [
                AudioCue(turn: 1, kind: .footstep, direction: "右侧极近", intensity: 0.96, note: "脚步声停在桌边。"),
                AudioCue(turn: 1, kind: .wrapper, direction: "桌面偏右", intensity: 0.86, note: "包装纸被放大。"),
                AudioCue(turn: 1, kind: .heartbeat, direction: "颅内", intensity: 0.72, note: "心跳盖过翻书声。")
            ],
            teacherNear: true,
            allowsWhispering: false
        )
        let riskReaction = SensoryClassroomGroupReaction.derive(from: riskSoundscape)

        let supportSoundscape = SensorySoundscape.derive(
            from: [
                AudioCue(turn: 2, kind: .paper, direction: "左侧近处", intensity: 0.94, note: "纸条被轻轻推近。"),
                AudioCue(turn: 2, kind: .whisper, direction: "后排偏左", intensity: 0.84, note: "有人低声提醒。"),
                AudioCue(turn: 2, kind: .crying, direction: "前排", intensity: 0.48, note: "抽泣声被同伴接住。")
            ],
            teacherNear: false,
            allowsWhispering: true
        )
        let supportReaction = SensoryClassroomGroupReaction.derive(from: supportSoundscape)

        XCTAssertGreaterThan(riskReaction.pressure, 0.72)
        XCTAssertGreaterThan(riskReaction.compression, 0.48)
        XCTAssertGreaterThan(riskReaction.opacityDrop, 0.12)
        XCTAssertGreaterThan(riskReaction.glowIntensity, 0.68)
        XCTAssertGreaterThan(riskReaction.leanZ, 0.02)
        XCTAssertFalse(riskReaction.supportDominant)

        XCTAssertGreaterThan(supportReaction.support, riskReaction.support + 0.34)
        XCTAssertLessThan(supportReaction.compression, riskReaction.compression * 0.45)
        XCTAssertLessThan(supportReaction.opacityDrop, riskReaction.opacityDrop)
        XCTAssertTrue(supportReaction.supportDominant)
        XCTAssertTrue(supportReaction.isActive)
    }

    func testSensoryPeerCueChoosesWarningAndSupportWithoutNumbers() {
        let warningMate = Classmate(
            id: 12,
            name: "陈言",
            seat: (row: 2, column: 2),
            profile: ClassmateProfile(cooperation: 52, orderliness: 86, rebelliousness: 22, empathy: 48, anxiety: 78, maskStrength: 62),
            support: 36,
            stress: 82,
            state: .studying,
            relationship: 48,
            hasSharedTruth: false
        )
        let supportMate = Classmate(
            id: 13,
            name: "许栀",
            seat: (row: 2, column: 0),
            profile: ClassmateProfile(cooperation: 74, orderliness: 48, rebelliousness: 36, empathy: 92, anxiety: 42, maskStrength: 58),
            support: 72,
            stress: 34,
            state: .studying,
            relationship: 70,
            hasSharedTruth: true
        )
        let risk = SensorySoundscape(
            cueCount: 2,
            dominantKind: .footstep,
            dominantDirection: "右侧极近",
            averageIntensity: 0.88,
            riskPressure: 0.86,
            supportSignal: 0.08,
            bodyAlarm: 0.18,
            institutionalPressure: 0.22
        )
        let support = SensorySoundscape(
            cueCount: 3,
            dominantKind: .paper,
            dominantDirection: "左侧同桌",
            averageIntensity: 0.68,
            riskPressure: 0.16,
            supportSignal: 0.74,
            bodyAlarm: 0.12,
            institutionalPressure: 0.08
        )

        let warningCue = SensoryPeerCue.derive(from: risk, classmates: [warningMate, supportMate], playerSupport: 32, allowsWhispering: false)
        let supportCue = SensoryPeerCue.derive(from: support, classmates: [warningMate, supportMate], playerSupport: 58, allowsWhispering: true)

        XCTAssertEqual(warningCue?.tone, .warning)
        XCTAssertEqual(warningCue?.classmateID, warningMate.id)
        XCTAssertTrue(warningCue?.lowPressureAction.contains("脚步声") == true)
        XCTAssertFalse((warningCue?.eventDetail ?? "").contains("86"))
        XCTAssertEqual(supportCue?.tone, .support)
        XCTAssertEqual(supportCue?.classmateID, supportMate.id)
        XCTAssertTrue(supportCue?.spokenLine.contains("要不要") == true)
        XCTAssertFalse((supportCue?.eventDetail ?? "").contains("74"))
    }

    func testAmbientSensoryPeerCueDoesNotInterruptChapterOneFlow() {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.startGame()
        game.dismissFeaturedMonologue()
        game.settings.allowsWhispering = true
        game.audioCues = [
            AudioCue(turn: 1, kind: .paper, direction: "左侧同桌", intensity: 0.94, note: "纸条被轻轻推近。"),
            AudioCue(turn: 1, kind: .whisper, direction: "左侧同桌", intensity: 0.86, note: "有人低声提醒。"),
            AudioCue(turn: 1, kind: .crying, direction: "前排", intensity: 0.52, note: "抽泣声被接住。")
        ]

        game.execute(.breathe)

        XCTAssertEqual(game.chapterOneStep, .observeLinChe)
        guard case .playing = game.gameState else {
            return XCTFail("Ambient sensory cue should not present an interrupting event")
        }
        XCTAssertEqual(game.sensoryPeerCue?.tone, .support)
        XCTAssertTrue(game.message.contains(game.sensoryPeerCue?.classmateName ?? ""))
        XCTAssertTrue(game.eventLog.first?.title.contains(game.sensoryPeerCue?.classmateName ?? "") == true)
        XCTAssertTrue(game.directionalSubtitleEvents.first?.note.contains("低声") == true || game.directionalSubtitleEvents.first?.note.contains("纸条") == true)
    }

    func testSensoryPeerCueViewRendersAudibleClassmateFeedback() throws {
        let cue = SensoryPeerCue(
            id: "support-preview",
            classmateID: 4,
            classmateName: "许栀",
            direction: "左侧同桌",
            tone: .support,
            surfaceSignal: "停下笔，朝声音的方向看了一眼，又很快移开视线",
            spokenLine: "低声问：要不要我帮你看一下？",
            lowPressureAction: "可以用一句很短的低声回应。",
            audioKind: .whisper,
            audioIntensity: 0.58
        )
        let renderer = ImageRenderer(content: ZStack {
            Color.black
            SensoryPeerCueView(cue: cue, compact: false)
                .padding(18)
                .frame(width: 520)
        }
        .frame(width: 620, height: 170))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 620, height: 170)

        guard let image = renderer.nsImage else {
            XCTFail("SensoryPeerCueView did not render")
            return
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        var visibleSamples = 0
        var mintSamples = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                if luminance > 0.05 { visibleSamples += 1 }
                if color.greenComponent > 0.38, color.blueComponent > 0.22, color.redComponent < 0.34 {
                    mintSamples += 1
                }
            }
        }

        if let path = ProcessInfo.processInfo.environment["CAPTURE_SENSORY_PEER_CUE_VIEW"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }

        XCTAssertGreaterThan(visibleSamples, 4_000)
        XCTAssertGreaterThan(mintSamples, 90)
    }

    func testSensorySoundscapeClassroomGroupReactionSnapshot() throws {
        guard ProcessInfo.processInfo.environment["CAPTURE_CLASSMATE_SENSORY_REACTION_VIEW"] != nil else {
            throw XCTSkip("Set CAPTURE_CLASSMATE_SENSORY_REACTION_VIEW to render the SceneKit group-reaction evidence snapshot.")
        }
        let game = GameManager(userDefaults: isolatedUserDefaults())
        let coordinator = ClassroomCoordinator()
        game.startGame()
        game.teacher.isNearPlayer = true
        game.audioCues = [
            AudioCue(turn: 1, kind: .footstep, direction: "右侧极近", intensity: 0.96, note: "脚步声停在桌边。"),
            AudioCue(turn: 1, kind: .wrapper, direction: "桌面偏右", intensity: 0.86, note: "包装纸被放大。"),
            AudioCue(turn: 1, kind: .heartbeat, direction: "颅内", intensity: 0.72, note: "心跳盖过翻书声。")
        ]
        coordinator.update(game: game)

        let riskOpacities = coordinator.classmateSensoryReactionOpacities
        let riskScales = coordinator.classmateSensoryReactionScales
        let riskGlow = coordinator.classmateSensoryReactionEmissionIntensities
        let riskLean = coordinator.classmateSensoryReactionLeanAngles
        let riskPressureGaze = coordinator.classmatePressureGazeOpacities
        let riskSupportSignal = coordinator.classmateSupportSignalOpacities
        let riskBystanderFold = coordinator.classmateBystanderFoldOpacities
        let riskAverageOpacity = riskOpacities.reduce(0, +) / CGFloat(riskOpacities.count)
        let riskAverageScaleY = riskScales.map { $0.y }.reduce(0, +) / CGFloat(riskScales.count)
        XCTAssertGreaterThan(riskOpacities.count, 8)
        XCTAssertLessThan(riskAverageOpacity, 0.94)
        XCTAssertLessThan(riskAverageScaleY, 0.94)
        XCTAssertGreaterThan(riskGlow.max() ?? 0, 0.68)
        XCTAssertGreaterThan(riskLean.map { abs($0) }.max() ?? 0, 0.02)
        XCTAssertGreaterThan(riskPressureGaze.filter { $0 > 0.2 }.count, 5)
        XCTAssertGreaterThan(riskBystanderFold.filter { $0 > 0.12 }.count, 5)
        XCTAssertGreaterThan((riskPressureGaze.max() ?? 0), (riskSupportSignal.max() ?? 0) + 0.08)

        let image = coordinator.renderSnapshot(size: CGSize(width: 960, height: 600))
        let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        var visibleSamples = 0
        var minimum = 1.0
        var maximum = 0.0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                minimum = min(minimum, luminance)
                maximum = max(maximum, luminance)
                if luminance > 0.04 { visibleSamples += 1 }
            }
        }
        XCTAssertGreaterThan(visibleSamples, 18_000)
        XCTAssertGreaterThan(maximum - minimum, 0.08)
        if let path = ProcessInfo.processInfo.environment["CAPTURE_CLASSMATE_SENSORY_REACTION_VIEW"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
            XCTAssertGreaterThan(png.count, 20_000)
        }

        game.teacher.isNearPlayer = false
        game.settings.allowsWhispering = true
        game.audioCues = [
            AudioCue(turn: 2, kind: .paper, direction: "左侧近处", intensity: 0.94, note: "纸条被轻轻推近。"),
            AudioCue(turn: 2, kind: .whisper, direction: "后排偏左", intensity: 0.84, note: "有人低声提醒。"),
            AudioCue(turn: 2, kind: .crying, direction: "前排", intensity: 0.48, note: "抽泣声被同伴接住。")
        ]
        coordinator.update(game: game)

        let supportOpacities = coordinator.classmateSensoryReactionOpacities
        let supportScales = coordinator.classmateSensoryReactionScales
        let supportGlow = coordinator.classmateSensoryReactionEmissionIntensities
        let supportPressureGaze = coordinator.classmatePressureGazeOpacities
        let supportSignal = coordinator.classmateSupportSignalOpacities
        let supportBystanderFold = coordinator.classmateBystanderFoldOpacities
        let supportAverageOpacity = supportOpacities.reduce(0, +) / CGFloat(supportOpacities.count)
        let supportAverageScaleY = supportScales.map { $0.y }.reduce(0, +) / CGFloat(supportScales.count)
        XCTAssertGreaterThan(supportAverageOpacity, riskAverageOpacity + 0.05)
        XCTAssertGreaterThan(supportAverageScaleY, riskAverageScaleY + 0.04)
        XCTAssertGreaterThan(supportGlow.max() ?? 0, 0.52)
        XCTAssertGreaterThan(supportSignal.filter { $0 > 0.2 }.count, 4)
        XCTAssertGreaterThan((supportSignal.max() ?? 0), (supportPressureGaze.max() ?? 0) + 0.06)
        XCTAssertLessThan((supportBystanderFold.max() ?? 0), (riskBystanderFold.max() ?? 0))
    }

    func testAutonomousPlayCompletesThePlayableSixChapterRoute() {
        let game = GameManager()
        game.startFullNarrativeCampaign()

        var visitedChapters = Set<NarrativeChapter>()
        var decisions: [String] = []
        for _ in 0..<320 {
            if game.narrativeCampaign.isActive {
                visitedChapters.insert(game.narrativeCampaign.chapter)
            }
            guard game.autonomousPlayOneStep() else { break }
            decisions.append(game.autonomousPlayLastDecision)
            if game.narrativeCampaign.isComplete { break }
        }

        XCTAssertTrue(game.narrativeCampaign.isComplete, decisions.suffix(12).joined(separator: " | "))
        XCTAssertEqual(visitedChapters, Set([.mirror, .noteTrace, .stairwell, .counseling, .epilogue]))
        XCTAssertEqual(game.chapterOneStep, .completed)
        XCTAssertEqual(game.chapterClues.map(\.id), [.linChePage, .hiddenCrying, .unsignedNote])
        XCTAssertEqual(game.narrativeCampaign.companionID, "许栀")
        XCTAssertEqual(game.narrativeCampaign.safetyRoute, NarrativeSafetyRoute.standardCounseling.displayName)
        XCTAssertTrue(game.narrativeCampaign.privacyProtected)
        XCTAssertTrue(game.narrativeCampaign.sharedSelf)
        XCTAssertTrue(decisions.contains { $0.contains("风险确认卡") })
        XCTAssertGreaterThan(game.autonomousPlayStepCount, 20)
    }

    func testAutonomousPlayRecordsRouteTranscriptWithFrictionAndFeedback() {
        let game = GameManager()
        game.startFullNarrativeCampaign()

        for _ in 0..<220 {
            guard game.autonomousPlayOneStep() else { break }
            if game.playtestRouteTranscript.contains(where: { $0.feedback.contains("选择回响") }) {
                break
            }
        }

        XCTAssertGreaterThan(game.playtestRouteTranscript.count, 8)
        XCTAssertTrue(game.playtestRouteTranscript.contains { $0.actor == "自主游玩" })
        XCTAssertTrue(game.playtestRouteTranscript.contains { $0.feedback.contains("提示") })
        XCTAssertTrue(game.playtestRouteTranscript.contains { $0.beforeState != $0.afterState })
    }

    func testAutonomousPlayTranscriptRecordsMirrorMicroEchoFeedback() {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.developerJump(to: .mirror, momentIndex: 1)
        game.dismissFeaturedMonologue()
        game.narrativeCampaign.exploration.positionX = -1.18
        game.narrativeCampaign.exploration.positionZ = -2.42
        XCTAssertTrue(game.interactNarrativeHotspot())
        XCTAssertTrue(game.narrativeCampaign.currentMomentActionReady)
        XCTAssertTrue(game.message.contains("感知闪现开始"))
        XCTAssertTrue(game.developerPlaytestLog.contains { $0.contains("MICRO_PORTAL enter trace") })
        let beforeCount = game.playtestRouteTranscript.count

        for _ in 0..<8 where game.developerPlaytestLog.contains(where: { $0.contains("MICRO_ECHO trace") }) == false {
            XCTAssertTrue(game.autonomousPlayOneStep())
        }

        XCTAssertGreaterThan(game.playtestRouteTranscript.count, beforeCount)
        let entry = game.playtestRouteTranscript.last(where: { $0.feedback.contains("微光回响") })
        XCTAssertTrue(entry?.input.contains("微互动") == true)
        XCTAssertTrue(entry?.feedback.contains("微光回响") == true)
        XCTAssertTrue(entry?.feedback.contains("微互动手感") == true)
        XCTAssertTrue(entry?.feedback.contains("镜面闪现") == true)
        XCTAssertTrue(entry?.feedback.contains("镜面草稿灯") == true)
        XCTAssertTrue(game.developerPlaytestLog.contains { $0.contains("MICRO_ECHO trace") })
    }

    func testAutonomousPlayTranscriptRecordsMelodyRhythmFeedback() {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.developerJump(to: .mirror, momentIndex: 2)
        game.dismissFeaturedMonologue()
        game.narrativeCampaign.exploration.positionX = 0
        game.narrativeCampaign.exploration.positionZ = -2.42
        XCTAssertTrue(game.interactNarrativeHotspot())
        let beforeCount = game.playtestRouteTranscript.count

        XCTAssertTrue(game.autonomousPlayOneStep())

        XCTAssertGreaterThan(game.playtestRouteTranscript.count, beforeCount)
        let entry = game.playtestRouteTranscript.last(where: { $0.feedback.contains("旋律节拍") })
        XCTAssertTrue(entry?.feedback.contains("392Hz / 523Hz / 330Hz / 440Hz") == true)
        XCTAssertTrue(game.developerPlaytestLog.contains { $0.contains("MELODY_RHYTHM caught next=夜") })
    }

    func testAutonomousPlayTranscriptRecordsMirrorReturnDirectorFeedback() {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.developerJump(to: .mirror, momentIndex: 3)
        game.dismissFeaturedMonologue()
        game.narrativeCampaign.exploration.positionX = 1.18
        game.narrativeCampaign.exploration.positionZ = -2.42
        XCTAssertTrue(game.interactNarrativeHotspot())
        let beforeCount = game.playtestRouteTranscript.count

        for _ in 0..<6 where game.narrativeCampaign.miniGameCompleted == false {
            XCTAssertTrue(game.autonomousPlayOneStep())
        }

        XCTAssertTrue(game.narrativeCampaign.miniGameCompleted)
        XCTAssertGreaterThan(game.playtestRouteTranscript.count, beforeCount)
        let entry = game.playtestRouteTranscript.last(where: { $0.feedback.contains("镜面回归导演") })
        XCTAssertTrue(entry?.feedback.contains("褪色 72") == true)
        XCTAssertTrue(entry?.feedback.contains("擦痕灯") == true)
    }

    func testAutonomousPlayTranscriptRecordsMirrorDialogueConsequenceFeedback() {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.developerJump(to: .mirror, momentIndex: 4)
        game.dismissFeaturedMonologue()
        game.narrativeCampaign.exploration.interactionCount = 1
        let beforeCount = game.playtestRouteTranscript.count

        XCTAssertTrue(game.autonomousPlayOneStep())

        XCTAssertEqual(game.narrativeCampaign.chapter, .noteTrace)
        XCTAssertGreaterThan(game.playtestRouteTranscript.count, beforeCount)
        let entry = game.playtestRouteTranscript.last(where: { $0.feedback.contains("林澈后果") })
        XCTAssertTrue(entry?.input.contains("invite") == true)
        XCTAssertTrue(entry?.feedback.contains("林澈信任 +2") == true)
        XCTAssertTrue(entry?.feedback.contains("成人交接") == true)
        XCTAssertTrue(game.audioCues.contains { $0.kind == .whisper && $0.direction == "林澈回应" })
        XCTAssertTrue(game.developerPlaytestLog.contains { $0.contains("MIRROR_DIALOGUE invite") })
    }

    func testAutonomousPlayTranscriptConsumesChoiceImpactFromHotspotChoice() {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.developerJump(to: .noteTrace, momentIndex: 2)
        game.dismissFeaturedMonologue()
        game.narrativeCampaign.exploration.positionX = 1.8
        game.narrativeCampaign.exploration.positionZ = 0.25

        XCTAssertTrue(game.autonomousPlayOneStep())
        let entry = game.playtestRouteTranscript.last

        XCTAssertEqual(game.narrativeCampaign.companionID, "许栀")
        XCTAssertTrue(entry?.input.contains("xu") == true)
        XCTAssertTrue(entry?.feedback.contains("选择回响") == true)
        XCTAssertTrue(entry?.hasChoiceImpactFeedback == true)
        XCTAssertTrue(entry?.choiceImpactFeedback?.contains("支持靠近") == true)
    }

    func testNarrativeStallGuidanceAppearsBeforeFallbackWithoutChoosingForPlayer() {
        let game = GameManager()
        game.developerJump(to: .mirror)
        let momentID = game.narrativeCampaign.currentMoment.id

        for _ in 0..<299 {
            game.tickNarrativeExploration(deltaTime: 0.1)
        }
        XCTAssertNil(game.narrativeGuidanceCue)

        game.tickNarrativeExploration(deltaTime: 0.1)

        XCTAssertEqual(game.narrativeCampaign.currentMoment.id, momentID)
        XCTAssertEqual(game.narrativeGuidanceCue?.stage, .gentle)
        XCTAssertEqual(game.narrativeGuidanceCue?.momentID, momentID)
        XCTAssertTrue(game.narrativeGuidanceCue?.detail.contains("慢慢靠近") == true)
        XCTAssertTrue(game.developerPlaytestLog.contains("GUIDE_HINT \(momentID)"))
    }

    func testNarrativeStallDirectorNudgeTurnsPlayerTowardSpatialObjective() {
        let game = GameManager()
        game.developerJump(to: .mirror)
        let momentID = game.narrativeCampaign.currentMoment.id
        let startX = game.narrativeCampaign.exploration.positionX
        let startZ = game.narrativeCampaign.exploration.positionZ

        for _ in 0..<901 {
            game.tickNarrativeExploration(deltaTime: 0.1)
        }

        XCTAssertEqual(game.narrativeCampaign.currentMoment.id, momentID)
        XCTAssertEqual(game.narrativeGuidanceCue?.stage, .directorNudge)
        XCTAssertTrue(game.narrativeGuidanceCue?.detail.contains("空间方向") == true)
        XCTAssertTrue(game.developerPlaytestLog.contains("GUIDE_NUDGE \(momentID)"))
        XCTAssertGreaterThan(hypot(
            game.narrativeCampaign.exploration.positionX - startX,
            game.narrativeCampaign.exploration.positionZ - startZ
        ), 0.2)
        XCTAssertTrue(game.audioCues.contains { $0.note.contains("空间线索") })
    }

    func testNarrativeStallGuidanceRendersVisibleCueCard() throws {
        let game = GameManager()
        game.developerJump(to: .mirror)
        for _ in 0..<300 {
            game.tickNarrativeExploration(deltaTime: 0.1)
        }

        XCTAssertEqual(game.narrativeGuidanceCue?.stage, .gentle)

        let renderer = ImageRenderer(content: NarrativeCampaignView(game: game)
            .environmentObject(game)
            .frame(width: 960, height: 540))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 960, height: 540)

        guard let image = renderer.nsImage else {
            XCTFail("NarrativeCampaignView guidance cue did not render")
            return
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        var minimum = 1.0
        var maximum = 0.0
        var visibleSamples = 0
        for y in stride(from: 8, to: bitmap.pixelsHigh, by: 24) {
            for x in stride(from: 8, to: bitmap.pixelsWide, by: 24) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                minimum = min(minimum, luminance)
                maximum = max(maximum, luminance)
                if luminance > 0.04 { visibleSamples += 1 }
            }
        }
        XCTAssertGreaterThan(visibleSamples, 150)
        XCTAssertGreaterThan(maximum - minimum, 0.14)

        if let path = ProcessInfo.processInfo.environment["CAPTURE_STALL_GUIDANCE_VIEW"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }
    }

    func testPlaytestRouteTranscriptViewRendersVisibleEntries() throws {
        let game = GameManager()
        game.startFullNarrativeCampaign()
        for _ in 0..<45 {
            guard game.autonomousPlayOneStep() else { break }
        }

        let sensoryEntry = PlaytestRouteTranscriptEntry(
            id: 9_001,
            step: 9_001,
            actor: "自主游玩",
            input: "顺着许栀的支援信号，低声问候林澈",
            beforeState: "第一章 approachLinChe · 线索 2 · 视角 forward",
            afterState: "第一章 inspectNote · 线索 2 · 视角 forward",
            friction: "第一章物理视角链路",
            feedback: "选择回响 支持靠近 · 低语 · 强度 48 / 同学声场 许栀@左侧同桌：可以用一句很短的低声回应。 / 音频 低语@左侧同桌 / 提示 许栀低声问：要不要我帮你看一下？"
        )
        let spatialEntry = PlaytestRouteTranscriptEntry(
            id: 9_002,
            step: 9_002,
            actor: "自主游玩",
            input: "走向热点：值日表",
            beforeState: "第三章 3.note · 线索 0 · 位置 -2.4,1.2",
            afterState: "第三章 3.note · 线索 0 · 位置 -1.7,0.4",
            friction: "空间探索门槛未完成：值日表",
            feedback: "空间导航 向右后方靠近 · 中距 · 脉冲 55 / 提示 脚步转向值日表"
        )
        let companionEntry = PlaytestRouteTranscriptEntry(
            id: 9_003,
            step: 9_003,
            actor: "自主游玩",
            input: "走向热点：门轴声",
            beforeState: "第三章 3.door · 许栀同行 · 位置 -2.4,-0.6",
            afterState: "第三章 3.door · 许栀同行 · 位置 -1.5,0.1",
            friction: "空间探索门槛未完成：门轴声",
            feedback: "同伴低语 许栀压低声音：门轴声在前方，还差 2.3m。 / 空间导航 向前方靠近 · 中距 · 脉冲 59"
        )
        let entries = Array(game.playtestRouteTranscript.suffix(2)) + [sensoryEntry, spatialEntry, companionEntry]
        XCTAssertEqual(entries.count, 5)
        XCTAssertTrue(entries.contains { $0.hasFriction })
        XCTAssertTrue(entries.contains { $0.hasChoiceImpactFeedback })
        XCTAssertTrue(entries.contains { $0.hasSensoryPeerFeedback })
        XCTAssertTrue(entries.contains { $0.hasSpatialNavigationFeedback })
        XCTAssertTrue(entries.contains { $0.hasCompanionNavigationFeedback })

        let renderer = ImageRenderer(content: ZStack {
            Color.black
            PlaytestRouteTranscriptView(entries: entries)
                .frame(width: 560, height: 252)
                .padding(24)
        }
        .frame(width: 640, height: 342))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 640, height: 342)

        guard let image = renderer.nsImage else {
            XCTFail("PlaytestRouteTranscriptView did not render")
            return
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        var minimum = 1.0
        var maximum = 0.0
        var visibleSamples = 0
        var mintSamples = 0
        var bottomVisibleSamples = 0
        var orangeSamples = 0
        for y in stride(from: 8, to: bitmap.pixelsHigh, by: 18) {
            for x in stride(from: 8, to: bitmap.pixelsWide, by: 18) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                minimum = min(minimum, luminance)
                maximum = max(maximum, luminance)
                if luminance > 0.04 { visibleSamples += 1 }
                if y > bitmap.pixelsHigh - 74, luminance > 0.04 { bottomVisibleSamples += 1 }
                if color.greenComponent > 0.32, color.blueComponent > 0.2, color.redComponent < 0.36 {
                    mintSamples += 1
                }
            }
        }
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.redComponent > 0.38, color.greenComponent > 0.18, color.blueComponent < 0.24, color.redComponent > color.blueComponent + 0.18 {
                    orangeSamples += 1
                }
            }
        }
        XCTAssertGreaterThan(visibleSamples, 50)
        XCTAssertGreaterThan(mintSamples, 1)
        XCTAssertGreaterThan(bottomVisibleSamples, 14)
        XCTAssertGreaterThan(orangeSamples, 60)
        XCTAssertGreaterThan(maximum - minimum, 0.12)

        if let path = ProcessInfo.processInfo.environment["CAPTURE_PLAYTEST_TRANSCRIPT_VIEW"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
           try png.write(to: url)
        }
    }

    func testAutonomousDirectorOverlayRendersDecisionAndSensoryRationale() throws {
        let soundscape = SensorySoundscape(
            cueCount: 3,
            dominantKind: .footstep,
            dominantDirection: "右侧极近",
            averageIntensity: 0.84,
            riskPressure: 0.78,
            supportSignal: 0.48,
            bodyAlarm: 0.36,
            institutionalPressure: 0.42
        )
        let cue = SensoryPeerCue(
            id: "warning-preview",
            classmateID: 4,
            classmateName: "许栀",
            direction: "左侧同桌",
            tone: .warning,
            surfaceSignal: "停下笔，朝讲台看了一眼",
            spokenLine: "几乎不动嘴唇地说：先别动，脚步在旁边。",
            lowPressureAction: "把视线收回前方，等脚步声位置稳定。",
            audioKind: .whisper,
            audioIntensity: 0.64
        )
        let entry = PlaytestRouteTranscriptEntry(
            id: 12,
            step: 12,
            actor: "自主游玩",
            input: "听见许栀提醒，先把视线收回前方",
            beforeState: "第一章 inspectNote · 视角 desk",
            afterState: "第一章 inspectNote · 视角 forward",
            friction: "第一章物理视角链路",
            feedback: "同学声场 许栀@左侧同桌：把视线收回前方。 / 音频 低语@左侧同桌"
        )

        let renderer = ImageRenderer(content: ZStack {
            Color.black
            AutonomousDirectorOverlay(
                status: "自主游玩中",
                decision: "听见许栀提醒，先把视线收回前方",
                stepCount: 12,
                soundscape: soundscape,
                peerCue: cue,
                latestEntry: entry,
                onTakeover: {}
            )
            .padding(18)
            .frame(width: 420)
        }
        .frame(width: 500, height: 260))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 500, height: 260)

        guard let image = renderer.nsImage else {
            XCTFail("AutonomousDirectorOverlay did not render")
            return
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        var minimum = 1.0
        var maximum = 0.0
        var visibleSamples = 0
        var mintSamples = 0
        var orangeSamples = 0
        for y in stride(from: 8, to: bitmap.pixelsHigh, by: 14) {
            for x in stride(from: 8, to: bitmap.pixelsWide, by: 14) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                minimum = min(minimum, luminance)
                maximum = max(maximum, luminance)
                if luminance > 0.04 { visibleSamples += 1 }
                if color.greenComponent > 0.32, color.blueComponent > 0.2, color.redComponent < 0.36 {
                    mintSamples += 1
                }
                if color.redComponent > 0.38, color.greenComponent > 0.18, color.blueComponent < 0.28, color.redComponent > color.blueComponent + 0.14 {
                    orangeSamples += 1
                }
            }
        }

        if let path = ProcessInfo.processInfo.environment["CAPTURE_AUTONOMOUS_DIRECTOR_OVERLAY"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }

        XCTAssertGreaterThan(visibleSamples, 70)
        XCTAssertGreaterThan(mintSamples, 1)
        XCTAssertGreaterThan(orangeSamples, 1)
        XCTAssertGreaterThan(maximum - minimum, 0.14)
    }

    func testRenderedCampaignRequiresPhysicalExplorationBeforeChoicesUnlock() {
        let game = GameManager()
        game.developerJump(to: .mirror)
        let firstMoment = game.narrativeCampaign.currentMoment.id

        game.advanceNarrative("enterMirror")
        XCTAssertEqual(game.narrativeCampaign.currentMoment.id, firstMoment)
        XCTAssertFalse(game.narrativeCampaign.explorationReady)

        for _ in 0..<100 where game.nearbyNarrativeHotspot == nil {
            game.moveNarrativeExploration(forward: 1, strafe: 0, deltaTime: 0.05)
        }
        XCTAssertTrue(game.interactNarrativeHotspot())
        XCTAssertTrue(game.narrativeCampaign.explorationReady)

        game.advanceNarrative("enterMirror")
        XCTAssertEqual(game.narrativeCampaign.currentMoment.id, "2.trace")
    }

    func testChapterThreeInvestigationRequiresTheAuthoredHotspotForEachStep() {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.developerJump(to: .noteTrace, momentIndex: 0)

        game.advanceNarrative("inspectFold")
        XCTAssertEqual(game.narrativeCampaign.currentMoment.id, "3.note")

        game.narrativeCampaign.exploration.positionX = -0.2
        game.narrativeCampaign.exploration.positionZ = 1.5
        XCTAssertEqual(game.nearbyNarrativeHotspot?.id, "note.paperTrail")
        XCTAssertTrue(game.interactNarrativeHotspot())
        game.advanceNarrative("inspectFold")
        XCTAssertEqual(game.narrativeCampaign.currentMoment.id, "3.note")
        XCTAssertTrue(game.message.contains("值日表"))

        game.narrativeCampaign.exploration.positionX = 0
        game.narrativeCampaign.exploration.positionZ = -1.45
        XCTAssertEqual(game.nearbyNarrativeHotspot?.id, "note.table")
        XCTAssertTrue(game.interactNarrativeHotspot())
        game.advanceNarrative("inspectFold")
        XCTAssertEqual(game.narrativeCampaign.currentMoment.id, "3.locate")

        game.advanceNarrative("locateJiang")
        XCTAssertEqual(game.narrativeCampaign.currentMoment.id, "3.locate")
        XCTAssertTrue(game.message.contains("桌面痕迹"))

        game.narrativeCampaign.exploration.positionX = -0.2
        game.narrativeCampaign.exploration.positionZ = 1.5
        XCTAssertEqual(game.nearbyNarrativeHotspot?.id, "note.paperTrail")
        XCTAssertTrue(game.interactNarrativeHotspot())
        XCTAssertEqual(game.narrativeCampaign.noteTraceDepartureClues, [.doorSound])
        game.advanceNarrative("locateJiang")
        XCTAssertEqual(game.narrativeCampaign.currentMoment.id, "3.locate")
        XCTAssertTrue(game.message.contains("桌面痕迹"))

        game.narrativeCampaign.exploration.positionX = 1.45
        game.narrativeCampaign.exploration.positionZ = -0.45
        XCTAssertEqual(game.nearbyNarrativeHotspot?.id, "note.deskTrace")
        XCTAssertTrue(game.interactNarrativeHotspot())
        XCTAssertEqual(game.narrativeCampaign.noteTraceDepartureClues, Set(NoteTraceDepartureClue.allCases))
        game.advanceNarrative("locateJiang")
        XCTAssertEqual(game.narrativeCampaign.currentMoment.id, "3.companion")
    }

    func testCompanionChoiceRequiresNearbyNpcHotspotRatherThanDirectButtonAdvance() {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.developerJump(to: .noteTrace, momentIndex: 2)

        game.advanceNarrative("zhou")
        XCTAssertTrue(game.narrativeCampaign.companionID.isEmpty)
        XCTAssertEqual(game.narrativeCampaign.currentMoment.id, "3.companion")
        XCTAssertTrue(game.narrativeCampaign.currentMomentActionPrompt?.contains("周予安") == true)
        XCTAssertTrue(game.narrativeCampaign.currentMomentActionPrompt?.contains("许栀") == true)

        game.narrativeCampaign.exploration.positionX = 1.8
        game.narrativeCampaign.exploration.positionZ = 0.25
        XCTAssertEqual(game.nearbyNarrativeHotspot?.choiceID, "xu")
        XCTAssertTrue(game.interactNarrativeHotspot())
        XCTAssertEqual(game.narrativeCampaign.companionID, "许栀")
        XCTAssertEqual(game.narrativeCampaign.currentMoment.id, "3.door")
    }

    func testChapterThreeNavigationCueTracksDistanceAndInteractionRange() throws {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.developerJump(to: .noteTrace, momentIndex: 0)

        game.narrativeCampaign.exploration.positionX = -2.4
        game.narrativeCampaign.exploration.positionZ = 1.2
        var cue = try XCTUnwrap(ChapterThreeNavigationCue.derive(from: game.narrativeCampaign))
        XCTAssertEqual(cue.targetID, "note.table")
        XCTAssertEqual(cue.targetTitle, "值日表")
        XCTAssertFalse(cue.isInRange)
        XCTAssertEqual(cue.headingText, "向右后方靠近")
        XCTAssertEqual(cue.compassSymbol, "arrow.down.right.circle.fill")
        XCTAssertEqual(cue.distanceBand, "中距")
        XCTAssertTrue(cue.statusText.contains("继续靠近"))
        XCTAssertLessThan(cue.proximity, 1)
        XCTAssertGreaterThan(cue.pulseIntensity, cue.proximity)

        game.narrativeCampaign.exploration.positionX = 0
        game.narrativeCampaign.exploration.positionZ = -1.45
        cue = try XCTUnwrap(ChapterThreeNavigationCue.derive(from: game.narrativeCampaign))
        XCTAssertTrue(cue.isInRange)
        XCTAssertEqual(cue.headingText, "目标就在身边")
        XCTAssertEqual(cue.compassSymbol, "scope")
        XCTAssertEqual(cue.distanceBand, "确认范围")
        XCTAssertTrue(cue.statusText.contains("按 E 互动"))
        XCTAssertEqual(cue.proximity, 1)
        XCTAssertEqual(cue.pulseIntensity, 1)

        XCTAssertTrue(game.interactNarrativeHotspot())
        game.advanceNarrative("inspectFold")
        cue = try XCTUnwrap(ChapterThreeNavigationCue.derive(from: game.narrativeCampaign))
        XCTAssertEqual(cue.targetID, "note.deskTrace")
        XCTAssertEqual(cue.targetTitle, "江越座位")

        game.narrativeCampaign.exploration.positionX = 1.45
        game.narrativeCampaign.exploration.positionZ = -0.45
        XCTAssertTrue(game.interactNarrativeHotspot())
        cue = try XCTUnwrap(ChapterThreeNavigationCue.derive(from: game.narrativeCampaign))
        XCTAssertEqual(cue.targetID, "note.paperTrail")
        XCTAssertEqual(cue.targetTitle, "门轴声")
    }

    func testAutonomousPlayTranscriptRecordsChapterThreeNavigationPulse() {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.developerJump(to: .noteTrace, momentIndex: 0)
        game.dismissFeaturedMonologue()
        game.narrativeCampaign.exploration.positionX = -2.4
        game.narrativeCampaign.exploration.positionZ = 1.2

        XCTAssertTrue(game.autonomousPlayOneStep())
        let entry = game.playtestRouteTranscript.last

        XCTAssertTrue(entry?.hasSpatialNavigationFeedback == true)
        XCTAssertTrue(entry?.spatialNavigationFeedback?.contains("向右后方靠近") == true)
        XCTAssertTrue(entry?.spatialNavigationFeedback?.contains("脉冲") == true)
    }

    func testCompanionNavigationLineFollowsChapterThreeTargetWithoutAdvancing() {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.developerJump(to: .noteTrace, momentIndex: 2)
        game.dismissFeaturedMonologue()
        game.narrativeCampaign.exploration.positionX = 1.8
        game.narrativeCampaign.exploration.positionZ = 0.25
        XCTAssertTrue(game.interactNarrativeHotspot())

        game.narrativeCampaign.exploration.positionX = -2.4
        game.narrativeCampaign.exploration.positionZ = -0.6
        let status = game.narrativeCampaign.companionPresenceStatus
        XCTAssertEqual(status?.companionID, "许栀")
        XCTAssertEqual(status?.mode, .following)
        XCTAssertTrue(status?.navigationLine?.contains("许栀压低声音") == true)
        XCTAssertTrue(status?.navigationLine?.contains("门轴声") == true)
        XCTAssertEqual(game.narrativeCampaign.currentMoment.id, "3.door")

        XCTAssertTrue(game.autonomousPlayOneStep())
        let entry = game.playtestRouteTranscript.last
        XCTAssertTrue(entry?.hasCompanionNavigationFeedback == true)
        XCTAssertTrue(entry?.companionNavigationFeedback?.contains("门轴声") == true)
        XCTAssertEqual(game.narrativeCampaign.currentMoment.id, "3.door")
    }

    func testCompanionNavigationWhisperPublishesSpatialCueAndSubtitleWithoutRepeating() throws {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.developerJump(to: .noteTrace, momentIndex: 2)
        game.dismissFeaturedMonologue()
        game.narrativeCampaign.exploration.positionX = 1.8
        game.narrativeCampaign.exploration.positionZ = 0.25
        XCTAssertTrue(game.interactNarrativeHotspot())

        game.narrativeCampaign.exploration.positionX = -2.4
        game.narrativeCampaign.exploration.positionZ = -0.6
        game.moveNarrativeExploration(forward: 0, strafe: 0, deltaTime: 0.05)

        let whisperCue = game.audioCues.first
        XCTAssertEqual(whisperCue?.kind, .whisper)
        XCTAssertEqual(whisperCue?.direction, "右侧同伴")
        XCTAssertTrue(whisperCue?.note.contains("许栀压低声音") == true)
        XCTAssertTrue(whisperCue?.note.contains("门轴声") == true)

        let subtitle = game.directionalSubtitleEvents.first
        XCTAssertEqual(subtitle?.kind, .whisper)
        XCTAssertEqual(subtitle?.direction, "右侧同伴")
        XCTAssertTrue(subtitle?.caption.contains("右侧同伴") == true)
        XCTAssertTrue(subtitle?.accessibilitySummary.contains("门轴声") == true)

        let audioCount = game.audioCues.count
        let subtitleCount = game.directionalSubtitleEvents.count
        game.moveNarrativeExploration(forward: 0, strafe: 0, deltaTime: 0.05)
        XCTAssertEqual(game.audioCues.count, audioCount)
        XCTAssertEqual(game.directionalSubtitleEvents.count, subtitleCount)

        let renderer = ImageRenderer(content: ZStack {
            Color.black
            DirectionalSubtitleStripView(
                events: Array(game.directionalSubtitleEvents.prefix(2)),
                captionsEnabled: true
            )
            .padding(14)
            .frame(width: 292, alignment: .leading)
            .background(.black.opacity(0.46), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.14), lineWidth: 1))
            .padding(24)
        }
        .frame(width: 400, height: 180))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 400, height: 180)

        guard let image = renderer.nsImage else {
            XCTFail("Companion whisper subtitle strip did not render")
            return
        }
        let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        var visibleSamples = 0
        var cyanSamples = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                if luminance > 0.04 { visibleSamples += 1 }
                if color.blueComponent > color.redComponent + 0.08, color.greenComponent > color.redComponent + 0.04 {
                    cyanSamples += 1
                }
            }
        }

        if let path = ProcessInfo.processInfo.environment["CAPTURE_COMPANION_WHISPER_SUBTITLE_VIEW"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }

        XCTAssertGreaterThan(visibleSamples, 2_000)
        XCTAssertGreaterThan(cyanSamples, 120)
    }

    func testSpatialAudioDirectionMappingPreservesEightDirectionAndCompanionSide() {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        let base = game.debugSpatialPositionForAudioCueDirection("颅内")

        let rightFront = game.debugSpatialPositionForAudioCueDirection("右前方")
        XCTAssertGreaterThan(rightFront.x, base.x + 0.75)
        XCTAssertLessThan(rightFront.z, base.z - 0.75)

        let leftRear = game.debugSpatialPositionForAudioCueDirection("左后方")
        XCTAssertLessThan(leftRear.x, base.x - 0.75)
        XCTAssertGreaterThan(leftRear.z, base.z + 0.75)

        let rightCompanion = game.debugSpatialPositionForAudioCueDirection("右侧同伴")
        XCTAssertGreaterThan(rightCompanion.x, base.x + 0.45)
        XCTAssertLessThan(abs(rightCompanion.z - base.z), abs(rightFront.z - base.z))

        let leftCompanion = game.debugSpatialPositionForAudioCueDirection("左侧同伴")
        XCTAssertLessThan(leftCompanion.x, base.x - 0.45)
        XCTAssertEqual(leftCompanion.z, rightCompanion.z, accuracy: 0.001)
    }

    func testChapterThreeInvestigationViewRendersVisibleProgressState() throws {
        var campaign = NarrativeCampaign(isActive: true, chapter: .noteTrace, momentIndex: 1)
        campaign.completedMomentIDs.insert("3.note")
        campaign.exploration.positionX = -0.2
        campaign.exploration.positionZ = 1.5

        let renderer = ImageRenderer(content: ZStack {
            Color.black
            ChapterThreeInvestigationView(campaign: campaign)
                .padding(18)
                .frame(width: 560)
        }
        .frame(width: 620, height: 260))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 620, height: 260)

        guard let image = renderer.nsImage else {
            XCTFail("ChapterThreeInvestigationView did not render")
            return
        }
        let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        var visibleSamples = 0
        var mintSamples = 0
        var cyanSamples = 0
        var maximum = 0.0
        var minimum = 1.0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                minimum = min(minimum, luminance)
                maximum = max(maximum, luminance)
                if luminance > 0.04 { visibleSamples += 1 }
                if color.greenComponent > color.redComponent + 0.08, color.greenComponent > 0.42 {
                    mintSamples += 1
                }
                if color.blueComponent > color.redComponent + 0.08, color.greenComponent > color.redComponent + 0.04 {
                    cyanSamples += 1
                }
            }
        }

        if let path = ProcessInfo.processInfo.environment["CAPTURE_CHAPTER_THREE_INVESTIGATION_VIEW"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }

        XCTAssertGreaterThan(visibleSamples, 4_500)
        XCTAssertGreaterThan(mintSamples, 120)
        XCTAssertGreaterThan(cyanSamples, 120)
        XCTAssertGreaterThan(maximum - minimum, 0.16)
    }

    func testChapterThreeRequiredHotspotsLightTheThreeDimensionalStage() throws {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        let coordinator = ClassroomCoordinator()
        game.developerJump(to: .noteTrace, momentIndex: 0)
        coordinator.update(game: game)

        var opacities = coordinator.noteTraceHotspotOpacities
        let emissions = coordinator.noteTraceHotspotEmissionIntensities
        XCTAssertGreaterThan(try XCTUnwrap(opacities["note.table"]), try XCTUnwrap(opacities["note.paperTrail"]))
        XCTAssertGreaterThan(try XCTUnwrap(emissions["note.table"]), try XCTUnwrap(emissions["note.paperTrail"]))

        game.narrativeCampaign.exploration.positionX = 0
        game.narrativeCampaign.exploration.positionZ = -1.45
        XCTAssertTrue(game.interactNarrativeHotspot())
        game.advanceNarrative("inspectFold")
        coordinator.update(game: game)

        opacities = coordinator.noteTraceHotspotOpacities
        XCTAssertGreaterThan(try XCTUnwrap(opacities["note.paperTrail"]), try XCTUnwrap(opacities["note.table"]))

        game.developerJump(to: .noteTrace, momentIndex: 2)
        coordinator.update(game: game)
        opacities = coordinator.noteTraceHotspotOpacities
        XCTAssertGreaterThan(try XCTUnwrap(opacities["companion.zhou"]), try XCTUnwrap(opacities["note.table"]))
        XCTAssertGreaterThan(try XCTUnwrap(opacities["companion.xu"]), try XCTUnwrap(opacities["note.table"]))

        game.narrativeCampaign.exploration.positionX = 1.8
        game.narrativeCampaign.exploration.positionZ = 0.25
        XCTAssertTrue(game.interactNarrativeHotspot())
        coordinator.update(game: game)
        opacities = coordinator.noteTraceHotspotOpacities
        XCTAssertGreaterThan(try XCTUnwrap(opacities["note.paperTrail"]), try XCTUnwrap(opacities["companion.xu"]))
    }

    func testChapterThreeNavigationPulseRendersInWorldDirection() throws {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        let coordinator = ClassroomCoordinator()
        game.developerJump(to: .noteTrace, momentIndex: 0)
        game.narrativeCampaign.exploration.positionX = -2.4
        game.narrativeCampaign.exploration.positionZ = 1.2
        coordinator.update(game: game)

        let cue = try XCTUnwrap(ChapterThreeNavigationCue.derive(from: game.narrativeCampaign))
        XCTAssertEqual(cue.headingText, "向右后方靠近")
        XCTAssertGreaterThan(try XCTUnwrap(coordinator.noteTraceNavigationRigOpacity), 0.34)
        let distantBeamOpacity = try XCTUnwrap(coordinator.noteTraceNavigationBeamOpacity)
        XCTAssertGreaterThan(distantBeamOpacity, 0.38)
        XCTAssertGreaterThan(try XCTUnwrap(coordinator.noteTraceNavigationBeamLength), 3.1)
        XCTAssertGreaterThan(try XCTUnwrap(coordinator.noteTraceNavigationBeamAngle), 0.6)
        XCTAssertGreaterThan(try XCTUnwrap(coordinator.noteTraceNavigationTargetRingOpacity), 0.45)

        game.narrativeCampaign.exploration.positionX = 0
        game.narrativeCampaign.exploration.positionZ = -1.45
        coordinator.update(game: game)
        XCTAssertLessThan(try XCTUnwrap(coordinator.noteTraceNavigationBeamOpacity), distantBeamOpacity)
        XCTAssertEqual(try XCTUnwrap(coordinator.noteTraceNavigationTargetRingOpacity), 0.86, accuracy: 0.02)

        if let path = ProcessInfo.processInfo.environment["CAPTURE_NOTE_TRACE_NAVIGATION_PULSE_STAGE"] {
            game.narrativeCampaign.exploration.positionX = -2.4
            game.narrativeCampaign.exploration.positionZ = 1.2
            coordinator.update(game: game)
            let image = coordinator.renderSnapshot(size: CGSize(width: 960, height: 600))
            let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
            var cyanSamples = 0
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                    if color.blueComponent > 0.54,
                       color.greenComponent > 0.44,
                       color.redComponent < 0.42,
                       color.blueComponent > color.redComponent + 0.16 {
                        cyanSamples += 1
                    }
                }
            }
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
            XCTAssertGreaterThan(cyanSamples, 240)
            XCTAssertGreaterThan(png.count, 20_000)
        }
    }

    func testPhysicalCompanionChoiceFollowsAndRebuildsAcrossChapters() throws {
        let game = GameManager()
        let coordinator = ClassroomCoordinator()
        game.developerJump(to: .noteTrace, momentIndex: 2)
        game.narrativeCampaign.exploration.positionX = -1.8
        game.narrativeCampaign.exploration.positionZ = 0.25

        XCTAssertEqual(game.nearbyNarrativeHotspot?.choiceID, "zhou")
        XCTAssertTrue(game.interactNarrativeHotspot())
        XCTAssertEqual(game.narrativeCampaign.companionID, "周予安")
        XCTAssertEqual(game.narrativeCampaign.currentMoment.id, "3.door")
        XCTAssertTrue(game.developerPlaytestLog.contains("COMPANION companion.zhou"))

        game.advanceNarrative("xu")
        XCTAssertEqual(game.narrativeCampaign.companionID, "周予安", "同伴选择写入后不可更改")

        coordinator.update(game: game)
        XCTAssertEqual(coordinator.activeNarrativeCompanionName, "companionZhou")
        let followingPosition = try XCTUnwrap(coordinator.activeNarrativeCompanionPosition)
        XCTAssertEqual(followingPosition.z, 1.75, accuracy: 0.001)

        game.advanceNarrative("openDoor")
        XCTAssertEqual(game.narrativeCampaign.chapter, .noteTrace)
        game.narrativeCampaign.exploration.positionX = -0.2
        game.narrativeCampaign.exploration.positionZ = 1.5
        XCTAssertEqual(game.nearbyNarrativeHotspot?.id, "note.paperTrail")
        XCTAssertTrue(game.interactNarrativeHotspot())
        game.advanceNarrative("openDoor")
        coordinator.update(game: game)
        XCTAssertEqual(game.narrativeCampaign.chapter, .stairwell)
        XCTAssertEqual(coordinator.activeNarrativeCompanionName, "companionZhou")
        let stairwellPosition = try XCTUnwrap(coordinator.activeNarrativeCompanionPosition)
        XCTAssertEqual(stairwellPosition.x, -2.25, accuracy: 0.001)
        XCTAssertEqual(stairwellPosition.z, 3.45, accuracy: 0.001)
    }

    func testCompanionProximityStageShowsFollowLineAndBoundaryRing() throws {
        let game = GameManager()
        let coordinator = ClassroomCoordinator()
        game.developerJump(to: .noteTrace, momentIndex: 2)
        game.narrativeCampaign.exploration.positionX = 1.8
        game.narrativeCampaign.exploration.positionZ = 0.25

        XCTAssertEqual(game.nearbyNarrativeHotspot?.choiceID, "xu")
        XCTAssertTrue(game.interactNarrativeHotspot())
        coordinator.update(game: game)

        XCTAssertEqual(coordinator.activeNarrativeCompanionName, "companionXu")
        XCTAssertGreaterThan(try XCTUnwrap(coordinator.activeNarrativeCompanionFollowLineOpacity), 0.25)
        XCTAssertEqual(try XCTUnwrap(coordinator.activeNarrativeCompanionFollowLineLength), 1.5, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(coordinator.activeNarrativeCompanionBoundaryRingOpacity), 0, accuracy: 0.001)

        game.advanceNarrative("openDoor")
        game.narrativeCampaign.exploration.positionX = -0.2
        game.narrativeCampaign.exploration.positionZ = 1.5
        XCTAssertTrue(game.interactNarrativeHotspot())
        game.advanceNarrative("openDoor")
        coordinator.update(game: game)

        XCTAssertEqual(game.narrativeCampaign.chapter, .stairwell)
        XCTAssertEqual(try XCTUnwrap(coordinator.activeNarrativeCompanionFollowLineOpacity), 0, accuracy: 0.001)
        XCTAssertGreaterThan(try XCTUnwrap(coordinator.activeNarrativeCompanionBoundaryRingOpacity), 0.18)

        game.developerJump(to: .counseling, momentIndex: 1)
        game.narrativeCampaign.companionID = "许栀"
        game.narrativeCampaign.counselingState = NarrativeCounselingState(entryMode: .standardWaiting)
        coordinator.update(game: game)

        XCTAssertEqual(game.narrativeCampaign.currentMoment.id, "5.rumor")
        XCTAssertGreaterThan(try XCTUnwrap(coordinator.activeNarrativeCompanionBoundaryRingOpacity), 0.48)
        XCTAssertTrue(coordinator.activeNarrativeCompanionPrivacyShieldVisible)

        if let path = ProcessInfo.processInfo.environment["CAPTURE_COMPANION_PROXIMITY_STAGE_VIEW"] {
            let image = coordinator.renderSnapshot(size: CGSize(width: 960, height: 600))
            let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try FileManager.default.createDirectory(atPath: URL(fileURLWithPath: path).deletingLastPathComponent().path, withIntermediateDirectories: true)
            try png.write(to: URL(fileURLWithPath: path))
            XCTAssertGreaterThan(png.count, 20_000)
        }
    }

    func testMirrorDialogueCarryoverPullsChapterThreeCompanionCloserInScene() throws {
        let baselineGame = GameManager(userDefaults: isolatedUserDefaults())
        let baselineCoordinator = ClassroomCoordinator()
        baselineGame.developerJump(to: .noteTrace, momentIndex: 2)
        baselineGame.narrativeCampaign.companionID = "许栀"
        baselineGame.narrativeCampaign.exploration.positionX = 1.8
        baselineGame.narrativeCampaign.exploration.positionZ = 0.25
        baselineCoordinator.update(game: baselineGame)

        let carryoverGame = GameManager(userDefaults: isolatedUserDefaults())
        let carryoverCoordinator = ClassroomCoordinator()
        carryoverGame.developerJump(to: .mirror, momentIndex: 4)
        carryoverGame.narrativeCampaign.exploration.interactionCount = 1
        carryoverGame.advanceNarrative("invite")
        carryoverGame.narrativeCampaign.momentIndex = 2
        carryoverGame.narrativeCampaign.companionID = "许栀"
        carryoverGame.narrativeCampaign.exploration.positionX = 1.8
        carryoverGame.narrativeCampaign.exploration.positionZ = 0.25
        carryoverCoordinator.update(game: carryoverGame)

        XCTAssertEqual(try XCTUnwrap(baselineCoordinator.activeNarrativeCompanionFollowLineLength), 1.5, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(carryoverCoordinator.activeNarrativeCompanionFollowLineLength), 1.32, accuracy: 0.02)
        XCTAssertGreaterThan(
            try XCTUnwrap(carryoverCoordinator.activeNarrativeCompanionGazeOpacity),
            try XCTUnwrap(baselineCoordinator.activeNarrativeCompanionGazeOpacity)
        )
    }

    func testCompanionPresenceStatusPersistsFromChoiceThroughStairwellAndCounseling() {
        let game = GameManager()
        game.developerJump(to: .noteTrace, momentIndex: 2)
        XCTAssertNil(game.narrativeCampaign.companionPresenceStatus)

        game.narrativeCampaign.exploration.positionX = 1.8
        game.narrativeCampaign.exploration.positionZ = 0.25
        XCTAssertTrue(game.interactNarrativeHotspot())

        var status = game.narrativeCampaign.companionPresenceStatus
        XCTAssertEqual(status?.companionID, "许栀")
        XCTAssertEqual(status?.mode, .following)
        XCTAssertTrue(status?.detail.contains("可见距离") == true)

        game.advanceNarrative("openDoor")
        XCTAssertEqual(game.narrativeCampaign.chapter, .noteTrace)
        game.narrativeCampaign.exploration.positionX = -0.2
        game.narrativeCampaign.exploration.positionZ = 1.5
        XCTAssertTrue(game.interactNarrativeHotspot())
        game.advanceNarrative("openDoor")
        status = game.narrativeCampaign.companionPresenceStatus
        XCTAssertEqual(status?.mode, .boundary)
        XCTAssertTrue(status?.title.contains("角落") == true)

        game.developerJump(to: .stairwell, momentIndex: 3)
        game.narrativeCampaign.companionID = "许栀"
        status = game.narrativeCampaign.companionPresenceStatus
        XCTAssertEqual(status?.mode, .contactingAdult)
        XCTAssertEqual(status?.symbol, "message.badge.filled.fill")

        game.developerJump(to: .counseling)
        game.narrativeCampaign.companionID = "许栀"
        status = game.narrativeCampaign.companionPresenceStatus
        XCTAssertEqual(game.narrativeCampaign.chapter, .counseling)
        XCTAssertEqual(status?.mode, .waiting)

        game.developerJump(to: .counseling, momentIndex: 1)
        game.narrativeCampaign.companionID = "许栀"
        status = game.narrativeCampaign.companionPresenceStatus
        XCTAssertEqual(status?.mode, .privacyGuard)
        XCTAssertTrue(status?.detail.contains("不说出江越") == true)
    }

    func testCompanionStatusIconRendersBottomRightPresence() throws {
        let game = GameManager()
        game.developerJump(to: .noteTrace, momentIndex: 3)
        game.narrativeCampaign.companionID = "许栀"
        game.narrativeCampaign.exploration.positionX = -2.4
        game.narrativeCampaign.exploration.positionZ = -0.6
        XCTAssertTrue(game.narrativeCampaign.companionPresenceStatus?.navigationLine?.contains("门轴声") == true)

        let renderer = ImageRenderer(content: NarrativeCampaignView(game: game)
            .environmentObject(game)
            .frame(width: 960, height: 540))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 960, height: 540)

        guard let image = renderer.nsImage else {
            XCTFail("NarrativeCampaignView companion status did not render")
            return
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        var minimum = 1.0
        var maximum = 0.0
        var visibleSamples = 0
        for y in stride(from: bitmap.pixelsHigh / 2, to: bitmap.pixelsHigh - 8, by: 18) {
            for x in stride(from: bitmap.pixelsWide / 2, to: bitmap.pixelsWide - 8, by: 18) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                minimum = min(minimum, luminance)
                maximum = max(maximum, luminance)
                if luminance > 0.04 { visibleSamples += 1 }
            }
        }
        XCTAssertGreaterThan(visibleSamples, 45)
        XCTAssertGreaterThan(maximum - minimum, 0.12)

        if let path = ProcessInfo.processInfo.environment["CAPTURE_COMPANION_STATUS_VIEW"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }
    }

    func testNarrativeRouteRailRendersVisibleSixChapterHUD() throws {
        var campaign = NarrativeCampaign(isActive: true, chapter: .stairwell, momentIndex: 2)
        campaign.clueCount = 4
        campaign.companionID = "许栀"
        campaign.selfCared = true
        campaign.privacyProtected = false
        campaign.sharedSelf = false
        campaign.safetyHandoffState = NarrativeSafetyHandoffState(
            authoredRisk: .high,
            riskAsked: true,
            adultContactInitiated: true,
            contactMethod: "消息",
            safetyHandoffComplete: true,
            route: .urgentSchoolResponse,
            entryMode: .urgentHandoffWaiting,
            resolutionPath: .voluntary
        )

        let renderer = ImageRenderer(content: ZStack {
            Color.black
            NarrativeRouteRailView(campaign: campaign)
                .padding(16)
                .frame(width: 900)
                .background(.black.opacity(0.54), in: RoundedRectangle(cornerRadius: 12))
                .background(campaign.chapter.atmosphere.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.18), lineWidth: 1))
                .padding(24)
        }
        .frame(width: 960, height: 220))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 960, height: 220)

        guard let image = renderer.nsImage else {
            XCTFail("NarrativeRouteRailView did not render")
            return
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        var minimum = 1.0
        var maximum = 0.0
        var visibleSamples = 0
        for y in stride(from: 8, to: bitmap.pixelsHigh, by: 14) {
            for x in stride(from: 8, to: bitmap.pixelsWide, by: 18) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                minimum = min(minimum, luminance)
                maximum = max(maximum, luminance)
                if luminance > 0.04 { visibleSamples += 1 }
            }
        }

        XCTAssertGreaterThan(visibleSamples, 110)
        XCTAssertGreaterThan(maximum - minimum, 0.12)

        if let path = ProcessInfo.processInfo.environment["CAPTURE_ROUTE_RAIL_VIEW"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }
    }

    func testNarrativeIntegrationMatrixViewRendersSixteenScenarioGrid() throws {
        let renderer = ImageRenderer(content: ZStack {
            Color.black
            NarrativeIntegrationMatrixView(results: NarrativeIntegrationMatrix.results)
                .padding(24)
        }
        .frame(width: 900, height: 560))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 900, height: 560)

        guard let image = renderer.nsImage else {
            XCTFail("NarrativeIntegrationMatrixView did not render")
            return
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        var minimum = 1.0
        var maximum = 0.0
        var visibleSamples = 0
        var coloredSamples = 0
        for y in stride(from: 10, to: bitmap.pixelsHigh, by: 14) {
            for x in stride(from: 10, to: bitmap.pixelsWide, by: 16) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                minimum = min(minimum, luminance)
                maximum = max(maximum, luminance)
                if luminance > 0.04 { visibleSamples += 1 }
                let channelSpread = max(color.redComponent, color.greenComponent, color.blueComponent)
                    - min(color.redComponent, color.greenComponent, color.blueComponent)
                if luminance > 0.035, channelSpread > 0.045 {
                    coloredSamples += 1
                }
            }
        }

        XCTAssertEqual(NarrativeIntegrationMatrix.results.count, 16)
        XCTAssertEqual(NarrativeIntegrationMatrix.passingCount, 16)
        XCTAssertGreaterThan(visibleSamples, 260)
        XCTAssertGreaterThan(coloredSamples, 20)
        XCTAssertGreaterThan(maximum - minimum, 0.14)

        if let path = ProcessInfo.processInfo.environment["CAPTURE_INTEGRATION_MATRIX_VIEW"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }
    }

    func testCampaignDossierViewRendersSixChapterArchive() throws {
        var campaign = NarrativeCampaign(isActive: true, isComplete: true, chapter: .epilogue)
        campaign.clueCount = 5
        campaign.companionID = "许栀"
        campaign.safetyRoute = NarrativeSafetyRoute.standardCounseling.displayName
        campaign.privacyProtected = true
        campaign.selfCared = true
        campaign.sharedSelf = true
        campaign.safetyHandoffState = NarrativeSafetyHandoffState(
            authoredRisk: .moderate,
            riskAsked: true,
            adultContactInitiated: true,
            contactMethod: "消息",
            safetyHandoffComplete: true,
            route: .standardCounseling,
            entryMode: .standardWaiting,
            resolutionPath: .voluntary
        )
        campaign.counselingState = NarrativeCounselingState(
            entryMode: .standardWaiting,
            handoffSceneStarted: true,
            boundaryHeld: true,
            rumorHandled: true,
            rumorOutcome: .suppressed,
            companionMessageReplied: true,
            handoffConfirmed: true,
            supportHandedOff: true
        )
        campaign.jiangDialogueState = NarrativeJiangDialogueState(
            segmentIndex: 3,
            responseKinds: [.listening, .accompanying, .silentPresence],
            listenPhaseComplete: true,
            educationCardDismissed: true,
            riskAskMethod: .gentle,
            disclosedRisk: .confirmed
        )

        let renderer = ImageRenderer(content: ZStack {
            Color.black
            CampaignDossierView(campaign: campaign)
                .padding(24)
        }
        .frame(width: 760, height: 520))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 760, height: 520)

        guard let image = renderer.nsImage else {
            XCTFail("CampaignDossierView did not render")
            return
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        var minimum = 1.0
        var maximum = 0.0
        var visibleSamples = 0
        var coloredSamples = 0
        for y in stride(from: 10, to: bitmap.pixelsHigh, by: 14) {
            for x in stride(from: 10, to: bitmap.pixelsWide, by: 16) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                let spread = max(color.redComponent, color.greenComponent, color.blueComponent)
                    - min(color.redComponent, color.greenComponent, color.blueComponent)
                minimum = min(minimum, luminance)
                maximum = max(maximum, luminance)
                if luminance > 0.04 { visibleSamples += 1 }
                if luminance > 0.035, spread > 0.045 { coloredSamples += 1 }
            }
        }

        let dossier = NarrativeCampaignDossier.make(for: campaign)
        XCTAssertEqual(dossier.chapterCards.count, 6)
        XCTAssertTrue(dossier.isCoherent)
        XCTAssertGreaterThan(visibleSamples, 190)
        XCTAssertGreaterThan(coloredSamples, 18)
        XCTAssertGreaterThan(maximum - minimum, 0.13)

        if let path = ProcessInfo.processInfo.environment["CAPTURE_CAMPAIGN_DOSSIER_VIEW"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }
    }

    func testAutonomousRouteAuditViewRendersMultipleRouteResults() throws {
        let results = AutonomousRouteAuditor.runAll()
        let renderer = ImageRenderer(content: ZStack {
            Color.black
            AutonomousRouteAuditView(results: results)
                .padding(24)
        }
        .frame(width: 760, height: 420))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 760, height: 420)

        guard let image = renderer.nsImage else {
            XCTFail("AutonomousRouteAuditView did not render")
            return
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        var minimum = 1.0
        var maximum = 0.0
        var visibleSamples = 0
        var coloredSamples = 0
        for y in stride(from: 10, to: bitmap.pixelsHigh, by: 14) {
            for x in stride(from: 10, to: bitmap.pixelsWide, by: 16) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                let spread = max(color.redComponent, color.greenComponent, color.blueComponent)
                    - min(color.redComponent, color.greenComponent, color.blueComponent)
                minimum = min(minimum, luminance)
                maximum = max(maximum, luminance)
                if luminance > 0.04 { visibleSamples += 1 }
                if luminance > 0.035, spread > 0.045 { coloredSamples += 1 }
            }
        }

        XCTAssertEqual(results.count, 4)
        XCTAssertTrue(results.allSatisfy(\.isPassing))
        XCTAssertGreaterThan(visibleSamples, 140)
        XCTAssertGreaterThan(coloredSamples, 16)
        XCTAssertGreaterThan(maximum - minimum, 0.13)

        if let path = ProcessInfo.processInfo.environment["CAPTURE_AUTONOMOUS_ROUTE_AUDIT_VIEW"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }
    }

    func testPhysicalSafetyHandoffAndCounselingInteractionsDriveSceneActors() throws {
        let game = GameManager()
        let coordinator = ClassroomCoordinator()
        func capture(_ name: String) throws -> Data {
            let image = coordinator.renderSnapshot(size: CGSize(width: 960, height: 600))
            let tiff = try XCTUnwrap(image.tiffRepresentation)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            if let directory = ProcessInfo.processInfo.environment["CAPTURE_NARRATIVE_DIR"] {
                try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
                try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
            }
            return png
        }
        game.developerJump(to: .stairwell, momentIndex: 3)
        game.narrativeCampaign.exploration.positionX = -2.25
        game.narrativeCampaign.exploration.positionZ = 3.45

        coordinator.update(game: game)
        XCTAssertFalse(coordinator.narrativeTeacherVisible)
        XCTAssertEqual(game.nearbyNarrativeHotspot?.choiceID, "contactAdult")
        XCTAssertTrue(game.interactNarrativeHotspot())
        XCTAssertEqual(game.narrativeCampaign.currentMoment.id, "4.handoff")

        coordinator.update(game: game)
        XCTAssertTrue(coordinator.narrativeTeacherVisible)
        XCTAssertGreaterThan(try capture("safety-handoff").count, 20_000)
        game.advanceNarrative("followAdultPlan")
        XCTAssertEqual(game.narrativeCampaign.currentMoment.id, "4.handoff", "未走到成人身边时不得完成交接")
        game.narrativeCampaign.exploration.positionX = -1.15
        game.narrativeCampaign.exploration.positionZ = 0.1
        XCTAssertEqual(game.nearbyNarrativeHotspot?.id, "handoff.teacher")
        XCTAssertTrue(game.interactNarrativeHotspot())
        game.advanceNarrative("followAdultPlan")
        XCTAssertEqual(game.narrativeCampaign.chapter, .counseling)
        XCTAssertEqual(game.narrativeCampaign.counselingState?.entryMode, .standardWaiting)

        game.narrativeCampaign.exploration.positionX = 0
        game.narrativeCampaign.exploration.positionZ = 0.45
        XCTAssertTrue(game.interactNarrativeHotspot(), "进入新场景后先确认等候椅")
        game.advanceNarrative("wait")
        game.narrativeCampaign.exploration.positionX = 0
        game.narrativeCampaign.exploration.positionZ = 4
        coordinator.update(game: game)
        XCTAssertEqual(game.narrativeCampaign.currentMoment.id, "5.rumor")
        XCTAssertEqual(coordinator.visibleNarrativeRumorNPCCount, 2)
        XCTAssertGreaterThan(try capture("counseling-rumor").count, 20_000)
        game.narrativeCampaign.counselingState?.entryMode = .emergencyClosure
        coordinator.update(game: game)
        XCTAssertEqual(coordinator.visibleNarrativeRumorNPCCount, 0, "应急收束入口不得生成流言 NPC")
        game.narrativeCampaign.counselingState?.entryMode = .standardWaiting
        coordinator.update(game: game)
        XCTAssertEqual(coordinator.visibleNarrativeRumorNPCCount, 2)

        game.narrativeCampaign.exploration.positionX = -2.45
        game.narrativeCampaign.exploration.positionZ = 1.35
        XCTAssertTrue(game.interactNarrativeHotspot())
        coordinator.update(game: game)
        XCTAssertEqual(game.narrativeCampaign.currentMoment.id, "5.message")
        XCTAssertEqual(coordinator.visibleNarrativeRumorNPCCount, 0)
        XCTAssertTrue(coordinator.narrativeMessagePhoneVisible)
        game.narrativeCampaign.exploration.positionX = 0
        game.narrativeCampaign.exploration.positionZ = 2.5
        coordinator.update(game: game)
        XCTAssertGreaterThan(try capture("counseling-message").count, 20_000)

        game.narrativeCampaign.exploration.positionX = 0
        game.narrativeCampaign.exploration.positionZ = 0.45
        XCTAssertTrue(game.interactNarrativeHotspot())
        XCTAssertEqual(game.narrativeCampaign.chapter, .epilogue)
        XCTAssertTrue(game.narrativeCampaign.counselingState?.supportHandedOff == true)
        XCTAssertTrue(game.narrativeCampaign.privacyProtected)
    }

    func testNarrativeActorPerformanceRelaxesWhenAdultHandoffIsComplete() throws {
        let game = GameManager()
        let coordinator = ClassroomCoordinator()
        game.developerJump(to: .stairwell)
        coordinator.update(game: game)

        let tenseShoulder = try XCTUnwrap(coordinator.narrativeJiangShoulderTilt)
        let tenseBreath = try XCTUnwrap(coordinator.narrativeJiangBreathOpacity)
        XCTAssertFalse(coordinator.narrativeTeacherVisible)

        game.narrativeCampaign.jiangYueTrust = 64
        game.narrativeCampaign.safetyHandoffState = NarrativeSafetyHandoffState(
            authoredRisk: .moderate,
            riskAsked: true,
            adultContactInitiated: true,
            contactMethod: "电话",
            safetyHandoffComplete: true,
            route: .standardCounseling,
            entryMode: .standardWaiting,
            resolutionPath: .voluntary
        )
        coordinator.update(game: game)

        XCTAssertTrue(coordinator.narrativeTeacherVisible)
        XCTAssertGreaterThan(try XCTUnwrap(coordinator.narrativeTeacherGazeOpacity), 0.6)
        XCTAssertGreaterThan(try XCTUnwrap(coordinator.narrativeJiangShoulderTilt), tenseShoulder)
        XCTAssertLessThan(try XCTUnwrap(coordinator.narrativeJiangBreathOpacity), tenseBreath)

        if let directory = ProcessInfo.processInfo.environment["CAPTURE_PERFORMANCE_VIEW"] {
            let image = coordinator.renderSnapshot(size: CGSize(width: 960, height: 600))
            let tiff = try XCTUnwrap(image.tiffRepresentation)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try FileManager.default.createDirectory(atPath: URL(fileURLWithPath: directory).deletingLastPathComponent().path, withIntermediateDirectories: true)
            try png.write(to: URL(fileURLWithPath: directory))
            XCTAssertGreaterThan(png.count, 20_000)
        }
    }

    func testCompanionPerformanceShowsPrivacyGuardDuringCounselingRumorMoment() throws {
        let game = GameManager()
        let coordinator = ClassroomCoordinator()
        game.developerJump(to: .counseling)
        game.narrativeCampaign.companionID = "许栀"
        coordinator.update(game: game)

        XCTAssertEqual(coordinator.activeNarrativeCompanionName, "companionXu")
        XCTAssertFalse(coordinator.activeNarrativeCompanionPrivacyShieldVisible)

        game.narrativeCampaign.momentIndex = 1
        game.narrativeCampaign.counselingState = NarrativeCounselingState(entryMode: .standardWaiting)
        coordinator.update(game: game)

        XCTAssertEqual(game.narrativeCampaign.currentMoment.id, "5.rumor")
        XCTAssertTrue(coordinator.activeNarrativeCompanionPrivacyShieldVisible)
        XCTAssertGreaterThan(try XCTUnwrap(coordinator.activeNarrativeCompanionGazeOpacity), 0.5)
    }

    func testNarrativeWorldDirectorMapsRumorPressureIntoVisibleStageSignals() throws {
        let game = GameManager()
        let coordinator = ClassroomCoordinator()
        game.developerJump(to: .counseling)
        game.narrativeCampaign.companionID = "周予安"
        game.narrativeCampaign.momentIndex = 1
        game.narrativeCampaign.counselingState = NarrativeCounselingState(entryMode: .standardWaiting)
        coordinator.update(game: game)

        let rumorPressure = try XCTUnwrap(coordinator.narrativeWorldPressureOpacity)
        let rumorPrivacy = try XCTUnwrap(coordinator.narrativeWorldPrivacyOpacity)
        let rumorSupport = try XCTUnwrap(coordinator.narrativeWorldSupportOpacity)

        XCTAssertEqual(game.narrativeCampaign.worldDirectorSignal.cue, .privacy)
        XCTAssertEqual(coordinator.visibleNarrativeWorldWitnessCount, 5)
        XCTAssertGreaterThan(rumorPressure, 0.4)
        XCTAssertGreaterThan(rumorPrivacy, 0.7)

        game.narrativeCampaign.counselingState?.rumorHandled = true
        game.narrativeCampaign.counselingState?.companionMessageReplied = true
        game.narrativeCampaign.counselingState?.handoffConfirmed = true
        game.narrativeCampaign.counselingState?.supportHandedOff = true
        game.narrativeCampaign.momentIndex = 2
        coordinator.update(game: game)

        XCTAssertEqual(game.narrativeCampaign.worldDirectorSignal.cue, .support)
        XCTAssertLessThan(coordinator.visibleNarrativeWorldWitnessCount, 5)
        XCTAssertLessThan(try XCTUnwrap(coordinator.narrativeWorldPressureOpacity), rumorPressure)
        XCTAssertGreaterThan(try XCTUnwrap(coordinator.narrativeWorldSupportOpacity), rumorSupport)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(coordinator.narrativeWorldSafetyOpacity), 0.4)

        if let directory = ProcessInfo.processInfo.environment["CAPTURE_WORLD_DIRECTOR_VIEW"] {
            let image = coordinator.renderSnapshot(size: CGSize(width: 960, height: 600))
            let tiff = try XCTUnwrap(image.tiffRepresentation)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try FileManager.default.createDirectory(atPath: URL(fileURLWithPath: directory).deletingLastPathComponent().path, withIntermediateDirectories: true)
            try png.write(to: URL(fileURLWithPath: directory))
            XCTAssertGreaterThan(png.count, 20_000)
        }
    }

    func testNarrativeAmbientActorsReblockFromRumorToSupportHandoff() throws {
        let game = GameManager()
        let coordinator = ClassroomCoordinator()
        game.developerJump(to: .counseling)
        game.narrativeCampaign.companionID = "许栀"
        game.narrativeCampaign.momentIndex = 1
        game.narrativeCampaign.counselingState = NarrativeCounselingState(entryMode: .standardWaiting)
        coordinator.update(game: game)

        let rumorPositions = coordinator.narrativeAmbientActorPositions

        XCTAssertEqual(game.narrativeCampaign.ambientActorDirectives.map(\.role), [.bystander, .bystander, .boundaryKeeper])
        XCTAssertEqual(coordinator.visibleNarrativeAmbientActorCount, 3)
        XCTAssertEqual(rumorPositions.count, 3)
        XCTAssertLessThan(rumorPositions[0].x, -1.8)

        game.narrativeCampaign.counselingState?.rumorHandled = true
        game.narrativeCampaign.counselingState?.companionMessageReplied = true
        game.narrativeCampaign.counselingState?.handoffConfirmed = true
        game.narrativeCampaign.counselingState?.supportHandedOff = true
        game.narrativeCampaign.momentIndex = 2
        coordinator.update(game: game)

        let supportPositions = coordinator.narrativeAmbientActorPositions

        XCTAssertEqual(game.narrativeCampaign.ambientActorDirectives.map(\.role), [.facilitator, .quietWitness])
        XCTAssertEqual(coordinator.visibleNarrativeAmbientActorCount, 2)
        XCTAssertEqual(supportPositions.count, 2)
        XCTAssertNotEqual(supportPositions[0].x, rumorPositions[0].x, accuracy: 0.01)
        XCTAssertLessThan(supportPositions[0].z, rumorPositions[0].z)

        if let directory = ProcessInfo.processInfo.environment["CAPTURE_AMBIENT_ACTORS_VIEW"] {
            let image = coordinator.renderSnapshot(size: CGSize(width: 960, height: 600))
            let tiff = try XCTUnwrap(image.tiffRepresentation)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try FileManager.default.createDirectory(atPath: URL(fileURLWithPath: directory).deletingLastPathComponent().path, withIntermediateDirectories: true)
            try png.write(to: URL(fileURLWithPath: directory))
            XCTAssertGreaterThan(png.count, 20_000)
        }
    }

    func testEpilogueConsequenceEchoesLightStageFromCampaignMemory() throws {
        let game = GameManager()
        let coordinator = ClassroomCoordinator()
        game.developerJump(to: .epilogue, momentIndex: 2)
        game.narrativeCampaign.clueCount = 5
        game.narrativeCampaign.companionID = "周予安"
        game.narrativeCampaign.selfCared = true
        game.narrativeCampaign.sharedSelf = true
        game.narrativeCampaign.privacyProtected = true
        game.narrativeCampaign.jiangDialogueState = NarrativeJiangDialogueState(
            segmentIndex: 3,
            responseKinds: [.listening, .accompanying],
            consecutiveTimeouts: 0,
            listenPhaseComplete: true,
            educationCardDismissed: true,
            riskAskMethod: .direct,
            disclosedRisk: .confirmed
        )
        game.narrativeCampaign.safetyHandoffState = NarrativeSafetyHandoffState(
            authoredRisk: .high,
            riskAsked: true,
            adultContactInitiated: true,
            contactMethod: "电话",
            safetyHandoffComplete: true,
            route: .urgentSchoolResponse,
            entryMode: .urgentHandoffWaiting,
            resolutionPath: .voluntary
        )
        game.narrativeCampaign.safetyRoute = NarrativeSafetyRoute.urgentSchoolResponse.displayName
        game.narrativeCampaign.counselingState = NarrativeCounselingState(
            entryMode: .urgentHandoffWaiting,
            handoffSceneStarted: true,
            boundaryHeld: true,
            rumorHandled: true,
            rumorOutcome: .suppressed,
            companionMessageReplied: true,
            handoffConfirmed: true,
            supportHandedOff: true
        )
        coordinator.update(game: game)

        XCTAssertEqual(game.narrativeCampaign.consequenceEchoes.count, 6)
        XCTAssertEqual(coordinator.visibleNarrativeConsequenceEchoCount, 6)
        XCTAssertEqual(coordinator.narrativeConsequenceEchoOpacities.count, 6)
        XCTAssertGreaterThan(try XCTUnwrap(coordinator.narrativeConsequenceEchoOpacities.max()), 0.85)

        game.narrativeCampaign.selfCared = false
        coordinator.update(game: game)

        let opacitiesAfterSelfCareLoss = coordinator.narrativeConsequenceEchoOpacities
        XCTAssertEqual(opacitiesAfterSelfCareLoss.count, 6)
        XCTAssertLessThan(opacitiesAfterSelfCareLoss[4], 0.6)

        if let directory = ProcessInfo.processInfo.environment["CAPTURE_CONSEQUENCE_ECHO_VIEW"] {
            let image = coordinator.renderSnapshot(size: CGSize(width: 960, height: 600))
            let tiff = try XCTUnwrap(image.tiffRepresentation)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try FileManager.default.createDirectory(atPath: URL(fileURLWithPath: directory).deletingLastPathComponent().path, withIntermediateDirectories: true)
            try png.write(to: URL(fileURLWithPath: directory))
            XCTAssertGreaterThan(png.count, 20_000)
        }
    }

    func testEpilogueChapterMemoryBeaconsReflectSixChapterRouteMarkers() throws {
        let game = GameManager()
        let coordinator = ClassroomCoordinator()
        game.developerJump(to: .epilogue, momentIndex: 2)
        game.narrativeCampaign.clueCount = 5
        game.narrativeCampaign.companionID = "许栀"
        game.narrativeCampaign.selfCared = true
        game.narrativeCampaign.sharedSelf = true
        game.narrativeCampaign.privacyProtected = true
        game.narrativeCampaign.safetyHandoffState = NarrativeSafetyHandoffState(
            authoredRisk: .high,
            riskAsked: true,
            adultContactInitiated: true,
            contactMethod: "消息",
            safetyHandoffComplete: true,
            route: .urgentSchoolResponse,
            entryMode: .urgentHandoffWaiting,
            resolutionPath: .voluntary
        )
        game.narrativeCampaign.safetyRoute = NarrativeSafetyRoute.urgentSchoolResponse.displayName
        coordinator.update(game: game)

        let brightOpacities = coordinator.narrativeChapterMemoryBeaconOpacities

        XCTAssertEqual(coordinator.visibleNarrativeChapterMemoryBeaconCount, 6)
        XCTAssertEqual(brightOpacities.count, 6)
        XCTAssertEqual(coordinator.narrativeChapterMemoryLineOpacities.count, 5)
        XCTAssertGreaterThan(try XCTUnwrap(brightOpacities.max()), 0.84)
        XCTAssertGreaterThan(try XCTUnwrap(coordinator.narrativeChapterMemoryLineOpacities.max()), 0.45)

        game.narrativeCampaign.sharedSelf = false
        coordinator.update(game: game)

        let quietOpacities = coordinator.narrativeChapterMemoryBeaconOpacities
        XCTAssertEqual(quietOpacities.count, 6)
        XCTAssertLessThan(quietOpacities[5], brightOpacities[5])

        if let directory = ProcessInfo.processInfo.environment["CAPTURE_CHAPTER_MEMORY_VIEW"] {
            let image = coordinator.renderSnapshot(size: CGSize(width: 960, height: 600))
            let tiff = try XCTUnwrap(image.tiffRepresentation)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try FileManager.default.createDirectory(atPath: URL(fileURLWithPath: directory).deletingLastPathComponent().path, withIntermediateDirectories: true)
            try png.write(to: URL(fileURLWithPath: directory))
            XCTAssertGreaterThan(png.count, 20_000)
        }
    }

    func testJiangDialoguePerformanceBeatsTrackResponseQuality() {
        var campaign = NarrativeCampaign(isActive: true, chapter: .stairwell, momentIndex: 1)
        campaign.prepareRuntimeStateForCurrentChapter()

        XCTAssertEqual(campaign.currentMoment.id, "4.listen.0")
        campaign.choose("dialogue.listen")
        XCTAssertEqual(campaign.currentJiangDialoguePerformanceBeat, .reflectiveListening)
        XCTAssertGreaterThan(campaign.jiangDialoguePerformanceSupport, 0.6)
        XCTAssertEqual(campaign.jiangDialoguePerformanceRupture, 0)

        campaign.choose("dialogue.inspire")
        XCTAssertEqual(campaign.currentJiangDialoguePerformanceBeat, .thinEncouragement)
        XCTAssertGreaterThan(campaign.jiangDialoguePerformanceRupture, 0.2)
        XCTAssertEqual(campaign.jiangDialogueState?.performanceBeats, [.reflectiveListening, .thinEncouragement])
        XCTAssertEqual(campaign.jiangDialogueState?.responseKinds, [.listening, .inspirational])
    }

    func testJiangDialogueEmbodiedCueKeepsTrustInvisible() {
        let supportiveCue = NarrativeJiangEmbodiedCue.derive(beat: .reflectiveListening)
        let ruptureCue = NarrativeJiangEmbodiedCue.derive(beat: .rupture)
        let timeoutCue = NarrativeJiangEmbodiedCue.derive(beat: .patientSilence, consecutiveTimeouts: 2)

        XCTAssertTrue(supportiveCue.title.contains("听见"))
        XCTAssertTrue(supportiveCue.postureLine.contains("肩"))
        XCTAssertTrue(supportiveCue.voiceLine.contains("句"))
        XCTAssertTrue(ruptureCue.postureLine.contains("脚"))
        XCTAssertTrue(timeoutCue.nextPrompt.contains("连续沉默"))

        let visibleText = [
            supportiveCue.title,
            supportiveCue.postureLine,
            supportiveCue.voiceLine,
            supportiveCue.boundaryLine,
            supportiveCue.nextPrompt,
            ruptureCue.title,
            ruptureCue.postureLine,
            ruptureCue.voiceLine,
            ruptureCue.boundaryLine,
            ruptureCue.nextPrompt,
            timeoutCue.title,
            timeoutCue.postureLine,
            timeoutCue.voiceLine,
            timeoutCue.boundaryLine,
            timeoutCue.nextPrompt
        ].joined(separator: " ")

        XCTAssertFalse(visibleText.contains { character in
            character.unicodeScalars.contains { scalar in
                scalar.value >= 48 && scalar.value <= 57
            }
        })
        for forbidden in ["信任", "进度", "承接", "收紧", "%"] {
            XCTAssertFalse(visibleText.contains(forbidden), "Embodied cue should not expose metric term: \(forbidden)")
        }
    }

    func testJiangDialogueEmbodiedCueViewRendersWithoutMetricBars() throws {
        let cue = NarrativeJiangEmbodiedCue.derive(beat: .reflectiveListening)
        XCTAssertEqual(JiangDialogueEmbodiedCueView.minimumHeight, 154)

        let renderer = ImageRenderer(content: ZStack {
            Color(red: 0.04, green: 0.05, blue: 0.06)
            JiangDialogueEmbodiedCueView(cue: cue)
                .frame(width: 620)
                .padding(22)
        }
        .frame(width: 700, height: 260))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 700, height: 260)

        guard let image = renderer.nsImage else {
            return XCTFail("JiangDialogueEmbodiedCueView did not render")
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))

        var visibleSamples = 0
        var textLikeSamples = 0
        var orangeSamples = 0
        var maximum = 0.0
        var minimum = 1.0
        for y in stride(from: 8, to: bitmap.pixelsHigh, by: 12) {
            for x in stride(from: 8, to: bitmap.pixelsWide, by: 12) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                minimum = min(minimum, luminance)
                maximum = max(maximum, luminance)
                if luminance > 0.055 { visibleSamples += 1 }
                if color.redComponent > 0.72, color.greenComponent > 0.72, color.blueComponent > 0.72 { textLikeSamples += 1 }
                if color.redComponent > 0.72, color.greenComponent > 0.28, color.greenComponent < 0.64, color.blueComponent < 0.24 {
                    orangeSamples += 1
                }
            }
        }

        XCTAssertGreaterThan(visibleSamples, 48)
        XCTAssertGreaterThan(textLikeSamples, 6)
        XCTAssertGreaterThan(maximum - minimum, 0.18)
        XCTAssertLessThan(orangeSamples, 2)

        if let path = ProcessInfo.processInfo.environment["CAPTURE_JIANG_EMBODIED_CUE_VIEW"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }
    }

    func testSafetyHandoffBriefingDerivesAdultRouteWithoutStudentDiagnosis() throws {
        var campaign = NarrativeCampaign(isActive: true, chapter: .mirror, momentIndex: 4, linCheTrust: 3)
        campaign.choose("invite")
        campaign.chapter = .stairwell
        campaign.momentIndex = 4
        campaign.companionID = "许栀"
        campaign.jiangYueTrust = 8
        campaign.jiangDialogueState = NarrativeJiangDialogueState(
            segmentIndex: 3,
            responseKinds: [.judgmental, .inspirational, .timeout, .advisory],
            listenPhaseComplete: true,
            educationCardDismissed: true,
            riskAskMethod: .deferToAdult,
            disclosedRisk: .unknown
        )
        campaign.safetyHandoffState = NarrativeSafetyHandoffState(
            authoredRisk: .high,
            riskAsked: false,
            adultContactInitiated: true,
            contactMethod: "消息",
            safetyHandoffComplete: false,
            route: nil,
            entryMode: nil,
            resolutionPath: .adultCameAfterUnclearDisclosure
        )

        var briefing = try XCTUnwrap(NarrativeSafetyHandoffBriefing(campaign: campaign))
        XCTAssertEqual(briefing.routeTitle, NarrativeSafetyRoute.urgentSchoolResponse.displayName)
        XCTAssertTrue(briefing.isHighPriority)
        XCTAssertFalse(briefing.teacherReachedJiang)
        XCTAssertEqual(briefing.steps.map(\.state), [.complete, .current, .pending, .pending])
        XCTAssertTrue(briefing.contactLine.contains("许栀"))
        XCTAssertTrue(briefing.contactLine.contains("消息"))
        XCTAssertTrue(briefing.routeLine.contains("校内紧急支持"))
        XCTAssertTrue(briefing.entryLine.contains("紧急交接等候区"))
        XCTAssertTrue(briefing.supportLine?.contains("成人支持") == true)
        XCTAssertTrue(briefing.studentBoundaryLine.contains("不评估风险"))

        let visibleText = [
            briefing.contactLine,
            briefing.adultArrivalLine,
            briefing.routeTitle,
            briefing.routeLine,
            briefing.entryLine,
            briefing.supportLine ?? "",
            briefing.studentBoundaryLine
        ].joined(separator: " ")
        for forbidden in ["信任", "披露", "伤害自己的打算", "谁告诉", "诊断"] {
            XCTAssertFalse(visibleText.contains(forbidden), "Handoff briefing should avoid leaking F-16 or clinical wording: \(forbidden)")
        }

        campaign.exploration.lastInteractedHotspot = "handoff.teacher"
        briefing = try XCTUnwrap(NarrativeSafetyHandoffBriefing(campaign: campaign))
        XCTAssertTrue(briefing.teacherReachedJiang)
        XCTAssertTrue(briefing.adultArrivalLine.contains("已经来到江越所在的平台"))
        XCTAssertEqual(briefing.steps.map(\.state), [.complete, .complete, .current, .current])

        campaign.safetyHandoffState?.safetyHandoffComplete = true
        campaign.safetyHandoffState?.route = .urgentSchoolResponse
        campaign.safetyHandoffState?.entryMode = .urgentHandoffWaiting
        briefing = try XCTUnwrap(NarrativeSafetyHandoffBriefing(campaign: campaign))
        XCTAssertEqual(briefing.steps.map(\.state), [.complete, .complete, .complete, .complete])
    }

    func testSafetyHandoffBriefingViewRendersAdultArrivalRoute() throws {
        var campaign = NarrativeCampaign(isActive: true, chapter: .mirror, momentIndex: 4, linCheTrust: 3)
        campaign.choose("invite")
        campaign.chapter = .stairwell
        campaign.momentIndex = 4
        campaign.companionID = "周予安"
        campaign.exploration.lastInteractedHotspot = "handoff.teacher"
        campaign.safetyHandoffState = NarrativeSafetyHandoffState(
            authoredRisk: .imminent,
            riskAsked: true,
            adultContactInitiated: true,
            contactMethod: "电话",
            safetyHandoffComplete: false,
            route: nil,
            entryMode: nil,
            resolutionPath: .voluntary
        )
        let briefing = try XCTUnwrap(NarrativeSafetyHandoffBriefing(campaign: campaign))
        XCTAssertTrue(briefing.supportLine?.contains("成人支持") == true)
        XCTAssertEqual(SafetyHandoffBriefingView.minimumHeight, 226)

        let renderer = ImageRenderer(content: ZStack {
            Color(red: 0.04, green: 0.05, blue: 0.06)
            SafetyHandoffBriefingView(briefing: briefing)
                .frame(width: 620)
                .padding(22)
        }
        .frame(width: 720, height: 350))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 720, height: 350)

        guard let image = renderer.nsImage else {
            return XCTFail("SafetyHandoffBriefingView did not render")
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))

        var visibleSamples = 0
        var textLikeSamples = 0
        var orangeSamples = 0
        var maximum = 0.0
        var minimum = 1.0
        for y in stride(from: 8, to: bitmap.pixelsHigh, by: 12) {
            for x in stride(from: 8, to: bitmap.pixelsWide, by: 12) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                minimum = min(minimum, luminance)
                maximum = max(maximum, luminance)
                if luminance > 0.055 { visibleSamples += 1 }
                if color.redComponent > 0.72, color.greenComponent > 0.72, color.blueComponent > 0.72 { textLikeSamples += 1 }
                if color.redComponent > 0.72, color.greenComponent > 0.28, color.greenComponent < 0.66, color.blueComponent < 0.30 {
                    orangeSamples += 1
                }
            }
        }

        XCTAssertGreaterThan(visibleSamples, 60)
        XCTAssertGreaterThan(textLikeSamples, 8)
        XCTAssertGreaterThan(maximum - minimum, 0.18)
        XCTAssertGreaterThan(orangeSamples, 1)

        if let path = ProcessInfo.processInfo.environment["CAPTURE_SAFETY_HANDOFF_BRIEFING_VIEW"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }
        if let path = ProcessInfo.processInfo.environment["CAPTURE_SAFETY_HANDOFF_CARRYOVER_VIEW"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }
    }

    func testCounselingWaitingStatusPreservesEntryPrivacyAndBiasCap() throws {
        var urgent = NarrativeCampaign(isActive: true, chapter: .mirror, momentIndex: 4, linCheTrust: 3)
        urgent.choose("invite")
        urgent.chapter = .counseling
        urgent.momentIndex = 1
        urgent.privacyProtected = true
        urgent.companionID = "周予安"
        urgent.counselingState = NarrativeCounselingState(
            entryMode: .urgentHandoffWaiting,
            handoffSceneStarted: true,
            boundaryHeld: true,
            rumorHandled: true,
            rumorOutcome: .suppressed,
            companionMessageReplied: false,
            handoffConfirmed: false,
            supportHandedOff: false
        )

        let urgentStatus = try XCTUnwrap(NarrativeCounselingWaitingStatus(campaign: urgent))
        XCTAssertEqual(urgentStatus.entryTitle, "紧急交接等候区")
        XCTAssertFalse(urgentStatus.isEmergency)
        XCTAssertTrue(urgentStatus.entryLine.contains("支持室外"))
        XCTAssertTrue(urgentStatus.boundaryLine.contains("不能进入"))
        XCTAssertTrue(urgentStatus.rumorLine.contains("隐私边界"))
        XCTAssertTrue(urgentStatus.companionLine.contains("回复只传递陪伴"))
        XCTAssertTrue(urgentStatus.supportLine?.contains("第五章") == true)
        XCTAssertTrue(urgent.companionPresenceStatus?.detail.contains("第五章") == true)
        XCTAssertLessThanOrEqual(urgentStatus.biasCards.count, NarrativeCounselingWaitingStatus.maxBiasCards)
        XCTAssertEqual(urgentStatus.biasCards.count, 2)

        let visibleText = [
            urgentStatus.entryLine,
            urgentStatus.boundaryLine,
            urgentStatus.rumorLine,
            urgentStatus.companionLine,
            urgentStatus.supportLine ?? "",
            urgentStatus.handoffLine
        ].joined(separator: " ") + urgentStatus.biasCards.map(\.line).joined(separator: " ")
        for forbidden in ["江越怎么了", "咨询内容", "门内说了", "位置在", "诊断"] {
            XCTAssertFalse(visibleText.contains(forbidden), "Waiting status should not leak private detail: \(forbidden)")
        }

        var emergency = urgent
        emergency.counselingState = NarrativeCounselingState(
            entryMode: .emergencyClosure,
            handoffSceneStarted: true,
            boundaryHeld: true,
            rumorHandled: true,
            rumorOutcome: .contained,
            companionMessageReplied: true,
            handoffConfirmed: true,
            supportHandedOff: true
        )
        let emergencyStatus = try XCTUnwrap(NarrativeCounselingWaitingStatus(campaign: emergency))
        XCTAssertTrue(emergencyStatus.isEmergency)
        XCTAssertEqual(emergencyStatus.entryTitle, "成人确认后的安全收束")
        XCTAssertTrue(emergencyStatus.entryLine.contains("江越不再出镜"))
        XCTAssertTrue(emergencyStatus.rumorLine.contains("未生成围观流言"))
        XCTAssertTrue(emergencyStatus.handoffLine.contains("成人交接已确认"))
    }

    func testCounselingWaitingStatusViewRendersPrivacyAndBiasCards() throws {
        var campaign = NarrativeCampaign(isActive: true, chapter: .mirror, momentIndex: 4, linCheTrust: 3)
        campaign.choose("invite")
        campaign.chapter = .counseling
        campaign.momentIndex = 1
        campaign.counselingState = NarrativeCounselingState(
            entryMode: .standardWaiting,
            handoffSceneStarted: true,
            boundaryHeld: true,
            rumorHandled: true,
            rumorOutcome: .suppressed,
            companionMessageReplied: false,
            handoffConfirmed: false,
            supportHandedOff: false
        )
        let status = try XCTUnwrap(NarrativeCounselingWaitingStatus(campaign: campaign))
        XCTAssertTrue(status.supportLine?.contains("第五章") == true)
        XCTAssertEqual(CounselingWaitingStatusView.minimumHeight, 206)

        let renderer = ImageRenderer(content: ZStack {
            Color(red: 0.04, green: 0.05, blue: 0.06)
            CounselingWaitingStatusView(status: status)
                .frame(width: 620)
                .padding(22)
        }
        .frame(width: 740, height: 390))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 740, height: 390)

        guard let image = renderer.nsImage else {
            return XCTFail("CounselingWaitingStatusView did not render")
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))

        var visibleSamples = 0
        var textLikeSamples = 0
        var yellowSamples = 0
        var mintSamples = 0
        var maximum = 0.0
        var minimum = 1.0
        for y in stride(from: 8, to: bitmap.pixelsHigh, by: 12) {
            for x in stride(from: 8, to: bitmap.pixelsWide, by: 12) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                minimum = min(minimum, luminance)
                maximum = max(maximum, luminance)
                if luminance > 0.055 { visibleSamples += 1 }
                if color.redComponent > 0.72, color.greenComponent > 0.72, color.blueComponent > 0.72 { textLikeSamples += 1 }
                if color.redComponent > 0.55, color.greenComponent > 0.45, color.blueComponent < 0.46 { yellowSamples += 1 }
                if color.greenComponent > 0.56, color.blueComponent > 0.40, color.redComponent < 0.42 { mintSamples += 1 }
            }
        }

        XCTAssertGreaterThan(visibleSamples, 80)
        XCTAssertGreaterThan(textLikeSamples, 10)
        XCTAssertGreaterThan(maximum - minimum, 0.18)
        XCTAssertGreaterThan(yellowSamples, 2)
        XCTAssertGreaterThan(mintSamples, 1)

        if let path = ProcessInfo.processInfo.environment["CAPTURE_COUNSELING_WAITING_STATUS_VIEW"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }
        if let path = ProcessInfo.processInfo.environment["CAPTURE_COUNSELING_WAITING_CARRYOVER_VIEW"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }
    }

    func testJiangDialoguePerformancePanelRendersVisibleFeedback() throws {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.developerJump(to: .stairwell, momentIndex: 1)
        game.narrativeCampaign.choose("dialogue.listen")

        let renderer = ImageRenderer(content: NarrativeCampaignView(game: game)
            .frame(width: 980, height: 620))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 980, height: 620)

        guard let image = renderer.nsImage else {
            return XCTFail("NarrativeCampaignView did not render")
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        var visibleSamples = 0
        var maximum = 0.0
        var minimum = 1.0
        for y in stride(from: 12, to: bitmap.pixelsHigh, by: 26) {
            for x in stride(from: 12, to: bitmap.pixelsWide, by: 26) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                minimum = min(minimum, luminance)
                maximum = max(maximum, luminance)
                if luminance > 0.02 { visibleSamples += 1 }
            }
        }

        XCTAssertGreaterThan(visibleSamples, 120)
        XCTAssertGreaterThan(maximum - minimum, 0.16)

        if let path = ProcessInfo.processInfo.environment["CAPTURE_JIANG_DIALOGUE_PERFORMANCE_VIEW"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }
    }

    func testNarrativeChoiceSignalPreviewRendersChoiceConsequences() throws {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.developerJump(to: .stairwell, momentIndex: 1)
        let moment = game.narrativeCampaign.currentMoment
        let supportiveChoice = try XCTUnwrap(moment.choices.first { $0.id == "dialogue.listen" })
        let riskyChoice = try XCTUnwrap(moment.choices.first { $0.id == "dialogue.advise" })

        XCTAssertTrue(
            NarrativeChoiceSignalModel.signals(
                for: supportiveChoice,
                moment: moment,
                campaign: game.narrativeCampaign
            ).map(\.id).contains("support")
        )
        XCTAssertTrue(
            NarrativeChoiceSignalModel.signals(
                for: riskyChoice,
                moment: moment,
                campaign: game.narrativeCampaign
            ).map(\.id).contains("risk")
        )

        let renderer = ImageRenderer(content: NarrativeCampaignView(game: game)
            .frame(width: 980, height: 920))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 980, height: 920)

        guard let image = renderer.nsImage else {
            return XCTFail("NarrativeCampaignView did not render")
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        var visibleSamples = 0
        var textLikeSamples = 0
        var accentSamples = 0
        var maximum = 0.0
        var minimum = 1.0
        for y in stride(from: 12, to: bitmap.pixelsHigh, by: 18) {
            for x in stride(from: 12, to: bitmap.pixelsWide, by: 18) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                minimum = min(minimum, luminance)
                maximum = max(maximum, luminance)
                if luminance > 0.035 { visibleSamples += 1 }
                if color.redComponent > 0.72, color.greenComponent > 0.72, color.blueComponent > 0.72 { textLikeSamples += 1 }
                if color.redComponent > 0.34, color.greenComponent > 0.25, color.blueComponent < 0.24 { accentSamples += 1 }
            }
        }

        XCTAssertGreaterThan(visibleSamples, 160)
        XCTAssertGreaterThan(textLikeSamples, 16)
        XCTAssertGreaterThan(accentSamples, 8)
        XCTAssertGreaterThan(maximum - minimum, 0.16)

        if let path = ProcessInfo.processInfo.environment["CAPTURE_NARRATIVE_CHOICE_SIGNAL_PREVIEW_VIEW"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }
    }

    func testNarrativeChoiceImpactBannerPersistsAndRendersImmediateFeedback() throws {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.developerJump(to: .stairwell, momentIndex: 1)
        let sourceMomentID = game.narrativeCampaign.currentMoment.id

        game.narrativeCampaign.choose("dialogue.advise")

        let impact = try XCTUnwrap(game.narrativeCampaign.activeChoiceImpact)
        XCTAssertEqual(impact.sourceMomentID, sourceMomentID)
        XCTAssertTrue(impact.signalIDs.contains("risk"))
        XCTAssertTrue(impact.title.contains("绷紧"))
        XCTAssertNotEqual(game.narrativeCampaign.currentMoment.id, sourceMomentID)

        let data = try JSONEncoder().encode(game.narrativeCampaign)
        let restored = try JSONDecoder().decode(NarrativeCampaign.self, from: data)
        XCTAssertEqual(restored.lastChoiceImpact, game.narrativeCampaign.lastChoiceImpact)
        XCTAssertEqual(restored.activeChoiceImpact?.signalIDs, impact.signalIDs)

        let renderer = ImageRenderer(content: NarrativeCampaignView(game: game)
            .frame(width: 980, height: 920))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 980, height: 920)

        guard let image = renderer.nsImage else {
            return XCTFail("NarrativeCampaignView did not render choice impact banner")
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        var visibleSamples = 0
        var textLikeSamples = 0
        var orangeSamples = 0
        var maximum = 0.0
        var minimum = 1.0
        for y in stride(from: 12, to: bitmap.pixelsHigh, by: 18) {
            for x in stride(from: 12, to: bitmap.pixelsWide, by: 18) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                minimum = min(minimum, luminance)
                maximum = max(maximum, luminance)
                if luminance > 0.035 { visibleSamples += 1 }
                if color.redComponent > 0.72, color.greenComponent > 0.72, color.blueComponent > 0.72 { textLikeSamples += 1 }
                if color.redComponent > 0.42, color.greenComponent > 0.22, color.blueComponent < 0.20 { orangeSamples += 1 }
            }
        }

        XCTAssertGreaterThan(visibleSamples, 170)
        XCTAssertGreaterThan(textLikeSamples, 16)
        XCTAssertGreaterThan(orangeSamples, 10)
        XCTAssertGreaterThan(maximum - minimum, 0.16)

        if let path = ProcessInfo.processInfo.environment["CAPTURE_NARRATIVE_CHOICE_IMPACT_BANNER_VIEW"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }
    }

    func testMirrorDialogueConsequenceViewRendersAfterListenChoice() throws {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.developerJump(to: .mirror, momentIndex: 4)
        game.narrativeCampaign.exploration.interactionCount = 1
        game.advanceNarrative("invite")

        let consequence = MirrorDialogueConsequenceModel.derive(from: game.narrativeCampaign)
        XCTAssertTrue(consequence.isActive)
        XCTAssertEqual(consequence.choiceID, "invite")
        XCTAssertTrue(consequence.nextChapterHint.contains("成人支持"))

        let renderer = ImageRenderer(content: NarrativeCampaignView(game: game)
            .frame(width: 980, height: 920))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 980, height: 920)

        guard let image = renderer.nsImage else {
            return XCTFail("NarrativeCampaignView did not render mirror dialogue consequence")
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        var visibleSamples = 0
        var textLikeSamples = 0
        var panelSamples = 0
        var maximum = 0.0
        var minimum = 1.0
        for y in stride(from: 12, to: bitmap.pixelsHigh, by: 18) {
            for x in stride(from: 12, to: bitmap.pixelsWide, by: 18) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                minimum = min(minimum, luminance)
                maximum = max(maximum, luminance)
                if luminance > 0.035 { visibleSamples += 1 }
                if color.redComponent > 0.72, color.greenComponent > 0.72, color.blueComponent > 0.72 { textLikeSamples += 1 }
                if color.greenComponent > 0.24, color.blueComponent > 0.24, color.redComponent < 0.34 { panelSamples += 1 }
            }
        }

        XCTAssertGreaterThan(visibleSamples, 170)
        XCTAssertGreaterThan(textLikeSamples, 18)
        XCTAssertGreaterThan(panelSamples, 14)
        XCTAssertGreaterThan(maximum - minimum, 0.16)

        if let path = ProcessInfo.processInfo.environment["CAPTURE_MIRROR_DIALOGUE_CONSEQUENCE_VIEW"],
           let png = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
        }
    }

    func testJiangDialoguePerformanceStageShowsSupportAndRuptureDifferently() throws {
        let supportiveGame = GameManager(userDefaults: isolatedUserDefaults())
        let supportiveCoordinator = ClassroomCoordinator()
        supportiveGame.developerJump(to: .stairwell, momentIndex: 1)
        supportiveGame.narrativeCampaign.choose("dialogue.listen")
        supportiveCoordinator.update(game: supportiveGame)

        let ruptureGame = GameManager(userDefaults: isolatedUserDefaults())
        let ruptureCoordinator = ClassroomCoordinator()
        ruptureGame.developerJump(to: .stairwell, momentIndex: 1)
        ruptureGame.narrativeCampaign.choose("dialogue.advise")
        ruptureCoordinator.update(game: ruptureGame)

        XCTAssertGreaterThan(
            try XCTUnwrap(supportiveCoordinator.narrativeJiangDialogueSupportOpacity),
            try XCTUnwrap(ruptureCoordinator.narrativeJiangDialogueSupportOpacity)
        )
        XCTAssertGreaterThan(
            try XCTUnwrap(supportiveCoordinator.narrativeJiangDialogueAnchorOpacity),
            try XCTUnwrap(ruptureCoordinator.narrativeJiangDialogueAnchorOpacity)
        )
        XCTAssertGreaterThan(
            try XCTUnwrap(ruptureCoordinator.narrativeJiangDialogueRuptureOpacity),
            try XCTUnwrap(supportiveCoordinator.narrativeJiangDialogueRuptureOpacity)
        )

        let supportiveImage = supportiveCoordinator.renderSnapshot(size: CGSize(width: 960, height: 600))
        let ruptureImage = ruptureCoordinator.renderSnapshot(size: CGSize(width: 960, height: 600))
        let supportiveBitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(supportiveImage.tiffRepresentation)))
        let ruptureBitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(ruptureImage.tiffRepresentation)))
        let supportivePng = try XCTUnwrap(supportiveBitmap.representation(using: .png, properties: [:]))
        let rupturePng = try XCTUnwrap(ruptureBitmap.representation(using: .png, properties: [:]))
        XCTAssertNotEqual(supportivePng, rupturePng)
    }

    func testNarrativeChoiceImpactShapesWorldDirectorStageSignals() throws {
        let supportiveGame = GameManager(userDefaults: isolatedUserDefaults())
        let supportiveCoordinator = ClassroomCoordinator()
        supportiveGame.developerJump(to: .stairwell, momentIndex: 1)
        supportiveGame.narrativeCampaign.choose("dialogue.listen")
        supportiveCoordinator.update(game: supportiveGame)

        let ruptureGame = GameManager(userDefaults: isolatedUserDefaults())
        let ruptureCoordinator = ClassroomCoordinator()
        ruptureGame.developerJump(to: .stairwell, momentIndex: 1)
        ruptureGame.narrativeCampaign.choose("dialogue.advise")
        ruptureCoordinator.update(game: ruptureGame)

        XCTAssertEqual(supportiveGame.narrativeCampaign.worldDirectorSignal.cue, .support)
        XCTAssertEqual(ruptureGame.narrativeCampaign.worldDirectorSignal.cue, .risk)
        XCTAssertGreaterThan(
            try XCTUnwrap(supportiveCoordinator.narrativeWorldSupportOpacity),
            try XCTUnwrap(ruptureCoordinator.narrativeWorldSupportOpacity)
        )
        XCTAssertGreaterThan(
            try XCTUnwrap(ruptureCoordinator.narrativeWorldPressureOpacity),
            try XCTUnwrap(supportiveCoordinator.narrativeWorldPressureOpacity)
        )
        XCTAssertGreaterThan(try XCTUnwrap(supportiveCoordinator.narrativeWorldChoiceImpactRingOpacity), 0.48)
        XCTAssertGreaterThan(try XCTUnwrap(ruptureCoordinator.narrativeWorldChoiceImpactRingOpacity), 0.48)
        XCTAssertGreaterThan(try XCTUnwrap(supportiveCoordinator.narrativeWorldChoiceImpactCrownOpacity), 0.52)
        XCTAssertGreaterThan(try XCTUnwrap(ruptureCoordinator.narrativeWorldChoiceImpactCrownOpacity), 0.52)
        XCTAssertNotEqual(
            try XCTUnwrap(supportiveCoordinator.narrativeWorldChoiceImpactRayAngle),
            try XCTUnwrap(ruptureCoordinator.narrativeWorldChoiceImpactRayAngle),
            accuracy: 0.01
        )
        XCTAssertGreaterThan(try XCTUnwrap(ruptureCoordinator.narrativeWorldChoiceImpactRayOpacity), 0.42)
        XCTAssertGreaterThanOrEqual(ruptureCoordinator.visibleNarrativeWorldWitnessCount, supportiveCoordinator.visibleNarrativeWorldWitnessCount)

        if let path = ProcessInfo.processInfo.environment["CAPTURE_CHOICE_IMPACT_STAGE_VIEW"] {
            let image = ruptureCoordinator.renderSnapshot(size: CGSize(width: 960, height: 600))
            let tiff = try XCTUnwrap(image.tiffRepresentation)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
            XCTAssertGreaterThan(png.count, 20_000)
        }
    }

    func testCounselingDoorDwellPullsPlayerBackAndPreservesPrivacyBoundary() throws {
        let game = GameManager()
        let coordinator = ClassroomCoordinator()
        game.developerJump(to: .counseling)
        coordinator.update(game: game)
        let idleIntensity = try XCTUnwrap(coordinator.narrativeBoundaryLineIntensity)

        game.narrativeCampaign.exploration.positionX = 0
        game.narrativeCampaign.exploration.positionZ = -2.3
        for _ in 0..<59 {
            game.tickNarrativeExploration(deltaTime: 0.05)
        }
        coordinator.update(game: game)

        XCTAssertEqual(game.narrativeBoundaryPullbackCount, 0)
        XCTAssertEqual(game.narrativeCampaign.exploration.positionZ, -2.3, accuracy: 0.001)
        XCTAssertGreaterThan(game.narrativeBoundaryDwellProgress, 0.95)
        XCTAssertGreaterThan(try XCTUnwrap(coordinator.narrativeBoundaryLineIntensity), idleIntensity)

        if let directory = ProcessInfo.processInfo.environment["CAPTURE_NARRATIVE_DIR"] {
            let image = coordinator.renderSnapshot(size: CGSize(width: 960, height: 600))
            let tiff = try XCTUnwrap(image.tiffRepresentation)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("counseling-boundary.png"))
        }

        game.tickNarrativeExploration(deltaTime: 0.05)
        game.tickNarrativeExploration(deltaTime: 0.05)

        XCTAssertEqual(game.narrativeBoundaryPullbackCount, 1)
        XCTAssertEqual(game.narrativeCampaign.exploration.positionZ, -1.2, accuracy: 0.001)
        XCTAssertTrue(game.narrativeCampaign.counselingState?.boundaryHeld == true)
        XCTAssertTrue(game.message.contains("退回等候区"))
        XCTAssertTrue(game.developerPlaytestLog.contains("BOUNDARY counseling.pullback"))
    }

    func testEmergencyCounselingEntryBlocksDoorWithoutPrivacyPullbackBeat() {
        let game = GameManager()
        game.developerJump(to: .counseling)
        game.narrativeCampaign.counselingState?.entryMode = .emergencyClosure
        game.narrativeCampaign.exploration.positionX = 0
        game.narrativeCampaign.exploration.positionZ = -4

        for _ in 0..<80 {
            game.tickNarrativeExploration(deltaTime: 0.05)
        }

        XCTAssertEqual(game.narrativeCampaign.exploration.positionZ, -2.3, accuracy: 0.001)
        XCTAssertEqual(game.narrativeBoundaryDwellSeconds, 0, accuracy: 0.001)
        XCTAssertEqual(game.narrativeBoundaryPullbackCount, 0)
    }

    func testNarrativeFallbackClockAdvancesStalledPlayerWithoutSkippingEarly() {
        let game = GameManager()
        game.developerJump(to: .noteTrace, momentIndex: 2)

        for _ in 0..<899 {
            game.tickNarrativeExploration(deltaTime: 0.1)
        }
        XCTAssertEqual(game.narrativeCampaign.currentMoment.id, "3.companion")
        XCTAssertTrue(game.narrativeCampaign.companionID.isEmpty)

        game.tickNarrativeExploration(deltaTime: 0.1)
        game.tickNarrativeExploration(deltaTime: 0.1)

        XCTAssertEqual(game.narrativeCampaign.companionID, "周予安")
        XCTAssertEqual(game.narrativeCampaign.currentMoment.id, "3.door")
        XCTAssertEqual(game.developerPlaytestLog.filter { $0 == "FALLBACK 3.companion -> zhou" }.count, 1)
    }

    func testTimedAdultContactAndRumorFallbackUseNormalStateMachineCommits() {
        let game = GameManager()
        game.developerJump(to: .stairwell, momentIndex: 3)

        for _ in 0..<301 {
            game.tickNarrativeExploration(deltaTime: 0.1)
        }
        XCTAssertEqual(game.narrativeCampaign.currentMoment.id, "4.handoff")
        XCTAssertTrue(game.narrativeCampaign.safetyHandoffState?.adultContactInitiated == true)
        XCTAssertEqual(game.narrativeCampaign.safetyHandoffState?.contactMethod, "电话")

        game.developerJump(to: .counseling, momentIndex: 1)
        for _ in 0..<201 {
            game.tickNarrativeExploration(deltaTime: 0.1)
        }
        XCTAssertEqual(game.narrativeCampaign.currentMoment.id, "5.message")
        XCTAssertEqual(game.narrativeCampaign.counselingState?.rumorOutcome, .contained)
        XCTAssertTrue(game.narrativeCampaign.counselingState?.rumorHandled == true)
        XCTAssertTrue(game.narrativeCampaign.privacyProtected)
    }

    func testCompanionsUseVisiblyDifferentAdultContactActions() throws {
        var frames: [Data] = []
        for (companion, expectedMethod, expectedX, expectedY) in [
            ("周予安", "电话", 0.23, 1.38),
            ("许栀", "消息", 0.0, 1.02)
        ] {
            let game = GameManager()
            let coordinator = ClassroomCoordinator()
            game.developerJump(to: .stairwell, momentIndex: 3)
            game.narrativeCampaign.companionID = companion
            game.narrativeCampaign.exploration.positionX = companion == "周予安" ? -2.25 : 2.75
            game.narrativeCampaign.exploration.positionZ = companion == "周予安" ? 3.45 : -0.35
            XCTAssertEqual(game.nearbyNarrativeHotspot?.choiceID, "contactAdult")
            XCTAssertTrue(game.interactNarrativeHotspot())
            coordinator.update(game: game)

            XCTAssertEqual(game.narrativeCampaign.safetyHandoffState?.contactMethod, expectedMethod)
            let propPosition = try XCTUnwrap(coordinator.activeNarrativeCompanionContactPropPosition)
            XCTAssertEqual(propPosition.x, expectedX, accuracy: 0.001)
            XCTAssertEqual(propPosition.y, expectedY, accuracy: 0.001)

            let image = coordinator.renderSnapshot(size: CGSize(width: 960, height: 600))
            let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            XCTAssertGreaterThan(png.count, 20_000)
            frames.append(png)
        }
        XCTAssertEqual(Set(frames.map(\.hashValue)).count, 2)
    }

    func testEmergencyCounselingRouteContainsRumorImmediatelyWithoutNPCEvent() {
        let game = GameManager()
        let coordinator = ClassroomCoordinator()
        game.developerJump(to: .counseling, momentIndex: 1)
        game.narrativeCampaign.counselingState?.entryMode = .emergencyClosure
        coordinator.update(game: game)
        XCTAssertEqual(coordinator.visibleNarrativeRumorNPCCount, 0)

        game.tickNarrativeExploration(deltaTime: 0.1)

        XCTAssertEqual(game.narrativeCampaign.currentMoment.id, "5.message")
        XCTAssertEqual(game.narrativeCampaign.counselingState?.rumorOutcome, .contained)
        XCTAssertTrue(game.message.contains("不要在群里讨论"))
    }

    func testDeveloperAutoplayCompletesTheRealCampaignStateMachine() async {
        let game = GameManager()
        game.startDeveloperAutoplay(stepDelay: .zero)

        for _ in 0..<3000 where game.narrativeCampaign.isComplete == false || game.developerPlaytestStatus == "运行中" {
            try? await Task.sleep(for: .milliseconds(1))
        }

        XCTAssertTrue(game.narrativeCampaign.isComplete)
        XCTAssertTrue(game.narrativeCampaign.isActive)
        XCTAssertEqual(game.narrativeCampaign.chapter, .epilogue)
        XCTAssertFalse(game.narrativeCampaign.companionID.isEmpty)
        XCTAssertFalse(game.narrativeCampaign.safetyRoute.isEmpty)
        XCTAssertEqual(game.developerPlaytestStatus, "通过：六章完成")
        XCTAssertTrue(game.developerPlaytestLog.last?.contains("complete=true") == true)
        XCTAssertGreaterThanOrEqual(game.developerPlaytestLog.filter { $0.hasPrefix("EXPLORE ") }.count, 5)
        XCTAssertEqual(game.developerPlaytestLog.filter { $0.hasPrefix("COMPANION ") }.count, 1)
        XCTAssertGreaterThanOrEqual(game.developerPlaytestLog.filter { $0.hasPrefix("ACTION ") }.count, 3)
        XCTAssertTrue(game.developerPlaytestLog.contains("ACTION mirror.light.trace"))
        XCTAssertTrue(game.developerPlaytestLog.contains("ACTION mirror.light.melody"))
        XCTAssertTrue(game.developerPlaytestLog.contains("ACTION mirror.light.erase"))
    }

    func testSelfRegulationAndOrdinaryActionsStayAvailableDuringClueSteps() {
        let game = GameManager()
        game.startGame()

        for action in [PlayerAction.study, .phone, .note, .talk, .breathe, .window, .drink, .snack] {
            XCTAssertTrue(game.chapterOneAvailableActions.contains(action), "\(action.rawValue) should remain available")
        }
        XCTAssertFalse(game.chapterOneAvailableActions.contains(.leaveSeat))

        game.execute(.breathe)
        XCTAssertEqual(game.chapterOneStep, .observeLinChe)
    }

    func testContinuousLookDoesNotSnapToPoseCenter() {
        let game = makePlayingGame()

        game.rotateStudentView(deltaX: -50, deltaY: 0)
        XCTAssertEqual(game.cameraPose, .forward)
        XCTAssertEqual(game.studentLookYaw, 0.3, accuracy: 0.0001)

        game.rotateStudentView(deltaX: -30, deltaY: 0)
        XCTAssertEqual(game.cameraPose, .left)
        XCTAssertEqual(game.studentLookYaw, 0.48, accuracy: 0.0001)

        game.rotateStudentView(deltaX: -10, deltaY: 0)
        XCTAssertEqual(game.cameraPose, .left)
        XCTAssertEqual(game.studentLookYaw, 0.54, accuracy: 0.0001)
    }

    func testMovementUsesFacingDirectionForForwardAndStrafe() {
        let game = makeRoamingGame(yaw: 0)

        game.moveStudentFreeRoam(forward: 1, strafe: 0, deltaTime: 0.1)
        XCTAssertEqual(game.freeRoam.positionX, 5, accuracy: 0.0001)
        XCTAssertLessThan(game.freeRoam.positionZ, 0)

        game.freeRoam.positionX = 5
        game.freeRoam.positionZ = 0
        game.freeRoam.yaw = .pi / 2
        game.moveStudentFreeRoam(forward: 1, strafe: 0, deltaTime: 0.1)
        XCTAssertLessThan(game.freeRoam.positionX, 5)
        XCTAssertEqual(game.freeRoam.positionZ, 0, accuracy: 0.0001)

        game.freeRoam.positionX = 5
        game.freeRoam.positionZ = 0
        game.moveStudentFreeRoam(forward: 0, strafe: 1, deltaTime: 0.1)
        XCTAssertEqual(game.freeRoam.positionX, 5, accuracy: 0.0001)
        XCTAssertLessThan(game.freeRoam.positionZ, 0)
    }

    func testDiagonalMovementIsNotFasterThanStraightMovement() {
        let game = makeRoamingGame(yaw: 0)

        game.moveStudentFreeRoam(forward: 1, strafe: 0, deltaTime: 0.1)
        let straightDistance = hypot(game.freeRoam.positionX - 5, game.freeRoam.positionZ)

        game.freeRoam.positionX = 5
        game.freeRoam.positionZ = 0
        game.moveStudentFreeRoam(forward: 1, strafe: 1, deltaTime: 0.1)
        let diagonalDistance = hypot(game.freeRoam.positionX - 5, game.freeRoam.positionZ)

        XCTAssertEqual(diagonalDistance, straightDistance, accuracy: 0.0001)
    }

    func testControlSprintMovesFasterAndIncreasesHunger() {
        let game = makeRoamingGame(yaw: 0)
        let initialHunger = game.player.hunger

        for _ in 0..<10 {
            game.moveStudentFreeRoam(forward: 1, strafe: 0, deltaTime: 0.1)
        }
        let walkingDistance = abs(game.freeRoam.positionZ)

        game.freeRoam.positionX = 5
        game.freeRoam.positionZ = 0
        game.setFreeRoamSprinting(true)
        for _ in 0..<10 {
            game.moveStudentFreeRoam(forward: 1, strafe: 0, deltaTime: 0.1)
        }
        game.setFreeRoamSprinting(false)
        let sprintingDistance = abs(game.freeRoam.positionZ)

        XCTAssertGreaterThan(sprintingDistance, walkingDistance * 1.6)
        XCTAssertGreaterThan(game.player.hunger, initialHunger)
        XCTAssertFalse(game.freeRoam.isSprinting)
    }

    func testEventPreservesRoamingPositionAndPausesCountdown() {
        let game = makeRoamingGame(yaw: 0.7)
        game.freeRoam.positionX = 5.4
        game.freeRoam.positionZ = -2.3
        let remainingBeforeEvent = game.freeRoam.endsAt.timeIntervalSinceNow

        game.presentEvent(kind: .knockOnDoor, title: "测试事件", body: "测试", choices: [])
        Thread.sleep(forTimeInterval: 0.2)
        game.continueAfterEvent()

        XCTAssertEqual(game.freeRoam.positionX, 5.4, accuracy: 0.0001)
        XCTAssertEqual(game.freeRoam.positionZ, -2.3, accuracy: 0.0001)
        XCTAssertEqual(game.freeRoam.yaw, 0.7, accuracy: 0.0001)
        XCTAssertTrue(game.freeRoam.isActive)
        XCTAssertEqual(game.freeRoam.endsAt.timeIntervalSinceNow, remainingBeforeEvent, accuracy: 0.08)
    }

    func testReturnToSeatKeepsRoamingUntilScreenIsCovered() {
        let game = makeRoamingGame(yaw: 0.7)

        game.returnToSeatFromFreeRoam()
        XCTAssertTrue(game.isReturningToSeat)
        XCTAssertTrue(game.freeRoam.isActive)

        game.returnToSeatStartedAt = Date().addingTimeInterval(-0.5)
        XCTAssertTrue(game.isReturningToSeat)
        XCTAssertTrue(game.freeRoam.isActive)

        game.completeReturnToSeatCoverForTesting()
        XCTAssertTrue(game.isReturningToSeat)
        XCTAssertFalse(game.freeRoam.isActive)
        XCTAssertEqual(game.player.posture, .seated)
        XCTAssertEqual(game.cameraPose, .forward)

        game.finishReturnToSeatRevealForTesting()
        XCTAssertFalse(game.isReturningToSeat)
    }

    func testTeacherCollisionStopsPlayerBeforeModelOverlap() {
        let game = makeRoamingGame(yaw: 0)
        game.teacher.positionIndex = 0
        game.freeRoam.positionX = -2.7
        game.freeRoam.positionZ = -3.55
        game.freeRoam.hasExitedClassroom = false

        for _ in 0..<20 {
            game.moveStudentFreeRoam(forward: 1, strafe: 0, deltaTime: 0.05)
        }

        let teacher = game.teacherFreeRoamPosition
        let distance = hypot(game.freeRoam.positionX - teacher.x, game.freeRoam.positionZ - teacher.z)
        XCTAssertGreaterThanOrEqual(distance, 0.49)
        XCTAssertGreaterThan(game.freeRoam.positionZ, teacher.z)
        XCTAssertTrue(game.isTeacherBlockingFreeRoamPosition(x: teacher.x, z: teacher.z))
    }

    func testFirstPersonHidesOwnChairButRoamingRestoresIt() {
        let coordinator = ClassroomCoordinator()
        let game = makePlayingGame()

        game.player.posture = .seated
        coordinator.update(game: game)
        XCTAssertTrue(coordinator.playerSeatedPropsVisible)
        XCTAssertFalse(coordinator.playerGroundedChairVisible)

        game.player.posture = .standing
        game.freeRoam = StudentFreeRoamState(
            isActive: true,
            positionX: -0.6,
            positionZ: 1.65,
            yaw: 0,
            pitch: 0,
            startedAt: Date(),
            endsAt: Date().addingTimeInterval(60),
            hasExitedClassroom: false,
            isSideways: false,
            isSprinting: false,
            frontDoorOpen: false,
            rearDoorOpen: false
        )
        coordinator.update(game: game)
        XCTAssertFalse(coordinator.playerSeatedPropsVisible)
        XCTAssertTrue(coordinator.playerGroundedChairVisible)

        game.freeRoam = StudentFreeRoamState()
        game.player.posture = .seated
        game.viewMode = .teacher
        coordinator.update(game: game)
        XCTAssertFalse(coordinator.playerSeatedPropsVisible)
        XCTAssertTrue(coordinator.playerGroundedChairVisible)
    }

    func testDoorInteractionAndLeafSizedCollision() {
        let game = makeRoamingGame(yaw: 0)
        game.frontDoorOpen = false
        game.freeRoam.frontDoorOpen = false
        game.freeRoam.positionX = 3.6
        game.freeRoam.positionZ = StudentDoor.front.centerZ

        XCTAssertTrue(game.isDoorBlockingFreeRoamPosition(.front, x: 4.02, z: StudentDoor.front.centerZ))
        XCTAssertTrue(game.interactWithNearbyDoor())
        XCTAssertTrue(game.frontDoorOpen)
        XCTAssertFalse(game.isDoorBlockingFreeRoamPosition(.front, x: 4.02, z: StudentDoor.front.centerZ))
        XCTAssertTrue(game.isDoorBlockingFreeRoamPosition(.front, x: 4.31, z: StudentDoor.front.centerZ - 0.43))
        XCTAssertTrue(game.isDoorBlockingFreeRoamPosition(.front, x: 4.31, z: StudentDoor.front.centerZ + 0.43))

        XCTAssertTrue(game.interactWithNearbyDoor())
        XCTAssertFalse(game.frontDoorOpen)
        XCTAssertTrue(game.isDoorBlockingFreeRoamPosition(.front, x: 4.02, z: StudentDoor.front.centerZ))
    }

    private func makePlayingGame() -> GameManager {
        let game = GameManager(userDefaults: isolatedUserDefaults())
        game.gameState = .playing
        game.activeRole = .regularStudent
        game.viewMode = .student
        return game
    }

    private func localizeChapterOneSound(
        _ game: GameManager,
        pose: CameraPose,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        game.setPose(pose)
        guard let threshold = DwellThreshold.threshold(for: pose) else {
            XCTFail("No dwell threshold for \(pose)", file: file, line: line)
            return
        }
        game.advanceChapterOneDwell(by: threshold + 0.1)
    }

    private func chooseLinCheDialogue(
        _ game: GameManager,
        choiceID: String = "chapter1_linche_listen",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .event(let event) = game.gameState else {
            XCTFail("Expected Lin Che dialogue event", file: file, line: line)
            return
        }
        XCTAssertEqual(event.kind, .linCheDialogue, file: file, line: line)
        XCTAssertEqual(
            event.choices.map(\.id),
            ["chapter1_linche_listen", "chapter1_linche_wait", "chapter1_linche_mask"],
            file: file,
            line: line
        )
        guard let choice = event.choices.first(where: { $0.id == choiceID }) else {
            XCTFail("Missing Lin Che dialogue choice \(choiceID)", file: file, line: line)
            return
        }
        game.resolveEventChoice(choice)
    }

    private func isolatedUserDefaults(
        function: StaticString = #function,
        line: UInt = #line
    ) -> UserDefaults {
        let suiteName = "LateStudySimulatorTests.\(function).\(line).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeRoamingGame(yaw: Double) -> GameManager {
        let game = makePlayingGame()
        game.player.posture = .standing
        game.studentLookYaw = yaw
        game.freeRoam = StudentFreeRoamState(
            isActive: true,
            positionX: 5,
            positionZ: 0,
            yaw: yaw,
            pitch: 0,
            startedAt: Date(),
            endsAt: Date().addingTimeInterval(60),
            hasExitedClassroom: true,
            isSideways: false,
            isSprinting: false,
            frontDoorOpen: true,
            rearDoorOpen: true
        )
        return game
    }
}
