#!/usr/bin/env python3
"""Canonical visual-quality regression bundle owned by VISUAL_EVIDENCE_GATE.

This module reuses historical P0 visual tests without making E.16 or Contract
Check responsible for provisioning or executing visual-quality regressions.
It does not decide applicability, path admission, exact-head transport, human
decisions, runtime activation, or production authorization.
"""
from __future__ import annotations

import argparse
import importlib.metadata as md
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

sys.dont_write_bytecode = True

REPO_ROOT = Path(__file__).resolve().parents[2]
P0_ROOT = REPO_ROOT / "sandbox/story_creator_p0_visual/v1.1"
P0_CONFIG = P0_ROOT / "evals/p0-visual-quality-runtime-config.json"

VISUAL_COMMANDS: tuple[tuple[str, tuple[str, ...]], ...] = (
    ("ocr-causal-regression", ("sandbox/lf_contract_gate_test/P0_OCR_CAUSAL_REGRESSION_V1.py",)),
    ("text-group-family-generalization", ("sandbox/lf_contract_gate_test/P0_TEXT_GROUP_FAMILY_GENERALIZATION_V1.py",)),
    ("legacy-negative-suite", ("sandbox/story_creator_p0_visual/v1.1/evals/p0_machine_visual_quality_negative_suite.py",)),
    ("human-binding-selftest", ("sandbox/story_creator_p0_visual/v1.1/scripts/validate_p0_human_binding.py", "--self-test")),
    ("legacy-integration-verifier", ("sandbox/story_creator_p0_visual/v1.1/scripts/verify_p0_integration_candidate.py",)),
    ("v2-negative-restore-suite", ("sandbox/story_creator_p0_visual/v1.1/evals/p0_machine_visual_quality_negative_suite_v2.py",)),
    ("v2-runtime-regressions", ("sandbox/story_creator_p0_visual/v1.1/evals/p0_visual_quality_runtime_regression_suite.py",)),
    ("v2-forward-adversarial", ("sandbox/story_creator_p0_visual/v1.1/evals/p0_blind_forward_adversarial_test.py",)),
    ("v3-schema-contracts", ("sandbox/story_creator_p0_visual/v1.1/scripts/validate_p0_v3_schemas.py",)),
    ("v3-negative-restore-regressions", ("sandbox/story_creator_p0_visual/v1.1/evals/p0_visual_fidelity_v3_suite.py",)),
    ("v3-forward-adversarial", ("sandbox/story_creator_p0_visual/v1.1/evals/p0_visual_fidelity_forward_adversarial_v3.py",)),
    ("v3-runtime-hash-inventory", ("sandbox/story_creator_p0_visual/v1.1/scripts/verify_p0_v3_manifest.py",)),
    ("v3-premerge-compliance", ("sandbox/story_creator_p0_visual/v1.1/scripts/audit_p0_handoff_v3_compliance.py", "--phase", "premerge")),
    ("v4-contracts", ("sandbox/story_creator_p0_visual/v1.1/scripts/validate_p0_v4_closed_loop.py",)),
    ("v4-graders", ("sandbox/story_creator_p0_visual/v1.1/evals/p0_visual_discovery_v4_suite.py",)),
    ("v4-grader-coverage", ("sandbox/story_creator_p0_visual/v1.1/evals/p0_visual_grader_coverage_v4.py",)),
    ("v4-closed-loop", ("sandbox/story_creator_p0_visual/v1.1/evals/p0_visual_closed_loop_v4_suite.py",)),
    ("v4-durable-state", ("sandbox/story_creator_p0_visual/v1.1/evals/p0_visual_durable_state_v4.py",)),
    ("v4-known-failure-regressions", ("sandbox/story_creator_p0_visual/v1.1/evals/p0_visual_known_failure_regression_v4.py",)),
    ("v4-forward-adversarial", ("sandbox/story_creator_p0_visual/v1.1/evals/p0_visual_forward_adversarial_v4.py",)),
    ("v4-independent-omission-sweep", ("sandbox/story_creator_p0_visual/v1.1/evals/p0_independent_omission_sweep_v4.py",)),
    ("v4-reader-producer-contract", ("sandbox/story_creator_p0_visual/v1.1/evals/p0_reader_producer_contract_v4.py",)),
    ("v4-grader-producer-field-audit", ("sandbox/story_creator_p0_visual/v1.1/evals/p0_grader_producer_field_audit_v4.py",)),
    ("p0-5-blind-annotation-contract", ("sandbox/lf_contract_gate_test/P0_5_BLIND_ANNOTATION_CONTRACT_V1.py",)),
)


def _command(label: str, relative_args: tuple[str, ...]) -> list[str]:
    if not relative_args:
        raise SystemExit(f"FAIL_VISUAL_BUNDLE_EMPTY_COMMAND:{label}")
    script = (REPO_ROOT / relative_args[0]).resolve()
    try:
        script.relative_to(REPO_ROOT.resolve())
    except ValueError as exc:
        raise SystemExit(f"FAIL_VISUAL_BUNDLE_PATH_ESCAPE:{label}") from exc
    if not script.is_file():
        raise SystemExit(f"FAIL_VISUAL_BUNDLE_SCRIPT_MISSING:{label}:{relative_args[0]}")
    return [sys.executable, str(script), *relative_args[1:]]


