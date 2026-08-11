import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var game: GameManager
    @State private var isPerceptionPanelPresented = false

    var body: some View {
        GeometryReader { proxy in
        ZStack {
            ClassroomSceneView(game: game)
                .ignoresSafeArea()

            if game.isPrologueActive == false {
                vignette
            }
            if game.isPrologueActive == false {
                if isCompactPhone(proxy.size) {
                    compactPhoneStressEdges
                } else {
                    peripheralIndicators
                }
                eventCinematicLayer
            }

            if case .menu = game.gameState {
                if isCompactPhone(proxy.size) {
                    compactPhoneMenuOverlay
                } else {
                    menuOverlay
                }
            } else if game.isPrologueActive {
                if isCompactPhone(proxy.size) {
                    compactPhonePrologueHUD
                } else {
                    prologueHUD
                }
            } else {
                if isCompactPhone(proxy.size) {
                    compactPhoneHUD
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
            }

            if case .event(let event) = game.gameState {
                if isCompactPhone(proxy.size) {
                    compactPhoneEventOverlay(event)
                } else {
                    eventOverlay(event)
                }
            }

            if case .ending(let ending) = game.gameState {
                if isCompactPhone(proxy.size) {
                    compactPhoneEndingOverlay(ending)
                } else {
                    endingOverlay(ending)
                }
            }

            if isPerceptionPanelPresented {
                if isCompactPhone(proxy.size) {
                    compactPhonePerceptionPanel
                } else {
                    perceptionPanel
                }
            }

            if game.isAccessibilityPanelPresented {
                Group {
                    if isCompactPhone(proxy.size) {
                        compactPhoneAccessibilityPanel
                    } else {
                        accessibilityPanel
                    }
                }
                    .zIndex(30)
            }

            if game.isGameGuidePresented {
                Group {
                    if isCompactPhone(proxy.size) {
                        compactPhoneGameGuideOverlay
                    } else {
                        gameGuideOverlay
                    }
                }
                .zIndex(40)
            }

            if game.isChapterOneTransitionPresented {
                chapterOneTransitionOverlay
                    .zIndex(45)
            }

            if game.isPrologueActive && game.isPrologueTutorialPresented {
                Group {
                    if isCompactPhone(proxy.size) {
                        compactPhonePrologueTutorialOverlay
                    } else {
                        prologueTutorialOverlay
                    }
                }
                .zIndex(28)
            }

            if game.isPrologueActive && game.prologuePaused && game.isAccessibilityPanelPresented == false && game.isPrologueTutorialPresented == false {
                prologuePauseOverlay
                    .zIndex(25)
            }

            returnToSeatTransitionLayer

            if let monologue = game.featuredMonologue {
                featuredMonologueLayer(monologue)
                    .transition(.opacity)
                    .zIndex(20)
            }
        }
        .frame(width: proxy.size.width, height: proxy.size.height)
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

    private func isCompactPhone(_ size: CGSize) -> Bool {
        #if os(iOS)
        return size.width < 1000 && size.height < 600
        #else
        return false
        #endif
    }

    private var compactPhoneHUD: some View {
        VStack(spacing: 5) {
            // Keep the center clear for the Dynamic Island and reserve only compact status chips.
            HStack(spacing: 6) {
                compactStatusChip(icon: game.activeRole.icon, text: game.activeRole.rawValue, tint: game.activeRole.isTeacher ? .purple : .cyan)
                compactStatusChip(icon: "clock", text: game.clockText, tint: .white)
                Spacer(minLength: 4)
                compactIconButton("arrow.uturn.backward.circle", help: "回到前方") { game.recenterStudentView() }
                compactIconButton(game.mouseLookEnabled ? "cursorarrow.slash" : "cursorarrow.motionlines", help: "切换视角捕获") {
                    game.setMouseLookEnabled(!game.mouseLookEnabled)
                }
                compactIconButton("gearshape.fill", help: "辅助与体验设置") { game.openAccessibilityPanel() }
            }
            .padding(.horizontal, 10)
            .padding(.top, 3)

            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(game.activeChapter.rawValue)
                        .font(.system(size: 10, weight: .bold))
                    Text(game.chapterCurrentObjective)
                        .font(.system(size: 9, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(.white.opacity(0.76))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                compactStatusChip(icon: "flag.fill", text: game.chapterProgressText, tint: .yellow)
                compactIconButton("slider.horizontal.3", help: "查看状态") { isPerceptionPanelPresented.toggle() }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .liquidGlassPanel(tint: .black.opacity(0.16))

            if game.activeRole.isTeacher {
                compactPhoneTeacherControls
            }

            Spacer(minLength: 0)

            if game.message.isEmpty == false {
                Text(game.message)
                    .font(.custom("Kaiti SC", size: 10))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .foregroundStyle(.white.opacity(0.88))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: 520)
                    .liquidGlassPanel(tint: .black.opacity(0.12))
            }

            if game.activeRole.isTeacher == false && game.freeRoam.isActive == false {
                HStack(spacing: 6) {
                    compactNeedChip(title: "能量", value: game.player.psychicEnergy, color: .green)
                    compactNeedChip(title: "注意", value: game.player.visualAttention, color: .mint)
                    Spacer(minLength: 0)
                    if game.freeRoam.isActive {
                        compactIconButton("chair.fill", help: "回到座位") { game.returnToSeatFromFreeRoam() }
                    }
                }
                .padding(.horizontal, 10)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if game.activeRole.isTeacher {
                        ForEach(TeacherAction.allCases) { action in
                            compactActionButton(icon: action.icon, title: action.rawValue) { game.executeTeacherAction(action) }
                        }
                    } else if game.freeRoam.isActive {
                        EmptyView()
                    } else {
                        ForEach(chapterOneActions) { action in
                            compactActionButton(icon: action.icon, title: action.rawValue) { game.execute(action) }
                        }
                    }
                }
                .padding(.horizontal, 10)
            }
            .frame(height: 48)
            .padding(.bottom, 4)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
        .overlay {
            if game.freeRoam.isActive {
                compactPhoneFreeRoamControls
            }
        }
    }

    private var compactPhoneStressEdges: some View {
        GeometryReader { proxy in
            let progress = min(1, max(0, game.player.stress / 100))
            let reach = 10 + proxy.size.width * 0.105 * progress
            let intensity = 0.12 + progress * 0.5

            HStack(spacing: 0) {
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.red.opacity(intensity), .red.opacity(intensity * 0.28), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: reach)
                    Rectangle()
                        .fill(.red.opacity(intensity))
                        .frame(width: 3)
                    Text("压力 \(Int(game.player.stress))")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.58 + progress * 0.34))
                        .rotationEffect(.degrees(-90))
                        .fixedSize()
                        .offset(x: 4)
                }
                .frame(width: reach, alignment: .leading)

                Spacer(minLength: 0)

                ZStack(alignment: .trailing) {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.clear, .red.opacity(intensity * 0.28), .red.opacity(intensity)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: reach)
                    Rectangle()
                        .fill(.red.opacity(intensity))
                        .frame(width: 3)
                }
                .frame(width: reach, alignment: .trailing)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.45), value: game.player.stress)
    }

    private func compactStatusChip(icon: String, text: String, tint: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(tint.opacity(0.94))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(.ultraThinMaterial, in: Capsule())
    }

    private func compactNeedChip(title: String, value: Double, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(title).font(.system(size: 8, weight: .semibold)).foregroundStyle(.white.opacity(0.62))
            Text("\(Int(value))").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(color)
        }
        .frame(width: 48, height: 30)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 7))
    }

    private func compactIconButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .frame(width: 30, height: 28)
        }
        .buttonStyle(SegmentButtonStyle(isSelected: false))
        .help(help)
    }

    private func compactActionButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.system(size: 8, weight: .semibold))
                    .lineLimit(1)
            }
            .frame(width: 56, height: 36)
        }
        .buttonStyle(CompactPhoneButtonStyle())
    }

    private var compactPhoneFreeRoamControls: some View {
        HStack(alignment: .bottom) {
            CompactPhoneMovementPad { forward, strafe, deltaTime in
                game.moveStudentFreeRoam(forward: forward, strafe: strafe, deltaTime: deltaTime)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 6) {
                    compactToggleButton(icon: "rectangle.compress.vertical", title: "侧身", isSelected: game.freeRoam.isSideways) {
                        game.setFreeRoamSideways(!game.freeRoam.isSideways)
                    }
                    compactToggleButton(icon: "figure.run", title: "奔跑", isSelected: game.freeRoam.isSprinting) {
                        game.setFreeRoamSprinting(!game.freeRoam.isSprinting)
                    }
                }
                if let interaction = compactPhoneInteraction {
                    Button { performCompactPhoneInteraction() } label: {
                        Label(interaction.title, systemImage: interaction.icon)
                            .font(.system(size: 10, weight: .bold))
                            .frame(minWidth: 118, minHeight: 34)
                    }
                    .buttonStyle(ActionButtonStyle())
                }
                if game.isPrologueActive == false {
                    Button { game.returnToSeatFromFreeRoam() } label: {
                        Label("回到座位", systemImage: "chair.fill")
                            .font(.system(size: 10, weight: .bold))
                            .frame(minWidth: 118, minHeight: 30)
                    }
                    .buttonStyle(CompactPhoneButtonStyle())
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 58)
        .allowsHitTesting(true)
    }

    private func compactToggleButton(icon: String, title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 13, weight: .bold))
                Text(title).font(.system(size: 8, weight: .semibold))
            }
            .frame(width: 54, height: 36)
            .background(isSelected ? Color.cyan.opacity(0.78) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(CompactPhoneButtonStyle())
    }

    private var compactPhoneInteraction: (title: String, icon: String)? {
        if game.isPrologueActive, game.prologueCurrentBeat == .returnToSeat, game.prologueSeatNearby {
            return ("坐回座位", "chair.fill")
        }
        if let door = game.nearbyStudentDoor {
            return (game.isStudentDoorOpen(door) ? "关闭\(door.rawValue)" : "打开\(door.rawValue)", "door.left.hand.open")
        }
        if game.isNearWaterDispenser { return ("接水", "drop.fill") }
        if game.isNearRestroom { return ("如厕", "figure.stand") }
        if game.isNearPlayerLocker { return (game.playerLockerOpen ? "关闭储物柜" : "打开储物柜", "lock.open.fill") }
        return nil
    }

    private func performCompactPhoneInteraction() {
        if game.confirmPrologueSeat() { return }
        if game.interactWithNearbyDoor() { return }
        if game.isNearWaterDispenser { game.refillWaterCup(); return }
        if game.isNearRestroom { game.useRestroom(); return }
        if game.isNearPlayerLocker { game.togglePlayerLocker(); return }
        game.confirmPrologueInteraction()
    }

    private var compactPhoneTeacherControls: some View {
        VStack(spacing: 5) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(TeacherLocation.allCases) { location in
                        Button { game.setTeacherLocation(location) } label: {
                            Label(location.rawValue, systemImage: location.icon)
                                .font(.system(size: 9, weight: .semibold))
                                .frame(minHeight: 26)
                        }
                        .buttonStyle(SegmentButtonStyle(isSelected: game.teacher.location == location))
                    }
                }
                .padding(.horizontal, 10)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(game.teacherTargetCandidates) { mate in
                        Button { game.selectedTeacherTargetID = mate.id } label: {
                            Text("\(mate.name) · 压力 \(Int(mate.stress))")
                                .font(.system(size: 9, weight: .semibold))
                                .frame(minHeight: 26)
                        }
                        .buttonStyle(SegmentButtonStyle(isSelected: game.selectedTeacherTargetID == mate.id))
                    }
                }
                .padding(.horizontal, 10)
            }
        }
    }

    private var compactPhonePrologueHUD: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(game.prologueCurrentBeat.currentGoal)
                        .font(.system(size: 12, weight: .bold))
                    Text(compactPhonePrologueInstruction)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                compactIconButton(game.accessibilityPreferences.directionalSubtitles ? "captions.bubble.fill" : "captions.bubble", help: "方向字幕") {
                    game.accessibilityPreferences.directionalSubtitles.toggle()
                }
                compactIconButton("pause.fill", help: "暂停") { game.setProloguePaused(true) }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .liquidGlassPanel(tint: .black.opacity(0.2))

            Spacer()

            Text(game.message)
                .font(.custom("Kaiti SC", size: 11))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: 560)
                .liquidGlassPanel(tint: .black.opacity(0.18))

            if game.prologueCurrentBeat == .placeWater {
                compactActionButton(icon: "hand.tap.fill", title: "放好水杯") { game.confirmPrologueInteraction() }
            } else if game.prologueCurrentBeat == .settleBreath {
                HStack(spacing: 6) {
                    compactActionButton(icon: "wind", title: "深呼吸") { game.execute(.breathe) }
                    compactActionButton(icon: "chair.fill", title: "先坐一会") { game.acknowledgeSettleBreathWithoutAction() }
                }
            } else if game.prologueCurrentBeat == .accessibility {
                HStack(spacing: 6) {
                    compactActionButton(icon: "accessibility", title: "调整体验") { game.acknowledgeAccessibilityTutorial(openSettings: true) }
                    compactActionButton(icon: "arrow.right", title: "继续") { game.acknowledgeAccessibilityTutorial(openSettings: false) }
                }
            }
            if game.canCompleteCurrentPrologueEarly {
                compactActionButton(icon: "checkmark.circle.fill", title: "完成本步") { game.completeCurrentPrologueEarly() }
            }
        }
        .padding(8)
        .overlay {
            if game.freeRoam.isActive { compactPhoneFreeRoamControls }
        }
    }

    private var compactPhonePrologueInstruction: String {
        switch game.prologueCurrentBeat {
        case .lookDownHall: return "在画面上拖动环视，累计移动视角 5 秒；双击可回正。"
        case .returnToSeat: return "使用左侧摇杆行走，右侧拖动画面转向；靠近座位后点击入座。"
        case .placeWater: return "点击下方按钮，把水杯放到桌面。"
        case .noticeLinChe: return "向左拖动画面并停留，认真观察林澈。"
        case .settleBreath: return "选择深呼吸，或允许自己先安静坐一会。"
        case .accessibility: return "可以调整方向字幕、音量和动态效果。"
        default: return "观察画面与声音，准备进入晚自习。"
        }
    }

    private var compactPhonePrologueTutorialOverlay: some View {
        ZStack {
            Color.black.opacity(0.82).ignoresSafeArea()
            VStack(spacing: 10) {
                Text("新手教程").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.55))
                Text(game.prologueCurrentBeat.currentGoal).font(.system(size: 20, weight: .bold))
                Text(compactPhonePrologueInstruction)
                    .font(.custom("Kaiti SC", size: 14))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.8))
                Button { game.dismissCurrentPrologueTutorial() } label: {
                    Label("确认并开始", systemImage: "play.fill").frame(minWidth: 140, minHeight: 34)
                }
                .buttonStyle(ActionButtonStyle())
            }
            .padding(18)
            .frame(maxWidth: 560, maxHeight: 260)
            .liquidGlassPanel()
            .padding(.horizontal, 20)
        }
    }

    private var compactPhoneAccessibilityPanel: some View {
        ZStack {
            Color.black.opacity(0.66).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Label("辅助与体验设置", systemImage: "accessibility")
                            .font(.system(size: 15, weight: .bold))
                        Spacer()
                        compactIconButton("xmark", help: "关闭") { game.closeAccessibilityPanel() }
                    }
                    Toggle("方向字幕", isOn: $game.accessibilityPreferences.directionalSubtitles)
                    prologueVolumeSlider("对白", value: $game.accessibilityPreferences.dialogueVolume)
                    prologueVolumeSlider("环境", value: $game.accessibilityPreferences.ambienceVolume)
                    prologueVolumeSlider("提示音", value: $game.accessibilityPreferences.cueVolume)
                    HStack(spacing: 18) {
                        Toggle("减少动态", isOn: $game.accessibilityPreferences.reduceMotion)
                        Toggle("替代输入", isOn: $game.accessibilityPreferences.keyboardAlternativeInput)
                    }
                    .font(.system(size: 10, weight: .semibold))
                    HStack(spacing: 8) {
                        if game.isGameInProgress {
                            Button { game.returnToMenuFromSettings() } label: {
                                Label("返回主页", systemImage: "house.fill").frame(minHeight: 30)
                            }
                            .buttonStyle(ActionButtonStyle())
                        }
                        if game.gameState == .menu {
                            Button { game.resetProgress() } label: {
                                Label("重置进度", systemImage: "arrow.counterclockwise").frame(minHeight: 30)
                            }
                            .buttonStyle(ActionButtonStyle())
                        }
                    }
                    .font(.system(size: 10, weight: .bold))
                }
                .toggleStyle(.switch)
                .padding(12)
            }
            .frame(maxWidth: 560, maxHeight: 330)
            .liquidGlassPanel()
            .padding(.horizontal, 20)
        }
    }

    private func compactPhoneEndingOverlay(_ ending: Ending) -> some View {
        ZStack {
            Color.black.opacity(0.76).ignoresSafeArea()
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 12) {
                    Text(ending.title)
                        .font(.system(size: 24, weight: .bold))
                    Text(ending.body)
                        .font(.system(size: 12))
                        .multilineTextAlignment(.center)
                    Text(ending.reflection)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.center)

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

                    Button { game.returnToMenuForNewGame() } label: {
                        Label("返回菜单", systemImage: "house.fill").frame(minWidth: 130, minHeight: 34)
                    }
                    .buttonStyle(ActionButtonStyle())
                }
                .padding(10)
                .frame(maxWidth: 720)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var compactPhoneMenuOverlay: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("晚自习模拟器").font(.system(size: 24, weight: .bold))
                    Text("选择本局视角").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.58))
                }
                Spacer()
                compactIconButton("book.pages.fill", help: "游戏说明") {
                    if game.hasCompletedInitialGameGuide { game.presentGameGuide() }
                }
                compactIconButton("gearshape.fill", help: "设置") { game.openAccessibilityPanel() }
            }

            HStack(spacing: 7) {
                ForEach(PlayableRole.selectableCases) { role in
                    Button { game.selectedRole = role } label: {
                        VStack(spacing: 3) {
                            Image(systemName: role.icon).font(.system(size: 15, weight: .bold))
                            Text(role.rawValue).font(.system(size: 10, weight: .bold))
                            Text(role.roleType).font(.system(size: 8)).foregroundStyle(.white.opacity(0.55))
                        }
                        .frame(width: 96, height: 52)
                    }
                    .buttonStyle(SegmentButtonStyle(isSelected: game.selectedRole == role))
                }
            }

            Text(game.selectedRole.shortDescription)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineLimit(2)

            if game.selectedRole.isTeacher {
                Button { game.startGame(as: game.selectedRole) } label: {
                    Label("进入教师线", systemImage: "person.text.rectangle.fill").frame(minWidth: 170, minHeight: 34)
                }
                .buttonStyle(ActionButtonStyle())
                .disabled(game.isMenuEntryLocked)
            } else if game.prologueState.prologueCompleted {
                HStack(spacing: 8) {
                    Button { game.startExperience(forcePrologue: true) } label: {
                        Label("进入序章", systemImage: "building.2.fill").frame(minWidth: 130, minHeight: 34)
                    }
                    .buttonStyle(ActionButtonStyle())
                    Button { game.startGame(as: game.selectedRole) } label: {
                        Label("直接第一章", systemImage: "book.fill").frame(minWidth: 130, minHeight: 34)
                    }
                    .buttonStyle(ActionButtonStyle())
                }
                .disabled(game.isMenuEntryLocked)
            } else {
                Button { game.startExperience() } label: {
                    Label("走进教学楼", systemImage: "door.left.hand.open").frame(minWidth: 170, minHeight: 34)
                }
                .buttonStyle(ActionButtonStyle())
                .disabled(game.isMenuEntryLocked)
            }

            if game.hasCompletedInitialGameGuide == false {
                Text("游戏说明将在 \(game.menuGuideCountdown) 秒后打开")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.56))
            }
        }
        .padding(14)
        .frame(maxWidth: 520)
        .liquidGlassPanel()
        .padding(.horizontal, 18)
    }

    private var compactPhoneGameGuideOverlay: some View {
        ZStack {
            Color.black.opacity(0.9).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("晚自习模拟器")
                            .font(.custom("Songti SC", size: 22).weight(.bold))
                        Text("先照顾好自己，再试着看见别人。")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.58))
                    }
                    Spacer()
                    Image(systemName: "book.pages.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.cyan.opacity(0.78))
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("你将以苏念的第一视角走进晚自习。留意疲惫、呼吸和压力，也从声音与动作中理解同学没有说出口的需要。")
                            .font(.custom("Kaiti SC", size: 13))
                            .foregroundStyle(.white.opacity(0.86))
                        compactGuideRow(icon: "hand.draw.fill", title: "触控视角", text: "在教室画面拖动环视，双击回到前方；底部横向滑动可查看全部动作。")
                        compactGuideRow(icon: "figure.walk", title: "移动与互动", text: "自由活动时使用移动控件，靠近目标后使用出现的交互按钮。")
                        compactGuideRow(icon: "heart.text.square.fill", title: "体验提醒", text: "没有唯一正确答案。深呼吸、喝水、休息和表达需要同样重要。")
                    }
                }

                HStack {
                    Text("说明可在游戏中再次打开")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    Button {
                        game.dismissGameGuide()
                    } label: {
                        if game.gameGuideExitCountdown > 0 {
                            Label("请阅读 \(game.gameGuideExitCountdown) 秒", systemImage: "lock.fill")
                        } else {
                            Label("我已了解", systemImage: "checkmark")
                        }
                    }
                    .font(.system(size: 10, weight: .bold))
                    .buttonStyle(ActionButtonStyle())
                    .disabled(game.gameGuideExitCountdown > 0)
                }
            }
            .padding(14)
            .frame(maxWidth: 620, maxHeight: 330)
            .liquidGlassPanel()
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    private func compactGuideRow(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.cyan)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 11, weight: .bold))
                Text(text).font(.system(size: 10)).foregroundStyle(.white.opacity(0.68))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var compactPhonePerceptionPanel: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea().onTapGesture { isPerceptionPanelPresented = false }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("声场与视线", systemImage: "waveform.and.magnifyingglass")
                        .font(.system(size: 15, weight: .bold))
                    Spacer()
                    compactIconButton("xmark", help: "关闭") { isPerceptionPanelPresented = false }
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        perceptionRow(icon: "eye.fill", title: game.cameraPose.rawValue, detail: game.cameraPose.visionZone.displayName, advice: visualAdvice, tint: .mint)
                        ForEach(game.audioCues.prefix(3)) { cue in
                            perceptionRow(icon: icon(for: cue.kind), title: "\(cue.kind.rawValue) · \(cue.direction)", detail: cue.note, advice: audioAdvice(for: cue), tint: color(for: cue.kind))
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: 620, maxHeight: 320)
            .liquidGlassPanel()
            .padding(.horizontal, 16)
        }
    }

    private func compactPhoneEventOverlay(_ event: ActiveEvent) -> some View {
        VStack(spacing: 8) {
            Text(event.title)
                .font(.system(size: 17, weight: .bold))
            Text(event.body)
                .font(.system(size: 11))
                .multilineTextAlignment(.center)
                .lineLimit(3)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(event.choices) { choice in
                        Button { game.resolveEventChoice(choice) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(choice.title).font(.system(size: 11, weight: .bold))
                                Text(choice.detail).font(.system(size: 9)).foregroundStyle(.white.opacity(0.62)).lineLimit(2)
                            }
                            .frame(width: 150, height: 44, alignment: .leading)
                        }
                        .buttonStyle(ActionButtonStyle())
                    }
                }
                .padding(.horizontal, 2)
            }
            if event.choices.isEmpty {
                Button("继续晚自习") { game.continueAfterEvent() }
                    .font(.system(size: 11, weight: .bold))
                    .buttonStyle(ActionButtonStyle())
            }
        }
        .padding(12)
        .frame(maxWidth: 620)
        .liquidGlassPanel()
        .padding(.horizontal, 16)
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
                    Text("新手必看！！！游戏说明")
                        .font(.custom("Songti SC", size: 25).weight(.bold))
                        .foregroundStyle(.white.opacity(0.92))
                    if game.hasCompletedInitialGameGuide == false {
                        Text("\(game.menuGuideCountdown) 秒后自动跳转")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.78))
                    } else {
                        Text("点击再次查看")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
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

            if game.prologueState.prologueCompleted {
                HStack(spacing: 12) {
                    Button { game.startExperience(forcePrologue: true) } label: {
                        Label("进入序章", systemImage: "building.2.fill")
                            .frame(width: 150, height: 38)
                    }
                    .buttonStyle(ActionButtonStyle())
                    .disabled(game.isMenuEntryLocked)
                    Button { game.startGame() } label: {
                        Label("直接第一章", systemImage: "book.fill")
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
                        Text("游戏简介 · 草稿")
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
                        Text("你将以学生苏念的第一视角，走进一场看似普通的晚自习。这里没有悬浮在人物头顶的状态数字，也没有唯一正确的标准答案。你需要留意自己的疲惫、呼吸和压力，也要从声音、动作与短暂的交流中，慢慢理解身边同学没有说出口的需要。")
                            .font(.custom("Kaiti SC", size: 18))
                            .lineSpacing(6)
                            .foregroundStyle(.white.opacity(0.88))

                        HStack(alignment: .top, spacing: 32) {
                            gameGuideCharacters
                            gameGuideChapterRoadmap
                        }

                        gameGuideAttributes

                        Divider().overlay(.white.opacity(0.12))

                            HStack(alignment: .top, spacing: 28) {
                            guideSection(
                                title: "如何操作",
                                icon: "keyboard",
                                text: "移动鼠标控制视角，WASD 行走，E 键确认互动。按 ～ 释放或恢复鼠标；新手教学中按 T 可重新查看当前提示。"
                            )
                            guideSection(
                                title: "如何体验",
                                icon: "eye.fill",
                                text: "观察别人并不是唯一任务。深呼吸、喝水、休息和表达自己的需要同样重要。错过某条线索不会立刻判定失败。"
                            )
                            guideSection(
                                title: "内容提醒",
                                icon: "heart.text.square.fill",
                                text: "故事涉及学业压力、情绪低落和求助。它用于理解与体验，不替代心理咨询、医学诊断或现实中的紧急帮助。"
                            )
                        }

                        HStack(alignment: .top, spacing: 28) {
                            guideSection(
                                title: "提前完成",
                                icon: "forward.end.fill",
                                text: "需要互动的步骤必须先完成核心操作，随后才会解锁 C（Complete），用于提前结束剩余倒计时。步骤 1/8 必须完成 5 秒有效环视。"
                            )
                            guideSection(
                                title: "再次查看",
                                icon: "arrow.counterclockwise.circle.fill",
                                text: "练习过程中按 T（Tips）可以重新打开当前步骤说明。教程会暂停，点击确认后继续。"
                            )
                        }
                    }
                }
                .frame(maxHeight: 440)

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
            Text(gameGuideCharacterText)
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
            Text("当前版本已搭建第一章框架，后续章节将依次完成。")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
            Text(gameGuideChapterText)
                .font(.custom("Kaiti SC", size: 15))
                .foregroundStyle(.white.opacity(0.74))
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var gameGuideCharacterText: String {
        let jiangYue = game.prologueState.prologueCompleted
            ? "江越：求助纸条的主人，主线中真正需要被可靠支持接住的人。"
            : "江越：？？？"
        return "苏念：玩家角色，高二（3）班新任心理委员。她善于观察，也承受着自己的学业与家庭压力。\n林澈：苏念的同桌，成绩优秀，却被完美主义困住。\n\(jiangYue)\n周予安：班级事务的执行者，做事直接，习惯把混乱整理成清单。\n许栀：细心而敏感，常常先注意到别人情绪里的细小变化。\n陈言：安静可靠，愿意在关键时刻提供实际帮助。\n方老师：高二（3）班班主任，负责维持班级秩序，也在学习如何真正理解学生。\n心理老师：学校专业支持的承接者，帮助学生把难以独自承担的事情交给可靠的大人。"
    }

    private var gameGuideChapterText: String {
        let chapterFour = game.prologueState.prologueCompleted
            ? "4 13 楼的缝隙：陪江越留下并判断风险。"
            : "4 ？？？"
        return "1 静音的教室：发现异常与求助纸条。\n2 走廊的镜子：练习倾听，不急着说教。\n3 那张纸条：确认求助者与去向。\n\(chapterFour)\n5 有灯亮着的房间：把支持交给可靠成人。\n6 这里有光：看见支持网络，也允许苏念被帮助。"
    }

    private var gameGuideAttributes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("重要属性", systemImage: "waveform.path.ecg")
                .font(.system(size: 15, weight: .bold))
            Text("心理能量：苏念维持行动和自我调节的内在余力。能量过低时，选择会变得更困难，也更需要先休息。\n注意力：当前能够稳定观察、倾听和处理信息的程度。注意力不足时，细节可能从视线和声音中滑过去。\n面具成本：为了表现得“没事”、维持合适的样子而付出的心理代价。它越高，越需要留意自己是否一直在压抑真实感受。\n压力：学业、秩序、他人目光和未解决的情绪共同形成的紧绷感。压力会影响感知和行动，也可以通过呼吸、休息、喝水与可靠的交流逐渐缓解。")
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
                if game.accessibilityPreferences.directionalSubtitles, let cue = game.audioCues.first {
                    Text("[\(cue.direction)：\(cue.kind.rawValue)]")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.black.opacity(0.48))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                Text(game.message)
                    .font(.custom("Kaiti SC", size: 18))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.94))
                    .frame(maxWidth: 760)
                    .padding(14)
                    .background(.black.opacity(0.48))
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                prologueControls
            }
            .padding(18)
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
                .font(.custom("Kaiti SC", size: 18))
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

                prologueTutorialInstructionText
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

    private var prologueTutorialInstructionText: Text {
        guard game.prologueCurrentBeat == .placeWater else {
            return Text(game.prologueCurrentBeat.tutorialInstruction)
        }
        return Text("先把水杯放到桌上，做好晚自习的一切准备。单击 E 键即可完成操作，\(Text("游戏里的其他交互也都是 E 键").bold())。放好后会解锁 C，可以提前结束剩余倒计时。")
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
        case .accessibility:
            HStack(spacing: 10) {
                Button { game.acknowledgeAccessibilityTutorial(openSettings: true) } label: {
                    Label("调整体验", systemImage: "accessibility").frame(width: 130, height: 36)
                }
                .buttonStyle(ActionButtonStyle())
                Button { game.acknowledgeAccessibilityTutorial(openSettings: false) } label: {
                    Text("继续").frame(width: 100, height: 36)
                }
                .buttonStyle(ActionButtonStyle())
            }
            .padding(.top, 8)
        case .placeWater:
            Text("E · 确认")
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
                Toggle("方向字幕", isOn: $game.accessibilityPreferences.directionalSubtitles)
                prologueVolumeSlider("对白", value: $game.accessibilityPreferences.dialogueVolume)
                prologueVolumeSlider("环境", value: $game.accessibilityPreferences.ambienceVolume)
                prologueVolumeSlider("提示音", value: $game.accessibilityPreferences.cueVolume)
                Toggle("减少动态效果", isOn: $game.accessibilityPreferences.reduceMotion)
                Toggle("键盘替代输入", isOn: $game.accessibilityPreferences.keyboardAlternativeInput)
                Text("这些设置会立即保留到后续章节。")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.58))
                Divider().overlay(.white.opacity(0.12))
                HStack(spacing: 10) {
                    Button {
                        game.returnToMenuFromSettings()
                    } label: {
                        Label("返回主页", systemImage: "house.fill")
                            .frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .buttonStyle(ActionButtonStyle())
                    .disabled(game.isGameInProgress == false)

                    Button {
                        game.resetProgress()
                    } label: {
                        Label("重置进度", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .buttonStyle(ActionButtonStyle())
                    .disabled(game.gameState != .menu)
                }
                Text(game.isGameInProgress
                     ? "退出当前一局后，才能重置全部进度。"
                     : "重置后将重新显示首次说明，并隐藏尚未解锁的剧情信息。")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
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

    private var topHUD: some View {
        HStack(alignment: .top, spacing: 14) {
            compactChapterIdentity

            Spacer()

            chapterPanel
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

    private var chapterPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "note.text")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.yellow.opacity(0.9))
                Text(game.activeChapter.rawValue)
                    .font(.system(size: 13, weight: .bold))
            }
            Text(game.chapterObjectiveText)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.66))
                .fixedSize(horizontal: false, vertical: true)
            Text(game.chapterCurrentObjective)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.94))
                .fixedSize(horizontal: false, vertical: true)
            Text(game.chapterProgressText)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.cyan.opacity(0.86))
                .fixedSize(horizontal: false, vertical: true)
            Divider()
                .overlay(.white.opacity(0.18))
            if game.chapterClues.isEmpty {
                Text("线索便签会在你真正看见异常时出现。")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.52))
            } else {
                ForEach(game.chapterClues.suffix(3).reversed()) { clue in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("便签 · \(clue.title)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.yellow.opacity(0.86))
                        Text(clue.detail)
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(10)
        .frame(width: 260, alignment: .topLeading)
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
#if os(macOS)
                .toggleStyle(.checkbox)
#else
                .toggleStyle(.switch)
#endif
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
            ForEach(game.audioCues.prefix(3)) { cue in
                HStack(spacing: 6) {
                    Image(systemName: icon(for: cue.kind))
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 14)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(cue.kind.rawValue) · \(cue.direction)")
                            .font(.system(size: 10, weight: .semibold))
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.13))
                                Capsule().fill(.cyan.opacity(0.78)).frame(width: geo.size.width * cue.intensity)
                            }
                        }
                        .frame(height: 4)
                    }
                }
                .help(cue.note)
            }
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
                            perceptionRow(
                                icon: icon(for: cue.kind),
                                title: "\(cue.kind.rawValue) · \(cue.direction) · \(cueIntensityText(cue.intensity))",
                                detail: cue.note,
                                advice: audioAdvice(for: cue),
                                tint: color(for: cue.kind)
                            )
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

            for cue in game.audioCues.prefix(5) {
                let angle = audioAngle(for: cue.direction)
                let distance = radius * (0.22 + 0.7 * min(1, cue.intensity))
                let point = CGPoint(
                    x: center.x + cos(angle) * distance,
                    y: center.y + sin(angle) * distance
                )
                let dotRadius = 2.5 + cue.intensity * 4.5
                let dot = Path(ellipseIn: CGRect(x: point.x - dotRadius, y: point.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
                context.fill(dot, with: .color(color(for: cue.kind).opacity(0.48 + cue.intensity * 0.42)))
            }
        }
        .accessibilityLabel("声音方向雷达")
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
        case .broadcast:
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
                .font(.custom("Kaiti SC", size: 14))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
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

    private func audioAngle(for direction: String) -> Double {
        if direction.contains("颅内") { return -.pi / 2 }
        if direction.contains("头顶") { return -.pi / 2 }
        if direction.contains("后") { return .pi / 2 }
        if direction.contains("左") { return .pi }
        if direction.contains("右") { return 0 }
        if direction.contains("桌面") || direction.contains("桌边") || direction.contains("座位") { return -.pi / 5 }
        if direction.contains("讲台") || direction.contains("前") { return -.pi / 2 }
        if direction.contains("过道") { return -.pi / 8 }
        return -.pi / 2
    }

    private func color(for kind: AudioCueKind) -> Color {
        switch kind {
        case .footstep, .knock: return .orange
        case .phone, .broadcast: return .blue
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
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.66 + monologue.intensity * 0.12))
                .background(.ultraThinMaterial)
                .ignoresSafeArea()

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
            .padding(48)
        }
        .contentShape(Rectangle())
        .onTapGesture {
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

    private func eventOverlay(_ event: ActiveEvent) -> some View {
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
        VStack(alignment: .leading, spacing: 6) {
            Text("心理支持资源")
                .font(.system(size: 14, weight: .bold))
            ForEach(resources) { resource in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.cyan)
                        .frame(width: 14, height: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(resource.title)
                            .font(.system(size: 11, weight: .semibold))
                        Text(resource.detail)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: 700, alignment: .leading)
        .liquidGlassPanel()
    }
}

struct ActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
#if os(macOS)
        configuration.label
            .foregroundStyle(.white)
            .padding(1)
            .glassEffect(.regular, in: .rect(cornerRadius: 8))
            .buttonStyle(.glass)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
#else
        configuration.label
            .foregroundStyle(.white)
            .padding(8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.14)))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
