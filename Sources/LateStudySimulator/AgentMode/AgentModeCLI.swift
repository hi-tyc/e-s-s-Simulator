import Foundation

/// Agent 模式命令行入口。
///
/// 让 AI / 脚本以文本协议完整游玩游戏。
///
/// ## 用法
///
/// ```bash
/// # 交互式（逐条输入命令）
/// swift run LateStudySimulator --agent
///
/// # 开启全知视角（显示所有隐藏数值）
/// swift run LateStudySimulator --agent --omniscient
///
/// # 执行单条命令后退出（适合脚本逐条调用）
/// swift run LateStudySimulator --agent --omniscient --command "look left"
///
/// # 输出 JSON（机器可读，适合程序化消费）
/// swift run LateStudySimulator --agent --json
///
/// # 按剧本自动跑（每行一条命令，空行忽略，# 开头为注释）
/// swift run LateStudySimulator --agent --script path/to/script.txt
/// ```
@MainActor
enum AgentModeCLI {

    /// 解析命令行并运行。返回是否接管了程序（true 表示不应启动 GUI）。
    static func runIfRequested(arguments: [String]) -> Bool {
        guard arguments.contains("--agent") else { return false }

        let omniscient = arguments.contains("--omniscient")
        let jsonMode = arguments.contains("--json")

        if let index = arguments.firstIndex(of: "--command"), index + 1 < arguments.count {
            runSingleCommand(arguments[index + 1], omniscient: omniscient, jsonMode: jsonMode)
            return true
        }

        if let index = arguments.firstIndex(of: "--script"), index + 1 < arguments.count {
            runScript(path: arguments[index + 1], omniscient: omniscient, jsonMode: jsonMode)
            return true
        }

        if let index = arguments.firstIndex(of: "--auto") {
            // --auto 可带策略名，也可省略（默认主线优先）
            let strategyName = index + 1 < arguments.count && arguments[index + 1].hasPrefix("--") == false
                ? arguments[index + 1]
                : AutoPlayer.Strategy.mainQuest.rawValue
            let strategy = AutoPlayer.Strategy(rawValue: strategyName) ?? .mainQuest
            runAuto(strategy: strategy, omniscient: omniscient)
            return true
        }

        if arguments.contains("--auto-all") {
            runAllStrategies(omniscient: omniscient)
            return true
        }

        runInteractive(omniscient: omniscient, jsonMode: jsonMode)
        return true
    }

    private static func runAuto(strategy: AutoPlayer.Strategy, omniscient: Bool) {
        let session = AgentGameSession(omniscient: omniscient)
        print(AutoPlayer.play(session: session, strategy: strategy))
        print(session.renderDefaultView())
    }

    private static func runAllStrategies(omniscient: Bool) {
        for strategy in AutoPlayer.Strategy.allCases {
            let session = AgentGameSession(omniscient: omniscient)
            print(AutoPlayer.play(session: session, strategy: strategy, verbose: false))
            print(session.agentEndingSummary())
            print("")
        }
    }

    // MARK: - 模式

    private static func runSingleCommand(_ command: String, omniscient: Bool, jsonMode: Bool) {
        let session = AgentGameSession(omniscient: omniscient)
        if jsonMode && command == "state" {
            print(session.stateJSON())
            return
        }
        let result = session.execute(command: command)
        print(render(result))
        if jsonMode { print("\n--- JSON ---"); print(session.stateJSON()) }
    }

    private static func runScript(path: String, omniscient: Bool, jsonMode: Bool) {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            FileHandle.standardError.write(Data("无法读取脚本：\(path)\n".utf8))
            exit(1)
        }
        let session = AgentGameSession(omniscient: omniscient)
        print(session.renderDefaultView())
        for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let command = line.trimmingCharacters(in: .whitespaces)
            if command.isEmpty || command.hasPrefix("#") { continue }
            print("\n>>> \(command)")
            let result = session.execute(command: command)
            print(render(result))
            if session.isFinished { break }
        }
        if jsonMode { print("\n--- 最终 JSON ---"); print(session.stateJSON()) }
    }

    private static func runInteractive(omniscient: Bool, jsonMode: Bool) {
        let session = AgentGameSession(omniscient: omniscient)
        print(session.renderDefaultView())
        print("\n输入 help 查看命令，quit 退出。\n")

        while true {
            FileHandle.standardOutput.write(Data("> ".utf8))
            guard let line = readLine(strippingNewline: true) else { break }
            let command = line.trimmingCharacters(in: .whitespaces)
            if command.isEmpty { continue }
            if command.lowercased() == "quit" { break }
            if jsonMode && command.lowercased() == "state" {
                print(session.stateJSON())
                continue
            }
            let result = session.execute(command: command)
            print(render(result))
            if jsonMode { print("\n--- JSON ---"); print(session.stateJSON()) }
            if session.isFinished { break }
        }
    }

    private static func render(_ result: AgentGameSession.CommandResult) -> String {
        switch result {
        case .ok(let text): return text
        case .error(let text): return "⚠ \(text)"
        case .finished(let text): return text
        }
    }
}
