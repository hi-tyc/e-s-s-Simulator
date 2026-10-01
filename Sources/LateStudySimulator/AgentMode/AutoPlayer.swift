import Foundation

/// 内置的自动游玩策略。
///
/// 用途：
/// 1. 让 AI 在没有外部脚本时也能完整跑完一局（自动演示）；
/// 2. 作为基线策略，用来对比人类 / LLM 的表现；
/// 3. 批量跑不同策略以观察数值平衡（配合 `--auto <strategy>`）。
///
/// 这些策略刻意保持"朴素"，代表一个普通玩家的直觉选择而非最优解。
/// 若某种朴素策略能轻松通关，说明难度偏低。
@MainActor
enum AutoPlayer {

    enum Strategy: String, CaseIterable {
        /// 推进主线，其余时间写作业。最接近真实玩家的方式。
        case mainQuest = "main"
        /// 只写作业。
        case studyOnly = "study"
        /// 优先自我照顾。
        case selfCare = "care"
        /// 优先社交。
        case social = "social"
        /// 随机选择，用于探测异常路径。
        case random = "random"

        var displayName: String {
            switch self {
            case .mainQuest: return "主线优先"
            case .studyOnly: return "全力学习"
            case .selfCare: return "自我照顾"
            case .social: return "社交路线"
            case .random: return "随机游走"
            }
        }
    }

    /// 每个策略维护自己的命令轮转索引（避免每次调用都从头开始）。
    private static var cursor: [Strategy: Int] = [:]

    private static func rotate(_ strategy: Strategy, over commands: [String]) -> String {
        let index = (cursor[strategy] ?? 0) % commands.count
        cursor[strategy] = index + 1
        return commands[index]
    }

    /// 驱动一局游戏直到结束或达到动作上限。
    static func play(
        session: AgentGameSession,
        strategy: Strategy,
        maxActions: Int = 80,
        verbose: Bool = true
    ) -> String {
        var log: [String] = []
        var actions = 0
        cursor[strategy] = 0

        while actions < maxActions && session.isFinished == false {
            // 章节转场与纸条：自动推进
            if session.needsTransitionContinue {
                _ = session.execute(command: "继续")
                if verbose { log.append("  [转场] 继续") }
                actions += 1
                continue
            }
            if session.needsPaperRead {
                _ = session.execute(command: "阅读")
                if verbose { log.append("  [纸条] 阅读") }
                actions += 1
                continue
            }

            // 事件优先处理
            if let event = session.pendingEvent {
                let choice = chooseEventChoice(event, strategy: strategy)
                _ = session.execute(command: choice.id)
                if verbose { log.append("  [事件] \(event.title) → \(choice.title)") }
                actions += 1
                continue
            }

            let command = nextCommand(session: session, strategy: strategy)
            let before = session.debugPlayerNeeds()
            _ = session.execute(command: command)
            if verbose {
                let after = session.debugPlayerNeeds()
                log.append(String(
                    format: "  A%-3d %-10@ 能量%5.0f→%-5.0f 渴%3.0f 饿%3.0f",
                    actions + 1, command as NSString,
                    before.energy, after.energy,
                    after.thirst, after.hunger
                ))
            }
            actions += 1
        }

        let header = """
        ══════════════════════════════════════════════════════════════════════════════
        自动游玩 · 策略：\(strategy.displayName) · 共 \(actions) 个动作
        ══════════════════════════════════════════════════════════════════════════════
        """
        return ([header] + log).joined(separator: "\n")
    }

    private static func nextCommand(session: AgentGameSession, strategy: Strategy) -> String {
        let available = Set(session.availableActions())

        // 主线推进优先
        if let quest = mainQuestCommand(session: session, available: available, strategy: strategy) {
            return quest
        }

        switch strategy {
        case .mainQuest:
            // 等待信号成熟时，像普通玩家一样过晚自习：能量见底先恢复，
            // 否则写作业推进进度。
            if session.debugPlayerNeeds().energy < 40 { return "深呼吸" }
            return rotate(.mainQuest, over: ["写作业", "写作业", "看窗外"])
        case .studyOnly:
            return "写作业"
        case .selfCare:
            return selfCareCommand(session: session, available: available)
        case .social:
            return rotate(.social, over: ["同桌", "传纸条", "同桌", "写作业"])
        case .random:
            return session.availableActions().randomElement() ?? "写作业"
        }
    }

    /// 依据主线步骤给出推进命令。返回 nil 表示当前无需推进主线。
    private static func mainQuestCommand(
        session: AgentGameSession,
        available: Set<String>,
        strategy: Strategy
    ) -> String? {
        // 时机未到：线索催不来。这一回合应该真的去过晚自习，
        // 而不是把动作浪费在被拒绝的划线动作上——那既不像玩家，
        // 也会让 --auto-all 的数值对比失去意义。
        guard session.debugChapterWaitRemaining() == 0 else { return nil }

        switch session.debugStepDescription() {
        case "observeLinChe":
            return rotate(strategy, over: ["look left", "观察"])
        case "locateHiddenSound":
            return rotate(strategy, over: ["look right", "观察"])
        case "regulateSelf":
            return rotate(strategy, over: ["深呼吸", "喝水"])
        case "approachLinChe":
            return rotate(strategy, over: ["同桌", "传纸条"])
        case "inspectNote":
            return rotate(strategy, over: ["look desk", "观察"])
        case "followLinChe":
            return "举手"
        default:
            return nil
        }
    }

    private static func selfCareCommand(session: AgentGameSession, available: Set<String>) -> String {
        let needs = session.debugPlayerNeeds()
        if needs.bladder > 60, available.contains("举手") { return "举手" }
        if needs.thirst > 60, available.contains("喝水") { return "喝水" }
        if needs.hunger > 60, available.contains("吃零食") { return "吃零食" }
        if needs.energy < 45 { return "深呼吸" }
        return rotate(.selfCare, over: ["深呼吸", "看窗外", "写作业"])
    }

    /// 事件选择策略。
    private static func chooseEventChoice(_ event: ActiveEvent, strategy: Strategy) -> EventChoice {
        // 第一章章末决策：四种策略分别走向四种不同的处理方式，
        // 便于观察"同样的场景、不同选择"带来的差异。
        let chapterOnePreference: [Strategy: String] = [
            .mainQuest: "chapter1_teacher",
            .studyOnly: "chapter1_tomorrow",
            .selfCare: "chapter1_monitor",
            .social: "chapter1_wait",
            .random: ""
        ]
        if let wanted = chapterOnePreference[strategy],
           wanted.isEmpty == false,
           let choice = event.choices.first(where: { $0.id == wanted }) {
            return choice
        }

        let preferred: [String]
        switch strategy {
        case .social:
            preferred = ["comfort", "accept", "help", "share"]
        case .selfCare:
            preferred = ["admit", "support", "breathe", "calm"]
        case .studyOnly:
            preferred = ["push", "reject", "smile", "ignore"]
        case .mainQuest:
            preferred = []
        case .random:
            // 随机策略真的随机，用于探测异常路径。
            return event.choices.randomElement() ?? event.choices[0]
        }
        if let match = event.choices.first(where: { choice in
            preferred.contains { choice.id.contains($0) }
        }) {
            return match
        }
        return event.choices[0]
    }
}
