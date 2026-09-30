import SwiftUI

/// 程序入口。
///
/// 通过 `--agent` 参数进入无头 Agent 模式（供 AI / 脚本游玩），
/// 否则启动正常的 SwiftUI 图形界面。
///
/// 之所以不使用 `@main struct App`，是因为需要在 SwiftUI 初始化之前
/// 拦截命令行参数；`@main` 的 `App` 协议没有提供这样的插入点。
@main
enum EntryPoint {
    static func main() {
        if AgentModeCLI.runIfRequested(arguments: CommandLine.arguments) {
            return
        }
        LateStudySimulatorApp.main()
    }
}

struct LateStudySimulatorApp: App {
    @StateObject private var game = GameManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup("晚自习模拟器 3D") {
            ContentView()
                .environmentObject(game)
                .frame(minWidth: 1100, minHeight: 720)
                .onChange(of: scenePhase) { _, phase in
                    game.setApplicationActive(phase == .active)
                }
        }
        .windowStyle(.hiddenTitleBar)
    }
}
