/**
 * 分类图标映射（包豪斯配色版）
 * bgColor 统一引用 Theme.category*Bg，避免在映射表中写死 hex
 */
import { Theme } from './Theme';

interface CategoryIconInfo {
  symbol: Resource;
  bgColor: string;
}

export function getCategoryIcon(category: string): CategoryIconInfo {
  switch (category) {
    case '食品':
      return {
        symbol: $r('sys.symbol.cart'),
        bgColor: Theme.categoryFoodBg
      };
    case '药品':
      return {
        symbol: $r('sys.symbol.cross_case'),
        bgColor: Theme.categoryMedicineBg
      };
    case '日用品':
      return {
        symbol: $r('sys.symbol.house'),
        bgColor: Theme.categoryDailyBg
      };
    case '美妆护肤':
      return {
        symbol: $r('sys.symbol.star'),
        bgColor: Theme.categoryBeautyBg
      };
    default:
      return {
        symbol: $r('sys.symbol.square'),
        bgColor: Theme.inputBg
      };
  }
}
