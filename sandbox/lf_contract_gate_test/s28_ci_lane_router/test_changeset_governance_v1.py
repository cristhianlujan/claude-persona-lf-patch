#!/usr/bin/env python3
from lf_changeset_governance import ChangesetIntegrityError, evaluate_pr_integrity
from lf_ci_lane_router import classify


def expect(code, fn):
    try:
        fn()
    except ChangesetIntegrityError as exc:
        assert exc.code == code, (exc.code, code)
    else:
        raise AssertionError(code)


def main():
    checks = 0
    # D3 6/6
    r=evaluate_pr_integrity(["supabase/migrations/20260923000000_x.sql"]); assert r["families"] and not r["classification_required"]; checks+=1
    r=evaluate_pr_integrity([".github/workflows/x.yml"]); assert not r["classification_required"]; checks+=1
    r=evaluate_pr_integrity([".github/workflows/x.yml.bak"]); assert r["classification_required"] and r["violations"]==["UNDECLARED_PATH:.github/workflows/x.yml.bak"]
    r=evaluate_pr_integrity(["services/profile_runtime_api/x.py"]); assert r["families"]["services/profile_runtime_api/x.py"]=="SERVICE_RUNTIME"; checks+=1
    r=evaluate_pr_integrity(["changesets/SOL-1.json","custom/a.py"], manifest_data={"solution_ref":"SOL-1","paths":{"custom/a.py":"CUSTOM"}}); assert not r["classification_required"]; checks+=1
    r=evaluate_pr_integrity(["custom/a.py"]); assert r["classification_required"] and r["violations"]==["UNDECLARED_PATH:custom/a.py"]; checks+=1
    expect("FAIL_CHANGESET_FIXED_FAMILY_OVERRIDE", lambda: evaluate_pr_integrity(["changesets/SOL-2.json","services/a.py"], manifest_data={"solution_ref":"SOL-2","paths":{"services/a.py":"TEST"}})); checks+=1
    print(f"CHANGESET_FIXED_FAMILY_TESTS={checks}/6 PASS")
    # D4 2/2
    r=evaluate_pr_integrity(["changesets/SOL-3.json","other/a.txt"], manifest_data={"solution_ref":"SOL-3","paths":{"other/a.txt":"DOC"}}); assert r["solution_ref"]=="SOL-3"; checks2=1
    expect("FAIL_CHANGESET_MULTIPLE_SOLUTIONS", lambda: evaluate_pr_integrity(["changesets/A.json","changesets/B.json"])); checks2+=1
    print(f"CHANGESET_MANIFEST_TESTS={checks2}/2 PASS")
    routed=classify(["changesets/SOL-4.json","custom/x.py"], manifest_data={"solution_ref":"SOL-4","paths":{"custom/x.py":"CUSTOM"}})
    assert routed.mode != "CLASSIFICATION_REQUIRED" and not routed.migration_parity_required, routed
    unknown=classify(["custom/x.py"])
    assert unknown.mode == "CLASSIFICATION_REQUIRED" and not unknown.migration_parity_required, unknown
    print("CHANGESET_ROUTER_WIRING=2/2 PASS")

if __name__ == "__main__":
    main()
