/**
 * PostToolUse Hook: State Tracking
 *
 * After specific tool executions, re-reads state from disk
 * and injects updated context. This prevents the agent from
 * working with stale or misread task data.
 */
export interface PostToolInput {
    tool_name?: string;
    toolName?: string;
    tool_input?: Record<string, unknown>;
    toolInput?: Record<string, unknown>;
    tool_output?: string;
    toolOutput?: string;
    tool_response?: unknown;
    toolResponse?: unknown;
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
export declare function handlePostToolUse(data: PostToolInput): PostToolOutput;
