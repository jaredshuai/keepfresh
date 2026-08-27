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
import { MaterialDb } from '../db/MaterialDb';
import { Material, MaterialStatus } from '../model/Material';
import { CustomField, generateCustomFieldId } from '../model/CustomField';
import { SettingsService } from './SettingsService';
import { ReminderService, ReminderSettings } from './ReminderService';
import { todayStr } from '../common/DateUtils';

const DOMAIN: number = 0x0000;
const TAG: string = 'BackupService';
const SCHEMA_VERSION: number = 1;

/** 备份文件 JSON 结构 */
export interface BackupData {
  schemaVersion: number;
  exportedAt: string;
  settings: BackupSettings;
  customFields: CustomField[];
  materials: Material[];
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
      const materials: Material[] = await db.listAll();
      const customFields: CustomField[] = await db.listCustomFields();

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
        materials: materials
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
    const existing: Material[] = await db.listAll();

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

      // ── 2. 处理物资 ──
      let importedCount: number = 0;

      if (mode === 'overwrite') {
        // 清空后导入：删除所有现有物资
        const existing: Material[] = await db.listAll();
        for (const m of existing) {
          await db.remove(m.id);
        }
        // 全部作为新增插入
        for (const m of data.materials) {
          const mapped = this.mapImportedMaterial(m, fieldIdMap);
          await db.insert(mapped);
          importedCount++;
        }
      } else {
        // 增量合并：冲突覆盖、不冲突新增
        const existing: Material[] = await db.listAll();
        const existingByKey = new Map<string, Material>();
        for (const m of existing) {
          existingByKey.set(this.businessKey(m), m);
        }

        for (const m of data.materials) {
          const key = this.businessKey(m);
          const mapped = this.mapImportedMaterial(m, fieldIdMap);
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

      // ── 3. 导入设置 ──
      if (data.settings) {
        await this.applySettings(context, data.settings);
      }

      // ── 4. 同步每日提醒：失败时不中断导入，写入 warnings 给 UI 可见提示
      try {
        await ReminderService.getInstance().syncDailyReminder(context);
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
   * 处理自定义字段定义冲突，返回「导入字段名 → 现有字段 ID」映射。
   *
   * 规则（ticket #6）：
   * - 同名同类型：保留现有定义，导入物资按字段名映射到现有定义 ID。
   * - 同名不同类型：重命名导入字段为「原名_导入」，新建定义。
   * - 不存在：直接新建定义。
   */
  private async resolveCustomFieldDefs(
    db: MaterialDb,
    importedDefs: CustomField[]
  ): Promise<Map<string, string>> {
    // 导入字段名 → 最终使用的字段 ID
    const fieldIdMap = new Map<string, string>();
    if (!importedDefs || importedDefs.length === 0) {
      return fieldIdMap;
    }

    const existingDefs: CustomField[] = await db.listCustomFields();
    // 现有定义按名称索引
    const existingByName = new Map<string, CustomField>();
    for (const def of existingDefs) {
      existingByName.set(def.name, def);
    }

    let maxOrder: number = existingDefs.length > 0
      ? Math.max(...existingDefs.map((d: CustomField) => d.order))
      : -1;

    for (const imported of importedDefs) {
      const existing = existingByName.get(imported.name);
      if (existing) {
        if (existing.type === imported.type) {
          // 同名同类型：保留现有，映射到现有 ID
          fieldIdMap.set(imported.name, existing.id);
        } else {
          // 同名不同类型：重命名导入字段为「原名_导入」
          const renamedName = `${imported.name}_导入`;
          const newId = generateCustomFieldId();
          maxOrder++;
          const newDef: CustomField = {
            id: newId,
            name: renamedName,
            type: imported.type,
            options: imported.options,
            order: maxOrder,
            createdAt: todayStr()
          };
          await db.insertCustomField(newDef);
          // 映射：导入物资中原字段名 → 新定义 ID
          fieldIdMap.set(imported.name, newId);
          // 更新索引，防止后续导入的字段与被重命名的字段再冲突
          existingByName.set(renamedName, newDef);
        }
      } else {
        // 不存在：新建定义
        const newId = generateCustomFieldId();
        maxOrder++;
        const newDef: CustomField = {
          id: newId,
          name: imported.name,
          type: imported.type,
          options: imported.options,
          order: maxOrder,
          createdAt: todayStr()
        };
        await db.insertCustomField(newDef);
        fieldIdMap.set(imported.name, newId);
        existingByName.set(imported.name, newDef);
      }
    }

    return fieldIdMap;
  }

  /**
   * 将导入的 Material 映射为可写入数据库的对象：
   * - 不保留原 id（由数据库自增或覆盖时保留现有 id）
   * - customFields 按字段名映射到现有定义 ID
   */
  private mapImportedMaterial(m: Material, fieldIdMap: Map<string, string>): Material {
    // 映射自定义字段：导入数据中 key 是字段名，需转为字段 ID
    let mappedCustomFields: Record<string, string> | undefined = undefined;
    if (m.customFields) {
      mappedCustomFields = {};
      for (const key of Object.keys(m.customFields)) {
        const targetId = fieldIdMap.get(key);
        if (targetId) {
          mappedCustomFields[targetId] = m.customFields[key];
        } else {
          // 字段名不在映射表中（可能备份中无对应定义），保留原 key
          mappedCustomFields[key] = m.customFields[key];
        }
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
