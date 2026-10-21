#!/usr/bin/env python3
from __future__ import annotations
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
FROZEN = ROOT / "docs/programming-agent/router_wave/RW1_05_C2_GPT_NATIVE_CANARY_FROZEN_V1.json"
CAPTURE = ROOT / "docs/programming-agent/router_wave/RW1_05_C2_GPT_NATIVE_CANARY_CAPTURE_V1.json"
REVIEW = ROOT / "docs/programming-agent/router_wave/RW1_05_C2_GPT_NATIVE_INDEPENDENT_SEMANTIC_REVIEW_V1.json"
RESUME = ROOT / "docs/programming-agent/router_wave/RW1_05_C2_GPT_NATIVE_SEMANTIC_RESUME_V2.json"
SCHEMA = ROOT / "profiles/evidence_lineage_reviewer_lf/schemas/output.schema.json"

RUN_ID = "EXEC-RW105-C2-GPT-NATIVE-CANARY-20261021-001"
RAW_SHA = "86cc34048f8436479acff5fe0830b03cc0a8bbaf6f98acfeb31e7d1c094def07"
INPUT_SHA = "81a55cf5c0ff80bfea428b775f1cfc2b0fa70e907a89b81619d158061276833e"
SOURCE_SHA = "9c27521f19d35331080b95af6cb57ddead5e69816be5550770f91125e5e48434"
PROFILE = "PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF"
FORBIDDEN_RESULT_AUTHORITY = {
    "operation_code","action_code","candidate_action_code","router_action_binding",
    "executor","executor_mode","effect_authority","downstream_execution_allowed","route_authority",
}

def sha_json(v):
    return hashlib.sha256(json.dumps(v,ensure_ascii=False,sort_keys=True,separators=(",",":")).encode()).hexdigest()

def sha_text(v):
    return hashlib.sha256(v.encode()).hexdigest()

def require(ok, code):
    if not ok:
        raise SystemExit(code)

frozen=json.loads(FROZEN.read_text())
capture=json.loads(CAPTURE.read_text())
review=json.loads(REVIEW.read_text())
resume=json.loads(RESUME.read_text())
schema=json.loads(SCHEMA.read_text())
runs=[r for r in frozen["runs"] if r["run_id"]==RUN_ID]
require(len(runs)==1,"FROZEN_RUN_NOT_UNIQUE")
run=runs[0]
raw=capture["raw_output"]

require(sha_text(run["input_literal"])==INPUT_SHA==run["input_sha256"],"INPUT_SHA_MISMATCH")
require(capture["run_id"]==RUN_ID and capture["profile_code"]==PROFILE,"CAPTURE_IDENTITY_MISMATCH")
require(capture["input_sha256"]==INPUT_SHA and capture["profile_source_sha256"]==SOURCE_SHA,"CAPTURE_BINDING_MISMATCH")
require(sha_json(raw)==RAW_SHA==capture["raw_output_sha256"],"RAW_SHA_MISMATCH")
require(sha_json(run["profile_source_manifest"])==SOURCE_SHA,"SOURCE_MANIFEST_SHA_MISMATCH")
for item in run["profile_source_manifest"]:
    p=ROOT/item["ref"]
    require(p.is_file(),"SOURCE_FILE_MISSING:"+item["ref"])
    require(sha_text(p.read_text())==item["content_sha256"],"SOURCE_CONTENT_DRIFT:"+item["ref"])

required=set(schema["required"])
require(required.issubset(raw),"SCHEMA_REQUIRED_FIELD_MISSING")
require(isinstance(raw["status"],str) and raw["status"] in schema["properties"]["status"]["enum"],"SCHEMA_STATUS_INVALID")
for key,typ in (
    ("claim",str),("authority_reads",list),("source_readbacks",list),
    ("revision_binding",dict),("structural_identifier_reconciliation",dict),
    ("evidence_map",list),("blocking_codes",list),("next_gate",str),("routing",dict),
):
    require(isinstance(raw[key],typ),"SCHEMA_TYPE_INVALID:"+key)
