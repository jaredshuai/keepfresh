/**
 * 物资分类图标与颜色映射。
 * 返回 HarmonyOS 系统 Symbol 资源，未命中时返回默认叶子图标。
 */

import { Theme } from './Theme';

export interface CategoryIcon {
  symbol: Resource;
  bgColor: string;
}

export function getCategoryIcon(category: string): CategoryIcon {
  switch (category) {
    case '食品':
      return {
        symbol: $r('sys.symbol.carrot'),
        bgColor: '#E8F8EC'
      };
    case '药品':
      return {
        symbol: $r('sys.symbol.cross_case'),
        bgColor: '#FFF4E5'
      };
    case '日用品':
      return {
        symbol: $r('sys.symbol.house'),
        bgColor: '#E8F4FD'
      };
    case '美妆护肤':
      return {
        symbol: $r('sys.symbol.sparkles'),
        bgColor: '#F3E8FF'
      };
    case '其他':
    default:
      return {
        symbol: $r('sys.symbol.cube_box'),
        bgColor: Theme.inputBg
      };
  }
}
