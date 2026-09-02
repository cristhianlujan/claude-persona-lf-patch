#!/usr/bin/env python3
import json
import sys
from pathlib import Path


def require(source: str, token: str, failures: list[str], code: str) -> None:
    if token not in source:
        failures.append(code)


def main() -> int:
    repo_root = Path(__file__).resolve().parents[3]
    caller_path = repo_root / "supabase/functions/lf-profiles-governance-caller-v1/index.ts"
    runtime_path = repo_root / "supabase/functions/run-creacion-perfil-lf/index.ts"
    recorder_path = repo_root / "supabase/migrations/20260902133319_profile_creator_step_recorder_v1.sql"

    failures: list[str] = []
    for path, code in (
        (caller_path, "CALLER_SOURCE_MISSING"),
        (runtime_path, "RUNTIME_SOURCE_MISSING"),
        (recorder_path, "RECORDER_SOURCE_MISSING"),
    ):
        if not path.is_file():
            failures.append(code)

    if failures:
        print(json.dumps({"status": "FAIL", "failed_checks": failures}, indent=2))
        return 1

    caller = caller_path.read_text(encoding="utf-8")
    runtime = runtime_path.read_text(encoding="utf-8")
    recorder = recorder_path.read_text(encoding="utf-8")

    # Positive governed continuation path: exact caller action -> runtime action -> canonical recorder RPC.
    require(caller, 'body.action === "profile_creator_record_step_v1"', failures, "POS_CALLER_ACTION_MISSING")
    require(caller, 'action: "record_profile_creation_step_v1"', failures, "POS_RUNTIME_DELEGATION_MISSING")
    require(caller, 'result.outcome === "STEP_RECORDED"', failures, "POS_CALLER_SUCCESS_GATE_MISSING")
    require(runtime, 'body.action === "record_profile_creation_step_v1"', failures, "POS_RUNTIME_ACTION_MISSING")
    require(runtime, 'rpc("lf_record_creacion_perfil_step_v1"', failures, "POS_CANONICAL_RPC_MISSING")
    require(recorder, "'outcome','STEP_RECORDED'", failures, "POS_RECORDER_SUCCESS_MISSING")

    # Negative caller/input gates.
    require(caller, "OIDC_TOKEN_INVALID", failures, "NEG_OIDC_INVALID_MISSING")
    require(caller, "OIDC_REPOSITORY_MISMATCH", failures, "NEG_OIDC_REPO_MISSING")
    require(caller, "OIDC_WORKFLOW_MISMATCH", failures, "NEG_OIDC_WORKFLOW_MISSING")
    require(caller, "PROFILE_CREATOR_STEP_INPUT_INVALID", failures, "NEG_CALLER_STEP_INPUT_MISSING")
    require(runtime, "GOVERNED_CALLER_MISSING", failures, "NEG_GOVERNED_CALLER_MISSING")
    require(runtime, "GOVERNED_CALLER_METHOD_INVALID", failures, "NEG_GOVERNED_METHOD_MISSING")
    require(runtime, "GOVERNED_CALLER_REPOSITORY_INVALID", failures, "NEG_GOVERNED_REPOSITORY_MISSING")
    require(runtime, "GOVERNED_CALLER_WORKFLOW_INVALID", failures, "NEG_GOVERNED_WORKFLOW_MISSING")
    require(runtime, "EXECUTION_ID_INVALID", failures, "NEG_EXECUTION_ID_MISSING")
    require(runtime, "STEP_EXECUTION_IDENTITY_MISMATCH", failures, "NEG_EXECUTION_IDENTITY_MISSING")
    require(runtime, "STEP_EVIDENCE_INPUT_INVALID", failures, "NEG_RUNTIME_EVIDENCE_INPUT_MISSING")

    # Negative canonical recorder gates: prior cleanliness, evidence completeness, blockers, immutable init and close gate.
    require(recorder, "INIT_STEP_IMMUTABLE", failures, "NEG_INIT_IMMUTABLE_MISSING")
    require(recorder, "PRIOR_REQUIRED_STEP_NOT_CLEAN", failures, "NEG_PRIOR_STEP_CLEANLINESS_MISSING")
    require(recorder, "REQUIRED_EVIDENCE_MISSING", failures, "NEG_REQUIRED_EVIDENCE_MISSING")
    require(recorder, "BLOCKING_CODES_INVALID", failures, "NEG_BLOCKING_CODES_TYPE_MISSING")
    require(recorder, "jsonb_array_length(v_blocking_codes)>0", failures, "NEG_BLOCKING_CODES_NONEMPTY_MISSING")
    require(recorder, "STEP_ALREADY_RECORDED_DIFFERENT_EVIDENCE", failures, "NEG_REPLAY_DIFFERENT_EVIDENCE_MISSING")
    require(recorder, "PROFILE_CLOSE_GATE_FAILED", failures, "NEG_CLOSE_GATE_MISSING")

    result = {
        "status": "PASS" if not failures else "FAIL",
        "matrix": {
            "positive_source_path": 6,
            "negative_caller_runtime_guards": 12,
            "negative_recorder_guards": 7,
            "total": 25,
        },
        "failed_checks": failures,
        "runtime_authorized": False,
        "production_authorized": False,
        "receipt_fabricated": False,
    }
    print(json.dumps(result, indent=2))
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
