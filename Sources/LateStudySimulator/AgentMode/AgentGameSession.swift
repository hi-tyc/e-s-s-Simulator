import Foundation

/// Agent 模式：让 AI 或自动化脚本像真人一样游玩。
///
/// 设计原则：
/// 1. **信息分层**：区分"玩家可见"与"内部隐藏"信息，AI 默认只看可见层，
///    需要时可用 `--omniscient` 打开全知视角以便调试。
/// 2. **完整动作集**：暴露 `PlayerAction` / 教师动作 / 场景操作等全部 API。
/// 3. **无头运行**：不依赖 SwiftUI 与 SceneKit 渲染，纯逻辑驱动。
/// 4. **可回放**：记录每个动作与结果，便于事后分析。
///
/// 使用方式见 `AgentModeCLI`。
@MainActor
final class AgentGameSession {

    private let game: GameManager
    private var history: [ActionRecord] = []
    private(set) var turnCount = 0

    /// 一次动作的记录，用于回放与统计。
    struct ActionRecord {
        let turn: Int
        let command: String
        let resultSummary: String
        let stateAfter: StateSnapshot
    }

    /// 状态快照，便于对比动作前后的变化。
    struct StateSnapshot {
        var psychicEnergy: Double
        var stress: Double
        var exposure: Double
        var maskCost: Double
        var support: Double
        var homework: Double
        var visualAttention: Double
        var thirst: Double
        var hunger: Double
        var bladder: Double
        var position: String
        var period: String
    }

    init(omniscient: Bool = false, seedLess: Bool = true) {
        let defaults = UserDefaults(suiteName: "AgentMode.\(UUID().uuidString)")!
        game = GameManager(store: defaults)
        self.omniscient = omniscient
        game.startGame()
        game.dismissChapterOneGuide()
        game.dismissFeaturedMonologueForTesting()
    }

    let omniscient: Bool

    /// 是否使用带光照的真彩渲染（默认开启）。
    var useColorRendering = true
    /// 是否输出 ANSI 颜色码。纯文本环境可关闭。
    var supportsANSI = true

    // MARK: - 状态查询

    var isFinished: Bool {
        if case .ending = game.gameState { return true }
        if case .menu = game.gameState { return true }
        return false
    }

    var requiresEventChoice: Bool {
        if case .event = game.gameState { return true }
        return false
    }

    /// 当前待处理的事件（若有）。
    var pendingEvent: ActiveEvent? {
        if case .event(let event) = game.gameState { return event }
        return nil
    }

    /// 是否处于章节转场，需要输入「继续」。
    var needsTransitionContinue: Bool {
        game.isChapterOneTransitionPresented
    }

    /// 是否正在展示纸条，需要输入「阅读」。
    var needsPaperRead: Bool {
        game.isChapterOnePaperPresented
    }

    // MARK: - 渲染

    /// 默认视图：AI 能看到的一切（不含隐藏数值）。
    func renderDefaultView() -> String {
        var out: [String] = []
        out.append(renderHeader())
        // 默认使用带光照的真彩渲染；无颜色环境可回退到线框渲染。
        if useColorRendering {
            let context = SceneRGBRenderer.context(game: game)
            out.append(SceneRGBRenderer.render(context: context, colored: supportsANSI))
        } else {
            out.append(SceneASCIIRenderer.render(game: game))
        }
        out.append(renderLegend())
        out.append(renderSubjectiveState())
        if omniscient { out.append(renderOmniscientState()) }
        out.append(renderAvailableActions())
        if let event = pendingEvent { out.append(renderEvent(event)) }
        return out.joined(separator: "\n")
    }

    private func renderHeader() -> String {
        let bar = String(repeating: "─", count: 78)
        var lines = [bar]
        lines.append("  晚自习模拟器 · Agent 模式")
        lines.append("  回合 \(game.currentTurn)/\(game.maxTurns)   |   阶段 \(game.currentPeriod.displayName)   |   时钟 \(game.clockText)")
        lines.append("  视角 \(game.cameraPose.rawValue)   |   \(game.player.posture == .seated ? "坐着" : "站着")   |   \(game.freeRoam.isActive ? "自由活动中" : "在座")")
        lines.append(bar)
        return lines.joined(separator: "\n")
    }

