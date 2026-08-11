import SceneKit
import SwiftUI

struct IOSOriginalGameView: View {
    @EnvironmentObject private var game: GameManager
    @State private var showInspector = false
    @State private var sideways = false
    @State private var sprinting = false

    var body: some View {
        ZStack {
            switch game.gameState {
            case .menu: menu
            case .playing: playSurface
            case .event(let event): playSurface.overlay(eventCard(event))
            case .ending(let ending): endingView(ending)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var menu: some View {
        ZStack {
            Color(red: 0.025, green: 0.04, blue: 0.065).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                Spacer()
                Text("晚自习模拟器").font(.system(size: 44, weight: .bold, design: .serif))
                Text("iOS 版 · 原版状态机移植").foregroundStyle(.cyan)
                Text("序章、学生线、教师线、事件选择、NPC 状态、回放和结局分析均由原 macOS 游戏核心驱动。")
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 540, alignment: .leading)
                HStack(spacing: 12) {
                    Button { game.startExperience() } label: { Label("进入序章", systemImage: "building.2.fill").frame(width: 160) }
                        .buttonStyle(IOSPrimaryButtonStyle())
                    Button { game.startGame() } label: { Label("直接开始第一章", systemImage: "book.fill").frame(width: 170) }
                        .buttonStyle(IOSSecondaryButtonStyle())
                }
                Text("触控拖动环视 · 底部按钮执行行动 · 手机后台会自动暂停")
                    .font(.caption).foregroundStyle(.white.opacity(0.4))
                Spacer()
            }
            .padding(42).frame(maxWidth: 760, alignment: .leading)
        }
    }

    private var playSurface: some View {
        ZStack {
            ClassroomSceneView(game: game).ignoresSafeArea()
            VStack(spacing: 10) {
                topBar
                Spacer()
                Text(game.message)
                    .font(.subheadline).foregroundStyle(.white.opacity(0.9))
                    .padding(13).frame(maxWidth: 680, alignment: .leading)
                    .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 12))
                actionBar
            }
            .padding(16)
            if game.freeRoam.isActive {
                freeRoamControls
            }
        }
    }

    private var topBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(game.isPrologueActive ? "序章 · 铃响之前" : game.activeChapter.rawValue).font(.headline)
                Text(game.isPrologueActive ? game.prologueCurrentBeat.currentGoal : game.chapterCurrentObjective)
                    .font(.caption).foregroundStyle(.cyan).lineLimit(2)
            }
            Spacer()
            Text(game.clockText).font(.system(.headline, design: .monospaced))
            Button { showInspector = true } label: { Image(systemName: "line.3.horizontal.decrease.circle").frame(width: 36, height: 36) }
                .buttonStyle(IOSControlButtonStyle(selected: false))
        }
        .padding(13).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .sheet(isPresented: $showInspector) { inspector }
    }

    private var actionBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 7) {
                ForEach(CameraPose.allCases, id: \.self) { pose in
                    Button { game.setPose(pose) } label: { Image(systemName: poseSymbol(pose)).frame(maxWidth: .infinity).frame(height: 34) }
                        .buttonStyle(IOSControlButtonStyle(selected: game.cameraPose == pose))
                }
            }
            HStack(spacing: 7) {
                ForEach(game.viewMode == .teacher ? TeacherAction.allCases.map(\.rawValue) : game.chapterOneAvailableActions.map(\.rawValue), id: \.self) { title in
                    Button {
                        if let action = PlayerAction(rawValue: title) { game.execute(action) }
                        else if let action = TeacherAction(rawValue: title) { game.executeTeacherAction(action) }
                    } label: { Text(title).font(.system(size: 11, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 40) }
                    .buttonStyle(IOSControlButtonStyle(selected: false))
                }
            }
        }
    }

    private var freeRoamControls: some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom) {
                IOSMovementPad { forward, strafe in
                    game.moveStudentFreeRoam(forward: forward, strafe: strafe, deltaTime: 1.0 / 24.0)
                }
                Spacer()
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Button { sideways.toggle(); game.setFreeRoamSideways(sideways) } label: { Label("侧身", systemImage: "figure.walk.motion").frame(width: 82, height: 36) }
                            .buttonStyle(IOSControlButtonStyle(selected: sideways))
                        Button { sprinting.toggle(); game.setFreeRoamSprinting(sprinting) } label: { Label("奔跑", systemImage: "figure.run").frame(width: 82, height: 36) }
                            .buttonStyle(IOSControlButtonStyle(selected: sprinting))
                    }
                    Button { interactAtCurrentPosition() } label: { Label("交互", systemImage: "hand.tap.fill").frame(width: 172, height: 42) }
                        .buttonStyle(IOSPrimaryButtonStyle())
                    Button { game.returnToSeatFromFreeRoam() } label: { Label("回到座位", systemImage: "chair.fill").frame(width: 172, height: 34) }
                        .buttonStyle(IOSSecondaryButtonStyle())
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 84)
        }
        .allowsHitTesting(true)
    }

    private func interactAtCurrentPosition() {
        if game.confirmPrologueSeat() { return }
        if game.interactWithNearbyDoor() { return }
        if game.isNearWaterDispenser { game.refillWaterCup(); return }
        if game.isNearRestroom { game.useRestroom(); return }
        if game.isNearPlayerLocker { game.togglePlayerLocker(); return }
        game.confirmPrologueInteraction()
    }

    private func eventCard(_ event: ActiveEvent) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(event.title).font(.title3.bold())
            Text(event.body).font(.subheadline).foregroundStyle(.white.opacity(0.72)).lineSpacing(4)
            ForEach(event.choices) { choice in
                Button { game.resolveEventChoice(choice) } label: {
                    VStack(alignment: .leading, spacing: 2) { Text(choice.title).bold(); Text(choice.detail).font(.caption).foregroundStyle(.white.opacity(0.6)) }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(IOSSecondaryButtonStyle())
            }
        }
        .padding(22).frame(maxWidth: 450).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func endingView(_ ending: Ending) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(ending.title).font(.system(size: 34, weight: .bold, design: .serif))
                Text(ending.body).foregroundStyle(.white.opacity(0.78)).lineSpacing(5)
                Text(ending.reflection).italic().foregroundStyle(.cyan.opacity(0.85))
                Text(ending.story.title).font(.title3.bold())
                Text(ending.story.body).foregroundStyle(.white.opacity(0.72))
                ForEach(ending.analysis) { metric in
                    HStack { Text(metric.title); Spacer(); Text(metric.value).foregroundStyle(.cyan) }
                }
                Button { game.returnToMenuForNewGame() } label: { Label("返回菜单", systemImage: "arrow.uturn.backward").frame(width: 160) }
                    .buttonStyle(IOSPrimaryButtonStyle())
            }
            .padding(34).frame(maxWidth: 700, alignment: .leading)
        }
    }

    private var inspector: some View {
        NavigationStack {
            List {
                Section("班级") {
                    ForEach(game.classmates) { classmate in
                        HStack { Text(classmate.name); Spacer(); Text(classmate.state.rawValue).foregroundStyle(.secondary) }
                    }
                }
                Section("回放") {
                    ForEach(game.replay) { snapshot in
                        VStack(alignment: .leading) { Text("第\(snapshot.turn)回合 · \(snapshot.actionLabel)").bold(); Text(snapshot.visibleScene).font(.caption).foregroundStyle(.secondary); Text(snapshot.innerTruth).font(.caption).italic().foregroundStyle(.cyan) }
                    }
                }
                Section("体验") {
                    Text(game.audioAssetStatus.summary)
                    Text(game.accessibilityPreferences.reduceMotion ? "已减少动态效果" : "动态效果开启")
                }
            }.navigationTitle("现场与回放").navigationBarTitleDisplayMode(.inline)
        }.presentationDetents([.medium, .large])
    }

    private func poseSymbol(_ pose: CameraPose) -> String {
        switch pose { case .forward: return "arrow.up"; case .desk: return "arrow.down"; case .board: return "rectangle.fill"; case .left: return "arrow.left"; case .right: return "arrow.right"; case .rear: return "arrow.uturn.backward" }
    }
}

