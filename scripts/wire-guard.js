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
import { getEtsFiles } from './lib/ets-files.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.join(__dirname, '..');
const etsRoot = path.join(rootDir, 'entry', 'src', 'main', 'ets');
const pagesDir = path.join(etsRoot, 'pages');

const DB_FILE = path.join(etsRoot, 'db', 'MaterialDb.ets');
const MODEL_FILE = path.join(etsRoot, 'model', 'Material.ets');
const EXPIRY_FILE = path.join(etsRoot, 'service', 'ExpiryService.ets');

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
  // 审计复核新增（任务清单外）：defaults() 提供者行，语义等价于 listEffectiveNames 的 defaults 参数
  {
    file: 'pages/CategoryManager.ets',
    substring: 'return DEFAULT_',
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
    consolidateDuplicateBatches: 'init() 启动并条钩子内部调用的语义核心，保留 public（测试无法触达 db 层）',
  },
  ExpiryService: {
    getNearExpiryThreshold: '仅测试消费的缓存 getter',
    isExpired: 'getActualStatus/sortBy 内部组合件',
    isExpiringSoon: 'getActualStatus/sortBy 内部组合件',
    riskOrderOf: 'getActualStatus/sortBy 内部组合件',
    sortByRiskAndExpiration: '预留分页/统计，测试覆盖',
    sortByCreatedDesc: '预留分页/统计，测试覆盖',
    buildOverview: '预留分页/统计，测试覆盖',
    levelSoftColor: '预留徽标色，清理候选',
    levelBadgeTextColor: '预留徽标色，清理候选',
  },
  common: {
    normalizeNullableText: '预留',
    formatQuantityUnit: '清理候选：无外部调用方（原 AddItem 死导入已删，ticket #18）',
    pad2: 'toDateStr 内部件',
    // 审计复核新增（任务清单外）：InputNormalize 内部组合件，与 softDelete/pad2 同性质
    normalizeText: 'InputNormalize 内部组合件（被 normalizeNullableText/parseNonNegativeInteger 复用）',
    normalizeNonNegativeInteger: 'InputNormalize 内部组合件（被 parseNonNegativeInteger 复用）',
  },
};

// 规则 5：未使用 import 豁免（file 为相对 entry/src/main/ets 的路径）
// 存量 5 条已于 ticket #18 任务 1 清理（删 import → wire:check 绿 → 移除白名单），当前清零。
const RULE5_WHITELIST = [];