    private func renderLegend() -> String {
        """
        ┌ 图例 ─────────────────────────────────────────────────────────────┐
        │ ▬黑板  ▰讲台  ▯门  ◷钟  ▢课桌  ☖老师                             │
        │ ☺写题 ◉焦虑 ▤手机 ☁困倦 ⊙看你 ♥关心 ◍崩溃 ▥掩护                  │
        └───────────────────────────────────────────────────────────────────┘
        """
    }

    /// 玩家"能感觉到"的主观状态（不显示精确数字，模拟真人感知）。
    private func renderSubjectiveState() -> String {
        let p = game.player
        var lines: [String] = []
        lines.append("【你的感受】")

        lines.append("  精力：\(describe(p.psychicEnergy, thresholds: (80, 55, 30)))")
        lines.append("  压力：\(describeInverted(p.stress, thresholds: (30, 55, 75)))")
        lines.append("  被注意的程度：\(describeInverted(p.exposure, thresholds: (25, 50, 75)))")
        // 危险前兆必须和 GUI 一样可感知：P1 反馈层存在的意义就是
        // "在被抓住之前知道自己在冒险"，agent 模式看不到这一层就没法验证它。
        lines.append("  风险前兆：\(game.dangerSignalLevel.title) —— \(game.dangerSignalText)")
        lines.append("  维持形象的疲惫：\(describeInverted(p.maskCost, thresholds: (30, 55, 75)))")
        lines.append("  身边人的支持：\(describe(p.support, thresholds: (30, 55, 75)))")
        lines.append("  注意力：\(describe(p.visualAttention, thresholds: (75, 45, 20)))")

        // 身体信号（只在明显时才提示）
        if p.thirst > 55 { lines.append("  你有点渴。") }
        if p.hunger > 55 { lines.append("  你有点饿。") }
        if p.bladder > 55 { lines.append("  你想去洗手间。") }

        lines.append("  作业进度：\(Int(p.homework))%")

        let near = game.teacher.isNearPlayer ? "老师就在附近。" : "老师在教室另一侧。"
        lines.append("  \(near)")

        // 环境信息
        if game.frontDoorOpen { lines.append("  前门开着。") }
        if game.rearDoorOpen { lines.append("  后门开着。") }

        // 独白与消息
        if let mono = game.featuredMonologue {
            lines.append("")
            lines.append("  「\(mono.text)」")
        }
        if let clue = game.chapterClues.last {
            lines.append("  最近线索：\(clue.title)")
        }
        lines.append("")
        lines.append("  \(game.message)")
        return lines.joined(separator: "\n")
    }

    /// 全知视角：所有内部数值与隐藏状态。
    private func renderOmniscientState() -> String {
        let p = game.player
        let t = game.teacher
        var lines: [String] = []
        lines.append("")
        lines.append("【全知视角 · 仅调试可见】")
        lines.append(String(format: "  能量%.0f 压力%.0f 暴露%.0f 面具%.0f 支持%.0f 注意%.0f 聚焦%.2f",
                            p.psychicEnergy, p.stress, p.exposure, p.maskCost,
                            p.support, p.visualAttention, p.focusQuality))
        lines.append(String(format: "  渴%.0f 饿%.0f 如厕%.0f 水杯%.0f | 崩溃风险%.0f 最高需求%.0f",
                            p.thirst, p.hunger, p.bladder, p.waterCup,
                            p.breakdownRisk, p.highestBodyNeed))
        lines.append(String(format: "  教师: 位置%d KPI%.0f 疲劳%.0f 同理心%.0f 信任%.0f 靠近%@",
                            t.positionIndex, t.kpiPressure, t.fatigue, t.empathy,
                            t.studentTrust, t.isNearPlayer ? "是" : "否"))
        lines.append(String(format: "  警告%d 关心%d | 帮助过同桌%@ 面具负荷%.0f",
                            p.teacherWarnings, p.teacherCareMoments,
                            p.helpedClassmate ? "是" : "否", p.maskCost))
        lines.append("  同学状态：" + game.classmates.map {
            "\($0.name)(压\(Int($0.stress)) 关\(Int($0.relationship)) \($0.state.rawValue))"
        }.joined(separator: " "))
        lines.append("  章节步骤：\(game.chapterOneStep)")
        lines.append("  已触发事件：崩溃\(game.hasTriggeredPlayerBreakdown ? "✓" : "✗") 孤独\(game.hasTriggeredLoneliness ? "✓" : "✗") 支持\(game.hasTriggeredSupportNetworkProtection ? "✓" : "✗")")
        return lines.joined(separator: "\n")
    }

