/**
 * KeepFresh 全局设计令牌 —— 包豪斯（Bauhaus）风格
 * 暖白纸底 + 纯黑边框 + 硬阴影 + 三原色几何形状
 * 所有页面统一引用，禁止页面内写死色值。
 */

// 类型定义
interface ShadowOptions {
  radius: number;
  color: string;
  offsetX: number;
  offsetY: number;
}

interface BorderOptions {
  width: number;
  color: string;
}

// 阴影配置
const cardShadow: ShadowOptions = {
  radius: 0,
  color: 'rgba(26,26,26,0.15)',
  offsetX: 4,
  offsetY: 4
};

const fabShadow: ShadowOptions = {
  radius: 0,
  color: 'rgba(26,26,26,0.25)',
  offsetX: 4,
  offsetY: 4
};

const buttonShadow: ShadowOptions = {
  radius: 0,
  color: 'rgba(26,26,26,0.20)',
  offsetX: 4,
  offsetY: 4
};

const shadowStyle: ShadowOptions = {
  radius: 0,
  color: 'rgba(26,26,26,0.15)',
  offsetX: 4,
  offsetY: 4
};

const fabShadowStyle: ShadowOptions = {
  radius: 0,
  color: 'rgba(26,26,26,0.25)',
  offsetX: 4,
  offsetY: 4
};

export class Theme {
  /* ───── 主色与强调色 ───── */
  static readonly yellowDark: string = '#d69a00';   // 主按钮底（配白字）
  static readonly yellow: string = '#ffb703';       // 点缀色（不用于文字底）
  static readonly paper: string = '#f2f0ea';        // 页面背景（暖白纸）
  static readonly ink: string = '#1a1a1a';          // 文字/边框/阴影

  /* ───── 背景 ───── */
  static readonly pageBg: string = '#f2f0ea';       // 页面背景（暖白纸）
  static readonly cardBg: string = '#ffffff';       // 卡片背景（纯白）
  static readonly inputBg: string = '#ffffff';      // 输入框背景（纯白）
  static readonly sheetBg: string = '#ffffff';      // 底部面板背景

  /* ───── 文字 ───── */
  static readonly textPrimary: string = '#1a1a1a';  // 主文字（纯黑）
  static readonly textSecondary: string = '#5c5c5c';// 次文字
  static readonly textTertiary: string = '#a8a498'; // 占位符/禁用态
  static readonly textWhite: string = '#ffffff';    // 反白文字
  static readonly textWhiteDim: string = 'rgba(255,255,255,0.85)'; // 反白次级文字

  /* ───── 状态色（几何形状语言） ───── */
  static readonly expired: string = '#e63946';      // 过期状态（红色圆形）
  static readonly expiredSoft: string = '#ffe5e7';  // 过期浅色背景
  static readonly near: string = '#f4a261';         // 临期状态（橙色三角形）
  static readonly nearSoft: string = '#fff0e0';     // 临期浅色背景
  static readonly safe: string = '#2a9d8f';         // 安全状态（蓝绿正方形）
  static readonly safeSoft: string = '#e0f2f0';     // 安全浅色背景
  static readonly danger: string = '#e63946';       // 删除/错误（同过期红）
  static readonly dangerSoft: string = '#ffe5e7';   // 危险浅色

  /* ───── 中性色 ───── */
  static readonly divider: string = '#1a1a1a';      // 分隔线（纯黑，1vp）
  static readonly border: string = '#1a1a1a';       // 边框（纯黑，2vp）
  static readonly shadow: string = '#1a1a1a';       // 硬阴影颜色（纯黑）

  /* ───── 字号（vp） ───── */
  static readonly textHero: number = 24;            // 页面大标题
  static readonly textTitle: number = 20;           // 页面标题
  static readonly textHeadline: number = 18;        // 卡片标题
  static readonly textBody: number = 16;            // 正文/列表主文字
  static readonly textSubhead: number = 15;         // 辅助主文字
  static readonly textCaption: number = 13;         // 列表辅助文字
  static readonly textSmall: number = 12;           // 标签文字
  static readonly textTiny: number = 11;            // 极小标签

  /* ───── 统计数字 ───── */
  static readonly statNumber: number = 32;

  /* ───── 间距（vp）：8 的倍数 ───── */
  static readonly pagePadding: number = 16;
  static readonly cardPadding: number = 16;
  static readonly cardGap: number = 16;
  static readonly elementGap: number = 12;
  static readonly smallGap: number = 8;
  static readonly tinyGap: number = 4;

  /* ───── 圆角（vp）：包豪斯全局零圆角 ───── */
  static readonly cardRadius: number = 0;
  static readonly buttonRadius: number = 0;
  static readonly inputRadius: number = 0;
  static readonly badgeRadius: number = 0;
  static readonly chipRadius: number = 0;
  static readonly iconBtnRadius: number = 0;
  static readonly fabRadius: number = 0;

  /* ───── 尺寸（vp） ───── */
  static readonly navHeight: number = 56;
  static readonly fabSize: number = 56;
  static readonly iconBtnSize: number = 40;
  static readonly primaryBtnHeight: number = 48;
  static readonly chipHeight: number = 34;

  /* ───── 阴影 ───── */
  static readonly cardShadow: ShadowOptions = cardShadow;
  static readonly fabShadow: ShadowOptions = fabShadow;
  static readonly buttonShadow: ShadowOptions = buttonShadow;
  static readonly shadowStyle: ShadowOptions = shadowStyle;
  static readonly fabShadowStyle: ShadowOptions = fabShadowStyle;

  /* ───── 边框：引用上方已声明的 Theme 令牌，改令牌即同步生效 ───── */
  static readonly borderThin: BorderOptions = { width: 2, color: Theme.ink };
  static readonly borderBrand: BorderOptions = { width: 2, color: Theme.yellowDark };
  static readonly borderExpired: BorderOptions = { width: 2, color: Theme.expired };
  static readonly borderNear: BorderOptions = { width: 2, color: Theme.near };
  static readonly borderSafe: BorderOptions = { width: 2, color: Theme.safe };

  /* ───── 几何状态形状尺寸 ───── */
  static readonly geoSize: number = 16;              // 状态几何图形尺寸
  static readonly hardShadowOffset: number = 4;      // 硬阴影偏移量

  /* ───── 分类图标浅底 ───── */
  static readonly categoryFoodBg: string = '#fff0e0';    // 食品 → 临期橙浅底
  static readonly categoryMedicineBg: string = '#e0f2f0';// 药品 → 安全蓝绿浅底
  static readonly categoryDailyBg: string = '#fff8e0';   // 日用品 → 黄系浅底
  static readonly categoryBeautyBg: string = '#ffe5e7';  // 美妆护肤 → 过期红浅底
}
