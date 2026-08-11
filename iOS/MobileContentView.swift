import SwiftUI

struct MobileContentView: View {
    @EnvironmentObject private var game: MobileGameManager
    @State private var showGuide = false
    @State private var showInspector = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch game.screen {
            case .menu: menu
            case .prologue: prologue
            case .playing: gameView
            case .ending: ending
            }
        }
        .statusBarHidden(true)
        .sheet(isPresented: $showInspector) { inspector }
    }

    private var menu: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.04, green: 0.07, blue: 0.12), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 20) {
                Spacer()
                Text("晚自习模拟器")
                    .font(.system(size: 42, weight: .bold, design: .serif))
                Text("静音的教室 · iOS 触控版")
                    .font(.headline)
                    .foregroundStyle(.cyan.opacity(0.82))
                Text("一个关于观察、压力和陪伴的第一视角体验。状态不会以数字告诉你答案，留意声音、动作和自己的呼吸。")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.68))
                    .lineSpacing(5)
                    .frame(maxWidth: 520, alignment: .leading)
                Picker("模式", selection: $game.playMode) {
                    ForEach(MobilePlayMode.allCases) { mode in
                        Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
                HStack(spacing: 12) {
                    Button {
                        if game.playMode == .teacher { game.startTeacherMode() } else { game.start() }
                    } label: {
                        Label("走进教室", systemImage: "door.left.hand.open")
                            .frame(minWidth: 150)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    Button { showGuide = true } label: {
                        Label("查看说明", systemImage: "book.pages.fill")
                            .frame(minWidth: 130)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                Button { game.startPrologue() } label: {
                    Label("先体验序章", systemImage: "building.2.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.62))
                Spacer()
                Text("建议横屏 · 支持触控拖动环视")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.38))
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(44)
        }
        .sheet(isPresented: $showGuide) { guide }
    }

    private var gameView: some View {
        ZStack {
            MobileClassroomSceneView(game: game).ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                Spacer()
                messageCard
                controls
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            if let monologue = game.monologue {
                Button { game.dismissMonologue() } label: {
                    Text(monologue)
                        .font(.system(size: 25, weight: .medium, design: .serif))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding(28)
                        .frame(maxWidth: 560)
                }
                .buttonStyle(.plain)
                .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.16)))
            }
            if let event = game.activeEvent {
                eventOverlay(event)
                    .zIndex(20)
            }
            if game.isPaused {
                Color.black.opacity(0.38).ignoresSafeArea()
                VStack(spacing: 8) {
                    Image(systemName: "pause.fill").font(.title2)
                    Text("已暂停").font(.headline)
                    Text("回到游戏后会继续当前晚自习")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                }
                .padding(22)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private var prologue: some View {
        ZStack {
            MobileClassroomSceneView(game: game).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                Text("序章 · 铃响之前")
                    .font(.system(size: 28, weight: .bold, design: .serif))
                Text(game.message)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.82))
                    .lineSpacing(5)
                Text("第 \(game.prologueStep + 1) / 3 段")
                    .font(.caption)
                    .foregroundStyle(.cyan)
                Spacer()
                Button { game.continuePrologue() } label: {
                    Label(game.prologueStep == 2 ? "进入第一章" : "继续", systemImage: "arrow.right")
                        .frame(width: 170)
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(36)
            .frame(maxWidth: 620, maxHeight: .infinity, alignment: .topLeading)
            .background(.black.opacity(0.48), in: RoundedRectangle(cornerRadius: 18))
            .padding(30)
        }
    }

    private var topBar: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("第一章 · 静音的教室")
                    .font(.headline)
                Text(game.currentGoal)
                    .font(.subheadline)
                    .foregroundStyle(.cyan.opacity(0.9))
                    .lineLimit(2)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(game.clockText).font(.system(.headline, design: .monospaced))
                Text(game.direction.rawValue).font(.caption).foregroundStyle(.white.opacity(0.58))
            }
            Image(systemName: game.direction.symbol)
                .font(.title3)
                .frame(width: 36, height: 36)
                .background(.black.opacity(0.42), in: Circle())
            Button { showInspector = true } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(ControlButtonStyle(isSelected: false))
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var messageCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(game.message)
                .font(.system(size: 15, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Image(systemName: "ear.fill")
                Text(game.sensoryStatus)
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.6))
        }
        .padding(15)
        .frame(maxWidth: 680, alignment: .leading)
        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 14))
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ForEach(MobileLookDirection.allCases) { direction in
                    Button { game.look(direction) } label: {
                        Image(systemName: direction.symbol)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                    }
                    .buttonStyle(ControlButtonStyle(isSelected: game.direction == direction))
                }
            }
            if game.playMode == .teacher {
                HStack(spacing: 8) {
                    ForEach(game.availableTeacherActions, id: \.self) { action in
                        Button { game.performTeacherAction(action) } label: {
                            Text(action).font(.system(size: 12, weight: .semibold))
                                .frame(maxWidth: .infinity).frame(height: 42)
                        }
                        .buttonStyle(ControlButtonStyle(isSelected: false))
                    }
                }
            } else {
                HStack(spacing: 8) {
                    ForEach(game.availableActions) { action in
                        Button { game.perform(action) } label: {
                            Label(action.rawValue, systemImage: action.symbol)
                                .font(.system(size: 12, weight: .semibold))
                                .frame(maxWidth: .infinity).frame(height: 42)
                        }
                        .buttonStyle(ControlButtonStyle(isSelected: game.lastAction == action))
                    }
                }
            }
        }
    }

    private func eventOverlay(_ event: MobileEvent) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("正在发生", systemImage: "exclamationmark.bubble.fill")
                .font(.caption.weight(.bold)).foregroundStyle(.cyan)
            Text(event.title).font(.title2.weight(.bold))
            Text(event.body).foregroundStyle(.white.opacity(0.72)).lineSpacing(4)
            ForEach(event.choices, id: \.self) { choice in
                Button { game.resolveEvent(choice: choice) } label: {
                    Text(choice).frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(22)
        .frame(maxWidth: 440)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.18)))
    }

    private var ending: some View {
        VStack(spacing: 22) {
            Image(systemName: "moon.stars.fill").font(.system(size: 46)).foregroundStyle(.cyan)
            Text("第一章完成").font(.system(size: 34, weight: .bold, design: .serif))
            Text(game.endingSummary)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.72))
                .frame(maxWidth: 520)
            Text("你发现的线索：\(game.discoveredClues.count) / 3")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
            Button { game.returnToMenu() } label: {
                Label("返回菜单", systemImage: "arrow.uturn.backward")
                    .frame(width: 170)
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(34)
    }

    private var guide: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("这不是一场寻找唯一正确答案的考试。拖动场景环视，点按方向按钮锁定视线，再选择一个行动。")
                    Text("第一章的线索不会自动出现：观察左侧、右侧、桌面，或先照顾好自己的呼吸，都会改变你能听见和理解的内容。")
                    Text("后台状态会影响感官反馈，但不会显示成数字。出现内心独白时，点按文字即可收起。")
                }
                .font(.body)
                .lineSpacing(5)
                .padding()
            }
            .navigationTitle("游戏说明")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private var inspector: some View {
        NavigationStack {
            List {
                Section("班级现场") {
                    ForEach(game.classmates) { classmate in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(classmate.name).font(.headline)
                                Text(classmate.state).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(classmate.stress > 65 ? "呼吸很紧" : "还能维持")
                                .font(.caption).foregroundStyle(classmate.stress > 65 ? .orange : .secondary)
                        }
                    }
                }
                Section("夜间回放") {
                    if game.snapshots.isEmpty { Text("行动会在这里留下表面与内心的双层记录").foregroundStyle(.secondary) }
                    ForEach(game.snapshots.reversed()) { snapshot in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("第\(snapshot.turn)回合 · \(snapshot.action)").font(.subheadline.weight(.semibold))
                            Text(snapshot.surface).font(.caption).foregroundStyle(.secondary)
                            Text(snapshot.innerTruth).font(.caption).italic().foregroundStyle(.cyan.opacity(0.75))
                        }
                    }
                }
                Section("制度参数") {
                    VStack(alignment: .leading) {
                        Text("晚自习时长：\(game.studyHours, specifier: "%.1f") 小时")
                        Slider(value: $game.studyHours, in: 1...4, step: 0.5)
                    }
                    VStack(alignment: .leading) {
                        Text("排名压力：\(Int(game.rankingPressure))")
                        Slider(value: $game.rankingPressure, in: 0...100)
                    }
                    VStack(alignment: .leading) {
                        Text("巡视频率：\(Int(game.patrolFrequency))")
                        Slider(value: $game.patrolFrequency, in: 0...100)
                    }
                }
            }
            .navigationTitle("现场与回放")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .padding(.vertical, 12)
            .foregroundStyle(.black)
            .background(Color.cyan.opacity(configuration.isPressed ? 0.65 : 0.95), in: RoundedRectangle(cornerRadius: 10))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .padding(.vertical, 12)
            .foregroundStyle(.white)
            .background(.white.opacity(configuration.isPressed ? 0.16 : 0.1), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.18)))
    }
}

private struct ControlButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isSelected ? .black : .white.opacity(0.9))
            .background((isSelected ? Color.cyan : Color.black.opacity(0.58)).opacity(configuration.isPressed ? 0.66 : 1), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(.white.opacity(isSelected ? 0 : 0.15)))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}
