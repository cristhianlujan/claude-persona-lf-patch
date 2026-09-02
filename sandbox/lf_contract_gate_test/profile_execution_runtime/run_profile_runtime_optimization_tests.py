#!/usr/bin/env python3
"""56 deterministic regression cases for profile runtime optimization and fail-closed output."""
from __future__ import annotations

import ast
import json
from datetime import datetime, timezone
from pathlib import Path

from runtime_optimization_contract import (
    artifact_verification_decision,
    build_llama_cache_key,
    build_metrics,
    build_model_cache_key,
    effective_parallelism,
    governance_cache_key,
    governance_receipt_reusable,
    image_binding_complete,
    validate_batch_request_ids,
)

PASS = 0
TOTAL = 0


def check(family: str, name: str, condition: bool) -> None:
    global PASS, TOTAL
    TOTAL += 1
    if not condition:
        raise AssertionError(f"{family}/{name}")
    PASS += 1
    print(f"PASS {family} {name}")


def raises(code: str, fn) -> bool:
    try:
        fn()
    except ValueError as exc:
        return str(exc) == code
    return False


# A — Runtime cache (7)
base_llama = dict(runner_os="Linux", runner_arch="X64", toolchain_fingerprint="tool123", llama_commit="a"*40, llama_release="b7100")
k1 = build_llama_cache_key(**base_llama)
check("A", "cold_key_deterministic", k1 == build_llama_cache_key(**base_llama))
check("A", "llama_sha_invalidates", k1 != build_llama_cache_key(**{**base_llama, "llama_commit": "b"*40}))
check("A", "toolchain_invalidates", k1 != build_llama_cache_key(**{**base_llama, "toolchain_fingerprint": "tool999"}))
check("A", "release_invalidates", k1 != build_llama_cache_key(**{**base_llama, "llama_release": "b7101"}))
base_model = dict(runner_os="Linux", runner_arch="X64", model_id="Qwen2.5-VL-3B-Instruct-Q4_K_M.gguf", revision="5"*40, model_sha256="d"*64, mmproj_sha256="e"*64)
m1 = build_model_cache_key(**base_model)
check("A", "model_key_deterministic", m1 == build_model_cache_key(**base_model))
check("A", "model_sha_invalidates", m1 != build_model_cache_key(**{**base_model, "model_sha256": "f"*64}))
check("A", "mmproj_sha_invalidates", m1 != build_model_cache_key(**{**base_model, "mmproj_sha256": "1"*64}))

# B — Batch (7)
u1,u2,u3,u4 = "11111111-1111-4111-8111-111111111111","22222222-2222-4222-8222-222222222222","33333333-3333-4333-8333-333333333333","44444444-4444-4444-8444-444444444444"
check("B", "one_profile", validate_batch_request_ids([u1]) == [u1])
check("B", "three_profiles", len(validate_batch_request_ids([u1,u2,u3])) == 3)
check("B", "duplicate_blocked", raises("BATCH_REQUEST_ID_DUPLICATE", lambda: validate_batch_request_ids([u1,u1])))
check("B", "four_blocked", raises("BATCH_SIZE_INVALID", lambda: validate_batch_request_ids([u1,u2,u3,u4])))
check("B", "empty_blocked", raises("BATCH_SIZE_INVALID", lambda: validate_batch_request_ids([])))
check("B", "invalid_uuid_blocked", raises("BATCH_REQUEST_ID_INVALID", lambda: validate_batch_request_ids(["x"])))
check("B", "order_preserved", validate_batch_request_ids([u3,u1,u2]) == [u3,u1,u2])

# C — Concurrency (7)
check("C", "one_is_one", effective_parallelism(1,2) == 1)
check("C", "two_is_two", effective_parallelism(2,2) == 2)
check("C", "three_capped_two", effective_parallelism(3,3) == 2)
check("C", "three_requested_one", effective_parallelism(3,1) == 1)
check("C", "requested_many_capped", effective_parallelism(2,99) == 2)
check("C", "zero_parallel_blocked", raises("PARALLELISM_INVALID", lambda: effective_parallelism(2,0)))
check("C", "batch_overflow_blocked", raises("BATCH_SIZE_INVALID", lambda: effective_parallelism(4,2)))

