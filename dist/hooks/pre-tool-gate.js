/**
 * PreToolUse Hook: Gate Enforcement
 *
 * Blocks tool usage when the current gate doesn't allow it.
 * This is the primary mechanism preventing the agent from
 * skipping gates (e.g., editing files before CLASSIFY is done).
 */
import { readState, readGate } from '../state-reader.js';
import { checkToolAllowed } from '../gate-rules.js';
export function handlePreToolUse(data) {
    const toolName = data.tool_name || data.toolName || '';
    const toolInput = (data.tool_input || data.toolInput || null);
    const cwd = data.cwd || data.directory || process.cwd();
    // No .teamx/state.json → not in a workflow, allow everything
    const state = readState(cwd);
    if (!state) {
        return { continue: true, suppressOutput: true };
    }
    const gate = readGate(cwd);
    // IDLE = no active workflow
    if (gate === 'IDLE') {
        return { continue: true, suppressOutput: true };
    }
    const flowVariant = state.current_task?.flow_variant || 'standard';
    const result = checkToolAllowed(toolName, toolInput, gate, flowVariant);
    if (result.allowed) {
        return { continue: true, suppressOutput: true };
    }
    // Deny the tool with explanation
    return {
        continue: true,
        hookSpecificOutput: {
            hookEventName: 'PreToolUse',
            permissionDecision: 'deny',
            permissionDecisionReason: result.reason,
        },
    };
}
