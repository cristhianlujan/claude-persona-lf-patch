#!/usr/bin/env python3
"""NIUBIZ candidate proposals: references-only contracts, NO canonical writes."""
import json
from pathlib import Path
import re
import unittest
import unicodedata

ROOT = Path(__file__).resolve().parents[3]
SPEC_PATH = ROOT / "docs/input-governance/NIUBIZ_THREE_CANDIDATE_RULES_20261118.json"
SPEC = json.loads(SPEC_PATH.read_text(encoding="utf-8"))
RULES = {r["code"]: r for r in SPEC["rules"]}
UNIQUE = RULES["REG_CLIENT_NIUBIZ_UNIQUE_EMAIL_001"]
RECEIPT = RULES["REG_CLIENT_PAYMENT_RECEIPT_REAL_EMAIL_001"]
BOUNCE = RULES["REG_CLIENT_NIUBIZ_GENERIC_BOUNCE_001"]
CONFIG_REFS = [
    {"scope": "PAGOS", "config_key": "NIUBIZ_EMAIL_TEMPLATE"},
    {"scope": "PAGOS", "config_key": "NIUBIZ_EMAIL_DOMAIN"},
]

# Test fixture, deliberately NOT copied into the rule or official config.
FAKE_CONFIG_A = {
    ("PAGOS", "NIUBIZ_EMAIL_TEMPLATE"): "{nombre}.{apellido}.id-{codigo}",
    ("PAGOS", "NIUBIZ_EMAIL_DOMAIN"): "example.test",
}
FAKE_CONFIG_B = {
    ("PAGOS", "NIUBIZ_EMAIL_TEMPLATE"): "{apellido}-{nombre}-{codigo}",
    ("PAGOS", "NIUBIZ_EMAIL_DOMAIN"): "sandbox.test",
}

def model_identifier(first_name, surname, code, refs, fake_config):
    """Pure test model, not production runtime or Niubiz sandbox evidence."""
    if not re.fullmatch(r"[a-z][a-z0-9]*", code or ""):
        raise ValueError("MISSING_OR_INVALID_STABLE_CLIENT_CODE")
    def normalize(value):
        value = unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode().lower()
        value = re.sub(r"\s+", "", value)
        if re.fullmatch(r"[a-z]+", value) is None:
            raise ValueError("INVALID_NAME")
        return value
    if refs != CONFIG_REFS:
        raise ValueError("UNEXPECTED_CONFIG_REFERENCE")
    template = fake_config.get(("PAGOS", "NIUBIZ_EMAIL_TEMPLATE"))
    domain = fake_config.get(("PAGOS", "NIUBIZ_EMAIL_DOMAIN"))
    if not template or not domain:
        raise ValueError("MISSING_CONFIG_VALUE")
    return template.format(nombre=normalize(first_name), apellido=normalize(surname), codigo=code) + "@" + domain


