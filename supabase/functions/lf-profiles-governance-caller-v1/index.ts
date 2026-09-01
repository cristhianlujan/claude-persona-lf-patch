import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createRemoteJWKSet, jwtVerify, type JWTPayload } from "npm:jose@6.0.11";

const REPOSITORY = "cristhianlujan/claude-persona-lf-patch";
const REPOSITORY_ID = "1244397752";
const BRANCH = "governance/profiles-unblock-secure-caller-20260901";
const REF = `refs/heads/${BRANCH}`;
const WORKFLOW_NAME = "LF Profiles Governance Caller";
const WORKFLOW_REF = `${REPOSITORY}/.github/workflows/lf-profiles-governance-caller.yml@${REF}`;
const AUDIENCE = "lf-profiles-governance-caller-v1";
const ISSUER = "https://token.actions.githubusercontent.com";
const CALLER_METHOD = "GITHUB_ACTIONS_OIDC_EXACT_PROFILE_GOV_V1";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")?.trim() ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() ?? "";
const JWKS = createRemoteJWKSet(new URL(`${ISSUER}/.well-known/jwks`));
const PILOT_SCREENS = [
  { pantalla_id: 2, codigo: "ONB_002" },
  { pantalla_id: 3, codigo: "ONB_003" },
  { pantalla_id: 57, codigo: "ONB_004" },
  { pantalla_id: 5, codigo: "HOME_002" },
] as const;
const B2B_402_SCREENS = [
  { pantalla_id: 43, codigo: "B2B-CARGA-001" },
] as const;

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
  if (payload.event_name !== "push") throw new Error("OIDC_EVENT_MISMATCH");
  if (!payload.run_id || !payload.workflow_sha || !/^[0-9a-f]{40}$/.test(String(payload.workflow_sha))) throw new Error("OIDC_RUN_IDENTITY_INCOMPLETE");
  return payload;
}

async function callRuntime(slug: string, body: Record<string, unknown>): Promise<Record<string, unknown>> {
  const response = await fetch(`${SUPABASE_URL}/functions/v1/${slug}`, {
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
  if (!response.ok) throw new Error(`${slug.toUpperCase()}_${response.status}:${JSON.stringify(payload).slice(0, 1500)}`);
  return payload;
}

async function materializeScreen(
  screen: { pantalla_id: number; codigo: string },
  consumer = "STORY_CREATOR",
) {
  const payload = await callRuntime("input-governance-agent-v1", {
    pantalla_id: screen.pantalla_id,
    consumer,
  });
  const result = (payload.result ?? {}) as Record<string, unknown>;
  return { ...screen, consumer, status: result.status ?? null, run_id: result.run_id ?? result.latest_run_id ?? null, payload };
}

Deno.serve(async (req: Request) => {
  try {
    if (req.method !== "POST") return json({ outcome: "BLOCKED", code: "METHOD_NOT_ALLOWED" }, 405);
    if (!SUPABASE_URL || !SERVICE_ROLE_KEY) return json({ outcome: "BLOCKED", code: "RUNTIME_CONFIG_MISSING" }, 500);
    const claims = await requireOidc(req);
    let body: Record<string, unknown>;
    try { body = await req.json(); }
    catch { return json({ outcome: "BLOCKED", code: "INVALID_JSON" }, 400); }

    const runId = String(claims.run_id);
    const workflowSha = String(claims.workflow_sha);
    const caller = {
      method: CALLER_METHOD,
      repository: REPOSITORY,
      workflow_ref: WORKFLOW_REF,
      run_id: runId,
      workflow_sha: workflowSha,
    };

    if (body.action === "input_readiness_screen_v1") {
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

    if (body.action === "input_readiness_b2b_402_v1") {
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

    if (body.action === "input_readiness_pilot_v1") {
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

    if (body.action === "profile_creator_init_v1") {
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

    return json({ outcome: "BLOCKED", code: "ACTION_NOT_ALLOWED" }, 400);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(message.replace(/Bearer\s+\S+/g, "Bearer [REDACTED]"));
    const unauthorized = message.startsWith("OIDC_");
    return json({ outcome: "BLOCKED", code: message.slice(0, 1000) }, unauthorized ? 401 : 409);
  }
});
