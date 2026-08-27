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
  },
  {
    name: '硬编码色值',
    pattern: /#[0-9a-fA-F]{3,8}\b/,
    exclude: /Theme\.|import/,
    excludeComment: true,
  },
  {
    name: '写死 rgba',
    pattern: /rgba\(/,
    exclude: /Theme\./,
    excludeComment: true,
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

console.log('');
if (hasError) {
  console.error('💥 设计守护失败，请修复上述问题后再提交');
  process.exit(1);
} else {
  console.log('✅ 包豪斯设计守护全部通过');
}
