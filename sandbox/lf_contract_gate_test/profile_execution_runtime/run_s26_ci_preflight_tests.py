#!/usr/bin/env python3
from __future__ import annotations

import json
import tempfile
from copy import deepcopy
from pathlib import Path

from s26_ci_preflight import (
    BASE,
    MANIFEST_PATH,
    MANIFEST_SCHEMA_PATH,
    PREFLIGHT_COMMAND,
    PreflightError,
    validate_manifest,
)

R = "S26"


def write(root: Path, rel: str, content: str = "x") -> None:
    path = root / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def test_schema() -> dict:
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "type": "object",
        "required": [
            "schema", "run_scope", "required_files", "required_scripts", "required_validators",
            "schemas", "authority_sources", "bindings", "inputs", "workflow_guards",
        ],
        "properties": {
            "schema": {"const": "S26_CI_PREFLIGHT_MANIFEST_V1"},
            "run_scope": {"const": "S26"},
            "required_files": {"type": "array", "minItems": 1, "items": {"type": "string", "minLength": 1}},
            "required_scripts": {"type": "array", "minItems": 1, "items": {"type": "string", "minLength": 1}},
            "required_validators": {"type": "array", "minItems": 1, "items": {"type": "string", "minLength": 1}},
            "schemas": {"type": "array", "minItems": 1},
            "authority_sources": {"type": "array", "minItems": 2},
            "bindings": {"type": "array", "minItems": 2},
            "inputs": {"type": "array", "minItems": 1},
            "workflow_guards": {"type": "array", "minItems": 1},
        },
        "additionalProperties": False,
    }


