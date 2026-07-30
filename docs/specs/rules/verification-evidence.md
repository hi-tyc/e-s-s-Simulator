---
kind: autocode-spec-rule
id: verification-evidence
title: 验证证据规则
version: v1
category: verification
scope: feature-development
status: active
owner: product-engineering
appliesTo: [test, review, evidence, ui, frontend]
appliesToWorkflows: [feature-development-prepare, feature-implementation, test-generation-execution, multi-review, delivery-closure]
severity: blocking
evidenceRequired: [test-report, screenshot-report, review-conclusion, approval-reference]
blockOnFailure: true
source: autocode-target-repo-setup
reviewState: review-required
---

# 验证证据规则

完成声明必须由可复核证据支撑。测试、截图、评审和人工判断应写入 `.ac/tests/**`、`.ac/runs/**` 或目标仓库约定路径，并能回指当前 featurePath。

## 必须执行

- 实现前先确认实施计划里的验证命令、证据路径和阻塞条件。
- 测试报告、截图报告、视觉对照、明确审批事实和评审结论必须能回指 workflowRunId 与 featurePath。
- UI 改动必须至少提供浏览器截图或等价视觉证据；有设计源时还必须能对照相关 frame / 状态。
- 证据缺失、命令失败或验证环境不可用时，必须记录 blocker，不得用口头判断替代。

## 禁止

- 用 `summary.md`、`result.json` 或子代理预审报告替代人工计划确认事实。
- 用“测试没跑但代码看起来对”作为完成证据。
- 把无关测试、过期截图或无法回指 featurePath 的报告当作当前特性证据。
- 忽略失败命令继续进入完成评审。
