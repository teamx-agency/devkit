#!/usr/bin/env node
/**
 * PreCompact entry point — Context preservation.
 */

import { dirname, join } from 'path';
import { fileURLToPath, pathToFileURL } from 'url';
import { readStdin } from './lib/stdin.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));

async function main() {
  try {
    const input = await readStdin();
    let data = {};
    try { data = JSON.parse(input); } catch {}

    const runtimeBase = process.env.CLAUDE_PLUGIN_ROOT || join(__dirname, '..');
    const { handlePreCompact } = await import(
      pathToFileURL(join(runtimeBase, 'dist', 'hooks', 'pre-compact-save.js')).href
    );

    const result = handlePreCompact(data);
    console.log(JSON.stringify(result));
  } catch {
    console.log(JSON.stringify({ continue: true, suppressOutput: true }));
  }
}

main();
