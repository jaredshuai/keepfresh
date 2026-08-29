# AGENTS.md

This file provides guidance to AI coding agents when working with code in this repository.

## 项目概述

**KeepFresh** — 物资保质期管理 App（HarmonyOS 原生应用）。

- **语言/UI**：ArkTS + ArkUI（声明式范式）
- **构建**：DevEco Studio / hvigor（工程配置为 `*.json5` + `hvigorfile.ts`）
- **本地存储**：RelationalStore（SQLite），物资数据不出设备
- **目标**：录入物资及保质期 → 自动计算到期日 → 临期分级提醒 → 减少过期浪费
- **工程结构**：标准 DevEco Studio 工程根目录（`AppScope/` + `entry/`）；hvigor wrapper（`hvigorw` 等）由 DevEco Studio 首次打开同步时自动生成；首次运行需在 DevEco Studio 中配置应用签名

## 代码结构（entry/src/main/ets/）

分层：model（领域模型，纯逻辑）/ common（无 `@kit` 依赖纯工具，Node 测试唯一可 import 层）/ db（RelationalStore 封装）/ service（平台绑定业务服务）/ pages（UI，全走 Theme 令牌）/ entryability（入口）。文件级清单见 `docs/agents/code-structure.md`（wire-guard 规则 7 校验其 .ets 路径真实性，增删文件需同步该文件，否则 CI 红）。

## 关键不变量（改动前必读）

1. **custom_fields 的键 = CustomField.id（非字段名）**。键语义操作必须走 `entry/src/main/ets/model/CustomField.ets` 契约函数；pages/ 与 service/ 裸下标访问会被 wire-guard 规则 6 拦截（#14 教训：键语义错配曾导致跨设备恢复静默丢值）
2. **软删除不入统计**：`is_deleted` 行不出现在首页/统计/提醒口径；备份导出为全集快照（含回收站行）
3. **状态机终态保护**：EMPTY / DISCARDED 不可逆，只能恢复为 ACTIVE
4. **到期日 = productionDate + shelfLife(Days|Months)**，分级与派生状态统一走 ExpiryService，页面不自算

## 踩坑沉淀地图（按场景触发，改代码前对号入座）

- 动 `pages/` 任何 UI → `docs/agents/arkui-pitfalls.md`（ArkUI 渲染陷阱：Button 胶囊 / @Builder 按值传参 / layoutWeight 轴向 / Scroll 居中等；design-guard 报错锚点即此文档条目）
- 动系统栏/全面屏（EntryAbility 窗口、沉浸式、避让）→ `docs/agents/arkui-pitfalls.md#fullscreen-immersive`（只刷窗口背景色不生效，必须全屏布局 + 页内避让）
- 新增/修改 Material 字段或 DB 表 → `CONTEXT.md`「新字段必改清单」；断链事故背景与修复记录见 `docs/audit-wiring.md`
- 动视觉样式（色值/圆角/阴影/版式）→ `DESIGN.md`；包豪斯审计背景见 `docs/audit-bauhaus.md`
- 好奇"为什么这么决策" → `docs/adr/`

## 测试与工具链

- `npm run ci` = design:check + wire:check + docs:check + test，提交前必跑
- **Node 测试仅能 import 无 `@kit.*` 依赖的纯模块**（test/loader.mjs 限制）：需测的逻辑应下沉 common/ 与 model/；service 层直接 import 会失败
- `npm run build` / `npm run build:release` — hvigor 自动探测（本项目本地 / DevEco 默认 / `DEVECO_HOME`）
- `npm run test` / `npm run design:check` / `npm run wire:check` / `npm run docs:check` 可单独执行

## Agent skills

- Issue 管理在 GitHub Issues（`jaredshuai/keepfresh`，`gh` CLI）：`docs/agents/issue-tracker.md`
- Triage 五标签词表：`docs/agents/triage-labels.md`
- 领域文档布局（`CONTEXT.md` + `docs/adr/`）：`docs/agents/domain.md`
- 复杂问题（调用方分析 / 重构影响 / 死代码判定）用 understand-codebase skill，三 MCP 交叉验证：`docs/agents/codebase-understanding.md`
- Dogfood 观测协议（拉使用日志 / 两周验证闭环）：`docs/dogfood.md`
