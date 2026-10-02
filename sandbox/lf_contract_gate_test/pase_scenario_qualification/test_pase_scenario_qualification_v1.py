#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace

HERE = Path(__file__).resolve().parent
TARGET = HERE / "pase_scenario_qualification_v1.py"

def load():
    spec = importlib.util.spec_from_file_location("pase_scenario_matrix_tested", TARGET)
    if spec is None or spec.loader is None:
        raise SystemExit("FAIL_SCENARIO_MATRIX_TEST_LOAD")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module

M = load()

def main() -> int:
    checks = 0
    catalog = {
        "schema_version":M.CATALOG_SCHEMA,"policy_id":M.POLICY_ID,
        "selection_rule":"maturity_match AND all_traits_subset AND (any_traits_empty OR any_trait_matches)",
        "allowed_maturities":["CUTOVER","ACTIVE"],"allowed_selected_dispositions":["TESTED","BLOCKED_EXPLICITLY"],
        "unselected_disposition":"NOT_APPLICABLE","unknown_selected_forbidden":True,
        "scenarios":[
            {"scenario_id":"SCN-A","family":"A","maturities":["CUTOVER"],"all_traits":["A"],"any_traits":[],"purpose":"selected positive"},
            {"scenario_id":"SCN-B","family":"B","maturities":["CUTOVER"],"all_traits":["A"],"any_traits":[],"purpose":"selected negative"},
            {"scenario_id":"SCN-C","family":"C","maturities":["ACTIVE"],"all_traits":["ACTIVE_ONLY"],"any_traits":[],"purpose":"not applicable now"}
        ]
    }
    profile = {
        "schema_version":M.PROFILE_SCHEMA,"policy_id":M.POLICY_ID,"control_id":"TEST_CONTROL","maturity":"CUTOVER","traits":["A"],
        "evidence_commands":{"ONE":{"argv":["python3","sandbox/lf_contract_gate_test/fake.py"]}},
        "assertions":{
            "SCN-A":{"disposition":"TESTED","evidence":[{"command_id":"ONE","marker":"PASS_ONE"},{"runtime_assertion":"SCOPE_MANIFEST_EXACT"}]},
            "SCN-B":{"disposition":"BLOCKED_EXPLICITLY","evidence":[{"command_id":"ONE","marker":"PASS_BLOCK"}]}
        }
    }
    base, head = "a"*40, "b"*40
    with tempfile.TemporaryDirectory(prefix="pase-scenario-matrix-") as td:
        runtime = Path(td)
        (runtime/"scope-manifest.json").write_text(json.dumps({
            "policy_id":"PASE_EVALUATION_SCOPE_POLICY_V1","control_maturity":"CUTOVER","evaluation_scope":"CHANGESET_SCOPED",
            "historical_debt_disposition":"RECONCILIATION_WORK_ITEM","base_sha":base,"head_sha":head,"unbounded_historical_scan":False
        }), encoding="utf-8")
        (runtime/"run-summary.json").write_text(json.dumps({
            "policy_id":"PASE_EVALUATION_SCOPE_POLICY_V1","control_maturity":"CUTOVER","evaluation_scope":"CHANGESET_SCOPED",
            "historical_debt_disposition":"RECONCILIATION_WORK_ITEM","unbounded_historical_scan":False,"status":"PASS","returncode":0
        }), encoding="utf-8")
        calls = []
        old_run = M.subprocess.run
        M.subprocess.run = lambda argv, **kwargs: (calls.append(tuple(argv)) or SimpleNamespace(returncode=0,stdout="PASS_ONE\nPASS_BLOCK\n",stderr=""))
        try:
            result = M.qualify(root=HERE.parents[2],catalog=catalog,profile=profile,maturity="CUTOVER",base_sha=base,head_sha=head,runtime_dir=runtime)
        finally:
            M.subprocess.run = old_run
    assert result["verdict"] == "PASS" and result["selected_count"] == 2 and result["not_applicable_count"] == 1
    assert result["unknown_selected_count"] == 0 and len(calls) == 1
    assert next(row for row in result["scenarios"] if row["scenario_id"]=="SCN-C")["disposition"] == "NOT_APPLICABLE"
    checks += 1

    broken = json.loads(json.dumps(profile)); del broken["assertions"]["SCN-B"]
    with tempfile.TemporaryDirectory(prefix="pase-scenario-matrix-") as td:
        runtime = Path(td); (runtime/"scope-manifest.json").write_text("{}",encoding="utf-8"); (runtime/"run-summary.json").write_text("{}",encoding="utf-8")
        try:
            M.qualify(root=HERE.parents[2],catalog=catalog,profile=broken,maturity="CUTOVER",base_sha=base,head_sha=head,runtime_dir=runtime)
        except M.ScenarioQualificationError as exc:
            assert str(exc).startswith("BLOCK_SCENARIO_SELECTED_UNKNOWN"), exc
        else:
            raise AssertionError("missing selected scenario was accepted")
    checks += 1

    selected_active, _ = M.select_scenarios(catalog,"ACTIVE",{"A","ACTIVE_ONLY"})
    assert [row["scenario_id"] for row in selected_active] == ["SCN-C"]
    checks += 1
    M.self_test(); checks += 1
    print(f"PASS_PASE_SCENARIO_QUALIFICATION_MATRIX_TESTS={checks}/{checks}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
