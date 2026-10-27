"""All readbacks, authority/judge verdicts and writer effects are synthetic."""
from copy import deepcopy
import unittest
from caller_simulation_v1 import (
    caller_request_identity, normalized_handoff, simulate_caller,
)


class FakePorts:
    synthetic = True

    def __init__(self):
        h = {"context_id": "aaaaaaaa-0000-4000-8000-000000000001",
             "context_sha256": "a" * 64, "target_ref": "lf-screen-contract://TEST",
             "requested_scope_ids": ["S1", "S2"], "producer_execution_ref": "PROFILE",
             "entry_contract_digest_sha256": "b" * 64}
        self.values = {
            "terminal": {"state": "PASS", "execution_id": "PROFILE"},
            "prepare": {"programming_admission_request": {
                "source_execution_id": "PROFILE", "router_action_binding": {"binding_sha256": "PIN"},
                "programming_handoff": h}},
            "context": {"context_id": h["context_id"], "context_sha256": h["context_sha256"],
                        "created_by_execution_id": "PROFILE"},
            "judge": {"state": "VERIFIED", "subject_sha256": h["context_sha256"], "execution_id": "JUDGE"},
            "resolve": {"admissible": True},
            "admit": {"paso": "PROGRAMACION_DESARROLLO_ADMITIDO", "downstream_execution_allowed": False},
        }
        self.faults = {}
        self.calls = []
        self.ledger = set()
        self.timeout_after_write = False

    def call(self, stage, payload):
        self.calls.append((stage, deepcopy(payload)))
        if self.faults.get(stage, 0):
            self.faults[stage] -= 1
            raise TimeoutError("synthetic fault")
        if stage == "record":
            # Tuple of the six normalized fields is a test identity, NOT D7's
            # jsonb-text SHA. Real SQL key parity is tested separately.
            h = normalized_handoff(payload["request"]["programming_handoff"])
            key = tuple((k, tuple(v) if isinstance(v, list) else v) for k, v in sorted(h.items()))
            replay = key in self.ledger
            self.ledger.add(key)
            if self.timeout_after_write:
                self.timeout_after_write = False
                raise TimeoutError("synthetic committed-write/lost-response")
            return {"status": "IDEMPOTENT_REPLAY" if replay else "RECORDED"}
        return deepcopy(self.values[stage])


