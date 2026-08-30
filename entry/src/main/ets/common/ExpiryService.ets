import type { Material } from '../model/Material';
import { ExpiryLevel, MaterialStatus, DerivedStatus } from '../model/Material';
import { addDays, addMonths, diffDays, todayStr } from '../common/DateUtils';
import { NEAR_EXPIRY_DAYS_MIN, NEAR_EXPIRY_DAYS_MAX } from '../common/Validation';

export const DEFAULT_NEAR_EXPIRY_DAYS: number = 7;

/** 模块级临期阈值缓存（保证同步函数高性能） */
let cachedNearExpiryDays: number = DEFAULT_NEAR_EXPIRY_DAYS;

export function getNearExpiryThreshold(): number {
  return cachedNearExpiryDays;
}

export function setNearExpiryThreshold(days: number): void {
  if (days >= NEAR_EXPIRY_DAYS_MIN && days <= NEAR_EXPIRY_DAYS_MAX) {
    cachedNearExpiryDays = Math.floor(days);
  }
}

export interface ExpiryStats {
  total: number;
  expired: number;
  near: number;
  safe: number;
}

/** 多维度统计概览（移植自 the-ai-menu buildPantryOverview） */
export interface MaterialOverview {
  total: number;
  expired: number;
  expiring: number;
  safe: number;
  opened: number;
  empty: number;
  discarded: number;
  byCategory: Record<string, number>;
  byLocation: Record<string, number>;
}

/**
 * 计算到期日：月数优先（按月加法 + 月末 clamp），否则按天数加。
 * 2024-01-31 + 1 个月 = 2024-02-29。
 */
export function calcExpiryDate(productionDate: string, shelfLifeDays: number, shelfLifeMonths?: number): string {
  if (shelfLifeMonths !== undefined && shelfLifeMonths !== null && shelfLifeMonths > 0) {
    return addMonths(productionDate, shelfLifeMonths);
  }
  return addDays(productionDate, shelfLifeDays);
}

/** 距到期的剩余天数，负数表示已过期的天数 */
export function remainingDays(m: Material): number {
  return diffDays(m.expiryDate, todayStr());
}

export function levelOf(m: Material, customThreshold?: number): ExpiryLevel {
  const left: number = remainingDays(m);
  if (left < 0) {
    return ExpiryLevel.EXPIRED;
  }
  const th = customThreshold !== undefined ? customThreshold : cachedNearExpiryDays;
  if (left <= th) {
    return ExpiryLevel.NEAR;
  }
  return ExpiryLevel.SAFE;
}

/** 过期日早于今天 */
export function isExpired(m: Material): boolean {
  return remainingDays(m) < 0;
}

/** 0 <= 剩余天数 <= 阈值。今天到期算临期：CONTEXT.md 临期定义即"剩余不大于阈值"，
 *  levelOf/统计头一直按此口径；旧版此处排除 0 导致分组把今天到期的物品沉进"安全"组，
 *  与统计头矛盾（直录到期日默认今天，一发现在就修） */
export function isExpiringSoon(m: Material, customThreshold?: number): boolean {
  const left: number = remainingDays(m);
  if (left < 0) {
    return false;
  }
  const th = customThreshold !== undefined ? customThreshold : cachedNearExpiryDays;
  return left <= th;
}

/**
 * 实际状态（状态机，移植自 the-ai-menu getActualStatus）：
 * 终态（empty/discarded）优先且不可被过期覆盖 → expired → expiring → 持久化状态。
 */
export function getActualStatus(m: Material): string {
  const persisted: string = m.status ?? MaterialStatus.ACTIVE;
  if (persisted === MaterialStatus.EMPTY || persisted === MaterialStatus.DISCARDED) {
    return persisted;
  }
  if (isExpired(m)) {
    return DerivedStatus.EXPIRED;
  }
  if (isExpiringSoon(m)) {
    return DerivedStatus.EXPIRING;
  }
  return persisted;
}

