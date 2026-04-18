/**
 * TeamX DevKit — OpenCode Plugin
 *
 * Ports the Claude Code hook system to OpenCode's plugin API.
 * Self-contained — no external devkit imports required.
 *
 * Installation: copy to .opencode/plugins/devkit.js in the target project.
 * OpenCode loads all files from .opencode/plugins/ automatically.
 *
 * Hook mapping:
 *   Claude Code PreToolUse  → tool.execute.before  (gate enforcement)
 *   Claude Code PostToolUse → tool.execute.after   (state tracking + QA warnings)
 *   Claude Code SessionStart → session.created      (state restoration)
 *   Claude Code PreCompact  → experimental.session.compacting (context preservation)
 *   Claude Code Stop        → session.idle          (stop guard — best-effort)
 */

import { readFileSync, existsSync, writeFileSync, mkdirSync } from 'fs'
import { join, dirname } from 'path'

// ============================================================
// STATE READER (ported from src/state-reader.ts)
// ============================================================

const ALL_GATES = [
  'IDLE', 'INIT', 'SELECT', 'CLASSIFY', 'PLAN',
  'IMPLEMENT', 'VERIFY', 'COMMIT', 'PUSH', 'MR',
  'PIPELINE', 'REVIEW', 'MERGE', 'EVIDENCE', 'RETROSPECTIVE',
]

function readState(cwd) {
  const statePath = join(cwd, '.teamx', 'state.json')
  if (!existsSync(statePath)) return null
  try {
    return JSON.parse(readFileSync(statePath, 'utf-8'))
  } catch {
    return null
  }
}

function readGate(cwd) {
  const state = readState(cwd)
  if (!state) return 'IDLE'
  const gate = state.current_gate
  return ALL_GATES.includes(gate) ? gate : 'IDLE'
}

function buildStateSummary(state) {
  const t = state.current_task
  const lines = [`Project: ${state.project_code} | Gate: ${state.current_gate}`]

  if (t) {
    lines.push(`Task: "${t.title}" (${t.uuid})`)
    if (t.work_type) lines.push(`Type: ${t.work_type} (${t.flow_variant || 'standard'})`)
    if (t.branch) lines.push(`Branch: ${t.branch}`)
    if (t.readiness) lines.push(`Readiness: ${t.readiness}`)
    if (t.plan) lines.push(`Plan: ${t.plan.approved ? 'approved' : 'pending approval'}`)

    if (t.criteria_total !== undefined && t.criteria_total > 0) {
      const satisfied = t.criteria_satisfied ?? 0
      const pending = t.criteria_total - satisfied
      lines.push(`Criteria: ${satisfied}/${t.criteria_total} satisfied${pending > 0 ? ` — ${pending} PENDING` : ' — all done'}`)
    } else if (t.acceptance_criteria?.length > 0) {
      lines.push(`Criteria: ${t.acceptance_criteria.length} loaded`)
    } else {
      lines.push(`Criteria: not loaded — call teamx_get_task_detail`)
    }

    const vChecks = Object.entries(t.verification ?? {})
    if (vChecks.length > 0) {
      const passed = vChecks.filter(([, v]) => v.status === 'pass').length
      lines.push(`Verification: ${passed}/${vChecks.length} passed`)
    }

    const g = t.git
    if (g) lines.push(`Git: committed=${g.committed} pushed=${g.pushed} mr=${g.mr_iid ?? 'none'} merged=${g.merged}`)
  }

  if (state.active_milestone) {
    const m = state.active_milestone
    lines.push(`Milestone: "${m.title}" (${m.done_tasks}/${m.total_tasks})`)
  }

  return lines.join('\n')
}

/**
 * Render the pause-for-decision block when the current task has an
 * unresolved pause. Port of state-reader.ts buildPauseBlock (Phase 1).
 */
function buildPauseBlock(state) {
  const pause = state.current_task?.pause
  if (!pause || pause.resolved === true || !pause.category) return null

  const lines = [
    `⏸  PAUSE-FOR-DECISION [${pause.category}]`,
    pause.reason,
  ]
  if (pause.options) lines.push(`Opciones: ${pause.options}`)
  lines.push('Workflow parado. Resuelve con el usuario y corre: source .teamx/lib/state.sh && resolve_pause')
  return lines.join('\n')
}

// ============================================================
// GATE RULES (ported from src/gate-rules.ts)
// ============================================================

