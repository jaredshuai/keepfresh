# 包豪斯设计一致性审计报告

分支: `fix/bauhaus-audit` · 基准: `DESIGN.md` + commit `64d9378`
审计日期: 2026-08-24 · Issue #9

---

## 0. 验证维度

| 维度 | 定义 | 判定标准 |
|---|---|---|
| 色值一致性 | pages 内禁止写死 hex/rgba | 必须引用 Theme 令牌 |
| 圆角全局零 | 任何 borderRadius > 0 违规 (形状组件除外) | 只能用 Theme.*Radius 令牌 (均为 0) |
| 几何形状语言 | 过期=红圆 ● / 临期=橙三角 ▲ / 安全=蓝绿方 ■ | 使用 Circle / Polygon / Rect 形状组件 |
| 边框 | 2vp 纯黑 #1a1a1a | 优先 Theme.borderThin 或 具名边框令牌 |
| 间距 | 8vp 倍数 (允许 4vp 步长 tinyGap) | 异常 flag 人工复核 |
| 硬阴影 | 4×4 偏移黑色（Stack 双层叠加）| 禁止渐变柔和 shadow() 降级 |
| 主按钮 | 深黄 #d69a00 底 + 白字 + 黑边 + 硬阴影 | 色值必须引用 Theme.yellowDark |

---

## 1. 审计发现的偏差 (共 18 项，全部已修复)

### HIGH 严重度 (4 项)

| # | 文件 | 类型 | 位置 | 描述 | 修复 commit |
|---|---|---|---|---|---|
| H1 | ItemDetail.ets | RADIUS_GT_ZERO | L236 | 过期圆标识使用 `Column + borderRadius(28)`，而非形状组件，违反零圆角约束 | `f98cf73` |
| H2 | Index.ets | HARDCODED_RGBA | L464 | 过期卡分类信息行写死 `'rgba(255,255,255,0.85)'` | `68dfc6d` |
| H3 | Index.ets | HARDCODED_RGBA | L478 | 过期卡「已过期」标签写死 `'rgba(255,255,255,0.85)'` | `68dfc6d` |
| H4 | CategoryIcons.ets | HARDCODED_HEX_COLOR × 4 | L13/L18/L23/L28 | 4 个分类 bgColor 写死 hex：`#fff0e5 / #e0f2f0 / #fff8e0 / #ffe5e7` | `f1c34be` + `f08a4d6` |

### MEDIUM 严重度 (14 项)

| # | 文件 | 类型 | 描述 | 修复 commit |
|---|---|---|---|---|
| M1–M14 | CustomFieldManager.ets | RADIUS_LITERAL_ZERO × 12 + 未在 H 列的 2 处 textInput | 12 处写死 `borderRadius(0)` 字面量，未引用 Theme.*Radius 令牌：<br/>• 图标按钮 40×40 (2处) → `Theme.iconBtnRadius`<br/>• 主/次/危险/小文字按钮 (6处) → `Theme.buttonRadius`<br/>• Chip / EnumChip (2处) → `Theme.chipRadius`<br/>• 输入框 (2处) → `Theme.inputRadius` | `e4719bd` |

### LOW 严重度 (0 项)

未发现需修复的低严重度问题。Divider `strokeWidth(1)` 符合 DESIGN.md 分隔线设计（与卡片 2vp 边框区分）。

---

## 2. 修复详情 (5 commits)

| Commit | 改动 | 增加令牌 |
|---|---|---|
| `f08a4d6` Theme.ets | 新增：`textWhiteDim = rgba(255,255,255,0.85)`（反白次级文字）<br/>新增：`categoryFoodBg / categoryMedicineBg / categoryDailyBg / categoryBeautyBg` 4 个分类背景浅色系令牌<br/>食品浅底从审计时的 `#fff0e5` 对齐为 `#fff0e0` (= nearSoft)，统一色系 | +5 令牌 |
| `68dfc6d` Index.ets | `L464`, `L478` 两处 `fontColor('rgba(…)')` → `Theme.textWhiteDim` | — |
| `f98cf73` ItemDetail.ets | 过期标识：`Row + backgroundColor + borderRadius(28)` → `Circle({56,56}) + fill + stroke(2)`<br/>安全标识：`Row + backgroundColor` → `Rect({56,56}) + fill + stroke(2)`<br/>临期标识保持 Polygon 实现不变 | — |
| `e4719bd` CustomFieldManager.ets | 12 处 `borderRadius(0)` → 对应语义化 Theme 令牌：`iconBtnRadius / buttonRadius / chipRadius / inputRadius`，按组件语义映射 | — |
| `f1c34be` CategoryIcons.ets | 4 个分类 `bgColor: '#xxxxx'` → `Theme.category*Bg`，在文件头新增 `import { Theme } from './Theme'` | — |

---

## 3. 各文件审计结论

### Theme.ets ✅ PASS

- 15 个主令牌 (yellowDark/yellow/paper/ink/expired/near/safe/danger + 7 radius) 全部与 DESIGN.md 标称值一一对应
- 所有 radius 令牌 = 0
- 色值采用具名命名，易于语义化引用
- 新增的 textWhiteDim / category*Bg 令牌符合 Theme 架构

