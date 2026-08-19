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
