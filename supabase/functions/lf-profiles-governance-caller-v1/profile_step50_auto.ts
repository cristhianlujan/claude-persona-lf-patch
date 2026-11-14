// Candidate only: run Step 50 inside the EXISTING authorized profile continuation.
// A Responses API invocation is an OpenAI API producer, NOT a ChatGPT-native receipt.
export type Step50AutoConfig = {
  enabled: boolean;
  githubToken?: string;
  openaiApiKey?: string;
  openaiModel?: string;
  validatorUrl?: string;
  validatorToken?: string;
};
type Dict = Record<string, unknown>;
type Fetcher = (input: string | URL | Request, init?: RequestInit) => Promise<Response>;
export type Step50AutoResult =
  | { ok: false; code: string }
  | { ok: true; profileOutput: Dict; validation: Dict; modelRef: string; validatorRef: string; producer: "OPENAI_RESPONSES_API" };

function object(x: unknown): x is Dict {
  return x !== null && typeof x === "object" && !Array.isArray(x);
}
function sha256(bytes: Uint8Array): Promise<string> {
  return crypto.subtle.digest("SHA-256", new Uint8Array(bytes)).then(b =>
    [...new Uint8Array(b)].map(n => n.toString(16).padStart(2, "0")).join(""));
}
const sha = (v: string) => sha256(new TextEncoder().encode(v));
async function json(response: Response): Promise<Dict | null> {
  try { const value: unknown = await response.json(); return object(value) ? value : null; }
  catch { return null; }
}
function outputText(data: Dict): string | null {
  if (typeof data.output_text === "string") return data.output_text;
  const output = data.output;
  if (!Array.isArray(output)) return null;
  const texts: string[] = [];
  for (const item of output) {
    if (!object(item) || !Array.isArray(item.content)) continue;
    for (const piece of item.content) {
      if (object(piece) && piece.type === "output_text" && typeof piece.text === "string") texts.push(piece.text);
    }
  }
  return texts.length ? texts.join("") : null;
}

