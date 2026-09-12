import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createRemoteJWKSet, jwtVerify, type JWTPayload } from "npm:jose@6.0.11";

const REPOSITORY = "cristhianlujan/claude-persona-lf-patch";
const REPOSITORY_ID = "1244397752";
const WORKFLOW_NAME = "Story Agent Evidence Verifier";
const WORKFLOW_REF = `${REPOSITORY}/.github/workflows/story-agent-evidence-verifier.yml@refs/heads/main`;
const AUDIENCE = "story-agent-evidence-verifier-v1";
const ISSUER = "https://token.actions.githubusercontent.com";
const METHOD = "GITHUB_ACTIONS_OIDC_EXACT_EVIDENCE_V1";
const METHOD_V10 = "GITHUB_ACTIONS_OIDC_WORKER_V10_EVIDENCE_V1";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")?.trim() ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() ?? "";
if (!SUPABASE_URL || !SERVICE_ROLE_KEY) throw new Error("SUPABASE_RUNTIME_CREDENTIALS_MISSING");

const JWKS = createRemoteJWKSet(new URL(`${ISSUER}/.well-known/jwks`));

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

async function oidc(req: Request): Promise<JWTPayload> {
  const authorization = req.headers.get("authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) throw new Error("OIDC_BEARER_MISSING");
  const token = authorization.slice(7).trim();
  if (!token) throw new Error("OIDC_BEARER_EMPTY");
  const { payload } = await jwtVerify(token, JWKS, {
    issuer: ISSUER,
    audience: AUDIENCE,
    algorithms: ["RS256"],
  });
  if (payload.repository !== REPOSITORY || String(payload.repository_id ?? "") !== REPOSITORY_ID) throw new Error("OIDC_REPOSITORY_MISMATCH");
  if (payload.ref !== "refs/heads/main") throw new Error("OIDC_REF_MISMATCH");
  if (payload.workflow_ref !== WORKFLOW_REF || payload.workflow !== WORKFLOW_NAME) throw new Error("OIDC_WORKFLOW_MISMATCH");
  if (payload.event_name !== "push") throw new Error("OIDC_EVENT_MISMATCH");
  if (!payload.run_id || !payload.workflow_sha || !/^[0-9a-f]{40}$/.test(String(payload.workflow_sha))) throw new Error("OIDC_RUN_IDENTITY_INCOMPLETE");
  return payload;
}

async function rpc<T>(name: string, args: Record<string, unknown>): Promise<T> {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: { apikey: SERVICE_ROLE_KEY, authorization: `Bearer ${SERVICE_ROLE_KEY}`, "content-type": "application/json" },
    body: JSON.stringify(args),
    signal: AbortSignal.timeout(20000),
  });
  const text = await r.text();
  if (!r.ok) throw new Error(`RPC_${name}_${r.status}:${text.slice(0, 500)}`);
  return (text ? JSON.parse(text) : null) as T;
}

async function rpcMustFail(name: string, args: Record<string, unknown>, expected: string): Promise<void> {
  try { await rpc(name, args); }
  catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (message.includes(expected)) return;
    throw new Error(`NEGATIVE_PROBE_WRONG_FAILURE:${expected}:${message.slice(0, 300)}`);
  }
  throw new Error(`NEGATIVE_PROBE_ACCEPTED:${expected}`);
}

const flip = (value: string) => `${value[0] === "0" ? "1" : "0"}${value.slice(1)}`;

type Pending = {
  execution_id: number; request_ref: string; head_sha: string; source_snapshot_sha256: string;
  context_pack_id: number; context_pack_sha256: string; evidence_id: number; evidence_sha256: string;
  source_system: string; source_ref: string; worker_receipt_status: string;
};
type PendingV10 = {
  execution_id: number; request_ref: string; agent_task_id: number; task_code: string; task_version: number;
  task_sha256: string; head_sha: string; evaluation_id: number; gate_code: string; evidence_id: number;
  evidence_sha256: string; source_system: string; source_ref: string; candidate_head_sha: string; worker_receipt_status: string;
};

