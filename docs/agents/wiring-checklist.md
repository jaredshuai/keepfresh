# 新字段必改清单（Wiring Checklist）

> 从根 CONTEXT.md 外迁（CONTEXT.md 只保留领域词汇表）。
> 新增 Material 字段（或新 DB 表）时**必改**的接线点，漏任何一处即产生断链（背景见 `docs/audit-wiring.md`；规则 1/2/5 由 `npm run wire:check` 机器拦截，其余靠本清单）。

1. `model/Material.ets` 接口字段
2. `db/MaterialDb.ets`：建表 SQL / migrate() ALTER + `toRow` 写入键 + `rowToMaterial` 读取列
3. 写入方：`pages/AddItem.ets` 表单（含编辑回填 + 扫码预填 `applyScanSuggestion`）
4. 渲染消费：`pages/Index.ets` 卡片 / `pages/ItemDetail.ets` 信息行
5. 派生计算：`service/ExpiryService.ets`（若参与分级/排序/统计）
6. 提醒链路：`service/ReminderService.ets`（若影响提醒口径）
7. 备份闭环：`service/BackupService.ets` 导出序列化（注意 JSON.stringify 丢弃 undefined 可选字段）**+** 导入还原 `mapImportedMaterial`
8. 测试：`test/PantryLogic.test.ts` 或对应测试文件
9. 新表另需：管理页 CRUD + 数据消费方改走查询 API（禁硬编码 DEFAULT_* 数据源，wire-guard 规则 3 拦截）
