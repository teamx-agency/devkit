/**
 * PostToolUse Hook: State Tracking
 *
 * After specific tool executions, re-reads state from disk
 * and injects updated context. This prevents the agent from
 * working with stale or misread task data.
 */
import { writeFileSync, mkdirSync, renameSync } from 'fs';
import { join, dirname } from 'path';
import { readState, buildStateSummary, buildPauseBlock } from '../state-reader.js';
import { resetBlockCount } from './stop-guard.js';
import { runHooks, buildHookReport } from '../extensions.js';
/** Tools that trigger state re-injection */
const STATE_TRIGGER_TOOLS = new Set([
    'mcp__teamx__teamx_get_workflow_state',
    'mcp__teamx__teamx_get_task_detail',
    'mcp__teamx__teamx_transition_task',
    'mcp__teamx__teamx_batch_transition_tasks',
    'mcp__teamx__teamx_satisfy_acceptance_criterion',
    'mcp__teamx__teamx_update_acceptance_criteria',
]);
/**
 * Read server-authoritative qa_warnings from the workflow state response.
 * The server computes these with full DB access — more reliable than client-side parsing.
 */
function extractServerQaWarnings(toolOutput) {
    try {
        const parsed = JSON.parse(toolOutput);
        const warnings = parsed?.data?.data?.qa_warnings ?? [];
        return warnings.filter((w) => typeof w === 'string');
    }
    catch {
        return [];
    }
}
function detectDuplicateCriteria(toolOutput) {
    const warnings = [];
    try {
        const parsed = JSON.parse(toolOutput);
        const milestones = parsed?.data?.data?.milestones ?? [];
        // Build map: normalized description → tasks that have it
        const criteriaMap = new Map();
        for (const ms of milestones) {
            const milestone = ms;
            if (!milestone.is_active)
                continue;
            const tasks = milestone.tasks ?? [];
            for (const t of tasks) {
                const task = t;
                const uuid = task.uuid;
                const title = task.title;
                const criteria = task.acceptance_criteria ?? [];
                for (const c of criteria) {
                    const crit = c;
                    const desc = (crit.description ?? '').trim().toLowerCase();
                    if (!desc)
                        continue;
                    if (!criteriaMap.has(desc))
                        criteriaMap.set(desc, []);
                    criteriaMap.get(desc).push({
                        task_uuid: uuid,
                        task_title: title,
                        sort_order: crit.sort_order,
                    });
                }
            }
        }
        // Find criteria shared across 2+ tasks
        for (const [desc, refs] of criteriaMap.entries()) {
            if (refs.length < 2)
                continue;
            const taskList = refs.map(r => `"${r.task_title}"`).join(', ');
            const preview = desc.length > 80 ? desc.slice(0, 80) + '...' : desc;
            warnings.push(`[QA WARNING] Criterio duplicado detectado en ${refs.length} tareas: "${preview}"\n` +
                `  → Compartido por: ${taskList}\n` +
                `  → Criterios no específicos por tarea generan ambigüedad en validación. ` +
                `Refina cada criterio para que sea verificable de forma independiente.`);
        }
    }
    catch { /* ignore parse errors — output may be non-JSON */ }
    return warnings;
}
// ---------------------------------------------------------------------------
// Helpers — API response validation (Gap #8)
// ---------------------------------------------------------------------------
function checkSatisfyResponse(toolOutput) {
    try {
        const parsed = JSON.parse(toolOutput);
        const inner = parsed?.data ?? parsed;
        if (inner?.success === false) {
            const error = inner?.error ?? 'error desconocido';
            return (`[QA WARNING] teamx_satisfy_acceptance_criterion FALLÓ en el backend.\n` +
                `  Error: ${error}\n` +
                `  El criterio NO fue marcado como satisfecho. Verifica el error y reintenta.`);
        }
        // Also warn if already_satisfied (idempotent call — may indicate agent confusion)
        if (inner?.data?.already_satisfied === true) {
            return (`[TeamX] Criterio ya estaba satisfecho previamente (already_satisfied=true). ` +
                `Evidencia existente: "${inner.data.existing_evidence ?? 'n/a'}".`);
        }
    }
    catch { /* non-JSON output */ }
    return null;
}
const GATE_MODE_MAP = {
    SELECT: { mode: 'execution', hint: 'Show prioritization criteria. Pick highest-priority available task.' },
    CLASSIFY: { mode: 'pairing', hint: 'Analyze work type and readiness. Think out loud — name type, criteria clarity, and blockers.' },
    PLAN: { mode: 'pairing', hint: 'Propose plan with tradeoffs. List files, sequence, risks. Wait for approval before proceeding.' },
    IMPLEMENT: { mode: 'execution', hint: 'Path is clear. Brief plan, then execute. Minimal narration during routine work.' },
    VERIFY: { mode: 'recovery', hint: 'Report each check result plainly. On failure: root cause (not symptoms) + specific repair plan. Zero panic.' },
    COMMIT: { mode: 'execution', hint: 'Encapsulate cleanly. Brief and factual.' },
    PUSH: { mode: 'execution', hint: 'Signal forward movement. Minimal.' },
    MR: { mode: 'execution', hint: 'Confirm MR created. Set merge-when-pipeline-succeeds.' },
    PIPELINE: { mode: 'recovery', hint: 'On failure: read job log, diagnose root cause, set gate back to VERIFY. On success: confirm briefly.' },
    REVIEW: { mode: 'review', hint: 'Pipeline passed. Present criteria evidence. Do NOT self-approve — wait for human QA confirmation.' },
    MERGE: { mode: 'execution', hint: 'Confirm integration. Handle conflicts explicitly if present.' },
    EVIDENCE: { mode: 'review', hint: 'Map each acceptance criterion to concrete evidence (file, line, test, behavior). Be specific — not vague claims.' },
    RETROSPECTIVE: { mode: 'review', hint: 'Extract learning. At least 1 insight. Push lessons with teamx_push_lessons. Update or delete stale lessons with teamx_update_lesson / teamx_delete_lesson. Capture ADRs, conventions and stack decisions with teamx_set_knowledge before advancing.' },
};
/**
 * Builds a mode directive message when a gate transition occurs.
 * Only emits on set_gate calls (not on other state.sh commands).
 */
