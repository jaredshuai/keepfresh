/**
 * 录入决策单测（C1 下沉）：历史→表单日期参数、表单→物资构造、同批次并条、保质期展示。
 */
import test, { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import type { Material } from '../entry/src/main/ets/model/Material.ets';
import { MaterialStatus, DateEntryMode } from '../entry/src/main/ets/model/Material.ets';
import {
  dateParamsFromMaterial,
  shelfLifeText,
  buildMaterialFromForm,
  mergeIntoBatch,
  prefillFromMaterial
} from '../entry/src/main/ets/common/MaterialForm.ets';
import type { MaterialFormInput, FormEditContext } from '../entry/src/main/ets/common/MaterialForm.ets';
import { todayStr, addDays, addMonths } from '../entry/src/main/ets/common/DateUtils.ets';

function makeRow(overrides: Partial<Material> & Pick<Material, 'id' | 'name'>): Material {
  const base: Material = {
    id: overrides.id,
    name: overrides.name,
    category: '饮料',
    quantity: '1',
    unit: '瓶',
    location: '客厅',
    productionDate: '2026-08-29',
    shelfLifeDays: 217,
    expiryDate: '2027-04-03',
    note: '',
    status: 'active',
    isDeleted: false,
    createdAt: '2026-08-29',
    updatedAt: '2026-08-29'
  } as Material;
  return { ...base, ...overrides } as Material;
}

function makeForm(overrides: Partial<MaterialFormInput> = {}): MaterialFormInput {
  const base: MaterialFormInput = {
    name: '脉动',
    category: '饮料',
    quantityStr: '1',
    unit: '瓶',
    location: '客厅',
    dateMode: DateEntryMode.SHELF,
    productionDate: '2026-08-30',
    shelfLifeMode: 'days',
    shelfLifeStr: '7',
    shelfLifeMonthsStr: '',
    directExpiryDate: '',
    note: '',
    barcode: '',
    customFields: {}
  };
  return { ...base, ...overrides } as MaterialFormInput;
}

const NEW_EDIT: FormEditContext = {
  isEdit: false,
  editId: -1,
  loadedCreatedAt: '',
  loadedStatus: 'active'
};

describe('dateParamsFromMaterial（三入口唯一映射）', () => {
  it('54. direct 口径：落 DIRECT 模式带出原到期日，保质期字段清空', () => {
    const m = makeRow({ id: 1, name: 'd', productionDate: '', shelfLifeDays: 0, expiryDate: '2027-04-03' });
    const dp = dateParamsFromMaterial(m);
    assert.equal(dp.dateMode, DateEntryMode.DIRECT);
    assert.equal(dp.directExpiryDate, '2027-04-03');
    assert.equal(dp.shelfLifeStr, '');
  });

  it('55. shelf 月数口径：还原 months 模式（不退化为 365×n 天）', () => {
    const m = makeRow({ id: 2, name: 'm', shelfLifeMonths: 10, shelfLifeDays: 3650 });
    const dp = dateParamsFromMaterial(m);
    assert.equal(dp.dateMode, DateEntryMode.SHELF);
    assert.equal(dp.shelfLifeMode, 'months');
    assert.equal(dp.shelfLifeMonthsStr, '10');
    assert.equal(dp.productionDate, '2026-08-29');
  });

  it('56. shelf 天数口径：还原 days 模式', () => {
    const dp = dateParamsFromMaterial(makeRow({ id: 3, name: 'd2' }));
    assert.equal(dp.shelfLifeMode, 'days');
    assert.equal(dp.shelfLifeStr, '217');
  });
});

describe('buildMaterialFromForm（校验+构造）', () => {
  const now = todayStr();

  it('57. 校验：空名/非正数数量/direct 缺到期日/月数不足/天数不足', () => {
    assert.equal(buildMaterialFromForm(makeForm({ name: ' ' }), NEW_EDIT, now).error, '请输入物资名称');
    assert.equal(buildMaterialFromForm(makeForm({ quantityStr: '0' }), NEW_EDIT, now).error, '数量需大于 0');
    assert.equal(buildMaterialFromForm(makeForm({ quantityStr: 'x' }), NEW_EDIT, now).error, '数量需大于 0');
    assert.equal(
      buildMaterialFromForm(makeForm({ dateMode: DateEntryMode.DIRECT, directExpiryDate: '' }), NEW_EDIT, now).error,
      '请选择到期日期');
    assert.equal(
      buildMaterialFromForm(makeForm({ shelfLifeMode: 'months', shelfLifeMonthsStr: '0' }), NEW_EDIT, now).error,
      '保质期需至少 1 个月');
    assert.equal(buildMaterialFromForm(makeForm({ shelfLifeStr: '0' }), NEW_EDIT, now).error, '保质期需至少 1 天');
  });

  it('58. direct 构造：productionDate 空 + shelfLifeDays 0 + 到期日直录（口径标记）', () => {
    const r = buildMaterialFromForm(
      makeForm({ dateMode: DateEntryMode.DIRECT, directExpiryDate: '2027-01-01' }), NEW_EDIT, now);
    assert.equal(r.error, '');
    assert.equal(r.material!.productionDate, '');
    assert.equal(r.material!.shelfLifeDays, 0);
    assert.equal(r.material!.expiryDate, '2027-01-01');
    assert.equal(r.material!.status, MaterialStatus.ACTIVE);
  });

  it('59. shelf 月数构造：到期日按月加法（月末 clamp）', () => {
    const r = buildMaterialFromForm(
      makeForm({ productionDate: '2026-01-31', shelfLifeMode: 'months', shelfLifeMonthsStr: '1' }), NEW_EDIT, now);
    assert.equal(r.error, '');
    assert.equal(r.material!.shelfLifeMonths, 1);
    assert.equal(r.material!.expiryDate, addMonths('2026-01-31', 1));
  });

  it('60. 编辑构造：延续 createdAt/status/handled；新建用 now', () => {
    const edit: FormEditContext = {
      isEdit: true, editId: 9, loadedCreatedAt: '2026-01-01',
      loadedStatus: MaterialStatus.OPENED, loadedHandledType: undefined, loadedHandledAt: undefined
    };
    const r = buildMaterialFromForm(makeForm(), edit, now);
    assert.equal(r.material!.id, 9);
    assert.equal(r.material!.createdAt, '2026-01-01');
    assert.equal(r.material!.status, MaterialStatus.OPENED);
  });
});

describe('mergeIntoBatch（同批次并条）', () => {
  it('61. 数量求和 + 空位补齐（备注/条码/自定义字段不覆盖既有）', () => {
    const twin = makeRow({ id: 1, name: '脉动', quantity: '1', note: '', barcode: undefined });
    const incoming = makeRow({ id: -1, name: '脉动', quantity: '2', note: '赠品', barcode: '690123' });
    const merged = mergeIntoBatch(twin, incoming, '2026-08-30 12:00:00');
    assert.ok(merged);
    assert.equal(merged.quantity, '3');
    assert.equal(merged.note, '赠品');
    assert.equal(merged.barcode, '690123');
    assert.equal(merged.updatedAt, '2026-08-30 12:00:00');
  });

  it('62. 既有信息不被覆盖；数量不可解析返回 null', () => {
    const twin = makeRow({ id: 1, quantity: '1', note: '原备注', barcode: '111' });
    const incoming = makeRow({ id: -1, quantity: '半箱', note: '新备注', barcode: '222' });
    assert.equal(mergeIntoBatch(twin, incoming, 'now'), null);
    const ok = mergeIntoBatch(makeRow({ id: 2, quantity: '1', note: '原备注' }),
      makeRow({ id: -1, quantity: '1', note: '新备注' }), 'now');
    assert.equal(ok!.note, '原备注');
  });
});

describe('shelfLifeText（月数优先展示）', () => {
  it('63. 月数口径显示 N个月，无月数退回 N天', () => {
    assert.equal(shelfLifeText(makeRow({ id: 1, name: 'm', shelfLifeMonths: 10, shelfLifeDays: 3650 })), '保质期10个月');
    assert.equal(shelfLifeText(makeRow({ id: 2, name: 'd' })), '保质期217天');
  });
});

describe('prefillFromMaterial（三入口预填唯一映射）', () => {
  it('64. edit：全量回填（数量归一化/位置兜底/note/customFields/barcode）', () => {
    const m = makeRow({
      id: 1, name: '脉动', quantity: '500g', unit: '瓶', location: '',
      note: '备注', barcode: '690123', customFields: { cf_a: '山东' }
    });
    const p = prefillFromMaterial(m, 'edit');
    assert.equal(p.name, '脉动');
    assert.equal(p.quantityStr, '500');      // 混合输入归一化
    assert.equal(p.unit, 'g');
    assert.equal(p.location, '橱柜');        // 空位置兜底 DEFAULT_LOCATIONS[2]
    assert.equal(p.note, '备注');
    assert.equal(p.barcode, '690123');
    assert.deepEqual(p.customFields, { cf_a: '山东' });
  });

  it('65. suggestion：不带 note/customFields/barcode，位置空则留空（保留当前）', () => {
    const m = makeRow({ id: 1, name: '脉动零糖白桃', location: '', note: '备注', barcode: '690123' });
    const p = prefillFromMaterial(m, 'suggestion');
    assert.equal(p.name, '脉动零糖白桃');
    assert.equal(p.quantityStr, '1');
    assert.equal(p.location, '');            // 空 = 页面保留当前位置
    assert.equal(p.note, undefined);
    assert.equal(p.customFields, undefined);
    assert.equal(p.barcode, undefined);
  });

  it('66. scan：不覆盖数量（quantityStr 为 undefined），单位直取源值', () => {
    const m = makeRow({ id: 1, name: '脉动', quantity: '2', unit: '瓶', location: '客厅' });
    const p = prefillFromMaterial(m, 'scan');
    assert.equal(p.name, '脉动');
    assert.equal(p.quantityStr, undefined);  // 数量留给用户按新批次填
    assert.equal(p.unit, '瓶');
    assert.equal(p.location, '客厅');
    assert.equal(p.note, undefined);
  });

  it('67. 三入口日期口径一致：月数优先还原（H3 防回归）', () => {
    const m = makeRow({ id: 1, name: 'x', shelfLifeMonths: 10, shelfLifeDays: 3650 });
    for (const entry of ['edit', 'suggestion', 'scan'] as const) {
      const p = prefillFromMaterial(m, entry);
      assert.equal(p.dateParams.shelfLifeMode, 'months');
      assert.equal(p.dateParams.shelfLifeMonthsStr, '10');
    }
  });
});
