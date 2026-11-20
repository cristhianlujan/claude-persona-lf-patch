"""Pure offline contract tests. Never claim Router execution."""
import copy
import json
import pathlib
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from handler import hello_world  # noqa: E402

FIXTURE = json.loads((pathlib.Path(__file__).parent / "transport_fixture.json").read_text())


class SalYVisualProbeTests(unittest.TestCase):
    def test_hello_world_transport_roundtrip(self):
        response = hello_world(copy.deepcopy(FIXTURE))
        self.assertEqual(response["status"], "HELLO_WORLD_OFFLINE")
        self.assertEqual(response["mensaje"], "Hola mundo, ya llegué.")
        self.assertEqual(response["transporte_recibido"], FIXTURE["transport"])
        self.assertTrue(response["simulated"])
        self.assertFalse(response["runtime_invoked"])
        self.assertFalse(response["effect_authority"])
        self.assertEqual(len(response["transport_sha256"]), 64)

    def test_reject_actual_runtime(self):
        p = copy.deepcopy(FIXTURE)
        p["pilot_mode"] = "PRODUCTION"
        self.assertEqual(hello_world(p)["blocking_code"], "OFFLINE_CONTRACT_TEST_ONLY")

    def test_block_saly_disabled(self):
        p = copy.deepcopy(FIXTURE)
        p["transport"]["route_result"]["paso"] = "NEGOCIO_NO_HABILITADO"
        self.assertEqual(hello_world(p)["blocking_code"], "BUSINESS_NOT_ENABLED")

    def test_no_cross_brand(self):
        p = copy.deepcopy(FIXTURE)
        p["transport"]["stage1_payload"]["negocio_codigo"] = "LF"
        self.assertEqual(hello_world(p)["blocking_code"], "CROSS_BUSINESS_OR_UNKNOWN")

    def test_no_forced_wrong_profile(self):
        p = copy.deepcopy(FIXTURE)
        p["transport"]["semantic_result"]["selected_profile_code"] = "ACT-0051"
        self.assertEqual(hello_world(p)["blocking_code"], "WRONG_PROFILE")

    def test_no_incorrect_skill(self):
        p = copy.deepcopy(FIXTURE)
        p["transport"]["skill_selection"]["skill_code"] = "SCREEN_RULES_SNAPSHOT"
        self.assertEqual(hello_world(p)["blocking_code"], "WRONG_SKILL_SELECTION")

    def test_missing_handoff(self):
        p = copy.deepcopy(FIXTURE)
        del p["transport"]["router_profile_handoff"]
        self.assertEqual(hello_world(p)["blocking_code"], "TRANSPORT_INCOMPLETE_OR_INVALID")

    def test_no_fabricated_effect_authority(self):
        p = copy.deepcopy(FIXTURE)
        p["transport"]["gate2_derivation"]["effect_authority"] = True
        self.assertEqual(hello_world(p)["blocking_code"], "UNAUTHORIZED_EFFECT")

    def test_redact_secret(self):
        p = copy.deepcopy(FIXTURE)
        p["transport"]["request_context"]["access_token"] = "SECRET_TEST_ONLY"
        response = hello_world(p)
        self.assertEqual(response["transporte_recibido"]["request_context"]["access_token"], "[REDACTED]")
        self.assertNotIn("SECRET_TEST_ONLY", json.dumps(response))

    def test_requires_explicit_fixture(self):
        p = copy.deepcopy(FIXTURE)
        p["transport"]["fixture_only"] = False
        self.assertEqual(hello_world(p)["blocking_code"], "REAL_ROUTER_RECEIPT_REQUIRED")


if __name__ == "__main__":
    unittest.main()
