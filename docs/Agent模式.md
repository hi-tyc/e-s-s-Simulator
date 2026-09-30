# Agent 模式

让 AI / 脚本像真人一样游玩这个游戏，无需图形界面。

## 为什么需要它

游戏的逻辑全部在 `GameManager` 里，SwiftUI 与 SceneKit 只是它的渲染层。
Agent 模式直接驱动 `GameManager`，把状态翻译成文本，因此可以：

- 让 AI 完整游玩，而不是靠读代码猜测手感
- 用脚本批量跑策略，观察数值平衡
- 在 CI 中自动检测"玩不下去"的回归

## 快速开始

```bash
# 交互式游玩（逐条输入命令）
swift run LateStudySimulator --agent

# 开启全知视角（显示所有隐藏数值，便于调试）
swift run LateStudySimulator --agent --omniscient

# 执行单条命令后退出
swift run LateStudySimulator --agent --omniscient --command "look left"

# 输出 JSON（机器可读）
swift run LateStudySimulator --agent --json --command "state"

# 按剧本自动跑
swift run LateStudySimulator --agent --script play.txt

# 内置 AI 自动游玩
swift run LateStudySimulator --agent --auto main
swift run LateStudySimulator --agent --auto-all
```

## 命令

| 命令 | 说明 |
|---|---|
| `<动作名>` | 执行玩家动作，如 `写作业`、`深呼吸`、`看手机` |
| `look <方向>` | 改变视角：`forward` / `desk` / `board` / `left` / `right` / `rear` |
| `move <wasd>` | 自由活动中移动 |
| `wait` | 跳过一回合（推进教师巡逻） |
| `water` / `refill` / `restroom` / `locker` | 使用物品与设施 |
| `door <front\|rear> <open\|close>` | 开关前后门 |
| `state` | 重新渲染当前画面 |
| `omniscient` | 查看所有隐藏数值 |
| `history` | 查看动作历史与数值变化 |
| `help` / `quit` | 帮助 / 退出 |

事件发生时，输入选项编号或 choice id 进行选择。

## 输出结构

默认视图包含四层信息：

```
┌ 头部     ──  回合 / 阶段 / 时钟 / 视角 / 姿态
├ 场景     ──  ASCII 字符画（射线投射渲染）
├ 主观感受 ──  模糊化描述（"精力：尚可（74）"），模拟真人感知
├ 全知视角 ──  （仅 --omniscient）所有精确数值与隐藏状态
└ 可用动作 ──  当前合法命令列表
```

**信息分层是刻意的**：默认视图只给"玩家能感知到的东西"，
让 AI 的决策更接近真人；`--omniscient` 用于调试与数值分析。

## 关于"用字符绘制游戏画面"

`SceneASCIIRenderer` 用射线投射把 3D 教室渲染成字符画：

- 坐标系与 `ClassroomSceneView` 一致（x: -4→4，z: -6→6）
- 每个字符代表一条射线的最近命中
- 图例：`▬`黑板 `▰`讲台 `▯`门 `◷`钟 `▢`课桌 `☖`老师
- 同学用状态字符区分：`☺`写题 `◉`焦虑 `▤`手机 `☁`困倦 `⊙`看你 `♥`关心 `◍`崩溃 `▥`掩护

## 已知的设计问题（通过本工具发现）

用 `--auto-all` 跑所有内置策略后，观察到：

1. **主线走完即游戏结束**：`completeChapterOne()` 直接调用 `finish()`，
   因此跟着剧情走只能玩到第 6 回合，且必定得到"普通的一晚"。
2. **其他结局需要偏离主线**：想拿到"学霸之夜""社交之夜"等结局，
   必须在第一章故意不推进主线——这与"鼓励玩家跟随叙事"的意图冲突。
3. **朴素策略全部收敛**：五种策略都得到相同结局，说明结局判定与玩家行为的相关性不足。

这些不是代码 bug，而是**数值与流程设计需要决策的地方**。
建议先决定：第一章结束后应该继续游戏，还是作为完整作品收尾？

## 相关文件

| 文件 | 职责 |
|---|---|
| `AgentMode/AgentGameSession.swift` | 会话核心：状态渲染、命令解析、执行 |
| `AgentMode/SceneASCIIRenderer.swift` | 字符画渲染（射线投射） |
| `AgentMode/AutoPlayer.swift` | 内置自动游玩策略 |
| `AgentMode/AgentModeCLI.swift` | 命令行入口与参数解析 |
