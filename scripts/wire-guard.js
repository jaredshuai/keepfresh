// 接线守护脚本 - 固化「跨层接线审计」不变量为 CI 规则（Node.js 原生实现，跨平台）
// 五条规则：
//   规则 1 · Material 字段 ⇄ DB 行 双向映射完整性（toRow 写入 / rowToMaterial 读取）
//   规则 2 · 建表列（CREATE_TABLE_V2_SQL + migrate ALTER）⊆ toRow 写入键 ∪ 白名单
//   规则 3 · pages 层硬编码预设数据源检测（防陈旧源：合法上下文之外一律违规）
//   规则 4 · 导出 API 必须有非测试外部调用者（零调用者必须进白名单并附理由）
//   规则 5 · 未使用 import 检测（存量进白名单待清理）
// 风格对齐 scripts/design-guard.js：✅/❌ + 中文输出 + 结尾汇总。
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.join(__dirname, '..');
const etsRoot = path.join(rootDir, 'entry', 'src', 'main', 'ets');
const pagesDir = path.join(etsRoot, 'pages');

const DB_FILE = path.join(etsRoot, 'db', 'MaterialDb.ets');
const MODEL_FILE = path.join(etsRoot, 'model', 'Material.ets');
const EXPIRY_FILE = path.join(etsRoot, 'service', 'ExpiryService.ets');
const COMMON_API_FILES = ['QuantityUnit.ets', 'InputNormalize.ets', 'SearchFilter.ets', 'CategoryOrder.ets', 'DateUtils.ets'];

// ─────────────────────────── 白名单（每条附理由） ───────────────────────────

// 规则 1：Material 字段豁免（不要求出现在 toRow 写入键；rowToMaterial 读取侧仍校验）
const RULE1_WHITELIST = {
  id: '自增主键，INSERT 不写（由 SQLite AUTOINCREMENT 分配）；读取侧走 id 列，天然存在',
};

// 规则 2：建表列豁免（不要求出现在 toRow 写入键）
const RULE2_WHITELIST = {
  id: '自增主键，INSERT 不写',
};

// 规则 3：pages 硬编码预设行豁免。按「文件 + 行内容包含特异子串」匹配
//（行号会漂移，不用行号；子串取足够特异的代码片段）。
const RULE3_WHITELIST = [
  {
    file: 'pages/AddItem.ets',
    substring: 'm.location && m.location.length > 0 ? m.location : DEFAULT_LOCATIONS[2]',
    reason: '编辑回填兜底：编辑历史记录无位置时的兜底默认',
  },
  {
    file: 'pages/AddItem.ets',
    substring: 'this.chipGroup(DEFAULT_UNITS',
    reason: '已知缺口：name_defs 无 unit kind、无单位查询 API，单位暂只能预设；待未来支持单位管理后移除',
  },
  // 审计复核新增（任务清单外）：defaults() 提供者行，语义等价于 listEffectiveNames 的 defaults 参数
  {
    file: 'pages/CategoryManager.ets',
    substring: "this.activeKind === 'category' ? DEFAULT_CATEGORIES : DEFAULT_LOCATIONS",
    reason: 'defaults() 提供者：返回值仅作 listEffectiveNames 的 defaults 参数与 isPreset 只读判断，非列表数据源',
  },
];

