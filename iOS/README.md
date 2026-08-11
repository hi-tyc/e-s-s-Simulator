# 晚自习模拟器 iOS

这是现有 macOS Swift Package 的 iPhone/iPad 触控移植目标。当前工程已经直接编译并使用原版 `GameManager`、`GameModels`、`PrologueModels` 和 `SpatialAudioManager`；iOS 层只负责 UIKit/触控窗口适配。

## 当前范围

- 横屏 SwiftUI 界面与 SceneKit 第一视角教室。
- 在 3D 场景中拖动环视，也可用底部方向按钮快速定位。
- 第一章「静音的教室」六步主线：观察林澈、辨认声音、自我调节、低声问候、确认纸条、跟随离开。
- 写作业、观察、深呼吸、喝水等非主线行动会改变隐藏状态。
- 不直接展示心理数值，改用视觉、听觉描述与内心独白反馈。
- iPhone 和 iPad，最低 iOS 17。
- 进入后台自动暂停计时，回到前台继续；低电量模式下自动降到 30 FPS 并关闭抗锯齿。
- 双指缩放调整视野，双击回正视角；行动和结局使用系统触觉反馈。

## 运行

1. 用 Xcode 打开 `LateStudySimulatorIOS.xcodeproj`。
2. 在 Signing & Capabilities 中选择自己的开发团队，并按需修改 Bundle Identifier。
3. 选择一个 iPhone/iPad 模拟器或已连接设备后运行。

命令行构建验证：

```bash
xcodebuild \
  -project iOS/LateStudySimulatorIOS.xcodeproj \
  -scheme LateStudySimulatorIOS \
  -sdk iphonesimulator \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO build
```

## 与 macOS 版本的关系

macOS 版本深度依赖 AppKit 的鼠标、键盘、窗口与音频输入层，因此 iOS 版目前采用独立的移动端表示层和轻量状态机。后续适合把跨平台领域逻辑抽成共享 Swift Package，再分别保留 AppKit 与 UIKit/触控适配层。

移动版当前直接使用原作的 `ContentView`、`ClassroomSceneView`、序章、学生/教师状态机、事件选择、NPC 状态、结局分析、回放和跨局 UserDefaults 记忆。AppKit 鼠标/窗口捕获已替换为 UIKit 拖动环视、捏合视野、虚拟摇杆、侧身/奔跑和交互按钮；Liquid Glass 在 iOS 17 下使用 material 兼容实现。
