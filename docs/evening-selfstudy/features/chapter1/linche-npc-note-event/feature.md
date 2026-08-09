# F-10 林澈 NPC 与纸条事件

> 状态：final / accepted
> 实现阶段：Phase 2
> 依赖特性：F-02（SceneDirector 节拍系统）、F-04（叙事相机模式与场景呈现）、F-08（视角停留判定与聚焦反馈）、F-09（内心独白与线索便签）

## 产品能力描述

在第一章《静音的教室》中，为玩家提供通过观察和对话感知林澈状态的完整交互链，并在铃声响起时触发纸条发现事件，让苏念在不主动介入的情况下"看见了"一条匿名求助。林澈 NPC 的微小动作（书翻停、铃前抬头、起身离开）是玩家判断异常的主要感知来源，为后续章节的关系建立奠定基础。

## 功能边界

**包含：**
- 林澈 NPC 在第一章的全部行为状态：idle 翻书停止、第 6 回合抬头看门口、铃后起身离开路径动画
- 步骤 1 聚焦观察结果写入（`Ch1State.linCheObserved`、`GameNarrativeState.linCheSuspicion`）
- 步骤 4 对话选择（3 选 1）及结果写入（`linCheListenScore`、`linCheTrust`、`Ch1State.spokeToLinChe`）
- 步骤 5 纸条事件：`ActiveEventKind.noteDrop` 触发、纸条 SCNNode 出现、纸条特写 overlay、`noteFound` / `notePicked` 写入
- 步骤 6 林澈起身离开动画及玩家跟随判定，向第二章的衔接过渡
- 铃声音效（`AudioCueKind.bell`）与椅子移动音效（`AudioCueKind.chair`）的程序化触发

**不包含：**
- 视角停留判定与聚焦触发逻辑（F-08 负责）
- 内心独白与线索便签的渲染组件（F-09 负责）
- SceneDirector Beat 调度框架（F-02 负责）
- 第二章走廊场景及林澈镜像空间版本（F-11）
- `dwellTimer` 累计计时逻辑（F-08）

## 验收标准

- [ ] 第一章开始后，林澈 NPC 书翻停（idle 停在同一页），从晚自习开始到步骤 1 完成前始终保持该状态
- [ ] 步骤 1 完成后，`Ch1State.linCheObserved == true`、`GameNarrativeState.linCheSuspicion += 30`，线索便签 +1，内心独白播放；同一 stepID 重复提交不追加第二次数值
- [ ] 第 6 回合时 SceneDirector 触发林澈抬头看门口再低头的 Beat 动画，且该动画只执行一次（completedBeatIDs 去重）
- [ ] 步骤 4 三选项均可完成步骤，`linCheTrust` 和 `linCheListenScore` 按设计写入且只写入一次；对话 overlay 关闭后恢复正常视角控制
- [ ] `currentTurn >= 8` 或步骤 4 完成 60 秒后纸条事件触发：椅子声响起 → 纸条 SCNNode 出现 → 铃声播放 → HUD 目标更新；事件 ID 全局唯一，重复请求无副作用
- [ ] 纸条特写 overlay 正确显示手写字体正文及蓝格线撕痕，关闭后 `noteFound == true`、`notePicked == true`、HUD 线索便签 +1
- [ ] 铃声后 5 秒林澈 NPC 沿预设路径动画（约 8 秒）走向教室门口；玩家在动画结束前执行 `leaveSeat` 则主动跟随；玩家不操作则 SceneDirector 自动推进苏念起身
- [ ] 步骤 6 完成时按 `linCheTrust` 选择对应衔接动画版本（`.open/.neutral/.closed`），淡出至走廊场景，第二章 HUD 正确接管
- [ ] 全部步骤均可仅用键盘完成；纸条特写 overlay 提供确认键关闭

## 设计约束

- 林澈 NPC 的情绪动作（肩膀幅度、抬头速度）不得在 UI 上添加任何标签或进度指示；玩家通过动作感知，不通过数字感知
- `ActiveEventKind.noteDrop` 使用全局唯一事件 ID，SceneDirector 重复请求必须被 `completedBeatIDs` 拦截，不得重复播放音效或生成第二张纸条
- 纸条内容为固定文本（「心里很难受，但我不知道找谁说。不知道有没有人想听。」），不随机，不由玩家选项影响
- `linCheTrust` 值（`.open/.neutral/.closed`）在步骤 4 一次性写入，后续章节只读；第一章结束前不得再次覆盖
- 步骤 6 的衔接动画必须在 `Ch1State.notePicked == true` 后才能触发；不允许在未捡纸条的情况下进入第二章
- `AudioCueKind.bell` 与 `.chair` 缺少真实素材时必须程序化回退，不得静默跳过
