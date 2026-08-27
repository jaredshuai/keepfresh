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
| location | ✅ | ✅ | ✅ | ✅ | ⚫ | ⚫ | ✅ | ✅ | ✅；**扫码预填不回填 🔴** |
| productionDate | ✅ | ✅ | ✅ | ✅ | ✅入参 | ⚫ | ✅ | ✅ | ✅ |
| shelfLifeDays | ✅ | ✅ | ✅ | ✅ | ✅ | ⚫ | ✅ | ✅ | ✅ |
| shelfLifeMonths | ✅ | ✅ | ✅ | ✅ | ✅月数优先 | ⚫ | ✅ | ✅ | ✅；**扫码预填不回填 🔴** |
| expiryDate | ✅ | ✅ | ✅ | ✅ | ✅核心 | ✅提醒 | ✅ | ✅+业务键 | ✅ |
| note | ✅ | ✅ | ✅ | ✅ | ⚫搜索 | ⚫ | ✅ | ✅ | ✅ |
| status | ✅ | ✅ | ✅ | ✅ | ✅状态机 | ✅终态跳过 | ✅ | ✅ | ✅ |
| handledType | ✅ | ✅ | ✅ | **🔴无渲染消费** | ⚫ | ⚫ | ✅ | ✅ | **🔴零测试** |
| handledAt | ✅ | ✅ | ✅ | ✅ | ⚫ | ⚫ | ✅ | ✅ | 🔴零测试 |
| isDeleted | ✅ | ✅ | ✅ | ✅回收站 | ✅统计跳过 | ⚫ | **🔴导出排除软删除** | ✅(成死分支) | ✅ |
| createdAt | ✅ | ✅ | ✅ | ✅ | ✅排序 | ⚫ | ✅ | ✅ | ✅ |
| updatedAt | ✅ | ✅ | ✅ | ⚫仅DB排序 | ⚫ | ⚫ | ✅ | ⚫强制刷新 | 🔴零测试 |
| barcode | ✅ | ✅ | ✅ | ✅ | ⚫搜索 | ⚫ | ✅ | ✅ | 🔴零测试 |
| customFields | ✅ | ✅JSON | ✅ | ✅ | ⚫ | ⚫ | ✅ | ✅映射 | ✅ |

其余 5 张子矩阵（常量/枚举、custom_field_defs、name_defs、DB 方法×调用方、持久化键）完整数据见审计执行记录；关键结论并入下方发现清单。

---

## 四、发现清单（两 agent 交叉验证去重，按严重度）

### HIGH（数据丢失/错误行为，待修复）

| # | 问题 | 证据 | 影响 |
|---|---|---|---|
| H1 | **name_defs 整表不进备份** | BackupService grep `nameDefs\|name_def` 零命中；BackupData 仅 5 字段 | 自定义分类/位置名称+排序在备份往返后丢失（listEffectiveNames 只能靠物资数据兜底捡回名字，定义与排序永久丢） |
| H2 | **回收站数据不进备份** | exportBackup 用无参 `listAll()`（默认 `is_deleted=0`）；导入侧 `isDeleted` 还原分支因此恒不可达 | 软删除物资静默蒸发；导入还原代码成死分支（两处矛盾，倾向缺陷） |
| H3 | **扫码预填丢失月数/位置** | applyScanSuggestion 仅回填 name/category/unit/shelfLifeStr 4 字段 | 月数口径历史记录预填成"365×n 天"，到期日与原记录不一致；location 不回填 |

### MED（断链/平行实现，待决策）

| # | 问题 | 证据 |
|---|---|---|
| M1 | AppStorage `targetFilterLevel` 双向死写 | EntryAbility 写→Index 读后即清，从未驱动 activeStatusTab；且无 Want 生产者（ReminderService wantAgent 无 parameters） |
| M2 | ExpiryService 移植函数未接 UI | Index L208 自实现比较器（注释自认"sortByExpirationAsc 语义"），sortBy*×3/buildOverview/levelSoftColor/levelBadgeTextColor 全死 |
| M3 | BarcodeProduct.ets 死模块 | 全仓零引用；设计文档计划 ScanService 消费 findPresetBarcode 未接线 |
| M4 | CategoryOrder.ets 整文件死 | 三导出零生产调用（仅测试） |
| M5 | 自定义字段 order/createdAt 导入不还原 | resolveCustomFieldDefs 只读 name/type/options，新定义 maxOrder++ 追加尾部 → 备份往返后字段顺序打乱 |
| M6 | DEFAULT_UNITS 硬编码数据源 | AddItem L550 chip 直传预设；name_defs 无 unit kind（分类/位置已动态化，单位未跟上） |

### LOW（清理项，已由 wire-guard 白名单登记）

| # | 问题 |
|---|---|
| L1 | `NEAR_EXPIRY_DAYS`（Material.ets:49）死常量，与 `DEFAULT_NEAR_EXPIRY_DAYS` 双源 |
| L2 | 死 API：MaterialDb.listLocations / getCustomFieldById / MaterialFilter 全参数 |
| L3 | 未使用 import ×5：Index.levelColor、ItemDetail.levelSoftColor/getActualStatus/DerivedStatus、AddItem.formatQuantityUnit |
| L4 | handledType 写而不显（渲染仅用 status/handledAt） |
| L5 | 测试空洞：MaterialDb 27 方法/Backup/Reminder/Scan/Notification/Settings 零直接测试；Settings.test 的 validateNearExpiryDays 是本地复刻而非 import 真实现 |

### 待产品决策（证据矛盾格）

- isDeleted 导出缺失：有意（"回收站不进备份"）vs 缺陷（导入还原分支存在表明原意支持）→ 建议 H2 修复时一并定夺
- updatedAt 导入强制 todayStr 与 createdAt 保留原值不对称 → 建议：非关键，保持现状并记录
- quantity/quantity_text 双写（迁移兼容）→ 长期版本可清理

---

## 五、Phase 3 · CI 守护（wire-guard.js）

五规则 + 白名单已固化进 `scripts/wire-guard.js`，`npm run ci` = design-guard + **wire-guard** + test（当前全绿）：

| 规则 | 拦截的断链形态 | 当前状态 |
|---|---|---|
| 1 Material 字段 ⇄ toRow/rowToMaterial 双向映射 | 中途断（字段蒸发） | 19/19 通过 |
| 2 建表列 ⊆ toRow 键 | 中途断 | 19+9 通过 |
| 3 pages 硬编码预设数据源（仅允许 import/@State/listEffectiveNames defaults 行） | 消费端断（陈旧源） | 19 处=15 合法+4 白名单 |
| 4 导出 API 必须有非测试外部调用者（否则白名单登记理由） | 源头断（死写） | 63 API=42 接通+21 白名单 |
| 5 未使用 import | 冗余断链 | 168 导入=163 使用+5 白名单 |

白名单哲学：**不掩盖**——每条附理由与处置状态（清理候选/预留/内部组合件），白名单项若日后获得调用者，脚本会打 ⚠️ 提醒移除登记。

---

## 六、修复建议（未执行，待批准）

H1-H3 为真实缺陷建议修复；M 级需决策（M2/M4 要么接线要么删除，避免平行实现漂移）。wire-guard 已把"新增断链"挡在 CI，存量清理由白名单追踪。
