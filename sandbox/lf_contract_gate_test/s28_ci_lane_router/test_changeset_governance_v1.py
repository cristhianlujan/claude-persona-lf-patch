#!/usr/bin/env python3
from lf_ci_lane_router import classify
from lf_changeset_governance import ChangesetIntegrityError, compile_family_registry, evaluate_pr_integrity

MANIFEST_PREFIX = "sandbox/lf_contract_gate_test/changesets"


def manifest(name: str) -> str:
    return f"{MANIFEST_PREFIX}/{name}.json"


def expect(code, fn):
    try:
        fn()
    except ChangesetIntegrityError as exc:
        assert exc.code == code, (exc.code, code)
    else:
        raise AssertionError(code)


def main():
    checks = 0

    r = evaluate_pr_integrity(["supabase/migrations/20260923000000_x.sql"])
    assert r["families"] and not r["classification_required"]
    checks += 1

    r = evaluate_pr_integrity([".github/workflows/lf-contract-check.yml"])
    assert r["families"][".github/workflows/lf-contract-check.yml"] == "WORKFLOW"
    assert not r["classification_required"]
    checks += 1

    expect(
        "FAIL_UNAUTHORIZED_GITHUB_PATH",
        lambda: evaluate_pr_integrity([".github/workflows/x.yml"]),
    )
    checks += 1

    expect(
        "FAIL_UNAUTHORIZED_GITHUB_PATH",
        lambda: evaluate_pr_integrity([".github/workflows/x.yml.bak"]),
    )
    checks += 1

    r = evaluate_pr_integrity(["services/profile_runtime_api/x.py"])
    assert r["families"]["services/profile_runtime_api/x.py"] == "SERVICE_RUNTIME"
    checks += 1

    grouped = compile_family_registry({
        "registry_version": "LF_CHANGE_FAMILY_REGISTRY_V1",
        "fixed_families": [{
            "family": "GROUPED_TEST_FAMILY",
            "kind": "prefixes",
            "prefixes": ["sandbox/lf_contract_gate_test/group_a/", "sandbox/lf_contract_gate_test/group_b/"],
        }],
        "family_controls": {"GROUPED_TEST_FAMILY": ["CI_ROUTER_SELFTEST"]},
    })
    assert grouped.family_for("sandbox/lf_contract_gate_test/group_a/test.py") == "GROUPED_TEST_FAMILY"
    assert grouped.family_for("sandbox/lf_contract_gate_test/group_b/test.py") == "GROUPED_TEST_FAMILY"
    assert grouped.family_for("sandbox/lf_contract_gate_test/group_c/test.py") is None
    checks += 1

    expect(
        "FAIL_CHANGESET_FIXED_FAMILY_MATCHER",
        lambda: compile_family_registry({
            "registry_version": "LF_CHANGE_FAMILY_REGISTRY_V1",
            "fixed_families": [{"family": "BAD_GROUP", "kind": "prefixes", "prefixes": ["../outside/"]}],
            "family_controls": {"BAD_GROUP": ["CI_ROUTER_SELFTEST"]},
        }),
    )
    checks += 1

    r = evaluate_pr_integrity(
        [manifest("SOL-1"), "custom/a.py"],
        manifest_data={"solution_ref": "SOL-1", "paths": {"custom/a.py": "CUSTOM"}},
    )
    assert not r["classification_required"]
    checks += 1

    r = evaluate_pr_integrity(["custom/a.py"])
    assert r["classification_required"] and r["violations"] == ["UNDECLARED_PATH:custom/a.py"]
    checks += 1

    expect(
        "FAIL_CHANGESET_FIXED_FAMILY_OVERRIDE",
        lambda: evaluate_pr_integrity(
            [manifest("SOL-2"), "services/a.py"],
            manifest_data={"solution_ref": "SOL-2", "paths": {"services/a.py": "TEST"}},
        ),
    )
    checks += 1

    legacy_root = "changesets/SOL-LEGACY.json"
    r = evaluate_pr_integrity([legacy_root])
    assert r["classification_required"] and r["violations"] == [f"UNDECLARED_PATH:{legacy_root}"]
    checks += 1
    print(f"CHANGESET_FIXED_FAMILY_TESTS={checks}/11 PASS")

    r = evaluate_pr_integrity(
        [manifest("SOL-3"), "other/a.txt"],
        manifest_data={"solution_ref": "SOL-3", "paths": {"other/a.txt": "DOC"}},
    )
    assert r["solution_ref"] == "SOL-3"
    checks2 = 1

    expect(
        "FAIL_CHANGESET_MULTIPLE_SOLUTIONS",
        lambda: evaluate_pr_integrity([manifest("A"), manifest("B")]),
    )
    checks2 += 1
    print(f"CHANGESET_MANIFEST_TESTS={checks2}/2 PASS")

    routed = classify(
        [manifest("SOL-4"), "custom/x.py"],
        manifest_data={"solution_ref": "SOL-4", "paths": {"custom/x.py": "CUSTOM"}},
    )
    assert routed.mode != "CLASSIFICATION_REQUIRED" and not routed.migration_parity_required, routed

    unknown = classify(["custom/x.py"])
    assert unknown.mode == "CLASSIFICATION_REQUIRED" and not unknown.migration_parity_required, unknown

    try:
        classify([".github/workflows/unregistered.yml"])
    except ChangesetIntegrityError as exc:
        assert exc.code == "FAIL_UNAUTHORIZED_GITHUB_PATH", exc
    else:
        raise AssertionError("unregistered GitHub workflow bypassed Changeset Governance admission")
    print("CHANGESET_ROUTER_WIRING=3/3 PASS")


if __name__ == "__main__":
    main()