const TOOL_GATE_MAP = {
  Edit:                                          ['IMPLEMENT'],
  Write:                                         ['IMPLEMENT'],
  MultiEdit:                                     ['IMPLEMENT'],
  NotebookEdit:                                  ['IMPLEMENT'],
  mcp__teamx__teamx_transition_task:             ['SELECT', 'EVIDENCE'],
  mcp__teamx__teamx_batch_transition_tasks:      ['SELECT', 'EVIDENCE'],
  mcp__teamx__teamx_satisfy_acceptance_criterion:['EVIDENCE'],
  mcp__teamx__teamx_log_time_entry:              ['EVIDENCE'],
  mcp__teamx__teamx_push_lessons:                ['RETROSPECTIVE'],
  mcp__teamx__teamx_update_lesson:               ['RETROSPECTIVE'],
  mcp__teamx__teamx_delete_lesson:               ['RETROSPECTIVE'],
  mcp__teamx__teamx_set_knowledge:               ['PLAN', 'RETROSPECTIVE'],
  mcp__teamx__teamx_delete_knowledge:            ['RETROSPECTIVE'],
  mcp__teamx__teamx_update_acceptance_criteria:  ['CLASSIFY', 'PLAN'],
  mcp__teamx__gitlab_create_merge_request:       ['MR'],
  mcp__teamx__gitlab_merge:                      ['MR', 'MERGE'],
  mcp__teamx__gitlab_retry_job:                  ['PIPELINE'],
}

const BASH_GATE_RULES = [
  { pattern: /\bgit\s+commit\b/,          allowedGates: ['COMMIT'],              description: 'git commit' },
  { pattern: /\bgit\s+push\b/,            allowedGates: ['PUSH'],                description: 'git push' },
  { pattern: /\bgit\s+merge\b/,           allowedGates: ['MERGE'],               description: 'git merge' },
  // Phase 3.7 — per-feature strategy may checkout -B (reset to tracking)
  // or plain `git checkout <branch>` to reuse a sibling task's feature branch.
  { pattern: /\bgit\s+checkout\s+-[bB]\b/,allowedGates: ['CLASSIFY'],            description: 'git checkout -b / -B (create or reset branch)' },
  { pattern: /\bgit\s+checkout\s+[^-\s]/, allowedGates: ['CLASSIFY'],            description: 'git checkout <branch> (switch)' },
  { pattern: /\bgit\s+switch\s+-c\b/,     allowedGates: ['CLASSIFY'],            description: 'git switch -c (create branch)' },
  { pattern: /\bgit\s+switch\s+[^-\s]/,   allowedGates: ['CLASSIFY'],            description: 'git switch <branch>' },
  { pattern: /verify\.sh\b/,              allowedGates: ['VERIFY'],              description: 'verify.sh' },
  { pattern: /\bgit\s+reset\b/,           allowedGates: ['CLASSIFY', 'IMPLEMENT'], description: 'git reset' },
  { pattern: /\bgit\s+rebase\b/,          allowedGates: [],                      description: 'git rebase' },
  { pattern: /\bgit\s+clean\b/,           allowedGates: ['CLASSIFY', 'IMPLEMENT'], description: 'git clean' },
  { pattern: /\bgit\s+restore\b/,         allowedGates: ['CLASSIFY', 'IMPLEMENT'], description: 'git restore' },
]

const SKIP_GATES = {
  compressed: ['PLAN'],
  discovery:  ['VERIFY', 'COMMIT', 'PUSH', 'MR', 'PIPELINE', 'REVIEW', 'MERGE'],
}

const SAFE_STOP_GATES = ['IDLE', 'INIT', 'SELECT']

const ALWAYS_ALLOWED = new Set([
  'Read', 'Glob', 'Grep', 'Bash', 'Agent', 'Task', 'TaskCreate',
  'TaskUpdate', 'TaskList', 'TaskGet', 'AskUserQuestion',
  'EnterPlanMode', 'ExitPlanMode', 'Skill', 'WebSearch', 'WebFetch',
  'LSP', 'ToolSearch',
  'mcp__engram__get_context',
  'mcp__engram__save_observation',
])

function expandGatesForVariant(gates, flowVariant) {
  const skipped = SKIP_GATES[flowVariant] ?? []
  return skipped.length === 0 ? gates : gates.filter(g => !skipped.includes(g))
}

function checkToolAllowed(toolName, toolArgs, currentGate, flowVariant = 'standard') {
  // Bash: check command patterns
  if (toolName === 'Bash') {
    const command = (toolArgs?.command) || ''
    if (!command) return { allowed: true }

    for (const rule of BASH_GATE_RULES) {
      if (rule.pattern.test(command)) {
        const effective = expandGatesForVariant(rule.allowedGates, flowVariant)
        if (!effective.includes(currentGate)) {
          return {
            allowed: false,
            reason: `[TeamX Gate Guard] Cannot run "${rule.description}" at gate ${currentGate}. ` +
              `Allowed gates: ${rule.allowedGates.join(', ')}. Advance the state machine first.`,
          }
        }
      }
    }
    return { allowed: true }
  }

  if (ALWAYS_ALLOWED.has(toolName)) return { allowed: true }

  const allowedGates = TOOL_GATE_MAP[toolName]
  if (!allowedGates) return { allowed: true }

  const effective = expandGatesForVariant(allowedGates, flowVariant)
  if (effective.includes(currentGate)) return { allowed: true }

  return {
    allowed: false,
    reason: `[TeamX Gate Guard] Cannot use ${toolName} at gate ${currentGate}. ` +
      `Allowed gates: ${allowedGates.join(', ')}. Advance the state machine to the correct gate first.`,
  }
}

// ============================================================
// STOP GUARD helpers (ported from src/hooks/stop-guard.ts)
// ============================================================

