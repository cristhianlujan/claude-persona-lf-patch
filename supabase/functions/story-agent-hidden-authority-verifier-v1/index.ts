import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createRemoteJWKSet, jwtVerify, type JWTPayload } from "npm:jose@6.0.11";

const ISSUER = "https://token.actions.githubusercontent.com";
const AUDIENCE = "story-agent-hidden-authority-v1";
const REPOSITORY = "cristhianlujan/libertad-financiera";
const REPOSITORY_ID = "1301234955";
const REF = "refs/heads/story-agent-f03-oidc-probe";
const WORKFLOW = "Story Agent F03 OIDC Probe";
const WORKFLOW_REF = `${REPOSITORY}/.github/workflows/story-agent-f03-oidc-probe.yml@${REF}`;
const JOB_WORKFLOW_REF = "cristhianlujan/programming-agent/.github/workflows/story-agent-hidden-authority-v1.yml@refs/heads/story-agent-f03-mutation-oracle-v1";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")?.trim() ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() ?? "";
if (!SUPABASE_URL || !SERVICE_ROLE_KEY) throw new Error("SUPABASE_RUNTIME_CREDENTIALS_MISSING");

const JWKS = createRemoteJWKSet(new URL(`${ISSUER}/.well-known/jwks`));
const HEX40 = /^[0-9a-f]{40}$/;
const HEX64 = /^[0-9a-f]{64}$/;

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

async function verifyOidc(req: Request): Promise<JWTPayload> {
  const authorization = req.headers.get("authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) throw new Error("OIDC_BEARER_MISSING");
  const token = authorization.slice(7).trim();
  if (!token) throw new Error("OIDC_BEARER_EMPTY");
  const { payload } = await jwtVerify(token, JWKS, {
    issuer: ISSUER,
    audience: AUDIENCE,
    algorithms: ["RS256"],
  });
  if (payload.repository !== REPOSITORY || String(payload.repository_id ?? "") !== REPOSITORY_ID) {
    throw new Error("F03_OIDC_REPOSITORY_MISMATCH");
  }
  if (payload.ref !== REF) throw new Error("F03_OIDC_REF_MISMATCH");
  if (payload.workflow !== WORKFLOW || payload.workflow_ref !== WORKFLOW_REF) {
    throw new Error("F03_OIDC_WORKFLOW_MISMATCH");
  }
  if (payload.job_workflow_ref !== JOB_WORKFLOW_REF) throw new Error("F03_OIDC_JOB_WORKFLOW_MISMATCH");
  if (!HEX40.test(String(payload.workflow_sha ?? "")) || !HEX40.test(String(payload.job_workflow_sha ?? ""))) {
    throw new Error("F03_OIDC_WORKFLOW_SHA_INVALID");
  }
  if (payload.event_name !== "push" || !payload.run_id || !payload.run_attempt) {
    throw new Error("F03_OIDC_RUN_BINDING_INVALID");
  }
  return payload;
}

async function rpc<T>(name: string, args: Record<string, unknown>): Promise<T> {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      apikey: SERVICE_ROLE_KEY,
      authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(args),
    signal: AbortSignal.timeout(20000),
  });
  const text = await r.text();
  if (!r.ok) throw new Error(`RPC_${name}_${r.status}:${text.slice(0, 500)}`);
  return (text ? JSON.parse(text) : null) as T;
}

function stringField(body: Record<string, unknown>, key: string): string {
  const value = body[key];
  return typeof value === "string" ? value : "";
}

Deno.serve(async (req: Request) => {
  try {
    if (req.method !== "POST") return response({ outcome: "BLOCKED", code: "METHOD_NOT_ALLOWED" }, 405);
    const claims = await verifyOidc(req);
    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      return response({ outcome: "BLOCKED", code: "INVALID_JSON" }, 400);
    }
    if (body.action !== "attest_f03_policy_v1") {
      return response({ outcome: "BLOCKED", code: "ACTION_NOT_ALLOWED" }, 400);
    }

    const taskId = Number(body.task_id);
    const mutationCount = Number(body.mutation_count);
    const killedCount = Number(body.killed_count);
    const taskSha = stringField(body, "task_sha256");
    const generationSourceSha = stringField(body, "generation_source_sha256");
    const selftestSha = stringField(body, "selftest_result_sha256");
    const seedCommitment = stringField(body, "seed_commitment");
    const caseManifestSha = stringField(body, "case_manifest_sha256");
    if (taskId !== 27 || !HEX64.test(taskSha) || !HEX64.test(generationSourceSha)) {
      return response({ outcome: "BLOCKED", code: "F03_TASK_BINDING_INVALID" }, 400);
    }
    if (body.engine !== "F03_OIDC_MUTATION_ORACLE_V1" || body.hidden_output !== "HASH_ONLY") {
      return response({ outcome: "BLOCKED", code: "F03_ORACLE_CONTRACT_INVALID" }, 400);
    }
    if (!HEX64.test(selftestSha) || !HEX64.test(seedCommitment) || !HEX64.test(caseManifestSha)) {
      return response({ outcome: "BLOCKED", code: "F03_SELFTEST_DIGEST_INVALID" }, 400);
    }
    if (!Number.isSafeInteger(mutationCount) || mutationCount < 8 || killedCount !== mutationCount) {
      return response({ outcome: "BLOCKED", code: "F03_MUTATION_SENSITIVITY_INVALID" }, 400);
    }

    const result = await rpc<Record<string, unknown>>("fn_record_f03_oidc_audit_verdict_v1", {
      p_task_id: taskId,
      p_task_sha256: taskSha,
      p_generation_source_sha256: generationSourceSha,
      p_job_workflow_ref: String(claims.job_workflow_ref),
      p_job_workflow_sha: String(claims.job_workflow_sha),
      p_github_repository: String(claims.repository),
      p_github_repository_id: String(claims.repository_id),
      p_github_ref: String(claims.ref),
      p_github_workflow: String(claims.workflow),
      p_github_workflow_ref: String(claims.workflow_ref),
      p_github_workflow_sha: String(claims.workflow_sha),
      p_run_id: Number(claims.run_id),
      p_run_attempt: Number(claims.run_attempt),
      p_event_name: String(claims.event_name),
      p_selftest_result_sha256: selftestSha,
      p_seed_commitment: seedCommitment,
      p_case_manifest_sha256: caseManifestSha,
      p_mutation_count: mutationCount,
      p_killed_count: killedCount,
    });
    if (result?.status !== "ATTESTED") throw new Error("F03_RECEIPT_RESULT_INVALID");
    return response({ outcome: "ATTESTED", result }, 201);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(message.replace(/Bearer\s+\S+/g, "Bearer [REDACTED]"));
    const unauthorized = message.startsWith("OIDC_") || message.startsWith("F03_OIDC_");
    return response({ outcome: "BLOCKED", code: message.slice(0, 500) }, unauthorized ? 401 : 409);
  }
});
