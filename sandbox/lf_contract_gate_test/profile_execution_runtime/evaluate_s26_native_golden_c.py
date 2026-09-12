#!/usr/bin/env python3
"""Evaluate S26 Native Golden C through the independent-quality boundary."""

from __future__ import annotations

import hashlib
import importlib.util
import json
import subprocess
from datetime import datetime
from pathlib import Path
from typing import Any

from profile_runtime_runner import _build_lf_adapter_invocations
from semantic_mini_judge import canonical_json_sha256, partition_checks, validate_bundle
from semantic_obligation_manifest import build_check_bundle
from validate_profile_execution import build_receipt, validate_receipt

ROOT = Path(__file__).resolve().parents[3]
EVIDENCE = ROOT / "sandbox/lf_contract_gate_test/profile_execution_runtime/evidence/s26_native_golden_003"
RAW_PATH = EVIDENCE / "raw_output.json"
INPUT_PATH = EVIDENCE / "input.txt"
GOVERNED_CONTEXT_PATH = EVIDENCE / "governed_context_receipt.json"
METRICS_PATH = EVIDENCE / "metrics_plan.json"
PREPARE = ROOT / "sandbox/lf_contract_gate_test/profile_execution_runtime/prepare_s26_native_golden_c.py"
MATERIALIZATION_COMMIT = "de6d1e837d39dde92110ad06afc17c4caf9bf975"
MATERIALIZATION_COMMIT_AT = "2026-09-08T20:49:48+00:00"
PRODUCER_RUN_ID = "CHATGPT-NATIVE-S26-N08C-GOLDEN-C-001"


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def load_ui_validator():
    path = ROOT / "profiles/ui_architect/validators/validate_ui_architect_output.py"
    spec = importlib.util.spec_from_file_location("ui_architect_validator_s26_c", path)
    if spec is None or spec.loader is None:
        raise SystemExit("BLOCK_UI_VALIDATOR_LOAD")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.validate


def resolve_preflight() -> dict[str, Any]:
    completed = subprocess.run(
        ["python3", str(PREPARE)], cwd=ROOT, check=True, capture_output=True, text=True,
    )
    return json.loads(completed.stdout)


