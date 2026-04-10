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

/**
 * Resolve the base directory for experience files (persona.yaml, modes.yaml, voice.md).
 * Resolution order:
 *   1. Project's .teamx/ — per-project customization (set up by INIT)
 *   2. $CLAUDE_PLUGIN_ROOT/teamx-lib/ — plugin install method
 *   3. ~/.claude/teamx-devkit/teamx-lib/ — install.sh method
 */
function resolveExperienceBase(cwd: string): string | null {
  const candidates = [
    join(cwd, '.teamx'),
    ...(process.env.CLAUDE_PLUGIN_ROOT ? [join(process.env.CLAUDE_PLUGIN_ROOT, 'teamx-lib')] : []),
    join(process.env.HOME || '', '.claude', 'teamx-devkit', 'teamx-lib'),
  ];
  for (const base of candidates) {
    if (existsSync(join(base, 'persona.yaml')) ||
        existsSync(join(base, 'modes.yaml')) ||
        existsSync(join(base, 'voice.md'))) {
      return base;
    }
  }
  return null;
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

  // Project knowledge (from teamx_list_knowledge, saved at last INIT)
  const knowledgePath = join(cwd, '.teamx', 'project-knowledge.json');
  if (existsSync(knowledgePath)) {
    try {
      const knowledgeData = JSON.parse(readFileSync(knowledgePath, 'utf-8'));
      const items: Array<{ type: string; title: string; content: string }> =
        knowledgeData?.items ?? [];
      if (items.length > 0) {
        const top = items.slice(0, 5)
          .map(k => `- [${k.type}] ${k.title}`)
          .join('\n');
        messages.push(`[TeamX Project Knowledge]\n${top}`);
      }
    } catch { /* ignore */ }
  }

  // Persona + experience files — re-inject on every session so behavior survives context resets
  const personaPath = join(cwd, '.teamx', 'persona.yaml');
  if (existsSync(personaPath)) {
    try {
      const persona = readFileSync(personaPath, 'utf-8').trim();
      if (persona) {
        messages.push(`[TeamX Persona — Active]\n${persona}`);
      }
    } catch { /* ignore */ }
  }

  // Engram memory layer — inject instructions if available (graceful degradation)
  const engramStatusPath = join(cwd, '.teamx', 'engram-status.json');
  if (existsSync(engramStatusPath)) {
    try {
      const engramStatus = JSON.parse(readFileSync(engramStatusPath, 'utf-8'));
      if (engramStatus?.available === true) {
        messages.push(
          `[Engram Memory Available]\n` +
          `Persistent cross-session memory is active for this project.\n` +
          `→ At INIT: bash .teamx/lib/engram.sh import, then call get_context(layers=["project","architecture","recent-decisions"])\n` +
          `→ During IMPLEMENT: call save_observation when the human corrects your approach (most important capture point)\n` +
          `→ At EVIDENCE: call save_observation(layer="completed-work") with delivery summary\n` +
          `→ At RETROSPECTIVE: save_observation per insight, then bash .teamx/lib/engram.sh export`
        );
      }
    } catch { /* ignore — never block session start */ }
  }

  // Experience layer — persona, modes, voice (behavioral contract)
  // Resolution order: project's .teamx/ → plugin root teamx-lib/ → install.sh teamx-lib/
  const experienceBase = resolveExperienceBase(cwd);
  if (experienceBase) {
    const experienceFiles = [
      { file: 'persona.yaml', label: 'Persona' },
      { file: 'modes.yaml',   label: 'Modes' },
      { file: 'voice.md',     label: 'Voice' },
    ];
    const experienceParts: string[] = [];
    for (const { file, label } of experienceFiles) {
      const filePath = join(experienceBase, file);
      if (existsSync(filePath)) {
        try {
          const content = readFileSync(filePath, 'utf-8').trim();
          if (content) experienceParts.push(`### ${label}\n${content}`);
        } catch { /* ignore */ }
      }
    }
    if (experienceParts.length > 0) {
      messages.push(
        `[TeamX Experience Layer — Behavior Contract]\n` +
        `These files govern tone, communication modes, and message grammar. Apply them throughout the session.\n\n` +
        experienceParts.join('\n\n---\n\n')
      );
    }
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
