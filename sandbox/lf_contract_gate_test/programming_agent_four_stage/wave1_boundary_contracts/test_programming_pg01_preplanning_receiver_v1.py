"""Synthetic unit + disposable-Postgres integration cases."""
from copy import deepcopy
from types import SimpleNamespace
import json
from pathlib import Path
import unittest
import subprocess

from programming_pg01_receiver_v1 import ROOT
from programming_pg01_technical_currentness_v1 import TechnicalCurrentnessPort

from programming_pg01_receiver_v1 import ExpectedHandoff, canonical_sha256
from programming_pg01_preplanning_receiver_v1 import SourcePreplanningReceiver, PACKET_SCHEMA
import test_programming_pg01_preplanning_checks_v1 as fixture_checks

HERE = Path(__file__).resolve().parent


def case_fixture():
    fixture = fixture_checks.PreplanningChecks()
    fixture.setUp()
    fixture.complete_c7()
    fixture.snapshot["target"]["repo_full_name"] = fixture.repo
    return fixture


def packet_for(expected, scope_ids, fixture):
    return {
        "schema_version": PACKET_SCHEMA,
        "context_id": expected.context_id, "context_sha256": expected.context_sha256,
        "scope_ids": list(scope_ids), "snapshot_sha256": canonical_sha256(fixture.snapshot),
        "target": deepcopy(fixture.snapshot["target"]),
        "technical_framework": deepcopy(fixture.frame), "binding_map": fixture.mapping(),
    }


def currentness_fixture(fixture, mutate=None):
    """Synthetic provider over the real canonical evaluator; no live provenance."""
    revision = subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip()

    def provider(expected, scope, closure, additional):
        snapshot = fixture.snapshot
        values = {"context": expected.context_sha256,
                  "snapshot_schema": expected.snapshot_schema_digest_sha256,
                  "snapshot_authority": snapshot["authority_fingerprint_sha256"],
                  "snapshot_source": snapshot["source_snapshot_sha256"], **additional}
        binding = {
            "schema_version": "LF_MATERIAL_CURRENTNESS_BINDING_V1",
            "authority": {"ref": "fixture://technical-authority", "bound_revision": revision, "current_revision": revision},
            "evidence_revision": revision, "dependency_completeness": "COMPLETE", "require_ancestor": True,
            "contract_identity": "PROGRAMMING_CONTEXT_SNAPSHOT_V1:" + expected.snapshot_schema_digest_sha256,
            "implementation_binding": "PG-01:" + scope,
            "materials": [{"material_id": key, "kind": "DIGEST", "bound_digest": value, "current_digest": value, "depends_on": []} for key, value in values.items()],
            "root_material_ids": list(values), "compatibility_contract": {"assessments": []},
        }
        packet = {"context_id": expected.context_id, "context_sha256": expected.context_sha256,
                  "scope_id": scope, "scope_ids": sorted(closure), "target": deepcopy(snapshot["target"]),
                  "technical_materials_sha256": canonical_sha256(additional), "binding": binding}
        if mutate:
            mutate(packet)
        return packet
    return TechnicalCurrentnessPort(ROOT, provider)


