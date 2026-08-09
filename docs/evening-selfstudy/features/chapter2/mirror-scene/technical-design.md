# F-11 镜像空间场景 — 技术设计

> 状态：final / accepted

## 实现方案

走廊场景的 SceneKit 节点树下新增一个 `mirrorRoot` 子节点，默认隐藏。玩家进入镜像空间时，`ClassroomCoordinator` 根据 `ScenePresentationState.transition == .colorTemperatureFlip` 执行以下操作：将 `mirrorRoot` 设为可见，对主环境灯的 `color` 和 `temperature` 做 0.8s 插值（暖黄→冷蓝），同时替换林澈 NPC 为冷调材质版本，并触发 `SpatialAudioManager` 切换背景音。退出时（三灯全亮后）以 10s 线性 `SCNTransaction` 将 `mirrorRoot` 材质透明度从 1→0.7，再在完成后切回现实材质并隐藏 `mirrorRoot`。

地面光路通过一条发光几何贴图节点（`lightPathNode`）实现，每完成一盏灯后将节点延伸到下一盏灯方向，由 `update(game:)` 根据 `Ch2State.completedLights` 确定性重建显示长度，无需保存几何状态进存档。

步骤 7、8 的对话选项复用现有 `ChapterDialogue` / `EventChoice` 扩展，选择结果一次性 `completeStep` 写入，幂等门禁由 `GameManager` 保证。

## 关键类型与接口

```
// 新增
struct MirrorSceneNodes           // ClassroomCoordinator 内部容器，持有 mirrorRoot、lightPathNode、linCheMirrorNode
class ColorTemperatureAnimator    // 封装 SCNTransaction 色温插值，接受 normalizedProgress 从检查点恢复
enum MirrorScenePhase             // .reality / .entering / .mirrorActive / .exiting
                                  // 由 ScenePresentationState 派生，不单独存档

// 扩展已有类型
extension Ch2State: Codable, Equatable   // 新增（见数据模型文档）
extension NarrativeCameraMode            // 新增 .mirrorFirstPerson case
extension SceneTransition                // 新增 .colorTemperatureFlip(duration:) case
extension ClassroomCoordinator          // 新增 updateMirrorScene(game:) 方法
extension SpatialAudioManager           // 新增 enterMirrorAmbient() / exitMirrorAmbient() 方法

// 林澈 NPC 双态
linCheNode.geometry.materials            // 现实材质集合（复用现有）
linCheMirrorMaterials: [SCNMaterial]     // 冷调材质集合，在 ClassroomCoordinator.setupMirrorScene() 中预构建
```

## iPad 适配注意事项

本特性无特定 iPad 约束，遵循全局 PlatformViewRepresentable 规范即可。镜像空间的触控输入路径（靠近镜面确认、步骤 7/8 对话点击）与 macOS 确认键等价，统一通过现有输入抽象层处理，F-21 激活时无需额外改造。

## 与现有代码的关系

**复用：**
- `ClassroomCoordinator`：在其 `update(game:)` 内新增 `updateMirrorScene(game:)` 分支，不修改现有座位/教室节点映射
- `SpatialAudioManager`：复用 `AVAudioEnvironmentNode` 空间定位，新增两个方法切换镜像空间环境音
- `liquidGlassPanel`：步骤 7/8 对话选项面板沿用现有样式辅助器
- `SceneTransition`、`NarrativeCameraMode`：新增 case，不修改现有 case

**新增：**
- `MirrorSceneNodes` 结构体（ClassroomCoordinator 内部）
- `ColorTemperatureAnimator` 类（封装插值逻辑，支持从归一化进度恢复）
- `Ch2State` 结构体（`GameModels.swift` 新增）
- `MirrorLightID` 枚举（`GameModels.swift` 新增）

**修改：**
- `GameManager`：新增 `ch2State: Ch2State` 属性，`startChapter(.mirror)` 注册第二章 Beat
- `ChapterRuntimeState`：新增 `.mirror(Ch2State)` case

## 风险与注意事项

- `SCNTransaction` 10s 褪色与 `activePauseReasons` 冻结机制需协同：必须在 `update(game:)` 每帧检查暂停状态并调整动画速率，而非依赖 completion 回调
- 林澈 NPC 冷调材质在预构建阶段（`setupMirrorScene()`）完成，避免在帧渲染中动态创建 `SCNMaterial` 造成卡顿
- `colorTemperatureFlip` 过渡中途若应用失焦，需将归一化进度写入 `ScenePresentationState.transition` 并在恢复时传给 `ColorTemperatureAnimator`；不得从 0 重新开始
- 镜像空间作为走廊根的子节点，章节切换时只隐藏 `mirrorRoot` 而非销毁节点，避免重复构建开销
