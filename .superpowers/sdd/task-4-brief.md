# Task 4 Brief: 首页 `Index.ets` 交互联动与提醒设置面板

## Files
- Modify: `entry/src/main/ets/pages/Index.ets`

## Requirements
1. In `Index.ets`:
   - Import `ReminderService`, `ReminderSettings` from `../service/ReminderService`.
   - On `onPageShow()`:
     - Check `AppStorage.get<string>('targetFilterLevel')`.
     - If `'NEAR'`, set `this.filter = ListFilter.NEAR` and clear `AppStorage.setOrCreate('targetFilterLevel', undefined)`.
     - If `'EXPIRED'`, set `this.filter = ListFilter.EXPIRED` and clear `AppStorage.setOrCreate('targetFilterLevel', undefined)`.
   - Add state for reminder settings dialog:
     - `@State showSettingsDialog: boolean = false;`
     - `@State reminderEnabled: boolean = true;`
     - `@State reminderHour: number = 9;`
     - `@State reminderMinute: number = 0;`
   - In `onPageShow()`, load current settings via `ReminderService.getInstance().getSettings()`:
     ```typescript
     const settings = await ReminderService.getInstance().getSettings();
     this.reminderEnabled = settings.enabled;
     this.reminderHour = settings.hour;
     this.reminderMinute = settings.minute;
     ```
   - In the header `Row()` of `Index.ets`:
     - On the right side (after `Blank()`), add a bell/settings button:
       ```typescript
       Button({ type: ButtonType.Circle, stateEffect: true }) {
         SymbolGlyph($r('sys.symbol.bell'))
           .fontSize(20)
           .fontColor([this.reminderEnabled ? CLR_BRAND : CLR_TEXT_SUB])
       }
       .backgroundColor(CLR_CARD)
       .width(40)
       .height(40)
       .onClick(() => {
         this.openReminderSettingsDialog();
       })
       ```
   - Implement `openReminderSettingsDialog()`:
     - Use `this.getUIContext().showAlertDialog` or a clean CustomDialog/Sheet providing:
       - 每日临期汇总开关
       - 提醒时间选择（如利用 `showTimePickerDialog` 选择小时与分钟）
       - 保存时调用 `ReminderService.getInstance().updateSettings(...)` 和 `ReminderService.getInstance().syncDailyReminder(ctx)`，并 Toast 提示 `已更新提醒设置`。
2. Verify ArkTS / HarmonyOS syntax and typing.
3. Commit with message:
   `feat(ui): add reminder settings panel and handle notification deep-link filter`