routing=raw["routing"]
routing_schema=schema["properties"]["routing"]
require(set(routing)==set(routing_schema["required"]),"SCHEMA_ROUTING_KEYS_INVALID")
require(routing["activation_path"] in routing_schema["properties"]["activation_path"]["enum"],"SCHEMA_ACTIVATION_INVALID")
require(routing["via"]==routing_schema["properties"]["via"]["const"],"SCHEMA_VIA_INVALID")
require(routing["pipeline_action"] in routing_schema["properties"]["pipeline_action"]["enum"],"SCHEMA_PIPELINE_ACTION_INVALID")
require(routing["resolution_target"] in routing_schema["properties"]["resolution_target"]["enum"],"SCHEMA_RESOLUTION_TARGET_INVALID")
expected_by_status={
 "PASS_EVIDENCE_LINEAGE":("CONTINUE","QUALITY_PACK"),
 "PASS_WITH_RESTRICTIONS":("CONTINUE_WITH_RESTRICTIONS","QUALITY_PACK"),
 "RETURN_TO_SOURCE_FOR_READBACK":("RETURN_TO_ORCHESTRATOR","SOURCE_READBACK"),
 "BLOCK_PIPELINE":("BLOCK_PIPELINE","NONE"),
}
require((routing["pipeline_action"],routing["resolution_target"])==expected_by_status[raw["status"]],"SCHEMA_STATUS_ROUTING_CONDITIONAL_FAILED")

obligations=run["scoped_semantic_obligation_manifest"]["obligations"]
observed={
 "/status":raw["status"],
 "/routing/pipeline_action":routing["pipeline_action"],
 "/routing/resolution_target":routing["resolution_target"],
}
for ob in obligations:
    require(ob["check_type"]=="EXACT_VALUE","OBLIGATION_CHECK_TYPE_INVALID")
    require(observed.get(ob["evidence_pointer"])==ob["expected_value"],"OBLIGATION_FAILED:"+ob["obligation_id"])

require(review["execution_id"]==RUN_ID and review["profile_code"]==PROFILE,"REVIEW_IDENTITY_MISMATCH")
require(review["input_sha256"]==INPUT_SHA and review["profile_source_sha256"]==SOURCE_SHA,"REVIEW_BINDING_MISMATCH")
require(review["raw_output_sha256"]==RAW_SHA,"REVIEW_RAW_BINDING_MISMATCH")
require(review["status"]=="PASS" and review["validator_status"]=="PASS","REVIEW_NOT_PASS")
require(review["verdict"]=="PASS_INDEPENDENT_SEMANTIC","REVIEW_VERDICT_INVALID")
require(review["reviewer_is_producer"] is False and review["producer_independence_proven"] is True,"REVIEW_INDEPENDENCE_INVALID")
require(review["producer_context_reuse"] is False and review["model_call_count"]==1,"REVIEW_EXECUTION_INVALID")
require(review["unsupported_claims"]==[] and review["blocking_codes"]==[],"REVIEW_BLOCKED")
require(all(o["result"]=="PASS" for o in review["obligations"]),"REVIEW_OBLIGATION_FAILED")

semantic=resume["semantic_result"]
require(resume["execution_id"]==RUN_ID and resume["producer_mode"]=="GPT_NATIVE","RESUME_IDENTITY_INVALID")
require(resume["raw_regenerated"] is False and resume["independent_judge_regenerated"] is False,"RESUME_REGEN_FORBIDDEN")
require(semantic["schema_version"]=="LF_ROUTER_SEMANTIC_RESULT_V1" and semantic["request_sha256"]==INPUT_SHA,"RESUME_SCHEMA_OR_REQUEST_INVALID")
require(semantic["positive_target_refs"]==[PROFILE] and semantic["allowed_scope"]==[PROFILE],"RESUME_TARGET_SCOPE_INVALID")
require(not FORBIDDEN_RESULT_AUTHORITY.intersection(semantic),"RESUME_RESULT_AUTHORITY_FORBIDDEN")
body={k:v for k,v in semantic.items() if k!="semantic_receipt_sha256"}
require(sha_json(body)==semantic["semantic_receipt_sha256"],"RESUME_RECEIPT_SHA_MISMATCH")

print(json.dumps({
 "status":"PASS_RW105_C2_FROZEN_NATIVE_BINDING",
 "execution_id":RUN_ID,
 "raw_output_sha256":RAW_SHA,
 "input_sha256":INPUT_SHA,
 "profile_source_sha256":SOURCE_SHA,
 "deterministic_schema_validation":"PASS",
 "independent_semantic_verdict":"PASS_INDEPENDENT_SEMANTIC",
 "semantic_resume_authority_free":True,
},sort_keys=True))
