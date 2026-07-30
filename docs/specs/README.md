---
kind: autocode-spec-index
version: v1
status: active
owner: product-engineering
scope: target-repo
source: autocode-target-repo-setup
reviewState: review-required
---

# 开发规范索引

`docs/specs/**` 是目标仓库开发规范事实源。AutoCode workflow、评审流程和开发人员应先读取这里的适用规范，再读取更细的 feature、requirement、design 或测试证据。

## 目录约定

- `docs/specs/rules/**`：可被开发和评审直接执行的规则。每个文件必须带 YAML frontmatter，声明 `kind`、`category`、`scope`、`appliesTo`、`status` 和 `reviewState`。
- `docs/specs/references/**`：可选的背景说明、示例和决策记录。不能替代 rules。
- `docs/specs/templates/**`：可选的规范模板。正式规则仍应落到 `rules/**`。

## Rule frontmatter 建议

新增或补充规则时，优先使用这些稳定字段，便于 AutoCode workflow 发现、筛选和回填证据：

- `kind: autocode-spec-rule`
- `id` / `title`：规则稳定标识和人读标题。
- `category`：规则分类，例如 `ui-design`、`design-system`、`verification`。
- `scope` / `appliesTo` / `appliesToWorkflows`：适用代码范围、任务类型和 workflow。
- `severity`：`blocking`、`important` 或 `advisory`。
- `evidenceRequired`：完成声明必须关联的证据类型。
- `blockOnFailure`：违反规则时是否必须阻塞。

## 持续补充

- 新增产品域、设计系统、测试工具或评审约束时，先补充 `docs/specs/rules/**`，再让 feature 计划引用它。
- 规则正文必须写清“必须执行”和“禁止”，不要只写背景说明。
- 规则冲突、缺失或需要豁免时，应在 `.ac/runs/**` 证据和评审结论中记录取舍。

## 执行规则

- 开始实现前，先读取与当前 diff 相关的 rules。
- UI 或前端改动必须读取 `rules/ui-design-conformance.md` 和 `rules/design-system-style.md`。
- 测试、截图、审查证据或 `.ac/tests/**` 产物必须读取 `rules/verification-evidence.md`。
- 规范缺失、冲突或无法判断适用性时，必须在实施计划或评审结论里记录缺口；不得静默按个人理解继续。
