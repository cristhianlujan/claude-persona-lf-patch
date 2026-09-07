#!/usr/bin/env python3
from __future__ import annotations

import csv
import hashlib
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock

import input_governance_migration_parity_compact as subject
import migration_transport_normalization as transport


class InputGovernanceTransportParityTests(unittest.TestCase):
    def test_direct_and_cli_representations_pass(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            migrations = root / "migrations"
            migrations.mkdir()
            v1 = "20260907010101"
            v2 = "20260907010102"
            n1 = "input_governance_direct_v1"
            n2 = "input_governance_cli_v1"
            sql1 = "select 1;\n"
            sql2 = "-- header\n\nselect 2;\n"
            (migrations / f"{v1}_{n1}.sql").write_text(sql1, encoding="utf-8")
            (migrations / f"{v2}_{n2}.sql").write_text(sql2, encoding="utf-8")

            remote = root / "remote.csv"
            with remote.open("w", newline="", encoding="utf-8") as handle:
                writer = csv.writer(handle)
                writer.writerow([v1, n1, "sha256:" + transport.direct_source_hash(sql1)])
                writer.writerow([v2, n2, "sha256:" + transport.cli_statement_storage_hash(sql2)])

            counts = root / "counts.csv"
            counts.write_text(f"{v1},1\n{v2},1\n", encoding="utf-8")

            local_map = subject.load_local(migrations, v1)
            remote_map = subject.load_remote(remote, v1)
            count_map = subject.load_statement_counts_csv(counts)
            digest, comparisons, direct_count, cli_count = subject.evaluate_parity(
                local_map, remote_map, count_map
            )
            self.assertRegex(digest, r"^[0-9a-f]{64}$")
            self.assertEqual(direct_count, 1)
            self.assertEqual(cli_count, 1)
            self.assertEqual(comparisons[v1].representation, "DIRECT_SOURCE")
            self.assertEqual(comparisons[v2].representation, "CLI_STATEMENT_STORAGE")

    def test_statement_boundary_collision_fails_closed(self):
        version = "20260907010103"
        name = "input_governance_boundary_v1"
        valid = "select 1;\nselect 2;"
        mutated = "select 1\nselect 2;"
        self.assertEqual(
            transport.cli_statement_storage_hash(valid),
            transport.cli_statement_storage_hash(mutated),
        )
        local = {
            version: (
                name,
                mutated,
                hashlib.sha256(subject.canonical(mutated)).hexdigest(),
            )
        }
        remote = {
            version: (name, transport.cli_statement_storage_hash(valid))
        }
        with self.assertRaisesRegex(
            SystemExit, "FAIL_INPUT_GOVERNANCE_MIGRATION_CONTENT_PARITY"
        ):
            subject.evaluate_parity(local, remote, {version: 2})

    def test_version_set_mismatch_fails_before_content(self):
        v1 = "20260907010104"
        v2 = "20260907010105"
        local = {v1: ("input_governance_a", "select 1;", transport.direct_source_hash("select 1;"))}
        remote = {v2: ("input_governance_b", transport.direct_source_hash("select 2;"))}
        with self.assertRaisesRegex(
            SystemExit, "FAIL_INPUT_GOVERNANCE_MIGRATION_VERSION_PARITY"
        ):
            subject.evaluate_parity(local, remote, {v2: 1})

    def test_name_mismatch_fails_closed(self):
        version = "20260907010106"
        sql = "select 1;"
        local = {version: ("input_governance_a", sql, transport.direct_source_hash(sql))}
        remote = {version: ("input_governance_b", transport.direct_source_hash(sql))}
        with self.assertRaisesRegex(
            SystemExit, "FAIL_INPUT_GOVERNANCE_MIGRATION_NAME_PARITY"
        ):
            subject.evaluate_parity(local, remote, {version: 1})

    def test_statement_count_set_must_match_remote_versions(self):
        version = "20260907010107"
        sql = "select 1;"
        local = {version: ("input_governance_a", sql, transport.direct_source_hash(sql))}
        remote = {version: ("input_governance_a", transport.direct_source_hash(sql))}
        with self.assertRaisesRegex(
            SystemExit, "FAIL_INPUT_GOVERNANCE_STATEMENT_COUNT_SET"
        ):
            subject.evaluate_parity(local, remote, {})

    def test_live_count_query_requires_explicit_pg_environment(self):
        with mock.patch.dict(os.environ, {}, clear=True):
            with self.assertRaisesRegex(
                SystemExit, "FAIL_INPUT_GOVERNANCE_STATEMENT_COUNT_ENV_MISSING"
            ):
                subject.query_remote_statement_counts(["20260907010108"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
