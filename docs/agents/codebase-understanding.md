# 复杂问题的代码库理解（understand-codebase skill）

> 从根 AGENTS.md 外迁（渐进式披露：仅复杂问题场景按需加载）。

When solving non-trivial problems — codebase orientation/discovery, caller analysis, refactor impact analysis, dead-code detection, or any "who uses X / what breaks if I change Y" question — you MUST use the `understand-codebase` skill instead of relying on grep and single-file reads alone.

The skill orchestrates three MCPs, and all three are expected to participate (cross-verified, not single-source):

- **fast-context** — semantic search (concept → file, Chinese/English, cross-layer)
- **codegraph** — call graph + symbol index (LSP-backed, precise file:line)
- **codebase-memory** — graph database + static metrics (Cypher queries, blast radius)

Operational rules:

- On first contact with this repo (or after major changes), run `index_repository(repo_path, mode: "moderate")` and confirm with `index_status` before using codebase-memory tools.
- An answer is reliable only when at least two independent sources agree, or one Tier-1 source is verified against `rg`. Negative answers ("no callers", "dead code") must always be cross-verified before any irreversible action (rename, delete, migrate).
- Simple, single-file edits with a known path do not need this skill — plain read/grep is fine.
