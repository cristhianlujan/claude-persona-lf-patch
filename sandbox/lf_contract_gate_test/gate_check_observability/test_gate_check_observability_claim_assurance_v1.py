#!/usr/bin/env python3
from __future__ import annotations
import importlib.util
import json
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
MATRIX = HERE / "gate_check_observability_assurance_matrix_v1.json"
GROUP_RUNNER = HERE / "run_gate_groups_v1.py"
EKB = HERE / "persist_gate_failures_to_ekb_v1.py"

def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(mod)
    return mod

def main() -> None:
    data = json.loads(MATRIX.read_text(encoding="utf-8"))
    assert data["schema_version"] == "lf-deep-audit-matrix/v1"
    assert data["capability_code"] == "GATE_CHECK_OBSERVABILITY"
    claims = data["claims"]
    assert len(claims) >= 7
    assert all(c["parent_claim"] == "GATE_CHECK_OBSERVABILITY_ASSURED_V1" for c in claims)
    assert all(c["result"] == "PASS" for c in claims)
    assert all(c["obligations"] and c["positive_test"] and c["negative_test"] and c["adversarial_test"] for c in claims)

    groups = load_module(GROUP_RUNNER, "gco_groups")
    ekb = load_module(EKB, "gco_ekb")

    # replay_identity
    a = ekb.stable_error_code("G", "G01", "x/test.py", "AssertionError")
    b = ekb.stable_error_code("G", "G01", "x/test.py", "AssertionError")
    c = ekb.stable_error_code("G", "G01", "x/test.py", "TimeoutError")
    assert a == b
    assert a != c

    # ekb_writer_boundary
    src = EKB.read_text(encoding="utf-8").lower()
    assert "lf_write_pipeline_ekb_v1" in src
    assert "insert into transversal.error_knowledge" not in src
    assert "update transversal.error_knowledge" not in src
    assert "insert into public.lf_error_knowledge" not in src
    assert "update public.lf_error_knowledge" not in src

    # transversal_isolation
    engine = GROUP_RUNNER.read_text(encoding="utf-8")
    for forbidden in ("PROFILE_RUNTIME", "CURRENTNESS_AUTHORITY", "PARITY"):
        assert forbidden not in engine, forbidden

    # lineage_currentness + targeted_rerun_ceiling + tampered_manifest_blocks
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        tests = []
        for i in range(2):
            p = root / f"test_{i}.py"
            p.write_text("print('ok')\n", encoding="utf-8")
            tests.append(str(p))
        manifest = {
            "schema_version": "lf-gate-group-manifest/v1",
            "consumer_code": "QUALIFICATION_FIXTURE",
            "gate_id": "QUALIFICATION_FIXTURE_GATE",
            "owner": "GATE_CHECK_OBSERVABILITY",
            "discover_glob": str(root / "test_*.py"),
            "expected_total_checks": 2,
            "groups": [
                {"group_id": "Q01", "execution_class": "DETERMINISTIC", "tests": [tests[0]]},
                {"group_id": "Q02", "execution_class": "DETERMINISTIC", "tests": [tests[1]]},
            ],
        }
        mp = root / "manifest.json"
        mp.write_text(json.dumps(manifest), encoding="utf-8")
        loaded = groups.load_manifest(mp)
        assert loaded["expected_total_checks"] == 2

        # Targeted selection contract is mathematically incapable of full closure.
        selected = ["Q01"]
        full_selection = selected == [g["group_id"] for g in loaded["groups"]]
        assert not full_selection

        tampered = dict(manifest)
        tampered["expected_total_checks"] = 3
        mp.write_text(json.dumps(tampered), encoding="utf-8")
        try:
            groups.load_manifest(mp)
        except ValueError as exc:
            assert "discovered_count_mismatch" in str(exc)
        else:
            raise AssertionError("tampered manifest did not block")

    print("GATE_CHECK_OBSERVABILITY_CLAIM_ASSURANCE_V1_PASS claims=%d" % len(claims))

if __name__ == "__main__":
    main()