class IntegratedReceiverChecks(unittest.TestCase):
    def setUp(self):
        self.fixture = case_fixture()
        self.expected = ExpectedHandoff(
            "11111111-1111-1111-1111-111111111111", "a"*64, "b"*64,
            "FIXTURE", "fixture://subject", "2026-10-23T00:00:00Z")
        self.calls = []
        projection = {"scope_id": "S1", "snapshot": deepcopy(self.fixture.snapshot)}
        self.base = {
            "schema_version": "PG01_READ_ONLY_BOUNDARY_RESULT_V1",
            "state": "ACCEPT", "code": "READ_ONLY_BOUNDARY_ACCEPTED",
            "scope_id": "S1", "execution_allowed": False,
            "pending_gates": ["PG-01_C4", "PG-01_C7", "PG-01_C6_PERSISTENCE"],
            "admitted_scope_ids": ["S1"], "material_projection": projection,
            "receipt": {"schema_version": "PROGRAMMING_CONTEXT_HANDOFF_RECEIPT_V1",
                "context_id": self.expected.context_id, "context_sha256": self.expected.context_sha256,
                "snapshot_schema_digest_sha256": "b"*64, "receiver_schema_digest_sha256": "b"*64,
                "material_projection_sha256": canonical_sha256(projection),
                "validated_material_paths": ["extensions.programming_context_snapshot"],
                "verdict": "ACCEPT"},
        }

    def receiver(self, mutate=None, provider=None, reader=None):
        def get(expected, scope, closure):
            self.calls.append((expected.context_id, scope, closure))
            packet = packet_for(expected, closure, self.fixture)
            if mutate:
                mutate(packet)
            return packet
        return SourcePreplanningReceiver(
            SimpleNamespace(consume=lambda *a: deepcopy(self.base)),
            provider or get,
            reader or (lambda p: self.fixture.store[p["path"]]),
            technical_currentness=currentness_fixture(self.fixture))

    def test_enriched_projection_hash_and_same_seven_fields(self):
        got = self.receiver().consume(self.expected, "S1")
        self.assertEqual(got["state"], "ACCEPT")
        self.assertEqual(got["receipt"]["material_projection_sha256"], canonical_sha256(got["material_projection"]))
        self.assertNotEqual(got["receipt"]["material_projection_sha256"], self.base["receipt"]["material_projection_sha256"])
        self.assertEqual(set(got["receipt"]), set(self.base["receipt"]))
        self.assertEqual(got["material_projection"]["snapshot"], self.fixture.snapshot)

    def test_accept_never_promotes_operational_gates(self):
        got = self.receiver().consume(self.expected, "S1")
        for flag in ("planning_allowed", "execution_allowed", "operational_admission"):
            self.assertIs(got[flag], False)
        self.assertTrue(set(self.base["pending_gates"]).issubset(got["pending_gates"]))
        self.assertNotIn("admitted_scope_ids", got)

    def test_repeat_and_proposed_projection(self):
        receiver = self.receiver()
        before = deepcopy(self.base)
        got = receiver.consume(self.expected, "S1")
        self.assertEqual(receiver.consume(self.expected, "S1"), got)
        self.assertEqual(receiver.consume(self.expected, "S1", proposed_projection=got["material_projection"]), got)
        self.assertEqual(self.base, before)

    def test_lossy_projection_and_block_hash(self):
        receiver = self.receiver()
        full = receiver.consume(self.expected, "S1")
        for key in ("technical_framework", "sufficiency_report", "sufficiency_binding_map", "snapshot", "technical_currentness"):
            lossy = deepcopy(full["material_projection"]); lossy.pop(key)
            got = receiver.consume(self.expected, "S1", proposed_projection=lossy)
            self.assertEqual(got["code"], "PREPLANNING_PROJECTION_LOSS_OR_MISMATCH")
            self.assertEqual(got["receipt"]["verdict"], "BLOCK")
            self.assertEqual(got["receipt"]["material_projection_sha256"], canonical_sha256(full["material_projection"]))

    def test_wrong_subject_scope_hash_or_target(self):
        variants = [
            lambda p: p.update(context_id="OTHER"),
            lambda p: p.update(context_sha256="0"*64),
            lambda p: p.update(scope_ids=["OTHER"]),
            lambda p: p.update(snapshot_sha256="0"*64),
            lambda p: p["target"].update(repo_full_name="OTHER/REPO"),
            lambda p: p["target"].update(base_head_sha="0"*40),
        ]
        for change in variants:
            got = self.receiver(change).consume(self.expected, "S1")
            self.assertEqual(got["code"], "PREPLANNING_EVIDENCE_SUBJECT_MISMATCH")

    def test_unknown_packet_field_and_invalid_json(self):
        got = self.receiver(lambda p: p.update(operational_admission=True)).consume(self.expected, "S1")
        self.assertEqual(got["code"], "PREPLANNING_EVIDENCE_PACKET_INVALID")
        got = self.receiver(lambda p: p.update(technical_framework=float("nan"))).consume(self.expected, "S1")
        self.assertEqual(got["state"], "BLOCK")

    def test_missing_frame_and_missing_map(self):
        for key, target in (("technical_framework", "PROJECT_TECHNICAL_AUTHORITY"), ("binding_map", "ANALYSIS")):
            got = self.receiver(lambda p: p.update({key: None})).consume(self.expected, "S1")
            self.assertEqual(got["state"], "BLOCK")
            self.assertIn(target, got["return_targets"])

    def test_provider_exception_and_artifact_unavailable(self):
        def unavailable(*a): raise RuntimeError("fixture")
        got = self.receiver(provider=unavailable).consume(self.expected, "S1")
        self.assertEqual(got["code"], "PREPLANNING_EVIDENCE_UNAVAILABLE")
        self.assertEqual(got["receipt"]["verdict"], "BLOCK")
        got = self.receiver(reader=unavailable).consume(self.expected, "S1")
        self.assertEqual(got["technical_framework"]["status"], "MISSING")

    def test_rejected_boundary_never_calls_provider(self):
        self.base.update(state="BLOCK", code="FIXTURE_EARLY_BLOCK", receipt=None)
        got = self.receiver().consume(self.expected, "S1")
        self.assertEqual(got["receipt"], None)
        self.assertEqual(self.calls, [])
        self.assertIs(got["preplanning_evaluated"], False)

    def test_technical_input_change_changes_digest(self):
        first = self.receiver().consume(self.expected, "S1")
        got = self.receiver(lambda p: p["technical_framework"]["request_budget"].update(spent="0.80")).consume(self.expected, "S1")
        self.assertEqual(got["state"], "ACCEPT")
        self.assertNotEqual(got["receipt"]["material_projection_sha256"], first["receipt"]["material_projection_sha256"])
        self.assertEqual(got["technical_framework"]["budget_state"], "WARNING")

    def test_mapping_change_changes_digest(self):
        first = self.receiver().consume(self.expected, "S1")
        got = self.receiver(lambda p: p["binding_map"].update(source_ref="fixture://new-map")).consume(self.expected, "S1")
        self.assertEqual(got["state"], "ACCEPT")
        self.assertNotEqual(got["receipt"]["material_projection_sha256"], first["receipt"]["material_projection_sha256"])

    def test_valid_map_but_missing_material_returns_analysis(self):
        def alter(packet):
            packet["binding_map"]["binding_kinds"]["messages"] = "FIXTURE_ABSENT_KIND"
        got = self.receiver(alter).consume(self.expected, "S1")
        self.assertEqual(got["state"], "BLOCK")
        self.assertEqual(got["sufficiency_report"]["status"], "MISSING")
        self.assertIn("ANALYSIS", got["return_targets"])

    def test_malformed_projection_block_and_retains_authentic_digest(self):
        receiver = self.receiver()
        full = receiver.consume(self.expected, "S1")
        got = receiver.consume(self.expected, "S1", proposed_projection={"bad": float("nan")})
        self.assertEqual(got["code"], "PREPLANNING_PROJECTION_INVALID")
        self.assertEqual(got["receipt"]["material_projection_sha256"], full["receipt"]["material_projection_sha256"])

    def test_exhausted_budget_returns_decision(self):
        got = self.receiver(lambda p: p["technical_framework"]["request_budget"].update(spent="1.00")).consume(self.expected, "S1")
        self.assertEqual(got["code"], "PREPLANNING_REQUIRES_DECISION")
        self.assertEqual(got["receipt"]["verdict"], "BLOCK")


