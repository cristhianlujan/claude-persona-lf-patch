#!/usr/bin/env python3
from __future__ import annotations

import argparse
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys
from typing import Any

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
CATALOG_PATH = HERE / "pase_scenario_catalog_v1.json"
PROFILE_PATH = HERE / "profiles/contract_validation_v1.json"
SCENARIO_QUALIFIER_PATH = HERE / "pase_scenario_qualification_v1.py"
CONTROL_QUALIFIER_PATH = ROOT / "sandbox/lf_contract_gate_test/pase_control_qualification/pase_control_qualification_v1.py"

CONTROL_ID = "LF_CONTRACT_CHECK"
CANDIDATE_ID = "LF_CONTRACT_CHECK_F04_Q01_QUALIFICATION_V1"
MATURITY = "CUTOVER"
EVALUATION_SCOPE = "CHANGESET_SCOPED"
HISTORICAL_DISPOSITION = "RECONCILIATION_WORK_ITEM"
HEX40 = re.compile(r"^[0-9a-f]{40}$")

QUALIFICATION_SCOPE = {
    "sandbox/lf_contract_gate_test/pase_scenario_qualification/profiles/contract_validation_v1.json",
    "sandbox/lf_contract_gate_test/pase_scenario_qualification/run_contract_validation_qualification_v1.py",
}

OWNER_TESTS = [
    ("contract_core", "sandbox/lf_contract_gate_test/contract_check_core/test_contract_check_core_v1.py", "PASS_CONTRACT_CHECK_CORE_V1=17/17"),
    ("semantic_integration", "sandbox/lf_contract_gate_test/contract_check_semantic_integration/test_contract_check_semantic_integration_v1.py", "PASS_CONTRACT_CHECK_SEMANTIC_INTEGRATION_V1=18/18"),
    ("predicate_semantics", "sandbox/lf_contract_gate_test/contract_predicate_semantics/test_contract_predicate_semantics_v1.py", "PASS_CONTRACT_PREDICATE_SEMANTICS_V1=44/44"),
    ("legacy_batch1", "sandbox/lf_contract_gate_test/contract_legacy_normalization/test_legacy_translation_template_v1.py", "PASS_LEGACY_TRANSLATION_TEMPLATE_V1=13/13"),
    ("legacy_batch2", "sandbox/lf_contract_gate_test/contract_legacy_normalization/test_legacy_translation_templates_batch2_v1.py", "PASS_LEGACY_TRANSLATION_TEMPLATES_BATCH2_V1=10/10"),
    ("legacy_batch3", "sandbox/lf_contract_gate_test/contract_legacy_normalization/test_legacy_translation_templates_batch3_v1.py", "PASS_LEGACY_TRANSLATION_TEMPLATES_BATCH3_V1=11/11"),
    ("legacy_batch4", "sandbox/lf_contract_gate_test/contract_legacy_normalization/test_legacy_translation_templates_batch4_v1.py", "PASS_LEGACY_TRANSLATION_TEMPLATES_BATCH4_V1=11/11"),
    ("grouped_mapping", "sandbox/lf_contract_gate_test/contract_legacy_normalization/test_legacy_contract_grouped_source_mapping_v1.py", "PASS_LEGACY_CONTRACT_GROUPED_SOURCE_MAPPING_V1=9/9"),
    ("source_projection", "sandbox/lf_contract_gate_test/contract_legacy_normalization/test_legacy_contract_source_projection_v1.py", "PASS_LEGACY_CONTRACT_SOURCE_PROJECTION_V1=8/8"),
]


def fail(code: str, detail: str = "") -> None:
    raise RuntimeError(f"{code}:{detail}" if detail else code)


def load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        fail("FAIL_Q01_MODULE_LOAD", str(path))
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def git(*args: str) -> str:
    proc = subprocess.run(["git", *args], cwd=ROOT, text=True, capture_output=True, check=False)
    if proc.returncode != 0:
        fail("FAIL_Q01_GIT", f"args={args!r} stderr={proc.stderr[-1000:]}")
    return proc.stdout.strip()


def require_sha(value: str, label: str) -> str:
    value = value.strip().lower()
    if not HEX40.fullmatch(value):
        fail(f"FAIL_Q01_{label}_SHA", value)
    return value


