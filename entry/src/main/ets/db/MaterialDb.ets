/**
 * RelationalStore 封装：materials 表 CRUD（单例）。
 */
import { relationalStore } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Material, MaterialStatus } from '../model/Material';
import { CustomField, CustomFieldType } from '../model/CustomField';

const DB_NAME: string = 'keepfresh.db';
const TABLE: string = 'materials';
const CUSTOM_FIELDS_TABLE: string = 'custom_field_defs';

/** 新安装直接建全量列；老库走 ALTER 增量迁移 */
const CREATE_TABLE_V2_SQL: string = `
CREATE TABLE IF NOT EXISTS ${TABLE} (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  category TEXT NOT NULL,
  quantity TEXT NOT NULL DEFAULT '0',
  unit TEXT NOT NULL,
  location TEXT NOT NULL DEFAULT '',
  production_date TEXT NOT NULL,
  shelf_life_days INTEGER NOT NULL,
  shelf_life_months INTEGER,
  expiry_date TEXT NOT NULL,
  note TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'active',
  handled_type TEXT,
  handled_at TEXT,
  is_deleted INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  barcode TEXT,
  custom_fields TEXT
)
`;

const CREATE_INDEX_SQLS: string[] = [
  `CREATE INDEX IF NOT EXISTS idx_materials_status_expiry ON ${TABLE}(status, expiry_date);`,
  `CREATE INDEX IF NOT EXISTS idx_materials_category_location ON ${TABLE}(category, location);`,
  `CREATE INDEX IF NOT EXISTS idx_materials_is_deleted ON ${TABLE}(is_deleted);`
];

const CREATE_CUSTOM_FIELD_DEFS_TABLE_SQL: string = `
CREATE TABLE IF NOT EXISTS ${CUSTOM_FIELDS_TABLE} (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  type TEXT NOT NULL,
  options TEXT,
  sort_order INTEGER NOT NULL,
  created_at TEXT NOT NULL
)
`;

/** 列表筛选条件 */
export interface MaterialFilter {
  category?: string;    // 空/undefined 不过滤
  location?: string;
  status?: string;      // 持久化 status（active/opened/empty/discarded）
  includeDeleted?: boolean; // 默认 false：软删除项不返回
}

export class MaterialDb {
  private store?: relationalStore.RdbStore;
  private static instance?: MaterialDb;

  private constructor() {
  }

  static getInstance(): MaterialDb {
    if (!MaterialDb.instance) {
      MaterialDb.instance = new MaterialDb();
    }
    return MaterialDb.instance;
  }

  /**
   * 统一异常处理：打印结构化日志 + 保留原错误 code/stack 后重新抛出。
   * 解决 1. as BusinessError 后直接 throw err 触发 arkts-limited-throw；
   *      2. throw new Error(message) 丢失 code/stack 的两难。
   */
  private rethrow(e: Object, op: string): never {
    const be = e as BusinessError;
    const codeStr = (be.code !== undefined && be.code !== null) ? `[${be.code}]` : '';
    console.error(`${op} failed${codeStr}: ${be.message}`);
    const out: Error = new Error(be.message);
    // 用 BusinessError 接口写附加属性（code/stack），保留原错误信息给调用方
    const beOut: BusinessError = out as BusinessError;
    if (be.code !== undefined && be.code !== null) {
      beOut.code = be.code;
    }
    if (be.stack !== undefined && be.stack !== null) {
      beOut.stack = be.stack;
    }
    throw out;
  }

  async init(context: Context): Promise<void> {
    if (this.store) {
      return;
    }
    const config: relationalStore.StoreConfig = {
      name: DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    };
    try {
      this.store = await relationalStore.getRdbStore(context, config);
      await this.migrate();
      await this.store.executeSql(CREATE_CUSTOM_FIELD_DEFS_TABLE_SQL);
    } catch (e) {
      this.rethrow(e, 'init db');
    }
  }

