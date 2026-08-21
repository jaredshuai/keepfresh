# ⚠️ 已淘汰 — 请勿使用

**拍照入库功能已放弃（ADR-0002）**：实测证明端侧 textRecognition 对真实包装日期引擎层乱码，不可依赖。本提示词仅存档备查。

---

# 施工任务：喷码/印刷包装 OCR 真机实测页（KeepFresh 前置实测门，ticket #8）

## 你的角色

你是 HarmonyOS（ArkTS/ArkUI）开发工程师。为仓库 `keepfresh` 开发一个**最小 OCR 实测页面**，用于真机验证端侧 textRecognition 对商品包装日期的识别率。**这是一次性 PoC，代码在 `poc/ocr-spray-test` 分支上开发，不进 main。**

## 先读（动手前必读）

1. `docs/research/on-device-vision.md` — 端侧视觉研究结论（API 用法、约束、黑名单规则都在里面，**严格按它的链路写**）
2. `CONTEXT.md`、`docs/adr/0001-on-device-ai-only.md`
3. 现有代码：`entry/src/main/ets/` 结构与 `pages/Index.ets`（实测页入口挂在首页即可）

## 背景

研究结论：印刷体日期 OCR 预期可用；**喷码点阵（dot-matrix）日期识别率官方无口径，必须真机实测**。实测结果决定拍照入库功能的交互文案是否降级（喷码 ≥50% 命中保留预期，<50% 降级为"对准印刷日期拍摄"）。

## 实现要求

1. **实测页**（`pages/OcrTest.ets`，注册进 main_pages；首页加一个临时入口按钮标注"OCR 实测"）：
   - 「拍照」按钮：`cameraPicker.pick(context, [PickerMediaType.PHOTO], profile)`，`saveUri` 指向**预建可写沙箱文件**（`fileIo.createRandomAccessFileSync` 建文件 + `fileUri.getUriFromPath` 转 URI）
   - 「从相册选图」按钮：`PhotoViewPicker` 选图（便于批量测已拍样本）
   - 拿到图 → `image.createImageSource` → `createPixelMap`（**RGBA_8888**）→ `textRecognition.init()` → `recognizeText()` → `release()`；**finally 中 `pixelMap.release()`**
   - 结果展示：全部 lines 原文列表 + **日期候选高亮**（正则命中行标绿）
2. **日期抽取层**（独立工具文件，未来可复用到正式功能）：
   - 正则覆盖：`YYYY[./-年]MM[./-月]DD[日]?`、`YYYYMMDD`、`EXP/MFG/生产日期/保质期至/有效期至` 前缀变体
   - 字符纠错：日期上下文中的 `O→0`、`l/I→1`、`S→5` 替换后重试
   - 黑名单过滤：`生产日期.{0,6}见|见(瓶|盖|底|包装)` 命中行不做候选
3. **实测记录**：每次识别后页面底部追加一条记录卡（时间、命中/未命中、识别文本摘要、耗时 ms）；「导出实测日志」按钮把全部记录写为沙箱 JSON 并提示文件路径（便于取出汇总）。
4. 页面上常驻计数：总样本数、印刷命中数、喷码命中数（用户手动标记每张是"印刷"还是"喷码"——记录卡上加两个标记按钮）。
5. 错误处理：recognizeText 失败（喷码模糊等）也记为一条"未命中"记录，不 crash。

## 验收标准（实测执行人视角）

- 真机上拍照/选图 → 2 秒内出结果 → lines 与日期候选正确高亮
- 连续测 30 张样本不 OOM、不闪退（重点验证 pixelMap.release 与 textRecognition release）
- 实测日志 JSON 可从沙箱取出（告知用户文件路径与取出方式）
- 计数统计准确

## 环境约束（重要）

- Core Vision Kit **不支持模拟器**——本页只能真机验证；模拟器上点击应给出"请用真机"提示而非崩溃
- 仅中国大陆设备可用
- API 24 基线

## 交付

- 分支 `poc/ocr-spray-test` 上的提交
- 文件清单 + 关键实现说明
- 给实测执行人（用户）的一页操作说明：如何构建、如何标记样本、日志文件在哪、如何取出
