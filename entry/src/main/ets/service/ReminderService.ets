/**
 * 日程提醒服务：基于 Calendar Kit 的每日提醒 + 首选项配置管理。
 * （原 reminderAgentManager 代理提醒路径已废弃：PUBLISH_AGENT_REMINDER 为受限权限，
 *  未授权时配额恒为 0，publish 必抛 1700002；日历日程是普通 user_grant 权限路径）
 */
import { preferences } from '@kit.ArkData';
import { abilityAccessCtrl, common, Context, PermissionRequestResult, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { calendarManager } from '@kit.CalendarKit';
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

/** 每日提醒日程的标题与标识（filterByTitle 找旧日程，identifier 留作系统侧关联键） */
const EVENT_TITLE: string = 'KeepFresh 临期提醒';
const EVENT_IDENTIFIER: string = 'keepfresh-daily-reminder';
const CALENDAR_ACCOUNT_NAME: string = 'keepfresh_reminder';

export interface ReminderSettings {
  enabled: boolean;
  hour: number;    // 0~23, default 9
  minute: number;  // 0~59, default 0
}

export class ReminderService {
  private static instance?: ReminderService;
  private prefStore?: preferences.Preferences;
  private syncPromise: Promise<void> | undefined;
  private calendarContext?: Context;

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
      // 设置已持久化；仅同步失败（如未授予日历权限）附提示
      console.error(`reminder settings saved but sync failed: ${(syncErr as BusinessError).message}`);
      hint = '，但提醒同步失败（检查日历权限）';
    }
    return `已更新提醒设置${hint}`;
  }

  /** 删除标题匹配的 KeepFresh 提醒日程（幂等清理；Calendar Kit 无 cancelAll 语义） */
  public async cancelAllReminders(): Promise<void> {
    try {
      const calendar: calendarManager.Calendar = await this.getOrCreateCalendar();
      const filter: calendarManager.EventFilter = calendarManager.EventFilter.filterByTitle(EVENT_TITLE);
      const events: calendarManager.Event[] = await calendar.getEvents(filter);
      for (const e of events) {
        if (e.id !== undefined) {
          await calendar.deleteEvent(e.id);
        }
      }
      hilog.info(DOMAIN, TAG, `Cleared ${events.length} reminder event(s).`);
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      hilog.error(DOMAIN, TAG, `Failed to clear reminder events: ${e.code}, message: ${e.message}`);
      throw new Error(e.message);
    }
  }

  /**
   * 同步每日提醒（串行化）：onCreate + onForeground 同帧双触发会产生并发操作，
   * 串行保证同一时刻只有一个同步任务在改日历。
   */
  public syncDailyReminder(context: Context): Promise<void> {
    if (this.syncPromise) {
      return this.syncPromise;
    }
    this.syncPromise = this.doSyncDailyReminder(context).finally(() => {
      this.syncPromise = undefined;
    });
    return this.syncPromise;
  }

  private async ensureCalendarPermission(context: Context): Promise<boolean> {
    const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    const permissions: Permissions[] = ['ohos.permission.READ_CALENDAR', 'ohos.permission.WRITE_CALENDAR'];
    try {
      const result: PermissionRequestResult = await atManager.requestPermissionsFromUser(
        context as common.UIAbilityContext, permissions);
      const granted: boolean = result.authResults.every((code: number) => code === 0);
      if (!granted) {
        hilog.warn(DOMAIN, TAG, `Calendar permission denied: ${JSON.stringify(result.authResults)}`);
      }
      return granted;
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      hilog.error(DOMAIN, TAG, `requestPermissionsFromUser failed: ${e.code}, message: ${e.message}`);
      return false;
    }
  }

  /** 取应用专属日历账户；首次调用时创建（LOCAL 账户，不联网） */
  private async getOrCreateCalendar(): Promise<calendarManager.Calendar> {
    const mgr: calendarManager.CalendarManager = calendarManager.getCalendarManager(this.calendarContext!);
    const account: calendarManager.CalendarAccount = {
      name: CALENDAR_ACCOUNT_NAME,
      type: calendarManager.CalendarType.LOCAL,
      displayName: 'KeepFresh 提醒'
    };
    try {
      return await mgr.getCalendar(account);
    } catch {
      return await mgr.createCalendar(account);
    }
  }

  private async doSyncDailyReminder(context: Context): Promise<void> {
    await this.init(context);
    const settings: ReminderSettings = await this.getSettings();
    this.calendarContext = context;

    if (!settings.enabled) {
      await this.cancelAllReminders();
      return;
    }

    const granted: boolean = await this.ensureCalendarPermission(context);
    if (!granted) {
      hilog.warn(DOMAIN, TAG, 'Calendar permission not granted; skip reminder sync');
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

    // 旧日程先删再建：日历 Event 无就地更新语义，标题/文案/提醒时间以最新为准
    await this.cancelAllReminders();

    const textContent: string = `${buildReminderText(materials)}，请及时处理`;
    const now: Date = new Date();
    const start: Date = new Date(now.getFullYear(), now.getMonth(), now.getDate(), settings.hour, settings.minute, 0);
    if (start.getTime() <= now.getTime()) {
      start.setDate(start.getDate() + 1); // 今天已过点则排明天
    }

    const event: calendarManager.Event = {
      type: calendarManager.EventType.NORMAL,
      title: EVENT_TITLE,
      description: textContent,
      identifier: EVENT_IDENTIFIER,
      startTime: start.getTime(),
      endTime: start.getTime() + 30 * 60 * 1000,
      reminderTime: [0], // 开始时刻即提醒（设置的 hour:minute）
      recurrenceRule: {
        recurrenceFrequency: calendarManager.RecurrenceFrequency.DAILY
      }
    };

    try {
      const calendar: calendarManager.Calendar = await this.getOrCreateCalendar();
      const eventId: number = await calendar.addEvent(event);
      hilog.info(DOMAIN, TAG, `Reminder event published, eventId: ${eventId}`);
      UsageService.getInstance().logReminderPublished(expiredCount, nearCount);
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      hilog.error(DOMAIN, TAG, `Failed to publish reminder event: ${e.code}, message: ${e.message}`);
      throw new Error(e.message);
    }
  }
}
