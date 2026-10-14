/**
 * M10.5/CP2 sole Edge adapter. OIDC identity is checked by the existing caller.
 * No release promotion, SQL recuration, synthetic receipt or direct production activation.
 */
export const CP2_PREFLIGHT_ACTION = "ig_m105_cp2_edge_preflight_v1";
export const CP2_EXECUTE_ACTION = "ig_m105_cp2_edge_screen_v1";

export class Cp2Fault extends Error {
  constructor(public code: string, public status = 409) { super(code); }
}

type BridgeConfig = {
  supabaseUrl: string;
  serviceRoleKey: string;
  recurationTimeoutMs: number;
};
type FetchLike = (input: string | URL | Request, init?: RequestInit) => Promise<Response>;
type RecordValue = Record<string, unknown>;
const isObj = (x: unknown): x is RecordValue => !!x && typeof x === "object" && !Array.isArray(x);
const isId = (x: unknown): x is number => typeof x === "number" && Number.isSafeInteger(x) && x > 0;

async function request(config: BridgeConfig, fetchFn: FetchLike, path: string, body: RecordValue): Promise<unknown> {
  let response: Response;
  try {
    response = await fetchFn(config.supabaseUrl + path, {
      method: "POST",
      headers: {
        authorization: `Bearer ${config.serviceRoleKey}`,
        apikey: config.serviceRoleKey,
        "content-type": "application/json",
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(path.startsWith("/functions/") ? config.recurationTimeoutMs : 20_000),
    });
  } catch { throw new Cp2Fault("CP2_CANONICAL_TRANSPORT_FAILED", 502); }
  if (!response.ok) throw new Cp2Fault("CP2_CANONICAL_PROVIDER_REJECTED", 502);
  try { return await response.json(); }
  catch { throw new Cp2Fault("CP2_PROVIDER_RESPONSE_INVALID", 502); }
}

export async function cp2Context(config: BridgeConfig, fetchFn: FetchLike): Promise<{
  screen_ids: number[]; release: RecordValue;
}> {
  const response = await request(config, fetchFn, "/rest/v1/rpc/fn_ig_m105_cp2_dispatch_context_v1", {});
  if (!isObj(response) || response.status !== "AUTHORIZED_CONTEXT" || response.dispatch_permitted !== true) {
    throw new Cp2Fault("CP2_AUTHENTIC_RELEASE_OR_SIGNED_AUTHORITY_MISSING");
  }
  const scope = response.scope, release = response.release;
  if (!isObj(scope) || !isObj(release)
    || scope.schema_version !== "M105_SCOPE_SNAPSHOT_V1"
    || !Array.isArray(scope.screen_ids) || scope.screen_ids.length !== 13
    || !scope.screen_ids.every(isId) || new Set(scope.screen_ids).size !== 13
    || typeof release.version !== "string" || typeof release.previous_version !== "string"
    || release.version === release.previous_version
    || typeof release.manifest_sha256 !== "string"
    || !/^[0-9a-f]{64}$/.test(release.manifest_sha256)) {
    throw new Cp2Fault("CP2_AUTHORITY_SCOPE_OR_RELEASE_DRIFT");
  }
  return {screen_ids: scope.screen_ids as number[], release};
}

function edgeRunId(result: RecordValue): number | null {
  const nested = isObj(result.result) ? result.result : {};
  const worker = isObj(nested.worker_spec) ? nested.worker_spec : {};
  const x = nested.run_id ?? nested.latest_run_id ?? worker.latest_run_id;
  return isId(x) ? x : null;
}

export async function executeCp2(
  config: BridgeConfig, fetchFn: FetchLike, action: string, body: RecordValue,
): Promise<{status: number; result: RecordValue}> {
  const authority = await cp2Context(config, fetchFn);
  if (action === CP2_PREFLIGHT_ACTION) {
    return {status: 200, result: {
      outcome: "READY", scope: "IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.5/CP2",
      pantalla_ids: authority.screen_ids, release_version: authority.release.version,
      production_activation: false,
    }};
  }
  if (action !== CP2_EXECUTE_ACTION || !isId(body.pantalla_id)
     || Object.keys(body).some((k) => !["action", "pantalla_id"].includes(k))) {
    throw new Cp2Fault("CP2_ONE_SCREEN_INPUT_REQUIRED", 400);
  }
  const pantallaId = body.pantalla_id;
  if (!authority.screen_ids.includes(pantallaId)) throw new Cp2Fault("CP2_SCREEN_OUTSIDE_FROZEN_COHORT", 400);

  // The actual Edge orchestrator, NOT the SQL recuration queue.
  const edge = await request(config, fetchFn, "/functions/v1/input-governance-agent-v1", {
    pantalla_id: pantallaId, consumer: "STORY_CREATOR",
  });
  if (!isObj(edge)) throw new Cp2Fault("CP2_EDGE_RESPONSE_INVALID");
  if (edge.status === "VALIDATOR_RESUME_REQUIRED") {
    return {status: 202, result: {
      outcome: "CONTINUATION_REQUIRED", pantalla_id: pantallaId,
      code: "VALIDATOR_RESUME_REQUIRED", production_activation: false,
    }};
  }
  const nested = isObj(edge.result) ? edge.result : {};
  if (!["READY","BLOCKED","HUMAN_DECISION_REQUIRED"].includes(String(nested.status ?? ""))) {
    throw new Cp2Fault("CP2_EDGE_NONTERMINAL");
  }
  const runId = edgeRunId(edge);
  if (!runId) throw new Cp2Fault("CP2_EDGE_RUN_ID_MISSING");
  const before = await request(config, fetchFn, "/rest/v1/rpc/fn_ig_m105_cp2_screen_readback_v1",
    {p_pantalla_id: pantallaId});
  if (!Array.isArray(before) || before.length !== 1 || !isObj(before[0])
      || before[0].run_id !== runId) throw new Cp2Fault("CP2_EDGE_RUN_READBACK_MISMATCH");

  const attestation = await request(config, fetchFn, "/rest/v1/rpc/fn_ig_m105_cp2_attest_run_v1",
    {p_run_id: runId});
  if (!isObj(attestation) || attestation.status !== "PERSISTED_VERIFIED"
    || attestation.run_id !== runId || !isId(attestation.receipt_id)) {
    throw new Cp2Fault("CP2_INDEPENDENT_SIGNED_RECEIPT_REQUIRED");
  }
  const after = await request(config, fetchFn, "/rest/v1/rpc/fn_ig_m105_cp2_screen_readback_v1",
    {p_pantalla_id: pantallaId});
  if (!Array.isArray(after) || after.length !== 1 || !isObj(after[0])
    || after[0].run_id !== runId) throw new Cp2Fault("CP2_POST_ATTEST_RUN_MISMATCH");
  const verdict = after[0].cp2_verdict;
  return {
    status: verdict === "PASS_CP2" ? 200 : 409,
    result: {
      outcome: verdict === "PASS_CP2" ? "VERIFIED_EDGE_RUN" : "BLOCKED",
      cp2_verdict: typeof verdict === "string" ? verdict : "INVALID_VERDICT",
      pantalla_id: pantallaId, run_id: runId,
      signed_receipt_id: attestation.receipt_id,
      release_version: authority.release.version, production_activation: false,
    },
  };
}
