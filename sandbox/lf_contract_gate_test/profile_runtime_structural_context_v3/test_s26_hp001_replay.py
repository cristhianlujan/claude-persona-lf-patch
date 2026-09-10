#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path

from s26_hp001.happy_path_preexecution import run_preexecution

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
FIXTURE = HERE / "s26_hp001"
MANIFEST = FIXTURE / "replay_manifest.json"
OUTPUT_TEST = HERE / "test_s26_hp001_output.py"
EXPECTED_POLICY_CODES = {
    "POL-LF-OPERATION-LIFECYCLE",
    "POL-LF-POLICY-CONSUMPTION",
    "POL-LF-SOURCE-RESOLUTION",
    "POL-LF-STATE-MODEL",
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"MODULE_LOAD_FAILED:{path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def validate_bootstrap_trace(pre: dict) -> dict:
    boot = pre.get("bootstrap") or {}
    if boot.get("status") != "PASS":
        raise RuntimeError("REPLAY_BOOTSTRAP_NOT_PASS")
    if boot.get("operation_code") != "EJECUCION_PERFIL_LF":
        raise RuntimeError("REPLAY_BOOTSTRAP_OPERATION_INVALID")
    if boot.get("execution_mode") != "SANDBOX":
        raise RuntimeError("REPLAY_EXECUTION_MODE_MISSING_OR_INVALID")
    if boot.get("execution_mode_source") != "TEST_HARNESS_EXPLICIT_NON_PRODUCTION":
        raise RuntimeError("REPLAY_EXECUTION_MODE_SOURCE_INVALID")
    if boot.get("distribution_mode") != "DIRECT":
        raise RuntimeError("REPLAY_DISTRIBUTION_MODE_INVALID")
    if boot.get("router_execution_mode_resolved") is not False:
        raise RuntimeError("REPLAY_FALSE_ROUTER_EXECUTION_MODE_PROVENANCE")
    if boot.get("active_policy_count") != 4:
        raise RuntimeError("REPLAY_ACTIVE_POLICY_COUNT_INVALID")
    refs = boot.get("active_policy_refs") or []
    codes = {ref.get("policy_code") for ref in refs if isinstance(ref, dict)}
    if codes != EXPECTED_POLICY_CODES:
        raise RuntimeError("REPLAY_REQUIRED_POLICY_SET_MISMATCH")
    if any(not isinstance(ref.get("policy_sha"), str) or len(ref["policy_sha"]) != 64 for ref in refs):
        raise RuntimeError("REPLAY_POLICY_SHA_INVALID")
    bootstrap_sha = boot.get("bootstrap_context_sha256")
    policy_sha = boot.get("policy_snapshot_sha256")
    if not isinstance(bootstrap_sha, str) or len(bootstrap_sha) != 64:
        raise RuntimeError("REPLAY_BOOTSTRAP_SHA_INVALID")
    if not isinstance(policy_sha, str) or len(policy_sha) != 64:
        raise RuntimeError("REPLAY_POLICY_SNAPSHOT_SHA_INVALID")
    assurance = boot.get("development_assurance") or {}
    if assurance.get("policy_version") != "v1.1-candidate" or assurance.get("status") != "CANDIDATE":
        raise RuntimeError("REPLAY_DEVELOPMENT_ASSURANCE_INVALID")
    if assurance.get("authority_mode") != "SHADOW_ASSURANCE_ONLY_NOT_ACTIVE_POLICY":
        raise RuntimeError("REPLAY_CANDIDATE_POLICY_AUTHORITY_MISREPRESENTED")

    for stage_name in ("upstream_gate_a", "stage_b", "stage_c", "stage_d", "stage_e"):
        stage = pre.get(stage_name) or {}
        if stage.get("bootstrap_context_sha256") != bootstrap_sha:
            raise RuntimeError(f"REPLAY_BOOTSTRAP_DRIFT:{stage_name}")
    return boot


def main() -> int:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if manifest.get("schema") != "S26_HP001_REPLAY_MANIFEST_V1":
        raise RuntimeError("REPLAY_SCHEMA_INVALID")
    if manifest.get("candidate_sha_authority") != "GITHUB_EVENT_HEAD_SHA":
        raise RuntimeError("REPLAY_SHA_AUTHORITY_INVALID")
    if manifest.get("main_is_not_replay_authority") is not True:
        raise RuntimeError("MAIN_WRONGLY_USED_AS_REPLAY_AUTHORITY")
    if manifest.get("merge_ref_is_not_replay_authority") is not True:
        raise RuntimeError("MERGE_REF_WRONGLY_USED_AS_REPLAY_AUTHORITY")
    if manifest.get("independent_review_satisfied_by_replay") is not False:
        raise RuntimeError("REPLAY_WRONGLY_CLAIMS_INDEPENDENT_REVIEW")

    input_path = REPO / manifest["input_path"]
    output_path = REPO / manifest["output_path"]
    if sha256(input_path) != manifest.get("input_sha256"):
        raise RuntimeError("REPLAY_INPUT_SHA_MISMATCH")
    if sha256(output_path) != manifest.get("output_sha256"):
        raise RuntimeError("REPLAY_OUTPUT_SHA_MISMATCH")

    pre = run_preexecution()
    if pre.get("result") != "PASS":
        raise RuntimeError("REPLAY_PREEXECUTION_FAILED")
    boot = validate_bootstrap_trace(pre)

    output_module = load_module(OUTPUT_TEST, "s26_hp001_output_replay")
    if output_module.main() != 0:
        raise RuntimeError("REPLAY_OUTPUT_VALIDATION_FAILED")

    print(json.dumps({
        "gate": "S26_HP001_DETERMINISTIC_REPLAY_V2",
        "result": "PASS",
        "input_sha256": manifest["input_sha256"],
        "output_sha256": manifest["output_sha256"],
        "execution_mode": boot["execution_mode"],
        "distribution_mode": boot["distribution_mode"],
        "operation_code": boot["operation_code"],
        "active_policy_refs": boot["active_policy_refs"],
        "policy_snapshot_sha256": boot["policy_snapshot_sha256"],
        "bootstrap_context_sha256": boot["bootstrap_context_sha256"],
        "bootstrap_continuity_a_to_e": True,
        "preexecution_replayed": True,
        "canonical_output_validation_replayed": True,
        "independent_semantic_review_performed": False,
        "claim_ceiling": manifest["claim_ceiling"],
    }, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
