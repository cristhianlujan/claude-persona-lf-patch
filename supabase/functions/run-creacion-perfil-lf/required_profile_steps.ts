/** Required-step projection matching existing Profile recorder's frozen PASS_POLICY. */
export type ProfileOperationStep = {
  step_id: string;
  required: boolean;
  execution_order: number;
};

export type ProfileRecordedStep = {
  step_id: string;
  status: string;
  evidence_payload?: unknown;
};

export function resolveProfileRequiredSteps(
  operationCode: string,
  steps: ProfileOperationStep[],
  manifest: unknown,
  recorded: ProfileRecordedStep[] = [],
): ProfileOperationStep[] {
  const legacy = steps.filter((step) => step.required);
  if (operationCode !== "ACTUALIZACION_PERFIL_LF") return legacy;
  const root = manifest && typeof manifest === "object" && !Array.isArray(manifest)
    ? manifest as Record<string, unknown> : {};
  const snapshots = root.operation_policy_snapshots;
  const passPolicy = snapshots && typeof snapshots === "object" && !Array.isArray(snapshots)
    ? (snapshots as Record<string, unknown>).PASS_POLICY : null;
  const policyPayload = passPolicy && typeof passPolicy === "object" && !Array.isArray(passPolicy)
    ? (passPolicy as Record<string, unknown>).policy_payload : null;
  const snapshot = policyPayload && typeof policyPayload === "object" && !Array.isArray(policyPayload)
    ? (policyPayload as Record<string, unknown>).required_steps : null;
  const routes = policyPayload && typeof policyPayload === "object" && !Array.isArray(policyPayload)
    ? (policyPayload as Record<string, unknown>).required_steps_by_outcome : null;
  // Only missing/NULL frozen required_steps falls back to the live catalog.
  if (snapshot == null) return legacy;
  if (!Array.isArray(snapshot) || snapshot.length === 0 ||
      !snapshot.every((item) => typeof item === "string" && item.trim().length > 0)) {
    throw new Error("FROZEN_REQUIRED_STEPS_INVALID");
  }
  const ids = new Set<string>(snapshot);
  if (ids.size !== snapshot.length ||
      snapshot.some((id) => !legacy.some((step) => step.step_id === id))) {
    throw new Error("FROZEN_REQUIRED_STEPS_INVALID");
  }
  // New conditional route support is inert unless an immutable execution
  // policy snapshot contains BOTH route lists. Never inspect today's policy
  // to reinterpret an old execution.
  if (routes != null) {
    if (!routes || typeof routes !== "object" || Array.isArray(routes)) {
      throw new Error("PROFILE_EVOLUTION_FROZEN_ROUTES_INVALID");
    }
    const configured = routes as Record<string, unknown>;
    const update = configured.UPDATE;
    const noChange = configured.NO_CHANGE;
    const valid = (items: unknown): items is string[] =>
      Array.isArray(items) && items.length > 0 &&
      items.every((id) => typeof id === "string" && ids.has(id)) &&
      new Set(items).size === items.length;
    if (!valid(update) || !valid(noChange) ||
        update.length !== snapshot.length || update.some((v, i) => snapshot[i] !== v) ||
        noChange.some((id) => !update.includes(id)) ||
        noChange.includes("github_write") ||
        noChange.includes("pre_write_execution_binding_gate") ||
        noChange.includes("post_merge_reconcile")) {
      throw new Error("PROFILE_EVOLUTION_FROZEN_ROUTES_INVALID");
    }
    const decisionIdx = update.indexOf("evolution_decision");
    const selectionIdx = update.indexOf("method_selection");
    if (selectionIdx < 0 || decisionIdx !== selectionIdx + 1 ||
        decisionIdx < 1 || update[decisionIdx + 1] !== "change_scope" ||
        noChange.slice(0, decisionIdx + 1).join("|") !==
          update.slice(0, decisionIdx + 1).join("|")) {
      throw new Error("PROFILE_EVOLUTION_FROZEN_ROUTES_INVALID");
    }
    const decision = recorded.find((row) => row.step_id === "evolution_decision");
    // Until a clean authorized judge decision is recorded, the cursor cannot
    // branch. The producer's own candidate receipt is never a pass.
    if (!decision || decision.status !== "STEP_PASS_WITH_EVIDENCE") {
      const prefix = new Set(update.slice(0, decisionIdx + 1));
      return legacy.filter((step) => prefix.has(step.step_id));
    }
    const payload = decision.evidence_payload;
    const outcome = payload && typeof payload === "object" && !Array.isArray(payload)
      ? (payload as Record<string, unknown>).decision : null;
    if (outcome !== "UPDATE" && outcome !== "NO_CHANGE") {
      throw new Error("PROFILE_EVOLUTION_ROUTE_NOT_ADMITTED");
    }
    const route = new Set(outcome === "UPDATE" ? update : noChange);
    return legacy.filter((step) => route.has(step.step_id));
  }
  return legacy.filter((step) => ids.has(step.step_id));
}
