# F-12 三灯微游戏 — 技术设计

> 状态：final / accepted

## 实现方案

`MicroGameOverlay` 以 SwiftUI `ZStack` 叠加在 `ClassroomSceneView` 的 `NSViewRepresentable` 上层，由 `GameManager` 的 `@Published var activeMicroGame: MicroGameID?` 控制可见性。三个微游戏共用同一 overlay 容器，通过 `switch activeMicroGame` 渲染不同子视图。

overlay 打开/关闭不经过 `GameState.event`，使用独立 `@Published` 属性，避免与 `.event` 覆盖层语义混淆。overlay 可见期间 `GameManager` 向 `activePauseReasons` 插入新增的 `PauseReason.microGame`，冻结镜像空间内的 SceneDirector 受控 Beat（灯管环境循环可继续）。overlay 关闭时移除该原因。

每个微游戏完成时调用 `GameManager.completeMicroGame(_:)` 一次，内部调用 `completeStep` 写入 `Ch2State.completedLights`，再请求 `ClassroomCoordinator` 在下一帧映射灯节点变化。

**草稿灯（描线）**：`DraftLineMicroGame` 以 `GeometryReader` + `DragGesture` 在 SwiftUI `Canvas` 上绘制路径；命中判定将手指坐标投影到折线段，累计覆盖比例达 80% 触发完成。容忍误差 ±15pt 定义为可配置常量。

**旋律灯（接唱）**：`MelodyMicroGame` 以 `AVAudioEngine`（复用 `SpatialAudioManager` 已有实例）程序化生成 4 个音高（约 330/392/440/523 Hz），播放顺序固定。答题阶段显示 4 个 `Button`；错误时重播序列，第 3 次后 `isAutoPass = true` 并调用完成路径。

**擦痕灯（擦除）**：`EraseMicroGame` 在 `Canvas` 上维护已擦区域列表，`DragGesture.onChanged` 追加当前笔触矩形，计算并集覆盖面积比。达 60% 触发完成；剩余 40% 为编剧意图，不强制清零。

## 关键类型与接口

```
enum MicroGameID: String, Codable, CaseIterable { case draft, melody, comparison }

// PauseReason 新增 case
case microGame   // 追加到现有 PauseReason 枚举

struct MicroGameOverlayView: View              // ZStack overlay 容器，读 activeMicroGame
struct DraftLineMicroGame: View                // 描线子视图
struct MelodyMicroGame: View                   // 旋律接唱子视图
struct EraseMicroGame: View                    // 擦除子视图

// GameManager 新增属性与方法
var activeMicroGame: MicroGameID?              // @Published
func presentMicroGame(_ id: MicroGameID)       // 设置 activeMicroGame，插入 .microGame 暂停原因
func completeMicroGame(_ id: MicroGameID)      // 幂等提交 completedLights，关闭 overlay
func dismissMicroGame()                        // 读档/返回菜单时强制关闭 overlay
```

## iPad 适配注意事项

本特性无特定 iPad 约束，遵循全局 PlatformViewRepresentable 规范即可。`DragGesture` 在 iPad 触控与 macOS 触控板上行为一致；旋律接唱的答题按钮布局使用 `LazyVGrid` 以适应不同屏幕尺寸；描线和擦除的命中容差（±15pt）应基于逻辑点而非物理像素，保持跨分辨率一致。

## 与现有代码的关系

**复用：**
- `liquidGlassPanel(cornerRadius:tint:)` / `ActionButtonStyle`：overlay 背景与按钮样式（需先提升为模块内共享 View modifier，参考 PRD §E）
- `SpatialAudioManager`：旋律灯复用已有 `AVAudioEngine` 实例，不另建
- `PauseReason`：在现有枚举中追加 `.microGame` case
- `ClassroomCoordinator.update(game:)`：读取 `Ch2State.completedLights`，单向映射灯光强度与光路节点

**新增：**
- `MicroGameOverlayView` 及三个子视图（独立文件）
- `GameManager` 中的 `activeMicroGame`、`presentMicroGame`、`completeMicroGame`、`dismissMicroGame`
- `PauseReason.microGame` case

**不修改：**
- `GameState` enum（不新增 case）
- `ClassroomSceneView.swift` 结构（只通过 `@Published` 驱动 overlay 显示）
- `Ch2State` 类型定义（由 F-11 定义，本特性只负责写入 `completedLights` 和 `currentLight`）

## 风险与注意事项

- 描线命中容差（±15pt）需在 macOS 触控板上迭代，建议定义为 `enum DraftLineConstants { static let hitTolerance: CGFloat = 15 }` 便于调整
- 擦除面积计算基于矩形并集，不是精确像素 mask；若视觉效果不符合预期，可换为 Core Graphics 位图方案，工期上浮约 1 天
- 旋律自动通过（3 次后）与 SceneDirector 超时兜底（18min 软上限）可能同时触发，需通过 `completeMicroGame` 幂等保证只写入一次
- 应用失焦时需同时插入 `PauseReason.appInactive` 与保留 `PauseReason.microGame`；恢复时只移除 `.appInactive`，overlay 保持冻结直到玩家继续操作
- `liquidGlassPanel` 目前为 `ContentView.swift` 私有扩展；本特性依赖它前须先确认已提升为模块内共享 modifier