def fixture(root: Path) -> dict:
    validator_a = f"{BASE}/validate_profile_execution.py"
    validator_b = f"{BASE}/semantic_obligation_manifest.py"
    preflight = f"{BASE}/s26_ci_preflight.py"
    tests = f"{BASE}/run_s26_ci_preflight_tests.py"
    run_tests = f"{BASE}/run_tests.py"
    mini_tests = f"{BASE}/run_semantic_mini_judge_tests.py"
    opt_tests = f"{BASE}/run_profile_runtime_optimization_tests.py"
    workflow = ".github/workflows/story-agent-evidence-verifier.yml"

    write(root, "CLAUDE.md", "authority")
    write(root, f"{BASE}/README.md", "runtime authority")
    write(root, validator_a, "def validate_receipt(value):\n    return ['RECEIPT_NOT_OBJECT']\n")
    write(
        root,
        validator_b,
        "class ObligationManifestError(ValueError):\n    pass\n\n"
        "def validate_obligation_manifest(value):\n    raise ObligationManifestError('MANIFEST_SCHEMA_INVALID')\n",
    )
    for script in (preflight, tests, run_tests, mini_tests, opt_tests):
        write(root, script, "x\n")
    write(root, MANIFEST_SCHEMA_PATH, json.dumps(test_schema()))

    workflow_text = f"""jobs:
  semantic-mini-judge-smoke:
    steps:
      - name: S26 cheap deterministic preflight
        run: |
          set -euo pipefail
          {PREFLIGHT_COMMAND}
      - name: Build pinned llama.cpp server from source
        run: |
          echo build
      - name: Download and verify pinned semantic judge model
        run: |
          echo model
  run-zero-cost-profile-runtime:
    steps:
      - name: S26 cheap deterministic preflight
        run: |
          set -euo pipefail
          {PREFLIGHT_COMMAND}
      - name: Build pinned llama.cpp from source
        run: |
          echo build
      - name: Download and verify pinned multimodal model
        run: |
          echo model
  run-zero-cost-profile-batch:
    steps:
      - name: S26 cheap deterministic preflight
        run: |
          set -euo pipefail
          {PREFLIGHT_COMMAND}
      - name: Build pinned llama.cpp runtime bundle on cache miss
        run: |
          echo build
      - name: Download pinned model on cache miss
        run: |
          echo model
"""
    write(root, workflow, workflow_text)

    manifest = {
        "schema": "S26_CI_PREFLIGHT_MANIFEST_V1",
        "run_scope": R,
        "required_files": ["CLAUDE.md", f"{BASE}/README.md", workflow, MANIFEST_PATH],
        "required_scripts": [preflight, tests, run_tests, mini_tests, opt_tests],
        "required_validators": [validator_a, validator_b],
        "schemas": [{"path": MANIFEST_SCHEMA_PATH, "schema_role": "PREFLIGHT_MANIFEST", "run_id": R}],
        "authority_sources": [
            {"authority_type": "CI_CONTRACT", "source_ref": "CLAUDE.md", "run_id": R},
            {"authority_type": "RUNTIME_CONTRACT", "source_ref": f"{BASE}/README.md", "run_id": R},
        ],
        "bindings": [
            {
                "binding_id": "PROFILE_EXECUTION_VALIDATOR",
                "target_ref": validator_a,
                "callable": "validate_receipt",
                "probe_mode": "RETURNS_NONEMPTY_ERROR_LIST",
                "run_id": R,
            },
            {
                "binding_id": "SEMANTIC_MANIFEST_VALIDATOR",
                "target_ref": validator_b,
                "callable": "validate_obligation_manifest",
                "probe_mode": "RAISES_EXPECTED_ERROR",
                "expected_error": "MANIFEST_SCHEMA_INVALID",
                "run_id": R,
            },
        ],
        "inputs": [{"input_id": "CANONICAL_PREFLIGHT_MANIFEST", "path": MANIFEST_PATH, "run_id": R}],
        "workflow_guards": [
            {
                "workflow_path": workflow,
                "job": "semantic-mini-judge-smoke",
                "preflight_marker": "S26 cheap deterministic preflight",
                "heavy_markers": [
                    "Build pinned llama.cpp server from source",
                    "Download and verify pinned semantic judge model",
                ],
                "run_id": R,
            },
            {
                "workflow_path": workflow,
                "job": "run-zero-cost-profile-runtime",
                "preflight_marker": "S26 cheap deterministic preflight",
                "heavy_markers": [
                    "Build pinned llama.cpp from source",
                    "Download and verify pinned multimodal model",
                ],
                "run_id": R,
            },
            {
                "workflow_path": workflow,
                "job": "run-zero-cost-profile-batch",
                "preflight_marker": "S26 cheap deterministic preflight",
                "heavy_markers": [
                    "Build pinned llama.cpp runtime bundle on cache miss",
                    "Download pinned model on cache miss",
                ],
                "run_id": R,
            },
        ],
    }
    write(root, MANIFEST_PATH, json.dumps(manifest))
    return manifest