  /**
   * Schema 迁移：新库建 V2 全量表；老库逐列 ALTER 增量补齐 + quantity REAL→TEXT 迁移 + 索引。
   * 旧数据兼容：新列全部有默认值，quantity 转字符串。
   */
  private async migrate(): Promise<void> {
    const store = this.getStore();
    // 新库：V2 全量建表（IF NOT EXISTS 对老库无副作用）
    await store.executeSql(CREATE_TABLE_V2_SQL);
    // 老库：逐列增量补齐
    const alterColumns: string[] = [
      `ALTER TABLE ${TABLE} ADD COLUMN location TEXT NOT NULL DEFAULT '';`,
      `ALTER TABLE ${TABLE} ADD COLUMN shelf_life_months INTEGER;`,
      `ALTER TABLE ${TABLE} ADD COLUMN status TEXT NOT NULL DEFAULT 'active';`,
      `ALTER TABLE ${TABLE} ADD COLUMN handled_type TEXT;`,
      `ALTER TABLE ${TABLE} ADD COLUMN handled_at TEXT;`,
      `ALTER TABLE ${TABLE} ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0;`
    ];
    for (let i = 0; i < alterColumns.length; i++) {
      try {
        await store.executeSql(alterColumns[i]);
      } catch (_) {
        // 列已存在，忽略
      }
    }
    // quantity REAL → TEXT（SQLite 动态类型，ALTER 仅改声明；实际取值转字符串在读取时处理）
    try {
      await store.executeSql(`ALTER TABLE ${TABLE} ADD COLUMN quantity_text TEXT;`);
      await store.executeSql(`UPDATE ${TABLE} SET quantity_text = CAST(quantity AS TEXT);`);
      // 读取时优先 quantity_text 列（见 rowToMaterial）
    } catch (_) {
      // 已迁移过，忽略
    }
    // barcode / custom_fields（兼容最早版本老库）
    try {
      await store.executeSql(`ALTER TABLE ${TABLE} ADD COLUMN barcode TEXT;`);
    } catch (_) {
      // 列已存在，忽略
    }
    try {
      await store.executeSql(`ALTER TABLE ${TABLE} ADD COLUMN custom_fields TEXT;`);
    } catch (_) {
      // 列已存在，忽略
    }
    // 索引
    for (let i = 0; i < CREATE_INDEX_SQLS.length; i++) {
      try {
        await store.executeSql(CREATE_INDEX_SQLS[i]);
      } catch (_) {
        // 索引已存在，忽略
      }
    }
  }

  private getStore(): relationalStore.RdbStore {
    if (!this.store) {
      throw new Error('Database not initialized');
    }
    return this.store;
  }

