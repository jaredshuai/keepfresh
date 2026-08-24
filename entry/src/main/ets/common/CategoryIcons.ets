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
        bgColor: '#fff0e5'
      };
    case '药品':
      return {
        symbol: $r('sys.symbol.cross_case'),
        bgColor: '#e0f2f0'
      };
    case '日用品':
      return {
        symbol: $r('sys.symbol.house'),
        bgColor: '#fff8e0'
      };
    case '美妆护肤':
      return {
        symbol: $r('sys.symbol.sparkles'),
        bgColor: '#ffe5e7'
      };
    case '其他':
    default:
      return {
        symbol: $r('sys.symbol.cube_box'),
        bgColor: Theme.inputBg
      };
  }
}