    private func describe(_ value: Double, thresholds: (Double, Double, Double)) -> String {
        if value >= thresholds.0 { return "充足（\(Int(value))）" }
        if value >= thresholds.1 { return "尚可（\(Int(value))）" }
        if value >= thresholds.2 { return "偏低（\(Int(value))）" }
        return "很低（\(Int(value))）"
    }

    private func describeInverted(_ value: Double, thresholds: (Double, Double, Double)) -> String {
        if value < thresholds.0 { return "低（\(Int(value))）" }
        if value < thresholds.1 { return "中等（\(Int(value))）" }
        if value < thresholds.2 { return "偏高（\(Int(value))）" }
        return "很高（\(Int(value))）"
    }

    /// 当前可执行的动作（尊重主线限制与可用性）。
    private func renderAvailableActions() -> String {
        var lines: [String] = []
        lines.append("")
        lines.append("【可用动作】")
        let actions = availableActions()
        lines.append("  " + actions.joined(separator: "  "))
        lines.append("")
        lines.append("【场景操作】  look <方向> | move <w/a/s/d> | wait | restroom | water | refill | locker | door <front/rear> <open/close>")
        lines.append("【系统命令】  state | history | omniscient | help | quit")
        return lines.joined(separator: "\n")
    }

    func availableActions() -> [String] {
        if game.chapterOneStep != .completed && game.activeChapter == .silentClassroom {
            return game.chapterOneAvailableActions.map(\.rawValue)
        }
        return PlayerAction.allCases.map(\.rawValue)
    }

    private func renderEvent(_ event: ActiveEvent) -> String {
        var lines: [String] = []
        lines.append("")
        lines.append(String(repeating: "═", count: 78))
        lines.append("  ⚠ 事件：\(event.title)")
        lines.append(String(repeating: "═", count: 78))
        lines.append("  \(event.body)")
        lines.append("")
        for (index, choice) in event.choices.enumerated() {
            lines.append("  [\(index + 1)] \(choice.title) — \(choice.detail)")
        }
        lines.append("")
        lines.append("  → 输入编号或 choice id 进行选择。")
        return lines.joined(separator: "\n")
    }

    // MARK: - 执行命令

    enum CommandResult {
        case ok(String)
        case error(String)
        case finished(String)
    }

    func execute(command raw: String) -> CommandResult {
        let command = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard command.isEmpty == false else { return .error("空命令") }

        // 章节转场：必须先"继续"才能进入下一步
        if game.isChapterOneTransitionPresented {
            if command == "继续" || command.lowercased() == "continue" {
                game.enterChapterTwo()
                return .ok(renderDefaultView())
            }
            return .error("当前处于章节转场。输入「继续」进入下一步。")
        }

        // 纸条：必须先"阅读/关闭"才能进入最终决策
        if game.isChapterOnePaperPresented {
            if command == "阅读" || command == "continue" || command == "继续" {
                game.dismissChapterOnePaper()
                if let event = pendingEvent { return .ok(renderEvent(event)) }
                if isFinished { return .finished(renderEndingIfAny()) }
                return .ok(renderDefaultView())
            }
            return .error("当前正在阅读纸条。输入「阅读」继续。")
        }

        // 事件期间只接受选择
        if let event = pendingEvent {
            return handleEventChoice(command, event: event)
        }

        if isFinished {
            return handleFinishedCommand(command)
        }

        let parts = command.split(separator: " ", maxSplits: 1).map(String.init)
        let verb = parts[0].lowercased()
        let argument = parts.count > 1 ? parts[1] : ""

        switch verb {
        case "help":
            return .ok(helpText())
        case "state":
            return .ok(renderDefaultView())
        case "omniscient":
            return .ok(renderOmniscientState())
        case "frame":
            return .ok(frameJSON())
        case "noColor":
            supportsANSI = false
            return .ok("已关闭 ANSI 颜色（纯字符密度）。")
        case "color":
            supportsANSI = true
            return .ok("已开启 ANSI 真彩。")
        case "history":
            return .ok(renderHistory())
        case "quit":
            return .ok("quit requested")
        case "look":
            return handleLook(argument)
        case "move":
            return handleMove(argument)
        case "wait":
            return handleWait()
        case "restroom":
            return handleSimple { $0.useRestroom() }
        case "water":
            return handlePlayerAction(PlayerAction.drink.rawValue)
        case "refill":
            return handleSimple { $0.refillWaterCup() }
        case "locker":
            return handleSimple { $0.togglePlayerLocker() }
        case "door":
            return handleDoor(argument)
        default:
            return handlePlayerAction(command)
        }
    }

