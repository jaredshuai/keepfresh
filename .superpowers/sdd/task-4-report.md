# Task 4 Report: 首页 `Index.ets` 交互联动与提醒设置面板

## 1. 任务概述
- **任务名称**: Task 4 首页 `Index.ets` 交互联动与提醒设置面板
- **目标文件**:
  - `entry/src/main/ets/pages/Index.ets`
- **状态**: ✅ 完成 (Completed)

## 2. 变更详情
1. **通知深度链接筛选联动 (`targetFilterLevel`)**:
   - 在 `Index.ets` 的 `onPageShow()` 中读取 `AppStorage.get<string>('targetFilterLevel')`。
   - 当值为 `'NEAR'` 时，自动将首页列表筛选切换至 `ListFilter.NEAR`，并重置 `AppStorage` 状态。
   - 当值为 `'EXPIRED'` 时，自动将首页列表筛选切换至 `ListFilter.EXPIRED`，并重置 `AppStorage` 状态。

2. **提醒配置加载与状态管理**:
   - 新增 `@State showSettingsDialog`、`@State reminderEnabled`、`@State reminderHour`、`@State reminderMinute`。
   - 在 `onPageShow()` 中通过 `loadReminderSettings()` 调用 `ReminderService.getInstance().getSettings()` 异步加载首选项配置并更新状态。

3. **首页顶部铃铛设置入口**:
   - 在首页顶部导航栏标题右侧新增圆形按钮与系统铃铛图标 `SymbolGlyph($r('sys.symbol.bell'))`。
   - 颜色根据 `reminderEnabled` 动态高亮（开启显示品牌绿 `CLR_BRAND`，关闭显示辅助灰 `CLR_TEXT_SUB`）。
   - 点击时触发 `openReminderSettingsDialog()` 打开半模态设置面板。

4. **半模态提醒设置面板 (`reminderSettingsSheet`)**:
   - 基于 `.bindSheet` 实现符合鸿蒙设计规范的底部抽屉面板。
   - 提供「每日临期汇总提醒」开关 (`ToggleSwitch`)。
   - 提供「提醒时间」选择行，点击调用系统 `showTimePickerDialog` 选择小时和分钟。
   - 状态变更时自动保存至 `Preferences` 首选项，并通过 `ReminderService.getInstance().syncDailyReminder(ctx)` 重新同步后台日历提醒，同时弹出 Toast 提示「已更新提醒设置」。

## 3. Git 提交
- **Commit**: `12063cb`
- **Message**: `feat(ui): add reminder settings panel and handle notification deep-link filter`

## 4. 自检与验证
- ArkTS / ArkUI 语法、生命周期与类型约束验证通过。
- 深度链接过滤逻辑与 `EntryAbility` 传递的 `filterLevel` 完美契合。
- 提醒设置状态流转清晰，首选项持久化与后台代理提醒调度无缝联动。
