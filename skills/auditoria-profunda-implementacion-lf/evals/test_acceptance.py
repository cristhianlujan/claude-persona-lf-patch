"""Behavioral acceptance: inspect RAW artifacts then exercise actual consumers.

Expected obligations live here/in schemas, never inside the AST detector.
All execution is local, with fixtures, no DB write, no model/provider call.
"""
import copy
import importlib.util
import json
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path

PACK = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PACK / "scripts"))
sys.path.insert(0, str(PACK / "fixtures/implementation"))
from inspect_sources import contract_candidates, call_candidates, enum_candidates
from assess_contracts import assess_authorization, assess_step, data_strategy, snapshot, read_snapshot
import producer
import consumer
import judges


def policy_fixture():
    evaluation = {"context_pass": True, "spec_pass": True, "eval_pass": True,
                  "evidence_refs": ["fixture://SPEC-v1", "fixture://actual-test"]}
    policy = {"source_ref": "fixture://POLICY-CONTEXTUAL-v1", "version": "1",
              "sha256": "a" * 64, "current": True, "verified": True,
              "effect": "REQUEST_PROMOTION", "actor": "fixture-auditor", "object_id": "RULE-FIXTURE",
              "scope_sha256": "b" * 64, "requires_independence": False, "allow_contextual": True}
    evidence = {k: policy[k] for k in ("effect", "actor", "object_id", "scope_sha256")}
    evidence.update(independence_verified=False, isolated_context_verified=False,
                    independence_ref=None, material_blockers=[])
    return evaluation, policy, evidence


def sql_measurement():
    db = sqlite3.connect(":memory:")
    db.execute("CREATE TABLE payments(id INTEGER PRIMARY KEY, tenant TEXT, external_id TEXT, amount INTEGER)")
    db.executemany("INSERT INTO payments VALUES(?,?,?,?)",
                   ((i, "tenant-" + str(i % 5), "ext-" + str(i), i * 2) for i in range(20000)))
    query = (PACK / "fixtures/implementation/broken_query.sql").read_text()
    args = ("tenant-1", "ext-19201")
    def measure():
        ticks = [0]
        def progress():
            ticks[0] += 1
            return 0
        plan = [row[3] for row in db.execute("EXPLAIN QUERY PLAN " + query, args)]
        db.set_progress_handler(progress, 1)
        result = db.execute(query, args).fetchall()
        db.set_progress_handler(None, 0)
        return {"plan": plan, "vm_operations": ticks[0], "result": result}
    before = measure()
    db.executescript((PACK / "fixtures/implementation/correct_index.sql").read_text())
    after = measure()
    # Negative: composite tenant filter remains in place after optimization.
    wrong_tenant = db.execute(query, ("tenant-2", "ext-19201")).fetchall()
    db.close()
    return {"engine": "SQLite in-memory fixture; not PG performance", "rows": 20000,
            "before": before, "after": after, "wrong_tenant_result": wrong_tenant}


def freshness_measurement():
    """SQLite cache-table analogue, NOT execution of a PG materialized view."""
    db = sqlite3.connect(":memory:")
    db.execute("CREATE TABLE movements(tenant TEXT, amount INTEGER)")
    db.execute("INSERT INTO movements VALUES('tenant-1', 5)")
    db.execute("CREATE VIEW live_balance AS SELECT tenant, sum(amount) balance FROM movements GROUP BY tenant")
    db.execute("CREATE TABLE periodic_cache AS SELECT * FROM live_balance")
    before = db.execute("SELECT balance FROM periodic_cache WHERE tenant='tenant-1'").fetchone()[0]
    db.execute("INSERT INTO movements VALUES('tenant-1', 7)")
    live = db.execute("SELECT balance FROM live_balance WHERE tenant='tenant-1'").fetchone()[0]
    stale = db.execute("SELECT balance FROM periodic_cache WHERE tenant='tenant-1'").fetchone()[0]
    db.close()
    return {"engine": "SQLite cache-table analogue, not PG materialized view",
            "before": before, "source_after_change": live, "cached_after_change": stale}


