"""Synthetic API-boundary tests; no Supabase or business case executions."""
import unittest
from copy import deepcopy
from profile_runtime_api.source_investigation_preparation import (
    PreparationContractError, PREPARATION_SQL, prepare_source_investigation,
)


def good():
    return {
        "schema_version": "LF_SOURCE_INVESTIGATION_PREPARATION_V1",
        "next_action": "SEARCH_OTHER_CANDIDATES_OR_GOVERN_BINDING",
        "planner_stop_is_local_only": True,
        "discovery": {"discovery_state": "CANDIDATES_FOUND"},
        "binding_checks": [{
            "source_ref": "db://example.relation",
            "binding_decision": "BLOCK_BINDING_ABSENT_OR_AMBIGUOUS",
            "access_authorized": False,
            "rows_accessed": False,
        }],
        "binding_checks_count": 1,
        "d3": {"next_action": "SEARCH_OTHER_CANDIDATES_OR_GOVERN_BINDING",
               "final_business_answer_allowed": False},
        "business_data_read_authorized": False,
        "rows_accessed": False,
        "runtime_dispatched": False,
        "final_business_answer_allowed": False,
        "effects_executed": False,
        "global_discovery_exhausted": False,
    }


class Cursor:
    def __init__(self, value=None, error=None):
        self.value = good() if value is None else value
        self.error = error
        self.calls = []

    def execute(self, sql, args):
        self.calls.append((sql, args))
        if self.error:
            raise self.error

    def fetchone(self):
        return (self.value,)


class AdapterTests(unittest.TestCase):
    def assert_block(self, payload=None, code="LF_D4_UNAUTHORIZED_EFFECT_IN_PREPARATION"):
        cur = Cursor(value=payload)
        with self.assertRaises(PreparationContractError) as cm:
            prepare_source_investigation(cur, "metadata discovery")
        self.assertEqual(str(cm.exception), code)

    def test_happy_path_stays_metadata_only(self):
        cur = Cursor()
        got = prepare_source_investigation(cur, "  source question  ", 2)
        self.assertEqual(got, good())
        self.assertEqual(cur.calls, [(PREPARATION_SQL, ("source question", 2))])
        self.assertNotIn("lf_ops", PREPARATION_SQL)

    def test_sql_injection_stays_parameter(self):
        cur = Cursor()
        query = "search source'); drop table impossible;--"
        prepare_source_investigation(cur, query)
        self.assertEqual(cur.calls[0], (PREPARATION_SQL, (query, 12)))
        self.assertNotIn("drop table", PREPARATION_SQL)

    def test_invalid_objective(self):
        for value in (None, "", "  ", "hi", "x" * 1001):
            with self.subTest(value=repr(value)[:20]):
                cur = Cursor()
                with self.assertRaisesRegex(PreparationContractError, "OBJECTIVE_INVALID"):
                    prepare_source_investigation(cur, value)
                self.assertEqual(cur.calls, [])

    def test_invalid_budget(self):
        for budget in (0, 26, True, 1.2, None, "12"):
            with self.subTest(budget=budget):
                cur = Cursor()
                with self.assertRaisesRegex(PreparationContractError, "LIMIT_INVALID"):
                    prepare_source_investigation(cur, "metadata discovery", budget)
                self.assertEqual(cur.calls, [])

    def test_database_error_is_redacted(self):
        cur = Cursor(error=RuntimeError("sensitive connection secret"))
        with self.assertRaises(PreparationContractError) as cm:
            prepare_source_investigation(cur, "metadata discovery")
        self.assertEqual(str(cm.exception), "LF_D4_CANONICAL_READBACK_FAILED")
        self.assertNotIn("sensitive", str(cm.exception))

    def test_wrong_schema(self):
        p = good(); p["schema_version"] = "NOT_CANONICAL"
        self.assert_block(p, "LF_D4_CANONICAL_SCHEMA_MISMATCH")

    def test_business_flags_fail_closed(self):
        for key in (
            "business_data_read_authorized", "rows_accessed", "runtime_dispatched",
            "final_business_answer_allowed", "effects_executed", "global_discovery_exhausted",
        ):
            for bad in (True, "false", None):
                with self.subTest(key=key, bad=bad):
                    p = good(); p[key] = bad
                    self.assert_block(p)

    def test_global_exhaustion_forgery(self):
        p = good(); p["planner_stop_is_local_only"] = False
        self.assert_block(p, "LF_D4_DISCOVERY_EXHAUSTION_SCOPE_INVALID")

    def test_unknown_action(self):
        p = good(); p["next_action"] = "RUN_BUSINESS_SQL"
        self.assert_block(p, "LF_D4_NEXT_ACTION_NOT_RECOGNIZED")

    def test_missing_discovery(self):
        p = good(); p.pop("discovery")
        self.assert_block(p, "LF_D4_DISCOVERY_RESULT_INVALID")

    def test_wrong_check_count(self):
        p = good(); p["binding_checks_count"] = 2
        self.assert_block(p, "LF_D4_BINDING_READBACK_COUNT_MISMATCH")

    def test_forged_source_allow(self):
        p = good(); p["binding_checks"][0]["access_authorized"] = True
        self.assert_block(p, "LF_D4_SOURCE_READ_NOT_ADMITTED")

    def test_d3_mismatch(self):
        p = good(); p["d3"]["next_action"] = "WRONG"
        self.assert_block(p, "LF_D4_D3_ACTION_MISMATCH")

    def test_d3_answer_forgery(self):
        p = good(); p["d3"]["final_business_answer_allowed"] = True
        self.assert_block(p, "LF_D4_D3_BUSINESS_ANSWER_FORBIDDEN")

    def test_business_rows_forgery(self):
        p = good(); p["business_rows"] = [{"secret": "fake"}]
        self.assert_block(p, "LF_D4_UNAUTHORIZED_DATA_PLANE_PAYLOAD")

    def test_drift_block_without_d3_is_valid(self):
        p = good(); p["next_action"] = "BLOCK_INVENTORY_LOOKUP_CURRENTNESS_UNSTABLE"
        p.pop("d3"); p.pop("binding_checks"); p["binding_checks_count"] = 0
        p["discovery"] = {"discovery_state": "ERROR_FAIL_CLOSED"}
        got = prepare_source_investigation(Cursor(value=p), "metadata discovery")
        self.assertEqual(got["next_action"], p["next_action"])


if __name__ == "__main__":
    unittest.main()
