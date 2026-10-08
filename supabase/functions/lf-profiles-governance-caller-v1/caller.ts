export const OIDC_ISSUER = "https://token.actions.githubusercontent.com";
export const OIDC_AUDIENCE = "lf-profiles-governance-caller-v1";

const LEGACY_BRANCH = "governance/profiles-unblock-secure-caller-20260901";
const LEGACY_REF = `refs/heads/${LEGACY_BRANCH}`;
const LEGACY_WORKFLOW_NAME = "LF Profiles Governance Caller";
const LEGACY_WORKFLOW_FILE = "lf-profiles-governance-caller.yml";
const RECURATION_ACTION = "input_readiness_recurate_v1";
const PILOT_ACTION = "input_readiness_pilot_v1";
const SCREEN_ACTION = "input_readiness_screen_v1";
const B2B_ACTION = "input_readiness_b2b_402_v1";
const PROFILE_INIT_ACTION = "profile_creator_init_v1";
const PROFILE_STEP_ACTION = "profile_creator_record_step_v1";
const STORY_CREATOR_CONSUMER = "STORY_CREATOR";
const MANUAL_CONSUMER = "MANUAL";
const ALLOWLIST_RPC = "lf_input_gov_recuration_allowlist_v1";
const ALLOWLIST_SCHEMA_VERSION = "lf-input-gov-recuration-allowlist/v1";
const ALLOWLIST_RULE_ID = 661;
const ALLOWLIST_CONTRACT_VERSION = "1.0.0";
const ALLOWLIST_CALLER_USAGE = "ALLOWLIST_FOR_GOVERNED_RECURATION";

const PILOT_SCREENS = [
  { pantalla_id: 2, codigo: "ONB_002" },
  { pantalla_id: 3, codigo: "ONB_003" },
  { pantalla_id: 57, codigo: "ONB_004" },
  { pantalla_id: 5, codigo: "HOME_002" },
] as const;
const B2B_402_SCREENS = [
  { pantalla_id: 43, codigo: "B2B-CARGA-001" },
] as const;

export type JwtPayload = Record<string, unknown>;
export type EnvGetter = (name: string) => string | undefined;
export type FetchLike = (input: string | URL | Request, init?: RequestInit) => Promise<Response>;
export type JwtVerifyLike = (
  token: string,
  jwks: unknown,
  options: { issuer: string; audience: string; algorithms: string[] },
) => Promise<{ payload: JwtPayload }>;

export type CallerConfig = {
  supabaseUrl: string;
  serviceRoleKey: string;
  repository: string;
  repositoryId: string;
  recurationRef: string;
  recurationWorkflowRef: string;
  recurationDispatchWorkflowRef: string;
  recurationWorkflowName: string;
  inputGovernanceSlug: string;
  profileCreatorSlug: string;
  recurationTimeoutMs: number;
  defaultTimeoutMs: number;
};

type OidcIdentity = {
  method: string;
  ref: string;
  workflowRef: string;
  scope: "LEGACY_PROFILE_GOVERNANCE" | "INPUT_GOVERNANCE_RECURATION_ONLY";
};

type RuntimeDeps = {
  getEnv: EnvGetter;
  fetchFn: FetchLike;
  jwtVerifyFn: JwtVerifyLike;
  jwks: unknown;
};

type RecurationAuthority = {
  ruleId: number;
  observedAt: string;
  screenIds: number[];
};

