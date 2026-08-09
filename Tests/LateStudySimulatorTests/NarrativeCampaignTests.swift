import XCTest
@testable import LateStudySimulator

final class NarrativeCampaignTests: XCTestCase {
    func testMelodyFeedbackNamesTheActualNextPad() {
        var campaign = NarrativeCampaign(isActive: true, chapter: .mirror, momentIndex: 2)
        campaign.miniGameProgress = 3

        let feedback = MirrorMicroGameInputFeedbackModel.ready(from: campaign, miniGame: .melody)

        XCTAssertEqual(feedback.targetText, "目标：第 4 拍 笔")
    }

    private let maximumCampaignSteps = 240

    func testLegacyCampaignSaveDecodesWithoutNewSafetySubstates() throws {
        let encoded = try JSONEncoder().encode(NarrativeCampaign(isActive: true, chapter: .mirror))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "safetyHandoffState")
        object.removeValue(forKey: "counselingState")

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let restored = try JSONDecoder().decode(NarrativeCampaign.self, from: legacyData)

        XCTAssertEqual(restored.chapter, .mirror)
        XCTAssertNil(restored.safetyHandoffState)
        XCTAssertNil(restored.counselingState)
    }

    func testCompanionHotspotsOnlyAppearDuringTheAuthoredChoiceMoment() {
        var campaign = NarrativeCampaign()
        campaign.startAfterPlayableChapterOne()
        campaign.chapter = .noteTrace
        campaign.exploration.reset(for: .noteTrace)

        XCTAssertTrue(campaign.interactionHotspots.allSatisfy { $0.choiceID == nil })

        campaign.momentIndex = 2
        let companionHotspots = campaign.interactionHotspots.filter { $0.choiceID != nil }
        XCTAssertEqual(Set(companionHotspots.map(\.choiceID)), Set(["zhou", "xu"]))
        XCTAssertEqual(Set(companionHotspots.map(\.title)), Set(["周予安", "许栀"]))

        campaign.choose("xu")
        XCTAssertEqual(campaign.companionID, "许栀")
        XCTAssertTrue(campaign.interactionHotspots.allSatisfy { $0.choiceID == nil })
    }

    func testChapterThreeInvestigationStepsTrackSpatialProgress() {
        var campaign = NarrativeCampaign()
        campaign.startAfterPlayableChapterOne()
        campaign.chapter = .noteTrace
        campaign.exploration.reset(for: .noteTrace)

        XCTAssertEqual(campaign.chapterThreeInvestigationSteps.map(\.state), [.active, .locked, .locked, .locked])

        campaign.exploration.lastInteractedHotspot = "note.table"
        XCTAssertEqual(campaign.chapterThreeInvestigationSteps.map(\.state), [.complete, .locked, .locked, .locked])

        campaign.choose("inspectFold")
        XCTAssertEqual(campaign.currentMoment.id, "3.locate")
        XCTAssertEqual(campaign.chapterThreeInvestigationSteps.map(\.state), [.complete, .active, .locked, .locked])

        campaign.recordNoteTraceDepartureClue(for: "note.paperTrail")
        campaign.choose("locateJiang")
        XCTAssertEqual(campaign.currentMoment.id, "3.locate")
        XCTAssertEqual(campaign.chapterThreeInvestigationSteps.map(\.state), [.complete, .active, .locked, .locked])

        campaign.recordNoteTraceDepartureClue(for: "note.deskTrace")
        campaign.choose("locateJiang")
        XCTAssertEqual(campaign.currentMoment.id, "3.companion")
        XCTAssertEqual(campaign.chapterThreeInvestigationSteps.map(\.state), [.complete, .complete, .active, .locked])

        campaign.companionID = "许栀"
        XCTAssertEqual(campaign.chapterThreeInvestigationSteps.map(\.state), [.complete, .complete, .complete, .locked])
    }

    func testFirstPersonExplorationMovesWithinBoundsAndRequiresProximity() {
        var exploration = NarrativeExplorationState()
        exploration.reset(for: .mirror)

        XCTAssertNil(exploration.nearbyHotspot)
        XCTAssertNil(exploration.interact())

        for _ in 0..<100 where exploration.nearbyHotspot == nil {
            exploration.move(forward: 1, strafe: 0, deltaTime: 0.05)
        }

        XCTAssertEqual(exploration.nearbyHotspot?.id, "mirror.linche")
        XCTAssertEqual(exploration.interact()?.id, "mirror.linche")
        XCTAssertEqual(exploration.interactionCount, 1)

        for _ in 0..<300 {
            exploration.move(forward: 1, strafe: 0, deltaTime: 0.05)
        }
        XCTAssertEqual(exploration.positionZ, -5.75, accuracy: 0.0001)
    }

    func testExplorationRotationAndDiagonalMovementStayNormalized() {
        var straight = NarrativeExplorationState()
        straight.reset(for: .noteTrace)
        var diagonal = straight

        straight.move(forward: 1, strafe: 0, deltaTime: 0.05)
        diagonal.move(forward: 1, strafe: 1, deltaTime: 0.05)

        let straightDistance = hypot(straight.positionX - 0.28, straight.positionZ - 4.85)
        let diagonalDistance = hypot(diagonal.positionX - 0.28, diagonal.positionZ - 4.85)
        XCTAssertEqual(diagonalDistance, straightDistance, accuracy: 0.0001)

        diagonal.rotate(deltaX: 10_000, deltaY: -10_000)
        XCTAssertEqual(diagonal.yaw, .pi, accuracy: 0.0001)
        XCTAssertEqual(diagonal.pitch, 0.3, accuracy: 0.0001)
    }

    func testStateMachineRejectsStaleOrFabricatedPlayerChoices() {
        var campaign = NarrativeCampaign()
        campaign.startAfterPlayableChapterOne()
        let initialMoment = campaign.currentMoment.id

        campaign.choose("finish")

        XCTAssertEqual(campaign.currentMoment.id, initialMoment)
        XCTAssertTrue(campaign.completedMomentIDs.contains(initialMoment) == false)
    }

    func testSafetyPolicyMapsAuthoredRiskWithoutPlayerDiagnosis() {
        let expected: [(NarrativeRiskLevel, NarrativeSafetyRoute, NarrativeCounselingEntryMode)] = [
            (.low, .standardCounseling, .standardWaiting),
            (.moderate, .standardCounseling, .standardWaiting),
            (.high, .urgentSchoolResponse, .urgentHandoffWaiting),
            (.imminent, .emergencyServices, .emergencyClosure)
        ]

        for (risk, route, entryMode) in expected {
            let resolved = NarrativeSafetyHandoffPolicy.resolve(risk)
            XCTAssertEqual(resolved.route, route)
            XCTAssertEqual(resolved.entryMode, entryMode)
        }
    }

    func testWorldDirectorSignalMovesFromStairwellRiskToAdultSupport() {
        var campaign = NarrativeCampaign(isActive: true, chapter: .stairwell)
        campaign.companionID = "周予安"
        campaign.safetyHandoffState = NarrativeSafetyHandoffState(authoredRisk: .high)
        campaign.prepareRuntimeStateForCurrentChapter()

        let riskSignal = campaign.worldDirectorSignal

        XCTAssertEqual(riskSignal.cue, .risk)
        XCTAssertGreaterThan(riskSignal.ambientTension, 0.7)
        XCTAssertLessThan(riskSignal.safetyResponse, 0.1)

        campaign.jiangYueTrust = 72
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

        let responseSignal = campaign.worldDirectorSignal

        XCTAssertEqual(responseSignal.cue, .safetyResponse)
        XCTAssertLessThan(responseSignal.ambientTension, riskSignal.ambientTension)
        XCTAssertGreaterThan(responseSignal.supportPresence, riskSignal.supportPresence)
        XCTAssertGreaterThan(responseSignal.safetyResponse, 0.8)
        XCTAssertGreaterThan(responseSignal.privacyBoundary, riskSignal.privacyBoundary)
    }

    func testAmbientActorDirectivesShiftFromRumorCrowdToSupportHandoff() {
        var campaign = NarrativeCampaign(isActive: true, chapter: .counseling, momentIndex: 1)
        campaign.companionID = "许栀"
        campaign.counselingState = NarrativeCounselingState(entryMode: .standardWaiting)

        let rumorDirectives = campaign.ambientActorDirectives

        XCTAssertEqual(rumorDirectives.map(\.role), [.bystander, .bystander, .boundaryKeeper])
        XCTAssertTrue(rumorDirectives.allSatisfy { $0.line.isEmpty == false })
        XCTAssertGreaterThan(rumorDirectives[2].intensity, rumorDirectives[1].intensity)

        campaign.counselingState?.rumorHandled = true
        campaign.counselingState?.companionMessageReplied = true
        campaign.counselingState?.handoffConfirmed = true
        campaign.counselingState?.supportHandedOff = true
        campaign.momentIndex = 2

        let supportDirectives = campaign.ambientActorDirectives

        XCTAssertEqual(supportDirectives.map(\.role), [.facilitator, .quietWitness])
        XCTAssertFalse(supportDirectives.contains { $0.role == .bystander })
        XCTAssertGreaterThan(supportDirectives[0].intensity, supportDirectives[1].intensity)
    }

    func testConsequenceEchoesReflectRoutePrivacyRiskQuestionAndSelfCare() throws {
        var campaign = NarrativeCampaign(isActive: true, isComplete: true, chapter: .epilogue)
        campaign.clueCount = 5
        campaign.companionID = "周予安"
        campaign.privacyProtected = true
        campaign.selfCared = true
        campaign.sharedSelf = true
        campaign.jiangDialogueState = NarrativeJiangDialogueState(
            segmentIndex: 3,
            responseKinds: [.listening, .accompanying],
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

        let echoes = campaign.consequenceEchoes

        XCTAssertEqual(echoes.map(\.kind), [.noticed, .companion, .riskQuestion, .privacy, .selfCare, .handoff])
        XCTAssertTrue(try XCTUnwrap(echoes.first { $0.kind == .companion }).trace.contains("周予安"))
        XCTAssertTrue(try XCTUnwrap(echoes.first { $0.kind == .riskQuestion }).trace.contains("直接问清"))
        XCTAssertTrue(try XCTUnwrap(echoes.first { $0.kind == .privacy }).trace.contains("挡在门外"))
        XCTAssertGreaterThan(try XCTUnwrap(echoes.first { $0.kind == .handoff }).strength, 0.85)

        campaign.selfCared = false
        let selfCareEcho = try XCTUnwrap(campaign.consequenceEchoes.first { $0.kind == .selfCare })
        XCTAssertTrue(selfCareEcho.trace.contains("也需要被接住"))
        XCTAssertLessThan(selfCareEcho.strength, 0.5)
    }

    func testEmpathyReplayTurnsCampaignStateIntoSystemicCauseAndResponse() throws {
        var campaign = NarrativeCampaign(isActive: true, isComplete: true, chapter: .epilogue)
        campaign.clueCount = 5
        campaign.companionID = "许栀"
        campaign.selfCared = true
        campaign.sharedSelf = true
        campaign.privacyProtected = true
        campaign.jiangDialogueState = NarrativeJiangDialogueState(
            segmentIndex: 3,
            responseKinds: [.listening, .accompanying, .silentPresence, .advisory],
            consecutiveTimeouts: 0,
            listenPhaseComplete: true,
            educationCardDismissed: true,
            riskAskMethod: .direct,
            disclosedRisk: .confirmed
        )
        campaign.safetyHandoffState = NarrativeSafetyHandoffState(
            authoredRisk: .imminent,
            riskAsked: true,
            adultContactInitiated: true,
            contactMethod: "消息",
            safetyHandoffComplete: true,
            route: .emergencyServices,
            entryMode: .emergencyClosure,
            resolutionPath: .voluntary
        )
        campaign.counselingState = NarrativeCounselingState(
            entryMode: .emergencyClosure,
            handoffSceneStarted: true,
            boundaryHeld: true,
            rumorHandled: true,
            rumorOutcome: .contained,
            companionMessageReplied: true,
            handoffConfirmed: true,
            supportHandedOff: true
        )

        let replay = campaign.empathyReplayBeats

        XCTAssertEqual(replay.map(\.kind), [.observation, .connection, .risk, .handoff, .boundary, .selfReflection])
        XCTAssertTrue(try XCTUnwrap(replay.first { $0.kind == .observation }).playerTrace.contains("5 条线索"))
        XCTAssertTrue(try XCTUnwrap(replay.first { $0.kind == .connection }).playerTrace.contains("许栀"))
        XCTAssertTrue(try XCTUnwrap(replay.first { $0.kind == .risk }).playerTrace.contains("直接确认"))
        XCTAssertTrue(try XCTUnwrap(replay.first { $0.kind == .handoff }).supportResponse.contains("紧急服务接管"))
        XCTAssertGreaterThan(try XCTUnwrap(replay.first { $0.kind == .selfReflection }).empathyScore, 0.85)

        campaign.companionID = ""
        campaign.sharedSelf = false
        campaign.selfCared = false
        let weakerReplay = campaign.empathyReplayBeats
        XCTAssertLessThan(
            try XCTUnwrap(weakerReplay.first { $0.kind == .connection }).empathyScore,
            try XCTUnwrap(replay.first { $0.kind == .connection }).empathyScore
        )
        XCTAssertTrue(try XCTUnwrap(weakerReplay.first { $0.kind == .selfReflection }).playerTrace.contains("只照顾别人"))
    }

    func testTruthReplayRevealsHiddenStudentStateAcrossPerspectives() throws {
        var campaign = NarrativeCampaign(isActive: true, isComplete: true, chapter: .epilogue)
        campaign.clueCount = 5
        campaign.companionID = "周予安"
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

        let reveals = campaign.truthReplayReveals

        XCTAssertEqual(reveals.map(\.perspective), [.teacher, .linChe, .jiangYue, .suNian])
        XCTAssertTrue(try XCTUnwrap(reveals.first { $0.perspective == .teacher }).hiddenTruth.contains("5 条求助线索"))
        XCTAssertTrue(try XCTUnwrap(reveals.first { $0.perspective == .linChe }).repairAction.contains("周予安"))
        XCTAssertTrue(try XCTUnwrap(reveals.first { $0.perspective == .jiangYue }).hiddenTruth.contains("4 次"))
        XCTAssertGreaterThan(try XCTUnwrap(reveals.first { $0.perspective == .suNian }).revealStrength, 0.85)

        campaign.sharedSelf = false
        campaign.selfCared = false
        campaign.companionID = ""
        campaign.jiangDialogueState?.disclosedRisk = .unknown
        campaign.safetyHandoffState?.route = nil
        let weakerReveals = campaign.truthReplayReveals

        XCTAssertLessThan(
            try XCTUnwrap(weakerReveals.first { $0.perspective == .jiangYue }).revealStrength,
            try XCTUnwrap(reveals.first { $0.perspective == .jiangYue }).revealStrength
        )
        XCTAssertTrue(try XCTUnwrap(weakerReveals.first { $0.perspective == .suNian }).hiddenTruth.contains("放到最后"))
    }

    func testPolicyExperimentsCompareInstitutionalPressureSupportAndMissedSignals() throws {
        var campaign = NarrativeCampaign(isActive: true, isComplete: true, chapter: .epilogue)
        campaign.clueCount = 5
        campaign.companionID = "许栀"
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

        let experiments = campaign.policyExperiments
        XCTAssertEqual(experiments.map(\.id), [
            "policy.protected-whisper",
            "policy.strict-patrol",
            "policy.counseling-duty"
        ])

        let protectedWhisper = try XCTUnwrap(experiments.first { $0.id == "policy.protected-whisper" })
        let strictPatrol = try XCTUnwrap(experiments.first { $0.id == "policy.strict-patrol" })
        let counselingDuty = try XCTUnwrap(experiments.first { $0.id == "policy.counseling-duty" })

        XCTAssertLessThan(protectedWhisper.pressureIndex, strictPatrol.pressureIndex)
        XCTAssertGreaterThan(protectedWhisper.supportIndex, strictPatrol.supportIndex)
        XCTAssertLessThan(protectedWhisper.missedSignalRisk, strictPatrol.missedSignalRisk)
        XCTAssertLessThan(counselingDuty.missedSignalRisk, strictPatrol.missedSignalRisk)
        XCTAssertTrue(strictPatrol.outcomeLine.contains("藏回去"))
    }

    func testEndingSelectorPrioritizesAdultHandoffRoutes() {
        var campaign = NarrativeCampaign(isActive: true, isComplete: true, chapter: .epilogue)
        campaign.sharedSelf = true
        campaign.selfCared = true
        campaign.safetyHandoffState = NarrativeSafetyHandoffState(
            authoredRisk: .imminent,
            riskAsked: true,
            adultContactInitiated: true,
            contactMethod: "电话",
            safetyHandoffComplete: true,
            route: .emergencyServices,
            entryMode: .emergencyClosure,
            resolutionPath: .voluntary
        )
        campaign.safetyRoute = NarrativeSafetyRoute.standardCounseling.displayName

        XCTAssertEqual(EndingSelector.select(campaign: campaign), .emergencyHandoff)

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
        campaign.safetyRoute = NarrativeSafetyRoute.urgentSchoolResponse.displayName

        XCTAssertEqual(EndingSelector.select(campaign: campaign), .urgentHandoff)

        campaign.safetyHandoffState = nil
        campaign.safetyRoute = NarrativeSafetyRoute.emergencyServices.displayName

        XCTAssertEqual(EndingSelector.select(campaign: campaign), .emergencyHandoff)
    }

    func testEndingSelectorReflectsDisclosureAndSelfCareBranches() {
        var campaign = NarrativeCampaign(isActive: true, isComplete: true, chapter: .epilogue)
        campaign.sharedSelf = true
        campaign.selfCared = false
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

        XCTAssertEqual(EndingSelector.select(campaign: campaign), .voluntaryAndShared)
        XCTAssertTrue(EndingSelector.needsSelfCareReminder(campaign: campaign))

        campaign.selfCared = true
        XCTAssertFalse(EndingSelector.needsSelfCareReminder(campaign: campaign))

        campaign.safetyHandoffState?.resolutionPath = .adultCameAfterUnclearDisclosure
        XCTAssertEqual(EndingSelector.select(campaign: campaign), .unclearDisclosure)

        campaign.safetyHandoffState?.resolutionPath = .adultCameAfterLowTrust
        XCTAssertEqual(EndingSelector.select(campaign: campaign), .lowTrustHandoff)

        campaign.safetyHandoffState = nil
        campaign.sharedSelf = false
        XCTAssertEqual(EndingSelector.select(campaign: campaign), .didNotShare)

        campaign.sharedSelf = true
        XCTAssertEqual(EndingSelector.select(campaign: campaign), .standardLight)
    }

    func testEndingRouteSpectrumExplainsAllSevenRoutesAndHighlightsOnlySelected() {
        func campaign(
            route: NarrativeSafetyRoute? = nil,
            risk: NarrativeRiskLevel = .moderate,
            resolution: NarrativeResolutionPath? = nil,
            sharedSelf: Bool,
            selfCared: Bool = true
        ) -> NarrativeCampaign {
            var campaign = NarrativeCampaign(isActive: true, isComplete: true, chapter: .epilogue)
            campaign.sharedSelf = sharedSelf
            campaign.selfCared = selfCared
            if let route {
                campaign.safetyRoute = route.displayName
                campaign.safetyHandoffState = NarrativeSafetyHandoffState(
                    authoredRisk: risk,
                    riskAsked: true,
                    adultContactInitiated: true,
                    contactMethod: "电话",
                    safetyHandoffComplete: true,
                    route: route,
                    entryMode: route == .emergencyServices ? .emergencyClosure : .standardWaiting,
                    resolutionPath: resolution
                )
            } else if let resolution {
                campaign.safetyHandoffState = NarrativeSafetyHandoffState(
                    authoredRisk: risk,
                    riskAsked: true,
                    adultContactInitiated: true,
                    contactMethod: "消息",
                    safetyHandoffComplete: true,
                    route: .standardCounseling,
                    entryMode: .standardWaiting,
                    resolutionPath: resolution
                )
            }
            return campaign
        }

        let scenarios: [(EndingType, NarrativeCampaign)] = [
            (.emergencyHandoff, campaign(route: .emergencyServices, risk: .imminent, resolution: .voluntary, sharedSelf: true)),
            (.urgentHandoff, campaign(route: .urgentSchoolResponse, risk: .high, resolution: .voluntary, sharedSelf: true)),
            (.voluntaryAndShared, campaign(route: .standardCounseling, resolution: .voluntary, sharedSelf: true)),
            (.unclearDisclosure, campaign(resolution: .adultCameAfterUnclearDisclosure, sharedSelf: true)),
            (.lowTrustHandoff, campaign(resolution: .adultCameAfterLowTrust, sharedSelf: true)),
            (.didNotShare, campaign(sharedSelf: false)),
            (.standardLight, campaign(sharedSelf: true))
        ]

        for (expected, campaign) in scenarios {
            let spectrum = EndingSelector.routeSpectrum(for: campaign)
            XCTAssertEqual(spectrum.count, EndingType.allCases.count)
            XCTAssertEqual(spectrum.map(\.type), EndingType.allCases)

            let selected = spectrum.filter(\.isSelected)
            XCTAssertEqual(selected.count, 1)
            XCTAssertEqual(selected.first?.type, expected)
            XCTAssertEqual(selected.first?.matchStrength, 1)

            for signal in spectrum {
                XCTAssertFalse(signal.triggerLine.isEmpty)
                XCTAssertFalse(signal.evidenceLine.isEmpty)
                XCTAssertGreaterThanOrEqual(signal.matchStrength, 0)
                XCTAssertLessThanOrEqual(signal.matchStrength, 1)
                XCTAssertFalse(signal.triggerLine.contains("赢"))
                XCTAssertFalse(signal.triggerLine.contains("失败"))
                XCTAssertFalse(signal.evidenceLine.contains("赢"))
                XCTAssertFalse(signal.evidenceLine.contains("失败"))
            }
        }
    }

    func testNarrativeRouteMarkersSummarizeSixChapterMemory() {
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

        let markers = campaign.routeMarkers

        XCTAssertEqual(markers.map(\.chapter), NarrativeChapter.allCases)
        XCTAssertEqual(markers.map(\.state), [.completed, .completed, .completed, .current, .upcoming, .upcoming])
        XCTAssertTrue(markers[0].statusLine.contains("4 条线索"))
        XCTAssertTrue(markers[1].statusLine.contains("照顾自己"))
        XCTAssertTrue(markers[2].statusLine.contains("许栀"))
        XCTAssertEqual(markers[3].statusLine, NarrativeSafetyRoute.urgentSchoolResponse.displayName)
        XCTAssertTrue(markers[4].statusLine.contains("隐私仍需照顾"))
        XCTAssertEqual(markers[5].statusLine, "下次也可以")
        XCTAssertGreaterThan(markers[3].signalStrength, markers[4].signalStrength)

        campaign.isComplete = true
        XCTAssertTrue(campaign.routeMarkers.allSatisfy { $0.state == .completed })
    }

    func testIntegrationStateMatrixCoversSixteenRouteCombinationsWithoutLosingState() {
        let results = NarrativeIntegrationMatrix.results
        let cases = results.map(\.matrixCase)

        XCTAssertEqual(results.count, 16)
        XCTAssertEqual(Set(cases.map(\.id)).count, 16)
        XCTAssertEqual(Set(cases.map(\.profile)), Set(NarrativeIntegrationRouteProfile.allCases))
        XCTAssertEqual(Set(cases.map(\.companionID)), Set(NarrativeIntegrationMatrix.companions))
        XCTAssertEqual(Set(cases.map(\.sharedSelf)), Set([true, false]))

        for result in results {
            XCTAssertTrue(result.companionPreserved, result.id)
            XCTAssertTrue(result.sharedSelfPreserved, result.id)
            XCTAssertTrue(result.uniqueConsequenceEchoes, result.id)
            XCTAssertTrue(result.routeMarkersComplete, result.id)
            XCTAssertTrue(result.audioProfileResolved, result.id)
            XCTAssertTrue(result.missingStateLines.isEmpty, "\(result.id): \(result.missingStateLines)")
            XCTAssertEqual(result.endingType, EndingSelector.select(campaign: result.campaign), result.id)
            XCTAssertEqual(result.campaign.safetyHandoffState?.route, result.matrixCase.profile.route, result.id)
            XCTAssertEqual(result.campaign.safetyHandoffState?.resolutionPath, result.matrixCase.profile.resolutionPath, result.id)
            XCTAssertEqual(result.campaign.privacyProtected, result.matrixCase.profile.privacyProtected, result.id)
            XCTAssertEqual(result.campaign.jiangDialogueState?.riskAskMethod, result.matrixCase.profile.riskAskMethod, result.id)
            XCTAssertFalse(result.consequenceEchoIDs.isEmpty, result.id)
        }

        let lowTrust = results.filter { $0.matrixCase.profile == .lowTrustContained }
        XCTAssertEqual(Set(lowTrust.map(\.endingType)), [.lowTrustHandoff])
        XCTAssertTrue(results.contains { $0.endingType == .emergencyHandoff })
        XCTAssertTrue(results.contains { $0.endingType == .urgentHandoff })
        XCTAssertTrue(results.contains { $0.endingType == .voluntaryAndShared })
        XCTAssertTrue(results.contains { $0.endingType == .didNotShare })
    }

    func testCampaignDossierBuildsSixChapterArchiveFromRouteState() {
        var campaign = NarrativeCampaign(isActive: true, isComplete: true, chapter: .epilogue)
        campaign.clueCount = 5
        campaign.companionID = "许栀"
        campaign.selfCared = true
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

        let dossier = NarrativeCampaignDossier.make(for: campaign)

        XCTAssertEqual(dossier.endingType, .voluntaryAndShared)
        XCTAssertEqual(dossier.chapterCards.map(\.chapter), NarrativeChapter.allCases)
        XCTAssertTrue(dossier.routeSignature.contains("许栀"))
        XCTAssertTrue(dossier.routeSignature.contains("苏念开口"))
        XCTAssertTrue(dossier.chapterCards[0].routeLine.contains("5 条线索"))
        XCTAssertTrue(dossier.chapterCards[2].routeLine.contains("许栀"))
        XCTAssertTrue(dossier.chapterCards[3].routeLine.contains(NarrativeSafetyRoute.standardCounseling.displayName))
        XCTAssertTrue(dossier.chapterCards[4].routeLine.contains("隐私"))
        XCTAssertTrue(dossier.chapterCards[5].evidenceLine.contains(dossier.endingType.title))
        XCTAssertEqual(dossier.uniqueEchoCount, dossier.echoCount)
        XCTAssertTrue(dossier.unresolvedWarnings.isEmpty)
        XCTAssertTrue(dossier.isCoherent)
        XCTAssertGreaterThan(dossier.supportContinuity, 0.7)

        campaign.sharedSelf = false
        let quietDossier = NarrativeCampaignDossier.make(for: campaign)
        XCTAssertEqual(quietDossier.endingType, .didNotShare)
        XCTAssertTrue(quietDossier.routeSignature.contains("保留节奏"))
    }

    func testAutonomousRouteAuditorCompletesMultiplePlayerIntents() {
        let results = AutonomousRouteAuditor.runAll()

        XCTAssertEqual(results.map(\.intent), AutonomousRouteIntent.allCases)
        XCTAssertEqual(results.count, 4)
        XCTAssertTrue(results.allSatisfy(\.isPassing), results.map { "\($0.intent.title): \($0.warnings)" }.joined(separator: " | "))
        XCTAssertTrue(results.allSatisfy { $0.campaign.isComplete })
        XCTAssertTrue(results.allSatisfy { $0.stepCount > 16 })
        XCTAssertEqual(Set(results.map(\.companionID)), Set(["许栀", "周予安"]))
        XCTAssertEqual(Set(results.map(\.sharedSelf)), Set([true, false]))
        XCTAssertTrue(results.contains { $0.endingType == .didNotShare })
        XCTAssertTrue(results.contains { $0.endingType == .unclearDisclosure })
        XCTAssertTrue(results.contains { $0.endingType == .voluntaryAndShared || $0.endingType == .standardLight })

        for result in results {
            XCTAssertEqual(Set(result.campaign.consequenceEchoes.map(\.id)).count, result.campaign.consequenceEchoes.count, result.id)
            XCTAssertTrue(result.decisionTrace.contains { $0.contains("4.risk") }, result.id)
            XCTAssertTrue(result.decisionTrace.contains { $0.contains("5.rumor") }, result.id)
            XCTAssertEqual(result.campaign.sharedSelf, result.intent.shareChoiceID == "share", result.id)
        }
    }

    func testAdultHandoffCommitsRouteAndCounselingEntryAtomically() {
        var campaign = NarrativeCampaign(isActive: true, chapter: .stairwell)
        campaign.companionID = "许栀"
        campaign.momentIndex = 3
        campaign.safetyHandoffState = NarrativeSafetyHandoffState(authoredRisk: .high)

        campaign.choose("contactAdult")
        XCTAssertEqual(campaign.currentMoment.id, "4.handoff")
        XCTAssertEqual(campaign.safetyHandoffState?.contactMethod, "消息")
        XCTAssertTrue(campaign.safetyHandoffState?.adultContactInitiated == true)
        XCTAssertNil(campaign.safetyHandoffState?.route)
        XCTAssertFalse(campaign.safetyHandoffState?.safetyHandoffComplete == true)

        campaign.exploration.lastInteractedHotspot = "handoff.teacher"
        campaign.choose("holdSafeSpace")
        XCTAssertEqual(campaign.chapter, .counseling)
        XCTAssertEqual(campaign.safetyHandoffState?.route, .urgentSchoolResponse)
        XCTAssertEqual(campaign.safetyHandoffState?.entryMode, .urgentHandoffWaiting)
        XCTAssertTrue(campaign.safetyHandoffState?.safetyHandoffComplete == true)
        XCTAssertEqual(campaign.counselingState?.entryMode, .urgentHandoffWaiting)
        XCTAssertEqual(campaign.safetyRoute, "校内紧急支持")
    }

    func testRealPlayerRoutePreservesConsequencesAcrossAllSixChapters() {
        var campaign = NarrativeCampaign()
        campaign.startAfterPlayableChapterOne()
        var visitedMoments: [String] = []

        for _ in 0..<maximumCampaignSteps where campaign.isComplete == false {
            let moment = campaign.currentMoment
            visitedMoments.append(moment.id)

            switch moment.miniGame {
            case .trace:
                campaign.performMiniGameAction(3)
                XCTAssertEqual(campaign.miniGameProgress, 0, "描线必须从玩家眼前的第一个节点开始")
                for slot in 0..<NarrativeMiniGame.trace.requiredInteractions { campaign.performMiniGameAction(slot) }
            case .melody:
                campaign.performMiniGameAction(0)
                XCTAssertEqual(campaign.miniGameProgress, 0, "按错节奏后应允许玩家重试")
                for slot in [1, 3, 0, 2] { campaign.performMiniGameAction(slot) }
            case .erase:
                for slot in [5, 2, 0, 4, 1, 3] { campaign.performMiniGameAction(slot) }
            case nil:
                break
            }

            let choiceID: String
            switch moment.id {
            case "2.listen": choiceID = "invite"
            case "3.companion": choiceID = "xu"
            case "4.risk": choiceID = "askSafety"
            case "4.contact": choiceID = "contactAdult"
            case "4.handoff": choiceID = "followAdultPlan"
            case "5.rumor": choiceID = "privacy"
            case "6.share": choiceID = "share"
            default: choiceID = moment.choices[0].id
            }
            dismissRiskEducationCardIfNeeded(campaign: &campaign)
            completeNoteTraceDepartureIfNeeded(campaign: &campaign)
            if moment.id == "4.handoff" {
                campaign.exploration.lastInteractedHotspot = "handoff.teacher"
            }
            campaign.choose(choiceID)
        }

        XCTAssertTrue(campaign.isComplete, "Campaign stopped at \(campaign.currentMoment.id)")
        XCTAssertEqual(Set(visitedMoments), campaign.completedMomentIDs.subtracting(
            Set(NarrativeCampaign.moments(for: .classroom).map(\.id))
        ))
        XCTAssertEqual(campaign.companionID, "许栀")
        XCTAssertEqual(campaign.safetyRoute, "咨询室陪同")
        XCTAssertEqual(campaign.safetyHandoffState?.route, .standardCounseling)
        XCTAssertEqual(campaign.counselingState?.entryMode, .standardWaiting)
        XCTAssertTrue(campaign.counselingState?.supportHandedOff == true)
        XCTAssertGreaterThanOrEqual(campaign.linCheTrust, 3)
        XCTAssertGreaterThanOrEqual(campaign.jiangYueTrust, 2)
        XCTAssertTrue(campaign.privacyProtected)
        XCTAssertTrue(campaign.sharedSelf)
        XCTAssertEqual(campaign.miniGameHintCount, 0, "进入下一场景后提示计数应清零")
    }

    func testCompleteCampaignVisitsEveryChapterAndMiniGame() {
        var campaign = NarrativeCampaign()
        campaign.start()
        var visitedChapters = Set<NarrativeChapter>()
        var completedMiniGames = Set<NarrativeMiniGame>()

        for _ in 0..<maximumCampaignSteps where campaign.isComplete == false {
            visitedChapters.insert(campaign.chapter)
            let moment = campaign.currentMoment
            if let miniGame = moment.miniGame {
                while campaign.miniGameCompleted == false {
                    campaign.progressMiniGame()
                }
                completedMiniGames.insert(miniGame)
            }
            dismissRiskEducationCardIfNeeded(campaign: &campaign)
            completeNoteTraceDepartureIfNeeded(campaign: &campaign)
            if moment.id == "4.handoff" {
                campaign.exploration.lastInteractedHotspot = "handoff.teacher"
            }
            campaign.choose(try! XCTUnwrap(moment.choices.first).id)
        }

        XCTAssertEqual(visitedChapters, Set(NarrativeChapter.allCases))
        XCTAssertEqual(completedMiniGames, Set(NarrativeMiniGame.allCases))
        XCTAssertTrue(campaign.isComplete)
        XCTAssertEqual(campaign.chapter, .epilogue)
        XCTAssertTrue(campaign.isActive)
    }

    func testMiniGamesRequireTheirFullInteractionCount() {
        for miniGame in NarrativeMiniGame.allCases {
            var campaign = NarrativeCampaign()
            campaign.start()
            for _ in 0..<maximumCampaignSteps where campaign.currentMoment.miniGame != miniGame {
                let moment = campaign.currentMoment
                if moment.miniGame != nil {
                    while campaign.miniGameCompleted == false { campaign.progressMiniGame() }
                }
                dismissRiskEducationCardIfNeeded(campaign: &campaign)
                completeNoteTraceDepartureIfNeeded(campaign: &campaign)
                campaign.choose(try! XCTUnwrap(moment.choices.first).id)
            }
            XCTAssertEqual(campaign.currentMoment.miniGame, miniGame, "Campaign stopped at \(campaign.currentMoment.id)")

            let requiredCount = miniGame.requiredInteractions
            for _ in 0..<(requiredCount - 1) { campaign.progressMiniGame() }
            XCTAssertFalse(campaign.miniGameCompleted)
            campaign.progressMiniGame()
            XCTAssertTrue(campaign.miniGameCompleted)
        }
    }

    func testInteractiveMiniGamesRequireTheirAuthoredActions() {
        var campaign = NarrativeCampaign()
        campaign.start()
        advanceToMiniGame(.trace, campaign: &campaign)
        campaign.performMiniGameAction(2)
        XCTAssertEqual(campaign.miniGameProgress, 0)
        for slot in 0..<NarrativeMiniGame.trace.requiredInteractions { campaign.performMiniGameAction(slot) }
        XCTAssertTrue(campaign.miniGameCompleted)

        campaign.choose(campaign.currentMoment.choices[0].id)
        advanceToMiniGame(.melody, campaign: &campaign)
        campaign.replayMiniGameCue()
        XCTAssertEqual(campaign.miniGameProgress, 0)
        XCTAssertEqual(campaign.miniGameHintCount, 1)
        campaign.performMiniGameAction(0)
        XCTAssertEqual(campaign.miniGameProgress, 0)
        XCTAssertEqual(campaign.miniGameHintCount, 2)
        for slot in [1, 3, 0, 2] { campaign.performMiniGameAction(slot) }
        XCTAssertTrue(campaign.miniGameCompleted)

        var melodyAutoPassCampaign = NarrativeCampaign()
        melodyAutoPassCampaign.start()
        advanceToMiniGame(.melody, campaign: &melodyAutoPassCampaign)
        for _ in 0..<3 { melodyAutoPassCampaign.performMiniGameAction(0) }
        XCTAssertTrue(melodyAutoPassCampaign.miniGameCompleted)

        var melodyReplayAutoPassCampaign = NarrativeCampaign()
        melodyReplayAutoPassCampaign.start()
        advanceToMiniGame(.melody, campaign: &melodyReplayAutoPassCampaign)
        for _ in 0..<3 { melodyReplayAutoPassCampaign.replayMiniGameCue() }
        XCTAssertTrue(melodyReplayAutoPassCampaign.miniGameCompleted)

        campaign.choose(campaign.currentMoment.choices[0].id)
        advanceToMiniGame(.erase, campaign: &campaign)
        campaign.performMiniGameAction(2)
        campaign.performMiniGameAction(2)
        XCTAssertEqual(campaign.miniGameProgress, 1)
        for slot in [0, 1, 3] { campaign.performMiniGameAction(slot) }
        XCTAssertTrue(campaign.miniGameCompleted)
    }

    func testEraseMiniGameCompletesAtSixtyPercentAndPreservesRemainder() {
        var campaign = NarrativeCampaign()
        campaign.start()
        advanceToMiniGame(.erase, campaign: &campaign)

        campaign.performMiniGameAction(99)
        campaign.performMiniGameAction(-1)
        XCTAssertEqual(campaign.miniGameTouchedSlots.count, 0)
        XCTAssertEqual(campaign.miniGameProgress, 0)

        for slot in [0, 1, 2] { campaign.performMiniGameAction(slot) }
        XCTAssertFalse(campaign.miniGameCompleted)
        XCTAssertEqual(campaign.miniGameTouchedSlots.count, 3)

        campaign.performMiniGameAction(3)
        XCTAssertTrue(campaign.miniGameCompleted)
        XCTAssertEqual(campaign.miniGameTouchedSlots.count, NarrativeMiniGame.erase.requiredInteractions)

        campaign.performMiniGameAction(4)
        campaign.performMiniGameAction(5)
        XCTAssertEqual(campaign.miniGameTouchedSlots.count, NarrativeMiniGame.erase.requiredInteractions)
        XCTAssertFalse(campaign.miniGameTouchedSlots.contains(4))
        XCTAssertFalse(campaign.miniGameTouchedSlots.contains(5))
    }

    func testAccessibleMiniGameCompletionFinishesWithoutClearingEraseRemainder() {
        var traceCampaign = NarrativeCampaign()
        traceCampaign.start()
        advanceToMiniGame(.trace, campaign: &traceCampaign)
        traceCampaign.completeMiniGameAccessibly()
        XCTAssertTrue(traceCampaign.miniGameCompleted)
        XCTAssertEqual(traceCampaign.miniGameProgress, NarrativeMiniGame.trace.requiredInteractions)

        var melodyCampaign = NarrativeCampaign()
        melodyCampaign.start()
        advanceToMiniGame(.melody, campaign: &melodyCampaign)
        melodyCampaign.completeMiniGameAccessibly()
        XCTAssertTrue(melodyCampaign.miniGameCompleted)
        XCTAssertEqual(melodyCampaign.miniGameProgress, NarrativeMiniGame.melody.requiredInteractions)

        var eraseCampaign = NarrativeCampaign()
        eraseCampaign.start()
        advanceToMiniGame(.erase, campaign: &eraseCampaign)
        eraseCampaign.performMiniGameAction(4)
        eraseCampaign.performMiniGameAction(5)
        eraseCampaign.completeMiniGameAccessibly()
        XCTAssertTrue(eraseCampaign.miniGameCompleted)
        XCTAssertEqual(eraseCampaign.miniGameTouchedSlots.count, NarrativeMiniGame.erase.requiredInteractions)
        XCTAssertTrue(eraseCampaign.miniGameTouchedSlots.contains(4))
        XCTAssertTrue(eraseCampaign.miniGameTouchedSlots.contains(5))
        XCTAssertFalse(eraseCampaign.miniGameTouchedSlots.contains(2))
        XCTAssertFalse(eraseCampaign.miniGameTouchedSlots.contains(3))
    }

    func testCompletedMiniGameRouteCopyPointsToTheNextLampOrDialogue() {
        XCTAssertEqual(NarrativeMiniGame.trace.completionRouteTitle, "让草稿灯把路接到旋律灯")
        XCTAssertTrue(NarrativeMiniGame.trace.completionRouteDetail.contains("下一盏"))

        XCTAssertEqual(NarrativeMiniGame.melody.completionRouteTitle, "跟着旋律灯走到擦痕灯")
        XCTAssertTrue(NarrativeMiniGame.melody.completionRouteDetail.contains("最后一盏"))

        XCTAssertEqual(NarrativeMiniGame.erase.completionRouteTitle, "让三盏灯一起照回林澈身边")
        XCTAssertTrue(NarrativeMiniGame.erase.completionRouteDetail.contains("真实的话"))
    }

    func testMirrorDissolveProgressStartsAfterThirdLampAndCompletesAtLinCheDialogue() {
        var campaign = NarrativeCampaign()
        campaign.startAfterPlayableChapterOne()
        XCTAssertEqual(campaign.mirrorDissolveProgress, 0)

        advanceToMiniGame(.erase, campaign: &campaign)
        XCTAssertEqual(campaign.currentMoment.id, "2.erase")
        XCTAssertEqual(campaign.mirrorDissolveProgress, 0)

        for slot in 0..<NarrativeMiniGame.erase.requiredInteractions {
            campaign.performMiniGameAction(slot)
        }

        XCTAssertTrue(campaign.miniGameCompleted)
        XCTAssertEqual(campaign.mirrorDissolveProgress, 0.72, accuracy: 0.001)

        campaign.choose("playErase")
        XCTAssertEqual(campaign.currentMoment.id, "2.listen")
        XCTAssertEqual(campaign.mirrorDissolveProgress, 1, accuracy: 0.001)

        campaign.choose("invite")
        XCTAssertEqual(campaign.chapter, .noteTrace)
        XCTAssertEqual(campaign.mirrorDissolveProgress, 1, accuracy: 0.001)
    }

    private func advanceToMiniGame(_ target: NarrativeMiniGame, campaign: inout NarrativeCampaign) {
        for _ in 0..<maximumCampaignSteps where campaign.currentMoment.miniGame != target {
            let moment = campaign.currentMoment
            if moment.miniGame != nil {
                while campaign.miniGameCompleted == false { campaign.progressMiniGame() }
            }
            dismissRiskEducationCardIfNeeded(campaign: &campaign)
            completeNoteTraceDepartureIfNeeded(campaign: &campaign)
            campaign.choose(moment.choices[0].id)
        }
        XCTAssertEqual(campaign.currentMoment.miniGame, target, "Campaign stopped at \(campaign.currentMoment.id)")
    }

    private func completeNoteTraceDepartureIfNeeded(campaign: inout NarrativeCampaign) {
        guard campaign.currentMoment.id == "3.locate" else { return }
        campaign.recordNoteTraceDepartureClue(for: "note.deskTrace")
        campaign.recordNoteTraceDepartureClue(for: "note.paperTrail")
    }

    private func dismissRiskEducationCardIfNeeded(campaign: inout NarrativeCampaign) {
        if campaign.shouldPresentRiskEducationCard {
            campaign.dismissRiskEducationCard()
        }
    }
}
