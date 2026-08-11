import SwiftUI

@main
struct LateStudySimulatorIOSApp: App {
    @StateObject private var game = GameManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(game)
                .preferredColorScheme(.dark)
                .onAppear {
                    let process = ProcessInfo.processInfo
                    if process.arguments.contains("--uitest-teacher"), game.gameState == .menu {
                        game.startGame(as: .homeroomTeacher)
                    } else if process.arguments.contains("--uitest-free-roam"), game.gameState == .menu {
                        game.startGame()
                        game.execute(.leaveSeat)
                        if case .event(let event) = game.gameState,
                           let choice = event.choices.first(where: { $0.id == "go_washroom" }) {
                            game.resolveEventChoice(choice)
                        }
                    } else if process.arguments.contains("--uitest-prologue"), game.gameState == .menu {
                        game.startExperience(forcePrologue: true)
                    } else if (process.arguments.contains("--uitest-start-game") || process.environment["LATE_STUDY_START_GAME"] == "1"), game.gameState == .menu {
                        game.startGame()
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    game.setApplicationActive(phase == .active)
                }
        }
    }
}