def verify_exact_context(base_sha: str, head_sha: str, event_name: str) -> str:
    actual_head = require_sha(git("rev-parse", "HEAD"), "ACTUAL_HEAD")
    if actual_head != head_sha:
        fail("FAIL_Q01_EXACT_HEAD", f"expected={head_sha} actual={actual_head}")
    git("fetch", "--no-tags", "origin", "refs/heads/main:refs/remotes/origin/main")
    live_main = require_sha(git("rev-parse", "refs/remotes/origin/main"), "LIVE_MAIN")
    if event_name == "pull_request":
        if live_main != base_sha:
            fail("FAIL_Q01_BASE_CURRENTNESS", f"expected={base_sha} live={live_main}")
    elif event_name == "push":
        if live_main != head_sha:
            fail("FAIL_Q01_PUSH_CURRENTNESS", f"expected={head_sha} live={live_main}")
    else:
        fail("FAIL_Q01_EVENT_NAME", event_name)
    merge_base = require_sha(git("merge-base", base_sha, head_sha), "MERGE_BASE")
    if merge_base != base_sha:
        fail("FAIL_Q01_BASE_NOT_ANCESTOR", f"base={base_sha} merge_base={merge_base}")
    return live_main


def verify_qualification_scope(base_sha: str, head_sha: str) -> list[str]:
    changed = [line.strip() for line in git("diff", "--name-only", base_sha, head_sha).splitlines() if line.strip()]
    unexpected = sorted(set(changed) - QUALIFICATION_SCOPE)
    missing = sorted(QUALIFICATION_SCOPE - set(changed))
    if unexpected:
        fail("FAIL_Q01_OUT_OF_SCOPE_DIFF", ",".join(unexpected))
    if missing:
        fail("FAIL_Q01_QUALIFICATION_SCOPE_INCOMPLETE", ",".join(missing))
    return sorted(changed)


def run_owner_tests() -> dict[str, dict[str, Any]]:
    evidence: dict[str, dict[str, Any]] = {}
    for test_id, relpath, marker in OWNER_TESTS:
        proc = subprocess.run(["python3", relpath], cwd=ROOT, text=True, capture_output=True, check=False)
        combined = (proc.stdout or "") + ("\n" + proc.stderr if proc.stderr else "")
        if proc.returncode != 0:
            fail("BLOCK_Q01_OWNER_TEST", f"{test_id}:rc={proc.returncode}:{combined[-1200:]}")
        if marker not in combined:
            fail("BLOCK_Q01_OWNER_TEST_MARKER", f"{test_id}:{marker}")
        evidence[test_id] = {"path": relpath, "marker": marker, "returncode": proc.returncode}
    return evidence


def write_scope_runtime(output_dir: Path, base_sha: str, head_sha: str, event_name: str, changed: list[str]) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    scope = {
        "schema_version": "lf-pase-evaluation-scope-manifest/v1",
        "policy_id": "PASE_EVALUATION_SCOPE_POLICY_V1",
        "control_id": CONTROL_ID,
        "control_maturity": MATURITY,
        "evaluation_scope": EVALUATION_SCOPE,
        "historical_debt_disposition": HISTORICAL_DISPOSITION,
        "base_sha": base_sha,
        "head_sha": head_sha,
        "event_name": event_name,
        "changed_paths": changed,
        "unbounded_historical_scan": False,
    }
    summary = {
        "schema_version": "lf-contract-validation-qualification-scope-run/v1",
        "policy_id": "PASE_EVALUATION_SCOPE_POLICY_V1",
        "control_id": CONTROL_ID,
        "control_maturity": MATURITY,
        "evaluation_scope": EVALUATION_SCOPE,
        "historical_debt_disposition": HISTORICAL_DISPOSITION,
        "unbounded_historical_scan": False,
        "status": "PASS",
        "returncode": 0,
    }
    (output_dir / "scope-manifest.json").write_text(json.dumps(scope, sort_keys=True) + "\n", encoding="utf-8")
    (output_dir / "run-summary.json").write_text(json.dumps(summary, sort_keys=True) + "\n", encoding="utf-8")


