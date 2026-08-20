# 研究：端侧视觉能力（商品分类与日期 OCR）

> Ticket: [#4](https://github.com/jaredshuai/keepfresh/issues/4)（wayfinder:research）
> 日期: 2026-08-20 ｜ 基线: HarmonyOS API 24（6.1.1(24)），Stage 模型，ArkTS
> 用途: 为「拍照入库交互定稿」ticket 提供端侧识别能力边界结论与降级建议

## 结论速览（TL;DR）

| 研究问题 | 结论 |
|---|---|
| CoreVisionKit 有图像分类 API 吗 | **没有**。Core Vision Kit 全部 9 个 ArkTS API 中无 imageClassification/图像标签类接口；功能上最近似的是 objectDetection（多目标识别，15 类粗粒度数字编码标签），其中仅「食物」一类可映射到 KeepFresh 分类 |
| OCR 能识别包装喷码日期吗 | **印刷体可用，喷码点阵存疑**。textRecognition 输出纯文本+坐标（无结构化字段），日期抽取必须自己做正则；官方明示「手写识别能力弱」、拍摄夹角<30°、建议 720p+；喷码点阵场景官方未明确支持，需真机实测 |
| 相机怎么接最省事 | **cameraPicker（系统相机拍照）**。API 11 起、无需相机权限、`pick()` 一次调用返回 `resultUri`，配 `saveUri` 可直接写入应用沙箱不污染媒体库 |
| 拍照入库可行形态 | **拍照 → OCR 抽日期 → 人工选分类**。自动分类不可行，OCR+人工分类够用；objectDetection 的「食物」标签可作可选预填增强 |

---

## 1. CoreVisionKit 是否有图像分类 API

### 1.1 事实结论：无图像分类/图像标签 API

Core Vision Kit（基础视觉服务，`@kit.CoreVisionKit`）的 ArkTS API 全集为 9 个，**不含任何图像分类（imageClassification）/图像标签接口**：

| API | 用途 | 起始版本 |
|---|---|---|
| visionBase | 视觉服务公共基类（Request/Response/Analyzer） | API 11 |
| textRecognition | 通用文字识别（OCR） | API 10（4.0.0(10)） |
| faceDetector | 人脸检测 | API 11 |
| faceComparator | 人脸比对 | API 12 |
| subjectSegmentation | 主体分割 | API 11 |
| **objectDetection** | **多目标识别（最接近"分类"的能力）** | API 12（5.0.0(12)） |
| skeletonDetection | 骨骼点检测 | API 12 |
| imageSuperResolution | 图像超分 | API 11 |
| textSearchImage | 以文搜图（图库检索） | API 12 |

该结论由三个独立来源交叉验证：

1. 官方 API 目录页（Core Vision Kit ArkTS API 清单）无图像分类条目 — [core-vision-arkts](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/core-vision-arkts)
2. 官方 Kit 介绍页「能力清单」（8 项能力：OCR、人脸检测、人脸比对、主体分割、多目标识别、骨骼点检测、图像超分、文本搜图）无「图像分类/图像标签」 — [core-vision-introduction](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/core-vision-introduction)
3. Context7 索引的 HarmonyOS References 全文检索 `imageClassification` 无命中（返回的都是 objectDetection/skeletonDetection 等其他能力）

注：HarmonyOS 曾在早期（API 9 时代，HMS 机器学习服务）有 imageClassification 相关能力，但 HarmonyOS NEXT / 5.0+ 的 Core Vision Kit 中不存在，本文以当前官方文档为准。

### 1.2 最近似替代：objectDetection（多目标识别）

**API 要点**（[core-vision-object-detection-api](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/core-vision-object-detection-api)）：

- 模块：`import { objectDetection, visionBase } from '@kit.CoreVisionKit'`
- 起始版本：5.0.0(12)；系统能力 `SystemCapability.AI.Vision.ObjectDetection`；仅 Stage 模型
- 输入：`visionBase.Request = { inputData: { pixelMap }, scene: visionBase.SceneMode.FOREGROUND }`，仅支持单张图
- 输出：`ObjectDetectionResponse { objects: VisionObject[] }`，其中 `VisionObject`：
  - `boundingBox`：目标外接框
  - `score`：置信度 (0,1)
  - `labels: Array<number>`：**类别标签为数字编码，非文字标签**
  - `id`：从 0 递增的唯一标识
- 图片约束：宽高均 100~10000px，宽高比 ≤5:1，物体占比需 >0.1%
- 错误码：401（参数）、1011000001/1011000003（运行失败）、1011000004（超时）
- 用法：`ObjectDetector.create()` → `process()` → `destroy()`（须显式释放）

**支持的类别全集（15 类）**：

| 标签值 | 类别 | 标签值 | 类别 |
|---|---|---|---|
| 0 | 风景 | 9 | 猫头 |
| 1 | 动物 | 10 | 狗头 |
| 2 | 植物 | 11 | **食物** |
| 3 | 建筑 | 12 | 汽车 |
| 5 | 人脸 | 13 | 人体 |
| 6 | 表格 | 21 | 文档 |
| 7 | 文本 | 22 | 卡证 |
| 8 | 人头 | | |

**与 KeepFresh 分类的映射评估**：

| KeepFresh 分类 | objectDetection 可覆盖性 |
|---|---|
| 食品 | 部分：标签 11「食物」可映射（但无细分，如生鲜/乳制品/零食不可区分） |
| 药品 | 不可：无药品类别 |
| 日用品 | 不可：无日用品/家居类别 |
| 美妆护肤 | 不可：无美妆类别 |
| 其他 | 兜底：无匹配时归其他 |

结论：objectDetection 的标签粒度（15 类通用场景）远粗于 KeepFresh 的 5 个物资分类，**不能作为可靠的自动分类来源**，至多用「食物」标签做预填建议。

### 1.3 其他 Kit 也无现成分类标签输出

- **Vision Kit（场景化视觉服务）的 AI 识图控件** `visionImageAnalyzer`（`@kit.VisionKit`，API 12 起）：聚合 OCR、主体分割、实体识别、多目标识别，提供文字选取（`textAnalysis` 回调返回 string）、主体分割（`Subject[]`）、识图搜索（拉起系统搜索面板）等交互，**控件能力清单中没有"图像分类标签"输出**；且它是挂靠 Image/Video/XComponent 控件的交互式形态（长按选字、抠图），不适合"拍照→识别→表单"的自动化链路 — [vision-image-analyzer](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/vision-image-analyzer)、[指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/vision-imageanalyzer)
- Vision Kit 其余能力为活体检测/卡证识别/文档扫描，与商品分类无关 — [vision-introduction](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/vision-introduction)

### 1.4 若确需端侧自动分类的长期路径（超出本 ticket 范围）

HarmonyOS 提供 MindSpore Lite Kit（`@kit.MindSporeLiteKit`）端侧推理框架，可部署自定义训练的图像分类模型（.ms 格式，ArkTS 或 Native 侧调用）。属自研模型方案，模型获取/转换/量化/维护成本高，不建议 KeepFresh 首版采用，仅作为后续演进备选。（此路径为方向性描述，未在本轮逐 API 查证，标注为**未深入查证**。）

---

## 2. TextRecognition OCR 对包装喷码日期的实用度

### 2.1 API 事实

（来源：[core-vision-text-recognition-api](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/core-vision-text-recognition-api)、[指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/core-vision-text-recognition)）

- 模块：`import { textRecognition } from '@kit.CoreVisionKit'`
- 起始版本：`recognizeText` 4.0.0(10)；`init()/release()` 5.0.0(12)；系统能力 `SystemCapability.AI.OCR.TextRecognition`；仅 Stage 模型
- **输入**：`VisionInfo { pixelMap: image.PixelMap }`，PixelMap 须为 **RGBA_8888** 格式
  - 图片约束（Kit 约束与限制页）：JPEG/JPG/PNG；宽 100~10000px、高 100~15210px；宽高比 ≤10:1；单图文本 ≤10000 字符；拍摄夹角 <30°；建议成像 720p 以上
  - 官方定位为「票据、卡证、表格、报刊、书籍等**印刷品**文字」识别；**手写识别能力弱**（官方原话）
- **配置**：`TextRecognitionConfiguration { isDirectionDetectionSupported: boolean }`（默认 true 开启朝向检测；可确定图片正向时设 false 提升性能）
- **输出**：`TextRecognitionResult { value: string, blocks: TextBlock[] }`，层级为 `blocks（段落）→ lines（行）→ words（词）`，行/词级别均带顺时针 `cornerPoints` 外框坐标（首点左上角）
  - **没有结构化字段抽取**：不区分"生产日期/保质期"等语义字段，只给文本与坐标
- 支持语言：简体中文(zh-CN)、英语(en)、日语(ja)、韩语(ko)、繁体中文(zh-TW)
- 错误码：200（超时）、401（参数）、1001400001（OCR 运行失败）、1001400002（服务异常）

### 2.2 版式支持评估：印刷体 vs 喷码点阵

| 版式 | 评估 | 依据 |
|---|---|---|
| 包装盒印刷体日期（如「生产日期：2026.08.15」） | **预期可用** | 属官方定位的印刷品文字场景；输出带行级坐标便于定位 |
| 瓶身/罐底喷码点阵日期（dot-matrix inkjet） | **存疑，需真机实测** | 官方文档未明确提及喷码点阵支持度；点阵字符笔画断裂、对比度低是通用 OCR 的典型弱项；官方已明示「手写识别能力弱」，风格化/低质量字符同样是风险区 |
| 激光刻印/压痕日期 | 存疑，需实测 | 同上，官方未覆盖 |
| 手写日期 | 弱 | 官方明示手写识别能力弱 |

诚实标注：喷码点阵是 KeepFresh 核心场景（饮料、乳品、罐头多见喷码），官方文档没有给出支持/不支持的明确口径，**本结论只能给出"高风险、必须真机验证"的判断，建议用 20~30 张真实包装样本（喷码/印刷各半）做一次实测再定稿交互**。

### 2.3 日期字段抽取：需要自己做正则

**是。** `TextRecognitionResult` 只输出文本与坐标，无任何语义字段（对比华为云 OCR 的结构化票据接口，端侧 textRecognition 没有「键值对提取」）。落地需要自建一层抽取逻辑：

1. 遍历 `blocks → lines` 拿行文本（日期通常独占一行或跟在「生产日期」后缀后）
2. 正则匹配候选日期，需覆盖常见格式：
   - `2026.08.15` / `2026-08-15` / `2026/08/15` / `20260815`
   - `2026年8月15日`
   - 前缀变体：`生产日期`/`见瓶身`/`PROD.DATE`/`MFG` 等
   - OCR 常见误识别（`O`→`0`、`l`→`1`、`S`→`5`）可在容错层处理
3. 用 `cornerPoints` 坐标聚类相邻行（「生产日期」标签行与数值行常常分行），提高召回
4. 多候选时全部列出供用户点选确认（不要自动采用唯一解）

### 2.4 已知坑（识别「生产日期见瓶身」类文本）

- **提示语陷阱**：大量包装印刷的是「生产日期见瓶身上部/见瓶盖/见包装底部」等提示语而非日期本身，OCR 会忠实地识别出这句提示。抽取逻辑必须先黑名单过滤此类提示语（正则 `生产日期.{0,6}见|见(瓶|盖|底|包装)`），否则会把它当日期上下文误传给用户。这是品类包装的普遍现象，属于**经验性结论**（官方文档不涉及），标注为设计建议。
- **保质期与生产日期混排**：「保质期12个月」与「生产日期2026.08.15」常相邻出现，正则须区分两种字段语义；KeepFresh 已有「生产日期+保质期」双录入模式，正好可分别匹配「生产日期/MFG」与「保质期/EXP/到期日」关键字。
- **朝向与夹角**：拍摄夹角须 <30°，倒置/侧拍需依赖 `isDirectionDetectionSupported: true`（默认开启）；竖排喷码可能需要用户手动旋转重拍。
- **质量红线**：<720p 成像、反光、褶皱标签、玻璃瓶曲面形变都会显著降低识别率；交互上应引导近距离正对拍摄。
- **失败兜底**：识别为空或无日期候选时，直接回落到手动输入，不阻塞录入流程。

---

## 3. 相机拍照的推荐接入方式

### 3.1 三种方式对比

| 维度 | cameraPicker（系统相机拍照） | CameraKit（自定义相机） | PhotoViewPicker（相册选图） |
|---|---|---|---|
| 模块 | `@kit.CameraKit` 内 `cameraPicker` | `@kit.CameraKit` 内 `camera` | `@kit.MediaLibraryKit` 内 `photoAccessHelper` |
| 起始版本 | API 11（元服务 API 12） | API 10+（各接口不同） | API 10+ |
| 相机权限 | **无需** `ohos.permission.CAMERA` | **需要**（`createCameraInput` 等接口明示要求） | 无需 |
| 开发成本 | 极低：一次 `pick()` 调用 | 高：CameraInput/Session/PreviewOutput/PhotoOutput + XComponent surface + 生命周期管理 | 低：一次 `select()` |
| 返回 | `PickerResult { resultCode(0成功), resultUri, mediaType }` | 自行接收 photoOutput 数据 | `PhotoSelectResult { photoUris[] }`（URI 永久授权） |
| 存储控制 | `saveUri` 不配→存系统媒体库；配→覆盖写入应用沙箱指定文件 | 完全自控 | 只读相册 |
| 适用 | **只需拿到一张即时拍摄的照片** | 需要自定义取景框/连续扫描/内嵌预览 | 用户已有照片（拍过的包装） |

来源：[camera-picker 指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/camera-picker)、[js-apis-camerapicker 参考](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-camerapicker)、[PhotoViewPicker 参考](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arkts-apis-photoaccesshelper-photoviewpicker)。

### 3.2 结论：cameraPicker 最省事

对「拍照 → 识别 → 表单」链路：

1. **首选拍照：`cameraPicker.pick(context, [PickerMediaType.PHOTO], profile)`**
   - 免相机权限、免自研相机 UI；`resultCode === 0` 即成功
   - **建议配置 `saveUri` 指向应用沙箱文件**（先用 `fileIo.createRandomAccessFileSync()` 建文件，`fileUri.getUriFromPath()` 转 URI）：拍摄结果直接落到沙箱，**不污染用户媒体库**，且避免事后读媒体库 URI 的授权差异；`resultUri` 即该文件，直接 `image.createImageSource` 解码
   - 注意：必须在 UIAbility 界面上下文中调用；折叠设备展开态启动后折回会把 picker 推后台
   - 官方指南原话建议：只需要获取即时拍摄的照片/视频，用 CameraPicker 即可
2. **补充入口：`PhotoViewPicker.select()`**——用户拍过照（如先前拍过包装）可直接从相册选，URI 永久授权，同样免权限
3. **不推荐 CameraKit 自定义相机**：KeepFresh 无取景定制/连续扫描需求，`ohos.permission.CAMERA` 权限申请 + 会话/surface 管理的成本换不来收益；除非后续要做「实时取景+日期高亮框」这类深度交互再评估
4. 所谓「系统相机跳转」在 HarmonyOS NEXT 语境下即 cameraPicker 本身（系统提供交互界面），无需另行通过 want 拉起相机应用

完整链路（均为已验证 API，版本满足 API 24 基线）：

```
cameraPicker.pick(saveUri=沙箱文件) → resultUri
→ fileIo.open + image.createImageSource + createPixelMap(RGBA_8888)
→ textRecognition.recognizeText({ pixelMap })
→ 行级文本 + 正则抽取日期候选（黑名单过滤"见瓶身"类提示语）
→ 预填表单（日期候选供点选，分类由人工选择，可选用 objectDetection 预填"食品"）
→ 失败/空结果 → 手动输入兜底
```

---

## 4. 拍照入库能力边界结论 + 降级建议

### 4.1 能力边界

| 能力 | 可用性 | 说明 |
|---|---|---|
| 自动商品分类 | **不可行** | Core Vision Kit 无分类 API；objectDetection 仅 15 类粗粒度且标签为数字编码，只有「食物」可映射 |
| 印刷体日期 OCR | 可行 | 官方定位场景；需自建正则抽取 |
| 喷码点阵日期 OCR | 待实测 | 官方未明确；高风险项，须真实样本验证 |
| 拍照免权限接入 | 可行 | cameraPicker，API 11+ |
| 全离线/端侧 | 未能完全查证 | 见 5 节 |

通用约束（影响测试与发布计划）：Core Vision Kit 仅中国大陆地区可用（不含港澳台）；**不支持模拟器，必须真机调试**；同一用户不可并发调用同一特性（并发返回系统繁忙错误）。来源：[Kit 约束与限制](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/core-vision-introduction)。

### 4.2 降级建议（供「拍照入库交互定稿」直接采用）

1. **交互主形态定为「OCR 辅助 + 人工确认」**：拍照 → OCR 日期候选点选 → 分类人工选择（沿用现有 5 分类选择器）。自动分类不可行不阻塞该 ticket。
2. **objectDetection 作可选增强**：识别出标签 11（食物）时把分类预填为「食品」，并低置信度展示（用户可改）；识别不到就不干预。这是零额外成本的顺手增强，注意其类别是数字编码需自行映射。
3. **OCR 失败兜底**：无日期候选/识别为空 → 无痕回落手动输入；提示语「见瓶身」类文本一律过滤不展示为候选。
4. **前置实测门**：定稿交互前用 20~30 张真实包装（喷码/印刷各半）真机跑一次 recognizeText，若喷码样本识别率不可接受，交互文案改为「对准印刷日期拍摄」并弱化喷码场景预期。
5. **长期选项**（不承诺）：MindSpore Lite Kit 自训练分类模型；或等待后续系统版本是否补充分类能力。

---

## 5. 未查证事项（如实标注）

- **Core Vision Kit 是否收费 / 是否纯端侧运行**：官方 Kit 介绍页与 textRecognition API 页均未标注计费与部署位置；Vision Kit 的活体检测官方明确标注「纯端侧算法、试用期免费」，但该口径不能外推到 Core Vision Kit。社区资料（百度百科、论坛）称 Core Vision Kit 为端侧免费，属二手来源，本文不采信为结论。**建议以华为开发者官网「Kit 收费策略」页面或商务渠道为准。**
- **喷码点阵日期识别率**：无官方口径，需真机实测（见 4.2 第 4 条）。
- **MindSpore Lite Kit 自定义分类模型的完整落地路径**：仅确认存在该端侧推理框架，未逐 API 查证。
- objectDetection 15 类标签中编号 4、14~20 在文档中缺失/未定义，本文按官方文档现状照录。

## 6. 来源清单（均为一手来源：华为开发者官方文档）

| # | 内容 | 链接 |
|---|---|---|
| 1 | Core Vision Kit API 目录（9 个 ArkTS API 清单） | https://developer.huawei.com/consumer/cn/doc/harmonyos-references/core-vision-arkts |
| 2 | Core Vision Kit 介绍（能力清单、约束与限制、地区/模拟器限制） | https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/core-vision-introduction |
| 3 | textRecognition（文字识别）API 参考 | https://developer.huawei.com/consumer/cn/doc/harmonyos-references/core-vision-text-recognition-api |
| 4 | 通用文字识别开发指南 | https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/core-vision-text-recognition |
| 5 | objectDetection（多目标识别）API 参考（含 15 类标签表） | https://developer.huawei.com/consumer/cn/doc/harmonyos-references/core-vision-object-detection-api |
| 6 | visionImageAnalyzer（AI识图控件）API 参考 | https://developer.huawei.com/consumer/cn/doc/harmonyos-references/vision-image-analyzer |
| 7 | AI识图控件开发指南 | https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/vision-imageanalyzer |
| 8 | Vision Kit（场景化视觉服务）简介 | https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/vision-introduction |
| 9 | 通过系统相机拍照和录像（CameraPicker）指南 | https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/camera-picker |
| 10 | @ohos.multimedia.cameraPicker API 参考 | https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-camerapicker |
| 11 | PhotoViewPicker API 参考 | https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arkts-apis-photoaccesshelper-photoviewpicker |
| 12 | CameraKit CameraManager（CAMERA 权限要求） | https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arkts-apis-camera-cameramanager |

（以上文档均于 2026-08-20 通过 Context7 索引与 developer.huawei.com `.md` 原文抓取双重核对。）
