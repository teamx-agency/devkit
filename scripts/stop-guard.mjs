#!/usr/bin/env node
/**
 * Stop hook entry point — Completion guard.
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
    const { handleStop } = await import(
      pathToFileURL(join(runtimeBase, 'dist', 'hooks', 'stop-guard.js')).href
    );

    const result = handleStop(data);
    console.log(JSON.stringify(result));
  } catch {
    // On error, allow stop (never trap the agent)
    console.log(JSON.stringify({ decision: 'approve' }));
  }
}

main();
