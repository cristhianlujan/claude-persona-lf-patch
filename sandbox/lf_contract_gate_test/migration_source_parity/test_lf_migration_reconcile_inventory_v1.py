#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import pathlib
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
        self.assertEqual(summary["legacy"]["git_files"], 1)
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


if __name__ == "__main__":
    unittest.main()
