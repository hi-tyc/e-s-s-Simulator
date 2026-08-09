# F-09 内心独白与线索便签 — 数据模型

> 状态：final / accepted

## 新增类型

F-03 已定义 `InnerMonologueItem` 和 `ClueCard`（均为 `Equatable`，后者为 `Identifiable`）。F-09 新增两个内容目录枚举，仅含静态常量，无实例存储，不需要 `Codable`。

### MonologueCatalog

```swift
enum MonologueCatalog {
    // 第一章各步骤独白（key 格式：chapter.step.eventName）
    static let ch1: [String: InnerMonologueItem] = [
        "ch1.step1.linCheObserved": InnerMonologueItem(
            id: "ch1.step1.linCheObserved",
            text: "林澈今天只翻了一页书。从晚自习开始到现在，一直是同一页。"
        ),
        "ch1.step2.soundObserved": InnerMonologueItem(
            id: "ch1.step2.soundObserved",
            text: "……有人在哭？还是我听错了？"
        ),
        "ch1.step3.selfCared": InnerMonologueItem(
            id: "ch1.step3.selfCared",
            text: "我也不太好……不是说我有什么大事，就是，有点压着。"
        ),
        "ch1.step4.b.linCheOpen": InnerMonologueItem(
            id: "ch1.step4.b.linCheOpen",
            text: "他说「嗯」——不是敷衍，是真的认了。"
        ),
        "ch1.step4.other": InnerMonologueItem(
            id: "ch1.step4.other",
            text: "他说没事。也许真的没事。也许不是。"
        ),
        "ch1.step5.notePicked": InnerMonologueItem(
            id: "ch1.step5.notePicked",
            text: "这不是传给我的。但我看见了。"
        ),
    ]

    // 第三章步骤 1 独白
    static let ch3Step1NoteClue = InnerMonologueItem(
        id: "ch3.step1.noteClue",
        text: "这是从某本蓝格笔记本上撕下来的。我见过有人用这种本子……"
    )

    // 第三章步骤 2 独白
    static let ch3Step2Confirmed = InnerMonologueItem(
        id: "ch3.step2.jiangYueConfirmed",
        text: "是他的本子。纸条是江越写的。"
    )
}
```

### ClueCatalog

```swift
enum ClueCatalog {
    // 第一章
    static let ch1Step1 = ClueCard(
        id: "ch1.step1.clue",
        title: "林澈今晚一直看着同一页",
        detail: nil
    )
    static let ch1Step2 = ClueCard(
        id: "ch1.step2.clue",
        title: "右侧传来被掩盖的声音",
        detail: nil
    )
    static let ch1Step5 = ClueCard(
        id: "ch1.step5.clue",
        title: "匿名求助纸条",
        detail: "心里很难受，但我不知道找谁说。"
    )

    // 第三章
    static let ch3Step1 = ClueCard(
        id: "ch3.step1.clue",
        title: "纸条来自蓝格笔记本",
        detail: "背面有 HB 铅笔印，角落有撕痕。"
    )
}
```

## 存档策略

| 字段 | 存档位置 | 说明 |
|---|---|---|
| `clueCards: [ClueCard]` | 进入 `NarrativeSave` | 已收集的便签列表，恢复后 HUD 直接展示，不重播音效 |
| `completedMonologueIDs: Set<String>` | **不存档**，运行态 | 章节切换时清空；恢复存档后清空即可，独白不需要恢复显示 |
| `pendingMonologue: InnerMonologueItem?` | **不存档**，运行态 | 恢复存档后设为 nil，正在播放的独白不恢复 |
| `monologueRemainingTime: TimeInterval?` | **不存档**，运行态 | 存档发生时正在播放的独白被丢弃；恢复后无残余独白 |

存档 key：`LateStudySimulator.NarrativeSave.v1`（由 F-01 定义的 `NarrativeSave.chapterState` 内已包含 `clueCards` 的章节状态）。

便签列表随 `NarrativeSave.chapterState` 中对应章节状态一同序列化，无独立 key。

## 数据一致性约束

- `ClueCard.id` 全局唯一，格式固定为 `chapter.step.clue`（或 `chapter.step.序号`）；`ClueCatalog` 是唯一可信来源，禁止在别处构造同名 ID 的 `ClueCard`
- `clueCards` 最多 5 条，超出时静默忽略，不回滚已有便签
- `MonologueCatalog` 中的 `InnerMonologueItem.id` 与 `completedMonologueIDs` 的 key 格式保持一致；任何新增独白先在 `MonologueCatalog` 注册，再调用 `presentMonologue`
- `ClueCard.detail` 中展示的纸条内容与 `GameNarrativeState.noteContent` 保持一致（第一章步骤 5 便签的 `detail` 是纸条摘录，不得与实际纸条内容矛盾）
