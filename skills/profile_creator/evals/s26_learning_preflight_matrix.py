#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
from pathlib import Path

HERE = Path(__file__).resolve()
SKILL = HERE.parents[1]
MODULE = SKILL / "validators/evaluate_s26_learning_preflight.py"
spec = importlib.util.spec_from_file_location("s26_learning_preflight_eval", MODULE)
mod = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(mod)

HEAD = "a" * 40
EVIDENCE = "b" * 64
CORE = ["PROFILES-EKB-PREFLIGHT-OMISSION-001", "GOV-024", "AUD-018", "CI-014"]


def payload(extra_codes: list[str] | None = None) -> dict:
    codes = CORE + list(extra_codes or [])
    return {
        "schema": "S26_PROFILE_UPDATE_LEARNING_PREFLIGHT_V1", "profile_slug": "demo", "repository": "owner/repo", "current_main_sha": HEAD,
        "ekb_preflight": {
            "status": "EKB_PREFLIGHT_COMPLETED", "source": "public.lf_error_knowledge", "matched_error_codes": codes,
            "matched_prevention_rules": [{"code": code, "rule": f"prevent {code}", "source_ref": f"ekb://{code}"} for code in codes],
            "prevention_checks": [{"code": code, "status": "PASS", "test_id": f"reg-{i}", "executed": True, "exit_code": 0, "result": "PASS", "evidence_sha256": EVIDENCE, "source_ref": f"evidence://{code}"} for i, code in enumerate(codes)],
        },
        "execution_binding": {
            "execution_id": "EXEC-DEMO-001", "operation_code": "ACTUALIZACION_PERFIL_LF", "target_type": "PROFILE", "target_path": "profiles/demo", "status": "IN_PROGRESS",
            "step_id": "pre_write_execution_binding_gate", "step_status": "STEP_PASS_WITH_EVIDENCE", "pre_write_gate_passed": True, "execution_bound_to_target_before_change": True,
            "bound_revision": {"repo":"owner/repo","path":"profiles/demo","revision_sha":HEAD},
            "write_plan": {"allowed_paths":["profiles/demo/**"],"automatic_runtime_activation":False,"production_change":False},
        },
    }


def main() -> int:
    checks = {}
    p = payload(); x = mod.evaluate_learning_preflight(p, "demo", current_revision=HEAD)
    checks["fresh_complete_preflight_passes"] = x["status"] == "PASS" and x["metrics"]["learning_coverage_pct"] == 100.0
    x = mod.evaluate_learning_preflight(None, "demo", current_revision=HEAD)
    checks["missing_preflight_blocks"] = x["status"] == "BLOCKED" and "EKB_PREFLIGHT_MISSING" in x["blocking_codes"]
    p = payload(); x = mod.evaluate_learning_preflight(p, "demo", current_revision="c" * 40)
    checks["stale_main_blocks"] = "STALE_MAIN_REVISION" in x["blocking_codes"] and "BOUND_REVISION_STALE" in x["blocking_codes"]
    p = payload(["NEW-EKB-CODE-001"]); p["ekb_preflight"]["prevention_checks"] = p["ekb_preflight"]["prevention_checks"][:-1]; x = mod.evaluate_learning_preflight(p, "demo", current_revision=HEAD)
    checks["new_code_without_prevention_mapping_blocks"] = any(code.startswith("EKB_PREVENTION_UNMAPPED:NEW-EKB-CODE-001") for code in x["blocking_codes"])
    p = payload(); p["ekb_preflight"]["matched_prevention_rules"] = p["ekb_preflight"]["matched_prevention_rules"][:-1]; x = mod.evaluate_learning_preflight(p, "demo", current_revision=HEAD)
    checks["missing_prevention_rule_traceability_blocks"] = any(code.startswith("EKB_PREVENTION_RULE_UNMAPPED:") for code in x["blocking_codes"])
    p = payload(); p["execution_binding"]["status"] = "COMPLETED"; x = mod.evaluate_learning_preflight(p, "demo", current_revision=HEAD)
    checks["false_completed_prewrite_status_blocks"] = "EXECUTION_NOT_ACTIVE_PREWRITE" in x["blocking_codes"]
    p = payload(); p["execution_binding"]["write_plan"]["allowed_paths"] = ["profiles/demo/**","services/**"]; x = mod.evaluate_learning_preflight(p, "demo", current_revision=HEAD)
    checks["scope_escape_blocks"] = "WRITE_SCOPE_ESCAPE" in x["blocking_codes"]
    p = payload(); p["ekb_preflight"]["prevention_checks"].append(dict(p["ekb_preflight"]["prevention_checks"][0])); x = mod.evaluate_learning_preflight(p, "demo", current_revision=HEAD)
    checks["duplicate_prevention_receipt_blocks"] = "EKB_PREVENTION_CHECK_DUPLICATED" in x["blocking_codes"]
    p = payload(); p["ekb_preflight"]["prevention_checks"][0]["executed"] = False; x = mod.evaluate_learning_preflight(p, "demo", current_revision=HEAD)
    checks["declarative_pass_without_execution_blocks"] = any(code.startswith("EKB_PREVENTION_EXECUTION_RECEIPT_INVALID:") for code in x["blocking_codes"])
    p = payload(); p["profile_slug"] = "other"; x = mod.evaluate_learning_preflight(p, "demo", current_revision=HEAD)
    checks["cross_profile_replay_blocks"] = "LEARNING_PREFLIGHT_PROFILE_MISMATCH" in x["blocking_codes"]
    ok = all(checks.values())
    print(json.dumps({"contract":"S26_LEARNING_PREFLIGHT_MATRIX_V1","checks":checks,"count":len(checks),"result":"PASS" if ok else "FAIL"}, sort_keys=True)); return 0 if ok else 1


if __name__ == "__main__": raise SystemExit(main())
