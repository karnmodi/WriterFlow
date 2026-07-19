/** Canonical operation state machine — Docs/contracts/inference-stream.md. */
export const OPERATION_STATES = [
  "reserved",
  "running",
  "streaming",
  "completed",
  "failed",
  "cancelled"
] as const;
export type OperationState = (typeof OPERATION_STATES)[number];

export const TERMINAL_OPERATION_STATES: readonly OperationState[] = [
  "completed",
  "failed",
  "cancelled"
];

export function isTerminalState(state: OperationState): boolean {
  return TERMINAL_OPERATION_STATES.includes(state);
}

/** Valid transitions — used to reject an invalid state write at the DB boundary. */
export const OPERATION_STATE_TRANSITIONS: Readonly<Record<OperationState, readonly OperationState[]>> = {
  reserved: ["running", "failed", "cancelled"],
  running: ["streaming", "completed", "failed", "cancelled"],
  streaming: ["completed", "failed", "cancelled"],
  completed: [],
  failed: [],
  cancelled: []
};
