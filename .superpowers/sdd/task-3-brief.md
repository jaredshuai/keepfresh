# Task 3 Brief: 物资生命周期与启动时自动同步 (`AddItem.ets`, `ItemDetail.ets`, `EntryAbility.ets`)

## Files
- Modify: `entry/src/main/ets/entryability/EntryAbility.ets`
- Modify: `entry/src/main/ets/pages/AddItem.ets`
- Modify: `entry/src/main/ets/pages/ItemDetail.ets`

## Requirements
1. In `entry/src/main/ets/entryability/EntryAbility.ets`:
   - Import `ReminderService` from `../service/ReminderService`.
   - In `onCreate(want: Want, launchParam: AbilityConstant.LaunchParam)`:
     - Check if `want?.parameters?.filterLevel` is provided. If so, store in `AppStorage.setOrCreate('targetFilterLevel', want.parameters.filterLevel as string)`.
     - Call `ReminderService.getInstance().syncDailyReminder(this.context)` (catch errors gracefully).
   - In `onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam)`:
     - If `want?.parameters?.filterLevel` is provided, store in `AppStorage.setOrCreate('targetFilterLevel', want.parameters.filterLevel as string)`.
     - Call `ReminderService.getInstance().syncDailyReminder(this.context)` (catch errors gracefully).
   - In `onForeground()`:
     - Call `ReminderService.getInstance().syncDailyReminder(this.context)` to refresh daily reminder on app foreground.
2. In `entry/src/main/ets/pages/AddItem.ets`:
   - Import `ReminderService` from `../service/ReminderService`.
   - In `save()`, after successfully inserting or updating database:
     - `ReminderService.getInstance().syncDailyReminder(ctx);`
3. In `entry/src/main/ets/pages/ItemDetail.ets`:
   - Import `ReminderService` from `../service/ReminderService`.
   - In `doDelete()`, after successfully removing item:
     - `const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;`
     - `ReminderService.getInstance().syncDailyReminder(ctx);`
4. Commit with message:
   `feat(reminder): sync offline reminders on data mutations and app startup`
