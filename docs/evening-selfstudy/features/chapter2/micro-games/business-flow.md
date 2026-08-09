# F-12 三灯微游戏 — 业务流程

> 状态：final / accepted

## 主流程

```mermaid
flowchart TD
    Start([第二章步骤 3 激活\n草稿灯出现]) --> NearDraft{玩家靠近\n草稿灯 ≤1.5m?}

    NearDraft -->|是| OpenDraft[presentMicroGame .draft\noverlay 淡入 0.3s\nDraftLineMicroGame 显示]
    NearDraft -->|18min 软上限\n二次提示后| ShowAutoBtn1["由苏念慢慢完成"\n按钮出现]
    ShowAutoBtn1 --> CompleteDraft

    OpenDraft --> DraftLoop{描线 ≥80%?}
    DraftLoop -->|偏差过大| RetryDraft[虚线重置\n提示"慢一点也没关系"]
    RetryDraft --> DraftLoop
    DraftLoop -->|是| CompleteDraft[completeMicroGame .draft\noverlay 淡出\n灯光 50→400 intensity\n光路出现]

    CompleteDraft --> NearMelody{玩家沿光路\n到达旋律灯 ≤1.5m?}
    NearMelody -->|是| OpenMelody[presentMicroGame .melody\n4 音符依次播放]
    NearMelody -->|超时| ShowAutoBtn2["由苏念完成"按钮]
    ShowAutoBtn2 --> CompleteMelody

    OpenMelody --> MelodyLoop{按正确顺序?}
    MelodyLoop -->|错误| CheckAttempt{attemptCount < 3?}
    CheckAttempt -->|是| ReplayMelody[重播旋律\nattemptCount++]
    ReplayMelody --> MelodyLoop
    CheckAttempt -->|≥3 次| AutoPass[isAutoPass = true\n自动通过]
    AutoPass --> CompleteMelody
    MelodyLoop -->|正确| CompleteMelody[completeMicroGame .melody\n全旋律响起\n暖色人声引入\n光路延伸]

    CompleteMelody --> NearErase{玩家到达\n擦痕灯 ≤1.5m?}
    NearErase -->|是| OpenErase[presentMicroGame .comparison\n比较文字浮现 SCNAction]
    NearErase -->|超时| ShowAutoBtn3["由苏念完成"按钮]
    ShowAutoBtn3 --> CompleteErase

    OpenErase --> EraseLoop{擦除面积 ≥60%?}
    EraseLoop -->|未达阈值| ContinueErase[继续擦\n保留剩余 40%]
    ContinueErase --> EraseLoop
    EraseLoop -->|是| CompleteErase[completeMicroGame .comparison\n三灯全亮\n暖色偏移 0→20%\n林澈 NPC 转过身]

    CompleteErase --> AllLit([三灯全亮\nCh2State.currentLight = nil\n步骤 7 对话激活])
```

## 边界与兜底

**暂停/应用失焦**：overlay 可见时 `activePauseReasons` 包含 `.microGame`；应用失焦时再叠加 `.appInactive`。Beat 冻结，overlay 内计时停止。恢复时只移除对应原因，`.microGame` 保留直到玩家操作。描线/旋律/擦除的当前进度（未完成灯）在内存中保留，不因暂停丢失。

**读档恢复**：`activeMicroGame` 不存档，读档后 overlay 关闭。若 `Ch2State.currentLight` 非 nil（灯未完成），玩家重新走近该灯即可再次触发 overlay；当次微游戏进度（描线比例、旋律次数、擦除面积）不恢复，需重新开始，无失败惩罚。

**幂等保证**：玩家完成与"由苏念完成"按钮在同一帧触发时，`completeMicroGame` 内部检查 `completedLights.contains(id)`，已包含则直接 return，不重复写入。

**键盘替代输入（F-07 提供开关）**：
- 描线：Tab 在折线锚点间切换，空格确认锚点，全部锚点确认 = 100% 完成
- 擦除：按住空格自动缓慢擦除（约 5%/秒），达 60% 自动完成
- 旋律：键盘 1-4 对应四个音高按钮；提供"再听一次"按钮

**Reduce Motion**：overlay 淡入淡出保持 0.3s；描线路径动画与旋律音符高亮改为即时状态切换；完成判定逻辑不受影响。

## 与其他特性的交互点

| 时机 | 调用方 | 被调用方 | 说明 |
|---|---|---|---|
| 玩家走近某灯 | `ClassroomCoordinator.update(game:)` 距离检测 | `GameManager.presentMicroGame(_:)` | Coordinator 在 update 循环中判断距离，不直接操作 overlay |
| 微游戏完成 | `MicroGameOverlayView` 子视图回调 | `GameManager.completeMicroGame(_:)` | overlay 只通过闭包/binding 通知，不直接写 `Ch2State` |
| overlay 可见性变化 | `GameManager.activeMicroGame` @Published | `ContentView` ZStack + `activePauseReasons` | ContentView 读取属性控制 overlay 显隐；GameManager 同步管理暂停原因 |
| 灯光/节点更新 | `GameManager` 写入 `Ch2State.completedLights` | `ClassroomCoordinator.update(game:)` | 单向映射，Coordinator 下一帧读取后更新 `SCNLight.intensity` 和光路节点 |
| 三灯全亮后 | F-12 完成（`completedLights == allCases`） | 第二章步骤 7 对话系统 | 本特性完成是步骤 7-8 的前置门禁；`currentLight == nil` 作为解锁条件 |
| 读档恢复 | `GameManager.loadNarrativeSave()` | `ClassroomCoordinator` 重建场景 | Coordinator 依据 `completedLights` 确定性重建灯光强度、光路节点和林澈 NPC 朝向 |
| 辅助设置变更 | F-07（辅助设置面板） | `MicroGameOverlayView` | 键盘替代输入开关从 F-07 读取，overlay 中动态切换输入模式 |