    private func handlePlayerAction(_ command: String) -> CommandResult {
        guard let action = PlayerAction.allCases.first(where: { $0.rawValue == command || String(describing: $0) == command }) else {
            return .error("未知动作：\(command)。输入 help 查看可用命令。")
        }
        let before = snapshot()
        game.execute(action)
        turnCount += 1
        let after = snapshot()
        record(command: command, before: before, after: after)

        if let event = pendingEvent {
            return .ok("执行：\(action.rawValue)\n\n" + renderEvent(event))
        }
        if isFinished { return .finished(renderEndingIfAny()) }
        return .ok("执行：\(action.rawValue)\n\n" + renderDefaultView())
    }

    private func handleLook(_ argument: String) -> CommandResult {
        let map: [String: CameraPose] = [
            "forward": .forward, "front": .forward, "前": .forward,
            "desk": .desk, "低头": .desk, "下": .desk,
            "board": .board, "抬头": .board, "上": .board,
            "left": .left, "左": .left,
            "right": .right, "右": .right,
            "rear": .rear, "back": .rear, "后": .rear
        ]
        guard let pose = map[argument.lowercased()] else {
            return .error("未知方向：\(argument)。可用：forward/desk/board/left/right/rear")
        }
        game.setPose(pose)
        return .ok("看向\(pose.rawValue)。\n\n" + renderDefaultView())
    }

    private func handleMove(_ argument: String) -> CommandResult {
        guard game.freeRoam.isActive else {
            return .error("当前不在自由活动中，无法移动。")
        }
        let dir = argument.lowercased()
        let forward = dir == "w" ? 1.0 : (dir == "s" ? -1.0 : 0)
        let strafe = dir == "d" ? 1.0 : (dir == "a" ? -1.0 : 0)
        guard forward != 0 || strafe != 0 else { return .error("未知方向：\(argument)") }
        game.moveStudentFreeRoam(forward: forward, strafe: strafe, deltaTime: 1.0)
        return .ok("移动 \(dir)。\n\n" + renderDefaultView())
    }

    private func handleWait() -> CommandResult {
        let before = snapshot()
        game.continueAfterEvent()
        turnCount += 1
        record(command: "wait", before: before, after: snapshot())
        if let event = pendingEvent { return .ok(renderEvent(event)) }
        if isFinished { return .finished(renderEndingIfAny()) }
        return .ok(renderDefaultView())
    }

    private func handleSimple(_ body: (GameManager) -> Void) -> CommandResult {
        body(game)
        if isFinished { return .finished(renderEndingIfAny()) }
        return .ok(renderDefaultView())
    }

    private func handleDoor(_ argument: String) -> CommandResult {
        let parts = argument.split(separator: " ").map(String.init)
        guard parts.count == 2 else { return .error("用法：door <front|rear> <open|close>") }
        let isFront = parts[0] == "front"
        let shouldOpen = parts[1] == "open"
        if isFront { game.frontDoorOpen = shouldOpen } else { game.rearDoorOpen = shouldOpen }
        return .ok(renderDefaultView())
    }

