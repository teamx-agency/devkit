/**
 * PreCompact Hook: Context Preservation
 *
 * Before context window compaction, injects a compact summary
 * of the current state that survives the compaction.
 */
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
export declare function handlePreCompact(data: PreCompactInput): PreCompactOutput;
