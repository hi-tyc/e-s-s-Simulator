# F-13 引导第三人称移动与热点交互 — 技术设计

> 状态：final / accepted

## 实现方案

在 `ClassroomCoordinator` 内为 `guidedThirdPerson` 模式新增相机跟随逻辑。`update(game:)` 读取 `ScenePresentationState.cameraMode`，当值为 `.guidedThirdPerson` 时调用 `updateThirdPersonCamera` 将相机节点定位到玩家角色背后上方的固定偏移点，并用 `SCNTransaction` 平滑插值，消除帧间抖动。

热点以 `HotspotDefinition` 描述（位置、触发半径、关联动作 ID），由 `HotspotRegistry` 在章节开始时注册、章节切换时清空。每帧 `update(game:)` 遍历当前章节热点，计算玩家距离，达到阈值时更新 `SCNNode` 高亮材质并通知 SwiftUI 侧显示键位提示；距离恢复后撤销高亮。

玩家按确认键时，`GameManager` 检查当前高亮热点 ID，调用 `completeStep(_:result:)`；`completeStep` 内部通过 `completedStepIDs` 检查幂等性，防止双触发。

模式切换（`leaveSeat` → `guidedThirdPerson` / 进入对话 → `dialogueFirstPerson`）通过 `GameManager` 写 `ScenePresentationState`，`ClassroomCoordinator.update` 检测 `cameraMode` 变化后执行 `SCNTransaction` 过渡；Reduce Motion 开启时降级为淡入淡出。

## 关键类型与接口

新增或扩展的 Swift 类型：

```
ThirdPersonCameraConfig: Codable, Equatable
  - offset: SCNVector3      // 角色后上方偏移，默认 (0, 1.8, -3.2)
  - followSmoothing: Float  // SCNTransaction 时长，默认 0.08s

HotspotDefinition: Codable, Equatable, Identifiable
  - id: String
  - worldPosition: SIMD3<Float>
  - activationRadius: Float          // 默认 1.5m
  - actionID: BeatActionID
  - keyboardFocusLabel: String       // 无障碍朗读文本

HotspotRegistry
  - func register(_ hotspot: HotspotDefinition)
  - func clearAll()
  - func nearestActive(to position: SIMD3<Float>) -> HotspotDefinition?

// ClassroomCoordinator 新增方法
func updateThirdPersonCamera(playerWorldPos: SCNVector3, config: ThirdPersonCameraConfig)
func updateHotspotHighlights(nearestID: String?)

// GameManager 新增或修改
func handleHotspotConfirm(hotspotID: String)   // 调用 completeStep，幂等
func setNarrativeCameraMode(_ mode: NarrativeCameraMode)  // 写 ScenePresentationState
```

## iPad 适配注意事项

本特性无特定 iPad 约束，遵循全局 PlatformViewRepresentable 规范即可。触控输入（点击目标位置移动）若后续在 iPad 启用，可复用现有 `NSViewRepresentable` 对应的 `UIViewRepresentable` 封装，热点激活半径保持不变。

## 与现有代码的关系

**复用（不修改）：**
- `NarrativeCameraMode.guidedThirdPerson`（已在 `ScenePresentationState` 定义）
- `ClassroomCoordinator` 框架与 `update(game:)` 驱动模式
- 现有移动与碰撞逻辑（`PlayerAction.leaveSeat`、角色节点位移）
- `BeatActionID` / `completeStep` 幂等机制（来自 F-01/F-02）
- `liquidGlassPanel` 热点提示气泡样式

**修改（增量）：**
- `ClassroomCoordinator.update(game:)`：新增 `guidedThirdPerson` 分支，调用 `updateThirdPersonCamera` 和 `updateHotspotHighlights`
- `GameManager`：新增 `handleHotspotConfirm`，写 `ScenePresentationState.cameraMode` 的公共方法

**新增：**
- `ThirdPersonCameraConfig`
- `HotspotDefinition`
- `HotspotRegistry`
- `ClassroomCoordinator` 内两个辅助方法

## 风险与注意事项

- 相机跟随偏移与场景几何的遮挡处理：若相机节点被墙体遮挡，需在 `updateThirdPersonCamera` 中做射线检测推近；未处理时玩家在角落移动会看到穿墙画面
- `SCNTransaction` 时长太短会导致抖动，太长会有跟随延迟；默认 0.08s 需在实际场景中调校
- 热点距离检测在每帧遍历所有热点；第三章热点数量有限（< 10 个），不需要空间分区，但后续章节若增加热点需注意
- 键盘焦点与 3D 热点的坐标映射：SwiftUI 焦点环绘制在 HUD 层，需要把 SCNNode 世界坐标投影到屏幕坐标以确定焦点视觉位置
- 从 `guidedThirdPerson` 切回 `seatedFirstPerson` 时（章节结束或读档），需确保相机节点归位正确锚点，否则下一章视角会偏移
