/** LF Input Governance transport preflight V1.
 * Pure, deterministic, no network, no secrets and no remote privileges.
 * Field names only in failures: never place RAW values in logs or receipts.
 * Missing required fields and prohibited semantic metadata in RAW abort BEFORE fetch.
 */
export type LfTransportFault = Readonly<{
  code: "IG_TRANSPORT_REQUIRED_FIELD_INVALID" | "IG_TRANSPORT_RAW_FORBIDDEN_FIELD" | "IG_TRANSPORT_RAW_EMPTY";
  field: string;
  stage: string;
  continuation_allowed: false;
  downstream_call_attempted: false;
}>;

const FORBIDDEN_RAW = new Set(["semantic_receipt_sha256","catalog_sha256","request_sha256"]);
const isObject = (v: unknown): v is Record<string, unknown> =>
  v !== null && typeof v === "object" && !Array.isArray(v);
const missing = (v: unknown): boolean =>
  v === null || v === undefined ||
  (typeof v === "string" && (v.trim() === "" || v.trim() === "{}")) ||
  (isObject(v) && Object.keys(v).length === 0) ||
  (Array.isArray(v) && v.length === 0);
function readField(body: Record<string, unknown>, path: string): unknown {
  let val: unknown = body;
  for (const part of path.split(".")) {
    if (!isObject(val)) return undefined;
    val = val[part];
  }
  return val;
}
function fault(code: LfTransportFault["code"], field: string, stage: string): LfTransportFault {
  return {code,field,stage,continuation_allowed:false,downstream_call_attempted:false};
}
function scanRaw(value: unknown, path: string, stage: string): LfTransportFault | null {
  if (missing(value)) return fault("IG_TRANSPORT_RAW_EMPTY",path,stage);
  let parsed = value;
  if (typeof value === "string") {
    const trimmed = value.trim();
    if (trimmed.startsWith("{") || trimmed.startsWith("[")) {
      try { parsed = JSON.parse(trimmed); } catch { return null; } // plain RAW text may be non-JSON
    }
  }
  if (isObject(parsed)) {
    for (const [key, item] of Object.entries(parsed)) {
      if (FORBIDDEN_RAW.has(key)) return fault("IG_TRANSPORT_RAW_FORBIDDEN_FIELD",path+"."+key,stage);
      const child = scanRawInner(item,path+"."+key,stage);
      if (child) return child;
    }
  } else if (Array.isArray(parsed)) {
    for (let i=0; i<parsed.length; i++) {
      const child=scanRawInner(parsed[i],path+"["+i+"]",stage);
      if (child) return child;
    }
  }
  return null;
}
function scanRawInner(value: unknown, path: string, stage: string): LfTransportFault | null {
  if (isObject(value)) {
    for (const [key,item] of Object.entries(value)) {
      if (FORBIDDEN_RAW.has(key)) return fault("IG_TRANSPORT_RAW_FORBIDDEN_FIELD",path+"."+key,stage);
      const child=scanRawInner(item,path+"."+key,stage);
      if (child) return child;
    }
  } else if (Array.isArray(value)) {
    for(let i=0; i<value.length; i++) {
      const child=scanRawInner(value[i],path+"["+i+"]",stage);
      if (child) return child;
    }
  }
  return null;
}
function walkForRaw(obj: unknown, path: string, stage: string, depth: number): LfTransportFault | null {
  if (depth > 18) return fault("IG_TRANSPORT_REQUIRED_FIELD_INVALID",path,stage);
  if (isObject(obj)) {
    for (const [key,value] of Object.entries(obj)) {
      const next=path ? path+"."+key:key;
      if (["raw","RAW","raw_payload","raw_output","raw_input","profile_output"].includes(key)) {
        const problem=scanRaw(value,next,stage);
        if (problem) return problem;
      } else if (isObject(value) || Array.isArray(value)) {
        const problem=walkForRaw(value,next,stage,depth+1);
        if (problem) return problem;
      }
    }
  } else if (Array.isArray(obj)) {
    for(let i=0;i<obj.length;i++) {
      const problem=walkForRaw(obj[i],path+"["+i+"]",stage,depth+1);
      if(problem)return problem;
    }
  }
  return null;
}
export function validateLfIgTransport(
  stage: string, payload: unknown, required: readonly string[] = []
): LfTransportFault | null {
  if (!isObject(payload)) return fault("IG_TRANSPORT_REQUIRED_FIELD_INVALID","$",stage);
  for (const path of required) if (missing(readField(payload,path))) {
    return fault("IG_TRANSPORT_REQUIRED_FIELD_INVALID",path,stage);
  }
  return walkForRaw(payload,"",stage,0);
}
export const IG_RUNTIME_REQUIRED: Readonly<Record<string, readonly string[]>> = {
  "input-governance-agent-v1":["pantalla_id","consumer","ticket"],
  "input-governance-curator-v1":["pantalla_id","consumer","ticket"],
  "input-governance-validator-v1":["run_id","ticket"],
};
export const IG_RPC_REQUIRED: Readonly<Record<string, readonly string[]>> = {
  fn_input_governance_execute:["p_pantalla_id","p_consumer","p_ticket"],
  fn_input_governance_safe_autofix_v1:["p_run_id","p_ticket"],
  fn_input_governance_curator_materialize_v1:["p_pantalla_id","p_consumer","p_curator_identity","p_ticket"],
  fn_input_governance_curator_handoff_receipt_v1:["p_run_id","p_expected_curator_identity","p_ticket"],
  fn_input_governance_validator_handoff_assert_v1:["p_run_id","p_ticket"],
  fn_input_governance_validator_resume_context_v1:["p_run_id","p_ticket"],
  fn_input_governance_validator_validate_handoff_v1:["p_run_id","p_validator_identity","p_ticket"],
  lf_profile_native_bridge_prepare_v1:["p_execution_id","p_source_revision","p_source_digest","p_actor_execution_id"],
  lf_profile_skill_runtime_ticket_consume_v1:["p_ticket","p_execution_id","p_skill_code"],
  lf_profile_input_governance_runtime_ticket_consume_v1:["p_ticket","p_execution_id","p_pantalla_id","p_consumer"],
  fn_input_governance_queue_submit_oidc_v1:["p_pantalla_id","p_consumer","p_oidc_run_id"],
  fn_input_governance_queue_poll_oidc_v1:["p_request_id","p_oidc_run_id"],
};