def exercise_preplanning(*, context, persisted, boundary_factory, check):
    """Real SQL boundary, canonical currentness engine, synthetic evidence."""
    fixture = case_fixture()
    candidate = deepcopy(context)
    candidate["extensions"]["programming_context_snapshot"] = deepcopy(fixture.snapshot)
    good, handoff = persisted(candidate, "preplanning")
    boundary = boundary_factory(good)

    def provider(expected, scope, closure):
        return packet_for(expected, closure, fixture)

    wrapper = SourcePreplanningReceiver(boundary, provider,
                                       lambda pin: fixture.store[pin["path"]],
                                       technical_currentness=currentness_fixture(fixture))
    accepted = wrapper.consume(handoff, "S1")
    check("preplanning_real_sql_boundary_accept", accepted["state"], "ACCEPT")
    check("preplanning_framework_complete", accepted["technical_framework"]["status"], "COMPLETE")
    check("preplanning_sufficiency_complete", accepted["sufficiency_report"]["status"], "COMPLETE")
    check("preplanning_hash_recomputed", accepted["receipt"]["material_projection_sha256"], canonical_sha256(accepted["material_projection"]))
    check("preplanning_exact_snapshot_preserved", accepted["material_projection"]["snapshot"], fixture.snapshot)
    check("preplanning_full_repeat_deterministic", wrapper.consume(handoff, "S1"), accepted)
    check("preplanning_never_execution", accepted["execution_allowed"], False)
    check("preplanning_never_operational", accepted["operational_admission"], False)
    check("preplanning_never_planning", accepted["planning_allowed"], False)
    check("preplanning_C4_C7_still_pending", all(g in accepted["pending_gates"] for g in ("PG-01_C4", "PG-01_C7", "PG-01_C6_PERSISTENCE")), True)
    check("technical_currentness_real_engine_CURRENT", accepted["technical_currentness"]["decision"], "CURRENT")
    canonical_receipt = deepcopy(accepted["technical_currentness"])
    digest = canonical_receipt.pop("receipt_sha256")
    check("technical_currentness_receipt_hash_intact", digest, canonical_sha256(canonical_receipt))
    check("technical_missing_port_BLOCK", SourcePreplanningReceiver(boundary, provider, lambda pin: fixture.store[pin["path"]]).consume(handoff, "S1")["state"], "BLOCK")
    def stale(packet):
        next(row for row in packet["binding"]["materials"] if row["material_id"] == "technical_artifact:standards_catalog")["current_digest"] = "0"*64
    stale_wrapper = SourcePreplanningReceiver(boundary, provider, lambda pin: fixture.store[pin["path"]],
                                              technical_currentness=currentness_fixture(fixture, stale))
    rejected = stale_wrapper.consume(handoff, "S1")
    check("technical_changed_pin_BLOCK", rejected["state"], "BLOCK")
    check("technical_changed_pin_receipt_BLOCK", rejected["receipt"]["verdict"], "BLOCK")
    lossy = deepcopy(accepted["material_projection"]); lossy.pop("sufficiency_report")
    check("preplanning_lossy_report_rejected", wrapper.consume(handoff, "S1", proposed_projection=lossy)["state"], "BLOCK")
    def absent_frame(expected, scope, closure):
        packet = provider(expected, scope, closure); packet["technical_framework"] = None
        return packet
    check("preplanning_missing_frame_BLOCK", SourcePreplanningReceiver(boundary, absent_frame, lambda pin: fixture.store[pin["path"]],
                                       technical_currentness=currentness_fixture(fixture)).consume(handoff, "S1")["state"], "BLOCK")
    from test_programming_pg01_exact_artifact_reader_v1 import exercise_git_source_reads
    source_readback = exercise_git_source_reads(boundary=boundary, expected=handoff, check=check)
    return {"evidence_tier": "REAL_LOCAL_SQL_BOUNDARY_SYNTHETIC_TECHNICAL_PORTS",
            "sample_receipt": accepted["receipt"], "operational_provider_verified": False, "source_readback": source_readback}


if __name__ == "__main__":
    unittest.main()
