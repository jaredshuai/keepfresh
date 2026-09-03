/**
 * 备份导入决策测试（common/BackupPlan.ets，纯函数 Node 直测）。
 * 下沉前这两块决策困在 service/BackupService.ets（@kit 层）零测试（audit-wiring L5）；
 * 本套件锁住冲突裁决与 nameDefs 目标序规则，防回归。
 */
import test, { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import type { CustomField } from '../entry/src/main/ets/model/CustomField.ets';
import { planFieldDefs, planNameDefOrder } from '../entry/src/main/ets/common/BackupPlan.ets';

/** 确定性 idFactory：按调用序产出可断言的 ID */
function seqIdFactory(): () => string {
  let n = 0;
  return (): string => `cf_gen_${++n}`;
}

function def(id: string, name: string, type: string = 'text', order: number = 0): CustomField {
  return { id: id, name: name, type: type as CustomField['type'], order: order, createdAt: '2026-09-03' };
}

describe('planFieldDefs 字段定义冲突裁决', () => {
  it('1. 同名同类型：映射现有 ID，不新建', () => {
    const plan = planFieldDefs([def('L1', '产地')], [def('B1', '产地')], '2026-09-03', seqIdFactory());
    assert.equal(plan.fieldIdMap.get('产地'), 'L1');
    assert.equal(plan.toCreate.length, 0);
  });

  it('2. 不存在：新建，映射到新 ID', () => {
    const plan = planFieldDefs([], [def('B1', '产地')], '2026-09-03', seqIdFactory());
    assert.equal(plan.fieldIdMap.get('产地'), 'cf_gen_1');
    assert.equal(plan.toCreate.length, 1);
    assert.equal(plan.toCreate[0].name, '产地');
    assert.equal(plan.toCreate[0].createdAt, '2026-09-03');
  });

  it('3. 同名不同类型：改名「原名_导入」新建，映射到新 ID', () => {
    const plan = planFieldDefs(
      [def('L1', '产地', 'text')],
      [def('B1', '产地', 'number')],
      '2026-09-03', seqIdFactory());
    assert.equal(plan.fieldIdMap.get('产地'), 'cf_gen_1');
    assert.equal(plan.toCreate.length, 1);
    assert.equal(plan.toCreate[0].name, '产地_导入');
    assert.equal(plan.toCreate[0].type, 'number');
  });

  it('4. 改名后索引更新：备份后续同名不同型字段不与已改名 def 再冲突', () => {
    // 本地无「产地」；备份先 text 后 number——text 新建占名，number 触发改名
    const plan = planFieldDefs(
      [],
      [def('B1', '产地', 'text'), def('B2', '产地', 'number')],
      '2026-09-03', seqIdFactory());
    assert.equal(plan.fieldIdMap.get('产地'), 'cf_gen_2'); // 映射到改名后的新 def
    assert.equal(plan.toCreate.length, 2);
    assert.equal(plan.toCreate[0].name, '产地');
    assert.equal(plan.toCreate[1].name, '产地_导入');
  });

  it('5. order 还原（M5）：新建定义用备份 order，不追加尾部', () => {
    const plan = planFieldDefs(
      [def('L1', '现有', 'text', 5)],
      [def('B1', '产地', 'text', 2)],
      '2026-09-03', seqIdFactory());
    assert.equal(plan.toCreate[0].order, 2);
  });

  it('6. order 缺失/非法回退 maxOrder+1', () => {
    const imported = def('B1', '产地');
    imported.order = -1;
    const plan = planFieldDefs([def('L1', '现有', 'text', 5)], [imported], '2026-09-03', seqIdFactory());
    assert.equal(plan.toCreate[0].order, 6);
  });

  it('7. 空导入：空映射空清单', () => {
    const plan = planFieldDefs([def('L1', '产地')], [], '2026-09-03', seqIdFactory());
    assert.equal(plan.fieldIdMap.size, 0);
    assert.equal(plan.toCreate.length, 0);
  });
});

describe('planNameDefOrder nameDefs 目标序', () => {
  it('1. merge：导入在前，本地独有按现有序追加尾部', () => {
    const target = planNameDefOrder(['冷藏', '冷冻'], ['冷冻', '橱柜', '阳台'], 'merge');
    assert.deepEqual(target, ['冷藏', '冷冻', '橱柜', '阳台']);
  });

  it('2. overwrite：仅保留导入定义', () => {
    const target = planNameDefOrder(['冷藏'], ['冷冻', '橱柜'], 'overwrite');
    assert.deepEqual(target, ['冷藏']);
  });

  it('3. 导入侧去空去重（保备份序）', () => {
    const target = planNameDefOrder([' 冷藏 ', '', '冷藏', '冷冻'], [], 'merge');
    assert.deepEqual(target, ['冷藏', '冷冻']);
  });

  it('4. overwrite 空导入：清空本地（空数组也要 restore 的语义）', () => {
    const target = planNameDefOrder([], ['冷冻', '橱柜'], 'overwrite');
    assert.deepEqual(target, []);
  });
});
