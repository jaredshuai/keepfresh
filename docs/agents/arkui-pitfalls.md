# ArkUI 已知陷阱速查

design-guard / wire-guard 报错时会直接指向本文档的具体锚点。每条格式：症状 → 根因 → 项目内实例 → 修法。
新增条目保持此结构，锚点一旦被守卫引用就不要改。

---

## <a id="button-capsule"></a>Button 胶囊（`#button-capsule`）

**症状**：按钮明明设了 `borderRadius(0)`，渲染出来仍是两端全圆的胶囊；TextInput 同理自带大圆角。

**根因**：ArkUI 的 `Button` 组件默认类型是 `ButtonType.Capsule`，胶囊圆角由系统按高度/2 强制生成，
**`borderRadius` 对 Capsule 不生效**。`TextInput` 单行模式默认样式也自带胶囊级圆角。

**实例**：commit `0525a6b` —— 详情页编辑/删除、新增页扫码快填、设置页阈值输入框等 9 处，全部呈胶囊状与包豪斯零圆角冲突。

**修法**：Button 一律显式 `{ type: ButtonType.Normal, stateEffect: true }`（Circle 用于圆形几何图形除外）；
TextInput 显式补 `.borderRadius(Theme.inputRadius)`。design-guard 规则「Button 默认胶囊」执法。

---

## <a id="builder-by-value"></a>@Builder 按值传参（`#builder-by-value`）

**症状**：点选芯片/按钮后选中高亮或禁用态停滞在旧位置；界面显示与实际保存值不一致（更危险）。

**根因**：`@Builder` 的标量参数按值传递，父组件状态变化**不会**触发 @Builder 片段重渲染，
参数停留在首次求值的结果。只有 builder 体内直接读到的组件状态才会建立依赖。

**实例**：commit `554236e` —— AddItem 分类芯片高亮停滞（点药品存食品）；`0e56ad9` —— CFM 字段类型芯片、
CFM/CategoryManager 上移下移箭头禁用态停滞。

**修法**（二选一，项目内均有范本）：
1. 独立 `@Component` + `@Prop` —— AddItem.ets 的 `ChipGroup` 是范本（@Prop 由父状态驱动，响应式有保证）；
2. builder 体内读 state 内联比较/实时求值 —— Settings.ets `chipButton`、CategoryManager.ets `smallIconBtn`
   （`moveEnabled()` 在体内经方法读 @State）是范本。
不要为它写正则守卫（静态分析无法可靠区分静态常量与状态衍生参数），靠评审 + 本文档。

---

## <a id="percent-height-in-scroll"></a>滚动容器内的百分比高度（`#percent-height-in-scroll`）

**症状**：卡片下方出现整屏黑板 / 巨大色块，内容被挤出视口。

**根因**：`height('100%')` 在滚动容器的子层解析为**父约束的最大可用高度（视口高）**，而不是内容高。
内容比视口短时，百分比层就裸露成大色块。

**实例**：commit `0525a6b` —— HardShadowCard 的 `shadowMode: -1`（意图"跟随主层"）在详情页×3、
CategoryManager、RecycleBin 共 5 处生成整屏黑板，且详情页"生命周期"操作区被完全埋没。

**修法**：HardShadowCard 的 `shadowMode` 只认正数（固定 vp）或 0（阴影层贴内容，绝大多数场景）；
负值语义已在组件内并入无 height 分支（HardShadow.ets），**不要恢复百分比语义**。写新的定高容器时用正数 vp。

---

## <a id="layoutweight-axis"></a>layoutWeight 轴向（`#layoutweight-axis`）

**症状**：按钮被拉伸成占满剩余屏幕的巨大色块/死白区（约 300vp 级）。

**根因**：`layoutWeight(1)` 的含义随父容器轴向变化——在 Row 里是"平分剩余**宽度**"（按钮对的常见正用），
在 Column 里是"吃掉剩余**高度**"。含 `layoutWeight(1)` 的复用按钮 builder 若被裸 Column 包裹复用，
按钮会被拉伸到视口剩余高度。另外：`layoutWeight` 写在 **Stack 子层**是无效写法（不参与该父容器的
weight 分配），属良性哑弹，清理时随手删。

**实例**：Settings 备份卡的 dogfood 按钮被拉高约 300vp 死白（`secondaryButton` 内含 layoutWeight(1)，
被裸 Column 包裹复用；commit `554236e` 修复）。同族哑弹：Settings `secondaryButton`/`primaryButton`、
ItemDetail `primaryBtn`、CFM 弹窗按钮对的外层墨影 Column 里的 Stack 子层 layoutWeight（未清理，见 issue）。

**修法**：复用含 weight 的按钮 builder 时，包一层 **Row**（让 weight 作用回横向宽度）；
Stack 子层的 `layoutWeight(1)` 直接删除。

---

## <a id="scroll-default-center"></a>Scroll 短内容默认居中（`#scroll-default-center`）

**症状**：列表只有一两条时，内容悬在屏幕垂直中部，头顶一大块空白。

**根因**：Scroll 的通用 `align` 默认 `Alignment.Center`，当内容尺寸小于视口时按此对齐——垂直方向就是居中。
内容超长时无感，短列表页（回收站/管理页）必现。

**实例**：commit `0525a6b` —— RecycleBin 头顶 ~245vp、CategoryManager ~87vp 空隙（此前被黑板卡遮住未暴露）。

**修法**：列表类页面的垂直 Scroll 一律 `.align(Alignment.TopStart)`。注意 **`Alignment.Start` 不行**——
它只是水平靠左，垂直仍是居中（踩过一次）。
