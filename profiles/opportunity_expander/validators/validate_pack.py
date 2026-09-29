#!/usr/bin/env python3
from pathlib import Path
import json, sys

ROOT = Path(__file__).resolve().parents[1]

def load_json(rel):
    return json.loads((ROOT / rel).read_text(encoding="utf-8"))

def fail(msg):
    print(f"FAIL: {msg}")
    raise SystemExit(1)

manifest = load_json("manifest.json")
schema = load_json("schemas/output.schema.json")
evals = load_json("evals/eval_matrix.json")
good = load_json("examples/good_output.json")
bad = load_json("examples/bad_output.json")

for rel in manifest["required_files"] + manifest["selected_optional_files"]:
    p = ROOT / rel
    if not p.exists() or not p.read_text(encoding="utf-8").strip():
        fail(f"missing or empty file: {rel}")

expected_statuses = {
    "READY_FOR_REVIEW",
    "NEEDS_CAPABILITY_CONTEXT",
    "RETURN_TO_WORKER_FOR_DIVERGENCE",
    "BLOCKED",
}
expected_reasons = {
    "READY",
    "CAPABILITY_CONTEXT_REQUIRED",
    "REDUNDANT_SET",
    "INCOMPLETE_OPPORTUNITY",
    "SCOPE_MUTATION",
    "OUTPUT_CONTRACT",
    "AUTHORITY_OVERREACH",
}
status_enum = set(schema["properties"]["status"]["enum"])
reason_enum = set(schema["properties"]["reason_code"]["enum"])
if status_enum != expected_statuses:
    fail(f"status enum mismatch: {status_enum}")
if reason_enum != expected_reasons:
    fail(f"reason enum mismatch: {reason_enum}")

def validate_opportunity(op):
    required = {
        "id","lane","idea","mechanism","potential_value","required_data","risk",
        "experiment","confidence","evidence_refs","requires_scope_change"
    }
    if not required.issubset(op):
        fail(f"incomplete opportunity: {op.get('id')}")
    if not op["evidence_refs"] or any(not str(x).strip() for x in op["evidence_refs"]):
        fail(f"missing evidence refs: {op.get('id')}")

for op in good["user_payload"]["opportunities"]:
    validate_opportunity(op)
if good["status"] != "READY_FOR_REVIEW" or good["reason_code"] != "READY":
    fail("good fixture not ready")
if not good["internal_envelope"]["scope_guard_passed"]:
    fail("good fixture scope guard failed")
if not any(op["lane"] == "FRONTIER" for op in good["user_payload"]["opportunities"]):
    fail("good fixture lacks frontier")
if good["capability_requests"]:
    fail("good fixture unexpectedly requests capability")

if bad["status"] != "RETURN_TO_WORKER_FOR_DIVERGENCE" or bad["reason_code"] != "REDUNDANT_SET":
    fail("bad fixture expected redundant return")
if bad["internal_envelope"]["redundancy_check"] != "FAIL":
    fail("bad fixture does not demonstrate redundancy failure")

ids = {c["id"] for c in evals["cases"]}
required_cases = {
    "excel_bulk_upload_expands_beyond_commodity",
    "commodity_only_set_is_rejected",
    "missing_capability_context_fails_closed",
    "capability_context_resolved_second_pass",
    "silent_scope_mutation_is_blocked",
    "authority_overreach_is_blocked",
    "missing_opportunity_evidence_returns_for_repair",
    "frontier_missing_data_becomes_experiment_dependency",
}
if ids != required_cases:
    fail(f"eval case set mismatch: {ids}")

ecd = manifest["external_capability_discovery"]
if ecd["role"] != "CONSUMER_NOT_OWNER" or ecd["free_search_inside_profile"] is not False:
    fail("external capability discovery authority invalid")
if manifest["runtime_enabled"] or manifest["production_authorization"] or manifest["scheduler_authorization"]:
    fail("runtime/production/scheduler must remain disabled")
if manifest["prototype_pr_756_disposition"] != "PREINVESTIGATION_ONLY_NOT_OFFICIAL_IMPLEMENTATION":
    fail("prototype disposition invalid")

print("PASS: Opportunity Expander candidate pack deterministic validation")
