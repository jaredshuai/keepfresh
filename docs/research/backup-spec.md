# 鸿蒙数据备份与导出规范 — 研究结论

> 研究 ticket #2 · 2026-08-20 · 认领与产出：main 会话（原代理被终止，本会话接手补完）

## 结论摘要

鸿蒙没有"把 RelationalStore 数据库文件拷走"的推荐做法。KeepFresh 备份功能的可行方案是 **业务层 JSON 序列化 + DocumentViewPicker（文件选择器）让用户自选存放位置**：

- **导出**：`MaterialDb.listAll()` 读出全量 → 序列化为 JSON（含 schema 版本、自定义字段定义、设置项）→ `DocumentViewPicker.save()` 获取用户选择的保存位置 URI → `fs` 写入。
- **导入**：`DocumentViewPicker.select()` 获取用户选择的文件 URI → `fs` 读取 → `JSON.parse` → 按冲突策略写入数据库。
- **免权限**：Picker 由用户通过系统 UI 授权访问公共目录，应用**无需声明任何文件权限**。

## 事实明细（来源见文末）

### 1. RelationalStore 是否有官方导出/备份 API

- RelationalStore（`@kit.ArkData`）提供的是 CRUD 与事务 API，**没有**"导出数据库文件/生成备份"的一体化 API。
- 系统层面存在**应用数据备份恢复框架**（用于设备升级、系统云备份等场景），但它面向系统级备份与恢复流程，**不适用**"应用内导出文件给用户自存/换机手动导入"的产品需求。
- 因此"读出记录 → 序列化"是应用内导出功能的规范做法。

### 2. 导出文件的推荐存放位置

| 方案 | 说明 | 结论 |
|---|---|---|
| 应用沙箱目录（`context.filesDir` 等） | 免权限但用户取不出文件，导出无意义 | ✗ |
| 公共目录直接写（如 `Documents`） | 需 `ohos.permission.WRITE_MEDIA` 等权限，与"免权限"原则冲突 | ✗ |
| **DocumentViewPicker.save()** | 用户通过系统弹窗选择保存位置（文档/下载/网盘等），系统返回 URI 后应用写入；**免权限**，由用户授予临时访问资格 | ✓ **推荐** |

`DocumentViewPicker.save()` 关键参数：`newFileNames`（新文件名）、`fileSuffixChoices`（可选后缀列表，如 `['.json']`）、`defaultFilePathUri`；返回 `Promise<string>`（保存文件 URI）。拿到 URI 后用 `fs.open()` / `fs.write()` 写入内容。

### 3. 导入回读的推荐路径

- `DocumentViewPicker.select()`：参数 `maxSelectNumber`、`fileSuffixFilters`（如 `['.json']`）；返回 `Promise<Array<string>>`（所选文件 URI 数组）。
- 拿到 URI → `fs.open()` → 读文本 → `JSON.parse()` → 校验 schema 版本 → 写入数据库。
- 导入与现有数据的冲突策略（覆盖/合并/询问）属于**产品决策**，由「备份方案定稿」ticket（#6）定夺，本研究不越权。

### 4. JSON 格式草案（供 #6 参考）

```jsonc
{
  "schemaVersion": 1,
  "exportedAt": "2026-08-20T00:00:00+08:00",
  "settings": { "nearExpiryDays": 7, "reminderEnabled": true, "reminderHour": 8, "reminderMinute": 0 },
  "customFields": [ /* 自定义字段定义（名称/类型/枚举选项） */ ],
  "materials": [ /* Material 全量字段 */ ]
}
```

要点：`schemaVersion` 必须保留（未来字段演进可迁移）；导出含设置与自定义字段定义，保证换机后完整还原。

### 5. 未查证事项（如实标注）

- 官方文档站为 SPA，未能直接抓取 `js-apis-file-picker` 正文逐字核对 `save()`/`select()` 全部参数——以上签名来自官方文档站标题/片段 + 多篇实践文章交叉印证，API 24 下应再在真机验证一次。
- 应用数据备份恢复框架的细节未展开（与本次需求无关，仅确认其存在且不适用）。

## 落地建议（供 #6 备份方案定稿使用）

1. 导出：读全量 → JSON（含 `schemaVersion`/设置/自定义字段定义/物资）→ `DocumentViewPicker.save()` → `fs` 写入。
2. 导入：`DocumentViewPicker.select()`（过滤 `.json`）→ 读 → 解析 → 校验 schema → 冲突策略由 #6 定 → 写入。
3. 全程无需文件权限；`Picker` 是 HarmonyOS 文件访问的"正确姿势"。
4. 建议真机验证一次 `save()` 对 `fileSuffixChoices` 的处理（避免文件名不带后缀）。

## 来源

- 华为官方：@ohos.file.picker（选择器）API 参考 `developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-file-picker`（DocumentViewPicker 的 select/save、免权限、用户授权机制）
- 华为官方：Core File Kit 文档（文件选择器体系、应用沙箱与公共目录访问规则）
- 多篇 HarmonyOS 实践文章（CSDN/掘金，2024-2025）：Picker 免权限机制、save 后配合 fs 写入、select 后配合 fs 读取的完整链路
- 未查证：官方文档正文逐字核对（SPA 无法抓取）、备份恢复框架细节