# D — Visual evidence (7)
sha = "a"*64
check("D", "ui_bytes_present", artifact_verification_decision(profile_code="PERFIL-UI-ARCHITECT",screen_code="B2B-CARGA-001",image_sha256=sha) == "PASS")
check("D", "ui_bytes_absent", artifact_verification_decision(profile_code="PERFIL-UI-ARCHITECT",screen_code="B2B-CARGA-001",image_sha256=None) == "FAIL")
check("D", "quality_private_ref_no_bytes", artifact_verification_decision(profile_code="PERFIL-QUALITY-PACK",screen_code="B2B-CARGA-001",image_sha256=None) == "FAIL")
check("D", "product_bad_hash", artifact_verification_decision(profile_code="PERFIL-PRODUCT-DIRECTOR-LF",screen_code="B2B-CARGA-001",image_sha256="bad") == "FAIL")
check("D", "nonvisual_not_applicable", artifact_verification_decision(profile_code="PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF",screen_code="B2B-CARGA-001",image_sha256=None) == "NOT_APPLICABLE")
check("D", "no_screen_not_applicable", artifact_verification_decision(profile_code="PERFIL-QUALITY-PACK",screen_code=None,image_sha256=None) == "NOT_APPLICABLE")
check("D", "image_triplet_requires_all", image_binding_complete({"input_image_base64":"YQ==","input_image_media_type":"image/png","input_image_sha256":sha}) and not image_binding_complete({"input_image_sha256":sha}))

# E — Receipts / exactness (7)
ready = {"applicable":True,"status":"READY","continuation_allowed":True,"governance_receipt":{"decision":"PASS","currentness":"LIVE_CURRENT","screen_code":"B2B-CARGA-001","snapshot_hash":"b"*64}}
check("E", "ready_reusable", governance_receipt_reusable(ready,screen_code="B2B-CARGA-001"))
check("E", "screen_mismatch_blocked", not governance_receipt_reusable(ready,screen_code="OTHER"))
check("E", "stale_blocked", not governance_receipt_reusable({**ready,"governance_receipt":{**ready["governance_receipt"],"currentness":"STALE"}},screen_code="B2B-CARGA-001"))
check("E", "decision_fail_blocked", not governance_receipt_reusable({**ready,"governance_receipt":{**ready["governance_receipt"],"decision":"FAIL"}},screen_code="B2B-CARGA-001"))
check("E", "snapshot_missing_blocked", not governance_receipt_reusable({**ready,"governance_receipt":{**ready["governance_receipt"],"snapshot_hash":""}},screen_code="B2B-CARGA-001"))
check("E", "not_required_allowed", governance_receipt_reusable({"applicable":False,"status":"NOT_REQUIRED","continuation_allowed":True},screen_code=None))
check("E", "not_required_denied", not governance_receipt_reusable({"applicable":False,"status":"NOT_REQUIRED","continuation_allowed":False},screen_code=None))

# F — Failures / governance (7)
adapters=[{"adapter_code":"A1","adapter_metadata":{"canonical_adapter_id":"ADAPTER_LF_SHELL_PROFILE"}}]
g1=governance_cache_key(screen_code="B2B-CARGA-001",adapters=adapters,input_literal="review B2B-CARGA-001")
check("F", "governance_cache_stable", g1 == governance_cache_key(screen_code="B2B-CARGA-001",adapters=adapters,input_literal="review B2B-CARGA-001"))
check("F", "input_change_invalidates", g1 != governance_cache_key(screen_code="B2B-CARGA-001",adapters=adapters,input_literal="change B2B-CARGA-001"))
check("F", "screen_change_invalidates", g1 != governance_cache_key(screen_code="ONB_002",adapters=adapters,input_literal="review B2B-CARGA-001"))
check("F", "adapter_change_invalidates", g1 != governance_cache_key(screen_code="B2B-CARGA-001",adapters=[{"adapter_code":"A2","adapter_metadata":{"canonical_adapter_id":"OTHER"}}],input_literal="review B2B-CARGA-001"))
check("F", "governance_blocked_not_reusable", not governance_receipt_reusable({"applicable":True,"status":"BLOCKED","continuation_allowed":False},screen_code="B2B-CARGA-001"))
check("F", "governance_pending_not_reusable", not governance_receipt_reusable({"applicable":True,"status":"INPUT_GOVERNANCE_REQUIRED","continuation_allowed":False},screen_code="B2B-CARGA-001"))
check("F", "malformed_not_reusable", not governance_receipt_reusable({},screen_code="B2B-CARGA-001"))

