# 跨层接线审计报告（Wiring Audit）

日期：2026-08-27 · 分支：`feat/pantry-logic-port` · 方法：封闭世界接线矩阵
触发背景：pantry-logic 移植后用户肉眼发现"管理页自定义分类在录入表单不生效"（源头断链：DB 写了 `name_defs`，页面读硬编码）。本审计用可复核的枚举法排查**全部同类问题**，并把不变量固化为 CI 守护（`scripts/wire-guard.js`）。

审计由两个独立 agent 交叉验证（矩阵法 + 集合差集法），两法均独立命中已知断链，结论取并集。

---

## 一、方法

**封闭世界**：不从"哪里可疑"出发，从定义处枚举全部数据元素全集（111 条），每个元素占矩阵一行，逐格核查 9 个生命周期环节。每格必须处于 ✅（附 file:line 证据）/ 🔴（应接通未接通）/ ⚫（N.A. 附理由）三态之一——**遗漏在结构上不可能**，因为一个字段必然占一行，一行必然被逐格填完。

**断链三形态**（grep "零调用者"只能抓第一种，本审计三种全查）：

| 形态 | 例子 |
|---|---|
| 源头断：写了没人读 | `name_defs` 表无页面消费（已修复 6951706） |
| 中途断：链上环节丢字段 | 备份导出含 months、导入映射丢了 |
| 消费端断：读陈旧/硬编码源 | AddItem 读 `DEFAULT_CATEGORIES` 而非查库（已修复 6951706） |

**诚实边界**：本审计保证静态数据流接线完整性；不保证逻辑正确性（测试职责，55 用例）、视觉规范（design-guard 职责）、运行时行为。

---

## 二、Phase 0 · 全集（111 条）

- **A** Material 接口 19 字段（model/Material.ets L20-40）+ CustomField 6 字段 + NameDef 5 字段
- **B** 16 条常量/枚举（MaterialStatus 4、DerivedStatus 2、ExpiryLevel 3、DEFAULT_*×3、SHELF_PRESET_*×2、阈值×2、CUSTOM_FIELD_TYPES、BarcodeProduct 组）
- **C** DB 列 39 条：materials V2 建表 19 列 + migrate() 9 条 ALTER + custom_field_defs 6 列 + name_defs 5 列
- **D** MaterialDb 27 个 public 方法
- **E** 10 条持久化键/AppStorage 键/路由参数（settings 2、reminder 4、AppStorage 1、RouteParams 2、want 1）

---

## 三、Phase 1 · 接线矩阵（核心表：Material 字段）

列：①模型 ②DB双向映射 ③写入 ④渲染 ⑤派生 ⑥提醒 ⑦备份导出 ⑧备份导入 ⑨测试

| 字段 | ① | ② | ③ | ④ | ⑤ | ⑥ | ⑦ | ⑧ | ⑨ |
|---|---|---|---|---|---|---|---|---|---|
| id | ✅ | ✅ | ✅自增 | ✅路由 | ✅排序 | ⚫ | ✅ | ✅ | ✅ |
| name | ✅ | ✅ | ✅ | ✅ | ⚫搜索 | ⚫ | ✅ | ✅ | ✅ |
| category | ✅ | ✅ | ✅ | ✅ | ⚫ | ⚫ | ✅ | ✅ | ✅ |
| quantity(+text) | ✅ | ✅双写双读 | ✅归一化 | ✅ | ⚫ | ⚫ | ✅ | ✅ | ✅ |
| unit | ✅ | ✅ | ✅ | ✅ | ⚫ | ⚫ | ✅ | ✅ | ✅ |
| location | ✅ | ✅ | ✅ | ✅ | ⚫ | ⚫ | ✅ | ✅ | ✅；扫码预填回填（已修复，见 H3） |
| productionDate | ✅ | ✅ | ✅ | ✅ | ✅入参 | ⚫ | ✅ | ✅ | ✅ |
| shelfLifeDays | ✅ | ✅ | ✅ | ✅ | ✅ | ⚫ | ✅ | ✅ | ✅ |
| shelfLifeMonths | ✅ | ✅ | ✅ | ✅ | ✅月数优先 | ⚫ | ✅ | ✅ | ✅；扫码预填回填月数模式（已修复，见 H3） |
| expiryDate | ✅ | ✅ | ✅ | ✅ | ✅核心 | ✅提醒 | ✅ | ✅+业务键 | ✅ |
| note | ✅ | ✅ | ✅ | ✅ | ⚫搜索 | ⚫ | ✅ | ✅ | ✅ |
| status | ✅ | ✅ | ✅ | ✅ | ✅状态机 | ✅终态跳过 | ✅ | ✅ | ✅ |
| handledType | ✅ | ✅ | ✅ | **🔴无渲染消费** | ⚫ | ⚫ | ✅ | ✅ | **🔴零测试** |
| handledAt | ✅ | ✅ | ✅ | ✅ | ⚫ | ⚫ | ✅ | ✅ | 🔴零测试 |
| isDeleted | ✅ | ✅ | ✅ | ✅回收站 | ✅统计跳过 | ⚫ | ✅含回收站快照（已修复，见 H2） | ✅(成死分支) | ✅ |
| createdAt | ✅ | ✅ | ✅ | ✅ | ✅排序 | ⚫ | ✅ | ✅ | ✅ |
| updatedAt | ✅ | ✅ | ✅ | ⚫仅DB排序 | ⚫ | ⚫ | ✅ | ⚫强制刷新 | 🔴零测试 |
| barcode | ✅ | ✅ | ✅ | ✅ | ⚫搜索 | ⚫ | ✅ | ✅ | 🔴零测试 |
| customFields | ✅ | ✅JSON | ✅ | ✅ | ⚫ | ⚫ | ✅ | ✅映射 | ✅ |

