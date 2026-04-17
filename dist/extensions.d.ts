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
import type { TeamXState } from './state-reader.js';
type Phase = 'before' | 'after';
export interface ExtensionHookEntry {
    extension: string;
    command: string;
    optional: boolean;
}
export interface ExtensionHookResult {
    extension: string;
    phase: Phase;
    gate: string;
    exit_code: number;
    stdout: string;
    stderr: string;
    optional: boolean;
    ok: boolean;
}
export interface ExtensionsFile {
    hooks: Record<string, ExtensionHookEntry[]>;
}
export declare function loadExtensions(cwd: string): ExtensionsFile | null;
/**
 * Run the registered hooks for `<phase>_<gate>` (e.g. "before_merge"). Returns
 * one result per hook in declaration order. Never throws — all errors are
 * reported as `ok: false` entries.
 */
export declare function runHooks(cwd: string, phase: Phase, gate: string, state: TeamXState): ExtensionHookResult[];
/**
 * Render hook results into a single agent-facing block. Failed mandatory
 * extensions are called out so the agent can register a pause_for_decision.
 */
export declare function buildHookReport(results: ExtensionHookResult[]): string | null;
export {};
