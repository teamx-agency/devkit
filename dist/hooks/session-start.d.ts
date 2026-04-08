/**
 * SessionStart Hook: State Restoration
 *
 * Reads .teamx/state.json on session start and injects
 * the current state summary into the agent's context.
 * Also loads handoff and lessons if available.
 */
export interface SessionStartInput {
    cwd?: string;
    directory?: string;
    session_id?: string;
    sessionId?: string;
}
export interface SessionStartOutput {
    continue: true;
    suppressOutput?: boolean;
    hookSpecificOutput?: {
        hookEventName: 'SessionStart';
        additionalContext: string;
    };
}
export declare function handleSessionStart(data: SessionStartInput): SessionStartOutput;
