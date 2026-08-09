import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var game: GameManager
    @State private var isPerceptionPanelPresented = false

    private var currentSoundscape: SensorySoundscape {
        game.currentSensorySoundscape
    }

    private var currentPeerCue: SensoryPeerCue? {
        game.sensoryPeerCue
    }

    private var currentSpatialObjective: SpatialAudioObjective? {
        game.currentSpatialAudioObjective
    }

    var body: some View {
        ZStack {
            ClassroomSceneView(game: game)
                .ignoresSafeArea()

            if game.isPrologueActive == false {
                vignette
                if let feedback = game.focusFeedbackTrigger {
                    FocusFeedbackOverlay(feedback: feedback, reduceMotion: game.accessibilityPreferences.reduceMotion)
                        .allowsHitTesting(false)
                        .zIndex(12)
                }
            }
            if game.isPrologueActive == false {
                peripheralIndicators
                eventCinematicLayer
            }

            if game.narrativeCampaign.isActive {
                NarrativeCampaignView(game: game)
                    .zIndex(15)
                if let microGame = game.activeNarrativeMicroGame {
                    MicroGameOverlayView(game: game, miniGame: microGame)
                        .zIndex(38)
                }
            } else if case .menu = game.gameState {
                menuOverlay
            } else if game.isPrologueActive {
                prologueHUD
            } else if game.isFullNarrativeRun, game.shouldUseMinimalNarrativeHUD == false {
                fullNarrativeGameplayHUD
            } else {
                VStack(spacing: 0) {
                    topHUD
                    modePanel
                    Spacer()
                    messagePanel
                    actionBar
                }
                .padding(18)
            }

            if game.narrativeCampaign.isActive == false, case .event(let event) = game.gameState {
                eventOverlay(event)
            }

            if game.narrativeCampaign.isActive == false, case .ending(let ending) = game.gameState {
                endingOverlay(ending)
            }

            if isPerceptionPanelPresented {
                perceptionPanel
            }

            if game.isAccessibilityPanelPresented {
                accessibilityPanel
                    .zIndex(90)
            }

            if game.isGameGuidePresented {
                gameGuideOverlay
                    .zIndex(40)
            }

            if game.isChapterOneTransitionPresented {
                chapterOneTransitionOverlay
                    .zIndex(45)
            }

            if game.isPrologueActive && game.isPrologueTutorialPresented {
                prologueTutorialOverlay
                    .zIndex(28)
            }

            if game.isPrologueActive && game.prologuePaused && game.isAccessibilityPanelPresented == false && game.isPrologueTutorialPresented == false {
                prologuePauseOverlay
                    .zIndex(82)
            }

            if game.shouldShowNarrativePauseOverlay && game.isAccessibilityPanelPresented == false {
                narrativePauseOverlay
                    .zIndex(84)
            }

            if game.isDeveloperPanelPresented {
                developerPanel
                    .zIndex(60)
            }

            returnToSeatTransitionLayer

            if let monologue = game.featuredMonologue {
                featuredMonologueLayer(monologue)
                    .transition(.opacity)
                    .zIndex(20)
            }

            if game.scenePresentation.isActive {
                scenePresentationLayer
                    .zIndex(70)
            }

            if game.shouldUseMinimalNarrativeHUD {
                narrativeMinimalHUDOverlay
                    .zIndex(72)
            }

            if shouldShowMainQuestHUD {
                mainQuestHUDOverlay
                    .zIndex(73)
            }

            if game.isAutonomousPlayEnabled,
               game.scenePresentation.isActive == false,
               game.featuredMonologue == nil {
                autonomousDirectorOverlay
                    .zIndex(74)
            }
        }
        .animation(.easeInOut(duration: 0.55), value: game.featuredMonologue?.id)
        .onChange(of: game.accessibilityPreferences) { _, _ in
            game.applyAccessibilityPreferences()
        }
        .onAppear {
            game.beginInitialGameGuideIfNeeded()
        }
        .foregroundStyle(.white)
    }

    private var autonomousDirectorOverlay: some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom) {
                AutonomousDirectorOverlay(
                    status: game.autonomousPlayStatus,
                    decision: game.autonomousPlayLastDecision,
                    stepCount: game.autonomousPlayStepCount,
                    soundscape: currentSoundscape,
                    peerCue: currentPeerCue,
                    latestEntry: game.playtestRouteTranscript.last,
                    onTakeover: {
                        game.stopAutonomousPlay(reason: "玩家接管")
                    }
                )
                .frame(width: 370)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 92)
        }
        .allowsHitTesting(true)
    }

    private var shouldShowMainQuestHUD: Bool {
        game.scenePresentation.isActive == false
            && game.featuredMonologue == nil
            && game.isPrologueActive == false
            && game.narrativeCampaign.isComplete == false
            && game.isAccessibilityPanelPresented == false
            && game.narrativePaused == false
            && game.isDeveloperPanelPresented == false
            && game.activeRole.isTeacher == false
            && game.narrativeCampaign.isActive == false
            && game.gameState == .playing
    }

    private var mainQuestHUDOverlay: some View {
        VStack(alignment: .leading, spacing: 8) {
            MainQuestHUD(
                item: mainQuestHUDItem,
                reduceMotion: game.accessibilityPreferences.reduceMotion
            )
            if game.activeRole.isTeacher == false {
                ClassroomSupportWeatherStripView(
                    classmates: game.classmates,
                    playerSupport: game.player.support
                )
                .frame(width: MainQuestHUD.width)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.leading, 16)
        .padding(.top, 16)
        .allowsHitTesting(false)
    }

    private var mainQuestHUDItem: MainQuestHUDItem {
        if game.narrativeCampaign.isActive {
            let moment = game.narrativeCampaign.currentMoment
            return MainQuestHUDItem(
                quest: game.narrativeCampaign.chapter.title,
                currentGoal: moment.goal,
                hint: game.narrativeCampaign.progressText,
                isUrgent: moment.id.hasPrefix("4.") || moment.id.hasPrefix("5.rumor")
            )
        }
        return MainQuestHUDItem(
            quest: game.activeChapter.rawValue,
            currentGoal: game.chapterCurrentObjective,
            hint: game.chapterProgressText,
            isUrgent: game.chapterOneStep == .inspectNote || game.chapterOneStep == .followLinChe
        )
    }

    private var fullNarrativeGameplayHUD: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    ChapterClueStackView(clues: game.chapterClues)
                }
                Spacer()
                narrativeKeyboardFocusChip
                audioCueStrip
                Button { game.openNarrativePauseMenu() } label: {
                    Image(systemName: "pause.fill")
                        .frame(width: 34, height: 30)
                }
                .buttonStyle(SegmentButtonStyle(isSelected: false))
                .help("暂停")
            }
            Spacer(minLength: 20)
            messagePanel
            actionBar
        }
        .padding(18)
    }

    private var narrativeKeyboardFocusChip: some View {
        Group {
            if game.accessibilityPreferences.keyboardAlternativeInput,
               let target = game.focusedNarrativeKeyboardTarget {
                Label(target.title, systemImage: target.symbol)
                    .font(.system(size: 11, weight: .bold))
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .liquidGlassPanel(tint: target.requiresMovement ? .mint.opacity(0.08) : .cyan.opacity(0.08))
                    .help("Tab 切换目标，Enter/空格确认")
            }
        }
    }

    private var narrativeMinimalHUDOverlay: some View {
        VStack {
            HStack {
                Spacer()
                NarrativeMinimalHUDControls(
                    captionsEnabled: game.accessibilityPreferences.directionalSubtitles,
                    onToggleCaptions: {
                        game.updateAccessibilityPreferences { $0.directionalSubtitles.toggle() }
                    },
                    onPause: {
                        game.openNarrativePauseMenu()
                    }
                )
            }
            Spacer()
        }
        .padding(18)
    }

    private var developerPanel: some View {
        VStack {
            HStack {
                Spacer()
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("状态机控制台", systemImage: "wrench.and.screwdriver.fill")
                            .font(.system(size: 14, weight: .bold))
                        Spacer()
                        Button { game.isDeveloperPanelPresented = false } label: {
                            Image(systemName: "xmark").frame(width: 26, height: 24)
                        }
                        .buttonStyle(SegmentButtonStyle(isSelected: false))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(game.developerPlaytestStatus)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(game.developerPlaytestStatus.contains("通过") ? .mint : .white)
                        Text(game.developerStateSummary)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(2)
                    }

                    HStack(spacing: 7) {
                        ForEach(NarrativeChapter.allCases) { chapter in
                            Button { game.developerJump(to: chapter) } label: {
                                Text("\(chapter.rawValue)")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .frame(width: 27, height: 25)
                            }
                            .buttonStyle(SegmentButtonStyle(isSelected: game.narrativeCampaign.isActive && game.narrativeCampaign.chapter == chapter))
                            .help(chapter.title)
                        }
                    }

                    HStack(spacing: 8) {
                        Button { game.startDeveloperAutoplay() } label: {
                            Label("全流程", systemImage: "play.fill")
                                .frame(maxWidth: .infinity, minHeight: 30)
                        }
                        .buttonStyle(SegmentButtonStyle(isSelected: game.developerPlaytestStatus == "运行中"))
                        Button { game.developerAdvanceOneStep() } label: {
                            Image(systemName: "forward.frame.fill")
                                .frame(width: 34, height: 30)
                        }
                        .buttonStyle(SegmentButtonStyle(isSelected: false))
                        .help("提交一次真实状态机输入")
                        Button { game.stopDeveloperAutoplay() } label: {
                            Image(systemName: "stop.fill")
                                .frame(width: 34, height: 30)
                        }
                        .buttonStyle(SegmentButtonStyle(isSelected: false))
                        .help("停止自动游玩")
                    }

                    Divider().overlay(.white.opacity(0.18))
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(game.developerPlaytestLog.suffix(6).enumerated()), id: \.offset) { _, entry in
                            Text(entry)
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.65))
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 66, alignment: .topLeading)

                    Divider().overlay(.white.opacity(0.18))
                    PlaytestRouteTranscriptView(entries: Array(game.playtestRouteTranscript.suffix(4)))

                    Divider().overlay(.white.opacity(0.18))
                    NarrativeIntegrationMatrixView(results: NarrativeIntegrationMatrix.results, compact: true)

                    Divider().overlay(.white.opacity(0.18))
                    AutonomousRouteAuditView(results: AutonomousRouteAuditor.runAll(), compact: true)
                }
                .padding(14)
                .frame(width: 380)
                .liquidGlassPanel(tint: .black.opacity(0.34))
            }
            Spacer()
        }
        .padding(18)
    }

    private var menuOverlay: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Text("晚自习模拟器")
                    .font(.system(size: 34, weight: .bold))
                Text("3D 第一视角心理健康体验")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
            }

            Button {
                if game.hasCompletedInitialGameGuide {
                    game.presentGameGuide()
                }
            } label: {
                VStack(spacing: 5) {
                    Text("游戏说明")
                        .font(.custom("Songti SC", size: 25).weight(.bold))
                    if game.hasCompletedInitialGameGuide == false {
                        Text("\(game.menuGuideCountdown) 秒后自动跳转")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.64))
                    } else {
                        Text("点击再次查看")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .disabled(game.hasCompletedInitialGameGuide == false)

            VStack(alignment: .leading, spacing: 10) {
                Text(game.prologueState.prologueCompleted ? "从哪里开始" : "序章 · 铃响之前")
                    .font(.system(size: 13, weight: .bold))
                Text(game.prologueState.prologueCompleted
                     ? "你已经熟悉基本操作，可以重新走进铃响前的教室，也可以直接开始第一章。"
                     : "先走进教学楼，认识视角、移动、互动和自我照顾。这里没有失败，也没有需要背下来的正确答案。")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .liquidGlassPanel()

            if game.hasContinuableNarrativeSave {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "tray.and.arrow.down.fill")
                            .foregroundStyle(.mint)
                        Text(game.narrativeSaveTitle)
                            .font(.system(size: 13, weight: .bold))
                        Spacer()
                        Text("稳定检查点")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.mint.opacity(0.86))
                    }
                    Text(game.narrativeSaveDetail)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                    Button { game.continueNarrativeSaveFromMenu() } label: {
                        Label("继续旅程", systemImage: "play.fill")
                            .frame(width: 180, height: 38)
                    }
                    .buttonStyle(ActionButtonStyle())
                    .keyboardShortcut(.defaultAction)
                }
                .padding(12)
                .frame(width: 340, alignment: .leading)
                .liquidGlassPanel(tint: .mint.opacity(0.08))
            }

            if game.prologueState.prologueCompleted {
                HStack(spacing: 12) {
                    Button { game.startExperience(forcePrologue: true) } label: {
                        Label("进入序章", systemImage: "building.2.fill")
                            .frame(width: 150, height: 38)
                    }
                    .buttonStyle(ActionButtonStyle())
                    .disabled(game.isMenuEntryLocked)
                    Button { game.startFullNarrativeCampaign() } label: {
                        Label("直接六章主线", systemImage: "book.fill")
                            .frame(width: 150, height: 38)
                    }
                    .buttonStyle(ActionButtonStyle())
                    .disabled(game.isMenuEntryLocked)
                    .keyboardShortcut(.defaultAction)
                }
            } else {
                Button {
                    game.startExperience()
                } label: {
                    Label("走进教学楼", systemImage: "door.left.hand.open")
                        .frame(width: 180, height: 38)
                }
                .buttonStyle(ActionButtonStyle())
                .disabled(game.isMenuEntryLocked)
                .keyboardShortcut(.defaultAction)
            }

            Button { game.startFullNarrativeCampaign() } label: {
                Label("完整六章叙事", systemImage: "sparkles.rectangle.stack")
                    .frame(width: 180, height: 38)
            }
            .buttonStyle(ActionButtonStyle())
            .help("从静音的教室一路走到咨询室，含镜像三灯互动、同伴选择与安全交接")

        }
        .padding(26)
        .liquidGlassPanel()
    }

    private var gameGuideOverlay: some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("晚自习模拟器")
                            .font(.custom("Songti SC", size: 34).weight(.bold))
                        Text("六章互动叙事")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white.opacity(0.52))
                    }
                    Spacer()
                    Image(systemName: "book.pages.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.white.opacity(0.52))
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        Text("你将以学生苏念的第一视角，走进一场普通的晚自习。留意那些没有说出口的需要，也别忘记自己的呼吸和疲惫。")
                            .font(.custom("Kaiti SC", size: 18))
                            .lineSpacing(6)
                            .foregroundStyle(.white.opacity(0.88))

                        HStack(alignment: .top, spacing: 28) {
                            guideSection(
                                title: "六章故事",
                                icon: "book.pages.fill",
                                text: "阅读当前场景并作出选择。重要选择会改变信任、陪伴方式和最终支持路线。"
                            )
                            guideSection(
                                title: "空间互动",
                                icon: "figure.walk",
                                text: "需要调查时，界面会给出明确的靠近按钮；也可以用 WASD 自己探索。"
                            )
                            guideSection(
                                title: "内容提醒",
                                icon: "heart.text.square.fill",
                                text: "故事涉及学业压力、情绪低落和求助。它用于理解与体验，不替代心理咨询、医学诊断或现实中的紧急帮助。"
                            )
                        }

                    }
                }
                .frame(maxHeight: 300)

                Divider().overlay(.white.opacity(0.12))

                HStack {
                    Text("先照顾好自己，再试着看见别人。")
                        .font(.custom("Kaiti SC", size: 16))
                        .foregroundStyle(.white.opacity(0.62))
                    Spacer()
                    Button {
                        game.dismissGameGuide()
                    } label: {
                        if game.gameGuideExitCountdown > 0 {
                            Label("请阅读 \(game.gameGuideExitCountdown) 秒", systemImage: "lock.fill")
                                .frame(width: 160, height: 40)
                        } else {
                            Label("我已了解", systemImage: "checkmark")
                                .frame(width: 160, height: 40)
                        }
                    }
                    .buttonStyle(ActionButtonStyle())
                    .disabled(game.gameGuideExitCountdown > 0)
                }
            }
            .padding(34)
            .frame(maxWidth: 920)
            .background(Color.black.opacity(0.78))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.white.opacity(0.16), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func guideSection(title: String, icon: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: icon)
                .font(.system(size: 14, weight: .bold))
            Text(text)
                .font(.custom("Kaiti SC", size: 15))
                .foregroundStyle(.white.opacity(0.72))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chapterOneTransitionOverlay: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
                .transition(.opacity)
            VStack(spacing: 18) {
                Text("序章结束")
                    .font(.custom("Songti SC", size: 28).weight(.semibold))
                Text("铃响以后，真正需要被看见的事才刚刚开始。")
                    .font(.custom("Kaiti SC", size: 17))
                    .foregroundStyle(.white.opacity(0.68))
                Button {
                    game.enterChapterOneAfterPrologue()
                } label: {
                    Label("进入第一章", systemImage: "arrow.right.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 180, height: 42)
                }
                .buttonStyle(ActionButtonStyle())
                .keyboardShortcut(.defaultAction)
                Button {
                    game.restartPrologueTutorial()
                } label: {
                    Label("重新学习基础操作", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 180, height: 36)
                }
                .buttonStyle(ActionButtonStyle())
            }
            .padding(28)
            .transition(.opacity)
        }
        .animation(.easeIn(duration: 1.2), value: game.isChapterOneTransitionPresented)
    }

    private var gameGuideCharacters: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("主要人物", systemImage: "person.3.fill")
                .font(.system(size: 15, weight: .bold))
            Text("苏念：玩家角色，高二（3）班新任心理委员。她善于观察，也承受着自己的学业与家庭压力。\n林澈：苏念的同桌，成绩优秀，却被完美主义困住。\n江越：求助纸条的主人，主线中真正需要被可靠支持接住的人。\n周予安、许栀、陈言：以不同方式参与协作的班干部。\n方老师与心理老师：成人支持和专业帮助的承接者。")
                .font(.custom("Kaiti SC", size: 15))
                .foregroundStyle(.white.opacity(0.74))
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var gameGuideChapterRoadmap: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("六章故事规划", systemImage: "map.fill")
                .font(.system(size: 15, weight: .bold))
            Text("故事会从教室一路走到咨询室。选择不会给出标准答案，但会改变信任、陪伴方式与最终支持路线。")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
            Text("1 静音的教室：发现异常与求助纸条。\n2 走廊的镜子：练习倾听，不急着说教。\n3 那张纸条：确认求助者与去向。\n4 13 楼的缝隙：陪江越留下并判断风险。\n5 有灯亮着的房间：把支持交给可靠成人。\n6 这里有光：看见支持网络，也允许苏念被帮助。")
                .font(.custom("Kaiti SC", size: 15))
                .foregroundStyle(.white.opacity(0.74))
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var prologueHUD: some View {
        ZStack(alignment: .topTrailing) {
            VStack {
                HStack {
                    if game.prologueCurrentBeat != .gateArrival {
                        prologueQuestPanel
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        Button { game.accessibilityPreferences.directionalSubtitles.toggle() } label: {
                            Image(systemName: game.accessibilityPreferences.directionalSubtitles ? "captions.bubble.fill" : "captions.bubble")
                                .frame(width: 30, height: 28)
                        }
                        .buttonStyle(SegmentButtonStyle(isSelected: game.accessibilityPreferences.directionalSubtitles))
                        .help("方向字幕")
                        Button { game.setProloguePaused(true) } label: {
                            Image(systemName: "pause.fill")
                                .frame(width: 30, height: 28)
                        }
                        .buttonStyle(SegmentButtonStyle(isSelected: false))
                        .help("暂停")
                    }
                    .liquidGlassPanel()
                }
                Spacer()
                if game.accessibilityPreferences.directionalSubtitles,
                   let subtitle = game.directionalSubtitleEvents.first,
                   subtitle.createdAt.timeIntervalSinceNow > -5 {
                    Text(subtitle.caption)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.black.opacity(0.48))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                Text(game.message)
                    .font(.custom("STXingkai", size: 20))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.94))
                    .frame(maxWidth: 760)
                    .padding(14)
                    .background(.black.opacity(0.48))
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                prologueControls
            }
            .padding(18)

            if game.prologueCurrentBeat == .accessibility {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        PrologueAccessibilityHintView(
                            onOpenSettings: { game.acknowledgeAccessibilityTutorial(openSettings: true) },
                            onContinue: { game.acknowledgeAccessibilityTutorial(openSettings: false) }
                        )
                        .padding(.trailing, 18)
                        .padding(.bottom, 18)
                    }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .animation(.easeInOut(duration: game.accessibilityPreferences.reduceMotion ? 0.2 : 0.3), value: game.prologueCurrentBeat)
            }
        }
    }

    private var prologueQuestPanel: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let step = game.prologueCurrentBeat.tutorialStep {
                Text("步骤：\(step)/\(PrologueBeatID.tutorialBeats.count)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
            } else {
                Text("序章 · 走进教学楼")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            Text(game.prologueCurrentBeat.currentGoal)
                .font(.custom("Songti SC", size: 16).weight(.semibold))
                .id(game.prologueCurrentBeat)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            Text(game.prologueCurrentBeat.tutorialInstruction)
                .font(.custom("Kaiti SC", size: 14))
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
            if game.prologueCurrentBeat == .lookDownHall {
                VStack(alignment: .leading, spacing: 3) {
                    Text("有效环视：\(game.prologueLookExplorationElapsed, specifier: "%.1f") / 5.0 秒")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                    Text("视角静止时暂停计时 · C 当前已锁定")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(.top, 5)
            } else if let remaining = game.prologueAutoAdvanceSecondsRemaining {
                VStack(alignment: .leading, spacing: 3) {
                    Text("再过 \(remaining) 秒将自动执行操作")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                    Text(game.prologueActionReady
                         ? "操作条件已满足 · 按 C 可提前完成"
                         : (game.prologueCurrentBeat == .returnToSeat && game.prologueSeatNearby
                            ? "已靠近座位 · 按 E 入座"
                            : "完成当前操作后解锁 C"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(.top, 5)
            }
            if let echo = game.prologueState.lastBeatEcho {
                PrologueBeatEchoView(echo: echo)
                .padding(.top, 4)
            }
        }
        .padding(13)
        .frame(width: 330, alignment: .leading)
        .liquidGlassPanel(cornerRadius: 8)
        .animation(.easeInOut(duration: 0.3), value: game.prologueCurrentBeat)
    }

    private var prologueTutorialOverlay: some View {
        ZStack {
            Color.black.opacity(0.76).ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Text("新手教程")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.58))
                    Spacer()
                    if let step = game.prologueCurrentBeat.tutorialStep {
                        Text("步骤：\(step)/\(PrologueBeatID.tutorialBeats.count)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.78))
                    }
                }

                Spacer().frame(height: 30)

                Text(game.prologueCurrentBeat.currentGoal)
                    .font(.custom("Songti SC", size: 34).weight(.semibold))
                    .multilineTextAlignment(.center)

                Text(game.prologueCurrentBeat.tutorialInstruction)
                    .font(.custom("Kaiti SC", size: 20))
                    .foregroundStyle(.white.opacity(0.82))
                    .multilineTextAlignment(.center)
                    .lineSpacing(7)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 680)
                    .padding(.top, 18)

                HStack(spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                    Text(game.prologueCurrentBeat == .lookDownHall
                         ? "按 T 可重新查看说明；本步骤必须完成 5 秒有效环视，C 无法跳过"
                         : "按 T 可重新查看说明；完成本步骤的核心操作后会解锁 C")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.58))
                .padding(.top, 24)

                Button {
                    game.dismissCurrentPrologueTutorial()
                } label: {
                    Label("确认并开始", systemImage: "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 180, height: 42)
                }
                .buttonStyle(ActionButtonStyle())
                .keyboardShortcut(.defaultAction)
                .padding(.top, 22)
            }
            .padding(32)
            .frame(width: 820)
            .frame(minHeight: 430)
            .background(Color.black.opacity(0.84))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.white.opacity(0.16), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.45), radius: 28, y: 12)
        }
        .transition(.opacity)
    }

    @ViewBuilder
    private var prologueControls: some View {
        switch game.prologueCurrentBeat {
        case .settleBreath:
            HStack(spacing: 10) {
                Button { game.execute(.breathe) } label: {
                    Label("深呼吸", systemImage: "wind").frame(width: 120, height: 36)
                }
                .buttonStyle(ActionButtonStyle())
                Button { game.acknowledgeSettleBreathWithoutAction() } label: {
                    Text("先坐一会儿").frame(width: 120, height: 36)
                }
                .buttonStyle(ActionButtonStyle())
            }
            .padding(.top, 8)
        case .placeWater:
            Text("空格 · 确认")
                .font(.system(size: 12, weight: .bold))
                .padding(.horizontal, 13)
                .frame(height: 32)
                .liquidGlassPanel()
        default:
            EmptyView()
        }
    }

    private var prologuePauseOverlay: some View {
        ZStack {
            Color.black.opacity(0.56).ignoresSafeArea()
            VStack(spacing: 14) {
                Text("已暂停").font(.system(size: 22, weight: .bold))
                Button("继续") { game.setProloguePaused(false) }
                    .buttonStyle(ActionButtonStyle())
                Button("辅助设置") {
                    game.isAccessibilityPanelPresented = true
                }
                .buttonStyle(ActionButtonStyle())
                Button("返回菜单") { game.returnToMenuForNewGame() }
                    .buttonStyle(ActionButtonStyle())
            }
            .padding(28)
            .liquidGlassPanel(cornerRadius: 8)
        }
    }

    private var narrativePauseOverlay: some View {
        ZStack {
            Color.black.opacity(0.58).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "pause.circle.fill")
                        .foregroundStyle(.mint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("旅程已暂停")
                            .font(.system(size: 22, weight: .bold))
                        Text(game.narrativeSaveTitle)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.68))
                    }
                    Spacer()
                }

                Text(game.narrativeSaveDetail)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)

                Divider().overlay(.white.opacity(0.18))

                HStack(spacing: 10) {
                    Button { game.resumeNarrativeFromPause() } label: {
                        Label("继续", systemImage: "play.fill")
                            .frame(width: 120, height: 34)
                    }
                    .buttonStyle(ActionButtonStyle())
                    .keyboardShortcut(.defaultAction)

                    Button { game.openAccessibilityPanel() } label: {
                        Label("辅助设置", systemImage: "accessibility")
                            .frame(width: 136, height: 34)
                    }
                    .buttonStyle(ActionButtonStyle())

                    Button { game.pauseNarrativeToMenu() } label: {
                        Label("回主菜单", systemImage: "rectangle.portrait.and.arrow.right")
                            .frame(width: 136, height: 34)
                    }
                    .buttonStyle(ActionButtonStyle())
                }
            }
            .padding(24)
            .frame(width: 470, alignment: .leading)
            .liquidGlassPanel(cornerRadius: 8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("旅程已暂停")
    }

    private var accessibilityPanel: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("辅助与体验设置").font(.system(size: 18, weight: .bold))
                    Spacer()
                    Button { game.closeAccessibilityPanel() } label: {
                        Image(systemName: "xmark").frame(width: 28, height: 28)
                    }
                    .buttonStyle(SegmentButtonStyle(isSelected: false))
                }
                Toggle("方向字幕", isOn: accessibilityBinding(\.directionalSubtitles))
                prologueVolumeSlider("对白", value: accessibilityBinding(\.dialogueVolume))
                prologueVolumeSlider("环境", value: accessibilityBinding(\.ambienceVolume))
                prologueVolumeSlider("提示音", value: accessibilityBinding(\.cueVolume))
                Toggle("减少动态效果", isOn: accessibilityBinding(\.reduceMotion))
                Toggle("键盘替代输入", isOn: accessibilityBinding(\.keyboardAlternativeInput))
                Text("这些设置会立即保留到后续章节。")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.58))
            }
            .toggleStyle(.switch)
            .padding(22)
            .frame(width: 430)
            .liquidGlassPanel(cornerRadius: 8)
        }
    }

    private func prologueVolumeSlider(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title).frame(width: 48, alignment: .leading)
            Slider(value: value, in: 0...1)
            Text("\(Int(value.wrappedValue * 100))%")
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 40, alignment: .trailing)
        }
    }

    private func accessibilityBinding<Value>(_ keyPath: WritableKeyPath<AccessibilityPreferences, Value>) -> Binding<Value> {
        Binding(
            get: { game.accessibilityPreferences[keyPath: keyPath] },
            set: { newValue in
                game.updateAccessibilityPreferences { preferences in
                    preferences[keyPath: keyPath] = newValue
                }
            }
        )
    }

    private var topHUD: some View {
        HStack(alignment: .top, spacing: 14) {
            compactChapterIdentity

            Spacer()
        }
    }

    private var compactChapterIdentity: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("苏念 · 心理委员")
                .font(.system(size: 13, weight: .bold))
            Text("\(game.clockText) · \(game.currentPeriod.displayName)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.65))
        }
        .padding(10)
        .frame(width: 180, alignment: .leading)
        .liquidGlassPanel()
    }

    private var fixedParameterPanel: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: game.activeRole.icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(game.activeRole.isTeacher ? .purple : .cyan)
                    .frame(width: 16)
                Text("固定参数")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Text("第 \(game.currentTurn)/\(game.maxTurns)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
            }
            fixedParameterRow("角色", value: "\(game.activeRole.rawValue) · \(game.activeRole.roleType)")
            fixedParameterRow("职责", value: game.activeRole.fixedDuty)
            fixedParameterRow("学校KPI", value: "\(Int(game.settings.rankingPressure))")
            fixedParameterRow("晚自习", value: "\(Int(game.settings.studyHours * 60)) 分钟 · \(game.currentPeriod.displayName)")
            fixedParameterRow("交流规则", value: game.settings.allowsWhispering ? "允许低声交流" : "禁止交流")
            fixedParameterRow("巡视要求", value: "\(Int(game.settings.patrolFrequency))")
        }
        .padding(10)
        .frame(width: 250, alignment: .topLeading)
        .liquidGlassPanel()
    }

    private func fixedParameterRow(_ title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 48, alignment: .leading)
            Text(value)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var roleStatusPanel: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("\(game.clockText) · \(game.currentPhase.rawValue) · \(game.viewMode.perspectiveDescription)")
                .font(.system(size: 12, weight: .bold))
            Text(game.activeRole.shortDescription)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.64))
                .fixedSize(horizontal: false, vertical: true)
            if game.activeRole.isTeacher {
                if let risk = game.highestRiskClassmate {
                    Text("重点关注：\(risk.name) · \(risk.state.rawValue) · \(risk.riskReason)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange.opacity(0.88))
                }
                Text("教师变量不再使用学生的作业/饥饿作为核心胜负指标，重点看班级风险、信任、疲惫和咨询容量。")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("\(game.cameraPose.visionZone.rawValue) · \(game.cameraPose.visionZone.displayName) · 姿态 \(game.player.posture.rawValue)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.cyan.opacity(0.84))
                if game.freeRoam.isActive {
                    Text("自由活动中 · 剩余 \(game.freeRoam.remainingSeconds)s · \(game.freeRoam.hasExitedClassroom ? "已到走廊" : "仍在教室")")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.mint.opacity(0.9))
                }
            }
        }
        .padding(10)
        .frame(width: 270, alignment: .topLeading)
        .liquidGlassPanel()
    }

    private var dynamicVariablePanel: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("动态变量")
                .font(.system(size: 13, weight: .bold))
            if game.activeRole.isTeacher {
                teacherDynamicMeters
            } else {
                studentDynamicMeters
            }
        }
        .padding(10)
        .frame(width: 230, alignment: .topLeading)
        .liquidGlassPanel()
    }

    private var studentDynamicMeters: some View {
        VStack(spacing: 8) {
            meter("心理能量", value: game.player.psychicEnergy, color: .green)
            meter("视觉注意力", value: game.player.visualAttention, color: .mint)
            meter("面具成本", value: game.player.maskCost, color: .purple)
            meter("支持网络", value: game.player.support, color: .cyan)
            meter("压力", value: game.player.stress, color: .orange)
            meter("暴露", value: game.player.exposure, color: .red)
            meter("作业", value: game.player.homework, color: .blue)
            meter("口渴", value: game.player.thirst, color: .cyan)
            meter("杯水", value: game.player.waterCup, color: .blue)
            meter("饥饿", value: game.player.hunger, color: .yellow)
            meter("如厕", value: game.player.bladder, color: .teal)
        }
    }

    private var teacherDynamicMeters: some View {
        VStack(spacing: 8) {
            meter("疲惫指数", value: game.teacher.fatigue, color: .orange)
            meter("制度压力", value: game.teacher.institutionalPressure, color: .red)
            meter("表面秩序", value: game.teacher.classOrder, color: .blue)
            meter("真实风险", value: game.teacher.classRisk, color: .red)
            meter("误判风险", value: game.teacher.misreadRisk, color: .yellow)
            meter("学生信任", value: game.teacher.studentTrust, color: .cyan)
            meter("同理心", value: game.teacher.empathy, color: .mint)
            meter("咨询容量", value: game.teacher.counselingCapacity, color: .green)
            teacherCounterRow("提醒", value: game.teacher.studentsWarned, tint: .orange)
            teacherCounterRow("关心", value: game.teacher.studentsHelped, tint: .cyan)
        }
    }

    private func teacherCounterRow(_ title: String, value: Int, tint: Color) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .medium))
            Spacer()
            Text("\(value)")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(tint.opacity(0.9))
        }
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("如果模式")
                    .font(.system(size: 11, weight: .bold))
                Spacer()
                if case .menu = game.gameState {
                    EmptyView()
                } else {
                    Button {
                        game.restartWithCurrentSettings()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .frame(width: 24, height: 20)
                    }
                    .buttonStyle(SegmentButtonStyle(isSelected: false))
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("可玩角色")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.72))
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(96), spacing: 6), count: 2), spacing: 6) {
                    ForEach(PlayableRole.selectableCases) { role in
                        Button {
                            game.selectedRole = role
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: role.icon)
                                    .font(.system(size: 13, weight: .bold))
                                Text(role.rawValue)
                                    .font(.system(size: 9, weight: .semibold))
                                    .lineLimit(1)
                                Text(role.roleType)
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.58))
                            }
                            .frame(width: 88, height: 52)
                        }
                        .buttonStyle(SegmentButtonStyle(isSelected: game.selectedRole == role))
                        .help(role.shortDescription)
                    }
                }
                Text(game.selectedRole.shortDescription)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .controlGlass()

            Toggle("允许低声交流", isOn: $game.settings.allowsWhispering)
                .font(.system(size: 10, weight: .medium))
                .toggleStyle(.checkbox)
                .controlGlass()

            settingSlider("时长", value: $game.settings.studyHours, range: 1...3, suffix: "h")
            settingSlider("排名", value: $game.settings.rankingPressure, range: 0...100, suffix: "")
            settingSlider("巡视", value: $game.settings.patrolFrequency, range: 0...100, suffix: "")

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: game.audioAssetStatus.hasAnyRealAsset ? "waveform.badge.checkmark" : "waveform")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(game.audioAssetStatus.hasAnyRealAsset ? .mint : .white.opacity(0.58))
                        .frame(width: 14)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("真实音频")
                            .font(.system(size: 9, weight: .semibold))
                        Text(game.audioAssetStatus.summary)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.62))
                    }
                    Spacer()
                    Text(game.audioAssetStatus.missingSummary)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(game.audioAssetStatus.missingTotal == 0 ? .mint.opacity(0.82) : .orange.opacity(0.82))
                }
                HStack(spacing: 6) {
                    audioToolButton("shoeprints.fill", help: "试听脚步声") { game.previewAudioCue(.footstep) }
                    audioToolButton("heart.fill", help: "试听心跳声") { game.previewAudioCue(.heartbeat) }
                    audioToolButton("doc.text.fill", help: "试听纸张声") { game.previewAudioCue(.paper) }
                    Spacer()
                    audioToolButton("arrow.clockwise", help: "刷新音频素材状态") { game.refreshAudioAssetStatus() }
                    audioToolButton("folder", help: "打开外部音频素材目录") { game.openExternalAudioDirectory() }
                }
            }
            .controlGlass()
            .help(game.audioAssetStatus.missingDetail)

            if !game.classmateMemory.isEmpty {
                HStack(spacing: 6) {
                    Label("\(game.classmateMemory.count) 个记忆", systemImage: "memorychip.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.mint.opacity(0.86))
                    Spacer()
                    Button {
                        game.clearClassmateMemory()
                    } label: {
                        Image(systemName: "trash")
                            .frame(width: 24, height: 20)
                    }
                    .buttonStyle(SegmentButtonStyle(isSelected: false))
                    .help("清除同学跨局记忆")
                }
                .controlGlass()
            }
        }
        .frame(width: 210)
    }

    private func settingSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10))
                .frame(width: 28, alignment: .leading)
            Slider(value: value, in: range)
            Text("\(Int(value.wrappedValue))\(suffix)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .frame(width: 34, alignment: .trailing)
        }
        .controlGlass()
    }

    private func audioToolButton(_ systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 24, height: 20)
        }
        .buttonStyle(SegmentButtonStyle(isSelected: false))
        .help(help)
    }

    private var modePanel: some View {
        HStack(alignment: .top, spacing: 12) {
            Label(game.activeRole.isTeacher ? "教师模式锁定" : "学生模式锁定", systemImage: game.activeRole.isTeacher ? "lock.fill" : "person.fill")
                .font(.system(size: 12, weight: .bold))
                .padding(.horizontal, 10)
                .frame(height: 32)
                .liquidGlassPanel(tint: game.activeRole.isTeacher ? .purple.opacity(0.18) : .cyan.opacity(0.14))

            if game.activeRole.isTeacher {
                teacherModeStrip
            } else {
                deskmateStrip
            }

            Spacer()

            audioCueStrip
            eventStrip
        }
        .padding(.top, 10)
    }

    private var teacherModeStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("位置")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.68))
                ForEach(TeacherLocation.allCases) { location in
                    Button {
                        game.setTeacherLocation(location)
                    } label: {
                        Image(systemName: location.icon)
                            .frame(width: 26, height: 24)
                    }
                    .buttonStyle(SegmentButtonStyle(isSelected: game.teacher.location == location))
                    .help(location.rawValue)
                }
                Text(game.teacher.location.rawValue)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.purple.opacity(0.86))
            }

            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("目标学生")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.68))
                    if let target = game.selectedTeacherTarget {
                        Text("\(target.name) · \(target.state.rawValue) · 压力 \(Int(target.stress)) · \(target.riskReason)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.orange.opacity(0.88))
                    }
                    Text(game.teacherFocusDescription)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 230, alignment: .leading)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(game.teacherTargetCandidates) { mate in
                            Button {
                                game.selectTeacherTarget(mate.id)
                            } label: {
                                VStack(spacing: 2) {
                                    Text(mate.name)
                                        .font(.system(size: 10, weight: .bold))
                                        .lineLimit(1)
                                    Text("\(Int(mate.stress)) · \(mate.state.rawValue)")
                                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.64))
                                }
                                .frame(width: 72, height: 38)
                            }
                            .buttonStyle(SegmentButtonStyle(isSelected: game.selectedTeacherTargetID == mate.id))
                            .help("\(mate.profile.traitLabel) · \(mate.riskReason)")
                        }
                    }
                }
                .frame(width: 330)
            }

            if game.isTeacherTruthRunActive {
                TeacherTruthRoutePanel(
                    summary: game.teacherTruthRunSummary,
                    objectives: game.teacherTruthObjectives
                )
            }

            HStack(spacing: 6) {
                ForEach(TeacherAction.allCases) { action in
                    Button {
                        game.executeTeacherAction(action)
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: action.icon)
                                .font(.system(size: 12, weight: .bold))
                            Text(action.rawValue)
                                .font(.system(size: 8.5, weight: .bold))
                                .lineLimit(1)
                        }
                        .frame(width: 66, height: 38)
                    }
                    .buttonStyle(SegmentButtonStyle(isSelected: game.currentTeacherTruthObjective?.action == action))
                    .help("教师行动 \(String(action.shortcut))：\(action.rawValue)")
                }
            }
        }
        .padding(10)
        .frame(width: 620, alignment: .topLeading)
        .liquidGlassPanel()
    }

    private var deskmateStrip: some View {
        HStack(spacing: 8) {
            ForEach(game.classmates.filter { $0.seat.row == 2 && ($0.seat.column == 0 || $0.seat.column == 2) }) { mate in
                VStack(alignment: .leading, spacing: 3) {
                    Text(mate.name)
                        .font(.system(size: 12, weight: .bold))
                    Text("\(mate.profile.traitLabel) · \(mate.state.rawValue) · \(mate.hasSharedTruth || mate.suspicionOfPlayer > 0 ? "有记忆" : "新关系")")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle((mate.hasSharedTruth || mate.suspicionOfPlayer > 0) ? .mint.opacity(0.86) : .white.opacity(0.54))
                    Text(relationshipTone(for: mate))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.72))
                    Text(relationshipMemoryLine(for: mate))
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .frame(width: 170, alignment: .leading)
                .liquidGlassPanel(tint: classmateColor(mate.state).opacity(0.18))
            }
        }
    }

    private func relationshipTone(for mate: Classmate) -> String {
        if mate.suspicionOfPlayer > 38 { return "对你的小动作很敏感" }
        if mate.relationship > 62 { return "愿意靠近一点" }
        if mate.relationship < 24 { return "保持距离" }
        if mate.hasSharedTruth { return "记得一次真实交流" }
        return "关系停在普通同学"
    }

    private func relationshipMemoryLine(for mate: Classmate) -> String {
        if mate.hasSharedTruth && mate.relationship > 58 {
            return "记得你接住过一次真话。"
        }
        if mate.suspicionOfPlayer > 30 {
            return "还记得你的异常动作。"
        }
        if mate.relationship < 24 {
            return "距离感会延续到下一晚。"
        }
        if mate.hasSharedTruth {
            return "共享过真实状态。"
        }
        return "关系还停在表面。"
    }

    private var eventStrip: some View {
        VStack(alignment: .trailing, spacing: 4) {
            ForEach(game.eventLog.prefix(2)) { item in
                Text("\(item.turn) · \(item.title)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
            }
        }
        .frame(width: 160, alignment: .trailing)
    }

    private var audioCueStrip: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text("听觉线索")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.76))
                Spacer()
                Button {
                    isPerceptionPanelPresented.toggle()
                } label: {
                    Image(systemName: isPerceptionPanelPresented ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(SegmentButtonStyle(isSelected: isPerceptionPanelPresented))
                .help(isPerceptionPanelPresented ? "关闭声场详情" : "打开声场详情")
                soundRadar
                    .frame(width: 46, height: 46)
            }
            SensorySoundscapeView(soundscape: currentSoundscape, compact: true)
            if let latestCue = game.audioCues.first {
                AudioCueReadoutView(cue: latestCue, compact: true)
            }
            if let feedback = game.seatedPosePressureFeedback {
                SeatedPosePressureView(feedback: feedback, compact: true)
            }
            if let readout = game.teacherPatrolReadout {
                TeacherPatrolReadoutView(readout: readout, compact: true)
            }
            if let currentSpatialObjective {
                SpatialAudioObjectiveView(objective: currentSpatialObjective, compact: true)
            }
            if let currentPeerCue {
                SensoryPeerCueView(cue: currentPeerCue, compact: true)
            }
            DirectionalSubtitleStripView(
                events: Array(game.directionalSubtitleEvents.prefix(3)),
                captionsEnabled: game.accessibilityPreferences.directionalSubtitles
            )
        }
        .padding(8)
        .frame(width: 180, alignment: .leading)
        .liquidGlassPanel()
    }

    private var perceptionPanel: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.34))
                .ignoresSafeArea()
                .onTapGesture {
                    isPerceptionPanelPresented = false
                }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "waveform.and.magnifyingglass")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.cyan)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("声场与视线")
                            .font(.system(size: 20, weight: .bold))
                        Text("第 \(game.currentTurn) 回合 · 第三排中间 · \(game.cameraPose.visionZone.rawValue) \(game.cameraPose.visionZone.displayName)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.66))
                    }
                    Spacer()
                    Button {
                        isPerceptionPanelPresented = false
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 28, height: 26)
                    }
                    .buttonStyle(SegmentButtonStyle(isSelected: false))
                    .keyboardShortcut(.cancelAction)
                }

                SensorySoundscapeView(soundscape: currentSoundscape, compact: false)
                if let currentPeerCue {
                    SensoryPeerCueView(cue: currentPeerCue, compact: false)
                }

                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 8) {
                        soundRadar
                            .frame(width: 116, height: 116)
                            .padding(8)
                            .liquidGlassPanel()
                        Text("强度越高，圆点越靠外、越亮。")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.58))
                            .multilineTextAlignment(.center)
                    }
                    .frame(width: 140)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("视觉线索")
                            .font(.system(size: 13, weight: .bold))
                        perceptionRow(
                            icon: "eye.fill",
                            title: "\(game.cameraPose.rawValue) · \(game.cameraPose.visionZone.displayName)",
                            detail: "视线\(visualStabilityText)，姿态 \(game.player.posture.rawValue)。",
                            advice: visualAdvice,
                            tint: .mint
                        )
                        perceptionRow(
                            icon: game.teacher.isNearPlayer ? "person.crop.circle.badge.exclamationmark.fill" : "person.crop.circle.fill",
                            title: game.teacher.isNearPlayer ? "老师在近处" : "老师在远处或不确定位置",
                            detail: teacherStateText,
                            advice: teacherDistanceAdvice,
                            tint: game.teacher.isNearPlayer ? .orange : .cyan
                        )
                        perceptionRow(
                            icon: "rectangle.lefthalf.inset.filled",
                            title: "余光变化",
                            detail: "余光越高，越可能代表同桌、过道、老师或后门的不确定信号。",
                            advice: peripheralAdvice,
                            tint: .purple
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("当前声音")
                        .font(.system(size: 13, weight: .bold))
                    if game.audioCues.isEmpty {
                        perceptionRow(
                            icon: "speaker.slash.fill",
                            title: "暂无突出声源",
                            detail: "教室只剩环境底噪，暂时没有需要立即处理的声音事件。",
                            advice: "保持低暴露动作，优先恢复注意力或推进作业。",
                            tint: .white
                        )
                    } else {
                        ForEach(game.audioCues.prefix(5)) { cue in
                            AudioCueReadoutView(cue: cue, compact: false)
                        }
                    }
                }
            }
            .padding(18)
            .frame(width: 720, alignment: .leading)
            .liquidGlassPanel()
        }
        .transition(.opacity)
    }

    private func perceptionRow(icon: String, title: String, detail: String, advice: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint.opacity(0.9))
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.66))
                    .fixedSize(horizontal: false, vertical: true)
                Text(advice)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .liquidGlassPanel()
    }

    private var soundRadar: some View {
        SoundRadarView(cues: Array(game.audioCues.prefix(5)))
    }

    private var visualAdvice: String {
        switch game.cameraPose {
        case .forward:
            return "适合维持普通状态，风险较低；如果能量还够，可以继续写作业或观察老师节奏。"
        case .desk:
            return "桌面近景适合隐藏动作，但会切断中景信息；老师靠近时不要连续停留太久。"
        case .board:
            return "抬头看起来认真，但会消耗注意力；高压时可以短暂停留后切回前方。"
        case .left, .right:
            return "余光能确认同桌或过道信息，但转头本身会增加暴露；用完线索后及时收回视线。"
        case .rear:
            return "后方视野能确认门口和身后风险，但坐着回头非常显眼；除非必要，否则先用声音判断。"
        }
    }

    private var teacherDistanceAdvice: String {
        if game.teacher.isNearPlayer {
            return "先停止手机、零食、传纸条等高暴露动作，选择前方、写作业或呼吸更稳。"
        }
        if game.teacher.positionIndex == 8 {
            return "后门观察缺少脚步声，别只依赖听觉；余光和后方声音都要一起判断。"
        }
        return "老师暂时不近，但 KPI 和巡视频率会让风险回升；可以趁低风险做恢复或低声连接。"
    }

    private var peripheralAdvice: String {
        if game.peripheralLeft > 0.65 || game.peripheralRight > 0.65 {
            return "余光信号偏强，说明旁边或过道有变化；优先确认风险来源，再决定是否行动。"
        }
        return "余光信号不强，当前更适合处理桌面任务或主动恢复注意力。"
    }

    private func audioAdvice(for cue: AudioCue) -> String {
        switch cue.kind {
        case .footstep:
            return cue.intensity > 0.7 ? "脚步很近，立刻降低暴露，等位置确定后再行动。" : "脚步还在远处，可以先观察节奏，不要急着回头。"
        case .phone:
            return "手机声会快速推高暴露；如果想获得连接感，优先让同桌掩护或只看一眼后收起。"
        case .paper:
            return "纸张声通常意味着求助、纸条或作业推进；强度不高时适合低风险连接。"
        case .whisper:
            return game.settings.allowsWhispering ? "低声交流被制度允许，适合建立支持。" : "禁止交流时低语风险更高，尽量缩短交流时间。"
        case .chair:
            return "椅子声代表姿态变化或身体需求；先判断是不是老师靠近或同学崩溃。"
        case .crying:
            return "抽泣是高优先级信号。递纸巾、低声询问或告诉老师都比忽视更能降低风险。"
        case .lights:
            return "灯光或吊扇变化会短暂打乱秩序，可以用来休息眼睛，也可能暴露手机光。"
        case .heartbeat:
            return "心跳声变大说明身体进入报警。先呼吸或降低输入，不要连续做高消耗判断。"
        case .broadcast, .bell:
            return "广播会提高全班制度压力。坐直能降暴露，但也会增加面具成本。"
        case .knock:
            return "后门声音会制造不确定性。确认信息有代价，回头前先看当前暴露值。"
        case .stomach:
            return "饥饿会削弱注意力。若老师不近，可以考虑零食；否则等课间或先呼吸。"
        case .wrapper:
            return "包装纸声很容易被放大。老师近时先停止，远时也要尽快收尾。"
        case .teacherCough, .teacherSigh:
            return "老师的声音也是状态线索。疲惫和 KPI 高时，更容易把小动作误读成纪律问题。"
        }
    }


    private var messagePanel: some View {
        VStack(spacing: 8) {
            if !game.monologues.isEmpty {
                VStack(spacing: 4) {
                    ForEach(game.monologues.prefix(2)) { monologue in
                        Text("“\(monologue.text)”")
                            .font(.system(size: monologue.intensity > 0.7 ? 16 : 14, weight: .medium, design: .serif))
                            .italic()
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.58 + monologue.intensity * 0.34))
                            .lineLimit(2)
                    }
                }
            }
            Text(game.message)
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: 760)
        .liquidGlassPanel()
        .padding(.bottom, 12)
    }

    private func classmateColor(_ state: ClassmateState) -> Color {
        switch state {
        case .crying: return .red
        case .anxious: return .orange
        case .offeringHelp, .covering, .lookingAtPlayer: return .cyan
        case .usingPhone: return .blue
        case .sleeping: return .gray
        case .studying: return .white
        }
    }

    private func color(for kind: AudioCueKind) -> Color {
        switch kind {
        case .footstep, .knock: return .orange
        case .phone, .broadcast, .bell: return .blue
        case .paper, .wrapper, .chair: return .yellow
        case .whisper, .crying: return .cyan
        case .lights: return .mint
        case .heartbeat, .stomach: return .red
        case .teacherCough, .teacherSigh: return .purple
        }
    }

    private var visualStabilityText: String {
        if game.player.visualAttention < 22 { return "开始发散" }
        if game.player.visualAttention < 48 { return "不太稳" }
        if game.player.stress > 76 { return "被压力拉紧" }
        return "还算稳定"
    }

    private var teacherStateText: String {
        if game.teacher.institutionalPressure > 70 || game.teacher.fatigue > 76 {
            return "老师的停顿和叹气变多，管理压力明显压在她身上。"
        }
        if game.teacher.isNearPlayer {
            return "脚步停得很近，你更容易先感觉到风险，而不是看清原因。"
        }
        return "老师仍在维持全班秩序，但你无法确定她正在看谁。"
    }

    private func cueIntensityText(_ value: Double) -> String {
        if value > 0.76 { return "很清楚" }
        if value > 0.42 { return "能分辨" }
        return "很轻"
    }

    private func icon(for kind: AudioCueKind) -> String {
        switch kind {
        case .footstep: return "shoeprints.fill"
        case .paper: return "doc.text.fill"
        case .phone: return "iphone"
        case .whisper: return "text.bubble.fill"
        case .chair: return "chair.fill"
        case .crying: return "drop.fill"
        case .lights: return "lightbulb.fill"
        case .heartbeat: return "heart.fill"
        case .broadcast: return "speaker.wave.2.fill"
        case .bell: return "bell.fill"
        case .knock: return "door.left.hand.closed"
        case .stomach: return "figure.core.training"
        case .wrapper: return "takeoutbag.and.cup.and.straw.fill"
        case .teacherCough: return "lungs.fill"
        case .teacherSigh: return "wind"
        }
    }

    private var actionBar: some View {
        VStack(spacing: 10) {
            if game.activeRole.isTeacher == false {
                studentControlHint
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    if game.activeRole.isTeacher {
                        ForEach(TeacherAction.allCases) { action in
                            Button {
                                game.executeTeacherAction(action)
                            } label: {
                                actionLabel(icon: action.icon, text: action.rawValue)
                            }
                            .buttonStyle(ActionButtonStyle())
                            .keyboardShortcut(KeyEquivalent(action.shortcut), modifiers: [])
                            .help("\(action.rawValue) · \(String(action.shortcut))")
                        }
                    } else if game.freeRoam.isActive {
                        Text("自由活动中：WASD 行走，Shift 侧身，Control 疾跑；按 ~ 可释放或捕获鼠标。")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.72))
                            .frame(height: 44)
                    } else {
                        ForEach(chapterOneActions) { action in
                            Button {
                                game.execute(action)
                            } label: {
                                actionLabel(icon: action.icon, text: action.rawValue)
                            }
                            .buttonStyle(ActionButtonStyle())
                            .keyboardShortcut(KeyEquivalent(action.shortcut), modifiers: [])
                            .help("\(action.rawValue) · \(String(action.shortcut))")
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .liquidGlassPanel()
    }

    private var chapterOneActions: [PlayerAction] {
        game.chapterOneAvailableActions
    }

    private func featuredMonologueLayer(_ monologue: FeaturedMonologue) -> some View {
        FeaturedMonologueView(monologue: monologue) {
            game.dismissFeaturedMonologue()
        }
    }

    private var studentControlHint: some View {
        HStack(spacing: 10) {
            Label(game.mouseLookCaptured ? "移动鼠标自由环视" : "鼠标已释放", systemImage: "cursorarrow.motionlines")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.cyan.opacity(0.88))
            Label(game.mouseLookCaptured ? "` / ~ 释放鼠标" : "` / ~ 捕获视角", systemImage: "keyboard.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.72))
            Text("\(game.cameraPose.rawValue) · \(game.cameraPose.visionZone.displayName)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.62))

            Button {
                game.setMouseLookEnabled(!game.mouseLookEnabled)
            } label: {
                Label(game.mouseLookEnabled ? "释放视角" : "捕获视角", systemImage: game.mouseLookEnabled ? "cursorarrow.slash" : "cursorarrow.motionlines")
                    .frame(minWidth: 74, minHeight: 26)
            }
            .buttonStyle(SegmentButtonStyle(isSelected: game.mouseLookEnabled))
            .help(game.mouseLookEnabled ? "释放鼠标视角，允许操作界面；也可按键盘左上角 ` / ~" : "捕获鼠标视角；也可按键盘左上角 ` / ~")

            Button {
                game.recenterStudentView()
            } label: {
                Label("回到前方", systemImage: "arrow.uturn.backward.circle")
                    .frame(minWidth: 74, minHeight: 26)
            }
            .buttonStyle(SegmentButtonStyle(isSelected: game.cameraPose == .forward))
            .help("把学生视角回到前方")

            Button {
                game.toggleAutonomousPlay()
            } label: {
                Label(game.isAutonomousPlayEnabled ? "接管" : "自主游玩", systemImage: game.isAutonomousPlayEnabled ? "stop.fill" : "play.fill")
                    .frame(minWidth: 76, minHeight: 26)
            }
            .buttonStyle(SegmentButtonStyle(isSelected: game.isAutonomousPlayEnabled))
            .help(game.autonomousPlaySummary)

            if game.isAutonomousPlayEnabled {
                Text("第 \(game.autonomousPlayStepCount) 步")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.mint.opacity(0.9))
                    .help(game.autonomousPlayLastDecision)
            }

            if game.freeRoam.isActive {
                Divider()
                    .frame(height: 20)
                    .overlay(.white.opacity(0.22))
                Label("WASD移动", systemImage: "keyboard.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.mint.opacity(0.9))
                Label(game.freeRoam.isSideways ? "侧身中" : "Shift侧身", systemImage: "rectangle.compress.vertical")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(game.freeRoam.isSideways ? .orange.opacity(0.92) : .white.opacity(0.62))
                Label(game.freeRoam.isSprinting ? "疾跑中" : "Control疾跑", systemImage: "figure.run")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(game.freeRoam.isSprinting ? .yellow.opacity(0.94) : .white.opacity(0.62))
                Text("\(game.freeRoam.remainingSeconds)s")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.orange.opacity(0.92))
                if let door = game.nearbyStudentDoor {
                    let isOpen = game.isStudentDoorOpen(door)
                    Label("E · \(isOpen ? "关" : "开")\(door.rawValue)", systemImage: isOpen ? "door.left.hand.open" : "door.left.hand.closed")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.cyan.opacity(0.94))
                        .frame(minWidth: 88, minHeight: 28)
                }
                if game.isNearPlayerLocker {
                    Button {
                        game.togglePlayerLocker()
                    } label: {
                        Label(game.playerLockerOpen ? "关柜" : "开柜", systemImage: game.playerLockerOpen ? "lock.open.fill" : "lock.fill")
                            .frame(width: 76, height: 28)
                    }
                    .buttonStyle(ActionButtonStyle())
                    .help(game.playerLockerOpen ? "关闭储物柜" : "打开储物柜")
                }
                if game.isNearWaterDispenser {
                    Button {
                        game.refillWaterCup()
                    } label: {
                        Label("接水10s", systemImage: "drop.fill")
                            .frame(width: 86, height: 28)
                    }
                    .buttonStyle(ActionButtonStyle())
                    .help("消耗 10 秒，把水杯补满到 100")
                }
                if game.isNearRestroom {
                    Button {
                        game.useRestroom()
                    } label: {
                        Label("如厕10s", systemImage: "figure.stand")
                            .frame(width: 86, height: 28)
                    }
                    .buttonStyle(ActionButtonStyle())
                    .help("进入厕所并靠近马桶后，消耗 10 秒，如厕需求归零")
                }
                Button {
                    game.returnToSeatFromFreeRoam()
                } label: {
                    Label("回座", systemImage: "chair.fill")
                        .frame(width: 76, height: 28)
                }
                .buttonStyle(ActionButtonStyle())
                .keyboardShortcut(.return, modifiers: [])
                .disabled(game.isReturningToSeat)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .liquidGlassPanel(tint: game.freeRoam.isActive ? .mint.opacity(0.14) : .cyan.opacity(0.1))
    }

    private func actionLabel(icon: String, text: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
            Text(text)
                .font(.system(size: 10, weight: .medium))
        }
        .frame(width: 74, height: 44)
    }

    private var peripheralIndicators: some View {
        GeometryReader { proxy in
            HStack {
                Rectangle()
                    .fill(.red.opacity(game.peripheralLeft * 0.42))
                    .blur(radius: 18)
                    .frame(width: proxy.size.width * 0.08)
                Spacer()
                Rectangle()
                    .fill(.red.opacity(game.peripheralRight * 0.48))
                    .blur(radius: 20)
                    .frame(width: proxy.size.width * 0.1)
            }
            .allowsHitTesting(false)
        }
    }

    private var vignette: some View {
        Rectangle()
            .fill(
                RadialGradient(
                    colors: [.clear, .black.opacity(0.36)],
                    center: .center,
                    startRadius: 120,
                    endRadius: 760
                )
            )
            .allowsHitTesting(false)
    }

    private var returnToSeatTransitionLayer: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: game.isReturningToSeat == false)) { timeline in
            GeometryReader { proxy in
                let progress = returnToSeatProgress(at: timeline.date)
                let motion = smoothStep(from: 0.04, to: 0.25, value: progress) * (1 - smoothStep(from: 0.48, to: 0.66, value: progress))
                let closing = smoothStep(from: 0.24, to: 0.6, value: progress)
                let reopening = smoothStep(from: 0.69, to: 1, value: progress)
                let eyelidClosure = max(0, closing - reopening)
                let blackout = smoothStep(from: 0.3, to: 0.61, value: progress) * (1 - smoothStep(from: 0.72, to: 1, value: progress))
                let revealGlow = smoothStep(from: 0.7, to: 0.84, value: progress) * (1 - smoothStep(from: 0.88, to: 1, value: progress))

                ZStack {
                    Color.black
                        .opacity(game.isReturningToSeat ? 0.18 + blackout * 0.7 : 0)

                    ForEach(0..<14, id: \.self) { index in
                        let lane = Double(index) / 13
                        let travel = (progress * 2.4 + lane).truncatingRemainder(dividingBy: 1)
                        Capsule()
                            .fill(index.isMultiple(of: 3) ? Color.cyan.opacity(0.42) : (index.isMultiple(of: 2) ? Color.orange.opacity(0.34) : Color.white.opacity(0.3)))
                            .frame(width: 48 + CGFloat(index % 5) * 18, height: index.isMultiple(of: 4) ? 2.2 : 1.2)
                            .rotationEffect(.degrees(index.isMultiple(of: 2) ? -8 : 7))
                            .position(
                                x: proxy.size.width * (0.08 + 0.84 * lane),
                                y: proxy.size.height * (0.12 + 0.76 * travel)
                            )
                            .blur(radius: index.isMultiple(of: 3) ? 1.4 : 0.5)
                            .opacity(motion * (0.28 + Double(index % 4) * 0.08))
                    }

                    Rectangle()
                        .fill(.white.opacity(revealGlow * 0.16))

                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(.black)
                            .frame(height: proxy.size.height * 0.5 * eyelidClosure + 1)
                        Spacer(minLength: 0)
                        Rectangle()
                            .fill(.black)
                            .frame(height: proxy.size.height * 0.5 * eyelidClosure + 1)
                    }

                    Rectangle()
                        .fill(.white.opacity(0.28 * eyelidClosure * (1 - blackout)))
                        .frame(height: 1)
                        .blur(radius: 1.5)

                    VStack(spacing: 10) {
                        HStack(spacing: 9) {
                            Rectangle()
                                .fill(.white.opacity(0.42))
                                .frame(width: 34, height: 1)
                            Image(systemName: progress < 0.62 ? "figure.walk.motion" : "chair.fill")
                                .font(.system(size: 19, weight: .semibold))
                            Rectangle()
                                .fill(.white.opacity(0.42))
                                .frame(width: 34, height: 1)
                        }
                        Text(returnToSeatPhaseText(progress: progress))
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.white.opacity(0.86))
                    .offset(y: CGFloat(sin(progress * .pi * 8)) * 2.5)
                    .opacity(game.isReturningToSeat ? min(1, motion + blackout * 0.72) * (1 - reopening) : 0)
                }
                .allowsHitTesting(game.isReturningToSeat)
            }
        }
        .ignoresSafeArea()
    }

    private func returnToSeatProgress(at date: Date) -> Double {
        guard game.isReturningToSeat else { return 0 }
        return (date.timeIntervalSince(game.returnToSeatStartedAt) / GameManager.returnToSeatTotalDuration).clamped(to: 0...1)
    }

    private func returnToSeatPhaseText(progress: Double) -> String {
        if progress < 0.28 {
            return "转身，沿原路折返"
        } else if progress < 0.62 {
            return "脚步重新进入教室"
        }
        return "坐回桌前，呼吸慢下来"
    }

    private func smoothStep(from start: Double, to end: Double, value: Double) -> Double {
        let amount = ((value - start) / (end - start)).clamped(to: 0...1)
        return amount * amount * (3 - 2 * amount)
    }

    private var eventCinematicLayer: some View {
        GeometryReader { proxy in
            if case .event(let event) = game.gameState {
                let style = cinematicStyle(for: event.kind)
                ZStack {
                    Rectangle()
                        .fill(style.tint.opacity(style.opacity))
                    RadialGradient(
                        colors: [.clear, style.edge.opacity(style.edgeOpacity)],
                        center: .center,
                        startRadius: proxy.size.width * 0.12,
                        endRadius: proxy.size.width * 0.62
                    )
                    if style.pulse {
                        Circle()
                            .stroke(style.edge.opacity(0.38), lineWidth: 18)
                            .frame(width: min(proxy.size.width, proxy.size.height) * 0.72)
                            .blur(radius: 10)
                    }
                }
                .blendMode(style.blendMode)
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
    }

    private var scenePresentationLayer: some View {
        GeometryReader { proxy in
            if game.scenePresentation.isActive {
                let presentation = game.scenePresentation
                let bottomInset = max(CGFloat(44), proxy.size.height * 0.10)

                if game.accessibilityPreferences.reduceMotion {
                    scenePresentationLayerContent(
                        presentation: presentation,
                        presence: 1,
                        phaseProgress: 0,
                        size: proxy.size,
                        bottomInset: bottomInset
                    )
                    .ignoresSafeArea()
                    .allowsHitTesting(true)
                } else {
                    TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { timeline in
                        let phaseProgress = presentation.phaseProgress(at: timeline.date)
                        let presence = scenePresentationPresence(for: presentation.phase, progress: phaseProgress)

                        scenePresentationLayerContent(
                            presentation: presentation,
                            presence: presence,
                            phaseProgress: phaseProgress,
                            size: proxy.size,
                            bottomInset: bottomInset
                        )
                    }
                    .ignoresSafeArea()
                    .allowsHitTesting(true)
                }
            }
        }
    }

    @ViewBuilder
    private func scenePresentationLayerContent(
        presentation: ScenePresentationState,
        presence: Double,
        phaseProgress: Double,
        size: CGSize,
        bottomInset: CGFloat
    ) -> some View {
        ZStack {
            scenePresentationBackdrop(for: presentation, presence: presence, progress: phaseProgress, size: size)
            scenePresentationLetterbox(presence: presence, progress: phaseProgress, size: size)
            scenePresentationCard(
                presentation: presentation,
                presence: presence,
                phaseProgress: phaseProgress,
                size: size,
                bottomInset: bottomInset,
                classmates: game.classmates,
                playerSupport: game.player.support
            )
        }
    }

    private func scenePresentationCard(
        presentation: ScenePresentationState,
        presence: Double,
        phaseProgress: Double,
        size: CGSize,
        bottomInset: CGFloat,
        classmates: [Classmate],
        playerSupport: Double
    ) -> some View {
        ScenePresentationCardView(
            presentation: presentation,
            presence: presence,
            phaseProgress: phaseProgress,
            maxWidth: min(size.width * CGFloat(0.74), CGFloat(700)),
            bottomInset: bottomInset,
            classmates: classmates,
            playerSupport: playerSupport
        )
    }

    private func scenePresentationCardPanel(
        presentation: ScenePresentationState,
        presence: Double,
        phaseProgress: Double,
        size: CGSize
    ) -> AnyView {
        AnyView(EmptyView())
    }

    @ViewBuilder
    private func scenePresentationBackdrop(for presentation: ScenePresentationState, presence: Double, progress: Double, size: CGSize) -> some View {
        switch presentation.transition {
        case .fade:
            scenePresentationFadeBackdrop(presentation: presentation, presence: presence, progress: progress, size: size)
        case .colorTemperatureFlip:
            scenePresentationColorTemperatureBackdrop(presentation: presentation, presence: presence, progress: progress, size: size)
        case .mirrorRipple:
            scenePresentationMirrorRippleBackdrop(presentation: presentation, presence: presence, progress: progress, size: size)
        }
    }

    private func scenePresentationFadeBackdrop(presentation: ScenePresentationState, presence: Double, progress: Double, size: CGSize) -> some View {
        let maxDimension = max(size.width, size.height)
        return ZStack {
            LinearGradient(
                colors: [
                    presentation.chapter.atmosphere.opacity(0.28 + presence * 0.16),
                    .black.opacity(0.72)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [
                    presentation.chapter.atmosphere.opacity(0.34 * presence),
                    .clear,
                    .black.opacity(0.84)
                ],
                center: .center,
                startRadius: maxDimension * 0.04,
                endRadius: maxDimension * 0.84
            )
            ForEach(0..<4, id: \.self) { index in
                scenePresentationStreak(
                    width: size.width * CGFloat(0.26 + Double(index) * 0.09),
                    height: index.isMultiple(of: 2) ? 2.2 : 1.2,
                    offset: CGFloat(index - 1) * CGFloat(16) + CGFloat(sin(progress * .pi * 2 + Double(index))) * 6,
                    color: presentation.chapter.atmosphere.opacity(0.08 + Double(index) * 0.03),
                    presence: presence
                )
            }
        }
        .blendMode(.screen)
        .opacity(0.54 + presence * 0.28)
    }

    private func scenePresentationColorTemperatureBackdrop(presentation: ScenePresentationState, presence: Double, progress: Double, size: CGSize) -> some View {
        return ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.68, blue: 0.27).opacity(0.28 + presence * 0.18),
                    presentation.chapter.atmosphere.opacity(0.22),
                    Color(red: 0.34, green: 0.64, blue: 0.98).opacity(0.28 + presence * 0.16)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            ForEach(0..<10, id: \.self) { index in
                scenePresentationStreak(
                    width: 48 + CGFloat(index % 4) * 18,
                    height: index.isMultiple(of: 3) ? 2.0 : 1.2,
                    offset: 0,
                    color: index.isMultiple(of: 2) ? Color.orange.opacity(0.14) : Color.cyan.opacity(0.14),
                    presence: 0.14 + 0.18 * presence,
                    x: size.width * CGFloat(0.1 + 0.8 * (Double(index) / 9.0)),
                    y: size.height * CGFloat(0.18 + 0.62 * (Double((index * 7) % 10) / 9.0)) + CGFloat(sin(progress * .pi * 2 + Double(index))) * 5,
                    rotation: index.isMultiple(of: 2) ? -10 : 9
                )
            }
        }
        .blendMode(.plusLighter)
        .opacity(0.54 + presence * 0.28)
    }

    private func scenePresentationMirrorRippleBackdrop(presentation: ScenePresentationState, presence: Double, progress: Double, size: CGSize) -> some View {
        return ZStack {
            LinearGradient(
                colors: [
                    presentation.chapter.atmosphere.opacity(0.26 + presence * 0.14),
                    .black.opacity(0.82)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            ForEach(0..<5, id: \.self) { index in
                scenePresentationMirrorRing(index: index, progress: progress, size: size)
            }
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            .clear,
                            Color.white.opacity(0.12 + presence * 0.08),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 10)
                .position(x: size.width * CGFloat(0.5 + 0.03 * sin(progress * .pi * 4)), y: size.height / 2)
                .blur(radius: 10)
        }
        .blendMode(.screen)
        .opacity(0.54 + presence * 0.28)
    }

    @ViewBuilder
    private func scenePresentationStreak(
        width: CGFloat,
        height: CGFloat,
        offset: CGFloat,
        color: Color,
        presence: Double,
        x: CGFloat? = nil,
        y: CGFloat? = nil,
        rotation: Double = 0
    ) -> some View {
        if let x, let y {
            Capsule()
                .fill(color)
                .frame(width: width, height: height)
                .rotationEffect(.degrees(rotation))
                .position(x: x, y: y)
                .blur(radius: 5)
                .opacity(presence)
        } else {
            Capsule()
                .fill(color)
                .frame(width: width, height: height)
                .rotationEffect(.degrees(rotation))
                .offset(y: offset)
                .blur(radius: 5)
                .opacity(presence)
        }
    }

    private func scenePresentationMirrorRing(index: Int, progress: Double, size: CGSize) -> some View {
        Circle()
            .stroke(.white.opacity(0.12 + Double(index) * 0.012), lineWidth: CGFloat(1 + index))
            .frame(width: min(size.width, size.height) * CGFloat(0.22 + 0.11 * Double(index)))
            .offset(
                x: CGFloat(sin(Double(index) * 1.4 + progress * .pi * 2)) * 16,
                y: CGFloat(cos(Double(index) * 1.2 + progress * .pi * 2)) * 10
            )
            .blur(radius: 0.9)
    }

    private func scenePresentationLetterbox(presence: Double, progress: Double, size: CGSize) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(.black.opacity(0.9))
                .frame(height: max(CGFloat(18), size.height * CGFloat(0.105 - presence * 0.012 + 0.002 * sin(progress * .pi * 2))))
            Spacer(minLength: 0)
            Rectangle()
                .fill(.black.opacity(0.9))
                .frame(height: max(CGFloat(18), size.height * CGFloat(0.105 - presence * 0.012 + 0.002 * sin(progress * .pi * 2))))
        }
        .frame(width: size.width, height: size.height)
    }

    private func scenePresentationPresence(for phase: ScenePresentationPhase, progress: Double) -> Double {
        switch phase {
        case .prepare:
            return 0.28 + progress * 0.72
        case .commit:
            return 1
        case .cleanup:
            return 1 - progress * 0.92
        case .idle:
            return 0
        }
    }

    struct ScenePresentationCardView: View {
        let presentation: ScenePresentationState
        let presence: Double
        let phaseProgress: Double
        let maxWidth: CGFloat
        let bottomInset: CGFloat
        let classmates: [Classmate]
        let playerSupport: Double

        private var phaseLabel: String {
            switch presentation.phase {
            case .prepare: return "准备切入"
            case .commit: return "镜头展开"
            case .cleanup: return "收束离场"
            case .idle: return "待命"
            }
        }

        private var progressWidth: CGFloat {
            max(8, maxWidth * CGFloat(presence))
        }

        var body: some View {
            VStack {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(presentation.chapter.atmosphere.opacity(0.24 + presence * 0.12))
                            Image(systemName: presentation.transition.symbolName)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                        .frame(width: 38, height: 38)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(presentation.title)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(presentation.subtitle)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.78))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 8)

                        Label(phaseLabel, systemImage: presentation.transition.symbolName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.84))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.white.opacity(0.08), in: Capsule())
                    }

                    HStack(spacing: 10) {
                        Text(presentation.chapter.sceneSubtitle)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        Text("\(Int((presence * 100).rounded()))%")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.66))
                    }

                    if classmates.isEmpty == false {
                        SceneEntryForecastStripView(
                            chapter: presentation.chapter,
                            classmates: classmates,
                            playerSupport: playerSupport
                        )
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(.white.opacity(0.12))
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            presentation.chapter.atmosphere.opacity(0.96),
                                            .white.opacity(0.7)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: min(geo.size.width, progressWidth))
                        }
                    }
                    .frame(height: 5)
                }
                .padding(18)
                .frame(maxWidth: maxWidth, alignment: .leading)
                .background(.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 8))
                .background(presentation.chapter.atmosphere.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.white.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.24), radius: 16, y: 10)
                .offset(y: CGFloat((1 - presence) * 18 + sin(phaseProgress * .pi) * 4))
                .opacity(0.9 + presence * 0.1)
                .padding(.horizontal, 24)
                .padding(.bottom, bottomInset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func cinematicStyle(for kind: ActiveEventKind) -> (tint: Color, edge: Color, opacity: Double, edgeOpacity: Double, pulse: Bool, blendMode: BlendMode) {
        switch kind {
        case .playerBreakdown:
            return (.red, .red, 0.16, 0.72, true, .plusLighter)
        case .loneliness:
            return (.blue, .black, 0.16, 0.78, false, .multiply)
        case .powerOutage:
            return (.black, .blue, 0.38, 0.64, false, .multiply)
        case .phoneNotification:
            return (.blue, .cyan, 0.1, 0.36, true, .plusLighter)
        case .broadcast:
            return (.yellow, .orange, 0.1, 0.5, false, .plusLighter)
        case .knockOnDoor:
            return (.gray, .white, 0.12, 0.48, true, .plusLighter)
        case .discovery:
            return (.orange, .red, 0.12, 0.58, true, .plusLighter)
        case .linCheDialogue:
            return (.mint, .cyan, 0.1, 0.42, false, .plusLighter)
        case .noteDrop:
            return (.yellow, .teal, 0.14, 0.52, true, .plusLighter)
        case .classmateCrying:
            return (.purple, .red, 0.12, 0.5, false, .plusLighter)
        case .classmateHelpRequest:
            return (.mint, .cyan, 0.1, 0.34, true, .plusLighter)
        case .classmateReport:
            return (.orange, .yellow, 0.12, 0.46, true, .plusLighter)
        case .memoryTrust:
            return (.mint, .green, 0.08, 0.28, true, .plusLighter)
        case .memorySuspicion:
            return (.orange, .red, 0.14, 0.54, true, .plusLighter)
        case .teacherConcern, .supportOffer:
            return (.cyan, .cyan, 0.08, 0.26, false, .plusLighter)
        case .leaveSeatRequest:
            return (.white, .orange, 0.08, 0.42, false, .plusLighter)
        }
    }

    private func meter(_ title: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Text("\(Int(value))")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.18))
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * value / 100)
                }
            }
            .frame(height: 7)
        }
    }

    @ViewBuilder
    private func eventOverlay(_ event: ActiveEvent) -> some View {
        if event.kind == .noteDrop {
            noteReadOverlay(event)
        } else {
            VStack(spacing: 14) {
                Text(event.title)
                    .font(.system(size: 24, weight: .bold))
                Text(event.body)
                    .font(.system(size: 15))
                    .multilineTextAlignment(.center)
                    .lineLimit(5)
                    .frame(maxWidth: 620)

                HStack(spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.yellow)
                    Text(educationHint(for: event.kind))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(2)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: 560)
                .liquidGlassPanel()

                if event.kind == .playerBreakdown, game.activeBreakdownRecoverySteps.isEmpty == false {
                    BreakdownRecoveryPanel(
                        summary: game.breakdownRecoverySummary,
                        steps: game.activeBreakdownRecoverySteps,
                        completed: game.completedBreakdownRecoverySteps,
                        current: game.currentBreakdownRecoveryStep
                    )
                    .frame(maxWidth: 560)
                }

                VStack(spacing: 8) {
                    ForEach(event.choices) { choice in
                        Button {
                            game.resolveEventChoice(choice)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(choice.title)
                                        .font(.system(size: 13, weight: .bold))
                                    Text(choice.detail)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.white.opacity(0.68))
                                }
                                Spacer()
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .padding(.horizontal, 12)
                            .frame(width: 460)
                            .frame(minHeight: 48)
                        }
                        .buttonStyle(ActionButtonStyle())
                    }
                }

                if event.choices.isEmpty {
                    Button("继续晚自习") {
                        game.continueAfterEvent()
                    }
                    .buttonStyle(ActionButtonStyle())
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(28)
            .liquidGlassPanel()
        }
    }

    private func noteReadOverlay(_ event: ActiveEvent) -> some View {
        VStack(spacing: 18) {
            Text(event.title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white.opacity(0.82))

            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(red: 0.94, green: 0.96, blue: 0.9))
                    .shadow(color: .black.opacity(0.34), radius: 24, y: 14)
                VStack(spacing: 17) {
                    ForEach(0..<5, id: \.self) { _ in
                        Rectangle()
                            .fill(.blue.opacity(0.16))
                            .frame(height: 1)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 42)

                Text(ChapterOneNoteDropCue.content)
                    .font(.system(size: 22, weight: .medium, design: .serif))
                    .foregroundStyle(.black.opacity(0.82))
                    .multilineTextAlignment(.leading)
                    .lineSpacing(8)
                    .padding(.horizontal, 38)
                    .padding(.vertical, 48)
                    .frame(width: 420, height: 250, alignment: .center)

                TornNoteEdge()
                    .fill(.blue.opacity(0.28))
                    .frame(width: 54, height: 74)
                    .offset(x: 8, y: -12)
            }
            .frame(width: 420, height: 250)
            .rotationEffect(.degrees(-1.6))

            Text("你看见了，但还不知道是谁写的。")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))

            ForEach(event.choices) { choice in
                Button {
                    game.resolveEventChoice(choice)
                } label: {
                    Label(choice.title, systemImage: "tray.and.arrow.down.fill")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 240, height: 44)
                }
                .buttonStyle(ActionButtonStyle())
                .keyboardShortcut(.defaultAction)
                .help(choice.detail)
            }
        }
        .padding(30)
        .liquidGlassPanel(tint: .yellow.opacity(0.08))
    }

    private func educationHint(for kind: ActiveEventKind) -> String {
        switch kind {
        case .playerBreakdown:
            return "崩溃不是失败，是心理能量和压力共同发出的报警。"
        case .loneliness:
            return "孤独感是压力信号，不是软弱；先承认它，才可能求助。"
        case .classmateCrying:
            return "沉默不代表没事。很小的支持也可能改变一次焦虑峰值。"
        case .classmateHelpRequest:
            return "求助常常不会以清楚的话出现；看见微弱信号，本身就是支持网络的一部分。"
        case .classmateReport:
            return "同学也会传导制度压力。守纪律、害怕受罚和同理心可能同时存在。"
        case .memoryTrust:
            return "关系会跨过一晚。被接住的真话会降低下一次求助成本。"
        case .memorySuspicion:
            return "怀疑也会跨过一晚。没有被修复的关系会让风险更早出现。"
        case .supportOffer:
            return "支持网络不能解决所有问题，但能提高恢复速度和崩溃阈值。"
        case .teacherConcern:
            return "权力关系里的关心需要降低声音，也需要给对方选择。"
        case .discovery:
            return "违规行为背后可能是逃离、疲惫或求助，不只是态度问题。"
        case .linCheDialogue:
            return "低压力回应不是逼对方交代，而是给他一个可以稍后开口的位置。"
        case .noteDrop:
            return "匿名求助先被看见，不等于立刻追问来源；确认信号比猜答案更重要。"
        case .powerOutage:
            return "环境变化会改变风险，也会短暂暴露每个人的真实状态。"
        case .phoneNotification:
            return "想看消息不只是分心，也可能是对连接和逃离的需求。"
        case .broadcast:
            return "制度声音会同时改变学生和老师的行为压力。"
        case .knockOnDoor:
            return "不确定性会消耗注意力；确认信息和维持秩序都有代价。"
        case .leaveSeatRequest:
            return "身体想离开座位时，可能是在提醒你需要恢复空间。"
        }
    }

    private func endingOverlay(_ ending: Ending) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 14) {
                Text(ending.title)
                    .font(.system(size: 30, weight: .bold))
                Text(ending.body)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 660)
                Text(ending.reflection)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.76))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 660)

                performanceReviewPanel(game.performanceReview)
                teacherReflectionPanel(game.teacherPostgameReflection)
                mechanicPanel(game.mechanicExplanations)
                endingAnalysis(ending)
                nightTrajectoryPanel
                comparisonPanel(ending.comparisons)
                storyPanel(ending.story)
                empathyPanel(ending.empathyReflections)
                relationshipEchoPanel(ending.relationshipEchoes)
                replayPanel
                resourcesPanel(ending.resources)

                Button("返回菜单") {
                    game.returnToMenuForNewGame()
                }
                .buttonStyle(ActionButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
            .padding(32)
        }
        .frame(maxWidth: 760, maxHeight: 660)
        .liquidGlassPanel()
    }

    private func performanceReviewPanel(_ review: PerformanceReview) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "checklist.checked")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.green)
                Text("当晚表现复盘")
                    .font(.system(size: 14, weight: .bold))
            }

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(330), spacing: 8), count: 2), spacing: 8) {
                reviewColumn(title: "做得好的地方", points: review.strengths, tint: .green)
                reviewColumn(title: "下次可调整", points: review.improvements, tint: .orange)
            }

            Text(review.encouragement)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.cyan.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .padding(12)
        .frame(maxWidth: 700, alignment: .leading)
        .liquidGlassPanel()
    }

    private func reviewColumn(title: String, points: [ReviewPoint], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint.opacity(0.9))
            ForEach(points.prefix(4)) { point in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: point.icon)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(tint.opacity(0.86))
                        .frame(width: 14, height: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(point.title)
                            .font(.system(size: 11, weight: .semibold))
                        Text(point.detail)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.68))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(10)
        .frame(width: 330, alignment: .topLeading)
        .frame(minHeight: 178, alignment: .topLeading)
        .liquidGlassPanel()
    }

    private func teacherReflectionPanel(_ reflection: TeacherPostgameReflection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "person.text.rectangle.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.purple)
                Text("教师视角：整晚复盘")
                    .font(.system(size: 14, weight: .bold))
            }
            Text("“\(reflection.monologue)”")
                .font(.system(size: 12, weight: .medium, design: .serif))
                .italic()
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 7) {
                Text("整晚内心独白")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.purple.opacity(0.9))
                ForEach(reflection.segments) { segment in
                    HStack(alignment: .top, spacing: 9) {
                        Text(segment.time)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.purple.opacity(0.88))
                            .frame(width: 44, alignment: .leading)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(segment.title)
                                .font(.system(size: 11, weight: .bold))
                            Text(segment.text)
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.7))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .liquidGlassPanel()
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("站在老师这边的分析")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.orange.opacity(0.92))
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(330), spacing: 8), count: 2), spacing: 8) {
                    ForEach(reflection.analysis) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: item.icon)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.orange.opacity(0.86))
                                .frame(width: 14, height: 14)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                    .font(.system(size: 11, weight: .bold))
                                Text(item.detail)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white.opacity(0.68))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(10)
                        .frame(width: 330, alignment: .topLeading)
                        .frame(minHeight: 118, alignment: .topLeading)
                        .liquidGlassPanel()
                    }
                }
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "hands.sparkles.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.cyan)
                    .frame(width: 16, height: 16)
                Text(reflection.studentTakeaway)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.cyan.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .liquidGlassPanel()

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(126), spacing: 8), count: 3), spacing: 8) {
                ForEach(reflection.metrics) { item in
                    compactMetricCard(item, tint: .purple)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: 700, alignment: .leading)
        .liquidGlassPanel()
    }

    private func mechanicPanel(_ explanations: [MechanicExplanation]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "function")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.cyan)
                Text("焦虑与崩溃机制")
                    .font(.system(size: 14, weight: .bold))
            }
            ForEach(explanations) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.system(size: 11, weight: .bold))
                    Text(item.formula)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.cyan.opacity(0.86))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.note)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .liquidGlassPanel()
            }
        }
        .padding(12)
        .frame(maxWidth: 700, alignment: .leading)
        .liquidGlassPanel()
    }

    private func compactMetricCard(_ item: EndingMetric, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
            Text(item.value)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(tint.opacity(0.92))
            Text(item.note)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.58))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(9)
        .frame(width: 126, alignment: .topLeading)
        .frame(minHeight: 82, alignment: .topLeading)
        .liquidGlassPanel()
    }

    private func endingAnalysis(_ ending: Ending) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(126), spacing: 8), count: 3), spacing: 8) {
            ForEach(ending.analysis) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                    Text(item.value)
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                    Text(item.note)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(9)
                .frame(width: 126, alignment: .topLeading)
                .frame(minHeight: 84, alignment: .topLeading)
                .liquidGlassPanel()
            }
        }
        .frame(maxWidth: 420)
    }

    private var nightTrajectoryPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.red)
                Text("夜间轨迹")
                    .font(.system(size: 14, weight: .bold))
            }
            if game.replay.count > 1 {
                trajectoryChart
                    .frame(height: 86)
                HStack(spacing: 8) {
                    trajectoryBadge("压力峰值", value: "\(Int(game.replay.map(\.stress).max() ?? 0))", color: .orange)
                    trajectoryBadge("最低能量", value: "\(Int(game.replay.map(\.energy).min() ?? 0))", color: .green)
                    trajectoryBadge("最高身体", value: "\(Int(game.replay.map(\.bodyNeed).max() ?? 0))", color: .teal)
                    trajectoryBadge("关键回合", value: "\(keyReplayMoments.count)", color: .cyan)
                }
                ForEach(keyReplayMoments.prefix(3)) { snapshot in
                    Text("第 \(snapshot.turn) 回合 · \(snapshot.actionLabel)：压力 \(Int(snapshot.stress))，能量 \(Int(snapshot.energy))，支持 \(Int(snapshot.support))")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
            } else {
                Text("回合数据不足，无法生成轨迹。")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(12)
        .frame(maxWidth: 700, alignment: .leading)
        .liquidGlassPanel()
    }

    private var trajectoryChart: some View {
        Canvas { context, size in
            let snapshots = game.replay
            guard snapshots.count > 1 else { return }
            let inset: CGFloat = 6
            let width = max(1, size.width - inset * 2)
            let height = max(1, size.height - inset * 2)

            func point(index: Int, value: Double) -> CGPoint {
                let x = inset + CGFloat(index) / CGFloat(max(1, snapshots.count - 1)) * width
                let y = inset + (1 - CGFloat(value.clamped(to: 0...100) / 100)) * height
                return CGPoint(x: x, y: y)
            }

            var grid = Path()
            for ratio in [0.25, 0.5, 0.75] {
                let y = inset + height * ratio
                grid.move(to: CGPoint(x: inset, y: y))
                grid.addLine(to: CGPoint(x: inset + width, y: y))
            }
            context.stroke(grid, with: .color(.white.opacity(0.12)), lineWidth: 1)

            drawLine(values: snapshots.map(\.stress), color: .orange, context: &context, point: point)
            drawLine(values: snapshots.map(\.energy), color: .green, context: &context, point: point)
            drawLine(values: snapshots.map(\.bodyNeed), color: .teal, context: &context, point: point)
        }
    }

    private func drawLine(values: [Double], color: Color, context: inout GraphicsContext, point: (Int, Double) -> CGPoint) {
        guard values.count > 1 else { return }
        var path = Path()
        path.move(to: point(0, values[0]))
        for index in values.indices.dropFirst() {
            path.addLine(to: point(index, values[index]))
        }
        context.stroke(path, with: .color(color.opacity(0.84)), lineWidth: 2)
    }

    private func trajectoryBadge(_ title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.58))
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(color.opacity(0.9))
        }
        .frame(width: 90, alignment: .leading)
    }

    private var keyReplayMoments: [TurnSnapshot] {
        game.replay
            .filter { snapshot in
                snapshot.stress >= 70
                    || snapshot.energy <= 28
                    || snapshot.bodyNeed >= 76
                    || snapshot.actionLabel.contains("求助")
                    || snapshot.actionLabel.contains("同桌")
                    || snapshot.actionLabel.contains("看手机")
                    || snapshot.actionLabel.contains("洗手间")
            }
            .sorted { lhs, rhs in
                let lhsScore = lhs.stress + lhs.bodyNeed + (100 - lhs.energy) + lhs.exposure * 0.35 - lhs.support * 0.18
                let rhsScore = rhs.stress + rhs.bodyNeed + (100 - rhs.energy) + rhs.exposure * 0.35 - rhs.support * 0.18
                return lhsScore > rhsScore
            }
    }

    private func comparisonPanel(_ comparisons: [EndingComparison]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.orange)
                Text("数据对照")
                    .font(.system(size: 14, weight: .bold))
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(160), spacing: 8), count: 2), spacing: 8) {
                ForEach(comparisons) { item in
                    comparisonCard(item)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: 700, alignment: .leading)
        .liquidGlassPanel()
    }

    private func comparisonCard(_ item: EndingComparison) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
            Text(item.playerValue)
                .font(.system(size: 17, weight: .bold, design: .monospaced))
            Text(item.referenceValue)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.orange.opacity(0.86))
            Text(item.note)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.58))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(9)
        .frame(width: 160, alignment: .topLeading)
        .frame(minHeight: 104, alignment: .topLeading)
        .liquidGlassPanel()
    }

    private func storyPanel(_ story: EndingStory) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "quote.bubble.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.cyan)
                Text("真实故事出口")
                    .font(.system(size: 14, weight: .bold))
            }
            Text(story.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
            Text(story.body)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.76))
                .fixedSize(horizontal: false, vertical: true)
            Text(story.prompt)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.cyan.opacity(0.86))
        }
        .padding(12)
        .frame(maxWidth: 700, alignment: .leading)
        .liquidGlassPanel()
    }

    private func empathyPanel(_ reflections: [EmpathyReflection]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "person.3.sequence.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.mint)
                Text("三方同理心")
                    .font(.system(size: 14, weight: .bold))
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(210), spacing: 8), count: 3), spacing: 8) {
                ForEach(reflections) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 5) {
                            Image(systemName: item.icon)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.mint)
                                .frame(width: 14)
                            Text(item.role)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        Text(item.text)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.72))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .frame(width: 210, alignment: .topLeading)
                    .frame(minHeight: 132, alignment: .topLeading)
                    .liquidGlassPanel()
                }
            }
        }
        .padding(12)
        .frame(maxWidth: 700, alignment: .leading)
        .liquidGlassPanel()
    }

    private func relationshipEchoPanel(_ echoes: [RelationshipEcho]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.pink)
                Text("关系余波")
                    .font(.system(size: 14, weight: .bold))
            }
            if echoes.isEmpty {
                Text("这一晚没有留下明显的同学关系记忆。沉默不等于没有影响，只是还没有进入可见的支持网络。")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(330), spacing: 8), count: 2), spacing: 8) {
                    ForEach(echoes) { echo in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 5) {
                                Text(echo.name)
                                    .font(.system(size: 12, weight: .bold))
                                Text(echo.title)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.pink.opacity(0.86))
                            }
                            Text(echo.text)
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.72))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(10)
                        .frame(width: 330, alignment: .topLeading)
                        .frame(minHeight: 94, alignment: .topLeading)
                        .liquidGlassPanel()
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: 700, alignment: .leading)
        .liquidGlassPanel()
    }

    private var replayPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("学生视角真相回放")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Button {
                    game.selectReplay(offset: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 26, height: 24)
                }
                .buttonStyle(ActionButtonStyle())
                Button {
                    game.selectReplay(offset: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 26, height: 24)
                }
                .buttonStyle(ActionButtonStyle())
            }

            if let snapshot = game.selectedReplay {
                Text("第 \(snapshot.turn) 回合 · \(snapshot.metrics)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.72))
                Text(snapshot.visibleScene)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.82))
                Text(snapshot.innerTruth)
                    .font(.system(size: 12, weight: .semibold))
                Text(snapshot.teacherInterpretation)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.76))
            } else {
                Text("本局没有足够回合生成回放。")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(12)
        .frame(maxWidth: 700)
        .liquidGlassPanel()
    }

    private func resourcesPanel(_ resources: [SupportResource]) -> some View {
        SupportResourceView(resources: resources)
            .frame(maxWidth: 700, alignment: .leading)
    }
}

