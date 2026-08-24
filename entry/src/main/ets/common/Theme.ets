/**
 * KeepFresh 全局设计令牌 —— 清新自然风格
 * 所有页面统一引用，禁止页面内写死色值。
 */
import { ShadowOptions, BorderOptions } from '@kit.ArkUI';

export namespace Theme {
  /* ───── 主色 ───── */
  export const brand: string = '#34C759';
  export const brandSoft: string = '#E8F8EC';
  export const brandDark: string = '#28A745';
  export const brandGradientStart: string = '#3BD268';
  export const brandGradientEnd: string = '#2AB85A';

  /* ───── 背景 ───── */
  export const pageBg: string = '#F7FAF8';
  export const cardBg: string = '#FFFFFF';
  export const inputBg: string = '#F1F5F2';
  export const sheetBg: string = '#FFFFFF';

  /* ───── 文字 ───── */
  export const textPrimary: string = '#1A231E';
  export const textSecondary: string = '#5A6B62';
  export const textTertiary: string = '#8E9E96';
  export const textWhite: string = '#FFFFFF';

  /* ───── 状态色 ───── */
  export const safe: string = '#34C759';
  export const safeSoft: string = '#E8F8EC';
  export const near: string = '#FF9500';
  export const nearSoft: string = '#FFF4E5';
  export const expired: string = '#FF5A5F';
  export const expiredSoft: string = '#FFEBEE';
  export const danger: string = '#FF3B30';
  export const dangerSoft: string = '#FFEBEE';

  /* ───── 中性色 ───── */
  export const divider: string = '#E8EEEA';
  export const border: string = '#DDE5E0';
  export const shadow: string = 'rgba(26, 35, 30, 0.06)';
  export const shadowStrong: string = 'rgba(26, 35, 30, 0.10)';

  /* ───── 字号（vp） ───── */
  export const textHero: number = 24;
  export const textTitle: number = 20;
  export const textHeadline: number = 18;
  export const textBody: number = 16;
  export const textSubhead: number = 15;
  export const textCaption: number = 13;
  export const textSmall: number = 12;
  export const textTiny: number = 11;

  /* ───── 统计数字 ───── */
  export const statNumber: number = 32;

  /* ───── 间距（vp） ───── */
  export const pagePadding: number = 20;
  export const cardPadding: number = 18;
  export const cardGap: number = 16;
  export const elementGap: number = 12;
  export const smallGap: number = 8;
  export const tinyGap: number = 4;

  /* ───── 圆角（vp） ───── */
  export const cardRadius: number = 20;
  export const buttonRadius: number = 24;
  export const inputRadius: number = 14;
  export const badgeRadius: number = 12;
  export const chipRadius: number = 18;
  export const iconBtnRadius: number = 14;
  export const fabRadius: number = 20;

  /* ───── 尺寸（vp） ───── */
  export const navHeight: number = 56;
  export const fabSize: number = 56;
  export const iconBtnSize: number = 40;
  export const primaryBtnHeight: number = 48;
  export const chipHeight: number = 34;

  /* ───── 阴影参数 ───── */
  export const cardShadow: ShadowOptions = {
    radius: 16,
    color: shadow,
    offsetX: 0,
    offsetY: 4
  };

  export const fabShadow: ShadowOptions = {
    radius: 20,
    color: 'rgba(52,199,89,0.30)',
    offsetX: 0,
    offsetY: 6
  };

  export const buttonShadow: ShadowOptions = {
    radius: 12,
    color: 'rgba(52,199,89,0.25)',
    offsetX: 0,
    offsetY: 4
  };

  /* ───── 统一边框 ───── */
  export const borderThin: BorderOptions = { width: 1, color: border };
  export const borderBrand: BorderOptions = { width: 2, color: brand };

  /* ───── 快速阴影样式（用于链式调用 .shadow()） ───── */
  export const shadowStyle = {
    radius: 16,
    color: shadow,
    offsetX: 0,
    offsetY: 4
  };

  export const fabShadowStyle = {
    radius: 20,
    color: 'rgba(52,199,89,0.30)',
    offsetX: 0,
    offsetY: 6
  };
}
