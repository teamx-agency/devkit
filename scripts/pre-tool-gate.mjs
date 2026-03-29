#!/usr/bin/env node
/**
 * PreToolUse entry point — Gate enforcement.
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
    const { handlePreToolUse } = await import(
      pathToFileURL(join(runtimeBase, 'dist', 'hooks', 'pre-tool-gate.js')).href
    );

    const result = handlePreToolUse(data);
    console.log(JSON.stringify(result));
  } catch {
    // On error, always continue (never block Claude Code)
    console.log(JSON.stringify({ continue: true, suppressOutput: true }));
  }
}

main();
