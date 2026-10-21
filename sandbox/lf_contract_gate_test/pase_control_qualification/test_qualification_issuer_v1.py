#!/usr/bin/env python3
from __future__ import annotations

import copy
import importlib.util
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
TARGET = HERE / "qualification_issuer_v1.py"


def load():
    spec = importlib.util.spec_from_file_location("issuer", TARGET)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def snapshot():
    return {
        "schema_version": "lf-pase-control-qualification-issuer-input/v1",
        "repository": "cristhianlujan/claude-persona-lf-patch",
        "pr_number": 4242,
        "base_sha": "1" * 40,
        "head_sha": "2" * 40,
        "observed_main_sha": "1" * 40,
        "candidate_id": "EXAMPLE_CONTROL_V1",
        "declared_owner": "LF_GOVERNANCE",
        "qualification_type": "CONTROL_REFACTOR",
        "builder_session_id": "builder-session-001",
        "builder_session_ref": "https://chatgpt.com/share/builder-001",
        "route": {
            "schema_version": "lf-pase-merge-route/v1",
            "mode": "CONTROL_SYSTEM_QUALIFICATION",
            "candidate_id": "EXAMPLE_CONTROL_V1",
        },
        "changeset_manifest_sha256": "3" * 64,
        "scope_paths": ["sandbox/example_control/"],
        "owner_local_tests": ["python3 sandbox/example_control/test.py"],
        "boundary_invariants": ["EXAMPLE_BOUNDARY"],
        "expected_coverage": ["EXAMPLE_RESPONSIBILITY"],
        "replacement": None,
        "changed_files": [
            {
                "path": "sandbox/example_control/control.py",
                "status": "modified",
                "blob_sha": "4" * 40,
                "review_material": True,
            },
            {
                "path": "sandbox/lf_contract_gate_test/changesets/example.json",
                "status": "added",
                "blob_sha": "5" * 40,
                "review_material": False,
            },
        ],
        "auto_evidence": {
            "Q01": ["git://exact-head@"+("2"*40)],
            "Q02": ["changeset://manifest@"+("3"*64)],
            "Q03": ["route://owner=LF_GOVERNANCE"],
            "Q04": ["github-check://owner-local-tests/success@"+("2"*40)],
            "Q07": ["changeset://no-out-of-scope-effects"],
            "Q08": ["issuer://deterministic-request-identity"],
            "Q11": ["github://exact-head-readback@"+("2"*40)],
        },
    }


def review(m, snap, *, verdict="REVIEW_PASS", reviewer="reviewer-session-002"):
    material = m.material_sha256(snap)
    rows = [
        {"id": "Q05", "status": "PASS", "evidence": ["review://boundary"], "rationale": "Boundary ownership is preserved."},
        {"id": "Q06", "status": "PASS", "evidence": ["review://negative"], "rationale": "Negative and adversarial behavior fails closed."},
        {"id": "Q09", "status": "NA", "evidence": [], "rationale": "Not a CONTROL_REPLACEMENT candidate."},
        {"id": "Q10", "status": "PASS", "evidence": ["review://coverage"], "rationale": "Declared responsibility coverage is preserved."},
    ]
    if verdict == "REVIEW_BLOCK":
        rows[-1] = {"id": "Q10", "status": "BLOCKED", "evidence": ["review://coverage-missing"], "rationale": "Coverage cannot be proven."}
    if verdict == "REVIEW_FAIL":
        rows[0] = {"id": "Q05", "status": "FAIL", "evidence": ["review://boundary-violation"], "rationale": "Boundary violation is material."}
    return {
        "schema_version": "lf-pase-control-independent-review/v1",
        "repository": snap["repository"],
        "pr_number": snap["pr_number"],
        "candidate_id": snap["candidate_id"],
        "candidate_material_sha256": material,
        "builder_session_id": snap["builder_session_id"],
        "builder_session_ref": snap["builder_session_ref"],
        "reviewer_session_id": reviewer,
        "reviewer_session_ref": "https://chatgpt.com/share/" + reviewer,
        "blind_review": True,
        "checks": rows,
        "verdict": verdict,
    }


