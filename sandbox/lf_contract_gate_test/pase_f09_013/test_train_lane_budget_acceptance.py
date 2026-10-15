from __future__ import annotations

import pathlib
import sys
import unittest
from datetime import datetime, timedelta, timezone

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import train_lane_budget_acceptance as budget


BASE = datetime(2026, 10, 15, 0, 0, tzinfo=timezone.utc)


def freeze_event():
    frozen = {}
    for step, values in {
        "preflight": (2869, 4, 2855, "NOT_APPLICABLE", "NOT_APPLICABLE"),
        "patch": ("INFORMATIVE", 13, "NOT_APPLICABLE", 1, 720),
        "verify": (1659, 2, 1659, "NOT_APPLICABLE", "NOT_APPLICABLE"),
    }.items():
        duration, qcount, qduration, tcount, tduration = values
        frozen[step] = {
            "duration_ms_cap": duration,
            "queries_count_cap": qcount,
            "queries_duration_ms_cap": qduration,
            "transport_count_cap": tcount,
            "transport_duration_ms_cap": tduration,
        }
    frozen["total"] = {"duration_ms_cap": "INFORMATIVE"}
    return {
        "id": 21100,
        "created_at": BASE - timedelta(minutes=31),
        "payload": {
            "acceptance_declared": False,
            "unit_state_transition": False,
            "budget_revision_code": budget.EVENT_CODE,
            "occurred_at": "2026-10-14T23:09:31.769234Z",
            "frozen_caps": frozen,
            "acceptance_rule": {"sample_count": 10, "min_cold_samples": 2},
        },
    }


def execution(execution_id, started, gap_after_previous, patch_duration=1000,
              target="20261015000000_lf_fixture_v1", status="COMPLETED"):
    started_at = started
    completed_at = started_at + timedelta(seconds=20)
    return {
        "execution_id": execution_id,
        "status": status,
        "target_code": target,
        "created_at": started_at,
        "started_at": started_at,
        "completed_at": completed_at,
        "updated_at": completed_at,
        "_patch_duration": patch_duration,
    }


def steps_for(run):
    result = []
    for step in budget.STEP_NAMES:
        duration = run["_patch_duration"] if step == "patch" else 500
        envelope = {
            "duration_ms": duration,
            "queries": {"count": 2, "duration_ms": min(duration - 1, 1000)},
            "transport": {
                "count": 1 if step == "patch" else budget.NOT_OBSERVED,
                "duration_ms": 10 if step == "patch" else budget.NOT_OBSERVED,
            },
        }
        result.append({
            "execution_id": run["execution_id"],
            "step_id": step,
            "evidence_payload": {"pase_f09_015_telemetry_v1": envelope},
        })
    return result


