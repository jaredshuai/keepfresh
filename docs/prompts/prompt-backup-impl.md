# 施工任务：备份导出/导入功能（KeepFresh，ticket #6 已定稿）

## 你的角色

你是 HarmonyOS（ArkTS/ArkUI）开发工程师。在仓库 `keepfresh` 现有代码上实现备份导出/导入功能。**只写本文件指定的内容，不要顺手重构其他代码。**

## 先读（动手前必读）

1. `docs/research/backup-spec.md` — 备份研究结论（Picker API、fileIo 链路、免权限机制都在里面，**严格按它的技术要点写**）
2. `docs/adr/0001-on-device-ai-only.md`、`CONTEXT.md`
3. 现有代码：`entry/src/main/ets/db/MaterialDb.ets`（含 materials/custom_field_defs 表 CRUD）、`service/SettingsService.ets`（阈值持久化）、`service/ReminderService.ets`（提醒设置持久化）、`pages/Settings.ets`（备份入口现为 Toast 占位，你要接真实实现）、`model/Material.ets`、`model/CustomField.ets`

## 已定稿决策（ticket #6 Resolution，不可更改）

1. **导出范围**：materials 全量 + customFieldDefs 全量 + settings（nearExpiryDays + reminder 的 enabled/hour/minute），`schemaVersion: 1`
2. **导出文件**：`DocumentViewPicker.save()`，`newFileNames: ['keepfresh_backup_YYYYMMDD.json']`（日期用当天）、`fileSuffixChoices: ['JSON 备份|.json']`
3. **导入冲突**：默认增量合并——业务键「名称+到期日」判定冲突（同名同到期日视为同一物资），冲突按导入数据覆盖、不冲突新增；导入前弹窗预览「将新增 X 件 / 覆盖 Y 件」；另提供「清空后导入」选项
4. **ID 处理**：导入不保留原 id，让数据库重新自增分配
5. **版本兼容**：schemaVersion > 1 拒绝导入 Toast「备份文件版本过新，请升级应用」；≤1 正常导入
6. **字段定义冲突**：同名同类型保留现有定义，导入物资 customFields 按字段名映射到现有定义 ID；同名不同类型重命名导入字段（`原名_导入`）
7. **设置导入**：settings 导入后写入 SettingsService/ReminderService 持久化（nearExpiryDays 同步 ExpiryService 缓存，reminder 触发 syncDailyReminder）

## 实现要求

1. 新建 `service/BackupService.ets`（单例，与 MaterialDb 解耦）：
   - `exportBackup(context)`：读 materials + customFieldDefs + settings → 组 JSON → `DocumentViewPicker.save()` 拿 URI（先存成员变量）→ `fileIo.openSync(uri, READ_WRITE)` → `writeSync` → `closeSync`；成功 Toast「已导出到所选位置」
   - `importBackup(context)`：`DocumentViewPicker.select()`（`fileSuffixFilters: ['KeepFresh 备份|.json']`、`maxSelectNumber: 1`）→ `openSync(READ_ONLY)` → 读 → `JSON.parse` → 校验 schemaVersion → 返回解析结果供预览
   - `executeImport(data, mode: 'merge' | 'overwrite')`：按冲突策略执行（merge=增量合并、overwrite=清空后导入），事务内 batchInsert
   - fileIo 全程 `try...finally` 保证 closeSync
2. 改 `pages/Settings.ets`：备份区块两个 Toast 占位改为真实调用——导出直接调 `exportBackup`；导入先 `importBackup` 解析 → 弹窗预览（新增/覆盖数 + 「清空后导入」选项）→ 确认调 `executeImport` → 成功 Toast「已导入 X 件物资」
3. JSON schema（导出格式）：
```jsonc
{
  "schemaVersion": 1,
  "exportedAt": "ISO8601 时间",
  "settings": { "nearExpiryDays": 7, "reminderEnabled": true, "reminderHour": 8, "reminderMinute": 0 },
  "customFields": [ /* CustomField 定义数组 */ ],
  "materials": [ /* Material 数组，不含 id 或 id 仅作参考 */ ]
}
```
4. 导入校验：非 JSON / 缺 schemaVersion / 缺 materials 字段 → Toast「备份文件格式不正确」
5. 中文 UI/文案，沿用现有风格

## 验收标准

- 导出：设置页点导出 → 选位置 → 所选目录出现 `keepfresh_backup_YYYYMMDD.json`，内容含 materials/customFields/settings
- 导入合并：删掉几件物资后导入 → 冲突预览正确显示新增/覆盖数 → 确认后物资恢复；自定义字段定义同步恢复
- 导入清空后导入：选该模式 → 现有物资清空 → 导入物资写入
- 版本拒绝：手改 schemaVersion 为 2 的备份文件 → 导入拒绝并提示
- 设置导入：备份文件改 nearExpiryDays 为 3 → 导入后设置页阈值变 3，首页分级按 3 天重算
- 杀进程重进：导入的设置持久化保留
- 模拟器可验证 UI 流程；Picker 真机验证文件读写

## 交付

- 改动/新增文件清单 + 关键实现说明（特别是冲突合并与字段映射逻辑）
- "模拟器可验证 / 需真机验证"清单
- 编译需通过
