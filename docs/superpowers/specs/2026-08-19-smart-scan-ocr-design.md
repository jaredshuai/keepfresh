# KeepFresh 智能扫码与 OCR 日期录入技术设计方案

- **日期**：2026-08-19
- **状态**：已评审 (Approved)
- **目标工程**：KeepFresh 物资保质期管理（HarmonyOS 原生应用）

---

## 1. 概述与设计目标

### 1.1 背景与痛点
当前 KeepFresh 在录入新物资（`AddItem.ets`）时，所有字段（商品名称、分类、生产日期、保质期天数等）均依赖用户纯手动输入，录入流程长且容易输错。

### 1.2 目标
1. **条码扫码识别（`ScanKit`）**：支持一键扫描商品条形码（69码/EAN），通过本地历史记录与内置常用商品字典自动补全商品名称、分类、单位及默认保质期。
2. **包装日期 OCR 识别（`CoreVisionKit` + `DateTextParser`）**：支持拍摄或相册选择食品/日化包装喷码，利用系统级 OCR 与智能正则解析引擎，自动抽取生产日期与保质期天数并自动填入表单。
3. **极简操作交互**：在录入页提供醒目的操作胶囊，识别后自动完成状态填充与实时预览计算，并提供明确的反馈提示。

---

## 2. 整体架构与模块划分

```
entry/src/main/ets/
├── common/
│   └── DateUtils.ets              # 基础日期格式化与计算工具
├── model/
│   ├── Material.ets               # 物资实体（扩展 barcode 字段）
│   └── BarcodeProduct.ets         # 条码实体与内置预置商品字典
├── db/
│   └── MaterialDb.ets             # 数据库层（支持 barcode 字段与按条码查询历史）
├── service/
│   ├── DateTextParser.ets         # 纯逻辑：从 OCR 文本中智能抽取日期与保质期
│   ├── ScanService.ets            # 扫码服务（封装 @kit.ScanKit 与条码匹配逻辑）
│   └── OcrService.ets             # 视觉文字识别服务（封装 @kit.CoreVisionKit 与图片选择）
└── pages/
    └── AddItem.ets                # 录入/编辑页面（集成扫码与 OCR 快捷入口及自动填充）
```

---

## 3. 详细设计规范

### 3.1 数据模型与数据库扩展

#### `Material.ets`
物资模型增加条形码可选字段：
```typescript
export interface Material {
  id?: number;
  name: string;
  category: string;
  quantity: number;
  unit: string;
  productionDate: string;  // YYYY-MM-DD
  shelfLifeDays: number;   // 保质期天数
  note?: string;
  barcode?: string;        // 69码/EAN等商品条形码
  createdAt?: string;
}
```

#### `MaterialDb.ets`
- SQLite 表结构更新：在 `materials` 表增加 `barcode TEXT` 字段。
- 新增查询接口：`getByBarcode(barcode: string): Promise<Material | undefined>`，按最新修改时间降序返回历史录入记录。

#### `BarcodeProduct.ets`
内置常用条码字典（开箱即用体验）：
```typescript
export interface BarcodeProductInfo {
  barcode: string;
  name: string;
  category: string;
  unit: string;
  defaultShelfLifeDays: number;
}
```
预置包含主流牛奶、饮料、调味品、常备日化等条码映射。

---

### 3.2 智能日期文本解析引擎 (`DateTextParser.ets`)

纯函数解析器，接受多行 OCR 识别文本，返回解析结果对象：
```typescript
export interface ParsedDateResult {
  productionDate?: string;     // YYYY-MM-DD
  shelfLifeDays?: number;      // 天数
  expiryDate?: string;          // YYYY-MM-DD
  rawMatchedText: string[];
}
```

#### 正则匹配与转换策略：
1. **日期格式匹配**：
   - `YYYY[-/.年]MM[-/.月]DD[日]?`（如 `2026-05-12`、`2026.05.12`、`2026/05/12`、`2026年05月12日`）
   - 纯紧凑格式：`YYYYMMDD`（如 `20260512`）
   - 前缀关键词识别：`生产日期`、`PD`、`MFG`、`PROD`