class Acceptance(unittest.TestCase):
    def test_A01_spec_two_undeclared_required_fields_from_consumer(self):
        schema = json.loads((PACK / "fixtures/implementation/spec_broken.json").read_text())
        candidates = contract_candidates(schema, PACK / "fixtures/implementation/consumer.py", "consume", "packet")
        self.assertEqual({c["field"] for c in candidates}, {"c", "d"})
        with self.assertRaises(KeyError):
            consumer.consume({"a": 4, "b": 5})
        corrected = json.loads((PACK / "fixtures/implementation/spec_correct.json").read_text())
        self.assertEqual(contract_candidates(corrected, PACK / "fixtures/implementation/consumer.py", "consume", "packet"), [])
        self.assertEqual(consumer.consume(producer.correct_payload()), (9, "tenant-1", "revision-1"))

    def test_A02_parameter_full_origin_transport_consumer_chain(self):
        paths = [PACK / "fixtures/implementation" / f for f in ("producer.py", "consumer.py")]
        candidates = call_candidates(paths)
        wrong = next(c for c in candidates if c.get("caller") == "broken_transport")
        self.assertEqual(wrong["missing"], ["variable2"])
        self.assertEqual(wrong["available_assignments"]["variable2"], "data['c']")
        self.assertEqual(producer.origin()["c"], "tenant-1")
        with self.assertRaises(TypeError):
            producer.broken_transport()
        self.assertEqual(producer.correct_transport(), (4, "tenant-1"))
        self.assertFalse(any(c.get("caller") == "correct_transport" for c in candidates))

    def test_A03_missing_branch_from_state_contract(self):
        states = {"READY": "EXECUTE", "RETRY": "REQUEUE", "BLOCKED": "STOP"}
        hints = enum_candidates(PACK / "fixtures/implementation/producer.py", "broken_branch", "state", states)
        self.assertEqual(set(hints[0]["missing"]), {"RETRY", "BLOCKED"})
        self.assertIsNone(producer.broken_branch("RETRY"))
        for state, expected in states.items():
            self.assertEqual(producer.correct_branch(state), expected)
        with self.assertRaises(ValueError):
            producer.correct_branch("UNKNOWN")
        self.assertEqual(enum_candidates(PACK / "fixtures/implementation/producer.py", "correct_branch", "state", states), [])

    def test_A04_sql_index_measured_equivalence_and_negative_tenant(self):
        observed = sql_measurement()
        self.assertEqual(observed["before"]["result"], observed["after"]["result"])
        self.assertEqual(observed["after"]["result"], [(19201, 38402)])
        self.assertLess(observed["after"]["vm_operations"], observed["before"]["vm_operations"])
        self.assertTrue(any("SCAN" in p for p in observed["before"]["plan"]))
        self.assertTrue(any("SEARCH" in p for p in observed["after"]["plan"]))
        self.assertEqual(observed["wrong_tenant_result"], [])

    def test_A05_repeated_queries_snapshot_and_currentness_negatives(self):
        class Db:
            def __init__(self): self.calls = 0
            def read(self, identity):
                self.calls += 1
                return {"identity": identity, "revision": "r1", "amount": 5}
        a, b = Db(), Db()
        before = consumer.per_step_reads(a, "tenant-1/object-1")
        after = consumer.shared_snapshot_reads(b, "tenant-1/object-1")
        self.assertEqual(before, after)
        self.assertEqual((a.calls, b.calls), (5, 1))
        ids = dict(run_id="fixture-run", tenant="tenant-1", object_id="object-1", source_revision="r1", authority_sha256="a" * 64)
        s = snapshot(after[0], **ids)
        self.assertEqual(read_snapshot(s, **ids), after[0])
        for key in ids:
            changed = {**ids, key: "different"}
            with self.subTest(key=key), self.assertRaises(ValueError): read_snapshot(s, **changed)
        tampered = copy.deepcopy(s); tampered["body"]["payload"]["amount"] = 9
        with self.assertRaises(ValueError): read_snapshot(tampered, **ids)
        first = read_snapshot(s, **ids); first["amount"] = 99
        self.assertEqual(read_snapshot(s, **ids)["amount"], 5)

    def test_A06_independence_not_extra_veto_when_context_is_authorized(self):
        e, p, evidence = policy_fixture()
        self.assertFalse(judges.broken_independence_gate(e, p, evidence)["promotion_authorized"])
        result = assess_authorization(e, p, evidence)
        self.assertTrue(result["promotion_authorized"])
        self.assertEqual(result["independence_status"], "NOT_PROVEN")
        self.assertTrue(judges.correct_gate(e, p, evidence)["promotion_authorized"])

    def test_A07_valid_review_does_not_create_authority(self):
        e, p, evidence = policy_fixture(); p["verified"] = False
        self.assertTrue(judges.broken_authority_gate(e, p, evidence)["promotion_authorized"])
        self.assertFalse(assess_authorization(e, p, evidence)["promotion_authorized"])
        self.assertFalse(judges.correct_gate(e, p, evidence)["promotion_authorized"])

    def test_A08_input_contract_passes_incompatible_consumer(self):
        import jsonschema
        wrong = json.loads((PACK / "fixtures/implementation/input_broken.json").read_text())
        corrected = json.loads((PACK / "fixtures/implementation/input_correct.json").read_text())
        jsonschema.validate({"amount": "7"}, wrong)
        with self.assertRaises(ValueError): consumer.amount_consumer({"amount": "7"})
        jsonschema.validate({"amount": 7}, corrected)
        self.assertEqual(consumer.amount_consumer({"amount": 7}), 8)
        for value in (None, "7", -1, True):
            with self.subTest(value=value), self.assertRaises(jsonschema.ValidationError):
                jsonschema.validate({"amount": value}, corrected)

    def test_A09_step_context_lost_at_transport(self):
        required = ["trace", "location", "source_code", "spec"]
        wrong = assess_step(required, judges.broken_context_transport(), [], {})
        self.assertEqual(wrong["code"], "STEP_CONTEXT_INSUFFICIENT")
        self.assertEqual(set(wrong["missing_inputs"]), {"trace", "location", "source_code"})
        self.assertTrue(all(k in judges.origin_context() for k in wrong["missing_inputs"]))
        self.assertEqual(assess_step(required, judges.correct_context_transport(), [], {})["code"], "SUFFICIENT")

    def test_A10_superficial_output_despite_available_evidence(self):
        context = judges.origin_context()
        required = ["cause", "location", "impact", "correction", "test"]
        wrong = assess_step(context, context, required, producer.broken_comment(context))
        self.assertEqual(wrong["code"], "OUTPUT_NOT_ACTIONABLE")
        right = producer.correct_comment(context)
        self.assertEqual(assess_step(context, context, required, right)["code"], "SUFFICIENT")
        self.assertIn("variable2", right["correction"])

    def test_N01_immediate_freshness_never_periodic_materialization(self):
        observed = freshness_measurement()
        self.assertEqual(observed["before"], 5)
        self.assertEqual(observed["source_after_change"], 12)
        self.assertEqual(observed["cached_after_change"], 5)
        self.assertNotEqual(observed["source_after_change"], observed["cached_after_change"])
        common = dict(repeated_reads=5, stable_scope=True, invalidation_proven=True,
                      security_equivalent=True, equivalence_proven=True, measured_operations_saved=4)
        self.assertEqual(data_strategy(**common, immediate_freshness=True)["recommendation"], "KEEP_LIVE_READ")
        self.assertEqual(data_strategy(**common, immediate_freshness=False)["recommendation"], "SNAPSHOT_CANDIDATE")
        for key in ("stable_scope", "invalidation_proven", "security_equivalent", "equivalence_proven"):
            with self.subTest(key=key):
                self.assertEqual(data_strategy(**{**common, key: False}, immediate_freshness=False)["recommendation"], "MEASURE_OR_KEEP_CURRENT")

    def test_N02_context_isolated_same_model_can_satisfy_independence(self):
        e, p, evidence = policy_fixture(); p["requires_independence"] = True
        self.assertFalse(assess_authorization(e, p, evidence)["promotion_authorized"])
        evidence.update(independence_verified=True, isolated_context_verified=True,
                        independence_ref="fixture://verified-context-chain")
        self.assertTrue(assess_authorization(e, p, evidence)["promotion_authorized"])
        self.assertEqual(assess_authorization(e, p, evidence)["independence_status"], "PROVEN")

    def test_N03_stale_wrong_scope_and_material_fail_remain_blocked(self):
        for field in ("actor", "object_id", "effect", "scope_sha256"):
            e, p, evidence = policy_fixture(); evidence[field] = "wrong"
            with self.subTest(field=field): self.assertFalse(assess_authorization(e, p, evidence)["promotion_authorized"])
        e, p, evidence = policy_fixture(); p["current"] = False
        self.assertFalse(assess_authorization(e, p, evidence)["promotion_authorized"])
        e, p, evidence = policy_fixture(); e["eval_pass"] = False
        self.assertFalse(assess_authorization(e, p, evidence)["promotion_authorized"])
        e, p, evidence = policy_fixture(); evidence["material_blockers"] = ["failure"]
        self.assertFalse(assess_authorization(e, p, evidence)["promotion_authorized"])

    def test_N04_renamed_undocumented_consumer_fields_generalize(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "settlement.py"
            path.write_text('def finish(row):\n    return row["currency"], row["settlement_nonce"]\n', encoding="utf8")
            result = contract_candidates({"properties": {"amount": {}}, "required": ["amount"]}, path, "finish", "row")
            self.assertEqual({x["field"] for x in result}, {"currency", "settlement_nonce"})
            path.write_text('def optional(row):\n    return row.get("memo", "")\n', encoding="utf8")
            self.assertEqual(contract_candidates({"properties": {}, "required": []}, path, "optional", "row"), [])


if __name__ == "__main__":
    unittest.main()
