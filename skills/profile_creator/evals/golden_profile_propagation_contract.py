#!/usr/bin/env python3
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTRACT = json.loads((ROOT / "contracts" / "golden_profile_propagation_v1.json").read_text(encoding="utf-8"))
PLANNER_PATH = ROOT / "planners" / "golden_profile_propagation.py"
spec = importlib.util.spec_from_file_location("golden_profile_propagation", PLANNER_PATH)
if spec is None or spec.loader is None:
    raise SystemExit("FAIL_GOLDEN_PROPAGATION_IMPORT")
planner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(planner)

base = {
    "golden": {
        "profile_code": "PERFIL-UI-ARCHITECT",
        "fingerprint": "sha256:golden-v1",
        "e2e_status": "CANDIDATE_READ_ONLY"
    },
    "targets": [
        {"profile_code": "PERFIL-PRODUCT-DIRECTOR-LF", "target_path": "profiles/product_director_lf"},
        {"profile_code": "PERFIL-QUALITY-PACK", "target_path": "profiles/quality_pack"}
    ],
    "authorized_delta": [
        {"component": "execution_binding_contract", "source_ref": "golden/execution-binding@v1", "action": "ALIGN_SHARED_CONTRACT"},
        {"component": "evidence_lineage_contract", "source_ref": "golden/evidence-lineage@v1", "action": "ALIGN_SHARED_CONTRACT"}
    ]
}

plan1 = planner.build_plan(base, CONTRACT)
plan2 = planner.build_plan(base, CONTRACT)
checks = {
    "dry_run_only": plan1["mode"] == "DRY_RUN",
    "stable_parent_plan": plan1["parent_plan_id"] == plan2["parent_plan_id"],
    "stable_delta": plan1["authorized_delta_sha256"] == plan2["authorized_delta_sha256"],
    "one_child_per_target": plan1["target_count"] == 2 and len(plan1["children"]) == 2,
    "isolated_update_children": all(c["operation_code"] == "ACTUALIZACION_PERFIL_LF" and c["execution_mode"] == "ISOLATED_CHILD_UPDATE" for c in plan1["children"]),
    "stable_child_keys": [c["idempotency_key"] for c in plan1["children"]] == [c["idempotency_key"] for c in plan2["children"]],
    "no_write": not plan1["repository_write_authorized"] and all(not c["repository_write_authorized"] for c in plan1["children"]),
    "no_runtime_transition": not plan1["runtime_transition_authorized"] and all(not c["runtime_transition_authorized"] for c in plan1["children"]),
    "no_family_pass_claim": plan1["family_pass_claimable"] is False,
    "pre_e2e_blocks_apply": plan1["apply_gate"] == "BLOCKED_GOLDEN_NOT_E2E_PASS",
    "preservation_present": all("identity" in c["required_preservations"] and "role_and_purpose" in c["required_preservations"] for c in plan1["children"]),
}

ready = json.loads(json.dumps(base))
ready["golden"]["e2e_status"] = "FAMILY_E2E_PASS"
ready_plan = planner.build_plan(ready, CONTRACT)
checks["e2e_only_opens_canary_gate"] = ready_plan["apply_gate"] == "READY_FOR_CHILD_CANARY" and ready_plan["repository_write_authorized"] is False

negative_cases = []
for name, mutate, expected in [
    ("profile_specific_delta", lambda p: p["authorized_delta"].append({"component": "role_and_purpose", "source_ref": "bad", "action": "COPY"}), "PROFILE_SPECIFIC_COMPONENT_PROPAGATION_FORBIDDEN"),
    ("duplicate_target", lambda p: p["targets"].append(dict(p["targets"][0])), "DUPLICATE_TARGET_FORBIDDEN"),
    ("golden_as_target", lambda p: p["targets"].append({"profile_code": "PERFIL-UI-ARCHITECT", "target_path": "profiles/ui_architect"}), "GOLDEN_PROFILE_CANNOT_BE_TARGET"),
]:
    candidate = json.loads(json.dumps(base))
    mutate(candidate)
    try:
        planner.build_plan(candidate, CONTRACT)
        negative_cases.append((name, False, "NO_ERROR"))
    except ValueError as exc:
        negative_cases.append((name, str(exc) == expected, str(exc)))

checks["negative_fail_closed"] = all(ok for _, ok, _ in negative_cases)
failed = [name for name, ok in checks.items() if not ok]
if failed:
    raise SystemExit("FAIL_GOLDEN_PROFILE_PROPAGATION:" + ",".join(failed) + ";negative=" + repr(negative_cases))
print(f"PASS_GOLDEN_PROFILE_PROPAGATION={sum(checks.values())}/{len(checks)}")
print("MODE=DRY_RUN_ONLY")
print("CHILD_OPERATION=ACTUALIZACION_PERFIL_LF")
print("WRITE_AUTHORIZED=false")