# G — Quality / isolation / metrics (7)
metrics = build_metrics(queued_at="2026-09-01T00:00:00Z",started_at="2026-09-01T00:00:01Z",runtime_ready_at="2026-09-01T00:00:02Z",inference_started_at="2026-09-01T00:00:03Z",completed_at="2026-09-01T00:00:05Z",runtime_prepare_ms=900,model_download_ms=0,inference_ms=2000,cache_hit_runtime=True,cache_hit_model=True,batch_size=3,parallelism=2,batch_total_ms=2500)
check("G", "queue_latency", metrics["queue_latency_ms"] == 1000)
check("G", "total_ms", metrics["total_ms"] == 4000)
check("G", "warm_runtime_hit", metrics["cache_hit_runtime"] is True)
check("G", "warm_model_hit", metrics["cache_hit_model"] is True)
check("G", "batch_size_recorded", metrics["batch_size"] == 3)
check("G", "parallelism_recorded", metrics["parallelism"] == 2)
check("G", "per_profile_inference_independent", metrics["per_profile_inference_ms"] == 2000 and metrics["batch_total_ms"] == 2500)

# H — Quality Pack post-model fail-closed contract (3)
# Execute the exact enforcement functions from the queue-worker source without importing psycopg.
worker_path = Path(__file__).with_name("github_actions_queue_worker.py")
worker_tree = ast.parse(worker_path.read_text(encoding="utf-8"), filename=str(worker_path))
selected_names = {
    "_assistant_completion",
    "_blocked_result",
    "_quality_pack_profile_code",
    "_validate_quality_pack_completion",
    "_enforce_profile_output_contract",
}
selected_constants = {
    "QUALITY_PACK_PROFILE_CODE",
    "QUALITY_PACK_VERDICTS",
    "QUALITY_PACK_PASS_VERDICTS",
    "QUALITY_PACK_NONPASS_VERDICTS",
    "QUALITY_PACK_REQUIRED_KEYS",
    "QUALITY_PACK_SCORE_KEYS",
    "QUALITY_PACK_ROUTE_BY_VERDICT",
}
selected_nodes = []
for node in worker_tree.body:
    if isinstance(node, (ast.Assign, ast.AnnAssign)):
        targets = node.targets if isinstance(node, ast.Assign) else [node.target]
        names = {target.id for target in targets if isinstance(target, ast.Name)}
        if names & selected_constants:
            selected_nodes.append(node)
    elif isinstance(node, ast.FunctionDef) and node.name in selected_names:
        selected_nodes.append(node)
namespace = {"json": json}
exec(compile(ast.Module(body=selected_nodes, type_ignores=[]), str(worker_path), "exec"), namespace)

def qp_result(completion: str) -> dict:
    return {
        "status": "SUCCEEDED",
        "raw_output": f"User:\nnegative\n\nAssistant:\n{completion}",
        "package": {"request": {"profile_code": "PERFIL-QUALITY-PACK"}},
    }

