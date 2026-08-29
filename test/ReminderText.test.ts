/**
 * 汇总提醒文案测试（dogfood P0.5）。
 * 被测对象：ExpiryService.buildReminderText —— 通知文案点名具体物品。
 */
import test, { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import type { Material } from '../entry/src/main/ets/model/Material.ets';
import { buildReminderText } from '../entry/src/main/ets/service/ExpiryService.ets';
import { addDays, addMonths, todayStr } from '../entry/src/main/ets/common/DateUtils.ets';

function mk(id: number, name: string, expiryDate: string): Material {
  const today = todayStr();
  return {
    id: id,
    name: name,
    category: '食品',
    quantity: '1',
    unit: '盒',
    location: '',
    productionDate: today,
    shelfLifeDays: 7,
    expiryDate: expiryDate,
    note: '',
    status: 'active',
    isDeleted: false,
    createdAt: today,
    updatedAt: today
  };
}

describe('buildReminderText 汇总提醒文案 Test Suite', () => {
  it('1. 无过期/临期时返回空串（调用方不发通知）', () => {
    const items = [mk(1, '罐头', addDays(todayStr(), 30)), mk(2, '冻肉', addMonths(todayStr(), 6))];
    assert.equal(buildReminderText(items), '');
  });

  it('2. 单件过期：点名物品与过期天数', () => {
    const items = [mk(1, '面包', addDays(todayStr(), -3))];
    assert.equal(buildReminderText(items), '面包（过期3天）');
  });

  it('3. 过期优先于临期，各自按剩余天数升序', () => {
    const items = [
      mk(1, '临期B', addDays(todayStr(), 5)),
      mk(2, '过期B', addDays(todayStr(), -1)),
      mk(3, '临期A', addDays(todayStr(), 2)),
      mk(4, '过期A', addDays(todayStr(), -5))
    ];
    const text = buildReminderText(items);
    assert.equal(text, '过期A（过期5天）、过期B（过期1天）、临期A（剩2天） 等4件');
  });

  it('4. 超出 limit 时以件数概括（默认 3）', () => {
    const items = [
      mk(1, '过期A', addDays(todayStr(), -1)),
      mk(2, '过期B', addDays(todayStr(), -2)),
      mk(3, '临期A', addDays(todayStr(), 1)),
      mk(4, '临期B', addDays(todayStr(), 2)),
      mk(5, '临期C', addDays(todayStr(), 3))
    ];
    const text = buildReminderText(items);
    assert.equal(text, '过期B（过期2天）、过期A（过期1天）、临期A（剩1天） 等5件');
  });

  it('5. limit 可自定义且终态（用完/丢弃）不计入', () => {
    const done = mk(1, '已丢弃', addDays(todayStr(), -1));
    done.status = 'discarded';
    const items = [done, mk(2, '牛奶', addDays(todayStr(), 6))];
    const text = buildReminderText(items, 1);
    assert.equal(text, '牛奶（剩6天）');
  });

  it('6. 剩余 0 天显示「今天到期」（非「剩0天」）', () => {
    const items = [mk(1, '酸奶', todayStr()), mk(2, '面包', addDays(todayStr(), 2))];
    assert.equal(buildReminderText(items), '酸奶（今天到期）、面包（剩2天）');
  });
});