// 规则 4：零外部调用者的导出 API 豁免
//（test/ 目录不算调用者；定义文件内部互调不算外部调用者，如 softDelete 被 remove 调）
const RULE4_WHITELIST = {
  MaterialDb: {
    listLocations: '已被 listEffectiveNames 取代，清理候选',
    getCustomFieldById: '零调用，清理候选',
    softDelete: 'remove() 内部转发的语义核心，保留 public',
  },
  ExpiryService: {
    getNearExpiryThreshold: '仅测试消费的缓存 getter',
    isExpired: 'getActualStatus/sortBy 内部组合件',
    isExpiringSoon: 'getActualStatus/sortBy 内部组合件',
    riskOrderOf: 'getActualStatus/sortBy 内部组合件',
    sortByRiskAndExpiration: '预留分页/统计，测试覆盖',
    sortByCreatedDesc: '预留分页/统计，测试覆盖',
    sortByExpirationAsc: '预留分页/统计，测试覆盖',
    buildOverview: '预留分页/统计，测试覆盖',
    levelSoftColor: '预留徽标色，清理候选',
    levelBadgeTextColor: '预留徽标色，清理候选',
  },
  common: {
    // CategoryOrder.ets 三个导出：整文件死，清理候选
    normalizeNameList: 'CategoryOrder.ets 整文件死，清理候选',
    moveNameOrder: 'CategoryOrder.ets 整文件死，清理候选',
    mergeWithDefaults: 'CategoryOrder.ets 整文件死，清理候选',
    normalizeNullableText: '预留',
    formatQuantityUnit: '预留展示拼接（AddItem 导入未用，见规则 5 白名单）',
    pad2: 'toDateStr 内部件',
    // 审计复核新增（任务清单外）：InputNormalize 内部组合件，与 softDelete/pad2 同性质
    normalizeText: 'InputNormalize 内部组合件（被 normalizeNullableText/parseNonNegativeInteger 复用）',
    normalizeNonNegativeInteger: 'InputNormalize 内部组合件（被 parseNonNegativeInteger 复用）',
  },
};

// 规则 5：未使用 import 豁免（file 为相对 entry/src/main/ets 的路径）
// 存量未使用导入：先修会改 .ets（接线守护任务禁改），故进白名单标注待清理。
const RULE5_WHITELIST = [
  { file: 'pages/Index.ets', identifier: 'levelColor', reason: '审计发现存量，待清理' },
  { file: 'pages/ItemDetail.ets', identifier: 'levelSoftColor', reason: '审计发现存量，待清理' },
  { file: 'pages/AddItem.ets', identifier: 'formatQuantityUnit', reason: '审计发现存量，待清理' },
  // 审计复核新增（任务说 3 处，实测 ItemDetail 另有 2 处存量，共 5 处）：
  { file: 'pages/ItemDetail.ets', identifier: 'getActualStatus', reason: '审计发现存量（任务清单外，Index 在用同名 API，此处为冗余导入），待清理' },
  { file: 'pages/ItemDetail.ets', identifier: 'DerivedStatus', reason: '审计发现存量（任务清单外，状态机判断改用了 MaterialStatus 直接比较），待清理' },
];

// ─────────────────────────── 通用解析工具 ───────────────────────────

// 递归读取目录下所有 .ets 文件（同 design-guard.js）
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

/**
 * 字符串/注释感知的全文剥离器（复用 design-guard.js stripLineComment 的字符串感知思路，
 * 升级为跨行状态机，可处理 /* ... *​/ 块注释与多行模板字符串）。
 * 返回两个与原文等长的文本（索引一一对应，可互相换算位置）：
 *   raw  —— 注释内容替换为空格、字符串字面量原样保留（规约：出现次数统计只剥注释）
 *   code —— 注释与字符串内容均替换为空格、仅保留引号定界符（用于花括号配对 / import 跨度等结构分析）
 * 换行全部保留，行号与原文对齐。
 */
function stripSource(content) {
  let raw = '';
  let code = '';
  let state = 'code'; // 'code' | 'str' | 'line' | 'block'
  let strChar = '';
  for (let i = 0; i < content.length; i++) {
    const ch = content[i];
    const next = i + 1 < content.length ? content[i + 1] : '';
    if (state === 'code') {
      if (ch === '/' && next === '/') {
        state = 'line';
        raw += '  ';
        code += '  ';
        i++;
      } else if (ch === '/' && next === '*') {
        state = 'block';
        raw += '  ';
        code += '  ';
        i++;
      } else if (ch === '"' || ch === "'" || ch === '`') {
        state = 'str';
        strChar = ch;
        raw += ch;
        code += ch;
      } else {
        raw += ch;
        code += ch;
      }
    } else if (state === 'str') {
      if (ch === '\\' && next !== '') {
        raw += ch + next;
        code += '  ';
        i++;
      } else if (ch === strChar) {
        state = 'code';
        raw += ch;
        code += ch;
      } else {
        raw += ch;
        code += ' ';
      }
    } else if (state === 'line') {
      if (ch === '\n') {
        state = 'code';
        raw += '\n';
        code += '\n';
      } else {
        raw += ' ';
        code += ' ';
      }
    } else { // block
      if (ch === '*' && next === '/') {
        state = 'code';
        raw += '  ';
        code += '  ';
        i++;
      } else if (ch === '\n') {
        raw += '\n';
        code += '\n';
      } else {
        raw += ' ';
        code += ' ';
      }
    }
  }
  return { raw, code };
}

