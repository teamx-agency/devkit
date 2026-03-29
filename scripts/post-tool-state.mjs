#!/usr/bin/env node
/**
 * PostToolUse entry point — State tracking.
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
    const { handlePostToolUse } = await import(
      pathToFileURL(join(runtimeBase, 'dist', 'hooks', 'post-tool-state.js')).href
    );

    const result = handlePostToolUse(data);
    console.log(JSON.stringify(result));
  } catch {
    console.log(JSON.stringify({ continue: true, suppressOutput: true }));
  }
}

main();
