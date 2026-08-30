/**
 * 物资写路径统一服务（C2）：所有物资写操作的唯一入口。
 * 写后义务集中于此——自增 AppStorage materialsVersion（Index @Watch 立即重查，
 * 兜住跨页写读竞速 #crosspage-write-read-race）+ 重算每日提醒
 * （恢复/删除回收站行同样影响提醒口径，此前回收站路径漏算）。
 * 页面不再各自记得这两件事；新增写方想忘都忘不掉。
 */
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { MaterialDb } from '../db/MaterialDb';
import { Material } from '../model/Material';
import { mergeIntoBatch } from '../common/MaterialForm';
import { ReminderService } from './ReminderService';

/** 保存结果：outcome 供分支，quantity 为落库后的数量（并条 = 求和值，供 toast） */
export interface SaveResult {
  outcome: 'updated' | 'merged' | 'inserted';
  quantity: string;
}

export class MaterialWriteService {
  private static instance?: MaterialWriteService;
  private db: MaterialDb = MaterialDb.getInstance();
  private ctx?: common.UIAbilityContext;

  private constructor() {}

  static getInstance(): MaterialWriteService {
    if (!MaterialWriteService.instance) {
      MaterialWriteService.instance = new MaterialWriteService();
    }
    return MaterialWriteService.instance;
  }

  async init(context: common.UIAbilityContext): Promise<void> {
    this.ctx = context;
    await this.db.init(context);
  }

  /** 写后义务：版本自增（Index @Watch 立即重查）+ 每日提醒重算。失败不阻断调用方 */
  private async afterWrite(): Promise<void> {
    AppStorage.setOrCreate('materialsVersion', (AppStorage.get<number>('materialsVersion') ?? 0) + 1);
    if (!this.ctx) {
      return;
    }
    try {
      await ReminderService.getInstance().syncDailyReminder(this.ctx);
    } catch (e) {
      console.error(`sync reminder failed: ${(e as BusinessError).message}`);
    }
  }

  /**
   * 保存物资：编辑走 1:1 更新；新增先找同批次在库行（同名+同位置+同到期日+同单位）
   * 命中则并条（数量求和+空位补齐），否则新插。并条策略唯一实现 common/MaterialForm。
   */
  async save(material: Material, isEdit: boolean): Promise<SaveResult> {
    if (isEdit) {
      await this.db.update(material);
      await this.afterWrite();
      return { outcome: 'updated', quantity: material.quantity };
    }
    const twin = await this.db.findActiveBatchMatch(material);
    const now: string = material.updatedAt;
    const merged = twin ? mergeIntoBatch(twin, material, now) : null;
    if (merged) {
      await this.db.update(merged);
      await this.afterWrite();
      return { outcome: 'merged', quantity: merged.quantity };
    }
    await this.db.insert(material);
    await this.afterWrite();
    return { outcome: 'inserted', quantity: material.quantity };
  }

  /** 生命周期状态变更（开封/用完/丢弃/恢复在库） */
  async markStatus(id: number, status: string, handledType?: string): Promise<void> {
    await this.db.updateStatus(id, status, handledType);
    await this.afterWrite();
  }

  /** 软删除（进回收站） */
  async softDelete(id: number): Promise<void> {
    await this.db.remove(id);
    await this.afterWrite();
  }

  /** 回收站恢复（恢复过期/临期行后提醒口径随之重算——此前此路径漏算是活缺陷） */
  async restore(id: number): Promise<void> {
    await this.db.restore(id);
    await this.afterWrite();
  }

  /** 彻底删除（物理） */
  async purge(id: number): Promise<void> {
    await this.db.purge(id);
    await this.afterWrite();
  }

  /** 批量写收尾（备份导入等成批操作后调用一次，替代逐行 afterWrite） */
  async batchDone(): Promise<void> {
    await this.afterWrite();
  }
}
