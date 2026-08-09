# F-01 叙事状态机与章节进度 — 业务流程

> 状态：final / accepted

## 主流程

### 章节转换状态机

```mermaid
flowchart TD
    MENU[主菜单] -->|startChapter| CH0[序章 Prologue]
    CH0 -->|prologueCompleted| CH1

    CH1[第一章 · 静音的教室] -->|notePicked && walkthrough| GATE1{门禁检查}
    GATE1 -->|通过| CH2[第二章 · 走廊的镜子]
    GATE1 -->|不通过| CH1

    CH2 -->|三灯完成 && 对话选择记录| GATE2{门禁检查}
    GATE2 -->|通过| CH3[第三章 · 那张纸条]
    GATE2 -->|不通过| CH2

    CH3 -->|jiangYueSeatConfirmed && companionChoice != none| GATE3{门禁检查}
    GATE3 -->|通过| CH4[第四章 · 13楼的缝隙]
    GATE3 -->|不通过| CH3

    CH4 -->|adultNotified && safetyHandoffComplete| GATE4{门禁检查}
    GATE4 -->|通过| CH5[第五章 · 有灯亮着的房间]
    GATE4 -->|不通过| CH4

    CH5 -->|handoffConfirmed && supportHandedOff| GATE5{门禁检查}
    GATE5 -->|通过| CH6[第六章 · 这里有光]
    GATE5 -->|不通过| CH5

    CH6 -->|resourceConfirmed| END[主菜单 · 解锁内容]
```

### 步骤提交流程

```mermaid
sequenceDiagram
    participant P as 玩家/SceneDirector
    participant GM as GameManager
    participant Save as NarrativeSave

    P->>GM: completeStep(stepID, result)
    GM->>GM: completedStepIDs.contains(stepID)?
    alt 已包含（重复提交）
        GM-->>P: return（幂等，无副作用）
    else 首次提交
        GM->>GM: 写入 narrative / chapterState 字段
        GM->>GM: completedStepIDs.insert(stepID)
        GM->>Save: 触发自动存档快照
        GM-->>P: 通知 UI / SceneDirector 继续
    end
```

### 多重暂停管理

```mermaid
flowchart LR
    subgraph 暂停来源
        E[.event 弹层]
        M[.pauseMenu 暂停]
        A[.appInactive 失焦]
        S[.systemSleep 休眠]
    end

    E -->|addPauseReason| SET[activePauseReasons Set]
    M --> SET
    A --> SET
    S --> SET

    SET -->|非空| FREEZE[冻结叙事计时]
    SET -->|清空| RESUME[从剩余时间恢复，不重置]

    E -->|弹层关闭 removePauseReason| SET
    M -->|继续游戏 removePauseReason| SET
    A -->|应用恢复 removePauseReason| SET
    S -->|系统唤醒 removePauseReason| SET
```

## 边界与兜底

**存档损坏**
- `current` 槽解码失败 → 尝试 `lastValid`；两者均失败 → 从当前章合法入口重建并显示非阻塞提示
- 未知 `schemaVersion`（未来版本存档在旧版本读取）→ 拒绝解码，不猜测，不拼接不一致状态

**章节一致性校验失败**
- `chapterState` case 与 `quest.currentChapter` 不匹配 → 使用 `lastValid`；两者均异常 → 重建入口

**步骤越级**
- `transitionChapter` 校验未通过的门禁条件 → 返回 `false`，保持当前章，不执行 cleanup；SceneDirector 继续运行当前章 Beat

**应用在转场中断**
- `prepare` 阶段终止：无可见副作用，存档仍是旧章检查点，恢复后重放转场
- `commit` 阶段终止：存档状态未更新，恢复后重放转场
- `cleanup` 阶段终止：新章检查点已写入，恢复后只清理残留旧节点，不触发双重热点

**读档时的暂停状态处理**
- 移除存档中的 `.appInactive` / `.systemSleep`（生命周期状态由当前运行时决定）
- 保留 `.pauseMenu`（用户有意暂停）和 `.event`（若有覆盖层事件待处理）

## 与其他特性的交互点

| 时机 | 调用方向 | 交互内容 |
|---|---|---|
| F-01 提供协议 `NarrativeQuestManaging` | F-02 SceneDirector 依赖 | SceneDirector 调用 `completeStep`、`addPauseReason`、`removePauseReason`；不直接修改状态字段 |
| F-01 提供 `quest` 和 `narrative` | F-03 MainQuestHUD 订阅 | HUD 读取 `@Published quest` 渲染当前目标；只读，不写 |
| F-01 提供 `ScenePresentationState` 引用 | F-04 叙事相机依赖 | F-04 定义 `ScenePresentationState` 和 `NarrativeCameraMode`，F-01 在 `NarrativeSave` 中持有其快照 |
| F-01 提供 `transitionChapter` | 各章功能（F-05、F-08–F-19）调用 | 章节逻辑完成后通过 `transitionChapter` 触发章节切换，由 F-01 执行门禁并写入存档 |
| F-01 提供 `GameNarrativeState.companionChoice` | F-14 同伴 NPC 读取 | 同伴选择写入全局字段，F-14 读取并驱动 NPC 跟随行为 |
| F-01 提供 `safetyRoute` / `jiangYueActualRisk` | F-17 安全路线分流读取 | F-17 读取编剧风险事实决定路线，写回 `safetyRoute` 后由 F-01 存档机制持久化 |
| F-01 提供结局相关字段 | F-19 结局选择逻辑读取 | `EndingSelector` 读取 `GameNarrativeState` 的累积事实生成结局；不回写 F-01 管理的字段 |
