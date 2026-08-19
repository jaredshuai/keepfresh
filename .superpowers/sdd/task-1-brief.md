# Task 1 Brief: 权限声明与首选项配置层 (`module.json5`, `ReminderService.ets`)

## Files
- Modify: `entry/src/main/module.json5`
- Create: `entry/src/main/ets/service/ReminderService.ets`

## Requirements
1. In `entry/src/main/module.json5`:
   - In `module` object, add `requestPermissions` array with:
     ```json5
     "requestPermissions": [
       {
         "name": "ohos.permission.PUBLISH_AGENT_REMINDER"
       }
     ]
     ```
2. Create `entry/src/main/ets/service/ReminderService.ets`:
   - Define interface `ReminderSettings`:
     ```typescript
     export interface ReminderSettings {
       enabled: boolean;
       hour: number;    // 0~23, default 9
       minute: number;  // 0~59, default 0
     }
     ```
   - Define singleton class `ReminderService`:
     - `public static getInstance(): ReminderService`
     - `public async init(context: Context): Promise<void>` -> uses `@kit.ArkData`'s `preferences.getPreferences(context, 'keepfresh_reminder_prefs')`.
     - `public async getSettings(): Promise<ReminderSettings>` -> reads `reminder_enabled` (default true), `reminder_hour` (default 9), `reminder_minute` (default 0).
     - `public async updateSettings(settings: ReminderSettings): Promise<void>` -> writes `reminder_enabled`, `reminder_hour`, `reminder_minute` and calls `flush()`.
3. Commit with message:
   `feat(reminder): add reminder permission and preferences configuration`
