/**
 * Stop Hook: Completion Guard
 *
 * Blocks the agent from stopping when work is in progress.
 * Allows stopping only at safe gates (IDLE, INIT, SELECT) or
 * after a safety valve (5 consecutive blocks).
 */
export interface StopInput {
    stop_hook_reason?: string;
    stopHookReason?: string;
    cwd?: string;
    directory?: string;
    session_id?: string;
    sessionId?: string;
}
export interface StopOutput {
    decision: 'block' | 'approve';
    reason?: string;
}
export declare function resetBlockCount(cwd: string): void;
export declare function handleStop(data: StopInput): StopOutput;
