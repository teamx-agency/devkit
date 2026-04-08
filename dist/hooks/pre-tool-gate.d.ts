/**
 * PreToolUse Hook: Gate Enforcement
 *
 * Blocks tool usage when the current gate doesn't allow it.
 * This is the primary mechanism preventing the agent from
 * skipping gates (e.g., editing files before CLASSIFY is done).
 */
export interface PreToolInput {
    tool_name?: string;
    toolName?: string;
    tool_input?: Record<string, unknown>;
    toolInput?: Record<string, unknown>;
    cwd?: string;
    directory?: string;
    session_id?: string;
    sessionId?: string;
}
export interface PreToolOutput {
    continue: boolean;
    suppressOutput?: boolean;
    hookSpecificOutput?: {
        hookEventName: 'PreToolUse';
        permissionDecision?: 'allow' | 'deny';
        permissionDecisionReason?: string;
        additionalContext?: string;
    };
}
export declare function handlePreToolUse(data: PreToolInput): PreToolOutput;
