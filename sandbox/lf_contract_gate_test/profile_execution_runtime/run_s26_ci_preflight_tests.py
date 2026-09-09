#!/usr/bin/env python3
from __future__ import annotations

import json
import tempfile
from copy import deepcopy
from pathlib import Path

from s26_ci_preflight import PreflightError, validate_manifest

R = "S26"
BASE = "sandbox/lf_contract_gate_test/profile_execution_runtime"


def write(root: Path, rel: str, content: str = "x") -> None:
    path = root / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def fixture(root: Path) -> dict:
    schema = f"{BASE}/s26_ci_preflight_manifest.schema.json"
    manifest_path = f"{BASE}/s26_ci_preflight_manifest_v1.json"
    validator_a = f"{BASE}/validate_profile_execution.py"
    validator_b = f"{BASE}/semantic_obligation_manifest.py"
    preflight = f"{BASE}/s26_ci_preflight.py"
    tests = f"{BASE}/run_s26_ci_preflight_tests.py"
    workflow = ".github/workflows/story-agent-evidence-verifier.yml"
    write(root, "CLAUDE.md", "authority")
    write(root, f"{BASE}/README.md", "runtime authority")
    write(root, validator_a)
    write(root, validator_b)
    write(root, preflight)
    write(root, tests)
    write(root, schema, json.dumps({"$schema": "https://json-schema.org/draft/2020-12/schema", "type": "object"}))
    workflow_text = """jobs:\n  semantic-mini-judge-smoke:\n    steps:\n      - name: S26 cheap deterministic preflight\n      - name: Build pinned llama.cpp server from source\n      - name: Download and verify pinned semantic judge model\n  run-zero-cost-profile-runtime:\n    steps:\n      - name: S26 cheap deterministic preflight\n      - name: Build pinned llama.cpp from source\n      - name: Download and verify pinned multimodal model\n  run-zero-cost-profile-batch:\n    steps:\n      - name: S26 cheap deterministic preflight\n      - name: Build pinned llama.cpp runtime bundle on cache miss\n      - name: Download pinned model on cache miss\n"""
    write(root, workflow, workflow_text)
    manifest = {
        "schema": "S26_CI_PREFLIGHT_MANIFEST_V1",
        "run_scope": R,
        "required_files": ["CLAUDE.md", f"{BASE}/README.md", workflow, manifest_path],
        "required_scripts": [preflight, tests],
        "required_validators": [validator_a, validator_b],
        "schemas": [{"path": schema, "run_id": R}],
        "authority_sources": [
            {"authority_type": "CI_CONTRACT", "source_ref": "CLAUDE.md", "run_id": R},
            {"authority_type": "RUNTIME_CONTRACT", "source_ref": f"{BASE}/README.md", "run_id": R},
        ],
        "bindings": [
            {"binding_id": "PROFILE_EXECUTION_VALIDATOR", "target_ref": validator_a, "run_id": R},
            {"binding_id": "SEMANTIC_MANIFEST_VALIDATOR", "target_ref": validator_b, "run_id": R},
        ],
        "inputs": [{"input_id": "CANONICAL_PREFLIGHT_MANIFEST", "path": manifest_path, "run_id": R}],
        "workflow_guards": [
            {"workflow_path": workflow, "job": "semantic-mini-judge-smoke", "preflight_marker": "S26 cheap deterministic preflight", "heavy_markers": ["Build pinned llama.cpp server from source", "Download and verify pinned semantic judge model"], "run_id": R},
            {"workflow_path": workflow, "job": "run-zero-cost-profile-runtime", "preflight_marker": "S26 cheap deterministic preflight", "heavy_markers": ["Build pinned llama.cpp from source", "Download and verify pinned multimodal model"], "run_id": R},
            {"workflow_path": workflow, "job": "run-zero-cost-profile-batch", "preflight_marker": "S26 cheap deterministic preflight", "heavy_markers": ["Build pinned llama.cpp runtime bundle on cache miss", "Download pinned model on cache miss"], "run_id": R},
        ],
    }
    write(root, manifest_path, json.dumps(manifest))
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
        print("PASS valid_manifest")

        case = deepcopy(valid); case.pop("bindings")
        expect_block("manifest_incomplete", case, root, "MANIFEST_INCOMPLETE")

        case = deepcopy(valid); case["required_files"].append("missing/file.txt")
        expect_block("missing_file_reference", case, root, "REQUIRED_FILE_MISSING")

        case = deepcopy(valid); case["authority_sources"] = case["authority_sources"][:1]
        expect_block("source_authority_absent", case, root, "SOURCE_AUTHORITY_MISSING")

        case = deepcopy(valid); case["bindings"] = [case["bindings"][0]]
        expect_block("required_binding_absent", case, root, "REQUIRED_BINDING_MISSING")

        bad_schema = f"{BASE}/bad.schema.json"; write(root, bad_schema, "{not-json")
        case = deepcopy(valid); case["schemas"] = [{"path": bad_schema, "run_id": R}]
        expect_block("schema_invalid", case, root, "SCHEMA_INVALID_JSON")

        case = deepcopy(valid); case["required_scripts"].append(f"{BASE}/not_materialized.py")
        expect_block("required_script_not_materialized", case, root, "REQUIRED_FILE_MISSING")

        case = deepcopy(valid); case["bindings"][0]["run_id"] = "S25"
        expect_block("cross_run_reference", case, root, "CROSS_RUN_REFERENCE")

        case = deepcopy(valid); case["inputs"][0]["path"] = f"{BASE}/missing_input.json"
        expect_block("declared_input_not_in_bundle", case, root, "REQUIRED_FILE_MISSING")

        print("PASS_S26_CI_PREFLIGHT_TESTS negative_cases=8/8 valid_cases=1/1")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
