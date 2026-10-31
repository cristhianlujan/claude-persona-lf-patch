"""Entrypoint for existing LF Edge Operation R17 Tests workflow.

Runs the actual step70 and native/feedback Router-only regressions from this PR.
No network, credentials, model invocation or Supabase writes are performed.
"""
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
SOURCES = (
    "tests/test_lf_profile_step70_consume_v3.py",
    "tests/test_lf_router_only_semantic_applicability.py",
)


def load_tests(loader, tests, pattern):
    suite = unittest.TestSuite()
    for index, relative_path in enumerate(SOURCES):
        source = ROOT / relative_path
        if not source.is_file():
            raise RuntimeError("ROUTER_ONLY_REGRESSION_SOURCE_MISSING:" + relative_path)
        spec = importlib.util.spec_from_file_location("router_only_bound_test_" + str(index), source)
        if spec is None or spec.loader is None:
            raise RuntimeError("ROUTER_ONLY_REGRESSION_IMPORT_INVALID:" + relative_path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        suite.addTests(loader.loadTestsFromModule(module))
    return suite