bare = namespace["_enforce_profile_output_contract"](qp_result("PASS_TO_COMPOSER"))
check("H", "bare_pass_blocked", bare.get("status") == "BLOCKED" and bare.get("error_code") == "QUALITY_PACK_OUTPUT_NOT_JSON")
valid_return = {
    "review_id": "QP-NEG-001",
    "reviewed_artifact": "B2B-CARGA-001",
    "verdict": "RETURN_TO_ORCHESTRATOR",
    "score_breakdown": {
        "contract_schema_compliance": 5,
        "evidence_integrity": 0,
        "lf_safety_governance": 5,
        "handoff_readiness": 0,
        "leakage_scope_control": 5,
        "total": 15,
    },
    "evidence_map": [],
    "blocking_codes": ["VISUAL_BYTES_NOT_OBSERVED"],
    "repair_actions": [],
    "remaining_risks": ["visual evidence missing"],
    "next_gate": "AUTHORITY_OR_CONTEXT_RESOLUTION",
    "routing": {
        "activation_path": "ROUTER",
        "via": "ORCHESTRATOR",
        "pipeline_action": "RETURN_TO_ORCHESTRATOR",
        "resolution_target": "AUTHORITY_OR_CONTEXT_RESOLUTION",
    },
}
accepted = namespace["_enforce_profile_output_contract"](qp_result(json.dumps(valid_return)))
check("H", "valid_failclosed_return_accepted", accepted.get("status") == "SUCCEEDED" and accepted.get("normalized_profile_output",{}).get("verdict") == "RETURN_TO_ORCHESTRATOR")
invalid_pass = dict(valid_return)
invalid_pass["verdict"] = "PASS_TO_COMPOSER"
invalid_pass["blocking_codes"] = []
invalid_pass["routing"] = {
    "activation_path": "ROUTER",
    "via": "ORCHESTRATOR",
    "pipeline_action": "CONTINUE",
    "resolution_target": "COMPOSER",
}
blocked = namespace["_enforce_profile_output_contract"](qp_result(json.dumps(invalid_pass)))
check("H", "empty_evidence_pass_blocked", blocked.get("status") == "BLOCKED" and blocked.get("error_code") == "QUALITY_PACK_OUTPUT_CONTRACT_INVALID" and "PASS_EVIDENCE_MAP_EMPTY" in blocked.get("error_detail", ""))

contradictory_pass = dict(invalid_pass)
contradictory_pass["evidence_map"] = [{"evidence_type": "SHA-256", "evidence_value": "a" * 64}]
contradictory_pass["blocking_codes"] = ["BLOCK_PIPELINE"]
contradictory_pass["repair_actions"] = []
blocked = namespace["_enforce_profile_output_contract"](qp_result(json.dumps(contradictory_pass)))
check("H", "pass_with_blocker_blocked", blocked.get("status") == "BLOCKED" and "PASS_BLOCKING_CODES_NONEMPTY" in blocked.get("error_detail", ""))

pass_with_repair = dict(contradictory_pass)
pass_with_repair["blocking_codes"] = []
pass_with_repair["repair_actions"] = [{"required_fix": "repair before continuation"}]
blocked = namespace["_enforce_profile_output_contract"](qp_result(json.dumps(pass_with_repair)))
check("H", "pass_to_composer_with_repair_blocked", blocked.get("status") == "BLOCKED" and "PASS_TO_COMPOSER_REPAIR_ACTIONS_NONEMPTY" in blocked.get("error_detail", ""))

nonpass_without_blocker = dict(valid_return)
nonpass_without_blocker["blocking_codes"] = []
blocked = namespace["_enforce_profile_output_contract"](qp_result(json.dumps(nonpass_without_blocker)))
check("H", "nonpass_without_blocker_blocked", blocked.get("status") == "BLOCKED" and "NONPASS_BLOCKING_CODES_EMPTY" in blocked.get("error_detail", ""))

repo_root = Path(__file__).resolve().parents[3]
quality_schema = repo_root / "profiles/quality_pack/schemas/quality_review.schema.json"
runtime_schema = repo_root / "profiles/quality_pack/schemas/runtime_output.schema.json"
check("H", "quality_runtime_schema_exact", runtime_schema.is_file() and runtime_schema.read_bytes() == quality_schema.read_bytes())

assert TOTAL == 56, TOTAL
assert PASS == 56, PASS
print(f"PROFILE_RUNTIME_OPTIMIZATION_CASES={PASS}/{TOTAL}")
