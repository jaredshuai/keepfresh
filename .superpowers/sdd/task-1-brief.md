# Task 1 Brief: 数据模型与条码字典扩展 (`Material.ets`, `BarcodeProduct.ets`, `MaterialDb.ets`)

## Files
- Modify: `entry/src/main/ets/model/Material.ets`
- Create: `entry/src/main/ets/model/BarcodeProduct.ets`
- Modify: `entry/src/main/ets/db/MaterialDb.ets`

## Requirements
1. Modify `Material.ets`: Add optional `barcode?: string` to `Material` interface.
2. Create `BarcodeProduct.ets`:
   - Define interface `BarcodeProductInfo { barcode: string; name: string; category: string; unit: string; defaultShelfLifeDays: number; }`
   - Define constant array `PRESET_BARCODE_PRODUCTS` with common presets (milk, soy sauce, cola, water, toothpaste, medicine, etc.).
   - Define helper function `findPresetBarcode(barcode: string): BarcodeProductInfo | undefined`.
3. Modify `MaterialDb.ets`:
   - Update `CREATE_TABLE_SQL` to include `barcode TEXT`.
   - In `init()`, execute alter table statement `ALTER TABLE materials ADD COLUMN barcode TEXT;` with try/catch to ensure compatibility for existing sqlite databases.
   - Update `insert()`, `update()`, and `rowToMaterial()` to read/write `barcode`.
   - Implement `async getByBarcode(barcode: string): Promise<Material | undefined>` that queries `materials` table by `barcode`, orders by `id DESC`, limit 1, and returns `Material | undefined`.
4. Commit the changes:
   - Commit message: `feat(model,db): add barcode support and preset product dictionary`
