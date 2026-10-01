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

    /// 按显示宽度补空格。
    ///
    /// 原来这里用 `String(format: "%-4s", "回合")`：`%s` 需要 C 字符串指针，
    /// 传 Swift String 会打印出乱码（表头一直是"腮C 腮C …"）。
    /// 中文字符宽度按 2 计算，表头才能对齐。
    private func pad(_ text: String, _ width: Int) -> String {
        let displayWidth = text.reduce(0) { $0 + ($1.unicodeScalars.first!.value > 0x2000 ? 2 : 1) }
        return text + String(repeating: " ", count: max(0, width - displayWidth))
    }

    /// 策略 A：全部写作业。用于观察"能量归零后的僵尸回合"。
    @Test func strategyA_allStudy() {
        let game = makeGame()
        header("策略 A：全部写作业")
        print(pad("回合", 5) + pad("能量", 7) + pad("压力", 7) + pad("作业", 7) + pad("面具", 7))
        for turn in 1...18 {
            game.execute(.study)
            // 只在真的弹出事件时才推进事件流程。无条件调用会额外结算一个回合
            // （多给一次恢复、多推进一次身体需求），探针数据会因此失真——
            // 这正是"能量看起来永远掉不下去"的假象来源之一。
            if case .event = game.gameState { game.continueAfterEvent() }
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
            // 只在真的弹出事件时才推进事件流程。无条件调用会额外结算一个回合
            // （多给一次恢复、多推进一次身体需求），探针数据会因此失真——
            // 这正是"能量看起来永远掉不下去"的假象来源之一。
            if case .event = game.gameState { game.continueAfterEvent() }
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
        print(pad("回合", 5) + pad("能量", 7) + pad("压力", 7) + pad("暴露", 7) + pad("面具", 7) + pad("作业", 7))
        for turn in 1...18 {
            game.execute(turn % 2 == 1 ? .study : .breathe)
            // 只在真的弹出事件时才推进事件流程。无条件调用会额外结算一个回合
            // （多给一次恢复、多推进一次身体需求），探针数据会因此失真——
            // 这正是"能量看起来永远掉不下去"的假象来源之一。
            if case .event = game.gameState { game.continueAfterEvent() }
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
            // 只在真的弹出事件时才推进事件流程。无条件调用会额外结算一个回合
            // （多给一次恢复、多推进一次身体需求），探针数据会因此失真——
            // 这正是"能量看起来永远掉不下去"的假象来源之一。
            if case .event = game.gameState { game.continueAfterEvent() }
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

    /// 策略 E：主线最优路径。
    ///
    /// 这是交接文档 §9.1 的验收探针：主线玩家按剧本推进，等待信号成熟的回合
    /// 用写作业/自我照顾"正常过晚自习"。用来检查：
    /// - 暴露是否至少达到 60（原基线只有 45）；
    /// - 能量是否至少一次低于 35（原基线最低 65）；
    /// - 曲线是否呈现"紧张—释放"，而不是一条平坦的直线。
    @Test func strategyE_mainQuestPath() {
        let game = makeGame()
        header("策略 E：主线最优路径（等待期间写作业 / 自我照顾）")
        print(pad("回合", 5) + pad("步骤", 19) + pad("能量", 7) + pad("压力", 7)
              + pad("暴露", 7) + pad("面具", 7) + pad("作业", 7) + pad("等待", 6))

        var minEnergy = game.player.psychicEnergy
        var maxExposure = game.player.exposure
        var turns = 0

        for turn in 1...24 {
            turns = turn
            // 章节转场 / 纸条：自动推进
            if game.isChapterOneTransitionPresented { game.enterChapterTwo() }
            if game.isChapterOnePaperPresented { game.dismissChapterOnePaper() }

            // 事件优先处理（被看见 / 能量见底等）
            if case .event(let event) = game.gameState {
                game.resolveEventChoice(event.choices[0])
                recordProbeRow(game, turn: turn, step: "事件", waiting: game.chapterOneStepsUntilReady)
                continue
            }
            if case .ending = game.gameState { break }

            let action = mainQuestAction(game)
            game.execute(action)

            if case .event(let event) = game.gameState {
                game.resolveEventChoice(event.choices[0])
            } else if game.isChapterOneTransitionPresented {
                game.enterChapterTwo()
                if game.isChapterOnePaperPresented { game.dismissChapterOnePaper() }
                if case .event(let event) = game.gameState {
                    game.resolveEventChoice(event.choices[0])
                }
            }

            let p = game.player
            minEnergy = min(minEnergy, p.psychicEnergy)
            maxExposure = max(maxExposure, p.exposure)
            recordProbeRow(game, turn: turn, step: "\(game.chapterOneStep)", waiting: game.chapterOneStepsUntilReady)

            if case .ending = game.gameState { break }
        }

        let p = game.player
        minEnergy = min(minEnergy, p.psychicEnergy)
        maxExposure = max(maxExposure, p.exposure)
        print(String(format: "  → 共 %d 回合｜能量最低 %.0f｜暴露最高 %.0f｜警告 %d 次",
                     turns, minEnergy, maxExposure, p.teacherWarnings))
        print("  → 结局：\(game.calculateEnding().title)")
    }

    private func mainQuestAction(_ game: GameManager) -> PlayerAction {
        // 时机未到：把这一回合用来"过晚自习"，而不是硬催线索。
        if game.chapterOneStepsUntilReady > 0 {
            return game.player.psychicEnergy < 45 ? .breathe : .study
        }
        switch game.chapterOneStep {
        case .observeLinChe:
            game.setPose(.left)
            return .observe
        case .locateHiddenSound:
            game.setPose(.right)
            return .observe
        case .regulateSelf:
            return .breathe
        case .approachLinChe:
            return .talk
        case .inspectNote:
            game.setPose(.desk)
            return .observe
        case .followLinChe, .completed:
            return .leaveSeat
        }
    }

    private func recordProbeRow(_ game: GameManager, turn: Int, step: String, waiting: Int) {
        let p = game.player
        let row = pad("T\(turn)", 5) + pad(step, 19)
            + pad(String(format: "%.0f", p.psychicEnergy), 7)
            + pad(String(format: "%.0f", p.stress), 7)
            + pad(String(format: "%.0f", p.exposure), 7)
            + pad(String(format: "%.0f", p.maskCost), 7)
            + pad(String(format: "%.0f", p.homework), 7)
            + "\(waiting)"
        print(row)
    }
}
