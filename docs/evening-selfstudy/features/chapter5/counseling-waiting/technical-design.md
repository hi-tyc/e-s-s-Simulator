# F-18 咨询室等候与隐私保护 — 技术设计

> 状态：final / accepted

## 实现方案

章节入口从 `GameNarrativeState.safetyRoute` 唯一映射 `Ch5State.entryMode`，由 `GameManager.startChapter(.counseling)` 在完成门禁校验后立即写入，任何后续步骤不得修改此值。`SceneDirector` 根据 `entryMode` 注册不同 Beat 集合，驱动三条独立的场景路线。

等候区沿用第一章的固定坐姿相机逻辑（`NarrativeCameraMode.waitingSeated`），只替换场景根节点和受限视角锚点。玩家靠近咨询室门时由 `ClassroomCoordinator.update(game:)` 检测距离阈值并触发 camera pull-back SCNAction，不需要额外 SwiftUI 逻辑。

流言事件由 `RumorEventDirector` 处理：NPC 路过动画 + 对话气泡 + 20 秒选项窗口，选项通过 `completeStep` 幂等提交 `rumorOutcome`。超时自动提交 `.contained`（不回应路径）。班长在场（`companionChoice == .zhouYuAn`）时 SceneDirector 在选项窗口打开前插入额外 Beat，由周予安自动说台词，压力减轻但不取消玩家输入窗口。

偏见便签由 `BiasCardSystem` 驱动：监听 `scenePresentation.objectiveTargetID` 的 NPC 路过事件，在余光 VisionZone 激活时随机（ ≤2 条预设语句中尚未触发的）触发一次。触发后生成左侧滑入 `BiasCardView`，复用 `liquidGlassPanel`。

同伴消息通过 HUD 通知呈现（不使用手机振动），消息文本根据 `companionChoice` 选择对应台词，回复选项提交后写入 `companionMessageReplied = true`。

"主线完成"反馈使用 `QuestCompleteHUD`：HUD 区域文字平滑替换，不弹框，保持 8 秒后收起。两行文字使用 SwiftUI `withAnimation(.easeInOut(duration: 0.3))` 依次淡入。

三条路线共用 `handoffConfirmed` 完成门禁，差别只在触发 Beat 的来源（江越离开 / 心理老师轮班确认 / 方老师紧急接管确认）。完成后以同一幂等 `completeStep` 原子写入 `handoffConfirmed`、`supportHandedOff`、`farewellChoice`（标准路线）。

## 关键类型与接口

```
struct Ch5State: Codable, Equatable
enum RumorOutcome: String, Codable          // unknown / suppressed / contained
enum CounselingEntryMode: String, Codable   // standardWaiting / urgentHandoffWaiting / emergencyClosure
class RumorEventDirector                    // GameManager 内部协作者，不持有剧情状态
struct BiasCardSystem                       // 偏见便签触发与去重逻辑
struct BiasCardView: View                   // 左侧滑入卡片，liquidGlassPanel
struct QuestCompleteHUD: View               // 主线完成 HUD 文字替换
func GameManager.startChapter(.counseling)  // 校验并写入 entryMode
func GameManager.completeStep(_:result:)    // 幂等提交步骤结果（复用全局接口）
```

`RumorEventDirector` 和 `BiasCardSystem` 作为 `GameManager` 的内部值类型协作者，不暴露为可观察对象，不直接操作 SCNNode。

## iPad 适配注意事项

本特性无特定 iPad 约束，遵循全局 `PlatformViewRepresentable` 规范即可。

等候区固定视角的 HUD 布局在宽屏幕下可能需要调整 `BiasCardView` 的左侧锚点偏移（当前设计为屏幕左侧固定百分比），开发时留意大屏适配。

## 与现有代码的关系

**复用：**
- `NarrativeCameraMode.waitingSeated`（第一章固定坐姿逻辑，换场景根节点）
- `CameraPose`（`.left/.right/.forward/.desk`，等候区可用子集）
- `liquidGlassPanel` UI 辅助器（偏见便签、科普卡、选项面板）
- `InnerMonologue` 触发逻辑（偏见便签和科普卡复用显示路径）
- `completeStep(_:result:)` 幂等提交接口
- `activePauseReasons` 多重暂停管理（F-02 SceneDirector 职责）
- `CompanionNPC`（F-14）在等候区的位置状态

**修改：**
- `GameManager.startChapter(.counseling)`：新增 `safetyRoute → entryMode` 映射与一致性校验
- `ClassroomCoordinator.update(game:)`：新增等候区场景根节点映射、门距离检测与 pull-back SCNAction

**新增：**
- `RumorEventDirector`（内部协作者）
- `BiasCardSystem` + `BiasCardView`
- `QuestCompleteHUD`
- 等候区场景根节点（咨询室走廊、支持室走廊、安全办公室走廊，三个独立 SCNNode 根）

## 风险与注意事项

- `entryMode` 与 `safetyRoute` 一致性校验必须在 `startChapter` 时执行，不能依赖 UI 层防护；读档路径同样需要校验
- 即时危险路线（`.emergencyClosure`）江越不再出镜，开发时确保 `jiangYueEntered` 和 `jiangYueExited` 在此路线不作为完成门禁，只有 `handoffConfirmed` 是全局门禁
- 流言事件 20 秒窗口与 SceneDirector 节拍冻结交互：若暂停发生在窗口内，剩余时间须冻结；恢复后继续倒计时，不重置为 20 秒
- 偏见便签触发依赖 NPC 路过事件，即时危险路线无路过 NPC，需确保 `BiasCardSystem` 不在此路线触发（改为方老师提醒台词替代）
- "主线完成" HUD 显示期间（8 秒），若应用失焦则 HUD 文字应保持，不因暂停被清除
