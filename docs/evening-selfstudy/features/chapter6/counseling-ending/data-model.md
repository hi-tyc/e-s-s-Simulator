# F-19 苏念咨询与支持网络结局 — 数据模型

> 状态：final / accepted

## 新增类型

### Ch6State
```
struct Ch6State: Codable, Equatable
  mirrorApproached: Bool = false       // 走到镜子前（≤ 1m）
  counselingEntered: Bool = false      // 走进咨询室，不可逆
  chosenTopicIDs: [String] = []        // 已选咨询主题 ID，有序，最多 2 项，去重
  networkViewed: Bool = false          // 支持网络图已打开
  resourceConfirmed: Bool = false      // 玩家确认求助资源，章节结束门禁
```

### EndingType
```
enum EndingType: String, Codable, CaseIterable
  case emergencyHandoff       // 紧急服务介入路线
  case urgentHandoff          // 学校紧急响应路线
  case voluntaryAndShared     // 自愿同行 + 苏念有表达
  case unclearDisclosure      // 未明确披露但成人已接管
  case lowTrustHandoff        // 低信任由成人接管
  case didNotShare            // 苏念未说出自己的事
  case standardLight          // 普通路线已完成
  // 附注（不是独立主结局）
  case selfCareReminder       // 苏念未自我照顾时叠加
```

### CounselingTopic
```
struct CounselingTopic: Identifiable
  id: String                           // e.g. "parentRelation", "studyFatigue", "helpFear", "justShare", "sitQuietly"
  suNianSpeaks: String                 // 苏念对话文本
  teacherResponseType: TeacherResponseType
  setsSharedSelf: Bool                 // 除 sitQuietly 外均为 true

enum TeacherResponseType: String, Codable
  case listening    // 倾听式：「嗯。然后呢？」「这让你感觉怎么样？」
  case affirming    // 确认式：「你今天做的事，不是每个人都做得到的。」
```

### SupportResource
```
struct SupportResource: Codable, Identifiable
  id: String
  region: String                       // "CN" 或具体省市代码
  displayName: String
  number: String?                      // 如 "12356"
  url: String?
  reviewedAt: Date                     // ISO 8601
  sourceURL: String                    // 政策文件 URL
```

## 存档策略

| 字段 / 类型 | 是否存档 | 存入位置 |
|---|---|---|
| `Ch6State` | 是 | `NarrativeSave.chapterState` 的 `.epilogue(Ch6State)` case |
| `EndingType` | 否（运行时派生） | 不存档，读档后由 `EndingSelector.select(narrative:)` 重新计算 |
| `SupportResource` 列表 | 否（本地配置） | 不进入存档，每次启动从 Bundle 加载 |
| `GameNarrativeState.suNianSharedSelf` | 是 | 已在 `NarrativeSave.narrative` 中，由 F-01 管理 |

存档 key：`LateStudySimulator.NarrativeSave.v1`（与全局存档共用，由 F-01 定义）。

自动存档时机：`counselingEntered` 写入后、每个 `chosenTopicIDs` 追加后、`resourceConfirmed` 写入后。每次都是幂等 step commit，由 `GameManager.completeStep(_:result:)` 触发。

## 数据一致性约束

- `counselingEntered` 一旦写入 `true` 不可回退；若读档校验发现 `counselingEntered == false` 而 `chosenTopicIDs` 非空，判定存档损坏，回退到 `lastValid`。
- `chosenTopicIDs` 元素个数不得超过 2，且不得包含重复值；写入前由 `CounselorDialogueSystem` 校验，违反时忽略本次追加并记录 `#if DEBUG` 断言。
- `resourceConfirmed == true` 是 `GameManager.transitionChapter(from: .epilogue, result:)` 的唯一完成门禁；不得在玩家未确认时自动推进到主菜单。
- `GameNarrativeState.supportHandedOff` 必须在进入第六章时为 `true`；章节转换门禁（F-01）拦截不满足条件的转换，第六章本身不重复检查。
- `SupportResource.reviewedAt` 超过 6 个月时，`SupportResourceCatalog.isExpired` 返回 `true`；Release 构建脚本检测到任何过期资源时拒绝打包，但不影响 `Ch6State` 的逻辑运行。
