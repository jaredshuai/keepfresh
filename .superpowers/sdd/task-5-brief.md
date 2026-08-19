# Task 5 Brief: 录入页 `AddItem.ets` UI 快捷胶囊与联动填充流程集成

## Files
- Modify: `entry/src/main/ets/pages/AddItem.ets`
- (Optional) Modify `entry/src/main/ets/pages/ItemDetail.ets` (if displaying barcode in item details)

## Requirements
1. In `AddItem.ets`:
   - Import `scanAndMatchProduct` from `../service/ScanService` and `pickAndRecognizeDate` from `../service/OcrService`.
   - Add `@State barcode: string = '';` and `@State isRecognizing: boolean = false;`.
   - In `aboutToAppear()` load existing `m.barcode` if editing.
   - In the form UI, right below errorMsg / above the form card, add a quick action bar:
     - **【📷 扫条码录入】** button (Brand green background, icon + text)
     - **【🔍 拍日期 OCR】** button (White card background with brand green border, icon + text)
   - Implement `handleScanBarcode()`:
     - Call `scanAndMatchProduct(ctx, this.db)`.
     - On match: auto-fill `name`, `category`, `unit`, `shelfLifeStr`, `barcode`.
     - Show appropriate toast feedback depending on `result.source` ('history' / 'preset' / 'raw_barcode').
     - Gracefully catch errors and show toast if scan fails or is canceled.
   - Implement `handleOcrDate()`:
     - Call `pickAndRecognizeDate(ctx)`.
     - On result: auto-fill `productionDate`, `shelfLifeStr`.
     - Show toast feedback with recognized date & shelf life.
     - Gracefully catch errors and show toast.
   - In `save()`, include `barcode` in the `Material` object saved to database.
   - In the form card, add an optional/display row for `条形码` (if `barcode` is not empty, display it so user can see the scanned code).
2. Commit the changes:
   - Commit message: `feat(ui): integrate barcode scan and OCR date extraction in AddItem page`
