"""Deterministic tests: no external network, no credential and no DB mutations."""
import os
import unittest
from unittest.mock import patch

from lf_engineering_checkpoint_mcp import (
    CONNECTOR, OPERATION, TARGET, Refused, TransitionRequest, authorize_checkpoint,
    authorize_execution, authorize_route, evidence_sha256, run_transaction,
    transition_checkpoint,
)


def req():
    return TransitionRequest(
        "IG_CURATOR_VALIDATOR_REFACTOR_V2", "M4.11", "PREREQ_GATES_PASS",
        "DONE", "supabase://programacion.provenance_receipts/1667#sha=example",
        "LF_TEST_RUNNER", "readback PASS", "EXEC-SANDBOX-TEST-1",
    )


def manifest(request):
    return {"operational_transaction_admission": {
        "status": "APPROVED", "connector": CONNECTOR,
        "plan_code": request.plan_code, "unit_code": request.unit_code,
        "checkpoint_code": request.checkpoint_code,
        "new_status": request.new_status,
        "evidence_ref_sha256": evidence_sha256(request.evidence_ref),
        "verification": "PASS",
    }}


ROUTE = {
    "router": "ACT-0001", "status": "READY_TO_EXECUTE",
    "operation_code": OPERATION, "asset_type": "DB", "action_code": "UPDATE",
    "downstream_execution_allowed": True,
}


def bootstrap(request):
    return {"terminal_action": "CONTINUE_CURRENT_CHECKPOINT",
            "current_checkpoint": {"checkpoint_code": request.checkpoint_code},
            "action_spec": {"status": "READY"}}


class Cursor:
    def __init__(self, values):
        self.values = iter(values)
        self.executed = []

    def __enter__(self):
        return self

    def __exit__(self, *_):
        return False

    def execute(self, query, params=None):
        self.executed.append((query, params))

    def fetchone(self):
        return next(self.values)


class FakeConnection:
    def __init__(self, values):
        self.cur = Cursor(values)

    def cursor(self):
        return self.cur


def data(request, *, route=None, authorization=None, state=None,
         checkpoint=None, applied=None, after=None):
    return [
        (route if route is not None else ROUTE,),
        authorization if authorization is not None else
        (OPERATION, "DB", TARGET, "IN_PROGRESS", manifest(request)),
        (state if state is not None else bootstrap(request),),
        checkpoint if checkpoint is not None else ("PENDING", None),
        (applied if applied is not None else {"transition": {"status": "APPLIED"}},),
        after if after is not None else (request.new_status, request.evidence_ref),
    ]


class TestConnector(unittest.TestCase):
    def test_canonical_run_positive_dry_run(self):
        request = req()
        db = FakeConnection(data(request))
        outcome = run_transaction(db, request, dry_run=True)
        self.assertEqual(outcome["status"], "DRY_RUN_PASS_NOT_COMMITTED")
        self.assertEqual(len(db.cur.executed), 6)
        self.assertEqual(sum("fn_engineering_checkpoint_transition_v1" in q
                             for q, _ in db.cur.executed), 1)
        self.assertFalse(any(q.strip().upper().startswith(("UPDATE", "DELETE", "INSERT",
                                                             "ALTER", "DROP", "CREATE"))
                             for q, _ in db.cur.executed))
        self.assertEqual(db.cur.executed[4][1][3], "DONE")

    def test_fail_closed_for_bad_router(self):
        request = req()
        for change in [{"status": "BLOCKED"}, {"operation_code": "UNAUTHORIZED"},
                       {"downstream_execution_allowed": False}]:
            db = FakeConnection(data(request, route={**ROUTE, **change}))
            with self.assertRaises(Refused):
                run_transaction(db, request)
            self.assertEqual(len(db.cur.executed), 1)

    def test_fail_closed_for_unapproved_or_mismatched_execution(self):
        request = req()
        for bad in [
            (OPERATION, "DB", TARGET, "IN_PROGRESS", {}),
            (OPERATION, "DB", TARGET, "COMPLETED", manifest(request)),
            (OPERATION, "MIGRATION", TARGET, "IN_PROGRESS", manifest(request)),
            (OPERATION, "DB", TARGET, "IN_PROGRESS", {
                "operational_transaction_admission": {
                    **manifest(request)["operational_transaction_admission"],
                    "checkpoint_code": "OTHER"}}),
        ]:
            db = FakeConnection(data(request, authorization=bad))
            with self.assertRaises(Refused):
                run_transaction(db, request)
            self.assertEqual(len(db.cur.executed), 2)

    def test_fail_closed_for_bootstrap(self):
        request = req()
        for change in [{"terminal_action": "STOP_ACTION_SPEC_INCOMPLETE"},
                       {"current_checkpoint": {"checkpoint_code": "CP3"}},
                       {"action_spec": {"status": "BLOCKED"}}]:
            db = FakeConnection(data(request, state={**bootstrap(request), **change}))
            with self.assertRaises(Refused):
                run_transaction(db, request)
            self.assertEqual(len(db.cur.executed), 3)

    def test_fail_closed_for_terminal_and_bad_readback(self):
        request = req()
        for changes in [dict(checkpoint=("DONE", "existing")),
                        dict(after=("PENDING", None)),
                        dict(applied={"transition": {"status": "BLOCKED"}})]:
            db = FakeConnection(data(request, **changes))
            with self.assertRaises(Refused):
                run_transaction(db, request)

    def test_no_write_without_operational_lane(self):
        request = req()
        with patch.dict(os.environ, {"LF_ENGINEERING_TX_LANE": "",
                                     "LF_ENGINEERING_TX_DSN": ""}):
            self.assertEqual(transition_checkpoint(request)["blocking_code"],
                             "BLOCK_OPERATIONAL_MCP_INACTIVE_BY_POLICY")

    def test_no_write_without_dedicated_credentials(self):
        request = req()
        with patch.dict(os.environ, {"LF_ENGINEERING_TX_LANE":
                                     "GOVERNED_OPERATIONAL_DML",
                                     "LF_ENGINEERING_TX_DSN": ""}):
            self.assertEqual(transition_checkpoint(request)["blocking_code"],
                             "BLOCK_DEDICATED_RUNTIME_CREDENTIAL_NOT_CONNECTED")

    def test_invalid_input(self):
        base = req()
        for invalid in [
            {**base.__dict__, "new_status": "BLOCKED"},
            {**base.__dict__, "evidence_ref": "  "},
            {**base.__dict__, "router_execution_id": "NO-EXEC"},
        ]:
            with self.assertRaises(Refused):
                TransitionRequest(**invalid).validate()


if __name__ == "__main__":
    unittest.main()
