from __future__ import annotations

import copy
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))

from lf_ci_lane_router import classify
from lf_shared_ci_control_ownership import (
    REGISTRY_PATH,
    SharedRegistryValidationError,
    compile_shared_registry,
    load_shared_registry,
)


class SharedOwnershipRegistryRegressionTest(unittest.TestCase):
    def setUp(self):
        load_shared_registry.cache_clear()

    def test_real_main_registry_loads_and_keeps_guard_controls(self):
        # Regression guard: load the checked-in registry, never a fixture copy.
        registry = load_shared_registry()
        self.assertTrue(REGISTRY_PATH.is_file())
        profiles = {entry.path: entry for entry in registry.controls}
        expected_controls = ("CI_ROUTER_SELFTEST", "MIGRATION_ROUTE_GUARD")
        for path in (
            ".github/workflows/lf-migration-name-classification.yml",
            ".github/workflows/lf-migration-route-guard.yml",
        ):
            self.assertEqual(profiles[path].required_controls, expected_controls)

    def test_classify_expected_docs_migration_workflow_and_guard_code(self):
        cases = {
            "docs": (
                "docs/pase/x16/SHADOW_RESULTS.md",
                "DEEP_SHARED_KNOWN", (), False, False,
            ),
            "migration": (
                "supabase/migrations/20261015000000_lf_example_v1.sql",
                "SPECIALIZED_REQUIRED", ("MIGRATION_SOURCE_PARITY",), True, False,
            ),
            "guard workflow": (
                ".github/workflows/lf-migration-route-guard.yml",
                "CI_ROUTER_SELFTEST_ONLY",
                ("CI_ROUTER_SELFTEST", "MIGRATION_ROUTE_GUARD"), False, True,
            ),
            "guard code": (
                "sandbox/lf_contract_gate_test/migration_route_guard/lf_migration_route_guard.py",
                "DEEP_SHARED_KNOWN", ("MIGRATION_ROUTE_GUARD",), False, False,
            ),
        }
        for label, (path, mode, controls, migration, deep_shared) in cases.items():
            with self.subTest(label=label):
                result = classify([path])
                self.assertEqual(result.mode, mode, result)
                self.assertEqual(result.required_controls, controls, result)
                self.assertEqual(result.migration_parity_required, migration, result)
                self.assertEqual(result.deep_shared, deep_shared, result)

    def test_specialized_profile_cannot_expand_to_extra_control(self):
        data = json.loads(REGISTRY_PATH.read_text(encoding="utf-8"))
        changed = copy.deepcopy(data)
        route_workflow = next(
            item for item in changed["controls"]
            if item["control_id"] == "LF_MIGRATION_ROUTE_GUARD_WORKFLOW"
        )
        route_workflow["required_controls"].append("MIGRATION_SOURCE_PARITY")
        with self.assertRaises(SharedRegistryValidationError) as raised:
            compile_shared_registry(changed)
        self.assertEqual(raised.exception.code, "FAIL_LF_SHARED_REGISTRY_PROFILE")

    def test_specialized_profile_cannot_be_reused_on_another_path(self):
        data = json.loads(REGISTRY_PATH.read_text(encoding="utf-8"))
        changed = copy.deepcopy(data)
        route_workflow = next(
            item for item in changed["controls"]
            if item["control_id"] == "LF_MIGRATION_ROUTE_GUARD_WORKFLOW"
        )
        route_workflow["path"] = ".github/workflows/unrelated.yml"
        with self.assertRaises(SharedRegistryValidationError) as raised:
            compile_shared_registry(changed)
        self.assertEqual(raised.exception.code, "FAIL_LF_SHARED_REGISTRY_PROFILE")

    def test_generic_v1_entry_rejects_migration_route_guard(self):
        data = json.loads(REGISTRY_PATH.read_text(encoding="utf-8"))
        changed = copy.deepcopy(data)
        ordinary = next(
            item for item in changed["controls"]
            if item["control_id"] == "LF_CONTRACT_CHECK_WORKFLOW"
        )
        ordinary["required_controls"] = ["CI_ROUTER_SELFTEST", "MIGRATION_ROUTE_GUARD"]
        with self.assertRaises(SharedRegistryValidationError) as raised:
            compile_shared_registry(changed)
        self.assertEqual(raised.exception.code, "FAIL_LF_SHARED_REGISTRY_PROFILE")


if __name__ == "__main__":
    unittest.main(verbosity=2)
