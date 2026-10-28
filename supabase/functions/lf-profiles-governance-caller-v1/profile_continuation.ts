// Governed, profile-agnostic continuation for an *existing* Router-admitted execution.
// It deliberately does not select a profile/screen, impersonate a model, or grant
// write authority. All substantive transitions use existing canonical RPCs.
export const PROFILE_SOURCE_BIND_ACTION = "profile_native_source_bind_v1";
export const PROFILE_CONTINUE_ACTION = "profile_native_continue_v1";
export const PROFILE_CONTINUATION_ACTIONS = [PROFILE_SOURCE_BIND_ACTION, PROFILE_CONTINUE_ACTION] as const;

type Fetcher = (input: string | URL | Request, init?: RequestInit) => Promise<Response>;
type Config = { supabaseUrl: string; serviceRoleKey: string; repository: string };
type Execution = {
  execution_id: string;
  status: string;
  operation_code: string;
  target_type: string;
  target_code: string;
  target_repo: string;
  target_path: string;
  manifest: Record<string, unknown>;
};
type Payload = Record<string, unknown>;

function respond(body: Payload, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store", "x-content-type-options": "nosniff" },
  });
}

function blocked(code: string, status = 409): Response {
  return respond({ outcome: "BLOCKED", code }, status);
}

async function parseResponse(response: Response): Promise<unknown> {
  try { return await response.json(); } catch { return null; }
}

async function authorizedExecution(
  config: Config,
  fetchFn: Fetcher,
  executionId: string,
): Promise<{ execution?: Execution; error?: Response }> {
  if (!/^[A-Za-z0-9][A-Za-z0-9_-]{10,127}$/.test(executionId)) {
    return { error: blocked("PROFILE_CONTINUATION_EXECUTION_ID_INVALID", 400) };
  }
  const endpoint = `${config.supabaseUrl}/rest/v1/lf_operation_execution?execution_id=eq.${encodeURIComponent(executionId)}&select=execution_id,status,operation_code,target_type,target_code,target_repo,target_path,manifest`;
  let response: Response;
  try {
    response = await fetchFn(endpoint, {
      method: "GET",
      headers: { apikey: config.serviceRoleKey, authorization: `Bearer ${config.serviceRoleKey}` },
      signal: AbortSignal.timeout(15_000),
    });
  } catch { return { error: blocked("PROFILE_CONTINUATION_READ_FAILED", 502) }; }
  if (!response.ok) return { error: blocked("PROFILE_CONTINUATION_READ_REJECTED", 502) };
  const rows = await parseResponse(response);
  if (!Array.isArray(rows) || rows.length !== 1 || !rows[0] || typeof rows[0] !== "object") {
    return { error: blocked("PROFILE_CONTINUATION_EXECUTION_NOT_FOUND", 404) };
  }
  const e = rows[0] as Execution;
  const m = e.manifest;
  const handoff = m?.router_profile_handoff as Record<string, unknown> | undefined;
  const receipt = handoff?.router_authorization_receipt as Record<string, unknown> | undefined;
  if (
    e.operation_code !== "EJECUCION_PERFIL_LF" || e.target_type !== "PERFIL" ||
    e.status !== "IN_PROGRESS" || e.target_repo !== config.repository ||
    !/^profiles\/[a-z0-9_-]+\/SKILL\.md$/.test(e.target_path) ||
    m?.executor_mode !== "GPT_NATIVE" || m?.read_only !== true || m?.no_write !== true ||
    m?.no_promotion !== true || m?.governed_repair_write !== false ||
    handoff?.profile_code !== e.target_code || receipt?.profile_code !== e.target_code ||
    receipt?.profile_execution_allowed !== true || receipt?.effect_authority !== false
  ) return { error: blocked("PROFILE_CONTINUATION_GOVERNED_READ_ONLY_AUTHORITY_REQUIRED", 403) };
  return { execution: e };
}

async function rpc(config: Config, fetchFn: Fetcher, name: string, parameters: Payload): Promise<{ result?: Payload; error?: Response }> {
  let response: Response;
  try {
    response = await fetchFn(`${config.supabaseUrl}/rest/v1/rpc/${name}`, {
      method: "POST",
      headers: {
        apikey: config.serviceRoleKey,
        authorization: `Bearer ${config.serviceRoleKey}`,
        "content-type": "application/json",
      },
      body: JSON.stringify(parameters),
      signal: AbortSignal.timeout(30_000),
    });
  } catch { return { error: blocked("PROFILE_CONTINUATION_RPC_TRANSPORT_FAILED", 502) }; }
  const data = await parseResponse(response);
  if (!response.ok || !data || typeof data !== "object" || Array.isArray(data)) {
    return { error: blocked("PROFILE_CONTINUATION_RPC_REJECTED", 502) };
  }
  return { result: data as Payload };
}

