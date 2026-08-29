/**
 * 物资数据模型与预设常量。
 * quantity 为字符串，支持 "500g" 混合输入（由 QuantityUnit.normalizeQuantityUnit 解析）。
 */

/** 物资生命周期状态（持久化） */
export enum MaterialStatus {
  ACTIVE = 'active',      // 在库
  OPENED = 'opened',      // 已开封
  EMPTY = 'empty',        // 已用完（终态）
  DISCARDED = 'discarded' // 已丢弃（终态）
}

/** 派生状态（运行时计算，不持久化） */
export enum DerivedStatus {
  EXPIRING = 'expiring',  // 临期
  EXPIRED = 'expired'     // 已过期
}

export interface Material {
  id: number;              // 新建时为 -1
  name: string;
  category: string;
  quantity: string;        // 字符串，支持 "500g" 混合输入
  unit: string;
  location: string;        // 存储位置（冷藏/冷冻/橱柜/自定义）
  productionDate: string;  // YYYY-MM-DD
  shelfLifeDays: number;
  shelfLifeMonths?: number; // 保质期月数（与天数并存时月数优先）
  expiryDate: string;      // YYYY-MM-DD
  note: string;
  status: string;          // MaterialStatus 持久化状态
  handledType?: string;    // 处理类型（empty/discarded）
  handledAt?: string;      // 处理时间
  isDeleted: boolean;      // 软删除标记
  createdAt: string;
  updatedAt: string;
  barcode?: string;
  customFields?: Record<string, string>;
}

export enum ExpiryLevel {
  EXPIRED = 0,   // 已过期
  NEAR = 1,      // 临期（剩余天数 <= 阈值）
  SAFE = 2       // 安全
}

/** 临期判定阈值（天） */
export const NEAR_EXPIRY_DAYS: number = 7;

export const DEFAULT_CATEGORIES: string[] = ['肉类', '水果', '蔬菜', '调味品', '谷物', '速食', '饮料'];

export const DEFAULT_LOCATIONS: string[] = ['冷藏', '冷冻', '橱柜'];

export const DEFAULT_UNITS: string[] = ['个', '袋', '盒', '瓶', '包', '份'];

export const SHELF_PRESET_DAYS: number[] = [7, 30, 90, 180, 365];

export const SHELF_PRESET_MONTHS: number[] = [1, 3, 6, 12, 18, 24];
