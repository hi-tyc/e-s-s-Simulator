# 需求评估：《这里有光》叙事冒险游戏

> 状态：final / accepted  
> 需求 ID：zhyl-narrative-game  
> 评估日期：2026-07-20  
> 评估人：AutoCode requirement-analysis workflow

---

## 需求尺寸

**L — 大规模需求**  
置信度：medium

| 决定性维度 | 判定 | 说明 |
|---|---|---|
| 业务范围 | L | 完整产品替换，7个叙事单元跨教程/教室/走廊/楼梯间/咨询室/终章 |
| 数据影响 | L | 新叙事存档 schema、8个章节状态结构、迁移器框架、章节一致性校验 |
| 方案未知数 | M | 设计文档 v1.1 路径明确，主要未知为场景资产策略 |
| 依赖面 | M | 单一 Swift Package 内，无跨系统/跨团队依赖 |
| 权限/稳定性 | M | 本地桌面应用，核心稳定性集中在幂等和存档恢复 |
| 评审风险 | M | 自研自审，无外部评审方 |

后续需求设计必须按大规模需求模板执行：子需求按实现阶段拆分、数据模型设计、章节一致性风险矩阵、每阶段独立交付门禁。

---

## 澄清结论

| 问题 | 结论 |
|---|---|
| 与现有产品的关系 | **完全替代**：《这里有光》替代原回合制模拟器，原有文档和逻辑按最新设计修改 |
| 心理专业审核 | **不需要外部机构**：自研非商业游戏，开发团队自行把控心理干预内容（选 C） |

---

## 当前满足度

**misfit** — 基础设施可复用（约 15-20%），游戏逻辑完全不匹配。

### 可复用

- `GameManager` ObservableObject 框架
- `ClassroomCoordinator` SceneKit 单向映射模式
- `CameraPose` 基础枚举值（`.left/.right/.forward/.desk`）
- `SpatialAudioManager` 音频引擎
- `liquidGlassPanel` UI 辅助器
- `PlayerAction.breathe/.drink`

### 不可复用（需全部替换）

- 回合制游戏循环（`execute(_:)`、`teacherTurn()`、NPC 压力矩阵）
- 多指标 HUD
- 现有结局系统
- `GameState.playing` 语义

---

## 产品与系统 Gap

共 11 个 Gap 类别，均为全部缺失：

| Gap | 类别 | 关键缺失 |
|---|---|---|
| A | 叙事状态机 | `MainQuestProgress`、`GameNarrativeState`、8个章节状态、`NarrativeSave` |
| B | SceneDirector | Beat 定义、多重暂停集合、幂等提交、时间冻结/恢复 |
| C | 新场景和相机 | 走廊/镜像/楼梯间/咨询室场景、`NarrativeCameraMode` 6种模式 |
| D | HUD 重构 | `MainQuestHUD`、内心独白、线索便签 |
| E | 对话系统 | `ChapterDialogue`、林澈/江越对话状态机 |
| F | 微游戏 overlay | 描线/旋律/擦除三种微游戏 + 替代输入 |
| G | 同伴 NPC | `CompanionNPC`、`CompanionFollowBehavior` |
| H | 第四章专用 | 信任值、披露状态、倒计时、安全路线分流 |
| I | 第五章专用 | 流言导演、偏见便签、等候区系统 |
| J | 第六章专用 | 支持网络图、7种结局、求助资源目录 |
| K | 音频扩展 | `AudioCueKind.bell`、`noteDrop` 事件、镜像空间音频 |

---

## 满足路径

按七个实现阶段推进（设计文档 §H 定义六个阶段 0-5，序章在其阶段 1 中；本评估将序章单独拆出为阶段 1，底座为阶段 0，后续为阶段 2-6，共七个阶段，工作量合计如下表）：

- **阶段 0**：底座（叙事状态机 + SceneDirector + 存档 + HUD + 相机模式）
- **阶段 1**：序章（Beat 状态机 + 校门/走廊场景 + 辅助设置）
- **阶段 2**：第一章（教室步骤 + 林澈 NPC + noteDrop + 独白/便签）
- **阶段 3**：第二章（镜像场景 + 三微游戏 + 色温动画 + 信任对话）
- **阶段 4**：第三章（第三人称相机 + 同伴 NPC + 楼梯间）
- **阶段 5**：第四-五章（江越对话/信任/披露 + 三路线 + 流言/偏见）
- **阶段 6**：第六章 + 集成（结局/资源/支持网络 + 六章转场 + 无障碍 + 测试）

---

## 轻量实现口径

- **叙事状态**：`GameManager` 新增三个存储属性（`quest`/`narrative`/`chapterState`），回合制属性逐步删除，不一次性大换血
- **SceneDirector**：`GameManager` 内部协作者，`async Task` 驱动 Beat 延迟，`activePauseReasons` 集合管理暂停，不保存 Task/Timer 本身进存档
- **新场景**：`ClassroomCoordinator` 按 `activeSceneRootID` 显示/隐藏场景根节点，程序化 SceneKit 构建优先
- **微游戏**：SwiftUI `ZStack` overlay + `DragGesture` + `GeometryReader`，不引入 SpriteKit
- **存档**：新增独立 UserDefaults key `LateStudySimulator.NarrativeSave.v1`，JSON 编解码，双槽
- **审核门禁**：降级为 `#if DEBUG` 编译警告，不阻塞 Release

---

## 工作量评估

以 AI 辅助编码为基准：

| 实现阶段 | 估算（开发天） |
|---|---|
| 阶段 0：底座 | 8-10 |
| 阶段 1：序章 | 7-9 |
| 阶段 2：第一章 | 7-9 |
| 阶段 3：第二章 | 10-13 |
| 阶段 4：第三章 | 7-9 |
| 阶段 5：第四-五章 | 12-15 |
| 阶段 6：第六章+集成 | 10-13 |
| **合计** | **61-78 天** |

---

## 风险

| 风险项 | 等级 | 说明 |
|---|---|---|
| 3D 场景资产策略 | 🔴 高 | 4个新场景（走廊/镜像/楼梯间/咨询室）若使用外部美术资产，工期上浮 50-80% |
| NPC 动画细腻度 | 🟡 中 | 林澈/江越情绪动作调试成本较高 |
| 微游戏手感 | 🟡 中 | 描线/擦除容差需迭代 |
| Windows 构建限制 | 🟡 中 | 每次验证需切换 macOS，增加验证周期 |

---

## 接纳建议

**建议接纳**，条件：

1. **场景资产策略先确认**：阶段 0 底座完成后，在进入阶段 1（序章）前确认走廊/镜像/楼梯间/咨询室场景使用程序化构建还是外部资产，这是工期最大变量。
2. **分阶段交付门禁**：每阶段完成后 `swift build` 通过 + 对应叙事单元可完整通关，才进入下一阶段，不允许跨阶段大换血。
3. **不一次性重写大文件**：`GameManager.swift` 和 `ClassroomSceneView.swift` 按阶段增量修改，每次修改后构建通过。

---

*文档状态：draft，待评审*