### CategoryIcons.ets ✅ PASS (修复后)

- 修复前：4/4 分类写死 hex，食品浅底 `#fff0e5` 与 nearSoft `#fff0e0` 不一致
- 修复后：4/4 引用 Theme.category*Bg，食品浅底对齐到 nearSoft 色系

### Index.ets ✅ PASS (修复后)

- 变体 C 状态分组布局：已过期红底白字卡置顶 → 临期橙 → 安全蓝绿方折叠 ✅
- 几何状态标识：Circle / Canvas+Polygon / Rect — 全部使用形状组件 ✅
- 硬阴影 Stack 双层：图标按钮、FAB、过期卡、普通卡均符合 4×4 黑块模拟 ✅
- 修复：2 处 rgba() → Theme.textWhiteDim ✅

### AddItem.ets ✅ PASS (未发现违规)

- 表单组件所有圆角均使用 `Theme.inputRadius / cardRadius / buttonRadius / chipRadius / iconBtnRadius` ✅
- 所有颜色使用 Theme 令牌，无写死 hex/rgba ✅
- Chip 选中态 = 深黄底白字黑边，未选中 = 白底黑字黑边 ✅
- 到期预览蓝绿卡、错误提示、SectionTitle 彩色装饰条均正确使用语义化令牌 ✅

### ItemDetail.ets ✅ PASS (修复后)

- 修复：几何形状改用 Circle / Polygon / Rect 形状组件 ✅
- 状态 Banner：大色块 + 大数字天数 + 白字 ✅
- 信息卡片：白底 2vp 黑边硬阴影、头部分类图标、行之间 1vp 黑分隔线 ✅
- 底部双按钮：编辑(深黄底白字) / 删除(白底红字) 并排 ✅

### Settings.ets ✅ PASS (未发现违规)

- 五模块卡片（黄/橙/蓝绿/红/黑图标方块）✅
- 阈值输入框 / 预设天数 Chip / 开关 / 导入预览 Sheet 全部包豪斯化 ✅
- 所有颜色、圆角均引用 Theme 令牌 ✅

### CustomFieldManager.ets ✅ PASS (修复后)

- 修复：12 处 `borderRadius(0)` 字面量全部替换为语义化令牌 ✅
- 新增 10 个可复用 Builder（bauhausShadow / bauhausPrimaryBtn 等）均硬阴影 + 零圆角 ✅
- 字段卡片紧凑按钮、Chip、Sheet 面板、空状态几何组合全部合规 ✅

---

## 4. 修复前后 grep 结果

### pages 目录下硬编码 hex/rgba：

| 阶段 | 结果 |
|---|---|
| 修复前 (commit 64d9378) | **Index.ets: 2** `rgba(255,255,255,0.85)` |
| 修复后 (HEAD fix/bauhaus-audit) | **0** ✅ |

### 全 .ets 目录写死字面量 borderRadius(非零正数 / 0)：

| 阶段 | 结果 |
|---|---|
| 修复前 (commit 64d9378) | **ItemDetail.ets: 1** `borderRadius(28)`<br/>**CustomFieldManager.ets: 12** `borderRadius(0)` |
| 修复后 (HEAD fix/bauhaus-audit) | **0** ✅ |

---

## 5. ExpiryService / DateUtils 单元测试（Issue 第4节，可选）

本审计未执行此可选项。如需补充单元测试，请新建 issue 跟踪：
- 跨月/跨年/闰年边界
- 临期阈值边界 (0 天、1 天、阈值当天、阈值+1 天)
- 时区处理

---

## 6. 遗留说明

1. **spacing 非 8 倍数（如 tinyGap=4vp、margin(left:4,top:4)）**：硬阴影 4vp 偏移和 tinyGap=4vp 属于设计系统内的「最小视觉步长」(Theme.tinyGap=4, Theme.hardShadowOffset=4)，不属于 spacing 违规。
2. **Theme.cardShadow/fabShadow 中仍有 rgba()**：这是 ArkUI ShadowOptions 降级方案，但所有页面实际使用的都是 Stack 双层硬阴影实现（而非 .shadow() 调用），因此无违规。
3. **Divider strokeWidth(1)**：分隔线 1vp 与卡片边框 2vp 形成层次对比，符合 DESIGN.md 的视觉语言（粗边框 + 细分隔）。

---

## 7. Commit 图 (fix/bauhaus-audit)

```
64d9378 main      ← 包豪斯初版 AI 改造 (基准)
f08a4d6 Theme+    ← fix(bauhaus): Theme.ets 新增 textWhiteDim + 分类背景浅色系令牌
68dfc6d Index+    ← fix(bauhaus): Index.ets 替换 2 处写死 rgba → Theme.textWhiteDim
f98cf73 Detail+   ← fix(bauhaus): ItemDetail.ets 几何形状改用原生 Circle/Polygon/Rect 组件
e4719bd Fields+   ← fix(bauhaus): CustomFieldManager.ets 12 处 borderRadius(0) → Theme 令牌
f1c34be Icons+    ← fix(bauhaus): CategoryIcons.ets bgColor 全部引用 Theme.category*Bg 令牌
```