struct TeacherTruthRoutePanel: View {
    let summary: String
    let objectives: [TeacherTruthObjective]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("真相二周目", systemImage: "eye.trianglebadge.exclamationmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.mint.opacity(0.9))
                Text(summary)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                ForEach(objectives) { objective in
                    VStack(spacing: 3) {
                        Image(systemName: objective.isComplete ? "checkmark.circle.fill" : objective.symbol)
                            .font(.system(size: 11, weight: .bold))
                        Text(objective.title)
                            .font(.system(size: 8.5, weight: .bold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(objective.isComplete ? .mint.opacity(0.86) : .white.opacity(0.7))
                    .frame(width: 78, height: 38)
                    .background(.white.opacity(objective.isComplete ? 0.10 : 0.055), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.white.opacity(objective.isComplete ? 0.18 : 0.08), lineWidth: 1)
                    )
                    .help(objective.detail)
                }
            }
        }
    }
}

struct BreakdownRecoveryPanel: View {
    let summary: String
    let steps: [BreakdownRecoveryStep]
    let completed: Set<BreakdownRecoveryStep>
    let current: BreakdownRecoveryStep?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Label("恢复序列", systemImage: "heart.text.square.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.cyan.opacity(0.9))
                Spacer()
                Text(summary)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                ForEach(steps) { step in
                    let isDone = completed.contains(step)
                    let isCurrent = current == step
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Image(systemName: isDone ? "checkmark.circle.fill" : step.symbol)
                                .font(.system(size: 11, weight: .bold))
                            Text(step.title)
                                .font(.system(size: 10.5, weight: .bold))
                                .lineLimit(1)
                        }
                        Text(step.detail)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.64))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(isDone ? .mint.opacity(0.88) : (isCurrent ? .cyan.opacity(0.9) : .white.opacity(0.72)))
                    .padding(9)
                    .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
                    .background(.white.opacity(isDone ? 0.10 : (isCurrent ? 0.085 : 0.045)), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.white.opacity(isDone || isCurrent ? 0.18 : 0.08), lineWidth: 1)
                    )
                }
            }
        }
        .padding(12)
        .background(.black.opacity(0.32), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        )
    }
}

