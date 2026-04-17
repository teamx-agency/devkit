/**
 * TeamX DevKit — Extension Hooks Loader
 *
 * Declarative hook system inspired by spec-kit's `.specify/extensions.yml`.
 * Plugins declare `before_<gate>` / `after_<gate>` commands that run when
 * the DevKit transitions gates. Keeps `state.sh` free of per-project custom
 * logic while giving teams a controlled extension surface.
 *
 * Schema (`.teamx/extensions.yml`):
 *
 *   hooks:
 *     before_merge:
 *       - extension: security-scan
 *         command: bash .teamx/ext/security-scan.sh
 *         optional: false
 *     after_evidence:
 *       - extension: slack-notify
 *         command: node .teamx/ext/slack-notify.js
 *         optional: true
 *
 * Runtime contract:
 *   - The command receives a compact JSON blob on stdin with
 *     `{gate, phase, project_code, task_uuid, state_summary}`.
 *   - Exit code 0 = success. Stdout is captured and surfaced to the agent
 *     as an `[Extension Output] <extension>` block.
 *   - Non-zero exit + `optional: false` → hook fails and the transition is
 *     surfaced as a `pause_for_decision` suggestion (we do not auto-rollback
 *     because the gate already moved).
 */
import { existsSync, readFileSync } from 'fs';
import { join } from 'path';
import { spawnSync } from 'child_process';
const EXTENSIONS_PATH = '.teamx/extensions.yml';
const MAX_OUTPUT_BYTES = 4000;
const DEFAULT_TIMEOUT_MS = 10_000;
/**
 * Parse a permissive YAML subset — enough for the declarative hooks schema.
 * Avoids pulling a full YAML dependency; if extensions.yml grows beyond this
 * shape, swap to js-yaml and keep the same return type.
 */
function parseExtensionsYaml(raw) {
    const lines = raw.split(/\r?\n/);
    const hooks = {};
    let currentHook = null;
    let currentEntry = null;
    const flushEntry = () => {
        if (currentHook && currentEntry && currentEntry.extension && currentEntry.command) {
            hooks[currentHook].push({
                extension: currentEntry.extension,
                command: currentEntry.command,
                optional: currentEntry.optional === true,
            });
        }
        currentEntry = null;
    };
    for (const rawLine of lines) {
        const line = rawLine.replace(/#.*$/, '').trimEnd();
        if (line.trim() === '')
            continue;
        if (line === 'hooks:')
            continue;
        // hook name (two-space indent, ends with colon)
        const hookMatch = line.match(/^ {2}([a-z_]+):$/i);
        if (hookMatch) {
            flushEntry();
            currentHook = hookMatch[1];
            hooks[currentHook] = hooks[currentHook] ?? [];
            continue;
        }
        // list start under hook ("    - extension: foo")
        const listStart = line.match(/^ {4}-\s*extension:\s*(.+)$/);
        if (listStart) {
            flushEntry();
            currentEntry = { extension: listStart[1].trim().replace(/^["']|["']$/g, '') };
            continue;
        }
        // entry fields (six-space indent)
        const fieldMatch = line.match(/^ {6}([a-z_]+):\s*(.+)$/);
        if (fieldMatch && currentEntry) {
            const key = fieldMatch[1];
            let value = fieldMatch[2].trim().replace(/^["']|["']$/g, '');
            if (key === 'optional') {
                value = value === 'true';
                currentEntry[key] = value;
            }
            else {
                currentEntry[key] = value;
            }
        }
    }
    flushEntry();
    return { hooks };
}
export function loadExtensions(cwd) {
    const path = join(cwd, EXTENSIONS_PATH);
    if (!existsSync(path))
        return null;
    try {
        const raw = readFileSync(path, 'utf-8');
        return parseExtensionsYaml(raw);
    }
    catch {
        return null;
    }
}
function truncate(s) {
    if (s.length <= MAX_OUTPUT_BYTES)
        return s;
    return s.slice(0, MAX_OUTPUT_BYTES) + '\n…[truncated]';
}
/**
 * Run the registered hooks for `<phase>_<gate>` (e.g. "before_merge"). Returns
 * one result per hook in declaration order. Never throws — all errors are
 * reported as `ok: false` entries.
 */
export function runHooks(cwd, phase, gate, state) {
    const file = loadExtensions(cwd);
    if (!file)
        return [];
    const key = `${phase}_${gate.toLowerCase()}`;
    const hooks = file.hooks?.[key] ?? [];
    if (hooks.length === 0)
        return [];
    const payload = JSON.stringify({
        gate,
        phase,
        project_code: state.project_code,
        task_uuid: state.current_task?.uuid ?? null,
        state_summary: {
            current_gate: state.current_gate,
            task_title: state.current_task?.title ?? null,
            work_type: state.current_task?.work_type ?? null,
        },
    });
    const results = [];
    for (const hook of hooks) {
        try {
            const proc = spawnSync('sh', ['-c', hook.command], {
                cwd,
                input: payload,
                timeout: DEFAULT_TIMEOUT_MS,
                encoding: 'utf-8',
            });
            const exitCode = proc.status ?? (proc.signal ? 124 : 1);
            results.push({
                extension: hook.extension,
                phase,
                gate,
                exit_code: exitCode,
                stdout: truncate(proc.stdout ?? ''),
                stderr: truncate(proc.stderr ?? ''),
                optional: hook.optional,
                ok: exitCode === 0,
            });
        }
        catch (err) {
            results.push({
                extension: hook.extension,
                phase,
                gate,
                exit_code: -1,
                stdout: '',
                stderr: err instanceof Error ? err.message : String(err),
                optional: hook.optional,
                ok: false,
            });
        }
    }
    return results;
}
/**
 * Render hook results into a single agent-facing block. Failed mandatory
 * extensions are called out so the agent can register a pause_for_decision.
 */
export function buildHookReport(results) {
    if (results.length === 0)
        return null;
    const lines = [`[TeamX Extensions — ${results[0].phase}_${results[0].gate.toLowerCase()}]`];
    for (const r of results) {
        const label = r.ok ? '✓' : r.optional ? '⚠ (optional)' : '✗ BLOCKING';
        lines.push(`${label} ${r.extension} (exit ${r.exit_code})`);
        if (r.stdout.trim() !== '') {
            lines.push(`  stdout: ${r.stdout.trim()}`);
        }
        if (!r.ok && r.stderr.trim() !== '') {
            lines.push(`  stderr: ${r.stderr.trim()}`);
        }
    }
    const mandatoryFailures = results.filter(r => !r.ok && !r.optional);
    if (mandatoryFailures.length > 0) {
        lines.push('');
        lines.push(`Mandatory extension(s) failed: ${mandatoryFailures.map(r => r.extension).join(', ')}. ` +
            `Register pause_for_decision "security-risk-detected" or "manual-review-required" before advancing.`);
    }
    return lines.join('\n');
}
