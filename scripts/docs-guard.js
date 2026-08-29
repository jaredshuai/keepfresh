// docs 可达性守护 - docs/**/*.md 必须能从 AGENTS.md 的引用链到达（Node.js 原生实现，跨平台）
// 断链形态：文档存在但入口文档不引用它 → 接手者永远发现不了（docs/audit-bauhaus.md 曾是孤儿）。
// 只校验「能被找到」，不校验内容质量。白名单不掩盖——每条附理由。
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.join(__dirname, '..');

// 引用链入口：接手的 AI 默认读这些文件
const ROOTS = ['AGENTS.md', 'CONTEXT.md', 'DESIGN.md'];

// 白名单（归档/产出类文档，由各自工作流发现，不需引用链可达）
const WHITELIST = [
  { prefix: 'docs/superpowers/', reason: 'superpowers 工作流产出（plans/specs），由 skill 自身发现' },
  { prefix: 'docs/prompts/', reason: '历史执行 prompt 存档，溯源用途' },
  { prefix: 'docs/research-prompts/', reason: '历史调研 prompt 存档，溯源用途' },
  { prefix: 'docs/design.md', reason: '旧版「清新自然」设计规范存档，已被根 DESIGN.md（包豪斯）取代，文件头已标废弃' },
];

function listMarkdownFiles(dir) {
  const out = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      out.push(...listMarkdownFiles(full));
    } else if (entry.name.endsWith('.md')) {
      out.push(path.relative(rootDir, full).split(path.sep).join('/'));
    }
  }
  return out;
}

// B 从 F 可达：F 的内容含 B 的仓根相对路径、B 相对 F 所在目录的相对路径，或 B 所在目录的前缀引用
function references(content, fromRel, toRel) {
  const fromDir = path.posix.dirname(fromRel);
  const relTo = path.posix.relative(fromDir, toRel);
  // 目录前缀仅限 docs 的子目录（如 "docs/adr/"）；顶层 "docs/" 不算，
  // 否则任何路径引用都会误覆盖顶层文档
  const toDir = path.posix.dirname(toRel);
  const dirHit = toDir.includes('/') && content.includes(toDir + '/');
  return content.includes(toRel) || content.includes(relTo) || dirHit;
}

console.log('🔍 docs 可达性守护检查（防孤儿文档）...\n');

const docsDir = path.join(rootDir, 'docs');
const universe = listMarkdownFiles(docsDir);
// 遍历节点 = docs 全集 + 根目录入口文档（CONTEXT.md / DESIGN.md 在链路上当中转）
const nodes = [...universe, ...ROOTS];

const reachable = new Set(ROOTS);
const queue = [...ROOTS];
const missingRoots = [];
while (queue.length > 0) {
  const current = queue.shift();
  let content;
  try {
    content = fs.readFileSync(path.join(rootDir, current), 'utf8');
  } catch {
    // 入口文档缺失没有任何别的守卫管，而 AGENTS.md 踩坑地图与 design-guard
    // 的报错文案都指向它们——静默跳过会让断链无人知晓，必须显式失败
    missingRoots.push(current);
    continue;
  }
  for (const candidate of nodes) {
    if (reachable.has(candidate)) continue;
    if (references(content, current, candidate)) {
      reachable.add(candidate);
      queue.push(candidate);
    }
  }
}

if (missingRoots.length > 0) {
  console.error(`❌ 入口文档缺失 (${missingRoots.length} 个) —— 引用链的根断了，踩坑地图与守卫报错文案都指向它们:`);
  for (const v of missingRoots) {
    console.error(`     ${v}`);
  }
  console.error('   修法：恢复文件；若确要改名/删除，同步更新 AGENTS.md 踩坑地图与本脚本 ROOTS');
  process.exit(1);
}

const violations = [];
const whitelistHits = [];
for (const doc of universe) {
  if (reachable.has(doc)) continue;
  const wl = WHITELIST.find((w) => doc.startsWith(w.prefix));
  if (wl) {
    whitelistHits.push(`${doc} —— ${wl.reason}`);
  } else {
    violations.push(doc);
  }
}

if (violations.length > 0) {
  console.error(`❌ 孤儿文档 (${violations.length} 个) —— 从 AGENTS.md 引用链不可达，接手者发现不了:`);
  for (const v of violations) {
    console.error(`     ${v}`);
  }
  console.error('   修法：在合适的上游文档补一行引用，或登记白名单（附理由）');
}

console.log(`✅ 可达 ${reachable.size - ROOTS.length}/${universe.length}，白名单 ${whitelistHits.length} 条:`);
for (const h of whitelistHits) {
  console.log(`   · ${h}`);
}
console.log('');

if (violations.length > 0) {
  console.error('💥 docs 可达性守护失败，请修复上述问题后再提交');
  process.exit(1);
} else {
  console.log('✅ docs 可达性守护通过');
}
