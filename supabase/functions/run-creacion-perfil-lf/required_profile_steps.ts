/** Required-step projection matching existing Profile recorder's frozen PASS_POLICY. */
export type ProfileOperationStep = {
  step_id: string;
  required: boolean;
  execution_order: number;
};

export function resolveProfileRequiredSteps(
  operationCode: string,
  steps: ProfileOperationStep[],
  manifest: unknown,
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
  return legacy.filter((step) => ids.has(step.step_id));
}