  private rowToMaterial(rs: relationalStore.ResultSet): Material {
    try {
      const barcodeIndex: number = rs.getColumnIndex('barcode');
      let barcode: string | undefined = undefined;
      if (barcodeIndex >= 0 && !rs.isColumnNull(barcodeIndex)) {
        const val: string = rs.getString(barcodeIndex);
        if (val && val.length > 0) {
          barcode = val;
        }
      }
      const customFieldsIndex: number = rs.getColumnIndex('custom_fields');
      let customFields: Record<string, string> | undefined = undefined;
      if (customFieldsIndex >= 0 && !rs.isColumnNull(customFieldsIndex)) {
        const val: string = rs.getString(customFieldsIndex);
        if (val && val.length > 0) {
          try {
            customFields = JSON.parse(val) as Record<string, string>;
          } catch (e) {
            customFields = {};
          }
        }
      }
      // quantity：迁移库优先 quantity_text，否则列值转字符串
      let quantity: string = '0';
      const quantityTextIndex: number = rs.getColumnIndex('quantity_text');
      if (quantityTextIndex >= 0 && !rs.isColumnNull(quantityTextIndex)) {
        quantity = rs.getString(quantityTextIndex);
      } else {
        const quantityIndex: number = rs.getColumnIndex('quantity');
        if (quantityIndex >= 0 && !rs.isColumnNull(quantityIndex)) {
          quantity = `${rs.getDouble(quantityIndex)}`;
        }
      }
      // 可选新列（老库迁移前可能缺列）
      const locationIndex: number = rs.getColumnIndex('location');
      const location: string = locationIndex >= 0 ? rs.getString(locationIndex) : '';
      const monthsIndex: number = rs.getColumnIndex('shelf_life_months');
      let shelfLifeMonths: number | undefined = undefined;
      if (monthsIndex >= 0 && !rs.isColumnNull(monthsIndex)) {
        shelfLifeMonths = rs.getLong(monthsIndex);
      }
      const statusIndex: number = rs.getColumnIndex('status');
      const status: string = statusIndex >= 0 ? rs.getString(statusIndex) : MaterialStatus.ACTIVE;
      const handledTypeIndex: number = rs.getColumnIndex('handled_type');
      let handledType: string | undefined = undefined;
      if (handledTypeIndex >= 0 && !rs.isColumnNull(handledTypeIndex)) {
        handledType = rs.getString(handledTypeIndex);
      }
      const handledAtIndex: number = rs.getColumnIndex('handled_at');
      let handledAt: string | undefined = undefined;
      if (handledAtIndex >= 0 && !rs.isColumnNull(handledAtIndex)) {
        handledAt = rs.getString(handledAtIndex);
      }
      const isDeletedIndex: number = rs.getColumnIndex('is_deleted');
      const isDeleted: boolean = isDeletedIndex >= 0 && rs.getLong(isDeletedIndex) === 1;

      const m: Material = {
        id: rs.getLong(rs.getColumnIndex('id')),
        name: rs.getString(rs.getColumnIndex('name')),
        category: rs.getString(rs.getColumnIndex('category')),
        quantity: quantity,
        unit: rs.getString(rs.getColumnIndex('unit')),
        location: location,
        productionDate: rs.getString(rs.getColumnIndex('production_date')),
        shelfLifeDays: rs.getLong(rs.getColumnIndex('shelf_life_days')),
        shelfLifeMonths: shelfLifeMonths,
        expiryDate: rs.getString(rs.getColumnIndex('expiry_date')),
        note: rs.getString(rs.getColumnIndex('note')),
        status: status,
        handledType: handledType,
        handledAt: handledAt,
        isDeleted: isDeleted,
        createdAt: rs.getString(rs.getColumnIndex('created_at')),
        updatedAt: rs.getString(rs.getColumnIndex('updated_at')),
        barcode: barcode,
        customFields: customFields
      };
      return m;
    } catch (e) {
      this.rethrow(e, 'rowToMaterial');
    }
  }

  private toRow(m: Material): relationalStore.ValuesBucket {
    const row: relationalStore.ValuesBucket = {
      'name': m.name,
      'category': m.category,
      'quantity': m.quantity,
      'quantity_text': m.quantity,
      'unit': m.unit,
      'location': m.location ?? '',
      'production_date': m.productionDate,
      'shelf_life_days': m.shelfLifeDays,
      'shelf_life_months': m.shelfLifeMonths ?? null,
      'expiry_date': m.expiryDate,
      'note': m.note,
      'status': m.status ?? MaterialStatus.ACTIVE,
      'handled_type': m.handledType ?? null,
      'handled_at': m.handledAt ?? null,
      'is_deleted': m.isDeleted ? 1 : 0,
      'created_at': m.createdAt,
      'updated_at': m.updatedAt,
      'barcode': m.barcode ?? '',
      'custom_fields': m.customFields ? JSON.stringify(m.customFields) : '{}'
    };
    return row;
  }