class CallerSimulationTests(unittest.TestCase):
    def setUp(self):
        self.p = FakePorts()

    def run_caller(self):
        return simulate_caller("PROFILE", self.p)

    def test_positive_order_no_authority_and_no_judge_creation(self):
        result = self.run_caller()
        self.assertEqual(result["state"], "SYNTHETIC_ADMISSION_OBSERVED")
        self.assertEqual([s for s, _ in self.p.calls],
                         ["terminal", "prepare", "context", "judge", "record", "resolve", "admit"])
        self.assertIs(result["operational_admission"], False)
        self.assertIs(result["downstream_execution_allowed"], False)

    def test_terminal_not_ready_stops_before_context_or_write(self):
        self.p.values["terminal"]["state"] = "NOT_TERMINAL"
        self.assertEqual(self.run_caller()["state"], "WAITING_TERMINAL")
        self.assertEqual(len(self.p.calls), 1)

    def test_foreign_terminal_does_not_prove_source(self):
        self.p.values["terminal"]["execution_id"] = "OTHER"
        self.assertEqual(self.run_caller()["state"], "WAITING_TERMINAL")

    def test_missing_continuation(self):
        self.p.values["prepare"] = {}
        self.assertEqual(self.run_caller()["state"], "NO_PROGRAMMING_CONTINUATION")

    def test_foreign_request_source(self):
        self.p.values["prepare"]["programming_admission_request"]["source_execution_id"] = "OTHER"
        self.assertEqual(self.run_caller()["state"], "SOURCE_MISMATCH")

    def test_context_is_read_and_compared_not_trusted_from_model(self):
        for field in ("context_id", "context_sha256", "created_by_execution_id"):
            with self.subTest(field=field):
                self.p = FakePorts()
                self.p.values["context"][field] = "OTHER"
                self.assertEqual(self.run_caller()["state"], "SNAPSHOT_SOURCE_MISMATCH")
                self.assertFalse(self.p.ledger)

    def test_absent_judge_does_not_create_or_write(self):
        self.p.values["judge"] = {"state": "MISSING"}
        self.assertEqual(self.run_caller()["state"], "WAITING_INDEPENDENT_JUDGE")
        self.assertFalse(self.p.ledger)

    def test_invalid_judge_no_retry(self):
        self.p.values["judge"]["subject_sha256"] = "c" * 64
        self.assertEqual(self.run_caller()["state"], "JUDGE_INVALID")
        self.assertEqual(sum(s == "judge" for s, _ in self.p.calls), 1)

    def test_write_blocked(self):
        self.p.call = lambda stage, payload: {"status": "BLOCKED"} if stage == "record" else deepcopy(self.p.values[stage])
        self.assertEqual(self.run_caller()["state"], "RECEIPT_WRITE_BLOCKED")

    def test_missing_stale_revoked_receipt_returns_without_admission(self):
        for reason in ("PG01_V2_RECEIPT_NOT_FOUND", "PG01_V2_EXPIRED", "PG01_V2_REVOKED"):
            with self.subTest(reason=reason):
                self.p = FakePorts()
                self.p.values["resolve"] = {"admissible": False, "reason": reason}
                self.assertEqual(self.run_caller()["state"], "RETURN_TO_ANALYSIS_NO_CODE")
                self.assertNotIn("admit", [s for s, _ in self.p.calls])

    def test_truthy_admissible_cannot_pass(self):
        self.p.values["resolve"]["admissible"] = "true"
        self.assertEqual(self.run_caller()["state"], "RETURN_TO_ANALYSIS_NO_CODE")

    def test_replay_rechecks_currentness_no_cached_positive(self):
        self.run_caller()
        self.p.values["resolve"] = {"admissible": False}
        self.assertEqual(self.run_caller()["state"], "RETURN_TO_ANALYSIS_NO_CODE")
        self.assertEqual(len(self.p.ledger), 1)
        self.assertEqual(sum(s == "terminal" for s, _ in self.p.calls), 2)

    def test_lost_write_response_replays_without_duplicate(self):
        self.p.timeout_after_write = True
        self.assertEqual(self.run_caller()["state"], "SYNTHETIC_ADMISSION_OBSERVED")
        self.assertEqual(len(self.p.ledger), 1)
        self.assertEqual(sum(s == "record" for s, _ in self.p.calls), 2)

    def test_transient_stage_recovers_within_three_attempts(self):
        self.p.faults["context"] = 2
        self.assertEqual(self.run_caller()["state"], "SYNTHETIC_ADMISSION_OBSERVED")
        self.assertEqual(sum(s == "context" for s, _ in self.p.calls), 3)

    def test_transient_retries_exhausted_no_downstream(self):
        self.p.faults["context"] = 99
        self.assertEqual(self.run_caller()["state"], "TRANSIENT_RETRIES_EXHAUSTED")
        self.assertEqual(sum(s == "context" for s, _ in self.p.calls), 3)
        self.assertFalse(self.p.ledger)

    def test_inactive_gate_and_unexpected_authority(self):
        self.p.values["admit"]["paso"] = "PROGRAMACION_OPERACION_NO_ACTIVA"
        self.assertEqual(self.run_caller()["state"], "ADMISSION_BLOCKED")
        self.p.values["admit"]["downstream_execution_allowed"] = True
        self.assertEqual(self.run_caller()["state"], "UNEXPECTED_EFFECT_AUTHORITY")

    def test_input_readbacks_unchanged(self):
        before = deepcopy(self.p.values)
        self.run_caller()
        self.assertEqual(before, self.p.values)

    def test_synthetic_opt_in_and_attempt_limit(self):
        self.p.synthetic = False
        with self.assertRaises(ValueError): self.run_caller()
        self.p.synthetic = True
        for value in (True, 0, 4):
            with self.assertRaises(ValueError): simulate_caller("PROFILE", self.p, max_attempts=value)

    def test_identity_covers_every_d7_field_and_router_binding(self):
        r = self.p.values["prepare"]["programming_admission_request"]
        h = r["programming_handoff"]
        key = caller_request_identity("PROFILE", r["router_action_binding"], h)
        for field, value in (("context_id", "aaaaaaaa-0000-4000-8000-000000000002"),
                             ("context_sha256", "c" * 64), ("target_ref", "OTHER"),
                             ("requested_scope_ids", ["S3"]),
                             ("entry_contract_digest_sha256", "e" * 64)):
            with self.subTest(field=field):
                changed = deepcopy(h); changed[field] = value
                self.assertNotEqual(key, caller_request_identity("PROFILE", r["router_action_binding"], changed))
        changed = deepcopy(h); changed["producer_execution_ref"] = "OTHER"
        self.assertNotEqual(key, caller_request_identity("OTHER", r["router_action_binding"], changed))
        self.assertNotEqual(key, caller_request_identity("PROFILE", {"binding_sha256": "OTHER"}, h))

    def test_scope_order_duplicates_do_not_create_new_identity(self):
        r = self.p.values["prepare"]["programming_admission_request"]
        h = r["programming_handoff"]
        changed = deepcopy(h); changed["requested_scope_ids"] = ["S2", "S1", "S2"]
        self.assertEqual(caller_request_identity("PROFILE", r["router_action_binding"], h),
                         caller_request_identity("PROFILE", r["router_action_binding"], changed))

    def test_malformed_handoffs_and_foreign_producer_fail_closed(self):
        for field, value in (("requested_scope_ids", None), ("context_id", "bad"),
                             ("producer_execution_ref", "OTHER"), ("context_sha256", None)):
            with self.subTest(field=field):
                self.p = FakePorts()
                self.p.values["prepare"]["programming_admission_request"]["programming_handoff"][field] = value
                self.assertEqual(self.run_caller()["state"], "INVALID_SYNTHETIC_READBACK")
                self.assertFalse(self.p.ledger)


if __name__ == "__main__":
    unittest.main()
