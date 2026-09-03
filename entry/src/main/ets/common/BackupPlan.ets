/**
 * 备份导入决策（纯函数，Node 可测）：自定义字段定义冲突裁决 + nameDefs 目标序。
 * 此前这两块决策困在 service/BackupService.ets（@kit 层）零测试（audit-wiring L5）；
 * 下沉后决策获 Node 直测，BackupService 只剩按 plan 落库。
 * 与 model/CustomField.ets 的 remapCustomFieldKeys 同构（纯决策下沉、IO 留 service）。
 */
import type { CustomField } from '../model/CustomField';
import { generateCustomFieldId } from '../model/CustomField';

/** 字段定义冲突裁决结果：fieldIdMap = 导入字段名 → 最终字段 ID；toCreate = 待新建定义（按导入序） */
export interface FieldDefPlan {
  fieldIdMap: Map<string, string>;
  toCreate: CustomField[];
}

/**
 * 自定义字段定义冲突裁决（规则同 ticket #6）：
 * - 同名同类型：保留现有定义，映射到现有 ID；
 * - 同名不同类型：重命名为「原名_导入」新建（并更新名称索引，防后续导入字段再冲突）；
 * - 不存在：直接新建。
 * 新建定义排序优先还原备份 order（M5 修复），缺失/非法回退 maxOrder+1。
 * idFactory 可注入以保证测试确定性（默认走 generateCustomFieldId）。
 */
export function planFieldDefs(
  existing: CustomField[],
  imported: CustomField[],
  now: string,
  idFactory?: () => string
): FieldDefPlan {
  const genId: () => string = idFactory ?? generateCustomFieldId;
  const fieldIdMap = new Map<string, string>();
  const toCreate: CustomField[] = [];
  if (!imported || imported.length === 0) {
    return { fieldIdMap: fieldIdMap, toCreate: toCreate };
  }

  const existingByName = new Map<string, CustomField>();
  for (const def of existing) {
    existingByName.set(def.name, def);
  }

  let maxOrder: number = -1;
  for (const def of existing) {
    if (def.order > maxOrder) {
      maxOrder = def.order;
    }
  }

  for (const importedDef of imported) {
    // 新建定义排序：优先还原备份 order；缺失/非法回退 maxOrder+1
    const restoredOrder: number =
      (importedDef.order !== undefined && importedDef.order !== null && importedDef.order >= 0)
        ? importedDef.order
        : maxOrder + 1;
    maxOrder = Math.max(maxOrder, restoredOrder);

    const existingDef: CustomField | undefined = existingByName.get(importedDef.name);
    if (existingDef) {
      if (existingDef.type === importedDef.type) {
        // 同名同类型：保留现有，映射到现有 ID
        fieldIdMap.set(importedDef.name, existingDef.id);
      } else {
        // 同名不同类型：重命名「原名_导入」新建
        const renamedName: string = `${importedDef.name}_导入`;
        const newId: string = genId();
        const newDef: CustomField = {
          id: newId,
          name: renamedName,
          type: importedDef.type,
          options: importedDef.options,
          order: restoredOrder,
          createdAt: now
        };
        toCreate.push(newDef);
        fieldIdMap.set(importedDef.name, newId);
        // 更新索引，防止后续导入的字段与被重命名的字段再冲突
        existingByName.set(renamedName, newDef);
      }
    } else {
      // 不存在：新建定义
      const newId: string = genId();
      const newDef: CustomField = {
        id: newId,
        name: importedDef.name,
        type: importedDef.type,
        options: importedDef.options,
        order: restoredOrder,
        createdAt: now
      };
      toCreate.push(newDef);
      fieldIdMap.set(importedDef.name, newId);
      existingByName.set(importedDef.name, newDef);
    }
  }

  return { fieldIdMap: fieldIdMap, toCreate: toCreate };
}

/**
 * nameDefs 还原目标序（自定义分类/位置/单位，备份 v2+）：
 * - 导入名称去空去重后按备份顺序在前；
 * - merge：本地独有名称按现有顺序追加尾部；
 * - overwrite：仅保留导入定义（与物资清空语义一致）。
 * 执行侧（BackupService.restoreNameDefs）按目标序删除重插；
 * name_defs.id 无外部引用（物资按文本名称关联），删除重插无损。
 */
export function planNameDefOrder(
  importedRawNames: string[],
  existingNames: string[],
  mode: 'merge' | 'overwrite'
): string[] {
  const target: string[] = [];
  const seen: Set<string> = new Set<string>();
  for (const raw of importedRawNames) {
    const n: string = raw.trim();
    if (n.length > 0 && !seen.has(n)) {
      seen.add(n);
      target.push(n);
    }
  }
  if (mode === 'merge') {
    for (const name of existingNames) {
      if (!seen.has(name)) {
        seen.add(name);
        target.push(name);
      }
    }
  }
  return target;
}