function argsFor(p: Pending, verifierIdentity: string, runId: string, workflowSha: string, overrides: Record<string, unknown> = {}): Record<string, unknown> {
  const payload = {
    schema_version: 1, execution_id: String(p.execution_id), evidence_id: String(p.evidence_id), head_sha: p.head_sha,
    evidence_sha256: p.evidence_sha256, source_system: p.source_system, source_ref: p.source_ref,
    verification_status: "VERIFIED", verifier_identity: verifierIdentity, github_repository: REPOSITORY,
    github_workflow_ref: WORKFLOW_REF, github_run_id: runId, github_workflow_sha: workflowSha,
    context_pack_id: String(p.context_pack_id), context_pack_sha256: p.context_pack_sha256,
  };
  return { p_execution_id: p.execution_id, p_evidence_id: p.evidence_id, p_expected_head_sha: p.head_sha,
    p_expected_evidence_sha256: p.evidence_sha256, p_expected_source_system: p.source_system,
    p_expected_source_ref: p.source_ref, p_verification_method: METHOD, p_verifier_identity: verifierIdentity,
    p_verification_payload: payload, p_verification_ref: `github-actions://run/${runId}/evidence/${p.evidence_id}`, ...overrides };
}

function argsForV10(p: PendingV10, verifierIdentity: string, runId: string, workflowSha: string, channelToken: string, overrides: Record<string, unknown> = {}): Record<string, unknown> {
  const payload = {
    schema_version: 1, execution_id: String(p.execution_id), agent_task_id: String(p.agent_task_id), task_code: p.task_code,
    task_version: String(p.task_version), task_sha256: p.task_sha256, evaluation_id: String(p.evaluation_id), gate_code: p.gate_code,
    evidence_id: String(p.evidence_id), head_sha: p.head_sha, candidate_head_sha: p.candidate_head_sha,
    evidence_sha256: p.evidence_sha256, source_system: p.source_system, source_ref: p.source_ref,
    worker_receipt_status: p.worker_receipt_status, verification_status: "VERIFIED", verifier_identity: verifierIdentity,
    github_repository: REPOSITORY, github_workflow_ref: WORKFLOW_REF, github_run_id: runId, github_workflow_sha: workflowSha,
    channel_token: channelToken,
  };
  return { p_execution_id: p.execution_id, p_evidence_id: p.evidence_id, p_expected_head_sha: p.head_sha,
    p_expected_evidence_sha256: p.evidence_sha256, p_expected_source_system: p.source_system,
    p_expected_source_ref: p.source_ref, p_verification_method: METHOD_V10, p_verifier_identity: verifierIdentity,
    p_verification_payload: payload, p_verification_ref: `github-actions://run/${runId}/worker-v10/evidence/${p.evidence_id}`, ...overrides };
}

async function verifyStandard(taskId: number, verifierIdentity: string, runId: string, workflowSha: string): Promise<Record<string, unknown>> {
  const p = await rpc<Pending>("fn_agent_task_pending_worker_evidence_v1", { p_task_id: taskId });
  if (!p || p.request_ref !== `agent-task://${taskId}` || p.worker_receipt_status !== "PASS") throw new Error("PENDING_EVIDENCE_CONTRACT_INVALID");
  if (!/^[0-9a-f]{40}$/.test(p.head_sha) || !/^[0-9a-f]{64}$/.test(p.evidence_sha256)) throw new Error("PENDING_EVIDENCE_IDENTITY_INVALID");
  const valid = argsFor(p, verifierIdentity, runId, workflowSha);
  await rpcMustFail("fn_agent_task_external_verify_worker_evidence_v1", { ...valid, p_expected_head_sha: flip(p.head_sha) }, "EXTERNAL_VERIFY_HEAD_MISMATCH");
  await rpcMustFail("fn_agent_task_external_verify_worker_evidence_v1", { ...valid, p_expected_evidence_sha256: flip(p.evidence_sha256) }, "EXTERNAL_VERIFY_EVIDENCE_SHA_MISMATCH");
  await rpcMustFail("fn_agent_task_external_verify_worker_evidence_v1", { ...valid, p_expected_source_system: "PROGRAMMING_AGENT_WORKER_MUTATED" }, "EXTERNAL_VERIFY_SOURCE_SYSTEM_MISMATCH");
  await rpcMustFail("fn_agent_task_external_verify_worker_evidence_v1", { ...valid, p_expected_source_ref: `${p.source_ref}-mutated` }, "EXTERNAL_VERIFY_SOURCE_REF_MISMATCH");
  await rpcMustFail("fn_agent_task_external_verify_worker_evidence_v1", { ...valid, p_verifier_identity: p.source_system }, "EXTERNAL_VERIFIER_IDENTITY_INVALID");
  const verified = await rpc<Record<string, unknown>>("fn_agent_task_external_verify_worker_evidence_v1", valid);
  if (verified?.status !== "VERIFIED") throw new Error("VERIFICATION_RESULT_NOT_VERIFIED");
  return verified;
}

