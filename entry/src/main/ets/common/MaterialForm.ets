/**
 * 录入决策（纯函数，Node 可测）：历史记录 → 表单日期参数、表单 → 物资构造、
 * 同批次并条合并、保质期展示。C1 下沉——编辑回填/同名联想/扫码建议三个入口
 * 与 save() 的并条策略此前各写一份且已漂移，此模块是唯一实现。
 */
import type { Material } from '../model/Material';
import { MaterialStatus, DateEntryMode, batchQuantitySum } from '../model/Material';
import { normalizeQuantityUnit } from './QuantityUnit';
import { parseNonNegativeInteger } from './InputNormalize';
import { calcExpiryDate } from './ExpiryService';

/** 历史记录 → 表单日期参数（口径跟随源记录；月数优先还原月数模式，避免 365×n 近似回填） */
export interface DateParams {
  dateMode: DateEntryMode;
  productionDate: string;
  shelfLifeMode: string;        // 'days' | 'months'
  shelfLifeStr: string;
  shelfLifeMonthsStr: string;
  directExpiryDate: string;
}

export function dateParamsFromMaterial(m: Material): DateParams {
  if (m.productionDate.length === 0) {
    // direct 口径源记录：不带保质期字段，直接落到「直接填到期日」模式并带出原到期日
    return {
      dateMode: DateEntryMode.DIRECT,
      productionDate: '',
      shelfLifeMode: 'days',
      shelfLifeStr: '',
      shelfLifeMonthsStr: '',
      directExpiryDate: m.expiryDate
    };
  }
  const months = m.shelfLifeMonths !== undefined && m.shelfLifeMonths !== null && m.shelfLifeMonths > 0;
  return {
    dateMode: DateEntryMode.SHELF,
    // 生产日期预填历史值（同批次命中即免改；不预填今天——生产日期几乎不可能是录入当天）
    productionDate: m.productionDate,
    shelfLifeMode: months ? 'months' : 'days',
    shelfLifeStr: months ? '' : m.shelfLifeDays.toString(),
    shelfLifeMonthsStr: months ? m.shelfLifeMonths!.toString() : '',
    directExpiryDate: ''
  };
}

/** 保质期展示（月数优先保留录入口径；无月数的旧数据才退回天数） */
export function shelfLifeText(m: Material): string {
  if (m.shelfLifeMonths !== undefined && m.shelfLifeMonths !== null && m.shelfLifeMonths > 0) {
    return `保质期${m.shelfLifeMonths}个月`;
  }
  return `保质期${m.shelfLifeDays}天`;
}

/** 保存用的表单快照（页面 @State 的镜像；自定义字段校验依赖定义列表，留在页面层） */
export interface MaterialFormInput {
  name: string;
  category: string;
  quantityStr: string;
  unit: string;
  location: string;
  dateMode: DateEntryMode;
  productionDate: string;
  shelfLifeMode: string;        // 'days' | 'months'
  shelfLifeStr: string;
  shelfLifeMonthsStr: string;
  directExpiryDate: string;
  note: string;
  barcode: string;
  customFields: Record<string, string>;
}

/** 编辑态需延续的持久化字段（新建时忽略） */
export interface FormEditContext {
  isEdit: boolean;
  editId: number;
  loadedCreatedAt: string;
  loadedStatus: string;
  loadedHandledType?: string;
  loadedHandledAt?: string;
}

/** 构造结果：error 非空即校验失败（文案直接上 UI），material 仅在 error 为空时有效 */
export interface FormBuildResult {
  error: string;
  material?: Material;
}

/** 表单 → 物资：校验（名称/数量/日期口径）+ 构造（含到期日推算，月数优先按月加法） */
export function buildMaterialFromForm(form: MaterialFormInput, edit: FormEditContext, now: string): FormBuildResult {
  const normalizedQty = normalizeQuantityUnit(form.quantityStr, form.unit);
  const qtyNumber = Number(normalizedQty.quantity);
  const direct = form.dateMode === DateEntryMode.DIRECT;
  const months = !direct && form.shelfLifeMode === 'months' ? parseNonNegativeInteger(form.shelfLifeMonthsStr) : null;
  const days = !direct && form.shelfLifeMode === 'months' ? 365 * (months ?? 1) : Number(form.shelfLifeStr);

  if (form.name.trim().length === 0) {
    return { error: '请输入物资名称' };
  }
  if (normalizedQty.quantity === '' || Number.isNaN(qtyNumber) || qtyNumber <= 0) {
    return { error: '数量需大于 0' };
  }
  if (direct) {
    if (form.directExpiryDate.length === 0) {
      return { error: '请选择到期日期' };
    }
  } else if (form.shelfLifeMode === 'months') {
    if (months === null || months < 1) {
      return { error: '保质期需至少 1 个月' };
    }
  } else {
    if (form.shelfLifeStr === '' || Number.isNaN(days) || days < 1) {
      return { error: '保质期需至少 1 天' };
    }
  }

  const material: Material = {
    id: edit.editId,
    name: form.name.trim(),
    category: form.category,
    quantity: normalizedQty.quantity,
    unit: normalizedQty.unit.length > 0 ? normalizedQty.unit : form.unit,
    location: form.location,
    productionDate: direct ? '' : form.productionDate,
    shelfLifeDays: direct ? 0 : Math.floor(days),
    shelfLifeMonths: direct ? undefined : (months ?? undefined),
    expiryDate: direct
      ? form.directExpiryDate
      : (months !== null && months >= 1
        ? calcExpiryDate(form.productionDate, 0, months)
        : calcExpiryDate(form.productionDate, Math.floor(days))),
    note: form.note.trim(),
    status: edit.isEdit ? edit.loadedStatus : MaterialStatus.ACTIVE,
    handledType: edit.isEdit ? edit.loadedHandledType : undefined,
    handledAt: edit.isEdit ? edit.loadedHandledAt : undefined,
    isDeleted: false,
    createdAt: edit.isEdit ? edit.loadedCreatedAt : now,
    updatedAt: now,
    barcode: form.barcode.trim().length > 0 ? form.barcode.trim() : undefined,
    customFields: form.customFields
  };
  return { error: '', material: material };
}

/**
 * 同批次并条（ADR-0003）：新记录并入既有在库行——数量求和 + 空位补齐
 * （备注/条码/自定义字段仅在原记录为空时带上，不覆盖既有信息）。
 * 数量不可解析为正数时返回 null（放弃合并走新增，宁两条不丢数）。原地更新 twin 并返回。
 */
export function mergeIntoBatch(twin: Material, incoming: Material, now: string): Material | null {
  const sum = batchQuantitySum(twin.quantity, incoming.quantity);
  if (sum === null) {
    return null;
  }
  twin.quantity = sum;
  twin.updatedAt = now;
  if (twin.note.length === 0 && incoming.note.length > 0) {
    twin.note = incoming.note;
  }
  if ((!twin.barcode || twin.barcode.length === 0) && incoming.barcode) {
    twin.barcode = incoming.barcode;
  }
  if ((!twin.customFields || Object.keys(twin.customFields).length === 0)
    && incoming.customFields && Object.keys(incoming.customFields).length > 0) {
    twin.customFields = incoming.customFields;
  }
  return twin;
}
