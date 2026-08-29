/**
 * pantry-logic 移植纯函数单测（issue #9 测试债 + 新移植逻辑）。
 * 覆盖：addMonths 月末 clamp、状态机、风险排序、数量单位解析、关键词搜索、输入归一化、分类排序。
 */
import test, { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import type { Material } from '../entry/src/main/ets/model/Material.ets';
import { batchQuantitySum, isLosslessDuplicate } from '../entry/src/main/ets/model/Material.ets';
import { addDays, todayStr, addMonths } from '../entry/src/main/ets/common/DateUtils.ets';
import { normalizeQuantityUnit, formatQuantityUnit } from '../entry/src/main/ets/common/QuantityUnit.ets';
import { normalizeText, normalizeNullableText, normalizeNonNegativeInteger, parseNonNegativeInteger } from '../entry/src/main/ets/common/InputNormalize.ets';
import { filterByKeyword } from '../entry/src/main/ets/common/SearchFilter.ets';
import {
  getActualStatus,
  riskOrderOf,
  sortByRiskAndExpiration,
  sortByCreatedDesc,
  sortByExpirationAsc,
  buildOverview,
  calcExpiryDate,
  setNearExpiryThreshold
} from '../entry/src/main/ets/service/ExpiryService.ets';

const MaterialStatus = { ACTIVE: 'active', OPENED: 'opened', EMPTY: 'empty', DISCARDED: 'discarded' } as const;
const DerivedStatus = { EXPIRING: 'expiring', EXPIRED: 'expired' } as const;

function makeMaterial(overrides: Record<string, unknown> & Pick<Record<string, unknown>, 'id' | 'name' | 'expiryDate'>): Material {
  const today = todayStr();
  const base: Record<string, unknown> = {
    id: 0,
    name: '',
    category: '食品',
    quantity: '1',
    unit: '盒',
    location: '',
    productionDate: today,
    shelfLifeDays: 30,
    expiryDate: today,
    note: '',
    status: MaterialStatus.ACTIVE,
    isDeleted: false,
    createdAt: today,
    updatedAt: today
  };
  return { ...base, ...overrides } as Material;
}

describe('DateUtils.addMonths 月末 clamp', () => {
  it('1. 闰年 1/31 + 1 月 = 2/29', () => {
    assert.equal(addMonths('2024-01-31', 1), '2024-02-29');
  });

  it('2. 平年 1/31 + 1 月 = 2/28', () => {
    assert.equal(addMonths('2023-01-31', 1), '2023-02-28');
  });

  it('3. 8/31 + 1 月 = 9/30', () => {
    assert.equal(addMonths('2024-08-31', 1), '2024-09-30');
  });

  it('4. 跨年：11/30 + 3 月 = 2/28（次年）', () => {
    assert.equal(addMonths('2024-11-30', 3), '2025-02-28');
  });

  it('5. 跨多年：2024-06-15 + 18 月 = 2025-12-15', () => {
    assert.equal(addMonths('2024-06-15', 18), '2025-12-15');
  });

  it('6. 月中日期不 clamp：2024-06-15 + 1 月 = 2024-07-15', () => {
    assert.equal(addMonths('2024-06-15', 1), '2024-07-15');
  });

  it('7. 12 月 + 1 月跨年：2024-12-10 + 1 月 = 2025-01-10', () => {
    assert.equal(addMonths('2024-12-10', 1), '2025-01-10');
  });

  it('8. 与 addDays 等价性（月中日期，2024-06-15 起闰日已过为 365 天）', () => {
    assert.equal(addMonths('2024-06-15', 12), addDays('2024-06-15', 365));
  });
});

describe('calcExpiryDate 月数优先', () => {
  it('9. 有月数时按月加法', () => {
    assert.equal(calcExpiryDate('2024-01-31', 30, 1), '2024-02-29');
  });

  it('10. 无月数时按天加法', () => {
    assert.equal(calcExpiryDate('2024-01-31', 30), '2024-03-01');
  });

  it('11. 月数为 0 或 undefined 时回退天数', () => {
    assert.equal(calcExpiryDate('2024-01-01', 30, 0), '2024-01-31');
    assert.equal(calcExpiryDate('2024-01-01', 30, undefined), '2024-01-31');
  });
});

describe('状态机 getActualStatus', () => {
  const today = todayStr();

  it('12. 终态 empty 不被过期覆盖', () => {
    const m = makeMaterial({ id: 1, name: '已用完', expiryDate: addDays(today, -10), status: MaterialStatus.EMPTY });
    assert.equal(getActualStatus(m), MaterialStatus.EMPTY);
  });

  it('13. 终态 discarded 不被过期覆盖', () => {
    const m = makeMaterial({ id: 2, name: '已丢弃', expiryDate: addDays(today, -10), status: MaterialStatus.DISCARDED });
    assert.equal(getActualStatus(m), MaterialStatus.DISCARDED);
  });

  it('14. 在库且过期 → 派生 expired', () => {
    const m = makeMaterial({ id: 3, name: '过期', expiryDate: addDays(today, -1), status: MaterialStatus.ACTIVE });
    assert.equal(getActualStatus(m), DerivedStatus.EXPIRED);
  });

  it('15. 在库且临期 → 派生 expiring', () => {
    const m = makeMaterial({ id: 4, name: '临期', expiryDate: addDays(today, 3), status: MaterialStatus.ACTIVE });
    assert.equal(getActualStatus(m), DerivedStatus.EXPIRING);
  });

  it('16. 已开封且安全 → 保持 opened', () => {
    const m = makeMaterial({ id: 5, name: '开封', expiryDate: addDays(today, 100), status: MaterialStatus.OPENED });
    assert.equal(getActualStatus(m), MaterialStatus.OPENED);
  });

  it('17. 今天到期算临期（0 天 → EXPIRING；与 levelOf/统计头/CONTEXT.md 临期定义对齐）', () => {
    const m = makeMaterial({ id: 6, name: '今天', expiryDate: today, status: MaterialStatus.ACTIVE });
    assert.equal(getActualStatus(m), DerivedStatus.EXPIRING);
  });
});

describe('风险排序 sortByRiskAndExpiration', () => {
  it('18. 过期在前，临期次之，安全随后，终态沉底', () => {
    const today = todayStr();
    const list: Material[] = [
      makeMaterial({ id: 1, name: '安全-远', expiryDate: addDays(today, 100), createdAt: '2026-08-01' }),
      makeMaterial({ id: 2, name: '已用完', expiryDate: addDays(today, -5), status: MaterialStatus.EMPTY }),
      makeMaterial({ id: 3, name: '过期-3天', expiryDate: addDays(today, -3) }),
      makeMaterial({ id: 4, name: '临期-2天', expiryDate: addDays(today, 2) }),
      makeMaterial({ id: 5, name: '过期-10天', expiryDate: addDays(today, -10) })
    ];
    const sorted = sortByRiskAndExpiration(list);
    assert.equal(sorted[0].name, '过期-10天');
    assert.equal(sorted[1].name, '过期-3天');
    assert.equal(sorted[2].name, '临期-2天');
    assert.equal(sorted[3].name, '安全-远');
    assert.equal(sorted[4].name, '已用完');
  });

  it('19. 同风险组内按到期日升序', () => {
    const today = todayStr();
    const list: Material[] = [
      makeMaterial({ id: 1, name: 'C', expiryDate: addDays(today, 5) }),
      makeMaterial({ id: 2, name: 'A', expiryDate: addDays(today, 1) }),
      makeMaterial({ id: 3, name: 'B', expiryDate: addDays(today, 3) })
    ];
    const sorted = sortByRiskAndExpiration(list);
    assert.equal(sorted.map((m: Material): string => m.name).join(','), 'A,B,C');
  });

  it('20. 不改变原数组（返回新数组）', () => {
    const today = todayStr();
    const list: Material[] = [
      makeMaterial({ id: 1, name: 'A', expiryDate: addDays(today, 5) }),
      makeMaterial({ id: 2, name: 'B', expiryDate: addDays(today, 1) })
    ];
    sortByRiskAndExpiration(list);
    assert.equal(list[0].name, 'A');
    assert.equal(list[1].name, 'B');
  });

  it('21. 风险序：expired=0 < expiring=1 < 其他=2 < 终态=3', () => {
    const today = todayStr();
    assert.equal(riskOrderOf(makeMaterial({ id: 1, name: 'x', expiryDate: addDays(today, -1) })), 0);
    assert.equal(riskOrderOf(makeMaterial({ id: 2, name: 'x', expiryDate: addDays(today, 2) })), 1);
    assert.equal(riskOrderOf(makeMaterial({ id: 3, name: 'x', expiryDate: addDays(today, 100) })), 2);
    assert.equal(riskOrderOf(makeMaterial({ id: 4, name: 'x', expiryDate: addDays(today, 100), status: MaterialStatus.EMPTY })), 3);
    assert.equal(riskOrderOf(makeMaterial({ id: 5, name: 'x', expiryDate: addDays(today, 100), status: MaterialStatus.DISCARDED })), 3);
  });
});

describe('数量单位解析 normalizeQuantityUnit', () => {
  it('22. 混合输入 "500g" → {500, g}', () => {
    assert.deepEqual(normalizeQuantityUnit('500g', ''), { quantity: '500', unit: 'g' });
  });

  it('23. 混合输入 "2盒" → {2, 盒}', () => {
    assert.deepEqual(normalizeQuantityUnit('2盒', ''), { quantity: '2', unit: '盒' });
  });

  it('24. quantity 以已知单位结尾 → 剥离', () => {
    assert.deepEqual(normalizeQuantityUnit('500克', '克'), { quantity: '500', unit: '克' });
  });

  it('25. 纯数字 + 独立单位 → 原样', () => {
    assert.deepEqual(normalizeQuantityUnit('500', 'g'), { quantity: '500', unit: 'g' });
  });

  it('26. 空 quantity → 空串保单位', () => {
    assert.deepEqual(normalizeQuantityUnit('', 'g'), { quantity: '', unit: 'g' });
  });

  it('27. formatQuantityUnit 拼回', () => {
    assert.equal(formatQuantityUnit('500', 'g'), '500 g');
    assert.equal(formatQuantityUnit('500', ''), '500');
    assert.equal(formatQuantityUnit('', 'g'), 'g');
  });
});

describe('输入归一化 InputNormalize', () => {
  it('28. normalizeText trim 与空值', () => {
    assert.equal(normalizeText('  abc  '), 'abc');
    assert.equal(normalizeText(undefined), '');
    assert.equal(normalizeText(null), '');
  });

  it('29. normalizeNullableText 空返回 null', () => {
    assert.equal(normalizeNullableText('  x  '), 'x');
    assert.equal(normalizeNullableText('   '), null);
    assert.equal(normalizeNullableText(undefined), null);
  });

  it('30. normalizeNonNegativeInteger 非法返回 null', () => {
    assert.equal(normalizeNonNegativeInteger(5), 5);
    assert.equal(normalizeNonNegativeInteger(0), 0);
    assert.equal(normalizeNonNegativeInteger(-1), null);
    assert.equal(normalizeNonNegativeInteger(1.5), null);
    assert.equal(normalizeNonNegativeInteger(Number.NaN), null);
    assert.equal(normalizeNonNegativeInteger(undefined), null);
  });

  it('31. parseNonNegativeInteger 字符串解析', () => {
    assert.equal(parseNonNegativeInteger('12'), 12);
    assert.equal(parseNonNegativeInteger(' 3 '), 3);
    assert.equal(parseNonNegativeInteger('abc'), null);
    assert.equal(parseNonNegativeInteger('-2'), null);
    assert.equal(parseNonNegativeInteger('1.5'), null);
    assert.equal(parseNonNegativeInteger(''), null);
  });
});

describe('关键词搜索 filterByKeyword', () => {
  it('32. 跨 name/category/location/note 匹配', () => {
    const list: Material[] = [
      makeMaterial({ id: 1, name: '纯牛奶', category: '食品', location: '冷藏', note: '' }),
      makeMaterial({ id: 2, name: '感冒药', category: '药品', location: '', note: '放抽屉' }),
      makeMaterial({ id: 3, name: '洗面奶', category: '美妆护肤', location: '卫生间', note: '未开封' })
    ];
    assert.equal(filterByKeyword(list, '牛奶').length, 1);
    assert.equal(filterByKeyword(list, '药').length, 1);
    assert.equal(filterByKeyword(list, '冷藏').length, 1);
    assert.equal(filterByKeyword(list, '抽屉').length, 1);
    assert.equal(filterByKeyword(list, '').length, 3);
    assert.equal(filterByKeyword(list, '不存在').length, 0);
  });

  it('33. 大小写不敏感', () => {
    const list: Material[] = [
      makeMaterial({ id: 1, name: 'Coke', category: '食品', note: '' })
    ];
    assert.equal(filterByKeyword(list, 'coke').length, 1);
  });
});

describe('多维度统计 buildOverview', () => {
  it('38. 各状态计数 + 分类/位置聚合 + 软删除排除', () => {
    const today = todayStr();
    const list: Material[] = [
      makeMaterial({ id: 1, name: '过期面包', category: '食品', location: '橱柜', expiryDate: addDays(today, -2) }),
      makeMaterial({ id: 2, name: '临期牛奶', category: '食品', location: '冷藏', expiryDate: addDays(today, 3) }),
      makeMaterial({ id: 3, name: '开封酱油', category: '食品', location: '橱柜', expiryDate: addDays(today, 100), status: MaterialStatus.OPENED }),
      makeMaterial({ id: 4, name: '用完饼干', category: '食品', location: '橱柜', expiryDate: addDays(today, 100), status: MaterialStatus.EMPTY }),
      makeMaterial({ id: 5, name: '丢弃药品', category: '药品', location: '橱柜', expiryDate: addDays(today, 100), status: MaterialStatus.DISCARDED }),
      makeMaterial({ id: 6, name: '软删除项', category: '药品', location: '橱柜', expiryDate: addDays(today, 100), isDeleted: true })
    ];
    const overview = buildOverview(list);
    assert.equal(overview.total, 5);
    assert.equal(overview.expired, 1);
    assert.equal(overview.expiring, 1);
    assert.equal(overview.opened, 1);
    assert.equal(overview.empty, 1);
    assert.equal(overview.discarded, 1);
    assert.equal(overview.byCategory['食品'], 4);
    assert.equal(overview.byCategory['药品'], 1); // 软删除项被排除
    assert.equal(overview.byLocation['橱柜'], 4);
    assert.equal(overview.byLocation['冷藏'], 1);
  });
});

describe('基础排序 sortByCreatedDesc / sortByExpirationAsc', () => {
  it('39. 创建时间倒序', () => {
    const list: Material[] = [
      makeMaterial({ id: 1, name: '旧', createdAt: '2026-01-01' }),
      makeMaterial({ id: 2, name: '新', createdAt: '2026-08-01' })
    ];
    assert.equal(sortByCreatedDesc(list)[0].name, '新');
  });

  it('40. 到期日升序', () => {
    const today = todayStr();
    const list: Material[] = [
      makeMaterial({ id: 1, name: '晚', expiryDate: addDays(today, 30) }),
      makeMaterial({ id: 2, name: '早', expiryDate: addDays(today, 1) })
    ];
    assert.equal(sortByExpirationAsc(list)[0].name, '早');
  });
});


describe('同批次并条（同名+同位置+同到期日+同单位 = 同一批次）', () => {
  it('41. 数量求和：整数、小数、浮点尾差封顶', () => {
    assert.equal(batchQuantitySum('1', '1'), '2');
    assert.equal(batchQuantitySum('1.5', '1'), '2.5');
    assert.equal(batchQuantitySum('0.1', '0.2'), '0.3');
  });

  it('42. 任一数量不可解析为正数 → null（放弃合并走新增，宁两条不丢数）', () => {
    assert.equal(batchQuantitySum('abc', '1'), null);
    assert.equal(batchQuantitySum('1', ''), null);
    assert.equal(batchQuantitySum('0', '3'), null);
    assert.equal(batchQuantitySum('-1', '3'), null);
  });

  it('43. 无损重复：同键 + 分类/备注/自定义字段一致 + 双在库 → 可并（数量不参与判定）', () => {
    const a = makeMaterial({
      id: 1, name: '脉动', expiryDate: '2027-04-04', quantity: '1', unit: '瓶',
      location: '客厅', category: '饮料', note: '', status: MaterialStatus.ACTIVE
    });
    const b = makeMaterial({
      id: 2, name: '脉动', expiryDate: '2027-04-04', quantity: '2', unit: '瓶',
      location: '客厅', category: '饮料', note: '', status: MaterialStatus.ACTIVE
    });
    assert.equal(isLosslessDuplicate(a, b), true);
  });

  it('44. 有独有信息或非在库态 → 不可并（备注/分类/到期日不同、开封、终态、同 id）', () => {
    const base = { name: '脉动', expiryDate: '2027-04-04', quantity: '1', unit: '瓶', location: '客厅', category: '饮料' };
    const a = makeMaterial({ ...base, id: 1, status: MaterialStatus.ACTIVE });
    assert.equal(isLosslessDuplicate(a, makeMaterial({ ...base, id: 2, note: '赠品' })), false);
    assert.equal(isLosslessDuplicate(a, makeMaterial({ ...base, id: 2, category: '速食' })), false);
    assert.equal(isLosslessDuplicate(a, makeMaterial({ ...base, id: 2, expiryDate: '2027-05-04' })), false);
    assert.equal(isLosslessDuplicate(a, makeMaterial({ ...base, id: 2, status: MaterialStatus.OPENED })), false);
    assert.equal(isLosslessDuplicate(a, makeMaterial({ ...base, id: 2, status: MaterialStatus.DISCARDED })), false);
    assert.equal(isLosslessDuplicate(a, makeMaterial({ ...base, id: 1 })), false);
  });
});

// 恢复默认阈值，避免影响其他测试文件（node --test 同进程串行）
setNearExpiryThreshold(7);
