import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createRemoteJWKSet, jwtVerify, type JWTPayload } from "npm:jose@6.0.11";
import { batchOutcome, validateProfileOperationBatch } from "./batch.ts";

const REPOSITORY = "cristhianlujan/claude-persona-lf-patch";
const REPOSITORY_ID = "1244397752";
const CUSTOMER_BRANCH = "lf/profiles/profile-creator-customer-caller-20260902";
const CUSTOMER_REF = `refs/heads/${CUSTOMER_BRANCH}`;
const WORKFLOW_NAME = "LF Customer Profile Creator Governance Caller";
const WORKFLOW_PATH = ".github/workflows/lf-customer-profile-creator-governance-caller.yml";
const CUSTOMER_WORKFLOW_REF = `${REPOSITORY}/${WORKFLOW_PATH}@${CUSTOMER_REF}`;
const AUDIENCE = "lf-profile-creator-governance-caller-v1";
const ISSUER = "https://token.actions.githubusercontent.com";
const CUSTOMER_CALLER_METHOD = "GITHUB_ACTIONS_OIDC_EXACT_PROFILE_CREATOR_CUSTOMER_V1";
const PROJECT_ID = "AGENTE_PROFILE_CREATOR";
const OWNER_LANE = "CUSTOMER_PROFILES";
const EXECUTION_ORIGIN = "AUTOMATION_PROFILE_CREATOR_DUAL_EXECUTOR";
const WORKSTREAM_ID = "PROFILE_CREATOR_INFRA";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")?.trim() ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() ?? "";
const JWKS = createRemoteJWKSet(new URL(`${ISSUER}/.well-known/jwks`));
const UPDATE_OPERATION = "ACTUALIZACION_PERFIL_LF";

const TARGETS: Record<string, string> = {
  "PERFIL-CUSTOMER-FINANCIAL-UX-DECISIONING": "customer_financial_ux_decisioning",
  "PERFIL-CUSTOMER-TRUST-CLARITY-VULNERABILITY": "customer_trust_clarity_vulnerability",
  "PERFIL-CUSTOMER-PAYMENTS-RECOVERY": "customer_payments_recovery",
  "PERFIL-CUSTOMER-IDENTITY-CONSENT-PRIVACY": "customer_identity_consent_privacy",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", "x-content-type-options": "nosniff" } });
}