class NiubizCandidateSpecTests(unittest.TestCase):
    def test_01_three_rule_codes(self):
        self.assertEqual(set(RULES), {
            "REG_CLIENT_NIUBIZ_UNIQUE_EMAIL_001",
            "REG_CLIENT_PAYMENT_RECEIPT_REAL_EMAIL_001",
            "REG_CLIENT_NIUBIZ_GENERIC_BOUNCE_001",
        })
        self.assertEqual(len(SPEC["rules"]), 3)

    def test_02_catalog_convention_and_no_overwrite(self):
        for code in RULES:
            self.assertRegex(code, r"^REG_CLIENT_[A-Z0-9_]+_001$")
        self.assertNotIn("REG_CLIENT_INSTALLMENT_COLLECTION_FAILURE_001", RULES)

    def test_03_baseline_and_target(self):
        self.assertEqual(SPEC["source"]["canonical_rules_before"], 579)
        self.assertEqual(SPEC["source"]["config_rows_before"], 40)
        self.assertEqual(SPEC["target"]["canonical_rules_after"], 582)
        self.assertEqual(SPEC["source"]["migration_version"], "20261118214500")

    def test_04_create_patch_shape(self):
        allowed = {"categoria", "titulo", "descripcion", "razon", "valor_config", "es_transversal", "origen"}
        for rule in RULES.values():
            self.assertEqual(rule["change_kind"], "CREATE")
            self.assertEqual(set(rule["changes"]), allowed)
            self.assertEqual(rule["changes"]["categoria"], "pago")
            self.assertGreaterEqual(len(rule["changes"]["titulo"]), 8)
            self.assertGreaterEqual(len(rule["changes"]["descripcion"]), 8)
            self.assertIs(rule["changes"]["es_transversal"], False)
            self.assertNotIn("estado", rule["changes"])

    def test_05_candidate_only(self):
        self.assertEqual(SPEC["target"]["all_new_rules_state"], "CANDIDATO")
        self.assertIs(SPEC["target"]["promotion_authorized"], False)
        for rule in RULES.values():
            self.assertIs(rule["changes"]["valor_config"]["production_authorized"], False)

    def test_06_every_rule_uses_scope_key_references(self):
        for rule in RULES.values():
            self.assertEqual(rule["changes"]["valor_config"]["niubiz_email_config_refs"], CONFIG_REFS)

    def test_07_no_copy_of_config_values_in_valor_config(self):
        for rule in RULES.values():
            cfg = rule["changes"]["valor_config"]
            self.assertNotIn("expected_domain", cfg)
            self.assertNotIn("expected_template", cfg)
            self.assertNotIn("parameter_refs", cfg)
            self.assertNotIn("config_value", cfg)
            dump = json.dumps(cfg)
            self.assertNotIn("gmail.com", dump)
            self.assertNotIn("lf-{codigo}", dump)

    def test_08_descriptions_name_location_and_both_keys(self):
        for rule in RULES.values():
            desc = rule["changes"]["descripcion"]
            self.assertIn("public.lf_global_config", desc)
            self.assertIn("NIUBIZ_EMAIL_TEMPLATE", desc)
            self.assertIn("NIUBIZ_EMAIL_DOMAIN", desc)
            self.assertIn("PAGOS", desc)

    def test_09_no_example_unmarked_or_literal_in_rule_text(self):
        for rule in RULES.values():
            desc = rule["changes"]["descripcion"]
            self.assertNotIn("gmail.com", desc)
            self.assertNotIn("lf-codigo", desc)
            self.assertNotIn("lf-{codigo}", desc)
        self.assertIn("scope/config_key", UNIQUE["changes"]["descripcion"])

    def test_10_test_fixture_normalization(self):
        email = model_identifier("Álvaro", "Núñez", "a7b9", CONFIG_REFS, FAKE_CONFIG_A)
        self.assertEqual(email, "alvaro.nunez.id-a7b9@example.test")

    def test_11_dynamic_config_reads_change_result(self):
        a = model_identifier("Ana", "Pérez", "ab12", CONFIG_REFS, FAKE_CONFIG_A)
        b = model_identifier("Ana", "Pérez", "ab12", CONFIG_REFS, FAKE_CONFIG_B)
        self.assertNotEqual(a, b)
        self.assertTrue(a.endswith("@example.test"))
        self.assertTrue(b.endswith("@sandbox.test"))

    def test_12_same_client_stable_different_client_unique(self):
        a = model_identifier("Ana", "Pérez", "ab12", CONFIG_REFS, FAKE_CONFIG_A)
        self.assertEqual(a, model_identifier("Ana", "Pérez", "ab12", CONFIG_REFS, FAKE_CONFIG_A))
        self.assertNotEqual(a, model_identifier("Ana", "Pérez", "ab13", CONFIG_REFS, FAKE_CONFIG_A))

    def test_13_invalid_code_blocks(self):
        for bad in ("", "1234", "1abc", "a-b", "A12"):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                model_identifier("María", "López", bad, CONFIG_REFS, FAKE_CONFIG_A)

    def test_14_invalid_name_blocks(self):
        for bad in ("", "123", "---"):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                model_identifier(bad, "López", "abc1", CONFIG_REFS, FAKE_CONFIG_A)

    def test_15_missing_config_value_blocks(self):
        for missing in (("PAGOS", "NIUBIZ_EMAIL_TEMPLATE"), ("PAGOS", "NIUBIZ_EMAIL_DOMAIN")):
            config = dict(FAKE_CONFIG_A)
            del config[missing]
            with self.subTest(missing=missing), self.assertRaisesRegex(ValueError, "MISSING_CONFIG_VALUE"):
                model_identifier("Ana", "Pérez", "abc1", CONFIG_REFS, config)

    def test_16_receipt_customer_real_email_only(self):
        v = RECEIPT["changes"]["valor_config"]
        self.assertEqual(v["customer_receipt_destination"], "REAL_EMAIL_ONLY")
        self.assertEqual(v["receipt_email_source"], "CUSTOMER_REAL_REGISTERED_VERIFIED_EMAIL")
        self.assertIs(v["provider_technical_email_not_receipt_destination"], True)
        self.assertNotEqual(v["provider_identifier_source"], v["receipt_email_source"])

    def test_17_receipt_confirmed_outcome_only(self):
        v = RECEIPT["changes"]["valor_config"]
        self.assertEqual(v["receipt_trigger"], "PAYMENT_CONFIRMED_AUTHORITATIVE")
        self.assertEqual(v["on_missing_real_email"], "TRACEABLE_INCIDENT_NO_GENERIC_FALLBACK")

    def test_18_bounce_accepted_not_payment_confirmation(self):
        v = BOUNCE["changes"]["valor_config"]
        self.assertEqual(v["generic_email_bounce_policy"], "ACCEPT_AFTER_PROVIDER_ACCEPTANCE")
        self.assertEqual(v["provider_format_rejection"], "BLOCK_AND_TRACE")
        self.assertIs(v["technical_email_mailbox_required"], False)
        self.assertIs(v["bounce_is_payment_rejection"], False)
        self.assertIs(v["bounce_is_payment_confirmation"], False)

    def test_19_niubiz_hyphen_still_not_tested(self):
        self.assertEqual(SPEC["pending_provider_validation"]["status"], "NOT_TESTED")
        self.assertEqual(UNIQUE["changes"]["valor_config"]["hyphen_niubiz_sandbox"], "NOT_TESTED")
        self.assertEqual(BOUNCE["changes"]["valor_config"]["hyphen_niubiz_sandbox"], "NOT_TESTED")
        self.assertNotIn('"PASS"', SPEC_PATH.read_text(encoding="utf-8"))

    def test_20_no_fake_v2_run_train_or_promote(self):
        gov = SPEC["governance"]
        self.assertEqual(gov["decision_user"], "Cristhian Lujan")
        self.assertEqual(gov["decision_type"], "ONE_OWNER_DECISION_V2_PER_RULE")
        self.assertTrue(gov["no_fabricated_run_or_pass"])
        self.assertTrue(gov["no_direct_insert_into_lf_ops_reglas"])
        self.assertTrue(gov["require_real_begin_rollback_and_independent_readback"])
        self.assertTrue(gov["no_production_activation"])
        self.assertTrue(gov["requires_rule_contract_level_train_evidence_per_rule"])
        self.assertTrue(SPEC["blocked_dependency"].startswith("RESOLVED_PR_4097_MERGED"))
        self.assertIn("NO_CANONICAL_WRITES", SPEC["status"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
