/**
 * 扫码建议挑选单测：在库优先 / 全删兜底 / 键去重。
 * 背景：回收站行保留「快速再录入」模板价值，但不得以旧名幽灵形式外漏
 * （2026-08-30 真机实测：改名后扫码仍弹两条已删旧名候选）。
 */
import test, { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import type { Material } from '../entry/src/main/ets/model/Material.ets';
import { selectScanSuggestions } from '../entry/src/main/ets/common/ScanSuggest.ets';

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

describe('扫码建议挑选（在库优先，已删兜底）', () => {
  it('45. 场景A：在库行存在 → 已删行（旧名幽灵）全部让位', () => {
    const history: Material[] = [
      makeRow({ id: 3, name: '脉动零糖白桃口味' }),                    // 在库（改名后）
      makeRow({ id: 2, name: '脉动零糖白桃', isDeleted: true }),       // 回收站旧名
      makeRow({ id: 1, name: '脉动零糖白桃', isDeleted: true })
    ];
    const out = selectScanSuggestions(history);
    assert.equal(out.length, 1);
    assert.equal(out[0].name, '脉动零糖白桃口味');
    assert.equal(out[0].isDeleted, false);
  });

  it('46. 场景B：条码全部已删 → 最近已删行兜底为历史模板', () => {
    const history: Material[] = [
      makeRow({ id: 5, name: '脉动零糖白桃', isDeleted: true }),
      makeRow({ id: 4, name: '脉动零糖白桃', isDeleted: true })
    ];
    const out = selectScanSuggestions(history);
    assert.equal(out.length, 1);
    assert.equal(out[0].id, 5);
    assert.equal(out[0].isDeleted, true);
  });

  it('47. 去重键 name|location|expiryDate：同键保留最近一条，direct 口径稳定', () => {
    const history: Material[] = [
      makeRow({ id: 8, name: '脉动', productionDate: '', shelfLifeDays: 0 }),   // direct 最新
      makeRow({ id: 7, name: '脉动', productionDate: '', shelfLifeDays: 0 })
    ];
    const out = selectScanSuggestions(history);
    assert.equal(out.length, 1);
    assert.equal(out[0].id, 8);
  });

  it('48. 在库与已删同键并存：只出在库那条（不重复弹）', () => {
    const history: Material[] = [
      makeRow({ id: 10, name: '脉动', isDeleted: true }),
      makeRow({ id: 9, name: '脉动' })
    ];
    const out = selectScanSuggestions(history);
    assert.equal(out.length, 1);
    assert.equal(out[0].id, 9);
  });

  it('49. 空历史 → 空建议', () => {
    assert.deepEqual(selectScanSuggestions([]), []);
  });
});
