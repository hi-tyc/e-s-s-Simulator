# 晚自习模拟器 iOS / iPadOS

这是晚自习模拟器的移动端版本，使用 SwiftUI、UIKit 和 SceneKit，支持 iPhone 与 iPad 横屏运行。

## 打开与构建

用 Xcode 打开 `iOS/LateStudySimulatorIOS.xcodeproj`，选择 `LateStudySimulatorIOS` scheme，然后选择 iPhone 或 iPad 模拟器运行。

命令行验证：

```bash
xcodebuild \
  -project iOS/LateStudySimulatorIOS.xcodeproj \
  -scheme LateStudySimulatorIOS \
  -sdk iphonesimulator \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO build
```

最低系统版本为 iOS 17。iPhone 使用紧凑 HUD、虚拟摇杆、快速移动和侧边压力提示；iPad 使用更宽的横屏布局。详细说明见 [iOS/README.md](iOS/README.md)。

## 目录

- `iOS/`：iOS/iPadOS Xcode 工程与移动端适配层
- `Sources/LateStudySimulator/`：移动端使用的共享游戏逻辑、SceneKit 场景和音频资源

本分支只包含 iOS/iPadOS 构建所需内容，不包含 macOS SwiftPM 工程和 macOS 专属资源。
