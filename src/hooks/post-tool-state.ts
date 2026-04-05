/**
 * PostToolUse Hook: State Tracking
 *
 * After specific tool executions, re-reads state from disk
 * and injects updated context. This prevents the agent from
 * working with stale or misread task data.
 */

import { readState, buildStateSummary } from '../state-reader.js';
import { resetBlockCount } from './stop-guard.js';

export interface PostToolInput {
  tool_name?: string;
  toolName?: string;
  tool_input?: Record<string, unknown>;
  toolInput?: Record<string, unknown>;
  tool_output?: string;
  toolOutput?: string;
  cwd?: string;
  directory?: string;
}

export interface PostToolOutput {
  continue: true;
  suppressOutput?: boolean;
  hookSpecificOutput?: {
    hookEventName: 'PostToolUse';
    additionalContext: string;
  };
}

/** Tools that trigger state re-injection */
const STATE_TRIGGER_TOOLS = new Set([
  'mcp__teamx__teamx_get_workflow_state',
  'mcp__teamx__teamx_get_task_detail',
  'mcp__teamx__teamx_transition_task',
  'mcp__teamx__teamx_batch_transition_tasks',
  'mcp__teamx__teamx_satisfy_acceptance_criterion',
]);

// ---------------------------------------------------------------------------
// Helpers — duplicate criteria detection (Gap #1)
// ---------------------------------------------------------------------------

interface CriterionRef {
  task_uuid: string;
  task_title: string;
  sort_order: number;
}

/**
 * Read server-authoritative qa_warnings from the workflow state response.
 * The server computes these with full DB access — more reliable than client-side parsing.
 */
function extractServerQaWarnings(toolOutput: string): string[] {
  try {
    const parsed = JSON.parse(toolOutput);
    const warnings: unknown[] = parsed?.data?.data?.qa_warnings ?? [];
    return warnings.filter((w): w is string => typeof w === 'string');
  } catch {
    return [];
  }
}

function detectDuplicateCriteria(toolOutput: string): string[] {
  const warnings: string[] = [];
  try {
    const parsed = JSON.parse(toolOutput);
    const milestones: unknown[] = parsed?.data?.data?.milestones ?? [];

    // Build map: normalized description → tasks that have it
    const criteriaMap = new Map<string, CriterionRef[]>();

    for (const ms of milestones) {
      const milestone = ms as Record<string, unknown>;
      if (!milestone.is_active) continue;
      const tasks = (milestone.tasks as unknown[]) ?? [];
      for (const t of tasks) {
        const task = t as Record<string, unknown>;
        const uuid = task.uuid as string;
        const title = task.title as string;
        const criteria = (task.acceptance_criteria as unknown[]) ?? [];
        for (const c of criteria) {
          const crit = c as Record<string, unknown>;
          const desc = (crit.description as string ?? '').trim().toLowerCase();
          if (!desc) continue;
          if (!criteriaMap.has(desc)) criteriaMap.set(desc, []);
          criteriaMap.get(desc)!.push({
            task_uuid: uuid,
            task_title: title,
            sort_order: crit.sort_order as number,
          });
        }
      }
    }

    // Find criteria shared across 2+ tasks
    for (const [desc, refs] of criteriaMap.entries()) {
      if (refs.length < 2) continue;
      const taskList = refs.map(r => `"${r.task_title}"`).join(', ');
      const preview = desc.length > 80 ? desc.slice(0, 80) + '...' : desc;
      warnings.push(
        `[QA WARNING] Criterio duplicado detectado en ${refs.length} tareas: "${preview}"\n` +
        `  → Compartido por: ${taskList}\n` +
        `  → Criterios no específicos por tarea generan ambigüedad en validación. ` +
        `Refina cada criterio para que sea verificable de forma independiente.`
      );
    }
  } catch { /* ignore parse errors — output may be non-JSON */ }
  return warnings;
}

// ---------------------------------------------------------------------------
// Helpers — API response validation (Gap #8)
// ---------------------------------------------------------------------------

function checkSatisfyResponse(toolOutput: string): string | null {
  try {
    const parsed = JSON.parse(toolOutput);
    const inner = parsed?.data ?? parsed;
    if (inner?.success === false) {
      const error = inner?.error ?? 'error desconocido';
      return (
        `[QA WARNING] teamx_satisfy_acceptance_criterion FALLÓ en el backend.\n` +
        `  Error: ${error}\n` +
        `  El criterio NO fue marcado como satisfecho. Verifica el error y reintenta.`
      );
    }
    // Also warn if already_satisfied (idempotent call — may indicate agent confusion)
    if (inner?.data?.already_satisfied === true) {
      return (
        `[TeamX] Criterio ya estaba satisfecho previamente (already_satisfied=true). ` +
        `Evidencia existente: "${inner.data.existing_evidence ?? 'n/a'}".`
      );
    }
  } catch { /* non-JSON output */ }
  return null;
}

export function handlePostToolUse(data: PostToolInput): PostToolOutput {
  const toolName = data.tool_name || data.toolName || '';
  const toolInput = (data.tool_input || data.toolInput || {}) as Record<string, unknown>;
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

  const messages: string[] = [];

  // After workflow state: remind to call get_task_detail + detect duplicate criteria (Gap #1)
  if (toolName === 'mcp__teamx__teamx_get_workflow_state') {
    if (state.current_task) {
      messages.push(
        `[TeamX] Task in state: "${state.current_task.title}" (${state.current_task.uuid}). ` +
        `Call teamx_get_task_detail for full description and acceptance criteria.`
      );
    }
    // Gap #1 — read server-authoritative qa_warnings (duplicate criteria, etc.)
    const output = data.tool_output || data.toolOutput || '';
    const serverWarnings = extractServerQaWarnings(output);
    if (serverWarnings.length > 0) {
      messages.push(serverWarnings.join('\n\n'));
    } else {
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
      messages.push(
        `[TeamX WARNING] Task has no acceptance criteria. ` +
        `Set readiness to "needs_refinement" in CLASSIFY and post a blocker.`
      );
    }
    // Gap #5 — inject criteria progress so it survives compaction
    try {
      const parsed = JSON.parse(output);
      const criteria: unknown[] = parsed?.data?.data?.acceptance_criteria ?? [];
      if (criteria.length > 0) {
        const total = criteria.length;
        const satisfied = criteria.filter((c) => (c as Record<string, unknown>).is_satisfied === true).length;
        const pending = total - satisfied;
        messages.push(
          `[TeamX Criteria Progress] ${satisfied}/${total} satisfied${pending > 0 ? ` — ${pending} PENDING` : ' — all done'}.\n` +
          `Run: source .teamx/lib/state.sh && set_criteria_progress ${total} ${satisfied}`
        );
      }
    } catch { /* ignore */ }
  }

  // After satisfy_acceptance_criterion: validate API response (Gap #8)
  if (toolName === 'mcp__teamx__teamx_satisfy_acceptance_criterion') {
    const output = data.tool_output || data.toolOutput || '';
    const warning = checkSatisfyResponse(output);
    if (warning) {
      messages.push(warning);
    }
  }

  // After state.sh or transition: inject updated state summary
  if (isStateShCall || toolName === 'mcp__teamx__teamx_transition_task') {
    const summary = buildStateSummary(state);
    messages.push(`[TeamX State Updated]\n${summary}`);
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

function isStateShCommand(toolInput: Record<string, unknown>): boolean {
  const command = (toolInput.command as string) || '';
  return /state\.sh/.test(command) && /\b(set_gate|set_current_task|set_work_type|set_readiness|approve_plan|complete_current_task)\b/.test(command);
}
