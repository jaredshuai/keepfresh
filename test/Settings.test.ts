import test, { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import type { Material } from '../entry/src/main/ets/model/Material.ets';
import {
  levelOf,
  statsOf,
  setNearExpiryThreshold,
  getNearExpiryThreshold,
  DEFAULT_NEAR_EXPIRY_DAYS
} from '../entry/src/main/ets/service/ExpiryService.ets';
import { addDays, todayStr } from '../entry/src/main/ets/common/DateUtils.ets';

const ExpiryLevel = {
  EXPIRED: 0,
  NEAR: 1,
  SAFE: 2
};

function validateNearExpiryDays(input: string | number): string | null {
  const num = typeof input === 'number' ? input : Number(input);
  if (input === '' || Number.isNaN(num)) {
    return '请输入有效的临期天数';
  }
  if (!Number.isInteger(num)) {
    return '临期天数必须为整数';
  }
  if (num < 1 || num > 365) {
    return '临期天数需在 1 到 365 天之间';
  }
  return null;
}

describe('Settings & ExpiryThreshold Test Suite', () => {
  it('1. 默认临期天数阈值为 7', () => {
    setNearExpiryThreshold(DEFAULT_NEAR_EXPIRY_DAYS);
    assert.equal(getNearExpiryThreshold(), 7);
  });

  it('2. 临期天数输入校验逻辑 (1~365 整数)', () => {
    assert.equal(validateNearExpiryDays(''), '请输入有效的临期天数');
    assert.equal(validateNearExpiryDays('abc'), '请输入有效的临期天数');
    assert.equal(validateNearExpiryDays('0'), '临期天数需在 1 到 365 天之间');
    assert.equal(validateNearExpiryDays('-5'), '临期天数需在 1 到 365 天之间');
    assert.equal(validateNearExpiryDays('366'), '临期天数需在 1 到 365 天之间');
    assert.equal(validateNearExpiryDays('7.5'), '临期天数必须为整数');
    assert.equal(validateNearExpiryDays('1'), null);
    assert.equal(validateNearExpiryDays('7'), null);
    assert.equal(validateNearExpiryDays('30'), null);
    assert.equal(validateNearExpiryDays('365'), null);
  });

  it('3. 动态阈值对单个物资分级（levelOf）的影响', () => {
    const today = todayStr();
    // 剩余 5 天到期
    const m5Days: Material = {
      id: 1,
      name: '酸奶',
      category: '食品',
      quantity: 1,
      unit: '盒',
      productionDate: today,
      shelfLifeDays: 5,
      expiryDate: addDays(today, 5),
      note: '',
      createdAt: today,
      updatedAt: today
    };

    // 当阈值 = 7 天时，剩余 5 天属于 NEAR (临期)
    setNearExpiryThreshold(7);
    assert.equal(levelOf(m5Days), ExpiryLevel.NEAR);

    // 当阈值调整为 3 天时，剩余 5 天变为 SAFE (安全)
    setNearExpiryThreshold(3);
    assert.equal(levelOf(m5Days), ExpiryLevel.SAFE);

    // 当阈值调整为 14 天时，剩余 5 天再次为 NEAR (临期)
    setNearExpiryThreshold(14);
    assert.equal(levelOf(m5Days), ExpiryLevel.NEAR);

    // 恢复默认阈值 7
    setNearExpiryThreshold(7);
  });

  it('4. 动态阈值对列表统计（statsOf）的影响', () => {
    const today = todayStr();
    const list: Material[] = [
      // 已过期 2 天 (left = -2)
      {
        id: 1,
        name: '过期面包',
        category: '食品',
        quantity: 1,
        unit: '袋',
        productionDate: addDays(today, -10),
        shelfLifeDays: 8,
        expiryDate: addDays(today, -2),
        note: '',
        createdAt: today,
        updatedAt: today
      },
      // 剩 2 天 (left = 2)
      {
        id: 2,
        name: '鲜牛奶',
        category: '食品',
        quantity: 1,
        unit: '盒',
        productionDate: today,
        shelfLifeDays: 2,
        expiryDate: addDays(today, 2),
        note: '',
        createdAt: today,
        updatedAt: today
      },
      // 剩 5 天 (left = 5)
      {
        id: 3,
        name: '火腿肠',
        category: '食品',
        quantity: 1,
        unit: '包',
        productionDate: today,
        shelfLifeDays: 5,
        expiryDate: addDays(today, 5),
        note: '',
        createdAt: today,
        updatedAt: today
      },
      // 剩 10 天 (left = 10)
      {
        id: 4,
        name: '罐头',
        category: '食品',
        quantity: 1,
        unit: '罐',
        productionDate: today,
        shelfLifeDays: 10,
        expiryDate: addDays(today, 10),
        note: '',
        createdAt: today,
        updatedAt: today
      }
    ];

    // 口径 1：阈值 = 7
    // expired: 1, near: 2 (2天, 5天), safe: 1 (10天)
    setNearExpiryThreshold(7);
    const stats7 = statsOf(list);
    assert.equal(stats7.total, 4);
    assert.equal(stats7.expired, 1);
    assert.equal(stats7.near, 2);
    assert.equal(stats7.safe, 1);

    // 口径 2：修改阈值 7 -> 3
    // expired: 1, near: 1 (2天), safe: 2 (5天, 10天)
    setNearExpiryThreshold(3);
    const stats3 = statsOf(list);
    assert.equal(stats3.total, 4);
    assert.equal(stats3.expired, 1);
    assert.equal(stats3.near, 1);
    assert.equal(stats3.safe, 2);

    // 口径 3：修改阈值 -> 14
    // expired: 1, near: 3 (2天, 5天, 10天), safe: 0
    setNearExpiryThreshold(14);
    const stats14 = statsOf(list);
    assert.equal(stats14.total, 4);
    assert.equal(stats14.expired, 1);
    assert.equal(stats14.near, 3);
    assert.equal(stats14.safe, 0);

    // 恢复默认
    setNearExpiryThreshold(7);
  });
});
