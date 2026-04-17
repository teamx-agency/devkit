/**
 * SessionStart Hook: State Restoration
 *
 * Reads .teamx/state.json on session start and injects
 * the current state summary into the agent's context.
 * Also loads handoff and lessons if available.
 */

import { existsSync, readFileSync } from 'fs';
import { join } from 'path';
import { readState, buildStateSummary, buildPauseBlock } from '../state-reader.js';

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

  // Unresolved pause — surface as top-priority blocker on resume
  const pauseBlock = buildPauseBlock(state);
  if (pauseBlock) {
    messages.push(pauseBlock);
  }

  // Criteria cache (Gap #5) — restore full acceptance criteria after compaction
  // so the agent never has to "remember to refresh" manually.
  if (state.current_task) {
    const criteriaCachePath = join(cwd, '.teamx', 'criteria-cache.json');
    if (existsSync(criteriaCachePath)) {
      try {
        const cache = JSON.parse(readFileSync(criteriaCachePath, 'utf-8'));
        if (cache?.task_uuid === state.current_task.uuid && Array.isArray(cache.criteria)) {
          const list = (cache.criteria as Array<{
            sort_order?: number;
            description?: string;
            is_satisfied?: boolean;
            evidence?: string | null;
          }>)
            .sort((a, b) => (a.sort_order ?? 0) - (b.sort_order ?? 0))
            .map((c, i) => {
              const mark = c.is_satisfied ? '✓' : '○';
              const idx = c.sort_order ?? i;
              return `  [${idx}] ${mark} ${c.description ?? '(sin descripción)'}`;
            })
            .join('\n');
          messages.push(
            `[TeamX Criteria Restored — task ${cache.task_uuid}] ${cache.satisfied}/${cache.total} satisfied\n` +
            list + '\n' +
            `Cache timestamp: ${cache.refreshed_at}. ` +
            `If the task changed upstream, call teamx_get_task_detail to refresh.`
          );
        }
      } catch { /* ignore */ }
    } else {
      messages.push(
        `[TeamX Criteria Missing] No local cache found for current task. ` +
        `Call teamx_get_task_detail("${state.current_task.uuid}") before advancing.`
      );
    }
  }

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

  // Constitution (Phase 3.4) — load project override first, then agency baseline.
  // Surface as "MUST / MUST NOT" reminders so every session inherits the contract.
  const constitutionSources: Array<{ label: string; path: string }> = [
    { label: 'project', path: join(cwd, '.teamx', 'constitution.md') },
  ];
  if (process.env.CLAUDE_PLUGIN_ROOT) {
    constitutionSources.push({
      label: 'agency',
      path: join(process.env.CLAUDE_PLUGIN_ROOT, 'teamx-lib', 'constitution.md'),
    });
  }
  constitutionSources.push({
    label: 'agency',
    path: join(process.env.HOME || '', '.claude', 'teamx-devkit', 'teamx-lib', 'constitution.md'),
  });
  const seenScopes = new Set<string>();
  for (const { label, path } of constitutionSources) {
    if (seenScopes.has(label)) continue;
    if (!existsSync(path)) continue;
    try {
      const raw = readFileSync(path, 'utf-8').trim();
      if (!raw) continue;
      const versionMatch = raw.match(/^version:\s*(.+)$/m);
      const version = versionMatch ? versionMatch[1].trim() : 'unversioned';
      const articles: string[] = [];
      const articleRe = /^##\s+(Article\s+[IVXLC]+\s+—\s+.+?)$/gm;
      let m: RegExpExecArray | null;
      while ((m = articleRe.exec(raw)) !== null) {
        articles.push(m[1]);
      }
      messages.push(
        `[TeamX Constitution — ${label} v${version}]\n` +
        articles.map(a => `- ${a}`).join('\n') +
        `\nThese articles are MUST-level. Violations raise qa_warnings and block SDD approval.`
      );
      seenScopes.add(label);
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