def expect_error(m, snap, rev, prefix):
    try:
        m.build(snap, rev)
    except m.IssuerError as exc:
        assert str(exc).startswith(prefix), (prefix, str(exc))
        return
    raise AssertionError(prefix)


def main():
    m = load()
    checks = 0

    # Canary A / R6: no review => BLOCK.
    s = snapshot()
    expect_error(m, s, None, "BLOCK_QUALIFICATION_REVIEW_MISSING")
    checks += 1

    # Canary B: valid independent review => exact packet READY_TO_RECORD.
    r = review(m, s)
    out = m.build(s, r)
    assert out["status"] == "READY_TO_RECORD"
    assert out["recordable"] is True
    assert out["qualification_result"]["verdict"] == "CANDIDATE_QUALIFIED"
    assert out["candidate_material_sha256"] == r["candidate_material_sha256"]
    checks += 1

    # R4: exact retry is deterministic: same identities and request digest.
    out2 = m.build(copy.deepcopy(s), copy.deepcopy(r))
    for key in ("source_execution_id", "idempotency_key", "request_sha256", "candidate_material_sha256", "review_sha256"):
        assert out[key] == out2[key], key
    checks += 1

    # Canary C / R5: builder == reviewer => BLOCK.
    same = review(m, s, reviewer=s["builder_session_id"])
    same["reviewer_session_ref"] = s["builder_session_ref"]
    expect_error(m, s, same, "BLOCK_QUALIFICATION_REVIEW_NOT_INDEPENDENT")
    checks += 1

    # Canary D / R5: protected qualifier path => escalation.
    protected = copy.deepcopy(s)
    protected["changed_files"][0] = {
        "path": "sandbox/lf_contract_gate_test/pase_control_qualification/qualification_issuer_v1.py",
        "status": "modified",
        "blob_sha": "6" * 40,
        "review_material": True,
    }
    expect_error(m, protected, review(m, protected), "ESCALATE_CONTROL_SYSTEM_SELF_CHANGE")
    checks += 1

    # R5: future DB issuer wrapper migration is also a protected self-change.
    protected_migration = copy.deepcopy(s)
    protected_migration["changed_files"][0] = {
        "path": "supabase/migrations/20261022000000_lf_ci_control_system_qualification_issuer_v1.sql",
        "status": "added",
        "blob_sha": "8" * 40,
        "review_material": True,
    }
    expect_error(
        m,
        protected_migration,
        review(m, protected_migration),
        "ESCALATE_CONTROL_SYSTEM_SELF_CHANGE",
    )
    checks += 1

    # R6: reviewer disagreement BLOCKED never becomes recordable/PASS.
    blocked = review(m, s, verdict="REVIEW_BLOCK")
    got = m.build(s, blocked)
    assert got["status"] == "BLOCKED" and got["recordable"] is False
    assert got["qualification_result"]["verdict"] == "BLOCKED"
    checks += 1

    # Reviewer FAIL never becomes recordable/PASS.
    failed = review(m, s, verdict="REVIEW_FAIL")
    got = m.build(s, failed)
    assert got["status"] == "FAIL" and got["recordable"] is False
    assert got["qualification_result"]["verdict"] == "FAIL"
    checks += 1

    # Material drift invalidates an otherwise valid review.
    drift = copy.deepcopy(s)
    drift["changed_files"][0]["blob_sha"] = "7" * 40
    expect_error(m, drift, r, "BLOCK_QUALIFICATION_REVIEW_STALE")
    checks += 1

    # Review transport is not part of the material hash.
    s2 = copy.deepcopy(s)
    s2["builder_session_ref"] = "https://chatgpt.com/share/builder-changed-metadata"
    assert m.material_sha256(s) == m.material_sha256(s2)
    checks += 1

    # Contract source must remain a dry-run builder: no writer/network primitives.
    source = TARGET.read_text(encoding="utf-8")
    for forbidden in ("execute_sql", "apply_migration", "psycopg", "psql", "requests.", "urllib.request", "subprocess.run"):
        assert forbidden not in source, forbidden
    checks += 1

    print(f"PASS_PASE_CONTROL_QUALIFICATION_ISSUER_V1 checks={checks}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