struct PlaytestRouteTranscriptView: View {
    let entries: [PlaytestRouteTranscriptEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Label("路线转录", systemImage: "waveform.path.ecg.rectangle")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.86))
                Spacer()
                Label("\(entries.count)", systemImage: "list.bullet.rectangle.portrait.fill")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(.mint.opacity(0.82))
            }

            if entries.isEmpty {
                Text("等待一次真实输入")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.52))
                    .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(alignment: .firstTextBaseline, spacing: 7) {
                                Text("#\(entry.step)")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.mint.opacity(0.86))
                                    .frame(width: 34, height: 18)
                                    .background(.mint.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.mint.opacity(0.18), lineWidth: 1))
                                Text(entry.actor)
                                    .font(.system(size: 8.5, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.58))
                                    .lineLimit(1)
                                Text(entry.input)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.94))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.78)
                            }

                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.branch")
                                    .font(.system(size: 8.5, weight: .bold))
                                    .foregroundStyle(.cyan.opacity(0.62))
                                Text(entry.beforeState)
                                    .lineLimit(1)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.38))
                                Text(entry.afterState)
                                    .lineLimit(1)
                            }
                            .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.58))

                            routeTranscriptSignalRow(entry)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity, minHeight: 46, alignment: .topLeading)
                        .background(.white.opacity(entry.hasChoiceImpactFeedback || entry.hasSensoryPeerFeedback || entry.hasSpatialNavigationFeedback || entry.hasCompanionNavigationFeedback ? 0.07 : 0.045), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(routeTranscriptStroke(for: entry), lineWidth: 1)
                        )
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(entry.hasFriction ? .orange.opacity(0.78) : .mint.opacity(0.45))
                                .frame(width: 2)
                                .padding(.vertical, 7)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
    }

    @ViewBuilder
    private func routeTranscriptSignalRow(_ entry: PlaytestRouteTranscriptEntry) -> some View {
        if let choiceImpactFeedback = entry.choiceImpactFeedback {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Label(choiceImpactFeedback, systemImage: "waveform.path.ecg")
                    .foregroundStyle(.orange.opacity(0.84))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Label(entry.friction, systemImage: entry.hasFriction ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(entry.hasFriction ? .orange.opacity(0.76) : .mint.opacity(0.62))
                    .lineLimit(1)
                    .frame(maxWidth: 138, alignment: .leading)
            }
            .font(.system(size: 8.5, weight: .medium))
        } else if let sensoryFeedback = entry.sensoryPeerFeedback {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Label(sensoryFeedback, systemImage: "ear.and.waveform")
                    .foregroundStyle(.mint.opacity(0.84))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Label(entry.friction, systemImage: entry.hasFriction ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(entry.hasFriction ? .orange.opacity(0.76) : .mint.opacity(0.62))
                    .lineLimit(1)
                    .frame(maxWidth: 138, alignment: .leading)
            }
            .font(.system(size: 8.5, weight: .medium))
        } else if let spatialNavigationFeedback = entry.spatialNavigationFeedback {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Label(spatialNavigationFeedback, systemImage: "location.north.line.fill")
                    .foregroundStyle(.cyan.opacity(0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Label(entry.friction, systemImage: entry.hasFriction ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(entry.hasFriction ? .orange.opacity(0.76) : .mint.opacity(0.62))
                    .lineLimit(1)
                    .frame(maxWidth: 138, alignment: .leading)
            }
            .font(.system(size: 8.5, weight: .medium))
        } else if let companionNavigationFeedback = entry.companionNavigationFeedback {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Label(companionNavigationFeedback, systemImage: "person.wave.2.fill")
                    .foregroundStyle(.blue.opacity(0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Label(entry.friction, systemImage: entry.hasFriction ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(entry.hasFriction ? .orange.opacity(0.76) : .mint.opacity(0.62))
                    .lineLimit(1)
                    .frame(maxWidth: 138, alignment: .leading)
            }
            .font(.system(size: 8.5, weight: .medium))
        } else {
            HStack(alignment: .top, spacing: 6) {
                Label(entry.friction, systemImage: entry.hasFriction ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(entry.hasFriction ? .orange.opacity(0.86) : .mint.opacity(0.7))
                    .lineLimit(1)
                if let supportingFeedback = entry.supportingFeedback {
                    Label(supportingFeedback, systemImage: "speaker.wave.2.fill")
                        .foregroundStyle(.cyan.opacity(0.68))
                        .lineLimit(1)
                }
            }
            .font(.system(size: 8.5, weight: .medium))
        }
    }

    private func routeTranscriptStroke(for entry: PlaytestRouteTranscriptEntry) -> Color {
        if entry.hasChoiceImpactFeedback {
            return .orange.opacity(0.26)
        }
        if entry.hasSensoryPeerFeedback {
            return .mint.opacity(0.24)
        }
        if entry.hasSpatialNavigationFeedback {
            return .cyan.opacity(0.22)
        }
        if entry.hasCompanionNavigationFeedback {
            return .blue.opacity(0.22)
        }
        return .white.opacity(0.1)
    }
}

struct TornNoteEdge: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.06))
        path.addLine(to: CGPoint(x: rect.maxX * 0.92, y: rect.minY + rect.height * 0.24))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.38))
        path.addLine(to: CGPoint(x: rect.maxX * 0.88, y: rect.minY + rect.height * 0.54))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.72))
        path.addLine(to: CGPoint(x: rect.maxX * 0.78, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.maxY * 0.88))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.52))
        path.closeSubpath()
        return path
    }
}

