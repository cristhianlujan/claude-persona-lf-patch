import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const REPOSITORY = "cristhianlujan/programming-agent";
const WORKFLOW_NAME = "canonical-ci";
const WORKFLOW_PATH = ".github/workflows/ci.yml";
const POLICY_ID = "c6f2c34aa7fac4117fb2df29a343164e7b9ed132a261052eb9e95370be75924b";
const GENERATOR_MODE = "opaque-external-bundle-v3";
const FAMILY_COUNTS: Record<string, number> = {
  concurrency_partial_failure: 2,
  root_cause_bug: 1,
  multi_file_feature: 1,
  security: 1,
};
const FAMILY_NAMES = Object.keys(FAMILY_COUNTS).sort();
const HEX40 = /^[0-9a-f]{40}$/;
const HEX64 = /^[0-9a-f]{64}$/;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")?.trim() ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() ?? "";
const encoder = new TextEncoder();

type Challenge = {
  challenge_id: string;
  source: string;
  timeout_seconds: number;
  max_output_bytes: number;
};

type HiddenBundle = {
  schema_version: number;
  policy_id: string;
  families: Record<string, Challenge[]>;
};

function response(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
    },
  });
}

function text(value: unknown): string {
  return String(value ?? "").trim();
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function canonicalJson(value: unknown): string {
  if (value === null) return "null";
  if (typeof value === "string" || typeof value === "boolean") return JSON.stringify(value);
  if (typeof value === "number") {
    if (!Number.isSafeInteger(value)) throw new Error("CANONICAL_NUMBER_INVALID");
    return String(value);
  }
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (isPlainObject(value)) {
    const keys = Object.keys(value).sort();
    return `{${keys.map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(",")}}`;
  }
  throw new Error("CANONICAL_VALUE_INVALID");
}

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(value));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function github(token: string, url: string): Promise<any> {
  const result = await fetch(url, {
    headers: {
      accept: "application/vnd.github+json",
      authorization: `Bearer ${token}`,
      "x-github-api-version": "2022-11-28",
      "user-agent": "programming-agent-hidden-oracle-v3",
    },
    signal: AbortSignal.timeout(15000),
  });
  const raw = await result.text();
  if (!result.ok) throw new Error(`GITHUB_READBACK_${result.status}`);
  return raw ? JSON.parse(raw) : null;
}

