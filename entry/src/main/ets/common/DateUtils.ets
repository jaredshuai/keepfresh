/**
 * 日期字符串工具：统一使用 YYYY-MM-DD 格式。
 */

export function pad2(n: number): string {
  return n < 10 ? `0${n}` : `${n}`;
}

export function toDateStr(d: Date): string {
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
}

export function todayStr(): string {
  return toDateStr(new Date());
}

export function parseDate(s: string): Date {
  return new Date(`${s}T00:00:00`);
}

export function addDays(dateStr: string, days: number): string {
  const d: Date = parseDate(dateStr);
  d.setDate(d.getDate() + days);
  return toDateStr(d);
}

/** from - to 的天数差（from 晚于 to 为正） */
export function diffDays(from: string, to: string): number {
  const a: Date = parseDate(from);
  const b: Date = parseDate(to);
  return Math.round((a.getTime() - b.getTime()) / 86400000);
}

/**
 * 按月加法，自动 clamp 到月末。
 * 例：2024-01-31 + 1 个月 = 2024-02-29（不是 3-03）；
 *     2023-01-31 + 1 个月 = 2023-02-28。
 * 负数月份同样支持（跨年取模兼容负数）。
 */
export function addMonths(dateStr: string, months: number): string {
  const d: Date = parseDate(dateStr);
  const year: number = d.getFullYear();
  const monthIndex: number = d.getMonth(); // 0-11
  const day: number = d.getDate();

  const nextMonthIndex: number = monthIndex + months;
  const targetYear: number = year + Math.floor(nextMonthIndex / 12);
  const targetMonth: number = ((nextMonthIndex % 12) + 12) % 12;

  // 取目标月最后一天（day=0 即上月末）
  const lastDayOfTargetMonth: number = new Date(targetYear, targetMonth + 1, 0).getDate();
  const clampedDay: number = Math.min(day, lastDayOfTargetMonth);

  const result: Date = new Date(targetYear, targetMonth, clampedDay);
  return toDateStr(result);
}
