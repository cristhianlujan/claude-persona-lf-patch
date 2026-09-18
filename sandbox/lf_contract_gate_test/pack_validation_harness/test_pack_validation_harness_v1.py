#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import shutil
import tempfile
from pathlib import Path

MODULE = Path(__file__).with_name("pack_validation_harness_v1.py")
spec = importlib.util.spec_from_file_location("pack_validation_harness_v1", MODULE)
mod = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(mod)

SHA = "a" * 40
POLICY_SHA = "b" * 64


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def py_json(path: Path, payload: dict, rc: int = 0) -> None:
    write(path, "import json\nprint(json.dumps(" + repr(payload) + "))\nraise SystemExit(" + str(rc) + ")\n")


def make_repo(
    root: Path,
    *,
    suite_pass: bool = True,
    suite_cases: int = 3,
    holdout_pass: bool = True,
    holdout_cases: int = 2,
    requested: int = 3,
) -> tuple[Path, Path]:
    profile = root / "profiles" / "alpha"
    write(profile / "SKILL.md", "# alpha\n")
    write(profile / "validators" / "validate_pack.py", "print('LOCAL_VALIDATOR_PASS')\n")
    py_json(
        profile / "evals" / "adversarial.py",
        {"passed": suite_pass, "case_count": suite_cases, "results_sha256": "producer-controlled"},
        0 if suite_pass else 1,
    )
    manifest = {
        "profile_pack_id": "ALPHA_V1",
        "target_code": "PERFIL-ALPHA",
        "pack_validation": {
            "validator_path": "validators/validate_pack.py",
            "suite_path": "evals/adversarial.py",
            "thresholds": {"min_profile_cases": requested},
            "enforcement_state": "NOT_ENFORCED",
        },
    }
    write(profile / "manifest.json", json.dumps(manifest))

    holdout = (
        root
        / "sandbox"
        / "lf_contract_gate_test"
        / "pack_validation_harness"
        / "holdouts"
        / "alpha_holdout.py"
    )
    py_json(
        holdout,
        {"passed": holdout_pass, "case_count": holdout_cases, "results_sha256": "producer-cannot-authorize"},
        0 if holdout_pass else 1,
    )

    inventory = [
        {
            "codigo_activo": "PERFIL-ALPHA",
            "ruta_esperada": "profiles/alpha",
            "estado_documental": "CANDIDATO",
            "estado_operativo": "READ_ONLY",
        }
    ]
    inv_path = root / "inventory.json"
    write(inv_path, json.dumps(inventory))

    policy = {
        "policy_code": "POL-PACK-VALIDATION-FLOOR",
        "policy_version": "v1.0",
        "policy_sha": POLICY_SHA,
        "policy_payload": {
            "schema": "LF_PACK_VALIDATION_FLOOR_V1",
            "requirements": {
                "inventory_reconciliation_required": True,
                "direct_suite_execution_required": True,
                "external_holdout_required_for_enforced": True,
                "hashes_computed_by_harness": True,
                "producer_self_exclusion_forbidden": True,
                "runtime_authorized_false": True,
                "automatic_impact_authorized_false": True,
            },
            "profiles": {
                "PERFIL-ALPHA": {
                    "enforcement_state": "ENFORCED",
                    "reason": "initial enforced fixture",
                    "min_profile_cases": 3,
                    "min_holdout_cases": 2,
                    "holdout_path": "sandbox/lf_contract_gate_test/pack_validation_harness/holdouts/alpha_holdout.py",
                    "allow_missing_materialization": False,
                }
            },
        },
    }
    policy_path = root / "policy.json"
    write(policy_path, json.dumps(policy))
    return inv_path, policy_path


def run(root: Path, inv: Path, policy: Path):
    return mod.evaluate(root, inv, policy, SHA, 10)


def profile(result):
    assert len(result["profiles"]) == 1, result
    return result["profiles"][0]


def test_happy():
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        inv, pol = make_repo(root)
        result = run(root, inv, pol)
        p = profile(result)
        assert result["status"] == "PASS", result
        assert p["status"] == "PASS", p
        assert p["enforcement_state"] == "ENFORCED", p
        assert p["case_count"] == 3 and p["holdout_case_count"] == 2, p
        assert p["runtime_authorized"] is False
        assert len(p["validator_sha256"]) == 64
        assert p["results_sha256"] not in {"producer-controlled", "producer-cannot-authorize"}


