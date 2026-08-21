# 施工任务：设置中心（KeepFresh）

## 你的角色

你是 HarmonyOS（ArkTS/ArkUI）开发工程师。在仓库 `keepfresh` 的现有代码上实现「设置中心」功能。**只写本文件指定的内容，不要顺手重构其他代码。**

## 先读（动手前必读）

1. `CONTEXT.md` — 领域词汇表（临期/临期阈值等术语必须沿用）
2. `docs/adr/0001-on-device-ai-only.md`
3. 现有代码：`entry/src/main/ets/` 全部 service 与 pages 文件；特别注意：
   - `service/ReminderService.ets`（用户已实现：ReminderSettings enabled/hour/minute + preferences 持久化 + syncDailyReminder）
   - `service/NotificationService.ets`（启动时应用内通知）
   - `service/ExpiryService.ets`（目前 `NEAR_EXPIRY_DAYS` 是硬编码常量 7）
   - `pages/Index.ets`（首页 header 区）
   - **先确认 main 上是否已有 Settings 页/入口**——用户可能在并行开发，存在则在其基础上扩展而非重建

## 已定产品决策（不可更改）

- 设置页四项：**临期天数阈值**（默认 7，正整数）+ **每日提醒时间**（默认 8:00，时间选择器）+ **提醒开关** + **备份导出/导入入口**（备份功能本体由另一个任务实现，本任务只放入口与跳转/占位）
- 阈值改为**用户可配置**：`ExpiryService` 的 `NEAR_EXPIRY_DAYS` 常量改为从设置读取（preferences 持久化，key 自定；提供 `getNearExpiryDays()` 异步获取并做模块级缓存，读取失败回落 7）
- 设置变更**即时生效**：阈值变更后首页重新分级；提醒时间/开关变更后调用 `ReminderService.syncDailyReminder()` 重新调度
- 设置页入口：首页 header 右上角齿轮图标

## 实现要求

1. **设置持久化**：沿用/扩展 `ReminderService` 的 preferences 方案（可新建 `service/SettingsService.ets` 统一管理，含 nearExpiryDays；ReminderSettings 的读写可迁进去或保留原处——若用户已有结构，以兼容为先）。
2. **设置页**（`pages/Settings.ets`，注册进 `main_pages.json`）：四个区块——
   - 临期提醒阈值：数字输入（1~365），说明文案"剩余 ≤N 天标记为临期"
   - 每日提醒时间：时间选择器（TimePickerDialog），显示 HH:mm
   - 后台提醒开关：Toggle；关闭时调 `ReminderService` 取消全部提醒
   - 数据备份：两个按钮"导出备份"/"导入备份"——**本任务只放入口**，点击先 Toast"备份功能开发中"或跳转到占位页（若备份任务已完成则接真实实现——动手前检查是否存在 BackupService）
   - 底部可加"自定义字段管理"入口占位（同理，字段任务完成后接真实页面）
3. **阈值接线**：`ExpiryService.levelOf`/`statsOf` 等改为读取可配阈值（注意它们是同步函数——设计一个合理的缓存+刷新方案：设置变更时写入缓存，App 启动时预热缓存；保持改动最小）。
4. **首页入口**：Index 页 header 右侧加设置图标按钮（用 @element 图标或文字"设置"），路由跳转 Settings。
5. **返回首页刷新**：设置返回后首页列表按新阈值重新计算（onPageShow 已 refresh，确认阈值缓存及时更新即可）。
6. **中文 UI**，沿用现有视觉风格。

## 验收标准

- 改阈值 7→3：首页"临期"统计立即按新口径变化
- 改提醒时间/开关：ReminderService 被正确调用（日志可见）；开关关闭后提醒取消
- 设置持久化：杀进程重进后设置值保留
- 备份/字段入口存在且不 crash

## 交付

- 改动/新增的文件清单 + 关键实现说明（特别是阈值缓存方案）
- "模拟器可验证 / 需真机验证"清单
- 编译需通过（若无法编译，说明原因）
