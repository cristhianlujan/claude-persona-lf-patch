// Governed, profile-agnostic continuation for an *existing* Router-admitted execution.
// It deliberately does not select a profile/screen, impersonate a model, or grant
// write authority. All substantive transitions use existing canonical RPCs.
export const PROFILE_SOURCE_BIND_ACTION = "profile_native_source_bind_v1";
export const PROFILE_CONTINUE_ACTION = "profile_native_continue_v1";
export const PROFILE_CONTINUATION_ACTIONS = [PROFILE_SOURCE_BIND_ACTION, PROFILE_CONTINUE_ACTION] as const;

// Native executors are bound to their provider; any other mode/provider pair is rejected.
const NATIVE_EXECUTOR_PROVIDER_BY_MODE = new Set([
  "GPT_NATIVE|OPENAI_CHATGPT_NATIVE",
  "CLAUDE_NATIVE|ANTHROPIC_CLAUDE_NATIVE",
]);

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
    !NATIVE_EXECUTOR_PROVIDER_BY_MODE.has(`${m?.executor_mode}|${m?.executor_provider}`) ||
    m?.read_only !== true || m?.no_write !== true ||
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

// Resolve only the existing post-model steps; never relax the pre-model 7-step guard.
async function resolveExistingPostModelStep(
  e: Execution,
  prepareResult: Payload,
  config: Config,
  fetchFn: Fetcher,
): Promise<Response | null> {
  if (
    prepareResult.status !== "BLOCKED" ||
    prepareResult.blocking_code !== "BLOCK_PROFILE_NATIVE_BRIDGE_PRE_MODEL_STEP_COUNT" ||
    prepareResult.expected_clean_step_count !== 7 ||
    (prepareResult.clean_step_count !== 9 && prepareResult.clean_step_count !== 10)
  ) return null;

  const url = `${config.supabaseUrl}/rest/v1/lf_operation_execution_steps?execution_id=eq.${encodeURIComponent(e.execution_id)}&select=step_id,status&order=step_order.asc`;
  let response: Response;
  try {
    response = await fetchFn(url, {
      method: "GET",
      headers: { apikey: config.serviceRoleKey, authorization: `Bearer ${config.serviceRoleKey}` },
      signal: AbortSignal.timeout(15_000),
    });
  } catch { return blocked("PROFILE_POST_MODEL_STEP_READ_FAILED", 502); }
  if (!response.ok) return blocked("PROFILE_POST_MODEL_STEP_READ_REJECTED", 502);
  const rows = await parseResponse(response);
  if (!Array.isArray(rows)) return blocked("PROFILE_POST_MODEL_STEPS_INVALID", 409);

  const steps = new Map<string, string>();
  for (const row of rows) {
    if (!row || typeof row !== "object" || Array.isArray(row)) {
      return blocked("PROFILE_POST_MODEL_STEPS_INVALID", 409);
    }
    const item = row as Record<string, unknown>;
    if (typeof item.step_id !== "string" || typeof item.status !== "string" || steps.has(item.step_id)) {
      return blocked("PROFILE_POST_MODEL_STEPS_INVALID", 409);
    }
    steps.set(item.step_id, item.status);
  }
  const completed = [
    "init_execution", "router", "profile_resolve", "profile_source_read",
    "input_validate", "context_admission", "research_baseline_freeze",
    "execute_profile", "output_validate",
  ];
  if (
    steps.size !== prepareResult.clean_step_count ||
    !completed.every(step => steps.get(step) === "STEP_PASS_WITH_EVIDENCE") ||
    steps.has("report_output")
  ) return blocked("PROFILE_POST_MODEL_STEPS_NOT_CLEAN", 409);

  let nextStep: string;
  let phase: string;
  if (steps.size === 9 && !steps.has("semantic_judge")) {
    nextStep = "semantic_judge";
    phase = "INDEPENDENT_SEMANTIC_JUDGE_REQUIRED";
  } else if (steps.size === 10 && steps.get("semantic_judge") === "STEP_PASS_WITH_EVIDENCE") {
    nextStep = "report_output";
    phase = "REPORT_OUTPUT_REQUIRED";
  } else {
    return blocked("PROFILE_POST_MODEL_STEPS_NOT_CLEAN", 409);
  }
  return respond({
    outcome: "CONTINUATION_REQUIRED",
    phase,
    code: null,
    execution_id: e.execution_id,
    profile_code: e.target_code,
    next_action: nextStep === "semantic_judge"
      ? "RUN_EXISTING_INDEPENDENT_SEMANTIC_JUDGE"
      : "RECORD_EXISTING_REPORT_OUTPUT",
    result: {
      status: phase,
      last_completed_step: nextStep === "semantic_judge" ? "output_validate" : "semantic_judge",
      next_step: nextStep,
      clean_step_count: steps.size,
      execution_id: e.execution_id,
    },
  });
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
  const semanticKeys = [
    "context_resolution_valid", "evidence_supported", "decision_resolves_objective",
    "authority_resolution_valid", "constraints_preserved", "claims_authorized",
    "materiality_handled_correctly", "tradeoff_defensible",
    "acceptance_detects_wrong_implementation", "handoff_implementation_ready",
    "router_direct_consistency", "counterfactual_trajectory",
  ];

  if (Object.prototype.hasOwnProperty.call(body, "semantic_judge_result")) {
    const semantic = body.semantic_judge_result;
    const semanticRef = body.semantic_evidence_ref;
    if (
      !semantic || typeof semantic !== "object" || Array.isArray(semantic) ||
      typeof semanticRef !== "string" || !semanticRef.startsWith("actions://")
    ) return blocked("PROFILE_NATIVE_SEMANTIC_SUBMISSION_INVALID", 400);

    const receipt = semantic as Payload;
    const review = receipt.judge_v3_evidence;
    const resultObj = receipt.result;
    if (
      receipt.status !== "PASS" ||
      receipt.verdict !== "PASS_INDEPENDENT_SEMANTIC" ||
      receipt.validator_status !== "PASS" ||
      receipt.producer_independence_proven !== true ||
      receipt.model_call_count !== 1 ||
      typeof receipt.candidate_sha256 !== "string" ||
      !/^[0-9a-f]{64}$/.test(receipt.candidate_sha256) ||
      typeof receipt.scope_packet_sha256 !== "string" ||
      !/^[0-9a-f]{64}$/.test(receipt.scope_packet_sha256) ||
      !resultObj || typeof resultObj !== "object" || Array.isArray(resultObj) ||
      (resultObj as Payload).verdict !== "PASS_INDEPENDENT_SEMANTIC" ||
      (resultObj as Payload).candidate_sha256 !== receipt.candidate_sha256 ||
      (resultObj as Payload).scope_packet_sha256 !== receipt.scope_packet_sha256 ||
      !Array.isArray((resultObj as Payload).unsupported_claims) ||
      ((resultObj as Payload).unsupported_claims as unknown[]).length !== 0 ||
      !Array.isArray((resultObj as Payload).blocking_codes) ||
      ((resultObj as Payload).blocking_codes as unknown[]).length !== 0 ||
      !review || typeof review !== "object" || Array.isArray(review)
    ) return blocked("PROFILE_NATIVE_SEMANTIC_RECEIPT_NOT_PASS", 409);

    const v3 = review as Payload;
    const checks = v3.decision_checks;
    if (
      v3.verdict !== "PASS_INDEPENDENT_SEMANTIC" ||
      v3.producer_independence_proven !== true ||
      v3.model_call_count !== 1 ||
      v3.candidate_sha256 !== receipt.candidate_sha256 ||
      v3.scope_packet_sha256 !== receipt.scope_packet_sha256 ||
      !Array.isArray(v3.unsupported_claims) || v3.unsupported_claims.length !== 0 ||
      !Array.isArray(v3.blocking_codes) || v3.blocking_codes.length !== 0 ||
      !Array.isArray(v3.source_refs) || v3.source_refs.length === 0 ||
      !Array.isArray(v3.resolved_context_refs) || v3.resolved_context_refs.length === 0 ||
      !["PASS", "NOT_TESTED"].includes(String(v3.router_direct_consistency ?? "")) ||
      !v3.counterfactual_result ||
      !checks || typeof checks !== "object" || Array.isArray(checks) ||
      Object.keys(checks).sort().join("|") !== [...semanticKeys].sort().join("|")
    ) return blocked("PROFILE_NATIVE_SEMANTIC_V3_EVIDENCE_INVALID", 409);

    for (const key of semanticKeys) {
      const check = (checks as Payload)[key];
      if (
        !check || typeof check !== "object" || Array.isArray(check) ||
        ![true, "true"].includes((check as Payload).result as true | string) ||
        typeof (check as Payload).reason !== "string" || !(check as Payload).reason ||
        !Array.isArray((check as Payload).source_refs)
      ) return blocked("PROFILE_NATIVE_SEMANTIC_V3_CHECK_FAILED", 409);
    }

    const recordedSemantic = await rpc(config, fetchFn, "lf_profile_native_bridge_record_semantic_v1", {
      p_execution_id: e.execution_id,
      p_semantic_judge_result: receipt,
      p_evidence_ref: semanticRef,
      p_actor_execution_id: e.execution_id,
    });
    if (recordedSemantic.error) return recordedSemantic.error;
    if (
      recordedSemantic.result?.status !== "SEMANTIC_JUDGE_RECORDED" ||
      Number(recordedSemantic.result?.clean_step_count ?? 0) !== 10
    ) {
      return respond({
        outcome: "BLOCKED",
        phase: "SEMANTIC_RECORD",
        code: recordedSemantic.result?.blocking_code ?? "PROFILE_NATIVE_SEMANTIC_RECORD_REJECTED",
        execution_id: e.execution_id,
        profile_code: e.target_code,
        result: recordedSemantic.result,
      }, 409);
    }

    const reportRef = `supabase://public.lf_operation_execution_steps/${e.execution_id}/report_output`;
    const recordedReport = await rpc(config, fetchFn, "lf_profile_native_bridge_record_report_v1", {
      p_execution_id: e.execution_id,
      p_evidence_ref: reportRef,
      p_actor_execution_id: e.execution_id,
    });
    if (recordedReport.error) return recordedReport.error;
    if (recordedReport.result?.status !== "PROFILE_EXECUTION_COMPLETED") {
      return respond({
        outcome: "BLOCKED",
        phase: "REPORT_RECORD",
        code: recordedReport.result?.blocking_code ?? "PROFILE_NATIVE_REPORT_RECORD_REJECTED",
        execution_id: e.execution_id,
        profile_code: e.target_code,
        result: recordedReport.result,
      }, 409);
    }
    return respond({
      outcome: "TERMINAL",
      phase: "PROFILE_EXECUTION_COMPLETED",
      code: null,
      execution_id: e.execution_id,
      profile_code: e.target_code,
      next_gate: recordedReport.result?.next_gate ?? "RETURN_TO_ROUTER",
      result: recordedReport.result,
    });
  }

  if (body.finalize_report === true) {
    const reportRef = `supabase://public.lf_operation_execution_steps/${e.execution_id}/report_output`;
    const recordedReport = await rpc(config, fetchFn, "lf_profile_native_bridge_record_report_v1", {
      p_execution_id: e.execution_id,
      p_evidence_ref: reportRef,
      p_actor_execution_id: e.execution_id,
    });
    if (recordedReport.error) return recordedReport.error;
    if (recordedReport.result?.status !== "PROFILE_EXECUTION_COMPLETED") {
      return respond({
        outcome: "BLOCKED",
        phase: "REPORT_RECORD",
        code: recordedReport.result?.blocking_code ?? "PROFILE_NATIVE_REPORT_RECORD_REJECTED",
        execution_id: e.execution_id,
        profile_code: e.target_code,
        result: recordedReport.result,
      }, 409);
    }
    return respond({
      outcome: "TERMINAL",
      phase: "PROFILE_EXECUTION_COMPLETED",
      code: null,
      execution_id: e.execution_id,
      profile_code: e.target_code,
      next_gate: recordedReport.result?.next_gate ?? "RETURN_TO_ROUTER",
      result: recordedReport.result,
    });
  }

  // The pre-model bridge must never be reentered to complete an existing 9/11
  // or 10/11 execution. Read canonical step states and hand off the next gate.
  const postModel = await resolveExistingPostModelStep(e, result, config, fetchFn);
  if (postModel) return postModel;

  // Post-model submission is accepted only from this already-authorized OIDC
  // continuation transport. The model supplies only its RAW profile output;
  // deterministic validity must come from the source-bound canonical runner.
  if (Object.prototype.hasOwnProperty.call(body, "profile_output")) {
    if (result.status !== "NATIVE_MODEL_INPUT_READY") {
      return blocked("PROFILE_NATIVE_OUTPUT_NOT_REQUESTED", 409);
    }
    const profileOutput = body.profile_output;
    const validation = body.validation_result;
    const rawEvidenceRef = body.raw_evidence_ref;
    const validatorEvidenceRef = body.validator_evidence_ref;
    if (
      !profileOutput || typeof profileOutput !== "object" || Array.isArray(profileOutput) ||
      !validation || typeof validation !== "object" || Array.isArray(validation) ||
      typeof rawEvidenceRef !== "string" || !rawEvidenceRef.startsWith("actions://") ||
      typeof validatorEvidenceRef !== "string" || !validatorEvidenceRef.startsWith("actions://")
    ) return blocked("PROFILE_NATIVE_OUTPUT_SUBMISSION_INVALID", 400);

    const receipt = validation as Payload;
    const blockingCodes = receipt.blocking_codes;
    const validatorErrors = receipt.validator_errors;
    if (
      receipt.schema !== "PROFILE_OUTPUT_VALIDATION_RESULT_V1" ||
      receipt.status !== "CANDIDATE_OUTPUT_PARITY_OBSERVED" ||
      receipt.structural_check_executed !== true ||
      receipt.profile_validator_executed !== true ||
      receipt.source_readback_matched !== true ||
      receipt.independent_review_executed !== false ||
      receipt.provider_attested !== false ||
      receipt.admission_authorized !== false ||
      receipt.profile_write_authorized !== false ||
      receipt.runtime_activation_authorized !== false ||
      !Array.isArray(blockingCodes) || blockingCodes.length !== 0 ||
      !Array.isArray(validatorErrors) || validatorErrors.length !== 0 ||
      typeof receipt.raw_output_sha256 !== "string" ||
      !/^[0-9a-f]{64}$/.test(receipt.raw_output_sha256)
    ) return blocked("PROFILE_NATIVE_OUTPUT_VALIDATOR_RECEIPT_NOT_PASS", 409);

    const recorded = await rpc(config, fetchFn, "lf_profile_native_bridge_record_output_v1", {
      p_execution_id: e.execution_id,
      p_profile_output: profileOutput,
      p_validation: {
        valid: true,
        errors: validatorErrors,
        blocking_codes: blockingCodes,
        source_bound_validation: receipt,
      },
      p_raw_evidence_ref: rawEvidenceRef,
      p_validator_evidence_ref: validatorEvidenceRef,
      p_actor_execution_id: e.execution_id,
    });
    if (recorded.error) return recorded.error;
    if (recorded.result?.status !== "NATIVE_PRODUCER_VALIDATED") {
      return respond({
        outcome: "BLOCKED",
        phase: "OUTPUT_RECORD",
        code: recorded.result?.blocking_code ?? "PROFILE_NATIVE_OUTPUT_RECORD_REJECTED",
        execution_id: e.execution_id,
        profile_code: e.target_code,
        result: recorded.result,
      }, 409);
    }
    return respond({
      outcome: "CONTINUATION_REQUIRED",
      phase: "INDEPENDENT_SEMANTIC_JUDGE_REQUIRED",
      code: null,
      execution_id: e.execution_id,
      profile_code: e.target_code,
      next_action: "RUN_EXISTING_INDEPENDENT_SEMANTIC_JUDGE",
      result: recorded.result,
    });
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
