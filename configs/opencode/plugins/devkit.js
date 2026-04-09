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
  mcp__teamx__teamx_update_acceptance_criteria:  ['CLASSIFY', 'PLAN'],
  mcp__teamx__gitlab_create_merge_request:       ['MR'],
  mcp__teamx__gitlab_merge:                      ['MR', 'MERGE'],
  mcp__teamx__gitlab_retry_job:                  ['PIPELINE'],
}

const BASH_GATE_RULES = [
  { pattern: /\bgit\s+commit\b/,      allowedGates: ['COMMIT'],              description: 'git commit' },
  { pattern: /\bgit\s+push\b/,        allowedGates: ['PUSH'],                description: 'git push' },
  { pattern: /\bgit\s+merge\b/,       allowedGates: ['MERGE'],               description: 'git merge' },
  { pattern: /\bgit\s+checkout\s+-b/, allowedGates: ['CLASSIFY'],            description: 'git checkout -b' },
  { pattern: /\bgit\s+switch\s+-c/,   allowedGates: ['CLASSIFY'],            description: 'git switch -c' },
  { pattern: /verify\.sh\b/,          allowedGates: ['VERIFY'],              description: 'verify.sh' },
  { pattern: /\bgit\s+reset\b/,       allowedGates: ['CLASSIFY', 'IMPLEMENT'], description: 'git reset' },
  { pattern: /\bgit\s+rebase\b/,      allowedGates: [],                      description: 'git rebase' },
  { pattern: /\bgit\s+clean\b/,       allowedGates: ['CLASSIFY', 'IMPLEMENT'], description: 'git clean' },
  { pattern: /\bgit\s+restore\b/,     allowedGates: ['CLASSIFY', 'IMPLEMENT'], description: 'git restore' },
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
  RETROSPECTIVE: { mode: 'REVIEW',    hint: 'At least 1 insight. Push lessons before advancing.' },
}

function isStateShCommand(args) {
  const command = (args?.command) || ''
  return /state\.sh/.test(command) &&
    /\b(set_gate|set_current_task|set_work_type|set_readiness|approve_plan|complete_current_task)\b/.test(command)
}

function buildPostToolContext(toolName, toolArgs, toolOutput, cwd) {
  const isStateSh = toolName === 'Bash' && isStateShCommand(toolArgs)
  if (!STATE_TRIGGER_TOOLS.has(toolName) && !isStateSh) return null

  const state = readState(cwd)
  if (!state) return null

  if (isStateSh) resetBlockCount(cwd)

  const messages = []

  if (toolName === 'mcp__teamx__teamx_get_workflow_state' && state.current_task) {
    messages.push(
      `[TeamX] Task in state: "${state.current_task.title}" (${state.current_task.uuid}). ` +
      `Call teamx_get_task_detail for full description and acceptance criteria.`
    )
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
    try {
      const parsed = JSON.parse(outputStr)
      const criteria = parsed?.data?.data?.acceptance_criteria ?? []
      if (criteria.length > 0) {
        const total = criteria.length
        const satisfied = criteria.filter(c => c.is_satisfied === true).length
        const pending = total - satisfied
        messages.push(
          `[TeamX Criteria Progress] ${satisfied}/${total} satisfied${pending > 0 ? ` — ${pending} PENDING` : ' — all done'}.\n` +
          `Run: source .teamx/lib/state.sh && set_criteria_progress ${total} ${satisfied}`
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

        const context = buildPostToolContext(toolName, toolArgs, toolOutput, cwd)
        if (context && output) {
          // Append devkit context to the tool output so the LLM sees it
          const existing = typeof output.result === 'string' ? output.result : JSON.stringify(output.result ?? '')
          output.result = existing + '\n\n' + context
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

        // State summary
        messages.push(`[TeamX State Restored]\n${buildStateSummary(state)}`)

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

        // Persona
        const personaPath = join(cwd, '.teamx', 'persona.yaml')
        if (existsSync(personaPath)) {
          const persona = readFileSync(personaPath, 'utf-8').trim()
          if (persona) messages.push(`[TeamX Persona — Active]\n${persona}`)
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

        const criteriaReminder = state.current_task
          ? `\n\n⚠ CRITERIA: After compaction, call teamx_get_task_detail("${state.current_task.uuid}") to restore acceptance criteria status.`
          : ''

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
