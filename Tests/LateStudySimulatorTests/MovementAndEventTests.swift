import XCTest
@testable import LateStudySimulator

@MainActor
final class MovementAndEventTests: XCTestCase {
    func testNarrativeContextActionEntersMirrorWithoutCollisionFriction() {
        let game = GameManager()
        game.startFullNarrativeCampaign()
        for choiceID in ["notice", "listen", "breathe", "stay", "takeNote", "follow"] {
            game.advanceNarrative(choiceID)
        }

        XCTAssertEqual(game.narrativeCampaign.currentMoment.id, "2.enter")
        XCTAssertFalse(game.narrativeCampaign.explorationReady)
        XCTAssertTrue(game.performNarrativeKeyboardCommand(.confirm))
        XCTAssertTrue(game.narrativeCampaign.explorationReady)
        game.advanceNarrative("enterMirror")
        XCTAssertEqual(game.narrativeCampaign.currentMoment.id, "2.trace")
    }

    func testInitialGameGuideLocksEntryThenBecomesFreelyReopenable() {
        let suiteName = "MovementAndEventTests.guide.\(UUID().uuidString)"
        let storage = UserDefaults(suiteName: suiteName)!
        defer { storage.removePersistentDomain(forName: suiteName) }
        let game = GameManager(userDefaults: storage)
        game.beginInitialGameGuideIfNeeded()

        XCTAssertTrue(game.isMenuEntryLocked)
        XCTAssertTrue(game.isGameGuidePresented)
        XCTAssertEqual(game.gameGuideExitCountdown, 0)

        game.dismissGameGuide()
        XCTAssertFalse(game.isGameGuidePresented)
        XCTAssertFalse(game.isMenuEntryLocked)

        game.presentGameGuide()
        XCTAssertTrue(game.isGameGuidePresented)
        XCTAssertEqual(game.gameGuideExitCountdown, 0)
    }

    func testPrologueStartsBeforeChapterOneAndUsesNamedFirstBeat() {
        let game = GameManager()

        game.startPrologue(resume: false)

        XCTAssertTrue(game.isPrologueActive)
        XCTAssertEqual(game.prologueCurrentBeat, .gateArrival)
        XCTAssertEqual(game.prologueCurrentBeat.currentGoal, "走进教学楼")
        XCTAssertTrue(game.player.posture == .standing)
    }

    func testPrologueGateArrivalCompletesAfterAboutSevenSeconds() {
        let game = GameManager()
        game.startPrologue(resume: false)

        game.tickPrologue(delta: 6.9)
        XCTAssertEqual(game.prologueCurrentBeat, .gateArrival)
        game.tickPrologue(delta: 0.1)
        XCTAssertEqual(game.prologueCurrentBeat, .lookDownHall)
    }

    func testPrologueArrivalMovesForwardAndLooksBothWays() {
        let start = ClassroomCoordinator.prologueArrivalCamera(elapsed: 0, reduceMotion: false)
        let left = ClassroomCoordinator.prologueArrivalCamera(elapsed: 2.94, reduceMotion: false)
        let right = ClassroomCoordinator.prologueArrivalCamera(elapsed: 5.04, reduceMotion: false)
        let end = ClassroomCoordinator.prologueArrivalCamera(elapsed: 7, reduceMotion: false)

        XCTAssertGreaterThan(start.position.z, left.position.z)
        XCTAssertGreaterThan(left.position.z, right.position.z)
        XCTAssertGreaterThan(right.position.z, end.position.z)
        XCTAssertLessThan(left.yaw, 0)
        XCTAssertGreaterThan(right.yaw, 0)
        XCTAssertEqual(end.yaw, 0, accuracy: 0.001)
    }

