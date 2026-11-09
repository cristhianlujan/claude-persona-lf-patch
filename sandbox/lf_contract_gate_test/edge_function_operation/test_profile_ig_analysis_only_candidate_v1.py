"""Run source-first IG read-only candidate safeguards in existing R17 PR CI.
No new workflow, credential, DB connection, or mutating tool.
"""
import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
TARGET = ROOT / "sandbox/lf_contract_gate_test/profile_execution_runtime/test_profile_ig_analysis_only_contract_v1.py"


def load_tests(loader, tests, pattern):
    if not TARGET.is_file():
        raise RuntimeError("PROFILE_IG_ANALYSIS_CONTRACT_TEST_NOT_FOUND")
    spec = importlib.util.spec_from_file_location("profile_ig_analysis_only_contract_v1", TARGET)
    if spec is None or spec.loader is None:
        raise RuntimeError("PROFILE_IG_ANALYSIS_CONTRACT_LOADER_INVALID")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    tests.addTests(loader.loadTestsFromModule(module))
    return tests
