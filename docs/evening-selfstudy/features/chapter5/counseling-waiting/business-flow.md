# F-18 咨询室等候与隐私保护 — 业务流程

> 状态：final / accepted

## 主流程

```mermaid
flowchart TD
    A[从第四章安全交接完成] --> B{读取 safetyRoute}
    B -->|standardCounseling| C[entryMode = .standardWaiting]
    B -->|urgentSchoolResponse| D[entryMode = .urgentHandoffWaiting]
    B -->|emergencyServices| E[entryMode = .emergencyClosure]

    C --> C1[步骤1：心理老师接待 / 江越进门]
    C1 --> C2[jiangYueEntered = true\nhandoffSceneStarted = true]
    C2 --> C3[步骤2：坐到等候椅\nboundaryHeld 维护]
    C3 --> C4[步骤3：流言事件触发]
    C4 --> C5[步骤4：同伴消息回复]
    C5 --> C6[步骤5：等候期间\n可选偏见便签/书架科普]
    C6 --> C7[步骤6：江越在成人陪同下出来\n玩家做告别选择]
    C7 --> DONE

    D --> D1[步骤1：心理老师+方老师轮班确认]
    D1 --> D2[handoffSceneStarted = true]
    D2 --> D3[步骤2：走到支持室外等候锚点]
    D3 --> D4[步骤3：流言事件触发]
    D4 --> D5[步骤4：同伴消息回复]
    D5 --> D6[步骤5：等候\n偏见便签可选]
    D6 --> D7[步骤6：心理老师出来确认\n持续陪同安排]
    D7 --> DONE

    E --> E1[步骤1：方老师确认紧急服务接手]
    E1 --> E2[handoffSceneStarted = true]
    E2 --> E3[步骤2：保持安全办公室/走廊锚点]
    E3 --> E4[步骤3：方老师提醒「先别在群里讨论」\n替代流言事件]
    E4 --> E5[步骤4：同伴消息回复]
    E5 --> E6[步骤5：等约30秒\n无偏见便签NPC]
    E6 --> E7[步骤6：方老师确认紧急交接进行中\n玩家按确认回应]
    E7 --> DONE

    DONE["同一次幂等 completeStep:\nhandoffConfirmed = true\nsupportHandedOff = true\n写入 NarrativeSave → 触发第六章入口"]
```

**流言事件子流程（步骤 3，标准/高风险路线）：**

```mermaid
sequenceDiagram
    participant SD as SceneDirector
    participant NPC as 陈言+同学NPC
    participant Player as 玩家
    participant GM as GameManager

    SD->>NPC: 触发路过动画（坐下约1分钟后）
    Note over NPC: 余光区域出现，低声议论
    SD->>Player: 20秒选项窗口开启

    alt companionChoice == .zhouYuAn
        SD->>NPC: 周予安自动说「各自去忙吧」（减轻压力）
    end

    alt 玩家选择A（回应）
        Player->>GM: completeStep("ch5.step3", choiceID:"respond")
        GM-->>GM: rumorOutcome = .suppressed
    else 玩家选择B（不回应）或超时
        Player->>GM: completeStep("ch5.step3", choiceID:"silent")
        GM-->>GM: rumorOutcome = .contained
    end

    Note over GM: privacyProtected 不变（两种选项均不泄露）
    GM-->>GM: rumorHandled = true
```

## 边界与兜底

| 场景 | 处理方式 |
|---|---|
| 玩家靠近咨询室门（标准/高风险路线） | 距离 ≤0.5m 且停留 ≥3s → 内心独白 + camera pull-back；`boundaryHeld` 不变为 `true` |
| 流言选项 20 秒超时 | SceneDirector 自动提交 `.contained`（不回应路径），`rumorHandled = true` |
| 偏见便签玩家不操作 | 5 秒后自动消失，不计入任何完成门禁，不影响主线 |
| 同伴消息玩家不回复 | 章节软上限压缩等候 Beat 后，SceneDirector 提交默认回复选项（选项 A），写入 `companionMessageReplied = true` |
| 即时危险路线出现流言 NPC | 即时危险路线不生成路过 NPC；改为方老师说出「先别在群里讨论刚才的事」，`rumorHandled = true` 由该 Beat 完成 |
| 章节软上限 15 分钟超出 | 标准路线：SceneDirector 压缩等候等待时间；高风险/即时危险路线：按成人确认 Beat 直接收束 |
| 读档时 `entryMode` 与 `safetyRoute` 不一致 | 章节一致性校验拒绝，恢复 `lastValid`，显示一次非阻塞提示 |
| 应用在等候期间失焦/系统休眠 | `activePauseReasons` 插入对应暂停原因，所有受控 Beat 冻结，偏见便签倒计时暂停；恢复后继续剩余时间 |

## 与其他特性的交互点

| 时机 | 方向 | 交互特性 | 说明 |
|---|---|---|---|
| 章节入口 | F-17 → F-18 | F-17 安全路线分流 | `safetyRoute` 已持久化后 `startChapter(.counseling)` 读取并映射 `entryMode` |
| 步骤 3 流言事件 | F-18 使用 | F-14 同伴 NPC | `companionChoice == .zhouYuAn` 时周予安执行自动台词 Beat |
| 步骤 3 偏见便签 | F-18 使用 | F-09 内心独白/线索便签 | `BiasCardSystem` 复用 `InnerMonologue` 触发路径与 `liquidGlassPanel` 样式 |
| 步骤 6 完成 | F-18 → F-19 | F-19 终章入口 | `supportHandedOff = true` 写入后，`transitionChapter(.epilogue)` 门禁通过，苏念走向走廊大镜子 |
| 等候区相机 | F-18 使用 | F-03 叙事相机 | `NarrativeCameraMode.waitingSeated` 复用第一章固定坐姿逻辑，切换场景根节点 |
| 暂停/恢复 | F-18 使用 | F-02 SceneDirector | 流言事件窗口、偏见便签倒计时、成人等候 Beat 均受 `activePauseReasons` 冻结管理 |
