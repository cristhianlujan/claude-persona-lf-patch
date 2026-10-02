import { createHandler, OIDC_AUDIENCE, OIDC_ISSUER, type JwtPayload } from "./caller.ts";

function assert(condition: unknown, message = "assertion failed"): asserts condition {
  if (!condition) throw new Error(message);
}
function assertEquals(actual: unknown, expected: unknown, message = "values differ"): void {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a !== e) throw new Error(`${message}: actual=${a} expected=${e}`);
}

const REPO = "cristhianlujan/claude-persona-lf-patch";
const REPO_ID = "1244397752";
const REF = "refs/heads/main";
const REUSABLE = `${REPO}/.github/workflows/lf-input-governance-recurate.yml@${REF}`;
const DISPATCH = `${REPO}/.github/workflows/lf-input-governance-recurate-dispatch.yml@${REF}`;
const LEGACY_REF = "refs/heads/governance/profiles-unblock-secure-caller-20260901";
const LEGACY_WORKFLOW_REF = `${REPO}/.github/workflows/lf-profiles-governance-caller.yml@${LEGACY_REF}`;
const SHA = "a".repeat(40);
const MOCK_JWKS = { kind: "mock-jwks" };
const SCREEN_IDS = [1, 2, 3, 5, 43, 51, 52, 53, 54, 55, 56, 57, 58];

const BASE_ENV: Record<string, string> = {
  SUPABASE_URL: "https://project.supabase.co",
  SUPABASE_SERVICE_ROLE_KEY: "service-role-test-key",
  LF_CALLER_REPOSITORY: REPO,
  LF_CALLER_REPOSITORY_ID: REPO_ID,
  LF_CALLER_RECURATION_REF: REF,
  LF_CALLER_RECURATION_WORKFLOW_REF: REUSABLE,
  LF_CALLER_RECURATION_DISPATCH_WORKFLOW_REF: DISPATCH,
  LF_CALLER_RECURATION_WORKFLOW_NAME: "LF Input Governance Recuration",
  LF_CALLER_INPUT_GOVERNANCE_SLUG: "input-governance-agent-v1",
  LF_CALLER_PROFILE_CREATOR_SLUG: "run-creacion-perfil-lf",
  LF_CALLER_RECURATION_TIMEOUT_MS: "149000",
  LF_CALLER_DEFAULT_TIMEOUT_MS: "120000",
};

const DISPATCH_CLAIMS: JwtPayload = {
  repository: REPO,
  repository_id: REPO_ID,
  ref: REF,
  job_workflow_ref: REUSABLE,
  workflow_ref: DISPATCH,
  event_name: "workflow_dispatch",
  run_id: "9001",
  workflow_sha: SHA,
};

const REUSABLE_PUSH_CLAIMS: JwtPayload = {
  repository: REPO,
  repository_id: REPO_ID,
  ref: REF,
  job_workflow_ref: REUSABLE,
  workflow_ref: REUSABLE,
  event_name: "push",
  run_id: "9002",
  workflow_sha: SHA,
};

const REUSABLE_CALL_CLAIMS: JwtPayload = {
  ...REUSABLE_PUSH_CLAIMS,
  event_name: "workflow_call",
  run_id: "9003",
};

const LEGACY_CLAIMS: JwtPayload = {
  repository: REPO,
  repository_id: REPO_ID,
  ref: LEGACY_REF,
  workflow_ref: LEGACY_WORKFLOW_REF,
  workflow: "LF Profiles Governance Caller",
  event_name: "push",
  run_id: "9004",
  workflow_sha: SHA,
};

function goodAllowlist(): Record<string, unknown> {
  return {
    schema_version: "lf-input-gov-recuration-allowlist/v1",
    rule_id: 661,
    codigo: "INPUT-GOV-RECURATION-AUTHORIZED-SCREENS-001",
    estado: "VIGENTE",
    valor_config: {
      contract_version: "1.0.0",
      screen_ids: [...SCREEN_IDS],
      authorized_screen_count: 13,
      caller_usage: "ALLOWLIST_FOR_GOVERNED_RECURATION",
      fail_closed: true,
    },
    updated_at: "2026-10-01T23:04:10.277265+00:00",
    observed_at: "2026-10-02T17:30:00.000000+00:00",
  };
}

