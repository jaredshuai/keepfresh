/**
 * DateTextParser 单元测试套件
 * 覆盖单到期日推导、生产日期+保质期推导、双通用日期、紧凑8位格式、全角字符转换等多种场景。
 */

import { parseDateFromText, ParsedDateResult } from '../service/DateTextParser';
import { todayStr, diffDays } from '../common/DateUtils';

export function runDateTextParserTests(): boolean {
  let allPassed = true;
  const assert = (condition: boolean, msg: string) => {
    if (!condition) {
      console.error(`[FAIL] ${msg}`);
      allPassed = false;
    } else {
      console.log(`[PASS] ${msg}`);
    }
  };

  console.log('--- 开始 DateTextParser 测试 ---');

  // 1. 单到期日推导测试 (EXP: 2027/01/01)
  {
    const res: ParsedDateResult = parseDateFromText('EXP: 2027/01/01');
    assert(res.expiryDate === '2027-01-01', 'EXP: 2027/01/01 提取到期日');
    const today = todayStr();
    const expectedDays = diffDays('2027-01-01', today);
    assert(res.productionDate === today, '单到期日默认生产日期为今天');
    assert(res.shelfLifeDays === expectedDays, `单到期日推导保质期天数 (${res.shelfLifeDays} === ${expectedDays})`);
  }

  // 2. 中文单到期日 (保质期至 2027-12-31)
  {
    const res: ParsedDateResult = parseDateFromText('保质期至: 2027-12-31');
    assert(res.expiryDate === '2027-12-31', '保质期至: 2027-12-31 提取到期日');
    assert(res.productionDate === todayStr(), '中文单到期日生产日期推导');
  }

  // 3. 生产日期 + 保质期天数
  {
    const res: ParsedDateResult = parseDateFromText('生产日期: 2026-05-12\n保质期: 180天');
    assert(res.productionDate === '2026-05-12', '生产日期 2026-05-12');
    assert(res.shelfLifeDays === 180, '保质期 180天');
    assert(res.expiryDate === '2026-11-08', '推导到期日 2026-11-08');
  }

  // 4. 生产日期 + 月份
  {
    const res: ParsedDateResult = parseDateFromText('生产日期: 2026年06月15日\n保质期: 12个月');
    assert(res.productionDate === '2026-06-15', '生产日期 2026-06-15');
    assert(res.shelfLifeDays === 360, '保质期 12个月 -> 360天');
    assert(res.expiryDate === '2027-06-10', '推导到期日 2027-06-10');
  }

  // 5. 生产日期 + 到期日反推保质期
  {
    const res: ParsedDateResult = parseDateFromText('生产日期: 2026-01-01\n保质期至: 2026-07-01');
    assert(res.productionDate === '2026-01-01', '生产日期 2026-01-01');
    assert(res.expiryDate === '2026-07-01', '到期日 2026-07-01');
    assert(res.shelfLifeDays === 181, '反推保质期天数 181天');
  }

  // 6. 紧凑 8 位格式 (PROD: 20260512 EXP: 20261108)
  {
    const res: ParsedDateResult = parseDateFromText('PROD: 20260512\nEXP: 20261108');
    assert(res.productionDate === '2026-05-12', '紧凑生产日期 2026-05-12');
    assert(res.expiryDate === '2026-11-08', '紧凑到期日 2026-11-08');
    assert(res.shelfLifeDays === 180, '紧凑日期计算差值 180天');
  }

  // 7. 英文前缀格式 (MFG DATE & BEST BEFORE)
  {
    const res: ParsedDateResult = parseDateFromText('MFG DATE: 2026/03/01\nBEST BEFORE: 2026/09/01');
    assert(res.productionDate === '2026-03-01', 'MFG DATE 2026-03-01');
    assert(res.expiryDate === '2026-09-01', 'BEST BEFORE 2026-09-01');
    assert(res.shelfLifeDays === 184, '英文前缀差值 184天');
  }

  // 8. 两个无前缀通用日期 (按时间先后排序)
  {
    const res: ParsedDateResult = parseDateFromText('2026.03.01\n2026.09.01');
    assert(res.productionDate === '2026-03-01', '通用第1日期作为生产日期');
    assert(res.expiryDate === '2026-09-01', '通用第2日期作为到期日');
  }

  // 9. 单个无前缀通用日期 (默认为生产日期)
  {
    const res: ParsedDateResult = parseDateFromText('2026-05-20');
    assert(res.productionDate === '2026-05-20', '单个通用日期作为生产日期');
  }

  // 10. 全角字符转换
  {
    const res: ParsedDateResult = parseDateFromText('生产日期：２０２６－０８－０１\n保质期：９０天');
    assert(res.productionDate === '2026-08-01', '全角生产日期转换');
    assert(res.shelfLifeDays === 90, '全角保质期转换');
  }

  // 11. 空文本 / 无效文本处理
  {
    const res: ParsedDateResult = parseDateFromText('');
    assert(res.productionDate === undefined, '空输入 productionDate 为 undefined');
    assert(res.expiryDate === undefined, '空输入 expiryDate 为 undefined');
    assert(res.shelfLifeDays === undefined, '空输入 shelfLifeDays 为 undefined');
  }

  // 12. 已过期单到期日 (差值 <= 0 不默认设生产日期)
  {
    const res: ParsedDateResult = parseDateFromText('EXP: 2020/01/01');
    assert(res.expiryDate === '2020-01-01', 'EXP: 2020/01/01 提取到期日');
    assert(res.productionDate === undefined, '过期单到期日不推导生产日期');
    assert(res.shelfLifeDays === undefined, '过期单到期日不推导保质期天数');
  }

  // 13. 别名前缀 (BEST BEFORE, 赏味期限, 有效期至)
  {
    const res1 = parseDateFromText('BEST BEFORE 2027/06/30');
    assert(res1.expiryDate === '2027-06-30', 'BEST BEFORE 提取到期日');

    const res2 = parseDateFromText('赏味期限: 2027-08-15');
    assert(res2.expiryDate === '2027-08-15', '赏味期限 提取到期日');

    const res3 = parseDateFromText('有效期至: 2027/12/01');
    assert(res3.expiryDate === '2027-12-01', '有效期至 提取到期日');
  }

  // 14. 保质期单位换算 (年、天)
  {
    const res1 = parseDateFromText('生产日期: 2026-01-01\n保质期: 2年');
    assert(res1.shelfLifeDays === 730, '保质期 2年 转换为 730天');

    const res2 = parseDateFromText('生产日期: 2026-01-01\nSHELF LIFE: 45 DAYS');
    assert(res2.shelfLifeDays === 45, 'SHELF LIFE: 45 DAYS 转换为 45天');
  }

  console.log(`--- DateTextParser 测试完成, 结果: ${allPassed ? '全部通过' : '有失败项'} ---`);
  return allPassed;
}
