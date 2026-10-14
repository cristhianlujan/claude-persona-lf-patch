#!/usr/bin/env python3
"""Exact-source F09-014 golden, blocking, difficult and replay cases."""
from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
MANIFEST_PATH = HERE / "f09_014_quality_cases_v1.json"
BASE_SHA = "70e02ec0e82bdc7184ad004bd91eb3673f287e56"
HEX40 = re.compile(r"^[0-9a-f]{40}$")
PROFILE_DIR = ROOT / "sandbox/lf_contract_gate_test/pase_scenario_qualification/profiles"
SCENARIO_DIR = ROOT / "sandbox/lf_contract_gate_test/pase_scenario_qualification"
ASSURANCE_DIR = ROOT / "sandbox/lf_contract_gate_test/assurance_evaluator_boundary"


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise AssertionError(f"BLOCK_MODULE_LOAD:{path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def git_blob_sha(path: Path) -> str:
    raw = path.read_bytes()
    framed = b"blob " + str(len(raw)).encode("ascii") + b"\0" + raw
    return hashlib.sha1(framed).hexdigest()


def verify_source_bindings(manifest: dict) -> int:
    checked = 0
    for case in manifest["cases"]:
        for ref in case["source_refs"]:
            path = ROOT / ref["path"]
            actual = git_blob_sha(path)
            if actual != ref["blob_sha"]:
                raise AssertionError(f"BLOCK_SOURCE_SHA:{ref['path']}:{actual}")
            checked += 1
    return checked


def run_script(path: Path, expected_marker: str) -> str:
    proc = subprocess.run(
        ["python3", str(path)], cwd=ROOT, text=True, capture_output=True, check=False
    )
    out = (proc.stdout or "") + ("\n" + proc.stderr if proc.stderr else "")
    if proc.returncode != 0 or expected_marker not in out:
        raise AssertionError(f"FAIL_EXISTING_GOLDEN:{path.name}:rc={proc.returncode}")
    return out.strip()


def case_golden(manifest: dict) -> tuple[str, str]:
    qualifier = load_module(
        SCENARIO_DIR / "pase_scenario_qualification_v1.py", "f09_014_scenario_qualifier"
    )
    catalog = json.loads((SCENARIO_DIR / "pase_scenario_catalog_v1.json").read_text())
    qualifier.validate_catalog(catalog)
    profiles = sorted(PROFILE_DIR.glob("*.json"))
    if len(profiles) != 11:
        raise AssertionError(f"BLOCK_F04_PROFILE_COUNT:{len(profiles)}")
    profile_count = 0
    for path in profiles:
        profile = json.loads(path.read_text())
        qualifier.validate_profile(profile, catalog)
        selected, _ = qualifier.select_scenarios(catalog, profile["maturity"], set(profile["traits"]))
        selected_ids = {row["scenario_id"] for row in selected}
        assertion_ids = set(profile["assertions"])
        if selected_ids != assertion_ids:
            raise AssertionError(f"BLOCK_PROFILE_COVERAGE:{path.name}")
        if any(row.get("disposition") not in {"TESTED", "BLOCKED_EXPLICITLY"} for row in profile["assertions"].values()):
            raise AssertionError(f"BLOCK_PROFILE_TERMINAL_DISPOSITION:{path.name}")
        profile_count += 1
    run_script(SCENARIO_DIR / "test_pase_scenario_qualification_v1.py", "PASS_PASE_SCENARIO_QUALIFICATION_MATRIX_TESTS=")
    run_script(ASSURANCE_DIR / "test_assurance_evaluator_core_v1.py", "PASS_ASSURANCE_EVALUATOR_CORE_V1 checks=16")
    return "PASS", f"profiles={profile_count}; existing scenario and assurance regression suites passed"


def case_stale_f06() -> tuple[str, str]:
    path = ROOT / "sandbox/lf_contract_gate_test/pase_control_binding_inventory/pase_control_binding_inventory_v1.json"
    inventory = json.loads(path.read_text())
    embedded = inventory["observed_git_main_sha"]
    if embedded == BASE_SHA:
        raise AssertionError("FAIL_STALE_CASE_FIXTURE_WAS_REFRESHED")
    return "BLOCK_STALE_CURRENTNESS", f"embedded={embedded}; exact_main={BASE_SHA}; fixture unchanged"


def case_unknown_selected(head_sha: str) -> tuple[str, str]:
    qualifier = load_module(
        SCENARIO_DIR / "pase_scenario_qualification_v1.py", "f09_014_unknown_selected_qualifier"
    )
    catalog = json.loads((SCENARIO_DIR / "pase_scenario_catalog_v1.json").read_text())
    profile = json.loads((PROFILE_DIR / "assurance_evaluator_v1.json").read_text())
    selected, _ = qualifier.select_scenarios(catalog, profile["maturity"], set(profile["traits"]))
    if not selected:
        raise AssertionError("BLOCK_NO_SELECTED_SCENARIO")
    broken = copy.deepcopy(profile)
    del broken["assertions"][selected[0]["scenario_id"]]
    with tempfile.TemporaryDirectory(prefix="f09-014-unknown-") as td:
        runtime = Path(td)
        (runtime / "scope-manifest.json").write_text("{}", encoding="utf-8")
        (runtime / "run-summary.json").write_text("{}", encoding="utf-8")
        try:
            qualifier.qualify(
                root=ROOT,
                catalog=catalog,
                profile=broken,
                maturity=profile["maturity"],
                base_sha=BASE_SHA,
                head_sha=head_sha,
                runtime_dir=runtime,
            )
        except qualifier.ScenarioQualificationError as exc:
            if not str(exc).startswith("BLOCK_SCENARIO_SELECTED_UNKNOWN"):
                raise
            return "BLOCK_SCENARIO_SELECTED_UNKNOWN", "selected scenario missing assertion was explicitly blocked"
    raise AssertionError("FAIL_UNKNOWN_SELECTED_FALSE_PASS")


def case_provider_bound_receipt() -> tuple[str, str]:
    if str(ASSURANCE_DIR) not in sys.path:
        sys.path.insert(0, str(ASSURANCE_DIR))
    from assurance_evaluator_runner_v1 import run_assurance_evaluator
    import test_assurance_evaluator_core_v1 as fixture

    packet = fixture.packet()
    packet["obligations"] = [fixture.obligation(verification_method="INDEPENDENT_REVIEW")]
    packet["claim"] = fixture.claim(
        closure_rule={"open_defeater_blocks_pass": True, "independent_review_required": True}
    )
    packet["review_references"] = [
        fixture.review(mode="HISTORICAL_LEGACY_READBACK", review_type="S36_ASSURANCE")
    ]
    packet["evidence"] = [fixture.evidence(judge_result_id=fixture.JUDGE)]
    absent = run_assurance_evaluator(packet)
    if absent.get("evaluator_result", {}).get("result") != "UNPROVEN":
        raise AssertionError(f"FAIL_PROVIDER_RECEIPT_MISSING_FALSE_PASS:{absent}")
    if "INDEPENDENT_REVIEW_PROVIDER_BOUND_RECEIPT_REQUIRED" not in absent["evaluator_result"].get("reasons", []):
        raise AssertionError(f"FAIL_PROVIDER_RECEIPT_REASON_MISSING:{absent}")

    # A typed VERIFIED label and provider-shaped fields cannot stand in for an
    # accepted, provider-bound Evidence Ledger readback contract.
    spoofed = copy.deepcopy(packet)
    spoofed["review_references"][0].update(
        {
            "verification_state": "VERIFIED",
            "provider": "SUPABASE",
            "provider_ref": "receipt://unbound",
            "provider_readback_verified": True,
            "digest_recomputed": True,
        }
    )
    rejected = run_assurance_evaluator(spoofed)
    if rejected.get("status") != "BLOCKED" or rejected.get("reason_code") != "BLOCKED_REVIEW_REFERENCE_FIELDS":
        raise AssertionError(f"FAIL_UNBOUND_VERIFIED_RECEIPT_ACCEPTED:{rejected}")
    return "UNPROVEN_AND_BLOCKED", "missing receipt stays UNPROVEN; receipt-shaped unbound VERIFIED fields are explicitly BLOCKED"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--head-sha", required=True)
    args = parser.parse_args()
    if not HEX40.fullmatch(args.head_sha) or args.head_sha == BASE_SHA:
        raise AssertionError("BLOCK_EXACT_HEAD_ARGUMENT")
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    if manifest.get("base_main_sha") != BASE_SHA or len(manifest.get("cases", [])) != 4:
        raise AssertionError("BLOCK_CASE_MANIFEST_DRIFT")
    judge_path = "sandbox/lf_contract_gate_test/pase_evaluation_quality/test_f09_014_quality_cases_v1.py"
    for case in manifest["cases"]:
        if case.get("judge_path") != judge_path or judge_path in case.get("producer_paths", []):
            raise AssertionError(f"BLOCK_PRODUCER_JUDGE_NOT_INDEPENDENT:{case.get('case_id')}")
    source_count = verify_source_bindings(manifest)
    outcomes = [
        ("GOLDEN-SCENARIO-MATRIX", *case_golden(manifest)),
        ("BLOCK-STALE-F06-INVENTORY", *case_stale_f06()),
        ("BLOCK-UNKNOWN-SELECTED-SCENARIO", *case_unknown_selected(args.head_sha)),
        ("DIFFICULT-PROVIDER-BOUND-RECEIPT", *case_provider_bound_receipt()),
    ]
    for case_id, actual, detail in outcomes:
        print(f"F09_014_CASE={case_id} ACTUAL={actual} DETAIL={detail}")
    expected_blocking = {
        "BLOCK-STALE-F06-INVENTORY",
        "BLOCK-UNKNOWN-SELECTED-SCENARIO",
        "DIFFICULT-PROVIDER-BOUND-RECEIPT",
    }
    blockers = sum(1 for case_id, _, _ in outcomes if case_id in expected_blocking)
    false_passes = sum(
        1
        for case_id, actual, _ in outcomes
        if case_id in expected_blocking and actual == "PASS"
    )
    false_fails = sum(
        1
        for case_id, actual, _ in outcomes
        if case_id == "GOLDEN-SCENARIO-MATRIX" and actual != "PASS"
    )
    independent_pairs = sum(
        1 for case in manifest["cases"] if case["judge_path"] not in case["producer_paths"]
    )
    if false_passes != 0:
        raise AssertionError("FAIL_BLOCKING_FALSE_PASS_TOLERANCE")
    if blockers != 3:
        raise AssertionError(f"FAIL_EXPECTED_BLOCKING_CASES:{blockers}")
    if independent_pairs != len(manifest["cases"]):
        raise AssertionError("FAIL_PRODUCER_JUDGE_INDEPENDENCE")
    print(f"PASS_F09_014_CASES=4/4 source_refs={source_count} false_pass={false_passes} false_fail={false_fails} producer_judge_independent={independent_pairs}/4 blockers={blockers}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