/** 提取全部具名 import 语句（支持多行 import 块与 import type），返回跨度与标识符 */
function findImports(code) {
  const imports = [];
  const re = /import\s+(?:type\s+)?\{([^}]*)\}\s*from\s*['"][^'"]*['"]/g;
  let m;
  while ((m = re.exec(code)) !== null) {
    const names = m[1]
      .split(',')
      .map(s => s.trim())
      .filter(s => s.length > 0)
      .map(s => s.split(/\s+as\s+/).pop().trim());
    imports.push({ start: m.index, end: m.index + m[0].length, names });
  }
  return imports;
}

/** 统计 text 中标识符出现次数，跳过 import 语句跨度内的出现（含模块路径中的同名单词） */
function countOutsideImports(text, imports, name) {
  const re = new RegExp(`\\b${name}\\b`, 'g');
  let count = 0;
  let m;
  while ((m = re.exec(text)) !== null) {
    const idx = m.index;
    let inImport = false;
    for (const imp of imports) {
      if (idx >= imp.start && idx < imp.end) {
        inImport = true;
        break;
      }
    }
    if (!inImport) {
      count++;
    }
  }
  return count;
}

/** 定位 headerRe 匹配处之后的配对花括号块（在 code 上做，字符串/注释中的 {} 不会干扰配对） */
function findBracedBlock(code, headerRe) {
  const m = headerRe.exec(code);
  if (!m) {
    return null;
  }
  let open = -1;
  for (let i = m.index + m[0].length; i < code.length; i++) {
    if (code[i] === '{') {
      open = i;
      break;
    }
    if (code[i] === '}') {
      return null; // 头部之后先遇 }，异常
    }
  }
  if (open === -1) {
    return null;
  }
  let depth = 1;
  for (let i = open + 1; i < code.length; i++) {
    if (code[i] === '{') {
      depth++;
    } else if (code[i] === '}') {
      depth--;
      if (depth === 0) {
        return { start: open + 1, end: i };
      }
    }
  }
  return null;
}

/** 读取并预解析一个 .ets 文件 */
function readEts(file) {
  const content = fs.readFileSync(file, 'utf8');
  const stripped = stripSource(content);
  const imports = findImports(stripped.code);
  return { file, content, stripped, imports };
}

/** 相对 etsRoot 的正斜杠路径（白名单匹配用） */
function relPath(file) {
  return path.relative(etsRoot, file).replace(/\\/g, '/');
}

// ─────────────────────────── 规则实现 ───────────────────────────

