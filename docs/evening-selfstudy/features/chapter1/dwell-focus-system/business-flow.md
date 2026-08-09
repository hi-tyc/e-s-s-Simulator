# F-08 视角停留判定与聚焦反馈 — 业务流程

> 状态：final / accepted

## 主流程

```mermaid
flowchart TD
    A([帧更新 update game]) --> B{cameraMode ==\nseatedFirstPerson?}
    B -- 否 --> Z([跳过，不计时])
    B -- 是 --> C{activePauseReasons\n非空?}
    C -- 是 --> D([冻结：不增加 dwellAccumulated])
    C -- 否 --> E{currentPose ==\ndwellFocus.activePose?}
    E -- 否，姿态切换 --> F[activePose = currentPose\ndwellAccumulated = 0]
    F --> G([等待下一帧])
    E -- 是 --> H[dwellAccumulated += deltaTime\n上限截断 delta ≤ 0.1s]
    H --> I{dwellAccumulated >=\nDwellThreshold[activePose]?}
    I -- 否 --> G
    I -- 是 --> J{activePose 已在\ntriggeredInCurrentStep?}
    J -- 是，已触发 --> G
    J -- 否 --> K[写入 triggeredInCurrentStep]
    K --> L[发布 focusFeedbackTrigger\n启动暖光 overlay + FOV 推近]
    L --> M[GameManager.completeStep\ncurrentStepID 幂等提交]
    M --> N{completeStep 实际\n写入了新结果?}
    N -- 是 --> O[SceneDirector 取消本步骤\n剩余兜底 Beat]
    N -- 否，已存在结果 --> G
    O --> P([步骤完成，HUD 切换下一目标])
```

## 边界与兜底

**玩家不操作（不转向目标方向）**
- 30 秒后 SceneDirector（F-02）触发强化引导 HUD，播放方向字幕
- 90 秒后 SceneDirector 触发兜底 Beat，以 `flags = ["softNoticed"]` 提交同一步骤结果
- 兜底路径与停留路径最终都调用同一 `completeStep`，幂等保证只写一次

**玩家在阈值前切换视角**
- `activePose` 更新，`dwellAccumulated` 归零
- 历史积累时间不保留；重新停留需从 0 计时
- 该行为是设计意图（"转头有成本"）

**游戏进入暂停（事件弹层 / 暂停菜单 / 应用失焦 / 系统休眠）**
- `activePauseReasons` 加入对应原因，帧循环不增加 `dwellAccumulated`
- 恢复后从冻结时的 `dwellAccumulated` 继续，不重置
- 如玩家在暂停期间被操作系统切回时姿态已改变，下一帧正常走"姿态切换"分支归零

**读档恢复**
- `DwellFocusState` 完全初始化为空（`activePose = nil, dwellAccumulated = 0`）
- 若恢复到的步骤在 `completedStepIDs` 中已有结果，HUD 已经指向下一步骤，dwellTimer 不会对已完成步骤再次触发
- 若恢复到步骤尚未完成（例如 30 秒兜底前），停留计时从 0 重新开始；SceneDirector 从 `pendingBeatRemainingTimes` 恢复剩余兜底时间，两条路径并行

**Reduce Motion 开启**
- FOV 推近改为 0.2 秒淡入淡出（SCNTransaction 持续时间缩短）
- 暖光 overlay 淡入时长从 0.3 秒改为 0.2 秒
- 步骤完成判定时机和阈值不变

## 与其他特性的交互点

| 交互方向 | 对端特性 | 时机与内容 |
|---|---|---|
| F-08 调用 | F-01 叙事状态机 | 阈值触达后调用 `GameManager.completeStep`；步骤切换时由 F-01 的 `completeStep` 逻辑触发 `resetDwellFocusForStep` |
| F-08 依赖 | F-01 叙事状态机 | 读取 `activePauseReasons` 判断是否冻结；读取 `quest.currentStep` 判断步骤上下文 |
| F-08 依赖 | F-02 SceneDirector | SceneDirector 的兜底 Beat 与停留路径共用同一 `completeStep` 入口；F-08 触发后，SceneDirector 应取消本步骤剩余 fallback Beat（由 F-01 的幂等门禁触发取消） |
| F-08 依赖 | F-04 叙事相机模式 | 只在 `NarrativeCameraMode.seatedFirstPerson` 下激活；读取 `scenePresentation.cameraMode` |
| 被 F-10 使用 | 第一章叙事步骤（未来特性） | 第一章步骤 1、2、3 将停留完成信号注册为对应 stepID；F-08 只提供信号，不持有步骤内容 |
| 被序章使用 | F-05 序章 Beat 状态机 | 序章段落 1（看向走廊）与段落 5（看见林澈）沿用相同的停留判定机制，阈值分别为 1.0 秒（感知确认较宽松）；具体阈值配置由 F-05 注册，F-08 机制复用 |