    func testReducedMotionStillAdvancesThroughFullArrivalPath() {
        let start = ClassroomCoordinator.prologueArrivalCamera(elapsed: 0, reduceMotion: true)
        let middle = ClassroomCoordinator.prologueArrivalCamera(elapsed: 3.5, reduceMotion: true)
        let end = ClassroomCoordinator.prologueArrivalCamera(elapsed: 7, reduceMotion: true)

        XCTAssertGreaterThan(start.position.z, middle.position.z)
        XCTAssertGreaterThan(middle.position.z, end.position.z)
        XCTAssertEqual(start.position.z - end.position.z, 10.5, accuracy: 0.001)
    }

    func testMenuEntryAlwaysReplaysExteriorArrival() {
        let game = GameManager()
        game.startPrologue(resume: false)
        game.completePrologueBeat(.gateArrival, source: .performance)
        XCTAssertEqual(game.prologueCurrentBeat, .lookDownHall)

        game.startExperience(forcePrologue: true)

        XCTAssertEqual(game.prologueCurrentBeat, .gateArrival)
        XCTAssertTrue(game.prologueState.completedBeats.isEmpty)
    }

    func testPassiveTutorialPerformancesUseVisibleExtendedTimeouts() {
        let game = GameManager()
        game.startPrologue(resume: false)
        for beat in PrologueBeatID.allCases.prefix(4) {
            game.completePrologueBeat(beat, source: .player)
        }
        XCTAssertEqual(game.prologueCurrentBeat, .studyHallRhythm)
        game.dismissCurrentPrologueTutorial()
        game.tickPrologue(delta: 29.9)
        XCTAssertEqual(game.prologueCurrentBeat, .studyHallRhythm)
        game.tickPrologue(delta: 0.1)
        XCTAssertEqual(game.prologueCurrentBeat, .noticeLinChe)

        game.completePrologueBeat(.noticeLinChe, source: .player)
        game.completePrologueBeat(.settleBreath, source: .player)
        game.completePrologueBeat(.accessibility, source: .player)
        XCTAssertEqual(game.prologueCurrentBeat, .bellBeforeClass)
        game.dismissCurrentPrologueTutorial()
        game.tickPrologue(delta: 6.9)
        XCTAssertEqual(game.prologueCurrentBeat, .bellBeforeClass)
        game.tickPrologue(delta: 0.1)
        XCTAssertFalse(game.isPrologueActive)
        XCTAssertTrue(game.isChapterOneTransitionPresented)

        game.enterChapterOneAfterPrologue()
        XCTAssertFalse(game.isChapterOneTransitionPresented)
    }

    func testStudyHallRhythmReachesAllFourAuthoredPhasesBeforeTimeout() {
        let game = GameManager()
        game.startPrologue(resume: false)
        for beat in PrologueBeatID.allCases.prefix(4) {
            game.completePrologueBeat(beat, source: .player)
        }
        game.dismissCurrentPrologueTutorial()

        game.tickPrologue(delta: 6)
        XCTAssertEqual(game.prologuePerformancePhase, 1)
        game.tickPrologue(delta: 6)
        XCTAssertEqual(game.prologuePerformancePhase, 2)
        game.tickPrologue(delta: 7)
        XCTAssertEqual(game.prologuePerformancePhase, 3)
        game.tickPrologue(delta: 7)
        XCTAssertEqual(game.prologuePerformancePhase, 4)
        XCTAssertEqual(game.prologueCurrentBeat, .studyHallRhythm)
        XCTAssertTrue(game.message.contains("林澈"))

        game.tickPrologue(delta: 4)
        XCTAssertEqual(game.prologueCurrentBeat, .noticeLinChe)
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
        game.dismissCurrentPrologueTutorial()
        game.setProloguePaused(true)
        game.setApplicationActive(false)

        game.tickPrologue(delta: 20)
        XCTAssertEqual(game.prologueCurrentBeat, .lookDownHall)

        game.setProloguePaused(false)
        game.tickPrologue(delta: 20)
        XCTAssertEqual(game.prologueCurrentBeat, .lookDownHall)

        game.setApplicationActive(true)
        game.updatePrologueLookExploration(isMoving: true, delta: 5)
        XCTAssertEqual(game.prologueCurrentBeat, .returnToSeat)
        XCTAssertTrue(game.prologueState.lookTutorialCompleted)
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
        XCTAssertTrue(game.narrativeCampaign.isActive)
        XCTAssertEqual(game.narrativeCampaign.chapter, .classroom)
        XCTAssertFalse(game.isFullNarrativeRun)
        guard case .playing = game.gameState else {
            return XCTFail("The prologue should hand off directly to chapter one")
        }
    }