type HarnessOptions = {
  env?: Record<string, string>;
  claims?: JwtPayload;
  allowlistStatus?: number;
  allowlistPayload?: unknown;
  inputStatus?: string;
};

function harness(options: HarnessOptions = {}) {
  const env = { ...BASE_ENV, ...(options.env ?? {}) };
  let claims = options.claims ?? DISPATCH_CLAIMS;
  let allowlistStatus = options.allowlistStatus ?? 200;
  let allowlistPayload = options.allowlistPayload ?? goodAllowlist();
  let inputStatus = options.inputStatus ?? "READY";
  const calls: Array<{ url: string; init?: RequestInit; body?: Record<string, unknown> }> = [];

  const handler = createHandler({
    getEnv: (name) => env[name],
    jwks: MOCK_JWKS,
    jwtVerifyFn: async (token, jwks, verifyOptions) => {
      assertEquals(token, "mock-token", "JWT token mismatch");
      assert(jwks === MOCK_JWKS, "JWKS mock was not propagated");
      assertEquals(verifyOptions, { issuer: OIDC_ISSUER, audience: OIDC_AUDIENCE, algorithms: ["RS256"] }, "JWT verify options mismatch");
      return { payload: claims };
    },
    fetchFn: async (input, init) => {
      const url = String(input);
      let body: Record<string, unknown> | undefined;
      if (typeof init?.body === "string" && init.body && init.body !== "{}") body = JSON.parse(init.body);
      calls.push({ url, init, body });
      if (url.endsWith("/rest/v1/rpc/lf_input_gov_recuration_allowlist_v1")) {
        return new Response(JSON.stringify(allowlistPayload), { status: allowlistStatus, headers: { "content-type": "application/json" } });
      }
      if (url.endsWith("/functions/v1/input-governance-agent-v1")) {
        const id = Number(body?.pantalla_id ?? 0);
        return new Response(JSON.stringify({ result: { status: inputStatus, run_id: 10000 + id } }), { status: 200 });
      }
      if (url.endsWith("/functions/v1/run-creacion-perfil-lf")) {
        return new Response(JSON.stringify({ outcome: "INITIALIZED" }), { status: 200 });
      }
      return new Response(JSON.stringify({ error: "unexpected url" }), { status: 404 });
    },
  });

  return {
    env,
    calls,
    handler,
    setClaims(value: JwtPayload) { claims = value; },
    setAllowlist(status: number, payload: unknown) { allowlistStatus = status; allowlistPayload = payload; },
    setInputStatus(value: string) { inputStatus = value; },
  };
}

async function invoke(h: ReturnType<typeof harness>, body: Record<string, unknown>) {
  const response = await h.handler(new Request("https://caller.test", {
    method: "POST",
    headers: { authorization: "Bearer mock-token", "content-type": "application/json" },
    body: JSON.stringify(body),
  }));
  const payload = await response.json();
  return { response, payload };
}

function recurationBody(id: number): Record<string, unknown> {
  return { action: "input_readiness_recurate_v1", pantalla_id: id };
}

Deno.test("positive: exact workflow_dispatch identity from main", async () => {
  const h = harness();
  const { response, payload } = await invoke(h, recurationBody(1));
  assertEquals(response.status, 200);
  assertEquals(payload.outcome, "TERMINAL");
  assertEquals(payload.caller.method, "GITHUB_ACTIONS_OIDC_INPUT_GOV_RECURATION_DISPATCH_V1");
  assertEquals(payload.caller.workflow_ref, DISPATCH);
  assertEquals(payload.caller.workflow_name, "LF Input Governance Recuration");
  assertEquals(payload.caller.recuration_rule_id, 661);
  assertEquals(payload.caller.recuration_rule_observed_at, "2026-10-02T17:30:00.000000+00:00");
  assertEquals(h.calls[0].url, "https://project.supabase.co/rest/v1/rpc/lf_input_gov_recuration_allowlist_v1");
  const headers = new Headers(h.calls[0].init?.headers);
  assertEquals(headers.get("apikey"), BASE_ENV.SUPABASE_SERVICE_ROLE_KEY);
  assertEquals(headers.get("authorization"), `Bearer ${BASE_ENV.SUPABASE_SERVICE_ROLE_KEY}`);
  assertEquals(h.calls[0].init?.body, "{}");
});

