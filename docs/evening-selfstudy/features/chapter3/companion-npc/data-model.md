# F-14 同伴 NPC 系统 — 数据模型

> 状态：final / accepted

## 新增类型

### CompanionFollowBehavior
```
struct CompanionFollowBehavior
  targetDistance: Float       // 跟随目标间距，固定 1.5m
  currentPhase: CompanionPhase // 当前行为阶段
  anchorNodeID: String?        // 差异行为锚点（第四章入口/角落）
```
不需要 Codable（纯运行时，不进存档）。

### CompanionPhase
```
enum CompanionPhase
  case idle           // NPC 初始状态，在教室门口/走廊等候
  case following      // 跟随玩家，第三章步骤 4 选择后进入
  case positioned     // 已到达差异位置锚点（第四章楼梯间内）
  case standby        // 第五章等候区，随时响应流言 Beat
```
不需要 Codable（不进存档，Coordinator 按 checkpointID 重建）。

### CompanionNPCNodes
```
struct CompanionNPCNodes
  rootNode: SCNNode
  bodyNode: SCNNode
  idleAnimationKey: String
  followAnimationKey: String
```
不需要 Codable（SceneKit 节点不进存档）。

### CompanionBeatID
```
enum CompanionBeatID: String, Codable, CaseIterable
  case ch4EnterStairwell      // 第四章进入楼梯间后，同伴分叉定位
  case ch4ContactAdult        // 第四章步骤 6，联络方老师
  case ch5HandleRumor         // 第五章步骤 3，周予安主动处理流言（许栀不触发）
```
Codable，用于 `SceneDirectorBeatDefinition.actionID`。

### CompanionStatusIcon（SwiftUI View）
```
struct CompanionStatusIcon: View
  companionChoice: CompanionID  // 读取 GameNarrativeState
```
纯展示，不持有独立状态。

## 存档策略

进入 `NarrativeSave` 的字段：
- `GameNarrativeState.companionChoice`（`CompanionID`）：跨章核心选择，存档 key 随 `NarrativeSave.v1` 整体持久化

不进存档的运行时状态：
- `CompanionFollowBehavior`（纯计算，按 checkpointID 重建）
- `CompanionNPCNodes`（SCNNode，由 Coordinator 重建）
- `CompanionPhase`（由 checkpointID 映射重建）

**重建规则**：读档后，`ClassroomCoordinator` 依据 `quest.currentChapter`、`quest.currentStep` 和 `companionChoice` 确定性重建同伴所在锚点和 `CompanionPhase`。不需要额外存档字段。

存档 key：统一在 `LateStudySimulator.NarrativeSave.v1`，无独立 key。

## 数据一致性约束

- `companionChoice` 在第三章步骤 4 通过 `completeStep` 一次性写入后不可更改；任何尝试第二次修改该字段的调用必须被 `GameManager` 忽略并记录日志
- 进入第四章的章节门禁校验：`companionChoice != .none`，不满足时 `transitionChapter` 拒绝转移并保持第三章当前状态
- `safetyRoute` 和 `adultNotified` 的值与 `companionChoice` 无直接绑定——无论选哪位同伴，成人交接都必须完成；同伴只影响节奏和空间感，不影响最终安全结果
