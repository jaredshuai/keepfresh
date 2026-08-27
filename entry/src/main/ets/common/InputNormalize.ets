/**
 * 输入归一化（移植自 the-ai-menu pantryService 归一化三件套）。
 * 表单提交前的统一防御处理。
 */

/** trim 后空返回 '' */
export function normalizeText(s: string | undefined | null): string {
  if (s === undefined || s === null) {
    return '';
  }
  return s.trim();
}

/** trim 后空返回 null */
export function normalizeNullableText(s: string | undefined | null): string | null {
  const t: string = normalizeText(s);
  if (t.length === 0) {
    return null;
  }
  return t;
}

/** 非负整数校验，非法返回 null */
export function normalizeNonNegativeInteger(n: number | undefined | null): number | null {
  if (n === undefined || n === null) {
    return null;
  }
  if (!Number.isFinite(n) || n < 0 || Math.floor(n) !== n) {
    return null;
  }
  return Math.floor(n);
}

/** 字符串转非负整数，非法（空/非数字/负数/小数）返回 null */
export function parseNonNegativeInteger(s: string | undefined | null): number | null {
  const t: string = normalizeText(s);
  if (t.length === 0) {
    return null;
  }
  const n: number = Number(t);
  return normalizeNonNegativeInteger(n);
}