for (const [eventName, claims] of [["push", REUSABLE_PUSH_CLAIMS], ["workflow_call", REUSABLE_CALL_CLAIMS]] as const) {
  Deno.test(`positive parity: reusable ${eventName} identity remains accepted`, async () => {
    const h = harness({ claims });
    const { response, payload } = await invoke(h, recurationBody(2));
    assertEquals(response.status, 200);
    assertEquals(payload.caller.method, "GITHUB_ACTIONS_OIDC_INPUT_GOV_RECURATION_REUSABLE_V1");
    assertEquals(payload.caller.workflow_ref, REUSABLE);
  });
}

Deno.test("positive parity: legacy identity remains accepted", async () => {
  const h = harness({ claims: LEGACY_CLAIMS });
  const { response, payload } = await invoke(h, { action: "input_readiness_screen_v1", codigo: "ONB_002" });
  assertEquals(response.status, 200);
  assertEquals(payload.outcome, "READY");
  assertEquals(payload.caller.method, "GITHUB_ACTIONS_OIDC_EXACT_PROFILE_GOV_V1");
  assertEquals(payload.caller.workflow_ref, LEGACY_WORKFLOW_REF);
});

for (const id of SCREEN_IDS) {
  Deno.test(`positive allowlist: authorized screen ${id}${id === 55 ? " (TRACEABILITY_ONLY but recurable)" : ""}`, async () => {
    const h = harness();
    const { response, payload } = await invoke(h, recurationBody(id));
    assertEquals(response.status, 200);
    assertEquals(payload.pantalla_id, id);
    assertEquals(payload.consumer, "STORY_CREATOR");
    assertEquals(payload.caller.recuration_rule_id, 661);
    assertEquals(h.calls.filter((c) => c.url.includes("/rest/v1/rpc/")).length, 1);
    assertEquals(h.calls.filter((c) => c.url.includes("/functions/v1/input-governance-agent-v1")).length, 1);
  });
}

const identityNegatives: Array<[string, JwtPayload, string]> = [
  ["dispatch from another branch", { ...DISPATCH_CLAIMS, ref: "refs/heads/feature" }, "OIDC_WORKFLOW_IDENTITY_MISMATCH"],
  ["dispatch with other workflow_ref", { ...DISPATCH_CLAIMS, workflow_ref: `${REPO}/.github/workflows/other.yml@${REF}` }, "OIDC_WORKFLOW_IDENTITY_MISMATCH"],
  ["dispatch with other job_workflow_ref", { ...DISPATCH_CLAIMS, job_workflow_ref: `${REPO}/.github/workflows/other.yml@${REF}` }, "OIDC_WORKFLOW_IDENTITY_MISMATCH"],
  ["dispatch with other repository_id", { ...DISPATCH_CLAIMS, repository_id: "999" }, "OIDC_REPOSITORY_MISMATCH"],
  ["bootstrap identity", { ...DISPATCH_CLAIMS, event_name: "push", workflow_ref: `${REPO}/.github/workflows/lf-bootstrap-reproducibility.yml@${REF}`, job_workflow_ref: "" }, "OIDC_WORKFLOW_IDENTITY_MISMATCH"],
];
for (const [name, claims, code] of identityNegatives) {
  Deno.test(`negative identity: ${name}`, async () => {
    const h = harness({ claims });
    const { response, payload } = await invoke(h, recurationBody(1));
    assertEquals(response.status, 401);
    assertEquals(payload.code, code);
    assertEquals(h.calls.length, 0, "identity rejection must happen before fetch");
  });
}

Deno.test("negative: screen outside rule is blocked without target Edge call", async () => {
  const h = harness();
  const { response, payload } = await invoke(h, recurationBody(999));
  assertEquals(response.status, 400);
  assertEquals(payload.code, "RECURATION_SCREEN_NOT_ALLOWED");
  assertEquals(payload.caller.recuration_rule_id, 661);
  assertEquals(h.calls.filter((c) => c.url.includes("/rest/v1/rpc/")).length, 1);
  assertEquals(h.calls.filter((c) => c.url.includes("/functions/v1/")).length, 0);
});