export async function handleProfileContinuation(
  action: string,
  body: Payload,
  config: Config,
  fetchFn: Fetcher,
  callerRevision: string,
): Promise<Response> {
  const executionId = typeof body.execution_id === "string" ? body.execution_id : "";
  const { execution: e, error } = await authorizedExecution(config, fetchFn, executionId);
  if (error || !e) return error ?? blocked("PROFILE_CONTINUATION_EXECUTION_NOT_FOUND");
  if (action === PROFILE_SOURCE_BIND_ACTION) {
    return respond({
      outcome: "SOURCE_BINDING_REQUIRED",
      execution_id: e.execution_id,
      profile_code: e.target_code,
      target_repo: e.target_repo,
      target_path: e.target_path,
      source_revision_required: callerRevision,
      next_action: "READ_PROFILE_AT_AUTHORIZED_SOURCE_REVISION",
    });
  }
  if (action !== PROFILE_CONTINUE_ACTION) return blocked("PROFILE_CONTINUATION_ACTION_UNSUPPORTED", 400);
  const revision = body.source_revision;
  const digest = body.source_digest;
  if (
    typeof revision !== "string" || !/^[0-9a-f]{40}$/.test(revision) ||
    revision !== callerRevision ||
    typeof digest !== "string" || !/^sha256:[0-9a-f]{64}$/.test(digest)
  ) return blocked("PROFILE_CONTINUATION_SOURCE_BINDING_INVALID", 400);

  // The native prepare function enforces ordered checkpoints and validates
  // Router handoff, profile source, screen selection, IG and compact context.
  let prepared = await rpc(config, fetchFn, "lf_profile_native_bridge_prepare_v1", {
    p_execution_id: e.execution_id,
    p_source_revision: revision,
    p_source_digest: digest,
    p_actor_execution_id: e.execution_id,
  });
  if (prepared.error) return prepared.error;
  let result = prepared.result!;
  // Only an explicit semantic decision may bind a screen; one candidate is NOT
  // auto-selected. SQL rehydrates the current shortlist and judges the draft.
  if (Object.prototype.hasOwnProperty.call(body, "screen_selection_draft")) {
    if (result.status !== "SCREEN_SELECTION_REQUIRED") {
      return blocked("PROFILE_CONTINUATION_SCREEN_SELECTION_NOT_REQUESTED", 409);
    }
    const draft = body.screen_selection_draft;
    if (!draft || typeof draft !== "object" || Array.isArray(draft)) {
      return blocked("PROFILE_CONTINUATION_SCREEN_SELECTION_DRAFT_INVALID", 400);
    }
    const submitted = await rpc(config, fetchFn, "lf_profile_screen_selector_semantic_submit_v1", {
      p_execution_id: e.execution_id,
      p_draft: draft,
      p_actor_execution_id: e.execution_id,
    });
    if (submitted.error) return submitted.error;
    if (!["BOUND", "ALREADY_BOUND"].includes(String(submitted.result?.status ?? ""))) {
      return respond({ outcome: "BLOCKED", code: "PROFILE_CONTINUATION_SCREEN_SELECTION_REJECTED", result: submitted.result }, 409);
    }
    prepared = await rpc(config, fetchFn, "lf_profile_native_bridge_prepare_v1", {
      p_execution_id: e.execution_id,
      p_source_revision: revision,
      p_source_digest: digest,
      p_actor_execution_id: e.execution_id,
    });
    if (prepared.error) return prepared.error;
    result = prepared.result!;
  }
  const status = String(result.status ?? "BLOCKED");
  const expected = [
    "SCREEN_SELECTION_REQUIRED",
    "INPUT_GOVERNANCE_RUNTIME_REQUIRED",
    "NATIVE_MODEL_INPUT_READY",
    "HUMAN_DECISION_REQUIRED",
    "SCREEN_SELECTION_AMBIGUOUS",
    "SCREEN_SELECTION_NO_MATCH",
  ];
  const recognized = expected.includes(status);
  return respond({
    outcome: recognized ? "CONTINUATION_REQUIRED" : "BLOCKED",
    phase: status,
    code: recognized ? null : (result.blocking_code ?? "PROFILE_CONTINUATION_PREPARE_BLOCKED"),
    execution_id: e.execution_id,
    profile_code: e.target_code,
    next_action: result.next_action ?? null,
    result,
  }, recognized ? 200 : 409);
}
