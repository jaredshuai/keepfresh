/**
 * 条码扫码与物资匹配服务：
 * 通过 ScanKit 唤起扫码页面，优先匹配历史录入数据，其次匹配内置常见商品预设，最后回退为纯条码。
 */
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { MaterialDb } from '../db/MaterialDb';
import { findPresetBarcode, BarcodeProductInfo } from '../model/BarcodeProduct';
import { Material } from '../model/Material';

const DOMAIN: number = 0x0000;
const TAG: string = 'ScanService';

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
  let barcodeValue: string = '';
  try {
    const options: scanBarcode.ScanOptions = {
      scanTypes: [scanCore.ScanType.ALL],
      enableMultiMode: false,
      enableAlbum: true
    };
    const result: scanBarcode.ScanResult = await scanBarcode.startScanForResult(context, options);
    if (result && result.originalValue) {
      barcodeValue = result.originalValue.trim();
    }
  } catch (err) {
    const e: BusinessError = err as BusinessError;
    hilog.info(DOMAIN, TAG, 'startScanForResult cancelled or ended, code: %{public}d, msg: %{public}s', e.code, e.message);
    return undefined;
  }

  if (!barcodeValue) {
    return undefined;
  }

  // 1. 尝试查询历史记录
  try {
    const historyItem: Material | undefined = await db.getByBarcode(barcodeValue);
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
  const preset: BarcodeProductInfo | undefined = findPresetBarcode(barcodeValue);
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
