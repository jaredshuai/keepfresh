/**
 * 物资列表筛选管线（纯函数，Node 可测）。
 * 关键词过滤（移植自 the-ai-menu pantry-screen.ts）+ 分类/状态 Tab 谓词 + 状态机分组。
 */
import type { Material } from '../model/Material';
import { sortByExpirationAsc, splitByAlertLevel, getActualStatus } from './ExpiryService';

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

/** 分组结果：过期 → 临期 → 安全（在库+开封）→ 已处理（终态沉底） */
export interface GroupedMaterials {
  expired: Material[];
  near: Material[];
  safe: Material[];
  handled: Material[];
}

/**
 * 完整筛选链：关键词 → 分类 → 状态 Tab（getActualStatus 口径：active/opened 直配，临期/过期为派生）。
 * 任一维度为空/全部即跳过该谓词。
 */
export function applyListFilters(
  list: Material[],
  keyword: string,
  category: string,
  statusTab: string
): Material[] {
  let filtered: Material[] = filterByKeyword(list, keyword);
  const cat: string = (category ?? '').trim();
  if (cat.length > 0) {
    filtered = filtered.filter((m: Material): boolean => m.category === cat);
  }
  const tab: string = (statusTab ?? 'all').trim();
  if (tab.length > 0 && tab !== 'all') {
    filtered = filtered.filter((m: Material): boolean => getActualStatus(m) === tab);
  }
  return filtered;
}

/**
 * 状态机分组：预警资格唯一判定（splitByAlertLevel）+ 组内按到期日升序（无到期日靠后）。
 */
export function groupByStatus(list: Material[]): GroupedMaterials {
  const s = splitByAlertLevel(list);
  const result: GroupedMaterials = {
    expired: sortByExpirationAsc(s.expired),
    near: sortByExpirationAsc(s.near),
    safe: sortByExpirationAsc(s.other),
    handled: sortByExpirationAsc(s.terminal)
  };
  return result;
}
