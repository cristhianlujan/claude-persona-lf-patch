#!/usr/bin/env python3
"""Intrinsic validation baseline for the LF contract-check capability.

This harness executes only the intrinsic contract validator (`validate_contract`)
from the frozen pre-restructure revision. It does not execute routing,
applicability planning, Migration Parity, packs, DB regression, runtime, P0,
assurance, or other carrier controls.
"""
from __future__ import annotations

import argparse
import ast
import contextlib
import hashlib
import importlib.util
import io
import json
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

BASELINE_COMMIT = "1f179dfb76741e3c96f921cf64c07533dd082bad"
EXPECTED_FILE = Path(__file__).with_name("contract_check_intrinsic_validation_expected_v1.json")
SOURCE_PATHS = (
    ".github/workflows/lf-contract-check.yml",
    "scripts/lf_contract_check.py",
    "sandbox/lf_contract_gate_test/lf_contract.yml",
)


def run(argv: list[str], *, cwd: Path | None = None, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(argv, cwd=cwd, text=True, capture_output=True, check=check)


def git_text(*args: str) -> str:
    return run(["git", *args]).stdout.strip()


def git_bytes(*args: str) -> bytes:
    return subprocess.check_output(["git", *args])


def assert_frozen_main() -> str:
    run(["git", "cat-file", "-e", f"{BASELINE_COMMIT}^{{commit}}"])
    for ref in ("refs/remotes/origin/main", "refs/heads/main"):
        completed = run(["git", "rev-parse", "--verify", ref], check=False)
        if completed.returncode != 0:
            continue
        ancestor = run(["git", "merge-base", "--is-ancestor", BASELINE_COMMIT, ref], check=False)
        if ancestor.returncode != 0:
            resolved = completed.stdout.strip()
            raise SystemExit(
                f"FAIL_CONTRACT_BASELINE_NOT_ANCESTOR_OF_CURRENT_MAIN:{ref}:{resolved}"
            )
        return ref
    raise SystemExit("FAIL_CONTRACT_BASELINE_MAIN_REF_UNRESOLVABLE")


def source_identity() -> dict[str, Any]:
    rows: dict[str, Any] = {}
    for path in SOURCE_PATHS:
        content = git_bytes("show", f"{BASELINE_COMMIT}:{path}")
        rows[path] = {
            "git_blob": git_text("rev-parse", f"{BASELINE_COMMIT}:{path}"),
            "sha256": hashlib.sha256(content).hexdigest(),
        }
    return rows


def load_module(path: Path):
    spec = importlib.util.spec_from_file_location("lf_contract_check_intrinsic_validation", path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"FAIL_CONTRACT_BASELINE_MODULE_LOAD:{path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def invoke_validate_contract(module, contract_path: Path) -> dict[str, Any]:
    original = module.CONTRACT_PATH
    stdout = io.StringIO()
    returned: str | None = None
    exit_code = 0
    module.CONTRACT_PATH = contract_path
    try:
        with contextlib.redirect_stdout(stdout):
            try:
                returned = module.validate_contract()
            except SystemExit as exc:
                exit_code = int(exc.code or 0)
    finally:
        module.CONTRACT_PATH = original

    lines = [line.strip() for line in stdout.getvalue().splitlines() if line.strip()]
    failure_code = None
    if lines and ":" in lines[0]:
        failure_code = lines[0].split(":", 1)[0]
    return {
        "exit_code": exit_code,
        "failure_code": failure_code,
        "returned_sha256": (
            hashlib.sha256(returned.encode("utf-8")).hexdigest()
            if returned is not None
            else None
        ),
    }


def script_wiring(script_text: str) -> dict[str, Any]:
    tree = ast.parse(script_text)
    main_fn = next(
        (node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == "main"),
        None,
    )
    if main_fn is None:
        raise SystemExit("FAIL_CONTRACT_BASELINE_MAIN_FUNCTION_MISSING")

    first_call = None
    for stmt in main_fn.body:
        if not isinstance(stmt, ast.Expr) or not isinstance(stmt.value, ast.Call):
            continue
        func = stmt.value.func
        if isinstance(func, ast.Name):
            first_call = func.id
        elif isinstance(func, ast.Attribute):
            first_call = func.attr
        break

    if first_call != "validate_contract":
        raise SystemExit(f"FAIL_CONTRACT_BASELINE_MAIN_FIRST_CALL:{first_call}")
    return {"script_main_first_call": first_call}


def normalize(value: dict[str, Any]) -> dict[str, Any]:
    value = json.loads(json.dumps(value))
    value.pop("demonstration_sha256", None)
    value.pop("resolved_main_ref", None)
    return value


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--output",
        default=(
            ".lf_gate_diagnostics/lf_contract_check/intrinsic_validation/"
            "contract_check_intrinsic_validation_baseline_v1.json"
        ),
    )
    parser.add_argument("--expected", default=str(EXPECTED_FILE))
    args = parser.parse_args()

    resolved_main_ref = assert_frozen_main()
    identities = source_identity()

    with tempfile.TemporaryDirectory(prefix="lf-contract-intrinsic-validation-") as td:
        worktree = Path(td) / "baseline"
        run(["git", "worktree", "add", "--detach", str(worktree), BASELINE_COMMIT])
        try:
            validator_path = worktree / "scripts/lf_contract_check.py"
            contract_path = worktree / "sandbox/lf_contract_gate_test/lf_contract.yml"
            workflow_path = worktree / ".github/workflows/lf-contract-check.yml"

            validator = load_module(validator_path)
            contract_text = contract_path.read_text(encoding="utf-8")
            script_text = validator_path.read_text(encoding="utf-8")
            workflow_text = workflow_path.read_text(encoding="utf-8")

            positive = invoke_validate_contract(validator, contract_path)
            if positive["exit_code"] != 0 or positive["failure_code"] is not None:
                raise SystemExit("FAIL_CONTRACT_BASELINE_POSITIVE_CONTRACT")
            if positive["returned_sha256"] != identities["sandbox/lf_contract_gate_test/lf_contract.yml"]["sha256"]:
                raise SystemExit("FAIL_CONTRACT_BASELINE_POSITIVE_CONTENT_BINDING")

            missing_path = worktree / "sandbox/lf_contract_gate_test/does-not-exist.yml"
            missing = invoke_validate_contract(validator, missing_path)
            if missing["exit_code"] != 1 or missing["failure_code"] != "FAIL_CONTRACT_MISSING":
                raise SystemExit("FAIL_CONTRACT_BASELINE_MISSING_CONTRACT_NEGATIVE")

            invalid_failures = 0
            for index, term in enumerate(validator.REQUIRED_TERMS):
                invalid_path = Path(td) / f"invalid-{index}.yml"
                invalid_path.write_text(contract_text.replace(term, "", 1), encoding="utf-8")
                result = invoke_validate_contract(validator, invalid_path)
                if result["exit_code"] != 1 or result["failure_code"] != "FAIL_CONTRACT_INVALID":
                    raise SystemExit(f"FAIL_CONTRACT_BASELINE_REQUIRED_TERM_NEGATIVE:{index}")
                invalid_failures += 1

            wiring = script_wiring(script_text)
            workflow_references_validator = "scripts/lf_contract_check.py" in workflow_text
            if not workflow_references_validator:
                raise SystemExit("FAIL_CONTRACT_BASELINE_WORKFLOW_VALIDATOR_REFERENCE_MISSING")
        finally:
            run(["git", "worktree", "remove", "--force", str(worktree)], check=False)

    demonstration: dict[str, Any] = {
        "schema_version": "lf-contract-check-intrinsic-validation-baseline/v1",
        "capability": "LF_CONTRACT_CORE",
        "baseline_commit": BASELINE_COMMIT,
        "resolved_main_ref": resolved_main_ref,
        "source_identity": identities,
        "wiring": {
            **wiring,
            "workflow_references_validator_path": workflow_references_validator,
        },
        "contract_behavior": {
            "positive": {
                "exit_code": positive["exit_code"],
                "returned_sha256": positive["returned_sha256"],
                "required_terms_count": len(validator.REQUIRED_TERMS),
            },
            "negative_missing_contract": {
                "exit_code": missing["exit_code"],
                "failure_code": missing["failure_code"],
            },
            "negative_each_required_term_removed": {
                "cases": invalid_failures,
                "all_fail_closed": True,
                "failure_code": "FAIL_CONTRACT_INVALID",
            },
        },
        "scope": {
            "executes_only": ["validate_contract"],
            "excluded_external_execution": [
                "router",
                "applicability_plan",
                "migration_parity",
                "validate_lf_packs",
                "db_regression",
                "profile_runtime",
                "p0",
                "assurance",
                "supabase_control_plane",
            ],
        },
    }

    raw = json.dumps(demonstration, sort_keys=True, separators=(",", ":")).encode("utf-8")
    demonstration["demonstration_sha256"] = hashlib.sha256(raw).hexdigest()

    expected_path = Path(args.expected)
    if not expected_path.exists():
        raise SystemExit(f"FAIL_CONTRACT_BASELINE_EXPECTED_MISSING:{expected_path}")
    expected = json.loads(expected_path.read_text(encoding="utf-8"))
    if normalize(expected) != normalize(demonstration):
        raise SystemExit("FAIL_CONTRACT_BASELINE_REPLAY_DIFFERS_FROM_FROZEN_EXPECTED")

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(demonstration, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    print(
        "CONTRACT_INTRINSIC_BASELINE_POSITIVE "
        f"required_terms={len(validator.REQUIRED_TERMS)} "
        f"returned_sha256={positive['returned_sha256']}"
    )
    print("CONTRACT_INTRINSIC_BASELINE_NEGATIVE missing_contract=FAIL_CONTRACT_MISSING")
    print(
        "CONTRACT_INTRINSIC_BASELINE_NEGATIVE "
        f"required_term_removals={invalid_failures}/{len(validator.REQUIRED_TERMS)} "
        "result=FAIL_CONTRACT_INVALID"
    )
    print("CONTRACT_INTRINSIC_BASELINE_SCOPE executes_only=validate_contract external_controls=0")
    print(f"CONTRACT_INTRINSIC_BASELINE_DEMONSTRATION_SHA256={demonstration['demonstration_sha256']}")
    print(f"CONTRACT_INTRINSIC_BASELINE_EVIDENCE={output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
