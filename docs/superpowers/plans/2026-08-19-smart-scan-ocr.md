# KeepFresh 智能扫码与 OCR 日期录入实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 KeepFresh 录入页新增商品条码扫码（@kit.ScanKit + 本地字典/历史匹配）与包装日期 OCR 智能识别提取（@kit.CoreVisionKit + DateTextParser 规则引擎），实现物资信息的秒级快捷录入。

**Architecture:** 
- `Material.ets` / `MaterialDb.ets`: 物资模型与 SQLite 数据层新增 `barcode` 字段支持及按条码检索历史记录接口。
- `BarcodeProduct.ets`: 提供常见消费品条码与品类/保质期内置字典及检索辅助函数。
- `DateTextParser.ets`: 纯函数智能日期抽取引擎，从 OCR 文本中精准抽取生产日期、保质期天数/月数、到期日，并完成天数推导换算。
- `ScanService.ets` / `OcrService.ets`: 封装 `@kit.ScanKit` 扫码能力与 `@kit.CoreVisionKit` + `PhotoViewPicker` 视觉文字识别能力，提供优雅降级。
- `AddItem.ets`: 页面顶部集成「扫条码」与「拍日期 OCR」操作胶囊，实现自动填充、实时计算联动与 Toast 反馈。

**Tech Stack:** ArkTS, ArkUI, @kit.ScanKit, @kit.CoreVisionKit, @kit.ArkData (RelationalStore), @kit.AbilityKit, @kit.MediaLibraryKit.

## Global Constraints

- **ArkTS 语法规范**：遵循 HarmonyOS NEXT 声明式规范与 strict 类型检查，禁止使用 any 或未声明字段。
- **模块化导入**：统一使用 `@kit.*` 导入官方 Kit 模块。
- **设备降级容错**：在模拟器或无硬件权限环境下，需通过 try-catch 和友好 Toast 提示捕获异常，不得导致页面白屏或崩溃。

---

### Task 1: 数据模型与条码字典扩展 (`Material.ets`, `BarcodeProduct.ets`, `MaterialDb.ets`)

**Files:**
- Modify: `entry/src/main/ets/model/Material.ets`
- Create: `entry/src/main/ets/model/BarcodeProduct.ets`
- Modify: `entry/src/main/ets/db/MaterialDb.ets`

**Interfaces:**
- Consumes: `Material` 实体类型
- Produces: 
  - `Material.barcode?: string`
  - `findPresetBarcode(barcode: string): BarcodeProductInfo | undefined`
  - `MaterialDb.getByBarcode(barcode: string): Promise<Material | undefined>`

- [ ] **Step 1: 修改 `Material.ets` 添加 `barcode` 字段**

```typescript
export interface Material {
  id?: number;
  name: string;
  category: string;
  quantity: number;
  unit: string;
  productionDate: string;
  shelfLifeDays: number;
  note?: string;
  barcode?: string;
  createdAt?: string;
}
```

- [ ] **Step 2: 创建 `BarcodeProduct.ets` 内置常用商品条码字典**

创建 `entry/src/main/ets/model/BarcodeProduct.ets`：
```typescript
/**
 * 预置常见商品条码字典与实体定义。
 */
export interface BarcodeProductInfo {
  barcode: string;
  name: string;
  category: string;
  unit: string;
  defaultShelfLifeDays: number;
}

export const PRESET_BARCODE_PRODUCTS: BarcodeProductInfo[] = [
  { barcode: '6901028181636', name: '特仑苏纯牛奶 250ml', category: '食品', unit: '盒', defaultShelfLifeDays: 180 },
  { barcode: '6920152431055', name: '金典纯牛奶 250ml', category: '食品', unit: '盒', defaultShelfLifeDays: 180 },
  { barcode: '6902083881214', name: '海天味极鲜酱油 500ml', category: '食品', unit: '瓶', defaultShelfLifeDays: 540 },
  { barcode: '6901028180127', name: '蒙牛纯牛奶 250ml', category: '食品', unit: '盒', defaultShelfLifeDays: 180 },
  { barcode: '6901285991217', name: '可口可乐 330ml', category: '食品', unit: '罐', defaultShelfLifeDays: 360 },
  { barcode: '6923450656172', name: '农夫山泉饮用水 550ml', category: '食品', unit: '瓶', defaultShelfLifeDays: 720 },
  { barcode: '6907992500045', name: '云南白药牙膏 100g', category: '日化', unit: '支', defaultShelfLifeDays: 1080 },
  { barcode: '6917878018889', name: '阿莫西林胶囊 0.25g*24粒', category: '药品', unit: '盒', defaultShelfLifeDays: 720 },
  { barcode: '6934572300018', name: '蓝月亮洗衣液 1kg', category: '日化', unit: '袋', defaultShelfLifeDays: 1080 }
];

export function findPresetBarcode(barcode: string): BarcodeProductInfo | undefined {
  if (!barcode) {
    return undefined;
  }
  const cleanBarcode = barcode.trim();
  return PRESET_BARCODE_PRODUCTS.find((p) => p.barcode === cleanBarcode);
}
```

