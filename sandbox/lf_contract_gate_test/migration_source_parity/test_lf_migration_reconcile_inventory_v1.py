#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import pathlib
import subprocess
import tempfile
import unittest

from lf_migration_reconcile_inventory_v1 import build_inventory
from run_migration_source_parity_flow_v1 import CUTOVER, LEGACY_END, LEGACY_START


def canon(sql: str) -> bytes:
    from migration_transport_normalization import canonical
    return canonical(sql)


def sha(sql: str) -> str:
    return hashlib.sha256(canon(sql)).hexdigest()


class ReconcileInventoryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temp.name)
        self.migrations = self.root / "supabase" / "migrations"
        self.migrations.mkdir(parents=True)

    def tearDown(self) -> None:
        self.temp.cleanup()

    def make_export(self, post_rows: list[dict[str, object]]) -> pathlib.Path:
        legacy = {
            "version": LEGACY_START,
            "name": "checkpoint_legacy_fixture",
            "statements": ["select 1;"],
        }
        legacy_sql = "\n--MIGRATION--\n".join((
            LEGACY_START + "\n" + legacy["name"] + "\n" + "\n--STATEMENT--\n".join(legacy["statements"]),
        ))
        legacy_sha = hashlib.sha256(legacy_sql.encode()).hexdigest()
        marker = (
            f"-- LF_MIGRATION_SOURCE_CHECKPOINT_V1 cutover={CUTOVER} "
            f"legacy_start={LEGACY_START} legacy_end={LEGACY_END} "
            f"legacy_count=1 legacy_sha256={legacy_sha}\n"
        )
        checkpoint_source = marker + "select 2;\n"
        checkpoint_version = CUTOVER
        checkpoint_name = "checkpoint_fixture"
        (self.migrations / f"{checkpoint_version}_{checkpoint_name}.sql").write_text(
            checkpoint_source, encoding="utf-8"
        )
        rows = [legacy, {
            "version": checkpoint_version,
            "name": checkpoint_name,
            "statements": [checkpoint_source],
        }, *post_rows]
        export = self.root / "ledger.json"
        export.write_text(json.dumps({"migrations": rows}), encoding="utf-8")
        return export

    def add_git(self, version: str, name: str, sql: str) -> None:
        (self.migrations / f"{version}_{name}.sql").write_text(sql, encoding="utf-8")

    def test_classifies_unique_rename_source_from_ledger_retire_and_unknown(self) -> None:
        self.add_git(LEGACY_START, "checkpoint_legacy_fixture", "select 1;\n")
        (self.migrations / "session_25_contract_fixes.sql").write_text("select 9;\n", encoding="utf-8")
        self.add_git("20261009000001", "alpha_old_v1", "-- source comment\nselect 10;\n")
        self.add_git("20261009000010", "retire_topic_v1", "select 20;\n")
        self.add_git("20261009000020", "unresolved_v1", "select 30;\n")
        self.add_git("20261009000030", "drift_v1", "select 40;\n")
        post_rows = [
            {"version": "20261009000002", "name": "alpha_new_v2", "statements": ["select 10;"]},
            {"version": "20261009000011", "name": "retire_topic_v2_train", "statements": ["select 21;"]},
            {"version": "20261009000021", "name": "ledger_only_v1", "statements": ["select 50;"]},
            {"version": "20261009000030", "name": "drift_v1", "statements": ["select 41;"]},
        ]
        export = self.make_export(post_rows)
        rows, summary = build_inventory(self.root, export)
        categories = [row["category"] for row in rows]
        self.assertIn("A_RENAME", categories)
        self.assertIn("B_SOURCE_FROM_LEDGER", categories)
        self.assertIn("C_RETIRE", categories)
        self.assertIn("D_UNKNOWN", categories)
        self.assertEqual(summary["legacy"]["parity_acceptance"], "PASS")
        self.assertEqual(summary["legacy"]["git_files"], 2)
        self.assertEqual(summary["legacy"]["git_unversioned_grandfathered"], 1)
        self.assertEqual(summary["legacy"]["ledger_rows"], 1)
        self.assertEqual(summary["post_cutover"]["categories"], {
            "A_RENAME": 1,
            "B_SOURCE_FROM_LEDGER": 2,
            "C_RETIRE": 1,
            "D_UNKNOWN": 2,
        })
        c_row = next(row for row in rows if row["category"] == "C_RETIRE")
        self.assertEqual(c_row["replacement_version"], "20261009000011")

    def test_deterministic_rows_and_summary(self) -> None:
        self.add_git("20261009000001", "rename_from_v1", "select 1;\n")
        export = self.make_export([
            {"version": "20261009000002", "name": "rename_to_v2", "statements": ["select 1;"]},
        ])
        first = build_inventory(self.root, export)
        second = build_inventory(self.root, export)
        self.assertEqual(first, second)



    def test_direct_source_hash_matches_and_mismatch_is_unknown(self) -> None:
        version = "20261009000001"
        name = "direct_fixture_v1"
        source = "select 10;\n"
        self.add_git(version, name, source)
        export = self.make_export([
            {"version": "20261009000002", "name": "direct_fixture_v2", "statements": [source]},
        ])
        rows, _ = build_inventory(self.root, export)
        self.assertIn("A_RENAME", [row["category"] for row in rows])

        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            self.root = root
            self.migrations = root / "supabase" / "migrations"
            self.migrations.mkdir(parents=True)
            self.add_git(version, name, source)
            export = self.make_export([
                {"version": version, "name": name, "statements": ["select 11;"]},
            ])
            rows, _ = build_inventory(self.root, export)
            self.assertIn("D_UNKNOWN", [row["category"] for row in rows])

    def test_cli_statement_storage_hash_matches_and_mismatch_is_unknown(self) -> None:
        version = "20261009000001"
        name = "cli_fixture_v1"
        source = "select 10;\nselect 20;\n"
        self.add_git(version, name, source)
        export = self.make_export([
            {"version": "20261009000002", "name": "cli_fixture_v2",
             "statements": ["select 10", "select 20"]},
        ])
        rows, _ = build_inventory(self.root, export)
        self.assertIn("A_RENAME", [row["category"] for row in rows])

        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            self.root = root
            self.migrations = root / "supabase" / "migrations"
            self.migrations.mkdir(parents=True)
            self.add_git(version, name, source)
            export = self.make_export([
                {"version": version, "name": name, "statements": ["select 10", "select 21"]},
            ])
            rows, _ = build_inventory(self.root, export)
            self.assertIn("D_UNKNOWN", [row["category"] for row in rows])

    def test_github_blob_pointer_matches_git_hash_object_and_mismatch_is_unknown(self) -> None:
        version = "20261009000001"
        name = "blob_fixture_v1"
        source = "select 10;\n"
        self.add_git(version, name, source)
        source_path = self.migrations / f"{version}_{name}.sql"
        raw = source_path.read_bytes()
        git_blob_sha = subprocess.run(
            ["git", "hash-object", str(source_path)],
            text=True, capture_output=True, check=True,
        ).stdout.strip()
        blob_sha = hashlib.sha1(f"blob {len(raw)}\0".encode("ascii") + raw).hexdigest()
        self.assertEqual(blob_sha, git_blob_sha)
        pointer = (
            "github://github.com/example/repo/blob/main/"
            f"supabase/migrations/{version}_{name}.sql#blob={blob_sha}"
        )
        export = self.make_export([
            {"version": "20261009000002", "name": "blob_fixture_v2", "statements": [pointer]},
        ])
        rows, _ = build_inventory(self.root, export)
        self.assertIn("A_RENAME", [row["category"] for row in rows])

        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            self.root = root
            self.migrations = root / "supabase" / "migrations"
            self.migrations.mkdir(parents=True)
            self.add_git(version, name, source)
            wrong_raw = b"select 11;\n"
            wrong_sha = hashlib.sha1(
                f"blob {len(wrong_raw)}\0".encode("ascii") + wrong_raw
            ).hexdigest()
            bad_pointer = (
                "github://github.com/example/repo/blob/main/"
                f"supabase/migrations/{version}_{name}.sql#blob={wrong_sha}"
            )
            export = self.make_export([
                {"version": version, "name": name, "statements": [bad_pointer]},
            ])
            rows, _ = build_inventory(self.root, export)
            self.assertIn("D_UNKNOWN", [row["category"] for row in rows])


if __name__ == "__main__":
    unittest.main()
