/**
 * Gate Rules — Maps tools to allowed gates.
 *
 * This is the core enforcement logic. It defines which tools
 * can be used at which gates in the state machine.
 */
import type { Gate } from './state-reader.js';
/** Gates where it's safe to stop */
export declare const SAFE_STOP_GATES: Gate[];
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
export declare function checkToolAllowed(toolName: string, toolInput: Record<string, unknown> | null, currentGate: Gate, flowVariant?: string): GateCheckResult;