  /** 全量列表（默认排除软删除），按到期日升序 */
  async listAll(filter?: MaterialFilter): Promise<Material[]> {
    const list: Material[] = [];
    try {
      const predicates = new relationalStore.RdbPredicates(TABLE);
      this.applyFilter(predicates, filter);
      predicates.orderByAsc('expiry_date');
      const rs: relationalStore.ResultSet = await this.getStore().query(predicates);
      try {
        while (rs.goToNextRow()) {
          list.push(this.rowToMaterial(rs));
        }
      } finally {
        rs.close();
      }
    } catch (e) {
      this.rethrow(e, 'listAll');
    }
    return list;
  }

  private applyFilter(predicates: relationalStore.RdbPredicates, filter?: MaterialFilter): void {
    const f: MaterialFilter = filter ?? {};
    if (!f.includeDeleted) {
      predicates.equalTo('is_deleted', 0);
    } else {
      predicates.greaterThanOrEqualTo('is_deleted', 0);
    }
    const cat: string = (f.category ?? '').trim();
    if (cat.length > 0) {
      predicates.equalTo('category', cat);
    }
    const loc: string = (f.location ?? '').trim();
    if (loc.length > 0) {
      predicates.equalTo('location', loc);
    }
    const st: string = (f.status ?? '').trim();
    if (st.length > 0) {
      predicates.equalTo('status', st);
    }
  }

  /** 回收站列表（仅软删除项），按删除时间（updated_at）倒序 */
  async listDeleted(): Promise<Material[]> {
    const list: Material[] = [];
    try {
      const predicates = new relationalStore.RdbPredicates(TABLE);
      predicates.equalTo('is_deleted', 1);
      predicates.orderByDesc('updated_at');
      const rs: relationalStore.ResultSet = await this.getStore().query(predicates);
      try {
        while (rs.goToNextRow()) {
          list.push(this.rowToMaterial(rs));
        }
      } finally {
        rs.close();
      }
    } catch (e) {
      this.rethrow(e, 'listDeleted');
    }
    return list;
  }

  /** 软删除：标记 is_deleted=1，返回受影响行数 */
  async softDelete(id: number): Promise<number> {
    try {
      const predicates = new relationalStore.RdbPredicates(TABLE);
      predicates.equalTo('id', id);
      const row: relationalStore.ValuesBucket = {
        'is_deleted': 1,
        'updated_at': new Date().toISOString().slice(0, 19).replace('T', ' ')
      };
      return await this.getStore().update(row, predicates);
    } catch (e) {
      this.rethrow(e, 'softDelete');
    }
  }

  /** 回收站恢复：is_deleted=0 */
  async restore(id: number): Promise<number> {
    try {
      const predicates = new relationalStore.RdbPredicates(TABLE);
      predicates.equalTo('id', id);
      const row: relationalStore.ValuesBucket = {
        'is_deleted': 0,
        'updated_at': new Date().toISOString().slice(0, 19).replace('T', ' ')
      };
      return await this.getStore().update(row, predicates);
    } catch (e) {
      this.rethrow(e, 'restore');
    }
  }

  /** 彻底删除（物理删除），返回受影响行数 */
  async purge(id: number): Promise<number> {
    try {
      const predicates = new relationalStore.RdbPredicates(TABLE);
      predicates.equalTo('id', id);
      return await this.getStore().delete(predicates);
    } catch (e) {
      this.rethrow(e, 'purge');
    }
  }

  /** 更新生命周期状态（开封/用完/丢弃），同时记录 handledType/handledAt */
  async updateStatus(id: number, status: string, handledType?: string): Promise<number> {
    try {
      const predicates = new relationalStore.RdbPredicates(TABLE);
      predicates.equalTo('id', id);
      const now: string = new Date().toISOString().slice(0, 19).replace('T', ' ');
      const row: relationalStore.ValuesBucket = {
        'status': status,
        'handled_type': handledType ?? null,
        'handled_at': handledType ? now : null,
        'updated_at': now
      };
      return await this.getStore().update(row, predicates);
    } catch (e) {
      this.rethrow(e, 'updateStatus');
    }
  }