class TrainLaneBudgetAcceptanceTest(unittest.TestCase):
    def test_cold_hot_and_intermediate_excluded_with_inside_outside_and_edge(self):
        prior_time = BASE - timedelta(minutes=60)
        prior = execution("EXEC-DB-TRAIN-PR1-20261014230000-R1", prior_time, None,
                          target="20261014230000_lf_probe_v1")
        prior["status"] = "COMPLETED"
        prior["completed_at"] = prior_time

        cold = execution("EXEC-DB-TRAIN-PR2-20261015003000-R2",
                         prior["completed_at"] + timedelta(minutes=30), None, patch_duration=10199)
        hot = execution("EXEC-DB-TRAIN-PR3-20261015005020-R3",
                        cold["completed_at"] + timedelta(minutes=10),
                        None, patch_duration=10201)
        intermediate = execution("EXEC-DB-TRAIN-PR4-20261015010540-R4",
                                 hot["completed_at"] + timedelta(minutes=15),
                                 None, patch_duration=10200)
        rows = [prior, cold, hot, intermediate]
        evidence = [row for run in (cold, hot, intermediate) for row in steps_for(run)]

        report = budget.analyze(freeze_event(), rows, evidence)
        samples = {row["execution_id"]: row for row in report["evaluated_executions"]}

        self.assertEqual(samples[cold["execution_id"]]["classification"], "cold")
        self.assertTrue(samples[cold["execution_id"]]["valid_sample"])
        self.assertEqual(samples[hot["execution_id"]]["classification"], "hot")
        self.assertTrue(samples[hot["execution_id"]]["valid_sample"])
        self.assertEqual(samples[intermediate["execution_id"]]["classification"], "excluded")
        self.assertFalse(samples[intermediate["execution_id"]]["valid_sample"])
        self.assertEqual(report["valid_sample_count"], 2)
        self.assertEqual(report["valid_cold_sample_count"], 1)
        self.assertEqual(report["valid_hot_sample_count"], 1)
        self.assertEqual(samples[hot["execution_id"]]["exceeded_caps"], [])
        self.assertEqual(samples[intermediate["execution_id"]]["exceeded_caps"], [])
        self.assertEqual(report["percentiles_nearest_rank"]["cold"]["patch.duration_ms"]["p99"], 10199)
        self.assertEqual(report["percentiles_nearest_rank"]["hot"]["patch.duration_ms"]["p99"], 10201)

    def test_patch_duration_is_informative_and_exact_ten_minutes_is_hot(self):
        prior_time = BASE - timedelta(minutes=60)
        prior = execution("EXEC-DB-TRAIN-PR1-20261014230000-R1", prior_time, None)
        prior["completed_at"] = prior_time
        sample = execution("EXEC-DB-TRAIN-PR2-20261015001020-R2",
                           prior_time + timedelta(minutes=10), None,
                           patch_duration=10200)
        event = freeze_event()
        event["created_at"] = prior_time + timedelta(minutes=5)
        report = budget.analyze(event, [prior, sample], steps_for(sample))
        item = report["evaluated_executions"][0]
        self.assertEqual(item["classification"], "hot")
        self.assertEqual(item["idle_gap_minutes"], 10)
        self.assertTrue(item["valid_sample"])
        self.assertEqual(item["exceeded_caps"], [])

    def test_not_observed_cap_has_no_limit_and_is_never_coerced_to_zero(self):
        event = freeze_event()
        prior_time = BASE - timedelta(minutes=60)
        run = execution("EXEC-DB-TRAIN-PR2-20261015003000-R2",
                        prior_time + timedelta(minutes=30), None)
        prior = execution("EXEC-DB-TRAIN-PR1-20261014230000-R1", prior_time, None)
        prior["completed_at"] = prior_time
        rows = steps_for(run)
        for row in rows:
            if row["step_id"] != "patch":
                envelope = row["evidence_payload"]["pase_f09_015_telemetry_v1"]
                envelope["transport"] = {
                    "count": budget.NOT_OBSERVED,
                    "duration_ms": budget.NOT_OBSERVED,
                }
        report = budget.analyze(event, [prior, run], rows)
        item = report["evaluated_executions"][0]
        self.assertTrue(item["valid_sample"])
        self.assertEqual(item["metrics"]["preflight.transport_count"], budget.NOT_OBSERVED)
        self.assertNotIn("preflight.transport_count", item["exceeded_caps"])
        self.assertIn("preflight.transport_count", report["percentiles_nearest_rank"]["cold"])
        self.assertEqual(
            report["percentiles_nearest_rank"]["cold"]["preflight.transport_count"]["p99"],
            budget.NOT_OBSERVED,
        )

    def test_c3_targets_and_noncompleted_runs_are_not_candidates(self):
        prior_time = BASE - timedelta(minutes=60)
        prior = execution("EXEC-DB-TRAIN-PR1-20261014230000-R1", prior_time, None)
        prior["completed_at"] = prior_time
        c3 = execution("EXEC-DB-TRAIN-PR2-20261015003000-R2",
                       prior_time + timedelta(minutes=30), None,
                       target="20261015003000_lf_pase_f09_015_c3_probe_v1")
        failed = execution("EXEC-DB-TRAIN-PR3-20261015005020-R3",
                            c3["completed_at"] + timedelta(minutes=10), None,
                            status="BLOCKED")
        report = budget.analyze(freeze_event(), [prior, c3, failed], [])
        self.assertEqual(report["evaluated_executions"], [])

    def test_cutoff_comes_from_event_and_excludes_exact_fractional_boundary(self):
        event = freeze_event()
        cutoff = datetime.fromisoformat(event["payload"]["occurred_at"].replace("Z", "+00:00"))
        event["created_at"] = cutoff
        prior_time = cutoff - timedelta(hours=1)
        prior = execution("EXEC-DB-TRAIN-PR1-20261014220000-R1", prior_time, None)
        prior["completed_at"] = prior_time
        at_cutoff = execution("EXEC-DB-TRAIN-PR2-20261014230931-R2", cutoff, None)
        after_cutoff = execution(
            "EXEC-DB-TRAIN-PR3-20261014231451-R3",
            cutoff + timedelta(minutes=5, seconds=20, microseconds=1), None,
        )
        report = budget.analyze(
            event,
            [prior, at_cutoff, after_cutoff],
            steps_for(after_cutoff),
        )
        self.assertEqual(
            report["cutoff_created_at_exclusive"], "2026-10-14T23:09:31.769234Z"
        )
        self.assertEqual(
            [row["execution_id"] for row in report["evaluated_executions"]],
            [after_cutoff["execution_id"]],
        )
        self.assertEqual(report["evaluated_executions"][0]["classification"], "hot")

    def test_wrong_freeze_event_fails_closed(self):
        event = freeze_event()
        event["payload"]["budget_revision_code"] = "OLD_EVENT"
        with self.assertRaisesRegex(ValueError, "RECALIBRATION_EVENT_CODE_MISMATCH"):
            budget.analyze(event, [], [])

    def test_heavy_patch_passes_when_train_overhead_stays_within_caps(self):
        prior_time = BASE - timedelta(minutes=60)
        prior = execution("EXEC-DB-TRAIN-PR1-20261014230000-R1", prior_time, None)
        prior["completed_at"] = prior_time
        heavy = execution(
            "EXEC-DB-TRAIN-PR2-20261015003000-R2",
            prior_time + timedelta(minutes=30), None, patch_duration=76000,
        )
        rows = steps_for(heavy)
        patch = next(row for row in rows if row["step_id"] == "patch")
        envelope = patch["evidence_payload"]["pase_f09_015_telemetry_v1"]
        envelope["queries"]["duration_ms"] = 75500
        report = budget.analyze(freeze_event(), [prior, heavy], rows)
        item = report["evaluated_executions"][0]
        self.assertTrue(item["valid_sample"])
        self.assertEqual(item["metrics"]["patch.duration_ms"], 76000)
        self.assertEqual(item["metrics"]["patch.queries_duration_ms"], 75500)
        self.assertEqual(item["exceeded_caps"], [])

    def test_preflight_over_cap_still_fails(self):
        prior_time = BASE - timedelta(minutes=60)
        prior = execution("EXEC-DB-TRAIN-PR1-20261014230000-R1", prior_time, None)
        prior["completed_at"] = prior_time
        sample = execution(
            "EXEC-DB-TRAIN-PR2-20261015003000-R2",
            prior_time + timedelta(minutes=30), None,
        )
        rows = steps_for(sample)
        preflight = next(row for row in rows if row["step_id"] == "preflight")
        preflight["evidence_payload"]["pase_f09_015_telemetry_v1"]["duration_ms"] = 2870
        report = budget.analyze(freeze_event(), [prior, sample], rows)
        item = report["evaluated_executions"][0]
        self.assertEqual(
            item["exceeded_caps"],
            [{"metric": "preflight.duration_ms", "observed": 2870, "cap": 2869}],
        )
        self.assertTrue(any(
            finding["kind"] == "BUDGET_EXCEEDED"
            and finding["metric"] == "preflight.duration_ms"
            for finding in report["findings"]
        ))


if __name__ == "__main__":
    unittest.main()