    private func handleEventChoice(_ command: String, event: ActiveEvent) -> CommandResult {
        // 支持编号或 choice id
        var choice: EventChoice?
        if let index = Int(command), index >= 1, index <= event.choices.count {
            choice = event.choices[index - 1]
        } else {
            choice = event.choices.first { $0.id == command }
        }
        guard let resolved = choice else {
            return .error("无效选择：\(command)。输入 1-\(event.choices.count) 或 choice id。")
        }
        let before = snapshot()
        game.resolveEventChoice(resolved)
        record(command: "choice:\(resolved.id)", before: before, after: snapshot())
        if isFinished { return .finished(renderEndingIfAny()) }
        return .ok("选择：\(resolved.title)\n\n" + renderDefaultView())
    }

    private func handleFinishedCommand(_ command: String) -> CommandResult {
        switch command.lowercased() {
        case "history": return .ok(renderHistory())
        case "state": return .ok(renderEndingIfAny())
        case "help": return .ok(helpText())
        default: return .finished(renderEndingIfAny())
        }
    }

    private func renderEndingIfAny() -> String {
        if case .ending(let ending) = game.gameState {
            var lines: [String] = []
            lines.append(String(repeating: "═", count: 78))
            lines.append("  结局：\(ending.title)")
            lines.append(String(repeating: "═", count: 78))
            lines.append(ending.body)
            lines.append("")
            lines.append("  反思：\(ending.reflection)")
            lines.append("")
            lines.append("【三方视角】")
            for r in ending.empathyReflections {
                lines.append("  \(r.role)：\(r.text)")
            }
            lines.append("")
            lines.append("【数据】")
            for m in ending.analysis {
                lines.append("  \(m.title)：\(m.value)  — \(m.note)")
            }
            lines.append("")
            lines.append(String(repeating: "═", count: 78))
            return lines.joined(separator: "\n")
        }
        return "游戏结束。"
    }

    private func snapshot() -> StateSnapshot {
        let p = game.player
        let seat = game.selectedChapterSeat ?? GameManager.defaultPlayerSeat
        return StateSnapshot(
            psychicEnergy: p.psychicEnergy, stress: p.stress, exposure: p.exposure,
            maskCost: p.maskCost, support: p.support, homework: p.homework,
            visualAttention: p.visualAttention, thirst: p.thirst, hunger: p.hunger,
            bladder: p.bladder,
            position: game.freeRoam.isActive ? "自由活动" : "座位(\(seat.row),\(seat.column))",
            period: game.currentPeriod.displayName
        )
    }

    private func record(command: String, before: StateSnapshot, after: StateSnapshot) {
        let delta = String(format: "能量%+.0f 压力%+.0f 暴露%+.0f 面具%+.0f 作业%+.0f",
                           after.psychicEnergy - before.psychicEnergy,
                           after.stress - before.stress,
                           after.exposure - before.exposure,
                           after.maskCost - before.maskCost,
                           after.homework - before.homework)
        history.append(ActionRecord(turn: game.currentTurn, command: command, resultSummary: delta, stateAfter: after))
    }

    private func renderHistory() -> String {
        var lines = ["【动作历史】"]
        for record in history {
            lines.append(String(format: "  T%-3d %-14@ %@", record.turn, record.command as NSString, record.resultSummary))
        }
        return lines.joined(separator: "\n")
    }

    /// 结局单行摘要（供批量对比）。
    func agentEndingSummary() -> String {
        if case .ending(let ending) = game.gameState {
            let p = game.player
            return String(
                format: "  结局：%@ | 回合%d | 能量%.0f 压力%.0f 暴露%.0f 面具%.0f 作业%.0f",
                ending.title as NSString, game.currentTurn,
                p.psychicEnergy, p.stress, p.exposure, p.maskCost, p.homework
            )
        }
        return "  未结束 | 回合\(game.currentTurn)"
    }

    /// 当前主线步骤的字符串描述（供自动玩家判断）。
    func debugStepDescription() -> String {
        String(describing: game.chapterOneStep)
    }

    /// 主线步骤还要等几个回合才能推进（0 表示现在就可以）。
    ///
    /// 自动玩家用它判断"这一回合该不该催线索"：时机未到时应该去过晚自习
    /// （写作业 / 自我照顾），而不是反复点同一个动作把回合浪费掉。
    func debugChapterWaitRemaining() -> Int {
        game.chapterOneStepsUntilReady
    }

