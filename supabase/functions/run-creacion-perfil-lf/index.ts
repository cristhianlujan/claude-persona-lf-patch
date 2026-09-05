import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const ENDPOINT_VERSION = "v22-profile-update-server-trust-context";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")?.trim() ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() ?? "";
const REPOSITORY = "cristhianlujan/claude-persona-lf-patch";
const LEGACY_CALLER_METHOD = "GITHUB_ACTIONS_OIDC_EXACT_PROFILE_GOV_V1";
const LEGACY_WORKFLOW = `${REPOSITORY}/.github/workflows/lf-profiles-governance-caller.yml@refs/heads/governance/profiles-unblock-secure-caller-20260901`;
const CUSTOMER_CALLER_METHOD = "GITHUB_ACTIONS_OIDC_EXACT_PROFILE_CREATOR_CUSTOMER_V1";
const CUSTOMER_WORKFLOW = `${REPOSITORY}/.github/workflows/lf-customer-profile-creator-governance-caller.yml@refs/heads/lf/profiles/profile-creator-customer-caller-20260902`;
const PROFILE_OPERATIONS = new Set(["CREACION_PERFIL_LF", "ACTUALIZACION_PERFIL_LF"]);
const SHA40 = /^[0-9a-f]{40}$/;
const TRUST_FIELDS = new Set([
  "trusted_current_revision",
  "current_revision_resolved_by_caller",
  "declared_current_revision_ignored",
  "server_trust_context_valid",
  "server_trust_context_source",
  "server_trust_context",
]);

