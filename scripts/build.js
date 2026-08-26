// KeepFresh 构建脚本 - 自动检测 hvigorw
import { execSync } from 'child_process';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// 检测 hvigorw
function findHvigorw() {
  const candidates = [
    // 项目本地
    path.join(__dirname, '..', 'hvigorw'),
    path.join(__dirname, '..', 'hvigorw.bat'),
    // DevEco Studio 默认路径
    'C:\\Program Files\\Huawei\\DevEco Studio\\tools\\hvigor\\bin\\hvigorw.bat',
    // 环境变量
    process.env.DEVECO_HOME && path.join(process.env.DEVECO_HOME, 'tools', 'hvigor', 'bin', 'hvigorw'),
    process.env.DEVECO_HOME && path.join(process.env.DEVECO_HOME, 'tools', 'hvigor', 'bin', 'hvigorw.bat'),
  ].filter(Boolean);

  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return null;
}

// 执行
const hvigorw = findHvigorw();
if (!hvigorw) {
  console.error('❌ 未找到 hvigorw');
  console.error('请安装 DevEco Studio 或设置 DEVECO_HOME 环境变量');
  process.exit(1);
}

console.log(`✅ 使用 hvigorw: ${hvigorw}`);

const args = process.argv.slice(2).join(' ') || 'assembleHap';
console.log(`🔨 执行: ${args}`);

// 清除 NODE_OPTIONS，避免 --use-system-ca 等参数导致 DevEco Node 报错
const env = { ...process.env, NODE_OPTIONS: '' };

try {
  // Windows 下用 .bat，其他平台用 shell
  const cmd = process.platform === 'win32'
    ? `"${hvigorw}" ${args}`
    : `sh "${hvigorw}" ${args}`;
  execSync(cmd, { stdio: 'inherit', cwd: path.join(__dirname, '..'), env });
} catch (e) {
  process.exit(e.status || 1);
}
