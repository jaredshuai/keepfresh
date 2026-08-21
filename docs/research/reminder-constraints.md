# ReminderKit 每日汇总提醒约束 — 研究结论

> 研究 ticket #3 · 2026-08-20 · 认领与产出：main 会话（原代理被终止，本会话接手补完）
> 多 AI 核验：报告 A（工具 B）全部 ✅ 同意 + 增量：错误码 1700002、AGC 申请实操、快照文案引导设计、reminderId 单槽管理（已并入）
> 多 AI 核验：报告 B（工具 C）**重大修正**——API 20+ 存在 `updateReminder` 原位更新接口（推翻"只能取消重发"结论）；数量上限按版本区分（API 25- ≤30 / API 26+ ≤64）；权益版本注意（5.1.1(19) 之前不生效）；旧邮件申请流程已被 AGC 流程取代（已并入）

## 结论摘要

ReminderKit（代理提醒 `reminderAgentManager`）**技术上完全支持** KeepFresh 的"每日固定时刻汇总一条"需求（闹钟型 + `daysOfWeek` 每日重复）。但存在一条**致命前置约束**：**手机 / 平板 / PC/2in1 上代理提醒受管控，三方应用必须先向华为申请"代理提醒开放能力"权益（AGC 线上申请，约 8 个工作日，通过后需手动签名），审核通过后才能调用接口**。未开通权益时 `publishReminder` 报错 1700002（系统视上限为 0）。

KeepFresh 的类型与场景均**符合申请条件**（生活服务类 App + 临期提醒属允许场景），因此可行路径是：申请权益 → 使用代理提醒；申请未通过期间，以"启动时应用内通知"（现有 `NotificationService`）作为降级。

**内容更新（API 20+ 有新能力）**：除"取消后重发"外，**`updateReminder(reminderId, reminderReq)`（API 20+，基线 24 可用）支持原位更新**未过期、未显示在通知中心的提醒——KeepFresh 应优先用它刷新每日内容，仅在其失败（1700003 等）时降级为取消重发。App 未启动时内容仍停留在上次发布/更新快照。

## 事实明细（来源见文末）

### 1. 管控限制（最关键）

- 设备差异：手机、平板、PC/2in1 **存在管控**；智慧屏、智能穿戴**无管控限制**。
- 未开通权益：无法直接调用代理提醒接口。两条出路：① 向华为申请"代理提醒开放能力"（在 **AGC 后台"项目设置 → 开放能力管理"**提交申请，审核约 **8 个工作日**，通过后须**重新下载 Profile 并配置手动签名**——自动签名不含该受控权限；未开通或签名不匹配时调用直接报错）；② 改用 Calendar Kit 替代。
- 应用类型限制（申请前提，缺一不可）：工具类、商务类、效率类、金融理财类、教育类、生活服务类、旅游类、医疗类、运动健康类、游戏类。**KeepFresh 属"生活服务类"（或"工具类"），符合**。
- 场景限制：禁止营销类（抢购/红包/优惠券/促销/直播预约）；**允许**列表中明确包含"临期提醒、习惯打卡"等个人管理场景。**KeepFresh 的临期提醒场景符合**。

### 2. 数量上限

- 单个普通应用：有效/未过期提醒 **API 25 及以下 ≤ 30 个，API 26+ ≤ 64 个**（KeepFresh 基线 API 24 适用 30；超限调用 `publishReminder` 抛错误码 **1700002** "The number of reminders exceeds the limit"。注意：未开通权益时也报 1700002，系统视上限为 0）。
- 系统总上限：API ≥ 10 时 12000 个；API ≤ 9 时 2000 个。
- "有效"判定：一次性提醒到点后未点 CLOSE 仍占名额；**周期性提醒（如每日重复）无论是否点 CLOSE 永远有效**，在系统调度表中永续占位，直到 `cancelReminder` 或应用卸载。KeepFresh 单条每日提醒只占 1 个名额，无压力。

### 3. 通知内容能否动态更新

