/**
 * Stop Hook: Completion Guard
 *
 * Blocks the agent from stopping when work is in progress.
 * Allows stopping only at safe gates (IDLE, INIT, SELECT) or
 * after a safety valve (5 consecutive blocks).
 */

import { existsSync, readFileSync, writeFileSync, mkdirSync } from 'fs';
import { join, dirname } from 'path';
import { readState, buildStateSummary, type TeamXState } from '../state-reader.js';
import { SAFE_STOP_GATES } from '../gate-rules.js';

const MAX_CONSECUTIVE_BLOCKS = 5;

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

function getBlockCountFile(cwd: string): string {
  return join(cwd, '.teamx', 'stop-guard-count.json');
}

function readBlockCount(cwd: string): number {
  const file = getBlockCountFile(cwd);
  try {
    if (existsSync(file)) {
      const data = JSON.parse(readFileSync(file, 'utf-8'));
      return data.count || 0;
    }
  } catch { /* ignore */ }
  return 0;
}

function writeBlockCount(cwd: string, count: number): void {
  const file = getBlockCountFile(cwd);
  try {
    const dir = dirname(file);
    if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
    writeFileSync(file, JSON.stringify({ count, updated_at: new Date().toISOString() }));
  } catch { /* best-effort */ }
}

export function resetBlockCount(cwd: string): void {
  writeBlockCount(cwd, 0);
}

// ---------------------------------------------------------------------------
// Gap #6 — Emergency handoff on safety valve
// ---------------------------------------------------------------------------

function writeEmergencyHandoff(cwd: string, state: TeamXState): void {
  const handoffPath = join(cwd, '.teamx', 'handoff.md');
  const t = state.current_task;
  const lines = [
    `# Emergency Handoff — Safety Valve Triggered`,
    ``,
    `> Generated automatically after ${MAX_CONSECUTIVE_BLOCKS} consecutive stop-guard blocks.`,
    `> Resume with: \`/teamx-handoff resume\``,
    ``,
    `**Date:** ${new Date().toISOString()}`,
    `**Gate at exit:** \`${state.current_gate}\``,
    ``,
    `## Task`,
    `- **Title:** ${t?.title ?? 'none'}`,
    `- **UUID:** ${t?.uuid ?? 'none'}`,
    `- **Branch:** ${t?.branch ?? 'none'}`,
    `- **Work type:** ${t?.work_type ?? 'unknown'} (${t?.flow_variant ?? 'standard'})`,
    `- **Readiness:** ${t?.readiness ?? 'unknown'}`,
    ``,
    `## Git State`,
    `- Committed: ${t?.git?.committed ?? false}`,
    `- Commit SHA: ${t?.git?.commit_sha ?? 'none'}`,
    `- Pushed: ${t?.git?.pushed ?? false}`,
    `- MR IID: ${t?.git?.mr_iid ?? 'none'}`,
    `- Pipeline: ${t?.git?.pipeline_status ?? 'none'}`,
    `- Merged: ${t?.git?.merged ?? false}`,
    ``,
    `## Verification`,
  ];

  if (t?.verification) {
    const checks = Object.entries(t.verification);
    if (checks.length > 0) {
      for (const [name, v] of checks) {
        lines.push(`- ${v.status === 'pass' ? '✓' : '✗'} ${name}: ${v.status}`);
      }
    } else {
      lines.push(`- No checks recorded`);
    }
  }

  lines.push(
    ``,
    `## Acceptance Criteria`,
    t?.acceptance_criteria?.length
      ? t.acceptance_criteria.map(c => `- ${c}`).join('\n')
      : `- Not loaded — call teamx_get_task_detail(${t?.uuid ?? ''}) after resuming`,
    ``,
    `## Milestone`,
    `- ${state.active_milestone?.title ?? 'none'} (${state.active_milestone?.done_tasks ?? 0}/${state.active_milestone?.total_tasks ?? 0})`,
    ``,
    `## ⚠ Warning`,
    `Agent exited by safety valve — work at gate \`${state.current_gate}\` may be incomplete.`,
    `Check uncommitted changes before resuming.`,
  );

  try {
    writeFileSync(handoffPath, lines.join('\n'), 'utf-8');
  } catch { /* best-effort */ }
}

export function handleStop(data: StopInput): StopOutput {
  const cwd = data.cwd || data.directory || process.cwd();
  const reason = data.stop_hook_reason || data.stopHookReason || '';

  // Always allow on user abort, context limit, rate limit
  const safeReasons = ['user_abort', 'context_limit', 'rate_limit', 'auth_error'];
  if (safeReasons.some(r => reason.toLowerCase().includes(r))) {
    resetBlockCount(cwd);
    return { decision: 'approve' };
  }

  // No state file → not in a workflow
  const state = readState(cwd);
  if (!state) {
    return { decision: 'approve' };
  }

  const gate = state.current_gate;

  // Safe gates → allow stop
  if (SAFE_STOP_GATES.includes(gate as any)) {
    resetBlockCount(cwd);
    return { decision: 'approve' };
  }

  // Safety valve: after MAX_CONSECUTIVE_BLOCKS, allow stop — but write emergency handoff first (Gap #6)
  const count = readBlockCount(cwd);
  if (count >= MAX_CONSECUTIVE_BLOCKS) {
    writeEmergencyHandoff(cwd, state);
    resetBlockCount(cwd);
    return {
      decision: 'approve',
      reason: `[TeamX Stop Guard] Safety valve: allowing stop after ${MAX_CONSECUTIVE_BLOCKS} consecutive blocks. ` +
        `Emergency handoff written to .teamx/handoff.md — resume with /teamx-handoff resume.`,
    };
  }

  // Block the stop — work in progress
  writeBlockCount(cwd, count + 1);

  const summary = buildStateSummary(state);
  return {
    decision: 'block',
    reason: `[TeamX Stop Guard] Work in progress — cannot stop.\n\n${summary}\n\n` +
      `Complete the current gate (${gate}) before stopping. ` +
      `Run: source .teamx/lib/state.sh && print_status` +
      (count > 0 ? `\n(Block ${count + 1}/${MAX_CONSECUTIVE_BLOCKS} — safety valve at ${MAX_CONSECUTIVE_BLOCKS})` : ''),
  };
}
