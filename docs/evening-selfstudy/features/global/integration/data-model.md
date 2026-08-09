# F-20 全局集成：转场/音频/无障碍 — 数据模型

> 状态：final / accepted

## 新增类型

本特性以补全和集成为主，新增独立类型较少。

### AudioCueKind 扩展（新增 case）

在 `GameModels.swift` 的现有 `AudioCueKind` 枚举中补充缺失 case：

```
.bell          — 上课/下课铃声，从讲台方向播放；缺少资源文件时程序化回退（短促方波）
.noteDrop      — 纸条落桌声，前排椅子移动音效；缺少时程序化回退（摩擦+碰撞组合）
.crying        — 压低的鼻息，低强度 0.3s，从右侧方向播放
.chair         — 椅子移动声，从前排方向播放
```

不新增 `Codable` 包装，`AudioCueKind` 已是 `RawRepresentable + Codable`。

### SupportResourceEntry（若 F-19 未提供，此处补全）

```
struct SupportResourceEntry: Codable, Identifiable {
    let id: String
    let region: String
    let name: String
    let phoneNumber: String?
    let url: String?
    let notes: String?
    let reviewedAt: Date
    let sourceURL: String
}
```

`Codable`，只读，从本地 JSON 配置文件加载，不进入 `NarrativeSave`。

### SceneTransitionCheckpoint（运行时，不存档）

```
struct SceneTransitionCheckpoint {
    let fromChapter: ChapterID
    let toChapter: ChapterID
    let phase: TransitionPhase   // .prepare / .commit / .cleanup
    let startedAt: Date
}

enum TransitionPhase { case prepare, commit, cleanup }
```

运行时状态，仅用于崩溃恢复诊断（通过 `lastValid` 槽恢复），不进入 `NarrativeSave`。

## 存档策略

本特性不新增 `NarrativeSave` 字段。所有新增字段均属于运行时状态：

| 字段 / 状态 | 存档策略 |
|---|---|
| `SceneTransitionCheckpoint` | 不存档；崩溃恢复依赖 `lastValid` 槽 |
| `SupportResourceEntry` 列表 | 不存档；从本地 JSON 配置文件每次启动加载 |
| `AccessibilitySettings.directionalSubtitles` | 已由 F-07 存档（`UserDefaults`，非 `NarrativeSave`） |
| `AccessibilitySettings.reduceMotion` | 已由 F-07 存档，跟随系统设置 |
| `AudioCueKind` 新增 case | 枚举值，不需要额外存档 |

**自动存档时机**（沿用 F-01 规则，本特性不变更）：
- 每个步骤完成后
- 章节切换的 `commit` 完成后（`prepare` 阶段不存档）
- 应用进入后台时

存档 key：`LateStudySimulator.NarrativeSave.v1`（不变），`SupportResourceCatalog` 使用独立配置文件，不写入 UserDefaults。

## 数据一致性约束

- **转场原子性**：`scenePresentation.chapter` 与 `quest.currentChapter`、`chapterState` case 必须始终一致；`commit` 阶段以单次 `NarrativeSave` 编码保证原子性
- **safetyRoute 不可变**：F-01 已约束 `safetyRoute` 写入后不可更改；本特性的第四→五章转场不得修改该字段，只读取以确定转场目标场景根节点
- **转场期间热点互斥**：`prepare` 阶段目标章节场景根可见但所有热点处于不可交互状态（`isEnabled = false`）；`commit` 后方可开放，`cleanup` 后旧章热点随节点一起移除
- **音频状态一致性**：跨场景音频切换与 `scenePresentation.activeSceneRootID` 变化绑定；若存档恢复后 `activeSceneRootID` 为镜像空间，`SpatialAudioManager` 必须在恢复时重新叠入镜像音轨，不依赖切换事件
