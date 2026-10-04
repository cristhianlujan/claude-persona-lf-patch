#!/usr/bin/env python3
"""Owner-local executable surface for PROFILE_RUNTIME_V3.

Applicability is decided upstream. This runner executes only the checks already
owned by Profile Runtime and consumes the transversal gate-group engine only as
a deterministic execution dependency for the PROFILE_RUNTIME manifest.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[3]
MANIFEST = ROOT / "sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/profile_runtime_v3_gate_manifest.json"
CONTRACT = Path(__file__).with_name("profile_runtime_v3_owner_runner_v1.json")
DEFAULT_ARTIFACT_DIR = ROOT / ".lf_gate_diagnostics/profile_runtime_v3"


def command_specs(artifact_dir: Path = DEFAULT_ARTIFACT_DIR) -> list[dict[str, Any]]:
    return [
        {
            "id": "S26_E_GOVERNANCE_GATE",
            "argv": [
                sys.executable,
                "gobernanza/judges/validate_s26_governance_ekb_gate_strict.py",
                "--self-test",
                "--input",
                "sandbox/lf_contract_gate_test/s26_governance_ekb/s26_e_preexecution_receipt.json",
            ],
            "env": {},
        },
        {
            "id": "PERSISTENT_PROFILE_RUNTIME_API",
            "argv": [sys.executable, "-m", "pytest", "services/profile_runtime_api/tests"],
            "env": {
                "PYTHONPATH": "services/profile_runtime_api",
                "PYTHONDONTWRITEBYTECODE": "1",
            },
        },
        {
            "id": "SEMANTIC_TO_RENDER_BINDING",
            "argv": [
                sys.executable,
                "sandbox/lf_contract_gate_test/profile_execution_runtime/run_semantic_binding_validator_tests.py",
            ],
            "env": {},
        },
        {
            "id": "INDEPENDENT_RECEIPT_BUNDLE_BINDING",
            "argv": [
                sys.executable,
                "profiles/quality_pack/evals/run_independent_review_bundle_binding_tests.py",
            ],
            "env": {},
        },
        {
            "id": "PROFILE_RUNTIME_STRUCTURAL_GROUPS",
            "argv": [
                sys.executable,
                "sandbox/lf_contract_gate_test/gate_check_observability/run_gate_groups_v1.py",
                "--manifest",
                "sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/profile_runtime_v3_gate_manifest.json",
                "--artifact-dir",
                artifact_dir.relative_to(ROOT).as_posix() if artifact_dir.is_relative_to(ROOT) else str(artifact_dir),
            ],
            "env": {
                "LF_PERSISTENT_RUNTIME_SCOPE": "ISOLATED_CANDIDATE",
                "LF_LLAMA_SOURCE_COMMIT": "925e1179947ea0c0ebfb0032df18af3a729822be",
            },
        },
    ]


def self_test() -> dict[str, Any]:
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    specs = command_specs()

    assert contract["durable_name"] == "PROFILE_RUNTIME_V3_OWNER_RUNNER_V1"
    assert contract["owner"] == "PROFILE_RUNTIME"
    assert contract["input_contract"]["must_not_decide_run_skip"] is True
    assert contract["handoff"] == "PASE_ORCHESTRATOR_BIND_PROFILE_RUNTIME_V3"
    assert contract["merge_authorized"] is False
    assert contract["deployment_authorized"] is False
    assert contract["production_authorized"] is False

    assert manifest["consumer_code"] == "PROFILE_RUNTIME_V3"
    assert manifest["owner"] == "PROFILE_RUNTIME"
    assert manifest["gate_id"] == "PROFILE_RUNTIME_V3_STRUCTURAL_QUALITY"
    assert manifest["expected_total_checks"] == 46
    assert len(manifest["groups"]) == 10

    expected_ids = [
        "S26_E_GOVERNANCE_GATE",
        "PERSISTENT_PROFILE_RUNTIME_API",
        "SEMANTIC_TO_RENDER_BINDING",
        "INDEPENDENT_RECEIPT_BUNDLE_BINDING",
        "PROFILE_RUNTIME_STRUCTURAL_GROUPS",
    ]
    assert [spec["id"] for spec in specs] == expected_ids

    forbidden = (
        "validate-lf-packs.yml",
        "emit_ci_execution_plan_v2.py",
        "lf_ci_execution_plan_v2.py",
        "s30_bounded_regression",
        "qualify_wf_diagnostic_claim_v1.py",
        "qualify_deep_excel_matrix_v1.py",
        "transversal_asset_readme",
        "validate_pack.py",
        "lf-db-regression",
        "psql",
        "supabase",
        "deploy",
        "production",
    )
    flattened = "\n".join(" ".join(spec["argv"]) for spec in specs).lower()
    for token in forbidden:
        assert token.lower() not in flattened, token

    for spec in specs:
        for arg in spec["argv"]:
            if not isinstance(arg, str) or not arg:
                raise AssertionError(f"invalid argv for {spec['id']}")

    return {
        "schema_version": "lf-profile-runtime-v3-owner-runner-selftest/v1",
        "status": "PASS",
        "owner": "PROFILE_RUNTIME",
        "command_count": len(specs),
        "manifest_groups": len(manifest["groups"]),
        "manifest_checks": manifest["expected_total_checks"],
    }


def run(artifact_dir: Path) -> dict[str, Any]:
    if not MANIFEST.is_file():
        raise SystemExit("BLOCK_PROFILE_RUNTIME_V3_MANIFEST_MISSING")
    specs = command_specs(artifact_dir)
    results: list[dict[str, Any]] = []
    for spec in specs:
        env = os.environ.copy()
        env.update(spec["env"])
        print(f"PROFILE_RUNTIME_V3_OWNER_CHECK={spec['id']}", flush=True)
        completed = subprocess.run(spec["argv"], cwd=ROOT, env=env, check=False)
        results.append({"id": spec["id"], "returncode": completed.returncode})
        if completed.returncode != 0:
            raise SystemExit(f"BLOCK_PROFILE_RUNTIME_V3_OWNER_CHECK:{spec['id']}:rc={completed.returncode}")
    return {
        "schema_version": "lf-profile-runtime-v3-owner-runner/v1",
        "owner": "PROFILE_RUNTIME",
        "status": "PASS",
        "checks": results,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--artifact-dir", type=Path, default=DEFAULT_ARTIFACT_DIR)
    args = parser.parse_args()

    if args.self_test:
        payload = self_test()
        print("PROFILE_RUNTIME_V3_OWNER_RUNNER_V1=PASS 12/12")
        print(json.dumps(payload, sort_keys=True))
        return 0
    if args.list:
        print(json.dumps({"owner": "PROFILE_RUNTIME", "commands": command_specs(args.artifact_dir)}, sort_keys=True))
        return 0

    payload = run(args.artifact_dir.resolve())
    print(json.dumps(payload, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
