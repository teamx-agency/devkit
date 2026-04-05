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

  // After workflow state: remind to call get_task_detail for full criteria
  if (toolName === 'mcp__teamx__teamx_get_workflow_state') {
    if (state.current_task) {
      messages.push(
        `[TeamX] Task in state: "${state.current_task.title}" (${state.current_task.uuid}). ` +
        `Call teamx_get_task_detail for full description and acceptance criteria.`
      );
    }
  }

  // After get_task_detail: warn if criteria are missing (chores are exempt)
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
