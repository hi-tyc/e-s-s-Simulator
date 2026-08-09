# F-04 叙事相机模式与场景呈现

> 状态：final / accepted
> 实现阶段：Phase 0
> 依赖特性：F-01（叙事状态机与章节进度）

## 产品能力描述

本特性为六章叙事游戏提供统一的相机模式体系和场景根节点管理，使 `ClassroomCoordinator` 能根据 `ScenePresentationState` 单向映射出六种视角体验（固定座位、引导第三人称、镜像空间等），并以三阶段转场协议（prepare → commit → cleanup）在章节切换时安全地激活/停用场景根节点。

## 功能边界

**包含：**
- `NarrativeCameraMode` 枚举定义（6 种模式）及各模式的相机参数约定
- `ScenePresentationState` 数据结构定义，作为 `ClassroomCoordinator` 唯一相机/场景输入
- `SceneTransition` 枚举定义（fade / colorTemperatureFlip / mirrorRipple）及持续时间
- 场景根节点显示/隐藏调度规则：任一时刻只激活当前章根节点及转场所需的相邻根节点
- `prepare → commit → cleanup` 三阶段转场协议及其原子性保证
- `ScenePresentationState` 进入 `NarrativeSave` 的存档与恢复规范
- `liquidGlassPanel` 提升为模块共享 View modifier 的先决条件拆解

**不包含：**
- 具体场景的 3D 资产（走廊、镜像空间、楼梯间、咨询室的 SCNNode 内容）
- NPC 动画和路径（属于各章特性）
- 微游戏 overlay（F-12）
- 引导第三人称的移动与碰撞逻辑（F-13）
- 具体章节的 Beat 注册（F-05 及后续各章特性）

## 验收标准

- [ ] 切换 `ScenePresentationState.cameraMode` 后，`ClassroomCoordinator` 在下一帧 `update(game:)` 调用中正确重配相机锚点、FOV 和视角限制，无需外部再触发
- [ ] 执行任意场景转场时，旧章热点在 `prepare` 阶段关闭，新章热点在 `commit` 完成后才开放，不允许两章热点同时可交互
- [ ] 应用在转场进行中失焦或终止，恢复时回到转场前最近稳定检查点（`commit` 前的旧检查点或 `commit` 后的新检查点），不出现相机/场景状态残留
- [ ] 从任意 `ScenePresentationState` 存档点恢复，`ClassroomCoordinator` 能确定性重建对应相机模式、场景根可见性和互动热点集合，不依赖保存时的 SCNNode 引用或 Timer
- [ ] `Reduce Motion` 开启时，`colorTemperatureFlip` 和 `mirrorRipple` 转场退化为 0.2–0.4 秒 `fade`，转场完成判定和时长不变
- [ ] `liquidGlassPanel` 已提升为 `LateStudySimulator` 模块内共享 View modifier，`MainQuestHUD` 等拆分文件可直接使用而不复制样式实现

## 设计约束

- `ScenePresentationState` 是 `ClassroomCoordinator` 唯一允许读取的相机/场景状态源；`ClassroomCoordinator` 不持有任何叙事进度字段，也不直接持有 `MainQuestProgress` 或 `GameNarrativeState`。
- 镜像空间不得复制整个 `SCNScene`，必须作为走廊场景中的独立节点根，通过可见性、灯光和材质切换实现。
- 场景切换的状态持久化必须在 `commit` 阶段以一次原子事务写入（章节、检查点、相机模式、目标 ID），不允许先切场景后异步补状态。
- `NarrativeCameraMode` 不替换现有 `CameraPose`；`CameraPose` 继续描述玩家的视线朝向（left/right/forward/desk），`NarrativeCameraMode` 描述当前的运动和视角控制方式。两者共存于 `ScenePresentationState` 和 `GameManager` 的不同层次。
- 新的场景根节点和相机逻辑由 `ClassroomCoordinator.update(game:)` 单向映射驱动；导演（SceneDirector）不直接持有或操作 SCNNode。
