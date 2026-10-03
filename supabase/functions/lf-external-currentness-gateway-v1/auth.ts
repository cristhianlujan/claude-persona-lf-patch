export const REPOSITORY = "cristhianlujan/claude-persona-lf-patch";
export const REPOSITORY_ID = "1244397752";
export const MAIN_REF = "refs/heads/main";
export const WORKFLOW_NAME = "LF External Currentness Detector";
export const WORKFLOW_PATH = ".github/workflows/lf-external-currentness-detector.yml";
export const WORKFLOW_REF = `${REPOSITORY}/${WORKFLOW_PATH}@${MAIN_REF}`;
export const AUDIENCE = "lf-external-currentness-gateway-v1";
export const ALLOWED_EVENTS = new Set(["push", "schedule", "workflow_dispatch"]);

export type Claims = Record<string, unknown>;
export type GatewayIdentity = {
  repository: string;
  ref: string;
  workflow: string;
  workflowRef: string;
  eventName: string;
  runId: string;
  workflowSha: string;
  actor: string;
};

function asString(value: unknown): string {
  return typeof value === "string" ? value : String(value ?? "");
}

export function validateGatewayClaims(payload: Claims): GatewayIdentity {
  if (payload.repository !== REPOSITORY || asString(payload.repository_id) !== REPOSITORY_ID) {
    throw new Error("OIDC_REPOSITORY_MISMATCH");
  }

  const ref = asString(payload.ref);
  if (ref !== MAIN_REF) throw new Error("OIDC_REF_MISMATCH");

  const workflow = asString(payload.workflow);
  const workflowRef = asString(payload.workflow_ref);
  const jobWorkflowRef = asString(payload.job_workflow_ref);
  if (
    workflow !== WORKFLOW_NAME ||
    workflowRef !== WORKFLOW_REF ||
    (jobWorkflowRef && jobWorkflowRef !== WORKFLOW_REF)
  ) {
    throw new Error("OIDC_WORKFLOW_IDENTITY_MISMATCH");
  }

  const eventName = asString(payload.event_name);
  if (!ALLOWED_EVENTS.has(eventName)) throw new Error("OIDC_EVENT_NOT_ALLOWED");

  const runId = asString(payload.run_id);
  const workflowSha = asString(payload.workflow_sha);
  if (!runId || !/^[0-9a-f]{40}$/.test(workflowSha)) {
    throw new Error("OIDC_RUN_IDENTITY_INCOMPLETE");
  }

  return {
    repository: REPOSITORY,
    ref,
    workflow,
    workflowRef,
    eventName,
    runId,
    workflowSha,
    actor: asString(payload.actor),
  };
}

export function requireObservedMainMatchesWorkflow(
  observedMainSha: string,
  identity: GatewayIdentity,
): string {
  if (observedMainSha !== identity.workflowSha) {
    throw new Error("REPORT_MAIN_SHA_MISMATCH");
  }
  return observedMainSha;
}

export function requireEdgeReadCredential(value: string): string {
  const token = value.trim();
  if (!token) throw new Error("EDGE_READ_CREDENTIAL_MISSING");
  return token;
}

export function baselineApprovalArgs(
  identity: GatewayIdentity,
  body: Record<string, unknown>,
): {
  p_sync_key: string;
  p_actor: string;
  p_github_run_id: number;
  p_workflow_sha: string;
} {
  if (identity.eventName !== "workflow_dispatch") {
    throw new Error("BASELINE_APPROVAL_EVENT_REQUIRED");
  }
  const syncKey = asString(body.approve_sync_key).trim();
  if (!/^[0-9a-f]{64}$/.test(syncKey)) {
    throw new Error("BASELINE_APPROVAL_SYNC_KEY_INVALID");
  }
  if (!identity.actor) throw new Error("BASELINE_APPROVAL_ACTOR_MISSING");
  if (!/^\d+$/.test(identity.runId)) throw new Error("BASELINE_APPROVAL_RUN_ID_INVALID");
  const runId = Number(identity.runId);
  if (!Number.isSafeInteger(runId) || runId <= 0) {
    throw new Error("BASELINE_APPROVAL_RUN_ID_INVALID");
  }
  // Intentionally ignore body.actor/body.run_id/body.workflow_sha. Approval identity
  // is derived only from verified GitHub OIDC claims.
  return {
    p_sync_key: syncKey,
    p_actor: identity.actor,
    p_github_run_id: runId,
    p_workflow_sha: identity.workflowSha,
  };
}
