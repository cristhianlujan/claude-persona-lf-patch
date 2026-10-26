"""Caller identity tests and real fixed-worker integration; synthetic data."""
from copy import deepcopy
from dataclasses import replace
import json
from pathlib import Path
from unittest.mock import patch
import unittest

import analysis_a6_a9_readonly_caller_v1 as caller

HERE = Path(__file__).resolve().parent


class ReadOnlyCallerTests(unittest.TestCase):
    def setUp(self):
        ctx = json.loads((HERE / "fixtures/programming_pg01_receiver_base_v1.json").read_text())["context"]
        self.expected = caller.ExpectedContext(ctx["consumer_code"], ctx["subject"]["ref"],
            "2026-10-02T00:00:00Z", "11111111-1111-1111-1111-111111111111", "a" * 64)
        self.resolution = {
            "schema_version": "LF_DECISION_CONTEXT_ASOF_RESOLUTION_V1",
            "state": "RESOLVED", "context_id": self.expected.context_id,
            "context_sha256": self.expected.context_sha256,
            "consumer_code": self.expected.consumer_code, "subject_ref": self.expected.subject_ref,
            "context": ctx, "latest_reinterpreted": False,
            "resolution_basis": "IMMUTABLE_RECORDED_CONTEXT",
        }
        self.packet = {"resolution": self.resolution, "transaction_read_only": True,
                       "recomputed_context_sha256": self.expected.context_sha256}
        self.calls = []

    def read(self, sql, params):
        self.calls.append((sql, params))
        return self.packet

    def execute(self, **options):
        port = caller.SqlReadPort(self.read)
        return caller.DecisionContextShadowCaller(port).resolve(self.expected, **options)

    def diagnostic(self, code):
        result = self.execute(enabled=True)
        self.assertIs(result.active_response, self.resolution)
        observation = result.observation.wait(3)
        self.assertEqual(observation["error_code"], code)
        self.assertIs(observation["route_effect_allowed"], False)

    def test_one_fixed_parameterized_read(self):
        self.execute()
        self.assertEqual(len(self.calls), 1)
        sql, params = self.calls[0]
        self.assertEqual(sql, caller.READ_SQL)
        self.assertEqual(params, (self.expected.consumer_code, self.expected.subject_ref, self.expected.as_of))
        self.assertNotIn(self.expected.subject_ref, sql)
        self.assertIn("fn_lf_decision_context_asof_resolve_v1", sql)
        self.assertNotIn("record_v1", sql)
        self.assertIn("current_setting('transaction_read_only')", sql)

    def test_disabled_does_not_call_shadow_or_change_original(self):
        with patch.object(caller, "shadow_after_response_v1") as observe:
            result = self.execute()
            self.assertIs(result.active_response, self.resolution)
            self.assertEqual(result.observation.read()["state"], "DISABLED")
            observe.assert_not_called()

    def test_complete_synthetic_context_observed(self):
        original = deepcopy(self.packet)
        result = self.execute(enabled=True)
        self.assertIs(result.active_response, self.resolution)
        report = result.observation.wait(3)
        self.assertEqual(report["state"], "OBSERVED")
        self.assertEqual(report["preview_status"], "CANDIDATE_ASSEMBLED")
        self.assertEqual(self.packet, original)
        for key in ("planning_allowed", "execution_allowed", "operational_admission", "persistence_allowed"):
            self.assertIs(report[key], False)

    def test_missing_context_keeps_resolver_unknown(self):
        self.resolution["state"] = "UNKNOWN"
        self.packet["recomputed_context_sha256"] = None
        result = self.execute(enabled=True)
        self.assertIs(result.active_response, self.resolution)
        self.assertEqual(result.observation.read()["state"], "SKIPPED_NO_CONTEXT")

    def test_wrong_context_id_cannot_select_another_record(self):
        self.resolution["context_id"] = "22222222-2222-2222-2222-222222222222"
        self.diagnostic("EXACT_CONTEXT_ID_MISMATCH")

    def test_declared_hash_mismatch(self):
        self.resolution["context_sha256"] = "b" * 64
        self.diagnostic("EXACT_CONTEXT_DIGEST_MISMATCH")

    def test_recomputed_postgres_hash_mismatch(self):
        self.packet["recomputed_context_sha256"] = "b" * 64
        self.diagnostic("EXACT_CONTEXT_DIGEST_MISMATCH")

    def test_readonly_flag_must_be_server_boolean(self):
        for value in (False, "on", "true", 1, None):
            self.packet["transaction_read_only"] = value
            self.diagnostic("READ_ONLY_TRANSACTION_UNVERIFIED")

    def test_cross_consumer_and_subject_resolution(self):
        for key in ("consumer_code", "subject_ref"):
            previous = self.resolution[key]
            self.resolution[key] = "OTHER"
            self.diagnostic("RESOLUTION_BINDING_MISMATCH")
            self.resolution[key] = previous

    def test_nested_context_binding_must_match(self):
        self.resolution["context"]["consumer_code"] = "OTHER"
        self.diagnostic("CONTEXT_BINDING_MISMATCH")

    def test_mutable_resolution_is_not_observed(self):
        self.resolution["latest_reinterpreted"] = True
        self.diagnostic("RESOLUTION_BINDING_MISMATCH")

    def test_no_snapshot_does_not_get_synthesized(self):
        self.resolution["context"]["extensions"] = {}
        self.diagnostic("PROGRAMMING_SNAPSHOT_MISSING")

    def test_shadow_exception_does_not_change_resolution(self):
        with patch.object(caller, "shadow_after_response_v1", side_effect=RuntimeError("synthetic")):
            self.diagnostic("SHADOW_CALLER_FAILED")

    def test_shadow_cannot_replace_active_response(self):
        fake = caller.ShadowDispatch({"different": True}, caller.Observation({}))
        with patch.object(caller, "shadow_after_response_v1", return_value=fake):
            self.diagnostic("SHADOW_RESPONSE_REPLACEMENT_REJECTED")

    def test_transport_error_propagates_without_retry(self):
        def fail(sql, params):
            self.calls.append((sql, params))
            raise ConnectionError("synthetic")
        obj = caller.DecisionContextShadowCaller(caller.SqlReadPort(fail))
        with self.assertRaises(ConnectionError):
            obj.resolve(self.expected, enabled=True)
        self.assertEqual(len(self.calls), 1)

    def test_invalid_expected_identity_never_queries(self):
        for value in (replace(self.expected, context_id="invalid"), replace(self.expected, context_sha256="bad"),
                      replace(self.expected, as_of="2026-10-02T00:00:00"), None):
            with self.assertRaises(ValueError):
                caller.DecisionContextShadowCaller(caller.SqlReadPort(self.read)).resolve(value)
        self.assertEqual(self.calls, [])

    def test_unexpected_resolution_schema_is_only_diagnostic(self):
        self.resolution["schema_version"] = "OTHER"
        self.diagnostic("RESOLUTION_SCHEMA_INVALID")

    def test_invalid_transport_packet_is_not_fake_success(self):
        with self.assertRaisesRegex(ValueError, "READ_PORT_PACKET_INVALID"):
            caller.observe_resolution_v1({}, self.expected, enabled=True)


if __name__ == "__main__":
    unittest.main()
