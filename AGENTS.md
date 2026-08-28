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

> 本节由实际文件枚举生成（2026-08-28，25 个 .ets）。wire-guard 规则 7 校验本文档列出的 .ets 路径真实存在（文档→代码单向）；**新增/删除文件时同步本节，删除文件而忘改文档会直接 CI 红**。

**model/（领域模型，纯逻辑）**
- `entry/src/main/ets/model/Material.ets` — 物资数据模型、状态机（active/opened/empty/discarded）、分类/位置/单位预设、临期阈值常量
- `entry/src/main/ets/model/CustomField.ets` — 自定义字段模型与校验；含 custom_fields 键语义契约（编解码 / 值键二次映射）

**common/（无 @kit 依赖的纯工具，Node 测试唯一可 import 层）**
- `entry/src/main/ets/common/DateUtils.ets` — 日期字符串工具（todayStr / addDays / diffDays / addMonths）
- `entry/src/main/ets/common/InputNormalize.ets` — 输入归一化（文本/非负整数/可空文本）
- `entry/src/main/ets/common/QuantityUnit.ets` — 数量单位解析与格式化
- `entry/src/main/ets/common/SearchFilter.ets` — 关键词过滤（跨 name/category/location/note）
- `entry/src/main/ets/common/Validation.ets` — 输入校验纯函数（临期天数范围常量 + 校验；service 层同名方法只转发）
- `entry/src/main/ets/common/Theme.ets` — 包豪斯设计令牌（页面禁写死色值/圆角，design-guard 执法）
- `entry/src/main/ets/common/CategoryIcons.ets` — 分类图标映射
- `entry/src/main/ets/common/HardShadow.ets` — 硬阴影容器组件（pages/ 禁手写阴影样板，design-guard 规则 4 执法）

**db/（存储层）**
- `entry/src/main/ets/db/MaterialDb.ets` — RelationalStore 封装（materials V2 / custom_field_defs / name_defs 三表 CRUD、迁移、软删除，单例；唯一允许裸 JSON 编解码 custom_fields 列之处）

**service/（平台绑定业务服务）**
- `entry/src/main/ets/service/ExpiryService.ets` — 到期计算、临期分级、状态机派生、统计、风险排序
- `entry/src/main/ets/service/SettingsService.ets` — 用户配置持久化（临期阈值等，Preferences）
- `entry/src/main/ets/service/ReminderService.ets` — 代理提醒（ReminderKit 每日汇总调度）
- `entry/src/main/ets/service/NotificationService.ets` — 通知授权与临期通知发布
- `entry/src/main/ets/service/BackupService.ets` — 备份导出/导入（JSON schema v2，DocumentViewPicker 免权限）
- `entry/src/main/ets/service/ScanService.ets` — 扫码快填（ScanKit + 条码历史建议）

**pages/（UI，7 页，全部走 Theme 令牌）**
- `entry/src/main/ets/pages/Index.ets` — 首页：状态分组列表 + 搜索筛选 + 提醒设置入口
- `entry/src/main/ets/pages/AddItem.ets` — 新增/编辑：扫码预填 + 自定义字段渲染
- `entry/src/main/ets/pages/ItemDetail.ets` — 详情：状态操作、编辑入口、删除/软删
- `entry/src/main/ets/pages/RecycleBin.ets` — 回收站：恢复 / 彻底删除
- `entry/src/main/ets/pages/Settings.ets` — 设置中心：阈值/提醒/备份/管理与字段入口
- `entry/src/main/ets/pages/CustomFieldManager.ets` — 自定义字段 CRUD 与排序
- `entry/src/main/ets/pages/CategoryManager.ets` — 分类/位置管理（name_defs）

**entryability/**
- `entry/src/main/ets/entryability/EntryAbility.ets` — 入口 Ability；通知 want 参数 filterLevel → AppStorage 深链状态 Tab

## 关键不变量（改动前必读）

1. **custom_fields 的键 = CustomField.id（非字段名）**。键语义操作必须走 `entry/src/main/ets/model/CustomField.ets` 契约函数；pages/ 与 service/ 裸下标访问会被 wire-guard 规则 6 拦截（#14 教训：键语义错配曾导致跨设备恢复静默丢值）
2. **软删除不入统计**：`is_deleted` 行不出现在首页/统计/提醒口径；备份导出为全集快照（含回收站行）
3. **状态机终态保护**：EMPTY / DISCARDED 不可逆，只能恢复为 ACTIVE
4. **到期日 = productionDate + shelfLife(Days|Months)**，分级与派生状态统一走 ExpiryService，页面不自算

## 测试与工具链

- `npm run ci` = design:check + wire:check + test，提交前必跑
- **Node 测试仅能 import 无 `@kit.*` 依赖的纯模块**（test/loader.mjs 限制）：需测的逻辑应下沉 common/ 与 model/；service 层直接 import 会失败
- `npm run build` / `npm run build:release` — hvigor 自动探测（本项目本地 / DevEco 默认 / `DEVECO_HOME`）
- `npm run test` / `npm run design:check` / `npm run wire:check` 可单独执行

## Agent skills

### Issue tracker

Issues live in GitHub Issues (`jaredshuai/keepfresh`), managed via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default five-label vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context layout: `CONTEXT.md` + `docs/adr/` at the repo root (created lazily by `/domain-modeling`). See `docs/agents/domain.md`.

### Codebase understanding (REQUIRED for complex problems)

When solving non-trivial problems — codebase orientation/discovery, caller analysis, refactor impact analysis, dead-code detection, or any "who uses X / what breaks if I change Y" question — you MUST use the `understand-codebase` skill instead of relying on grep and single-file reads alone.

The skill orchestrates three MCPs, and all three are expected to participate (cross-verified, not single-source):

- **fast-context** — semantic search (concept → file, Chinese/English, cross-layer)
- **codegraph** — call graph + symbol index (LSP-backed, precise file:line)
- **codebase-memory** — graph database + static metrics (Cypher queries, blast radius)

Operational rules:

- On first contact with this repo (or after major changes), run `index_repository(repo_path, mode: "moderate")` and confirm with `index_status` before using codebase-memory tools.
- An answer is reliable only when at least two independent sources agree, or one Tier-1 source is verified against `rg`. Negative answers ("no callers", "dead code") must always be cross-verified before any irreversible action (rename, delete, migrate).
- Simple, single-file edits with a known path do not need this skill — plain read/grep is fine.
