/**
 * 扫码建议挑选（纯函数，Node 可测）。
 * 条码管身份（ADR-0003 系）：同一条码下在库行代表产品的当前形态，
 * 已删行（回收站模板）只在「该条码已无任何在库行」时兜底出场。
 */
import type { Material } from '../model/Material';

/**
 * 从条码历史（含软删除行）挑选扫码建议：
 * 1. 存在在库行 → 只从在库行出，回收站行一律让位（改名/重录后旧名幽灵不再出现）
 * 2. 全部已删 → 最近入库的已删行作为「历史模板」兜底（点选仅预填表单，保存新建在库行）
 * 去重键 name|location|expiryDate，每键保留最近入库一条；键不含保质期字段——
 * direct 口径记录 shelfLifeDays 恒为 0，该键对两种日期口径都稳定。
 * 入参须已按最近入库倒序（created_at desc, id desc）。
 */
export function selectScanSuggestions(history: Material[]): Material[] {
  const active: Material[] = [];
  for (let i = 0; i < history.length; i++) {
    if (!history[i].isDeleted) {
      active.push(history[i]);
    }
  }
  const pool: Material[] = active.length > 0 ? active : history;
  const seen: Set<string> = new Set<string>();
  const suggestions: Material[] = [];
  for (let i = 0; i < pool.length; i++) {
    const m: Material = pool[i];
    const key: string = `${m.name}|${m.location}|${m.expiryDate}`;
    if (!seen.has(key)) {
      seen.add(key);
      suggestions.push(m);
    }
  }
  return suggestions;
}
