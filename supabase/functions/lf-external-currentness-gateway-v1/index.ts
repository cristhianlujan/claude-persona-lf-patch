import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createRemoteJWKSet, jwtVerify, type JWTPayload } from "npm:jose@6.0.11";
import {
  AUDIENCE,
  REPOSITORY,
  validateGatewayClaims,
  requireObservedMainMatchesWorkflow,
  requireEdgeReadCredential,
  type GatewayIdentity,
} from "./auth.ts";

const PROJECT_REF = "mhwmirqcgxxukpctffuv";
const ISSUER = "https://token.actions.githubusercontent.com";
const GITHUB_API = "https://api.github.com";
const MANAGEMENT_API = "https://api.supabase.com";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")?.trim() ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() ?? "";
const EDGE_READ_PAT = Deno.env.get("LF_SUPABASE_EDGE_FUNCTIONS_READ_PAT")?.trim() ?? "";
const JWKS = createRemoteJWKSet(new URL(`${ISSUER}/.well-known/jwks`));
const TIMEOUT_MS = 20000;

class GatewayError extends Error {
  status: number;
  constructor(code: string, status = 409) {
    super(code);
    this.status = status;
  }
}

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

function asObject(value: unknown): Record<string, unknown> {
  if (value && typeof value === "object" && !Array.isArray(value)) return value as Record<string, unknown>;
  if (Array.isArray(value) && value.length === 1 && value[0] && typeof value[0] === "object") {
    return value[0] as Record<string, unknown>;
  }
  throw new GatewayError("DB_RPC_RESPONSE_INVALID", 502);
}

async function requireOidc(req: Request): Promise<{ payload: JWTPayload; identity: GatewayIdentity }> {
  const authorization = req.headers.get("authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) throw new GatewayError("OIDC_BEARER_MISSING", 401);
  const token = authorization.slice(7).trim();
  if (!token) throw new GatewayError("OIDC_BEARER_EMPTY", 401);

  let payload: JWTPayload;
  try {
    ({ payload } = await jwtVerify(token, JWKS, {
      issuer: ISSUER,
      audience: AUDIENCE,
      algorithms: ["RS256"],
    }));
  } catch {
    throw new GatewayError("OIDC_TOKEN_INVALID", 401);
  }

  try {
    return { payload, identity: validateGatewayClaims(payload as Record<string, unknown>) };
  } catch (error) {
    const code = error instanceof Error ? error.message : String(error);
    throw new GatewayError(code, 401);
  }
}

async function inventoryRpc(name: string, args: Record<string, unknown>): Promise<unknown> {
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY) throw new GatewayError("RUNTIME_CONFIG_MISSING", 500);

  const response = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      apikey: SERVICE_ROLE_KEY,
      "content-type": "application/json",
    },
    body: JSON.stringify(args),
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  const text = await response.text();
  let payload: unknown;
  try { payload = text ? JSON.parse(text) : null; }
  catch { payload = { message: text.slice(0, 1200) }; }

  if (!response.ok) {
    const message = payload && typeof payload === "object" && !Array.isArray(payload)
      ? String((payload as Record<string, unknown>).message ?? "")
      : "";
    if (/^(REPORT_|OBSERVATION_)/.test(message)) throw new GatewayError(message, 409);
    throw new GatewayError(`DB_RPC_FAILED:${name}:${response.status}`, 502);
  }
  return payload;
}

async function listEdgeRuntime(): Promise<Record<string, unknown>[]> {
  let token: string;
  try { token = requireEdgeReadCredential(EDGE_READ_PAT); }
  catch { throw new GatewayError("EDGE_READ_CREDENTIAL_MISSING", 503); }

  const response = await fetch(`${MANAGEMENT_API}/v1/projects/${PROJECT_REF}/functions`, {
    method: "GET",
    headers: {
      authorization: `Bearer ${token}`,
      accept: "application/json",
      "user-agent": "lf-external-currentness-gateway-v1",
    },
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });

  if (response.status === 401 || response.status === 403) {
    throw new GatewayError("EDGE_READ_CREDENTIAL_FORBIDDEN", 503);
  }
  if (!response.ok) throw new GatewayError("EDGE_RUNTIME_FETCH_FAILED", 502);

  const payload = await response.json();
  if (!Array.isArray(payload)) throw new GatewayError("EDGE_RUNTIME_FETCH_FAILED", 502);

  return payload.map((row: Record<string, unknown>) => ({
    slug: row.slug ?? null,
    version: row.version ?? null,
    ezbr_sha256: row.ezbr_sha256 ?? null,
    verify_jwt: row.verify_jwt ?? null,
  }));
}