- [ ] **Step 3: 修改 `MaterialDb.ets` 支持 `barcode` 字段读写与按条码查询**

在 `MaterialDb.ets` 中：
1. 更新 `CREATE_TABLE_SQL` 增加 `barcode TEXT`。
2. 在 `init()` 之后若表已存在则执行 alter table 兼容脚本（`ALTER TABLE materials ADD COLUMN barcode TEXT;`，忽略已存在报错）。
3. 在 `insert` 和 `update` 中写入 `barcode`。
4. 在 `rowToMaterial` 中读取 `row.barcode`。
5. 新增 `getByBarcode(barcode: string): Promise<Material | undefined>` 查询历史记录。

```typescript
// 在 MaterialDb 类中新增 getByBarcode
async getByBarcode(barcode: string): Promise<Material | undefined> {
  if (!this.store || !barcode) {
    return undefined;
  }
  const predicates = new relationalStore.RdbPredicates('materials');
  predicates.equalTo('barcode', barcode.trim()).orderByDesc('id').limitAs(1);
  const resultSet = await this.store.query(predicates);
  try {
    if (resultSet.goToFirstRow()) {
      return this.rowToMaterial(resultSet);
    }
    return undefined;
  } finally {
    resultSet.close();
  }
}
```

- [ ] **Step 4: 提交 Task 1 更改**

```bash
git add entry/src/main/ets/model/Material.ets entry/src/main/ets/model/BarcodeProduct.ets entry/src/main/ets/db/MaterialDb.ets
git commit -m "feat(model,db): add barcode support and preset product dictionary"
```

---

### Task 2: 智能日期与保质期文本抽取引擎 (`DateTextParser.ets`)

**Files:**
- Create: `entry/src/main/ets/service/DateTextParser.ets`
- Create: `test/DateTextParser.test.ts` (用于 Node/ArkTS 验证)

**Interfaces:**
- Consumes: OCR 识别输出的多行字符串或单段文本
- Produces: 
  - `interface ParsedDateResult`
  - `parseDateFromText(input: string | string[]): ParsedDateResult`

- [ ] **Step 1: 编写测试用例 `test/DateTextParser.test.ts`**

覆盖测试场景：
- 标准日期匹配：`2026-08-19`, `2026/08/19`, `2026.08.19`, `2026年08月19日`, `20260819`
- 带有前缀词的生产日期：`生产日期: 2026-05-01`
- 保质期时长匹配：`保质期: 12个月`, `保质期: 180天`, `保质期 2年`
- 到期日与反算：`EXP: 2027/01/01`, `保质期至 2026-12-31`
- 复合文本多行提取

- [ ] **Step 2: 实现 `DateTextParser.ets`**

