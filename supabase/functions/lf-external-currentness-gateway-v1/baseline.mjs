const HEX40 = /^[0-9a-f]{40}$/;
const HEX64 = /^[0-9a-f]{64}$/;
const DELTA_STATES = new Set(["NEW", "STALE", "MISSING"]);
const EDGE_SOURCE_STATES = new Set(["SOURCE_PRESENT", "RUNTIME_WITHOUT_SOURCE"]);

function fail(code) {
  throw new Error(code);
}

function object(value, code) {
  if (!value || typeof value !== "object" || Array.isArray(value)) fail(code);
  return value;
}

function integer(value, code) {
  if (!Number.isInteger(value) || value < 0) fail(code);
  return value;
}

function positiveRunId(value) {
  const raw = String(value ?? "");
  if (!/^[1-9][0-9]*$/.test(raw)) fail("BASELINE_APPROVAL_RUN_ID_INVALID");
  const parsed = Number(raw);
  if (!Number.isSafeInteger(parsed) || parsed <= 0) fail("BASELINE_APPROVAL_RUN_ID_INVALID");
  return parsed;
}

function mapStageItem(item) {
  const row = object(item, "BASELINE_STAGE_ITEM_INVALID");
  const kind = row.kind;
  const state = row.state;
  if ((kind !== "REPO" && kind !== "EDGE") || !DELTA_STATES.has(state)) {
    fail("BASELINE_STAGE_ITEM_INVALID");
  }

  if (kind === "REPO") {
    const path = typeof row.path === "string" ? row.path : "";
    if (!path) fail("BASELINE_STAGE_ITEM_INVALID");
    if (state === "MISSING") {
      return {
        source_kind: "REPO",
        object_key: path,
        state,
        definition_sha256: null,
        source_version: null,
        git_blob: null,
        verify_jwt: null,
        source_state: null,
        bytes: null,
        extension: typeof row.extension === "string" && row.extension ? row.extension : null,
      };
    }
    if (
      typeof row.sha256 !== "string" || !HEX64.test(row.sha256) ||
      typeof row.file_last_commit !== "string" || !HEX40.test(row.file_last_commit) ||
      typeof row.git_blob !== "string" || !HEX40.test(row.git_blob) ||
      !Number.isInteger(row.bytes) || row.bytes < 0
    ) {
      fail("BASELINE_STAGE_ITEM_INVALID");
    }
    return {
      source_kind: "REPO",
      object_key: path,
      state,
      definition_sha256: row.sha256,
      source_version: row.file_last_commit,
      git_blob: row.git_blob,
      verify_jwt: null,
      source_state: null,
      bytes: row.bytes,
      extension: typeof row.extension === "string" && row.extension ? row.extension : null,
    };
  }

  const slug = typeof row.slug === "string" ? row.slug : "";
  if (!slug) fail("BASELINE_STAGE_ITEM_INVALID");
  if (state === "MISSING") {
    return {
      source_kind: "EDGE",
      object_key: slug,
      state,
      definition_sha256: null,
      source_version: null,
      git_blob: null,
      verify_jwt: null,
      source_state: null,
      bytes: null,
      extension: null,
    };
  }
  if (
    typeof row.ezbr_sha256 !== "string" || !HEX64.test(row.ezbr_sha256) ||
    row.runtime_version === null || row.runtime_version === undefined || String(row.runtime_version).trim() === "" ||
    typeof row.verify_jwt !== "boolean" ||
    !EDGE_SOURCE_STATES.has(row.source_state)
  ) {
    fail("BASELINE_STAGE_ITEM_INVALID");
  }
  return {
    source_kind: "EDGE",
    object_key: slug,
    state,
    definition_sha256: row.ezbr_sha256,
    source_version: String(row.runtime_version),
    git_blob: null,
    verify_jwt: row.verify_jwt,
    source_state: row.source_state,
    bytes: null,
    extension: null,
  };
}

export function requireBaselineWriteEnabled(value) {
  if (value !== "true") fail("BASELINE_WRITE_DISABLED");
}

export function buildEnabledBaselineRpcRequest(body, identity, writeEnabled) {
  requireBaselineWriteEnabled(writeEnabled);
  return buildBaselineRpcRequest(body, identity);
}

