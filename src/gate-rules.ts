/**
 * Gate Rules — Maps tools to allowed gates.
 *
 * This is the core enforcement logic. It defines which tools
 * can be used at which gates in the state machine.
 */

import type { Gate } from './state-reader.js';

// --- Tool-to-gate mapping ---

/** Tools that require specific gates to be active */
const TOOL_GATE_MAP: Record<string, Gate[]> = {
  // File editing only during IMPLEMENT
  Edit: ['IMPLEMENT'],
  Write: ['IMPLEMENT'],
  MultiEdit: ['IMPLEMENT'],
  NotebookEdit: ['IMPLEMENT'],

  // MCP TeamX — task lifecycle
  mcp__teamx__teamx_transition_task: ['SELECT', 'EVIDENCE'],
  mcp__teamx__teamx_batch_transition_tasks: ['SELECT', 'EVIDENCE'],
  mcp__teamx__teamx_satisfy_acceptance_criterion: ['EVIDENCE'],
  mcp__teamx__teamx_log_time_entry: ['EVIDENCE'],
  mcp__teamx__teamx_push_lessons: ['RETROSPECTIVE'],

  // MCP TeamX — GitLab write operations
  mcp__teamx__gitlab_create_merge_request: ['MR'],
  mcp__teamx__gitlab_merge: ['MR', 'MERGE'],
  mcp__teamx__gitlab_retry_job: ['PIPELINE'],
};

/** Bash command patterns that require specific gates */
const BASH_GATE_RULES: Array<{ pattern: RegExp; allowedGates: Gate[]; description: string }> = [
  {
    pattern: /\bgit\s+commit\b/,
    allowedGates: ['COMMIT'],
    description: 'git commit',
  },
  {
    pattern: /\bgit\s+push\b/,
    allowedGates: ['PUSH'],
    description: 'git push',
  },
  {
    pattern: /\bgit\s+merge\b/,
    allowedGates: ['MERGE'],
    description: 'git merge',
  },
  {
    pattern: /\bgit\s+checkout\s+-b\b/,
    allowedGates: ['CLASSIFY'],
    description: 'git checkout -b (create branch)',
  },
  {
    pattern: /\bgit\s+switch\s+-c\b/,
    allowedGates: ['CLASSIFY'],
    description: 'git switch -c (create branch)',
  },
  {
    pattern: /verify\.sh\b/,
    allowedGates: ['VERIFY'],
    description: 'verify.sh',
  },
];

/** Gates that can be skipped per flow variant */
const SKIP_GATES: Record<string, Gate[]> = {
  compressed: ['PLAN'],
  discovery: ['VERIFY', 'COMMIT', 'PUSH', 'MR', 'PIPELINE', 'MERGE'],
};

/** Gates where it's safe to stop */
export const SAFE_STOP_GATES: Gate[] = ['IDLE', 'INIT', 'SELECT'];

// --- Checker ---

export interface GateCheckResult {
  allowed: boolean;
  reason?: string;
}

/**
 * Check if a tool is allowed at the current gate.
 *
 * @param toolName - The tool being invoked
 * @param toolInput - The tool's input (for Bash command inspection)
 * @param currentGate - The current gate from state.json
 * @param flowVariant - The current flow variant (standard/compressed/discovery)
 * @returns allowed or denied with reason
 */
export function checkToolAllowed(
  toolName: string,
  toolInput: Record<string, unknown> | null,
  currentGate: Gate,
  flowVariant: string = 'standard',
): GateCheckResult {
  // Tools always allowed (reading, searching, state management)
  const alwaysAllowed = [
    'Read', 'Glob', 'Grep', 'Bash', 'Agent', 'Task', 'TaskCreate',
    'TaskUpdate', 'TaskList', 'TaskGet', 'AskUserQuestion',
    'EnterPlanMode', 'ExitPlanMode', 'Skill', 'WebSearch', 'WebFetch',
    'LSP', 'ToolSearch',
  ];

  // Bash needs special handling (check command patterns)
  if (toolName === 'Bash') {
    return checkBashCommand(toolInput, currentGate, flowVariant);
  }

  // Always-allowed tools pass through
  if (alwaysAllowed.includes(toolName)) {
    return { allowed: true };
  }

  // Check direct tool-to-gate mapping
  const allowedGates = TOOL_GATE_MAP[toolName];
  if (!allowedGates) {
    // Unknown tool — permissive by default
    return { allowed: true };
  }

  // Check if current gate is in allowed list (accounting for skipped gates)
  const effectiveGates = expandGatesForVariant(allowedGates, flowVariant);
  if (effectiveGates.includes(currentGate)) {
    return { allowed: true };
  }

  return {
    allowed: false,
    reason: `[TeamX Gate Guard] Cannot use ${toolName} at gate ${currentGate}. ` +
      `Allowed gates: ${allowedGates.join(', ')}. ` +
      `Advance the state machine to the correct gate first.`,
  };
}

function checkBashCommand(
  toolInput: Record<string, unknown> | null,
  currentGate: Gate,
  flowVariant: string,
): GateCheckResult {
  if (!toolInput) return { allowed: true };

  const command = (toolInput.command as string) || '';
  if (!command) return { allowed: true };

  for (const rule of BASH_GATE_RULES) {
    if (rule.pattern.test(command)) {
      const effectiveGates = expandGatesForVariant(rule.allowedGates, flowVariant);
      if (!effectiveGates.includes(currentGate)) {
        return {
          allowed: false,
          reason: `[TeamX Gate Guard] Cannot run "${rule.description}" at gate ${currentGate}. ` +
            `Allowed gates: ${rule.allowedGates.join(', ')}. ` +
            `Advance the state machine first.`,
        };
      }
    }
  }

  return { allowed: true };
}

/**
 * Expand allowed gates to account for skipped gates in the current flow variant.
 * If an allowed gate is skipped, the tool becomes unreachable — which is intentional.
 * discovery: no git commit/push/MR/merge tools (produces a findings doc instead).
 * compressed: no PLAN gate tools.
 */
function expandGatesForVariant(gates: Gate[], flowVariant: string): Gate[] {
  const skipped = SKIP_GATES[flowVariant] ?? [];
  if (skipped.length === 0) return gates;
  // Filter out skipped gates from allowed list — tool is not usable in this variant
  return gates.filter(g => !skipped.includes(g));
}