class CallerFault extends Error {
  constructor(
    public readonly code: string,
    public readonly status: number,
    public readonly details: Record<string, unknown> = {},
  ) {
    super(code);
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

function requiredEnv(getEnv: EnvGetter, name: string): string {
  const value = getEnv(name)?.trim() ?? "";
  if (!value) throw new CallerFault(`CONFIG_${name}_MISSING`, 500);
  return value;
}

function validRepository(value: string): boolean {
  return /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(value);
}

function validHeadRef(value: string): boolean {
  if (!value.startsWith("refs/heads/")) return false;
  const branch = value.slice("refs/heads/".length);
  return branch.length > 0 && !branch.includes("..") && !branch.includes("//") && /^[A-Za-z0-9._\/-]+$/.test(branch);
}

function validWorkflowRef(value: string, repository: string, ref: string): boolean {
  const prefix = `${repository}/.github/workflows/`;
  if (!value.startsWith(prefix) || !value.endsWith(`@${ref}`)) return false;
  const file = value.slice(prefix.length, value.length - (`@${ref}`).length);
  return /^[A-Za-z0-9._-]+\.ya?ml$/.test(file);
}

function validSlug(value: string): boolean {
  return /^[a-z0-9][a-z0-9-]{0,62}$/.test(value);
}

function parseTimeout(raw: string, name: string, max: number): number {
  if (!/^\d+$/.test(raw)) throw new CallerFault(`CONFIG_${name}_INVALID`, 500);
  const value = Number(raw);
  if (!Number.isInteger(value) || value < 1 || value > max) {
    throw new CallerFault(`CONFIG_${name}_INVALID`, 500);
  }
  return value;
}

export function loadConfig(getEnv: EnvGetter): CallerConfig {
  const supabaseUrl = requiredEnv(getEnv, "SUPABASE_URL");
  const serviceRoleKey = requiredEnv(getEnv, "SUPABASE_SERVICE_ROLE_KEY");
  const repository = requiredEnv(getEnv, "LF_CALLER_REPOSITORY");
  const repositoryId = requiredEnv(getEnv, "LF_CALLER_REPOSITORY_ID");
  const recurationRef = requiredEnv(getEnv, "LF_CALLER_RECURATION_REF");
  const recurationWorkflowRef = requiredEnv(getEnv, "LF_CALLER_RECURATION_WORKFLOW_REF");
  const recurationDispatchWorkflowRef = requiredEnv(getEnv, "LF_CALLER_RECURATION_DISPATCH_WORKFLOW_REF");
  const recurationWorkflowName = requiredEnv(getEnv, "LF_CALLER_RECURATION_WORKFLOW_NAME");
  const inputGovernanceSlug = requiredEnv(getEnv, "LF_CALLER_INPUT_GOVERNANCE_SLUG");
  const profileCreatorSlug = requiredEnv(getEnv, "LF_CALLER_PROFILE_CREATOR_SLUG");
  const recurationTimeoutRaw = requiredEnv(getEnv, "LF_CALLER_RECURATION_TIMEOUT_MS");
  const defaultTimeoutRaw = requiredEnv(getEnv, "LF_CALLER_DEFAULT_TIMEOUT_MS");

  try {
    const url = new URL(supabaseUrl);
    if (!(url.protocol === "https:" || url.protocol === "http:") || !url.hostname) throw new Error("invalid");
  } catch {
    throw new CallerFault("RUNTIME_CONFIG_MISSING", 500);
  }
  if (!serviceRoleKey) throw new CallerFault("RUNTIME_CONFIG_MISSING", 500);
  if (!validRepository(repository)) throw new CallerFault("CONFIG_LF_CALLER_REPOSITORY_INVALID", 500);
  if (!/^[1-9]\d*$/.test(repositoryId)) throw new CallerFault("CONFIG_LF_CALLER_REPOSITORY_ID_INVALID", 500);
  if (!validHeadRef(recurationRef)) throw new CallerFault("CONFIG_LF_CALLER_RECURATION_REF_INVALID", 500);
  if (!validWorkflowRef(recurationWorkflowRef, repository, recurationRef)) {
    throw new CallerFault("CONFIG_LF_CALLER_RECURATION_WORKFLOW_REF_INVALID", 500);
  }
  if (!validWorkflowRef(recurationDispatchWorkflowRef, repository, recurationRef)) {
    throw new CallerFault("CONFIG_LF_CALLER_RECURATION_DISPATCH_WORKFLOW_REF_INVALID", 500);
  }
  if (recurationWorkflowName.length > 200 || /[\r\n]/.test(recurationWorkflowName)) {
    throw new CallerFault("CONFIG_LF_CALLER_RECURATION_WORKFLOW_NAME_INVALID", 500);
  }
  if (!validSlug(inputGovernanceSlug)) throw new CallerFault("CONFIG_LF_CALLER_INPUT_GOVERNANCE_SLUG_INVALID", 500);
  if (!validSlug(profileCreatorSlug)) throw new CallerFault("CONFIG_LF_CALLER_PROFILE_CREATOR_SLUG_INVALID", 500);

  return {
    supabaseUrl: supabaseUrl.replace(/\/+$/, ""),
    serviceRoleKey,
    repository,
    repositoryId,
    recurationRef,
    recurationWorkflowRef,
    recurationDispatchWorkflowRef,
    recurationWorkflowName,
    inputGovernanceSlug,
    profileCreatorSlug,
    recurationTimeoutMs: parseTimeout(recurationTimeoutRaw, "LF_CALLER_RECURATION_TIMEOUT_MS", 149000),
    defaultTimeoutMs: parseTimeout(defaultTimeoutRaw, "LF_CALLER_DEFAULT_TIMEOUT_MS", 149000),
  };
}

function legacyWorkflowRef(config: CallerConfig): string {
  return `${config.repository}/.github/workflows/${LEGACY_WORKFLOW_FILE}@${LEGACY_REF}`;
}

export function resolveOidcIdentity(payload: JwtPayload, config: CallerConfig): OidcIdentity {
  const legacyRef = legacyWorkflowRef(config);
  if (
    payload.ref === LEGACY_REF &&
    payload.workflow_ref === legacyRef &&
    payload.workflow === LEGACY_WORKFLOW_NAME &&
    payload.event_name === "push"
  ) {
    return {
      method: "GITHUB_ACTIONS_OIDC_EXACT_PROFILE_GOV_V1",
      ref: LEGACY_REF,
      workflowRef: legacyRef,
      scope: "LEGACY_PROFILE_GOVERNANCE",
    };
  }

  const eventName = typeof payload.event_name === "string" ? payload.event_name : "";
  const jobWorkflowRef = typeof payload.job_workflow_ref === "string" ? payload.job_workflow_ref : "";
  if (
    payload.ref === config.recurationRef &&
    jobWorkflowRef === config.recurationWorkflowRef &&
    (eventName === "push" || eventName === "workflow_call")
  ) {
    return {
      method: "GITHUB_ACTIONS_OIDC_INPUT_GOV_RECURATION_REUSABLE_V1",
      ref: config.recurationRef,
      workflowRef: config.recurationWorkflowRef,
      scope: "INPUT_GOVERNANCE_RECURATION_ONLY",
    };
  }

  if (
    payload.ref === config.recurationRef &&
    jobWorkflowRef === config.recurationWorkflowRef &&
    payload.workflow_ref === config.recurationDispatchWorkflowRef &&
    eventName === "workflow_dispatch"
  ) {
    return {
      method: "GITHUB_ACTIONS_OIDC_INPUT_GOV_RECURATION_DISPATCH_V1",
      ref: config.recurationRef,
      workflowRef: config.recurationDispatchWorkflowRef,
      scope: "INPUT_GOVERNANCE_RECURATION_ONLY",
    };
  }

  throw new CallerFault("OIDC_WORKFLOW_IDENTITY_MISMATCH", 401);
}

async function requireOidc(req: Request, config: CallerConfig, deps: RuntimeDeps): Promise<{ payload: JwtPayload; identity: OidcIdentity }> {
  const authorization = req.headers.get("authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) throw new CallerFault("OIDC_BEARER_MISSING", 401);
  const token = authorization.slice(7).trim();
  if (!token) throw new CallerFault("OIDC_BEARER_EMPTY", 401);

  let payload: JwtPayload;
  try {
    ({ payload } = await deps.jwtVerifyFn(token, deps.jwks, {
      issuer: OIDC_ISSUER,
      audience: OIDC_AUDIENCE,
      algorithms: ["RS256"],
    }));
  } catch {
    throw new CallerFault("OIDC_TOKEN_INVALID", 401);
  }

  if (payload.repository !== config.repository || String(payload.repository_id ?? "") !== config.repositoryId) {
    throw new CallerFault("OIDC_REPOSITORY_MISMATCH", 401);
  }
  if (!payload.run_id || !payload.workflow_sha || !/^[0-9a-f]{40}$/.test(String(payload.workflow_sha))) {
    throw new CallerFault("OIDC_RUN_IDENTITY_INCOMPLETE", 401);
  }
  return { payload, identity: resolveOidcIdentity(payload, config) };
}

async function parseJsonObject(response: Response, code: string): Promise<Record<string, unknown>> {
  let value: unknown;
  try {
    value = await response.json();
  } catch {
    throw new CallerFault(code, 502);
  }
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new CallerFault(code, 502);
  return value as Record<string, unknown>;
}

function validateAllowlist(payload: Record<string, unknown>): RecurationAuthority {
  if (payload.schema_version !== ALLOWLIST_SCHEMA_VERSION) {
    throw new CallerFault("RECURATION_ALLOWLIST_SCHEMA_VERSION_INVALID", 409);
  }
  if (payload.rule_id !== ALLOWLIST_RULE_ID) throw new CallerFault("RECURATION_ALLOWLIST_RULE_ID_INVALID", 409);
  if (payload.estado !== "VIGENTE") throw new CallerFault("RECURATION_ALLOWLIST_STATE_INVALID", 409);
  const observedAt = typeof payload.observed_at === "string" ? payload.observed_at : "";
  if (!observedAt) throw new CallerFault("RECURATION_ALLOWLIST_OBSERVED_AT_INVALID", 409);

  const config = payload.valor_config;
  if (!config || typeof config !== "object" || Array.isArray(config)) {
    throw new CallerFault("RECURATION_ALLOWLIST_CONFIG_INVALID", 409);
  }
  const rule = config as Record<string, unknown>;
  if (rule.fail_closed !== true) throw new CallerFault("RECURATION_ALLOWLIST_FAIL_CLOSED_INVALID", 409);
  if (rule.contract_version !== ALLOWLIST_CONTRACT_VERSION) {
    throw new CallerFault("RECURATION_ALLOWLIST_CONTRACT_VERSION_INVALID", 409);
  }
  if (rule.caller_usage !== ALLOWLIST_CALLER_USAGE) {
    throw new CallerFault("RECURATION_ALLOWLIST_CALLER_USAGE_INVALID", 409);
  }
  if (!Array.isArray(rule.screen_ids)) throw new CallerFault("RECURATION_ALLOWLIST_SCREEN_IDS_INVALID", 409);
  const screenIds = rule.screen_ids as unknown[];
  if (!screenIds.every((item) => Number.isInteger(item))) {
    throw new CallerFault("RECURATION_ALLOWLIST_SCREEN_IDS_INVALID", 409);
  }
  const integerIds = screenIds as number[];
  if (new Set(integerIds).size !== integerIds.length) {
    throw new CallerFault("RECURATION_ALLOWLIST_SCREEN_IDS_DUPLICATED", 409);
  }
  if (!Number.isInteger(rule.authorized_screen_count) || (rule.authorized_screen_count as number) < 0) {
    throw new CallerFault("RECURATION_ALLOWLIST_AUTHORIZED_COUNT_INVALID", 409);
  }
  if (integerIds.length !== rule.authorized_screen_count) {
    throw new CallerFault("RECURATION_ALLOWLIST_COUNT_MISMATCH", 409);
  }

  return { ruleId: ALLOWLIST_RULE_ID, observedAt, screenIds: [...integerIds] };
}

async function readRecurationAuthority(config: CallerConfig, deps: RuntimeDeps): Promise<RecurationAuthority> {
  let response: Response;
  try {
    response = await deps.fetchFn(`${config.supabaseUrl}/rest/v1/rpc/${ALLOWLIST_RPC}`, {
      method: "POST",
      headers: {
        apikey: config.serviceRoleKey,
        authorization: `Bearer ${config.serviceRoleKey}`,
        "content-type": "application/json",
      },
      body: "{}",
      signal: AbortSignal.timeout(config.defaultTimeoutMs),
    });
  } catch {
    throw new CallerFault("RECURATION_ALLOWLIST_RPC_FETCH_FAILED", 502);
  }
  if (response.status !== 200) {
    throw new CallerFault("RECURATION_ALLOWLIST_RPC_HTTP_ERROR", 502, { rpc_status: response.status });
  }
  const payload = await parseJsonObject(response, "RECURATION_ALLOWLIST_RPC_RESPONSE_INVALID");
  return validateAllowlist(payload);
}

async function callRuntime(
  config: CallerConfig,
  deps: RuntimeDeps,
  slug: string,
  body: Record<string, unknown>,
  timeoutMs = config.defaultTimeoutMs,
): Promise<Record<string, unknown>> {
  const response = await deps.fetchFn(`${config.supabaseUrl}/functions/v1/${slug}`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${config.serviceRoleKey}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(timeoutMs),
  });
  const text = await response.text();
  let payload: Record<string, unknown>;
  try {
    const parsed = text ? JSON.parse(text) : {};
    payload = parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed as Record<string, unknown> : { raw: text.slice(0, 1000) };
  } catch {
    payload = { raw: text.slice(0, 1000) };
  }
  if (!response.ok) {
    throw new Error(`${slug.toUpperCase()}_${response.status}:${JSON.stringify(payload).slice(0, 1500)}`);
  }
  return payload;
}

// IG executes via a durable database queue. OIDC stays the HTTP trust boundary.
async function inputGovQueueRpc(
  config: CallerConfig, deps: RuntimeDeps,
  rpcName: "fn_input_governance_queue_submit_v1" | "fn_input_governance_queue_read_v1",
  body: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const response = await deps.fetchFn(`${config.supabaseUrl}/rest/v1/rpc/${rpcName}`, {
    method: "POST",
    headers: {
      apikey: config.serviceRoleKey,
      authorization: `Bearer ${config.serviceRoleKey}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(15_000),
  });
  const raw = await response.text();
  let payload: Record<string, unknown>;
  try {
    const parsed = raw ? JSON.parse(raw) : {};
    payload = parsed && typeof parsed === "object" && !Array.isArray(parsed)
      ? parsed as Record<string, unknown> : { error: "RPC_RESPONSE_INVALID" };
  } catch {
    throw new CallerFault("IG_DIRECT_QUEUE_RPC_INVALID_JSON", 502);
  }
  if (!response.ok) {
    throw new CallerFault("IG_DIRECT_QUEUE_RPC_REJECTED", 502, {
      rpc: rpcName, rpc_status: response.status,
      error_code: typeof payload.code === "string" ? payload.code : "UNKNOWN",
    });
  }
  return payload;
}

async function materializeScreen(
  config: CallerConfig,
  deps: RuntimeDeps,
  screen: { pantalla_id: number; codigo?: string },
  consumer = STORY_CREATOR_CONSUMER,
  timeoutMs = config.defaultTimeoutMs,
) {
  const submitted = await inputGovQueueRpc(config, deps, "fn_input_governance_queue_submit_v1", {
    p_pantalla_id: screen.pantalla_id, p_consumer: consumer,
  });
  const requestId = Number(submitted.request_id);
  if (!Number.isSafeInteger(requestId) || requestId < 1) {
    throw new CallerFault("IG_DIRECT_QUEUE_RECEIPT_INVALID", 502);
  }
  const deadline = Date.now() + Math.min(timeoutMs, 110_000);
  let snapshot: Record<string, unknown> = submitted;
  while (Date.now() < deadline) {
    snapshot = await inputGovQueueRpc(config, deps, "fn_input_governance_queue_read_v1", {
      p_request_id: requestId,
    });
    if (snapshot.queue_status === "DONE" || snapshot.queue_status === "ERROR") break;
    await new Promise<void>((resolve) => setTimeout(resolve, 4_000));
  }
  const done = snapshot.queue_status === "DONE";
  const failed = snapshot.queue_status === "ERROR";
  const currentStatus = done
    ? (typeof snapshot.status === "string" ? snapshot.status : "BLOCKED")
    : failed ? "BLOCKED" : "CONTINUATION_REQUIRED";
  return {
    ...screen, consumer, status: currentStatus,
    run_id: snapshot.run_id ?? null,
    payload: {
      transport: "DIRECT_SQL_PERSISTED_QUEUE_V1",
      request_id: requestId,
      queue_status: snapshot.queue_status ?? "QUEUED",
      next_action: done || failed ? "NONE" : "POLL_SAME_REQUEST",
      result: snapshot.result ?? null,
      step_count: snapshot.step_count ?? 0,
      error_code: failed ? snapshot.error_code ?? "IG_QUEUE_FAILED" : null,
    },
  };
}

function withAuthority(caller: Record<string, unknown>, authority: RecurationAuthority): Record<string, unknown> {
  return {
    ...caller,
    recuration_rule_id: authority.ruleId,
    recuration_rule_observed_at: authority.observedAt,
  };
}

export function createHandler(deps: RuntimeDeps): (req: Request) => Promise<Response> {
  return async (req: Request): Promise<Response> => {
    try {
      if (req.method !== "POST") return json({ outcome: "BLOCKED", code: "METHOD_NOT_ALLOWED" }, 405);
      const config = loadConfig(deps.getEnv);
      const { payload: claims, identity } = await requireOidc(req, config, deps);

      let body: Record<string, unknown>;
      try {
        const parsed = await req.json();
        if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error("invalid");
        body = parsed as Record<string, unknown>;
      } catch {
        return json({ outcome: "BLOCKED", code: "INVALID_JSON" }, 400);
      }

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
      const caller: Record<string, unknown> = {
        method: identity.method,
        scope: identity.scope,
        repository: config.repository,
        workflow_ref: identity.workflowRef,
        run_id: runId,
        workflow_sha: workflowSha,
      };
      if (isRecurationIdentity) caller.workflow_name = config.recurationWorkflowName;

      if (action === RECURATION_ACTION) {
        if (Object.prototype.hasOwnProperty.call(body, "pantalla_ids")) {
          return json({ outcome: "BLOCKED", code: "RECURATION_SINGLE_SCREEN_REQUIRED", caller }, 400);
        }
        const pantallaId = typeof body.pantalla_id === "number" ? body.pantalla_id : Number.NaN;
        if (!Number.isInteger(pantallaId)) {
          return json({ outcome: "BLOCKED", code: "RECURATION_SCREEN_ID_INVALID", caller }, 400);
        }

        const authority = await readRecurationAuthority(config, deps);
        const auditedCaller = withAuthority(caller, authority);
        if (!authority.screenIds.includes(pantallaId)) {
          return json({
            outcome: "BLOCKED",
            code: "RECURATION_SCREEN_NOT_ALLOWED",
            caller: auditedCaller,
            pantalla_id: pantallaId,
            allowed_pantalla_ids: authority.screenIds,
          }, 400);
        }

        const result = await materializeScreen(
          config,
          deps,
          { pantalla_id: pantallaId },
          STORY_CREATOR_CONSUMER,
          config.recurationTimeoutMs,
        );
        const terminal = typeof result.status === "string" &&
          result.status.length > 0 &&
          !["CONTINUATION_REQUIRED", "VALIDATOR_CONTINUE_REQUIRED", "VALIDATOR_RUNTIME_REQUIRED"].includes(result.status);
        if (!terminal) {
          return json({
            outcome: "CONTINUATION_REQUIRED",
            code: "IG_DIRECT_QUEUE_STILL_PROCESSING",
            scope: "IG_CURATOR_VALIDATOR_REFACTOR_V2_N2",
            caller: auditedCaller, consumer: STORY_CREATOR_CONSUMER,
            pantalla_id: pantallaId, result,
          }, 202);
        }
        return json({
          outcome: "TERMINAL",
          scope: "IG_CURATOR_VALIDATOR_REFACTOR_V2_N2",
          caller: auditedCaller,
          consumer: STORY_CREATOR_CONSUMER,
          pantalla_id: pantallaId,
          terminal_status: result.status,
          run_id: result.run_id,
          result,
        });
      }

      if (action === SCREEN_ACTION) {
        const codigo = typeof body.codigo === "string" ? body.codigo : "";
        const screen = PILOT_SCREENS.find((item) => item.codigo === codigo);
        if (!screen) return json({ outcome: "BLOCKED", code: "PILOT_SCREEN_NOT_ALLOWED", caller, codigo }, 400);
        const result = await materializeScreen(config, deps, screen);
        const ready = result.status === "READY";
        return json({
          outcome: ready ? "READY" : "BLOCKED",
          caller,
          required_count: 1,
          ready_count: ready ? 1 : 0,
          result,
        }, ready ? 200 : 409);
      }

      if (action === B2B_ACTION) {
        const codigo = typeof body.codigo === "string" ? body.codigo : "";
        const screen = B2B_402_SCREENS.find((item) => item.codigo === codigo);
        if (!screen) return json({ outcome: "BLOCKED", code: "B2B_402_SCREEN_NOT_ALLOWED", caller, codigo }, 400);
        const result = await materializeScreen(config, deps, screen, MANUAL_CONSUMER);
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

      if (action === PILOT_ACTION) {
        const results: Record<string, unknown>[] = [];
        for (const screen of PILOT_SCREENS) results.push(await materializeScreen(config, deps, screen));
        const readyCount = results.filter((item) => item.status === "READY").length;
        return json({
          outcome: readyCount === PILOT_SCREENS.length ? "READY" : "BLOCKED",
          caller,
          ready_count: readyCount,
          required_count: PILOT_SCREENS.length,
          results,
        }, readyCount === PILOT_SCREENS.length ? 200 : 409);
      }

      if (action === PROFILE_INIT_ACTION) {
        const callerRequestId = typeof body.caller_request_id === "string" ? body.caller_request_id : "";
        const targetCode = typeof body.target_code === "string" ? body.target_code : "";
        const profileSlug = typeof body.profile_slug === "string" ? body.profile_slug : "";
        const result = await callRuntime(config, deps, config.profileCreatorSlug, {
          action: "initialize_profile_creation_v1",
          caller_request_id: callerRequestId,
          target_code: targetCode,
          profile_slug: profileSlug,
          target_repo: config.repository,
          caller,
        });
        return json({ outcome: result.outcome ?? "BLOCKED", caller, result }, result.outcome === "INITIALIZED" ? 201 : 409);
      }

      if (action === PROFILE_STEP_ACTION) {
        const executionId = typeof body.execution_id === "string" ? body.execution_id : "";
        const stepId = typeof body.step_id === "string" ? body.step_id : "";
        const evidenceRef = typeof body.evidence_ref === "string" ? body.evidence_ref : "";
        const evidencePayload = body.evidence_payload && typeof body.evidence_payload === "object" && !Array.isArray(body.evidence_payload)
          ? body.evidence_payload as Record<string, unknown>
          : null;
        if (!executionId || !stepId || !evidenceRef || !evidencePayload) {
          return json({ outcome: "BLOCKED", code: "PROFILE_CREATOR_STEP_INPUT_INVALID", caller }, 400);
        }
        const result = await callRuntime(config, deps, config.profileCreatorSlug, {
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
      if (error instanceof CallerFault) {
        return json({ outcome: "BLOCKED", code: error.code, ...error.details }, error.status);
      }
      const message = error instanceof Error ? error.message : String(error);
      console.error(message.replace(/Bearer\s+\S+/g, "Bearer [REDACTED]"));
      const unauthorized = message.startsWith("OIDC_");
      return json({ outcome: "BLOCKED", code: message.slice(0, 1000) }, unauthorized ? 401 : 409);
    }
  };
}
