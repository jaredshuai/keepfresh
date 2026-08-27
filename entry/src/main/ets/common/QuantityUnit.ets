/**
 * 数量单位解析与格式化（移植自 the-ai-menu quantity-unit.ts）。
 * 支持 "500g" 这类混合输入自动拆分为数值 + 单位。
 */

export interface NormalizedQuantity {
  quantity: string;
  unit: string;
}

/** 数值 + 可选单位（中文或英文字母） */
const MIXED_INPUT_RE: RegExp = /^(\d+\.?\d*)([\u4e00-\u9fa5a-zA-Z]+)$/;

/**
 * 归一化数量与单位：
 * - quantity 为空 → 原样返回（保 unit）
 * - unit 已知且 quantity 以 unit 结尾 → 剥离单位，返回纯数值
 * - 混合输入（"500g"）→ 正则拆分为 {quantity:"500", unit:"g"}
 * - 其他 → 原样返回
 */
export function normalizeQuantityUnit(quantity: string, unit: string): NormalizedQuantity {
  const q: string = (quantity ?? '').trim();
  const u: string = (unit ?? '').trim();
  if (q.length === 0) {
    const empty: NormalizedQuantity = { quantity: '', unit: u };
    return empty;
  }
  // quantity 以已知单位结尾 → 剥离
  if (u.length > 0 && q.endsWith(u)) {
    const stripped: string = q.slice(0, q.length - u.length).trim();
    if (stripped.length > 0 && isFinite(Number(stripped))) {
      const parsed: NormalizedQuantity = { quantity: stripped, unit: u };
      return parsed;
    }
  }
  // 混合输入 "500g" → 拆分
  const match: RegExpMatchArray | null = q.match(MIXED_INPUT_RE);
  if (match !== null && match.length >= 3) {
    const mixed: NormalizedQuantity = { quantity: match[1], unit: match[2] };
    return mixed;
  }
  const asIs: NormalizedQuantity = { quantity: q, unit: u };
  return asIs;
}

/** 拼回显示文本，处理空边 */
export function formatQuantityUnit(quantity: string, unit: string, separator: string = ' '): string {
  const q: string = (quantity ?? '').trim();
  const u: string = (unit ?? '').trim();
  if (q.length === 0) {
    return u;
  }
  if (u.length === 0) {
    return q;
  }
  return `${q}${separator}${u}`;
}