#endif
    }
}

struct SegmentButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
#if os(macOS)
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(1)
            .background(isSelected ? .blue.opacity(0.28) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .glassEffect(.regular, in: .rect(cornerRadius: 7))
            .buttonStyle(.glass)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
#else
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(5)
            .background(isSelected ? .blue.opacity(0.28) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(0.12)))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
#endif
    }
}

private struct CompactPhoneButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.14)))
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

private struct CompactPhoneMovementPad: View {
    let onMove: (Double, Double, Double) -> Void
    @State private var offset = CGSize.zero
    @State private var movementTask: Task<Void, Never>?
    @State private var forward = 0.0
    @State private var strafe = 0.0

    var body: some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.4))
                .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
            Circle()
                .fill(.cyan.opacity(0.78))
                .frame(width: 38, height: 38)
                .offset(offset)
        }
        .frame(width: 104, height: 104)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let center: CGFloat = 52
                    let dx = value.location.x - center
                    let dy = value.location.y - center
                    let length = max(1, hypot(dx, dy))
                    let radius: CGFloat = 36
                    let scale = min(radius, length) / length
                    offset = CGSize(width: dx * scale, height: dy * scale)
                    forward = Double(-dy / center).clamped(to: -1...1)
                    strafe = Double(dx / center).clamped(to: -1...1)
                    startMovementLoopIfNeeded()
                }
                .onEnded { _ in
                    offset = .zero
                    forward = 0
                    strafe = 0
                    movementTask?.cancel()
                    movementTask = nil
                }
        )
        .onDisappear { movementTask?.cancel() }
        .accessibilityLabel("移动摇杆")
    }

    private func startMovementLoopIfNeeded() {
        guard movementTask == nil else { return }
        movementTask = Task { @MainActor in
            while Task.isCancelled == false {
                onMove(forward, strafe, 1.0 / 30.0)
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }
}

private extension View {
    func liquidGlassPanel(cornerRadius: CGFloat = 8, tint: Color = .clear) -> some View {
#if os(macOS)
        self
            .background(tint, in: RoundedRectangle(cornerRadius: cornerRadius))
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
#else
        self
            .background(tint, in: RoundedRectangle(cornerRadius: cornerRadius))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(.white.opacity(0.13)))
#endif
    }

    func controlGlass(cornerRadius: CGFloat = 7) -> some View {
#if os(macOS)
        self
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
#else
        self
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
#endif
    }
}
