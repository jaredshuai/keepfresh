// KeepFresh 构建脚本 - 自动检测 hvigorw
import { spawnSync } from 'child_process';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const isWin = process.platform === 'win32';

// 按平台生成 hvigorw 候选（优先级：项目本地 → DevEco 默认 → 环境变量）
function findHvigorw() {
  const projectLocal = path.join(__dirname, '..');
  const devecoDefault = 'C:\\Program Files\\Huawei\\DevEco Studio\\tools\\hvigor\\bin';
  const devecoEnv = process.env.DEVECO_HOME
    ? path.join(process.env.DEVECO_HOME, 'tools', 'hvigor', 'bin')
    : null;

  // win32 优先 .bat，其他平台优先无扩展 shell 脚本
  const extFirst = isWin ? 'hvigorw.bat' : 'hvigorw';
  const extSecond = isWin ? 'hvigorw' : 'hvigorw.bat';

  const dirs = [projectLocal, devecoDefault, devecoEnv].filter(Boolean);
  const candidates = [];
  for (const d of dirs) {
    candidates.push(path.join(d, extFirst));
    candidates.push(path.join(d, extSecond));
  }

  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return null;
}

const hvigorw = findHvigorw();
if (!hvigorw) {
  console.error('❌ 未找到 hvigorw');
  console.error('请安装 DevEco Studio 或设置 DEVECO_HOME 环境变量');
  process.exit(1);
}
console.log(`✅ 使用 hvigorw: ${hvigorw}`);

const argv = process.argv.slice(2);
const args = argv.length > 0 ? argv : ['assembleHap'];
console.log(`🔨 执行: ${args.join(' ')}`);

// 清除 NODE_OPTIONS，避免 --use-system-ca 等参数导致 DevEco Node 报错
const env = { ...process.env, NODE_OPTIONS: '' };

// spawn argv 数组模式，防止 shell 注入/参数被拆分；Windows 上 .bat 需要通过 shell 解析
const run = (() => {
  if (isWin) {
    // Windows：shell:true 走 cmd.exe /c，hvigorw 路径含空格需用双引号包裹
    const cmdParts = [`"${hvigorw}"`, ...args.map(a => `"${a.replace(/"/g, '\\"')}"`)];
    return spawnSync(cmdParts.join(' '), [], {
      stdio: 'inherit',
      cwd: path.join(__dirname, '..'),
      env,
      shell: true,
    });
  }
  // POSIX：直接 spawn sh 执行脚本，完全避免 shell 插值
  return spawnSync('sh', [hvigorw, ...args], { stdio: 'inherit', cwd: path.join(__dirname, '..'), env });
})();

if (run.signal) {
  console.error(`\n💥 构建被信号终止: ${run.signal}`);
  process.exit(128 + (run.status ?? 1));
}
process.exit(run.status ?? 1);
