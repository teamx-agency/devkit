/**
 * TeamX DevKit — Hook-enforced state machine for Claude Code
 */

export { readState, readGate, buildStateSummary, findStateFile } from './state-reader.js';
export { checkToolAllowed, SAFE_STOP_GATES } from './gate-rules.js';
export { handlePreToolUse } from './hooks/pre-tool-gate.js';
export { handleStop, resetBlockCount } from './hooks/stop-guard.js';
export { handleSessionStart } from './hooks/session-start.js';
export { handlePreCompact } from './hooks/pre-compact-save.js';
export { handlePostToolUse } from './hooks/post-tool-state.js';