for (const status of [401, 500]) {
  Deno.test(`negative allowlist RPC: HTTP ${status} fails closed before target Edge`, async () => {
    const h = harness({ allowlistStatus: status });
    const { response, payload } = await invoke(h, recurationBody(1));
    assertEquals(response.status, 502);
    assertEquals(payload.code, "RECURATION_ALLOWLIST_RPC_HTTP_ERROR");
    assertEquals(payload.rpc_status, status);
    assertEquals(h.calls.filter((c) => c.url.includes("/functions/v1/")).length, 0);
  });
}

type RuleMutation = [string, (rule: Record<string, unknown>) => void, string];
const ruleMutations: RuleMutation[] = [
  ["schema_version", (r) => { r.schema_version = "wrong"; }, "RECURATION_ALLOWLIST_SCHEMA_VERSION_INVALID"],
  ["rule_id", (r) => { r.rule_id = 662; }, "RECURATION_ALLOWLIST_RULE_ID_INVALID"],
  ["estado", (r) => { r.estado = "BORRADOR"; }, "RECURATION_ALLOWLIST_STATE_INVALID"],
  ["observed_at", (r) => { r.observed_at = ""; }, "RECURATION_ALLOWLIST_OBSERVED_AT_INVALID"],
  ["valor_config", (r) => { r.valor_config = null; }, "RECURATION_ALLOWLIST_CONFIG_INVALID"],
  ["fail_closed", (r) => { (r.valor_config as Record<string, unknown>).fail_closed = false; }, "RECURATION_ALLOWLIST_FAIL_CLOSED_INVALID"],
  ["contract_version", (r) => { (r.valor_config as Record<string, unknown>).contract_version = "2.0.0"; }, "RECURATION_ALLOWLIST_CONTRACT_VERSION_INVALID"],
  ["caller_usage", (r) => { (r.valor_config as Record<string, unknown>).caller_usage = "OTHER"; }, "RECURATION_ALLOWLIST_CALLER_USAGE_INVALID"],
  ["screen_ids not array", (r) => { (r.valor_config as Record<string, unknown>).screen_ids = "1,2"; }, "RECURATION_ALLOWLIST_SCREEN_IDS_INVALID"],
  ["screen_ids non-integer", (r) => { (r.valor_config as Record<string, unknown>).screen_ids = [1, "2"]; }, "RECURATION_ALLOWLIST_SCREEN_IDS_INVALID"],
  ["screen_ids duplicated", (r) => { (r.valor_config as Record<string, unknown>).screen_ids = [1, 1]; (r.valor_config as Record<string, unknown>).authorized_screen_count = 2; }, "RECURATION_ALLOWLIST_SCREEN_IDS_DUPLICATED"],
  ["authorized_screen_count invalid", (r) => { (r.valor_config as Record<string, unknown>).authorized_screen_count = "13"; }, "RECURATION_ALLOWLIST_AUTHORIZED_COUNT_INVALID"],
  ["count inconsistent", (r) => { (r.valor_config as Record<string, unknown>).authorized_screen_count = 12; }, "RECURATION_ALLOWLIST_COUNT_MISMATCH"],
];
for (const [name, mutate, code] of ruleMutations) {
  Deno.test(`negative allowlist field: ${name}`, async () => {
    const rule = goodAllowlist();
    mutate(rule);
    const h = harness({ allowlistPayload: rule });
    const { response, payload } = await invoke(h, recurationBody(1));
    assertEquals(response.status, 409);
    assertEquals(payload.code, code);
    assertEquals(h.calls.filter((c) => c.url.includes("/functions/v1/")).length, 0, "invalid authority must not call target Edge");
  });
}

const lfEnvVars = [
  "LF_CALLER_REPOSITORY",
  "LF_CALLER_REPOSITORY_ID",
  "LF_CALLER_RECURATION_REF",
  "LF_CALLER_RECURATION_WORKFLOW_REF",
  "LF_CALLER_RECURATION_DISPATCH_WORKFLOW_REF",
  "LF_CALLER_RECURATION_WORKFLOW_NAME",
  "LF_CALLER_INPUT_GOVERNANCE_SLUG",
  "LF_CALLER_PROFILE_CREATOR_SLUG",
  "LF_CALLER_RECURATION_TIMEOUT_MS",
  "LF_CALLER_DEFAULT_TIMEOUT_MS",
] as const;

