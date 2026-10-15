from __future__ import annotations

import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch


HERE = Path(__file__).resolve().parent
TARGET = HERE / "run_migration_source_parity_focal_v1.py"
SPEC = importlib.util.spec_from_file_location("x16_focal_canary", TARGET)
assert SPEC and SPEC.loader
FOCAL = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = FOCAL
SPEC.loader.exec_module(FOCAL)


def git(repo: Path, *args: str) -> str:
    return subprocess.run(
        ["git", "-C", str(repo), *args], check=True, text=True,
        capture_output=True,
    ).stdout.strip()


class X16ChangesetScopeCanary(unittest.TestCase):
    def test_historical_66_paths_and_17_ledger_rows_stay_outside_changeset(self):
        # A self-contained Git fixture; no connection to the shared database.
        repo = Path(tempfile.mkdtemp(prefix="x16-historical-debt-"))
        git(repo, "init", "-q")
        git(repo, "config", "user.email", "ci@example.invalid")
        git(repo, "config", "user.name", "CI fixture")
        migrations = repo / "supabase/migrations"
        migrations.mkdir(parents=True)
        for index in range(66):
            version = f"20260101{index:06d}"
            (migrations / f"{version}_lf_historical_{index:02d}.sql").write_text(
                "select 1;\n", encoding="utf-8"
            )
        # These 17 historical ledger identities are intentionally external to
        # the Git diff. The focal carrier accepts no whole-ledger input.
        historical_ledger_rows = [
            {"version": f"20260101{index:06d}", "name": f"lf_historical_{index:02d}"}
            for index in range(17)
        ]
        self.assertEqual(len(historical_ledger_rows), 17)
        git(repo, "add", ".")
        git(repo, "commit", "-m", "fixture historical state")
        base = git(repo, "rev-parse", "HEAD")

        feature_path = migrations / "20261015000001_lf_focal_canary.sql"
        feature_path.write_text("select 2;\n", encoding="utf-8")
        git(repo, "add", ".")
        git(repo, "commit", "-m", "fixture changeset")
        head = git(repo, "rev-parse", "HEAD")

        def fixture_git(*args: str) -> SimpleNamespace:
            output = git(repo, *args)
            return SimpleNamespace(stdout=output)

        with patch.object(FOCAL.FULL, "_git", side_effect=fixture_git):
            changed = FOCAL._changed_migration_paths(base, head)
        self.assertEqual(changed, ["supabase/migrations/20261015000001_lf_focal_canary.sql"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