def test_manifest_cannot_self_exclude():
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        inv, pol = make_repo(root)
        result = run(root, inv, pol)
        assert profile(result)["enforcement_state"] == "ENFORCED"


def test_suite_direct_failure_beats_validator_pass():
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        inv, pol = make_repo(root, suite_pass=False)
        result = run(root, inv, pol)
        p = profile(result)
        assert result["status"] == "FAIL", result
        assert "PROFILE_SUITE_FAILED" in p["blocking_codes"], p


def test_holdout_failure_blocks():
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        inv, pol = make_repo(root, holdout_pass=False)
        result = run(root, inv, pol)
        assert result["status"] == "FAIL", result
        assert "EXTERNAL_HOLDOUT_FAILED" in profile(result)["blocking_codes"]


def test_floor_cannot_be_lowered_by_manifest():
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        inv, pol = make_repo(root, requested=2, suite_cases=3)
        result = run(root, inv, pol)
        assert result["status"] == "FAIL", result
        assert "PROFILE_THRESHOLD_BELOW_EXTERNAL_FLOOR" in profile(result)["blocking_codes"]


def test_disk_profile_without_inventory_blocks():
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        inv, pol = make_repo(root)
        rogue = root / "profiles" / "rogue"
        write(rogue / "SKILL.md", "# rogue\n")
        result = run(root, inv, pol)
        assert result["status"] == "FAIL", result
        assert "DISK_PROFILE_NOT_IN_GOVERNED_INVENTORY:rogue" in result["blocking_codes"]


def test_inventory_missing_disk_requires_external_not_enforced():
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        inv, pol = make_repo(root)
        shutil.rmtree(root / "profiles" / "alpha")
        result = run(root, inv, pol)
        assert result["status"] == "FAIL", result
        assert "INVENTORY_PROFILE_MISSING_ON_DISK" in profile(result)["blocking_codes"]


def test_external_not_enforced_can_account_for_unmaterialized_inventory():
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        inv, pol = make_repo(root)
        shutil.rmtree(root / "profiles" / "alpha")
        policy = json.loads(pol.read_text())
        entry = policy["policy_payload"]["profiles"]["PERFIL-ALPHA"]
        entry["enforcement_state"] = "NOT_ENFORCED"
        entry["allow_missing_materialization"] = True
        entry["reason"] = "governed migration debt pending materialization"
        pol.write_text(json.dumps(policy), encoding="utf-8")
        result = run(root, inv, pol)
        assert result["status"] == "PASS", result
        assert profile(result)["status"] == "NOT_ENFORCED"


def test_missing_external_floor_entry_blocks():
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        inv, pol = make_repo(root)
        policy = json.loads(pol.read_text())
        policy["policy_payload"]["profiles"] = {}
        pol.write_text(json.dumps(policy), encoding="utf-8")
        result = run(root, inv, pol)
        assert result["status"] == "FAIL", result
        assert "EXTERNAL_FLOOR_ENTRY_MISSING" in profile(result)["blocking_codes"]


def test_malformed_suite_output_fails_closed():
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        inv, pol = make_repo(root)
        write(root / "profiles" / "alpha" / "evals" / "adversarial.py", "print('not-json')\n")
        result = run(root, inv, pol)
        assert result["status"] == "FAIL", result
        assert "SUITE_OUTPUT_NOT_JSON" in profile(result)["blocking_codes"]


def test_policy_required_invariants_cannot_be_disabled():
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        inv, pol = make_repo(root)
        policy = json.loads(pol.read_text())
        policy["policy_payload"]["requirements"]["external_holdout_required_for_enforced"] = False
        pol.write_text(json.dumps(policy), encoding="utf-8")
        try:
            run(root, inv, pol)
        except ValueError as exc:
            assert str(exc).startswith("POLICY_REQUIRED_INVARIANT_DISABLED")
        else:
            raise AssertionError("expected fail-closed policy validation")


def main() -> None:
    tests = [
        value
        for name, value in sorted(globals().items())
        if name.startswith("test_") and callable(value)
    ]
    for test in tests:
        test()
    print(f"PASS_PACK_VALIDATION_HARNESS_V1={len(tests)}/{len(tests)}")


if __name__ == "__main__":
    main()
