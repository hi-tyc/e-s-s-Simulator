# F-19 苏念咨询与支持网络结局 — 业务流程

> 状态：final / accepted

## 主流程

```mermaid
flowchart TD
    A([第五章完成\nsupportHandedOff=true]) --> B[步骤1 走向走廊镜子\nmirrorApproached=true]
    B --> C{玩家确认\n或30s兜底}
    C --> D[步骤2 进入咨询室\ncounselingEntered=true\n播放保密边界脚本]
    D --> E[步骤3 咨询对话\n最多2个主题]
    
    E --> E1{选择主题}
    E1 --> E2[倾听/确认式回应\nchosenTopicIDs追加\nsuNianSharedSelf=true]
    E2 --> E3{继续说 / 先到这里}
    E3 -- 继续且未满2项 --> E1
    E3 -- 先到这里或今天先坐一会儿 --> F

    E1 --> E4[今天先坐一会儿\nsuNianSharedSelf=false]
    E4 --> F

    F[步骤4 支持网络图\nnetworkViewed=true\n五节点逐一点亮]
    F --> G{玩家关闭\n或10s自动}
    G --> H[EndingSelector 计算主结局\n+ 自我照顾附注判断]
    H --> I[步骤5 结局卡片 + 求助资源卡片\n玩家点击确认]
    I --> J[resourceConfirmed=true\n返回主菜单]
```

### EndingSelector 优先级

```mermaid
flowchart TD
    S([开始选择]) --> P1{safetyRoute ==\n.emergencyServices}
    P1 -- 是 --> R1[「已经有人接手」]
    P1 -- 否 --> P2{safetyRoute ==\n.urgentSchoolResponse}
    P2 -- 是 --> R2[「把事情交出去」]
    P2 -- 否 --> P3{voluntary &&\nsuNianSharedSelf}
    P3 -- 是 --> R3[「今天不一样了」]
    P3 -- 否 --> P4{adultCameAfterUnclearDisclosure}
    P4 -- 是 --> R4[「不知道，也要行动」]
    P4 -- 否 --> P5{adultCameAfterLowTrust}
    P5 -- 是 --> R5[「你做了你能做的」]
    P5 -- 否 --> P6{suNianSharedSelf == false}
    P6 -- 是 --> R6[「下次也可以」]
    P6 -- 否 --> R7[「这里有光」]
    
    R1 & R2 & R3 & R4 & R5 & R6 & R7 --> ANN{suNianSelfCared == false}
    ANN -- 是 --> RADD[叠加附注\n「记得照顾自己」]
    ANN -- 否 --> END([结局文字完成])
    RADD --> END
```

## 边界与兜底

**步骤 1 兜底（30s 未操作）：** SceneDirector 自动让苏念走向镜子并触发确认，完成 `mirrorApproached=true`，进入步骤 2。

**步骤 2 保密边界脚本缺失：** Release 构建门禁拦截打包，Debug 构建显示占位文本并记录警告，不阻塞运行。

**步骤 3 玩家未选择任何主题：** 自动以「今天先坐一会儿」作为最终选择提交，`suNianSharedSelf=false`，进入步骤 4。

**步骤 4 玩家直接跳过网络图：** 允许立即关闭；10s 无操作后自动继续，`networkViewed=true` 仍写入。

**步骤 5 求助资源不可跳过：** `resourceConfirmed` 是章节唯一门禁，无任何超时自动完成逻辑；SceneDirector 不为此步骤注册 fallback Beat。

**存档恢复：** 恢复时 `EndingSelector` 从当前 `GameNarrativeState` 重新派生结局，不需要存档 `EndingType`。若 `counselingEntered=true` 但 `chosenTopicIDs` 为空，认为读档在步骤 3 开始前，从步骤 3 入口重建。

**多重暂停交错：** 步骤 1-4 的 SceneDirector Beat 遵循 F-02 定义的 `activePauseReasons` 集合冻结机制；步骤 5 无 Beat，恢复暂停后直接还原资源卡片显示状态。

## 与其他特性的交互点

| 调用方向 | 触发时机 | 说明 |
|---|---|---|
| F-19 读取 F-01 | 章节入口校验 | 检查 `supportHandedOff == true`，不满足则门禁拦截 |
| F-19 读取 F-01 | `EndingSelector.select` | 读取 `safetyRoute`、`jiangYueResolutionPath`、`suNianSharedSelf`、`suNianSelfCared` |
| F-19 读取 F-01 | `SupportNetworkView` 渲染 | 读取 `linCheListenScore`、`companionChoice`、`linCheTrust` 派生节点强度 |
| F-19 写入 F-01 | 步骤 3 完成 | `completeStep` 幂等提交 `suNianSharedSelf` 到 `GameNarrativeState` |
| F-19 调用 F-02 | 步骤 1 镜面涟漪 | 注册 SceneDirector Beat，驱动 `mirrorRipple` 转场 |
| F-19 被 F-20 依赖 | 全局集成 | F-20 要求本特性可通关后才能进行六章转场和音频完整测试 |
| F-19 被 F-21 依赖 | iPad 预置 | `SupportNetworkView` Canvas 和 `SupportResourceView` 需在 F-21 中验证 iPad 布局 |
