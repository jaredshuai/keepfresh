/**
 * 通知服务：授权申请与临期提醒发布。
 */
import { notificationManager } from '@kit.NotificationKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

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

/** 发布一条临期汇总通知（同一 id 会覆盖旧通知） */
export async function publishExpiryAlert(nearCount: number, expiredCount: number): Promise<void> {
  const parts: string[] = [];
  if (expiredCount > 0) {
    parts.push(`${expiredCount} 件已过期`);
  }
  if (nearCount > 0) {
    parts.push(`${nearCount} 件即将过期`);
  }
  if (parts.length === 0) {
    return;
  }
  const request: notificationManager.NotificationRequest = {
    id: NOTIFICATION_ID,
    content: {
      notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
      normal: {
        title: 'KeepFresh 临期提醒',
        text: `${parts.join('，')}，记得及时处理`
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
