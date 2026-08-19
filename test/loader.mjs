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
    const content = await readFile(filePath, 'utf8');
    return {
      format: 'module-typescript',
      shortCircuit: true,
      source: content,
    };
  }
  return nextLoad(url, context);
}