const MAX_CONSECUTIVE_BLOCKS = 5

function getBlockCountFile(cwd) {
  return join(cwd, '.teamx', 'stop-guard-count.json')
}

function readBlockCount(cwd) {
  const file = getBlockCountFile(cwd)
  try {
    if (existsSync(file)) return JSON.parse(readFileSync(file, 'utf-8')).count || 0
  } catch { /* ignore */ }
  return 0
}

function writeBlockCount(cwd, count) {
  const file = getBlockCountFile(cwd)
  try {
    mkdirSync(dirname(file), { recursive: true })
    writeFileSync(file, JSON.stringify({ count, updated_at: new Date().toISOString() }))
  } catch { /* best-effort */ }
}

function resetBlockCount(cwd) {
  writeBlockCount(cwd, 0)
}

function writeEmergencyHandoff(cwd, state) {
  const t = state.current_task
  const lines = [
    `# Emergency Handoff — Safety Valve Triggered`,
    ``,
    `> Generated after ${MAX_CONSECUTIVE_BLOCKS} consecutive stop-guard blocks.`,
    ``,
    `**Date:** ${new Date().toISOString()}`,
    `**Gate at exit:** \`${state.current_gate}\``,
    ``,
    `## Task`,
    `- **Title:** ${t?.title ?? 'none'}`,
    `- **UUID:** ${t?.uuid ?? 'none'}`,
    `- **Branch:** ${t?.branch ?? 'none'}`,
    `- **Work type:** ${t?.work_type ?? 'unknown'} (${t?.flow_variant ?? 'standard'})`,
    ``,
    `## Git State`,
    `- Committed: ${t?.git?.committed ?? false}`,
    `- Commit SHA: ${t?.git?.commit_sha ?? 'none'}`,
    `- Pushed: ${t?.git?.pushed ?? false}`,
    `- MR IID: ${t?.git?.mr_iid ?? 'none'}`,
    ``,
    `## Warning`,
    `Agent exited by safety valve — work at gate \`${state.current_gate}\` may be incomplete.`,
  ]
  try {
    writeFileSync(join(cwd, '.teamx', 'handoff.md'), lines.join('\n'), 'utf-8')
  } catch { /* best-effort */ }
}

// ============================================================
// POST-TOOL helpers (ported from src/hooks/post-tool-state.ts)
// ============================================================

const STATE_TRIGGER_TOOLS = new Set([
  'mcp__teamx__teamx_get_workflow_state',
  'mcp__teamx__teamx_get_task_detail',
  'mcp__teamx__teamx_transition_task',
  'mcp__teamx__teamx_batch_transition_tasks',
  'mcp__teamx__teamx_satisfy_acceptance_criterion',
  'mcp__teamx__teamx_update_acceptance_criteria',
])

const GATE_MODE_MAP = {
  SELECT:        { mode: 'EXECUTION', hint: 'Pick highest-priority available task.' },
  CLASSIFY:      { mode: 'PAIRING',   hint: 'Analyze work type and readiness. Name type, criteria clarity, and blockers.' },
  PLAN:          { mode: 'PAIRING',   hint: 'Propose plan with tradeoffs. Wait for approval before proceeding.' },
  IMPLEMENT:     { mode: 'EXECUTION', hint: 'Path clear. Minimal narration during routine work.' },
  VERIFY:        { mode: 'RECOVERY',  hint: 'Report each check result. On failure: root cause + repair plan.' },
  COMMIT:        { mode: 'EXECUTION', hint: 'Encapsulate cleanly. Brief and factual.' },
  PUSH:          { mode: 'EXECUTION', hint: 'Signal forward movement. Minimal.' },
  MR:            { mode: 'EXECUTION', hint: 'Confirm MR created. Do NOT set merge-when-pipeline-succeeds.' },
  PIPELINE:      { mode: 'RECOVERY',  hint: 'On failure: read job log, diagnose, set gate back to VERIFY.' },
  REVIEW:        { mode: 'REVIEW',    hint: 'Present criteria evidence. Do NOT self-approve — wait for human QA.' },
  MERGE:         { mode: 'EXECUTION', hint: 'Confirm integration. Handle conflicts explicitly.' },
  EVIDENCE:      { mode: 'REVIEW',    hint: 'Map each criterion to concrete evidence. Be specific.' },
  RETROSPECTIVE: { mode: 'REVIEW',    hint: 'At least 1 insight. Push lessons with teamx_push_lessons. Update or delete stale lessons with teamx_update_lesson / teamx_delete_lesson. Capture ADRs, conventions and stack decisions with teamx_set_knowledge before advancing.' },
}

// ============================================================
// EXTENSIONS LOADER (ported from src/extensions.ts — Phase 3.5)
// ============================================================
// Declarative hook system: plugins declare before_<gate>/after_<gate>
// commands in .teamx/extensions.yml. Keeps custom delivery hooks out
// of state.sh while giving teams a controlled extension surface.
// ============================================================

