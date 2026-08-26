/**
 * RelationalStore 封装：materials 表 CRUD（单例）。
 */
import { relationalStore } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Material } from '../model/Material';
import { CustomField, CustomFieldType } from '../model/CustomField';

const DB_NAME: string = 'keepfresh.db';
const TABLE: string = 'materials';
const CUSTOM_FIELDS_TABLE: string = 'custom_field_defs';

const CREATE_TABLE_SQL: string = `
CREATE TABLE IF NOT EXISTS ${TABLE} (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  category TEXT NOT NULL,
  quantity REAL NOT NULL,
  unit TEXT NOT NULL,
  production_date TEXT NOT NULL,
  shelf_life_days INTEGER NOT NULL,
  expiry_date TEXT NOT NULL,
  note TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  barcode TEXT,
  custom_fields TEXT
)
`;

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
      await this.store.executeSql(CREATE_TABLE_SQL);
      await this.store.executeSql(CREATE_CUSTOM_FIELD_DEFS_TABLE_SQL);
      try {
        await this.store.executeSql(`ALTER TABLE ${TABLE} ADD COLUMN barcode TEXT;`);
      } catch (_) {
        // Column might already exist, ignore error
      }
      try {
        await this.store.executeSql(`ALTER TABLE ${TABLE} ADD COLUMN custom_fields TEXT;`);
      } catch (_) {
        // Column might already exist, ignore error
      }
    } catch (e) {
      this.rethrow(e, 'init db');
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
      const m: Material = {
        id: rs.getLong(rs.getColumnIndex('id')),
        name: rs.getString(rs.getColumnIndex('name')),
        category: rs.getString(rs.getColumnIndex('category')),
        quantity: rs.getDouble(rs.getColumnIndex('quantity')),
        unit: rs.getString(rs.getColumnIndex('unit')),
        productionDate: rs.getString(rs.getColumnIndex('production_date')),
        shelfLifeDays: rs.getLong(rs.getColumnIndex('shelf_life_days')),
        expiryDate: rs.getString(rs.getColumnIndex('expiry_date')),
        note: rs.getString(rs.getColumnIndex('note')),
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
      'unit': m.unit,
      'production_date': m.productionDate,
      'shelf_life_days': m.shelfLifeDays,
      'expiry_date': m.expiryDate,
      'note': m.note,
      'created_at': m.createdAt,
      'updated_at': m.updatedAt,
      'barcode': m.barcode ?? '',
      'custom_fields': m.customFields ? JSON.stringify(m.customFields) : '{}'
    };
    return row;
  }

  /** 全量列表，按到期日升序 */
  async listAll(): Promise<Material[]> {
    const list: Material[] = [];
    try {
      const predicates = new relationalStore.RdbPredicates(TABLE);
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

  /** 删除，返回受影响行数 */
  async remove(id: number): Promise<number> {
    try {
      const predicates = new relationalStore.RdbPredicates(TABLE);
      predicates.equalTo('id', id);
      return await this.getStore().delete(predicates);
    } catch (e) {
      this.rethrow(e, 'remove');
    }
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
