/**
 * 代理提醒服务：首选项配置管理与代理提醒调度。
 */
import { preferences } from '@kit.ArkData';
import { Context, wantAgent } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { MaterialDb } from '../db/MaterialDb';
import { levelOf } from './ExpiryService';
import { Material, ExpiryLevel } from '../model/Material';

const DOMAIN: number = 0x0000;
const TAG: string = 'ReminderService';
const PREF_NAME: string = 'keepfresh_reminder_prefs';
const KEY_ENABLED: string = 'reminder_enabled';
const KEY_HOUR: string = 'reminder_hour';
const KEY_MINUTE: string = 'reminder_minute';

export interface ReminderSettings {
  enabled: boolean;
  hour: number;    // 0~23, default 9
  minute: number;  // 0~59, default 0
}

export class ReminderService {
  private static instance?: ReminderService;
  private prefStore?: preferences.Preferences;

  private constructor() {}

  public static getInstance(): ReminderService {
    if (!ReminderService.instance) {
      ReminderService.instance = new ReminderService();
    }
    return ReminderService.instance;
  }

  public async init(context: Context): Promise<void> {
    if (this.prefStore) {
      return;
    }
    try {
      this.prefStore = await preferences.getPreferences(context, PREF_NAME);
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      hilog.error(DOMAIN, TAG, `Failed to get preferences: ${e.code}, message: ${e.message}`);
    }
  }

  public async getSettings(): Promise<ReminderSettings> {
    if (!this.prefStore) {
      return { enabled: true, hour: 9, minute: 0 };
    }
    try {
      const enabled: boolean = await this.prefStore.get(KEY_ENABLED, true) as boolean;
      const hour: number = await this.prefStore.get(KEY_HOUR, 9) as number;
      const minute: number = await this.prefStore.get(KEY_MINUTE, 0) as number;
      return { enabled, hour, minute };
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      hilog.error(DOMAIN, TAG, `Failed to get settings: ${e.code}, message: ${e.message}`);
      return { enabled: true, hour: 9, minute: 0 };
    }
  }

  public async updateSettings(settings: ReminderSettings): Promise<void> {
    if (!this.prefStore) {
      return;
    }
    try {
      await this.prefStore.put(KEY_ENABLED, settings.enabled);
      await this.prefStore.put(KEY_HOUR, settings.hour);
      await this.prefStore.put(KEY_MINUTE, settings.minute);
      await this.prefStore.flush();
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      hilog.error(DOMAIN, TAG, `Failed to update settings: ${e.code}, message: ${e.message}`);
    }
  }

  public async cancelAllReminders(): Promise<void> {
    try {
      await reminderAgentManager.cancelAllReminders();
      hilog.info(DOMAIN, TAG, 'All reminders cancelled successfully.');
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      hilog.error(DOMAIN, TAG, `Failed to cancel reminders: ${e.message}`);
    }
  }

  public async syncDailyReminder(context: Context): Promise<void> {
    await this.init(context);
    const settings: ReminderSettings = await this.getSettings();
    if (!settings.enabled) {
      await this.cancelAllReminders();
      return;
    }

    const db: MaterialDb = MaterialDb.getInstance();
    await db.init(context);
    const materials: Material[] = await db.getAll();

    let expiredCount: number = 0;
    let nearCount: number = 0;
    for (const m of materials) {
      const level: ExpiryLevel = levelOf(m);
      if (level === ExpiryLevel.EXPIRED) {
        expiredCount++;
      } else if (level === ExpiryLevel.NEAR) {
        nearCount++;
      }
    }

    if (expiredCount === 0 && nearCount === 0) {
      await this.cancelAllReminders();
      return;
    }

    await this.cancelAllReminders();

    const parts: string[] = [];
    if (expiredCount > 0) {
      parts.push(`${expiredCount} 件已过期`);
    }
    if (nearCount > 0) {
      parts.push(`${nearCount} 件即将过期`);
    }
    const textContent: string = `${parts.join('，')}，请及时处理`;

    try {
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

      const calendarReq: reminderAgentManager.ReminderRequestCalendar = {
        reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
        hour: settings.hour,
        minute: settings.minute,
        repeatMonths: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
        repeatDays: [
          1, 2, 3, 4, 5, 6, 7, 8, 9, 10,
          11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
          21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31
        ],
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

      const reminderId: number = await reminderAgentManager.publishReminder(calendarReq);
      hilog.info(DOMAIN, TAG, `Reminder published successfully, reminderId: ${reminderId}`);
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      hilog.error(DOMAIN, TAG, `Failed to publish reminder: ${e.code}, message: ${e.message}`);
    }
  }
}
