<!-- BEGIN AUTOCODE MANAGED BLOCK: target-repo-setup -->
## AutoCode V2 目标仓库规则

- 标准过程产物写入 `.ac/**`；测试过程证据写入 `.ac/tests/**`。
- 开发规范事实源位于 `docs/specs/**`；开始实现或评审前，必须读取与当前任务相关的 rules，尤其是 UI、公共样式和验证证据规则。
- 产品特性资产位于 `docs/features/**`，正式写入前必须经过评审。
- 产品测试资产位于 `Tests/**`，正式写入前必须声明特性归属并经过评审。
- `docs/requirement/**` 是受保护需求事实源；普通 setup 和普通开发只能读取。
- legacy risk path 只做只读探测：`.autocode/**`、`.claude/notepads/**`、`docs/bugfix/**`。
- 任何计划写入审批边界外路径的行为都必须 `ALERT_AND_BLOCK`。
- hooks 只能增强显式检查项（gate）；不能替代 workflow gate 证据。
- 任何 AutoCode 任务（需求、设计、特性、缺陷、测试、交付、setup 或 PMS 协作）开始前，必须先加载 `autocode:using-autocode` Skill 完成入口识别，再进入最具体的 AutoCode Skill。Claude Code 会话由插件 SessionStart hook 自动注入该纪律；Codex 通过已安装 plugin 暴露的 Skill 加载，slash command 不可用时直接使用 `using-autocode` Skill。
<!-- END AUTOCODE MANAGED BLOCK: target-repo-setup -->
