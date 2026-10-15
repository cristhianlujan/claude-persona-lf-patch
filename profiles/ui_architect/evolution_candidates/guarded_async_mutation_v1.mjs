// Reusable, local-only helper for async UI mutation contracts; no backend authority.
export function createGuardedMutation({ send, lookup, timeoutMs = 8000, onState = () => {} }) {
  if (typeof send !== "function" || typeof lookup !== "function" || typeof onState !== "function"
      || !Number.isFinite(timeoutMs) || timeoutMs <= 0) {
    throw new Error("INVALID_MUTATION_DEPENDENCY");
  }
  let state = { phase: "idle", operationId: null, idempotencyKey: null };
  let inFlight = false;
  const transition = (phase, operationId, idempotencyKey) => {
    state = { phase, operationId, idempotencyKey };
    onState({ ...state });
  };
  const bounded = async (factory) => {
    let timer;
    const work = Promise.resolve().then(factory).then(
      value => ({ kind: "value", value }),
      () => ({ kind: "error" }));
    const deadline = new Promise(resolve => {
      timer = setTimeout(() => resolve({ kind: "timeout" }), timeoutMs);
    });
    try { return await Promise.race([work, deadline]); }
    finally { clearTimeout(timer); }
  };
  const outcome = (reply) => {
    if (reply && reply.outcome === "APPLIED") return "applied";
    if (reply && reply.outcome === "NOT_APPLIED") return "not_applied";
    return "unknown";
  };
  const reconcile = async () => {
    if (!state.operationId || !state.idempotencyKey) return "unknown";
    const r = await bounded(() => lookup({
      operationId: state.operationId, idempotencyKey: state.idempotencyKey
    }));
    const next = r.kind === "value" ? outcome(r.value) : "unknown";
    transition(next, state.operationId, state.idempotencyKey);
    return next;
  };
  async function submit({ operationId, idempotencyKey, payload }) {
    if (inFlight) return { phase: "pending", action: "DUPLICATE_SUPPRESSED" };
    if (typeof operationId !== "string" || !operationId.trim()
        || typeof idempotencyKey !== "string" || !idempotencyKey.trim()) {
      return { phase: state.phase, action: "INVALID_IDENTITY" };
    }
    if (state.phase === "applied") return { phase: "applied", action: "ALREADY_APPLIED" };
    if (state.phase === "unknown") return { phase: "unknown", action: "RECONCILIATION_REQUIRED" };
    if (state.phase === "not_applied"
        && (operationId !== state.operationId || idempotencyKey !== state.idempotencyKey)) {
      return { phase: "not_applied", action: "IDEMPOTENCY_IDENTITY_MISMATCH" };
    }
    inFlight = true;
    transition("pending", operationId, idempotencyKey);
    try {
      const r = await bounded(() => send({ operationId, idempotencyKey, payload }));
      const phase = r.kind === "value" ? outcome(r.value) : "unknown";
      if (phase !== "unknown") {
        transition(phase, operationId, idempotencyKey);
        return { phase, action: "SERVER_CONFIRMED" };
      }
      const reconciled = await reconcile();
      return { phase: reconciled, action: reconciled === "unknown" ? "UNRESOLVED" : "RECONCILED" };
    } finally { inFlight = false; }
  }
  async function refresh() {
    if (inFlight) return { phase: state.phase, action: "BUSY" };
    if (state.phase !== "unknown") return { phase: state.phase, action: "NO_RECONCILIATION_REQUIRED" };
    inFlight = true;
    try {
      const phase = await reconcile();
      return { phase, action: phase === "unknown" ? "UNRESOLVED" : "RECONCILED" };
    } finally { inFlight = false; }
  }
  return { submit, refresh, snapshot: () => ({ ...state }) };
}