/**
 * SessionStart Hook: State Restoration
 *
 * Reads .teamx/state.json on session start and injects
 * the current state summary into the agent's context.
 * Also loads handoff and lessons if available.
 */

import { existsSync, readFileSync } from 'fs';
import { join } from 'path';
import { readState, buildStateSummary } from '../state-reader.js';

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

export function handleSessionStart(data: SessionStartInput): SessionStartOutput {
  const cwd = data.cwd || data.directory || process.cwd();

  const state = readState(cwd);
  if (!state || state.current_gate === 'IDLE') {
    return { continue: true, suppressOutput: true };
  }

  const messages: string[] = [];

  // State summary
  const summary = buildStateSummary(state);
  messages.push(`[TeamX State Restored]\n${summary}`);

  // Handoff context
  const handoffPath = join(cwd, '.teamx', 'handoff.md');
  if (existsSync(handoffPath)) {
    try {
      const handoff = readFileSync(handoffPath, 'utf-8').trim();
      if (handoff) {
        messages.push(`[TeamX Handoff]\n${handoff}`);
      }
    } catch { /* ignore */ }
  }

  // Local lessons
  const lessonsPath = join(cwd, '.teamx', 'lessons.json');
  if (existsSync(lessonsPath)) {
    try {
      const lessons = JSON.parse(readFileSync(lessonsPath, 'utf-8'));
      if (lessons?.patterns?.length > 0) {
        const top = (lessons.patterns as string[]).slice(0, 3)
          .map((p: string) => `- ${p}`)
          .join('\n');
        messages.push(`[TeamX Lessons — Local]\n${top}`);
      }
    } catch { /* ignore */ }
  }

  // Shared lessons (from teamx_get_shared_lessons, saved at last INIT)
  const sharedPath = join(cwd, '.teamx', 'shared-lessons.json');
  if (existsSync(sharedPath)) {
    try {
      const shared = JSON.parse(readFileSync(sharedPath, 'utf-8'));
      const signals: Array<{ signal: string; pattern: string; frequency: number; gate: string }> =
        shared?.shared_lessons ?? [];
      if (signals.length > 0) {
        const top = signals.slice(0, 3)
          .map(s => `- [${s.gate}] ${s.pattern} (seen ${s.frequency}x across team)`)
          .join('\n');
        messages.push(`[TeamX Shared Lessons — Team]\n${top}`);
      }
    } catch { /* ignore */ }
  }

  if (messages.length === 0) {
    return { continue: true, suppressOutput: true };
  }

  return {
    continue: true,
    hookSpecificOutput: {
      hookEventName: 'SessionStart',
      additionalContext: messages.join('\n\n---\n\n'),
    },
  };
}
