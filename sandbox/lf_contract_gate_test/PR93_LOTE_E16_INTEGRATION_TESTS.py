#!/usr/bin/env python3
"""End-to-end synthetic execution of the E.16 adapter plus base validator."""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True


def run(command: list[str], cwd: Path, *, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=cwd,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
        text=True,
    )


def checked(command: list[str], cwd: Path) -> str:
    result = run(command, cwd)
    if result.returncode != 0:
        raise RuntimeError(f"{' '.join(command)} failed:\n{result.stdout}")
    return result.stdout.strip()


def write(path: Path, data: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(data, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate-root", type=Path, required=True)
    args = parser.parse_args()
    source = args.candidate_root.resolve()

    hardening = run(
        [sys.executable, "sandbox/lf_contract_gate_test/STORY_CREATOR_ARCHITECTURE_HARDENING_V1.py"],
        source,
    )
    if hardening.returncode != 0:
        raise SystemExit(f"story creator architecture hardening failed ({hardening.returncode}):\n{hardening.stdout}")
    try:
        hardening_result = json.loads(hardening.stdout.strip().splitlines()[-1])
    except (IndexError, json.JSONDecodeError) as exc:
        raise SystemExit(f"story creator architecture hardening emitted invalid evidence: {exc}")
    if hardening_result.get("result") != "PASS" or hardening_result.get("production_authorized") is not False:
        raise SystemExit(f"story creator architecture hardening evidence invalid: {hardening_result}")
    print("PASS_STORY_CREATOR_ARCHITECTURE_HARDENING=1/1")

    openai_provider = run(
        [sys.executable, "sandbox/lf_contract_gate_test/profile_execution_runtime/run_openai_provider_tests.py"],
        source,
    )
    if openai_provider.returncode != 0:
        raise SystemExit(
            f"OpenAI profile runtime provider regression failed ({openai_provider.returncode}):\n{openai_provider.stdout}"
        )
    if "OPENAI_PROFILE_RUNTIME_TESTS_PASS 10/10" not in openai_provider.stdout:
        raise SystemExit(
            "OpenAI profile runtime provider regression missing PASS marker:\n" + openai_provider.stdout
        )
    print("PASS_OPENAI_PROFILE_RUNTIME_PROVIDER=10/10")

    ekb_binding = run(
        [sys.executable, "sandbox/lf_contract_gate_test/EKB_EXECUTABLE_BINDING_GATE_V1.py"],
        source,
    )
    if ekb_binding.returncode != 0:
        raise SystemExit(f"EKB executable binding gate failed ({ekb_binding.returncode}):\n{ekb_binding.stdout}")
    try:
        ekb_binding_result = json.loads(ekb_binding.stdout.strip().splitlines()[-1])
    except (IndexError, json.JSONDecodeError) as exc:
        raise SystemExit(f"EKB executable binding gate emitted invalid evidence: {exc}")
    if (
        ekb_binding_result.get("result") != "PASS"
        or ekb_binding_result.get("legacy_status_only_blocked") is not True
        or ekb_binding_result.get("executed_blockers_visible") != ["EKB-P0-014", "EKB-P0-020"]
        or ekb_binding_result.get("tampered_receipt_blocked") is not True
        or ekb_binding_result.get("production_authorized") is not False
    ):
        raise SystemExit(f"EKB executable binding evidence invalid: {ekb_binding_result}")
    print("PASS_EKB_EXECUTABLE_BINDING_GATE=3/3")

    causal = run(
        [sys.executable, "sandbox/lf_contract_gate_test/P0_OCR_CAUSAL_REGRESSION_V1.py"],
        source,
    )
    if causal.returncode != 0:
        raise SystemExit(f"P0 OCR causal regression failed ({causal.returncode}):\n{causal.stdout}")
    try:
        causal_result = json.loads(causal.stdout.strip().splitlines()[-1])
    except (IndexError, json.JSONDecodeError) as exc:
        raise SystemExit(f"P0 OCR causal regression emitted invalid evidence: {exc}")
    if (
        causal_result.get("result") != "PASS"
        or causal_result.get("ekb_code") != "EKB-P0-014"
        or causal_result.get("real_geometry_recomposed") is not True
        or causal_result.get("far_gap_remains_separate") is not True
        or causal_result.get("different_baseline_remains_separate") is not True
        or causal_result.get("compact_glyph_remains_separate") is not True
        or causal_result.get("production_authorized") is not False
    ):
        raise SystemExit(f"P0 OCR causal regression evidence invalid: {causal_result}")
    print("PASS_P0_OCR_CAUSAL_REGRESSION=4/4")
    print(f"P0_OCR_READER_SHA256={causal_result.get('reader_file_sha256')}")

    family = run(
        [sys.executable, "sandbox/lf_contract_gate_test/P0_TEXT_GROUP_FAMILY_GENERALIZATION_V1.py"],
        source,
    )
    if family.returncode != 0:
        raise SystemExit(f"P0 text-group family generalization failed ({family.returncode}):\n{family.stdout}")
    try:
        family_result = json.loads(family.stdout.strip().splitlines()[-1])
    except (IndexError, json.JSONDecodeError) as exc:
        raise SystemExit(f"P0 text-group family gate emitted invalid evidence: {exc}")
    if (
        family_result.get("result") != "PASS"
        or family_result.get("family") != "EKB-P0-014_TEXT_GROUPING"
        or family_result.get("architecture") != "GEOMETRIC_COMPATIBILITY_GRAPH_CONNECTED_COMPONENTS"
        or family_result.get("real_topology_invariance") != "600/600"
        or family_result.get("synthetic_family") != "1600/1600"
        or family_result.get("negative_guards") != "600/600"
        or family_result.get("transitive_bridge") != "500/500"
        or family_result.get("screen_literals_in_production_logic") is not False
        or family_result.get("fixed_source_coordinates_in_production_logic") is not False
        or family_result.get("production_authorized") is not False
    ):
        raise SystemExit(f"P0 text-group family evidence invalid: {family_result}")
    print("PASS_P0_TEXT_GROUP_FAMILY_GENERALIZATION=3300/3300")

    workflow = (source / ".github/workflows/lf-contract-check.yml").read_text(encoding="utf-8")
    required_workflow_terms = (
        "actions: read",
        "if: github.event_name == 'pull_request'",
        'E16_HEAD_SHA: ${{ github.event.pull_request.head.sha }}',
        '--head-sha "$E16_HEAD_SHA"',
        "PR93_LOTE_E16_CONTRACT_CHECK_ENTRYPOINT.py",
        "PR93_LOTE_E16_REGRESSION_TESTS.py",
        "PR93_LOTE_E16_INVENTORY_TESTS.py",
        "PR93_LOTE_E16_GITHUB_INVENTORY.py",
        "PR93_LOTE_E16_RATIFICATION_TESTS.py",
        "PR93_LOTE_E16_INTEGRATION_TESTS.py",
    )
    missing = [term for term in required_workflow_terms if term not in workflow]
    if missing:
        raise SystemExit(f"workflow binding incomplete: {missing}")
    forbidden_workflow_terms = (
        '--head-sha "${{ github.event.pull_request.head.sha }}"',
        'python3 scripts/lf_contract_check.py',
    )
    present_forbidden = [term for term in forbidden_workflow_terms if term in workflow]
    if present_forbidden:
        raise SystemExit(f"workflow binding contains forbidden legacy forms: {present_forbidden}")
    if workflow.count('${{ github.event.pull_request.head.sha }}') != 1:
        raise SystemExit("workflow must bind pull_request.head.sha exactly once via env")
    print("PASS_E16_WORKFLOW_BINDING=13/13")

    with tempfile.TemporaryDirectory(prefix="pr93-e16-integration-") as temp:
        root = Path(temp)
        origin = root / "origin.git"
        repo = root / "repo"
        checked(["git", "init", "--bare", str(origin)], root)
        checked(["git", "init", "-b", "main", str(repo)], root)
        checked(["git", "config", "user.name", "E16 Integration"], repo)
        checked(["git", "config", "user.email", "e16@example.invalid"], repo)
        checked(["git", "remote", "add", "origin", str(origin)], repo)

        contract = '''contract_version: "v0.1"\ncontract_id: "LF-GH-GATE-INSTALL-SANDBOX-20260529-001"\nactivo_router: "ACT-0001"\nvista: "public.v_lf_fuente_operativa"\noperation_code: "GITHUB_CONTRACT_GATE_INSTALL_SANDBOX"\nimpacto_productivo: false\nestado_salida_permitido: "GATE_INSTALL_SANDBOX_TESTED"\n'''
        write(repo / "sandbox/lf_contract_gate_test/lf_contract.yml", contract)
        write(repo / "sandbox/lf_contract_gate_test/preexisting.txt", "base\n")
        checked(["git", "add", "-A"], repo)
        checked(["git", "commit", "-m", "base"], repo)
        base = checked(["git", "rev-parse", "HEAD"], repo)
        checked(["git", "push", "-u", "origin", "main"], repo)

        checked(["git", "checkout", "-b", "lf/e16-integration"], repo)
        files = [
            ".github/workflows/lf-contract-check.yml",
            "scripts/lf_contract_check.py",
            "sandbox/lf_contract_gate_test/profile_execution_runtime/profile_runtime_runner.py",
            "sandbox/lf_contract_gate_test/profile_execution_runtime/run_tests.py",
            "sandbox/lf_contract_gate_test/profile_execution_runtime/validate_profile_execution.py",
            "sandbox/lf_contract_gate_test/PR93_LOTE_E16_CONTRACT_CHECK_ENTRYPOINT.py",
            "sandbox/lf_contract_gate_test/PR93_LOTE_E16_GITHUB_INVENTORY.py",
            "sandbox/lf_contract_gate_test/PR93_LOTE_E16_INVENTORY_TESTS.py",
            "sandbox/lf_contract_gate_test/PR93_LOTE_E16_REGRESSION_TESTS.py",
            "sandbox/lf_contract_gate_test/PR93_LOTE_E16_RATIFICATION_TESTS.py",
            "sandbox/lf_contract_gate_test/PR93_LOTE_E16_INTEGRATION_TESTS.py",
            "sandbox/lf_contract_gate_test/PR93_LOTE_E16_GUARDS.md",
        ]
        for relative in files:
            destination = repo / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source / relative, destination)
        checked(["git", "add", "-A"], repo)
        checked(["git", "commit", "-m", "E16 candidate"], repo)
        head = checked(["git", "rev-parse", "HEAD"], repo)
        checked(["git", "push", "-u", "origin", "lf/e16-integration"], repo)

        payload = repo / "push.json"
        payload.write_text(
            json.dumps(
                {
                    "before": base,
                    "after": head,
                    "created": False,
                    "deleted": False,
                    "forced": False,
                    "repository": {"default_branch": "main"},
                }
            ),
            encoding="utf-8",
        )

        common = os.environ.copy()
        common["PYTHONDONTWRITEBYTECODE"] = "1"
        scenarios = [
            (
                "push",
                {
                    "GITHUB_EVENT_NAME": "push",
                    "GITHUB_EVENT_PATH": str(payload),
                    "GITHUB_SHA": head,
                },
            ),
            (
                "pull-request",
                {
                    "GITHUB_EVENT_NAME": "pull_request",
                    "GITHUB_EVENT_PATH": str(payload),
                    "GITHUB_SHA": head,
                    "GITHUB_BASE_REF": "main",
                },
            ),
            (
                "workflow-dispatch",
                {
                    "GITHUB_EVENT_NAME": "workflow_dispatch",
                    "GITHUB_EVENT_PATH": str(payload),
                    "GITHUB_SHA": head,
                },
            ),
        ]
        for index, (name, overrides) in enumerate(scenarios, start=1):
            env = dict(common)
            env.update(overrides)
            result = run([sys.executable, "sandbox/lf_contract_gate_test/PR93_LOTE_E16_CONTRACT_CHECK_ENTRYPOINT.py"], repo, env=env)
            if result.returncode != 0 or "PASS_CONTRACT_VALID" not in result.stdout:
                raise SystemExit(f"{name} failed ({result.returncode}):\n{result.stdout}")
            print(f"PASS_E16_INTEGRATION_{index:02d}={name}")

        print("PASS_E16_CONTRACT_CHECK_INTEGRATION=3/3")
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
