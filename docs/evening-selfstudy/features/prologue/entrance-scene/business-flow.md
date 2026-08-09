# F-06 校门/走廊新场景与入场演出 — 业务流程

> 状态：final / accepted

## 主流程

```mermaid
flowchart TD
    A([游戏启动 / 新档开始序章]) --> B{是否已完成序章？}
    B -- "是（二周目）" --> B1[显示"进入序章/直接第一章"选项]
    B1 -- 选直接第一章 --> Z([第一章开始])
    B1 -- 选进入序章 --> C
    B -- 否 --> C

    C[SceneDirector 注册 prologueBeatID.gateArrival\nactiveSceneRootID = gateExterior\n输入限制：仅暂停/设置] --> D

    D["段落 0：校门外受控演出\n苏念旁白 + NPC 入楼\n相机沿 GateArrivalSequence 推进"]

    D --> E{gateArrival 演出完成？}
    E -- "是（约 55 秒自然结束）" --> F
    E -- "暂停" --> P1[冻结演出计时\n环境循环继续]
    P1 --> D

    F[幂等提交 completePrologueBeat.gateArrival\n写入 completedBeatIDs\n自动存档检查点\nSceneTransition.fade 切换到走廊\nactiveSceneRootID = corridor]

    F --> G[SceneDirector 注册 lookDownHall Beat\nfallbackDelay = 12s\nHUD：当前目标"看向走廊尽头"]

    G --> H{玩家操作或 12 秒兜底}

    H -- "玩家转向目标区域并停留 ≥ 1s" --> I[聚焦反馈：画面边缘轻微暖光\n苏念旁白：有时候你先看见的只是一个人比平常安静]
    H -- "12 秒未操作" --> J[SceneDirector 触发：苏念自然转头\nHUD：你注意到了走廊里的动静\nflags = autoCompleted]

    I --> K
    J --> K

    K[幂等提交 completePrologueBeat.lookDownHall\nPrologueState.lookTutorialCompleted = true\n写入 completedBeatIDs\n自动存档检查点]

    K --> L[继续序章段落 2（returnToSeat）\n由 F-05 Beat 状态机接管]
    L --> M([最终衔接第一章])
```

## 边界与兜底

| 异常路径 | 处理方式 |
|---|---|
| 段落 0 演出进行中应用失焦（`appInactive`） | `activePauseReasons` 插入 `.appInactive`，演出时间冻结；重新获焦后移除原因，从剩余时间继续，不重新播放 |
| 段落 0 演出进行中系统休眠 | 同上，插入 `.systemSleep` |
| 读档时 `pendingBeatRemainingTimes["prologue.gateArrival"]` 有值 | 从剩余时间重建演出进度，相机从距结束最近的稳定锚点重放，不从头开始 |
| 读档时 `gateArrival` 已在 `completedBeatIDs` | 跳过段落 0，直接从走廊检查点恢复，不重演校门外演出 |
| 读档时场景一致性校验失败（`activeSceneRootID` 与 `completedBeatIDs` 不匹配） | 拒绝恢复当前槽，优先载入 `lastValid`；若也不可用，从 `gateExterior` 入口重建 |
| 玩家在段落 0 期间尝试移动或交互 | 输入被静默忽略（不弹提示），保持演出流畅 |
| 玩家在段落 1 视角停留判定未到阈值时暂停再恢复 | 12 秒兜底计时从冻结点恢复；停留计时不保存，从 0 重新计算（玩家需再次转向） |

## 与其他特性的交互点

| 时机 | 交互方向 | 说明 |
|---|---|---|
| F-05 注册 `gateArrival` Beat | F-05 → F-06 | F-05 的 Beat 状态机触发本特性演出逻辑开始 |
| 段落 0/1 完成后写入 `completedBeatIDs` | F-06 → F-01 | 通过 `GameManager.completeStep` 幂等提交，F-01 的状态机记录 |
| 走廊场景根节点 (`corridorRoot`) | F-06 ← F-11 | F-11（镜像空间）在第二章复用本特性创建的走廊根节点，并切换为镜像材质；F-06 应在 `CorridorSceneBuilder` 中预留镜像材质接口 |
| 相机锚点切换 | F-06 → F-04 | 使用 F-04 定义的 `ScenePresentationState` 和 `SceneTransition`；`NarrativeCameraMode` 在段落 0 为内部演出模式（相机由 `CinematicCameraSequence` 控制），段落 1 切回 `seatedFirstPerson` 的受限变体 |
| 辅助字幕显示 | F-06 → F-07 | 段落 0/1 期间的环境声方向字幕通过 F-07 辅助设置面板的字幕开关控制；F-06 只提供字幕内容数据，渲染由 F-07 负责 |
| `lookTutorialCompleted` 写入 | F-06 → F-05 | 通知 F-05 视角教学已完成，第一章不再弹出基础视角提示 |