struct ClassroomSupportWeatherStripView: View {
    let classmates: [Classmate]
    let playerSupport: Double

    private var nodes: [ClassmateSupportWeatherNode] {
        classmates
            .map { mate in
                ClassmateSupportWeatherNode(
                    id: mate.id,
                    name: mate.name,
                    detail: supportWeatherDetail(for: mate),
                    tint: supportWeatherTint(for: mate),
                    strength: supportWeatherStrength(for: mate)
                )
            }
            .sorted {
                if $0.strength == $1.strength {
                    return $0.id < $1.id
                }
                return $0.strength > $1.strength
            }
    }

    private var leadNode: ClassmateSupportWeatherNode? {
        nodes.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.cyan)
                Text("支持天气")
                    .font(.system(size: 10, weight: .bold))
                Spacer()
                Text("缓冲 \(Int(playerSupport))")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
            }

            if let leadNode {
                Text("当前最稳 \(leadNode.name)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            VStack(spacing: 5) {
                ForEach(Array(nodes.prefix(2))) { node in
                    supportWeatherRow(node)
                }
            }
        }
        .padding(7)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func supportWeatherRow(_ node: ClassmateSupportWeatherNode) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Circle()
                    .fill(node.tint.opacity(0.85))
                    .frame(width: 6, height: 6)
                Text(node.name)
                    .font(.system(size: 9.5, weight: .bold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(Int(node.strength * 100))")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.52))
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.10))
                    Capsule()
                        .fill(node.tint.opacity(0.82))
                        .frame(width: max(10, proxy.size.width * node.strength))
                }
            }
            .frame(height: 4)

            Text(node.detail)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(7)
        .background(node.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(node.tint.opacity(0.20), lineWidth: 1)
        )
    }

    private func supportWeatherStrength(for mate: Classmate) -> Double {
        let emotionalWeight = mate.relationship * 0.55
        let trustWeight = mate.support * 0.28
        let suspicionPenalty = mate.suspicionOfPlayer * 0.42
        let truthBoost = mate.hasSharedTruth ? 12.0 : 0.0
        return (emotionalWeight + trustWeight + truthBoost - suspicionPenalty).clamped(to: 0...100) / 100
    }

    private func supportWeatherTint(for mate: Classmate) -> Color {
        if mate.hasSharedTruth && mate.relationship > 58 { return .mint }
        if mate.suspicionOfPlayer > 32 { return .orange }
        if mate.relationship > 62 { return .cyan }
        if mate.relationship < 24 { return .purple }
        return .white
    }

    private func supportWeatherDetail(for mate: Classmate) -> String {
        if mate.hasSharedTruth && mate.relationship > 58 { return "接住过一次真话" }
        if mate.suspicionOfPlayer > 32 { return "还记得你的异常" }
        if mate.relationship > 62 { return "愿意靠近一点" }
        if mate.relationship < 24 { return "先保持距离" }
        return mate.profile.signalReaction
    }
}