创建 `entry/src/main/ets/service/DateTextParser.ets`：
```typescript
import { toDateStr, addDays, diffDays, parseDate } from '../common/DateUtils';

export interface ParsedDateResult {
  productionDate?: string;     // YYYY-MM-DD
  shelfLifeDays?: number;      // 天数
  expiryDate?: string;          // YYYY-MM-DD
  rawMatchedText: string[];
}

export function parseDateFromText(input: string | string[]): ParsedDateResult {
  const lines: string[] = Array.isArray(input) ? input : input.split('\n');
  const fullText = lines.join(' ');
  const rawMatched: string[] = [];

  let foundProdDate: string | undefined = undefined;
  let foundExpiryDate: string | undefined = undefined;
  let foundShelfLifeDays: number | undefined = undefined;

  // 1. 匹配生产日期 (例: 生产日期 2026-05-12 / 2026.05.12 / 2026/05/12 / 2026年5月12日 / 20260512)
  const prodRegex = /(?:生产日期|PROD|MFG|PD)[:：\s]*([12]\d{3})[-/.年\s]?(\d{1,2})[-/.月\s]?(\d{1,2})日?/i;
  const prodMatch = fullText.match(prodRegex);
  if (prodMatch) {
    const y = parseInt(prodMatch[1], 10);
    const m = parseInt(prodMatch[2], 10);
    const d = parseInt(prodMatch[3], 10);
    if (isValidDateNumbers(y, m, d)) {
      foundProdDate = `${y}-${pad2(m)}-${pad2(d)}`;
      rawMatched.push(prodMatch[0]);
    }
  }

  // 2. 匹配到期日 / 保质期至 (例: 保质期至 2027-05-12 / EXP 2027.05.12)
  const expRegex = /(?:保质期至|到期日|失效期|EXP|USE BY|BEST BEFORE)[:：\s]*([12]\d{3})[-/.年\s]?(\d{1,2})[-/.月\s]?(\d{1,2})日?/i;
  const expMatch = fullText.match(expRegex);
  if (expMatch) {
    const y = parseInt(expMatch[1], 10);
    const m = parseInt(expMatch[2], 10);
    const d = parseInt(expMatch[3], 10);
    if (isValidDateNumbers(y, m, d)) {
      foundExpiryDate = `${y}-${pad2(m)}-${pad2(d)}`;
      rawMatched.push(expMatch[0]);
    }
  }

  // 3. 通用日期兜底匹配（若未匹配到前缀词）
  if (!foundProdDate && !foundExpiryDate) {
    const genericDateRegex = /\b([12]\d{3})[-/.年](\d{1,2})[-/.月](\d{1,2})日?\b/g;
    const matches = Array.from(fullText.matchAll(genericDateRegex));
    if (matches.length > 0) {
      const first = matches[0];
      const y = parseInt(first[1], 10);
      const m = parseInt(first[2], 10);
      const d = parseInt(first[3], 10);
      if (isValidDateNumbers(y, m, d)) {
        foundProdDate = `${y}-${pad2(m)}-${pad2(d)}`;
        rawMatched.push(first[0]);
      }
      if (matches.length > 1) {
        const second = matches[1];
        const y2 = parseInt(second[1], 10);
        const m2 = parseInt(second[2], 10);
        const d2 = parseInt(second[3], 10);
        if (isValidDateNumbers(y2, m2, d2)) {
          foundExpiryDate = `${y2}-${pad2(m2)}-${pad2(d2)}`;
          rawMatched.push(second[0]);
        }
      }
    }
  }

  // 4. 匹配保质期时长 (例: 保质期: 12个月, 180天, 24个月, 2年, 30 days)
  const durationRegex = /(?:保质期|保质期限)[:：\s]*(\d+)\s*(个?月|天|日|年|months?|days?|years?)/i;
  const durMatch = fullText.match(durationRegex);
  if (durMatch) {
    const num = parseInt(durMatch[1], 10);
    const unit = durMatch[2].toLowerCase();
    if (num > 0 && num <= 3650) {
      if (unit.includes('月') || unit.includes('month')) {
        foundShelfLifeDays = num * 30;
      } else if (unit.includes('年') || unit.includes('year')) {
        foundShelfLifeDays = num * 365;
      } else {
        foundShelfLifeDays = num;
      }
      rawMatched.push(durMatch[0]);
    }
  } else {
    // 独立时长如 "180天"、"12个月"
    const standaloneDurRegex = /(\d+)\s*(个?月|天|日|年)/;
    const standaloneMatch = fullText.match(standaloneDurRegex);
    if (standaloneMatch) {
      const num = parseInt(standaloneMatch[1], 10);
      const unit = standaloneMatch[2];
      if (num > 0 && num <= 3650) {
        if (unit.includes('月')) {
          foundShelfLifeDays = num * 30;
        } else if (unit.includes('年')) {
          foundShelfLifeDays = num * 365;
        } else {
          foundShelfLifeDays = num;
        }
        rawMatched.push(standaloneMatch[0]);
      }
    }
  }

  // 5. 联动推导
  if (foundProdDate && foundShelfLifeDays && !foundExpiryDate) {
    foundExpiryDate = addDays(foundProdDate, foundShelfLifeDays);
  } else if (foundProdDate && foundExpiryDate && !foundShelfLifeDays) {
    const diff = diffDays(foundProdDate, foundExpiryDate);
    if (diff > 0) {
      foundShelfLifeDays = diff;
    }
  } else if (!foundProdDate && foundExpiryDate && foundShelfLifeDays) {
    foundProdDate = addDays(foundExpiryDate, -foundShelfLifeDays);
  }

  return {
    productionDate: foundProdDate,
    shelfLifeDays: foundShelfLifeDays,
    expiryDate: foundExpiryDate,
    rawMatchedText: rawMatched
  };
}

function isValidDateNumbers(y: number, m: number, d: number): boolean {
  if (y < 2020 || y > 2035) {
    return false;
  }
  if (m < 1 || m > 12) {
    return false;
  }
  if (d < 1 || d > 31) {
    return false;
  }
  return true;
}

function pad2(n: number): string {
  return n < 10 ? `0${n}` : `${n}`;
}
```