  /** 从现有物资的 location 字段提取去重位置列表（升序） */
  async listLocations(): Promise<string[]> {
    const locations: Set<string> = new Set<string>();
    try {
      const predicates = new relationalStore.RdbPredicates(TABLE);
      predicates.equalTo('is_deleted', 0);
      const rs: relationalStore.ResultSet = await this.getStore().query(predicates, ['location']);
      try {
        while (rs.goToNextRow()) {
          const locIndex: number = rs.getColumnIndex('location');
          if (locIndex >= 0 && !rs.isColumnNull(locIndex)) {
            const loc: string = rs.getString(locIndex).trim();
            if (loc.length > 0) {
              locations.add(loc);
            }
          }
        }
      } finally {
        rs.close();
      }
    } catch (e) {
      this.rethrow(e, 'listLocations');
    }
    return Array.from(locations).sort();
  }

  async getById(id: number): Promise<Material | undefined> {
    let m: Material | undefined = undefined;
    try {
      const predicates = new relationalStore.RdbPredicates(TABLE);
      predicates.equalTo('id', id);
      const rs: relationalStore.ResultSet = await this.getStore().query(predicates);
      try {
        if (rs.goToNextRow()) {
          m = this.rowToMaterial(rs);
        }
      } finally {
        rs.close();
      }
    } catch (e) {
      this.rethrow(e, 'getById');
    }
    return m;
  }

  /** 按条形码查历史入库记录，按最近入库倒序（created_at，同日再按 id 倒序） */
  async findByBarcode(barcode: string): Promise<Material[]> {
    const list: Material[] = [];
    const code: string = barcode.trim();
    if (code.length === 0) {
      return list;
    }
    try {
      const predicates = new relationalStore.RdbPredicates(TABLE);
      predicates.equalTo('barcode', code);
      predicates.orderByDesc('created_at');
      predicates.orderByDesc('id');
      const rs: relationalStore.ResultSet = await this.getStore().query(predicates);
      try {
        while (rs.goToNextRow()) {
          list.push(this.rowToMaterial(rs));
        }
      } finally {
        rs.close();
      }
    } catch (e) {
      this.rethrow(e, 'findByBarcode');
    }
    return list;
  }

  /** 插入，返回新记录 rowId */
  async insert(m: Material): Promise<number> {
    try {
      return await this.getStore().insert(TABLE, this.toRow(m));
    } catch (e) {
      this.rethrow(e, 'insert');
    }
  }

  /** 更新，返回受影响行数 */
  async update(m: Material): Promise<number> {
    try {
      const predicates = new relationalStore.RdbPredicates(TABLE);
      predicates.equalTo('id', m.id);
      return await this.getStore().update(this.toRow(m), predicates);
    } catch (e) {
      this.rethrow(e, 'update');
    }
  }

  /** 删除（软删除语义，进回收站），返回受影响行数 */
  async remove(id: number): Promise<number> {
    return this.softDelete(id);
  }

  private rowToCustomField(rs: relationalStore.ResultSet): CustomField {
    try {
      const idIndex: number = rs.getColumnIndex('id');
      const nameIndex: number = rs.getColumnIndex('name');
      const typeIndex: number = rs.getColumnIndex('type');
      const optionsIndex: number = rs.getColumnIndex('options');
      const orderIndex: number = rs.getColumnIndex('sort_order');
      const createdAtIndex: number = rs.getColumnIndex('created_at');

      let options: string[] | undefined = undefined;
      if (optionsIndex >= 0 && !rs.isColumnNull(optionsIndex)) {
        const rawOptions = rs.getString(optionsIndex);
        if (rawOptions && rawOptions.length > 0) {
          try {
            options = JSON.parse(rawOptions) as string[];
          } catch (e) {
            options = [];
          }
        }
      }

      const f: CustomField = {
        id: rs.getString(idIndex),
        name: rs.getString(nameIndex),
        type: rs.getString(typeIndex) as CustomFieldType,
        options: options,
        order: rs.getLong(orderIndex),
        createdAt: rs.getString(createdAtIndex)
      };
      return f;
    } catch (e) {
      this.rethrow(e, 'rowToCustomField');
    }
  }

