# F-19 苏念咨询与支持网络结局 — 技术设计

> 状态：final / accepted

## 实现方案

章节入口由 `GameManager.startChapter(.epilogue)` 触发，初始化 `Ch6State` 并注册本章 SceneDirector Beat。整个终章围绕五步线性推进，每步完成后幂等调用 `completeStep(_:result:)` 写入状态并触发自动存档。

结局逻辑集中在 `EndingSelector.select(state: GameNarrativeState) -> EndingType`，按固定优先级顺序命中唯一主结局，再独立判断是否追加自我照顾附注，不依赖外部可观察对象。支持网络图通过 `SupportNetworkView` 从 `GameNarrativeState` 读取节点强度，不写入状态。

`CounselorDialogueSystem` 管理咨询对话的多主题独立回应，话题去重和 2 项上限由系统维护，与信任值无关。心理老师的保密边界脚本以资源文件形式接入，审核日期由 `SupportResourceCatalog` 同一机制管理。

`SupportResourceCatalog` 在应用启动时从本地 JSON 加载，校验每条资源的 `reviewedAt`；Release 打包时由构建脚本检查，超期则拒绝打包。

## 关键类型与接口

```
struct Ch6State: Codable, Equatable
  - mirrorApproached: Bool
  - counselingEntered: Bool
  - chosenTopicIDs: [String]      // 最多 2 项，去重
  - networkViewed: Bool
  - resourceConfirmed: Bool

enum EndingType: String, CaseIterable
  // 对应 7 种主结局 + 附注标志
  case emergencyHandoff, urgentHandoff, voluntaryAndShared
  case unclearDisclosure, lowTrustHandoff, didNotShare, standardLight
  case selfCareReminder  // 附注，叠加在主结局之后

struct EndingSelector
  static func select(state: GameNarrativeState) -> EndingType
  static func needsSelfCareReminder(state: GameNarrativeState) -> Bool

struct SupportNetworkView: View
  - init(narrative: GameNarrativeState)
  // 五节点 Canvas 图，节点强度由 linCheListenScore / companionChoice / safetyRoute 派生

struct CounselorDialogueSystem
  func availableTopics(chosen: [String]) -> [CounselingTopic]
  func response(for topic: CounselingTopic) -> CounselorResponse

struct SupportResource: Codable
  - id: String
  - region: String
  - displayName: String
  - number: String?
  - url: String?
  - reviewedAt: Date
  - sourceURL: String

struct SupportResourceCatalog
  static func load() throws -> [SupportResource]
  static func isExpired(_ resource: SupportResource) -> Bool   // 超 6 个月
  func primaryHotline() -> SupportResource                     // 返回 12356 条目

struct SupportResourceView: View
  - init(catalog: [SupportResource])
  // 包含 NSPasteboard 复制按钮
```

## iPad 适配注意事项

本特性无特定 iPad 约束，遵循全局 PlatformViewRepresentable 规范即可。支持网络图使用 SwiftUI Canvas，在 iPad 上自动适配更大画布尺寸；求助资源复制按钮使用 `NSPasteboard`（macOS），若未来 iPad 版本需要 `UIPasteboard`，由 F-21 多平台适配统一处理。

## 与现有代码的关系

**复用：**
- `GameNarrativeState`（F-01）作为唯一输入，`EndingSelector` 读取 `safetyRoute`、`jiangYueResolutionPath`、`suNianSharedSelf`、`suNianSelfCared`
- `ChapterRuntimeState.epilogue(Ch6State)` 使用 F-01 定义的枚举扩展
- `liquidGlassPanel` 辅助器供结局卡片和资源卡片使用
- `SceneDirector` Beat 注册（F-02）管理步骤 1 的 SceneKit 镜面涟漪动画触发

**新增：**
- `EndingSelector`、`CounselorDialogueSystem`、`SupportNetworkView`、`SupportResourceView`、`SupportResourceCatalog` 均为新类型
- `NarrativeCameraMode.waitingSeated` 已在 F-04 定义，步骤 2 切换为 `dialogueFirstPerson`
- 咨询室场景根节点（`counselingRoom`）为新资产，由 `ClassroomCoordinator` 管理显示/隐藏

**修改：**
- `GameManager.startChapter(.epilogue)` 增加 `Ch6State` 初始化和本章 Beat 注册
- `ContentView` 增加支持网络图和结局卡片的条件渲染分支

## 风险与注意事项

- 保密边界脚本必须在 Release 前获得书面审核，未配置时构建失败是硬性门禁，不可跳过
- `EndingSelector` 优先级顺序必须与 §6.4 表格严格一致，多结局条件重叠时行为确定性是高频测试场景
- 支持网络图节点强度派生逻辑依赖 `linCheListenScore`，需覆盖得分为 0 的极端场景（节点灯亮但强度最低）
- `SupportResourceCatalog` 审核日期校验逻辑须同时覆盖 Debug 提示和 Release 拦截两条路径
- 咨询室场景根节点复用走廊场景还是新建，是场景资产风险的延续，工期估算时需确认
