// 包豪斯设计守护脚本 - 检查硬编码违规（Node.js 原生实现，跨平台）
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

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
    exclude: /Theme\.|import|\/\//,
    excludeComment: true,
  },
  {
    name: '写死 rgba',
    pattern: /rgba\(/,
    exclude: /Theme\./,
    excludeComment: true,
  },
];

// 递归读取目录下所有 .ets 文件
function getEtsFiles(dir) {
  const files = [];
  const items = fs.readdirSync(dir, { withFileTypes: true });
  for (const item of items) {
    const fullPath = path.join(dir, item.name);
    if (item.isDirectory()) {
      files.push(...getEtsFiles(fullPath));
    } else if (item.name.endsWith('.ets')) {
      files.push(fullPath);
    }
  }
  return files;
}

// 检查单个文件
function checkFile(filePath, rule) {
  const content = fs.readFileSync(filePath, 'utf8');
  const lines = content.split('\n');
  const violations = [];

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    // 跳过注释
    if (rule.excludeComment && (line.trim().startsWith('//') || line.trim().startsWith('/*'))) {
      continue;
    }
    // 排除特定模式
    if (rule.exclude && rule.exclude.test(line)) {
      continue;
    }
    if (rule.pattern.test(line)) {
      violations.push({ line: i + 1, content: line.trim() });
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
