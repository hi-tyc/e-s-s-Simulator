# F-21 多平台适配基础（iPad 预置） — 数据模型

> 状态：final / accepted

## 新增类型

### `enum SwipeDirection`

```
SwipeDirection: Equatable
  - left
  - right
  - up
  - down
```

- 表示 iOS 触摸滑动方向，在 `ClassroomCoordinator.handleSwipe(direction:)` 内映射到 `CameraPose`
- 运行时输入值，不存档
- 无 `Codable` 需求

### `struct PasteboardBridge`

```
PasteboardBridge
  + static func copy(_ string: String)
```

- 纯静态工具，无实例字段
- 内部按 `#if os(macOS)` 分发到 `NSPasteboard.general` 或 `UIPasteboard.general`
- 无 `Codable` 需求，不持有任何状态

### typealias 组（`PlatformShims.swift`）

```
PlatformViewRepresentable  →  NSViewRepresentable（macOS）/ UIViewRepresentable（iOS）
PlatformView               →  NSView（macOS）/ UIView（iOS）
PlatformGestureRecognizer  →  NSGestureRecognizer（macOS）/ UIGestureRecognizer（iOS）
```

- 纯编译期类型别名，无运行时存储，不影响任何运行时内存布局

## 存档策略

本特性**不新增任何存档字段**。

`NarrativeSave.v1` 的结构体完全不变，存档 key `LateStudySimulator.NarrativeSave.v1` 保持不变。

`AccessibilityPreferences`（由 F-07 引入）中的 `keyboardAlternativeInput: Bool` 字段已存在于存档结构。iOS 运行时在初始化 `AccessibilityPreferences` 时将该字段强制为 `false`，但不回写存档——即 macOS 侧保存的该字段值在 iOS 侧被静默忽略，iOS 返回 macOS 后字段原值仍然保留。

## 数据一致性约束

- 本特性不引入新的跨章不变量
- `PasteboardBridge.copy(_:)` 是无副作用的工具调用，不写入游戏状态，不触发存档
- iOS 平台对 `keyboardAlternativeInput` 的强制 false 是运行时修正，不写入存档，macOS 存档兼容性不受影响
- `SwipeDirection` 仅存活于单次手势回调的调用栈内，不缓存到任何对象属性，不持久化
