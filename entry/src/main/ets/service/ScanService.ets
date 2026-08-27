/**
 * 扫码快填服务：
 * ScanKit 默认界面扫码（免相机权限）→ 按条形码查询历史入库记录 → 生成搜索建议列表。
 * 建议列表只来自历史入库记录；无历史时由调用方走空表单 + 仅记录条码。
 */
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { MaterialDb } from '../db/MaterialDb';
import { Material } from '../model/Material';

const DOMAIN: number = 0x0000;
const TAG: string = 'ScanService';

/** ScanKit 错误码：用户取消扫码 */
const ERR_USER_CANCELED: number = 1000500002;

/** 扫码快填结果：条码 + 搜索建议（历史入库记录，按最近入库排序去重） */
export interface ScanFillResult {
  ok: boolean;         // false 表示扫码失败（如设备/模拟器不支持）
  barcode: string;
  suggestions: Material[];
}

/**
 * 唤起系统默认扫码 UI。
 * 返回识别到的条码内容；用户取消或未识别到内容返回 undefined；其余异常（如设备/模拟器不支持）返回空串。
 */
async function startScanForBarcode(context: common.UIAbilityContext): Promise<string | undefined> {
  const options: scanBarcode.ScanOptions = {
    scanTypes: [scanCore.ScanType.ALL],
    enableMultiMode: false,
    enableAlbum: true
  };
  try {
    const result: scanBarcode.ScanResult = await scanBarcode.startScanForResult(context, options);
    if (result && result.originalValue) {
      return result.originalValue.trim();
    }
    return undefined;
  } catch (err) {
    const e: BusinessError = err as BusinessError;
    if (e.code === ERR_USER_CANCELED) {
      hilog.info(DOMAIN, TAG, 'scan canceled by user');
      return undefined;
    }
    hilog.error(DOMAIN, TAG, 'startScanForResult failed, code: %{public}d, msg: %{public}s', e.code, e.message);
    return '';
  }
}

/**
 * 扫码快填主流程：扫码 → 按条码查历史入库记录 → 生成搜索建议。
 * 返回 undefined 表示用户取消；ok=false 表示扫码失败；历史查询失败不阻断条码结果（建议置空走手动填写）。
 */
export async function scanForSuggestions(
  context: common.UIAbilityContext,
  db: MaterialDb
): Promise<ScanFillResult | undefined> {
  const barcode: string | undefined = await startScanForBarcode(context);
  if (barcode === undefined) {
    return undefined;
  }
  if (barcode.length === 0) {
    return { ok: false, barcode: '', suggestions: [] };
  }
  let history: Material[] = [];
  try {
    history = await db.findByBarcode(barcode);
  } catch (dbErr) {
    hilog.warn(DOMAIN, TAG, 'query history by barcode failed: %{public}s', JSON.stringify(dbErr));
  }
  return {
    ok: true,
    barcode: barcode,
    suggestions: buildScanSuggestions(history)
  };
}

/**
 * 搜索建议去重：预填字段组合（名称/分类/单位/保质期天数）相同的历史记录只保留最近入库的一条。
 * 入参须已按最近入库倒序。
 */
function buildScanSuggestions(history: Material[]): Material[] {
  const seen: Set<string> = new Set<string>();
  const suggestions: Material[] = [];
  for (let i = 0; i < history.length; i++) {
    const m: Material = history[i];
    const key: string = `${m.name}|${m.category}|${m.unit}|${m.shelfLifeDays}`;
    if (!seen.has(key)) {
      seen.add(key);
      suggestions.push(m);
    }
  }
  return suggestions;
}
