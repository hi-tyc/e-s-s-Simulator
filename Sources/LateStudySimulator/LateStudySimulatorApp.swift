import SwiftUI

@main
struct LateStudySimulatorApp: App {
    @StateObject private var game = GameManager()

    var body: some Scene {
        WindowGroup("晚自习模拟器 3D") {
            ContentView()
                .environmentObject(game)
                .frame(minWidth: 1100, minHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
