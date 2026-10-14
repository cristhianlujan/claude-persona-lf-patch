#!/usr/bin/env python3
"""Bridge an OIDC-governed ACT-0001 update receipt to existing Updater assessment.

This is one read-only stage of ACTUALIZACION_PERFIL_LF, NOT an independent
router, model dispatcher, update completion, admission, or production cutover.
Input must be the actual response from the already authorized workflow/Edge
caller, not user-authored JSON or a fabricated Router receipt.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import Any

from evaluate_s26_profile_baseline import evaluate as evaluate_s26
from sandbox.lf_contract_gate_test.transversal_assets.profile_assessment.profile_assessment_v1 import assess_profile

SHA40 = re.compile(r"^[0-9a-f]{40}$")
PROFILE_CODE = re.compile(r"^PERFIL-[A-Z0-9-]{3,120}$")
REPO = "cristhianlujan/claude-persona-lf-patch"
OPERATION = "ACTUALIZACION_PERFIL_LF"
EXPECTED_CALLER = "GITHUB_ACTIONS_OIDC_EXACT_PROFILE_UPDATE_V1"


class UntrustedOperationReceipt(ValueError):
    pass


def git_blob_sha1(data: bytes) -> str:
    return hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()


def bootstrap(
    response: dict[str, Any], repo_root: Path, *,
    target_code: str, target_path: str, checkout_sha: str,
) -> dict[str, Any]:
    def require(ok: bool, code: str) -> None:
        if not ok:
            raise UntrustedOperationReceipt(code)

    repo_root = repo_root.resolve()
    require(isinstance(response, dict) and response.get("outcome") == "INITIALIZED",
            "GOVERNED_UPDATE_NOT_INITIALIZED")
    execution = response.get("execution")
    snapshot = response.get("snapshot")
    require(isinstance(execution, dict) and isinstance(snapshot, dict),
            "GOVERNED_UPDATE_RECEIPT_INCOMPLETE")
    manifest = execution.get("manifest")
    require(isinstance(manifest, dict), "GOVERNED_MANIFEST_MISSING")
    require(isinstance(target_code, str) and bool(PROFILE_CODE.fullmatch(target_code)),
            "INVALID_PROFILE_CODE")
    require(isinstance(target_path, str) and target_path.endswith("/SKILL.md"),
            "INVALID_TARGET_PATH")
    parts = Path(target_path).parts
    require(len(parts) == 3 and parts[0] == "profiles"
            and bool(re.fullmatch(r"[a-z0-9][a-z0-9_]{0,79}", parts[1])),
            "TARGET_PATH_NOT_PROFILE")
    require(execution.get("operation_code") == OPERATION
            and execution.get("target_type") == "PERFIL"
            and execution.get("target_code") == target_code
            and execution.get("target_repo") == REPO
            and execution.get("target_path") == target_path
            and execution.get("status") == "IN_PROGRESS",
            "GOVERNED_EXECUTION_IDENTITY_MISMATCH")
    execution_id = execution.get("execution_id")
    require(isinstance(execution_id, str)
            and execution_id.startswith("EXEC-ACTUALIZACION-PERFIL-LF-OIDC-"),
            "GOVERNED_EXECUTION_ID_UNEXPECTED")
    require(manifest.get("router") == "ACT-0001"
            and manifest.get("governed_caller_method") == EXPECTED_CALLER
            and manifest.get("caller_repository") == REPO
            and manifest.get("runtime_write_executed") is False
            and manifest.get("github_write_executed") is False
            and manifest.get("automatic_runtime_promotion") is False,
            "UNVERIFIED_ROUTER_OR_CALLER")
    require(snapshot.get("operation_code") == OPERATION
            and snapshot.get("target_code") == target_code
            and snapshot.get("target_path") == target_path
            and isinstance(snapshot.get("next_step"), dict)
            and snapshot["next_step"].get("step_id") == "router",
            "GOVERNED_NEXT_STEP_NOT_ROUTER")
    require(isinstance(checkout_sha, str) and bool(SHA40.fullmatch(checkout_sha)),
            "INVALID_CHECKOUT_REVISION")
    require(manifest.get("initial_main_revision") == checkout_sha,
            "PROFILE_UPDATE_CHECKOUT_STALE")
    expected_blob = manifest.get("initial_target_blob_sha")
    require(isinstance(expected_blob, str) and bool(SHA40.fullmatch(expected_blob)),
            "PROFILE_TARGET_SOURCE_UNBOUND")
    file_path = (repo_root / target_path).resolve()
    require(file_path.is_file() and file_path.is_relative_to(repo_root / "profiles"),
            "PROFILE_SOURCE_NOT_AVAILABLE")
    current_blob = git_blob_sha1(file_path.read_bytes())
    require(current_blob == expected_blob,
            "PROFILE_TARGET_SOURCE_DRIFT")

    # Execute existing Updater modules (no new selection engine).
    structural = evaluate_s26(repo_root, parts[1])
    structure_status = structural.get("decision")
    structural_evidence = {
        "status": "PASS" if structure_status == "NO_UPDATE_REQUIRED"
        else "FAIL" if structure_status == "UPDATE_REQUIRED" else "UNKNOWN",
        "refs": [f"git://{REPO}@{checkout_sha}/{target_path}#blob:{current_blob}"],
    }
    assessment = assess_profile({
        "signals": {},  # Unknown until a separately sourced, verified assessment exists.
        "evidence": {"structural_compatibility": structural_evidence},
    })
    return {
        "schema": "PROFILE_UPDATE_EVOLUTION_BOOTSTRAP_V1",
        "operation_code": OPERATION,
        "router": "ACT-0001",
        "profile_code": target_code,
        "profile_slug": parts[1],
        "profile_source_path": target_path,
        "execution_id": execution_id,
        "exact_checkout_sha": checkout_sha,
        "source_git_blob_sha1": current_blob,
        "stage_status": "EVIDENCE_ACQUISITION_REQUIRED",
        "actual_updater_functions_invoked": [
            "evaluate_s26_profile_baseline.evaluate",
            "profile_assessment_v1.assess_profile",
        ],
        "structural_baseline": structural,
        "profile_assessment": assessment,
        "next_operation_step": "router",
        "missing_for_evolution": [
            "EKB_LEARNING_PREFLIGHT_BOUND_TO_EXECUTION",
            "EXTERNALLY_VERIFIED_DOMAIN_TASK_ASSESSMENT",
            "QUALIFIED_METHODS_AND_BENCHMARK_RECEIPTS_WHEN_APPLICABLE",
            "GPT_NATIVE_EXECUTOR_ATTESTATION",
            "INDEPENDENT_SEMANTIC_HOLDOUT",
        ],
        "profile_source_write_allowed": False,
        "runtime_activation_allowed": False,
        "automatic_promotion_allowed": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--init-response", type=Path, required=True)
    parser.add_argument("--target-code", required=True)
    parser.add_argument("--target-path", required=True)
    parser.add_argument("--checkout-sha", required=True)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        result = bootstrap(
            json.loads(args.init_response.read_text(encoding="utf-8")),
            args.repo, target_code=args.target_code,
            target_path=args.target_path, checkout_sha=args.checkout_sha,
        )
    except (OSError, UnicodeError, ValueError, TypeError, KeyError) as exc:
        print(json.dumps({"outcome": "BLOCKED", "code": str(exc),
                          "runtime_activation_allowed": False}, sort_keys=True))
        return 3
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"outcome": result["stage_status"],
                      "execution_id": result["execution_id"],
                      "next_operation_step": result["next_operation_step"],
                      "output_ref": str(args.output),
                      "runtime_activation_allowed": False}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
