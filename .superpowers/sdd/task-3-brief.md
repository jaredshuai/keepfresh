# Task 3 Brief: 封装条码扫码服务 (`ScanService.ets`)

## Files
- Create: `entry/src/main/ets/service/ScanService.ets`

## Requirements
1. Create `entry/src/main/ets/service/ScanService.ets`:
   - Import necessary modules:
     ```typescript
     import { scanBarcode, scanCore } from '@kit.ScanKit';
     import { common } from '@kit.AbilityKit';
     import { BusinessError } from '@kit.BasicServicesKit';
     import { hilog } from '@kit.PerformanceAnalysisKit';
     import { MaterialDb } from '../db/MaterialDb';
     import { findPresetBarcode, BarcodeProductInfo } from '../model/BarcodeProduct';
     import { Material } from '../model/Material';
     ```
   - Export interface `ScanMatchedResult`:
     ```typescript
     export interface ScanMatchedResult {
       barcode: string;
       name?: string;
       category?: string;
       unit?: string;
       shelfLifeDays?: number;
       source: 'history' | 'preset' | 'raw_barcode';
     }
     ```
   - Export function `scanAndMatchProduct(context: common.UIAbilityContext, db: MaterialDb): Promise<ScanMatchedResult | undefined>`:
     - Calls `scanBarcode.startScanForResult(context, options)` with options:
       ```typescript
       const options: scanBarcode.ScanOptions = {
         scanTypes: [scanCore.ScanType.ALL],
         enableMultiMode: false,
         enableAlbum: true
       };
       ```
     - Handles errors with `try/catch` (log via `hilog.error` and throw descriptive error or return undefined gracefully).
     - Extract `barcodeValue` from `result.originalValue` (trimmed). If empty, return `undefined`.
     - Step 1: Query `db.getByBarcode(barcodeValue)`. If found, return matched info with `source: 'history'`.
     - Step 2: Query `findPresetBarcode(barcodeValue)`. If found, return matched info with `source: 'preset'`.
     - Step 3: Otherwise, return `{ barcode: barcodeValue, source: 'raw_barcode' }`.
2. Commit the changes:
   - Commit message: `feat(service): implement ScanKit barcode scanning and product matching service`
