/**
 * KeepFresh 全局设计令牌 —— 包豪斯（Bauhaus）风格
 * 暖白纸底 + 纯黑边框 + 硬阴影 + 三原色几何形状
 * 所有页面统一引用，禁止页面内写死色值。
 */
import { ShadowOptions, BorderOptions } from '@kit.ArkUI';

export namespace Theme {
  /* ───── 主色与强调色 ───── */
  export const yellowDark: string = '#d69a00';   // 主按钮底（配白字）
  export const yellow: string = '#ffb703';       // 点缀色（不用于文字底）
  export const paper: string = '#f2f0ea';        // 页面背景（暖白纸）
  export const ink: string = '#1a1a1a';          // 文字/边框/阴影

  /* ───── 背景 ───── */
  export const pageBg: string = '#f2f0ea';       // 页面背景（暖白纸）
  export const cardBg: string = '#ffffff';       // 卡片背景（纯白）
  export const inputBg: string = '#ffffff';      // 输入框背景（纯白）
  export const sheetBg: string = '#ffffff';      // 底部面板背景

  /* ───── 文字 ───── */
  export const textPrimary: string = '#1a1a1a';  // 主文字（纯黑）
  export const textSecondary: string = '#5c5c5c';// 次文字
  export const textTertiary: string = '#a8a498'; // 占位符/禁用态
  export const textWhite: string = '#ffffff';    // 反白文字

  /* ───── 状态色（几何形状语言）
   * 过期：圆形 + 红
   * 临期：三角形 + 橙
   * 安全：正方形 + 蓝绿
   * ───── */
  export const expired: string = '#e63946';      // 过期状态（红色圆形）
  export const expiredSoft: string = '#ffe5e7';  // 过期浅色背景
  export const near: string = '#f4a261';         // 临期状态（橙色三角形）
  export const nearSoft: string = '#fff0e0';     // 临期浅色背景
  export const safe: string = '#2a9d8f';         // 安全状态（蓝绿正方形）
  export const safeSoft: string = '#e0f2f0';     // 安全浅色背景
  export const danger: string = '#e63946';       // 删除/错误（同过期红）
  export const dangerSoft: string = '#ffe5e7';   // 危险浅色

  /* ───── 中性色 ───── */
  export const divider: string = '#1a1a1a';      // 分隔线（纯黑，1vp）
  export const border: string = '#1a1a1a';       // 边框（纯黑，2vp）
  export const shadow: string = '#1a1a1a';       // 硬阴影颜色（纯黑）

  /* ───── 字号（vp） ───── */
  export const textHero: number = 24;            // 页面大标题
  export const textTitle: number = 20;           // 页面标题
  export const textHeadline: number = 18;        // 卡片标题
  export const textBody: number = 16;            // 正文/列表主文字
  export const textSubhead: number = 15;         // 辅助主文字
  export const textCaption: number = 13;         // 列表辅助文字
  export const textSmall: number = 12;           // 标签文字
  export const textTiny: number = 11;            // 极小标签

  /* ───── 统计数字 ───── */
  export const statNumber: number = 32;

  /* ───── 间距（vp）：8 的倍数 ───── */
  export const pagePadding: number = 16;
  export const cardPadding: number = 16;
  export const cardGap: number = 16;
  export const elementGap: number = 12;
  export const smallGap: number = 8;
  export const tinyGap: number = 4;

  /* ───── 圆角（vp）：包豪斯全局零圆角 ───── */
  export const cardRadius: number = 0;
  export const buttonRadius: number = 0;
  export const inputRadius: number = 0;
  export const badgeRadius: number = 0;
  export const chipRadius: number = 0;
  export const iconBtnRadius: number = 0;
  export const fabRadius: number = 0;

  /* ───── 尺寸（vp） ───── */
  export const navHeight: number = 56;
  export const fabSize: number = 56;
  export const iconBtnSize: number = 40;
  export const primaryBtnHeight: number = 48;
  export const chipHeight: number = 34;

  /* ───── 硬阴影：4px 4px 0 #1a1a1a ─────
   * ArkUI 不直接支持偏移硬阴影，用双层 Stack 叠加模拟。
   * 此处保留 shadow 参数作为降级方案。
   */
  export const cardShadow: ShadowOptions = {
    radius: 0,
    color: 'rgba(26,26,26,0.15)',
    offsetX: 4,
    offsetY: 4
  };

  export const fabShadow: ShadowOptions = {
    radius: 0,
    color: 'rgba(26,26,26,0.25)',
    offsetX: 4,
    offsetY: 4
  };

  export const buttonShadow: ShadowOptions = {
    radius: 0,
    color: 'rgba(26,26,26,0.20)',
    offsetX: 4,
    offsetY: 4
  };

  /* ───── 快速阴影样式对象（用于 .shadow() 链式调用） ───── */
  export const shadowStyle = {
    radius: 0,
    color: 'rgba(26,26,26,0.15)',
    offsetX: 4,
    offsetY: 4
  };

  export const fabShadowStyle = {
    radius: 0,
    color: 'rgba(26,26,26,0.25)',
    offsetX: 4,
    offsetY: 4
  };

  /* ───── 统一边框：2vp 纯黑（包豪斯签名元素） ───── */
  export const borderThin: BorderOptions = { width: 2, color: border };
  export const borderBrand: BorderOptions = { width: 2, color: yellowDark };
  export const borderExpired: BorderOptions = { width: 2, color: expired };
  export const borderNear: BorderOptions = { width: 2, color: near };
  export const borderSafe: BorderOptions = { width: 2, color: safe };

  /* ───── 几何状态形状尺寸 ───── */
  export const geoSize: number = 16;              // 状态几何图形尺寸
  export const hardShadowOffset: number = 4;      // 硬阴影偏移量
}