struct ClassmateSupportWeatherNode: Identifiable {
    let id: Int
    let name: String
    let detail: String
    let tint: Color
    let strength: Double
}

struct SceneEntryForecastStripView: View {
    let chapter: NarrativeChapter
    let classmates: [Classmate]
    let playerSupport: Double

    private var leadMate: Classmate? {
        classmates.max { lhs, rhs in
            supportScore(lhs) < supportScore(rhs)
        }
    }

    private var leadLine: String {
        guard let leadMate else { return "支持网络尚未成形" }
        if leadMate.hasSharedTruth && leadMate.relationship > 58 {
            return "\(leadMate.name)记得一次真话"
        }
        if leadMate.relationship > 62 {
            return "\(leadMate.name)愿意靠近一点"
        }
        if leadMate.suspicionOfPlayer > 32 {
            return "\(leadMate.name)正在观察你"
        }
        return "\(leadMate.name)是当前最稳信号"
    }

    private var pressureLine: String {
        switch chapter {
        case .classroom:
            return "压力：低声观察"
        case .mirror:
            return "压力：呼吸被放大"
        case .noteTrace:
            return "压力：线索回流"
        case .stairwell:
            return "压力：位置要说清"
        case .counseling:
            return "压力：等待有重量"
        case .epilogue:
            return "压力：余波回看"
        }
    }

