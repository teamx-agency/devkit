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
    // Gap #5 — criteria snapshot is persisted to .teamx/criteria-cache.json on every
    // get_task_detail call. SessionStart restores it automatically; we only flag a
    // refresh if the cache is stale (> 30 min old) or missing.
    let criteriaReminder = '';
    if (state.current_task) {
        const cachePath = join(cwd, '.teamx', 'criteria-cache.json');
        let cacheOk = false;
        if (existsSync(cachePath)) {
            try {
                const cache = JSON.parse(readFileSync(cachePath, 'utf-8'));
                const refreshedAt = typeof cache?.refreshed_at === 'string' ? Date.parse(cache.refreshed_at) : NaN;
                const ageMinutes = Number.isFinite(refreshedAt) ? (Date.now() - refreshedAt) / 60000 : Infinity;
                cacheOk = cache?.task_uuid === state.current_task.uuid && ageMinutes <= 30;
            }
            catch { /* ignore */ }
        }
        criteriaReminder = cacheOk
            ? `\n\n✓ CRITERIA: snapshot in .teamx/criteria-cache.json is fresh — SessionStart will restore it automatically after compaction.`
            : `\n\n⚠ CRITERIA: cache stale or missing. After compaction, call teamx_get_task_detail("${state.current_task.uuid}") ` +
                `to refresh — hook will persist the snapshot automatically on return.`;
    }
    // Persona — remind agent to restore identity after compaction
    const personaPath = join(cwd, '.teamx', 'persona.yaml');
    const personaReminder = existsSync(personaPath)
        ? `\n\n⚠ PERSONA: Re-read .teamx/persona.yaml to restore identity, behavioral rules, and candor policy.`
        : '';
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
                personaReminder +
                experienceReminder +
                `\n\nRe-read .teamx/state.json for full context.\n` +
                `Run: bash .teamx/lib/state.sh print_status`,
        },
    };
}
