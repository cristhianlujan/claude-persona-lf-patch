"""One-pass H4 EX6 diagnostics against unmodified original LF producers.

Each result identifies (a) original producer result, (b) provenance, and
(c) which official fixtures underlie the structural probe. Never upgrades
fixture-backed structural PASS into real EX6 chain admission.
"""
from __future__ import annotations

import copy
import hashlib
import json
import sys
from pathlib import Path

from ex6_real_chain_v1 import (
    install, uninstall, make_pg04, make_pg05, make_pg06,
    authorize_from_real_hunks, official_pg01_fixture,
)
from ex6_source_truth_v1 import source_truth, SPEC_REF, TASK_REF, RUN_REF

STAGES = [f"PG-{i:02d}" for i in range(4, 15)]
ROOT = Path(__file__).resolve().parents[2]
FIXTURES = {
    "PG01": "test_pg06_c1_c5_chain_v1.pg01",
    "PG06_A7": "test_pg06_c1_c5_chain_v1.a7_and_plans",
    "PG06_LINT_PROBE_ONLY": "test_pg06_c1_c5_chain_v1.baseline",
}
FORBIDDEN = ("ex5c", "lote-c")

def digest(obj):
    return hashlib.sha256(json.dumps(obj, sort_keys=True,
        ensure_ascii=True, separators=(",", ":")).encode()).hexdigest()

def only_ex6(value):
    data = json.dumps(value, sort_keys=True, default=str).lower()
    if any(f in data for f in FORBIDDEN):
        raise AssertionError("EX6_FOREIGN_DATA_CONTAMINATION")
    return value

def entry(stage, outcome, code, origin, *, producer_invoked=True, fixtures=()):
    return {"stage": stage, "outcome": outcome, "code": code,
            "producer_invoked": producer_invoked,
            "provenance": origin, "fixture_status":
            ["FIXTURE_UNATTESTED:" + f for f in fixtures],
            "production_authority": False}

def attempt(stage, fn, *, origin, fixtures=()):
    try:
        result=fn()
        value = result if isinstance(result, dict) else {}
        if value.get("production_authority") is True or value.get("handoff_allowed") is True:
            raise AssertionError("EX6_AUTHORITY_ESCALATION")
        return entry(stage, "PASS_SOURCE_ONLY" if not fixtures else "PASS_FIXTURE_UNATTESTED",
                     "CANDIDATE_NOT_ADMITTED", origin, fixtures=fixtures), result
    except Exception as exc:
        return entry(stage, "BLOCK", str(exc).splitlines()[0] or type(exc).__name__,
                     origin, fixtures=fixtures), None

