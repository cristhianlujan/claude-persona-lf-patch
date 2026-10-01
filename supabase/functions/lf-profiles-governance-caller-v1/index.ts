import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createRemoteJWKSet, jwtVerify, type JWTPayload } from "npm:jose@6.0.11";

const REPOSITORY = "cristhianlujan/claude-persona-lf-patch";
const REPOSITORY_ID = "1244397752";
const LEGACY_BRANCH = "governance/profiles-unblock-secure-caller-20260901";
const LEGACY_REF = `refs/heads/${LEGACY_BRANCH}`;
const LEGACY_WORKFLOW_NAME = "LF Profiles Governance Caller";
const LEGACY_WORKFLOW_REF = `${REPOSITORY}/.github/workflows/lf-profiles-governance-caller.yml@${LEGACY_REF}`;
const RECURATION_REF = "refs/heads/main";
const RECURATION_WORKFLOW_NAME = "LF Input Governance Recuration";
const RECURATION_WORKFLOW_REF = `${REPOSITORY}/.github/workflows/lf-input-governance-recurate.yml@${RECURATION_REF}`;
const AUDIENCE = "lf-profiles-governance-caller-v1";
const ISSUER = "https://token.actions.githubusercontent.com";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")?.trim() ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() ?? "";
const JWKS = createRemoteJWKSet(new URL(`${ISSUER}/.well-known/jwks`));

// Hosted Edge requests must respond before the 150s idle timeout. Keep 1s for caller framing.
const INPUT_GOV_RECURATION_TIMEOUT_MS = 149000;
const DEFAULT_RUNTIME_TIMEOUT_MS = 120000;

const OIDC_IDENTITIES = [
  {
    method: "GITHUB_ACTIONS_OIDC_EXACT_PROFILE_GOV_V1",
    ref: LEGACY_REF,
    workflow: LEGACY_WORKFLOW_NAME,
    workflowRef: LEGACY_WORKFLOW_REF,
    eventName: "push",
    scope: "LEGACY_PROFILE_GOVERNANCE",
  },
  {
    method: "GITHUB_ACTIONS_OIDC_INPUT_GOV_RECURATION_V1",
    ref: RECURATION_REF,
    workflow: RECURATION_WORKFLOW_NAME,
    workflowRef: RECURATION_WORKFLOW_REF,
    eventName: "workflow_dispatch",
    scope: "INPUT_GOVERNANCE_RECURATION_ONLY",
  },
] as const;

type OidcIdentity = typeof OIDC_IDENTITIES[number];

const PILOT_SCREENS = [
  { pantalla_id: 2, codigo: "ONB_002" },
  { pantalla_id: 3, codigo: "ONB_003" },
  { pantalla_id: 57, codigo: "ONB_004" },
  { pantalla_id: 5, codigo: "HOME_002" },
] as const;
const B2B_402_SCREENS = [
  { pantalla_id: 43, codigo: "B2B-CARGA-001" },
] as const;
const RECURATION_SCREEN_IDS = [1, 2, 3, 5, 43, 51, 52, 53, 54, 55, 56, 57, 58] as const;
const RECURATION_SCREEN_SET = new Set<number>(RECURATION_SCREEN_IDS);
const RECURATION_ACTION = "input_readiness_recurate_v1";

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

async function requireOidc(req: Request): Promise<{ payload: JWTPayload; identity: OidcIdentity }> {
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
  if (!payload.run_id || !payload.workflow_sha || !/^[0-9a-f]{40}$/.test(String(payload.workflow_sha))) throw new Error("OIDC_RUN_IDENTITY_INCOMPLETE");

  const identity = OIDC_IDENTITIES.find((item) =>
    payload.ref === item.ref &&
    payload.workflow_ref === item.workflowRef &&
    payload.workflow === item.workflow &&
    payload.event_name === item.eventName
  );
  if (!identity) throw new Error("OIDC_WORKFLOW_IDENTITY_MISMATCH");
  return { payload, identity };
}

