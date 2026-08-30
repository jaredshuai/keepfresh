/**
 * 物资数据模型与预设常量。
 * quantity 为字符串，支持 "500g" 混合输入（由 QuantityUnit.normalizeQuantityUnit 解析）。
 */
import { encodeCustomFields } from './CustomField';

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

/** 录入页日期口径（仅表单状态，不入库；direct 口径的持久化标记是 productionDate === ''） */
export enum DateEntryMode {
  SHELF = 'shelf',    // 生产日期 + 保质期推算
  DIRECT = 'direct'   // 直接录入到期日（包装只印到期日）
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

/**
 * 物资列表 ForEach 的 key：id 之外编入可变展示字段（status/updatedAt）。
 * ArkUI ForEach 同 key 复用旧组件不重绘——状态翻转不改 id，卡片会凝滞
 * （#crosspage-write-read-race 实测）；所有物资列表（首页分组/回收站/建议单）必须共用。
 */
export function materialCardKey(m: Material): string {
  return `${m.id}_${m.status}_${m.updatedAt}`;
}

/* ============================================================
 * 同批次合并：同名+同位置+同到期日+同单位 的在库记录 = 同一批次，
 * 新增入库自动并入（数量求和）而非另起一条；启动时对存量无损重复做一次并条。
 * ============================================================ */

/**
 * 数量求和（入参为数值字符串）。
 * 任一不可解析为正数（如 "半箱"、空串、"0"）返回 null，调用方放弃合并走新增——宁可两条，不可丢数。
 */
export function batchQuantitySum(a: string, b: string): string | null {
  const na = Number((a ?? '').trim());
  const nb = Number((b ?? '').trim());
  if (Number.isNaN(na) || Number.isNaN(nb) || na <= 0 || nb <= 0) {
    return null;
  }
  // 两位小数封顶，规避 0.1+0.2 浮点尾差
  return `${Math.round((na + nb) * 100) / 100}`;
}

/**
 * 两行是否可「无损」并条：同批次键（名称/位置/到期日/单位）且分类、备注、自定义字段完全一致——
 * 即重复行不携带任何独有信息，只差数量。持久化 status 需均为 active（在库；开封/终态各自独立成条）。
 * 注意比较的是持久化 status 而非派生状态：过期但在库的两条重复同样应并。
 */
export function isLosslessDuplicate(a: Material, b: Material): boolean {
  if (a.id === b.id) {
    return false;
  }
  if (a.status !== MaterialStatus.ACTIVE || b.status !== MaterialStatus.ACTIVE) {
    return false;
  }
  return a.name === b.name
    && a.location === b.location
    && a.expiryDate === b.expiryDate
    && a.unit === b.unit
    && a.category === b.category
    && a.note === b.note
    && encodeCustomFields(a.customFields) === encodeCustomFields(b.customFields);
}
