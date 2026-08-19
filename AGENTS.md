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

- `model/Material.ets` — 物资数据模型、分类/单位预设、临期阈值常量
- `common/DateUtils.ets` — 日期字符串工具（todayStr / addDays / diffDays）
- `db/MaterialDb.ets` — RelationalStore 封装（materials 表 CRUD，单例）
- `service/ExpiryService.ets` — 到期计算、分级（已过期 / 临期 / 安全）、统计
- `service/NotificationService.ets` — 通知授权与临期通知发布
- `pages/` — Index（首页列表）/ AddItem（新增与编辑）/ ItemDetail（详情与删除）

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