2. **到期日与保质期匹配**：
   - 到期日前缀：`保质期至`、`到期日`、`EXP`、`USE BY`、`BEST BEFORE`
   - 保质期时长匹配：
     - `\d+\s*(天|日|days?)` → 直接转换为主天数
     - `\d+\s*(个?月|months?)` → `月数 * 30`
     - `\d+\s*(年|years?)` → `年数 * 365`
3. **计算推导逻辑**：
   - 若匹配到生产日期 + 保质期时长 → 自动计算到期日。
   - 若匹配到生产日期 + 到期日 → 自动反算保质期天数 `diffDays(productionDate, expiryDate)`。
   - 若仅匹配到到期日 → 默认将生产日期设为今天，天数设为距到期日的差值（若为正数）。

---

### 3.3 扫码服务 (`ScanService.ets`)

1. 调用 `@kit.ScanKit` 的标准扫码 API：
   - 优先调用 `scanBarcode.startScanForResult(context, options)`。
2. 结果处理流水线：
   ```
   扫码成功返回 Barcode 字符串
          ↓
   查询 MaterialDb.getByBarcode(barcode)
          ↓ (若存在历史)
   直接填充历史数据（name, category, unit, shelfLifeDays）
          ↓ (若无历史)
   查询 BarcodeProduct.queryPreset(barcode)
          ↓ (若命中预设)
   填充预设数据
          ↓ (若未命中)
   将 barcode 填入表单，Toast 提示：“已识别条形码，请完善商品信息”
   ```

---

### 3.4 OCR 文字识别服务 (`OcrService.ets`)

1. **图片来源**：
   - 支持从系统相册选择特写照片（使用 `photoAccessHelper.PhotoViewPicker`），或通过系统相机拍摄。
2. **文字识别**：
   - 将图片 PixelMap 或 URI 传入 `@kit.CoreVisionKit` 的文字识别接口（`textRecognition`）进行离线/本地快速识别。
   - 获取文本行集合。
3. **提取与填入**：
   - 调用 `DateTextParser.parse(textLines)`。
   - 若成功提取出日期/保质期，更新表单中的 `productionDate` 与 `shelfLifeDays`，并展示 Toast：“已自动识别生产日期与保质期”。
   - 若未识别到有效日期，Toast 提示：“未能提取到日期，请确认照片清晰或手动输入”。

---

### 3.5 界面交互与视觉设计 (`AddItem.ets`)

在 `AddItem.ets` 页面标题下方/表单顶部，新增一行快捷识别胶囊栏：
- **【📷 扫条码】**：绿色圆角图标胶囊按钮，点击触发扫码。
- **【🔍 拍日期 OCR】**：浅绿背景圆角图标胶囊按钮，点击触发拍照/选图识别。
- 表单各输入框支持识别后自动实时刷新与双向绑定，底部实时预览计算卡片同步更新。

---

## 4. 容错与降级机制

1. **设备权限/无硬件降级**：
   - 在不支持相机扫码的模拟器或用户拒绝权限时，友好捕获异常并给出提示，不影响用户纯手动输入。
2. **OCR 误识别过滤**：
   - 校验识别出的年份（限制在合理区间，如 2020~2035），防止将批号、条码号误当成日期。
3. **离线可用**：
   - 内置预置条码库与纯本地正则规则引擎，无需网络连接即可完全离线运行。

---

## 5. 验证与测试计划

1. **单元测试 (`DateTextParser`)**：
   - 覆盖标准格式（`2026-08-19`、`2026/08/19`、`2026年8月19日`、`20260819`）。
   - 覆盖带有前后文修饰词（`生产日期: 2026-01-01 保质期: 12个月`）。
   - 覆盖中英文保质期到期日（`EXP: 2027/01/01`、`保质期至2026.12.31`）。
2. **条码匹配测试**：
   - 验证内置预设条码匹配成功率。
   - 验证历史录入条码再次扫描时的属性回填。
3. **UI 与端到端录入流程验证**：
   - 验证扫码后自动填充表单各项属性及 Toast 提示。
   - 验证 OCR 提取日期后联动到期日预览。
