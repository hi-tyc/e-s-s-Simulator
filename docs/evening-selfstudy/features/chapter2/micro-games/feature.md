# F-12 三灯微游戏

> 状态：final / accepted
> 实现阶段：Phase 3
> 依赖特性：F-07（辅助设置面板）、F-11（镜像空间场景）

## 产品能力描述

第二章镜像空间内，玩家依次激活草稿灯、旋律灯、擦痕灯，通过描线、旋律接唱、擦除比较三个感知闪现微游戏，亲历林澈内心的压力模式。三灯全亮后解锁与林澈的核心对话，并将选择结果写入 `linCheListenScore` 与 `linCheTrust`，影响第三至五章的人物互动与同伴倾向。

## 功能边界

**包含：**
- `MicroGameOverlay`：SwiftUI ZStack overlay，0.3s 淡入淡出，叠加于 SCNView 上层
- 草稿灯（感知闪现·描线）：DragGesture 描折线路径，容忍误差 ±15pt，描过 80% 即完成
- 旋律灯（感知闪现·旋律接唱）：4 音符程序化播放，错误可重播，最多 3 次提示后自动通过
- 擦痕灯（感知闪现·擦除比较）：DragGesture 擦除 mask，达 60% 面积即完成，保留剩余 40%
- 键盘逐段确认替代输入（依赖 F-07 提供的辅助设置开关）
- "由苏念慢慢完成"无障碍选项（二次提示后出现，18min 软上限触发）
- 每灯完成后触发 3D 场景节点更新（灯光强度、内心独白、光路出现/延伸）

**不包含：**
- 失败判定或重来计数（三个微游戏均无失败状态）
- 旋律/描线外部资源文件（程序化生成，不依赖 wav/png 资产）
- 步骤 7、8 的对话逻辑（属于第二章叙事对话，不属于微游戏 overlay）
- 镜像空间场景根节点、色温过渡、林澈 NPC 双态材质（属于 F-11）

## 验收标准

- [ ] 三个微游戏均无失败判定，只有"完成"状态；描线偏差或旋律错误只重置当次，不计入失败
- [ ] `MicroGameOverlay` 背景使用 `.ultraThinMaterial` 或 `liquidGlassPanel`，不使用 `UIBlurEffect`
- [ ] 三灯状态（`Ch2State.completedLights`）在暂停、退出、读档后与微游戏结果一致；恢复后灯光强度、光路、林澈 NPC 位置与完成状态一致
- [ ] 步骤 8 的选择结果正确写入 `GameNarrativeState.linCheTrust`（`.open/.neutral/.closed` 三种）
- [ ] 键盘替代输入可独立完成描线（节点逐段确认）和擦除（按住空格缓慢擦除）；旋律接唱提供"再听一次"，不以听力作为通关门槛
- [ ] 旋律灯最多 3 次提示后自动通过，且自动通过与玩家完成路径幂等，只写入一次结果
- [ ] 每个微游戏完成后 1 秒内 3D 场景响应（灯光强度提升、内心独白出现、光路向下一灯方向延伸）
- [ ] 系统 Reduce Motion 开启时，overlay 淡入淡出保持 0.3s，微游戏内部动画改为即时状态切换

## 设计约束

- `MicroGameOverlay` 为纯 SwiftUI 视图，不引入 SpriteKit；手势均通过 `DragGesture` / `TapGesture` 实现
- 微游戏内部不持有剧情事实；完成信号通过回调通知 `GameManager`，由 `GameManager.completeMicroGame(_:)` 幂等写入 `Ch2State`
- 暂停时（`activePauseReasons` 非空）overlay 及其内部计时一并冻结；覆盖层关闭后从剩余进度恢复，不重新开始
- `completeLight(_:)` / `completeMicroGame(_:)` 必须幂等：玩家完成与超时兜底同时触发时只写入一次
- 擦除保留 40% 是编剧意图（比较不会完全消失），不得以任何逻辑将其清零
