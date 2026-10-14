"""Positive and adversarial unit tests for six generic checkpoint-close judges."""
import copy
import unittest

from checkpoint_step_judges_v1 import STEPS, validate_step

SHA = "a" * 64
PROOF = "b" * 64
RECEIPT = "c" * 64


def fixture():
    authority = {
        "source_kind": "CANONICAL_INDEPENDENT_READBACK",
        "operation_code": "CIERRE_CHECKPOINT_INGENIERIA_LF",
        "target_type": "ENGINEERING_CHECKPOINT",
        "target_count": 1,
        "target_code": "PLAN/UNIT/CP",
        "execution_id": "EXEC-VALID-SIGNED",
        "execution_state": "IN_PROGRESS",
        "idempotency_key": "idem-1",
        "request_sha256": SHA,
        "runtime_authenticated": True,
        "operation_lifecycle": "OP_OPERATIONAL",
        "operation_status": "SANDBOX_ACTIVE",
        "route_write_allowed": True,
        "router": "ACT-0001",
        "router_receipt": "server:router:rec123",
        "authority_applicable": True,
        "authority_valid": True,
        "route_action": "CHECKPOINT_CLOSE",
        "route_status": "READY_TO_EXECUTE",
        "operation_revision_sha256": SHA,
        "provider_ref": "programacion.fn_provider_v1(text,text,text)",
        "provider_binding_state": "ACTIVE",
        "provider_proof_status": "PASS",
        "source_current": True,
        "assertion_contract_sha256": SHA,
        "pass_when": {"source_current": True, "valid_family_count": 5},
        "observed": {"source_current": True, "valid_family_count": 5,
                     "sample_verdict": "PASS_CP2_MUESTRA"},
        "proof_sha256": PROOF,
        "assertion_receipt_sha256": RECEIPT,
        "assertion_passed": True,
        "assertion_contract_current": True,
        "receipt_is_canonical": True,
        "from_status": "PENDING",
        "checkpoint_status": "DONE",
        "material_done_guard_passed": True,
        "authorized_checkpoint_count": 1,
        "effect_guard_receipt": "effect:receipt:123",
        "effect_state": "SUCCEEDED",
        "next_checkpoint": "NEXT_CP",
        "rollback_test_passed": True,
        "unintended_effect_count": 0,
        "readback_source": "CANONICAL_DB",
    }
    evidence = {
        "init_execution": {"execution_id": "EXEC-VALID-SIGNED",
                           "target_code": "PLAN/UNIT/CP"},
        "router_authority": {"router_receipt": "server:router:rec123",
                             "operation_revision_sha256": SHA},
        "provider_readback": {
            "provider_ref": "programacion.fn_provider_v1(text,text,text)",
            "source_current": True, "proof_sha256": PROOF},
        "material_assertion": {"assertion_contract_sha256": SHA,
                               "assertion_receipt_sha256": RECEIPT},
        "checkpoint_transition": {"from_status": "PENDING", "to_status": "DONE",
                                  "effect_guard_receipt": "effect:receipt:123"},
        "independent_readback": {"checkpoint_status": "DONE",
                                 "receipt_sha": RECEIPT,
                                 "next_checkpoint": "NEXT_CP"}
    }
    return authority, evidence


