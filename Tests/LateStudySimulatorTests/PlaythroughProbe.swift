import Testing
import Foundation
@testable import LateStudySimulator

/// 数值平衡探针。
///
/// 用途：以固定策略跑完一局，把关键属性逐回合打印出来，
/// 用来判断"玩起来是什么手感"。修改数值后重跑即可对比效果：
///
///     swift test --filter PlaythroughProbe
///
/// 建议的观察点：
/// - 能量是否在若干回合后永久归零（出现"僵尸回合"）
/// - 是否存在单一无脑最优策略
/// - 暴露是否在少数回合内从 0 跳到临界值
@MainActor
struct PlaythroughProbe {

    private func makeGame() -> GameManager {
        let defaults = UserDefaults(suiteName: "Probe.\(UUID().uuidString)")!
        let game = GameManager(store: defaults)
        game.startGame()
        game.dismissChapterOneGuide()
        game.dismissFeaturedMonologueForTesting()
        return game
    }

    private func header(_ title: String) {
        print("\n" + String(repeating: "=", count: 76))
        print(title)
        print(String(repeating: "=", count: 76))
    }

    /// 策略 A：全部写作业。用于观察"能量归零后的僵尸回合"。
    @Test func strategyA_allStudy() {
        let game = makeGame()
        header("策略 A：全部写作业")
        print(String(format: "%-4s %6s %6s %6s %6s", "回合", "能量", "压力", "作业", "面具"))
        for turn in 1...18 {
            game.execute(.study)
            game.continueAfterEvent()
            guard case .playing = game.gameState else {
                print("  → 第 \(turn) 回合游戏结束（状态：\(game.gameState)）")
                break
            }
            print(String(format: "T%-3d %6.0f %6.0f %6.0f %6.0f",
                         turn, game.player.psychicEnergy, game.player.stress,
                         game.player.homework, game.player.maskCost))
        }
        print("  → 结局：\(game.calculateEnding().title)")
    }

    /// 策略 B：全部看手机。用于观察"暴露跳变速度"。
    @Test func strategyB_phoneOnly() {
        let game = makeGame()
        header("策略 B：全部看手机")
        for turn in 1...18 {
            game.execute(.phone)
            game.continueAfterEvent()
            guard case .playing = game.gameState else {
                print("  → 第 \(turn) 回合游戏结束")
                break
            }
            let p = game.player
            print(String(format: "T%-3d 能量%5.0f 压力%5.0f 暴露%5.0f 面具%5.0f 警告%2d",
                         turn, p.psychicEnergy, p.stress, p.exposure, p.maskCost, p.teacherWarnings))
            if p.exposure > 70 { print("  → 暴露越过 70 阈值"); break }
        }
        print("  → 结局：\(game.calculateEnding().title)")
    }

    /// 策略 C：写作业 / 深呼吸交替。用于检查是否存在"无脑最优解"。
    @Test func strategyC_alternating() {
        let game = makeGame()
        header("策略 C：写作业 / 深呼吸交替")
        print(String(format: "%-4s %6s %6s %6s %6s %6s", "回合", "能量", "压力", "暴露", "面具", "作业"))
        for turn in 1...18 {
            game.execute(turn % 2 == 1 ? .study : .breathe)
            game.continueAfterEvent()
            guard case .playing = game.gameState else {
                print("  → 第 \(turn) 回合游戏结束")
                break
            }
            let p = game.player
            print(String(format: "T%-3d %6.0f %6.0f %6.0f %6.0f %6.0f",
                         turn, p.psychicEnergy, p.stress, p.exposure, p.maskCost, p.homework))
        }
        print("  → 结局：\(game.calculateEnding().title)")
    }

    /// 策略 D：学习 + 帮助同桌。用于检查"社交路线"是否可行。
    @Test func strategyD_socialRoute() {
        let game = makeGame()
        header("策略 D：写作业 / 和同桌交流交替")
        for turn in 1...18 {
            game.execute(turn % 2 == 1 ? .study : .talk)
            game.continueAfterEvent()
            guard case .playing = game.gameState else {
                print("  → 第 \(turn) 回合游戏结束")
                break
            }
            let p = game.player
            print(String(format: "T%-3d 能量%5.0f 压力%5.0f 暴露%5.0f 支持%5.0f 作业%5.0f 帮助%@",
                         turn, p.psychicEnergy, p.stress, p.exposure,
                         p.support, p.homework, p.helpedClassmate ? "是" : "否"))
        }
        print("  → 结局：\(game.calculateEnding().title)")
    }
}
