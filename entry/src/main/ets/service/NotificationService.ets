/**
 * 通知服务：授权申请与临期提醒发布。
 */
import { notificationManager } from '@kit.NotificationKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Material } from '../model/Material';
import { buildReminderText } from './ExpiryService';

const NOTIFICATION_ID: number = 1001;

export async function ensureNotificationEnabled(context: common.UIAbilityContext): Promise<boolean> {
  try {
    return await notificationManager.isNotificationEnabled();
  } catch (err) {
    const e: BusinessError = err as BusinessError;
    console.error(`isNotificationEnabled failed, code: ${e.code}, message: ${e.message}`);
    return false;
  }
}

/** 弹出系统授权弹窗（用户此前拒绝过则直接失败） */
export async function requestNotificationEnable(context: common.UIAbilityContext): Promise<boolean> {
  try {
    await notificationManager.requestEnableNotification(context);
    return true;
  } catch (err) {
    const e: BusinessError = err as BusinessError;
    console.error(`requestEnableNotification failed, code: ${e.code}, message: ${e.message}`);
    return false;
  }
}

/** 发布一条临期汇总通知（同一 id 会覆盖旧通知）；文案点名具体物品（dogfood P0.5） */
export async function publishExpiryAlert(items: Material[]): Promise<void> {
  const text = buildReminderText(items);
  if (text === '') {
    return;
  }
  const request: notificationManager.NotificationRequest = {
    id: NOTIFICATION_ID,
    content: {
      notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
      normal: {
        title: 'KeepFresh 临期提醒',
        text: `${text}，记得及时处理`
      }
    }
  };
  try {
    await notificationManager.publish(request);
  } catch (err) {
    const e: BusinessError = err as BusinessError;
    console.error(`publish notification failed, code: ${e.code}, message: ${e.message}`);
  }
}
