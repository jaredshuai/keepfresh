/**
 * 物资数据模型与预设常量。
 */

export interface Material {
  id: number;              // 新建时为 -1
  name: string;
  category: string;
  quantity: number;
  unit: string;
  productionDate: string;  // YYYY-MM-DD
  shelfLifeDays: number;
  expiryDate: string;      // YYYY-MM-DD
  note: string;
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

export const DEFAULT_CATEGORIES: string[] = ['食品', '药品', '日用品', '美妆护肤', '其他'];

export const DEFAULT_UNITS: string[] = ['个', '袋', '盒', '瓶', '包', '份'];

export const SHELF_PRESET_DAYS: number[] = [7, 30, 90, 180, 365];
