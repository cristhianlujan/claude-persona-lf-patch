#!/usr/bin/env python3
"""M10.12 / NEG_CASCADE bounded test: NO DB WRITE, no physical DROP.

This verifies contract semantics for an exact candidate statement. It is a
checkpoint test artifact, not a deployed migration guard or release receipt.
Only a current signed REMOVE_READY allowlist may authorize a later batch.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import unittest
from dataclasses import dataclass
from pathlib import Path

CONTRACT_PATH = (Path(__file__).resolve().parents[2] /
                 "transversal_assets/asset_retirement_governance/asset_retirement_contract_v1.json")
# A deliberately narrow subset: one exact signature per proposed migration.
# Reject every unknown SQL form rather than trying to parse arbitrary SQL.
DROP_RE = re.compile(
    r"\A\s*DROP\s+FUNCTION\s+(?:IF\s+EXISTS\s+)?"
    r"(?P<signature>programacion\.[a-z_][a-z_0-9]*\("
    r"[a-z_][a-z_0-9]*(?:\s*,\s*[a-z_][a-z_0-9]*)*\))\s*;\s*\Z",
    re.IGNORECASE,
)


@dataclass(frozen=True)
class Observation:
    remove_ready: frozenset[str]
    dependent_functions: frozenset[str]
    sql_callers: frozenset[str]
    external_surfaces_verified: bool


def check_contract() -> None:
    contract = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
    if contract.get("asset_code") != "ASSET_RETIREMENT_GOVERNANCE":
        raise RuntimeError("WRONG_RETIREMENT_CONTRACT")
    if "DELETE_BEFORE_ZERO_CONSUMERS" not in contract["prohibitions"]:
        raise RuntimeError("ZERO_CONSUMER_GUARD_MISSING")
    if contract["closure_invariants"].get("ZERO_OPERATIONAL_CONSUMERS") is not True:
        raise RuntimeError("REQUIRED_CONSUMER_PROOF_MISSING")


def admit(sql: str, observed: Observation) -> tuple[bool, str]:
    """Conservative *test oracle*; not an actual DB execution entrypoint."""
    if not observed.external_surfaces_verified:
        return False, "EXTERNAL_CURRENTNESS_UNKNOWN"
    if not observed.remove_ready:
        return False, "NO_REMOVE_READY"
    # Fullmatch rejects CASCADE, multiple statements, comments with
    # extra commands, function overload ambiguity, and unauthorized SQL.
    match = DROP_RE.fullmatch(sql)
    if not match:
        return False, "NOT_EXACT_NO_CASCADE_SINGLE_DROP"
    signature = re.sub(r"\s+", "", match.group("signature").lower())
    if signature not in observed.remove_ready:
        return False, "NOT_ON_EXACT_REMOVE_READY_ALLOWLIST"
    if signature in observed.dependent_functions:
        return False, "LIVE_PG_DEPEND"
    if signature in observed.sql_callers:
        return False, "LIVE_SQL_CALLER"
    return True, "ADMISSIBLE_CANDIDATE_TEST_ONLY"


SIG = "programacion.fn_ig_fixture(integer)"
SQL = "DROP FUNCTION programacion.fn_ig_fixture(integer);"


class NegativeCascadeTest(unittest.TestCase):
    def setUp(self) -> None:
        check_contract()
        self.clean = Observation(frozenset({SIG}), frozenset(), frozenset(), True)

    def test_positive_exact_no_cascade_fixture(self) -> None:
        self.assertEqual(admit(SQL, self.clean), (True, "ADMISSIBLE_CANDIDATE_TEST_ONLY"))

    def test_zero_live_remove_ready_rejects(self) -> None:
        obs = Observation(frozenset(), frozenset(), frozenset(), True)
        self.assertEqual(admit(SQL, obs), (False, "NO_REMOVE_READY"))

    def test_explicit_cascade_rejects(self) -> None:
        self.assertEqual(admit(SQL.replace(";", " CASCADE;"), self.clean)[0], False)

    def test_live_pg_depend_rejects(self) -> None:
        obs = Observation(self.clean.remove_ready, frozenset({SIG}), frozenset(), True)
        self.assertEqual(admit(SQL, obs), (False, "LIVE_PG_DEPEND"))

    def test_live_sql_caller_even_if_pg_depend_empty_rejects(self) -> None:
        obs = Observation(self.clean.remove_ready, frozenset(), frozenset({SIG}), True)
        self.assertEqual(admit(SQL, obs), (False, "LIVE_SQL_CALLER"))

    def test_non_allowlisted_target_rejects(self) -> None:
        self.assertEqual(
            admit("DROP FUNCTION programacion.fn_not_approved(integer);", self.clean)[0], False
        )

    def test_unknown_external_surfaces_rejects(self) -> None:
        obs = Observation(self.clean.remove_ready, frozenset(), frozenset(), False)
        self.assertEqual(admit(SQL, obs), (False, "EXTERNAL_CURRENTNESS_UNKNOWN"))

    def test_multi_statement_injection_rejects(self) -> None:
        self.assertEqual(admit(SQL + " DROP TABLE public.lf_activos CASCADE;", self.clean)[0], False)

    def test_drop_not_run_as_database_side_effect(self) -> None:
        # This test does not invoke psql, a DB driver, or a write-capable connector.
        import inspect
        body = inspect.getsource(admit)
        self.assertNotIn("execute(", body)
        self.assertNotIn("subprocess", body)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--observed-current-json", default=None)
    opts = parser.parse_args()
    result = unittest.TextTestRunner(verbosity=1).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(NegativeCascadeTest)
    )
    if not result.wasSuccessful():
        return 1
    if opts.observed_current_json:
        value = json.loads(opts.observed_current_json)
        observation = Observation(
            frozenset(value["remove_ready"]),
            frozenset(value["dependent_functions"]),
            frozenset(value["sql_callers"]),
            bool(value["external_surfaces_verified"]),
        )
        decision = admit(value["sql"], observation)
        print(json.dumps({
            "case": "OBSERVED_READ_ONLY_SOURCE",
            "admitted": decision[0], "code": decision[1],
            "physical_operation_executed": False,
            "qualifies_runtime": False,
        }, sort_keys=True))
        if decision[0]:
            return 2  # live zero-target test must never grant a deletion
    print(json.dumps({
        "unit": "M10.12", "checkpoint": "NEG_CASCADE",
        "fixture_tests_run": result.testsRun, "fixture_tests_passed": result.testsRun,
        "real_db_drop_tested": False, "runtime_release_qualified": False,
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