function buildModeDirective(gate, toolInput) {
    // Only emit on actual set_gate transitions
    const command = toolInput.command || '';
    if (!/set_gate/.test(command))
        return null;
    const entry = GATE_MODE_MAP[gate];
    if (!entry)
        return null;
    return (`[TeamX Mode → ${entry.mode.toUpperCase()}]\n` +
        `Gate: ${gate} — ${entry.hint}`);
}
export function handlePostToolUse(data) {
    const toolName = data.tool_name || data.toolName || '';
    const toolInput = (data.tool_input || data.toolInput || {});
    const cwd = data.cwd || data.directory || process.cwd();
    // Check if this is a state.sh call (Bash with state.sh commands)
    const isStateShCall = toolName === 'Bash' && isStateShCommand(toolInput);
    if (!STATE_TRIGGER_TOOLS.has(toolName) && !isStateShCall) {
        return { continue: true, suppressOutput: true };
    }
    // Re-read state from disk
    const state = readState(cwd);
    if (!state) {
        return { continue: true, suppressOutput: true };
    }
    // Reset stop-guard counter on any gate transition (state.sh set_gate)
    if (isStateShCall) {
        resetBlockCount(cwd);
    }
    const messages = [];
    // After workflow state: remind to call get_task_detail + detect duplicate criteria (Gap #1)
    if (toolName === 'mcp__teamx__teamx_get_workflow_state') {
        if (state.current_task) {
            messages.push(`[TeamX] Task in state: "${state.current_task.title}" (${state.current_task.uuid}). ` +
                `Call teamx_get_task_detail for full description and acceptance criteria.`);
        }
        // Gap #1 — read server-authoritative qa_warnings (duplicate criteria, etc.)
        const output = data.tool_output || data.toolOutput || '';
        const serverWarnings = extractServerQaWarnings(output);
        if (serverWarnings.length > 0) {
            messages.push(serverWarnings.join('\n\n'));
        }
        else {
            // Fallback: client-side detection if server version is older
            const duplicateWarnings = detectDuplicateCriteria(output);
            if (duplicateWarnings.length > 0) {
                messages.push(duplicateWarnings.join('\n\n'));
            }
        }
    }
    // After get_task_detail: warn if criteria are missing, inject criteria progress hint (Gap #5)
    if (toolName === 'mcp__teamx__teamx_get_task_detail') {
        const output = data.tool_output || data.toolOutput || '';
        const criteriaMissing = output.includes('"criteria_status":"missing"') ||
            output.includes('"criteria_status": "missing"');
        if (criteriaMissing && state.current_task?.work_type !== 'chore') {
            messages.push(`[TeamX WARNING] Task has no acceptance criteria. ` +
                `Set readiness to "needs_refinement" in CLASSIFY and post a blocker.`);
        }
        // Gap #5 — persist full criteria cache to disk so compaction doesn't lose them
        try {
            const parsed = JSON.parse(output);
            const criteria = parsed?.data?.data?.acceptance_criteria ?? [];
            const taskUuid = parsed?.data?.data?.uuid ?? state.current_task?.uuid ?? '';
            if (criteria.length > 0 && taskUuid) {
                const total = criteria.length;
                const satisfied = criteria.filter((c) => c.is_satisfied === true).length;
                const pending = total - satisfied;
                // Atomic snapshot to .teamx/criteria-cache.json — survives compaction
                const cachePath = join(cwd, '.teamx', 'criteria-cache.json');
                try {
                    mkdirSync(dirname(cachePath), { recursive: true });
                    const tmp = `${cachePath}.tmp`;
                    writeFileSync(tmp, JSON.stringify({
                        task_uuid: taskUuid,
                        total,
                        satisfied,
                        refreshed_at: new Date().toISOString(),
                        criteria: criteria.map((c) => {
                            const entry = c;
                            return {
                                sort_order: entry.sort_order,
                                description: entry.description,
                                is_satisfied: entry.is_satisfied === true,
                                evidence: entry.evidence ?? null,
                            };
                        }),
                    }, null, 2));
                    renameSync(tmp, cachePath);
                }
                catch { /* best-effort cache — never fail the hook */ }
                messages.push(`[TeamX Criteria Progress] ${satisfied}/${total} satisfied${pending > 0 ? ` — ${pending} PENDING` : ' — all done'}.\n` +
                    `Snapshot cached at .teamx/criteria-cache.json (survives compaction).\n` +
                    `Run: source .teamx/lib/state.sh && set_criteria_progress ${total} ${satisfied}`);
            }
        }
        catch { /* ignore */ }
    }
    // After update_acceptance_criteria: confirm update and remind to re-check readiness
    if (toolName === 'mcp__teamx__teamx_update_acceptance_criteria') {
        const output = data.tool_output || data.toolOutput || '';
        try {
            const parsed = JSON.parse(output);
            const criteria = parsed?.data?.data?.acceptance_criteria
                ?? parsed?.data?.acceptance_criteria
                ?? [];
            const mode = toolInput.mode || 'replace';
            const count = criteria.length;
            if (count > 0) {
                messages.push(`[TeamX Criteria Updated — ${mode.toUpperCase()}]\n` +
                    `${count} criteria now on task. ` +
                    `Verify each is Given/When/Then and has a concrete pass/fail condition before advancing to IMPLEMENT.`);
            }
        }
        catch { /* non-JSON — still continue */ }
    }
    // After satisfy_acceptance_criterion: validate API response (Gap #8)
    if (toolName === 'mcp__teamx__teamx_satisfy_acceptance_criterion') {
        const output = data.tool_output || data.toolOutput || '';
        const warning = checkSatisfyResponse(output);
        if (warning) {
            messages.push(warning);
        }
    }
    // After state.sh or transition: inject updated state summary + active mode
    if (isStateShCall || toolName === 'mcp__teamx__teamx_transition_task') {
        const summary = buildStateSummary(state);
        messages.push(`[TeamX State Updated]\n${summary}`);
        // Inject mode directive on gate transitions
        const modeDirective = buildModeDirective(state.current_gate, toolInput);
        if (modeDirective) {
            messages.push(modeDirective);
        }
        // Extension hooks (Phase 3.5) — only on actual set_gate transitions.
        const command = toolInput.command || '';
        if (/set_gate/.test(command)) {
            try {
                const report = buildHookReport(runHooks(cwd, 'before', state.current_gate, state));
                if (report)
                    messages.push(report);
            }
            catch { /* extensions never block the hook itself */ }
        }
    }
    // Always surface an unresolved pause — even on non-state.sh tool calls —
    // so the agent cannot drift past a flagged blocker.
    const pauseBlock = buildPauseBlock(state);
    if (pauseBlock) {
        messages.push(pauseBlock);
    }
    if (messages.length === 0) {
        return { continue: true, suppressOutput: true };
    }
    return {
        continue: true,
        hookSpecificOutput: {
            hookEventName: 'PostToolUse',
            additionalContext: messages.join('\n\n'),
        },
    };
}
function isStateShCommand(toolInput) {
    const command = toolInput.command || '';
    return /state\.sh/.test(command) && /\b(set_gate|set_current_task|set_work_type|set_readiness|approve_plan|complete_current_task|auto_approve_plan_if_safe|auto_approve_qa_if_green|approve_qa_review|pause_for_decision|resolve_pause|set_task_user_story|register_feature_branch|register_feature_mr)\b/.test(command);
}
