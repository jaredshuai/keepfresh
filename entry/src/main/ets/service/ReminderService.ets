/**
 * 代理提醒服务：首选项配置管理与代理提醒调度。
 */
import { preferences } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

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
}
