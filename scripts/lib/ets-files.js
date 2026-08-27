import fs from 'fs';
import path from 'path';

/**
 * 递归读取目录下所有 .ets 文件。
 * design-guard / wire-guard 共用（避免两份拷贝漂移）。
 */
export function getEtsFiles(dir) {
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