/** 状态风险序：expired=0, expiring=1, 终态=2, 其他=3（排序用，终态沉底） */
export function riskOrderOf(m: Material): number {
  const actual: string = getActualStatus(m);
  if (actual === DerivedStatus.EXPIRED) {
    return 0;
  }
  if (actual === DerivedStatus.EXPIRING) {
    return 1;
  }
  if (actual === MaterialStatus.EMPTY || actual === MaterialStatus.DISCARDED) {
    return 3;
  }
  return 2;
}

/**
 * 风险优先排序（移植自 the-ai-menu sortPantryItemsByRiskAndExpiration）：
 * 先按 riskOrder 升序（过期 → 临期 → 在库/开封 → 终态沉底），
 * 组内按到期日升序（无到期日靠后），再按创建时间倒序。
 */
export function sortByRiskAndExpiration(list: Material[]): Material[] {
  const copy: Material[] = list.slice();
  copy.sort((a: Material, b: Material): number => {
    const ra: number = riskOrderOf(a);
    const rb: number = riskOrderOf(b);
    if (ra !== rb) {
      return ra - rb;
    }
    const ea: string = a.expiryDate ?? '';
    const eb: string = b.expiryDate ?? '';
    if (ea.length === 0 && eb.length === 0) {
      return compareCreatedAtDesc(a, b);
    }
    if (ea.length === 0) {
      return 1;
    }
    if (eb.length === 0) {
      return -1;
    }
    if (ea !== eb) {
      return ea < eb ? -1 : 1;
    }
    return compareCreatedAtDesc(a, b);
  });
  return copy;
}

function compareCreatedAtDesc(a: Material, b: Material): number {
  const ca: string = a.createdAt ?? '';
  const cb: string = b.createdAt ?? '';
  if (ca === cb) {
    return b.id - a.id;
  }
  return ca < cb ? 1 : -1;
}

/** 按创建时间倒序 */
export function sortByCreatedDesc(list: Material[]): Material[] {
  const copy: Material[] = list.slice();
  copy.sort((a: Material, b: Material): number => compareCreatedAtDesc(a, b));
  return copy;
}

/** 按到期日升序（无到期日靠后，再按创建倒序） */
export function sortByExpirationAsc(list: Material[]): Material[] {
  const copy: Material[] = list.slice();
  copy.sort((a: Material, b: Material): number => {
    const ea: string = a.expiryDate ?? '';
    const eb: string = b.expiryDate ?? '';
    if (ea.length === 0 && eb.length === 0) {
      return compareCreatedAtDesc(a, b);
    }
    if (ea.length === 0) {
      return 1;
    }
    if (eb.length === 0) {
      return -1;
    }
    if (ea !== eb) {
      return ea < eb ? -1 : 1;
    }
    return compareCreatedAtDesc(a, b);
  });
  return copy;
}

/** 多维度统计（软删除项不进入统计） */
export function buildOverview(list: Material[], customThreshold?: number): MaterialOverview {
  const overview: MaterialOverview = {
    total: 0,
    expired: 0,
    expiring: 0,
    safe: 0,
    opened: 0,
    empty: 0,
    discarded: 0,
    byCategory: {},
    byLocation: {}
  };
  for (let i = 0; i < list.length; i++) {
    const m: Material = list[i];
    if (m.isDeleted) {
      continue;
    }
    overview.total++;
    const actual: string = getActualStatus(m);
    if (actual === DerivedStatus.EXPIRED) {
      overview.expired++;
    } else if (actual === DerivedStatus.EXPIRING) {
      overview.expiring++;
    } else if (actual === MaterialStatus.EMPTY) {
      overview.empty++;
    } else if (actual === MaterialStatus.DISCARDED) {
      overview.discarded++;
    } else {
      if (actual === MaterialStatus.OPENED) {
        overview.opened++;
      }
      overview.safe++;
    }
    const cat: string = (m.category ?? '').trim();
    if (cat.length > 0) {
      overview.byCategory[cat] = (overview.byCategory[cat] ?? 0) + 1;
    }
    const loc: string = (m.location ?? '').trim();
    if (loc.length > 0) {
      overview.byLocation[loc] = (overview.byLocation[loc] ?? 0) + 1;
    }
  }
  return overview;
}

