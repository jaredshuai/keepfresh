/**
 * 代理提醒服务：首选项配置管理与代理提醒调度。
 */
import { preferences } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { MaterialDb } from '../db/MaterialDb';
import { buildReminderText, splitByAlertLevel } from '../common/ExpiryService';
import { UsageService } from './UsageService';
import { Material } from '../model/Material';

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

  /**
   * 编辑提醒设置（唯一入口，C5）：持久化 + 按开关重算/取消 + 返回 toast 文案。
   * 此前 Index/Settings 各养一份保存管线且已分叉（失败提示/关闭文案不一致）。
   */
  public async editSettings(context: Context, settings: ReminderSettings): Promise<string> {
    await this.init(context);
    await this.updateSettings(settings);
    if (!settings.enabled) {
      await this.cancelAllReminders();
      return '已关闭后台提醒';
    }
    let hint: string = '';
    try {
      await this.syncDailyReminder(context);
    } catch (syncErr) {
      // 设置已持久化；仅同步发布失败（如未授予通知权限）附提示
      console.error(`reminder settings saved but sync failed: ${(syncErr as BusinessError).message}`);
      hint = '，但提醒同步失败（检查通知权限）';
    }
    return `已更新提醒设置${hint}`;
  }

  public async cancelAllReminders(): Promise<void> {
    try {
      await reminderAgentManager.cancelAllReminders();
      hilog.info(DOMAIN, TAG, 'All reminders cancelled successfully.');
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      hilog.error(DOMAIN, TAG, `Failed to cancel reminders: ${e.code}, message: ${e.message}`);
      throw new Error(e.message);
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
    const materials: Material[] = await db.listAll();

    // 预警资格唯一判定（与统计头/提醒文案/首页分组同一口径）
    const split = splitByAlertLevel(materials);
    const expiredCount: number = split.expired.length;
    const nearCount: number = split.near.length;

    if (expiredCount === 0 && nearCount === 0) {
      await this.cancelAllReminders();
      return;
    }

    await this.cancelAllReminders();

    // 文案点名具体物品（dogfood P0.5）：不打开 App 即可知道该处理什么
    const textContent: string = `${buildReminderText(materials)}，请及时处理`;
    // 点通知直达对应状态列表：有过期优先「已过期」，否则「临期」。
    // EntryAbility 会把该参数存入 AppStorage，Index onPageShow 读取后切 Tab。
    const filterLevel: string = expiredCount > 0 ? 'expired' : 'expiring';

    try {
      const alarmReq: reminderAgentManager.ReminderRequestAlarm = {
        reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_ALARM,
        hour: settings.hour,
        minute: settings.minute,
        daysOfWeek: [1, 2, 3, 4, 5, 6, 7],
        title: 'KeepFresh 临期提醒',
        content: textContent,
        wantAgent: {
          pkgName: 'com.jaredshuai.keepfresh',
          abilityName: 'EntryAbility',
          parameters: {
            filterLevel: filterLevel
          }
        },
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

      const reminderId: number = await reminderAgentManager.publishReminder(alarmReq);
      hilog.info(DOMAIN, TAG, `Reminder published successfully, reminderId: ${reminderId}`);
      UsageService.getInstance().logReminderPublished(expiredCount, nearCount);
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      hilog.error(DOMAIN, TAG, `Failed to publish reminder: ${e.code}, message: ${e.message}`);
      throw new Error(e.message);
    }
  }
}
