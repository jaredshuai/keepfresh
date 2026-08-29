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
    case '肉类':
      return {
        symbol: $r('sys.symbol.fork_knife'),
        bgColor: Theme.categoryMeatBg
      };
    case '水果':
      return {
        symbol: $r('sys.symbol.sun'),
        bgColor: Theme.categoryFruitBg
      };
    case '蔬菜':
      return {
        symbol: $r('sys.symbol.leaf'),
        bgColor: Theme.categoryVegBg
      };
    case '调味品':
      return {
        symbol: $r('sys.symbol.drop'),
        bgColor: Theme.categoryCondimentBg
      };
    case '谷物':
      return {
        symbol: $r('sys.symbol.bag'),
        bgColor: Theme.categoryGrainBg
      };
    case '速食':
      return {
        symbol: $r('sys.symbol.flame'),
        bgColor: Theme.categoryInstantBg
      };
    case '饮料':
      return {
        symbol: $r('sys.symbol.cup'),
        bgColor: Theme.categoryDrinkBg
      };
    default:
      return {
        symbol: $r('sys.symbol.square'),
        bgColor: Theme.inputBg
      };
  }
}
