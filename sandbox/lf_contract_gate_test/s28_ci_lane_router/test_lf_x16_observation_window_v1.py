from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

TARGET = Path(__file__).with_name("lf_x16_observation_window_v1.py")
SPEC = importlib.util.spec_from_file_location("lf_x16_observation_window_v1", TARGET)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(MODULE)


class ObservationWindowFixturesTest(unittest.TestCase):
    def test_thresholds_for_30_prs_with_mixed_migrations_and_no_failures(self):
        pulls = []
        runs = {}
        files = {}
        for number in range(1, 31):
            pulls.append({"number": number, "title": f"fixture {number}", "state": "closed", "merged_at": None})
            runs[str(number)] = [{
                "id": number, "name": "PASE", "head_sha": f"sha-{number}",
                "status": "completed", "conclusion": "success",
                "started_at": "2026-10-14T10:00:00Z", "completed_at": "2026-10-14T10:01:00Z",
            }]
            files[str(number)] = ([f"supabase/migrations/{number}_lf_fixture.sql"] if number <= 5 else [f"sandbox/example/{number}.py"])

        report = MODULE.analyze_window(
            check="PASE", since="2026-10-14T00:00:00Z", pulls=pulls,
            check_runs_by_pr=runs, files_by_pr=files, now="2026-10-15T02:00:00Z",
        )
        self.assertEqual(report["thresholds"]["total_prs"], 30)
        self.assertEqual(report["thresholds"]["with_migration"], 5)
        self.assertEqual(report["thresholds"]["without_migration"], 25)
        self.assertTrue(report["thresholds"]["window_ready"])

    def test_failed_check_merged_without_cause_path_change_is_candidate(self):
        report = MODULE.analyze_window(
            check="pase-merge-gate", since="2026-10-14T00:00:00Z",
            pulls=[{"number": 42, "title": "fixture", "state": "closed", "merged_at": "2026-10-15T00:00:00Z"}],
            check_runs_by_pr={"42": [{
                "id": 9001, "name": "pase-merge-gate", "head_sha": "old", "status": "completed",
                "conclusion": "failure", "started_at": "2026-10-14T12:00:00Z", "completed_at": "2026-10-14T12:05:00Z",
            }]},
            files_by_pr={"42": ["sandbox/example.py"]},
            failure_paths_by_run={"9001": ["sandbox/example.py"]},
            changed_after_failure_by_run={"9001": ["docs/notes.md"]},
            now="2026-10-15T02:00:00Z",
        )
        self.assertEqual([row["pr"] for row in report["false_block_candidates"]], [42])
        self.assertFalse(report["thresholds"]["window_ready"])

    def test_failure_path_repaired_after_failure_is_not_candidate(self):
        report = MODULE.analyze_window(
            check="PASE / MIGRATION_SOURCE_PARITY", since="2026-10-14T00:00:00Z",
            pulls=[{"number": 43, "title": "fixture", "state": "closed", "merged_at": "2026-10-15T00:00:00Z"}],
            check_runs_by_pr={"43": [{
                "id": 9002, "name": "PASE / MIGRATION_SOURCE_PARITY", "status": "completed",
                "conclusion": "failure", "started_at": "2026-10-14T12:00:00Z", "completed_at": "2026-10-14T12:05:00Z",
            }]},
            files_by_pr={"43": ["supabase/migrations/1_lf_fixture.sql"]},
            failure_paths_by_run={"9002": ["supabase/migrations/1_lf_fixture.sql"]},
            changed_after_failure_by_run={"9002": ["supabase/migrations/1_lf_fixture.sql"]},
            now="2026-10-15T02:00:00Z",
        )
        self.assertEqual(report["false_block_candidates"], [])
        self.assertEqual(report["thresholds"]["with_migration"], 1)

    def test_missing_failure_annotations_remain_unresolved(self):
        report = MODULE.analyze_window(
            check="PASE", since="2026-10-14T00:00:00Z",
            pulls=[{"number": 44, "state": "closed", "merged_at": "2026-10-15T00:00:00Z"}],
            check_runs_by_pr={"44": [{
                "id": 9003, "name": "PASE", "status": "completed", "conclusion": "failure",
                "started_at": "2026-10-14T12:00:00Z", "completed_at": "2026-10-14T12:05:00Z",
            }]},
            files_by_pr={"44": []}, now="2026-10-15T02:00:00Z",
        )
        self.assertEqual(report["thresholds"]["unresolved_failure_evidence"], 1)
        self.assertFalse(report["thresholds"]["window_ready"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
