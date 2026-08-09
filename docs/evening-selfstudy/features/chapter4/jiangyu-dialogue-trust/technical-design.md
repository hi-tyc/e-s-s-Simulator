# F-16 江越对话与信任系统 — 技术设计

> 状态：final / accepted

## 实现方案

第四章核心是一个以信任值为隐性参数的对话状态机，结合编剧固定的风险事实驱动安全路线分流。

信任值由 `DialogueTrustReducer` 作为纯函数计算：输入为当前 `GameNarrativeState`（包含前三章积累的 `linCheListenScore`、`companionChoice` 等基础分）以及当前回应选项的类型，输出增量写回 `GameManager.narrative.jiangYueTrustValue`。不创建独立可观察对象，不在视图层暴露数值。

对话流程由 `JiangYueDialogueStateMachine` 管理四段独白的推进、每段的 15 秒响应窗口、超时后的默认选择以及阶段转换。每段独白播放完毕后 SceneDirector 激活响应窗口，窗口关闭（玩家选择或超时）后推进到下一段。

追问阶段（步骤 4）在选项展示前强制呈现教育便签，教育便签由 `EducationCardView` 展示，玩家确认关闭后才解锁选项。追问结果通过 `DisclosureResolver.resolve(method:trust:)` 纯函数计算 `RiskDisclosure`，与 `RiskAskMethod` 一起写入 `Ch4State`。

安全路线由 `SafetyHandoffPolicy` 读取编剧风险事实 `jiangYueActualRisk` 和成人接管状态，输出 `SafetyRoute` 和 `CounselingEntryMode`。高危/紧急路线触发后 SceneDirector 取消普通倒计时 Beat 并切换到安全响应 Beat 序列。章节转换必须以原子方式同时持久化 `safetyRoute`、`CounselingEntryMode` 和章节检查点。

课间倒计时由 `CountdownTimer(duration: 600)` 驱动，SwiftUI overlay 以极小数字（11pt，60% 透明度）显示在右上角，剩余 120 秒时颜色过渡为暖橙。高危/紧急路线触发后定时器暂停并从 UI 撤除。

## 关键类型与接口

```swift
// 纯函数：根据回应类型计算信任值增量
func DialogueTrustReducer.applyResponse(_ response: DialogueResponseKind, to trust: Double) -> Double

// 江越对话状态机：管理四段独白推进与响应窗口
class JiangYueDialogueStateMachine

// 风险询问结果：仅决定玩家获得多少信息，不输出真实风险
func DisclosureResolver.resolve(method: RiskAskMethod, trust: Double) -> RiskDisclosure

// 安全交接策略：读取编剧风险事实输出路线
struct SafetyHandoffPolicy
func SafetyHandoffPolicy.route(for risk: RiskLevel) -> (SafetyRoute, CounselingEntryMode)

// 教育便签视图：玩家确认关闭，不自动消失
struct EducationCardView: View

// 方老师到场序列
struct TeacherArrivalSequence

// 倒计时
class CountdownTimer
```

新增枚举值（已在 GameModels 中需确认声明）：
- `RiskAskMethod: none, gentle, direct, deferToAdult`
- `DialogueResponseKind: judgmental, inspirational, advisory, listening, accompanying, silentPresence, timeout`

## iPad 适配注意事项

本特性无特定 iPad 约束，遵循全局 PlatformViewRepresentable 规范即可。教育便签和倒计时 overlay 使用 SwiftUI 自适应布局，对话选项按钮使用系统最小点击目标尺寸（44pt）。

## 与现有代码的关系

复用：
- `GameManager`：在现有存储属性中新增 `quest`/`narrative`/`chapterState` 支持，`completeStep` 幂等接口
- `CameraPose`：步骤 2 切换为 `.dialogueFirstPerson` 模式（`NarrativeCameraMode` 新增值）
- `ActiveEvent`/`EventChoice`：扩展为 `ChapterDialogue`，支持多轮对话
- `ClassroomCoordinator`：江越 NPC 节点的情绪状态映射（表情/肩膀/姿态）由 Coordinator 在 `update(game:)` 单向映射
- `liquidGlassPanel`：教育便签、对话选项卡片使用现有辅助器

修改：
- `GameManager`：新增第四章 Beat 注册、`CountdownTimer` 持有、信任值写回路径、安全路线分流逻辑
- `SceneDirector`：新增高危路线 Beat 序列，`activePauseReasons` 集合加入倒计时暂停项

新增：
- `JiangYueDialogueStateMachine`（GameManager 内部协作者）
- `DialogueTrustReducer`（纯函数命名空间）
- `DisclosureResolver`（纯函数命名空间）
- `SafetyHandoffPolicy`（读取编剧配置和 GameManager 状态）
- `TeacherArrivalSequence`（移动路径 + 台词 overlay）
- `EducationCardView`（SwiftUI，含确认关闭逻辑）
- `CountdownTimer`（`ObservableObject` 或 `async Task`，不进入存档）
- `Ch4FallbackDirector`（信任不足时接管步骤推进）

## 风险与注意事项

- 幂等竞争：玩家响应与 fallback（15 秒超时）可能在同一帧到达，必须确保 `completeStep` 只写入一次
- 存档原子性：`safetyRoute` + `CounselingEntryMode` + 章节检查点必须在同一事务快照中编码；任何中间态都不能成为有效存档点
- 安全响应脚本依赖：心理专业审核文本是 Release 必需资源，未配置时 Release 构建失败
- `jiangYueActualRisk` 不可由玩家行为计算：该字段是编剧配置值，不得在逻辑代码中被信任分或披露结果覆盖
- 高危路线的 Beat 优先级：普通倒计时 Beat 必须在高危路线触发后被取消，不得继续推进普通剧情步骤
- 江越 NPC 情绪动画成本：肩膀/表情/姿态需要细腻的 SCNAction 调试，动画资产策略影响工期