private struct IOSPrimaryButtonStyle: ButtonStyle { func makeBody(configuration: Configuration) -> some View { configuration.label.font(.subheadline.bold()).padding(.vertical, 11).foregroundStyle(.black).background(Color.cyan.opacity(configuration.isPressed ? 0.65 : 0.95), in: RoundedRectangle(cornerRadius: 10)) } }
private struct IOSSecondaryButtonStyle: ButtonStyle { func makeBody(configuration: Configuration) -> some View { configuration.label.padding(.vertical, 10).foregroundStyle(.white).background(.white.opacity(configuration.isPressed ? 0.18 : 0.1), in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.15))) } }
private struct IOSControlButtonStyle: ButtonStyle { let selected: Bool; func makeBody(configuration: Configuration) -> some View { configuration.label.foregroundStyle(selected ? .black : .white.opacity(0.9)).background((selected ? Color.cyan : Color.black.opacity(0.58)).opacity(configuration.isPressed ? 0.65 : 1), in: RoundedRectangle(cornerRadius: 8)) } }

private struct IOSMovementPad: View {
    let onMove: (Double, Double) -> Void
    @State private var offset = CGSize.zero

    var body: some View {
        ZStack {
            Circle().fill(.black.opacity(0.48)).overlay(Circle().stroke(.white.opacity(0.2)))
            Circle().fill(.cyan.opacity(0.82)).frame(width: 44, height: 44).offset(offset)
        }
        .frame(width: 126, height: 126)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
            let dx = value.location.x - 63
            let dy = value.location.y - 63
            let length = max(1, hypot(dx, dy))
            let scale = min(44, length) / length
            offset = CGSize(width: dx * scale, height: dy * scale)
            onMove(Double(-dy / 63), Double(dx / 63))
        }.onEnded { _ in offset = .zero })
        .accessibilityLabel("移动摇杆")
    }
}
