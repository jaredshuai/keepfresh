# 代码结构（entry/src/main/ets/）

> 从根 AGENTS.md 外迁（渐进式披露：需要文件级清单时才加载本文件）。
> 本文件由实际文件枚举生成（2026-08-28 首版 25 个 .ets，2026-08-29 补登记 UsageService 后 26 个）。wire-guard 规则 7 双向校验：本文档列出的 .ets 路径必须真实存在，且每个 .ets 文件必须登记在本文档；**新增/删除文件时同步本文件，漏改任一方向都会直接 CI 红**。

**model/（领域模型，纯逻辑）**

- `entry/src/main/ets/model/Material.ets` — 物资数据模型、状态机（active/opened/empty/discarded）、分类/位置/单位预设、临期阈值常量

- `entry/src/main/ets/model/CustomField.ets` — 自定义字段模型与校验；含 custom\_fields 键语义契约（编解码 / 值键二次映射）

**common/（无 @kit 依赖的纯工具，Node 测试唯一可 import 层）**

- `entry/src/main/ets/common/DateUtils.ets` — 日期字符串工具（todayStr / addDays / diffDays / addMonths）

- `entry/src/main/ets/common/InputNormalize.ets` — 输入归一化（文本/非负整数/可空文本）

- `entry/src/main/ets/common/QuantityUnit.ets` — 数量单位解析与格式化

- `entry/src/main/ets/common/SearchFilter.ets` — 关键词过滤（跨 name/category/location/note）

- `entry/src/main/ets/common/ExpiryService.ets` — 到期计算、临期分级、状态机派生、统计、风险排序（纯函数，零 @kit；预警资格唯一判定 splitByAlertLevel）

- `entry/src/main/ets/common/Validation.ets` — 输入校验纯函数（临期天数范围常量 + 校验；service 层同名方法只转发）

- `entry/src/main/ets/common/Theme.ets` — 包豪斯设计令牌（页面禁写死色值/圆角，design-guard 执法）

- `entry/src/main/ets/common/CategoryIcons.ets` — 分类图标映射

- `entry/src/main/ets/common/HardShadow.ets` — 硬阴影容器组件（pages/ 禁手写阴影样板，design-guard 规则 4 执法）

- `entry/src/main/ets/common/ScanSuggest.ets` — 扫码建议挑选（在库优先，全删条码以最近已删行兜底历史模板；条码管身份）

- `entry/src/main/ets/common/MaterialForm.ets` — 录入决策（历史→表单日期参数 / 表单→物资构造 / 同批次并条 / 保质期展示，三入口唯一实现）

- `entry/src/main/ets/common/BackupPlan.ets` — 备份导入决策（字段定义冲突裁决 / nameDefs 目标序，纯函数；service/BackupService 按 plan 落库）

**db/（存储层）**

- `entry/src/main/ets/db/MaterialDb.ets` — RelationalStore 封装（materials V2 / custom\_field\_defs / name\_defs 三表 CRUD、迁移、软删除，单例；唯一允许裸 JSON 编解码 custom\_fields 列之处）

**service/（平台绑定业务服务）**

- `entry/src/main/ets/service/SettingsService.ets` — 用户配置持久化（临期阈值等，Preferences）

- `entry/src/main/ets/service/ReminderService.ets` — 代理提醒（ReminderKit 每日汇总调度）

- `entry/src/main/ets/service/MaterialWriteService.ets` — 物资写路径统一（落库+版本自增+提醒重算一个接口；并条决策在 common/MaterialForm）

- `entry/src/main/ets/service/NotificationService.ets` — 通知授权与临期通知发布

- `entry/src/main/ets/service/BackupService.ets` — 备份导出/导入（JSON schema v2，DocumentViewPicker 免权限）

- `entry/src/main/ets/service/ScanService.ets` — 扫码快填（ScanKit + 条码历史建议）

- `entry/src/main/ets/service/UsageService.ets` — dogfood 使用日志（端侧 JSONL 追加写，写失败静默；检索见 docs/dogfood.md）。补登记于 2026-08-29 规则 7 反向校验上线时

**components/（跨页共享 UI 组件，走 Theme 令牌）**
- `entry/src/main/ets/components/MaterialCard.ets` — 物资卡片（过期红卡/临期・安全白卡/已处理灰卡合一，变体由状态派生；候选 4 深化）
- `entry/src/main/ets/components/ReminderSettingsPanel.ets` — 提醒设置面板（开关+时间+editSettings 保存含失败回滚，首页 Sheet 与 Settings 共用；候选 3 深化）

**pages/（UI，7 页，全部走 Theme 令牌）**

- `entry/src/main/ets/pages/Index.ets` — 首页：状态分组列表 + 搜索筛选 + 提醒设置入口

- `entry/src/main/ets/pages/AddItem.ets` — 新增/编辑：扫码预填 + 自定义字段渲染

- `entry/src/main/ets/pages/ItemDetail.ets` — 详情：状态操作、编辑入口、删除/软删

- `entry/src/main/ets/pages/RecycleBin.ets` — 回收站：恢复 / 彻底删除

- `entry/src/main/ets/pages/Settings.ets` — 设置中心：阈值/提醒/备份/管理与字段入口

- `entry/src/main/ets/pages/CustomFieldManager.ets` — 自定义字段 CRUD 与排序

- `entry/src/main/ets/pages/CategoryManager.ets` — 分类/位置管理（name\_defs）

**entryability/**

- `entry/src/main/ets/entryability/EntryAbility.ets` — 入口 Ability；通知 want 参数 filterLevel → AppStorage 深链状态 Tab

