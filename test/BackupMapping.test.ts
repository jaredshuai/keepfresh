/**
 * custom_fields 键语义契约测试（ticket #14 / #18 任务 2）。
 * 被测对象：model/CustomField.ets 的契约函数（无 kit 依赖，Node 可测）。
 * 场景清单来自 #14 实施指令：跨设备恢复 / 幂等重导 / 删 def 重导 / 脏库重导 /
 * 改名分支 / def id 重复 / v1 兼容 / 同设备往返 / 导出快照不变量。
 */
import test, { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import type { CustomField } from '../entry/src/main/ets/model/CustomField.ets';
import {
  buildBackupDefNameIndex,
  remapCustomFieldKeys,
  decodeCustomFieldsJson,
  encodeCustomFields,
  readCustomFieldValue
} from '../entry/src/main/ets/model/CustomField.ets';

/** 本地定义 ID → def（构造 nameToLocalId 用），模拟 resolveCustomFieldDefs 的输出 */
function nameMap(pairs: Array<[string, string]>): Map<string, string> {
  const m = new Map<string, string>();
  for (const [name, id] of pairs) {
    m.set(name, id);
  }
  return m;
}

function def(id: string, name: string, order: number = 0): CustomField {
  return { id: id, name: name, type: 'text', order: order, createdAt: '2026-08-27' };
}

describe('CustomFields 键语义契约 Test Suite', () => {
  it('1. 跨设备恢复主场景：空库 + 备份 defs/materials → 值键正确挂上新 def', () => {
    const backupDefs = [def('D_orig', '产地'), def('D_orig2', '批次号', 1)];
    const index = buildBackupDefNameIndex(backupDefs);
    // 空库：resolveCustomFieldDefs 为每个备份 def 新建本地 def（ID 任意生成）
    const localMap = nameMap([['产地', 'D_gen_a'], ['批次号', 'D_gen_b']]);

    const remap = remapCustomFieldKeys({ 'D_orig': '山东', 'D_orig2': '20260827' }, index, localMap);

    assert.deepEqual(remap.values, { 'D_gen_a': '山东', 'D_gen_b': '20260827' });
    assert.equal(remap.unmappedKeys.length, 0);
  });

  it('2. 幂等重导：同一备份连续导入两次，值键稳定不漂移', () => {
    const backupDefs = [def('D_orig', '产地')];
    const index = buildBackupDefNameIndex(backupDefs);
    // 首次导入后本地 def 为 D_gen1；第二次导入 nameToLocalId 仍指向 D_gen1
    const localMap = nameMap([['产地', 'D_gen1']]);

    const first = remapCustomFieldKeys({ 'D_orig': '山东' }, index, localMap);
    const second = remapCustomFieldKeys({ 'D_orig': '山东' }, index, localMap);

    assert.deepEqual(first.values, second.values);
    assert.deepEqual(first.values, { 'D_gen1': '山东' });
  });

  it('3. 删 def 后重导：定义以新 ID 重建，先前孤儿值经二次映射挂回', () => {
    const backupDefs = [def('D_orig', '产地')];
    const index = buildBackupDefNameIndex(backupDefs);
    // 用户删过 def，重导时以新 ID D_gen2 重建
    const localMap = nameMap([['产地', 'D_gen2']]);

    const remap = remapCustomFieldKeys({ 'D_orig': '山东' }, index, localMap);

    assert.deepEqual(remap.values, { 'D_gen2': '山东' });
  });

  it('4. 脏库重导（核心价值场景）：坏 def 在地存在时重导原备份，值键桥接到现有 def', () => {
    const backupDefs = [def('D_orig', '产地')];
    const index = buildBackupDefNameIndex(backupDefs);
    // 旧 bug 遗留：本地同名 def 是坏 ID D_bad；二次映射使重导救回，而非继续孤儿
    const localMap = nameMap([['产地', 'D_bad']]);

    const remap = remapCustomFieldKeys({ 'D_orig': '山东' }, index, localMap);

    assert.deepEqual(remap.values, { 'D_bad': '山东' });
    assert.equal(remap.unmappedKeys.length, 0);
  });

  it('5. 同名不同类型改名分支：值键自然落入改名后的新 def', () => {
    const backupDefs = [def('D_orig', '产地')];
    const index = buildBackupDefNameIndex(backupDefs);
    // resolveCustomFieldDefs 改名分支的输出：新 def 名「产地_导入」、ID D_renamed
    const localMap = nameMap([['产地', 'D_renamed']]);

    const remap = remapCustomFieldKeys({ 'D_orig': '山东' }, index, localMap);

    assert.deepEqual(remap.values, { 'D_renamed': '山东' });
  });

  it('6. 备份 def id 重复：判不可桥接，值键保留原样并计入 unmapped', () => {
    const backupDefs = [def('X', '字段A'), def('X', '字段B', 1)];
    const index = buildBackupDefNameIndex(backupDefs);

    assert.equal(index.idToName.has('X'), false);
    assert.equal(index.unbridgeableIds.has('X'), true);

    const remap = remapCustomFieldKeys({ 'X': '值' }, index, nameMap([['字段A', 'L1']]));
    assert.deepEqual(remap.values, { 'X': '值' });
    assert.deepEqual(remap.unmappedKeys, ['X']);
  });

  it('7. v1 备份兼容（备份无 defs 段）：值键保留原样并计入 unmapped', () => {
    const index = buildBackupDefNameIndex([]);
    const remap = remapCustomFieldKeys({ 'D_orig': '山东' }, index, new Map<string, string>());

    assert.deepEqual(remap.values, { 'D_orig': '山东' });
    assert.deepEqual(remap.unmappedKeys, ['D_orig']);
  });

  it('8. 同设备往返：备份 def id 即本地 def id，映射为恒等', () => {
    const backupDefs = [def('D1', '产地'), def('D2', '批次号', 1)];
    const index = buildBackupDefNameIndex(backupDefs);
    const localMap = nameMap([['产地', 'D1'], ['批次号', 'D2']]);

    const remap = remapCustomFieldKeys({ 'D1': '山东', 'D2': 'B01' }, index, localMap);

    assert.deepEqual(remap.values, { 'D1': '山东', 'D2': 'B01' });
    assert.equal(remap.unmappedKeys.length, 0);
  });

  it('9. 导出快照不变量：导出侧值键 ⊆ defs.id 集合（#14 防回归网）', () => {
    const defs = [def('cf_a', '产地'), def('cf_b', '批次号', 1)];
    const defIds = new Set<string>(defs.map((d: CustomField): string => d.id));
    // 模拟导出数据：值键来自 defs.id，经 encode 存储再 decode 读回，键集合不变
    const exportedValues: Record<string, string> = { 'cf_a': '山东', 'cf_b': 'B01' };
    const roundTrip = decodeCustomFieldsJson(encodeCustomFields(exportedValues))!;

    for (const key of Object.keys(roundTrip)) {
      assert.equal(defIds.has(key), true, `导出值键 ${key} 不在 defs.id 集合中`);
    }
  });

  it('10. 存储编解码契约：空串/坏JSON/undefined 的边界行为与历史一致', () => {
    assert.equal(decodeCustomFieldsJson(''), undefined);
    assert.deepEqual(decodeCustomFieldsJson('not-json'), {});
    assert.deepEqual(decodeCustomFieldsJson('{"cf_a":"v"}'), { 'cf_a': 'v' });
    assert.equal(encodeCustomFields(undefined), '{}');
    assert.equal(encodeCustomFields({ 'cf_a': 'v' }), '{"cf_a":"v"}');
    assert.equal(readCustomFieldValue(undefined, 'k'), '');
    assert.equal(readCustomFieldValue({ 'k': 'v' }, 'missing'), '');
    assert.equal(readCustomFieldValue({ 'k': 'v' }, 'k'), 'v');
  });
});