async function callRuntime(
  slug: string,
  body: Record<string, unknown>,
  timeoutMs = DEFAULT_RUNTIME_TIMEOUT_MS,
): Promise<Record<string, unknown>> {
  const response = await fetch(`${SUPABASE_URL}/functions/v1/${slug}`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(timeoutMs),
  });
  const text = await response.text();
  let payload: Record<string, unknown>;
  try { payload = text ? JSON.parse(text) : {}; }
  catch { payload = { raw: text.slice(0, 1000) }; }
  if (!response.ok) throw new Error(`${slug.toUpperCase()}_${response.status}:${JSON.stringify(payload).slice(0, 1500)}`);
  return payload;
}

async function materializeScreen(
  screen: { pantalla_id: number; codigo?: string },
  consumer = "STORY_CREATOR",
  timeoutMs = DEFAULT_RUNTIME_TIMEOUT_MS,
) {
  const payload = await callRuntime("input-governance-agent-v1", {
    pantalla_id: screen.pantalla_id,
    consumer,
  }, timeoutMs);
  const result = (payload.result ?? {}) as Record<string, unknown>;
  return {
    ...screen,
    consumer,
    status: result.status ?? null,
    run_id: result.run_id ?? result.latest_run_id ?? null,
    payload,
  };
}

Deno.serve(async (req: Request) => {
  try {
    if (req.method !== "POST") return json({ outcome: "BLOCKED", code: "METHOD_NOT_ALLOWED" }, 405);
    if (!SUPABASE_URL || !SERVICE_ROLE_KEY) return json({ outcome: "BLOCKED", code: "RUNTIME_CONFIG_MISSING" }, 500);
    const { payload: claims, identity } = await requireOidc(req);
    let body: Record<string, unknown>;
    try { body = await req.json(); }
    catch { return json({ outcome: "BLOCKED", code: "INVALID_JSON" }, 400); }

    const action = typeof body.action === "string" ? body.action : "";
    const isRecurationIdentity = identity.scope === "INPUT_GOVERNANCE_RECURATION_ONLY";
    if (isRecurationIdentity && action !== RECURATION_ACTION) {
      return json({ outcome: "BLOCKED", code: "OIDC_ACTION_SCOPE_MISMATCH", allowed_action: RECURATION_ACTION }, 403);
    }
    if (!isRecurationIdentity && action === RECURATION_ACTION) {
      return json({ outcome: "BLOCKED", code: "RECURATION_CALLER_IDENTITY_REQUIRED" }, 403);
    }

    const runId = String(claims.run_id);
    const workflowSha = String(claims.workflow_sha);
    const caller = {
      method: identity.method,
      scope: identity.scope,
      repository: REPOSITORY,
      workflow_ref: identity.workflowRef,
      run_id: runId,
      workflow_sha: workflowSha,
    };

    if (action === RECURATION_ACTION) {
      if (Object.prototype.hasOwnProperty.call(body, "pantalla_ids")) {
        return json({
          outcome: "BLOCKED",
          code: "RECURATION_SINGLE_SCREEN_REQUIRED",
          caller,
          allowed_pantalla_ids: RECURATION_SCREEN_IDS,
        }, 400);
      }
      const pantallaId = typeof body.pantalla_id === "number" ? body.pantalla_id : Number.NaN;
      if (!Number.isInteger(pantallaId)) {
        return json({ outcome: "BLOCKED", code: "RECURATION_SCREEN_ID_INVALID", caller }, 400);
      }
      if (!RECURATION_SCREEN_SET.has(pantallaId)) {
        return json({
          outcome: "BLOCKED",
          code: "RECURATION_SCREEN_NOT_ALLOWED",
          caller,
          pantalla_id: pantallaId,
          allowed_pantalla_ids: RECURATION_SCREEN_IDS,
        }, 400);
      }

      const result = await materializeScreen(
        { pantalla_id: pantallaId },
        "STORY_CREATOR",
        INPUT_GOV_RECURATION_TIMEOUT_MS,
      );
      const terminal = typeof result.status === "string" && result.status.length > 0;
      if (!terminal) {
        return json({
          outcome: "BLOCKED",
          code: "INPUT_GOVERNANCE_AGENT_TERMINAL_STATUS_MISSING",
          scope: "IG_CURATOR_VALIDATOR_REFACTOR_V2_N2",
          caller,
          consumer: "STORY_CREATOR",
          pantalla_id: pantallaId,
          result,
        }, 409);
      }
      return json({
        outcome: "TERMINAL",
        scope: "IG_CURATOR_VALIDATOR_REFACTOR_V2_N2",
        caller,
        consumer: "STORY_CREATOR",
        pantalla_id: pantallaId,
        terminal_status: result.status,
        run_id: result.run_id,
        result,
      });
    }

    if (action === "input_readiness_screen_v1") {
      const codigo = typeof body.codigo === "string" ? body.codigo : "";
      const screen = PILOT_SCREENS.find((item) => item.codigo === codigo);
      if (!screen) return json({ outcome: "BLOCKED", code: "PILOT_SCREEN_NOT_ALLOWED", caller, codigo }, 400);
      const result = await materializeScreen(screen);
      const ready = result.status === "READY";
      return json({
        outcome: ready ? "READY" : "BLOCKED",
        caller,
        required_count: 1,
        ready_count: ready ? 1 : 0,
        result,
      }, ready ? 200 : 409);
    }

    if (action === "input_readiness_b2b_402_v1") {
      const codigo = typeof body.codigo === "string" ? body.codigo : "";
      const screen = B2B_402_SCREENS.find((item) => item.codigo === codigo);
      if (!screen) return json({ outcome: "BLOCKED", code: "B2B_402_SCREEN_NOT_ALLOWED", caller, codigo }, 400);
      const result = await materializeScreen(screen, "MANUAL");
      const ready = result.status === "READY";
      return json({
        outcome: ready ? "READY" : "BLOCKED",
        scope: "LF_EMPRESA_ISSUE_402",
        caller,
        required_count: 1,
        ready_count: ready ? 1 : 0,
        result,
      }, ready ? 200 : 409);
    }

    if (action === "input_readiness_pilot_v1") {
      const results: Record<string, unknown>[] = [];
      for (const screen of PILOT_SCREENS) results.push(await materializeScreen(screen));
      const readyCount = results.filter((item) => item.status === "READY").length;
      return json({
        outcome: readyCount === PILOT_SCREENS.length ? "READY" : "BLOCKED",
        caller,
        ready_count: readyCount,
        required_count: PILOT_SCREENS.length,
        results,
      }, readyCount === PILOT_SCREENS.length ? 200 : 409);
    }

    if (action === "profile_creator_init_v1") {
      const callerRequestId = typeof body.caller_request_id === "string" ? body.caller_request_id : "";
      const targetCode = typeof body.target_code === "string" ? body.target_code : "";
      const profileSlug = typeof body.profile_slug === "string" ? body.profile_slug : "";
      const result = await callRuntime("run-creacion-perfil-lf", {
        action: "initialize_profile_creation_v1",
        caller_request_id: callerRequestId,
        target_code: targetCode,
        profile_slug: profileSlug,
        target_repo: REPOSITORY,
        caller,
      });
      return json({ outcome: result.outcome ?? "BLOCKED", caller, result }, result.outcome === "INITIALIZED" ? 201 : 409);
    }

    if (action === "profile_creator_record_step_v1") {
      const executionId = typeof body.execution_id === "string" ? body.execution_id : "";
      const stepId = typeof body.step_id === "string" ? body.step_id : "";
      const evidenceRef = typeof body.evidence_ref === "string" ? body.evidence_ref : "";
      const evidencePayload = body.evidence_payload && typeof body.evidence_payload === "object"
        ? body.evidence_payload as Record<string, unknown>
        : null;
      if (!executionId || !stepId || !evidenceRef || !evidencePayload) {
        return json({ outcome: "BLOCKED", code: "PROFILE_CREATOR_STEP_INPUT_INVALID", caller }, 400);
      }
      const result = await callRuntime("run-creacion-perfil-lf", {
        action: "record_profile_creation_step_v1",
        execution_id: executionId,
        step_id: stepId,
        evidence_ref: evidenceRef,
        evidence_payload: evidencePayload,
        caller,
      });
      return json({ outcome: result.outcome ?? "BLOCKED", caller, result }, result.outcome === "STEP_RECORDED" ? 200 : 409);
    }

    return json({ outcome: "BLOCKED", code: "ACTION_NOT_ALLOWED" }, 400);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(message.replace(/Bearer\s+\S+/g, "Bearer [REDACTED]"));
    const unauthorized = message.startsWith("OIDC_");
    return json({ outcome: "BLOCKED", code: message.slice(0, 1000) }, unauthorized ? 401 : 409);
  }
});