- **发布时固定**：内容（title/content）在 `publishReminder` 时写入，触发时不重新计算。
- **API 20+ 提供原位更新接口 `updateReminder(reminderId, reminderReq)`**：KeepFresh 基线 API 24 可用。约束：仅"有效（未过期）且未显示在通知中心"的提醒支持更新；已弹出/已过期的需降级为取消后重发。错误码：201 权限拒绝 / 1700003 提醒不存在 / 1700007 参数错误。
- 兜底方式：`cancelAllReminders()`（或 `cancelReminder(id)`）后重新 `publishReminder`，用新内容覆盖。
- KeepFresh 含义：临期数量变化后，优先用持久化的 reminderId 调 `updateReminder` 原位刷新 content；捕获 1700003 时降级为重新 `publishReminder`。**优于 main 现有"取消重发"实现**（见对现有实现的核对）。

### 4. App 未启动时如何更新内容

- 代理提醒由系统代发，App 进程被杀也能到点弹通知；但**更新内容必须由 App 自己执行**（进程存活时）。
- 可行策略（即现有实现做法）：每次 App 启动/前台时调用 `syncDailyReminder()` 重新发布。App 长期不打开时内容停留在上次发布快照——个人自用可接受。

### 5. 点击提醒后的跳转

- **只能跳回本应用**（申请代理提醒的应用自身），通过 `wantAgent.pkgName + abilityName` 指定。
- KeepFresh 现有实现指向 `com.jaredshuai.keepfresh` / `EntryAbility`，**正确**。

### 6. 权限与前置条件

- 静态权限：`ohos.permission.PUBLISH_AGENT_REMINDER`（module.json5 `requestPermissions`）。**现有实现已声明**。
- 运行时通知授权：仍需先通过 `notificationManager.requestEnableNotification` 获得用户允许；**若无通知权限，调用报错误码 1700001**（现有 `NotificationService` 已实现）。
- 模块：`@kit.BackgroundTasksKit` 的 `reminderAgentManager`。
- 模拟器支持：**API 20 起**模拟器才支持代理提醒调试（本项目 API 24，可模拟器验证接口调用，但管控权益需真机验证；涉及系统挂起/唤醒特性的建议真机实测）。
- 权益版本注意：官方明确"新申请的权限在 HarmonyOS 5.1.1(19) 及之前版本不再生效"——KeepFresh 面向 6.x 无影响。
- 接口全集：publishReminder / cancelReminder / getValidReminders / cancelAllReminders / addNotificationSlot / removeNotificationSlot / getAllValidReminders(12+) / addExcludeDate(12+) / deleteExcludeDates(12+) / getExcludeDates(12+) / **updateReminder(20+)** / cancelReminderOnDisplay(23+) / subscribeReminderState(23+) / unsubscribeReminderState(23+)。`cancelReminderOnDisplay` 可只清通知卡片而保留周期数据（次日仍提醒）。系统不会拉起应用进程执行后台计算。

### 7. 提醒类型选型

| 类型 | 适用 | 周期字段 |
|---|---|---|
| 日历型 Calendar | 具体日期+时间，可按月/日重复 | `repeatMonths` / `repeatDays` |
| **闹钟型 Alarm** | **每天/每周固定时刻** | **`daysOfWeek`** |
| 倒计时型 Timer | 一次性 N 秒后 | `triggerTimeInSeconds` |

每日固定时刻 → **闹钟型**。现有实现 `ReminderRequestAlarm + daysOfWeek: [1..7]` **选型正确**。

## 对现有实现（main `a72be00`）的核对与风险

main 上已存在 `entry/src/main/ets/service/ReminderService.ets`（`syncDailyReminder`：禁用时 cancelAll、无临期/过期时 cancelAll、有则取消重发每日闹钟提醒），module.json5 已声明 `PUBLISH_AGENT_REMINDER`。核对结果：

