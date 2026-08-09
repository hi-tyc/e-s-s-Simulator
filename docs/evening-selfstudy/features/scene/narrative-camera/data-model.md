# F-04 叙事相机模式与场景呈现 — 数据模型

> 状态：final / accepted

## 新增类型

### `NarrativeCameraMode`

```
enum NarrativeCameraMode: String, Codable, Equatable, CaseIterable
```

| case | 使用章节 | 说明 |
|---|---|---|
| `seatedFirstPerson` | 序章、第一章、部分第二章 | 固定第三排座位，270° 坐姿视角限制，不可 leaveSeat |
| `freeRoamFirstPerson` | （预留） | 自由行走第一人称，当前无章节使用 |
| `guidedThirdPerson` | 第三、四章 | 相机跟随玩家，WASD 移动，碰撞由 F-13 实现 |
| `dialogueFirstPerson` | 第四章楼梯间对话 | 第一人称固定站立，位移冻结，环境动画继续 |
| `mirrorFirstPerson` | 第二章镜像空间 | 第一人称，色温冷调，镜像节点根激活 |
| `waitingSeated` | 第五章等候区 | 固定坐姿，相机锚点独立，受限视角（left/right/board/desk 可切，不可 leaveSeat） |

Codable 要求：使用 `RawRepresentable` String，无关联值，版本升级可直接添加 case。

---

### `ScenePresentationState`

```
struct ScenePresentationState: Codable, Equatable
```

| 字段 | 类型 | 说明 |
|---|---|---|
| `chapter` | `ChapterID` | 当前激活章节，必须与 `quest.currentChapter` 一致 |
| `cameraMode` | `NarrativeCameraMode` | 当前相机控制方式 |
| `activeSceneRootID` | `String` | 当前激活的场景根节点 ID（如 `"classroom"`, `"corridor"`, `"stairwell"`） |
| `transition` | `SceneTransition?` | 转场进行中时非空；`commit` 完成后由 `cleanup` 阶段清空 |
| `objectiveTargetID` | `String?` | 当前目标热点节点 ID，供 Coordinator 渲染高亮；可为空 |

Codable + Equatable，进入 `NarrativeSave`。

---

### `SceneTransition`

```
enum SceneTransition: Codable, Equatable
  case fade(duration: TimeInterval)
  case colorTemperatureFlip(duration: TimeInterval)
  case mirrorRipple(duration: TimeInterval)
```

关联值 `duration: TimeInterval` 用 `Codable` 自动合成。`Reduce Motion` 模式下由调用方将 `colorTemperatureFlip` 和 `mirrorRipple` 替换为 `fade(duration: 0.3)`，替换发生在 `prepareTransition` 入口。

---

### `ColorTemperatureAnimator`（内部辅助，不进存档）

```
struct ColorTemperatureAnimator
  func animate(from light: SCNLight, toTemperature: CGFloat, duration: TimeInterval)
  func reset(light: SCNLight)
```

运行时状态，不 Codable，不进入 `NarrativeSave`；恢复时由 `ClassroomCoordinator` 依据 `ScenePresentationState` 确定性重建。

---

## 存档策略

进入 `NarrativeSave`（key `LateStudySimulator.NarrativeSave.v1`）的字段：

| 字段 | 存档 | 说明 |
|---|---|---|
| `ScenePresentationState.chapter` | ✅ | 章节一致性校验必需 |
| `ScenePresentationState.cameraMode` | ✅ | 恢复后 Coordinator 据此重建相机 |
| `ScenePresentationState.activeSceneRootID` | ✅ | 恢复后据此激活正确场景根 |
| `ScenePresentationState.transition` | ⚠️ 仅存 nil | 存档只落在稳定检查点（commit 前旧点或 commit 后新点），进行中的转场不落档 |
| `ScenePresentationState.objectiveTargetID` | ✅ | 恢复后重建目标高亮 |
| `ColorTemperatureAnimator` 状态 | ❌ 运行时 | 由 Coordinator 依 `cameraMode` + `chapter` 确定性重建 |
| SCNNode 引用、Timer、CAAnimation | ❌ 运行时 | 不进存档，恢复时确定性重建 |

存档 key 继承自 `NarrativeSave`：`LateStudySimulator.NarrativeSave.v1`（不新增独立 key）。

## 数据一致性约束

- `ScenePresentationState.chapter` 必须与 `MainQuestProgress.currentChapter` 保持一致，二者在同一 `commit` 事务中写入，恢复时若不一致则校验失败，回退 `lastValid`。
- `activeSceneRootID` 必须是 `ClassroomCoordinator` 能够构建或已持有的合法 ID；非法值在 `prepareTransition` 入口断言失败，不进入 `commit`。
- `transition` 字段在存档中始终为 `nil`；若读取到非 nil 值说明存档在转场中途被截断，按损坏存档处理（优先恢复 `lastValid`）。
- `NarrativeCameraMode` 新增 case 时须在迁移器中为旧版本提供默认映射（如旧版无 `waitingSeated` 时回落到 `seatedFirstPerson`），不得解码失败直接崩溃。