def expect_block(name: str, manifest: dict, root: Path, expected: str) -> None:
    try:
        validate_manifest(root, manifest)
    except PreflightError as exc:
        if expected not in str(exc):
            raise AssertionError(f"{name}: expected {expected}, got {exc}") from exc
        print(f"PASS negative {name}: {exc}")
        return
    raise AssertionError(f"{name}: expected block")


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        valid = fixture(root)
        result = validate_manifest(root, valid)
        assert result["status"] == "PASS_S26_CHEAP_PREFLIGHT"
        assert result["manifest_schema_applied"] is True
        assert result["validator_bindings_executed"] == 2
        assert result["canonical_authorities_pinned"] is True
        assert result["canonical_workflow_guard_set_pinned"] is True
        print("PASS valid_manifest schema_applied=true bindings_executed=2 authorities_pinned=true guards_pinned=true")

        # Required 8 handoff negatives.
        case = deepcopy(valid); case.pop("bindings")
        expect_block("manifest_incomplete", case, root, "MANIFEST_INCOMPLETE")

        case = deepcopy(valid); case["required_files"].append("missing/file.txt")
        expect_block("missing_file_reference", case, root, "REQUIRED_FILE_MISSING")

        case = deepcopy(valid); case["authority_sources"] = case["authority_sources"][:1]
        expect_block("source_authority_absent", case, root, "MANIFEST_SCHEMA_VALIDATION_FAILED")

        case = deepcopy(valid); case["bindings"] = [case["bindings"][0]]
        expect_block("required_binding_absent", case, root, "MANIFEST_SCHEMA_VALIDATION_FAILED")

        schema_path = root / MANIFEST_SCHEMA_PATH
        good_schema = schema_path.read_text(encoding="utf-8")
        schema_path.write_text("{not-json", encoding="utf-8")
        expect_block("schema_invalid", deepcopy(valid), root, "SCHEMA_INVALID_JSON")
        schema_path.write_text(good_schema, encoding="utf-8")

        missing_script = f"{BASE}/run_tests.py"
        script_path = root / missing_script
        script_text = script_path.read_text(encoding="utf-8")
        script_path.unlink()
        expect_block("required_script_not_materialized", deepcopy(valid), root, "REQUIRED_FILE_MISSING")
        write(root, missing_script, script_text)

        case = deepcopy(valid); case["bindings"][0]["run_id"] = "S25"
        expect_block("cross_run_reference", case, root, "CROSS_RUN_REFERENCE")

        manifest_file = root / MANIFEST_PATH
        manifest_text = manifest_file.read_text(encoding="utf-8")
        manifest_file.unlink()
        expect_block("declared_input_not_in_bundle", deepcopy(valid), root, "REQUIRED_FILE_MISSING")
        write(root, MANIFEST_PATH, manifest_text)

        # Audit regressions: schema/use/bypass integrity.
        case = deepcopy(valid); case["unexpected"] = True
        expect_block("manifest_schema_actually_applied", case, root, "MANIFEST_SCHEMA_VALIDATION_FAILED")

        case = deepcopy(valid); case["bindings"][0]["callable"] = "missing_callable"
        expect_block("validator_binding_must_execute", case, root, "VALIDATOR_BINDING_MISMATCH")

        workflow = root / ".github/workflows/story-agent-evidence-verifier.yml"
        original = workflow.read_text(encoding="utf-8")
        spoofed = original.replace(
            "      - name: S26 cheap deterministic preflight\n        run: |\n          set -euo pipefail\n          " + PREFLIGHT_COMMAND,
            "      # - name: S26 cheap deterministic preflight\n      # run: |\n      #   " + PREFLIGHT_COMMAND,
            1,
        )
        workflow.write_text(spoofed, encoding="utf-8")
        expect_block("workflow_text_spoof_not_executable", valid, root, "PREFLIGHT_EXECUTABLE_STEP_MISSING")
        workflow.write_text(original, encoding="utf-8")

        write(root, "fake-authority.md", "fake")
        case = deepcopy(valid); case["authority_sources"][0]["source_ref"] = "fake-authority.md"
        expect_block("authority_ref_cannot_be_rebound", case, root, "SOURCE_AUTHORITY_REF_MISMATCH")

        case = deepcopy(valid); case["bindings"][0]["target_ref"] = f"{BASE}/semantic_obligation_manifest.py"
        expect_block("validator_target_cannot_be_rebound", case, root, "VALIDATOR_BINDING_MISMATCH")

        case = deepcopy(valid); case["workflow_guards"] = case["workflow_guards"][:1]
        expect_block("workflow_guard_set_cannot_be_weakened", case, root, "WORKFLOW_GUARD_SET_INVALID")

        case = deepcopy(valid); case["required_scripts"].remove(f"{BASE}/run_tests.py")
        expect_block("required_script_declaration_cannot_be_removed", case, root, "REQUIRED_SCRIPT_DECLARATION_MISSING")

        injected = original.replace(
            "      - name: S26 cheap deterministic preflight",
            "      - name: Download surprise weights\n        run: |\n          curl https://example.invalid/model.gguf -o /tmp/model.gguf\n"
            "      - name: S26 cheap deterministic preflight",
            1,
        )
        workflow.write_text(injected, encoding="utf-8")
        expect_block("unlisted_heavy_step_before_preflight", valid, root, "HEAVY_STAGE_BEFORE_PREFLIGHT")
        workflow.write_text(original, encoding="utf-8")

        print("PASS_S26_CI_PREFLIGHT_TESTS required_negative_cases=8/8 audit_regressions=8/8 valid_cases=1/1")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