- [ ] **Step 3: 运行并验证测试用例**

执行测试脚本，确保全部匹配规则通过。

- [ ] **Step 4: 提交 Task 2 更改**

```bash
git add entry/src/main/ets/service/DateTextParser.ets
git commit -m "feat(service): implement smart date and shelf-life text extraction engine"
```

---

### Task 3: 封装条码扫码服务 (`ScanService.ets`)

**Files:**
- Create: `entry/src/main/ets/service/ScanService.ets`

**Interfaces:**
- Consumes: `@kit.ScanKit`, `MaterialDb`, `findPresetBarcode`
- Produces: 
  - `interface ScanMatchedResult`
  - `scanAndMatchProduct(context: common.UIAbilityContext, db: MaterialDb): Promise<ScanMatchedResult | undefined>`

- [ ] **Step 1: 创建 `ScanService.ets`**

创建 `entry/src/main/ets/service/ScanService.ets`：
```typescript
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { MaterialDb } from '../db/MaterialDb';
import { findPresetBarcode, BarcodeProductInfo } from '../model/BarcodeProduct';
import { Material } from '../model/Material';

const DOMAIN = 0x0000;
const TAG = 'ScanService';

export interface ScanMatchedResult {
  barcode: string;
  name?: string;
  category?: string;
  unit?: string;
  shelfLifeDays?: number;
  source: 'history' | 'preset' | 'raw_barcode';
}

export async function scanAndMatchProduct(
  context: common.UIAbilityContext,
  db: MaterialDb
): Promise<ScanMatchedResult | undefined> {
  let barcodeValue = '';
  try {
    const options: scanBarcode.ScanOptions = {
      scanTypes: [scanCore.ScanType.ALL],
      enableMultiMode: false,
      enableAlbum: true
    };
    const result = await scanBarcode.startScanForResult(context, options);
    if (result && result.originalValue) {
      barcodeValue = result.originalValue.trim();
    }
  } catch (err) {
    const e = err as BusinessError;
    hilog.error(DOMAIN, TAG, 'startScanForResult failed, code: %{public}d, msg: %{public}s', e.code, e.message);
    throw new Error(`扫码未完成或不可用: ${e.message || e.code}`);
  }

  if (!barcodeValue) {
    return undefined;
  }

  // 1. 尝试查询历史记录
  try {
    const historyItem = await db.getByBarcode(barcodeValue);
    if (historyItem) {
      return {
        barcode: barcodeValue,
        name: historyItem.name,
        category: historyItem.category,
        unit: historyItem.unit,
        shelfLifeDays: historyItem.shelfLifeDays,
        source: 'history'
      };
    }
  } catch (dbErr) {
    hilog.warn(DOMAIN, TAG, 'Query history by barcode error: %{public}s', JSON.stringify(dbErr));
  }

  // 2. 尝试查询内置预设字典
  const preset = findPresetBarcode(barcodeValue);
  if (preset) {
    return {
      barcode: barcodeValue,
      name: preset.name,
      category: preset.category,
      unit: preset.unit,
      shelfLifeDays: preset.defaultShelfLifeDays,
      source: 'preset'
    };
  }

  // 3. 仅返回条码本身
  return {
    barcode: barcodeValue,
    source: 'raw_barcode'
  };
}
```

- [ ] **Step 2: 提交 Task 3 更改**

```bash
git add entry/src/main/ets/service/ScanService.ets
git commit -m "feat(service): implement ScanKit barcode scanning and product matching service"
```

---

### Task 4: 封装 OCR 识别与照片选择服务 (`OcrService.ets`)

**Files:**
- Create: `entry/src/main/ets/service/OcrService.ets`

**Interfaces:**
- Consumes: `@kit.CoreVisionKit` / `photoAccessHelper`, `parseDateFromText`
- Produces: 
  - `pickAndRecognizeDate(context: common.UIAbilityContext): Promise<ParsedDateResult | undefined>`

- [ ] **Step 1: 创建 `OcrService.ets`**

