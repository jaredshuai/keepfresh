/**
 * 备份导出/导入服务（单例，与 MaterialDb 解耦）。
 *
 * 技术要点（依据 docs/research/backup-spec.md）：
 * - 导出：读全量 → 组 JSON → DocumentViewPicker.save() 拿 URI（先存成员变量）→ fileIo 写入。
 * - 导入：DocumentViewPicker.select() 拿 URI → fileIo 读取 → JSON.parse → 校验 → 冲突策略写入。
 * - 免权限：Picker 由用户通过系统 UI 授权，应用无需声明文件权限。
 * - fileIo 全程 try...finally 保证 closeSync，防止 fd 泄漏。
 */
import { picker, fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { UIContext } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import { MaterialDb, MaterialFilter, NameDef, NameKind } from '../db/MaterialDb';
import { Material, MaterialStatus } from '../model/Material';
import { CustomField, BackupDefNameIndex, buildBackupDefNameIndex, remapCustomFieldKeys } from '../model/CustomField';
import { planFieldDefs, planNameDefOrder } from '../common/BackupPlan';
import { SettingsService } from './SettingsService';
import { ReminderService, ReminderSettings } from './ReminderService';
import { todayStr } from '../common/DateUtils';
import { MaterialWriteService } from './MaterialWriteService';

const DOMAIN: number = 0x0000;
const TAG: string = 'BackupService';
/** v2：新增 nameDefs 段（自定义分类/位置/单位定义）；v1 备份无此字段，导入时自动跳过 */
const SCHEMA_VERSION: number = 2;

/** 备份文件 JSON 结构 */
export interface BackupData {
  schemaVersion: number;
  exportedAt: string;
  settings: BackupSettings;
  customFields: CustomField[];
  materials: Material[];
  /** v2 起：自定义分类/位置/单位定义（含用户排序）；v1 备份无此字段 */
  nameDefs?: NameDefBackup[];
}

/** name_defs 表的备份形态（id 为设备本地自增，不导出；物资按文本名称关联） */
export interface NameDefBackup {
  kind: string;   // 'category' | 'location' | 'unit'
  name: string;
  order: number;
}

export interface BackupSettings {
  nearExpiryDays: number;
  reminderEnabled: boolean;
  reminderHour: number;
  reminderMinute: number;
}

/** 导入预览结果 */
export interface ImportPreview {
  data: BackupData;
  addCount: number;      // 将新增的物资数
  overwriteCount: number; // 将覆盖的物资数
}

/** 导入执行结果 */
export interface ImportResult {
  success: boolean;
  importedCount: number;
  message: string;
  /** 非致命警告（如「提醒同步失败」等），UI 可展示给用户并提示重试路径 */
  warnings: string[];
}

export class BackupService {
  private static instance?: BackupService;
  /** Picker 返回的 URI 先存成员变量，避免在回调中直接操作 */
  private savedUri: string = '';

  private constructor() {}

  public static getInstance(): BackupService {
    if (!BackupService.instance) {
      BackupService.instance = new BackupService();
    }
    return BackupService.instance;
  }

  private showToast(uiContext: UIContext, message: string): void {
    try {
      uiContext.getPromptAction().showToast({ message });
    } catch (e) {
      hilog.error(DOMAIN, TAG, `show toast failed: ${(e as BusinessError).message}`);
    }
  }

  /**
   * 导出备份：读全量数据 → 组 JSON → DocumentViewPicker.save() → fileIo 写入。
   */
  public async exportBackup(context: common.UIAbilityContext, uiContext: UIContext): Promise<void> {
    try {
      const db: MaterialDb = MaterialDb.getInstance();
      await db.init(context);
      // 含软删除（回收站）物资：备份应是完整快照，回收站数据可随备份恢复
      const allFilter: MaterialFilter = { includeDeleted: true };
      const materials: Material[] = await db.listAll(allFilter);
      const customFields: CustomField[] = await db.listCustomFields();
      // 自定义分类/位置/单位定义（v2 新增段；restore 侧三种 kind 都会还原，
      // 导出必须齐备，否则 overwrite 导入会删掉未导出的 kind 定义）
      const nameDefs: NameDefBackup[] = [];
      const categoryDefs: NameDef[] = await db.listNameDefs('category');
      for (const d of categoryDefs) {
        const row: NameDefBackup = { kind: 'category', name: d.name, order: d.order };
        nameDefs.push(row);
      }
      const locationDefs: NameDef[] = await db.listNameDefs('location');
      for (const d of locationDefs) {
        const row: NameDefBackup = { kind: 'location', name: d.name, order: d.order };
        nameDefs.push(row);
      }
      const unitDefs: NameDef[] = await db.listNameDefs('unit');
      for (const d of unitDefs) {
        const row: NameDefBackup = { kind: 'unit', name: d.name, order: d.order };
        nameDefs.push(row);
      }

      const settingsService: SettingsService = SettingsService.getInstance();
      await settingsService.init(context);
      const nearExpiryDays: number = await settingsService.getNearExpiryDays();
      const reminder: ReminderSettings = await ReminderService.getInstance().getSettings();

      const backup: BackupData = {
        schemaVersion: SCHEMA_VERSION,
        exportedAt: new Date().toISOString(),
        settings: {
          nearExpiryDays: nearExpiryDays,
          reminderEnabled: reminder.enabled,
          reminderHour: reminder.hour,
          reminderMinute: reminder.minute
        },
        customFields: customFields,
        materials: materials,
        nameDefs: nameDefs
      };
      const content: string = JSON.stringify(backup, null, 2);

      // 生成文件名：keepfresh_backup_YYYYMMDD.json
      const dateStr: string = todayStr().replace(/-/g, '');
      const fileName: string = `keepfresh_backup_${dateStr}.json`;

      const documentPicker = new picker.DocumentViewPicker(context);
      const saveOptions = new picker.DocumentSaveOptions();
      saveOptions.newFileNames = [fileName];
      saveOptions.fileSuffixChoices = ['JSON 备份|.json'];

      const uris: Array<string> = await documentPicker.save(saveOptions);
      if (!uris || uris.length === 0) {
        return; // 用户取消
      }
      this.savedUri = uris[0];

      // fileIo 写入，try...finally 保证 closeSync
      let fd: number = -1;
      try {
        const file = fileIo.openSync(this.savedUri, fileIo.OpenMode.READ_WRITE);
        fd = file.fd;
        fileIo.writeSync(fd, content);
        this.showToast(uiContext, '已导出到所选位置');
        hilog.info(DOMAIN, TAG, `Backup exported: ${this.savedUri}, materials=${materials.length}`);
      } finally {
        if (fd >= 0) {
          fileIo.closeSync(fd);
        }
      }
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      hilog.error(DOMAIN, TAG, `Export failed: ${e.code}, ${e.message}`);
      this.showToast(uiContext, '导出失败，请重试');
    }
  }

  /**
   * 导入备份第一步：选文件 → 读内容 → 解析校验 → 返回预览数据。
   * 校验失败时 Toast 并返回 undefined。
   */
  public async importBackup(context: common.UIAbilityContext, uiContext: UIContext): Promise<ImportPreview | undefined> {
    try {
      const documentPicker = new picker.DocumentViewPicker(context);
      const selectOptions = new picker.DocumentSelectOptions();
      selectOptions.fileSuffixFilters = ['KeepFresh 备份|.json'];
      selectOptions.maxSelectNumber = 1;

      const uris: Array<string> = await documentPicker.select(selectOptions);
      if (!uris || uris.length === 0) {
        return undefined; // 用户取消
      }
      this.savedUri = uris[0];

      // fileIo 读取，try...finally 保证 closeSync
      let content: string = '';
      let fd: number = -1;
      try {
        const file = fileIo.openSync(this.savedUri, fileIo.OpenMode.READ_ONLY);
        fd = file.fd;
        const stat = fileIo.statSync(fd);
        const buf = new ArrayBuffer(stat.size);
        fileIo.readSync(fd, buf);
        const decoder = util.TextDecoder.create('utf-8');
        content = decoder.decodeToString(new Uint8Array(buf));
      } finally {
        if (fd >= 0) {
          fileIo.closeSync(fd);
        }
      }

      // JSON.parse 校验
      let data: BackupData;
      try {
        data = JSON.parse(content) as BackupData;
      } catch (parseErr) {
        this.showToast(uiContext, '备份文件格式不正确');
        return undefined;
      }

      // 结构校验
      if (data.schemaVersion === undefined || data.schemaVersion === null) {
        this.showToast(uiContext, '备份文件格式不正确');
        return undefined;
      }
      if (!data.materials || !Array.isArray(data.materials)) {
        this.showToast(uiContext, '备份文件格式不正确');
        return undefined;
      }

      // 版本兼容：> 1 拒绝
      if (data.schemaVersion > SCHEMA_VERSION) {
        this.showToast(uiContext, '备份文件版本过新，请升级应用');
        return undefined;
      }

      // 计算冲突预览
      const preview = await this.buildPreview(context, data);
      return preview;
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      hilog.error(DOMAIN, TAG, `Import failed: ${e.code}, ${e.message}`);
      this.showToast(uiContext, '导入失败，请重试');
      return undefined;
    }
  }

  /**
   * 构建导入预览：按业务键「名称+到期日」判定冲突。
   */
  private async buildPreview(context: common.UIAbilityContext, data: BackupData): Promise<ImportPreview> {
    const db: MaterialDb = MaterialDb.getInstance();
    await db.init(context);
    // 与 executeImport 同口径：冲突判定含回收站行（回收站里的同名同到期日物资同样会被覆盖）
    const existing: Material[] = await db.listAll({ includeDeleted: true });

    // 现有物资业务键集合
    const existingKeys = new Set<string>();
    for (const m of existing) {
      existingKeys.add(this.businessKey(m));
    }

    let addCount: number = 0;
    let overwriteCount: number = 0;
    for (const m of data.materials) {
      if (existingKeys.has(this.businessKey(m))) {
        overwriteCount++;
      } else {
        addCount++;
      }
    }

    return { data, addCount, overwriteCount };
  }

  /**
   * 业务键：名称 + 到期日（同名同到期日视为同一物资）。
   */
  private businessKey(m: Material): string {
    return `${m.name}||${m.expiryDate}`;
  }

  /**
   * 执行导入。
   * @param context UIAbilityContext
   * @param data 已解析校验的备份数据
   * @param mode 'merge' = 增量合并（冲突覆盖、不冲突新增）；'overwrite' = 清空后导入
   */
  public async executeImport(
    context: common.UIAbilityContext,
    data: BackupData,
    mode: 'merge' | 'overwrite'
  ): Promise<ImportResult> {
    const warnings: string[] = [];
    try {
      const db: MaterialDb = MaterialDb.getInstance();
      await db.init(context);

      // ── 1. 处理自定义字段定义冲突 ──
      const fieldIdMap = await this.resolveCustomFieldDefs(db, data.customFields || []);
      // 值键桥接索引：备份值键（备份 def id）→ 备份 def 名 → 本地 def id（ticket #14）
      const defNameIndex: BackupDefNameIndex = buildBackupDefNameIndex(data.customFields || []);
      const unmappedKeySet = new Set<string>();

      // ── 1.5 还原自定义分类/位置/单位定义（v2+；v1 备份无此字段自动跳过）──
      // 空数组也要 restore：overwrite 语义下需清掉本地定义，不能靠 length>0 跳过
      if (data.nameDefs && Array.isArray(data.nameDefs)) {
        this.validateNameDefs(data.nameDefs);
        await this.restoreNameDefs(db, data.nameDefs, mode);
      }

      // ── 2. 处理物资 ──
      let importedCount: number = 0;
      // 冲突判定/清空范围须含回收站（软删除）行，否则 merge 会给回收站物品插重复业务键、
      // overwrite 会残留旧回收站行 —— 快照语义要求全集对齐
      const allFilter: MaterialFilter = { includeDeleted: true };

      if (mode === 'overwrite') {
        // 清空后导入：物理清除所有现有物资（含回收站），保证真正的快照替换
        const existing: Material[] = await db.listAll(allFilter);
        for (const m of existing) {
          await db.purge(m.id);
        }
        // 全部作为新增插入
        for (const m of data.materials) {
          const mapped = this.mapImportedMaterial(m, fieldIdMap, defNameIndex, unmappedKeySet);
          await db.insert(mapped);
          importedCount++;
        }
      } else {
        // 增量合并：冲突覆盖、不冲突新增（冲突集含回收站行，避免重复业务键）
        const existing: Material[] = await db.listAll(allFilter);
        const existingByKey = new Map<string, Material>();
        for (const m of existing) {
          existingByKey.set(this.businessKey(m), m);
        }

        for (const m of data.materials) {
          const key = this.businessKey(m);
          const mapped = this.mapImportedMaterial(m, fieldIdMap, defNameIndex, unmappedKeySet);
          const existingMatch = existingByKey.get(key);
          if (existingMatch) {
            // 冲突：按导入数据覆盖（保留现有 id）
            mapped.id = existingMatch.id;
            await db.update(mapped);
          } else {
            // 不冲突：新增（id 由数据库自增）
            mapped.id = -1;
            await db.insert(mapped);
          }
          importedCount++;
        }
      }

      // ── 2.5 值键无法桥接的字段：聚合为 warnings 上浮 UI（ticket #14）──
      unmappedKeySet.forEach((key: string) => {
        warnings.push(`部分物资的自定义字段值无法匹配字段定义（原键 ${key}），已按原样保留`);
      });

      // ── 3. 导入设置 ──
      if (data.settings) {
        await this.applySettings(context, data.settings);
      }

      // ── 4. 同步每日提醒：失败时不中断导入，写入 warnings 给 UI 可见提示
      try {
        // 写路径统一（C2）：批量导入收尾 = 版本自增 + 提醒重算
        await MaterialWriteService.getInstance().init(context);
        await MaterialWriteService.getInstance().batchDone();
      } catch (e) {
        const err = e as BusinessError;
        const msg = `每日提醒同步失败：${err.code ?? ''} ${err.message}`;
        hilog.error(DOMAIN, TAG, `${msg}. 用户可在设置页重新保存以重试`);
        warnings.push(msg + '。请在「设置→每日提醒」重新保存以重试');
      }

      hilog.info(DOMAIN, TAG, `Import done: mode=${mode}, imported=${importedCount}, warnings=${warnings.length}`);
      return { success: true, importedCount, warnings, message: `已导入 ${importedCount} 件物资` };
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      hilog.error(DOMAIN, TAG, `Execute import failed: ${e.code}, ${e.message}`);
      return { success: false, importedCount: 0, warnings, message: '导入失败，请重试' };
    }
  }

  /**
   * 校验备份中的 nameDefs：kind 合法、name 非空字符串、order 为非负整数。
   * 全量校验通过后才允许落库（restoreNameDefs 会先删后插），避免中途失败留下半成品。
   */
  private validateNameDefs(imported: NameDefBackup[]): void {
    for (let i = 0; i < imported.length; i++) {
      const d = imported[i];
      const kindStr: string = `${d.kind ?? ''}`;
      if (kindStr !== 'category' && kindStr !== 'location' && kindStr !== 'unit') {
        throw new Error(`nameDefs[${i}].kind 非法: ${kindStr}`);
      }
      // 非字符串 name 一律拒绝（防篡改备份把 number/object 混进来被持久化成字符串）
      if (typeof d.name !== 'string') {
        throw new Error(`nameDefs[${i}].name 非法（须为字符串）`);
      }
      const n: string = d.name.trim();
      if (n.length === 0 || n.length > 20) {
        throw new Error(`nameDefs[${i}].name 非法（空或超 20 字）`);
      }
      const o = d.order;
      if (o !== undefined && o !== null && (typeof o !== 'number' || o < 0 || !Number.isInteger(o))) {
        throw new Error(`nameDefs[${i}].order 非法: ${o}`);
      }
    }
  }

  /**
   * 还原自定义分类/位置/单位定义（v2+ 备份）。
   * 目标序为纯决策，唯一实现在 common/BackupPlan.planNameDefOrder（Node 可测）；
   * 本方法只负责按目标序删除重插。name_defs.id 无外部引用（物资按文本名称关联），
   * 删除重插只损失本地自增 id，不损失数据。
   */
  private async restoreNameDefs(
    db: MaterialDb,
    imported: NameDefBackup[],
    mode: 'merge' | 'overwrite'
  ): Promise<void> {
    const kinds: string[] = ['category', 'location', 'unit'];
    for (const kind of kinds) {
      const k: NameKind = kind as NameKind;
      // 导入侧名称序列（顺序即备份序；去空去重由 plan 负责）
      const importedNames: string[] = [];
      for (const d of imported) {
        if (d.kind === kind) {
          importedNames.push(d.name ?? '');
        }
      }
      // 本地现有定义
      const existing: NameDef[] = await db.listNameDefs(k);
      const existingNames: string[] = [];
      for (const def of existing) {
        existingNames.push(def.name);
      }
      const target: string[] = planNameDefOrder(importedNames, existingNames, mode);
      // 删除现有全部，按目标顺序重插
      for (const def of existing) {
        await db.removeNameDef(def.id);
      }
      for (let i = 0; i < target.length; i++) {
        await db.insertNameDef(k, target[i]);
      }
    }
  }

  /**
   * 处理自定义字段定义冲突，返回「导入字段名 → 现有字段 ID」映射。
   * 冲突裁决为纯决策，唯一实现在 common/BackupPlan.planFieldDefs（Node 可测）；
   * 本方法只负责按 plan 落库（规则见 planFieldDefs 注释，ticket #6）。
   */
  private async resolveCustomFieldDefs(
    db: MaterialDb,
    importedDefs: CustomField[]
  ): Promise<Map<string, string>> {
    if (!importedDefs || importedDefs.length === 0) {
      return new Map<string, string>();
    }
    const existingDefs: CustomField[] = await db.listCustomFields();
    const plan = planFieldDefs(existingDefs, importedDefs, todayStr());
    for (const def of plan.toCreate) {
      await db.insertCustomField(def);
    }
    return plan.fieldIdMap;
  }

  /**
   * 将导入的 Material 映射为可写入数据库的对象：
   * - 不保留原 id（由数据库自增或覆盖时保留现有 id）
   * - customFields 值键经 id→name→id 二次映射对齐本地定义 ID（ticket #14）
   */
  private mapImportedMaterial(
    m: Material,
    nameToLocalId: Map<string, string>,
    defNameIndex: BackupDefNameIndex,
    unmappedKeyCollector: Set<string>
  ): Material {
    // 值键重映射走契约函数；双跳落空的键保留原键并收集为 warnings
    let mappedCustomFields: Record<string, string> | undefined = undefined;
    if (m.customFields) {
      const remap = remapCustomFieldKeys(m.customFields, defNameIndex, nameToLocalId);
      mappedCustomFields = remap.values;
      for (let i = 0; i < remap.unmappedKeys.length; i++) {
        unmappedKeyCollector.add(remap.unmappedKeys[i]);
      }
    }

    const mapped: Material = {
      id: -1, // 默认新增，覆盖时由调用方设为现有 id
      name: m.name,
      category: m.category,
      quantity: typeof m.quantity === 'number' ? `${m.quantity}` : (m.quantity || '0'),
      unit: m.unit,
      location: m.location || '',
      productionDate: m.productionDate,
      shelfLifeDays: m.shelfLifeDays,
      shelfLifeMonths: m.shelfLifeMonths,
      expiryDate: m.expiryDate,
      note: m.note || '',
      status: m.status || MaterialStatus.ACTIVE,
      handledType: m.handledType,
      handledAt: m.handledAt,
      isDeleted: m.isDeleted === true,
      createdAt: m.createdAt || todayStr(),
      updatedAt: todayStr(),
      barcode: m.barcode,
      customFields: mappedCustomFields
    };
    return mapped;
  }

  /**
   * 应用导入的设置：写入 SettingsService / ReminderService 持久化，
   * nearExpiryDays 同步 ExpiryService 缓存，reminder 触发 syncDailyReminder。
   */
  private async applySettings(context: common.UIAbilityContext, settings: BackupSettings): Promise<void> {
    const settingsService: SettingsService = SettingsService.getInstance();
    await settingsService.init(context);

    // 临期阈值
    if (typeof settings.nearExpiryDays === 'number' && settings.nearExpiryDays >= 1 && settings.nearExpiryDays <= 365) {
      await settingsService.updateNearExpiryDays(Math.floor(settings.nearExpiryDays));
      // updateNearExpiryDays 内部已调 setNearExpiryThreshold 同步缓存
    }

    // 提醒设置
    const reminderService: ReminderService = ReminderService.getInstance();
    await reminderService.init(context);
    const reminderSettings: ReminderSettings = {
      enabled: settings.reminderEnabled === true,
      hour: typeof settings.reminderHour === 'number' ? settings.reminderHour : 9,
      minute: typeof settings.reminderMinute === 'number' ? settings.reminderMinute : 0
    };
    await reminderService.updateSettings(reminderSettings);
    // syncDailyReminder 由 executeImport 末尾统一调用
  }
}