export function buildBaselineRpcRequest(body, identity) {
  const request = object(body, "BASELINE_REQUEST_INVALID");
  const caller = object(identity, "BASELINE_IDENTITY_INVALID");
  const phase = request.phase;

  if (phase === "begin") {
    const observedMainSha = typeof request.observed_main_sha === "string" ? request.observed_main_sha : "";
    const reportSha256 = typeof request.report_sha256 === "string" ? request.report_sha256 : "";
    if (!HEX40.test(observedMainSha) || observedMainSha !== caller.sha) fail("BASELINE_MAIN_SHA_MISMATCH");
    if (!HEX64.test(reportSha256)) fail("BASELINE_REPORT_SHA_INVALID");
    return {
      phase,
      rpc: "lf_external_baseline_begin_v1",
      args: {
        p_observed_main_sha: observedMainSha,
        p_report_sha256: reportSha256,
        p_expected_repo_new: integer(request.repo_new, "BASELINE_COUNT_INVALID"),
        p_expected_repo_stale: integer(request.repo_stale, "BASELINE_COUNT_INVALID"),
        p_expected_repo_missing: integer(request.repo_missing, "BASELINE_COUNT_INVALID"),
        p_expected_edge_new: integer(request.edge_new, "BASELINE_COUNT_INVALID"),
        p_expected_edge_stale: integer(request.edge_stale, "BASELINE_COUNT_INVALID"),
        p_expected_edge_missing: integer(request.edge_missing, "BASELINE_COUNT_INVALID"),
        p_runtime_without_source_count: integer(request.runtime_without_source_count, "BASELINE_COUNT_INVALID"),
      },
    };
  }

  if (phase === "stage_batch") {
    const syncKey = typeof request.sync_key === "string" ? request.sync_key : "";
    if (!HEX64.test(syncKey) || !Number.isInteger(request.batch_no) || request.batch_no <= 0 || !Array.isArray(request.items)) {
      fail("BASELINE_STAGE_REQUEST_INVALID");
    }
    if (request.items.length < 1 || request.items.length > 100) fail("BASELINE_STAGE_BATCH_SIZE_INVALID");
    const mapped = request.items.map(mapStageItem);
    const keys = mapped.map((item) => `${item.source_kind}:${item.object_key}`);
    if (new Set(keys).size !== keys.length) fail("BASELINE_STAGE_DUPLICATE_ITEM");
    return {
      phase,
      rpc: "lf_external_baseline_stage_batch_v1",
      args: { p_sync_key: syncKey, p_batch_no: request.batch_no, p_items: mapped },
    };
  }

  if (phase === "approve") {
    if (caller.eventName !== "workflow_dispatch") fail("BASELINE_APPROVAL_EVENT_NOT_ALLOWED");
    const approveSyncKey = typeof request.approve_sync_key === "string" ? request.approve_sync_key : "";
    if (!HEX64.test(approveSyncKey)) fail("BASELINE_APPROVAL_SYNC_KEY_INVALID");
    const actor = typeof caller.actor === "string" ? caller.actor : "";
    if (!actor) fail("BASELINE_APPROVAL_ACTOR_MISSING");
    const workflowSha = typeof caller.sha === "string" ? caller.sha : "";
    if (!HEX40.test(workflowSha)) fail("BASELINE_APPROVAL_SHA_INVALID");
    return {
      phase,
      rpc: "lf_external_baseline_approve_v1",
      args: {
        p_sync_key: approveSyncKey,
        p_actor: actor,
        p_github_run_id: positiveRunId(caller.runId),
        p_workflow_sha: workflowSha,
      },
    };
  }

  if (phase === "finalize") {
    const syncKey = typeof request.sync_key === "string" ? request.sync_key : "";
    if (!HEX64.test(syncKey)) fail("BASELINE_FINALIZE_SYNC_KEY_INVALID");
    return {
      phase,
      rpc: "lf_external_baseline_finalize_v1",
      args: { p_sync_key: syncKey },
    };
  }

  fail("BASELINE_PHASE_NOT_ALLOWED");
}
