/**
 * PreCompact Hook: Context Preservation
 *
 * Before context window compaction, injects a compact summary
 * of the current state that survives the compaction.
 */

import { readState, buildStateSummary } from '../state-reader.js';

export interface PreCompactInput {
  cwd?: string;
  directory?: string;
}

export interface PreCompactOutput {
  continue: true;
  suppressOutput?: boolean;
  hookSpecificOutput?: {
    hookEventName: 'PreCompact';
    additionalContext: string;
  };
}

export function handlePreCompact(data: PreCompactInput): PreCompactOutput {
  const cwd = data.cwd || data.directory || process.cwd();

  const state = readState(cwd);
  if (!state || state.current_gate === 'IDLE') {
    return { continue: true, suppressOutput: true };
  }

  const summary = buildStateSummary(state);

  // Gap #5 — remind agent to restore criteria after compaction
  const criteriaReminder = state.current_task
    ? `\n\n⚠ CRITERIA: After compaction, call teamx_get_task_detail("${state.current_task.uuid}") ` +
      `to restore acceptance criteria status — criteria are NOT persisted in state.json.`
    : '';

  return {
    continue: true,
    hookSpecificOutput: {
      hookEventName: 'PreCompact',
      additionalContext:
        `[TeamX Context Checkpoint — READ THIS AFTER COMPACTION]\n` +
        `${summary}` +
        criteriaReminder +
        `\n\nRe-read .teamx/state.json for full context.\n` +
        `Run: source .teamx/lib/state.sh && print_status`,
    },
  };
}
