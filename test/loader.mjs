import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

export async function resolve(specifier, context, nextResolve) {
  try {
    return await nextResolve(specifier, context);
  } catch (err) {
    if (specifier.startsWith('.') || specifier.startsWith('/')) {
      const parentURL = context.parentURL;
      const urlWithEts = new URL(specifier + (specifier.endsWith('.ets') ? '' : '.ets'), parentURL);
      return {
        format: 'module-typescript',
        shortCircuit: true,
        url: urlWithEts.href,
      };
    }
    throw err;
  }
}

export async function load(url, context, nextLoad) {
  if (url.endsWith('.ets')) {
    const filePath = fileURLToPath(url);
    let content = await readFile(filePath, 'utf8');
    // Transform enum declarations for Node typescript strip-only compatibility
    content = content.replace(/export\s+enum\s+(\w+)\s*\{([^}]+)\}/g, (match, enumName, enumBody) => {
      const lines = enumBody
        .split('\n')
        .map(l => l.replace(/\/\*.*?\*\/|\/\/.*$/g, '').trim())
        .filter(Boolean)
        .map(l => {
          const line = l.replace(/\s*=\s*/, ': ');
          return line.endsWith(',') ? line : line + ',';
        })
        .join('\n');
      return `export const ${enumName} = Object.freeze({\n${lines}\n});\nexport type ${enumName} = number;`;
    });
    return {
      format: 'module-typescript',
      shortCircuit: true,
      source: content,
    };
  }
  return nextLoad(url, context);
}
