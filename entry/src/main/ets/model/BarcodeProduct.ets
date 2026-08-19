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
  { barcode: '6907992500045', name: '云南白药牙膏 100g', category: '日用品', unit: '支', defaultShelfLifeDays: 1080 },
  { barcode: '6917878018889', name: '阿莫西林胶囊 0.25g*24粒', category: '药品', unit: '盒', defaultShelfLifeDays: 720 },
  { barcode: '6934572300018', name: '蓝月亮洗衣液 1kg', category: '日用品', unit: '袋', defaultShelfLifeDays: 1080 },
  { barcode: '6901028000000', name: '康师傅红烧牛肉面 100g', category: '食品', unit: '袋', defaultShelfLifeDays: 180 }
];

export function findPresetBarcode(barcode: string): BarcodeProductInfo | undefined {
  if (!barcode) {
    return undefined;
  }
  const cleanBarcode: string = barcode.trim();
  return PRESET_BARCODE_PRODUCTS.find((p: BarcodeProductInfo): boolean => p.barcode === cleanBarcode);
}
