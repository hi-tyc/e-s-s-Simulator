# F-06 校门/走廊新场景与入场演出 — 技术设计

> 状态：final / accepted

## 实现方案

在 `ClassroomCoordinator` 中新增两个场景根节点：`gateExteriorRoot` 和 `corridorRoot`，通过 `ScenePresentationState.activeSceneRootID` 的值控制显示/隐藏，不复制 `SCNScene` 对象。入场演出（`gateArrival` Beat）期间，`SceneDirector` 按时间序列驱动苏念 NPC 路径动画和相机锚点切换；`ClassroomCoordinator.update(game:)` 单向读取 `GameManager` 发布的 `ScenePresentationState` 来更新 SceneKit 节点，不持有任何剧情状态。

走廊视角教学（`lookDownHall` Beat）将输入控制权交还玩家，`GameManager` 通过 `dwellTimer` 判断玩家视角是否已对准目标区域并保持足够停留，满足条件后调用幂等的 `completePrologueBeat(.lookDownHall)`。12 秒兜底由 SceneDirector 的 `fallbackDelay` 触发，执行苏念自然转头的 SCNAction 后以 `flags: ["autoCompleted"]` 提交同一条幂等路径。

场景过渡（校门外 → 走廊 → 教室）使用 `SceneTransition.fade(duration: 0.4)` 三阶段提交（`prepare` 预载下一根节点但不开放热点，`commit` 切换状态事务，`cleanup` 卸载旧根节点），保证自动存档落在稳定检查点而非过渡帧。

## 关键类型与接口

新增类型和方法（不写具体实现）：

- `GateExteriorSceneBuilder`：程序化构建校门外 SCNNode 树，返回根节点，供 `ClassroomCoordinator` 持有
- `CorridorSceneBuilder`：程序化构建走廊 SCNNode 树（含方老师、班长 NPC 占位节点和走廊尽头目标锚点），返回根节点
- `ClassroomCoordinator.gateExteriorRoot: SCNNode`
- `ClassroomCoordinator.corridorRoot: SCNNode`
- `ClassroomCoordinator.updateEntranceScene(presentation: ScenePresentationState)` — 在 `update(game:)` 中调用，根据 `activeSceneRootID` 显示/隐藏对应根节点
- `CinematicCameraSequence`：值类型，包含按时间序列排列的相机锚点列表和每段时长，由 SceneDirector Beat 持有并驱动
- `GateArrivalSequence: CinematicCameraSequence`（校门外演出的具体锚点定义）
- `PrologueBeatID.gateArrival` 和 `.lookDownHall`（已在 F-05 定义，本特性实现其对应的演出逻辑）
- `GameManager.handleLookDownHallDwell(pose: CameraPose, elapsed: TimeInterval)`：视角停留判定入口，内部调用 `completeStepIfDwellMet`

已有类型的扩展：
- `ScenePresentationState.activeSceneRootID` 新增合法值 `"gateExterior"` 和 `"corridor"`
- `ClassroomCoordinator.update(game:)` 扩展以调用 `updateEntranceScene`

## iPad 适配注意事项

本特性无特定 iPad 约束，遵循全局 `PlatformViewRepresentable` 规范即可。

场景根节点和 `CinematicCameraSequence` 均为数据驱动，相机锚点坐标不硬编码屏幕尺寸，天然支持不同分辨率。若 F-21 激活后需要适配触屏输入（触屏视角转动替代鼠标），`lookDownHall` 的停留判定逻辑本身不需修改，只需在输入层增加触屏手势映射。

## 与现有代码的关系

复用：
- `ClassroomCoordinator`（扩展，不重命名）
- `ScenePresentationState` 和 `SceneTransition`（已在 F-04 新增，本特性直接使用）
- `PrologueBeatID`（已在 F-05 定义，本特性实现 `gateArrival`/`lookDownHall` 两个 Beat 的 SceneKit 演出）
- `SpatialAudioManager`（扩展 `AudioCueKind` 新增 `.footsteps`/`.doorAxis`/`.broadcastTest` 等序章专用短音；缺失时程序化回退）
- `liquidGlassPanel` 等 UI 辅助器（HUD 极简态复用同一面板，不新增样式）

修改：
- `ClassroomCoordinator.update(game:)` — 新增入场场景的分支处理
- `GameManager` — 新增 `lookDownHall` 停留判定逻辑和 `gateArrival` 演出推进钩子

新增：
- `GateExteriorSceneBuilder.swift`
- `CorridorSceneBuilder.swift`
- `CinematicCameraSequence.swift`（若多章复用，可放在 `Features/Scene/` 公共目录）

## 风险与注意事项

- 校门外和走廊是首批程序化新场景，场景细节丰富度直接影响代入感；若后续引入外部 3D 资产，需重新对齐锚点坐标，建议从开始就把锚点定义提取为常量
- `gateArrival` 演出时长约 55 秒，是全流程最长的单一受控演出段；SceneDirector `fallbackDelay` 应设为演出总时长，不得提前触发
- 两个新根节点首次激活时的帧耗时需在真机 macOS 环境测试；若超过 100ms 需在 `prepare` 阶段预热
- `lookDownHall` 停留判定与 F-08（`dwellTimer`）共享机制；F-08 未完成时本特性需内联临时判定，待 F-08 完成后迁移，避免双重逻辑
- 走廊场景在第二章（F-11 镜像空间）也会使用；提前在 `CorridorSceneBuilder` 中预留镜像材质切换接口，避免第二章时大范围重构