- ✅ 选型正确（闹钟型每日重复）、wantAgent 正确、数量 1 条无压力
- ✅ 权限声明正确、与通知授权配套
- ⚠️ **更新策略可优化**：现实现用"取消重发"更新内容；API 24 基线已可用 `updateReminder(reminderId, reminderReq)` 原位更新（更省配额、避免取消/发布窗口期），建议改为"优先 updateReminder、1700003 时降级重发"
- ⚠️ **未持久化 reminderId**：建议在 Preferences 保存 reminderId，便于按 ID 精准更新/取消（单槽管理）
- ⚠️ **未处理管控权益失败路径**：真机未开通代理提醒权益时 `publishReminder` 将抛错（现实现仅 log error，静默失败）。建议：检测到发布失败时提示用户"需申请代理提醒权益"，并确认启动时应用内通知（`NotificationService`）仍在兜底
- ⚠️ 未申请权益前，真机行为需实测；错误码（如 1700001 通知未开启 / 1700002 权益未开通）建议在真机上确认

## 落地建议（供 #7 后台提醒实现定稿使用）

1. **提前启动 AGC 开放能力申请**：开发初期即在 AGC 提交"代理提醒"能力申请（应用分类设为"生活服务"、场景选"临期提醒（生活类）"，附应用分类截图 + 功能场景截图），并配置手动签名证书/Profile，避免联调或发布时被 8 个工作日审核阻断。注意：旧邮件申请流程已被 AGC 线上流程取代。
2. 保持现有闹钟型每日提醒实现形态（`ReminderRequestAlarm` + `daysOfWeek: [1..7]`）。
3. **优先 `updateReminder` 原位刷新**：每次前台/数据变更后用持久化的 reminderId 调 `updateReminder` 刷新 content；捕获 1700003（提醒不存在）时降级为重新 `publishReminder`；`publishReminder` 失败时记录 + 首次失败弹一次提示（不重复骚扰），确保 `NotificationService` 启动通知兜底。
4. 设置页：提醒开关/时间已由 `ReminderSettings` 支持（preferences 持久化）；开关关闭时 `cancelAllReminders()`（现有实现已做）。
5. **文案兼顾"快照特性"**：因长期不打开 App 文案无法动态刷新，每日提醒文案建议用半动态/引导性表述（如标题"保质期日报"，内容"截至上次整理有 N 件物资临期，点击打开查看今日最新动态"），避免物资在后台自然过期导致绝对数值失真引起困惑。
6. **关键生命周期自动刷新**：物资增删改、设置变更时触发重新计算并刷新提醒；App 每次进入前台（onForeground / onWindowStageCreate）自动重新计算临期统计，先 updateReminder（或 cancel+publish）覆盖旧快照。
7. **单 Slot 管理与持久化 reminderId**：在 Preferences 持久化保存每日汇总提醒的 reminderId，每次发布新提醒前严格按该 ID 撤销/更新旧提醒，确保配额内恒定只占 1 个槽位。
8. 若用户后续希望"内容每天自动更新而不依赖打开 App"：此场景**无解**（更新必须 App 进程执行），接受快照语义或申请权益后配合系统刷新策略评估。

## 来源

- 华为官方：代理提醒（ArkTS）开发指南 `developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/agent-powered-reminder`（管控限制、应用类型、场景限制、30 个上限、跳转限制、wantAgent）
- 华为官方：代理提醒 v5 指南（`agent-powered-reminder-V5`，30 上限、关闭/有效判定、周期提醒永续）
- 华为官方：reminderAgentManager 错误码（1700001 通知未开启、1700002 提醒过多等）
- 华为开发者问答：代理提醒权限问题（权益开通后仍报 publish 失败的实战案例）
- 掘金速记（2025-11）：申请流程细节（AGC 开放能力管理、8 个工作日、手动签名）、系统 12000/2000 总上限、`ReminderRequestCalendar` 完整字段、模拟器 API 20 支持
- 未查证事项：Calendar Kit 替代方案的细节——如实标注，待真机验证
- 报告 A（工具 B）称"所有 7 项问题均已查证闭环（无未查证事项）"，且给出手动签名配置、1700002 错误码等实操细节——已并入上文