    private var exitLine: String {
        switch chapter {
        case .classroom:
            return "出口：先看见"
        case .mirror:
            return "出口：稳住呼吸"
        case .noteTrace:
            return "出口：找同伴"
        case .stairwell:
            return "出口：成人接手"
        case .counseling:
            return "出口：守住隐私"
        case .epilogue:
            return "出口：支持回到自己"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Label("支持 \(Int(playerSupport))", systemImage: "point.3.connected.trianglepath.dotted")
                .foregroundStyle(.cyan.opacity(0.9))
            Divider()
                .frame(height: 16)
                .overlay(.white.opacity(0.18))
            Text("最稳 \(leadLine)")
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 6)
            Text(pressureLine)
                .foregroundStyle(.orange.opacity(0.86))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(exitLine)
                .foregroundStyle(.mint.opacity(0.86))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .font(.system(size: 10, weight: .bold))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("入场预报，支持 \(Int(playerSupport))，\(leadLine)，\(pressureLine)，\(exitLine)")
    }

    private func supportScore(_ mate: Classmate) -> Double {
        let truth = mate.hasSharedTruth ? 12.0 : 0.0
        return mate.relationship * 0.55 + mate.support * 0.28 + truth - mate.suspicionOfPlayer * 0.42
    }
}

struct MainQuestHUDItem: Equatable {
    let quest: String
    let currentGoal: String
    let hint: String?
    let isUrgent: Bool
}