def self_test() -> None:
    labels = [label for label, _ in VISUAL_COMMANDS]
    if len(labels) != len(set(labels)):
        raise SystemExit("FAIL_VISUAL_BUNDLE_DUPLICATE_LABEL")
    for label, args in VISUAL_COMMANDS:
        _command(label, args)
    if not P0_CONFIG.is_file():
        raise SystemExit("FAIL_VISUAL_BUNDLE_CONFIG_MISSING")
    print(f"PASS_P0_VISUAL_QUALITY_REGRESSION_BUNDLE_SELFTEST={len(VISUAL_COMMANDS)}/{len(VISUAL_COMMANDS)}")


def attest_visual_dependencies() -> None:
    if os.environ.get("P0_CI_ENGINEERING_REGRESSION") is not None:
        raise SystemExit("FAIL_P0_CI_ENGINEERING_REGRESSION_OVERRIDE_FORBIDDEN")
    if os.environ.get("CI") != "true":
        print("PASS_P0_VISUAL_TEST_DEPENDENCIES=SKIPPED_NON_CI_READ_ONLY_ATTESTATION")
        return
    config = json.loads(P0_CONFIG.read_text(encoding="utf-8"))
    if config.get("calibration", {}).get("status") != "GOVERNED_OPERATIONAL_CALIBRATION":
        raise SystemExit("FAIL_P0_VISUAL_GOVERNED_CALIBRATION_STATUS")
    try:
        tesseract = subprocess.run(
            ["tesseract", "--version"], text=True, capture_output=True, check=True
        ).stdout.splitlines()[0].split()[1]
    except Exception:
        tesseract = "UNAVAILABLE"
    actual: dict[str, str] = {}
    for package in ("Pillow", "numpy", "opencv-python-headless"):
        try:
            actual[package] = md.version(package)
        except md.PackageNotFoundError:
            actual[package] = "UNAVAILABLE"
    actual["tesseract"] = tesseract
    expected = config.get("dependencies", {})
    mismatches = {
        key: {"expected": value, "actual": actual.get(key)}
        for key, value in expected.items()
        if actual.get(key) != value
    }
    if mismatches:
        raise SystemExit(
            "FAIL_P0_VISUAL_GOVERNED_DEPENDENCY_MISMATCH="
            + json.dumps(mismatches, sort_keys=True)
        )
    probe = subprocess.run(
        ["tesseract", "--list-langs"], text=True, capture_output=True, check=False
    )
    langs = set(probe.stdout.split()) if probe.returncode == 0 else set()
    if "spa" not in langs:
        raise SystemExit("FAIL_P0_VISUAL_GOVERNED_LANGUAGE_MISSING=spa")
    print("PASS_P0_VISUAL_TEST_DEPENDENCIES=GOVERNED_EXACT " + json.dumps(actual, sort_keys=True))


def run_bundle() -> None:
    self_test()
    attest_visual_dependencies()
    evidence_dir = REPO_ROOT / ".audit-output/creating-integral-user-stories/p0-v3"
    evidence_dir.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    if env.get("P0_CI_ENGINEERING_REGRESSION") is not None:
        raise SystemExit("FAIL_P0_CI_ENGINEERING_REGRESSION_OVERRIDE_FORBIDDEN")

    for label, relative_args in VISUAL_COMMANDS:
        command = _command(label, relative_args)
        completed = subprocess.run(
            command,
            cwd=REPO_ROOT,
            text=True,
            capture_output=True,
            check=False,
            env=env,
        )
        output = (completed.stdout or "") + (("\nSTDERR:\n" + completed.stderr) if completed.stderr else "")
        (evidence_dir / f"{label}.log").write_text(output, encoding="utf-8")
        if completed.stdout:
            print(completed.stdout.rstrip())
        if completed.returncode != 0:
            if completed.stderr:
                print(completed.stderr.rstrip(), file=sys.stderr)
            raise SystemExit(
                f"P0_VISUAL_QUALITY_REGRESSION_FAILED[{label}]: {' '.join(command)}"
            )

    snapshot_dir = evidence_dir / "runtime-snapshot"
    snapshot_dir.mkdir(parents=True, exist_ok=True)
    for relative in (
        "scripts/p0_visual_fidelity_v3.py",
        "scripts/run_p0_visual_fidelity_v3_private.py",
        "evals/p0-visual-fidelity-runtime-config-v3.json",
        "manifest.visual-fidelity-v3.json",
    ):
        shutil.copy2(P0_ROOT / relative, snapshot_dir / Path(relative).name)
    print("PASS_P0_V3_RUNTIME_SNAPSHOT=4_PUBLIC_REPO_FILES")
    print(f"PASS_P0_VISUAL_QUALITY_REGRESSION_BUNDLE={len(VISUAL_COMMANDS)}/{len(VISUAL_COMMANDS)}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
    else:
        run_bundle()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
