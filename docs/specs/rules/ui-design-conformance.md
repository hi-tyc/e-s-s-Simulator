---
kind: autocode-spec-rule
id: ui-design-conformance
title: UI 设计一致性规则
version: v1
category: ui-design
scope: frontend
status: active
owner: product-engineering
appliesTo: [ui, frontend, page, modal, component]
appliesToWorkflows: [feature-development-prepare, feature-implementation, multi-review]
severity: blocking
evidenceRequired: [ui-design-evidence, frame-state-mapping, ui-screenshot-report, visual-review]
blockOnFailure: true
source: autocode-target-repo-setup
reviewState: review-required
---

# UI 设计一致性规则

当目标特性涉及界面开发，且仓库存在 `docs/ui-design/**/*.pen`、`docs/ui-design/**/ui-prototype.md` 或用户在对话 / context 中明确给出 UI 设计稿时，研发和验证必须以该设计源为约束。

## 必须执行

- 先确认设计源是否与当前 feature、requirement 或用户描述相关；仅发现候选设计源时，必须取得人工相关性结论。
- 相关设计源存在时，必须把 Pencil frame 或用户设计状态映射到 route、modal、tab、表格、空态、错误态或当前特性涉及的 UI 状态。
- 写 UI 源码前，必须读取 frame / 状态映射、公共组件契约、公共样式契约和视觉证据要求。
- 实现完成后，必须提供浏览器截图、Pencil frame 对照、人工视觉证据或等价报告。
- 如果设计源存在但无法导出、无法识别 frame，或证据不足以判断一致性，必须 `ALERT_AND_BLOCK` 并回到计划评审。

## 禁止

- 只写“遵循设计”而不列 frame、目标页面和证据路径。
- 用单元测试通过、接口可用或页面文字出现替代视觉验证。
- 把仓库中任意 `.pen` 文件静默当作无关设计跳过确认。
- 在相关设计源存在时按个人审美重画界面。
