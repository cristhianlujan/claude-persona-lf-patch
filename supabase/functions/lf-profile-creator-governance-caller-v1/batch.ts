export type ProfileOperationStepEvidence = {
  step_id: string;
  evidence_ref: string;
  evidence_payload: Record<string, unknown>;
};

export type BatchValidation =
  | { ok: true; steps: ProfileOperationStepEvidence[] }
  | { ok: false; code: string };

const STEP_ID_RE = /^[a-z0-9_]{2,80}$/;
// Transport safety bound only. Business step counts come from live operation contracts.
const MAX_SAFE_TRANSPORT_STEPS = 64;

export function validateProfileOperationBatch(value: unknown): BatchValidation {
  if (!Array.isArray(value) || value.length === 0) {
    return { ok: false, code: "PROFILE_OPERATION_BATCH_EMPTY" };
  }
  if (value.length > MAX_SAFE_TRANSPORT_STEPS) {
    return { ok: false, code: "PROFILE_OPERATION_BATCH_TRANSPORT_LIMIT" };
  }

  const seen = new Set<string>();
  const steps: ProfileOperationStepEvidence[] = [];
  for (const raw of value) {
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
      return { ok: false, code: "PROFILE_OPERATION_BATCH_STEP_INVALID" };
    }
    const item = raw as Record<string, unknown>;
    const stepId = typeof item.step_id === "string" ? item.step_id.trim() : "";
    const evidenceRef = typeof item.evidence_ref === "string" ? item.evidence_ref.trim() : "";
    const evidencePayload = item.evidence_payload && typeof item.evidence_payload === "object" && !Array.isArray(item.evidence_payload)
      ? item.evidence_payload as Record<string, unknown>
      : null;
    if (!STEP_ID_RE.test(stepId) || !evidenceRef || !evidencePayload) {
      return { ok: false, code: "PROFILE_OPERATION_BATCH_STEP_INVALID" };
    }
    if (seen.has(stepId)) {
      return { ok: false, code: "PROFILE_OPERATION_BATCH_DUPLICATE_STEP" };
    }
    seen.add(stepId);
    steps.push({ step_id: stepId, evidence_ref: evidenceRef, evidence_payload: evidencePayload });
  }
  return { ok: true, steps };
}

export function batchOutcome(recorded: number, total: number, blockedStepId?: string) {
  if (recorded === total) {
    return { outcome: "BATCH_RECORDED", recorded_count: recorded, requested_count: total, blocked_step_id: null };
  }
  return { outcome: "BATCH_BLOCKED", recorded_count: recorded, requested_count: total, blocked_step_id: blockedStepId ?? null };
}
