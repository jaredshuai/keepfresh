/**
 * 设置中心服务：统一管理用户配置（临期天数阈值、提醒设置等），基于 Preferences 持久化。
 */
import { preferences } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ReminderService, ReminderSettings } from './ReminderService';
import { setNearExpiryThreshold, DEFAULT_NEAR_EXPIRY_DAYS } from '../common/ExpiryService';
import { NEAR_EXPIRY_DAYS_MIN, NEAR_EXPIRY_DAYS_MAX, validateNearExpiryDays } from '../common/Validation';

const DOMAIN: number = 0x0000;
const TAG: string = 'SettingsService';
const PREF_NAME: string = 'keepfresh_settings_prefs';
const KEY_NEAR_EXPIRY_DAYS: string = 'near_expiry_days';

export interface AppSettings {
  nearExpiryDays: number;
  reminder: ReminderSettings;
}

export class SettingsService {
  private static instance?: SettingsService;
  private prefStore?: preferences.Preferences;
  private isInitialized: boolean = false;

  private constructor() {}

  public static getInstance(): SettingsService {
    if (!SettingsService.instance) {
      SettingsService.instance = new SettingsService();
    }
    return SettingsService.instance;
  }

  /**
   * 初始化设置服务并预热缓存
   */
  public async init(context: Context): Promise<void> {
    if (this.isInitialized && this.prefStore) {
      return;
    }
    try {
      this.prefStore = await preferences.getPreferences(context, PREF_NAME);
      const days = await this.getNearExpiryDays();
      setNearExpiryThreshold(days);
      await ReminderService.getInstance().init(context);
      this.isInitialized = true;
      hilog.info(DOMAIN, TAG, `Settings initialized, nearExpiryDays=${days}`);
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      hilog.error(DOMAIN, TAG, `Failed to init settings: ${e.code}, message: ${e.message}`);
      setNearExpiryThreshold(DEFAULT_NEAR_EXPIRY_DAYS);
    }
  }

  /**
   * 获取临期天数阈值（默认 7）
   */
  public async getNearExpiryDays(): Promise<number> {
    if (!this.prefStore) {
      return DEFAULT_NEAR_EXPIRY_DAYS;
    }
    try {
      const val: number = await this.prefStore.get(KEY_NEAR_EXPIRY_DAYS, DEFAULT_NEAR_EXPIRY_DAYS) as number;
      if (typeof val === 'number' && val >= NEAR_EXPIRY_DAYS_MIN && val <= NEAR_EXPIRY_DAYS_MAX) {
        return Math.floor(val);
      }
      return DEFAULT_NEAR_EXPIRY_DAYS;
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      hilog.error(DOMAIN, TAG, `Failed to get nearExpiryDays: ${e.code}, message: ${e.message}`);
      return DEFAULT_NEAR_EXPIRY_DAYS;
    }
  }

  /**
   * 更新临期天数阈值（1~365 天）并同步刷新模块级缓存
   */
  public async updateNearExpiryDays(days: number): Promise<boolean> {
    if (Number.isNaN(days) || days < NEAR_EXPIRY_DAYS_MIN || days > NEAR_EXPIRY_DAYS_MAX) {
      return false;
    }
    const cleanDays = Math.floor(days);
    setNearExpiryThreshold(cleanDays);
    if (!this.prefStore) {
      return true;
    }
    try {
      await this.prefStore.put(KEY_NEAR_EXPIRY_DAYS, cleanDays);
      await this.prefStore.flush();
      hilog.info(DOMAIN, TAG, `Updated nearExpiryDays to ${cleanDays}`);
      return true;
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      hilog.error(DOMAIN, TAG, `Failed to update nearExpiryDays: ${e.code}, message: ${e.message}`);
      return false;
    }
  }

  /**
   * 校验临期天数输入（转发纯模块实现，测试对象唯一 —— ticket #16）
   */
  public validateNearExpiryDays(input: string | number): string | null {
    return validateNearExpiryDays(input);
  }

  /**
   * 获取全量应用设置
   */
  public async getAllSettings(): Promise<AppSettings> {
    const nearExpiryDays = await this.getNearExpiryDays();
    const reminder = await ReminderService.getInstance().getSettings();
    return {
      nearExpiryDays,
      reminder
    };
  }
}