const EXTENSIONS_PATH = '.teamx/extensions.yml'
const EXT_MAX_OUTPUT_BYTES = 4000
const EXT_DEFAULT_TIMEOUT_MS = 10_000

function parseExtensionsYaml(raw) {
  const lines = raw.split(/\r?\n/)
  const hooks = {}
  let currentHook = null
  let currentEntry = null

  const flushEntry = () => {
    if (currentHook && currentEntry && currentEntry.extension && currentEntry.command) {
      hooks[currentHook].push({
        extension: currentEntry.extension,
        command: currentEntry.command,
        optional: currentEntry.optional === true,
      })
    }
    currentEntry = null
  }

  for (const rawLine of lines) {
    const line = rawLine.replace(/#.*$/, '').trimEnd()
    if (line.trim() === '') continue
    if (line === 'hooks:') continue

    const hookMatch = line.match(/^ {2}([a-z_]+):$/i)
    if (hookMatch) {
      flushEntry()
      currentHook = hookMatch[1]
      hooks[currentHook] = hooks[currentHook] ?? []
      continue
    }
    const listStart = line.match(/^ {4}-\s*extension:\s*(.+)$/)
    if (listStart) {
      flushEntry()
      currentEntry = { extension: listStart[1].trim().replace(/^["']|["']$/g, '') }
      continue
    }
    const fieldMatch = line.match(/^ {6}([a-z_]+):\s*(.+)$/)
    if (fieldMatch && currentEntry) {
      const key = fieldMatch[1]
      let value = fieldMatch[2].trim().replace(/^["']|["']$/g, '')
      if (key === 'optional') value = value === 'true'
      currentEntry[key] = value
    }
  }
  flushEntry()
  return { hooks }
}

function loadExtensions(cwd) {
  const path = join(cwd, EXTENSIONS_PATH)
  if (!existsSync(path)) return null
  try {
    return parseExtensionsYaml(readFileSync(path, 'utf-8'))
  } catch {
    return null
  }
}

function truncateExtOutput(s) {
  if (!s || s.length <= EXT_MAX_OUTPUT_BYTES) return s
  return s.slice(0, EXT_MAX_OUTPUT_BYTES) + '\n…[truncated]'
}

async function runExtensionHooks(cwd, phase, gate, state) {
  const file = loadExtensions(cwd)
  if (!file) return []
  const key = `${phase}_${gate.toLowerCase()}`
  const hooks = file.hooks?.[key] ?? []
  if (hooks.length === 0) return []

  // Lazy-load child_process only when extensions are configured (OpenCode
  // sandbox may not always expose it; fail gracefully).
  let spawnSync
  try {
    const mod = await import('child_process')
    spawnSync = mod.spawnSync
  } catch {
    return []
  }

  const payload = JSON.stringify({
    gate,
    phase,
    project_code: state.project_code,
    task_uuid: state.current_task?.uuid ?? null,
    state_summary: {
      current_gate: state.current_gate,
      task_title: state.current_task?.title ?? null,
      work_type: state.current_task?.work_type ?? null,
    },
  })

  const results = []
  for (const hook of hooks) {
    try {
      const proc = spawnSync('sh', ['-c', hook.command], {
        cwd,
        input: payload,
        timeout: EXT_DEFAULT_TIMEOUT_MS,
        encoding: 'utf-8',
      })
      const exitCode = proc.status ?? (proc.signal ? 124 : 1)
      results.push({
        extension: hook.extension,
        phase, gate,
        exit_code: exitCode,
        stdout: truncateExtOutput(proc.stdout ?? ''),
        stderr: truncateExtOutput(proc.stderr ?? ''),
        optional: hook.optional,
        ok: exitCode === 0,
      })
    } catch (err) {
      results.push({
        extension: hook.extension,
        phase, gate,
        exit_code: -1,
        stdout: '',
        stderr: err?.message ?? String(err),
        optional: hook.optional,
        ok: false,
      })
    }
  }
  return results
}

function buildExtensionReport(results) {
  if (!results || results.length === 0) return null
  const lines = [`[TeamX Extensions — ${results[0].phase}_${results[0].gate.toLowerCase()}]`]
  for (const r of results) {
    const label = r.ok ? '✓' : r.optional ? '⚠ (optional)' : '✗ BLOCKING'
    lines.push(`${label} ${r.extension} (exit ${r.exit_code})`)
    if (r.stdout?.trim() !== '') lines.push(`  stdout: ${r.stdout.trim()}`)
    if (!r.ok && r.stderr?.trim() !== '') lines.push(`  stderr: ${r.stderr.trim()}`)
  }
  const mandatoryFailures = results.filter(r => !r.ok && !r.optional)
  if (mandatoryFailures.length > 0) {
    lines.push('')
    lines.push(
      `Mandatory extension(s) failed: ${mandatoryFailures.map(r => r.extension).join(', ')}. ` +
      `Register pause_for_decision "security-risk-detected" or "manual-review-required" before advancing.`
    )
  }
  return lines.join('\n')
}

function isStateShCommand(args) {
  const command = (args?.command) || ''
  // Keep in sync with src/hooks/post-tool-state.ts isStateShCommand.
  // Matches both `source .teamx/lib/state.sh && FN ...` (legacy) and
  // `bash .teamx/lib/state.sh FN ...` (v2.2.3+ CLI dispatcher — preferred,
  // avoids Claude Code's "source evaluates shell code" warning).
  return /state\.sh/.test(command) &&
    /\b(set_gate|set_current_task|set_work_type|set_readiness|approve_plan|complete_current_task|auto_approve_plan_if_safe|auto_approve_qa_if_green|approve_qa_review|pause_for_decision|resolve_pause|set_task_user_story|register_feature_branch|register_feature_mr)\b/.test(command)
}

function buildPostToolContext(toolName, toolArgs, toolOutput, cwd) {
  const isStateSh = toolName === 'Bash' && isStateShCommand(toolArgs)
  if (!STATE_TRIGGER_TOOLS.has(toolName) && !isStateSh) return null

  const state = readState(cwd)
  if (!state) return null

  if (isStateSh) resetBlockCount(cwd)

  const messages = []

  if (toolName === 'mcp__teamx__teamx_get_workflow_state') {
    if (state.current_task) {
      messages.push(
        `[TeamX] Task in state: "${state.current_task.title}" (${state.current_task.uuid}). ` +
        `Call teamx_get_task_detail for full description and acceptance criteria.`
      )
    }
    // Gap #1 — server-authoritative qa_warnings (duplicate criteria, etc.)
    try {
      const outputStr = typeof toolOutput === 'string' ? toolOutput : JSON.stringify(toolOutput)
      const parsed = JSON.parse(outputStr)
      const warnings = parsed?.data?.data?.qa_warnings ?? []
      if (Array.isArray(warnings) && warnings.length > 0) {
        const serverWarnings = warnings.filter(w => typeof w === 'string')
        if (serverWarnings.length > 0) messages.push(serverWarnings.join('\n\n'))
      }
    } catch { /* ignore */ }
  }

  if (toolName === 'mcp__teamx__teamx_get_task_detail') {
    const outputStr = typeof toolOutput === 'string' ? toolOutput : JSON.stringify(toolOutput)
    const criteriaMissing = outputStr.includes('"criteria_status":"missing"') ||
                            outputStr.includes('"criteria_status": "missing"')
    if (criteriaMissing && state.current_task?.work_type !== 'chore') {
      messages.push(
        `[TeamX WARNING] Task has no acceptance criteria. ` +
        `Set readiness to "needs_refinement" in CLASSIFY and post a blocker.`
      )
    }
    // Phase 1 — persist criteria snapshot to .teamx/criteria-cache.json so
    // acceptance criteria survive context compaction without manual refresh.
    try {
      const parsed = JSON.parse(outputStr)
      const criteria = parsed?.data?.data?.acceptance_criteria ?? []
      const taskUuid = parsed?.data?.data?.uuid ?? state.current_task?.uuid ?? ''
      if (criteria.length > 0 && taskUuid) {
        const total = criteria.length
        const satisfied = criteria.filter(c => c.is_satisfied === true).length
        const pending = total - satisfied

        try {
          const cachePath = join(cwd, '.teamx', 'criteria-cache.json')
          mkdirSync(dirname(cachePath), { recursive: true })
          const tmp = cachePath + '.tmp'
          writeFileSync(tmp, JSON.stringify({
            task_uuid: taskUuid,
            total,
            satisfied,
            refreshed_at: new Date().toISOString(),
            criteria: criteria.map(c => ({
              sort_order: c.sort_order,
              description: c.description,
              is_satisfied: c.is_satisfied === true,
              evidence: c.evidence ?? null,
            })),
          }, null, 2))
          // atomic-ish: rename via fs (import at top)
          writeFileSync(cachePath, readFileSync(tmp, 'utf-8'))
          try { mkdirSync(dirname(tmp), { recursive: true }) } catch { /* noop */ }
        } catch { /* best-effort cache — never fail the hook */ }

        messages.push(
          `[TeamX Criteria Progress] ${satisfied}/${total} satisfied${pending > 0 ? ` — ${pending} PENDING` : ' — all done'}.\n` +
          `Snapshot cached at .teamx/criteria-cache.json (survives compaction).\n` +
          `Run: source .teamx/lib/state.sh && set_criteria_progress ${total} ${satisfied}`
        )
      }
    } catch { /* ignore */ }
  }

  // Phase 3 — confirmation after criteria update so agent knows to re-check readiness.
  if (toolName === 'mcp__teamx__teamx_update_acceptance_criteria') {
    try {
      const outputStr = typeof toolOutput === 'string' ? toolOutput : JSON.stringify(toolOutput)
      const parsed = JSON.parse(outputStr)
      const criteria = parsed?.data?.data?.acceptance_criteria
        ?? parsed?.data?.acceptance_criteria
        ?? []
      const mode = (toolArgs?.mode) || 'replace'
      if (criteria.length > 0) {
        messages.push(
          `[TeamX Criteria Updated — ${mode.toUpperCase()}]\n` +
          `${criteria.length} criteria now on task. ` +
          `Verify each is Given/When/Then and has a concrete pass/fail condition before advancing to IMPLEMENT.`
        )
      }
    } catch { /* ignore */ }
  }

  if (toolName === 'mcp__teamx__teamx_satisfy_acceptance_criterion') {
    try {
      const parsed = JSON.parse(typeof toolOutput === 'string' ? toolOutput : JSON.stringify(toolOutput))
      const inner = parsed?.data ?? parsed
      if (inner?.success === false) {
        messages.push(
          `[QA WARNING] teamx_satisfy_acceptance_criterion FAILED on backend.\n` +
          `Error: ${inner?.error ?? 'unknown error'}\n` +
          `The criterion was NOT marked satisfied. Verify and retry.`
        )
      }
      if (inner?.data?.already_satisfied === true) {
        messages.push(
          `[TeamX] Criterio ya estaba satisfecho previamente (already_satisfied=true). ` +
          `Evidencia existente: "${inner.data.existing_evidence ?? 'n/a'}".`
        )
      }
    } catch { /* ignore */ }
  }

  if (isStateSh || toolName === 'mcp__teamx__teamx_transition_task') {
    const summary = buildStateSummary(state)
    messages.push(`[TeamX State Updated]\n${summary}`)

    const entry = GATE_MODE_MAP[state.current_gate]
    if (entry && isStateSh && /set_gate/.test(toolArgs?.command || '')) {
      messages.push(`[TeamX Mode → ${entry.mode}]\nGate: ${state.current_gate} — ${entry.hint}`)
    }
  }

  // Phase 1 — always surface an unresolved pause even on non-state.sh calls so
  // the agent cannot drift past a flagged blocker.
  const pauseBlock = buildPauseBlock(state)
  if (pauseBlock) messages.push(pauseBlock)

  return messages.length > 0 ? messages.join('\n\n') : null
}

// ============================================================
// PLUGIN EXPORT
// ============================================================

export const DevKitPlugin = async ({ directory }) => {
  // `directory` is the project working directory (equivalent to cwd in Claude Code hooks)
  const cwd = directory

  return {
    /**
     * tool.execute.before — Gate Enforcement
     * Equivalent to Claude Code's PreToolUse hook.
     *
     * API: receives (input, output) where:
     *   input.tool = tool name
     *   output.args = tool arguments (can be mutated)
     * Throw to block the tool execution.
     */
    'tool.execute.before': async (input, output) => {
      try {
        const state = readState(cwd)
        if (!state) return  // no .teamx/state.json → not in a workflow

        const gate = readGate(cwd)
        if (gate === 'IDLE') return

        const toolName = input.tool ?? ''
        const toolArgs = output?.args ?? null
        const flowVariant = state.current_task?.flow_variant || 'standard'

        const result = checkToolAllowed(toolName, toolArgs, gate, flowVariant)
        if (!result.allowed) {
          throw new Error(result.reason)
        }
      } catch (err) {
        // Re-throw gate guard errors; swallow unexpected errors (never block agent on plugin crash)
        if (err.message?.startsWith('[TeamX Gate Guard]')) throw err
        // Unexpected error → log silently, allow tool
      }
    },

    /**
     * tool.execute.after — State Tracking + QA Warnings
     * Equivalent to Claude Code's PostToolUse hook.
     *
     * API: receives (input, output) where:
     *   input.tool = tool name
     *   input.args = tool arguments
     *   output.result = tool result
     */
    'tool.execute.after': async (input, output) => {
      try {
        const toolName = input.tool ?? ''
        const toolArgs = input.args ?? null
        const toolOutput = output?.result ?? null

        const messages = []
        const context = buildPostToolContext(toolName, toolArgs, toolOutput, cwd)
        if (context) messages.push(context)

        // Phase 3.5 — on set_gate transitions, run before_<newGate> extensions.
        if (toolName === 'Bash' && isStateShCommand(toolArgs) && /set_gate/.test(toolArgs?.command || '')) {
          const state = readState(cwd)
          if (state) {
            try {
              const results = await runExtensionHooks(cwd, 'before', state.current_gate, state)
              const report = buildExtensionReport(results)
              if (report) messages.push(report)
            } catch { /* extensions never block the hook itself */ }
          }
        }

        if (messages.length > 0 && output) {
          const existing = typeof output.result === 'string' ? output.result : JSON.stringify(output.result ?? '')
          output.result = existing + '\n\n' + messages.join('\n\n')
        }
      } catch {
        // Never crash on post-hook — swallow all errors
      }
    },

    /**
     * session.created — State Restoration
     * Equivalent to Claude Code's SessionStart hook.
     *
     * Injects state summary, handoff, lessons, and persona into
     * the session context so the LLM picks up where it left off.
     */
    'session.created': async (input) => {
      try {
        const state = readState(cwd)
        if (!state || state.current_gate === 'IDLE') return

        const messages = []

        // Phase 3.8 — default language reinforcement on every session.created.
        // persona.yaml is the source of truth; this block keeps the default
        // warm even after context compaction or cross-session jumps.
        messages.push(
          `[TeamX Language — default: es-MX]\n` +
          `Every user-facing message (narration, pauses, errors, progress, state summaries) ` +
          `must be in Spanish by default. Switch ONLY when the CURRENT user message ` +
          `addresses you in another language explicitly. Preserve verbatim: tool names, ` +
          `gate names, file paths, git refs, log excerpts, Given/When/Then syntax.`
        )

        // State summary
        messages.push(`[TeamX State Restored]\n${buildStateSummary(state)}`)

        // Phase 1 — surface unresolved pause as top-priority blocker on resume
        const pauseBlock = buildPauseBlock(state)
        if (pauseBlock) messages.push(pauseBlock)

        // Phase 1 — restore full acceptance criteria from cache so compaction
        // doesn't force a manual teamx_get_task_detail call on every resume.
        if (state.current_task) {
          const criteriaCachePath = join(cwd, '.teamx', 'criteria-cache.json')
          if (existsSync(criteriaCachePath)) {
            try {
              const cache = JSON.parse(readFileSync(criteriaCachePath, 'utf-8'))
              if (cache?.task_uuid === state.current_task.uuid && Array.isArray(cache.criteria)) {
                const list = cache.criteria
                  .slice()
                  .sort((a, b) => (a.sort_order ?? 0) - (b.sort_order ?? 0))
                  .map((c, i) => {
                    const mark = c.is_satisfied ? '✓' : '○'
                    const idx = c.sort_order ?? i
                    return `  [${idx}] ${mark} ${c.description ?? '(sin descripción)'}`
                  })
                  .join('\n')
                messages.push(
                  `[TeamX Criteria Restored — task ${cache.task_uuid}] ${cache.satisfied}/${cache.total} satisfied\n` +
                  list + '\n' +
                  `Cache timestamp: ${cache.refreshed_at}. ` +
                  `If the task changed upstream, call teamx_get_task_detail to refresh.`
                )
              }
            } catch { /* ignore */ }
          } else {
            messages.push(
              `[TeamX Criteria Missing] No local cache found for current task. ` +
              `Call teamx_get_task_detail("${state.current_task.uuid}") before advancing.`
            )
          }
        }

        // Handoff
        const handoffPath = join(cwd, '.teamx', 'handoff.md')
        if (existsSync(handoffPath)) {
          const handoff = readFileSync(handoffPath, 'utf-8').trim()
          if (handoff) messages.push(`[TeamX Handoff]\n${handoff}`)
        }

        // Local lessons
        const lessonsPath = join(cwd, '.teamx', 'lessons.json')
        if (existsSync(lessonsPath)) {
          const lessons = JSON.parse(readFileSync(lessonsPath, 'utf-8'))
          if (lessons?.patterns?.length > 0) {
            const top = lessons.patterns.slice(0, 3).map(p => `- ${p}`).join('\n')
            messages.push(`[TeamX Lessons — Local]\n${top}`)
          }
        }

        // Shared lessons
        const sharedPath = join(cwd, '.teamx', 'shared-lessons.json')
        if (existsSync(sharedPath)) {
          const shared = JSON.parse(readFileSync(sharedPath, 'utf-8'))
          const signals = shared?.shared_lessons ?? []
          if (signals.length > 0) {
            const top = signals.slice(0, 3)
              .map(s => `- [${s.gate}] ${s.pattern} (seen ${s.frequency}x across team)`)
              .join('\n')
            messages.push(`[TeamX Shared Lessons — Team]\n${top}`)
          }
        }

        // Project knowledge (from teamx_list_knowledge, saved at last INIT)
        const knowledgePath = join(cwd, '.teamx', 'project-knowledge.json')
        if (existsSync(knowledgePath)) {
          try {
            const knowledgeData = JSON.parse(readFileSync(knowledgePath, 'utf-8'))
            const items = knowledgeData?.items ?? []
            if (items.length > 0) {
              const top = items.slice(0, 5).map(k => `- [${k.type}] ${k.title}`).join('\n')
              messages.push(`[TeamX Project Knowledge]\n${top}`)
            }
          } catch { /* ignore */ }
        }

        // Persona
        const personaPath = join(cwd, '.teamx', 'persona.yaml')
        if (existsSync(personaPath)) {
          const persona = readFileSync(personaPath, 'utf-8').trim()
          if (persona) messages.push(`[TeamX Persona — Active]\n${persona}`)
        }

        // Phase 3.4 — Constitution injection. Project override takes priority
        // over agency baseline. Both are loaded if present, labelled by scope.
        const constitutionSources = [
          { label: 'project', path: join(cwd, '.teamx', 'constitution.md') },
        ]
        if (process.env.TEAMX_DEVKIT_ROOT) {
          constitutionSources.push({
            label: 'agency',
            path: join(process.env.TEAMX_DEVKIT_ROOT, 'teamx-lib', 'constitution.md'),
          })
        }
        if (process.env.HOME) {
          constitutionSources.push({
            label: 'agency',
            path: join(process.env.HOME, 'node_modules', 'teamx-devkit', 'teamx-lib', 'constitution.md'),
          })
        }
        const seenScopes = new Set()
        for (const { label, path } of constitutionSources) {
          if (seenScopes.has(label)) continue
          if (!existsSync(path)) continue
          try {
            const raw = readFileSync(path, 'utf-8').trim()
            if (!raw) continue
            const versionMatch = raw.match(/^version:\s*(.+)$/m)
            const version = versionMatch ? versionMatch[1].trim() : 'unversioned'
            const articles = []
            const articleRe = /^##\s+(Article\s+[IVXLC]+\s+—\s+.+?)$/gm
            let m
            while ((m = articleRe.exec(raw)) !== null) articles.push(m[1])
            messages.push(
              `[TeamX Constitution — ${label} v${version}]\n` +
              articles.map(a => `- ${a}`).join('\n') +
              `\nThese articles are MUST-level. Violations raise qa_warnings and block SDD approval.`
            )
            seenScopes.add(label)
          } catch { /* ignore */ }
        }

        // Experience layer (modes, voice)
        const expFiles = [
          { file: 'modes.yaml', label: 'Modes' },
          { file: 'voice.md',   label: 'Voice' },
        ]
        for (const { file, label } of expFiles) {
          const p = join(cwd, '.teamx', file)
          if (existsSync(p)) {
            const content = readFileSync(p, 'utf-8').trim()
            if (content) messages.push(`[TeamX ${label}]\n${content}`)
          }
        }

        // Inject into session via tui.prompt.append if available (OpenCode API)
        if (messages.length > 0 && input?.append) {
          input.append(messages.join('\n\n---\n\n'))
        }
      } catch {
        // Never crash on session start
      }
    },

    /**
     * experimental.session.compacting — Context Preservation
     * Equivalent to Claude Code's PreCompact hook.
     *
     * Injects a checkpoint summary that survives context window compaction.
     */
    'experimental.session.compacting': async (input, output) => {
      try {
        const state = readState(cwd)
        if (!state || state.current_gate === 'IDLE') return

        const summary = buildStateSummary(state)

        // Phase 1 — criteria cache freshness. session.created auto-restores
        // from .teamx/criteria-cache.json; we only prompt the agent when the
        // cache is stale (>30min) or absent.
        let criteriaReminder = ''
        if (state.current_task) {
          const cachePath = join(cwd, '.teamx', 'criteria-cache.json')
          let cacheOk = false
          if (existsSync(cachePath)) {
            try {
              const cache = JSON.parse(readFileSync(cachePath, 'utf-8'))
              const refreshedAt = typeof cache?.refreshed_at === 'string' ? Date.parse(cache.refreshed_at) : NaN
              const ageMinutes = Number.isFinite(refreshedAt) ? (Date.now() - refreshedAt) / 60000 : Infinity
              cacheOk = cache?.task_uuid === state.current_task.uuid && ageMinutes <= 30
            } catch { /* ignore */ }
          }
          criteriaReminder = cacheOk
            ? `\n\n✓ CRITERIA: snapshot in .teamx/criteria-cache.json is fresh — session.created will restore it automatically after compaction.`
            : `\n\n⚠ CRITERIA: cache stale or missing. After compaction, call teamx_get_task_detail("${state.current_task.uuid}") — the hook will persist the snapshot automatically on return.`
        }

        const experienceReminder = existsSync(join(cwd, '.teamx', 'persona.yaml'))
          ? `\n\n⚠ PERSONA: Re-read .teamx/persona.yaml, .teamx/modes.yaml, .teamx/voice.md to restore behavior contract.`
          : ''

        const checkpoint =
          `[TeamX Context Checkpoint — READ THIS AFTER COMPACTION]\n` +
          `${summary}` +
          criteriaReminder +
          experienceReminder +
          `\n\nRun: source .teamx/lib/state.sh && print_status`

        if (output) {
          output.summary = (output.summary ? output.summary + '\n\n' : '') + checkpoint
        }
      } catch {
        // Never crash on compaction
      }
    },

    /**
     * session.idle — Stop Guard (best-effort)
     * Approximate equivalent of Claude Code's Stop hook.
     *
     * Note: OpenCode may not have a direct "block agent from stopping" mechanism.
     * This hook fires when the session becomes idle — we use it to write a
     * warning/handoff if work is in progress at an unsafe gate.
     */
    'session.idle': async (input) => {
      try {
        const state = readState(cwd)
        if (!state) return

        const gate = state.current_gate
        if (SAFE_STOP_GATES.includes(gate) || gate === 'IDLE') {
          resetBlockCount(cwd)
          return
        }

        const count = readBlockCount(cwd)
        if (count >= MAX_CONSECUTIVE_BLOCKS) {
          writeEmergencyHandoff(cwd, state)
          resetBlockCount(cwd)
          return
        }

        writeBlockCount(cwd, count + 1)
        // Note: unlike Claude Code's Stop hook, we cannot truly block the agent here.
        // The handoff.md ensures context is preserved for the next session.
        writeEmergencyHandoff(cwd, state)
      } catch {
        // Never crash on idle
      }
    },
  }
}