class CheckpointJudgesTests(unittest.TestCase):
    def test_six_independent_positive_judges(self):
        auth, ev = fixture()
        self.assertEqual(len(STEPS), 6)
        for step in STEPS:
            with self.subTest(step=step):
                result = validate_step(step, ev[step], auth)
                self.assertTrue(result["valid"])
                self.assertEqual(result["server_assertions"],
                                 ["checkpoint_close_" + step + "_verified"])

    def test_malformed_steps_or_input_rejected(self):
        a, e = fixture()
        for step, evidence, auth in [
            ("alien_step", {}, a),
            ("init_execution", "not an object", a),
            ("init_execution", e["init_execution"], "user claimed authority"),
        ]:
            with self.assertRaises(ValueError):
                validate_step(step, evidence, auth)

    def test_all_steps_fail_closed_on_untrusted_authority(self):
        a, e = fixture()
        for step in STEPS:
            for key, value in (
                ("source_kind", "USER_SUPPLIED"),
                ("target_count", 2),
                ("target_type", "DB"),
                ("operation_code", "OTHER_OPERATION"),
                ("route_write_allowed", False),
                ("operation_lifecycle", "OP_CANDIDATE"),
                ("runtime_authenticated", False),
            ):
                with self.subTest(step=step, key=key):
                    b = copy.deepcopy(a)
                    b[key] = value
                    # Authentication is explicitly checked by init_execution;
                    # other steps depend on the authenticated runner's snapshot.
                    if key == "runtime_authenticated" and step != "init_execution":
                        continue
                    with self.assertRaises(ValueError):
                        validate_step(step, e[step], b)

    def test_init_execution_rejects_cross_target(self):
        a, e = fixture()
        e["init_execution"]["target_code"] = "OTHER/UNIT/CP"
        with self.assertRaisesRegex(ValueError, "TARGET"):
            validate_step("init_execution", e["init_execution"], a)

    def test_router_authority_rejects_stale_revision(self):
        a, e = fixture()
        e["router_authority"]["operation_revision_sha256"] = "f" * 64
        with self.assertRaisesRegex(ValueError, "REVISION_DRIFT"):
            validate_step("router_authority", e["router_authority"], a)

    def test_provider_missing_or_stale(self):
        a, e = fixture()
        for field, value in (("provider_binding_state", "CANDIDATE"),
                             ("source_current", False),
                             ("provider_proof_status", "FAIL")):
            b = copy.deepcopy(a)
            b[field] = value
            with self.subTest(field=field):
                with self.assertRaises(ValueError):
                    validate_step("provider_readback", e["provider_readback"], b)

    def test_provider_expected_semantics_cannot_be_skipped(self):
        a, e = fixture()
        a["observed"]["valid_family_count"] = 4
        with self.assertRaisesRegex(ValueError, "OBSERVED_SEMANTICS"):
            validate_step("provider_readback", e["provider_readback"], a)

    def test_material_assertion_rejects_forged_receipt(self):
        a, e = fixture()
        e["material_assertion"]["assertion_receipt_sha256"] = "f" * 64
        with self.assertRaisesRegex(ValueError, "RECEIPT"):
            validate_step("material_assertion", e["material_assertion"], a)

    def test_material_assertion_rejects_stale_contract(self):
        a, e = fixture()
        a["assertion_contract_current"] = False
        with self.assertRaisesRegex(ValueError, "STALE_CONTRACT"):
            validate_step("material_assertion", e["material_assertion"], a)

    def test_checkpoint_transition_rejects_other_checkpoint_mutation(self):
        a, e = fixture()
        a["authorized_checkpoint_count"] = 2
        with self.assertRaisesRegex(ValueError, "OTHER_CHECKPOINT"):
            validate_step("checkpoint_transition", e["checkpoint_transition"], a)

    def test_checkpoint_transition_rejects_missing_guard(self):
        a, e = fixture()
        a["material_done_guard_passed"] = False
        with self.assertRaisesRegex(ValueError, "DONE_GUARD"):
            validate_step("checkpoint_transition", e["checkpoint_transition"], a)

    def test_readback_rejects_fake_done_or_unintended_effects(self):
        a, e = fixture()
        for field, value in (("readback_source", "CLIENT"),
                             ("checkpoint_status", "PENDING"),
                             ("rollback_test_passed", False),
                             ("unintended_effect_count", 1)):
            b = copy.deepcopy(a)
            b[field] = value
            with self.subTest(field=field):
                with self.assertRaises(ValueError):
                    validate_step("independent_readback", e["independent_readback"], b)


if __name__ == "__main__":
    unittest.main(verbosity=2)