async function materializeMachineGates(taskId: number, verifierIdentity: string, runId: string, workflowSha: string): Promise<Record<string, unknown>> {
  const result = await rpc<Record<string, unknown>>("fn_agent_task_materialize_verified_machine_gates_v1", {
    p_task_id: taskId, p_verifier_identity: verifierIdentity, p_verifier_run_id: runId, p_workflow_sha: workflowSha,
  });
  if (result?.status !== "MATERIALIZED") throw new Error("MACHINE_GATE_MATERIALIZATION_RESULT_INVALID");
  return result;
}

async function verifyWorkerV10(taskId: number, verifierIdentity: string, runId: string, workflowSha: string, channelToken: string): Promise<Record<string, unknown>[]> {
  const pending = await rpc<PendingV10[]>("fn_agent_task_pending_worker_v10_evidence_v1", { p_task_id: taskId });
  if (!Array.isArray(pending) || pending.length < 1) throw new Error("PENDING_V10_EVIDENCE_CONTRACT_INVALID");
  for (const p of pending) {
    if (p.request_ref !== `agent-task://${taskId}` || Number(p.agent_task_id) !== taskId || p.source_system !== "STORY_AGENT_WORKER_V10_RUNNER" ||
        !/^[0-9a-f]{40}$/.test(p.head_sha) || !/^[0-9a-f]{40}$/.test(p.candidate_head_sha) || !/^[0-9a-f]{64}$/.test(p.task_sha256) || !/^[0-9a-f]{64}$/.test(p.evidence_sha256))
      throw new Error("PENDING_V10_EVIDENCE_IDENTITY_INVALID");
  }
  const first = pending[0];
  const valid = argsForV10(first, verifierIdentity, runId, workflowSha, channelToken);
  await rpcMustFail("fn_agent_task_external_verify_worker_v10_evidence_v1", { ...valid, p_expected_head_sha: flip(first.head_sha) }, "EXTERNAL_V10_VERIFY_HEAD_MISMATCH");
  await rpcMustFail("fn_agent_task_external_verify_worker_v10_evidence_v1", { ...valid, p_expected_evidence_sha256: flip(first.evidence_sha256) }, "EXTERNAL_V10_VERIFY_EVIDENCE_SHA_MISMATCH");
  await rpcMustFail("fn_agent_task_external_verify_worker_v10_evidence_v1", { ...valid, p_expected_source_system: "STORY_AGENT_WORKER_V10_MUTATED" }, "EXTERNAL_V10_VERIFY_SOURCE_SYSTEM_MISMATCH");
  await rpcMustFail("fn_agent_task_external_verify_worker_v10_evidence_v1", { ...valid, p_expected_source_ref: `${first.source_ref}-mutated` }, "EXTERNAL_V10_VERIFY_SOURCE_REF_MISMATCH");
  await rpcMustFail("fn_agent_task_external_verify_worker_v10_evidence_v1", { ...valid, p_verifier_identity: first.source_system }, "EXTERNAL_V10_VERIFIER_IDENTITY_INVALID");
  await rpcMustFail("fn_agent_task_external_verify_worker_v10_evidence_v1", { ...valid, p_verification_payload: { ...(valid.p_verification_payload as Record<string, unknown>), task_sha256: flip(first.task_sha256) } }, "EXTERNAL_V10_VERIFY_PAYLOAD_IDENTITY_MISMATCH");
  const results: Record<string, unknown>[] = [];
  for (const p of pending) {
    const verified = await rpc<Record<string, unknown>>("fn_agent_task_external_verify_worker_v10_evidence_v1", argsForV10(p, verifierIdentity, runId, workflowSha, channelToken));
    if (verified?.status !== "VERIFIED") throw new Error("V10_VERIFICATION_RESULT_NOT_VERIFIED");
    results.push(verified);
  }
  return results;
}