struct MainQuestHUD: View {
    static let width: CGFloat = 220
    static let questFontSize: CGFloat = 11
    static let currentGoalFontSize: CGFloat = 14
    static let defaultAnimationDuration = 0.3
    static let reduceMotionAnimationDuration = 0.2

    let item: MainQuestHUDItem
    let reduceMotion: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: item.isUrgent ? "exclamationmark.triangle.fill" : "scope")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(item.isUrgent ? .orange.opacity(0.92) : .cyan.opacity(0.84))
                    .frame(width: 15)
                Text("主线任务")
                    .font(.system(size: Self.questFontSize, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.50))
                    .accessibilitySortPriority(3)
            }

            Text(item.quest)
                .font(.system(size: Self.questFontSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.50))
                .lineLimit(2)
                .minimumScaleFactor(0.78)
                .accessibilitySortPriority(2)

            Text(item.currentGoal)
                .id(item.currentGoal)
                .font(.system(size: Self.currentGoalFontSize, weight: .semibold))
                .foregroundStyle(item.isUrgent ? .orange : .white)
                .lineLimit(3)
                .minimumScaleFactor(0.74)
                .transition(goalTransition)
                .accessibilitySortPriority(1)

            if let hint = item.hint, hint.isEmpty == false {
                Text(hint)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.cyan.opacity(0.76))
                    .lineLimit(3)
                    .minimumScaleFactor(0.76)
                    .accessibilitySortPriority(0)
            }
        }
        .padding(10)
        .frame(width: Self.width, alignment: .topLeading)
        .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(item.isUrgent ? .orange.opacity(0.28) : .white.opacity(0.14), lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(item.isUrgent ? .orange.opacity(0.78) : .cyan.opacity(0.58))
                .frame(width: 3)
                .padding(.vertical, 9)
        }
        .animation(
            .easeInOut(duration: Self.animationDuration(reduceMotion: reduceMotion)),
            value: item.currentGoal
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    static func animationDuration(reduceMotion: Bool) -> Double {
        reduceMotion ? reduceMotionAnimationDuration : defaultAnimationDuration
    }

    private var goalTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .opacity
        )
    }

    private var accessibilitySummary: String {
        let hintText = item.hint.map { "，提示，\($0)" } ?? ""
        return "主线任务，\(item.quest)，当前目标，\(item.currentGoal)\(hintText)"
    }
}

struct FeaturedMonologueView: View {
    static let minimumPanelHeight: CGFloat = 190

    let monologue: FeaturedMonologue
    let onDismiss: () -> Void

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 22) {
                Text(monologue.text)
                    .font(.custom("STXingkai", size: monologue.intensity >= 0.75 ? 34 : 30))
                    .foregroundStyle(.white.opacity(0.96))
                    .multilineTextAlignment(.center)
                    .lineSpacing(10)
                    .frame(maxWidth: 760)

                Rectangle()
                    .fill(.white.opacity(0.5))
                    .frame(width: 54, height: 1)
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 30)
            .frame(maxWidth: .infinity, minHeight: Self.minimumPanelHeight)
            .background(.black.opacity(0.70 + monologue.intensity * 0.10), in: Rectangle())
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(.white.opacity(0.10))
                    .frame(height: 1)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .contentShape(Rectangle())
        .onTapGesture(perform: onDismiss)
        .transition(.opacity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(monologue.text)
    }
}

struct AutonomousDirectorOverlay: View {
    let status: String
    let decision: String
    let stepCount: Int
    let soundscape: SensorySoundscape
    let peerCue: SensoryPeerCue?
    let latestEntry: PlaytestRouteTranscriptEntry?
    let onTakeover: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 9) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.mint.opacity(0.94))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("自主导演")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.66))
                    Text(decision)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.94))
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("#\(stepCount)")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(.mint.opacity(0.9))
                    Text(status)
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.white.opacity(0.52))
                        .lineLimit(1)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                directorSignalLine(
                    icon: soundscapeIcon,
                    title: "声场依据",
                    detail: soundscape.recommendation,
                    tint: soundscapeTint
                )
                if let peerCue {
                    directorSignalLine(
                        icon: "ear.and.waveform",
                        title: "\(peerCue.classmateName) · \(peerCue.direction)",
                        detail: peerCue.lowPressureAction,
                        tint: peerCueTint(peerCue)
                    )
                }
                if let latestEntry {
                    directorSignalLine(
                        icon: "arrow.triangle.branch",
                        title: "最近路线",
                        detail: latestEntry.afterState,
                        tint: latestEntry.hasFriction ? .orange : .cyan
                    )
                }
            }

            HStack(spacing: 8) {
                directorProgressBars
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onTakeover) {
                    Label("接管", systemImage: "stop.fill")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(.black.opacity(0.9))
                        .frame(width: 66, height: 24)
                        .background(.mint.opacity(0.9), in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(0.28), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("停止自主游玩，交还给玩家")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.mint.opacity(0.32), lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(soundscapeTint.opacity(0.82))
                .frame(width: 3)
                .padding(.vertical, 10)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("自主导演，第 \(stepCount) 步，\(decision)。\(soundscape.recommendation)")
    }

    private var directorProgressBars: some View {
        HStack(spacing: 4) {
            ForEach(0..<8, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3)
                    .fill(index < ((stepCount % 8) + 1) ? .mint.opacity(0.82) : .white.opacity(0.12))
                    .frame(height: 5)
            }
        }
        .padding(.horizontal, 2)
    }

    private func directorSignalLine(icon: String, title: String, detail: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint.opacity(0.86))
                .frame(width: 18, height: 18)
                .background(tint.opacity(0.28), in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(tint.opacity(0.34), lineWidth: 1))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(tint.opacity(0.78))
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(tint.opacity(0.16), lineWidth: 1))
    }

    private var soundscapeIcon: String {
        if soundscape.riskPressure >= 0.62 { return "exclamationmark.triangle.fill" }
        if soundscape.bodyAlarm >= 0.52 { return "waveform.path.ecg" }
        if soundscape.supportSignal >= 0.44 { return "ear.and.waveform" }
        return "waveform.and.magnifyingglass"
    }

    private var soundscapeTint: Color {
        if soundscape.riskPressure >= 0.62 { return .orange }
        if soundscape.bodyAlarm >= 0.52 { return .pink }
        if soundscape.supportSignal >= 0.44 { return .mint }
        return .cyan
    }

    private func peerCueTint(_ cue: SensoryPeerCue) -> Color {
        switch cue.tone {
        case .warning:
            return .orange
        case .support:
            return .mint
        case .body:
            return .pink
        case .institution:
            return .cyan
        }
    }
}

