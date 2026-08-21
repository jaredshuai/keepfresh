# 施工任务：后台提醒实现优化（KeepFresh，ticket #7 已定稿）

## 你的角色

你是 HarmonyOS（ArkTS/ArkUI）开发工程师。在仓库 `keepfresh` 现有代码上**改造**后台提醒实现。**只写本文件指定的内容，不要顺手重构其他代码。**

## 先读（动手前必读）

1. `docs/research/reminder-constraints.md` — ReminderKit 约束研究结论（`updateReminder`、管控权益、错误码都在里面）
2. `docs/adr/0001-on-device-ai-only.md`、`CONTEXT.md`
3. 现有代码：`entry/src/main/ets/service/ReminderService.ets`（用户手写，你要改造它）、`service/NotificationService.ets`（启动应用内通知，要移除）、`service/SettingsService.ets`、`pages/Settings.ets`

## 已定稿决策（ticket #7 Resolution，不可更改）

1. **updateReminder 优先**：`syncDailyReminder` 改为「优先 `reminderAgentManager.updateReminder(reminderId, req)` 原位刷新；捕获 1700003（提醒不存在）等失败时降级为 `cancelAllReminders()` + `publishReminder()`」。
2. **reminderId 持久化**：Preferences 新增 key（如 `daily_reminder_id`）保存每日提醒的 reminderId，供精准更新/取消。
3. **文案**：标题「保质期日报」；内容 `截至今天，N 件临期 / M 件已过期，点击查看详情`（无临期/过期时按现有逻辑 cancelAll 不发布）。
4. **落地页**：wantAgent 指向 EntryAbility 首页（现有已正确，保持）。
5. **移除启动时应用内通知**：删除 `NotificationService` 中启动时发布汇总通知的逻辑；保留/移除授权请求由你判断（后台提醒仍需通知授权，建议保留授权请求）。
6. **注册时机**：保持 onCreate/onForeground 启动时同步（现有时机不变）。
7. **刷新时机**：物资增删改后调用 `ReminderService.syncDailyReminder()`；App 前台刷新已有。
8. **默认时间统一 8:00**：ReminderService 中 `hour` 默认值 9 改为 8（getSettings 默认与 ReminderSettings 默认值同步改）。

## 实现要求

1. 改 `ReminderService.ets`：
   - 新增 reminderId 的 Preferences 读写（get/set/clear）
   - `syncDailyReminder` 流程：读设置 → 未启用则 cancelAll → 统计临期/过期 → 都为 0 则 cancelAll → 否则构造 ReminderRequestAlarm（hour/minute 用设置、daysOfWeek [1..7]、新文案、wantAgent 首页）→ 有持久化 reminderId 则先 `updateReminder`，失败（1700003 等）则 `cancelAllReminders()` 后 `publishReminder` 并保存新 reminderId；无 reminderId 则直接 publish 并保存
   - 默认 hour 9→8（getSettings 默认值与 ReminderSettings 接口默认值同步）
2. 改 `NotificationService.ets`：移除启动时应用内通知发布逻辑；保留 `ensureNotificationEnabled`/`requestNotificationEnable`（后台提醒仍需通知授权）
3. 数据增删改接线：在 AddItem（保存后）、ItemDetail（删除后）等物资变更处调用 `ReminderService.syncDailyReminder(context)` 刷新提醒
4. 错误处理：`publishReminder` 抛 1700002（未开通权益）时记录并提示一次（不重复骚扰），确保应用内兜底
5. 中文 UI/文案，沿用现有风格

## 验收标准

- 真机：设置提醒时间 8:30 → 到点收到「保质期日报」通知，内容含正确 N/M 数字
- 增删物资后提醒内容数字立即更新（updateReminder 路径）
- 杀掉 App 重开，提醒时间/开关状态保留；reminderId 持久化生效（二次启动用 update 而非重复 publish）
- 提醒开关关闭 → cancelAll；开启 → 重新注册
- 未开通权益真机：发布失败有提示，App 不 crash
- 不再出现启动时的应用内汇总通知

## 交付

- 改动文件清单 + 关键实现说明（特别是 updateReminder 降级逻辑）
- "模拟器可验证 / 需真机验证"清单（ReminderKit 管控需真机+权益，说明模拟器上的验证边界）
- 编译需通过
