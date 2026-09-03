import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const ENDPOINT_VERSION = "v20-generic-profile-operation-resumer-source";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")?.trim() ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() ?? "";
const REPOSITORY = "cristhianlujan/claude-persona-lf-patch";
const LEGACY_CALLER_METHOD = "GITHUB_ACTIONS_OIDC_EXACT_PROFILE_GOV_V1";
const LEGACY_CALLER_WORKFLOW_REF = `${REPOSITORY}/.github/workflows/lf-profiles-governance-caller.yml@refs/heads/governance/profiles-unblock-secure-caller-20260901`;
const CUSTOMER_CALLER_METHOD = "GITHUB_ACTIONS_OIDC_EXACT_PROFILE_CREATOR_CUSTOMER_V1";
const CUSTOMER_CALLER_WORKFLOW_REF = `${REPOSITORY}/.github/workflows/lf-customer-profile-creator-governance-caller.yml@refs/heads/lf/profiles/profile-creator-customer-caller-20260902`;
const SUPPORTED_PROFILE_OPERATIONS = new Set(["CREACION_PERFIL_LF", "ACTUALIZACION_PERFIL_LF"]);

function responseHeaders(): HeadersInit {
  return { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", "x-content-type-options": "nosniff" };
}
function jsonResponse(body: unknown, status: number): Response { return new Response(JSON.stringify(body), { status, headers: responseHeaders() }); }
function constantTimeEqual(left: string, right: string): boolean {
  const a = new TextEncoder().encode(left); const b = new TextEncoder().encode(right); let diff = a.length ^ b.length; const size = Math.max(a.length, b.length);
  for (let i = 0; i < size; i += 1) diff |= (a[i % Math.max(a.length, 1)] ?? 0) ^ (b[i % Math.max(b.length, 1)] ?? 0);
  return diff === 0;
}
function requireServiceRole(req: Request): Response | null {
  if (!SERVICE_ROLE_KEY) return jsonResponse({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "SERVICE_ROLE_SECRET_UNAVAILABLE" }, 500);
  const match = (req.headers.get("authorization") ?? "").match(/^Bearer\s+(.+)$/i); const received = match?.[1]?.trim() ?? "";
  if (!received || !constantTimeEqual(received, SERVICE_ROLE_KEY)) return jsonResponse({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "SERVICE_ROLE_REQUIRED" }, 403);
  return null;
}

type Caller = { method?: unknown; repository?: unknown; workflow_ref?: unknown; run_id?: unknown; workflow_sha?: unknown; };
type ValidCaller = { method: string; repository: string; workflow_ref: string; run_id: string; workflow_sha: string; };
function validateCaller(value: unknown): { ok: true; caller: ValidCaller } | { ok: false; code: string } {
  if (!value || typeof value !== "object") return { ok: false, code: "GOVERNED_CALLER_MISSING" };
  const caller = value as Caller;
  if (caller.repository !== REPOSITORY) return { ok: false, code: "GOVERNED_CALLER_REPOSITORY_INVALID" };
  const method = typeof caller.method === "string" ? caller.method : "";
  const workflowRef = typeof caller.workflow_ref === "string" ? caller.workflow_ref : "";
  const legacy = method === LEGACY_CALLER_METHOD && workflowRef === LEGACY_CALLER_WORKFLOW_REF;
  const customer = method === CUSTOMER_CALLER_METHOD && workflowRef === CUSTOMER_CALLER_WORKFLOW_REF;
  if (!legacy && !customer) return { ok: false, code: method ? "GOVERNED_CALLER_WORKFLOW_INVALID" : "GOVERNED_CALLER_METHOD_INVALID" };
  if (typeof caller.run_id !== "string" || !/^\d+$/.test(caller.run_id)) return { ok: false, code: "GOVERNED_CALLER_RUN_ID_INVALID" };
  if (typeof caller.workflow_sha !== "string" || !/^[0-9a-f]{40}$/.test(caller.workflow_sha)) return { ok: false, code: "GOVERNED_CALLER_SHA_INVALID" };
  return { ok: true, caller: { method, repository: REPOSITORY, workflow_ref: workflowRef, run_id: caller.run_id, workflow_sha: caller.workflow_sha } };
}

async function request(path: string, init: RequestInit): Promise<{ status: number; payload: any }> {
  const response = await fetch(`${SUPABASE_URL}${path}`, { ...init, headers: { authorization: `Bearer ${SERVICE_ROLE_KEY}`, apikey: SERVICE_ROLE_KEY, "content-type": "application/json", ...(init.headers ?? {}) }, signal: AbortSignal.timeout(30000) });
  const text = await response.text(); let payload: any; try { payload = text ? JSON.parse(text) : null; } catch { payload = { raw: text.slice(0, 1000) }; }
  return { status: response.status, payload };
}
async function rpc(name: string, args: Record<string, unknown>): Promise<any> {
  const result = await request(`/rest/v1/rpc/${name}`, { method: "POST", body: JSON.stringify(args) });
  if (result.status < 200 || result.status >= 300) throw new Error(`RPC_${name}_${result.status}:${JSON.stringify(result.payload).slice(0, 1000)}`);
  return result.payload;
}
async function selectExecution(executionId: string): Promise<any | null> {
  const result = await request(`/rest/v1/lf_operation_execution?execution_id=eq.${encodeURIComponent(executionId)}&select=execution_id,operation_code,target_type,target_code,target_repo,target_path,status,manifest,updated_at`, { method: "GET" });
  if (result.status !== 200) throw new Error(`EXECUTION_READ_${result.status}:${JSON.stringify(result.payload).slice(0, 1000)}`);
  return Array.isArray(result.payload) && result.payload.length ? result.payload[0] : null;
}
async function selectInitStep(executionId: string): Promise<any | null> {
  const result = await request(`/rest/v1/lf_operation_execution_steps?execution_id=eq.${encodeURIComponent(executionId)}&step_order=eq.0&step_id=eq.init_execution&select=execution_id,step_order,step_id,status,evidence_ref,evidence_payload`, { method: "GET" });
  if (result.status !== 200) throw new Error(`STEP_READ_${result.status}:${JSON.stringify(result.payload).slice(0, 1000)}`);
  return Array.isArray(result.payload) && result.payload.length ? result.payload[0] : null;
}
async function selectProfileOperationSnapshot(execution: any): Promise<any> {
  const operationCode = String(execution.operation_code ?? "");
  if (!SUPPORTED_PROFILE_OPERATIONS.has(operationCode) || execution.target_type !== "PERFIL") throw new Error("PROFILE_OPERATION_NOT_SUPPORTED");

  const [stepsResult, recordedResult, contractsResult, bindingsResult, policyResult] = await Promise.all([
    request(`/rest/v1/lf_operation_steps?operation_code=eq.${encodeURIComponent(operationCode)}&active=eq.true&select=step_order,execution_order,step_id,required,evidence_required,source_path,source_sha&order=execution_order.asc`, { method: "GET" }),
    request(`/rest/v1/lf_operation_execution_steps?execution_id=eq.${encodeURIComponent(execution.execution_id)}&select=step_order,step_id,status,evidence_ref,observed_at&order=step_order.asc`, { method: "GET" }),
    request(`/rest/v1/lf_operation_step_contracts?operation_code=eq.${encodeURIComponent(operationCode)}&select=step_id,step_order,execution_order,status,resolver_ref,required_evidence_keys,next_if_pass,next_if_blocked,blocking_code`, { method: "GET" }),
    request(`/rest/v1/lf_operation_step_judge_bindings?operation_code=eq.${encodeURIComponent(operationCode)}&status=eq.ACTIVE_ENFORCEMENT&select=step_id,step_order,judge_code,clean_result_value,blocked_result_value,return_result_value,required_evidence_keys`, { method: "GET" }),
    request(`/rest/v1/v_lf_operation_policy_snapshot?operation_code=eq.${encodeURIComponent(operationCode)}&select=*`, { method: "GET" }),
  ]);
  for (const [name, result] of [["steps", stepsResult], ["recorded", recordedResult], ["contracts", contractsResult], ["bindings", bindingsResult], ["policies", policyResult]] as const) {
    if (result.status !== 200) throw new Error(`PROFILE_OPERATION_${name.toUpperCase()}_READ_${result.status}:${JSON.stringify(result.payload).slice(0, 800)}`);
  }
  const steps = Array.isArray(stepsResult.payload) ? stepsResult.payload : [];
  const recorded = Array.isArray(recordedResult.payload) ? recordedResult.payload : [];
  const contracts = Array.isArray(contractsResult.payload) ? contractsResult.payload : [];
  const bindings = Array.isArray(bindingsResult.payload) ? bindingsResult.payload : [];
  const policies = Array.isArray(policyResult.payload) ? policyResult.payload : [];
  const recordedById = new Map(recorded.map((row: any) => [row.step_id, row]));
  const contractById = new Map(contracts.map((row: any) => [row.step_id, row]));
  const bindingById = new Map(bindings.map((row: any) => [row.step_id, row]));

  let nextStep: any = null;
  for (const step of steps) {
    if (!step.required || recordedById.has(step.step_id)) continue;
    const contract = contractById.get(step.step_id);
    const binding = bindingById.get(step.step_id);
    if (!contract || !binding) throw new Error(`PROFILE_OPERATION_STEP_CONTRACT_OR_JUDGE_MISSING:${step.step_id}`);
    nextStep = {
      step_id: step.step_id,
      step_order: step.step_order,
      execution_order: step.execution_order,
      resolver_ref: contract.resolver_ref,
      required_evidence_keys: binding.required_evidence_keys ?? contract.required_evidence_keys ?? [],
      judge_code: binding.judge_code,
      clean_result_value: binding.clean_result_value,
      blocked_result_value: binding.blocked_result_value,
      return_result_value: binding.return_result_value,
      next_if_pass: contract.next_if_pass,
      next_if_blocked: contract.next_if_blocked,
    };
    break;
  }
  return {
    operation_code: operationCode,
    target_code: execution.target_code,
    target_path: execution.target_path,
    execution_status: execution.status,
    execution_updated_at: execution.updated_at,
    declared_step_count: steps.length,
    recorded_step_count: recorded.length,
    remaining_required_count: steps.filter((step: any) => step.required && !recordedById.has(step.step_id)).length,
    next_step: nextStep,
    policies,
  };
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return jsonResponse({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "METHOD_NOT_ALLOWED" }, 405);
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY) return jsonResponse({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "RUNTIME_CONFIG_MISSING" }, 500);
  const authFailure = requireServiceRole(req); if (authFailure) return authFailure;
  try {
    let body: Record<string, unknown>; try { body = await req.json(); } catch { return jsonResponse({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "INVALID_JSON" }, 400); }
    const callerValidation = validateCaller(body.caller); if (!callerValidation.ok) return jsonResponse({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: callerValidation.code }, 403);
    const caller = callerValidation.caller;

    if (body.action === "next_profile_operation_step_v1") {
      const executionId = typeof body.execution_id === "string" ? body.execution_id.trim() : "";
      if (!executionId || executionId.length > 180) return jsonResponse({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "EXECUTION_ID_INVALID" }, 400);
      const execution = await selectExecution(executionId);
      if (!execution || execution.target_type !== "PERFIL" || execution.target_repo !== REPOSITORY || !SUPPORTED_PROFILE_OPERATIONS.has(execution.operation_code)) {
        return jsonResponse({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "PROFILE_OPERATION_EXECUTION_IDENTITY_MISMATCH" }, 409);
      }
      const snapshot = await selectProfileOperationSnapshot(execution);
      return jsonResponse({ outcome: snapshot.next_step ? "NEXT_STEP_RESOLVED" : "NO_REQUIRED_STEP_REMAINING", endpoint_version: ENDPOINT_VERSION, execution_id: executionId, snapshot, write_executed: false }, 200);
    }

    if (body.action === "record_profile_operation_step_v1" || body.action === "record_profile_creation_step_v1") {
      const executionId = typeof body.execution_id === "string" ? body.execution_id.trim() : "";
      const stepId = typeof body.step_id === "string" ? body.step_id.trim() : "";
      const evidenceRef = typeof body.evidence_ref === "string" ? body.evidence_ref.trim() : "";
      const evidencePayload = body.evidence_payload && typeof body.evidence_payload === "object" && !Array.isArray(body.evidence_payload) ? body.evidence_payload as Record<string, unknown> : null;
      if (!executionId || executionId.length > 180) return jsonResponse({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "EXECUTION_ID_INVALID" }, 400);
      if (!/^[a-z0-9_]{2,80}$/.test(stepId) || !evidenceRef || !evidencePayload) return jsonResponse({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "STEP_EVIDENCE_INPUT_INVALID" }, 400);
      const execution = await selectExecution(executionId);
      if (!execution || execution.target_type !== "PERFIL" || execution.target_repo !== REPOSITORY || !SUPPORTED_PROFILE_OPERATIONS.has(execution.operation_code)) {
        return jsonResponse({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "PROFILE_OPERATION_EXECUTION_IDENTITY_MISMATCH" }, 409);
      }
      const snapshotBefore = await selectProfileOperationSnapshot(execution);
      if (!snapshotBefore.next_step || snapshotBefore.next_step.step_id !== stepId) {
        return jsonResponse({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "PROFILE_OPERATION_STEP_NOT_CURRENT", expected_step: snapshotBefore.next_step?.step_id ?? null, requested_step: stepId }, 409);
      }
      if (execution.operation_code === "ACTUALIZACION_PERFIL_LF") {
        return jsonResponse({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "UPDATE_OPERATION_CANONICAL_RECORDER_REQUIRED", operation_code: execution.operation_code, next_step: snapshotBefore.next_step, write_executed: false }, 409);
      }
      const identityMatches = execution.operation_code === "CREACION_PERFIL_LF" && execution.status === "IN_PROGRESS" && execution.manifest?.governed_caller_method === caller.method && execution.manifest?.caller_repository === caller.repository && execution.manifest?.caller_workflow_ref === caller.workflow_ref;
      if (!identityMatches) return jsonResponse({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "STEP_EXECUTION_IDENTITY_MISMATCH" }, 409);
      const result = await rpc("lf_record_creacion_perfil_step_v1", { p_execution_id: executionId, p_step_id: stepId, p_evidence_ref: evidenceRef, p_evidence_payload: evidencePayload, p_actor_execution_id: executionId });
      const executionAfter = await selectExecution(executionId);
      const snapshotAfter = executionAfter ? await selectProfileOperationSnapshot(executionAfter) : null;
      return jsonResponse({ outcome: result?.outcome ?? "BLOCKED", endpoint_version: ENDPOINT_VERSION, execution_id: executionId, operation_code: execution.operation_code, step_id: stepId, result, snapshot_after: snapshotAfter, github_write_executed: false }, result?.outcome === "STEP_RECORDED" ? 200 : 409);
    }

    if (body.action !== "initialize_profile_creation_v1") return jsonResponse({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "ACTION_NOT_ALLOWED" }, 400);
    const callerRequestId = typeof body.caller_request_id === "string" ? body.caller_request_id.toLowerCase() : "";
    const targetCode = typeof body.target_code === "string" ? body.target_code.trim().toUpperCase() : "";
    const profileSlug = typeof body.profile_slug === "string" ? body.profile_slug.trim().toLowerCase() : "";
    const targetRepo = typeof body.target_repo === "string" ? body.target_repo.trim() : "";
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(callerRequestId)) return jsonResponse({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "CALLER_REQUEST_ID_INVALID" }, 400);
    if (!/^PERFIL-[A-Z0-9][A-Z0-9-]{2,120}$/.test(targetCode)) return jsonResponse({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "TARGET_CODE_INVALID" }, 400);
    if (!/^[a-z0-9][a-z0-9_]{2,80}$/.test(profileSlug)) return jsonResponse({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "PROFILE_SLUG_INVALID" }, 400);
    if (targetRepo !== REPOSITORY) return jsonResponse({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "TARGET_REPOSITORY_INVALID" }, 400);
    const executionId = `EXEC-CREACION-PERFIL-LF-OIDC-${callerRequestId}`;
    const existing = await selectExecution(executionId);
    if (existing) {
      const step = await selectInitStep(executionId);
      const identityMatches = existing.operation_code === "CREACION_PERFIL_LF" && existing.target_type === "PERFIL" && existing.target_code === targetCode && existing.target_repo === REPOSITORY && existing.manifest?.governed_caller_method === caller.method && existing.manifest?.caller_workflow_ref === caller.workflow_ref;
      if (!identityMatches || !step || step.status !== "STEP_CLEAN_PASS") return jsonResponse({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "IDEMPOTENCY_IDENTITY_MISMATCH", execution: existing, init_step: step }, 409);
      return jsonResponse({ outcome: "INITIALIZED", endpoint_version: ENDPOINT_VERSION, replay: true, execution: existing, init_step: step, write_executed: false, github_write_executed: false, next_gate: "router" }, 200);
    }
    const router = await rpc("lf_router_resolve_v1", { p_request_text: `Crear perfil ${targetCode}`, p_target_hint: targetCode, p_action_hint: "PROFILE_CREATE", p_asset_type_hint: "PERFIL", p_distribution_mode: "ROUTER" });
    if (router?.status !== "READY_TO_EXECUTE" || router?.operation_code !== "CREACION_PERFIL_LF" || router?.action_code !== "PROFILE_CREATE") return jsonResponse({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "ROUTER_CREATION_NOT_AUTHORIZED", router, write_executed: false }, 409);
    if (router?.next_step?.step_id !== "init_execution") return jsonResponse({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "ROUTER_INIT_STEP_MISMATCH", router, write_executed: false }, 409);
    const manifest = { schema_version: 1, router: "ACT-0001", creator_asset: "ACT-0045", governed_caller_method: caller.method, caller_request_id: callerRequestId, caller_repository: caller.repository, caller_workflow_ref: caller.workflow_ref, caller_run_id: caller.run_id, caller_workflow_sha: caller.workflow_sha, scope: "INIT_AND_ORDERED_STEP_RECORDING", profile_slug: profileSlug, github_write_allowed: false, github_write_executed: false, runtime_enabled: false, automatic_impact_enabled: false, closure_allowed: false, blocked_from_closure: true, next_gate: "router" };
    const executionInsert = await request("/rest/v1/lf_operation_execution", { method: "POST", headers: { Prefer: "return=representation" }, body: JSON.stringify({ execution_id: executionId, operation_code: "CREACION_PERFIL_LF", target_type: "PERFIL", target_code: targetCode, target_repo: REPOSITORY, target_path: `profiles/${profileSlug}/SKILL.md`, status: "IN_PROGRESS", manifest, created_by_execution_id: executionId }) });
    if (executionInsert.status !== 201) throw new Error(`EXECUTION_INSERT_${executionInsert.status}:${JSON.stringify(executionInsert.payload).slice(0, 1000)}`);
    const evidenceRef = `github-actions://run/${caller.run_id}/profile-creator/init_execution`;
    const evidencePayload = { execution_row_created: true, execution_id: executionId, operation_code: "CREACION_PERFIL_LF", target_type: "PERFIL", status: "IN_PROGRESS", step_result: "STEP_CLEAN_PASS", blocking_codes: [], assertions_checked: ["execution_row_created", "operation_code_exact", "target_type_perfil", "status_in_progress"], hard_fails_checked: [], blocking_findings: [], return_to_worker_reasons: [], governed_caller_method: caller.method, caller_workflow_ref: caller.workflow_ref, caller_run_id: caller.run_id, caller_workflow_sha: caller.workflow_sha };
    const stepInsert = await request("/rest/v1/lf_operation_execution_steps", { method: "POST", headers: { Prefer: "return=representation" }, body: JSON.stringify({ execution_id: executionId, step_order: 0, step_id: "init_execution", status: "STEP_CLEAN_PASS", evidence_ref: evidenceRef, evidence_payload: evidencePayload, notes: "Governed OIDC caller initialized canonical CREACION_PERFIL_LF execution; no GitHub write performed.", created_by_execution_id: executionId }) });
    if (stepInsert.status !== 201) throw new Error(`INIT_STEP_INSERT_${stepInsert.status}:${JSON.stringify(stepInsert.payload).slice(0, 1200)}`);
    const execution = await selectExecution(executionId); const initStep = await selectInitStep(executionId);
    if (!execution || !initStep || execution.status !== "IN_PROGRESS" || initStep.status !== "STEP_CLEAN_PASS") throw new Error("INIT_EXECUTION_READBACK_FAILED");
    return jsonResponse({ outcome: "INITIALIZED", endpoint_version: ENDPOINT_VERSION, replay: false, execution, init_step: initStep, router: { status: router.status, operation_code: router.operation_code, action_code: router.action_code, next_step: router.next_step }, write_executed: false, github_write_executed: false, next_gate: "router" }, 201);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error); console.error(message.replace(/Bearer\s+\S+/g, "Bearer [REDACTED]"));
    return jsonResponse({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "PROFILE_CREATOR_RUNTIME_FAILED", detail: message.slice(0, 1500), write_executed: false }, 409);
  }
});
