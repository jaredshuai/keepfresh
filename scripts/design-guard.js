// 包豪斯设计守护脚本 - 检查硬编码违规（Node.js 原生实现，跨平台）
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { getEtsFiles } from './lib/ets-files.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.join(__dirname, '..');
const pagesDir = path.join(rootDir, 'entry', 'src', 'main', 'ets', 'pages');

// 检查规则
const rules = [
  {
    name: '非零圆角',
    pattern: /borderRadius\((?!0\))/,  // borderRadius(非0)
    exclude: /Theme\./,
    excludeComment: true,
    doc: 'DESIGN.md（圆角/色值令牌统一在 common/Theme.ets，页面禁写死数值）',
  },
  {
    name: '硬编码色值',
    pattern: /#[0-9a-fA-F]{3,8}\b/,
    exclude: /Theme\.|import/,
    excludeComment: true,
    doc: 'DESIGN.md（圆角/色值令牌统一在 common/Theme.ets，页面禁写死数值）',
  },
  {
    name: '写死 rgba',
    pattern: /rgba\(/,
    exclude: /Theme\./,
    excludeComment: true,
    doc: 'DESIGN.md（圆角/色值令牌统一在 common/Theme.ets，页面禁写死数值）',
  },
];

/**
 * 剥离行内 `//` 注释，但跳过字符串字面量（', ", `）中的 `//`。
 * 避免 URL 等字符串中的 `//` 被误判为注释导致后续代码漏检。
 */
function stripLineComment(line) {
  let result = '';
  let inStr = false;
  let strChar = '';
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (inStr) {
      result += ch;
      if (ch === '\\' && i + 1 < line.length) {
        result += line[i + 1];
        i++;
      } else if (ch === strChar) {
        inStr = false;
      }
    } else {
      if (ch === '/' && line[i + 1] === '/') {
        break;
      }
      result += ch;
      if (ch === '"' || ch === "'" || ch === '`') {
        inStr = true;
        strChar = ch;
      }
    }
  }
  return result;
}

// 检查单个文件
function checkFile(filePath, rule) {
  const content = fs.readFileSync(filePath, 'utf8');
  const lines = content.split('\n');
  const violations = [];
  let inBlockComment = false; // 多行 /* ... */ 注释状态机

  for (let i = 0; i < lines.length; i++) {
    let line = lines[i];

    // ── 1. 处理多行注释 /* ... */（跨行状态） ──
    if (rule.excludeComment) {
      if (inBlockComment) {
        const endIdx = line.indexOf('*/');
        if (endIdx === -1) {
          continue; // 整行在注释块内
        }
        line = line.slice(endIdx + 2); // 保留 */ 之后的代码
        inBlockComment = false;
      }
      // 查找新的 /* 开始
      const startIdx = line.indexOf('/*');
      if (startIdx !== -1) {
        const endIdx = line.indexOf('*/', startIdx + 2);
        if (endIdx === -1) {
          // 行内开启但未结束，后续进入 block 模式
          line = line.slice(0, startIdx);
          inBlockComment = true;
        } else {
          // 同行包含完整 /* ... */，抠掉中间段
          line = line.slice(0, startIdx) + ' ' + line.slice(endIdx + 2);
        }
      }
    }

    // ── 2. 整行纯注释跳过（单行 // 已去注释后可能为空，下面 import 行也会被剥） ──
    if (rule.excludeComment && line.trim().startsWith('//')) {
      continue;
    }

    // ── 3. 字符串感知地剥行内 // 注释，再做 exclude/pattern 检测 ──
    //    避免 URL 字符串中的 // 被误判为注释导致后续代码漏检
    let codeOnly = stripLineComment(line);

    // ── 4. import 声明整行跳过（对需要 import exclude 的规则） ──
    //    单独用 import-only 判断，避免 Theme. 在同一行被一起跳过
    const stripped = codeOnly.trim();
    if (rule.exclude && /^import\s/.test(stripped)) {
      continue;
    }

    // ── 5. 排除特定模式（仅作用于 codeOnly，允许 token 在注释里但不影响代码） ──
    if (rule.exclude && rule.exclude.test(codeOnly)) {
      continue;
    }
    if (rule.pattern.test(codeOnly)) {
      violations.push({ line: i + 1, content: lines[i].trim() });
    }
  }
  return violations;
}