// Do not accept model status from a request body. Status is the source-bound SQL result.
export async function executeStep50Automatically(
  prepared: Dict,
  sourceRevision: string,
  repository: string,
  targetPath: string,
  config: Step50AutoConfig,
  fetchFn: Fetcher,
): Promise<Step50AutoResult> {
  const fail = (code: string): Step50AutoResult => ({ ok: false, code });
  if (prepared.status !== "NATIVE_MODEL_INPUT_READY" || prepared.next_step !== "execute_profile" ||
      prepared.operation_code !== "EJECUCION_PERFIL_LF") return fail("STEP50_PREDECESSORS_NOT_READY");
  if (!config.enabled) return fail("STEP50_AUTO_NOT_ENABLED");
  if (!config.githubToken || !config.openaiApiKey || !config.openaiModel ||
      !config.validatorUrl || !config.validatorToken) return fail("STEP50_PRODUCER_OR_VALIDATOR_NOT_CONFIGURED");
  if (!/^https:\/\//.test(config.validatorUrl)) return fail("STEP50_VALIDATOR_HTTPS_REQUIRED");
  if (!/^[0-9a-f]{40}$/.test(sourceRevision) ||
      !/^profiles\/[a-z0-9_-]+\/SKILL\.md$/.test(targetPath) ||
      !/^[a-zA-Z0-9_.-]+\/[a-zA-Z0-9_.-]+$/.test(repository) ||
      prepared.profile_source_ref === undefined ||
      !/^sha256:[0-9a-f]{64}$/.test(String(prepared.profile_source_digest || ""))) {
    return fail("STEP50_SOURCE_BINDING_INVALID");
  }
  // Fetch the EXACT authorized profile source, never execute a profile name as a prompt.
  let source: Dict | null;
  try {
    const r = await fetchFn(`https://api.github.com/repos/${repository}/contents/${targetPath}?ref=${sourceRevision}`, {
      headers: { authorization: `Bearer ${config.githubToken}`, accept: "application/vnd.github+json" },
      signal: AbortSignal.timeout(15_000),
    });
    if (!r.ok) return fail("STEP50_SOURCE_FETCH_REJECTED");
    source = await json(r);
  } catch { return fail("STEP50_SOURCE_FETCH_FAILED"); }
  if (!source || source.type !== "file" || typeof source.content !== "string") return fail("STEP50_SOURCE_READBACK_INVALID");
  let sourceBytes: Uint8Array;
  try {
    sourceBytes = Uint8Array.from(atob(source.content.replace(/\s/g, "")), c => c.charCodeAt(0));
  } catch { return fail("STEP50_SOURCE_BASE64_INVALID"); }
  if (`sha256:${await sha256(sourceBytes)}` !== prepared.profile_source_digest) return fail("STEP50_SOURCE_SHA256_DRIFT");
  const sourceText = new TextDecoder("utf-8", { fatal: true }).decode(sourceBytes);
  const request = prepared.literal_request;
  if (typeof request !== "string" || !request.trim()) return fail("STEP50_LITERAL_REQUEST_MISSING");
  const input = {
    operation_code: "EJECUCION_PERFIL_LF",
    execution_id: prepared.execution_id,
    profile_code: prepared.profile_code,
    literal_request: request,
    input_governance: prepared.input_governance ?? null, // Step 40, profile-owned
    context_capsule: prepared.context_capsule ?? null,   // Step 45
    research_baseline: prepared.research_baseline ?? null, // Step 47
    ig_open_work: prepared.ig_open_work ?? [],
    read_only: true, no_product_write: true,
  };
  // A real model call, not a local GPT-chat draft. No credentials are passed to the model.
  let model: Dict | null;
  try {
    const r = await fetchFn("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: {
        authorization: `Bearer ${config.openaiApiKey}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        model: config.openaiModel,
        instructions: sourceText + "\nReturn one JSON object. Do not execute external effects.",
        input: JSON.stringify(input),
        text: { format: { type: "json_object" } },
      }),
      signal: AbortSignal.timeout(90_000),
    });
    if (!r.ok) return fail("STEP50_MODEL_API_REJECTED");
    model = await json(r);
  } catch { return fail("STEP50_MODEL_API_FAILED"); }
  if (!model || model.status !== "completed" || typeof model.id !== "string" ||
      typeof model.model !== "string") return fail("STEP50_MODEL_COMPLETION_UNVERIFIED");
  const raw = outputText(model);
  if (!raw) return fail("STEP50_MODEL_RAW_MISSING");
  let profile: unknown;
  try { profile = JSON.parse(raw); } catch { return fail("STEP50_MODEL_JSON_INVALID"); }
  if (!object(profile)) return fail("STEP50_MODEL_OUTPUT_NOT_OBJECT");
  const trace = object(profile.traceability) ? { ...profile.traceability } : {};
  // Do not allow the model to self-assert canonical step state or false origin.
  delete trace.step50_status;
  delete trace.governed_step50_executed;
  delete trace.no_issue_opened;
  delete trace.no_label_applied;
  profile.traceability = {
    ...trace,
    producer: "OPENAI_RESPONSES_API",
    profile_output_origin: "OPENAI_RESPONSES_API",
    model_id: model.model,
    model_response_id: model.id,
    native_model_call_receipt: null, // API response is not a ChatGPT-native attestation
    identity_verified: false,
  };
  const rawOutputSha = await sha(JSON.stringify(profile));
  // Existing profile-bound canonical validator MUST actually execute and return a receipt.
  let receipt: Dict | null;
  try {
    const r = await fetchFn(config.validatorUrl, {
      method: "POST",
      headers: { authorization: `Bearer ${config.validatorToken}`, "content-type": "application/json" },
      body: JSON.stringify({
        execution_id: prepared.execution_id, profile_code: prepared.profile_code,
        profile_source_ref: prepared.profile_source_ref,
        profile_source_digest: prepared.profile_source_digest,
        source_revision: sourceRevision, profile_output: profile,
        raw_output_sha256: rawOutputSha, producer: "OPENAI_RESPONSES_API",
      }),
      signal: AbortSignal.timeout(30_000),
    });
    if (!r.ok) return fail("STEP50_CANONICAL_VALIDATOR_REJECTED");
    receipt = await json(r);
  } catch { return fail("STEP50_CANONICAL_VALIDATOR_UNREACHABLE"); }
  if (!receipt || receipt.schema !== "PROFILE_OUTPUT_VALIDATION_RESULT_V1" ||
      receipt.status !== "CANDIDATE_OUTPUT_PARITY_OBSERVED" ||
      receipt.profile_validator_executed !== true || receipt.structural_check_executed !== true ||
      receipt.source_readback_matched !== true ||
      receipt.independent_review_executed !== false || receipt.provider_attested !== false ||
      receipt.admission_authorized !== false || receipt.profile_write_authorized !== false ||
      receipt.runtime_activation_authorized !== false ||
      !Array.isArray(receipt.blocking_codes) || receipt.blocking_codes.length !== 0 ||
      !Array.isArray(receipt.validator_errors) || receipt.validator_errors.length !== 0 ||
      receipt.raw_output_sha256 !== rawOutputSha ||
      typeof receipt.evidence_ref !== "string" || !/^https:\/\//.test(receipt.evidence_ref)) {
    return fail("STEP50_CANONICAL_VALIDATOR_RECEIPT_INVALID");
  }
  return {
    ok: true,
    profileOutput: profile,
    validation: receipt,
    modelRef: `https://api.openai.com/v1/responses/${encodeURIComponent(model.id)}`,
    validatorRef: receipt.evidence_ref,
    producer: "OPENAI_RESPONSES_API",
  };
}