其余 5 张子矩阵（常量/枚举、custom_field_defs、name_defs、DB 方法×调用方、持久化键）完整数据见审计执行记录；关键结论并入下方发现清单。

---

## 四、发现清单（两 agent 交叉验证去重，按严重度）

### HIGH（数据丢失/错误行为，已修复见下表）

| # | 问题 | 证据 | 影响 | 状态 |
|---|---|---|---|---|
| H1 | **name_defs 整表不进备份** | BackupService grep `nameDefs\|name_def` 零命中；BackupData 仅 5 字段 | 自定义分类/位置名称+排序在备份往返后丢失 | ✅ 已修复：schema v2 新增 nameDefs 段 + restoreNameDefs 还原（merge 导入序在前/overwrite 仅导入序） |
| H2 | **回收站数据不进备份** | exportBackup 用无参 `listAll()`（默认 `is_deleted=0`）；导入侧 `isDeleted` 还原分支因此恒不可达 | 软删除物资静默蒸发 | ✅ 已修复：导出改 `listAll({includeDeleted:true})`，导入还原分支激活；决策=备份是完整快照 |
| H3 | **扫码预填丢失月数/位置** | applyScanSuggestion 仅回填 name/category/unit/shelfLifeStr 4 字段 | 月数口径历史记录预填成"365×n 天"；location 不回填 | ✅ 已修复：按 shelfLifeMonths 还原月数模式 + 位置回填 |

### MED（断链/平行实现，待决策）

| # | 问题 | 证据 |
|---|---|---|
| M1 | ~~AppStorage `targetFilterLevel` 双向死写~~ | **✅ 已修复：wantAgent 带 filterLevel 参数（有过期优先 expired，否则 expiring）→ EntryAbility 存 AppStorage → Index onPageShow 切对应状态 Tab 后清除** |
| M2 | ~~ExpiryService 移植函数未接 UI~~ | **✅ 已修复：Index 分组排序接线 sortByExpirationAsc，删除自实现比较器**（sortByRiskAndExpiration/sortByCreatedDesc/buildOverview/levelSoftColor/levelBadgeTextColor 仍留白名单，待统计页决策） |
| M3 | ~~BarcodeProduct.ets 死模块~~ | **✅ 已删除：全仓零引用（扫码建议只走历史记录，预置字典无消费方）** |
| M4 | ~~CategoryOrder.ets 整文件死~~ | **✅ 已删除：连同 4 个专属测试用例** |
| M5 | 自定义字段 order/createdAt 导入不还原 | resolveCustomFieldDefs 只读 name/type/options，新定义 maxOrder++ 追加尾部 → 备份往返后字段顺序打乱。**✅ 已修复：新建定义改用导入备份的 order（本 PR）** |
| M6 | ~~DEFAULT_UNITS 硬编码数据源~~ | **✅ 已修复：NameKind 扩展 'unit'，CategoryManager 新增「单位」Tab（CRUD+排序+重命名同步 materials.unit），AddItem 单位 chip 动态化（listEffectiveNames('unit', DEFAULT_UNITS)），备份 nameDefs 含 unit** |

### LOW（清理项，已由 wire-guard 白名单登记）

