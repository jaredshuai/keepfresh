/**
 * 到期计算与分级服务。
 */
import { Material, ExpiryLevel, NEAR_EXPIRY_DAYS } from '../model/Material';
import { addDays, diffDays, todayStr } from '../common/DateUtils';

export interface ExpiryStats {
  total: number;
  expired: number;
  near: number;
  safe: number;
}

export function calcExpiryDate(productionDate: string, shelfLifeDays: number): string {
  return addDays(productionDate, shelfLifeDays);
}

/** 距到期的剩余天数，负数表示已过期的天数 */
export function remainingDays(m: Material): number {
  return diffDays(m.expiryDate, todayStr());
}

export function levelOf(m: Material): ExpiryLevel {
  const left: number = remainingDays(m);
  if (left < 0) {
    return ExpiryLevel.EXPIRED;
  }
  if (left <= NEAR_EXPIRY_DAYS) {
    return ExpiryLevel.NEAR;
  }
  return ExpiryLevel.SAFE;
}

export function levelColor(level: ExpiryLevel): string {
  if (level === ExpiryLevel.EXPIRED) {
    return '#FA2A2D';
  }
  if (level === ExpiryLevel.NEAR) {
    return '#FF8D00';
  }
  return '#2FA84F';
}

/** 列表徽标短文案 */
export function levelText(level: ExpiryLevel, left: number): string {
  if (level === ExpiryLevel.EXPIRED) {
    return `已过期${-left}天`;
  }
  if (left === 0) {
    return '今天到期';
  }
  return `剩${left}天`;
}

/** 详情页剩余天数文案 */
export function remainingText(m: Material): string {
  const left: number = remainingDays(m);
  if (left < 0) {
    return `已过期 ${-left} 天`;
  }
  if (left === 0) {
    return '今天到期';
  }
  return `${left} 天`;
}

export function statsOf(list: Material[]): ExpiryStats {
  let expired: number = 0;
  let near: number = 0;
  for (let i = 0; i < list.length; i++) {
    const lv: ExpiryLevel = levelOf(list[i]);
    if (lv === ExpiryLevel.EXPIRED) {
      expired++;
    } else if (lv === ExpiryLevel.NEAR) {
      near++;
    }
  }
  const stats: ExpiryStats = {
    total: list.length,
    expired: expired,
    near: near,
    safe: list.length - expired - near
  };
  return stats;
}
