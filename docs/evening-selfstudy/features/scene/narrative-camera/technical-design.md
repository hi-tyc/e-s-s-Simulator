# F-04 叙事相机模式与场景呈现 — 技术设计

> 状态：final / accepted

## 实现方案

`NarrativeCameraMode` 和 `ScenePresentationState` 是本特性的两个核心新类型。`GameManager` 持有并发布 `ScenePresentationState`，`ClassroomCoordinator.update(game:)` 每帧消费它，单向映射到 SCNCamera 配置和场景根节点的显示/隐藏。

相机模式切换通过比较当前帧与上帧的 `cameraMode` 判断是否需要重配，重配只改相机节点位置、约束、FOV 和允许的 `CameraPose` 范围，不重建整个场景。

场景根节点按 `activeSceneRootID` 索引——`ClassroomCoordinator` 内部维护一个 `[String: SCNNode]` 字典，每次 `update` 时仅保持目标根节点和转场辅助节点可见，其余根节点 `isHidden = true`，不从场景图中移除（避免重复创建开销）。

章节转场遵循三阶段协议：
1. **prepare**：预载目标场景根节点（若尚未创建则惰性构建），关闭当前章热点，不对外开放新章热点；将 `transition` 字段写入 `ScenePresentationState`。
2. **commit**：以一次原子 UserDefaults 事务写入新章节、检查点 ID、相机模式、目标 ID，同时切换 `activeSceneRootID`；这是存档的合法落点。
3. **cleanup**：移除旧章 SceneDirector Beat，隐藏已不需要的旧根节点，清空 `transition` 字段。

`SceneTransition.colorTemperatureFlip` 由新增的 `ColorTemperatureAnimator` 驱动，对场景主环境灯的 `color` 和 `temperature` 属性做 `CABasicAnimation` 插值；`mirrorRipple` 通过对镜面 SCNNode 的 UV 偏移做周期动画实现，不使用 Metal shader，保持程序化优先策略。

## 关键类型与接口

```
enum NarrativeCameraMode: Codable, Equatable
  cases: seatedFirstPerson, freeRoamFirstPerson, guidedThirdPerson,
         dialogueFirstPerson, mirrorFirstPerson, waitingSeated

struct ScenePresentationState: Codable, Equatable
  var chapter: ChapterID
  var cameraMode: NarrativeCameraMode
  var activeSceneRootID: String
  var transition: SceneTransition?
  var objectiveTargetID: String?

enum SceneTransition: Codable, Equatable
  case fade(duration: TimeInterval)
  case colorTemperatureFlip(duration: TimeInterval)
  case mirrorRipple(duration: TimeInterval)

// ClassroomCoordinator 扩展（不重命名现有类型）
func applyNarrativeCameraMode(_ mode: NarrativeCameraMode)
func activateSceneRoot(id: String, transition: SceneTransition?)
func deactivateSceneRoot(id: String)
func sceneRoot(for id: String) -> SCNNode   // 惰性创建

// 转场协议方法（由 GameManager 调用）
func prepareTransition(to: ScenePresentationState)
func commitTransition(to: ScenePresentationState)
func cleanupTransition(from oldRootID: String)

// 色温动画辅助
struct ColorTemperatureAnimator
  func animate(from: SCNLight, toTemperature: CGFloat, duration: TimeInterval)

// liquidGlassPanel 提升（从 ContentView 私有扩展迁移）
extension View
  func liquidGlassPanel(cornerRadius: CGFloat, tint: Color) -> some View
```

## iPad 适配注意事项

本特性无特定 iPad 约束，遵循全局 `PlatformViewRepresentable` 规范即可。

F-04 是 F-21（多平台适配基础）的前置依赖；设计时须确保 `NarrativeCameraMode` 和 `ScenePresentationState` 不硬编码 macOS 专属 API，相机锚点、输入限制等平台差异推迟到 F-21 阶段注入。具体来说，`ClassroomCoordinator` 内部对 `NSViewRepresentable` 的依赖不得渗透到 `NarrativeCameraMode` 的定义层。

## 与现有代码的关系

| 层次 | 现有状态 | 本特性变更 |
|---|---|---|
| `CameraPose` | 存在，描述玩家视线朝向（left/right/forward/desk/up） | 保留不变，不被 `NarrativeCameraMode` 替换 |
| `ClassroomCoordinator` | 存在，持有单教室场景节点，`update(game:)` 映射旧 `GameState` | 扩展场景根节点字典，新增 `applyNarrativeCameraMode`、转场三阶段方法；不重命名类 |
| `ContentView.liquidGlassPanel` | 私有扩展，只 ContentView 可用 | 提升为 `LateStudySimulator` 模块内共享 modifier；原 ContentView 调用保持不变 |
| `GameManager` | 存在，回合制逻辑 | 新增 `scenePresentation: ScenePresentationState` 存储属性和 `transitionScene(to:)` 方法 |
| `NarrativeCameraMode` | 不存在 | 全新新增 |
| `ScenePresentationState` | 不存在 | 全新新增，进入 `NarrativeSave` |
| `SceneTransition` | 不存在 | 全新新增 |
| `ColorTemperatureAnimator` | 不存在 | 全新新增，内部辅助类型 |

## 风险与注意事项

- 场景根节点惰性创建时，首次构建可能引起短暂卡顿；需在 `prepare` 阶段完成预载，不在 `commit` 阶段同步创建。
- `commit` 阶段要求一次原子写入，若 UserDefaults 写入失败（极少见），必须回滚 `activeSceneRootID` 并恢复旧根节点可见性，避免出现场景与存档不一致的中间态。
- 镜像空间节点根与走廊节点根共享同一 `SCNScene`，材质切换时需防止跨根节点的材质引用混淆；建议各根节点使用独立材质实例而非共享引用。
- `Reduce Motion` 检测依赖 `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`（macOS），需在 `ColorTemperatureAnimator` 和 `SceneTransition` 应用层统一检查，避免分散处理。
- 第一章已有的 270° 坐姿视角限制逻辑（`CameraPose` 快捷键映射）在切换到 `seatedFirstPerson` 模式时应自动恢复；需确保 `applyNarrativeCameraMode` 不覆盖 `CameraPose` 的枚举定义和 shortcut 属性。
