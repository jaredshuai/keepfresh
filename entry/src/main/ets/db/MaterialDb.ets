/**
 * RelationalStore 封装：materials 表 CRUD（单例）。
 */
import { relationalStore } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';
import { Material } from '../model/Material';

const DB_NAME: string = 'keepfresh.db';
const TABLE: string = 'materials';

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
  updated_at TEXT NOT NULL
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

  async init(context: Context): Promise<void> {
    if (this.store) {
      return;
    }
    const config: relationalStore.StoreConfig = {
      name: DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    };
    this.store = await relationalStore.getRdbStore(context, config);
    await this.store.executeSql(CREATE_TABLE_SQL);
  }

  private getStore(): relationalStore.RdbStore {
    if (!this.store) {
      throw new Error('Database not initialized');
    }
    return this.store;
  }

  private rowToMaterial(rs: relationalStore.ResultSet): Material {
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
      updatedAt: rs.getString(rs.getColumnIndex('updated_at'))
    };
    return m;
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
      'updated_at': m.updatedAt
    };
    return row;
  }

  /** 全量列表，按到期日升序 */
  async listAll(): Promise<Material[]> {
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.orderByAsc('expiry_date');
    const rs: relationalStore.ResultSet = await this.getStore().query(predicates);
    const list: Material[] = [];
    while (rs.goToNextRow()) {
      list.push(this.rowToMaterial(rs));
    }
    rs.close();
    return list;
  }

  async getById(id: number): Promise<Material | undefined> {
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('id', id);
    const rs: relationalStore.ResultSet = await this.getStore().query(predicates);
    let m: Material | undefined = undefined;
    if (rs.goToNextRow()) {
      m = this.rowToMaterial(rs);
    }
    rs.close();
    return m;
  }

  /** 插入，返回新记录 rowId */
  async insert(m: Material): Promise<number> {
    return await this.getStore().insert(TABLE, this.toRow(m));
  }

  /** 更新，返回受影响行数 */
  async update(m: Material): Promise<number> {
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('id', m.id);
    return await this.getStore().update(this.toRow(m), predicates);
  }

  /** 删除，返回受影响行数 */
  async remove(id: number): Promise<number> {
    const predicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('id', id);
    return await this.getStore().delete(predicates);
  }
}
