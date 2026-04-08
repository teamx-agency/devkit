/**
 * TeamX State Reader
 *
 * Reads .teamx/state.json from disk. Every hook uses this.
 * This module is READ-ONLY — it never writes to state.json.
 */
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
    verification: Record<string, {
        status: string;
        output?: string;
    }>;
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
    overall_progress: {
        done: number;
        total: number;
    };
    last_sync: string | null;
    handoff: unknown | null;
}
export type Gate = 'IDLE' | 'INIT' | 'SELECT' | 'CLASSIFY' | 'PLAN' | 'IMPLEMENT' | 'VERIFY' | 'COMMIT' | 'PUSH' | 'MR' | 'PIPELINE' | 'REVIEW' | 'MERGE' | 'EVIDENCE' | 'RETROSPECTIVE';
export declare function findStateFile(cwd: string): string | null;
export declare function readState(cwd: string): TeamXState | null;
export declare function readGate(cwd: string): Gate;
export declare function isGate(value: string): value is Gate;
/**
 * Build a compact state summary for context injection.
 * Mirrors read_state_summary() from state.sh.
 */
export declare function buildStateSummary(state: TeamXState): string;
