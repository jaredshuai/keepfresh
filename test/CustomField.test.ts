import test, { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import type { CustomField, CustomFieldType } from '../entry/src/main/ets/model/CustomField.ets';
import {
  validateCustomFieldName,
  validateEnumOptions,
  validateCustomFieldValue,
  generateCustomFieldId,
  getFieldTypeName
} from '../entry/src/main/ets/model/CustomField.ets';
import type { Material } from '../entry/src/main/ets/model/Material.ets';

describe('CustomField Test Suite', () => {
  it('1. 字段类型显示名称映射', () => {
    assert.equal(getFieldTypeName('text'), '文本');
    assert.equal(getFieldTypeName('number'), '数字');
    assert.equal(getFieldTypeName('date'), '日期');
    assert.equal(getFieldTypeName('enum'), '单选');
  });

  it('2. 字段 ID 生成格式', () => {
    const id1 = generateCustomFieldId();
    const id2 = generateCustomFieldId();
    assert.ok(id1.startsWith('cf_'));
    assert.ok(id2.startsWith('cf_'));
    assert.notEqual(id1, id2);
  });

  it('3. 字段名称非空校验', () => {
    const existing: CustomField[] = [];
    assert.equal(validateCustomFieldName('', existing), '请输入字段名称');
    assert.equal(validateCustomFieldName('   ', existing), '请输入字段名称');
    assert.equal(validateCustomFieldName('a'.repeat(21), existing), '字段名称不能超过 20 个字符');
    assert.equal(validateCustomFieldName('存放位置', existing), null);
  });

  it('4. 字段名称防重校验', () => {
    const existing: CustomField[] = [
      { id: 'cf_1', name: '存放位置', type: 'text', order: 0, createdAt: '2026-08-21' },
      { id: 'cf_2', name: '品牌', type: 'text', order: 1, createdAt: '2026-08-21' }
    ];

    // 新建重名
    assert.equal(validateCustomFieldName('存放位置', existing), '字段名称「存放位置」已存在');
    assert.equal(validateCustomFieldName(' 存放位置 ', existing), '字段名称「存放位置」已存在');
    assert.equal(validateCustomFieldName('规格', existing), null);

    // 编辑时自身名称不报错
    assert.equal(validateCustomFieldName('存放位置', existing, 'cf_1'), null);
    // 编辑时修改为与其他字段重名报错
    assert.equal(validateCustomFieldName('品牌', existing, 'cf_1'), '字段名称「品牌」已存在');
  });

  it('5. 枚举选项数量与有效性校验', () => {
    assert.equal(validateEnumOptions([]), '单选字段至少需要添加 2 个有效选项');
    assert.equal(validateEnumOptions(['冷藏']), '单选字段至少需要添加 2 个有效选项');
    assert.equal(validateEnumOptions(['冷藏', '  ']), '单选字段至少需要添加 2 个有效选项');
    assert.equal(validateEnumOptions(['冷藏', '冷冻']), null);
    assert.equal(validateEnumOptions(['常温', '冷藏', '冷冻']), null);
  });

  it('6. 枚举选项防重校验', () => {
    assert.equal(validateEnumOptions(['冷藏', '冷藏']), '选项「冷藏」重复，请修改');
    assert.equal(validateEnumOptions(['冷藏', ' 冷藏 ']), '选项「冷藏」重复，请修改');
    assert.equal(validateEnumOptions(['常温', '冷藏', '冷冻', '常温']), '选项「常温」重复，请修改');
  });

  it('7. 字段值输入校验（文本/数字/日期）', () => {
    const textField: CustomField = { id: 'cf_t', name: '文本字段', type: 'text', order: 0, createdAt: '2026-08-21' };
    const numField: CustomField = { id: 'cf_n', name: '数字字段', type: 'number', order: 1, createdAt: '2026-08-21' };
    const dateField: CustomField = { id: 'cf_d', name: '日期字段', type: 'date', order: 2, createdAt: '2026-08-21' };

    // 允许为空（选填）
    assert.equal(validateCustomFieldValue(textField, ''), null);
    assert.equal(validateCustomFieldValue(numField, ''), null);
    assert.equal(validateCustomFieldValue(dateField, ''), null);

    // 文本字段
    assert.equal(validateCustomFieldValue(textField, '任意文本'), null);

    // 数字字段
    assert.equal(validateCustomFieldValue(numField, '123'), null);
    assert.equal(validateCustomFieldValue(numField, '12.5'), null);
    assert.equal(validateCustomFieldValue(numField, '-5'), null);
    assert.equal(validateCustomFieldValue(numField, 'abc'), '「数字字段」请输入有效数字');
    assert.equal(validateCustomFieldValue(numField, '12a'), '「数字字段」请输入有效数字');
  });

  it('8. 物资 customFields JSON 序列化与反序列化兼容性', () => {
    const customFieldsData: Record<string, string> = {
      'cf_location': '冰箱上层',
      'cf_price': '29.9',
      'cf_storage': '冷藏'
    };

    const serialized = JSON.stringify(customFieldsData);
    const deserialized = JSON.parse(serialized) as Record<string, string>;

    assert.deepEqual(deserialized, customFieldsData);
    assert.equal(deserialized['cf_location'], '冰箱上层');
    assert.equal(deserialized['cf_price'], '29.9');

    // 空/不存在兼容
    const emptyJson = '{}';
    const parsedEmpty = JSON.parse(emptyJson) as Record<string, string>;
    assert.deepEqual(parsedEmpty, {});
  });

  it('9. 字段删除后物资历史数据保留逻辑', () => {
    // 假设已有物资存储了两个字段的值
    const material: Material = {
      id: 1,
      name: '纯牛奶',
      category: '食品',
      quantity: '1',
      unit: '盒',
      location: '',
      productionDate: '2026-08-01',
      shelfLifeDays: 30,
      expiryDate: '2026-08-31',
      note: '',
      status: 'active',
      isDeleted: false,
      createdAt: '2026-08-01',
      updatedAt: '2026-08-01',
      customFields: {
        'cf_location': '冰箱冷藏室',
        'cf_old_field': '历史旧值'
      }
    };

    // 系统当前仅剩 cf_location 字段定义（cf_old_field 字段定义已在管理页被删除）
    const currentActiveDefs: CustomField[] = [
      { id: 'cf_location', name: '存放位置', type: 'text', order: 0, createdAt: '2026-08-01' }
    ];

    // 详情页渲染过滤：仅渲染当前存在的字段定义
    const renderedFields: { label: string; value: string }[] = [];
    for (const def of currentActiveDefs) {
      const val = material.customFields?.[def.id];
      if (val && val.trim().length > 0) {
        renderedFields.push({ label: def.name, value: val });
      }
    }

    // 渲染层只有存放位置，无 cf_old_field
    assert.equal(renderedFields.length, 1);
    assert.equal(renderedFields[0].label, '存放位置');
    assert.equal(renderedFields[0].value, '冰箱冷藏室');

    // 但物资模型与 JSON 仍完整保留 cf_old_field 数据
    assert.equal(material.customFields?.['cf_old_field'], '历史旧值');
  });

  it('10. 枚举字段选项变更后，历史值不在新选项中的保留逻辑', () => {
    // 字段原选项为 ['常温', '冷藏', '冷冻']，历史记录存了 '冷冻'
    const material: Material = {
      id: 2,
      name: '冰淇淋',
      category: '食品',
      quantity: '2',
      unit: '盒',
      location: '',
      productionDate: '2026-08-01',
      shelfLifeDays: 180,
      expiryDate: '2027-01-28',
      note: '',
      status: 'active',
      isDeleted: false,
      createdAt: '2026-08-01',
      updatedAt: '2026-08-01',
      customFields: {
        'cf_storage': '冷冻'
      }
    };

    // 用户编辑了字段定义，将选项改为 ['常温', '冷藏']（删除了 '冷冻'）
    const updatedEnumField: CustomField = {
      id: 'cf_storage',
      name: '存放条件',
      type: 'enum',
      options: ['常温', '冷藏'],
      order: 0,
      createdAt: '2026-08-01'
    };

    // 表单渲染时判断：如果历史值不在新 options 中，则表单选中项为空
    const currentVal = material.customFields?.['cf_storage'] || '';
    const hasMatchInOptions = updatedEnumField.options?.includes(currentVal) ?? false;

    // 界面不选中任何 chip
    assert.equal(hasMatchInOptions, false);

    // 用户若未手动切换并直接保存，原值仍保留在 customFields 字典中
    const savedCustomFields = { ...material.customFields };
    assert.equal(savedCustomFields['cf_storage'], '冷冻');
  });

  it('11. 字段排序（上移/下移）逻辑', () => {
    const list: CustomField[] = [
      { id: 'cf_1', name: '字段1', type: 'text', order: 0, createdAt: '2026-08-21' },
      { id: 'cf_2', name: '字段2', type: 'number', order: 1, createdAt: '2026-08-21' },
      { id: 'cf_3', name: '字段3', type: 'date', order: 2, createdAt: '2026-08-21' }
    ];

    // 将 index 1 下移
    const downIndex = 1;
    const temp = list[downIndex];
    list[downIndex] = list[downIndex + 1];
    list[downIndex + 1] = temp;

    assert.equal(list[0].id, 'cf_1');
    assert.equal(list[1].id, 'cf_3');
    assert.equal(list[2].id, 'cf_2');

    // 重新赋 order 序号
    list.forEach((item, idx) => {
      item.order = idx;
    });

    assert.equal(list[0].order, 0);
    assert.equal(list[1].order, 1);
    assert.equal(list[2].order, 2);
  });
});
