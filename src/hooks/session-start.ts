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

  // Lessons
  const lessonsPath = join(cwd, '.teamx', 'lessons.json');
  if (existsSync(lessonsPath)) {
    try {
      const lessons = JSON.parse(readFileSync(lessonsPath, 'utf-8'));
      if (lessons?.patterns?.length > 0) {
        const top = lessons.patterns.slice(0, 3)
          .map((p: { pattern: string; frequency: number }) => `- ${p.pattern} (seen ${p.frequency}x)`)
          .join('\n');
        messages.push(`[TeamX Lessons]\n${top}`);
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