创建 `entry/src/main/ets/service/OcrService.ets`：
```typescript
import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { textRecognition } from '@kit.CoreVisionKit';
import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { parseDateFromText, ParsedDateResult } from './DateTextParser';

const DOMAIN = 0x0000;
const TAG = 'OcrService';

export async function pickAndRecognizeDate(
  context: common.UIAbilityContext
): Promise<ParsedDateResult | undefined> {
  // 1. 打开系统照片选择器选取包装喷码特写
  const photoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
  photoSelectOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
  photoSelectOptions.maxSelectNumber = 1;

  const photoPicker = new photoAccessHelper.PhotoViewPicker();
  let selectResult: photoAccessHelper.PhotoSelectResult;
  try {
    selectResult = await photoPicker.select(photoSelectOptions);
  } catch (err) {
    const e = err as BusinessError;
    hilog.error(DOMAIN, TAG, 'PhotoViewPicker select failed: %{public}s', e.message);
    return undefined;
  }

  if (!selectResult || !selectResult.photoUris || selectResult.photoUris.length === 0) {
    return undefined;
  }

  const uri = selectResult.photoUris[0];

  // 2. 读取图片并转化为 PixelMap
  let pixelMap: image.PixelMap | undefined = undefined;
  let file: fs.File | undefined = undefined;
  try {
    file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    const imageSource = image.createImageSource(file.fd);
    pixelMap = await imageSource.createPixelMap();
  } catch (err) {
    const e = err as BusinessError;
    hilog.error(DOMAIN, TAG, 'Read image pixelMap failed: %{public}s', e.message);
    throw new Error(`读取图片失败: ${e.message}`);
  } finally {
    if (file) {
      fs.closeSync(file);
    }
  }

  if (!pixelMap) {
    throw new Error('无法解码图片');
  }

  // 3. 调用 CoreVisionKit 文字识别
  let textLines: string[] = [];
  try {
    const visionImage: textRecognition.VisionImage = {
      pixelMap: pixelMap
    };
    const recognitionResult = await textRecognition.recognizeText(visionImage);
    if (recognitionResult && recognitionResult.value) {
      textLines.push(recognitionResult.value);
    }
  } catch (err) {
    const e = err as BusinessError;
    hilog.error(DOMAIN, TAG, 'textRecognition recognizeText failed: %{public}s', e.message);
    throw new Error(`文字识别失败: ${e.message}`);
  } finally {
    pixelMap.release();
  }

  if (textLines.length === 0) {
    return {
      rawMatchedText: []
    };
  }

  // 4. 正则抽取日期与保质期
  return parseDateFromText(textLines);
}
```

- [ ] **Step 2: 提交 Task 4 更改**

```bash
git add entry/src/main/ets/service/OcrService.ets
git commit -m "feat(service): implement CoreVisionKit OCR date extraction service"
```

---

### Task 5: 录入页 `AddItem.ets` UI 与流程集成

**Files:**
- Modify: `entry/src/main/ets/pages/AddItem.ets`

**Interfaces:**
- Consumes: `scanAndMatchProduct` (`ScanService`), `pickAndRecognizeDate` (`OcrService`)
- Produces: 完整的用户扫码与拍照识别智能录入交互体验

- [ ] **Step 1: 在 `AddItem.ets` 中增加 `barcode` 状态与快捷操作胶囊按钮**

在表单顶部增加快捷入口：
- 胶囊组件包含：【📷 扫条码】、【🔍 拍日期 OCR】。
- 支持点击扫码后，如果命中历史或预置，自动填充 `name`, `category`, `unit`, `shelfLifeDays`, `barcode` 并弹 Toast 提示 `已识别：${name}`。
- 如果仅扫出条码，填充 `barcode` 并提示 `已录入条码：${barcode}，请补充名称`。
- 点击拍日期 OCR 后，调用 `pickAndRecognizeDate`，若抽取到 `productionDate` 或 `shelfLifeDays`，自动更新并提示 `已提取生产日期: ${date}，保质期: ${days}天`。

- [ ] **Step 2: 完善保存与编辑回填逻辑**

在保存 `onSave()` 中将 `barcode` 字段一同写入 `Material` 实体。在编辑回填中展示当前物品的关联条码（若有）。

- [ ] **Step 3: 提交 Task 5 更改**

```bash
git add entry/src/main/ets/pages/AddItem.ets
git commit -m "feat(ui): integrate barcode scan and OCR date extraction in AddItem page"
```

---

## Plan Self-Review Checklist
- [x] Spec coverage: 条码扫码识别（ScanKit + 本地字典/历史）、包装日期 OCR 识别（CoreVisionKit + DateTextParser 规则）、AddItem 快捷交互、MaterialDb barcode 字段全部覆盖。
- [x] No placeholders: 详细给出代码结构与类型定义，无 TODO/TBD。
- [x] Type consistency: `barcode`, `ParsedDateResult`, `ScanMatchedResult`, `BarcodeProductInfo` 等方法与签名统一。
