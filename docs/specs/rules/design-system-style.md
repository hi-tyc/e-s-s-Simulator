---
kind: autocode-spec-rule
id: design-system-style
title: 公共组件和样式规则
version: v1
category: design-system
scope: frontend
status: active
owner: product-engineering
appliesTo: [ui, frontend, css, component, layout]
appliesToWorkflows: [feature-development-prepare, feature-implementation, multi-review]
severity: blocking
evidenceRequired: [component-style-contract, code-review, ui-screenshot-report]
blockOnFailure: true
source: autocode-target-repo-setup
reviewState: review-required
---

# 公共组件和样式规则

界面实现必须优先遵循目标仓库已有设计系统、公共组件、页面布局模式和样式 token。没有 UI 设计稿时，这条规则仍然适用。

## 必须执行

- 写 UI 前，先读取相邻页面、同类表格 / 表单 / 弹窗 / Tab / 空态实现、公共组件目录、全局 CSS、CSS module、theme、token 或页面级样式。
- 使用 CSS 类名前，必须确认类真实存在，或在本次 diff 中明确定义。
- 复用公共组件和页面级容器；新增局部样式时，说明为什么现有模式不能覆盖。
- UI review 必须检查布局容器、间距、状态样式、空态、加载态、错误态和操作区是否对齐系统模式。

## 禁止

- 只拼零散 Button、Table 或 Badge，跳过页面级布局和公共样式。
- 使用不存在的 CSS 类导致界面退化为原生排版。
- 新增一套与目标仓库风格冲突的局部视觉语言。
- 在没有证据的情况下声称“公共组件不可用”。
