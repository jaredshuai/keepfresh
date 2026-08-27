/**
 * 物资关键词过滤（移植自 the-ai-menu pantry-screen.ts filterPantryItemsByKeyword）。
 * 跨 name/category/location/note/barcode 的小写包含匹配。
 */
import type { Material } from '../model/Material';

/** 匹配关键词的字段拼接（小写） */
function searchableText(m: Material): string {
  const parts: string[] = [m.name, m.category, m.location, m.note, m.barcode ?? ''];
  return parts.join(' ').toLowerCase();
}

/** 关键词过滤：空关键词返回原列表 */
export function filterByKeyword(list: Material[], keyword: string): Material[] {
  const kw: string = (keyword ?? '').trim().toLowerCase();
  if (kw.length === 0) {
    return list;
  }
  const result: Material[] = [];
  for (let i = 0; i < list.length; i++) {
    if (searchableText(list[i]).includes(kw)) {
      result.push(list[i]);
    }
  }
  return result;
}