/** 列表徽标短文案 */
export function levelText(level: ExpiryLevel, left: number): string {
  if (level === ExpiryLevel.EXPIRED) {
    return `已过期 ${-left} 天`;
  }
  if (left === 0) {
    return '今天到期';
  }
  return `剩 ${left} 天`;
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

/**
 * 预警资格分桶 —— 「谁进入临期/过期口径」的唯一判定（统计头/提醒文案/提醒触发/首页分组共用）。
 * 跳过软删除（不变量 2）与终态（终态不被过期覆盖）；其余按 levelOf 分桶。
 * other = 在库/开封且未临期；terminal 收集终态行供分组沉底用。
 */
export interface AlertSplit {
  expired: Material[];
  near: Material[];
  other: Material[];
  terminal: Material[];
}

export function splitByAlertLevel(list: Material[], customThreshold?: number): AlertSplit {
  const split: AlertSplit = { expired: [], near: [], other: [], terminal: [] };
  for (let i = 0; i < list.length; i++) {
    const m: Material = list[i];
    if (m.isDeleted) {
      continue;
    }
    const persisted: string = m.status ?? MaterialStatus.ACTIVE;
    if (persisted === MaterialStatus.EMPTY || persisted === MaterialStatus.DISCARDED) {
      split.terminal.push(m);
      continue;
    }
    const lv: ExpiryLevel = levelOf(m, customThreshold);
    if (lv === ExpiryLevel.EXPIRED) {
      split.expired.push(m);
    } else if (lv === ExpiryLevel.NEAR) {
      split.near.push(m);
    } else {
      split.other.push(m);
    }
  }
  return split;
}

export function statsOf(list: Material[], customThreshold?: number): ExpiryStats {
  const s: AlertSplit = splitByAlertLevel(list, customThreshold);
  const expired: number = s.expired.length;
  const near: number = s.near.length;
  const total: number = expired + near + s.other.length;
  const stats: ExpiryStats = {
    total: total,
    expired: expired,
    near: near,
    safe: s.other.length
  };
  return stats;
}

/** 汇总提醒文案：携带具体物品名，让提醒无需打开 App 即可行动（dogfood P0.5）。
 * 过期优先、按剩余天数升序，最多点名 limit 件；其余以件数概括。
 * 无过期/临期时返回空串（调用方据此取消提醒或不发通知）。 */
export function buildReminderText(items: Material[], limit: number = 3): string {
  const s: AlertSplit = splitByAlertLevel(items);
  if (s.expired.length + s.near.length === 0) {
    return '';
  }
  const expiredSorted = sortByExpirationAsc(s.expired);
  const nearSorted = sortByExpirationAsc(s.near);
  const picked: string[] = [];
  let remain: number = limit;
  for (let i = 0; i < expiredSorted.length && remain > 0; i++) {
    const left: number = remainingDays(expiredSorted[i]);
    picked.push(`${expiredSorted[i].name}（过期${-left}天）`);
    remain--;
  }
  for (let i = 0; i < nearSorted.length && remain > 0; i++) {
    const left: number = remainingDays(nearSorted[i]);
    picked.push(left === 0 ? `${nearSorted[i].name}（今天到期）` : `${nearSorted[i].name}（剩${left}天）`);
    remain--;
  }
  const total: number = s.expired.length + s.near.length;
  let text: string = picked.join('、');
  if (total > picked.length) {
    text = `${text} 等${total}件`;
  }
  return text;
}
