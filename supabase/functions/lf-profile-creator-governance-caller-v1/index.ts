import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createRemoteJWKSet, jwtVerify, type JWTPayload } from "npm:jose@6.0.11";

const REPOSITORY = "cristhianlujan/claude-persona-lf-patch";
const REPOSITORY_ID = "1244397752";
const BRANCH = "lf/profiles/profile-creator-customer-caller-20260902";
const REF = `refs/heads/${BRANCH}`;
const WORKFLOW_NAME = "LF Customer Profile Creator Governance Caller";
const WORKFLOW_REF = `${REPOSITORY}/.github/workflows/lf-customer-profile-creator-governance-caller.yml@${REF}`;
const AUDIENCE = "lf-profile-creator-governance-caller-v1";
const ISSUER = "https://token.actions.githubusercontent.com";
const CALLER_METHOD = "GITHUB_ACTIONS_OIDC_EXACT_PROFILE_CREATOR_CUSTOMER_V1";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")?.trim() ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() ?? "";
const JWKS = createRemoteJWKSet(new URL(`${ISSUER}/.well-known/jwks`));

const TARGETS: Record<string, string> = {
  CUSTOMER_FINANCIAL_UX_DECISIONING: "customer_financial_ux_decisioning",
  CUSTOMER_TRUST_CLARITY_VULNERABILITY: "customer_trust_clarity_vulnerability",
  CUSTOMER_PAYMENTS_RECOVERY: "customer_payments_recovery",
  CUSTOMER_IDENTITY_CONSENT_PRIVACY: "customer_identity_consent_privacy",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
    },
  });
}

async function requireOidc(req: Request): Promise<JWTPayload> {
  const authorization = req.headers.get("authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) throw new Error("OIDC_BEARER_MISSING");
  const token = authorization.slice(7).trim();
  if (!token) throw new Error("OIDC_BEARER_EMPTY");
  let payload: JWTPayload;
  try {
    ({ payload } = await jwtVerify(token, JWKS, {
      issuer: ISSUER,
      audience: AUDIENCE,
      algorithms: ["RS256"],
    }));
  } catch {
    throw new Error("OIDC_TOKEN_INVALID");
  }
  if (payload.repository !== REPOSITORY || String(payload.repository_id ?? "") !== REPOSITORY_ID) throw new Error("OIDC_REPOSITORY_MISMATCH");
  if (payload.ref !== REF) throw new Error("OIDC_REF_MISMATCH");
  if (payload.workflow_ref !== WORKFLOW_REF || payload.workflow !== WORKFLOW_NAME) throw new Error("OIDC_WORKFLOW_MISMATCH");
  if (!new Set(["push", "workflow_dispatch"]).has(String(payload.event_name ?? ""))) throw new Error("OIDC_EVENT_MISMATCH");
  if (!payload.run_id || !payload.workflow_sha || !/^[0-9a-f]{40}$/.test(String(payload.workflow_sha))) throw new Error("OIDC_RUN_IDENTITY_INCOMPLETE");
  return payload;
}

async function callRuntime(body: Record<string, unknown>): Promise<Record<string, unknown>> {
  const response = await fetch(`${SUPABASE_URL}/functions/v1/run-creacion-perfil-lf`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(120000),
  });
  const text = await response.text();
  let payload: Record<string, unknown>;
  try { payload = text ? JSON.parse(text) : {}; }
  catch { payload = { raw: text.slice(0, 1000) }; }
  if (!response.ok) throw new Error(`RUN_CREACION_PERFIL_LF_${response.status}:${JSON.stringify(payload).slice(0, 1500)}`);
  return payload;
}

Deno.serve(async (req: Request) => {
  try {
    if (req.method !== "POST") return json({ outcome: "BLOCKED", code: "METHOD_NOT_ALLOWED" }, 405);
    if (!SUPABASE_URL || !SERVICE_ROLE_KEY) return json({ outcome: "BLOCKED", code: "RUNTIME_CONFIG_MISSING" }, 500);
    const claims = await requireOidc(req);
    let body: Record<string, unknown>;
    try { body = await req.json(); }
    catch { return json({ outcome: "BLOCKED", code: "INVALID_JSON" }, 400); }

    const caller = {
      method: CALLER_METHOD,
      repository: REPOSITORY,
      workflow_ref: WORKFLOW_REF,
      run_id: String(claims.run_id),
      workflow_sha: String(claims.workflow_sha),
      owner_lane: "LF-CUSTOMER-PROFILES",
      execution_origin: "AUTOMATION_PROFILES_CUSTOMER_V2",
    };

    if (body.action === "profile_creator_init_v1") {
      const callerRequestId = typeof body.caller_request_id === "string" ? body.caller_request_id.trim() : "";
      const targetCode = typeof body.target_code === "string" ? body.target_code.trim() : "";
      const profileSlug = typeof body.profile_slug === "string" ? body.profile_slug.trim() : "";
      if (!callerRequestId || !TARGETS[targetCode] || TARGETS[targetCode] !== profileSlug) {
        return json({ outcome: "BLOCKED", code: "CUSTOMER_PROFILE_TARGET_NOT_ALLOWED", caller }, 400);
      }
      const result = await callRuntime({
        action: "initialize_profile_creation_v1",
        caller_request_id: callerRequestId,
        target_code: targetCode,
        profile_slug: profileSlug,
        target_repo: REPOSITORY,
        caller,
      });
      return json({ outcome: result.outcome ?? "BLOCKED", caller, result }, result.outcome === "INITIALIZED" ? 201 : 409);
    }

    if (body.action === "profile_creator_record_step_v1") {
      const executionId = typeof body.execution_id === "string" ? body.execution_id.trim() : "";
      const stepId = typeof body.step_id === "string" ? body.step_id.trim() : "";
      const evidenceRef = typeof body.evidence_ref === "string" ? body.evidence_ref.trim() : "";
      const evidencePayload = body.evidence_payload && typeof body.evidence_payload === "object"
        ? body.evidence_payload as Record<string, unknown>
        : null;
      if (!executionId || !stepId || !evidenceRef || !evidencePayload) {
        return json({ outcome: "BLOCKED", code: "PROFILE_CREATOR_STEP_INPUT_INVALID", caller }, 400);
      }
      const result = await callRuntime({
        action: "record_profile_creation_step_v1",
        execution_id: executionId,
        step_id: stepId,
        evidence_ref: evidenceRef,
        evidence_payload: evidencePayload,
        caller,
      });
      return json({ outcome: result.outcome ?? "BLOCKED", caller, result }, result.outcome === "STEP_RECORDED" ? 200 : 409);
    }

    return json({ outcome: "BLOCKED", code: "ACTION_NOT_ALLOWED", caller }, 400);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(message.replace(/Bearer\s+\S+/g, "Bearer [REDACTED]"));
    return json({ outcome: "BLOCKED", code: message.slice(0, 1000) }, message.startsWith("OIDC_") ? 401 : 409);
  }
});