    /// 玩家身体需求（供自动玩家决策）。
    func debugPlayerNeeds() -> (energy: Double, thirst: Double, hunger: Double, bladder: Double) {
        let p = game.player
        return (p.psychicEnergy, p.thirst, p.hunger, p.bladder)
    }

    /// 导出当前画面的**逐像素 RGB 数据**，供 AI 精确理解场景。
    ///
    /// 每格包含：字符、十六进制颜色、亮度、命中的物体名、距离。
    /// 采样分辨率可调，默认降到 24x10 以控制输出体积。
    func frameJSON(cols: Int = 24, rows: Int = 10) -> String {
        let context = SceneRGBRenderer.context(game: game)
        let grid = SceneRGBRenderer.sample(context: context, width: cols, height: rows)

        let rowsJSON: [[[String: Any]]] = grid.map { row in
            row.map { pixel in
                var cell: [String: Any] = [
                    "ch": String(pixel.glyph),
                    "hex": pixel.color.hex,
                    "lum": (pixel.luminance * 100).rounded() / 100
                ]
                if let name = pixel.entityName {
                    cell["obj"] = name
                    cell["dist"] = (pixel.distance * 10).rounded() / 10
                }
                return cell
            }
        }

        let payload: [String: Any] = [
            "cols": cols,
            "rows": rows,
            "camera": [
                "pose": game.cameraPose.rawValue,
                "posture": game.player.posture == .seated ? "seated" : "standing"
            ],
            "lighting": [
                "period": game.currentPeriod.displayName,
                "ambientIntensity": (context.ambientIntensity * 100).rounded() / 100,
                "saturation": (context.saturation * 100).rounded() / 100,
                "vignette": (context.vignette * 100).rounded() / 100,
                "pointLights": context.pointLights.count
            ],
            "grid": rowsJSON
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    /// 导出机器可读的状态（供 AI 程序化消费）。
    func stateJSON() -> String {
        let p = game.player
        var dict: [String: Any] = [
            "turn": game.currentTurn,
            "maxTurns": game.maxTurns,
            "period": game.currentPeriod.displayName,
            "clock": game.clockText,
            "pose": game.cameraPose.rawValue,
            "posture": game.player.posture == .seated ? "seated" : "standing",
            "freeRoam": game.freeRoam.isActive,
            "teacherNear": game.teacher.isNearPlayer,
            "state": describeGameState(),
            "player": [
                "energy": p.psychicEnergy,
                "stress": p.stress,
                "exposure": p.exposure,
                "maskCost": p.maskCost,
                "support": p.support,
                "homework": p.homework,
                "attention": p.visualAttention,
                "thirst": p.thirst,
                "hunger": p.hunger,
                "bladder": p.bladder,
                "breakdownRisk": p.breakdownRisk
            ],
            "availableActions": availableActions(),
            "classmates": game.classmates.map { [
                "name": $0.name,
                "state": $0.state.rawValue,
                "seat": [$0.seat.row, $0.seat.column]
            ] },
            "clues": game.chapterClues.map(\.title),
            "message": game.message
        ]
        if let event = pendingEvent {
            dict["event"] = [
                "title": event.title,
                "body": event.body,
                "choices": event.choices.map { ["id": $0.id, "title": $0.title, "detail": $0.detail] }
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    private func describeGameState() -> String {
        switch game.gameState {
        case .menu: return "menu"
        case .playing: return "playing"
        case .event: return "event"
        case .ending: return "ending"
        }
    }

    private func helpText() -> String {
        """
        【命令说明】
          <动作名>            执行玩家动作，如「写作业」「深呼吸」「看手机」
          look <方向>         改变视角：forward/desk/board/left/right/rear
          move <wasd>         自由活动中移动
          wait                跳过一回合（推进教师巡逻）
          drink / snack ...   使用物品（见可用动作列表）
          restroom            使用洗手间
          water               喝水
          refill              给水杯补水
          locker              开关个人储物柜
          door <front|rear> <open|close>
          state               重新渲染当前画面
          omniscient          查看全知视角（所有隐藏数值）
          frame               输出逐像素 RGB 数据（JSON，供 AI 精确解析画面）
          color / noColor     开关 ANSI 真彩输出
          history             查看动作历史与数值变化
          help                显示本说明
          quit                结束会话
        """
    }
}
