# Task 2 Brief: 封装 `reminderAgentManager` 代理提醒注册与 WantAgent (`ReminderService.ets`)

## Files
- Modify: `entry/src/main/ets/service/ReminderService.ets`

## Requirements
1. Import necessary modules:
   ```typescript
   import { reminderAgentManager } from '@kit.BackgroundTasksKit';
   import { wantAgent, WantAgent } from '@kit.AbilityKit';
   import { MaterialDb } from '../db/MaterialDb';
   import { levelOf } from './ExpiryService';
   import { Material } from '../model/Material';
   ```
2. In `ReminderService.ets`, implement `cancelAllReminders()`:
   ```typescript
   public async cancelAllReminders(): Promise<void> {
     try {
       await reminderAgentManager.cancelAllReminders();
       hilog.info(DOMAIN, TAG, 'All reminders cancelled successfully.');
     } catch (err) {
       const e = err as BusinessError;
       hilog.error(DOMAIN, TAG, 'Failed to cancel reminders: %{public}s', e.message);
     }
   }
   ```
3. Implement `syncDailyReminder(context: Context): Promise<void>`:
   - Call `await this.init(context)`.
   - Read `const settings = await this.getSettings()`.
   - If `!settings.enabled`, call `await this.cancelAllReminders()` and return.
   - Query materials using `const db = MaterialDb.getInstance(); await db.init(context); const materials = await db.getAll();`.
   - Compute `expiredCount` (where `levelOf(m) === 'EXPIRED'`) and `nearCount` (where `levelOf(m) === 'NEAR'`).
   - If `expiredCount === 0 && nearCount === 0`:
     - System is safe, keep silent: call `await this.cancelAllReminders()` and return.
   - If `expiredCount > 0 || nearCount > 0`:
     - First call `await this.cancelAllReminders()` to avoid duplicate alarms.
     - Prepare text parts: e.g. `${expiredCount} 件已过期`, `${nearCount} 件即将过期`. Join as `${parts.join('，')}，请及时处理`.
     - Build `WantAgentInfo`:
       ```typescript
       const wantAgentInfo: wantAgent.WantAgentInfo = {
         wants: [
           {
             bundleName: 'com.jaredshuai.keepfresh',
             abilityName: 'EntryAbility',
             parameters: {
               filterLevel: 'NEAR'
             }
           }
         ],
         operationType: wantAgent.OperationType.START_ABILITY,
         requestCode: 1001,
         wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
       };
       const agent = await wantAgent.getWantAgent(wantAgentInfo);
       ```
     - Construct `reminderAgentManager.ReminderRequestCalendar`:
       ```typescript
       // repeatMonths: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]
       // repeatDays: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31]
       const calendarReq: reminderAgentManager.ReminderRequestCalendar = {
         reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
         hour: settings.hour,
         minute: settings.minute,
         repeatMonths: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
         repeatDays: Array.from({ length: 31 }, (_, i) => i + 1),
         title: 'KeepFresh 临期提醒',
         content: textContent,
         wantAgent: agent,
         ringDuration: 5,
         snoozeTimes: 0,
         timeInterval: 0,
         actionButton: [
           {
             title: '查看',
             type: reminderAgentManager.ActionButtonType.ACTION_BUTTON_TYPE_CLOSE
           }
         ]
       };
       ```
     - Call `const reminderId = await reminderAgentManager.publishReminder(calendarReq);`.
     - Log success with `reminderId`.
4. Commit with message:
   `feat(reminder): implement reminderAgentManager scheduling and wantAgent binding`
