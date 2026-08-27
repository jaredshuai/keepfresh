/**
 * 分类/位置列表操作（移植自 the-ai-menu category-ordering.ts）。
 * 拖拽重排 + 去重归一化。
 */

/** trim + 过滤空串 + 去重（保持顺序） */
export function normalizeNameList(values: string[]): string[] {
  const seen: Set<string> = new Set<string>();
  const result: string[] = [];
  for (let i = 0; i < values.length; i++) {
    const v: string = (values[i] ?? '').trim();
    if (v.length > 0 && !seen.has(v)) {
      seen.add(v);
      result.push(v);
    }
  }
  return result;
}

/**
 * 拖拽重排：把 fromIndex 项移动到 toIndex。
 * 越界/相同索引返回原数组拷贝。
 */
export function moveNameOrder(names: string[], fromIndex: number, toIndex: number): string[] {
  const copy: string[] = names.slice();
  if (fromIndex < 0 || fromIndex >= copy.length) {
    return copy;
  }
  if (toIndex < 0 || toIndex >= copy.length) {
    return copy;
  }
  if (fromIndex === toIndex) {
    return copy;
  }
  const moved: string = copy.splice(fromIndex, 1)[0];
  copy.splice(toIndex, 0, moved);
  return copy;
}

/** 预设 + 用户已有值合并去重（预设在前） */
export function mergeWithDefaults(defaults: string[], custom: string[]): string[] {
  return normalizeNameList([...defaults, ...custom]);
}
