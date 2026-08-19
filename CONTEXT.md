# KeepFresh 领域模型与架构上下文 (CONTEXT.md)

KeepFresh 是一款基于 HarmonyOS 原生开发（ArkTS + ArkUI）的物资保质期管理应用，目标是帮助用户高效录入保质期、实现离线/后台智能提醒并减少物品过期浪费。

---

## 1. 核心领域术语 (Domain Glossary)

| 术语 | 英文 / 代码标识 | 含义与业务规则 |
| :--- | :--- | :--- |
| **物资 / 物品** | `Material` | 用户录入的单项资产，包含品名、分类、数量/单位、生产日期、保质期天数、到期日及可选条码。 |
| **生产日期** | `productionDate` | 物资出厂或制造日期（格式：`YYYY-MM-DD`）。 |
| **保质期天数** | `shelfLifeDays` | 物资从生产日期起算的安全有效期天数（大于等于 1 天）。 |
| **到期日** | `expiryDate` | 物资的最后有效日期，计算公式：`expiryDate = productionDate + shelfLifeDays`。 |
| **距到期天数** | `remainingDays` | 从当前系统日期（`todayStr()`）到 `expiryDate` 的天数差（正数为剩余天数，负数为已过期天数）。 |
| **临期状态等级** | `ExpiryLevel` | 物资按紧迫程度划分的三个业务等级：<br>• `EXPIRED`（已过期）：`remainingDays < 0`<br>• `NEAR`（临期）：`0 <= remainingDays <= threshold`（默认 `<= 3` 天）<br>• `SAFE`（安全）：`remainingDays > threshold` |
| **商品条码** | `barcode` | 商品包装上的 69 码/EAN 标准条形码，用于快速匹配内置字典或历史录入数据。 |
| **后台代理提醒** | `ReminderAgent` | 基于系统级 `reminderAgentManager` 的离线定时调度服务，在应用退出后依然能够按时唤醒通知。 |

---

## 2. 核心架构与服务分层

```
entry/src/main/ets/
├── common/
│   └── DateUtils.ets              # 日期字符串格式化与计算纯函数 (todayStr, addDays, diffDays)
├── model/
│   ├── Material.ets               # 物资实体模型定义与分类/单位常量预设
│   └── BarcodeProduct.ets         # 69码条码映射模型与内置常用商品字典
├── db/
│   └── MaterialDb.ets             # RelationalStore (SQLite) 数据持久化与按条码/状态 CRUD
├── service/
│   ├── ExpiryService.ets          # 保质期计算、等级评估与统计分析
│   ├── DateTextParser.ets         # OCR 文本智能抽取与双向日期推导引擎
│   ├── ScanService.ets            # ScanKit 统一扫码封装与多级条码匹配
│   ├── OcrService.ets             # CoreVisionKit OCR 识别与照片选择
│   ├── ReminderService.ets        # reminderAgentManager 后台定时代理提醒与首选项调度
│   └── NotificationService.ets    # NotificationKit 前台即时通知发布
└── pages/
    ├── Index.ets                  # 物资主列表、分类/状态筛选、搜索与统计仪表盘
    ├── AddItem.ets                # 物资快捷录入（扫码/OCR/手动）与编辑
    └── ItemDetail.ets             # 物资详情、状态卡片与删除
```

---

## 3. 架构决策记录 (ADR Index)

- [ADR 0001: 采用后台代理提醒（reminderAgentManager）实现每日离线临期汇总通知](docs/adr/0001-daily-summary-offline-reminder.md)
