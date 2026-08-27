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

/* ============================================================
 * custom_fields 键语义契约（ticket #14 / #18）
 *
 * 物资 custom_fields JSON 的键 = CustomField.id（非字段名）。
 * 所有键语义操作必须经由本契约，禁止在 pages/ 与 service/
 * 裸下标访问或同行 JSON 编解码（wire-guard 规则 6 执法）。
 * 裸 JSON.parse/stringify 仅允许存储层（db/）做整列编解码。
 * ============================================================ */

/** 备份定义桥接索引：idToName 由备份 defs 构建；id 重复的定义不可桥接 */
export interface BackupDefNameIndex {
  idToName: Map<string, string>;
  unbridgeableIds: Set<string>;
}

/** 值键重映射结果：unmappedKeys 为双跳落空而保留原键的键列表 */
export interface CustomFieldsRemapResult {
  values: Record<string, string>;
  unmappedKeys: string[];
}

/** 存储列解码：空串 → undefined；坏 JSON → {}（与历史行为一致） */
export function decodeCustomFieldsJson(raw: string): Record<string, string> | undefined {
  if (!raw || raw.length === 0) {
    return undefined;
  }
  try {
    return JSON.parse(raw) as Record<string, string>;
  } catch (e) {
    return {};
  }
}

/** 存储列编码：undefined → '{}'（与历史行为一致） */
export function encodeCustomFields(values: Record<string, string> | undefined): string {
  return values ? JSON.stringify(values) : '{}';
}

/** 读取单值：values 未定义或键不存在均返回 '' */
export function readCustomFieldValue(values: Record<string, string> | undefined, key: string): string {
  if (!values) {
    return '';
  }
  const val = values[key];
  return val ? val : '';
}

/**
 * 由备份 defs 构建桥接索引。
 * id 重复的定义记入 unbridgeableIds（不可覆盖先写，防错误桥接）；
 * id 缺失的定义跳过（物资值不可能以其引用）。
 */
export function buildBackupDefNameIndex(defs: CustomField[]): BackupDefNameIndex {
  const idToName = new Map<string, string>();
  const unbridgeableIds = new Set<string>();
  for (let i = 0; i < defs.length; i++) {
    const def = defs[i];
    if (!def.id || def.id.length === 0) {
      continue;
    }
    if (idToName.has(def.id) || unbridgeableIds.has(def.id)) {
      unbridgeableIds.add(def.id);
      idToName.delete(def.id);
      continue;
    }
    idToName.set(def.id, def.name);
  }
  const index: BackupDefNameIndex = { idToName: idToName, unbridgeableIds: unbridgeableIds };
  return index;
}

/**
 * 值键二次映射（id→name→id，ticket #14 最终形态）：
 * 备份值键（备份 def id）→ 备份 def 名 → 本地 def id。
 * 双跳任一落空或键不可桥接：保留原键并记入 unmappedKeys，由调用方计入 warnings。
 * 正确性不依赖新建 def 的 ID 生成策略（generateCustomFieldId 行为保持不变）。
 */
export function remapCustomFieldKeys(
  values: Record<string, string>,
  index: BackupDefNameIndex,
  nameToLocalId: Map<string, string>
): CustomFieldsRemapResult {
  const mapped: Record<string, string> = {};
  const unmappedKeys: string[] = [];
  const keys = Object.keys(values);
  for (let i = 0; i < keys.length; i++) {
    const key = keys[i];
    const val = values[key];
    let targetId: string | undefined = undefined;
    if (!index.unbridgeableIds.has(key)) {
      const name = index.idToName.get(key);
      if (name !== undefined) {
        const localId = nameToLocalId.get(name);
        if (localId !== undefined) {
          targetId = localId;
        }
      }
    }
    if (targetId !== undefined) {
      mapped[targetId] = val;
    } else {
      mapped[key] = val;
      unmappedKeys.push(key);
    }
  }
  const result: CustomFieldsRemapResult = { values: mapped, unmappedKeys: unmappedKeys };
  return result;
}
