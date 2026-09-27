#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parents[2]
GATE_PATH = HERE / "visual_evidence_gate_v1.py"
BUNDLE_PATH = REPO_ROOT / "sandbox/lf_contract_gate_test/P0_VISUAL_QUALITY_REGRESSION_BUNDLE_V1.py"


def load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise AssertionError(f"LOAD_FAILED:{path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def main() -> int:
    gate = load("visual_evidence_gate_coverage_subject", GATE_PATH)
    bundle = load("p0_visual_quality_bundle_subject", BUNDLE_PATH)

    helpers = dict(gate.CANONICAL_HELPERS)
    expected_bundle = "sandbox/lf_contract_gate_test/P0_VISUAL_QUALITY_REGRESSION_BUNDLE_V1.py"
    assert helpers.get("LEGACY_P0_VISUAL_QUALITY_REGRESSION_BUNDLE") == expected_bundle
    assert gate.EXPECTED_HELPER_COUNT == len(gate.CANONICAL_HELPERS) == 5

    command_paths = {args[0] for _, args in bundle.VISUAL_COMMANDS}
    assert "sandbox/lf_contract_gate_test/P0_OCR_CAUSAL_REGRESSION_V1.py" in command_paths
    assert "sandbox/lf_contract_gate_test/P0_TEXT_GROUP_FAMILY_GENERALIZATION_V1.py" in command_paths
    assert "sandbox/lf_contract_gate_test/P0_5_BLIND_ANNOTATION_CONTRACT_V1.py" in command_paths
    assert len(bundle.VISUAL_COMMANDS) == 24

    forbidden = {
        "sandbox/lf_contract_gate_test/PR93_LOTE_E16_INTEGRATION_TESTS.py",
        "sandbox/lf_contract_gate_test/PR93_P0_RUNTIME_SCOPE_TESTS.py",
        "scripts/lf_contract_check.py",
    }
    assert command_paths.isdisjoint(forbidden)

    bundle.self_test()
    gate.self_test(REPO_ROOT)
    print("PASS_VISUAL_EVIDENCE_GATE_LEGACY_P0_COVERAGE=24/24")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