// ── 规则 4：硬阴影样板防回潮（ticket #15）──
// pages/ 下禁止再手写 `margin({ left: Theme.hardShadowOffset` 样板，
// 统一走 common/HardShadow.ets 的 HardShadowCard / HardShadowBox。
// 白名单 = survey 遗留的复用型 builder 微模式（flex 按钮对 / chips /
// margin-trick / constraintSize），逐条附理由；新增样板必须走组件，不得扩白名单。
const SHADOW_RULE = {
  pattern: /margin\(\{\s*left: Theme\.hardShadowOffset/,
  whitelist: [
    { file: /AddItem\.ets$/, re: /constraintSize\(\{\s*minWidth: 88 \}\)/, reason: '主按钮阴影 constraintSize 微模式' },
    { file: /AddItem\.ets$/, re: /right: Theme\.smallGap \+ Theme\.hardShadowOffset/, reason: '自定义字段枚举 chips margin-trick 补位' },
    { file: /AddItem\.ets$/, re: /layoutWeight\(1\)/, reason: '胶囊按钮 builder（flex layoutWeight 阴影）' },
    { file: /Settings\.ets$/, re: /Theme\.chipHeight/, reason: 'chipButton 复用 builder（定高自适应宽）' },
    { file: /Settings\.ets$/, re: /formatTime/, reason: '提醒时间行（0 尺寸死阴影，清理候选）' },
    { file: /Settings\.ets$/, re: /layoutWeight\(1\)/, reason: '主/次按钮 builder（flex layoutWeight 阴影）' },
    { file: /ItemDetail\.ets$/, re: /layoutWeight\(1\)/, reason: 'primaryBtn builder（flex layoutWeight 阴影）' },
    { file: /CategoryManager\.ets$/, re: /layoutWeight\(1\)/, reason: '取消/保存按钮（flex layoutWeight 阴影）' },
  ],
};

function checkShadowRule() {
  const violations = [];
  let whitelistHits = 0;
  for (const file of etsFiles) {
    const rel = path.relative(rootDir, file);
    const lines = fs.readFileSync(file, 'utf8').split('\n');
    for (let i = 0; i < lines.length; i++) {
      if (!SHADOW_RULE.pattern.test(lines[i])) continue;
      const window = lines.slice(Math.max(0, i - 3), i + 26).join('\n');
      const wl = SHADOW_RULE.whitelist.find((w) => w.file.test(rel) && w.re.test(window));
      if (wl) {
        whitelistHits++;
      } else {
        violations.push({ line: i + 1, content: lines[i].trim(), file: rel });
      }
    }
  }
  return { violations, whitelistHits };
}

// 规则 5：Button 默认胶囊防回潮（docs/agents/arkui-pitfalls.md#button-capsule）
// ArkUI Button 默认 Capsule 类型，胶囊圆角由系统强制生成，borderRadius(0) 无效。
// \bButton\( 词边界避免误伤 iconButton/backButton/smallIconBtn 等以 Button 结尾的标识符；
// 语句行及其后 2 行内出现 ButtonType.（Normal / Circle 均可）即放行——容忍类型声明换行。
function checkButtonRule() {
  const violations = [];
  const pattern = /\bButton\(/;
  const exclude = /ButtonType\./;
  for (const file of etsFiles) {
    const rel = path.relative(rootDir, file);
    const lines = fs.readFileSync(file, 'utf8').split('\n');
    for (let i = 0; i < lines.length; i++) {
      const clean = stripLineComment(lines[i]);
      if (!pattern.test(clean) || exclude.test(clean)) continue;
      const window = lines.slice(i, i + 3).map(stripLineComment).join('\n');
      if (exclude.test(window)) continue;
      violations.push({ line: i + 1, content: lines[i].trim(), file: rel });
    }
  }
  return violations;
}

// 规则 6：Canvas 静态绘制防回潮（docs/agents/arkui-pitfalls.md#canvas-px-not-vp）
// Canvas 路径坐标按物理像素解释、不随 vp 缩放，高分屏上静态几何图形画得又小又偏
// （实测：3.3x 屏上三角只有约 1/3 大小且缩进不齐）。静态形状一律用原生组件
// Circle / Rect / Polygon。白名单按文件级豁免，只留给真正需要自由绘制的场景
// （须附理由，且路径坐标自行做 vp→px 换算），当前清零。
const CANVAS_WHITELIST = [
  // { file: /Xxx\.ets$/, reason: '真实自由绘制场景说明（vp→px 换算方式）' },
];

function checkCanvasRule() {
  const violations = [];
  const pattern = /\bCanvas\(\)/;
  for (const file of etsFiles) {
    const rel = path.relative(rootDir, file);
    if (CANVAS_WHITELIST.some((w) => w.file.test(rel))) continue;
    const lines = fs.readFileSync(file, 'utf8').split('\n');
    for (let i = 0; i < lines.length; i++) {
      const clean = stripLineComment(lines[i]);
      if (!pattern.test(clean)) continue;
      violations.push({ line: i + 1, content: lines[i].trim(), file: rel });
    }
  }
  return violations;
}

// 规则 7：Stack 子层 layoutWeight 哑弹防回潮（docs/agents/arkui-pitfalls.md#layoutweight-axis）
// layoutWeight 只在 Row/Column/Flex 的直接子层参与 weight 分配；Stack 不做 weight 分配，
// 子层写了 layoutWeight 等于没写：面层缩成内容宽、墨影层宽 '100%' 时视觉碎裂
// （实测 #19 整改只修了墨影层，面层漏网 → 设置页按钮渲染成大黑块）。
// 实现：行级容器嵌套栈——容器名 + 花括号深度入栈/出栈，layoutWeight 行的
// 最近宿主容器是 Stack 即违规（属父容器自身的链式 .layoutWeight 已先弹出，不误伤）。
const CONTAINER_OPEN = /\b(Stack|Row|Column|Flex|Grid|GridRow|List|Scroll|Swiper|RelativeContainer)\s*\(/;

function checkStackWeightRule() {
  const violations = [];
  for (const file of etsFiles) {
    const rel = path.relative(rootDir, file);
    const lines = fs.readFileSync(file, 'utf8').split('\n');
    // 嵌套栈：{ name, depth }，depth = 该容器 lambda 的花括号深度
    const frames = [];
    let depth = 0;
    for (let i = 0; i < lines.length; i++) {
      const clean = stripLineComment(lines[i]);
      // 1) 先按本行 `}` 收缩深度并弹出已关闭的容器 lambda（链式 .layoutWeight 属容器自身，不误判）
      let net = 0;
      for (const ch of clean) {
        if (ch === '{') net++;
        else if (ch === '}') net--;
      }
      depth += net < 0 ? net : 0; // 先应用收缩部分
      while (frames.length > 0 && depth < frames[frames.length - 1].depth) frames.pop();
      if (net > 0) depth += net;  // 展开部分在弹出判定之后计入

      // 2) 本行 layoutWeight：最近宿主是 Stack 直接子层 → 哑弹
      if (/\.layoutWeight\(/.test(clean) && frames.length > 0
        && frames[frames.length - 1].name === 'Stack'
        && depth === frames[frames.length - 1].depth) {
        violations.push({ line: i + 1, content: lines[i].trim(), file: rel });
      }

      // 3) 本行容器开括号（取最后一个，链式声明风格一行至多一个容器开 lambda）
      const m = clean.match(CONTAINER_OPEN);
      if (m && net > 0) {
        frames.push({ name: m[1], depth });
      }
    }
  }
  return violations;
}

// 主逻辑
let hasError = false;
const etsFiles = getEtsFiles(pagesDir);

console.log('🔍 包豪斯设计守护检查...\n');

for (const rule of rules) {
  let allViolations = [];
  for (const file of etsFiles) {
    const violations = checkFile(file, rule);
    if (violations.length > 0) {
      const relPath = path.relative(rootDir, file);
      allViolations.push({ file: relPath, violations });
    }
  }

  if (allViolations.length > 0) {
    console.error(`❌ ${rule.name} (${allViolations.reduce((s, v) => s + v.violations.length, 0)} 处):`);
    console.error(`   详见 ${rule.doc}`);
    for (const { file, violations } of allViolations.slice(0, 3)) {
      console.error(`   ${file}:`);
      for (const v of violations.slice(0, 3)) {
        console.error(`     L${v.line}: ${v.content}`);
      }
      if (violations.length > 3) console.error(`     ... 还有 ${violations.length - 3} 处`);
    }
    if (allViolations.length > 3) console.error(`   ... 还有 ${allViolations.length - 3} 个文件`);
    hasError = true;
  } else {
    console.log(`✅ ${rule.name}: 通过`);
  }
}

// 规则 4：硬阴影样板防回潮
{
  const { violations, whitelistHits } = checkShadowRule();
  if (violations.length > 0) {
    console.error(`❌ 硬阴影样板防回潮 (${violations.length} 处) —— 请改用 common/HardShadow.ets 组件:`);
    console.error('   阴影层高度语义陷阱详见 docs/agents/arkui-pitfalls.md#percent-height-in-scroll');
    for (const v of violations.slice(0, 8)) {
      console.error(`     ${v.file}:L${v.line}: ${v.content}`);
    }
    if (violations.length > 8) console.error(`     ... 还有 ${violations.length - 8} 处`);
    hasError = true;
  } else {
    console.log(`✅ 硬阴影样板防回潮: 通过`);
    console.log(`   组件化硬阴影 + 白名单长尾 ${whitelistHits} 条（附理由见 SHADOW_RULE）`);
  }
}

// 规则 5：Button 默认胶囊防回潮
{
  const violations = checkButtonRule();
  if (violations.length > 0) {
    console.error(`❌ Button 默认胶囊 (${violations.length} 处) —— ArkUI Button 默认 Capsule 类型，无视 borderRadius(0)，与包豪斯零圆角冲突。`);
    console.error('   修法：补 { type: ButtonType.Normal, stateEffect: true }。详见 docs/agents/arkui-pitfalls.md#button-capsule');
    for (const v of violations.slice(0, 8)) {
      console.error(`     ${v.file}:L${v.line}: ${v.content}`);
    }
    if (violations.length > 8) console.error(`     ... 还有 ${violations.length - 8} 处`);
    hasError = true;
  } else {
    console.log('✅ Button 默认胶囊防回潮: 通过');
  }
}

// 规则 6：Canvas 静态绘制防回潮
{
  const violations = checkCanvasRule();
  if (violations.length > 0) {
    console.error(`❌ Canvas 静态绘制 (${violations.length} 处) —— Canvas 路径坐标是物理像素、不随 vp 缩放，高分屏上静态几何图形会画小画偏（缩进不齐）。`);
    console.error('   静态形状改用原生组件 Circle/Rect/Polygon；确需自由绘制在 CANVAS_WHITELIST 登记理由。详见 docs/agents/arkui-pitfalls.md#canvas-px-not-vp');
    for (const v of violations.slice(0, 8)) {
      console.error(`     ${v.file}:L${v.line}: ${v.content}`);
    }
    if (violations.length > 8) console.error(`     ... 还有 ${violations.length - 8} 处`);
    hasError = true;
  } else {
    console.log('✅ Canvas 静态绘制防回潮: 通过');
  }
}

// 规则 7：Stack 子层 layoutWeight 哑弹防回潮
{
  const violations = checkStackWeightRule();
  if (violations.length > 0) {
    console.error(`❌ Stack 子层 layoutWeight 哑弹 (${violations.length} 处) —— Stack 不参与 weight 分配，子层 layoutWeight 等于没写：面层缩成内容宽、墨影 full-width 时渲染成大黑块（设置页按钮事故）。`);
    console.error('   修法：Stack 子层一律 .width(\'100%\')（+ alignContent TopStart 定几何），weight 只写在 Stack 自身（作为 Row/Column 子层时）。详见 docs/agents/arkui-pitfalls.md#layoutweight-axis');
    for (const v of violations.slice(0, 8)) {
      console.error(`     ${v.file}:L${v.line}: ${v.content}`);
    }
    if (violations.length > 8) console.error(`     ... 还有 ${violations.length - 8} 处`);
    hasError = true;
  } else {
    console.log('✅ Stack 子层 layoutWeight 哑弹防回潮: 通过');
  }
}

console.log('');
if (hasError) {
  console.error('💥 设计守护失败，请修复上述问题后再提交');
  process.exit(1);
} else {
  console.log('✅ 包豪斯设计守护全部通过');
}
