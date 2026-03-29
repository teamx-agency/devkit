#!/usr/bin/env node
'use strict';
/**
 * DevKit cross-platform hook runner (run.cjs)
 *
 * Uses process.execPath (the Node binary already running this script) to spawn
 * the target .mjs hook, bypassing PATH / shell discovery issues.
 *
 * Adapted from oh-my-claudecode's run.cjs pattern.
 *
 * Usage (from hooks.json):
 *   node "$CLAUDE_PLUGIN_ROOT"/scripts/run.cjs "$CLAUDE_PLUGIN_ROOT"/scripts/<hook>.mjs
 */

const { spawnSync } = require('child_process');
const { existsSync, realpathSync } = require('fs');
const { join, dirname } = require('path');

const target = process.argv[2];
if (!target) {
  // Nothing to run — exit cleanly so Claude Code hooks are never blocked.
  process.exit(0);
}

/**
 * Resolve the hook script target path, handling stale CLAUDE_PLUGIN_ROOT.
 */
function resolveTarget(targetPath) {
  if (existsSync(targetPath)) return targetPath;

  try {
    const resolved = realpathSync(targetPath);
    if (existsSync(resolved)) return resolved;
  } catch {
    // realpathSync throws if the path doesn't exist — expected
  }

  // Fallback: scan plugin cache for the same script in the latest version.
  try {
    const pluginRoot = process.env.CLAUDE_PLUGIN_ROOT;
    if (!pluginRoot) return null;

    const cacheBase = dirname(pluginRoot);
    const scriptRelative = targetPath.slice(pluginRoot.length);

    if (!scriptRelative || !existsSync(cacheBase)) return null;

    const { readdirSync } = require('fs');
    const entries = readdirSync(cacheBase).filter(v => /^\d+\.\d+\.\d+/.test(v));

    entries.sort((a, b) => {
      const pa = a.split('.').map(Number);
      const pb = b.split('.').map(Number);
      for (let i = 0; i < 3; i++) {
        if ((pa[i] || 0) !== (pb[i] || 0)) return (pb[i] || 0) - (pa[i] || 0);
      }
      return 0;
    });

    for (const version of entries) {
      const candidate = join(cacheBase, version) + scriptRelative;
      if (existsSync(candidate)) return candidate;
    }
  } catch {
    // Any error in fallback scan — give up gracefully
  }

  return null;
}

const resolved = resolveTarget(target);
if (!resolved) {
  process.exit(0);
}

const result = spawnSync(
  process.execPath,
  [resolved, ...process.argv.slice(3)],
  {
    stdio: 'inherit',
    env: process.env,
    windowsHide: true,
  }
);

process.exit(result.status ?? 0);