def stage06(upstream):
    """Use original PG06 C1-C5, preserving official authority fixture identity."""
    import test_pg06_c1_c5_chain_v1 as t6
    from ex6_pg06_evidence_v1 import c2_inputs, c4_partial_baseline
    t = upstream["handoff"]
    facts = {"fixture_pg01": official_pg01_fixture(),
             "fixture_a7": None, "fixture_lint": None}
    one = make_pg06(upstream)
    c1 = one["c1"]
    cat, obs = c2_inputs(t)
    c2 = t6.prepare_pg06_c2(pg05_exit=t, pg06_c1=c1,
                            toolchain_catalog=cat, environment_observations=obs)
    a7, plans = t6.a7_and_plans(t)  # exact official A7, no modified fields
    a7_again, plans_again = t6.a7_and_plans(t)
    if (a7, plans) != (a7_again, plans_again):
        raise AssertionError("EX6_A7_OFFICIAL_FIXTURE_DRIFT")
    facts["fixture_a7"] = {"sha256": digest(a7), "plans_sha256": digest(plans)}
    c3 = t6.prepare_pg06_c3(pg05_exit=t, pg06_c1=c1, pg06_c2=c2,
       a7_material_front_coverage=a7, solution_reversibility_plans=plans)
    partial = c4_partial_baseline(t)
    # A real EX6 baseline has BUILD CI but no LINT or full stdout/stderr.
    # Invoke C4 first with the incomplete EX6-only data and retain its exact
    # original rejection. Never label the synthetic fallback as real C4 PASS.
    try:
        t6.prepare_pg06_c4(pg05_exit=t, pg06_c1=c1, pg06_c2=c2,
             pg06_c3=c3, baseline_observations=partial)
        raise AssertionError("EX6_MISSING_LINT_ACCIDENTAL_PASS")
    except t6.BaselineBlocked as exc:
        c4_real_code = str(exc)
    synthetic = t6.baseline(t)  # official fixture unchanged, probe ONLY
    synthetic_again = t6.baseline(t)
    if synthetic != synthetic_again:
        raise AssertionError("EX6_C4_OFFICIAL_FIXTURE_DRIFT")
    facts["fixture_lint"] = {"sha256": digest(synthetic),
                            "real_code": c4_real_code,
                            "real_lint": partial["lint_status"]}
    c4 = t6.prepare_pg06_c4(pg05_exit=t, pg06_c1=c1, pg06_c2=c2,
                   pg06_c3=c3, baseline_observations=synthetic)
    parts = {"pg05_exit":t,"pg06_c1":c1,"pg06_c2":c2,"pg06_c3":c3,"pg06_c4":c4}
    manifest = {"source_head_sha": upstream["pg04"]["truth"]["base_head_sha"]
                if "truth" in upstream["pg04"] else source_truth()["base_head_sha"],
        **{k:{"ref":"ex6://manifest/"+k,"sha256":v["candidate_sha256"]}
        for k,v in parts.items()}}
    c5=t6.prepare_pg06_assurance_request(**parts,source_manifest=manifest,
        producer_execution_id="ex6://source-only/pg06-official-fixtures")
    return {"exit":t,"c1":c1,"c2":c2,"c3":c3,"c4":c4,"c5":c5,
            "a7":a7,"a7_plans":plans,"baseline_partial":partial,
            "fixture_facts":facts}

def run_all():
    install()
    table=[]
    evidence={}
    try:
        truth=source_truth()
        only_ex6(truth)
        changed, authorized, traces=authorize_from_real_hunks(truth)
        assert len(changed)==len(authorized)==len(traces)==3
        row, x=attempt("PG-04",lambda:make_pg04(truth),
              origin="EX6_SPEC_AND_VERIFIED_HUNKS")
        table.append(row)
        if x is None:
            return {"stages":table,"evidence":evidence}
        row, y=attempt("PG-05",lambda:make_pg05(x,truth),
              origin="EX6_TASK_SPEC_AND_WRITE_SCOPE")
        table.append(row)
        if y is None:
            return {"stages":table,"evidence":evidence}
        row, z=attempt("PG-06",lambda:stage06(y),
              origin="EX6_JAVA21_AND_BASELINE_WITH_OFFICIAL_FIXTURES",
              fixtures=("PG01","PG06_A7","PG06_LINT_PROBE_ONLY"))
        table.append(row)
        if z is not None:
            evidence["pg06_fixture_checks"]=z["fixture_facts"]
            evidence["pg06_c4_real_code"]=z["fixture_facts"]["fixture_lint"]["real_code"]
            evidence["pg06_c2_diagnostic"]=z["c2"]["required_toolchains"][0]["diagnostic_status"]
            evidence["pg06_c3_diagnostic"]=z["c3"]["status"]
            evidence["pg06_c4_fixture_diagnostic"]=z["c4"]["status"]
            evidence["pg06_c5_diagnostic"]=z["c5"]["status"]
        # Independent downstream probes are attempted even when upstream
        # has an authentic gap; each row must specify exact fixture provenance.
        for stage in STAGES[3:]:
            table.append(entry(stage,"NOT_RUN",
                 "EX6_ORIGINAL_PRODUCER_INPUT_NOT_YET_BOUND",
                 "EX6_ONLY_NO_FABRICATED_RECEIPTS",producer_invoked=False))
        return {"stages":table,"evidence":evidence,
                "fixture_allowlist":FIXTURES,
                "patch_sha256":truth["patch_sha256"],
                "proposal_sha256":truth["proposal_sha256"],
                "api_calls":truth["api_calls"]}
    finally:
        uninstall()

if __name__=="__main__":
    print(json.dumps(run_all(),indent=2,sort_keys=True))
