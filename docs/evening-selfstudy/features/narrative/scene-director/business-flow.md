# F-02 SceneDirector 节拍系统 — 业务流程

> 状态：final / accepted

## 主流程

### Beat 生命周期

```mermaid
flowchart TD
    A["GameManager.startChapter(chapterID)"] --> B[从 QuestCatalog 加载本章 Beat 列表]
    B --> C{有 pendingBeatRemainingTimes\n中对应的剩余时间?}
    C -- 是 读档恢复 --> D["使用保存的 remainingTime\n创建 async Task"]
    C -- 否 正常启动 --> E["使用 Beat.triggerDelay\n创建 async Task"]
    D --> F
    E --> F{activePauseReasons 非空?}
    F -- 是 --> G[记录当前已等待时间\n挂起 Task]
    G --> H{集合清空?}
    H -- 否 --> G
    H -- 是 --> I[用剩余时间继续等待]
    I --> F
    F -- 否 --> J[等待 triggerDelay / 剩余时间]
    J --> K{Beat ID 在 completedBeatIDs?}
    K -- 是 --> L[跳过 幂等]
    K -- 否 --> M{conditionID 存在\n且条件未满足?}
    M -- 否 直接执行 --> N["向 GameManager 请求\ndispatchBeatAction(actionID)"]
    M -- 是 且有 fallbackDelay --> O["等待 fallbackDelay\n（可再次暂停）"]
    O --> P["向 GameManager 请求\ndispatchBeatAction(fallbackActionID)"]
    M -- 是 且无 fallbackDelay --> L
    N --> Q["GameManager 执行动作\n写入 completedBeatIDs"]
    P --> Q
    Q --> R[触发自动存档检查点]
```

### 多重暂停交错

```mermaid
sequenceDiagram
    participant App
    participant GM as GameManager
    participant SD as SceneDirector

    App->>GM: addPauseReason(.appInactive)
    GM->>SD: 冻结所有 Beat Task（记录剩余时间）

    App->>GM: addPauseReason(.pauseMenu)
    Note over GM: activePauseReasons = {.appInactive, .pauseMenu}

    App->>GM: removePauseReason(.pauseMenu)
    Note over GM: activePauseReasons = {.appInactive}\n集合非空，继续冻结

    App->>GM: removePauseReason(.appInactive)
    Note over GM: activePauseReasons = {}\n集合清空，恢复计时
    GM->>SD: 从剩余时间继续各 Beat Task
```

## 边界与兜底

| 场景 | 处理方式 |
|---|---|
| 玩家操作与 fallback Beat 同帧到达 | `completeStep` 幂等，Beat ID 写入 `completedBeatIDs` 后第二个到达者直接跳过，不产生重复状态写入 |
| 应用进入后台时 Beat 正在等待 | `addPauseReason(.appInactive)`，`pendingBeatRemainingTimes` 随 `NarrativeSave` 写入 UserDefaults |
| 存档恢复时 `.appInactive/.systemSleep` 在集合中 | 恢复时从集合移除这两项，再根据当前应用状态决定是否重新插入 |
| 章节切换 / 返回菜单 / 读档 | 调用 `cancelAllBeats()`，清空本章 `pendingBeatRemainingTimes` 条目，旧 Task 立即取消 |
| Beat 定义中 `conditionID` 对应逻辑未注册 | GameManager 在 `evaluateBeatCondition` 中返回 `false`，由 fallback 路径或无 fallback 的跳过逻辑处理，不崩溃 |
| `completedBeatIDs` 与 `pendingBeatRemainingTimes` 中同一 Beat ID 并存 | 恢复时跳过已完成 Beat 的 Task 重建，以 `completedBeatIDs` 为准 |
| 第四章高危/紧急路线触发 | 安全响应 Beat 通过具名 Task cancellation 强制取消普通倒计时 Beat，不依赖优先级 |

## 与其他特性的交互点

| 时机 | 调用方向 | 涉及特性 |
|---|---|---|
| `GameManager.startChapter` 时 | F-01 → F-02：触发 SceneDirector 注册本章 Beat | F-01 |
| 序章各段落 Beat 超时兜底 | F-02 → F-01：`dispatchBeatAction` → `completeStep` | F-05（序章 Beat 定义） |
| 第一章 noteDrop Beat 触发 | F-02 → F-01/F-10：派发 `noteDrop` 动作 | F-10（林澈 NPC 与纸条事件） |
| `.event` 覆盖层激活/关闭 | F-01 ↔ F-02：插入/移除 `.event` 暂停原因 | F-01（GameState 管理） |
| 第四章高危路线分流 | F-17 → F-02：取消普通倒计时 Beat，注册安全响应 Beat | F-17（安全路线分流） |
| 第四章江越对话超时 | F-02 → F-16：fallback Beat 触发同伴自动联系方老师 | F-16（江越对话与信任） |
| 存档写入 `pendingBeatRemainingTimes` | F-02 → 存档系统：每步骤完成后、章节切换前随 `NarrativeSave` 持久化 | F-01（存档 schema） |
