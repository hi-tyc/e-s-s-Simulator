# F-16 江越对话与信任系统 — 业务流程

> 状态：final / accepted

## 主流程

```mermaid
flowchart TD
    A[进入第四章\n楼梯间场景\n倒计时 10 分钟启动] --> B[步骤 1\n找到江越\n自动完成]
    B --> C{步骤 2\n破冰选项}

    C -->|选 A 防御| D[江越起身要走\n同行者补救]
    D --> E[第二次选 B/C]
    E --> F[iceBreakSuccess = true\n基础信任 -10]

    C -->|选 B/C| F

    F --> G[步骤 3\n江越四段独白\n每段 15 秒响应窗口]
    G --> H{回应类型}
    H -->|倾听式/陪伴式/沉默| I[信任 +5 至 +10]
    H -->|鸡汤/评判式| J[信任 -5 至 -10]
    H -->|超时未选| K[信任 +1\n连续两次触发更明确提示]
    I & J & K --> L[四段全部完成\nlistenPhaseComplete = true]

    L --> M[步骤 4\n教育便签展示\n玩家确认关闭]
    M --> N{追问方式选择}

    N -->|gentle trust>=40| O[disclosedRisk = .partial]
    N -->|direct trust>=60| P[disclosedRisk = .confirmed]
    N -->|direct/gentle trust不足| Q[disclosedRisk = .unknown]
    N -->|deferToAdult| Q

    O & P --> R[步骤 5\n告知同行意愿]
    Q --> S[步骤 6\n直接联系成人\n路径 adultCameAfterUnclearDisclosure]

    R --> T{willingness}
    T -->|trust>=50 + 选 A| U[jiangYueWillingToGo = true\n路径 voluntary]
    T -->|选 B 或 trust<50| V[jiangYueWillingToGo = false\n路径 adultCameAfterLowTrust]
    U & V --> S2[步骤 6\n同行者联系成人]

    S --> W{jiangYueActualRisk}
    S2 --> W

    W -->|low/moderate| X[safetyRoute = .standardCounseling\nCounselingEntryMode = .standardWaiting]
    W -->|high| Y[safetyRoute = .urgentSchoolResponse\n取消普通倒计时]
    W -->|imminent| Z[safetyRoute = .emergencyServices\n立即进入紧急流程]

    X --> AA[步骤 7\n跟随方老师\n走向咨询室]
    Y --> AB[步骤 7\n留在安全区\n等候心理老师/校方]
    Z --> AC[步骤 7\n退到安全位置\n等候成人确认]

    AA & AB & AC --> AD[原子提交\nadultNotified / safetyRoute\n safetyHandoffComplete\nCounselingEntryMode]
    AD --> AE[进入第五章]
```

## 边界与兜底

**破冰失败（步骤 2 选 A）**
- 江越起身，同行者从侧面说"先别走"，给玩家第二次选择（只保留 B/C）
- 第二次任意选择后强制通过，`iceBreakSuccess = true`，信任基础值 -10
- 主线不断

**倾听超时（步骤 3）**
- 每段 15 秒未选择，自动提交"超时"回应，信任 +1
- 连续两次超时后 HUD 提示更明确的操作指引
- 四段全部播放后无论信任值多少均标记 `listenPhaseComplete`

**倒计时归零（步骤 6 前）**
- SceneDirector 自动触发：同行者（周予安/许栀）主动联系方老师
- 等效于玩家完成步骤 6，写入 `adultContactInitiated = true`

**信任不足路径**
- `jiangYueTrustValue < 40` 且选 gentle：`disclosedRisk = .unknown`
- `jiangYueTrustValue < 60` 且选 direct：`disclosedRisk = .unknown` 或 `.partial`
- `.unknown` 路径：HUD 更新为"他不想说，但我不能假装没听见"，直接进入步骤 6
- 任何披露状态下主线均可到达成人接管

**存档恢复**
- 从 `pendingBeatRemainingTimes` 恢复倒计时剩余秒数
- 从 `Ch4State` 恢复对话阶段（已完成的独白段落不重播）
- `activePauseReasons` 中移除 `.appInactive/.systemSleep`，按当前应用状态重新添加
- 江越 NPC 的 SCNNode 姿态由 `ClassroomCoordinator.update(game:)` 依据 `Ch4State` 确定性重建

**应用失焦/系统休眠**
- `activePauseReasons.insert(.appInactive/.systemSleep)`
- 倒计时、对话响应窗口、SceneDirector Beat 全部冻结
- 恢复后从剩余时间继续，不重新计时，已触发 Beat 不重放

**高危路线（.high/.imminent）**
- 触发后立即取消普通课间倒计时 Beat
- 安全响应 Beat 序列优先级覆盖普通剧情 Beat
- `.emergencyServices` 路线不展示处置细节，玩家只需退到安全锚点等待成人确认

## 与其他特性的交互点

**被调用（本特性读取前章输出）**
- F-13 第三章：`companionChoice`（`.zhouYuAn/.xuZhi`）决定同行者行为差异（周予安速度更快，许栀给江越更多空间）
- F-12 第二章：`linCheListenScore >= 3` 给信任基础分 +5（"苏念练习过倾听"）
- F-10 第一章：两条明确观察 + 捡到纸条给信任基础分 +10

**调用其他特性（本特性输出）**
- F-17 第五章：`safetyRoute` 决定第五章入口模式 `CounselingEntryMode`；`jiangYueResolutionPath` 影响第五章等候区内容
- F-18 第六章：`jiangYueResolutionPath` 参与多结局条件判断；`adultNotified` 影响支持网络图节点文字
- 存档系统：`safetyRoute` + `CounselingEntryMode` 原子写入，读档时做一致性校验；不一致恢复 `lastValid`
- `SceneDirector`：注册步骤 2-7 的 Beat 定义和倒计时；高危路线接管时取消普通 Beat 序列