async function authenticateGitHub(req: Request, body: Record<string, unknown>): Promise<void> {
  const authorization = req.headers.get("authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) throw new Error("GITHUB_TOKEN_MISSING");
  const token = authorization.slice(7).trim();
  if (!token) throw new Error("GITHUB_TOKEN_EMPTY");

  if (body.repository !== REPOSITORY) throw new Error("GITHUB_REPOSITORY_MISMATCH");
  const headSha = text(body.head_sha);
  const branch = text(body.head_branch);
  const eventName = text(body.event_name);
  const nonce = text(body.nonce);
  const runId = Number(body.run_id);
  const runAttempt = Number(body.run_attempt);

  if (!HEX40.test(headSha)) throw new Error("GITHUB_HEAD_INVALID");
  if (!branch || branch.length > 250) throw new Error("GITHUB_BRANCH_INVALID");
  if (!["pull_request", "push"].includes(eventName)) throw new Error("GITHUB_EVENT_INVALID");
  if (!Number.isSafeInteger(runId) || runId <= 0) throw new Error("GITHUB_RUN_ID_INVALID");
  if (!Number.isSafeInteger(runAttempt) || runAttempt <= 0) throw new Error("GITHUB_RUN_ATTEMPT_INVALID");
  if (!HEX64.test(nonce)) throw new Error("REQUEST_NONCE_INVALID");

  const installation = await github(token, "https://api.github.com/installation/repositories?per_page=100");
  const repositories = Array.isArray(installation?.repositories) ? installation.repositories : [];
  if (!repositories.some((repo: any) => repo?.full_name === REPOSITORY)) {
    throw new Error("GITHUB_INSTALLATION_REPOSITORY_MISMATCH");
  }

  const run = await github(token, `https://api.github.com/repos/${REPOSITORY}/actions/runs/${runId}`);
  if (Number(run?.id) !== runId || Number(run?.run_attempt) !== runAttempt) {
    throw new Error("GITHUB_RUN_IDENTITY_MISMATCH");
  }
  if (run?.repository?.full_name !== REPOSITORY || run?.name !== WORKFLOW_NAME || run?.path !== WORKFLOW_PATH) {
    throw new Error("GITHUB_WORKFLOW_IDENTITY_MISMATCH");
  }
  if (run?.head_sha !== headSha || run?.head_branch !== branch || run?.event !== eventName) {
    throw new Error("GITHUB_RUN_SOURCE_MISMATCH");
  }
  if (!["queued", "in_progress"].includes(run?.status)) {
    throw new Error("GITHUB_RUN_STATUS_INVALID");
  }
}

async function loadHiddenBundle(): Promise<HiddenBundle> {
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY) throw new Error("SUPABASE_RUNTIME_CONFIGURATION_MISSING");
  const result = await fetch(`${SUPABASE_URL}/rest/v1/rpc/programming_hidden_oracle_bundle_v3`, {
    method: "POST",
    headers: {
      apikey: SERVICE_ROLE_KEY,
      authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      "content-type": "application/json",
      accept: "application/json",
    },
    body: "{}",
    signal: AbortSignal.timeout(10000),
  });
  const raw = await result.text();
  if (!result.ok) throw new Error(`HIDDEN_BUNDLE_READBACK_${result.status}`);
  let value: unknown;
  try {
    value = JSON.parse(raw);
  } catch {
    throw new Error("HIDDEN_BUNDLE_RESPONSE_INVALID_JSON");
  }
  if (!isPlainObject(value)) throw new Error("HIDDEN_BUNDLE_OBJECT_REQUIRED");
  return validateBundle(value);
}

function validateBundle(value: Record<string, unknown>): HiddenBundle {
  if (value.schema_version !== 1 || value.policy_id !== POLICY_ID || !isPlainObject(value.families)) {
    throw new Error("HIDDEN_BUNDLE_CONTRACT_INVALID");
  }
  const familyKeys = Object.keys(value.families).sort();
  if (canonicalJson(familyKeys) !== canonicalJson(FAMILY_NAMES)) throw new Error("HIDDEN_BUNDLE_FAMILY_SET_INVALID");

  const seen = new Set<string>();
  const families: Record<string, Challenge[]> = {};
  for (const family of FAMILY_NAMES) {
    const rawChallenges = value.families[family];
    if (!Array.isArray(rawChallenges) || rawChallenges.length < FAMILY_COUNTS[family]) {
      throw new Error(`HIDDEN_BUNDLE_FAMILY_CAPACITY_INVALID:${family}`);
    }
    families[family] = rawChallenges.map((raw, index) => {
      if (!isPlainObject(raw)) throw new Error(`HIDDEN_BUNDLE_CHALLENGE_INVALID:${family}:${index}`);
      const keys = Object.keys(raw).sort();
      const expected = ["challenge_id", "max_output_bytes", "source", "timeout_seconds"];
      if (canonicalJson(keys) !== canonicalJson(expected)) throw new Error(`HIDDEN_BUNDLE_CHALLENGE_FIELDS_INVALID:${family}:${index}`);
      const challengeId = text(raw.challenge_id);
      const source = String(raw.source ?? "");
      const timeout = Number(raw.timeout_seconds);
      const outputLimit = Number(raw.max_output_bytes);
      if (!challengeId || challengeId.length > 200 || seen.has(challengeId)) throw new Error(`HIDDEN_BUNDLE_CHALLENGE_ID_INVALID:${family}`);
      if (!source || encoder.encode(source).byteLength > 200000) throw new Error(`HIDDEN_BUNDLE_SOURCE_INVALID:${family}:${challengeId}`);
      if (!Number.isSafeInteger(timeout) || timeout < 1 || timeout > 60) throw new Error(`HIDDEN_BUNDLE_TIMEOUT_INVALID:${family}:${challengeId}`);
      if (!Number.isSafeInteger(outputLimit) || outputLimit < 1024 || outputLimit > 200000) throw new Error(`HIDDEN_BUNDLE_OUTPUT_LIMIT_INVALID:${family}:${challengeId}`);
      seen.add(challengeId);
      return { challenge_id: challengeId, source, timeout_seconds: timeout, max_output_bytes: outputLimit };
    });
  }
  return { schema_version: 1, policy_id: POLICY_ID, families };
}

