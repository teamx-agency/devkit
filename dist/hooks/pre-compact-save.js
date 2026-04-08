/**
 * PreCompact Hook: Context Preservation
 *
 * Before context window compaction, injects a compact summary
 * of the current state that survives the compaction.
 */
import { existsSync, readFileSync } from 'fs';
import { join } from 'path';
import { readState, buildStateSummary } from '../state-reader.js';
export function handlePreCompact(data) {
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
    // Engram — remind agent to restore cognitive context after compaction
    let engramReminder = '';
    const engramStatusPath = join(cwd, '.teamx', 'engram-status.json');
    if (existsSync(engramStatusPath)) {
        try {
            const engramStatus = JSON.parse(readFileSync(engramStatusPath, 'utf-8'));
            if (engramStatus?.available === true) {
                engramReminder =
                    `\n\n⚠ ENGRAM: After compaction, call get_context(layers=["project","architecture","recent-decisions"]) ` +
                        `to restore cross-session memory context.`;
            }
        }
        catch { /* ignore */ }
    }
    // Experience layer — remind agent to re-read behavior contract after compaction
    const experiencePaths = ['persona.yaml', 'modes.yaml', 'voice.md'];
    const anyExperience = experiencePaths.some(f => existsSync(join(cwd, '.teamx', f)));
    const experienceReminder = anyExperience
        ? `\n\n⚠ EXPERIENCE: After compaction, re-read .teamx/persona.yaml, .teamx/modes.yaml, .teamx/voice.md ` +
            `to restore behavior contract (tone, interaction modes, message grammar).`
        : '';
    return {
        continue: true,
        hookSpecificOutput: {
            hookEventName: 'PreCompact',
            additionalContext: `[TeamX Context Checkpoint — READ THIS AFTER COMPACTION]\n` +
                `${summary}` +
                criteriaReminder +
                engramReminder +
                experienceReminder +
                `\n\nRe-read .teamx/state.json for full context.\n` +
                `Run: source .teamx/lib/state.sh && print_status`,
        },
    };
}