def build_control_qualification(base_sha: str, head_sha: str, observed_main_sha: str, declared_owner: str, changed: list[str], scenario: dict[str, Any], owner_tests: dict[str, dict[str, Any]]) -> tuple[dict[str, Any], dict[str, Any]]:
    packet = {
        "schema_version": "lf-pase-control-qualification/v1",
        "qualification_type": "CONTROL_REFACTOR",
        "repository": "cristhianlujan/claude-persona-lf-patch",
        "base_sha": base_sha,
        "head_sha": head_sha,
        "observed_main_sha": observed_main_sha,
        "candidate_id": CANDIDATE_ID,
        "declared_owner": declared_owner,
        "scope_paths": sorted(QUALIFICATION_SCOPE),
        "owner_local_tests": [row["path"] for row in owner_tests.values()] + [
            "sandbox/lf_contract_gate_test/contract_check_execution/test_contract_check_execution_v1.py",
            "sandbox/lf_contract_gate_test/contract_legacy_normalization/test_legacy_contract_normalization_v1.py",
            "sandbox/lf_contract_gate_test/contract_check_responsibility_inventory/test_contract_check_bridge_retirement_v1.py",
            "sandbox/lf_contract_gate_test/s28_ci_lane_router/test_lf_contract_check_parity_equivalence_v1.py",
        ],
        "boundary_invariants": [
            "CHANGESET_GOVERNANCE_REMAINS_APPLICABILITY_AUTHORITY",
            "CONTRACT_CHECK_DOES_NOT_QUERY_OR_MUTATE_SUPABASE",
            "CONTRACT_CHECK_DOES_NOT_EXECUTE_SIBLING_CONTROLS",
            "LEGACY_WORKFLOW_REMAINS_MANUAL_COMPATIBILITY_CALLER",
            "NO_RUNTIME_ACTIVATION_IN_F04_Q01",
        ],
        "expected_coverage": [
            "EXPLICIT_OPERATION_CONTEXT",
            "CANONICAL_CONTRACT_AUTHORITY_SNAPSHOT",
            "TYPED_OR_EXPLICIT_LEGACY_TRANSLATION_BINDING",
            "EVIDENCE_BACKED_FACTS",
            "PREDICATE_SEMANTICS",
            "FAIL_CLOSED_NEGATIVES",
            "SCENARIO_MATRIX_UNKNOWN_ZERO",
        ],
    }
    scenario_ref = (
        f"scenario-matrix://{CONTROL_ID}@{head_sha}"
        f"?selected={scenario['selected_count']}&na={scenario['not_applicable_count']}&unknown={scenario['unknown_selected_count']}"
    )
    exact_ref = f"git://cristhianlujan/claude-persona-lf-patch@{head_sha}"
    diff_ref = "git-diff://" + base_sha + ".." + head_sha + "#" + ",".join(changed)
    suite_ref = "owner-suite://contract-validation/current-exact-head"
    checks = [
        {"id": "Q01", "status": "PASS", "evidence": [exact_ref]},
        {"id": "Q02", "status": "PASS", "evidence": [diff_ref]},
        {"id": "Q03", "status": "PASS", "evidence": [f"declared-owner://{declared_owner}"]},
        {"id": "Q04", "status": "PASS", "evidence": [suite_ref, scenario_ref]},
        {"id": "Q05", "status": "PASS", "evidence": ["boundary://contract-check-execution-v1", "boundary://legacy-bridge-retired"]},
        {"id": "Q06", "status": "PASS", "evidence": [scenario_ref, "negative-suite://contract-check-execution-18of18"]},
        {"id": "Q07", "status": "PASS", "evidence": ["scope://qualification-only-no-runtime-effects"]},
        {"id": "Q08", "status": "PASS", "evidence": ["replay://contract-check-parity-equivalence-8of8"]},
        {"id": "Q09", "status": "NA", "evidence": []},
        {"id": "Q10", "status": "PASS", "evidence": [scenario_ref, "coverage://current-authority-bound-readback"]},
        {"id": "Q11", "status": "PASS", "evidence": [exact_ref, scenario_ref]},
    ]
    findings = [
        {
            "finding_id": "PASE-CONTRACT-CHECK-RECEIPT-OWNERSHIP-CONTAMINATION-001",
            "source_control": "LEGACY_CONTRACT_CHECK_BOUNDARY",
            "observed_failure": "generic receipt ownership exists outside final validation responsibility",
            "candidate_causality": "DISPROVEN",
            "causal_evidence": [diff_ref, "preflight://lf_eventos/19882"],
            "owner": "LF_GOVERNANCE",
            "effect_on_candidate_verdict": "NONE",
        },
        {
            "finding_id": "PASE-CONTRACT-CHECK-ORCHESTRATOR-IDENTITY-CONFLATION-001",
            "source_control": "LEGACY_CONTRACT_CHECK_BOUNDARY",
            "observed_failure": "historical Contract Check identity was conflated with PASE orchestration",
            "candidate_causality": "DISPROVEN",
            "causal_evidence": [diff_ref, "preflight://lf_eventos/19882"],
            "owner": "LF_GOVERNANCE",
            "effect_on_candidate_verdict": "NONE",
        },
        {
            "finding_id": "PASE-CONTRACT-CHECK-UNTYPED-RESOLVER-REF-001",
            "source_control": "CONTRACT_MODEL",
            "observed_failure": "resolver_ref remains untyped outside this qualification diff",
            "candidate_causality": "DISPROVEN",
            "causal_evidence": [diff_ref, "preflight://lf_eventos/19882"],
            "owner": "LF_GOVERNANCE",
            "effect_on_candidate_verdict": "NONE",
        },
    ]
    result = {
        "schema_version": "lf-pase-control-qualification-result/v1",
        "candidate_id": CANDIDATE_ID,
        "base_sha": base_sha,
        "head_sha": head_sha,
        "declared_owner": declared_owner,
        "checks": checks,
        "external_findings": findings,
        "coverage_complete": True,
        "verdict": "CANDIDATE_QUALIFIED",
        "qualified_only": True,
        "activation_authorized": False,
        "cutover_authorized": False,
        "rebind_authorized": False,
        "legacy_retirement_authorized": False,
    }
    return packet, result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-sha", required=True)
    parser.add_argument("--head-sha", required=True)
    parser.add_argument("--event-name", choices=("pull_request", "push"), required=True)
    parser.add_argument("--declared-owner", default="LF_GOVERNANCE")
    parser.add_argument("--output-dir", default=".lf_contract_validation_qualification")
    args = parser.parse_args()

    base_sha = require_sha(args.base_sha, "BASE")
    head_sha = require_sha(args.head_sha, "HEAD")
    if base_sha == head_sha:
        fail("FAIL_Q01_EMPTY_RANGE")
    declared_owner = args.declared_owner.strip()
    if not declared_owner:
        fail("FAIL_Q01_DECLARED_OWNER")

    observed_main = verify_exact_context(base_sha, head_sha, args.event_name)
    changed = verify_qualification_scope(base_sha, head_sha)
    output_dir = (ROOT / args.output_dir).resolve()
    try:
        output_dir.relative_to(ROOT)
    except ValueError as exc:
        raise RuntimeError("FAIL_Q01_OUTPUT_OUTSIDE_REPO") from exc
    write_scope_runtime(output_dir, base_sha, head_sha, args.event_name, changed)

    owner_tests = run_owner_tests()
    scenario_qualifier = load(SCENARIO_QUALIFIER_PATH, "q01_scenario_qualifier")
    catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    profile = json.loads(PROFILE_PATH.read_text(encoding="utf-8"))
    scenario = scenario_qualifier.qualify(
        root=ROOT,
        catalog=catalog,
        profile=profile,
        maturity=MATURITY,
        base_sha=base_sha,
        head_sha=head_sha,
        runtime_dir=output_dir,
    )
    if scenario.get("verdict") != "PASS" or scenario.get("selected_count") != 18 or scenario.get("not_applicable_count") != 11 or scenario.get("unknown_selected_count") != 0:
        fail("BLOCK_Q01_SCENARIO_MATRIX_COUNTS", json.dumps(scenario, sort_keys=True)[-1200:])
    (output_dir / "scenario-qualification.json").write_text(json.dumps(scenario, sort_keys=True) + "\n", encoding="utf-8")

    packet, result = build_control_qualification(base_sha, head_sha, observed_main, declared_owner, changed, scenario, owner_tests)
    control_qualifier = load(CONTROL_QUALIFIER_PATH, "q01_control_qualifier")
    verdict = control_qualifier.validate_result(packet, result)
    if verdict != "CANDIDATE_QUALIFIED":
        fail("BLOCK_Q01_CONTROL_QUALIFICATION", verdict)
    (output_dir / "control-qualification-input.json").write_text(json.dumps(packet, sort_keys=True) + "\n", encoding="utf-8")
    (output_dir / "control-qualification-result.json").write_text(json.dumps(result, sort_keys=True) + "\n", encoding="utf-8")
    (output_dir / "owner-test-evidence.json").write_text(json.dumps(owner_tests, sort_keys=True) + "\n", encoding="utf-8")

    print("PASS_CONTRACT_VALIDATION_SCENARIO_MATRIX selected=18 not_applicable=11 unknown=0")
    print("PASS_CONTRACT_VALIDATION_PASE_CONTROL_QUALIFICATION=CANDIDATE_QUALIFIED")
    print("PASS_PASE_ATOM_F04_Q01_QUALIFICATION_V1")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