async function requireOidc(req: Request): Promise<{ payload: JWTPayload; method: string; workflowRef: string }> {
  const authorization = req.headers.get("authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) throw new Error("OIDC_BEARER_MISSING");
  const token = authorization.slice(7).trim();
  if (!token) throw new Error("OIDC_BEARER_EMPTY");
  let payload: JWTPayload;
  try { ({ payload } = await jwtVerify(token, JWKS, { issuer: ISSUER, audience: AUDIENCE, algorithms: ["RS256"] })); }
  catch { throw new Error("OIDC_TOKEN_INVALID"); }
  if (payload.repository !== REPOSITORY || String(payload.repository_id ?? "") !== REPOSITORY_ID) throw new Error("OIDC_REPOSITORY_MISMATCH");
  if (payload.workflow !== WORKFLOW_NAME) throw new Error("OIDC_WORKFLOW_MISMATCH");
  const ref = String(payload.ref ?? "");
  const workflowRef = String(payload.workflow_ref ?? "");
  const eventName = String(payload.event_name ?? "");
  let method = "";
  if (ref === CUSTOMER_REF && workflowRef === CUSTOMER_WORKFLOW_REF && new Set(["push", "workflow_dispatch"]).has(eventName)) {
    method = CUSTOMER_CALLER_METHOD;
  } else {
    // Profile update (ACTUALIZACION_PERFIL_LF) is retired from this OIDC route: it only enters through a profile + skill.
    if (ref !== CUSTOMER_REF) throw new Error("OIDC_REF_MISMATCH");
    throw new Error("OIDC_WORKFLOW_MISMATCH");
  }
  if (!payload.run_id || !payload.workflow_sha || !/^[0-9a-f]{40}$/.test(String(payload.workflow_sha))) throw new Error("OIDC_RUN_IDENTITY_INCOMPLETE");
  return { payload, method, workflowRef };
}

async function callRuntime(body: Record<string, unknown>): Promise<Record<string, any>> {
  const response = await fetch(`${SUPABASE_URL}/functions/v1/run-creacion-perfil-lf`, {
    method: "POST",
    headers: { authorization: `Bearer ${SERVICE_ROLE_KEY}`, "content-type": "application/json" },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(120000),
  });
  const text = await response.text();
  let payload: Record<string, any>;
  try { payload = text ? JSON.parse(text) : {}; } catch { payload = { raw: text.slice(0, 1000) }; }
  if (!response.ok) throw new Error(`PROFILE_OPERATION_RUNTIME_${response.status}:${JSON.stringify(payload).slice(0, 1500)}`);
  return payload;
}

function rejectUpdateOperation(current: Record<string, any>, caller: Record<string, unknown>): Response | null {
  if (current?.snapshot?.operation_code === UPDATE_OPERATION) {
    return json({ outcome: "BLOCKED", code: "PROFILE_UPDATE_RETIRED_FROM_OIDC_ROUTE", detail: "ACTUALIZACION_PERFIL_LF enters only through a profile and its governed skill, not through this caller", caller }, 403);
  }
  return null;
}

Deno.serve(async (req: Request) => {
  try {
    if (req.method !== "POST") return json({ outcome: "BLOCKED", code: "METHOD_NOT_ALLOWED" }, 405);
    if (!SUPABASE_URL || !SERVICE_ROLE_KEY) return json({ outcome: "BLOCKED", code: "RUNTIME_CONFIG_MISSING" }, 500);
    const identity = await requireOidc(req);
    const claims = identity.payload;
    let body: Record<string, unknown>;
    try { body = await req.json(); } catch { return json({ outcome: "BLOCKED", code: "INVALID_JSON" }, 400); }
    const caller = { method: identity.method, repository: REPOSITORY, workflow_ref: identity.workflowRef, run_id: String(claims.run_id), workflow_sha: String(claims.workflow_sha), project_id: PROJECT_ID, owner_lane: OWNER_LANE, execution_origin: EXECUTION_ORIGIN, workstream_id: WORKSTREAM_ID };

    if (body.action === "profile_creator_init_v1") {
      if (caller.method !== CUSTOMER_CALLER_METHOD) return json({ outcome: "BLOCKED", code: "PROFILE_CREATE_CALLER_NOT_ALLOWED", caller }, 403);
      const callerRequestId = typeof body.caller_request_id === "string" ? body.caller_request_id.trim() : "";
      const targetCode = typeof body.target_code === "string" ? body.target_code.trim() : "";
      const profileSlug = typeof body.profile_slug === "string" ? body.profile_slug.trim() : "";
      if (!callerRequestId || !TARGETS[targetCode] || TARGETS[targetCode] !== profileSlug) return json({ outcome: "BLOCKED", code: "CUSTOMER_PROFILE_TARGET_NOT_ALLOWED", caller }, 400);
      const result = await callRuntime({ action: "initialize_profile_creation_v1", caller_request_id: callerRequestId, target_code: targetCode, profile_slug: profileSlug, target_repo: REPOSITORY, caller });
      return json({ outcome: result.outcome ?? "BLOCKED", caller, result }, result.outcome === "INITIALIZED" ? 201 : 409);
    }

    if (body.action === "profile_operation_next_step_v1") {
      const executionId = typeof body.execution_id === "string" ? body.execution_id.trim() : "";
      if (!executionId) return json({ outcome: "BLOCKED", code: "PROFILE_OPERATION_EXECUTION_ID_INVALID", caller }, 400);
      const result = await callRuntime({ action: "next_profile_operation_step_v1", execution_id: executionId, caller });
      const retired = rejectUpdateOperation(result, caller);
      if (retired) return retired;
      return json({ outcome: result.outcome ?? "BLOCKED", caller, result }, 200);
    }

    if (body.action === "profile_creator_record_step_v1" || body.action === "profile_operation_record_step_v1") {
      const executionId = typeof body.execution_id === "string" ? body.execution_id.trim() : "";
      const stepId = typeof body.step_id === "string" ? body.step_id.trim() : "";
      const evidenceRef = typeof body.evidence_ref === "string" ? body.evidence_ref.trim() : "";
      const evidencePayload = body.evidence_payload && typeof body.evidence_payload === "object" && !Array.isArray(body.evidence_payload) ? body.evidence_payload as Record<string, unknown> : null;
      if (!executionId || !stepId || !evidenceRef || !evidencePayload) return json({ outcome: "BLOCKED", code: "PROFILE_OPERATION_STEP_INPUT_INVALID", caller }, 400);
      const current = await callRuntime({ action: "next_profile_operation_step_v1", execution_id: executionId, caller });
      const retired = rejectUpdateOperation(current, caller);
      if (retired) return retired;
      const expectedStepId = current?.snapshot?.next_step?.step_id ?? null;
      if (expectedStepId !== stepId) return json({ outcome: "BLOCKED", code: "PROFILE_OPERATION_STEP_NOT_CURRENT", expected_step_id: expectedStepId, requested_step_id: stepId, caller }, 409);
      const result = await callRuntime({ action: "record_profile_operation_step_v1", execution_id: executionId, step_id: stepId, evidence_ref: evidenceRef, evidence_payload: evidencePayload, caller });
      return json({ outcome: result.outcome ?? "BLOCKED", caller, result }, result.outcome === "STEP_RECORDED" ? 200 : 409);
    }

    if (body.action === "profile_creator_record_batch_v1" || body.action === "profile_operation_record_batch_v1") {
      const executionId = typeof body.execution_id === "string" ? body.execution_id.trim() : "";
      const validation = validateProfileOperationBatch(body.steps);
      if (!executionId) return json({ outcome: "BLOCKED", code: "PROFILE_OPERATION_BATCH_EXECUTION_ID_INVALID", caller }, 400);
      if (!validation.ok) return json({ outcome: "BLOCKED", code: validation.code, caller }, 400);
      const receipts: Record<string, unknown>[] = [];
      for (const step of validation.steps) {
        const current = await callRuntime({ action: "next_profile_operation_step_v1", execution_id: executionId, caller });
        const retired = rejectUpdateOperation(current, caller);
        if (retired) return retired;
        const expectedStepId = current?.snapshot?.next_step?.step_id ?? null;
        if (expectedStepId !== step.step_id) return json({ ...batchOutcome(receipts.length, validation.steps.length, step.step_id), code: "PROFILE_OPERATION_BATCH_STEP_NOT_CURRENT", expected_step_id: expectedStepId, caller, execution_id: executionId, receipts }, 409);
        const result = await callRuntime({ action: "record_profile_operation_step_v1", execution_id: executionId, step_id: step.step_id, evidence_ref: step.evidence_ref, evidence_payload: step.evidence_payload, caller });
        receipts.push({ step_id: step.step_id, outcome: result.outcome ?? "BLOCKED", operation_code: result.operation_code ?? current?.snapshot?.operation_code ?? null, result });
        if (result.outcome !== "STEP_RECORDED") return json({ ...batchOutcome(receipts.length - 1, validation.steps.length, step.step_id), caller, execution_id: executionId, receipts }, 409);
      }
      return json({ ...batchOutcome(receipts.length, validation.steps.length), caller, execution_id: executionId, receipts }, 200);
    }

    return json({ outcome: "BLOCKED", code: "ACTION_NOT_ALLOWED", caller }, 400);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(message.replace(/Bearer\s+\S+/g, "Bearer [REDACTED]"));
    return json({ outcome: "BLOCKED", code: message.slice(0, 1000) }, message.startsWith("OIDC_") ? 401 : 409);
  }
});
