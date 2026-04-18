/**
 * TeamX State Reader
 *
 * Reads .teamx/state.json from disk. Every hook uses this.
 * This module is READ-ONLY — it never writes to state.json.
 */

import { readFileSync, existsSync } from 'fs';
import { join } from 'path';

// --- Types matching state.sh v3 structure ---

export interface GitState {
  committed: boolean;
  commit_sha: string | null;
  pushed: boolean;
  mr_iid: number | null;
  pipeline_id: number | null;
  pipeline_status: string | null;
  merged: boolean;
}

export interface PlanState {
  proposed_files: string[];
  risks: string;
  architecture_notes: string;
  created_at: string;
  approved: boolean;
  deviates_from_sdd?: boolean;
  files_touched?: number;
}

export interface PauseState {
  category: string;
  reason: string;
  options?: string;
  paused_at: string;
  resolved: boolean;
  resolved_at?: string;
}

export interface QaApprovalState {
  source: 'human' | 'auto';
  approved_at: string;
}

export interface TaskState {
  uuid: string;
  title: string;
  gitlab_issue_iid: number;
  branch: string | null;
  work_type: string | null;
  readiness: string | null;
  flow_variant: string | null;
  branch_prefix: string | null;
  commit_prefix: string | null;
  started_at: string;
  acceptance_criteria: string[];
  criteria_total?: number;
  criteria_satisfied?: number;
  plan: PlanState | null;
  pause?: PauseState | null;
  qa_approval?: QaApprovalState | null;
  verification: Record<string, { status: string; output?: string }>;
  git: GitState;
}

export interface MilestoneState {
  uuid: string;
  title: string;
  done_tasks: number;
  total_tasks: number;
}

export interface TeamXState {
  state_version: number;
  project_code: string;
  repo_path: string;
  current_gate: string;
  current_task: TaskState | null;
  active_milestone: MilestoneState | null;
  completed_tasks: string[];
  overall_progress: { done: number; total: number };
  last_sync: string | null;
  handoff: unknown | null;
}

export type Gate =
  | 'IDLE' | 'INIT' | 'SELECT' | 'CLASSIFY' | 'PLAN'
  | 'IMPLEMENT' | 'VERIFY' | 'COMMIT' | 'PUSH' | 'MR'
  | 'PIPELINE' | 'REVIEW' | 'MERGE' | 'EVIDENCE' | 'RETROSPECTIVE';

const ALL_GATES: Gate[] = [
  'IDLE', 'INIT', 'SELECT', 'CLASSIFY', 'PLAN',
  'IMPLEMENT', 'VERIFY', 'COMMIT', 'PUSH', 'MR',
  'PIPELINE', 'REVIEW', 'MERGE', 'EVIDENCE', 'RETROSPECTIVE',
];

// --- Reader ---

export function findStateFile(cwd: string): string | null {
  const statePath = join(cwd, '.teamx', 'state.json');
  return existsSync(statePath) ? statePath : null;
}

export function readState(cwd: string): TeamXState | null {
  const statePath = findStateFile(cwd);
  if (!statePath) return null;

  try {
    const raw = readFileSync(statePath, 'utf-8');
    return JSON.parse(raw) as TeamXState;
  } catch {
    return null;
  }
}

export function readGate(cwd: string): Gate {
  const state = readState(cwd);
  if (!state) return 'IDLE';
  const gate = state.current_gate as Gate;
  return ALL_GATES.includes(gate) ? gate : 'IDLE';
}

export function isGate(value: string): value is Gate {
  return ALL_GATES.includes(value as Gate);
}

/**
 * Build a compact state summary for context injection.
 * Mirrors read_state_summary() from state.sh.
 */
export function buildStateSummary(state: TeamXState): string {
  const t = state.current_task;
  const lines: string[] = [
    `Project: ${state.project_code} | Gate: ${state.current_gate}`,
  ];

  if (t) {
    lines.push(`Task: "${t.title}" (${t.uuid})`);
    if (t.work_type) lines.push(`Type: ${t.work_type} (${t.flow_variant || 'standard'})`);
    if (t.branch) lines.push(`Branch: ${t.branch}`);
    if (t.readiness) lines.push(`Readiness: ${t.readiness}`);
    if (t.plan) lines.push(`Plan: ${t.plan.approved ? 'approved' : 'pending approval'}`);

    // Acceptance criteria tracking
    if (t.criteria_total !== undefined && t.criteria_total > 0) {
      const satisfied = t.criteria_satisfied ?? 0;
      const pending = t.criteria_total - satisfied;
      lines.push(`Criteria: ${satisfied}/${t.criteria_total} satisfied${pending > 0 ? ` — ${pending} PENDING` : ' — all done'}`);
    } else if (t.acceptance_criteria.length > 0) {
      lines.push(`Criteria: ${t.acceptance_criteria.length} loaded (call teamx_get_task_detail for satisfaction status)`);
    } else {
      lines.push(`Criteria: not loaded — call teamx_get_task_detail`);
    }

    const vChecks = Object.entries(t.verification);
    if (vChecks.length > 0) {
      const passed = vChecks.filter(([, v]) => v.status === 'pass').length;
      lines.push(`Verification: ${passed}/${vChecks.length} passed`);
    }

    const g = t.git;
    lines.push(`Git: committed=${g.committed} pushed=${g.pushed} mr=${g.mr_iid ?? 'none'} merged=${g.merged}`);
  }

  if (state.active_milestone) {
    const m = state.active_milestone;
    lines.push(`Milestone: "${m.title}" (${m.done_tasks}/${m.total_tasks})`);
  }

  return lines.join('\n');
}

/**
 * Render the pause-for-decision block when the current task has an
 * unresolved pause. Returns null when no active pause exists.
 *
 * This is the structured "significant interrupt" — distinct from mode
 * directives, which fire on every gate transition. A pause means the
 * agent hit a genuine categorised blocker; the workflow does not advance
 * until `resolve_pause` is called.
 */
export function buildPauseBlock(state: TeamXState): string | null {
  const pause = state.current_task?.pause;
  if (!pause || pause.resolved === true || !pause.category) return null;

  const lines: string[] = [
    `⏸  PAUSE-FOR-DECISION [${pause.category}]`,
    pause.reason,
  ];
  if (pause.options) lines.push(`Opciones: ${pause.options}`);
  lines.push('Workflow parado. Resuelve con el usuario y corre: bash .teamx/lib/state.sh resolve_pause');
  return lines.join('\n');
}
