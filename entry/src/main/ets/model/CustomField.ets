/**
 * 自定义字段数据模型与校验函数。
 */

export type CustomFieldType = 'text' | 'number' | 'date' | 'enum';

export interface CustomField {
  id: string;              // 唯一标识，如 cf_1718888888888_abc
  name: string;            // 字段显示名称
  type: CustomFieldType;   // 字段类型：text | number | date | enum
  options?: string[];      // 仅 enum 类型使用：选项列表（至少 2 项）
  order: number;           // 排序号（升序）
  createdAt: string;       // 创建时间
}

export const CUSTOM_FIELD_TYPES: CustomFieldType[] = ['text', 'number', 'date', 'enum'];

export function getFieldTypeName(type: CustomFieldType): string {
  switch (type) {
    case 'text':
      return '文本';
    case 'number':
      return '数字';
    case 'date':
      return '日期';
    case 'enum':
      return '单选';
    default:
      return '文本';
  }
}

/**
 * 校验字段名称
 * @param name 输入的字段名
 * @param existingFields 现有字段列表
 * @param editingId 当前编辑的字段 ID（若为新建则为 undefined）
 * @returns 错误信息，若校验通过则返回 null
 */
export function validateCustomFieldName(
  name: string,
  existingFields: CustomField[],
  editingId?: string
): string | null {
  const trimmed = name.trim();
  if (trimmed.length === 0) {
    return '请输入字段名称';
  }
  if (trimmed.length > 20) {
    return '字段名称不能超过 20 个字符';
  }
  const isDuplicate = existingFields.some((f: CustomField): boolean => {
    if (editingId && f.id === editingId) {
      return false;
    }
    return f.name.trim() === trimmed;
  });
  if (isDuplicate) {
    return `字段名称「${trimmed}」已存在`;
  }
  return null;
}

/**
 * 校验枚举选项列表
 * @param options 选项数组
 * @returns 错误信息，若校验通过则返回 null
 */
export function validateEnumOptions(options: string[]): string | null {
  const cleaned = options.map((opt: string) => opt.trim()).filter((opt: string) => opt.length > 0);
  if (cleaned.length < 2) {
    return '单选字段至少需要添加 2 个有效选项';
  }
  const uniqueSet = new Set<string>();
  for (const opt of cleaned) {
    if (uniqueSet.has(opt)) {
      return `选项「${opt}」重复，请修改`;
    }
    uniqueSet.add(opt);
  }
  return null;
}

/**
 * 校验自定义字段的值输入
 * @param field 字段定义
 * @param value 输入值字符串
 * @returns 错误信息，若校验通过则返回 null
 */
export function validateCustomFieldValue(field: CustomField, value: string): string | null {
  const trimmed = value.trim();
  if (trimmed.length === 0) {
    return null; // 选填字段允许为空
  }
  if (field.type === 'number') {
    const num = Number(trimmed);
    if (Number.isNaN(num)) {
      return `「${field.name}」请输入有效数字`;
    }
  }
  return null;
}

/**
 * 生成唯一的自定义字段 ID
 */
export function generateCustomFieldId(): string {
  const ts = Date.now().toString(36);
  const rand = Math.random().toString(36).substring(2, 6);
  return `cf_${ts}_${rand}`;
}