| # | 问题 |
|---|---|
| L1 | ~~`NEAR_EXPIRY_DAYS`（Material.ets:49）死常量，与 `DEFAULT_NEAR_EXPIRY_DAYS` 双源~~ **✅ 已删除（2026-09-03）**：全仓词边界核查零使用，实际生效阈值源为 `common/ExpiryService.DEFAULT_NEAR_EXPIRY_DAYS` |
| L2 | ~~死 API：MaterialDb.listLocations / getCustomFieldById / MaterialFilter 全参数~~ **✅ 已消解（2026-09-03 核查）**：两个死 API 已随重构删除；MaterialFilter 现被 BackupService 全集快照（includeDeleted）实际使用，非死面 |
| L3 | ~~未使用 import ×5：Index.levelColor、ItemDetail.levelSoftColor/getActualStatus/DerivedStatus、AddItem.formatQuantityUnit~~ **✅ 已清零（2026-09-03 核查）**：wire-guard 规则 5 白名单豁免 0 / 违规 0，存量已随重构清理 |
| L4 | handledType 写而不显（渲染仅用 status/handledAt） |
| L5 | 测试空洞：MaterialDb 27 方法/Reminder/Scan/Notification/Settings 零直接测试；Settings.test 的 validateNearExpiryDays 是本地复刻而非 import 真实现。**Backup 导入决策已消解（2026-09-03）**：冲突裁决 + nameDefs 目标序下沉 `common/BackupPlan.ets` 纯函数，`test/BackupPlan.test.ts` 11 用例直测 |

### 待产品决策（证据矛盾格）

- ~~isDeleted 导出缺失~~ → 已随 H2 修复定为「备份是完整快照，回收站数据进备份」
- updatedAt 导入强制 todayStr 与 createdAt 保留原值不对称 → 建议：非关键，保持现状并记录
- quantity/quantity_text 双写（迁移兼容）→ 长期版本可清理

---

## 五、Phase 3 · CI 守护（wire-guard.js）

规则 + 白名单已固化进 `scripts/wire-guard.js`，`npm run ci` = design-guard + **wire-guard** + docs-guard + test（当前全绿）。

> 注：下表为 2026-08-27 审计时点的快照（五规则）。此后新增规则 6（custom_fields 键语义裸操作检测，#14/#18）与规则 7（文档 ⇄ 代码 .ets 双向校验，#17），现为七规则；统计数字以 `npm run wire:check` 实时输出为准。

| 规则 | 拦截的断链形态 | 审计时点状态 |
|---|---|---|
| 1 Material 字段 ⇄ toRow/rowToMaterial 双向映射 | 中途断（字段蒸发） | 19/19 通过 |
| 2 建表列 ⊆ toRow 键 | 中途断 | 19+9 通过 |
| 3 pages 硬编码预设数据源（仅允许 import/@State/listEffectiveNames defaults 行） | 消费端断（陈旧源） | 22 处=18 合法+4 白名单 |
| 4 导出 API 必须有非测试外部调用者（否则白名单登记理由） | 源头断（死写） | 70 API=53 接通+17 白名单 |
| 5 未使用 import | 冗余断链 | 173 导入=168 使用+5 白名单 |

白名单哲学：**不掩盖**——每条附理由与处置状态（清理候选/预留/内部组合件），白名单项若日后获得调用者，脚本会打 ⚠️ 提醒移除登记。

---

## 六、修复记录（已随本 PR 落地）

| 项 | 修复内容 |
|---|---|
| H1 | 备份 schema v2：BackupData 新增 nameDefs 段 + restoreNameDefs 还原（merge=导入序在前+本地独有追加尾部；overwrite=仅导入序；实现为按目标序删除重插，name_defs.id 无外部引用故无损）。v1 备份无此字段自动跳过 |
| H2 | 导出改 `listAll({includeDeleted:true})` 含回收站快照；导入侧 isDeleted 还原分支随之激活。决策：备份是完整快照 |
| H3 | applyScanSuggestion 按 shelfLifeMonths 还原月数录入模式（避免 365×n 天近似）+ location 回填 |
| M5 | resolveCustomFieldDefs 新建定义 order 改用导入备份值（缺失/非法回退 maxOrder+1），字段显示顺序备份往返不再打乱 |

M1/M2/M3/M4/M6 已全部随本 PR 修复（通知直达状态 Tab / 排序接线 sortByExpirationAsc / 死模块删除 / 单位自定义管理接入 name_defs）；LOW 项留白名单持续追踪，新断链由 CI 拦截。