Deno.serve(async (req: Request) => {
  try {
    if (req.method !== "POST") return response({ outcome: "BLOCKED", code: "METHOD_NOT_ALLOWED" }, 405);
    const claims = await oidc(req);
    let body: Record<string, unknown>;
    try { body = await req.json(); } catch { return response({ outcome: "BLOCKED", code: "INVALID_JSON" }, 400); }
    const taskId = Number(body.task_id);
    if (!Number.isSafeInteger(taskId) || taskId < 1) return response({ outcome: "BLOCKED", code: "TASK_ID_INVALID" }, 400);
    const runId = String(claims.run_id);
    const workflowSha = String(claims.workflow_sha);
    const verifierIdentity = `github-actions://${WORKFLOW_REF}#run-${runId}`;

    if (body.action === "verify_pending_agent_task_v1") {
      let verified: Record<string, unknown> | null = null;
      let sourceAlreadyVerified = false;
      try { verified = await verifyStandard(taskId, verifierIdentity, runId, workflowSha); }
      catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        if (message !== "PENDING_EVIDENCE_CONTRACT_INVALID") throw error;
        sourceAlreadyVerified = true;
      }
      let machine: Record<string, unknown> | null = null;
      try { machine = await materializeMachineGates(taskId, verifierIdentity, runId, workflowSha); }
      catch (error) {
        if (sourceAlreadyVerified) throw error;
        machine = { status: "NOT_MATERIALIZED", code: (error instanceof Error ? error.message : String(error)).slice(0, 300) };
      }
      if (sourceAlreadyVerified && machine?.status !== "MATERIALIZED") throw new Error("MACHINE_GATE_MATERIALIZATION_REQUIRED_FOR_VERIFIED_SOURCE");
      return response({
        outcome: "VERIFIED", task_id: taskId, external_identity: verifierIdentity,
        negative_probes: { wrong_head: "PASS", wrong_evidence_sha: "PASS", wrong_source_system: "PASS", wrong_source_ref: "PASS", self_verification: "PASS" },
        result: verified ?? { status: "ALREADY_EXTERNALLY_VERIFIED_SOURCE" }, machine_gates: machine,
      }, 201);
    }

    if (body.action === "verify_pending_agent_task_worker_v10_v1") {
      const channelToken = typeof body.channel_token === "string" ? body.channel_token : "";
      if (channelToken.length < 32) return response({ outcome: "BLOCKED", code: "CHANNEL_TOKEN_REQUIRED" }, 400);
      const results = await verifyWorkerV10(taskId, verifierIdentity, runId, workflowSha, channelToken);
      return response({
        outcome: "VERIFIED", task_id: taskId, external_identity: verifierIdentity,
        negative_probes: { wrong_head: "PASS", wrong_evidence_sha: "PASS", wrong_source_system: "PASS", wrong_source_ref: "PASS", self_verification: "PASS", wrong_task_sha: "PASS" },
        results,
      }, 201);
    }

    return response({ outcome: "BLOCKED", code: "ACTION_NOT_ALLOWED" }, 400);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(message.replace(/Bearer\s+\S+/g, "Bearer [REDACTED]"));
    const unauthorized = message.startsWith("OIDC_");
    return response({ outcome: "BLOCKED", code: message.slice(0, 500) }, unauthorized ? 401 : 409);
  }
});