# HandoffBundle · KeepFresh 包豪斯皮肤

> 交付时间：2026-08-24
> 皮肤：15 包豪斯（暖白纸底 + 三原色几何 + 硬阴影）
> 布局：变体 C（状态分组：已过期 / 临期 / 安全折叠）
> QA 状态：通过（10 项 AI 味 0 检出，可访问性/层级/交互全部修复后通过）

---

## 交付物清单

| 文件 | 说明 |
|------|------|
| `15-index.html` | 首页：状态分组列表 |
| `15-add.html` | 添加物资表单 |
| `15-detail.html` | 物资详情（以鲜牛奶为例） |
| `15-settings.html` | 设置页 |
| `DESIGN-SYSTEMS.md` | 4 套设计系统完整规范（含包豪斯） |
| `QA-REPORT.md` | 完整 QA 报告 + 修复记录 |

---

## 包豪斯设计系统速查

### 配色

| Token | 值 | 用途 |
|-------|-----|------|
| `--paper` | `#f2f0ea` | 页面背景 |
| `--ink` | `#1a1a1a` | 文字/边框/阴影 |
| `--red` | `#e63946` | 过期状态/圆形 |
| `--orange` | `#f4a261` | 临期状态/三角形 |
| `--teal` | `#2a9d8f` | 安全状态/正方形 |
| `--yellow` | `#ffb703` | 点缀（已不用于文字底） |
| `--yellow-dark` | `#d69a00` | 主按钮底（白字） |

### 字体

- Display: `Archivo Black` 400
- Body: `Archivo` 400/600
- CDN: `https://fonts.googleapis.com/css2?family=Archivo+Black&family=Archivo:wght@400;600&display=swap`

### 间距 / 圆角 / 阴影

- 间距：8px 倍数
- 圆角：0（全局）
- 阴影：`box-shadow: 4px 4px 0 #1a1a1a`
- 边框：2px 实线 `#1a1a1a`

### 几何状态语言

| 状态 | 形状 | 颜色 | CSS |
|------|------|------|-----|
| 已过期 | 圆形 | 红 | `width:16px;height:16px;border-radius:50%;background:#e63946;` |
| 临期 | 三角形 | 橙 | `width:0;height:0;border-left:9px solid transparent;border-right:9px solid transparent;border-bottom:16px solid #f4a261;` |
| 安全 | 正方形 | 蓝绿 | `width:16px;height:16px;background:#2a9d8f;` |

### 组件状态

所有交互元素包含：default / active / focus / disabled（移动端无 hover）

---

## ArkUI 落地建议

1. **几何形状**：ArkUI 用 `Circle()` / `Polygon()` / `Rect()` 或 `Path` 绘制，或用 `Canvas`
2. **硬阴影**：ArkUI 不直接支持偏移阴影，可用 `Stack` 叠加两层模拟（下层黑色偏移 4px）
3. **字体**：Archivo Black 需下载 ttf 放入 `resources/base/media/`，用 `fontFamily` 引用
4. **色彩**：直接映射到 `AppScope/resources/base/element/color.json`
5. **状态分组**：用 `LazyForEach` + 分组 header 实现，安全区用 `if/else` 条件渲染折叠

---

## 后续可选

- **make-tweakable**：如需微调配色/间距，可在原型上加浮动调参面板
- **generate-variations**：如需探索包豪斯的不同密度/氛围变体
- **make-a-deck**：如需给团队做设计评审演示文稿
