import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var game: GameManager

    var body: some View {
        ZStack {
            ClassroomSceneView(game: game)
                .ignoresSafeArea()

            vignette
            peripheralIndicators
            eventCinematicLayer

            if case .menu = game.gameState {
                menuOverlay
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

            if case .event(let event) = game.gameState {
                eventOverlay(event)
            }

            if case .ending(let ending) = game.gameState {
                endingOverlay(ending)
            }
        }
        .foregroundStyle(.white)
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

            VStack(alignment: .leading, spacing: 10) {
                Text("开局制度参数")
                    .font(.system(size: 13, weight: .bold))
                settingsPanel
            }
            .padding(12)
            .liquidGlassPanel()

            Button {
                game.startGame()
            } label: {
                Label("开始晚自习", systemImage: "play.fill")
                    .frame(width: 180, height: 38)
            }
            .buttonStyle(ActionButtonStyle())
            .keyboardShortcut(.defaultAction)
        }
        .padding(26)
        .liquidGlassPanel()
    }

    private var topHUD: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("第 \(game.currentTurn)/\(game.maxTurns) 回合 · \(game.currentPhase.rawValue)")
                    .font(.system(size: 13, weight: .semibold))
                Text("\(game.clockText) · \(game.currentPeriod.displayName) · \(game.viewMode.perspectiveDescription)")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.68))
                settingsPanel
            }
            .padding(10)
            .liquidGlassPanel()

            Spacer()

            VStack(spacing: 8) {
                meter("心理能量", value: game.player.psychicEnergy, color: .green)
                meter("视觉注意力", value: game.player.visualAttention, color: .mint)
                meter("面具成本", value: game.player.maskCost, color: .purple)
                meter("支持网络", value: game.player.support, color: .cyan)
            }
            .frame(width: 210)
            .padding(10)
            .liquidGlassPanel()

            VStack(spacing: 8) {
                meter("压力", value: game.player.stress, color: .orange)
                meter("暴露", value: game.player.exposure, color: .red)
                meter("作业", value: game.player.homework, color: .blue)
                meter("饥饿", value: game.player.hunger, color: .yellow)
                meter("如厕", value: game.player.bladder, color: .teal)
                Text("\(game.cameraPose.visionZone.rawValue) · \(game.cameraPose.visionZone.displayName)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Text("姿态 · \(game.player.posture.rawValue)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(game.player.posture == .standing ? 0.95 : 0.62))
            }
            .frame(width: 210)
            .padding(10)
            .liquidGlassPanel()
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
            Button {
                game.toggleViewMode()
            } label: {
                Label(game.viewMode.rawValue, systemImage: game.viewMode == .student ? "person.fill" : "person.text.rectangle.fill")
                    .frame(width: 128, height: 32)
            }
            .buttonStyle(SegmentButtonStyle(isSelected: game.viewMode == .teacher))

            if game.viewMode == .teacher {
                VStack(alignment: .leading, spacing: 6) {
                    Text("制度压力 \(Int(game.teacher.institutionalPressure)) · 疲惫 \(Int(game.teacher.fatigue)) · 已提醒 \(game.teacher.studentsWarned) · 已关心 \(game.teacher.studentsHelped)")
                        .font(.system(size: 12, weight: .semibold))
                    if let risk = game.highestRiskClassmate {
                        Text("最高风险学生：\(risk.name) · \(risk.state.rawValue) · 压力 \(Int(risk.stress)) · \(risk.riskReason)")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }
                .padding(10)
                .liquidGlassPanel()
            } else {
                deskmateStrip
            }

            Spacer()

            audioCueStrip
            eventStrip
        }
        .padding(.top, 10)
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
                    Text("关系 \(Int(mate.relationship)) · 怀疑 \(Int(mate.suspicionOfPlayer))")
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
        .frame(width: 160, alignment: .leading)
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
            HStack(spacing: 8) {
                ForEach(CameraPose.allCases, id: \.self) { pose in
                    Button {
                        game.setPose(pose)
                    } label: {
                        Text(pose.rawValue)
                            .frame(width: 64, height: 28)
                    }
                    .buttonStyle(SegmentButtonStyle(isSelected: game.cameraPose == pose))
                    .keyboardShortcut(KeyEquivalent(pose.shortcut), modifiers: [])
                    .help("\(pose.rawValue) · \(String(pose.shortcut).uppercased())")
                }
            }

            HStack(spacing: 10) {
                if game.viewMode == .teacher {
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
                } else {
                    ForEach(PlayerAction.allCases) { action in
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
        }
        .padding(12)
        .liquidGlassPanel()
    }

    private func actionLabel(icon: String, text: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
            Text(text)
                .font(.system(size: 11, weight: .medium))
        }
        .frame(width: 82, height: 58)
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

                endingAnalysis(ending)
                nightTrajectoryPanel
                comparisonPanel(ending.comparisons)
                storyPanel(ending.story)
                empathyPanel(ending.empathyReflections)
                relationshipEchoPanel(ending.relationshipEchoes)
                replayPanel
                resourcesPanel(ending.resources)

                Button("重新开始") {
                    game.startGame()
                }
                .buttonStyle(ActionButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
            .padding(32)
        }
        .frame(maxWidth: 760, maxHeight: 660)
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
