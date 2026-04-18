/**
 * TeamX State Reader
 *
 * Reads .teamx/state.json from disk. Every hook uses this.
 * This module is READ-ONLY — it never writes to state.json.
 */
import { readFileSync, existsSync } from 'fs';
import { join } from 'path';
const ALL_GATES = [
    'IDLE', 'INIT', 'SELECT', 'CLASSIFY', 'PLAN',
    'IMPLEMENT', 'VERIFY', 'COMMIT', 'PUSH', 'MR',
    'PIPELINE', 'REVIEW', 'MERGE', 'EVIDENCE', 'RETROSPECTIVE',
];
// --- Reader ---
export function findStateFile(cwd) {
    const statePath = join(cwd, '.teamx', 'state.json');
    return existsSync(statePath) ? statePath : null;
}
export function readState(cwd) {
    const statePath = findStateFile(cwd);
    if (!statePath)
        return null;
    try {
        const raw = readFileSync(statePath, 'utf-8');
        return JSON.parse(raw);
    }
    catch {
        return null;
    }
}
export function readGate(cwd) {
    const state = readState(cwd);
    if (!state)
        return 'IDLE';
    const gate = state.current_gate;
    return ALL_GATES.includes(gate) ? gate : 'IDLE';
}
export function isGate(value) {
    return ALL_GATES.includes(value);
}
/**
 * Build a compact state summary for context injection.
 * Mirrors read_state_summary() from state.sh.
 */
export function buildStateSummary(state) {
    const t = state.current_task;
    const lines = [
        `Project: ${state.project_code} | Gate: ${state.current_gate}`,
    ];
    if (t) {
        lines.push(`Task: "${t.title}" (${t.uuid})`);
        if (t.work_type)
            lines.push(`Type: ${t.work_type} (${t.flow_variant || 'standard'})`);
        if (t.branch)
            lines.push(`Branch: ${t.branch}`);
        if (t.readiness)
            lines.push(`Readiness: ${t.readiness}`);
        if (t.plan)
            lines.push(`Plan: ${t.plan.approved ? 'approved' : 'pending approval'}`);
        // Acceptance criteria tracking
        if (t.criteria_total !== undefined && t.criteria_total > 0) {
            const satisfied = t.criteria_satisfied ?? 0;
            const pending = t.criteria_total - satisfied;
            lines.push(`Criteria: ${satisfied}/${t.criteria_total} satisfied${pending > 0 ? ` — ${pending} PENDING` : ' — all done'}`);
        }
        else if (t.acceptance_criteria.length > 0) {
            lines.push(`Criteria: ${t.acceptance_criteria.length} loaded (call teamx_get_task_detail for satisfaction status)`);
        }
        else {
            lines.push(`Criteria: not loaded — call teamx_get_task_detail`);
        }
        const vChecks = Object.entries(t.verification);
        if (vChecks.length > 0) {
            const passed = vChecks.filter(([, v]) => v.status === 'pass').length;
            lines.push(`Verification: ${passed}/${vChecks.length} passed`);
        }
        const g = t.git;
        lines.push(`Git: committed=${g.committed} pushed=${g.pushed} mr=${g.mr_iid ?? 'none'} merged=${g.merged}`);
    }
    if (state.active_milestone) {
        const m = state.active_milestone;
        lines.push(`Milestone: "${m.title}" (${m.done_tasks}/${m.total_tasks})`);
    }
    return lines.join('\n');
}
/**
 * Render the pause-for-decision block when the current task has an
 * unresolved pause. Returns null when no active pause exists.
 *
 * This is the structured "significant interrupt" — distinct from mode
 * directives, which fire on every gate transition. A pause means the
 * agent hit a genuine categorised blocker; the workflow does not advance
 * until `resolve_pause` is called.
 */
export function buildPauseBlock(state) {
    const pause = state.current_task?.pause;
    if (!pause || pause.resolved === true || !pause.category)
        return null;
    const lines = [
        `⏸  PAUSE-FOR-DECISION [${pause.category}]`,
        pause.reason,
    ];
    if (pause.options)
        lines.push(`Opciones: ${pause.options}`);
    lines.push('Workflow parado. Resuelve con el usuario y corre: bash .teamx/lib/state.sh resolve_pause');
    return lines.join('\n');
}