  private customFieldToRow(field: CustomField): relationalStore.ValuesBucket {
    const row: relationalStore.ValuesBucket = {
      'id': field.id,
      'name': field.name,
      'type': field.type,
      'options': field.options ? JSON.stringify(field.options) : '',
      'sort_order': field.order,
      'created_at': field.createdAt
    };
    return row;
  }

  /** 查询全部自定义字段定义，按 sort_order 升序，同序按创建时间升序 */
  async listCustomFields(): Promise<CustomField[]> {
    const list: CustomField[] = [];
    try {
      const predicates = new relationalStore.RdbPredicates(CUSTOM_FIELDS_TABLE);
      predicates.orderByAsc('sort_order');
      predicates.orderByAsc('created_at');
      const rs: relationalStore.ResultSet = await this.getStore().query(predicates);
      try {
        while (rs.goToNextRow()) {
          list.push(this.rowToCustomField(rs));
        }
      } finally {
        rs.close();
      }
    } catch (e) {
      this.rethrow(e, 'listCustomFields');
    }
    return list;
  }

  /** 按 ID 获取单个自定义字段 */
  async getCustomFieldById(id: string): Promise<CustomField | undefined> {
    let field: CustomField | undefined = undefined;
    try {
      const predicates = new relationalStore.RdbPredicates(CUSTOM_FIELDS_TABLE);
      predicates.equalTo('id', id);
      const rs: relationalStore.ResultSet = await this.getStore().query(predicates);
      try {
        if (rs.goToNextRow()) {
          field = this.rowToCustomField(rs);
        }
      } finally {
        rs.close();
      }
    } catch (e) {
      this.rethrow(e, 'getCustomFieldById');
    }
    return field;
  }

  /** 插入自定义字段定义 */
  async insertCustomField(field: CustomField): Promise<number> {
    try {
      return await this.getStore().insert(CUSTOM_FIELDS_TABLE, this.customFieldToRow(field));
    } catch (e) {
      this.rethrow(e, 'insertCustomField');
    }
  }

  /** 更新自定义字段定义（修改名称、选项、排序） */
  async updateCustomField(field: CustomField): Promise<number> {
    try {
      const predicates = new relationalStore.RdbPredicates(CUSTOM_FIELDS_TABLE);
      predicates.equalTo('id', field.id);
      return await this.getStore().update(this.customFieldToRow(field), predicates);
    } catch (e) {
      this.rethrow(e, 'updateCustomField');
    }
  }

  /** 删除自定义字段定义（已有物资里的字段值保留在 custom_fields JSON 中） */
  async removeCustomField(id: string): Promise<number> {
    try {
      const predicates = new relationalStore.RdbPredicates(CUSTOM_FIELDS_TABLE);
      predicates.equalTo('id', id);
      return await this.getStore().delete(predicates);
    } catch (e) {
      this.rethrow(e, 'removeCustomField');
    }
  }

  /** 批量更新字段排序序号 */
  async updateCustomFieldsOrder(fields: CustomField[]): Promise<void> {
    for (let i = 0; i < fields.length; i++) {
      const f = fields[i];
      f.order = i;
      try {
        const predicates = new relationalStore.RdbPredicates(CUSTOM_FIELDS_TABLE);
        predicates.equalTo('id', f.id);
        const row: relationalStore.ValuesBucket = {
          'sort_order': i
        };
        await this.getStore().update(row, predicates);
      } catch (e) {
        this.rethrow(e, `updateCustomFieldsOrder[${i}]`);
      }
    }
  }
}