    func testPrologueOnlyAllowsLookDuringAuthoredLookBeats() {
        let game = GameManager()
        game.startPrologue(resume: false)

        game.rotateStudentView(deltaX: -100, deltaY: 0)
        XCTAssertEqual(game.studentLookYaw, 0)

        game.completePrologueBeat(.gateArrival, source: .performance)
        game.dismissCurrentPrologueTutorial()
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

    func testTutorialShortcutUsesPhysicalTKeyAcrossInputMethods() {
        XCTAssertTrue(ClassroomCoordinator.isTutorialToggle(keyCode: 17, characters: nil))
        XCTAssertTrue(ClassroomCoordinator.isTutorialToggle(keyCode: 0, characters: "T"))
        XCTAssertFalse(ClassroomCoordinator.isTutorialToggle(keyCode: 13, characters: "w"))
    }

    func testCompleteShortcutUsesPhysicalCKeyAcrossInputMethods() {
        XCTAssertTrue(ClassroomCoordinator.isCompleteTutorialKey(keyCode: 8, characters: nil))
        XCTAssertTrue(ClassroomCoordinator.isCompleteTutorialKey(keyCode: 0, characters: "C"))
        XCTAssertFalse(ClassroomCoordinator.isCompleteTutorialKey(keyCode: 17, characters: "t"))
    }

    func testEachTutorialStepRequiresConfirmationBeforePractice() {
        let game = GameManager()
        game.startPrologue(resume: false)
        game.completePrologueBeat(.gateArrival, source: .performance)

        XCTAssertEqual(game.prologueCurrentBeat, .lookDownHall)
        XCTAssertTrue(game.isPrologueTutorialPresented)
        XCTAssertTrue(game.prologuePaused)

        game.tickPrologue(delta: 20)
        XCTAssertEqual(game.prologueCurrentBeat, .lookDownHall)

        game.dismissCurrentPrologueTutorial()
        XCTAssertFalse(game.isPrologueTutorialPresented)
        XCTAssertFalse(game.prologuePaused)

        game.toggleCurrentPrologueTutorial()
        XCTAssertTrue(game.isPrologueTutorialPresented)
        XCTAssertTrue(game.prologuePaused)
    }

    func testLookTutorialStartsReleasedAndMovementTutorialAllowsMouseLook() {
        let game = GameManager()
        game.startPrologue(resume: false)
        game.completePrologueBeat(.gateArrival, source: .performance)

        XCTAssertEqual(game.prologueCurrentBeat, .lookDownHall)
        XCTAssertFalse(game.mouseLookEnabled)

        game.dismissCurrentPrologueTutorial()
        game.completePrologueBeat(.lookDownHall, source: .player)
        XCTAssertEqual(game.prologueCurrentBeat, .returnToSeat)
        XCTAssertTrue(game.mouseLookEnabled)
        game.dismissCurrentPrologueTutorial()

        let initialYaw = game.freeRoam.yaw
        game.rotateStudentView(deltaX: -80, deltaY: 0)
        XCTAssertNotEqual(game.freeRoam.yaw, initialYaw)
    }

    func testLookTutorialRequiresFiveSecondsOfActiveLookingAndLocksCompleteKey() {
        let game = GameManager()
        game.startPrologue(resume: false)
        game.completePrologueBeat(.gateArrival, source: .performance)
        game.dismissCurrentPrologueTutorial()

        game.updatePrologueLookExploration(isMoving: false, delta: 10)
        XCTAssertEqual(game.prologueLookExplorationElapsed, 0)
        game.completeCurrentPrologueEarly()
        XCTAssertEqual(game.prologueCurrentBeat, .lookDownHall)

        game.updatePrologueLookExploration(isMoving: true, delta: 4.9)
        game.completeCurrentPrologueEarly()
        XCTAssertEqual(game.prologueCurrentBeat, .lookDownHall)
        game.updatePrologueLookExploration(isMoving: true, delta: 0.1)
        XCTAssertEqual(game.prologueCurrentBeat, .returnToSeat)
    }

    func testCompleteKeyStaysLockedUntilRequiredActionIsFinished() {
        let game = GameManager()
        game.startPrologue(resume: false)
        game.completePrologueBeat(.gateArrival, source: .performance)
        game.completePrologueBeat(.lookDownHall, source: .player)
        XCTAssertEqual(game.prologueCurrentBeat, .returnToSeat)

        game.completeCurrentPrologueEarly()
        XCTAssertEqual(game.prologueCurrentBeat, .returnToSeat)
        game.dismissCurrentPrologueTutorial()
        game.completeCurrentPrologueEarly()
        XCTAssertEqual(game.prologueCurrentBeat, .returnToSeat)

        game.freeRoam.positionX = -0.55
        game.freeRoam.positionZ = 1.65
        XCTAssertTrue(game.confirmPrologueSeat())
        XCTAssertTrue(game.prologueActionReady)
        XCTAssertEqual(game.prologueCurrentBeat, .returnToSeat)
        XCTAssertFalse(game.freeRoam.isActive)
        XCTAssertEqual(game.player.posture, .seated)
        game.completeCurrentPrologueEarly()
        XCTAssertEqual(game.prologueCurrentBeat, .placeWater)
        XCTAssertTrue(game.prologueState.movementTutorialCompleted)

        game.dismissCurrentPrologueTutorial()
        game.completeCurrentPrologueEarly()
        XCTAssertEqual(game.prologueCurrentBeat, .placeWater)
        game.confirmPrologueInteraction()
        XCTAssertTrue(game.prologueActionReady)
        game.completeCurrentPrologueEarly()
        XCTAssertEqual(game.prologueCurrentBeat, .studyHallRhythm)
        XCTAssertTrue(game.prologueState.interactionTutorialCompleted)
    }

    func testCompleteKeyRecordsAccessibilityAcknowledgementAsPlayerCompletion() {
        let game = GameManager()
        game.startPrologue(resume: false)
        for beat in PrologueBeatID.allCases.prefix(7) {
            game.completePrologueBeat(beat, source: .player)
        }
        XCTAssertEqual(game.prologueCurrentBeat, .accessibility)
        game.dismissCurrentPrologueTutorial()

        game.acknowledgeAccessibilityTutorial(openSettings: false)
        game.completeCurrentPrologueEarly()

        XCTAssertEqual(game.prologueCurrentBeat, .bellBeforeClass)
        XCTAssertTrue(game.prologueState.accessibilityTutorialAcknowledged)
    }

    func testApproachingSeatDoesNotSnapPlayerOrUnlockCompleteKey() {
        let game = GameManager()
        game.startPrologue(resume: false)
        game.completePrologueBeat(.gateArrival, source: .performance)
        game.completePrologueBeat(.lookDownHall, source: .player)
        game.dismissCurrentPrologueTutorial()
        game.freeRoam.positionX = -0.55
        game.freeRoam.positionZ = 2.35

        game.moveStudentFreeRoam(forward: 1, strafe: 0, deltaTime: 0.05)

        XCTAssertTrue(game.prologueSeatNearby)
        XCTAssertFalse(game.prologueActionReady)
        XCTAssertNotEqual(game.freeRoam.positionZ, 1.65, accuracy: 0.001)
        game.completeCurrentPrologueEarly()
        XCTAssertEqual(game.prologueCurrentBeat, .returnToSeat)
    }

    func testObservingLinCheUnlocksCompleteKeyInsteadOfAdvancingImmediately() {
        let game = GameManager()
        game.startPrologue(resume: false)
        game.completePrologueBeat(.gateArrival, source: .performance)
        game.completePrologueBeat(.lookDownHall, source: .player)
        game.completePrologueBeat(.returnToSeat, source: .fallback)
        game.completePrologueBeat(.placeWater, source: .fallback)
        game.completePrologueBeat(.studyHallRhythm, source: .performance)
        XCTAssertEqual(game.prologueCurrentBeat, .noticeLinChe)
        game.dismissCurrentPrologueTutorial()

        game.studentLookYaw = 0.5
        game.updatePrologueDwell(delta: 1.0)

        XCTAssertTrue(game.prologueActionReady)
        XCTAssertEqual(game.prologueCurrentBeat, .noticeLinChe)
        game.completeCurrentPrologueEarly()
        XCTAssertEqual(game.prologueCurrentBeat, .settleBreath)
    }

    func testMovementTutorialCanEnterDeskAisleWithoutSidewaysMode() {
        let game = GameManager()
        game.startPrologue(resume: false)
        game.completePrologueBeat(.gateArrival, source: .performance)
        game.completePrologueBeat(.lookDownHall, source: .player)
        game.dismissCurrentPrologueTutorial()

        XCTAssertFalse(game.freeRoam.isSideways)
        let initialX = game.freeRoam.positionX
        for _ in 0..<10 {
            game.moveStudentFreeRoam(forward: 1, strafe: 0, deltaTime: 0.05)
        }
        XCTAssertLessThan(game.freeRoam.positionX, initialX - 0.4)
    }

    func testChapterOneAlwaysStartsAsSuNianStudentPath() {
        let game = GameManager()
        game.selectedRole = .homeroomTeacher

        game.startGame()

        XCTAssertEqual(game.activeRole, .regularStudent)
        XCTAssertEqual(game.activeChapter, .silentClassroom)
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

        game.setPose(.left)
        game.execute(.observe)
        XCTAssertEqual(game.chapterOneStep, .locateHiddenSound)
        XCTAssertEqual(game.chapterClues.map(\.id), [.linChePage])

        game.setPose(.right)
        game.execute(.observe)
        XCTAssertEqual(game.chapterOneStep, .regulateSelf)
        XCTAssertEqual(game.chapterClues.map(\.id), [.linChePage, .hiddenCrying])

        game.execute(.breathe)
        XCTAssertEqual(game.chapterOneStep, .approachLinChe)

        game.execute(.talk)
        XCTAssertEqual(game.chapterOneStep, .inspectNote)

        game.setPose(.desk)
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

    func testReturnToSeatKeepsRoamingUntilScreenIsCovered() async throws {
        let game = makeRoamingGame(yaw: 0.7)

        game.returnToSeatFromFreeRoam()
        XCTAssertTrue(game.isReturningToSeat)
        XCTAssertTrue(game.freeRoam.isActive)

        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertTrue(game.isReturningToSeat)
        XCTAssertTrue(game.freeRoam.isActive)

        try await Task.sleep(nanoseconds: 700_000_000)
        XCTAssertTrue(game.isReturningToSeat)
        XCTAssertFalse(game.freeRoam.isActive)
        XCTAssertEqual(game.player.posture, .seated)
        XCTAssertEqual(game.cameraPose, .forward)

        try await Task.sleep(nanoseconds: 750_000_000)
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

    func testStandingHidesFirstPersonBodyButKeepsGroundedChair() {
        let coordinator = ClassroomCoordinator()
        let game = makePlayingGame()

        game.player.posture = .seated
        coordinator.update(game: game)
        XCTAssertTrue(coordinator.playerSeatedPropsVisible)
        XCTAssertTrue(coordinator.playerGroundedChairVisible)
        XCTAssertEqual(coordinator.playerGroundedChairLegCount, 4)

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
        let game = GameManager()
        game.gameState = .playing
        game.activeRole = .regularStudent
        game.viewMode = .student
        return game
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
