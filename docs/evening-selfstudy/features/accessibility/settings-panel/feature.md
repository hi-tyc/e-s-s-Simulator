# F-07 辅助设置面板

> 状态：final / accepted
> 实现阶段：Phase 1（序章阶段）
> 依赖特性：F-01 叙事状态机底座、F-02 SceneDirector Beat 系统、F-03 MainQuestHUD

## 产品能力描述

辅助设置面板让玩家在序章段落 7（"暂停与辅助"）首次接触四项无障碍控件（方向字幕、音量、减少动态效果、键盘替代输入），并在整个游戏任意时刻通过暂停菜单调整。修改立即生效，并在会话与存档之间持久化。

## 功能边界

**包含：**
- 四项辅助控件的显示与交互：方向字幕开关、三通道音量（对白/环境/提示音）、减少动态效果开关、键盘替代输入开关
- 序章段落 7 中的非遮挡式首次引导入口（右下角浮现，不阻断游戏流程）
- 暂停菜单中的常驻设置入口
- 辅助偏好写入 `PrologueState` 并持久化到存档
- 系统 Reduce Motion 检测：减少动态效果默认跟随系统设置
- `AccessibilityPreferences` 结构体持有偏好值，供 SceneDirector 和场景动画读取

**不包含：**
- VoiceOver 的 rotor 配置（由系统负责，不在本特性范围）
- 字幕内容编辑或字体大小调整（字幕内容由音频事件提供，字号跟随系统动态字号）
- 键盘映射重绑定（快捷键固定在枚举 `shortcut` 属性）
- 全局音频混音曲线（属于 `SpatialAudioManager` 职责）

## 验收标准

- [ ] 序章段落 7 时，设置提示从右下角无遮挡地浮现；玩家可打开设置，也可按"继续"跳过，两种选择都不中断主线
- [ ] 四项控件在打开设置面板后立即可操作，修改后效果在不关闭面板的情况下实时生效（方向字幕出现/消失、音量变化可听到、动画立即切换为淡入淡出）
- [ ] 减少动态效果开启时，镜头推拉、转场和节点动画替换为 0.2-0.4 秒淡入淡出；关闭后恢复原始动画
- [ ] 键盘替代输入开启后，序章全部可交互节点可仅用键盘完成（无需鼠标拖动）
- [ ] 辅助偏好在游戏退出后重新启动时保持不变（持久化到 `NarrativeSave.v1`）
- [ ] 在任意章节从暂停菜单打开设置面板，修改后关闭，游戏从暂停前的精确状态继续，Beat 剩余时间不重置
- [ ] 首次未打开设置（按"继续"）时，`accessibilityTutorialAcknowledged` 仍写为 true，不重复展示首次引导

## 设计约束

- 设置面板使用 `liquidGlassPanel(cornerRadius:tint:)` 样式，不引入独立背景或 UIBlurEffect
- 序章引导提示不得遮挡视野中央或 HUD 主任务区；必须以极简形式（图标 + 一行文字）从右下角出现
- 暂停时叙事计时（SceneDirector Beat）冻结，设置面板的打开/关闭通过 `activePauseReasons.insert(.pauseMenu)` / `removePauseReason(.pauseMenu)` 管理，不使用额外 Bool 暂停接口
- `AccessibilityPreferences` 变更必须通过 `GameManager` 写入，不允许视图层直接修改存档状态
- 减少动态效果由 `SceneDirector` 和场景过渡逻辑读取 `AccessibilityPreferences.reduceMotion`，不在每处动画硬编码判断
