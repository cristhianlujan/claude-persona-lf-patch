import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createRemoteJWKSet, jwtVerify, type JWTPayload } from "npm:jose@6.0.11";

const REPOSITORY = "cristhianlujan/claude-persona-lf-patch";
const REPOSITORY_ID = "1244397752";
const WORKFLOW_NAME = "Story Agent Evidence Verifier";
const WORKFLOW_REF = `${REPOSITORY}/.github/workflows/story-agent-evidence-verifier.yml@refs/heads/main`;
const AUDIENCE = "story-agent-evidence-verifier-v1";
const ISSUER = "https://token.actions.githubusercontent.com";
const TASK_ID = 21;
const METHOD = "GITHUB_ACTIONS_OIDC_EXACT_EVIDENCE_V1";
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
  if (payload.repository !== REPOSITORY || String(payload.repository_id ?? "") !== REPOSITORY_ID) {
    throw new Error("OIDC_REPOSITORY_MISMATCH");
  }
  if (payload.ref !== "refs/heads/main") throw new Error("OIDC_REF_MISMATCH");
  if (payload.workflow_ref !== WORKFLOW_REF || payload.workflow !== WORKFLOW_NAME) {
    throw new Error("OIDC_WORKFLOW_MISMATCH");
  }
  if (payload.event_name !== "push") throw new Error("OIDC_EVENT_MISMATCH");
  if (!payload.run_id || !payload.workflow_sha || !/^[0-9a-f]{40}$/.test(String(payload.workflow_sha))) {
    throw new Error("OIDC_RUN_IDENTITY_INCOMPLETE");
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

async function rpcMustFail(name: string, args: Record<string, unknown>, expected: string): Promise<void> {
  try {
    await rpc(name, args);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (message.includes(expected)) return;
    throw new Error(`NEGATIVE_PROBE_WRONG_FAILURE:${expected}:${message.slice(0, 300)}`);
  }
  throw new Error(`NEGATIVE_PROBE_ACCEPTED:${expected}`);
}

function isExpectedNoPending(error: unknown, marker: string): boolean {
  const message = error instanceof Error ? error.message : String(error);
  return message.includes(marker);
}

function flip(value: string): string {
  if (!value) return value;
  return `${value[0] === "0" ? "1" : "0"}${value.slice(1)}`;
}

type PendingLegacy = {
  execution_id: number;
  request_ref: string;
  head_sha: string;
  source_snapshot_sha256: string;
  context_pack_id: number;
  context_pack_sha256: string;
  evidence_id: number;
  evidence_sha256: string;
  source_system: string;
  source_ref: string;
  worker_receipt_status: string;
};

type PendingV10 = {
  execution_id: number;
  head_sha: string;
  receipt_sha256: string;
  source_ref: string;
  source_system: string;
  evidence_ids: Record<string, number>;
  gate_count: number;
};

function legacyArgs(
  pending: PendingLegacy,
  verifierIdentity: string,
  runId: string,
  workflowSha: string,
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  const payload = {
    schema_version: 1,
    execution_id: String(pending.execution_id),
    evidence_id: String(pending.evidence_id),
    head_sha: pending.head_sha,
    evidence_sha256: pending.evidence_sha256,
    source_system: pending.source_system,
    source_ref: pending.source_ref,
    verification_status: "VERIFIED",
    verifier_identity: verifierIdentity,
    github_repository: REPOSITORY,
    github_workflow_ref: WORKFLOW_REF,
    github_run_id: runId,
    github_workflow_sha: workflowSha,
    context_pack_id: String(pending.context_pack_id),
    context_pack_sha256: pending.context_pack_sha256,
  };
  const base: Record<string, unknown> = {
    p_execution_id: pending.execution_id,
    p_evidence_id: pending.evidence_id,
    p_expected_head_sha: pending.head_sha,
    p_expected_evidence_sha256: pending.evidence_sha256,
    p_expected_source_system: pending.source_system,
    p_expected_source_ref: pending.source_ref,
    p_verification_method: METHOD,
    p_verifier_identity: verifierIdentity,
    p_verification_payload: payload,
    p_verification_ref: `github-actions://run/${runId}/evidence/${pending.evidence_id}`,
  };
  return { ...base, ...overrides };
}

function v10Args(
  pending: PendingV10,
  verifierIdentity: string,
  runId: string,
  workflowSha: string,
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  const payload = {
    schema_version: 1,
    task_id: String(TASK_ID),
    execution_id: String(pending.execution_id),
    head_sha: pending.head_sha,
    receipt_sha256: pending.receipt_sha256,
    source_system: pending.source_system,
    source_ref: pending.source_ref,
    evidence_ids: pending.evidence_ids,
    verification_status: "VERIFIED",
    verifier_identity: verifierIdentity,
    github_repository: REPOSITORY,
    github_workflow_ref: WORKFLOW_REF,
    github_run_id: runId,
    github_workflow_sha: workflowSha,
  };
  const base: Record<string, unknown> = {
    p_task_id: TASK_ID,
    p_expected_execution_id: pending.execution_id,
    p_expected_head_sha: pending.head_sha,
    p_expected_receipt_sha256: pending.receipt_sha256,
    p_expected_source_ref: pending.source_ref,
    p_verification_method: METHOD,
    p_verifier_identity: verifierIdentity,
    p_verification_payload: payload,
    p_verification_ref: `github-actions://run/${runId}/worker-v10/${pending.receipt_sha256}`,
  };
  return { ...base, ...overrides };
}

async function verifyLegacy(claims: JWTPayload): Promise<Response | null> {
  let pending: PendingLegacy;
  try {
    pending = await rpc<PendingLegacy>("fn_agent_task_pending_worker_evidence_v1", { p_task_id: TASK_ID });
  } catch (error) {
    if (isExpectedNoPending(error, "PENDING_WORKER_EVIDENCE_NOT_FOUND")) return null;
    throw error;
  }
  if (!pending || pending.request_ref !== `agent-task://${TASK_ID}` || pending.worker_receipt_status !== "PASS") {
    throw new Error("PENDING_EVIDENCE_CONTRACT_INVALID");
  }
  if (!/^[0-9a-f]{40}$/.test(pending.head_sha) || !/^[0-9a-f]{64}$/.test(pending.evidence_sha256)) {
    throw new Error("PENDING_EVIDENCE_IDENTITY_INVALID");
  }

  const runId = String(claims.run_id);
  const workflowSha = String(claims.workflow_sha);
  const verifierIdentity = `github-actions://${WORKFLOW_REF}#run-${runId}`;
  const valid = legacyArgs(pending, verifierIdentity, runId, workflowSha);

  await rpcMustFail("fn_agent_task_external_verify_worker_evidence_v1", {
    ...valid,
    p_expected_head_sha: flip(pending.head_sha),
  }, "EXTERNAL_VERIFY_HEAD_MISMATCH");
  await rpcMustFail("fn_agent_task_external_verify_worker_evidence_v1", {
    ...valid,
    p_expected_evidence_sha256: flip(pending.evidence_sha256),
  }, "EXTERNAL_VERIFY_EVIDENCE_SHA_MISMATCH");
  await rpcMustFail("fn_agent_task_external_verify_worker_evidence_v1", {
    ...valid,
    p_expected_source_system: "PROGRAMMING_AGENT_WORKER_MUTATED",
  }, "EXTERNAL_VERIFY_SOURCE_SYSTEM_MISMATCH");
  await rpcMustFail("fn_agent_task_external_verify_worker_evidence_v1", {
    ...valid,
    p_expected_source_ref: `${pending.source_ref}-mutated`,
  }, "EXTERNAL_VERIFY_SOURCE_REF_MISMATCH");
  await rpcMustFail("fn_agent_task_external_verify_worker_evidence_v1", {
    ...valid,
    p_verifier_identity: pending.source_system,
  }, "EXTERNAL_VERIFIER_IDENTITY_INVALID");

  const verified = await rpc<Record<string, unknown>>("fn_agent_task_external_verify_worker_evidence_v1", valid);
  if (verified?.status !== "VERIFIED") throw new Error("VERIFICATION_RESULT_NOT_VERIFIED");
  return response({
    outcome: "VERIFIED",
    mode: "legacy",
    task_id: TASK_ID,
    external_identity: verifierIdentity,
    negative_probes: {
      wrong_head: "PASS",
      wrong_evidence_sha: "PASS",
      wrong_source_system: "PASS",
      wrong_source_ref: "PASS",
      self_verification: "PASS",
    },
    result: verified,
  }, 201);
}

async function verifyV10(claims: JWTPayload): Promise<Response | null> {
  let pending: PendingV10;
  try {
    pending = await rpc<PendingV10>("fn_agent_task_pending_worker_v10_evidence_v1", { p_task_id: TASK_ID });
  } catch (error) {
    if (isExpectedNoPending(error, "PENDING_WORKER_V10_EVIDENCE_NOT_FOUND")) return null;
    throw error;
  }

  const expectedGates = new Set([
    "G_WORKER_SOURCE_IDENTITY",
    "G_WORKER_PATCH_POLICY",
    "G_WORKER_ACCEPTANCE",
    "G_WORKER_DELIVERY_BOUNDARY",
  ]);
  if (!pending || pending.gate_count !== 4 || pending.source_system !== "STORY_AGENT_WORKER_V10_RUNNER") {
    throw new Error("PENDING_WORKER_V10_CONTRACT_INVALID");
  }
  if (!/^[0-9a-f]{40}$/.test(pending.head_sha) || !/^[0-9a-f]{64}$/.test(pending.receipt_sha256)) {
    throw new Error("PENDING_WORKER_V10_IDENTITY_INVALID");
  }
  if (!pending.evidence_ids || typeof pending.evidence_ids !== "object") {
    throw new Error("PENDING_WORKER_V10_EVIDENCE_IDS_INVALID");
  }
  const gateNames = Object.keys(pending.evidence_ids);
  if (gateNames.length !== expectedGates.size || gateNames.some((name) => !expectedGates.has(name))) {
    throw new Error("PENDING_WORKER_V10_GATE_SET_INVALID");
  }

  const runId = String(claims.run_id);
  const workflowSha = String(claims.workflow_sha);
  const verifierIdentity = `github-actions://${WORKFLOW_REF}#run-${runId}`;
  const valid = v10Args(pending, verifierIdentity, runId, workflowSha);

  await rpcMustFail("fn_agent_task_external_verify_worker_v10_evidence_v1", {
    ...valid,
    p_expected_execution_id: pending.execution_id + 1000000,
  }, "WORKER_V10_EXTERNAL_EXECUTION_INVALID");
  await rpcMustFail("fn_agent_task_external_verify_worker_v10_evidence_v1", {
    ...valid,
    p_expected_head_sha: flip(pending.head_sha),
  }, "WORKER_V10_EXTERNAL_HEAD_MISMATCH");
  const wrongReceipt = flip(pending.receipt_sha256);
  await rpcMustFail("fn_agent_task_external_verify_worker_v10_evidence_v1", {
    ...v10Args(pending, verifierIdentity, runId, workflowSha, {
      p_expected_receipt_sha256: wrongReceipt,
    }),
    p_verification_payload: {
      ...(valid.p_verification_payload as Record<string, unknown>),
      receipt_sha256: wrongReceipt,
    },
  }, "WORKER_V10_EXTERNAL_GATE_SET_INCOMPLETE");
  const wrongSourceRef = `${pending.source_ref}-mutated`;
  await rpcMustFail("fn_agent_task_external_verify_worker_v10_evidence_v1", {
    ...v10Args(pending, verifierIdentity, runId, workflowSha, {
      p_expected_source_ref: wrongSourceRef,
    }),
    p_verification_payload: {
      ...(valid.p_verification_payload as Record<string, unknown>),
      source_ref: wrongSourceRef,
    },
  }, "WORKER_V10_EXTERNAL_GATE_SET_INCOMPLETE");
  await rpcMustFail("fn_agent_task_external_verify_worker_v10_evidence_v1", {
    ...valid,
    p_verifier_identity: pending.source_system,
  }, "WORKER_V10_EXTERNAL_VERIFIER_IDENTITY_INVALID");

  const verified = await rpc<Record<string, unknown>>("fn_agent_task_external_verify_worker_v10_evidence_v1", valid);
  if (verified?.status !== "VERIFIED_PASS" && verified?.status !== "VERIFIED_NONPASS") {
    throw new Error("WORKER_V10_VERIFICATION_RESULT_INVALID");
  }
  return response({
    outcome: "VERIFIED",
    mode: "worker_v10",
    task_id: TASK_ID,
    external_identity: verifierIdentity,
    negative_probes: {
      wrong_execution: "PASS",
      wrong_head: "PASS",
      wrong_receipt_sha: "PASS",
      wrong_source_ref: "PASS",
      self_verification: "PASS",
    },
    result: verified,
  }, 201);
}

Deno.serve(async (req: Request) => {
  try {
    if (req.method !== "POST") return response({ outcome: "BLOCKED", code: "METHOD_NOT_ALLOWED" }, 405);
    const claims = await oidc(req);
    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      return response({ outcome: "BLOCKED", code: "INVALID_JSON" }, 400);
    }
    if (Number(body.task_id) !== TASK_ID) {
      return response({ outcome: "BLOCKED", code: "TASK_NOT_ALLOWED" }, 400);
    }

    if (body.action === "verify_pending_agent_task_v1") {
      const legacy = await verifyLegacy(claims);
      if (legacy) return legacy;
      return response({ outcome: "NO_PENDING_EVIDENCE", mode: "legacy", task_id: TASK_ID }, 200);
    }

    if (body.action === "verify_pending_agent_task_worker_v10_v1") {
      const v10 = await verifyV10(claims);
      if (v10) return v10;
      return response({ outcome: "NO_PENDING_EVIDENCE", mode: "worker_v10", task_id: TASK_ID }, 200);
    }

    if (body.action === "verify_pending_agent_task_any_v2") {
      const v10 = await verifyV10(claims);
      if (v10) return v10;
      const legacy = await verifyLegacy(claims);
      if (legacy) return legacy;
      return response({ outcome: "NO_PENDING_EVIDENCE", mode: "none", task_id: TASK_ID }, 200);
    }

    return response({ outcome: "BLOCKED", code: "ACTION_NOT_ALLOWED" }, 400);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(message.replace(/Bearer\s+\S+/g, "Bearer [REDACTED]"));
    const unauthorized = message.startsWith("OIDC_");
    return response({ outcome: "BLOCKED", code: message.slice(0, 500) }, unauthorized ? 401 : 409);
  }
});
