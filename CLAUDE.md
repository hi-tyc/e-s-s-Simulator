# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

晚自习模拟器是一个 macOS 桌面端的 3D 第一视角心理健康体验游戏。玩家被固定在教室第三排座位,只能靠视角切换、声音和有限行动来判断局势并撑过晚自习。设计目标之一是「约 70% 的信息来自音频」。完整设计意图见 `docs/晚自习模拟器_v4.0_完整设计文档.md`,已有架构文档在 `docs/architecture/`。

## 构建与运行

项目用 Swift Package 组织(无 `.xcodeproj`),目标平台 macOS 26。

```bash
swift build                    # 构建
swift run LateStudySimulator   # 构建并运行
```

关键约束:
- 目标平台声明为 `.macOS(.v26)`,依赖 SwiftUI 官方 Liquid Glass API(`glassEffect`、玻璃按钮样式)。必须在支持 Liquid Glass 的 SDK/运行环境下构建,否则会编译或运行失败。
- 设计假设环境只有 Command Line Tools,因此用 `swift build`/`swift run` 而非 `xcodebuild`。
- **当前工作机是 Windows**,PATH 中没有 `swift`,无法在此环境直接构建。任何构建/运行验证需要在 macOS 上进行——在此环境下修改代码后无法本地验证编译,需明确告知用户。
- 目前没有 `Tests/` 目录,也没有测试框架。

## 架构

单一 `@MainActor` 状态机 + SwiftUI 声明式 UI + SceneKit 3D 场景 + AVFoundation 空间音频,四层通过一个全局 `GameManager` 串联。

### 数据流与所有权

- `LateStudySimulatorApp` 创建唯一的 `@StateObject GameManager`,通过 `environmentObject` 注入。
- `GameManager`(`GameManager.swift`,约 2000 行)是**唯一的可信状态源和游戏逻辑核心**:回合推进、玩家/教师行动、NPC 行为、事件生成、结局计算、回放快照、跨局记忆和音频调度都集中在这里。改游戏逻辑基本都在这个文件。
- `ContentView`(`ContentView.swift`)是纯展示层,`@EnvironmentObject` 读取 `GameManager` 的 `@Published` 属性渲染菜单/HUD/事件弹层/结局报告,并把用户操作转发回 `GameManager` 的方法。
- `ClassroomSceneView`(`ClassroomSceneView.swift`)用 `NSViewRepresentable` 包 `SCNView`。真正的 3D 状态在 `ClassroomCoordinator` 里——它持有所有 SCNNode(相机、教师、同学、手机、黑板、时钟、抽屉、吊扇等),`updateNSView` 每帧调用 `coordinator.update(game:)`,把 `GameManager` 的状态**单向**映射到场景节点。SwiftUI 不直接操作节点。
- `GameModels.swift` 是纯领域模型:所有 `enum`(`GameState`、`CameraPose`、`VisionZone`、`PlayerAction`、`TeacherAction`、`ClassmateState`、`StudyPeriod` 等)和 `struct`(`PlayerState`、`TeacherState`、`Classmate`、`Ending`、`TurnSnapshot`、`InstitutionSettings` 等)。没有逻辑,只有数据和派生计算属性。

### 核心循环

`GameState`(`.menu` / `.playing` / `.event(ActiveEvent)` / `.ending(Ending)`)驱动整个界面和流程。一个学生回合的执行链在 `GameManager.execute(_:)`:

```
玩家行动 → applyBodyNeeds() → clampPlayer()
        → 若触发事件则 recordSnapshot 后 return(暂停循环,等待 resolveEventChoice)
        → updateClassmates(after:) → recordSnapshot() → teacherTurn()
```

- **事件会打断循环**:`presentEvent` 把 `gameState` 切到 `.event`,`execute` 提前返回;`resolveEventChoice` / `continueAfterEvent` 负责恢复。新增行动逻辑时注意这个提前返回路径。
- `teacherTurn()` 是教师 AI,根据 KPI 压力、疲劳、同理心决定巡视/提醒/放过/关心/后门观察/假巡视,并驱动被发现、崩溃等关键事件(`checkCriticalState`)。
- 玩家视角(`CameraPose`)映射到 `VisionZone`,不同区消耗不同视觉注意力(`spendAttention`),影响压力和聚焦质量——这是「转头有成本」机制的核心。
- 结局由 `calculateEnding()` / `teacherEnding()` 根据累积指标和阈值生成,附带故事、三方同理心反思、数据分析和心理支持资源。

### 跨局记忆

`ClassmateMemory`(`Codable`)通过 `UserDefaults`(key `LateStudySimulator.ClassmateMemory.v1`)在启动间持久化同学关系、压力余波和怀疑值。`commitClassmateMemory` 在结局时写入,`loadClassmateMemory` 在 `init` 读取,`clearClassmateMemory` 清除。改记忆结构时注意向后兼容(key 里带版本号)。

### 音频

`SpatialAudioManager`(`SpatialAudioManager.swift`)基于 `AVAudioEngine` + `AVAudioEnvironmentNode` 做 3D 定位音频。设计为**程序化优先 + 真实素材可选覆盖**:

- 默认全部程序化合成(心跳、灯管嗡声、笔尖声、吊扇底噪等,由 `AVAudioSourceNode` 实时生成)。
- 若在 `Sources/LateStudySimulator/Resources/AudioCues`(事件短音)或 `Resources/AudioLoops`(循环环境声,固定 4 个:`light_hum`/`pen_scratch`/`ceiling_fan`/`outside_night`),或用户目录 `~/Library/Application Support/LateStudySimulator/` 下放入同名音频文件(wav/mp3/m4a/aif/aiff/caf),则优先播放真实素材,缺失自动回退程序化。
- `assetStatus` 计算真实素材覆盖率,菜单面板显示接入/缺失数量。

### Liquid Glass 约定

UI 面板统一走 `ContentView.swift` 底部 `private extension View` 里的 `liquidGlassPanel(cornerRadius:tint:)`,按钮走 `ActionButtonStyle` / `SegmentButtonStyle`(内部调 `glassEffect`)。新增 UI 面板时复用这些辅助,不要直接堆原生背景。

## 惯例

- 全部游戏逻辑运行在主线程:`GameManager` 和 `ClassroomCoordinator` 都标注 `@MainActor`。
- 用户可见文案(`message`、独白、事件文本、结局)大量使用第一/第二人称中文叙事,是产品的一部分而非调试信息,改动时保持语气一致。
- 快捷键映射硬编码在枚举的 `shortcut` 属性(`CameraPose`、`PlayerAction`、`TeacherAction`),不要在别处另设一套。