// 规则 1 · Material 字段 ⇄ DB 行 双向映射完整性
function runRule1() {
  const model = readEts(MODEL_FILE);
  const db = readEts(DB_FILE);

  const iface = findBracedBlock(model.stripped.code, /export\s+interface\s+Material\b/);
  if (!iface) {
    return { violations: ['未能在 model/Material.ets 定位 export interface Material 块'], whitelistHits: [], stat: '' };
  }
  const fields = [...model.stripped.raw.slice(iface.start, iface.end)
    .matchAll(/(?:^|\n)\s*(\w+)\s*\??\s*:/g)].map(m => m[1]);

  const toRowBlock = findBracedBlock(db.stripped.code, /(?:^|\n)\s*(?:private\s+)?toRow\s*\(/);
  const toRowKeys = new Set(toRowBlock
    ? [...db.stripped.raw.slice(toRowBlock.start, toRowBlock.end).matchAll(/['"](\w+)['"]\s*:/g)].map(m => m[1])
    : []);
  const rtmBlock = findBracedBlock(db.stripped.code, /(?:^|\n)\s*(?:private\s+)?rowToMaterial\s*\(/);
  const rtmCols = new Set(rtmBlock
    ? [...db.stripped.raw.slice(rtmBlock.start, rtmBlock.end).matchAll(/getColumnIndex\(\s*['"](\w+)['"]\s*\)/g)].map(m => m[1])
    : []);

  const violations = [];
  const whitelistHits = [];
  if (!toRowBlock) {
    violations.push('未能在 db/MaterialDb.ets 定位 toRow 方法体');
  }
  if (!rtmBlock) {
    violations.push('未能在 db/MaterialDb.ets 定位 rowToMaterial 方法体');
  }
  for (const field of fields) {
    // 驼峰 → 下划线（quantity 例外：迁移库读取列 quantity_text）
    const snake = field.replace(/([a-z0-9])([A-Z])/g, '$1_$2').toLowerCase();
    const candidates = field === 'quantity' ? [snake, 'quantity_text'] : [snake];
    const reason = RULE1_WHITELIST[field];
    if (reason) {
      whitelistHits.push(`Material.${field} —— ${reason}`);
    } else if (!candidates.some(k => toRowKeys.has(k))) {
      violations.push(`Material.${field} 缺 toRow 写入键（期望：${candidates.join(' / ')}）`);
    }
    if (!candidates.some(k => rtmCols.has(k))) {
      violations.push(`Material.${field} 缺 rowToMaterial 读取列（期望：${candidates.join(' / ')}）`);
    }
  }
  const stat = `Material 字段 ${fields.length} 个 / toRow 写入键 ${toRowKeys.size} 个 / rowToMaterial 读取列 ${rtmCols.size} 个`;
  return { violations, whitelistHits, stat };
}

// 规则 2 · 建表列 ⊆ toRow 写入键 ∪ 白名单
function runRule2() {
  const db = readEts(DB_FILE);

  // CREATE_TABLE_V2_SQL 模板字符串（raw 侧字符串保留，可取到列定义）
  const sqlMatch = db.stripped.raw.match(/const\s+CREATE_TABLE_V2_SQL[^\n`]*`([\s\S]*?)`/);
  const createCols = sqlMatch
    ? [...sqlMatch[1].matchAll(/(?:^|\n)\s*([a-z_]\w*)\s+(?:INTEGER|TEXT|REAL)\b/g)].map(m => m[1])
    : [];
  // migrate() 中每条 ALTER TABLE materials ADD COLUMN xxx
  const alterCols = [...db.stripped.raw.matchAll(/ALTER TABLE \$\{TABLE\} ADD COLUMN (\w+)/g)].map(m => m[1]);

  const toRowBlock = findBracedBlock(db.stripped.code, /(?:^|\n)\s*(?:private\s+)?toRow\s*\(/);
  const toRowKeys = new Set(toRowBlock
    ? [...db.stripped.raw.slice(toRowBlock.start, toRowBlock.end).matchAll(/['"](\w+)['"]\s*:/g)].map(m => m[1])
    : []);

  const violations = [];
  const whitelistHits = [];
  if (!sqlMatch) {
    violations.push('未能在 db/MaterialDb.ets 定位 CREATE_TABLE_V2_SQL 常量');
  }
  if (!toRowBlock) {
    violations.push('未能在 db/MaterialDb.ets 定位 toRow 方法体');
  }
  for (const col of createCols) {
    if (toRowKeys.has(col)) {
      continue;
    }
    const reason = RULE2_WHITELIST[col];
    if (reason) {
      whitelistHits.push(`建表列 ${col} —— ${reason}`);
    } else {
      violations.push(`建表列 ${col} 不在 toRow 写入键中（且不在白名单）`);
    }
  }
  for (const col of alterCols) {
    if (toRowKeys.has(col)) {
      continue;
    }
    const reason = RULE2_WHITELIST[col];
    if (reason) {
      whitelistHits.push(`ALTER 列 ${col} —— ${reason}`);
    } else {
      violations.push(`migrate() ALTER 列 ${col} 不在 toRow 写入键中（且不在白名单）`);
    }
  }
  const stat = `V2 建表列 ${createCols.length} 个 + migrate() ALTER 列 ${alterCols.length} 条 ⊆ toRow 写入键 ${toRowKeys.size} 个 ∪ 白名单`;
  return { violations, whitelistHits, stat };
}

// 规则 3 · pages 硬编码预设数据源检测（DEFAULT_CATEGORIES / DEFAULT_LOCATIONS / DEFAULT_UNITS）
function runRule3() {
  const files = getEtsFiles(pagesDir).map(readEts);
  const violations = [];
  const whitelistHits = [];
  let occurrences = 0;
  let legalContext = 0;
  let wlOccurrences = 0;
  const IDENT_RE = /\bDEFAULT_(?:CATEGORIES|LOCATIONS|UNITS)\b/g;

  for (const fi of files) {
    const rel = relPath(fi.file);
    const rawLines = fi.content.split('\n');
    const codeLines = fi.stripped.raw.split('\n'); // 注释已剥，字符串保留，行号与原文对齐
    for (let i = 0; i < codeLines.length; i++) {
      const line = codeLines[i];
      IDENT_RE.lastIndex = 0;
      const matched = line.match(IDENT_RE);
      if (!matched) {
        continue;
      }
      occurrences += matched.length;
      // 合法上下文：a. import 行 b. @State 声明行 c. listEffectiveNames 调用行
      if (/\bimport\b/.test(line) || line.includes('@State') || line.includes('listEffectiveNames')) {
        legalContext += matched.length;
        continue;
      }
      // d. 白名单行（文件 + 特异子串匹配）
      const wl = RULE3_WHITELIST.find(w => w.file === rel && line.includes(w.substring));
      if (wl) {
        wlOccurrences += matched.length;
        whitelistHits.push(`${rel} L${i + 1} [${matched.join(', ')}] —— ${wl.reason}`);
        continue;
      }
      violations.push(`${rel} L${i + 1} [${matched.join(', ')}] ${rawLines[i].trim()}`);
    }
  }
  const stat = `扫描 ${files.length} 个页面文件，标识符出现 ${occurrences} 处 = 合法上下文 ${legalContext} + 白名单 ${wlOccurrences} + 违规 ${violations.length}`;
  return { violations, whitelistHits, stat };
}

// 规则 4 · 导出 API 必须有非测试外部调用者
function collectApis() {
  const apis = [];
  // MaterialDb public 方法：async xxx(...)（private async 不算）+ static getInstance
  const db = readEts(DB_FILE);
  const dbMethods = [...db.stripped.code.matchAll(/(?:^|\n)\s*async\s+(\w+)\s*\(/g)].map(m => m[1]);
  if (/(?:^|\n)\s*static\s+getInstance\s*\(/.test(db.stripped.code)) {
    dbMethods.push('getInstance');
  }
  for (const name of dbMethods) {
    apis.push({ name, group: 'MaterialDb', module: 'db/MaterialDb.ets', defFile: DB_FILE });
  }
  // ExpiryService 的 export function
  const expiry = readEts(EXPIRY_FILE);
  for (const m of expiry.stripped.code.matchAll(/(?:^|\n)export\s+function\s+(\w+)\s*\(/g)) {
    apis.push({ name: m[1], group: 'ExpiryService', module: 'service/ExpiryService.ets', defFile: EXPIRY_FILE });
  }
  // common 五文件的 export function
  for (const f of COMMON_API_FILES) {
    const p = path.join(etsRoot, 'common', f);
    const s = readEts(p);
    for (const m of s.stripped.code.matchAll(/(?:^|\n)export\s+function\s+(\w+)\s*\(/g)) {
      apis.push({ name: m[1], group: 'common', module: `common/${f}`, defFile: p });
    }
  }
  return apis;
}

function runRule4(allFiles) {
  const apis = collectApis();
  const violations = [];
  const whitelistHits = [];
  const notes = [];
  let withCallers = 0;
  const zeroCaller = [];

  for (const api of apis) {
    let callers = 0;
    for (const fi of allFiles) {
      if (path.resolve(fi.file) === path.resolve(api.defFile)) {
        continue; // 定义文件内部互调不算外部调用者
      }
      callers += countOutsideImports(fi.stripped.raw, fi.imports, api.name);
    }
    if (callers > 0) {
      withCallers++;
      continue;
    }
    zeroCaller.push(api);
    const reason = (RULE4_WHITELIST[api.group] || {})[api.name];
    if (reason) {
      whitelistHits.push(`${api.module} · ${api.name}() —— ${reason}`);
    } else {
      violations.push(`${api.module} · ${api.name}() 零外部调用者（test/ 不算调用者，定义文件内部互调不算）`);
    }
  }
  // 白名单登记项维护提示（不算违规）：已有调用者或名称对不上时提示移除/核对
  const hitSet = new Set(zeroCaller.map(a => `${a.group}|${a.name}`));
  for (const [group, entries] of Object.entries(RULE4_WHITELIST)) {
    for (const name of Object.keys(entries)) {
      if (!hitSet.has(`${group}|${name}`)) {
        const known = apis.some(a => a.group === group && a.name === name);
        notes.push(known
          ? `白名单登记 ${group}.${name} 已有外部调用者，可移除豁免`
          : `白名单登记 ${group}.${name} 未匹配到任何导出 API，请核对名称`);
      }
    }
  }
  const stat = `导出 API ${apis.length} 个 = 有外部调用者 ${withCallers} + 零调用（白名单豁免 ${whitelistHits.length} / 违规 ${violations.length}）`;
  return { violations, whitelistHits, stat, notes };
}

// 规则 5 · 未使用 import 检测
function runRule5(allFiles) {
  const violations = [];
  const whitelistHits = [];
  let importedCount = 0;
  let usedCount = 0;

  for (const fi of allFiles) {
    const rel = relPath(fi.file);
    for (const imp of fi.imports) {
      for (const name of imp.names) {
        importedCount++;
        const uses = countOutsideImports(fi.stripped.raw, fi.imports, name);
        if (uses > 0) {
          usedCount++;
          continue;
        }
        const wl = RULE5_WHITELIST.find(w => w.file === rel && w.identifier === name);
        if (wl) {
          whitelistHits.push(`${rel} · ${name} —— ${wl.reason}`);
        } else {
          violations.push(`${rel} · import { ${name} } 导入后未使用`);
        }
      }
    }
  }
  const stat = `具名导入 ${importedCount} 个 = 已使用 ${usedCount} + 白名单豁免 ${whitelistHits.length} + 违规 ${violations.length}`;
  return { violations, whitelistHits, stat };
}

// ─────────────────────────── 主逻辑 ───────────────────────────

console.log('🔍 跨层接线守护检查（固化接线审计不变量）...\n');

const allFiles = getEtsFiles(etsRoot).map(readEts);

const results = [
  { title: '规则 1 · Material 字段 ⇄ DB 行双向映射完整性', ...runRule1() },
  { title: '规则 2 · 建表列 ⊆ toRow 写入键', ...runRule2() },
  { title: '规则 3 · pages 硬编码预设数据源检测', ...runRule3() },
  { title: '规则 4 · 导出 API 必须有非测试外部调用者', ...runRule4(allFiles) },
  { title: '规则 5 · 未使用 import 检测', ...runRule5(allFiles) },
];

let hasError = false;
for (const r of results) {
  if (r.violations.length > 0) {
    hasError = true;
    console.error(`❌ ${r.title} (${r.violations.length} 处):`);
    for (const v of r.violations) {
      console.error(`     ${v}`);
    }
  } else {
    console.log(`✅ ${r.title}: 通过`);
  }
  if (r.stat) {
    console.log(`   ${r.stat}`);
  }
  if (r.whitelistHits.length > 0) {
    console.log(`   白名单命中 ${r.whitelistHits.length} 条:`);
    for (const h of r.whitelistHits) {
      console.log(`     · ${h}`);
    }
  }
  for (const note of r.notes || []) {
    console.log(`   ⚠️ ${note}`);
  }
  console.log('');
}

if (hasError) {
  console.error('💥 接线守护失败，请修复上述问题后再提交');
  process.exit(1);
} else {
  console.log('✅ 接线守护全部通过');
}