def materialized_raw_bytes() -> bytes:
    rel = RAW_PATH.relative_to(ROOT).as_posix()
    completed = subprocess.run(
        ["git", "-C", str(ROOT), "show", f"{MATERIALIZATION_COMMIT}:{rel}"],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    return completed.stdout


def build_adapter_invocations(preflight: dict[str, Any]) -> list[dict[str, Any]]:
    binding = load_json(EVIDENCE / "router_adapter_binding_snapshot.json")
    capsule_path = ROOT / "adapters/lf_shell_profile_adapter/runtime/runtime_capsule.yaml"
    content = capsule_path.read_text(encoding="utf-8")
    request_stub = {
        "execution_id": preflight["execution_id"],
        "profile_code": "PERFIL-UI-ARCHITECT",
        "lf_adapter_sources": [
            {
                "adapter_code": binding["adapter_code"],
                "assurance_revision": binding["assurance_revision"],
                "binding_ref": "sandbox/lf_contract_gate_test/profile_execution_runtime/evidence/s26_native_golden_003/router_adapter_binding_snapshot.json",
                "target_ref": binding["target_asset_code"],
                "ref": "adapters/lf_shell_profile_adapter/runtime/runtime_capsule.yaml",
                "content": content,
                "capsule_char_count": len(content),
            }
        ],
    }
    return _build_lf_adapter_invocations(request_stub)


def validate_depth(raw: dict[str, Any], ui_errors: list[dict[str, Any]], metrics: dict[str, Any]) -> dict[str, Any]:
    score = raw.get("score") if isinstance(raw, dict) else None
    if not isinstance(score, dict):
        raise SystemExit("BLOCK_DEPTH_SCORE_MISSING")
    minimum = metrics["depth"]["minimum_score"]
    total = score.get("total")
    if not isinstance(total, int) or total < minimum:
        raise SystemExit("BLOCK_DEPTH_SCORE_BELOW_THRESHOLD")
    evidence = score.get("evidence_by_criterion")
    required = {
        "layout_precision", "visual_hierarchy", "lf_system_fidelity", "state_mapping", "handoff_quality"
    }
    if not isinstance(evidence, dict) or set(evidence) != required:
        raise SystemExit("BLOCK_DEPTH_CRITERION_EVIDENCE_COVERAGE")
    for key in sorted(required):
        item = evidence[key]
        if not isinstance(item, dict) or not item.get("refs") or not isinstance(item.get("summary"), str) or len(item["summary"].strip()) < 12:
            raise SystemExit(f"BLOCK_DEPTH_CRITERION_EVIDENCE_INVALID:{key}")
    if ui_errors:
        raise SystemExit("BLOCK_DEPTH_UI_VALIDATOR_NOT_PASS")
    return {
        "status": "CANDIDATE_PASS_PRE_INDEPENDENT_REVIEW",
        "score_total": total,
        "minimum_score": minimum,
        "criterion_evidence_count": len(required),
        "ui_validator_pass": True,
        "final_pass_requires_independent_quality": True,
    }


def main() -> int:
    preflight = resolve_preflight()
    if preflight.get("verdict") != "PASS":
        raise SystemExit("BLOCK_PREFLIGHT_NOT_PASS")

    raw = load_json(RAW_PATH)
    input_literal = INPUT_PATH.read_text(encoding="utf-8")
    governed = load_json(GOVERNED_CONTEXT_PATH)
    metrics = load_json(METRICS_PATH)

    if governed != preflight["governed_context_receipt"]:
        raise SystemExit("BLOCK_GOVERNED_CONTEXT_RECEIPT_READBACK_MISMATCH")
    if canonical_json_sha256(governed) != preflight["governed_context_receipt_sha256"]:
        raise SystemExit("BLOCK_GOVERNED_CONTEXT_RECEIPT_SHA_MISMATCH")

    raw_file_bytes = RAW_PATH.read_bytes()
    immutable_bytes = materialized_raw_bytes()
    if raw_file_bytes != immutable_bytes:
        raise SystemExit("BLOCK_RAW_OUTPUT_NOT_EQUAL_MATERIALIZATION_COMMIT")
    raw_byte_sha = sha256_bytes(immutable_bytes)
    raw_semantic_sha = canonical_json_sha256(raw)

    ui_errors = load_ui_validator()(raw)
    if ui_errors:
        print(json.dumps({"status": "BLOCK_UI_VALIDATOR", "errors": ui_errors}, ensure_ascii=False, indent=2))
        return 1

    manifest = preflight["obligation_manifest"]
    check_bundle = validate_bundle(build_check_bundle(manifest, raw, raw_output_sha256=raw_semantic_sha))
    deterministic, semantic = partition_checks(check_bundle)
    bad_deterministic = [item.as_dict() for item in deterministic if item.verdict != "COMPLIES"]
    if bad_deterministic:
        print(json.dumps({"status": "BLOCK_DETERMINISTIC_OBLIGATION", "checks": bad_deterministic}, indent=2))
        return 1
    semantic_ids = sorted(item["check_id"] for item in semantic)
    if semantic_ids != ["OVERFLOW-DIRECTION", "PAGINATION-DIRECTION"]:
        raise SystemExit("BLOCK_SEMANTIC_COVERAGE")

    depth_gate = validate_depth(raw, ui_errors, metrics)

    started_at = datetime.fromisoformat(metrics["execution_started_at"])
    completed_at = datetime.fromisoformat(MATERIALIZATION_COMMIT_AT)
    latency_ms = (completed_at - started_at).total_seconds() * 1000
    if latency_ms < 0:
        raise SystemExit("BLOCK_LATENCY_NEGATIVE")
    latency = {
        "status": "PASS",
        "metric": metrics["latency_observable"]["metric"],
        "started_at": metrics["execution_started_at"],
        "completed_at": MATERIALIZATION_COMMIT_AT,
        "value_ms": round(latency_ms, 3),
        "claim_scope": "OBSERVABLE_E2E_PERSISTENCE_UPPER_BOUND_NOT_MODEL_INFERENCE_LATENCY",
    }
    token_usage = {
        "status": "NOT_OBSERVED",
        "policy": metrics["token_usage"]["policy"],
        "estimated": False,
        "reason": "Exact token telemetry is not exposed by the native ChatGPT execution boundary used for this run.",
    }
    if token_usage["status"] not in metrics["token_usage"]["allowed_status"] or token_usage["estimated"] is not False:
        raise SystemExit("BLOCK_TOKEN_USAGE_STATUS_INVALID")

    native_request = {
        "schema": "LF_NATIVE_CHAT_EXECUTION_REQUEST_V1",
        "execution_id": preflight["execution_id"],
        "executor_mode": "GPT_NATIVE",
        "execution_contract_sha256": preflight["execution_contract_sha256"],
        "governed_context_receipt_sha256": preflight["governed_context_receipt_sha256"],
        "obligation_manifest_sha256": preflight["obligation_manifest_sha256"],
        "input_sha256": preflight["input_sha256"],
        "profile_source_sha256": preflight["profile_source_sha256"],
        "context_fingerprint": preflight["context_fingerprint"],
    }
    response_readback = {
        "schema": "LF_NATIVE_CHAT_OUTPUT_READBACK_V1",
        "materialization_commit_sha": MATERIALIZATION_COMMIT,
        "artifact_ref": RAW_PATH.relative_to(ROOT).as_posix(),
        "raw_output_sha256": raw_semantic_sha,
        "artifact_byte_sha256": raw_byte_sha,
    }
    request_sha = canonical_json_sha256(native_request)
    response_sha = canonical_json_sha256(response_readback)
    attestation_evidence_sha = canonical_json_sha256({"request": native_request, "response_readback": response_readback})

    invocations = build_adapter_invocations(preflight)
    if len(invocations) != 1 or invocations[0].get("verdict") != "APPLIED":
        raise SystemExit("BLOCK_ADAPTER_INVOCATION_NOT_EXACTLY_ONE_APPLIED")

    receipt = build_receipt(
        execution_id=preflight["execution_id"],
        profile_code="PERFIL-UI-ARCHITECT",
        profile_slug="ui_architect",
        profile_source_refs=[item["ref"] for item in preflight["profile_source_manifest"]],
        profile_source_sha256=preflight["profile_source_sha256"],
        input_literal=input_literal,
        raw_output=raw,
        runtime_attestation={
            "provider": "OPENAI_CHATGPT_NATIVE",
            "model_id": "GPT-5.6 Sol",
            "run_id": PRODUCER_RUN_ID,
            "attested_at": MATERIALIZATION_COMMIT_AT,
            "attestation_verifier": "GITHUB_MATERIALIZATION_READBACK_V1",
            "attestation_evidence_sha256": attestation_evidence_sha,
            "verified_request_sha256": request_sha,
            "verified_response_sha256": response_sha,
            "execution_mode": "GPT_NATIVE",
            "execution_contract_sha256": preflight["execution_contract_sha256"],
            "context_fingerprint": preflight["context_fingerprint"],
            "governed_context_receipt_sha256": preflight["governed_context_receipt_sha256"],
            "materialization_commit_sha": MATERIALIZATION_COMMIT,
            "materialization_path": RAW_PATH.relative_to(ROOT).as_posix(),
            "artifact_byte_sha256": raw_byte_sha,
            "attestation_boundary": "GitHub readback verifies persisted output bytes and exact pre-bound context lineage; native model internals and exact token telemetry are not independently observable at this boundary.",
        },
        obligation_manifest_sha256=preflight["obligation_manifest_sha256"],
        lf_adapter_invocations=invocations,
    )
    receipt["governed_context_receipt_sha256"] = preflight["governed_context_receipt_sha256"]
    receipt["context_fingerprint"] = preflight["context_fingerprint"]
    receipt["native_metrics"] = {
        "depth_gate": depth_gate,
        "latency_observable": latency,
        "token_usage": token_usage,
        "traceability": {
            "status": "PASS",
            "execution_id": preflight["execution_id"],
            "execution_contract_sha256": preflight["execution_contract_sha256"],
            "governed_context_receipt_sha256": preflight["governed_context_receipt_sha256"],
            "context_fingerprint": preflight["context_fingerprint"],
            "input_governance_snapshot_sha256": preflight["input_governance_snapshot_sha256"],
            "card_receipt_count": len(governed["card_receipts"]),
            "adapter_receipt_count": len(governed["adapter_receipts"]),
            "adapter_invocation_count": len(invocations),
            "raw_output_sha256": raw_semantic_sha,
            "artifact_byte_sha256": raw_byte_sha,
            "obligation_manifest_sha256": preflight["obligation_manifest_sha256"],
            "check_bundle_sha256": canonical_json_sha256(check_bundle),
        },
    }
    receipt["receipt_sha256"] = canonical_json_sha256({key: value for key, value in receipt.items() if key != "receipt_sha256"})

    receipt_errors = validate_receipt(
        receipt,
        expected_profile_code="PERFIL-UI-ARCHITECT",
        expected_input_literal=input_literal,
        expected_raw_output=raw,
        expected_profile_source_sha256=preflight["profile_source_sha256"],
    )
    if receipt_errors:
        print(json.dumps({"status": "BLOCK_EXECUTION_RECEIPT", "errors": receipt_errors}, indent=2))
        return 1

    result = {
        "schema": "S26_NATIVE_GOLDEN_C_EVALUATION_V1",
        "status": "PASS_PRE_INDEPENDENT_REVIEW",
        "golden_eligible": False,
        "golden_declared": False,
        "next_gate": "INDEPENDENT_CHAT_CONTEXT",
        "execution_id": preflight["execution_id"],
        "producer_run_id": PRODUCER_RUN_ID,
        "materialization_commit_sha": MATERIALIZATION_COMMIT,
        "raw_output_sha256": raw_semantic_sha,
        "artifact_byte_sha256": raw_byte_sha,
        "execution_contract_sha256": preflight["execution_contract_sha256"],
        "governed_context_receipt_sha256": preflight["governed_context_receipt_sha256"],
        "context_fingerprint": preflight["context_fingerprint"],
        "ui_architect_validator": {"valid": True, "errors": []},
        "depth_gate": depth_gate,
        "latency_observable": latency,
        "token_usage": token_usage,
        "traceability": receipt["native_metrics"]["traceability"],
        "deterministic_checks": [item.as_dict() for item in deterministic],
        "semantic_checks_pending": semantic_ids,
        "check_bundle": check_bundle,
        "check_bundle_sha256": canonical_json_sha256(check_bundle),
        "execution_receipt": receipt,
        "execution_receipt_sha256": receipt["receipt_sha256"],
        "blocking_codes": ["INDEPENDENT_QUALITY_REVIEW_NOT_EXECUTED"],
        "forbidden_claims": ["GOLDEN", "GOLDEN_ELIGIBLE", "INDEPENDENT_QUALITY_PASS", "PRODUCTION_AUTHORIZED"],
    }
    print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