const invalidEnv: Record<(typeof lfEnvVars)[number], string> = {
  LF_CALLER_REPOSITORY: "not-a-repository",
  LF_CALLER_REPOSITORY_ID: "abc",
  LF_CALLER_RECURATION_REF: "main",
  LF_CALLER_RECURATION_WORKFLOW_REF: "bad",
  LF_CALLER_RECURATION_DISPATCH_WORKFLOW_REF: "bad",
  LF_CALLER_RECURATION_WORKFLOW_NAME: "x".repeat(201),
  LF_CALLER_INPUT_GOVERNANCE_SLUG: "BAD_SLUG",
  LF_CALLER_PROFILE_CREATOR_SLUG: "BAD_SLUG",
  LF_CALLER_RECURATION_TIMEOUT_MS: "149001",
  LF_CALLER_DEFAULT_TIMEOUT_MS: "not-a-number",
};

for (const name of lfEnvVars) {
  Deno.test(`negative config: missing ${name} fails closed`, async () => {
    const h = harness();
    delete h.env[name];
    const { response, payload } = await invoke(h, recurationBody(1));
    assertEquals(response.status, 500);
    assertEquals(payload.code, `CONFIG_${name}_MISSING`);
    assertEquals(h.calls.length, 0);
  });
  Deno.test(`negative config: invalid ${name} fails closed`, async () => {
    const h = harness();
    h.env[name] = invalidEnv[name];
    const { response, payload } = await invoke(h, recurationBody(1));
    assertEquals(response.status, 500);
    assertEquals(payload.code, `CONFIG_${name}_INVALID`);
    assertEquals(h.calls.length, 0);
  });
}

Deno.test("negative scope: recuration action with legacy identity is rejected", async () => {
  const h = harness({ claims: LEGACY_CLAIMS });
  const { response, payload } = await invoke(h, recurationBody(1));
  assertEquals(response.status, 403);
  assertEquals(payload.code, "RECURATION_CALLER_IDENTITY_REQUIRED");
  assertEquals(h.calls.length, 0);
});

Deno.test("parity v7: legacy single-screen response shape and STORY_CREATOR consumer", async () => {
  const h = harness({ claims: LEGACY_CLAIMS });
  const { response, payload } = await invoke(h, { action: "input_readiness_screen_v1", codigo: "ONB_002" });
  assertEquals(response.status, 200);
  assertEquals(payload.outcome, "READY");
  assertEquals(payload.required_count, 1);
  assertEquals(payload.ready_count, 1);
  assertEquals(payload.result.consumer, "STORY_CREATOR");
  assertEquals(h.calls[0].body, { pantalla_id: 2, consumer: "STORY_CREATOR" });
});

Deno.test("parity v7: pilot response remains four governed screens", async () => {
  const h = harness({ claims: LEGACY_CLAIMS });
  const { response, payload } = await invoke(h, { action: "input_readiness_pilot_v1" });
  assertEquals(response.status, 200);
  assertEquals(payload.outcome, "READY");
  assertEquals(payload.required_count, 4);
  assertEquals(payload.ready_count, 4);
  assertEquals(payload.results.map((r: Record<string, unknown>) => r.pantalla_id), [2, 3, 57, 5]);
  assert(h.calls.every((c) => !c.body || c.body.consumer === "STORY_CREATOR"));
});

Deno.test("parity v7: B2B 402 response keeps MANUAL consumer", async () => {
  const h = harness({ claims: LEGACY_CLAIMS });
  const { response, payload } = await invoke(h, { action: "input_readiness_b2b_402_v1", codigo: "B2B-CARGA-001" });
  assertEquals(response.status, 200);
  assertEquals(payload.outcome, "READY");
  assertEquals(payload.scope, "LF_EMPRESA_ISSUE_402");
  assertEquals(payload.result.consumer, "MANUAL");
  assertEquals(h.calls[0].body, { pantalla_id: 43, consumer: "MANUAL" });
});
