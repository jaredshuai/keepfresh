# 施工任务：自定义字段功能（KeepFresh）

## 你的角色

你是 HarmonyOS（ArkTS/ArkUI）开发工程师。在仓库 `keepfresh` 的现有代码上实现「自定义字段」功能。**只写本文件指定的内容，不要顺手重构其他代码。**

## 先读（动手前必读）

1. `CONTEXT.md` — 领域词汇表（自定义字段术语的定义必须沿用）
2. `docs/adr/0001-on-device-ai-only.md` — 硬约束：全部端侧
3. 现有代码：`entry/src/main/ets/` 下的 `model/Material.ets`、`db/MaterialDb.ets`、`pages/AddItem.ets`、`pages/ItemDetail.ets`、`pages/Index.ets`（注意：用户可能已在 main 上新增了 Settings 页，动手前先 `ls pages/` 确认现状）

## 已定产品决策（不可更改）

- 字段类型**四类**：文本 / 数字 / 日期 / 单选枚举（每个枚举字段自带选项列表定义）
- 存储：**JSON 列**（物资表加 `customFields TEXT` 列存值；字段定义单独存）——随时加字段不改表结构
- 字段定义管理：**设置页 → "自定义字段管理"**（集中创建/编辑/删除字段；枚举字段在此维护选项）
- AddItem 表单和 ItemDetail 详情页**自动渲染所有已定义字段**（按定义顺序）
- 删除字段定义时：已存物资里的该字段值保留在 JSON 中但不再渲染（不主动清理）

## 实现要求

1. **字段定义模型**：新建 `model/CustomField.ets`：`{ id, name, type: 'text'|'number'|'date'|'enum', options?: string[], order: number, createdAt }`。字段定义存 preferences 或独立表（推荐独立表 `custom_field_defs`，或 preferences 存 JSON 数组——两者选一并说明理由）。
2. **物资侧存储**：`Material` 增加 `customFields: Record<string, string>`（key=字段定义 id，value=字符串化值；日期存 YYYY-MM-DD，数字存字符串由渲染层解析）。DB 加 `custom_fields TEXT` 列（兼容处理同扫码任务的说明）。
3. **管理页**：设置页新增"自定义字段"入口 → 管理页支持：新建字段（名称+类型；枚举需编选项，至少 2 个）、编辑（名称/选项；**不允许改类型**）、删除（确认弹窗提示"已有数据中的该字段值将保留但不再显示"）、排序（上下移即可，不做拖拽）。
4. **表单渲染**：AddItem 页在备注字段之前/之后（你判断合理位置）自动渲染全部已定义字段：文本→TextInput、数字→NumberInput、日期→DatePickerDialog、枚举→chips 单选。编辑物资时回填已有值。
5. **详情渲染**：ItemDetail 页信息卡中追加已定义字段的展示行（仅当有值时显示）。
6. **校验**：字段名非空且不重复；枚举选项至少 2 个且不重复；数字字段输入校验。
7. **中文 UI**，沿用现有视觉风格。

## 验收标准

- 设置页可创建四类字段各一个 → AddItem 自动出现对应输入控件 → 保存物资 → 详情页正确显示这些值
- 编辑字段（改名/加选项）后历史数据显示正常；删除字段后表单/详情不再显示该字段，但导出 JSON 中数据仍在
- 枚举字段改选项后，历史值若不在新选项中，表单显示为空但 JSON 原值保留

## 交付

- 改动/新增的文件清单 + 关键实现说明
- "模拟器可验证 / 需真机验证"清单
- 编译需通过（若无法编译，说明原因）