async function githubCommitMetadata(sha: string): Promise<{ sha: string; committedAt: string }> {
  if (!/^[0-9a-f]{40}$/.test(sha)) throw new GatewayError("REPORT_MAIN_SHA_MISMATCH", 400);

  const response = await fetch(`${GITHUB_API}/repos/${REPOSITORY}/commits/${sha}`, {
    method: "GET",
    headers: {
      accept: "application/vnd.github+json",
      "x-github-api-version": "2022-11-28",
      "user-agent": "lf-external-currentness-gateway-v1",
    },
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  if (!response.ok) throw new GatewayError("GITHUB_COMMIT_METADATA_UNRESOLVED", 502);

  const payload = await response.json() as Record<string, unknown>;
  if (payload.sha !== sha) throw new GatewayError("REPORT_MAIN_SHA_MISMATCH", 400);
  const commit = payload.commit as Record<string, unknown> | undefined;
  const committer = commit?.committer as Record<string, unknown> | undefined;
  const author = commit?.author as Record<string, unknown> | undefined;
  const value = typeof committer?.date === "string"
    ? committer.date
    : typeof author?.date === "string"
      ? author.date
      : "";
  const date = new Date(value);
  if (!value || Number.isNaN(date.getTime())) throw new GatewayError("GITHUB_COMMIT_METADATA_UNRESOLVED", 502);
  return { sha, committedAt: date.toISOString() };
}

function reportObject(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new GatewayError("REPORT_SCHEMA_INVALID", 400);
  }
  return value as Record<string, unknown>;
}

function nestedString(value: Record<string, unknown>, first: string, second: string): string {
  const parent = value[first];
  if (!parent || typeof parent !== "object" || Array.isArray(parent)) return "";
  const child = (parent as Record<string, unknown>)[second];
  return typeof child === "string" ? child : "";
}

async function readSnapshot(identity: GatewayIdentity): Promise<Response> {
  const edgeRuntime = await listEdgeRuntime();
  const readModel = asObject(await inventoryRpc("lf_external_currentness_read_model_v1", {}));

  return json({
    outcome: "SNAPSHOT",
    schema_version: "LF_EXTERNAL_CURRENTNESS_GATEWAY_SNAPSHOT_V1",
    caller: identity,
    project_ref: PROJECT_REF,
    captured_at: readModel.captured_at ?? null,
    repo_inventory: readModel.repo_inventory ?? [],
    edge_inventory: readModel.edge_inventory ?? [],
    repo_inventory_sha256: readModel.repo_inventory_sha256 ?? null,
    edge_inventory_sha256: readModel.edge_inventory_sha256 ?? null,
    repo_active_count: readModel.repo_active_count ?? null,
    edge_active_count: readModel.edge_active_count ?? null,
    edge_runtime: edgeRuntime,
  });
}

async function writeObservation(body: Record<string, unknown>, identity: GatewayIdentity): Promise<Response> {
  const report = reportObject(body.report);
  const observedMainSha = typeof report.observed_main_sha === "string" ? report.observed_main_sha : "";
  requireObservedMainMatchesWorkflow(observedMainSha, identity);
  const verifiedCommit = await githubCommitMetadata(observedMainSha);

  // Get DB server time immediately before write. This timestamp, not a runner clock,
  // becomes the persisted observed_at. The fresh read-model also closes the
  // read_snapshot -> write_observation race before the writer repeats the check.
  const freshReadModel = asObject(await inventoryRpc("lf_external_currentness_read_model_v1", {}));
  const dbObservedAt = typeof freshReadModel.captured_at === "string" ? freshReadModel.captured_at : "";
  if (!dbObservedAt || Number.isNaN(new Date(dbObservedAt).getTime())) {
    throw new GatewayError("DB_SERVER_TIME_UNRESOLVED", 502);
  }

  const reportRepoSha = nestedString(report, "input_sha256", "repo_inventory");
  const reportEdgeSha = nestedString(report, "input_sha256", "edge_inventory");
  if (
    reportRepoSha !== String(freshReadModel.repo_inventory_sha256 ?? "") ||
    reportEdgeSha !== String(freshReadModel.edge_inventory_sha256 ?? "")
  ) {
    throw new GatewayError("REPORT_INPUT_STALE", 409);
  }

  const result = await inventoryRpc("lf_external_currentness_apply_observation_v1", {
    p_report: report,
    p_observed_main_committed_at: verifiedCommit.committedAt,
    p_observed_at: dbObservedAt,
  });

  return json({
    outcome: "WRITE_OBSERVATION_RESULT",
    caller: identity,
    verified_main_commit: verifiedCommit,
    observed_at_source: "DATABASE_SERVER_TIME_FROM_READ_MODEL_IMMEDIATELY_BEFORE_WRITE",
    result,
  });
}

Deno.serve(async (req: Request) => {
  try {
    if (req.method !== "POST") return json({ outcome: "BLOCKED", code: "METHOD_NOT_ALLOWED" }, 405);
    const { identity } = await requireOidc(req);

    let body: Record<string, unknown>;
    try { body = await req.json(); }
    catch { return json({ outcome: "BLOCKED", code: "INVALID_JSON" }, 400); }

    if (body.action === "read_snapshot") return await readSnapshot(identity);
    if (body.action === "write_observation") return await writeObservation(body, identity);
    return json({ outcome: "BLOCKED", code: "ACTION_NOT_ALLOWED" }, 400);
  } catch (error) {
    const code = error instanceof Error ? error.message : String(error);
    console.error(code.replace(/Bearer\s+\S+/g, "Bearer [REDACTED]"));
    const status = error instanceof GatewayError ? error.status : 409;
    return json({ outcome: "BLOCKED", code: code.slice(0, 1000) }, status);
  }
});