function headers(): HeadersInit {
  return { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", "x-content-type-options": "nosniff" };
}
function json(body: unknown, status: number): Response { return new Response(JSON.stringify(body), { status, headers: headers() }); }
function constantTimeEqual(left: string, right: string): boolean {
  const a = new TextEncoder().encode(left), b = new TextEncoder().encode(right);
  let diff = a.length ^ b.length;
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
  const c = value as Caller;
  if (c.repository !== REPOSITORY) return { ok: false, code: "GOVERNED_CALLER_REPOSITORY_INVALID" };
  const method = typeof c.method === "string" ? c.method : "";
  const workflow = typeof c.workflow_ref === "string" ? c.workflow_ref : "";
  if (!((method === LEGACY_CALLER_METHOD && workflow === LEGACY_WORKFLOW) || (method === CUSTOMER_CALLER_METHOD && workflow === CUSTOMER_WORKFLOW))) return { ok: false, code: "GOVERNED_CALLER_WORKFLOW_INVALID" };
  if (typeof c.run_id !== "string" || !/^\d+$/.test(c.run_id)) return { ok: false, code: "GOVERNED_CALLER_RUN_ID_INVALID" };
  if (typeof c.workflow_sha !== "string" || !SHA40.test(c.workflow_sha)) return { ok: false, code: "GOVERNED_CALLER_SHA_INVALID" };
  return { ok: true, caller: { method, repository: REPOSITORY, workflow_ref: workflow, run_id: c.run_id, workflow_sha: c.workflow_sha } };
}

async function request(path: string, init: RequestInit): Promise<{ status: number; payload: any }> {
  const response = await fetch(`${SUPABASE_URL}${path}`, {
    ...init,
    headers: { authorization: `Bearer ${SERVICE_ROLE_KEY}`, apikey: SERVICE_ROLE_KEY, "content-type": "application/json", ...(init.headers ?? {}) },
    signal: AbortSignal.timeout(30000),
  });
  const text = await response.text();
  let payload: any;
  try { payload = text ? JSON.parse(text) : null; } catch { payload = { raw: text.slice(0, 1000) }; }
  return { status: response.status, payload };
}
async function rpc(name: string, args: Record<string, unknown>): Promise<any> {
  const r = await request(`/rest/v1/rpc/${name}`, { method: "POST", body: JSON.stringify(args) });
  if (r.status < 200 || r.status >= 300) throw new Error(`RPC_${name}_${r.status}:${JSON.stringify(r.payload).slice(0, 1000)}`);
  return r.payload;
}
async function one(path: string, label: string): Promise<any | null> {
  const r = await request(path, { method: "GET" });
  if (r.status !== 200) throw new Error(`${label}_${r.status}:${JSON.stringify(r.payload).slice(0, 800)}`);
  return Array.isArray(r.payload) && r.payload.length ? r.payload[0] : null;
}
async function rows(path: string, label: string): Promise<any[]> {
  const r = await request(path, { method: "GET" });
  if (r.status !== 200) throw new Error(`${label}_${r.status}:${JSON.stringify(r.payload).slice(0, 800)}`);
  return Array.isArray(r.payload) ? r.payload : [];
}
async function execution(id: string): Promise<any | null> {
  return one(`/rest/v1/lf_operation_execution?execution_id=eq.${encodeURIComponent(id)}&select=execution_id,operation_code,target_type,target_code,target_repo,target_path,status,manifest,updated_at`, "EXECUTION_READ");
}
async function initStep(id: string): Promise<any | null> {
  return one(`/rest/v1/lf_operation_execution_steps?execution_id=eq.${encodeURIComponent(id)}&step_order=eq.0&step_id=eq.init_execution&select=execution_id,step_order,step_id,status,evidence_ref,evidence_payload`, "INIT_STEP_READ");
}
function baselineObservation(recorded: any[]): Record<string, unknown> | null {
  const row = recorded.find((r: any) => r.step_id === "baseline_read");
  if (!row) return null;
  const payload = row.evidence_payload && typeof row.evidence_payload === "object" && !Array.isArray(row.evidence_payload) ? row.evidence_payload : {};
  const baselineRevision = typeof payload.baseline_revision === "string" ? payload.baseline_revision.trim() : "";
  return { step_id: "baseline_read", status: row.status ?? null, evidence_ref: row.evidence_ref ?? null, observed_at: row.observed_at ?? null, baseline_revision: baselineRevision };
}
async function operationSnapshot(ex: any): Promise<any> {
  const op = String(ex.operation_code ?? "");
  if (!PROFILE_OPERATIONS.has(op) || ex.target_type !== "PERFIL") throw new Error("PROFILE_OPERATION_NOT_SUPPORTED");
  const [steps, recorded, contracts, bindings, policies] = await Promise.all([
    rows(`/rest/v1/lf_operation_steps?operation_code=eq.${encodeURIComponent(op)}&active=eq.true&select=step_order,execution_order,step_id,required,evidence_required&order=execution_order.asc`, "OP_STEPS_READ"),
    rows(`/rest/v1/lf_operation_execution_steps?execution_id=eq.${encodeURIComponent(ex.execution_id)}&select=step_order,step_id,status,evidence_ref,evidence_payload,observed_at&order=step_order.asc`, "RECORDED_STEPS_READ"),
    rows(`/rest/v1/lf_operation_step_contracts?operation_code=eq.${encodeURIComponent(op)}&select=step_id,step_order,execution_order,status,resolver_ref,required_evidence_keys,next_if_pass,next_if_blocked,blocking_code`, "STEP_CONTRACTS_READ"),
    rows(`/rest/v1/lf_operation_step_judge_bindings?operation_code=eq.${encodeURIComponent(op)}&status=eq.ACTIVE_ENFORCEMENT&select=step_id,step_order,judge_code,clean_result_value,blocked_result_value,return_result_value,required_evidence_keys`, "JUDGE_BINDINGS_READ"),
    rows(`/rest/v1/v_lf_operation_policy_snapshot?operation_code=eq.${encodeURIComponent(op)}&select=*`, "POLICY_SNAPSHOT_READ"),
  ]);
  const rec = new Map(recorded.map((r: any) => [r.step_id, r]));
  const contractsBy = new Map(contracts.map((r: any) => [r.step_id, r]));
  const bindingsBy = new Map(bindings.map((r: any) => [r.step_id, r]));
  let next: any = null;
  for (const s of steps) {
    if (!s.required || rec.has(s.step_id)) continue;
    const c = contractsBy.get(s.step_id), b = bindingsBy.get(s.step_id);
    if (!c || !b) throw new Error(`PROFILE_OPERATION_STEP_CONTRACT_OR_JUDGE_MISSING:${s.step_id}`);
    next = { step_id: s.step_id, step_order: s.step_order, execution_order: s.execution_order, resolver_ref: c.resolver_ref, required_evidence_keys: b.required_evidence_keys ?? c.required_evidence_keys ?? [], judge_code: b.judge_code, clean_result_value: b.clean_result_value, blocked_result_value: b.blocked_result_value, return_result_value: b.return_result_value, next_if_pass: c.next_if_pass, next_if_blocked: c.next_if_blocked };
    break;
  }
  return { operation_code: op, target_code: ex.target_code, target_path: ex.target_path, execution_status: ex.status, execution_updated_at: ex.updated_at, declared_step_count: steps.length, recorded_step_count: recorded.length, remaining_required_count: steps.filter((s: any) => s.required && !rec.has(s.step_id)).length, baseline_observation: op === "ACTUALIZACION_PERFIL_LF" ? baselineObservation(recorded) : null, next_step: next, policies };
}

function stripCallerTrust(evidence: Record<string, unknown>): Record<string, unknown> {
  return Object.fromEntries(Object.entries(evidence).filter(([k]) => !TRUST_FIELDS.has(k)));
}
async function githubJson(url: string, label: string): Promise<any> {
  const r = await fetch(url, { headers: { accept: "application/vnd.github+json", "user-agent": "lf-profile-operation-runtime-v22" }, signal: AbortSignal.timeout(15000) });
  if (!r.ok) throw new Error(`${label}_${r.status}`);
  return await r.json();
}
async function deriveServerTrust(ex: any, before: any, evidence: Record<string, unknown>): Promise<{ ok: true; evidence: Record<string, unknown> } | { ok: false; code: string }> {
  const baseline = typeof before?.baseline_observation?.baseline_revision === "string" ? before.baseline_observation.baseline_revision.trim().toLowerCase() : "";
  if (!SHA40.test(baseline)) return { ok: false, code: "PROFILE_UPDATE_BASELINE_OBSERVATION_REQUIRED" };
  const targetPath = typeof ex.target_path === "string" ? ex.target_path.trim() : "";
  if (!targetPath) return { ok: false, code: "PROFILE_UPDATE_EXECUTION_TARGET_PATH_REQUIRED" };
  const ref = await githubJson(`https://api.github.com/repos/${REPOSITORY}/git/ref/heads/main`, "GITHUB_MAIN_REF");
  const current = typeof ref?.object?.sha === "string" ? ref.object.sha.toLowerCase() : "";
  if (!SHA40.test(current)) return { ok: false, code: "PROFILE_UPDATE_CURRENT_REVISION_UNRESOLVED" };
  const encodedPath = targetPath.split("/").map(encodeURIComponent).join("/");
  const target = await githubJson(`https://api.github.com/repos/${REPOSITORY}/contents/${encodedPath}?ref=${current}`, "GITHUB_TARGET_BLOB");
  if (Array.isArray(target)) return { ok: false, code: "PROFILE_UPDATE_EXACT_TARGET_FILE_REQUIRED" };
  const blob = typeof target?.sha === "string" ? target.sha.toLowerCase() : "";
  if (!SHA40.test(blob)) return { ok: false, code: "PROFILE_UPDATE_CURRENT_TARGET_BLOB_UNRESOLVED" };
  const bound = typeof evidence.bound_revision === "string" ? evidence.bound_revision.trim().toLowerCase() : "";
  if (!SHA40.test(bound)) return { ok: false, code: "PROFILE_UPDATE_BOUND_REVISION_STRUCTURED_REQUIRED" };
  if (evidence.execution_bound_to_target_before_change !== true) return { ok: false, code: "PROFILE_UPDATE_EXECUTION_BINDING_REQUIRED" };
  const stale = baseline !== current;
  if (bound !== current) return { ok: false, code: "PROFILE_UPDATE_BOUND_REVISION_CURRENT_MISMATCH" };
  if (stale) {
    if (evidence.reread_performed !== true) return { ok: false, code: "PROFILE_UPDATE_STALE_REREAD_REQUIRED" };
    if (evidence.rebind_performed !== true) return { ok: false, code: "PROFILE_UPDATE_STALE_REBIND_REQUIRED" };
    if (String(evidence.rebound_from_revision ?? "").toLowerCase() !== baseline) return { ok: false, code: "PROFILE_UPDATE_REBOUND_FROM_REVISION_MISMATCH" };
  }
  const continuity = stale ? "STALE_REBOUND_CURRENT" : "CURRENT_BOUND";
  const clean = stripCallerTrust(evidence);
  const assertions = [
    "execution_id_matches_current_execution",
    "target_code_matches_execution_target",
    "target_path_matches_execution_target",
    "execution_bound_to_target_before_change_is_true",
    "bound_revision_is_structured",
    "bound_revision_matches_current_resolved_revision",
    "stale_revision_has_reread_and_explicit_rebind_when_applicable",
    "required_exact_target_identity_fields_match_target_type",
  ];
  return { ok: true, evidence: { ...clean, execution_id: ex.execution_id, target_code: ex.target_code, target_path: targetPath, bound_revision: bound, execution_bound_to_target_before_change: true, assertions_checked: assertions, hard_fails_checked: [], server_trust_context_valid: true, server_trust_context_source: "run-creacion-perfil-lf", server_trust_context: { resolver: "GITHUB_PUBLIC_API_EXACT_REF_V1", repository: REPOSITORY, ref: "main", revision_sha: current, target_path: targetPath, target_blob_sha: blob, baseline_revision: baseline, bound_revision: bound, continuity_state: continuity, observed_at: new Date().toISOString() } } };
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "METHOD_NOT_ALLOWED" }, 405);
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY) return json({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "RUNTIME_CONFIG_MISSING" }, 500);
  const auth = requireServiceRole(req); if (auth) return auth;
  try {
    let body: Record<string, unknown>;
    try { body = await req.json(); } catch { return json({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "INVALID_JSON" }, 400); }
    const cv = validateCaller(body.caller); if (!cv.ok) return json({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: cv.code }, 403);
    const caller = cv.caller;

    if (body.action === "next_profile_operation_step_v1") {
      const id = typeof body.execution_id === "string" ? body.execution_id.trim() : "";
      if (!id || id.length > 180) return json({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "EXECUTION_ID_INVALID" }, 400);
      const ex = await execution(id);
      if (!ex || ex.target_type !== "PERFIL" || ex.target_repo !== REPOSITORY || !PROFILE_OPERATIONS.has(ex.operation_code)) return json({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "PROFILE_OPERATION_EXECUTION_IDENTITY_MISMATCH" }, 409);
      const snapshot = await operationSnapshot(ex);
      return json({ outcome: snapshot.next_step ? "NEXT_STEP_RESOLVED" : "NO_REQUIRED_STEP_REMAINING", endpoint_version: ENDPOINT_VERSION, execution_id: id, snapshot, write_executed: false }, 200);
    }

    if (body.action === "record_profile_operation_step_v1" || body.action === "record_profile_creation_step_v1") {
      const id = typeof body.execution_id === "string" ? body.execution_id.trim() : "";
      const stepId = typeof body.step_id === "string" ? body.step_id.trim() : "";
      const evidenceRef = typeof body.evidence_ref === "string" ? body.evidence_ref.trim() : "";
      let evidence = body.evidence_payload && typeof body.evidence_payload === "object" && !Array.isArray(body.evidence_payload) ? body.evidence_payload as Record<string, unknown> : null;
      if (!id || id.length > 180 || !/^[a-z0-9_]{2,80}$/.test(stepId) || !evidenceRef || !evidence) return json({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "STEP_EVIDENCE_INPUT_INVALID" }, 400);
      const ex = await execution(id);
      if (!ex || ex.target_type !== "PERFIL" || ex.target_repo !== REPOSITORY || !PROFILE_OPERATIONS.has(ex.operation_code)) return json({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "PROFILE_OPERATION_EXECUTION_IDENTITY_MISMATCH" }, 409);
      const before = await operationSnapshot(ex);
      if (!before.next_step || before.next_step.step_id !== stepId) return json({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "PROFILE_OPERATION_STEP_NOT_CURRENT", expected_step: before.next_step?.step_id ?? null, requested_step: stepId }, 409);
      const identity = ex.status === "IN_PROGRESS" && ex.manifest?.governed_caller_method === caller.method && ex.manifest?.caller_repository === caller.repository && ex.manifest?.caller_workflow_ref === caller.workflow_ref;
      if (!identity) return json({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "STEP_EXECUTION_IDENTITY_MISMATCH" }, 409);
      if (ex.operation_code === "ACTUALIZACION_PERFIL_LF") {
        evidence = stripCallerTrust(evidence);
        if (stepId === "pre_write_execution_binding_gate") {
          const trusted = await deriveServerTrust(ex, before, body.evidence_payload as Record<string, unknown>);
          if (!trusted.ok) return json({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: trusted.code, operation_code: ex.operation_code, step_id: stepId, write_executed: false }, 409);
          evidence = trusted.evidence;
        }
        const result = await rpc("lf_record_profile_operation_step_v1", { p_execution_id: id, p_step_id: stepId, p_evidence_ref: evidenceRef, p_evidence_payload: evidence, p_actor_execution_id: id });
        const afterEx = await execution(id), after = afterEx ? await operationSnapshot(afterEx) : null;
        return json({ outcome: result?.outcome ?? "BLOCKED", endpoint_version: ENDPOINT_VERSION, execution_id: id, operation_code: ex.operation_code, step_id: stepId, result, snapshot_after: after, server_trust_context_derived: stepId === "pre_write_execution_binding_gate", github_write_executed: false }, result?.outcome === "STEP_RECORDED" ? 200 : 409);
      }
      const result = await rpc("lf_record_creacion_perfil_step_v1", { p_execution_id: id, p_step_id: stepId, p_evidence_ref: evidenceRef, p_evidence_payload: evidence, p_actor_execution_id: id });
      const afterEx = await execution(id), after = afterEx ? await operationSnapshot(afterEx) : null;
      return json({ outcome: result?.outcome ?? "BLOCKED", endpoint_version: ENDPOINT_VERSION, execution_id: id, operation_code: ex.operation_code, step_id: stepId, result, snapshot_after: after, github_write_executed: false }, result?.outcome === "STEP_RECORDED" ? 200 : 409);
    }

    if (body.action !== "initialize_profile_creation_v1") return json({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "ACTION_NOT_ALLOWED" }, 400);
    const requestId = typeof body.caller_request_id === "string" ? body.caller_request_id.toLowerCase() : "";
    const targetCode = typeof body.target_code === "string" ? body.target_code.trim().toUpperCase() : "";
    const slug = typeof body.profile_slug === "string" ? body.profile_slug.trim().toLowerCase() : "";
    const targetRepo = typeof body.target_repo === "string" ? body.target_repo.trim() : "";
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(requestId) || !/^PERFIL-[A-Z0-9][A-Z0-9-]{2,120}$/.test(targetCode) || !/^[a-z0-9][a-z0-9_]{2,80}$/.test(slug) || targetRepo !== REPOSITORY) return json({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "PROFILE_CREATE_INPUT_INVALID" }, 400);
    const id = `EXEC-CREACION-PERFIL-LF-OIDC-${requestId}`;
    const existing = await execution(id);
    if (existing) {
      const step = await initStep(id);
      const identity = existing.operation_code === "CREACION_PERFIL_LF" && existing.target_type === "PERFIL" && existing.target_code === targetCode && existing.target_repo === REPOSITORY && existing.manifest?.governed_caller_method === caller.method && existing.manifest?.caller_workflow_ref === caller.workflow_ref;
      if (!identity || !step || step.status !== "STEP_CLEAN_PASS") return json({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "IDEMPOTENCY_IDENTITY_MISMATCH" }, 409);
      return json({ outcome: "INITIALIZED", endpoint_version: ENDPOINT_VERSION, replay: true, execution: existing, init_step: step, write_executed: false, github_write_executed: false, next_gate: "router" }, 200);
    }
    const router = await rpc("lf_router_resolve_v1", { p_request_text: `Crear perfil ${targetCode}`, p_target_hint: targetCode, p_action_hint: "PROFILE_CREATE", p_asset_type_hint: "PERFIL", p_distribution_mode: "ROUTER" });
    if (router?.status !== "READY_TO_EXECUTE" || router?.operation_code !== "CREACION_PERFIL_LF" || router?.action_code !== "PROFILE_CREATE" || router?.next_step?.step_id !== "init_execution") return json({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "ROUTER_CREATION_NOT_AUTHORIZED", router }, 409);
    const manifest = { schema_version: 1, router: "ACT-0001", creator_asset: "ACT-0045", governed_caller_method: caller.method, caller_repository: caller.repository, caller_workflow_ref: caller.workflow_ref, caller_run_id: caller.run_id, caller_workflow_sha: caller.workflow_sha, customer_profile_scope: true, runtime_write_executed: false, github_write_executed: false, production_authorized: true };
    const insert = await request("/rest/v1/lf_operation_execution", { method: "POST", headers: { prefer: "return=representation" }, body: JSON.stringify({ execution_id: id, operation_code: "CREACION_PERFIL_LF", target_type: "PERFIL", target_code: targetCode, target_repo: REPOSITORY, target_path: `profiles/${slug}`, status: "IN_PROGRESS", manifest, created_by_execution_id: id }) });
    if (insert.status !== 201) throw new Error(`EXECUTION_INSERT_${insert.status}:${JSON.stringify(insert.payload).slice(0, 1000)}`);
    const initPayload = { execution_id_created: true, target_code: targetCode, target_path: `profiles/${slug}`, profile_slug: slug, target_repo: REPOSITORY, governed_caller_method: caller.method, governed_caller_repository: caller.repository, governed_caller_workflow_ref: caller.workflow_ref, governed_caller_run_id: caller.run_id, governed_caller_workflow_sha: caller.workflow_sha, project_id: "AGENTE_PROFILE_CREATOR", owner_lane: "CUSTOMER_PROFILES", execution_origin: "AUTOMATION_PROFILE_CREATOR_DUAL_EXECUTOR", workstream_id: "PROFILE_CREATOR_INFRA", runtime_write_executed: false, github_write_executed: false, blocking_codes: [] };
    const recorded = await rpc("lf_record_creacion_perfil_step_v1", { p_execution_id: id, p_step_id: "init_execution", p_evidence_ref: `github-actions-oidc://${caller.run_id}/init_execution`, p_evidence_payload: initPayload, p_actor_execution_id: id });
    if (recorded?.outcome !== "STEP_RECORDED") return json({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "INIT_STEP_RECORD_FAILED", execution_id: id, recorded }, 409);
    const ex = await execution(id), snapshot = ex ? await operationSnapshot(ex) : null;
    return json({ outcome: "INITIALIZED", endpoint_version: ENDPOINT_VERSION, replay: false, execution: ex, snapshot, write_executed: true, github_write_executed: false, next_gate: snapshot?.next_step?.step_id ?? "router" }, 201);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(message.replace(/Bearer\s+\S+/g, "Bearer [REDACTED]"));
    return json({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: message.slice(0, 1000) }, 409);
  }
});
