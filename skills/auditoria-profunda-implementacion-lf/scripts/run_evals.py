#!/usr/bin/env python3
"""Execute the suite and save observed results, dynamically counted, locally."""
import argparse
import datetime as dt
import io
import json
import sys
import unittest
from pathlib import Path

PACK = Path(__file__).resolve().parents[1]


class RecordedResult(unittest.TextTestResult):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.observations = []

    def addSuccess(self, test):
        super().addSuccess(test)
        self.observations.append({"test": test.id(), "result": "PASS"})

    def addFailure(self, test, err):
        super().addFailure(test, err)
        self.observations.append({"test": test.id(), "result": "FAIL"})

    def addError(self, test, err):
        super().addError(test, err)
        self.observations.append({"test": test.id(), "result": "ERROR"})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    stream = io.StringIO()
    start = dt.datetime.now(dt.timezone.utc).isoformat()
    suite = unittest.defaultTestLoader.discover(str(PACK / "evals"), pattern="test_*.py")
    result = unittest.TextTestRunner(stream=stream, verbosity=2, resultclass=RecordedResult).run(suite)
    from test_acceptance import sql_measurement, freshness_measurement
    observed = {"executed_at": start, "scope": "LOCAL_TESTS_NOT_GOVERNANCE_PASS",
        "command": "python skills/auditoria-profunda-implementacion-lf/scripts/run_evals.py --output <path>",
        "tests_run": result.testsRun, "failures": len(result.failures), "errors": len(result.errors),
        "skipped": len(result.skipped), "successful": result.wasSuccessful(),
        "observations": result.observations, "log": stream.getvalue(),
        "sql_fixture_measurement": sql_measurement(), "freshness_fixture_measurement": freshness_measurement(),
        "query_count_fixture": {"before": 5, "after": 1,
            "evidence_test": "test_A05_repeated_queries_snapshot_and_currentness_negatives"},
        "promotion_authorized": False}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(observed, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
    print(json.dumps({k: observed[k] for k in ("tests_run", "failures", "errors", "skipped", "successful")}))
    return not result.wasSuccessful()


if __name__ == "__main__":
    raise SystemExit(main())
