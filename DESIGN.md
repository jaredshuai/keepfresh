# KeepFresh 设计系统

> **当前版本：包豪斯（Bauhaus）**
> 选定时间：2026-08-24
> 布局：变体 C（状态分组）
> 原型文件：`keepfresh-ui-preview.design/final/15-*.html`

---

## 设计决策记录

| 日期 | 决策 | 原因 |
|------|------|------|
| 2026-08-24 | 从星巴克绿改为包豪斯 | 原方案被判定为"AI 味太重"（奶油底+居中 FAB+通用绿） |
| 2026-08-24 | 布局选定变体 C（状态分组） | 用户要求"信息密、一眼扫全"，分组布局让紧急信号最强 |
| 2026-08-24 | 皮肤选定 15 包豪斯 | 浅色、排版驱动、几何图形张力、无暗色 |

### 淘汰方案

| 模板 | 淘汰原因 |
|------|---------|
| 01 编辑极简 | 暗色底，用户明确不要 |
| 02 电影感深空 | 暗色底 |
| 03 暖纸手作 | 候选但最终未选 |
| 04 数据终端 | 暗色底 |
| 05 粗野撞色 | 视觉冲击过强 |
| 06 液态玻璃 | 太像 Apple 官方模板 |
| 07 杂志编辑 | 候选但最终未选 |
| 08 游戏化活泼 | 太儿童向 |
| 09 日式禅意 | 候选但最终未选 |
| 10 复古未来 | 暗色底 |
| 11 瑞士网格 | 候选但最终未选 |
| 12 超市收银条 | 候选但最终未选 |
| 13 宣纸墨迹 | 候选但最终未选 |
| 14 北欧晨光 | 候选但最终未选 |
| 16 植物园 | 候选但最终未选 |

---

## 包豪斯设计系统

### 核心主张

暖白纸底 + 纯黑边框 + 硬阴影 + 三原色几何形状。用圆/三角/方三种基本几何形作为状态语言，零圆角，零渐变，排版驱动。

### 配色

| Token | 值 | 用途 |
|-------|-----|------|
| `--paper` | `#f2f0ea` | 页面背景（暖白纸） |
| `--ink` | `#1a1a1a` | 文字/边框/阴影 |
| `--red` | `#e63946` | 过期状态/圆形 |
| `--orange` | `#f4a261` | 临期状态/三角形 |
| `--teal` | `#2a9d8f` | 安全状态/正方形 |
| `--yellow` | `#ffb703` | 点缀（不用于文字底） |
| `--yellow-dark` | `#d69a00` | 主按钮底（配白字） |

### 字体

- **Display**: `Archivo Black` 400（标题、大数字）
- **Body**: `Archivo` 400/600（正文）
- **CDN**: `https://fonts.googleapis.com/css2?family=Archivo+Black&family=Archivo:wght@400;600&display=swap`

### 间距 / 圆角 / 阴影

- 间距：8px 倍数（8/16/24/32）
- 圆角：**0**（全局零圆角）
- 阴影：`box-shadow: 4px 4px 0 #1a1a1a`（硬阴影）
- 边框：2px 实线 `#1a1a1a`

### 几何状态语言

| 状态 | 形状 | 颜色 | CSS |
|------|------|------|-----|
| 已过期 | 圆形 | 红 `#e63946` | `width:16px;height:16px;border-radius:50%;background:#e63946;` |
| 临期 | 三角形 | 橙 `#f4a261` | `width:0;height:0;border-left:9px solid transparent;border-right:9px solid transparent;border-bottom:16px solid #f4a261;` |
| 安全 | 正方形 | 蓝绿 `#2a9d8f` | `width:16px;height:16px;background:#2a9d8f;` |

### 组件规范

#### 按钮

| 类型 | 背景 | 文字 | 边框 | 阴影 |
|------|------|------|------|------|
| 主要按钮 | `--yellow-dark` | 白 | 2px `--ink` | 4px 4px 0 `--ink` |
| 次要按钮 | 白 | `--ink` | 2px `--ink` | 4px 4px 0 `--ink` |
| 危险按钮 | 白 | `--red` | 2px `--ink` | 4px 4px 0 `--ink` |

- Active 状态：`box-shadow: 1px 1px 0 var(--ink); transform: translate(3px, 3px);`
- Disabled：`opacity: 0.5; cursor: not-allowed; box-shadow: 2px 2px 0 var(--ink);`
- Focus：`outline: 3px solid var(--ink); outline-offset: 2px;`
- 最小高度：48px（触控目标）

#### 卡片

- 背景：白 `#ffffff`
- 边框：2px `--ink`
- 阴影：4px 4px 0 `--ink`
- 内边距：16px

#### 输入框

- 背景：白
- 边框：2px `--ink`
- 聚焦：阴影偏移 `box-shadow: 4px 4px 0 var(--ink)`
- 占位符：`#a8a498`

#### 底部 Tab

- 4 等分网格
- Active：黑底白字
- 添加 Tab：黄底（`--yellow-dark`）黑字方块 "+"

### 布局：变体 C（状态分组）

```
┌─────────────────────────┐
│ KeepFresh.    6项·1过期·3临期 │
├─────────────────────────┤
│ ● 已过期                 │
│ ┌─────────────────────┐ │
│ │ 酸奶（红底白字卡片）  -2天 │ │
│ └─────────────────────┘ │
├─────────────────────────┤
│ ▲ 临期                   │
│ ┌─────────────────────┐ │
│ │▲布洛芬    2天        │ │
│ │▲鲜牛奶    3天        │ │
│ │▲鸡蛋      5天        │ │
│ └─────────────────────┘ │
├─────────────────────────┤
│ ■ 安全 · 9项（折叠）      │
├─────────────────────────┤
│ [首页] [+] [提醒] [我的]  │
└─────────────────────────┘
```

---

## 可访问性

- 对比度：所有文字/背景组合 ≥ 4.5:1（WCAG AA）
- Focus ring：3px 黑色 outline，offset 2px
- 触控目标：≥ 48px
- 动效降级：`@media (prefers-reduced-motion: reduce)` 支持
- 语义化：分类/阈值选择用 `button role="radio"`，开关用 `role="switch"`

---

## 文件位置

| 文件 | 说明 |
|------|------|
| `keepfresh-ui-preview.design/final/15-index.html` | 首页原型 |
| `keepfresh-ui-preview.design/final/15-add.html` | 添加物资原型 |
| `keepfresh-ui-preview.design/final/15-detail.html` | 详情页原型 |
| `keepfresh-ui-preview.design/final/15-settings.html` | 设置页原型 |
| `keepfresh-ui-preview.design/final/QA-REPORT.md` | QA 检查报告 |
| `keepfresh-ui-preview.design/final/HANDOFF.md` | 开发者交接说明 |
| `keepfresh-ui-preview.design/final/DESIGN-SYSTEMS.md` | 4 套皮肤完整规范 |
| `keepfresh-ui-preview.design/compare/` | 16 套模板对比稿（参考） |

---

## 禁止事项

- 不要暗色模式
- 不要紫色或蓝紫渐变
- 不要奶油底+高对比衬线+赤陶橙（AI 默认审美）
- 不要近黑底+单一酸性绿或朱红
- 不要三列 icon 卡片
- 不要 emoji 当 icon
- 不要 lorem ipsum
- 不要默认 Inter/Roboto/Arial 字体
- 不要圆角（全局零圆角是包豪斯签名元素）
