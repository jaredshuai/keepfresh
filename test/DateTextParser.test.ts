import test, { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { parseDateFromText } from '../entry/src/main/ets/service/DateTextParser.ets';
import type { ParsedDateResult } from '../entry/src/main/ets/service/DateTextParser.ets';
import { todayStr, diffDays } from '../entry/src/main/ets/common/DateUtils.ets';

describe('DateTextParser Test Suite', () => {
  it('1. 单到期日推导 (EXP: 2027/01/01)', () => {
    const res: ParsedDateResult = parseDateFromText('EXP: 2027/01/01');
    assert.equal(res.expiryDate, '2027-01-01');
    const today = todayStr();
    const expectedDays = diffDays('2027-01-01', today);
    assert.equal(res.productionDate, today);
    assert.equal(res.shelfLifeDays, expectedDays);
    assert.deepEqual(res.rawMatchedText, ['EXP: 2027/01/01']);
  });

  it('2. 中文单到期日推导 (保质期至: 2027-12-31)', () => {
    const res: ParsedDateResult = parseDateFromText('保质期至: 2027-12-31');
    assert.equal(res.expiryDate, '2027-12-31');
    const today = todayStr();
    const expectedDays = diffDays('2027-12-31', today);
    assert.equal(res.productionDate, today);
    assert.equal(res.shelfLifeDays, expectedDays);
  });

  it('3. 生产日期 + 保质期天数联动推导到期日 (生产日期: 2026-05-12, 保质期: 180天)', () => {
    const res: ParsedDateResult = parseDateFromText('生产日期: 2026-05-12\n保质期: 180天');
    assert.equal(res.productionDate, '2026-05-12');
    assert.equal(res.shelfLifeDays, 180);
    assert.equal(res.expiryDate, '2026-11-08');
  });

  it('4. 生产日期 + 月份 (生产日期: 2026年06月15日, 保质期: 12个月)', () => {
    const res: ParsedDateResult = parseDateFromText('生产日期: 2026年06月15日\n保质期: 12个月');
    assert.equal(res.productionDate, '2026-06-15');
    assert.equal(res.shelfLifeDays, 360);
    assert.equal(res.expiryDate, '2027-06-10');
  });

  it('5. 生产日期 + 到期日联动反推保质期 (生产日期: 2026-01-01, 保质期至: 2026-07-01)', () => {
    const res: ParsedDateResult = parseDateFromText('生产日期: 2026-01-01\n保质期至: 2026-07-01');
    assert.equal(res.productionDate, '2026-01-01');
    assert.equal(res.expiryDate, '2026-07-01');
    assert.equal(res.shelfLifeDays, 181);
  });

  it('6. 紧凑8位格式识别 (PROD: 20260512, EXP: 20261108)', () => {
    const res: ParsedDateResult = parseDateFromText('PROD: 20260512\nEXP: 20261108');
    assert.equal(res.productionDate, '2026-05-12');
    assert.equal(res.expiryDate, '2026-11-08');
    assert.equal(res.shelfLifeDays, 180);
  });

  it('7. 英文前缀格式识别 (MFG DATE & BEST BEFORE)', () => {
    const res: ParsedDateResult = parseDateFromText('MFG DATE: 2026/03/01\nBEST BEFORE: 2026/09/01');
    assert.equal(res.productionDate, '2026-03-01');
    assert.equal(res.expiryDate, '2026-09-01');
    assert.equal(res.shelfLifeDays, 184);
  });

  it('8. 两个无前缀独立通用日期 (2026.03.01 与 2026.09.01)', () => {
    const res: ParsedDateResult = parseDateFromText('2026.03.01\n2026.09.01');
    assert.equal(res.productionDate, '2026-03-01');
    assert.equal(res.expiryDate, '2026-09-01');
    assert.equal(res.shelfLifeDays, 184);
  });

  it('9. 单个无前缀独立通用日期 (2026-05-20)', () => {
    const res: ParsedDateResult = parseDateFromText('2026-05-20');
    assert.equal(res.productionDate, '2026-05-20');
    assert.equal(res.expiryDate, undefined);
    assert.equal(res.shelfLifeDays, undefined);
  });

  it('10. 全角字符转换识别 (生产日期：２０２６－０８－０１ 保质期：９０天)', () => {
    const res: ParsedDateResult = parseDateFromText('生产日期：２０２６－０８－０１\n保质期：９０天');
    assert.equal(res.productionDate, '2026-08-01');
    assert.equal(res.shelfLifeDays, 90);
    assert.equal(res.expiryDate, '2026-10-30');
  });

  it('11. 数组形式多行文本输入', () => {
    const res: ParsedDateResult = parseDateFromText([
      '品名：纯牛奶',
      '生产日期 2026-04-01',
      '保质期 6个月'
    ]);
    assert.equal(res.productionDate, '2026-04-01');
    assert.equal(res.shelfLifeDays, 180);
    assert.equal(res.expiryDate, '2026-09-28');
  });

  it('12. 空文本及无有效日期内容', () => {
    const res: ParsedDateResult = parseDateFromText('');
    assert.equal(res.productionDate, undefined);
    assert.equal(res.expiryDate, undefined);
    assert.equal(res.shelfLifeDays, undefined);
    assert.equal(res.rawMatchedText.length, 0);
  });

  it('13. 已过期单到期日 (EXP: 2020/01/01 差值 <= 0 不默认设生产日期)', () => {
    const res: ParsedDateResult = parseDateFromText('EXP: 2020/01/01');
    assert.equal(res.expiryDate, '2020-01-01');
    assert.equal(res.productionDate, undefined);
    assert.equal(res.shelfLifeDays, undefined);
  });

  it('14. 各种到期日前缀别名 (BEST BEFORE, 赏味期限, 有效期至)', () => {
    const res1 = parseDateFromText('BEST BEFORE 2027/06/30');
    assert.equal(res1.expiryDate, '2027-06-30');
    assert.equal(res1.productionDate, todayStr());

    const res2 = parseDateFromText('赏味期限: 2027-08-15');
    assert.equal(res2.expiryDate, '2027-08-15');

    const res3 = parseDateFromText('有效期至: 2027/12/01');
    assert.equal(res3.expiryDate, '2027-12-01');
  });

  it('15. 保质期单位换算 (年、天、月)', () => {
    const res1 = parseDateFromText('生产日期: 2026-01-01\n保质期: 2年');
    assert.equal(res1.shelfLifeDays, 730);

    const res2 = parseDateFromText('生产日期: 2026-01-01\nSHELF LIFE: 45 DAYS');
    assert.equal(res2.shelfLifeDays, 45);
    assert.equal(res2.expiryDate, '2026-02-15');
  });
});