// ─────────────────────────── 通用解析工具 ───────────────────────────

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
  // 模板插值栈（字符串恢复用）：栈底记录「当前未闭合模板串的恢复信息」。
  // 语义：${ 进入插值（按代码处理）；插值内 { } 计数嵌套（对象字面量/嵌套插值）；
  // 配平的 } 结束插值、回到模板文本态。
  const tmplStack = [];
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
      } else if (ch === '{') {
        // 插值内嵌套对象字面量：计数
        if (tmplStack.length > 0) {
          tmplStack[tmplStack.length - 1].depth++;
        }
        raw += ch;
        code += ch;
      } else if (ch === '}' && tmplStack.length > 0) {
        // 可能是插值闭合：配平判断（栈顶 depth 归零 → 回模板文本态）
        const top = tmplStack[tmplStack.length - 1];
        top.depth--;
        raw += ch;
        code += ch;
        if (top.depth === 0) {
          tmplStack.pop();
          strChar = tmplStack.length > 0 ? tmplStack[tmplStack.length - 1].quote : top.quote;
          state = 'str';
        }
      } else {
        raw += ch;
        code += ch;
      }
    } else if (state === 'str') {
      if (ch === '\\' && next !== '') {
        raw += ch + next;
        code += '  ';
        i++;
      } else if (strChar === '`' && ch === '$' && next === '{') {
        // 进入模板插值：${ 后按代码处理（插值里的标识符是真实使用）
        state = 'code';
        tmplStack.push({ depth: 1, quote: strChar });
        raw += ch + next;
        code += ch + next;
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
    // 驼峰 → 下划线（quantity 例外：写入要求双列，读取兼容历史 quantity_text）
    const snake = field.replace(/([a-z0-9])([A-Z])/g, '$1_$2').toLowerCase();
    const reason = RULE1_WHITELIST[field];
    if (reason) {
      whitelistHits.push(`Material.${field} —— ${reason}`);
    } else if (field === 'quantity') {
      // 写入侧：quantity 与 quantity_text 必须双列齐写（迁移期 REAL→TEXT 双写不变量，
      // 只写其一会导致 REAL/TEXT 两列漂移，历史行读取口径不一致）
      if (!toRowKeys.has('quantity') || !toRowKeys.has('quantity_text')) {
        violations.push('Material.quantity 缺 toRow 写入键（写入要求 quantity + quantity_text 双列齐写）');
      }
    } else if (!toRowKeys.has(snake)) {
      violations.push(`Material.${field} 缺 toRow 写入键（期望：${snake}）`);
    }
    // 读取侧：兼容历史库（老迁移行可能只填了其中一列，二选一即可）
    const readCandidates = field === 'quantity' ? [snake, 'quantity_text'] : [snake];
    if (!readCandidates.some(k => rtmCols.has(k))) {
      violations.push(`Material.${field} 缺 rowToMaterial 读取列（期望：${readCandidates.join(' / ')}）`);
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
  // 列名解析不依赖类型名（不再硬编码 INTEGER/TEXT/REAL）：行首标识符 + 任意类型词即视为列声明，
  // 用 SQL 声明关键字排除 PRIMARY KEY / UNIQUE / CHECK 等约束行，防止漏检非三种类型的新列
  const SQL_DECL_KEYWORDS = new Set([
    'primary', 'foreign', 'unique', 'check', 'constraint', 'index',
    'key', 'create', 'table', 'on', 'default', 'not', 'null', 'and',
  ]);
  const createCols = sqlMatch
    ? [...sqlMatch[1].matchAll(/(?:^|\n)\s*([a-z_]\w*)\s+[A-Za-z]/g)]
        .filter(m => !SQL_DECL_KEYWORDS.has(m[1].toLowerCase()))
        .map(m => m[1])
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
  // 反向校验：toRow 的每个写入键必须对应真实建表列（CREATE ∪ ALTER ∪ 白名单），
  // 防止多写/拼错的键静默通过（写入不存在的列会在运行期才爆）
  const schemaCols = new Set([...createCols, ...alterCols, ...Object.keys(RULE2_WHITELIST)]);
  for (const key of toRowKeys) {
    if (!schemaCols.has(key)) {
      violations.push(`toRow 写入键 ${key} 无对应建表列（CREATE/ALTER 均无，且不在白名单）`);
    }
  }
  const stat = `V2 建表列 ${createCols.length} 个 + migrate() ALTER 列 ${alterCols.length} 条 ⊆ toRow 写入键 ${toRowKeys.size} 个 ∪ 白名单（反向校验通过）`;
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
function collectApis(allFiles) {
  const apis = [];
  const seen = new Set();
  const add = (name, group, module, defFile) => {
    const key = `${group}|${name}`;
    if (seen.has(key)) {
      return;
    }
    seen.add(key);
    apis.push({ name, group, module, defFile });
  };
  // MaterialDb public 方法：async xxx(...)（private async 不算）+ static getInstance
  const db = readEts(DB_FILE);
  const dbMethods = [...db.stripped.code.matchAll(/(?:^|\n)\s*async\s+(\w+)\s*\(/g)].map(m => m[1]);
  if (/(?:^|\n)\s*static\s+getInstance\s*\(/.test(db.stripped.code)) {
    dbMethods.push('getInstance');
  }
  for (const name of dbMethods) {
    add(name, 'MaterialDb', 'db/MaterialDb.ets', DB_FILE);
  }
  // 其余：枚举 ETS 全树的 export function（不依赖硬编码文件清单，新增文件自动纳入）。
  // 分组沿用审计口径：ExpiryService / common 保留；其余按模块相对路径（如 model/CustomField）
  for (const fi of allFiles) {
    if (path.resolve(fi.file) === path.resolve(DB_FILE)) {
      continue; // MaterialDb 的 class 方法已在上面单独处理
    }
    const rel = relPath(fi.file);
    const group = rel === 'service/ExpiryService.ets' ? 'ExpiryService'
      : rel.startsWith('common/') ? 'common'
        : rel.replace(/\.ets$/, '');
    // 含 export async function（可选 async 修饰符），防止异步导出 API 漏检
    for (const m of fi.stripped.code.matchAll(/(?:^|\n)export\s+(?:async\s+)?function\s+(\w+)\s*\(/g)) {
      add(m[1], group, rel, fi.file);
    }
  }
  return apis;
}

function runRule4(allFiles) {
  const apis = collectApis(allFiles);
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
      // code 侧统计调用者：字符串字面量里的同名文本不算调用（与规则 5 同口径）
      callers += countOutsideImports(fi.stripped.code, fi.imports, api.name);
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
        // 用字符串剥离后的 code 侧统计：字符串字面量里的同名文本不算使用
        const uses = countOutsideImports(fi.stripped.code, fi.imports, name);
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

// 规则 6：custom_fields 键语义裸操作检测（ticket #14 / #18）
// pages/ 与 service/ 禁止裸下标访问 customFields[...] 及同行 JSON.parse/stringify；
// 键语义统一走 model/CustomField.ets 契约函数；db/ 存储层整列编解码豁免。
// 用字符串剥离后的 code 侧扫描：注释与字符串字面量不参与匹配。
function runRule6(allFiles) {
  const violations = [];
  let scanned = 0;
  const bareBracket = /customFields\s*\[/;
  const jsonOp = /JSON\.(?:parse|stringify)[^\n]*(?:customFields|custom_fields)|(?:customFields|custom_fields)[^\n]*JSON\.(?:parse|stringify)/;
  for (const fi of allFiles) {
    const rel = relPath(fi.file);
    if (!(rel.startsWith('pages/') || rel.startsWith('service/'))) continue;
    scanned++;
    const lines = fi.stripped.code.split('\n');
    for (let i = 0; i < lines.length; i++) {
      if (bareBracket.test(lines[i])) {
        violations.push(`${rel}:${i + 1} 裸下标访问 customFields[...]（应走 model/CustomField.ets 契约函数）`);
      } else if (jsonOp.test(lines[i])) {
        violations.push(`${rel}:${i + 1} 对 custom_fields 裸 JSON 编解码（应走 model/CustomField.ets 契约函数）`);
      }
    }
  }
  const stat = `pages/+service/ 共扫 ${scanned} 个文件，键语义裸操作 ${violations.length} 处`;
  return { violations, whitelistHits: [], stat };
}

// 规则 7：AGENTS.md 与 docs/agents/code-structure.md 引用的 .ets 路径必须真实存在（ticket #17，文档→代码单向）
// 只校验存在性，不要求「代码文件必须写进文档」——反向会劝退小改动。
function runRule7() {
  const violations = [];
  const docFiles = ['AGENTS.md', 'docs/agents/code-structure.md'];
  let count = 0;
  for (const docFile of docFiles) {
    const content = fs.readFileSync(path.join(rootDir, docFile), 'utf8');
    const re = /`([^`\n]*\.ets)`/g;
    let m;
    while ((m = re.exec(content)) !== null) {
      const p = m[1];
      if (p.includes('*') || p.includes('**')) continue;
      count++;
      if (!fs.existsSync(path.join(rootDir, p))) {
        violations.push(`${docFile} 引用的 ${p} 不存在（文件已删/移？请同步更新文档）`);
      }
    }
  }
  const stat = `校验 ${docFiles.join(' + ')} 中 ${count} 个 .ets 引用路径（单向：文档→代码）`;
  return { violations, whitelistHits: [], stat };
}

// ─────────────────────────── 主逻辑 ───────────────────────────

console.log('🔍 跨层接线守护检查（固化接线审计不变量）...\n');

const allFiles = getEtsFiles(etsRoot).map(readEts);

const results = [
  { title: '规则 1 · Material 字段 ⇄ DB 行双向映射完整性', doc: 'CONTEXT.md「新字段必改清单」（背景：docs/audit-wiring.md）', ...runRule1() },
  { title: '规则 2 · 建表列 ⊆ toRow 写入键', doc: 'CONTEXT.md「新字段必改清单」', ...runRule2() },
  { title: '规则 3 · pages 硬编码预设数据源检测', doc: 'CONTEXT.md「新字段必改清单」第 9 条（背景：docs/audit-wiring.md）', ...runRule3() },
  { title: '规则 4 · 导出 API 必须有非测试外部调用者', doc: 'docs/audit-wiring.md §五（白名单登记哲学）', ...runRule4(allFiles) },
  { title: '规则 5 · 未使用 import 检测', doc: 'docs/audit-wiring.md §五（白名单登记哲学）', ...runRule5(allFiles) },
  { title: '规则 6 · custom_fields 键语义裸操作检测', doc: 'AGENTS.md 关键不变量 1（#14 教训；契约函数在 model/CustomField.ets）', ...runRule6(allFiles) },
  // 规则 7 的违规信息本身已指名需同步的文档，不再附指针
  { title: '规则 7 · 文档 .ets 路径存在性（文档→代码单向）', doc: null, ...runRule7() },
];

let hasError = false;
for (const r of results) {
  if (r.violations.length > 0) {
    hasError = true;
    console.error(`❌ ${r.title} (${r.violations.length} 处):`);
    for (const v of r.violations) {
      console.error(`     ${v}`);
    }
    if (r.doc) console.error(`   详见 ${r.doc}`);
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
