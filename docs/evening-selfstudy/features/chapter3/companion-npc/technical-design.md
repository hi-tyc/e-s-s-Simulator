# F-14 同伴 NPC 系统 — 技术设计

> 状态：final / accepted

## 实现方案

同伴 NPC 系统由三部分协作：选择触发、跟随运动和差异行为。

**选择触发**：第三章步骤 4 在教室门口/走廊各有一个 NPC 交互热点（由 `F-13` 提供的热点交互机制触发）。玩家走近（≤1.5m）并按确认键后，`GameManager.completeStep` 以一次幂等提交将 `companionChoice` 写入 `GameNarrativeState`。选择后 NPC 切换为跟随状态。

**跟随运动**：`CompanionFollowBehavior` 是一个运行时纯计算组件，由 `ClassroomCoordinator.update(game:)` 每帧驱动。它读取玩家当前位置，使用 SceneKit `SCNAction` 路径序列让同伴保持约 1.5m 间距跟随，并在路径点变化时更新 `SCNNode` 移动动画。跟随逻辑不持有剧情状态，只依赖场景几何和玩家位置。

**差异行为**：第四章和第五章的同伴行为通过 `SceneDirector` 中预定义的 `CompanionBeatID` 触发。`ClassroomCoordinator` 依据 `companionChoice` 和当前 `checkpointID` 选择对应的 NPC 动画和台词，在章节入口或特定步骤时确定性执行。方老师联络路径（电话 vs 消息）差异通过不同 Beat 定义分支表达，都调用同一个 `completeStep` 完成安全交接标记。

HUD 右下角同伴图标由 `ContentView` 直接读取 `GameNarrativeState.companionChoice` 渲染，不需要额外状态。

## 关键类型与接口

```swift
// 新增：同伴 NPC 行为组件，由 ClassroomCoordinator 持有和驱动
struct CompanionFollowBehavior

// 新增：同伴场景节点容器，每名 NPC 一套
struct CompanionNPCNodes

// 新增：同伴行为 Beat 标识
enum CompanionBeatID: String, Codable, CaseIterable

// 新增：同伴 HUD 图标组件
struct CompanionStatusIcon: View

// 修改：ClassroomCoordinator.update(game:) — 新增同伴节点映射分支
func update(game: NarrativeQuestManaging)

// 修改：GameManager.completeStep — 同伴选择步骤写入 companionChoice
func completeStep(_ stepID: String, result: QuestStepResult)
```

## iPad 适配注意事项

本特性无特定 iPad 约束，遵循全局 PlatformViewRepresentable 规范即可。同伴图标使用标准 SwiftUI 视图，字号跟随系统辅助字号缩放，热点宽容半径（1.5m）在 iPad 触控场景下不需要额外调整，因判定在 3D 场景坐标系内完成。

## 与现有代码的关系

**复用**：
- `ClassroomCoordinator.update(game:)` 的单向映射模式；新增同伴节点分支，不拆分已有结构
- `GameNarrativeState.companionChoice`（类型已在全局数据模型定义）
- `CompanionID` 枚举（已在 `GameModels.swift` 全局数据模型中定义）
- `SceneDirectorBeatDefinition` / `BeatActionID` 框架（F-02 已实现）
- `liquidGlassPanel` 辅助器用于同伴图标背景

**修改**：
- `ClassroomCoordinator`：新增 `CompanionNPCNodes` 容器和 `updateCompanionFollow` 方法
- `GameManager`：在第三章步骤 4 的 `completeStep` 路径中写入 `companionChoice`

**新增**：
- `CompanionFollowBehavior` 结构体
- `CompanionNPCNodes` 节点容器
- `CompanionBeatID` 枚举（第四、五章差异行为 Beat）
- `CompanionStatusIcon` SwiftUI 视图

## 风险与注意事项

- NPC 路径跟随在走廊和楼梯间的碰撞处理需要与 F-13 的碰撞系统联合调试，避免同伴卡墙
- 周予安和许栀在第四章的位置差异（入口 vs 角落）需要在楼梯间场景几何确定后才能固定锚点坐标，建议阶段 4 场景搭建后再填写具体坐标
- 第五章周予安自动处理流言的 Beat 需与玩家手动选择时机竞争——必须保证 `completeStep` 幂等，不可重复提交 `rumorHandled`
- `companionChoice` 一旦写入不可更改，存档迁移时若该字段缺失须默认降级到兜底路径（方老师仍会介入），不得让 `Ch4State.adultContactInitiated` 依赖同伴类型才能为 `true`
