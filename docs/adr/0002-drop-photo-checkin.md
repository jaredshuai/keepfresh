# 放弃拍照入库（OCR 日期识别）

拍照入库（拍包装照片 → 端侧 OCR 抽生产日期/保质期 → 预填表单）**正式放弃**。实测结论：Core Vision Kit 端侧 `textRecognition` 在真实商品包装上的日期识别**在引擎层即失败（输出乱码），失败发生在正则/纠错之前，应用层无从补救**——不是调正则或纠错能解决的问题。

## Considered Options

- 拍照入库（cameraPicker + textRecognition + 正则/纠错 + 关键词分类建议器）——**否决**：真实包装上引擎层乱码，不可依赖；此前研究（`docs/research/on-device-vision.md`）已标注喷码点阵"官方无口径、需真机实测"，实测结果证伪了该路径
- 端侧图像分类辅助归类 ——**否决**：Core Vision Kit 无图像分类 API，objectDetection 仅"食物"大类可用（研究结论）
- 云端多模态识别 ——**否决**：违反 ADR-0001（仅端侧、禁止云端）

## Consequences

- 入库方式仅保留：手动录入 + 扫码快填（条形码搜索建议）
- `OcrTest` 实测页与 `docs/prompts/prompt-ocr-poc.md` 已淘汰（保留作历史记录，不再使用）
- `docs/research/on-device-vision.md` 中关于 OCR 可行性的研究结论被本实测结论取代
- 未来若端侧 OCR 引擎对包装喷码/印刷日期的识别有实质改进，可重新评估