function randomIndex(limit: number): number {
  if (!Number.isSafeInteger(limit) || limit <= 0 || limit > 0xffffffff) throw new Error("RANDOM_LIMIT_INVALID");
  const ceiling = Math.floor(0x100000000 / limit) * limit;
  const word = new Uint32Array(1);
  do crypto.getRandomValues(word); while (word[0] >= ceiling);
  return word[0] % limit;
}

function sample<T>(items: T[], count: number): T[] {
  const pool = [...items];
  for (let i = pool.length - 1; i > 0; i -= 1) {
    const j = randomIndex(i + 1);
    [pool[i], pool[j]] = [pool[j], pool[i]];
  }
  return pool.slice(0, count);
}

Deno.serve(async (req: Request) => {
  try {
    if (req.method !== "POST") return response({ outcome: "BLOCKED", code: "METHOD_NOT_ALLOWED" }, 405);
    let body: Record<string, unknown>;
    try {
      const parsed = await req.json();
      if (!isPlainObject(parsed)) throw new Error("object required");
      body = parsed;
    } catch {
      return response({ outcome: "BLOCKED", code: "INVALID_JSON" }, 400);
    }
    if (body.action !== "get_oracle_v3") return response({ outcome: "BLOCKED", code: "ACTION_NOT_ALLOWED" }, 400);

    await authenticateGitHub(req, body);
    const bundle = await loadHiddenBundle();
    const bundleSha = await sha256(canonicalJson(bundle));
    const nonceSha = await sha256(text(body.nonce));

    const selected: Record<string, Challenge[]> = {};
    const selectionIds: Record<string, string[]> = {};
    for (const family of FAMILY_NAMES) {
      selected[family] = sample(bundle.families[family], FAMILY_COUNTS[family]);
      selectionIds[family] = selected[family].map((item) => item.challenge_id).sort();
    }

    const context = {
      repository: REPOSITORY,
      exact_head: text(body.head_sha),
      run_id: Number(body.run_id),
      run_attempt: Number(body.run_attempt),
      event_name: text(body.event_name),
      head_branch: text(body.head_branch),
      request_nonce_sha256: nonceSha,
      authority_bundle_sha256: bundleSha,
      selection_ids: selectionIds,
    };
    const challengeId = await sha256(canonicalJson({ context, purpose: "challenge-instance-v3" }));
    const generationCommitment = await sha256(canonicalJson({ context, challenge_id: challengeId, policy_id: POLICY_ID }));

    return response({
      outcome: "EXTERNAL_ORACLE_DELIVERED",
      schema_version: 3,
      broker: "supabase-edge",
      broker_version: "3",
      broker_policy_id: POLICY_ID,
      generator_mode: GENERATOR_MODE,
      authority_bundle_sha256: bundleSha,
      exact_head: text(body.head_sha),
      run_id: Number(body.run_id),
      run_attempt: Number(body.run_attempt),
      event_name: text(body.event_name),
      head_branch: text(body.head_branch),
      request_nonce_sha256: nonceSha,
      challenge_id: challengeId,
      generation_commitment: generationCommitment,
      families: selected,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(message.replace(/Bearer\s+\S+/g, "Bearer [REDACTED]"));
    const unauthorized = message.startsWith("GITHUB_") || message.startsWith("REQUEST_NONCE_");
    return response({ outcome: "BLOCKED", code: message.slice(0, 240) }, unauthorized ? 401 : 409);
  }
});
