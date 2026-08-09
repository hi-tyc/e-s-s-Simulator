# F-08 视角停留判定与聚焦反馈 — 技术设计

> 状态：final / accepted

## 实现方案

`GameManager` 持有一个 `DwellFocusState` 内存结构体，跟踪当前活跃的 `CameraPose`、已累积的停留时长和本步骤已触发过的姿态集合。`ClassroomCoordinator` 的 `update(game:)` 驱动帧循环，每帧读取 `GameManager.scenePresentation.cameraMode` 和当前 `CameraPose`，若模式为 `seatedFirstPerson` 且 `activePauseReasons` 为空，则将 `deltaTime` 累加到 `dwellFocus.dwellAccumulated`。

姿态切换时立即将 `dwellAccumulated` 归零并更新 `activePose`。当 `dwellAccumulated` 超过对应姿态的 `DwellThreshold` 且该姿态尚未在 `triggeredInCurrentStep` 中时，按以下顺序执行：
1. 将当前姿态写入 `triggeredInCurrentStep`（防止重复触发）
2. 向 `GameManager` 发布 `focusFeedbackTrigger`（`@Published`），ContentView 读取并激活暖光 overlay 动画
3. 通过 `ClassroomCoordinator` 启动 FOV 推近 SCNAction
4. 调用 `GameManager.completeStep(currentStepID, result:)`（幂等）

步骤切换（`quest.currentStep` 变化）时，`GameManager` 重置 `dwellFocus.triggeredInCurrentStep` 和 `dwellAccumulated`，保证每步骤独立判定。

## 关键类型与接口

```
struct DwellFocusState                         // 纯运行时，非 Codable
    activePose: CameraPose?
    dwellAccumulated: TimeInterval
    triggeredInCurrentStep: Set<CameraPose>

struct DwellThreshold                          // 常量配置，非 Codable
    static let defaults: [CameraPose: TimeInterval]
    subscript(pose: CameraPose) -> TimeInterval

// GameManager 新增
var dwellFocus: DwellFocusState
@Published var focusFeedbackTrigger: CameraPose?   // nil = 无激活反馈
func updateDwellFocus(pose: CameraPose, delta: TimeInterval)
func resetDwellFocusForStep()

// ClassroomCoordinator 新增
func applyFocusFeedback(for pose: CameraPose, reduceMotion: Bool)
    // 触发 SCNCamera.fieldOfView 动画：current → current-2 → current，总时长 0.5s

// ContentView / FocusFeedbackOverlay
struct FocusFeedbackOverlay: View
    // 监听 focusFeedbackTrigger，执行 0.3s 淡入 + 0.2s 停留 + 0.3s 淡出的边缘暖光
```

## iPad 适配注意事项

本特性无特定 iPad 约束，遵循全局 PlatformViewRepresentable 规范即可。

（《这里有光》目标平台为 macOS 26，停留判定基于 CameraPose 离散状态，与鼠标/触控板输入方式无关，亦无触摸专属手势逻辑。）

## 与现有代码的关系

**复用：**
- `CameraPose` 枚举（`.left/.right/.forward/.desk`）：停留判定直接基于已有枚举值，不新增视角状态
- `activePauseReasons: Set<PauseReason>`：冻结逻辑复用 F-02 的暂停集合，不增加新的暂停接口
- `ClassroomCoordinator.update(game:)` 帧回调：FOV 动画在已有每帧映射点插入，不额外注册 displayLink
- `liquidGlassPanel` 样式：`FocusFeedbackOverlay` 使用共享 modifier，不自建背景实现

**修改：**
- `GameManager`：新增 `dwellFocus` 存储属性、`focusFeedbackTrigger @Published`、`updateDwellFocus` 与 `resetDwellFocusForStep` 方法；在步骤切换处（`completeStep` 内部）调用重置
- `ClassroomCoordinator.update(game:)`：读取 `focusFeedbackTrigger`，执行 FOV 动画并向 GameManager 清除信号
- `ContentView`：在主 ZStack 中加入 `FocusFeedbackOverlay`，监听 `focusFeedbackTrigger`

**新增：**
- `DwellFocusState` 结构体（GameModels.swift 或独立文件）
- `DwellThreshold` 常量结构体
- `FocusFeedbackOverlay` SwiftUI 视图（ContentView.swift 内嵌 private 结构体）

## 风险与注意事项

- 帧率波动导致 deltaTime 偏大时，阈值可能在单帧内越过；需在 `updateDwellFocus` 中对 delta 做上限截断（建议 ≤ 0.1s），避免跳帧时意外触发
- 同一帧内 `completeStep` 与 SceneDirector fallback Beat 同时到达时，幂等门禁（F-01）保证只写一次；但需确认 fallback Beat 取消逻辑在 `completeStep` 后立即执行，不留悬空 Timer
- FOV 推近动画通过 `SCNTransaction` 实现时，需在每次触发前先取消上一个未完成的 transaction，防止动画堆叠导致 FOV 漂移
- `Reduce Motion` 开启时需在 `applyFocusFeedback` 内分支处理，避免调用 `UIAccessibility.isReduceMotionEnabled`（macOS 应使用 `NSWorkspace.accessibilityDisplayShouldReduceMotion`）