struct SensorySoundscapeView: View {
    let soundscape: SensorySoundscape
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 9) {
            HStack(spacing: 7) {
                Image(systemName: symbolName)
                    .font(.system(size: compact ? 10 : 13, weight: .bold))
                    .foregroundStyle(accent.opacity(0.92))
                    .frame(width: compact ? 14 : 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(soundscape.title)
                        .font(.system(size: compact ? 10 : 13, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Text(soundscape.subtitle)
                        .font(.system(size: compact ? 8.5 : 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(compact ? 1 : 2)
                        .minimumScaleFactor(0.72)
                }
                Spacer(minLength: 0)
                Text("\(soundscape.cueCount)")
                    .font(.system(size: compact ? 9 : 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.58))
            }

            if compact == false {
                Text(soundscape.recommendation)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(accent.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    soundscapeGauge("风险", value: soundscape.riskPressure, tint: .orange)
                    soundscapeGauge("支持", value: soundscape.supportSignal, tint: .mint)
                    soundscapeGauge("身体", value: soundscape.bodyAlarm, tint: .pink)
                    soundscapeGauge("制度", value: soundscape.institutionalPressure, tint: .cyan)
                }
            }
        }
        .padding(compact ? 7 : 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(compact ? 0.08 : 0.11), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(accent.opacity(0.22), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(soundscape.title)，\(soundscape.subtitle)。\(soundscape.recommendation)")
    }

    private func soundscapeGauge(_ title: String, value: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 9.5, weight: .bold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(Int((value * 100).rounded()))")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.58))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule()
                        .fill(tint.opacity(0.82))
                        .frame(width: geo.size.width * value.clamped(to: 0...1))
                }
            }
            .frame(height: 5)
        }
        .frame(maxWidth: .infinity, minHeight: 32)
    }

    private var symbolName: String {
        if soundscape.riskPressure >= 0.62 { return "exclamationmark.triangle.fill" }
        if soundscape.bodyAlarm >= 0.52 { return "waveform.path.ecg" }
        if soundscape.supportSignal >= 0.44 { return "ear.and.waveform" }
        if soundscape.institutionalPressure >= 0.48 { return "building.columns.fill" }
        return "waveform.and.magnifyingglass"
    }

    private var accent: Color {
        if soundscape.riskPressure >= 0.62 { return .orange }
        if soundscape.bodyAlarm >= 0.52 { return .pink }
        if soundscape.supportSignal >= 0.44 { return .mint }
        if soundscape.institutionalPressure >= 0.48 { return .cyan }
        return .white
    }
}

struct SeatedPosePressureView: View {
    let feedback: SeatedPosePressureFeedback
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 8) {
            HStack(spacing: 7) {
                Image(systemName: symbolName)
                    .font(.system(size: compact ? 10 : 13, weight: .bold))
                    .foregroundStyle(accent.opacity(0.9))
                    .frame(width: compact ? 14 : 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(feedback.title)
                        .font(.system(size: compact ? 10 : 13, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                    Text(feedback.detail)
                        .font(.system(size: compact ? 8.5 : 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(compact ? 1 : 2)
                        .minimumScaleFactor(0.72)
                }
                Spacer(minLength: 0)
                Text("\(Int((feedback.intensity * 100).rounded()))")
                    .font(.system(size: compact ? 8.5 : 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(accent.opacity(0.84))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule()
                        .fill(accent.opacity(0.84))
                        .frame(width: geo.size.width * feedback.intensity.clamped(to: 0...1))
                }
            }
            .frame(height: compact ? 5 : 6)

            if compact == false {
                Text(feedback.recommendation)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(accent.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(compact ? 7 : 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(compact ? 0.08 : 0.11), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(accent.opacity(0.22), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(feedback.title)，\(feedback.detail)。\(feedback.recommendation)")
    }

    private var symbolName: String {
        switch feedback.tone {
        case .stable:
            return "person.crop.square"
        case .risk:
            return "exclamationmark.triangle.fill"
        case .body:
            return "waveform.path.ecg"
        case .connection:
            return "person.2.wave.2.fill"
        }
    }

    private var accent: Color {
        switch feedback.tone {
        case .stable:
            return .cyan
        case .risk:
            return .orange
        case .body:
            return .pink
        case .connection:
            return .mint
        }
    }
}

struct TeacherPatrolReadoutView: View {
    let readout: TeacherPatrolReadout
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 8) {
            HStack(spacing: 7) {
                Image(systemName: symbolName)
                    .font(.system(size: compact ? 10 : 13, weight: .bold))
                    .foregroundStyle(accent.opacity(0.9))
                    .frame(width: compact ? 14 : 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(readout.title)
                        .font(.system(size: compact ? 10 : 13, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                    Text("\(readout.location.rawValue) · \(readout.detail)")
                        .font(.system(size: compact ? 8.5 : 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(compact ? 1 : 2)
                        .minimumScaleFactor(0.72)
                }
                Spacer(minLength: 0)
                Text("\(Int((readout.intensity * 100).rounded()))")
                    .font(.system(size: compact ? 8.5 : 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(accent.opacity(0.84))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule()
                        .fill(accent.opacity(0.84))
                        .frame(width: geo.size.width * readout.intensity.clamped(to: 0...1))
                }
            }
            .frame(height: compact ? 5 : 6)

            if compact == false {
                Text(readout.recommendation)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(accent.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(compact ? 7 : 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(compact ? 0.08 : 0.11), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(accent.opacity(0.22), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(readout.title)，\(readout.detail)。\(readout.recommendation)")
    }

    private var symbolName: String {
        switch readout.tone {
        case .distant:
            return "figure.stand"
        case .approaching:
            return "shoeprints.fill"
        case .close:
            return "person.crop.circle.badge.exclamationmark.fill"
        case .unseen:
            return "door.left.hand.closed"
        }
    }

    private var accent: Color {
        switch readout.tone {
        case .distant:
            return .cyan
        case .approaching:
            return .yellow
        case .close:
            return .orange
        case .unseen:
            return .purple
        }
    }
}

struct SpatialAudioObjectiveView: View {
    let objective: SpatialAudioObjective
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 8) {
            HStack(alignment: .center, spacing: 7) {
                Image(systemName: objective.isLocated ? "ear.badge.checkmark" : "ear.and.waveform")
                    .font(.system(size: compact ? 10 : 13, weight: .bold))
                    .foregroundStyle(accent.opacity(0.94))
                    .frame(width: compact ? 15 : 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(objective.title)
                        .font(.system(size: compact ? 10 : 13, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                    Text(objective.sourceLine)
                        .font(.system(size: compact ? 8.5 : 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(compact ? 1 : 2)
                        .minimumScaleFactor(0.72)
                }
                Spacer(minLength: 0)
                Text(objective.targetPose.rawValue)
                    .font(.system(size: compact ? 8.5 : 10.5, weight: .bold))
                    .foregroundStyle(accent.opacity(0.82))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
            }

            HStack(spacing: 7) {
                objectiveMeter
                    .frame(maxWidth: .infinity)
                Text(objective.isLocated ? objective.confirmAction : objective.locateAction)
                    .font(.system(size: compact ? 8.5 : 10, weight: .bold))
                    .foregroundStyle(accent.opacity(0.86))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            if compact == false {
                Text(objective.statusLine)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(compact ? 7 : 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(compact ? 0.08 : 0.11), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(accent.opacity(0.24), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("声源目标，\(objective.title)，方向 \(objective.direction)，\(objective.statusLine)")
    }

    private var objectiveMeter: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                Capsule()
                    .fill(accent.opacity(0.84))
                    .frame(width: geo.size.width * objective.progress.clamped(to: 0...1))
            }
        }
        .frame(height: compact ? 5 : 6)
    }

    private var accent: Color {
        objective.isLocated ? .mint : .cyan
    }
}

struct SensoryPeerCueView: View {
    let cue: SensoryPeerCue
    let compact: Bool

    var body: some View {
        HStack(alignment: .top, spacing: compact ? 6 : 9) {
            Image(systemName: symbolName)
                .font(.system(size: compact ? 9 : 13, weight: .bold))
                .foregroundStyle(accent.opacity(0.9))
                .frame(width: compact ? 13 : 18, height: compact ? 13 : 18)
                .padding(.top, compact ? 1 : 2)
            VStack(alignment: .leading, spacing: compact ? 2 : 5) {
                HStack(spacing: 5) {
                    Text(cue.direction)
                        .font(.system(size: compact ? 8.5 : 10, weight: .bold))
                        .foregroundStyle(accent.opacity(0.86))
                        .lineLimit(1)
                    Text(cue.classmateName)
                        .font(.system(size: compact ? 8.5 : 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.64))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                Text(cue.spokenLine)
                    .font(.system(size: compact ? 9 : 11.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(compact ? 2 : 3)
                    .minimumScaleFactor(0.78)
                if compact == false {
                    Text(cue.lowPressureAction)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(accent.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(compact ? 7 : 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(compact ? 0.07 : 0.1), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(accent.opacity(0.2), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(cue.direction)，\(cue.classmateName)：\(cue.spokenLine)。\(cue.lowPressureAction)")
    }

    private var symbolName: String {
        switch cue.tone {
        case .warning:
            return "eye.trianglebadge.exclamationmark.fill"
        case .support:
            return "text.bubble.fill"
        case .body:
            return "heart.text.square.fill"
        case .institution:
            return "building.columns.fill"
        }
    }

    private var accent: Color {
        switch cue.tone {
        case .warning:
            return .orange
        case .support:
            return .mint
        case .body:
            return .pink
        case .institution:
            return .cyan
        }
    }
}

struct DirectionalSubtitleStripView: View {
    let events: [DirectionalSubtitleEvent]
    let captionsEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if captionsEnabled == false {
                Label("方向字幕关闭", systemImage: "captions.bubble")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
            } else if events.isEmpty {
                Label("等待声音事件", systemImage: "captions.bubble.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
            } else {
                ForEach(events) { event in
                    HStack(spacing: 6) {
                        Image(systemName: "captions.bubble.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.cyan.opacity(0.86))
                            .frame(width: 14)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(event.kind.rawValue) · \(event.direction)")
                                .font(.system(size: 10, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(.white.opacity(0.13))
                                    Capsule().fill(.cyan.opacity(0.78)).frame(width: geo.size.width * event.intensity)
                                }
                            }
                            .frame(height: 4)
                        }
                    }
                    .help(event.note)
                    .accessibilityLabel(event.accessibilitySummary)
                }
            }
        }
        .foregroundStyle(.white)
    }
}

struct SoundRadarView: View {
    let cues: [AudioCue]

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 3
            var grid = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            grid.move(to: CGPoint(x: center.x, y: center.y - radius))
            grid.addLine(to: CGPoint(x: center.x, y: center.y + radius))
            grid.move(to: CGPoint(x: center.x - radius, y: center.y))
            grid.addLine(to: CGPoint(x: center.x + radius, y: center.y))
            context.stroke(grid, with: .color(.white.opacity(0.18)), lineWidth: 1)

            let listener = Path(ellipseIn: CGRect(x: center.x - 2.5, y: center.y - 2.5, width: 5, height: 5))
            context.fill(listener, with: .color(.white.opacity(0.7)))

            let dominantCue = cues.prefix(5).max { lhs, rhs in lhs.intensity < rhs.intensity }

            for cue in cues.prefix(5) {
                let distance = radius * (0.22 + 0.7 * min(1, cue.intensity))
                let point = CGPoint(
                    x: center.x + cos(cue.radarAngleRadians) * distance,
                    y: center.y + sin(cue.radarAngleRadians) * distance
                )
                let dotRadius = 2.5 + cue.intensity * 4.5
                let dot = Path(ellipseIn: CGRect(x: point.x - dotRadius, y: point.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
                context.fill(dot, with: .color(color(for: cue.kind).opacity(0.48 + cue.intensity * 0.42)))
                if cue.id == dominantCue?.id {
                    var focus = Path()
                    focus.move(to: center)
                    focus.addLine(to: point)
                    context.stroke(focus, with: .color(color(for: cue.kind).opacity(0.3)), lineWidth: 1.4)
                    let ringInset = dotRadius + 3
                    let ring = Path(ellipseIn: CGRect(x: point.x - ringInset, y: point.y - ringInset, width: ringInset * 2, height: ringInset * 2))
                    context.stroke(ring, with: .color(color(for: cue.kind).opacity(0.95)), lineWidth: 1.8)
                }
            }
        }
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        guard cues.isEmpty == false else { return "声音方向雷达，暂无突出声源" }
        let summary = cues.prefix(5).map { "\($0.kind.rawValue)\($0.spatialReadout)" }.joined(separator: "，")
        return "声音方向雷达，\(summary)"
    }

    private func color(for kind: AudioCueKind) -> Color {
        switch kind {
        case .footstep, .knock: return .orange
        case .phone, .broadcast: return .blue
        case .bell: return .teal
        case .paper, .wrapper, .chair: return .yellow
        case .whisper, .crying: return .cyan
        case .lights: return .mint
        case .heartbeat, .stomach: return .red
        case .teacherCough, .teacherSigh: return .purple
        }
    }
}

struct AudioCueReadoutView: View {
    let cue: AudioCue
    var compact = false

    var body: some View {
        HStack(alignment: .top, spacing: compact ? 7 : 9) {
            Image(systemName: icon(for: cue.kind))
                .font(.system(size: compact ? 10 : 12, weight: .bold))
                .foregroundStyle(color(for: cue.kind).opacity(0.9))
                .frame(width: compact ? 14 : 18, height: compact ? 14 : 18)
            VStack(alignment: .leading, spacing: compact ? 2 : 3) {
                Text("\(cue.kind.rawValue) · \(cue.spatialReadout) · \(intensityText(cue.intensity))")
                    .font(.system(size: compact ? 10 : 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Text("\(cue.tacticalSignalText)信号")
                    .font(.system(size: compact ? 9 : 10, weight: .semibold))
                    .foregroundStyle(color(for: cue.kind).opacity(0.82))
                    .lineLimit(1)
                Text("\(cue.direction)：\(cue.note)")
                    .font(.system(size: compact ? 9 : 10))
                    .foregroundStyle(.white.opacity(0.66))
                    .lineLimit(compact ? 2 : nil)
                    .fixedSize(horizontal: false, vertical: true)
                if compact == false {
                    Text(advice(for: cue))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(color(for: cue.kind).opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(compact ? 7 : 9)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.white.opacity(compact ? 0.07 : 0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.12), lineWidth: 1))
        .accessibilityLabel("声音，\(cue.kind.rawValue)，\(cue.spatialReadout)，\(cue.direction)，\(cue.note)")
    }

    private func intensityText(_ value: Double) -> String {
        if value > 0.76 { return "很清楚" }
        if value > 0.42 { return "能分辨" }
        return "很轻"
    }

    private func advice(for cue: AudioCue) -> String {
        switch cue.kind {
        case .footstep, .knock:
            return cue.direction.contains("后") ? "后方声音需要用余光确认，别贸然回头太久。" : "先降低暴露，再决定是否继续当前动作。"
        case .phone, .wrapper:
            return "这是容易暴露的小声源，适合立刻收手或切回低风险姿态。"
        case .whisper, .paper, .crying:
            return "这可能是支持或求助入口，用短句回应，别把对方推到全班视线里。"
        case .heartbeat, .stomach:
            return "身体声音变大时，先做低消耗恢复动作。"
        case .teacherCough, .teacherSigh, .broadcast:
            return "这是制度压力信号，观察节奏比立刻行动更稳。"
        case .lights, .bell, .chair:
            return "环境或姿态声音在提醒阶段变化，利用它遮蔽或收束动作。"
        }
    }

    private func icon(for kind: AudioCueKind) -> String {
        switch kind {
        case .footstep: return "shoeprints.fill"
        case .paper: return "doc.text.fill"
        case .phone: return "iphone"
        case .whisper: return "text.bubble.fill"
        case .chair: return "chair.fill"
        case .crying: return "drop.fill"
        case .lights: return "lightbulb.fill"
        case .heartbeat: return "heart.fill"
        case .broadcast: return "speaker.wave.2.fill"
        case .bell: return "bell.fill"
        case .knock: return "door.left.hand.closed"
        case .stomach: return "figure.core.training"
        case .wrapper: return "takeoutbag.and.cup.and.straw.fill"
        case .teacherCough: return "lungs.fill"
        case .teacherSigh: return "wind"
        }
    }

    private func color(for kind: AudioCueKind) -> Color {
        switch kind {
        case .footstep, .knock: return .orange
        case .phone, .broadcast: return .blue
        case .bell: return .teal
        case .paper, .wrapper, .chair: return .yellow
        case .whisper, .crying: return .cyan
        case .lights: return .mint
        case .heartbeat, .stomach: return .red
        case .teacherCough, .teacherSigh: return .purple
        }
    }
}

struct NarrativeMinimalHUDControls: View {
    let captionsEnabled: Bool
    let onToggleCaptions: () -> Void
    let onPause: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggleCaptions) {
                Image(systemName: captionsEnabled ? "captions.bubble.fill" : "captions.bubble")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(captionsEnabled ? .cyan.opacity(0.92) : .white.opacity(0.72))
                    .frame(width: 34, height: 30)
                    .background(captionsEnabled ? .cyan.opacity(0.18) : .white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(0.16), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("方向字幕")
            .accessibilityLabel("方向字幕")

            Button(action: onPause) {
                Image(systemName: "pause.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(width: 34, height: 30)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(0.16), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("暂停")
            .accessibilityLabel("暂停")
        }
        .padding(6)
        .background(.black.opacity(0.46), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.14), lineWidth: 1))
    }
}

struct FocusFeedbackOverlay: View {
    let feedback: DwellFocusFeedback
    let reduceMotion: Bool
    @State private var visible: Bool

    init(feedback: DwellFocusFeedback, reduceMotion: Bool, initiallyVisible: Bool = false) {
        self.feedback = feedback
        self.reduceMotion = reduceMotion
        _visible = State(initialValue: initiallyVisible)
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.clear)
                .overlay(alignment: .center) {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(accent.opacity(visible ? 0.5 : 0), lineWidth: 3)
                        .padding(14)
                        .blur(radius: 7)
                }
            Rectangle()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            accent.opacity(visible ? 0.38 : 0),
                            .white.opacity(visible ? 0.08 : 0),
                            accent.opacity(visible ? 0.24 : 0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: visible ? 5 : 1
                )
                .blur(radius: visible ? 10 : 3)
        }
        .ignoresSafeArea()
        .onAppear {
            let duration = reduceMotion ? 0.2 : 0.32
            withAnimation(.easeOut(duration: duration)) {
                visible = true
            }
            let hold = reduceMotion ? 0.18 : 0.46
            DispatchQueue.main.asyncAfter(deadline: .now() + hold) {
                withAnimation(.easeIn(duration: duration)) {
                    visible = false
                }
            }
        }
        .id(feedback.id)
        .accessibilityHidden(true)
    }

    private var accent: Color {
        switch feedback.pose {
        case .left, .right:
            return .cyan
        case .desk:
            return .mint
        case .forward, .board, .rear:
            return .white
        }
    }
}

struct ChapterClueStackView: View {
    static let maxVisibleClues = 5

    let clues: [ChapterClue]

    private var visibleClues: [ChapterClue] {
        Array(clues.prefix(Self.maxVisibleClues))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "note.text.badge.plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.yellow.opacity(0.92))
                    .frame(width: 14)
                Text("线索便签")
                    .font(.system(size: 11, weight: .bold))
                Spacer()
                Text("\(visibleClues.count)/5")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.yellow.opacity(0.78))
            }

            if visibleClues.isEmpty {
                Text("看见异常后，便签会留在这里。")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.54))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ZStack(alignment: .topLeading) {
                    ForEach(Array(visibleClues.enumerated()), id: \.element.id) { index, clue in
                        clueCard(clue, index: index)
                            .offset(x: CGFloat(index) * 5, y: CGFloat(index) * 9)
                            .zIndex(Double(index))
                            .accessibilitySortPriority(Double(visibleClues.count - index))
                    }
                }
                .frame(height: CGFloat(visibleClues.count - 1) * 9 + 72, alignment: .topLeading)
            }
        }
        .padding(10)
        .frame(width: 260, alignment: .topLeading)
        .background(.black.opacity(0.30), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.yellow.opacity(0.16), lineWidth: 1))
    }

    private func clueCard(_ clue: ChapterClue, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text("TURN \(clue.turn)")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(.black.opacity(0.46))
                Spacer()
                Circle()
                    .fill(.black.opacity(0.18))
                    .frame(width: 5, height: 5)
            }
            Text(clue.title)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(.black.opacity(0.84))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Text(clue.detail)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.black.opacity(0.62))
                .lineLimit(2)
                .minimumScaleFactor(0.82)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(width: 222, height: 72, alignment: .topLeading)
        .background(
            clueTint(index: index),
            in: RoundedRectangle(cornerRadius: 6)
        )
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.black.opacity(0.10), lineWidth: 1))
        .rotationEffect(.degrees(Double(index % 2 == 0 ? -1 : 1)))
        .shadow(color: .black.opacity(0.22), radius: 5, x: 0, y: 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("线索便签，\(clue.title)，\(clue.detail)")
    }

    private func clueTint(index: Int) -> Color {
        let tints: [Color] = [
            Color(red: 1.0, green: 0.88, blue: 0.42),
            Color(red: 0.92, green: 0.96, blue: 0.62),
            Color(red: 1.0, green: 0.78, blue: 0.54),
            Color(red: 0.82, green: 0.93, blue: 0.98),
            Color(red: 0.94, green: 0.82, blue: 0.98)
        ]
        return tints[index % tints.count]
    }
}

struct PrologueBeatEchoView: View {
    let echo: PrologueBeatEcho

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: echo.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.mint.opacity(0.85))
                .frame(width: 15, height: 17)
            VStack(alignment: .leading, spacing: 2) {
                Text(echo.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(2)
                Text(echo.detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.64))
                    .lineLimit(3)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(echo.title)。\(echo.detail)")
    }
}

struct PrologueAccessibilityHintView: View {
    let onOpenSettings: () -> Void
    let onContinue: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Capsule()
                .fill(Color(red: 0.20, green: 0.92, blue: 0.68))
                .frame(width: 4, height: 72)
                .shadow(color: Color(red: 0.20, green: 0.92, blue: 0.68).opacity(0.45), radius: 8)

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.20, green: 0.92, blue: 0.68).opacity(0.18))
                            .frame(width: 24, height: 24)
                        Image(systemName: "accessibility")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color(red: 0.20, green: 0.92, blue: 0.68))
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("辅助设置")
                            .font(.system(size: 12, weight: .bold))
                        Text("字幕、声音和输入方式可以现在确认")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.white.opacity(0.66))
                            .lineLimit(2)
                            .minimumScaleFactor(0.84)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    Button { onOpenSettings() } label: {
                        Label("调整", systemImage: "slider.horizontal.3")
                            .frame(width: 96, height: 30)
                    }
                    .buttonStyle(ActionButtonStyle())

                    Button { onContinue() } label: {
                        Label("继续", systemImage: "checkmark")
                            .frame(width: 88, height: 30)
                    }
                    .buttonStyle(ActionButtonStyle())
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(12)
        .frame(width: 282, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(.black.opacity(0.18))
                .glassEffect(.regular, in: .rect(cornerRadius: 8))
        }
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.16), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("辅助设置提示。字幕、声音和输入方式可以现在确认。")
    }
}

struct ActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(1)
            .glassEffect(.regular, in: .rect(cornerRadius: 8))
            .buttonStyle(.glass)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct SegmentButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(1)
            .background(isSelected ? .blue.opacity(0.28) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .glassEffect(.regular, in: .rect(cornerRadius: 7))
            .buttonStyle(.glass)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private extension View {
    func liquidGlassPanel(cornerRadius: CGFloat = 8, tint: Color = .clear) -> some View {
        self
            .background(tint, in: RoundedRectangle(cornerRadius: cornerRadius))
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }

    func controlGlass(cornerRadius: CGFloat = 7) -> some View {
        self
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }
}
