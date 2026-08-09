# F-15 纸条调查链 — 业务流程

> 状态：final / accepted

## 主流程

```mermaid
flowchart TD
    A[第三章开始\n苏念从走廊返回教室\n切换为第三人称视角] --> B

    B[步骤1：看纸条背面\nCameraPose = .desk → 点击纸条热点]
    B --> C{玩家操作?}
    C -->|点击热点| D[纸条翻面 overlay\nnoteClueFound=true\n线索便签+1\n独白：蓝格笔记本线索]
    C -->|90s未操作| D

    D --> E[步骤2：去后排确认江越座位\nPlayerAction.leaveSeat → 移动到后排靠窗]
    E --> F{移动并交互?}
    F -->|到达热点并确认| G[蓝格本特写 overlay\njiangYueSeatConfirmed=true\njiangYueLocated=true\n独白：是他的本子]
    F -->|45s显示路径光引导| F
    F -->|路径光后仍未操作| G

    G --> H[步骤3：确认离开迹象\n两项观察任意顺序]

    H --> I[观察A：点击桌面热点\n水杯/书本]
    H --> J[观察B：CameraPose切换为.right/.forward\n停留2s感知楼梯间门轴声]

    I --> K{桌面观察完成?}
    J --> L{声音观察完成?}
    K -->|是| M[clue A 完成\n内心独白：水杯满，书没合]
    L -->|是| N[clue B 完成\n内心独白：楼梯间的门声]
    M --> O{两项均完成?}
    N --> O
    O -->|是| P[jiangYueStatus = .justLeft\n步骤3提交]
    O -->|90s仅一项完成| Q[SceneDirector 自动完成缺失项\n播放方向字幕]
    Q --> P

    P --> R[步骤4：找同伴\nHUD：找一个人一起去]

    R --> S{走近周予安?}
    R --> T{走近许栀?}
    S -->|≤1.5m + 确认| U[对话：好，我跟你去\ncompanionChoice = .zhouYuAn\ncompleteStep ch3.4]
    T -->|≤1.5m + 确认| V[对话：我跟你去，我不多说话\ncompanionChoice = .xuZhi\ncompleteStep ch3.4]

    U --> W[步骤5：前往楼梯间\n同伴跟随 F-14 启动\n右下角同伴图标显示]
    V --> W

    W --> X{到达楼梯间入口?}
    X -->|是| Y[transitionChapter校验门禁\n→ 第四章开始]
    X -->|30s路径光引导| X
```

## 边界与兜底

| 步骤 | 异常路径 | 兜底行为 |
|---|---|---|
| 步骤1（纸条背面）| 90s未操作 | SceneDirector 触发苏念自行翻看，结果相同，标记 `flags=["softNoticed"]` |
| 步骤2（座位确认）| 45s未移动 | 路径光出现；仍不操作时苏念自动走到座位并执行检查 |
| 步骤3（双观察）| 90s仅完成一项 | 缺失项由 SceneDirector 自动补全（播放楼梯间门轴声或低头看桌面），附方向字幕 |
| 步骤4（同伴选择）| 无超时自动兜底 | 章节守护 Beat（软上限 10 分钟）触发强化引导：HUD 高亮两位同伴位置；不自动选择 |
| 步骤5（前往楼梯间）| 30s不移动 | 路径光提示；苏念不自动走，保留玩家主动性 |
| 存档恢复 | 任意步骤恢复 | 已完成的观察 flag 不重置；`companionChoice` 已写入时跳过步骤4；同伴 NPC 按 `companionChoice` 确定性重建位置 |
| 章节门禁失败 | `companionChoice == .none` 时触发楼梯间入口 | `transitionChapter` 拒绝，HUD 提示"先找一个人一起去" |

## 与其他特性的交互点

| 时机 | 调用方向 | 说明 |
|---|---|---|
| 步骤1：纸条翻面 | F-15 → F-09 | 触发内心独白（`InnerMonologue`）和线索便签（`ClueCard`）显示 |
| 步骤2-5：教室内移动 | F-15 使用 F-13 | `guidedThirdPerson` 相机模式由 F-13 提供，本特性只调用切换接口 |
| 步骤4：同伴确认后 | F-15 启动 F-14 | `companionChoice` 写入后通知 `CompanionNPC` 激活跟随行为 |
| 步骤5：到达楼梯间 | F-15 → F-16 | `transitionChapter` 校验完成后，携带 `companionChoice` 和 `Ch3State` 初始化第四章 |
| 第四章步骤2/6 | F-16 读取 F-15 结果 | 同伴选择影响江越初次对话压力感和成人联络速度 |
| 第五章步骤3/4 | F-18 读取 F-15 结果 | 同伴图标和流言处理中的班长/许栀 NPC 行为取决于 `companionChoice` |
