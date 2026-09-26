#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import pathlib
import sys
import unittest

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[2]
TRANSPORT_ROOT = ROOT / "sandbox/lf_contract_gate_test"
if str(TRANSPORT_ROOT) not in sys.path:
    sys.path.insert(0, str(TRANSPORT_ROOT))

import migration_transport_normalization as transport

TARGET = ROOT / "sandbox/lf_contract_gate_test/migration_source_parity/migration_source_parity_core.py"
SPEC = importlib.util.spec_from_file_location("migration_source_parity_core", TARGET)
assert SPEC is not None and SPEC.loader is not None
core = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = core
SPEC.loader.exec_module(core)


class MigrationSourceParityCoreTests(unittest.TestCase):
    def test_direct_source_pass(self) -> None:
        version = "20260926010101"
        name = "lf_parity_core_direct"
        sql = "select 1;\n"
        result = core.evaluate_exact_parity(
            {version: (name, transport.direct_source_hash(sql), sql)},
            {version: (name, transport.direct_source_hash(sql))},
            {version: 1},
        )
        self.assertEqual(result.status, "PASS")
        self.assertEqual(result.code, "PASS_LF_MIGRATION_SOURCE_PARITY")
        self.assertEqual(result.direct_count, 1)
        self.assertEqual(result.cli_statement_storage_count, 0)

    def test_cli_statement_storage_pass(self) -> None:
        version = "20260926010102"
        name = "lf_parity_core_cli"
        sql = "-- source comment\nselect 1;\nselect 2;\n"
        result = core.evaluate_exact_parity(
            {version: (name, transport.direct_source_hash(sql), sql)},
            {version: (name, transport.cli_statement_storage_hash(sql))},
            {version: 2},
        )
        self.assertEqual(result.status, "PASS")
        self.assertEqual(result.direct_count, 0)
        self.assertEqual(result.cli_statement_storage_count, 1)

    def test_version_mismatch_fails_closed(self) -> None:
        with self.assertRaises(core.ParityCoreError) as ctx:
            core.evaluate_exact_parity(
                {"20260926010103": ("lf_local", "0" * 64, "select 1;\n")},
                {},
                {},
            )
        self.assertEqual(ctx.exception.code, "FAIL_LF_MIGRATION_VERSION_PARITY")

    def test_name_mismatch_fails_closed(self) -> None:
        version = "20260926010104"
        sql = "select 1;\n"
        source_sha = transport.direct_source_hash(sql)
        with self.assertRaises(core.ParityCoreError) as ctx:
            core.evaluate_exact_parity(
                {version: ("lf_local", source_sha, sql)},
                {version: ("lf_remote", source_sha)},
                {version: 1},
            )
        self.assertEqual(ctx.exception.code, "FAIL_LF_MIGRATION_NAME_PARITY")

    def test_content_mismatch_fails_closed(self) -> None:
        version = "20260926010105"
        sql = "select 1;\n"
        with self.assertRaises(core.ParityCoreError) as ctx:
            core.evaluate_exact_parity(
                {version: ("lf_content", transport.direct_source_hash(sql), sql)},
                {version: ("lf_content", "f" * 64)},
                {version: 1},
            )
        self.assertEqual(ctx.exception.code, "FAIL_LF_MIGRATION_CONTENT_PARITY")

    def test_core_has_no_ci_or_process_coupling(self) -> None:
        source = TARGET.read_text(encoding="utf-8")
        forbidden = (
            "GITHUB_BASE_REF",
            "GITHUB_EVENT_NAME",
            "GITHUB_REPOSITORY",
            "subprocess",
            "docker",
            ".github/workflows",
            "lf-contract-check",
            "required_controls",
        )
        for token in forbidden:
            self.assertNotIn(token, source)


if __name__ == "__main__":
    unittest.main()
