# DesignSystemManifest · 4 套皮肤

> 布局：变体 C（状态分组）——已过期区 / 临期区 / 安全区（折叠）+ 顶部品牌 + 底部 4 tab
> 数据：3 临期 · 1 过期 · 共 12 项，6 条列表项按到期日排序
> 通用：移动端 max-width 420px 居中、不用 emoji、Google Fonts CDN、真实数据

---

## 皮肤 03 · 暖纸手作

> ⚠️ 有意识选择：奶油底+衬线+赤陶橙，参考 Aesop / Stripe Press，非 AI 默认审美

### 配色
- bg `#faf8f2`（奶油纸）
- ink `#2d2a26`
- accent `#9d5f4d`（赤陶）
- aux `#537d96`（雾蓝）
- muted `#a8a29a`
- hairline `#e8e2d5`
- warn `#c2703e`（暖铜，临期）
- danger `#8b3a2a`（深赤陶，过期）
- safe `#6b7f5e`（苔绿，安全）

### 字体
- Display: 'Playfair Display' 500/600（标题、天数）
- Body: 'Source Serif 4' 400/500
- 手写注: 'Caveat' 500（小批注）

### 间距 / 圆角 / 阴影
- 基准 6px，行高 1.7
- 圆角 4px
- 不用阴影，用 1px hairline 分隔
- 纸质纹理：SVG 噪点 data-uri，opacity 0.4

### 组件
- **分组标题**: Playfair 600 18px + 右侧 Caveat 手写小注（如 "尽快吃掉"）
- **过期区**: 卡片带 1px 实线 `#8b3a2a`，左侧 4px 赤陶竖条，名称加删除线
- **临期区**: 卡片带 1px hairline，天数用 Playfair 600 28px 赤陶色
- **安全区**: 默认折叠，标题行右侧 "展开 ↓"
- **tab**: 底部 4 项文字 tab，active 项下方 2px 赤陶短线
- **添加 tab**: 文字 "+ 添加"，赤陶色
- **状态标签**: 手写感 Caveat 字体，不用胶囊
- **按钮**: 赤陶底白字，圆角 4px，无阴影
- **输入框**: 1px hairline 边框，聚焦时赤陶色

---

## 皮肤 07 · 杂志编辑

### 配色
- bg `#fdfdfb`（报纸白）
- ink `#1a1a1a`
- accent `#c8102e`（深红）
- aux `#6b6b6b`
- hairline `#d8d8d4`
- warn `#c8102e`（临期=accent）
- danger `#1a1a1a`（过期=黑）
- safe `#6b6b6b`（安全=灰）

### 字体
- Display: 'Playfair Display' 900 italic（大标题）
- Body: 'Source Sans 3' 400/600
- Mono: 'IBM Plex Mono' 400（天数、标签）

### 间距 / 圆角
- 12px 基线网格
- 圆角 0
- 1px 细规则线分隔

### 组件
- **分组标题**: Playfair 900 italic 22px + 英文小标签（"EXPIRED"/"EXPIRING"/"SAFE"）IBM Plex Mono 10px 大写
- **过期区**: 上下 1px 黑实线夹住，名称加删除线，天数 IBM Plex Mono 24px
- **临期区**: 左侧 3px 红竖条，天数红色
- **安全区**: 折叠，灰色
- **tab**: 文字 tab，active 项 Playfair italic 加粗
- **添加 tab**: "+ ADD"，红色
- **按钮**: 黑底白字，圆角 0，无阴影
- **输入框**: 底部 1px 黑线，聚焦时红线

---

## 皮肤 11 · 瑞士网格

### 配色
- bg `#ffffff`
- ink `#111111`
- accent `#e2001a`（瑞士正红）
- aux `#8a8a8a`
- hairline `#e5e5e5`
- warn `#e2001a`
- danger `#111111`
- safe `#8a8a8a`

### 字体
- 'Inter' 400/600/700（Inter Tight 兜底）
- 天数: Inter 700 tabular-nums

### 间距 / 圆角
- 8px 倍数，行高 1.65
- 圆角 0
- 1px 网格线

### 组件
- **左侧竖线**: 全页左侧 1px 竖线距边 20px，贯穿始终
- **分组标题**: 大写 12px 600 字距 0.1em + 编号（"01 — EXPIRED"）
- **列表项编号**: 每项左侧 01/02/03 mono 小号灰
- **过期区**: 黑底白字卡片
- **临期区**: 红色天数 32px
- **安全区**: 折叠，灰色
- **tab**: 文字 tab，active 加粗 + 上方 2px 红线
- **添加 tab**: "+ 添加"，红底白字方块
- **按钮**: 红底白字，圆角 0
- **输入框**: 1px 灰边，聚焦 1px 红边

---

## 皮肤 15 · 包豪斯

### 配色
- bg `#f2f0ea`（暖白纸）
- ink `#1a1a1a`
- red `#e63946`（过期/圆）
- orange `#f4a261`（临期/三角）
- teal `#2a9d8f`（安全/方）
- yellow `#ffb703`（点缀）

### 字体
- Display: 'Archivo Black' 400
- Body: 'Archivo' 400/600

### 间距 / 圆角 / 阴影
- 8px 倍数
- 圆角 0
- 硬阴影 `box-shadow: 4px 4px 0 #1a1a1a`
- 2px 黑色边框

### 组件
- **几何状态语言**: 圆形=过期（红）、三角形=临期（橙）、正方形=安全（蓝绿），纯 CSS 画（border-radius 50% / clip-path polygon / 方块）
- **分组标题**: Archivo Black 20px + 几何形状图标
- **过期区**: 红底白字卡片 + 硬阴影
- **临期区**: 白底 2px 黑边卡片 + 左侧橙色三角形 + 硬阴影
- **安全区**: 折叠，白底灰边
- **tab**: 文字 tab，active 项黑底白字
- **添加 tab**: 黄色方块黑字 "+"
- **按钮**: 黄底黑字 2px 黑边 + 硬阴影
- **输入框**: 2px 黑边，聚焦时阴影偏移
