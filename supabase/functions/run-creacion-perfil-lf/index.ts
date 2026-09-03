import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const ENDPOINT_VERSION = "v20-generic-profile-operation-resumer-source";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")?.trim() ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() ?? "";
const REPOSITORY = "cristhianlujan/claude-persona-lf-patch";
const LEGACY_CALLER_METHOD = "GITHUB_ACTIONS_OIDC_EXACT_PROFILE_GOV_V1";
const LEGACY_WORKFLOW = `${REPOSITORY}/.github/workflows/lf-profiles-governance-caller.yml@refs/heads/governance/profiles-unblock-secure-caller-20260901`;
const CUSTOMER_CALLER_METHOD = "GITHUB_ACTIONS_OIDC_EXACT_PROFILE_CREATOR_CUSTOMER_V1";
const CUSTOMER_WORKFLOW = `${REPOSITORY}/.github/workflows/lf-customer-profile-creator-governance-caller.yml@refs/heads/lf/profiles/profile-creator-customer-caller-20260902`;
const PROFILE_OPERATIONS = new Set(["CREACION_PERFIL_LF", "ACTUALIZACION_PERFIL_LF"]);

function headers(): HeadersInit { return { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", "x-content-type-options": "nosniff" }; }
function json(body: unknown, status: number): Response { return new Response(JSON.stringify(body), { status, headers: headers() }); }
function constantTimeEqual(left: string, right: string): boolean {
  const a = new TextEncoder().encode(left), b = new TextEncoder().encode(right); let diff = a.length ^ b.length;
  for (let i = 0, size = Math.max(a.length, b.length); i < size; i++) diff |= (a[i % Math.max(a.length, 1)] ?? 0) ^ (b[i % Math.max(b.length, 1)] ?? 0);
  return diff === 0;
}
function requireServiceRole(req: Request): Response | null {
  if (!SERVICE_ROLE_KEY) return json({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "SERVICE_ROLE_SECRET_UNAVAILABLE" }, 500);
  const received = (req.headers.get("authorization") ?? "").match(/^Bearer\s+(.+)$/i)?.[1]?.trim() ?? "";
  return received && constantTimeEqual(received, SERVICE_ROLE_KEY) ? null : json({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "SERVICE_ROLE_REQUIRED" }, 403);
}

type Caller = { method?: unknown; repository?: unknown; workflow_ref?: unknown; run_id?: unknown; workflow_sha?: unknown };
type ValidCaller = { method: string; repository: string; workflow_ref: string; run_id: string; workflow_sha: string };
function validateCaller(value: unknown): { ok: true; caller: ValidCaller } | { ok: false; code: string } {
  if (!value || typeof value !== "object") return { ok: false, code: "GOVERNED_CALLER_MISSING" };
  const c = value as Caller; if (c.repository !== REPOSITORY) return { ok: false, code: "GOVERNED_CALLER_REPOSITORY_INVALID" };
  const method = typeof c.method === "string" ? c.method : "", workflow = typeof c.workflow_ref === "string" ? c.workflow_ref : "";
  if (!((method === LEGACY_CALLER_METHOD && workflow === LEGACY_WORKFLOW) || (method === CUSTOMER_CALLER_METHOD && workflow === CUSTOMER_WORKFLOW))) return { ok: false, code: "GOVERNED_CALLER_WORKFLOW_INVALID" };
  if (typeof c.run_id !== "string" || !/^\d+$/.test(c.run_id)) return { ok: false, code: "GOVERNED_CALLER_RUN_ID_INVALID" };
  if (typeof c.workflow_sha !== "string" || !/^[0-9a-f]{40}$/.test(c.workflow_sha)) return { ok: false, code: "GOVERNED_CALLER_SHA_INVALID" };
  return { ok: true, caller: { method, repository: REPOSITORY, workflow_ref: workflow, run_id: c.run_id, workflow_sha: c.workflow_sha } };
}
async function request(path: string, init: RequestInit): Promise<{ status: number; payload: any }> {
  const response = await fetch(`${SUPABASE_URL}${path}`, { ...init, headers: { authorization: `Bearer ${SERVICE_ROLE_KEY}`, apikey: SERVICE_ROLE_KEY, "content-type": "application/json", ...(init.headers ?? {}) }, signal: AbortSignal.timeout(30000) });
  const text = await response.text(); let payload: any; try { payload = text ? JSON.parse(text) : null; } catch { payload = { raw: text.slice(0, 1000) }; }
  return { status: response.status, payload };
}
async function rpc(name: string, args: Record<string, unknown>): Promise<any> {
  const r = await request(`/rest/v1/rpc/${name}`, { method: "POST", body: JSON.stringify(args) });
  if (r.status < 200 || r.status >= 300) throw new Error(`RPC_${name}_${r.status}:${JSON.stringify(r.payload).slice(0, 1000)}`); return r.payload;
}
async function one(path: string, label: string): Promise<any | null> {
  const r = await request(path, { method: "GET" }); if (r.status !== 200) throw new Error(`${label}_${r.status}:${JSON.stringify(r.payload).slice(0, 800)}`);
  return Array.isArray(r.payload) && r.payload.length ? r.payload[0] : null;
}
async function execution(id: string): Promise<any | null> {
  return one(`/rest/v1/lf_operation_execution?execution_id=eq.${encodeURIComponent(id)}&select=execution_id,operation_code,target_type,target_code,target_repo,target_path,status,manifest,updated_at`, "EXECUTION_READ");
}
async function initStep(id: string): Promise<any | null> {
  return one(`/rest/v1/lf_operation_execution_steps?execution_id=eq.${encodeURIComponent(id)}&step_order=eq.0&step_id=eq.init_execution&select=execution_id,step_order,step_id,status,evidence_ref,evidence_payload`, "INIT_STEP_READ");
}
async function rows(path: string, label: string): Promise<any[]> {
  const r = await request(path, { method: "GET" }); if (r.status !== 200) throw new Error(`${label}_${r.status}:${JSON.stringify(r.payload).slice(0, 800)}`); return Array.isArray(r.payload) ? r.payload : [];
}

async function operationSnapshot(ex: any): Promise<any> {
  const op = String(ex.operation_code ?? "");
  if (!PROFILE_OPERATIONS.has(op) || ex.target_type !== "PERFIL") throw new Error("PROFILE_OPERATION_NOT_SUPPORTED");
  const [steps, recorded, contracts, bindings, policies] = await Promise.all([
    rows(`/rest/v1/lf_operation_steps?operation_code=eq.${encodeURIComponent(op)}&active=eq.true&select=step_order,execution_order,step_id,required,evidence_required&order=execution_order.asc`, "OP_STEPS_READ"),
    rows(`/rest/v1/lf_operation_execution_steps?execution_id=eq.${encodeURIComponent(ex.execution_id)}&select=step_order,step_id,status,evidence_ref,observed_at&order=step_order.asc`, "RECORDED_STEPS_READ"),
    rows(`/rest/v1/lf_operation_step_contracts?operation_code=eq.${encodeURIComponent(op)}&select=step_id,step_order,execution_order,status,resolver_ref,required_evidence_keys,next_if_pass,next_if_blocked,blocking_code`, "STEP_CONTRACTS_READ"),
    rows(`/rest/v1/lf_operation_step_judge_bindings?operation_code=eq.${encodeURIComponent(op)}&status=eq.ACTIVE_ENFORCEMENT&select=step_id,step_order,judge_code,clean_result_value,blocked_result_value,return_result_value,required_evidence_keys`, "JUDGE_BINDINGS_READ"),
    rows(`/rest/v1/v_lf_operation_policy_snapshot?operation_code=eq.${encodeURIComponent(op)}&select=*`, "POLICY_SNAPSHOT_READ"),
  ]);
  const rec = new Map(recorded.map((r: any) => [r.step_id, r])), contractsBy = new Map(contracts.map((r: any) => [r.step_id, r])), bindingsBy = new Map(bindings.map((r: any) => [r.step_id, r]));
  let next: any = null;
  for (const s of steps) {
    if (!s.required || rec.has(s.step_id)) continue;
    const c = contractsBy.get(s.step_id), b = bindingsBy.get(s.step_id);
    if (!c || !b) throw new Error(`PROFILE_OPERATION_STEP_CONTRACT_OR_JUDGE_MISSING:${s.step_id}`);
    next = { step_id: s.step_id, step_order: s.step_order, execution_order: s.execution_order, resolver_ref: c.resolver_ref, required_evidence_keys: b.required_evidence_keys ?? c.required_evidence_keys ?? [], judge_code: b.judge_code, clean_result_value: b.clean_result_value, blocked_result_value: b.blocked_result_value, return_result_value: b.return_result_value, next_if_pass: c.next_if_pass, next_if_blocked: c.next_if_blocked }; break;
  }
  return { operation_code: op, target_code: ex.target_code, target_path: ex.target_path, execution_status: ex.status, execution_updated_at: ex.updated_at, declared_step_count: steps.length, recorded_step_count: recorded.length, remaining_required_count: steps.filter((s: any) => s.required && !rec.has(s.step_id)).length, next_step: next, policies };
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "METHOD_NOT_ALLOWED" }, 405);
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY) return json({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "RUNTIME_CONFIG_MISSING" }, 500);
  const auth = requireServiceRole(req); if (auth) return auth;
  try {
    let body: Record<string, unknown>; try { body = await req.json(); } catch { return json({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "INVALID_JSON" }, 400); }
    const cv = validateCaller(body.caller); if (!cv.ok) return json({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: cv.code }, 403); const caller = cv.caller;

    if (body.action === "next_profile_operation_step_v1") {
      const id = typeof body.execution_id === "string" ? body.execution_id.trim() : ""; if (!id || id.length > 180) return json({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "EXECUTION_ID_INVALID" }, 400);
      const ex = await execution(id); if (!ex || ex.target_type !== "PERFIL" || ex.target_repo !== REPOSITORY || !PROFILE_OPERATIONS.has(ex.operation_code)) return json({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "PROFILE_OPERATION_EXECUTION_IDENTITY_MISMATCH" }, 409);
      const snapshot = await operationSnapshot(ex); return json({ outcome: snapshot.next_step ? "NEXT_STEP_RESOLVED" : "NO_REQUIRED_STEP_REMAINING", endpoint_version: ENDPOINT_VERSION, execution_id: id, snapshot, write_executed: false }, 200);
    }

    if (body.action === "record_profile_operation_step_v1" || body.action === "record_profile_creation_step_v1") {
      const id = typeof body.execution_id === "string" ? body.execution_id.trim() : "", stepId = typeof body.step_id === "string" ? body.step_id.trim() : "", evidenceRef = typeof body.evidence_ref === "string" ? body.evidence_ref.trim() : "";
      const evidence = body.evidence_payload && typeof body.evidence_payload === "object" && !Array.isArray(body.evidence_payload) ? body.evidence_payload as Record<string, unknown> : null;
      if (!id || id.length > 180 || !/^[a-z0-9_]{2,80}$/.test(stepId) || !evidenceRef || !evidence) return json({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "STEP_EVIDENCE_INPUT_INVALID" }, 400);
      const ex = await execution(id); if (!ex || ex.target_type !== "PERFIL" || ex.target_repo !== REPOSITORY || !PROFILE_OPERATIONS.has(ex.operation_code)) return json({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "PROFILE_OPERATION_EXECUTION_IDENTITY_MISMATCH" }, 409);
      const before = await operationSnapshot(ex); if (!before.next_step || before.next_step.step_id !== stepId) return json({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "PROFILE_OPERATION_STEP_NOT_CURRENT", expected_step: before.next_step?.step_id ?? null, requested_step: stepId }, 409);
      if (ex.operation_code === "ACTUALIZACION_PERFIL_LF") return json({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "UPDATE_OPERATION_CANONICAL_RECORDER_REQUIRED", operation_code: ex.operation_code, next_step: before.next_step, write_executed: false }, 409);
      const identity = ex.status === "IN_PROGRESS" && ex.manifest?.governed_caller_method === caller.method && ex.manifest?.caller_repository === caller.repository && ex.manifest?.caller_workflow_ref === caller.workflow_ref;
      if (!identity) return json({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "STEP_EXECUTION_IDENTITY_MISMATCH" }, 409);
      const result = await rpc("lf_record_creacion_perfil_step_v1", { p_execution_id: id, p_step_id: stepId, p_evidence_ref: evidenceRef, p_evidence_payload: evidence, p_actor_execution_id: id });
      const afterEx = await execution(id), after = afterEx ? await operationSnapshot(afterEx) : null;
      return json({ outcome: result?.outcome ?? "BLOCKED", endpoint_version: ENDPOINT_VERSION, execution_id: id, operation_code: ex.operation_code, step_id: stepId, result, snapshot_after: after, github_write_executed: false }, result?.outcome === "STEP_RECORDED" ? 200 : 409);
    }

    if (body.action !== "initialize_profile_creation_v1") return json({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "ACTION_NOT_ALLOWED" }, 400);
    const requestId = typeof body.caller_request_id === "string" ? body.caller_request_id.toLowerCase() : "", targetCode = typeof body.target_code === "string" ? body.target_code.trim().toUpperCase() : "", slug = typeof body.profile_slug === "string" ? body.profile_slug.trim().toLowerCase() : "", targetRepo = typeof body.target_repo === "string" ? body.target_repo.trim() : "";
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(requestId) || !/^PERFIL-[A-Z0-9][A-Z0-9-]{2,120}$/.test(targetCode) || !/^[a-z0-9][a-z0-9_]{2,80}$/.test(slug) || targetRepo !== REPOSITORY) return json({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "PROFILE_CREATE_INPUT_INVALID" }, 400);
    const id = `EXEC-CREACION-PERFIL-LF-OIDC-${requestId}`, existing = await execution(id);
    if (existing) {
      const step = await initStep(id), identity = existing.operation_code === "CREACION_PERFIL_LF" && existing.target_type === "PERFIL" && existing.target_code === targetCode && existing.target_repo === REPOSITORY && existing.manifest?.governed_caller_method === caller.method && existing.manifest?.caller_workflow_ref === caller.workflow_ref;
      if (!identity || !step || step.status !== "STEP_CLEAN_PASS") return json({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "IDEMPOTENCY_IDENTITY_MISMATCH" }, 409);
      return json({ outcome: "INITIALIZED", endpoint_version: ENDPOINT_VERSION, replay: true, execution: existing, init_step: step, write_executed: false, github_write_executed: false, next_gate: "router" }, 200);
    }
    const router = await rpc("lf_router_resolve_v1", { p_request_text: `Crear perfil ${targetCode}`, p_target_hint: targetCode, p_action_hint: "PROFILE_CREATE", p_asset_type_hint: "PERFIL", p_distribution_mode: "ROUTER" });
    if (router?.status !== "READY_TO_EXECUTE" || router?.operation_code !== "CREACION_PERFIL_LF" || router?.action_code !== "PROFILE_CREATE" || router?.next_step?.step_id !== "init_execution") return json({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "ROUTER_CREATION_NOT_AUTHORIZED", router }, 409);
    const manifest = { schema_version: 1, router: "ACT-0001", creator_asset: "ACT-0045", governed_caller_method: caller.method, caller_request_id: requestId, caller_repository: caller.repository, caller_workflow_ref: caller.workflow_ref, caller_run_id: caller.run_id, caller_workflow_sha: caller.workflow_sha, scope: "INIT_AND_ORDERED_STEP_RECORDING", profile_slug: slug, github_write_allowed: false, github_write_executed: false, runtime_enabled: false, automatic_impact_enabled: false, closure_allowed: false, blocked_from_closure: true, next_gate: "router" };
    const ins = await request("/rest/v1/lf_operation_execution", { method: "POST", headers: { Prefer: "return=representation" }, body: JSON.stringify({ execution_id: id, operation_code: "CREACION_PERFIL_LF", target_type: "PERFIL", target_code: targetCode, target_repo: REPOSITORY, target_path: `profiles/${slug}/SKILL.md`, status: "IN_PROGRESS", manifest, created_by_execution_id: id }) });
    if (ins.status !== 201) throw new Error(`EXECUTION_INSERT_${ins.status}`);
    const evidenceRef = `github-actions://run/${caller.run_id}/profile-creator/init_execution`, evidencePayload = { execution_row_created: true, execution_id: id, operation_code: "CREACION_PERFIL_LF", target_type: "PERFIL", status: "IN_PROGRESS", step_result: "STEP_CLEAN_PASS", blocking_codes: [], assertions_checked: ["execution_row_created", "operation_code_exact", "target_type_perfil", "status_in_progress"], hard_fails_checked: [], blocking_findings: [], return_to_worker_reasons: [], governed_caller_method: caller.method, caller_workflow_ref: caller.workflow_ref, caller_run_id: caller.run_id, caller_workflow_sha: caller.workflow_sha };
    const stepIns = await request("/rest/v1/lf_operation_execution_steps", { method: "POST", headers: { Prefer: "return=representation" }, body: JSON.stringify({ execution_id: id, step_order: 0, step_id: "init_execution", status: "STEP_CLEAN_PASS", evidence_ref: evidenceRef, evidence_payload: evidencePayload, notes: "Governed OIDC caller initialized canonical CREACION_PERFIL_LF execution; no GitHub write performed.", created_by_execution_id: id }) });
    if (stepIns.status !== 201) throw new Error(`INIT_STEP_INSERT_${stepIns.status}`);
    const ex = await execution(id), step = await initStep(id); if (!ex || !step || ex.status !== "IN_PROGRESS" || step.status !== "STEP_CLEAN_PASS") throw new Error("INIT_EXECUTION_READBACK_FAILED");
    return json({ outcome: "INITIALIZED", endpoint_version: ENDPOINT_VERSION, replay: false, execution: ex, init_step: step, router: { status: router.status, operation_code: router.operation_code, action_code: router.action_code, next_step: router.next_step }, write_executed: false, github_write_executed: false, next_gate: "router" }, 201);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error); console.error(message.replace(/Bearer\s+\S+/g, "Bearer [REDACTED]"));
    return json({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "PROFILE_CREATOR_RUNTIME_FAILED", detail: message.slice(0, 1500), write_executed: false }, 409);
  }
});
