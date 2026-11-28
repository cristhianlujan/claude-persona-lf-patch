"""F4 casos sintéticos N01-N04 (deben bloquear) y P01-P04 (deben pasar).
Sintéticos: no representan el prompt real del pedido 23 ni prescriben diseño."""
import copy
import unittest

from art_direction_preflight_v1 import (ArtBlocked, blocking, inspect_dimension_requirements,
                                        inspect_instruction_conflicts, preflight,
                                        verify_compiled_coverage, verify_prompt_integrity)
from creative_positive_gate_v1 import CreativeProcessBlocked, prepare_positive_review
from test_creative_positive_gate_v1 import fixture


def with_component_text(text):
    plan, dec = fixture()
    plan["components"][0]["instruction"] = text
    return plan, dec


def with_literal(extra, quote):
    plan, dec = fixture()
    plan["literal_request"] += " " + extra
    plan["requirements"].append({"id": "R3", "source": "REQUEST", "quote": quote})
    plan["direction"]["scene"]["requirements"] = ["R1", "R3"]
    return plan, dec


class F4Cases(unittest.TestCase):
    def test_n01_logo_contradiction_blocks(self):
        plan, _ = with_component_text(
            "Dibujar logotipos inventados para BBVA y Finanty. No inventar logotipos de terceros")
        with self.assertRaises(ArtBlocked) as cm:
            preflight(plan)
        self.assertEqual(str(cm.exception), "INSTRUCTION_CONFLICT_LOGO")

    def test_n02_button_attribute_dropped_blocks(self):
        plan, dec = with_literal("Botón sólido y completo.", "Botón sólido y completo")
        with self.assertRaises(CreativeProcessBlocked) as cm:
            prepare_positive_review(plan, dec)
        self.assertEqual(str(cm.exception), "CREATIVE_F4_REQUIREMENT_ATTRIBUTE_DROPPED")

    def test_n03_dimensions_altered_blocks(self):
        plan, dec = with_literal("Pantalla 390 × 844 px exactos.", "390 × 844")
        plan["direction"]["scene"]["instruction"] = "Generar pantalla de 400 × 900 px con relación clara"
        with self.assertRaises(CreativeProcessBlocked) as cm:
            prepare_positive_review(plan, dec)
        self.assertEqual(str(cm.exception), "CREATIVE_F4_DIMENSIONS_ALTERED")

    def test_n04_generic_direction_blocks(self):
        plan, _ = with_component_text("Moderno y premium")
        with self.assertRaises(ArtBlocked) as cm:
            preflight(plan)
        self.assertEqual(str(cm.exception), "INSTRUCTION_ONLY_GENERIC")

    def test_p01_brands_as_text_passes(self):
        plan, _ = with_component_text(
            "Mostrar BBVA y Finanty como texto. No dibujar ni inventar sus logotipos")
        self.assertEqual(preflight(plan)["status"], "STRUCTURAL_PASS_SEMANTIC_PENDING")

    def test_p02_button_attribute_kept_passes(self):
        plan, dec = with_literal("Botón sólido y completo.", "Botón sólido y completo")
        plan["direction"]["scene"]["instruction"] = "Mostrar botón sólido y completo con el texto solicitado"
        out = prepare_positive_review(plan, dec)
        self.assertEqual(out["qa_independent"], "NOT_EVALUATED")

    def test_p03_dimensions_kept_passes_with_warning(self):
        plan, dec = with_literal("Pantalla 390 × 844 px exactos.", "390 × 844")
        plan["direction"]["scene"]["instruction"] = "Pantalla de 390 × 844 px con relación clara"
        out = prepare_positive_review(plan, dec)
        self.assertEqual(out["status"], "CREATIVE_REVIEW_PREPARED_SEMANTIC_QA_PENDING")
        found = inspect_dimension_requirements(plan["literal_request"], out["prompt_review"])
        self.assertEqual([f[0] for f in found], ["WARNING"])
        self.assertEqual(found[0][1], "DIMENSIONS_NOT_VERIFIABLE_BEFORE_RENDER")

    def test_p04_concrete_direction_passes(self):
        plan, _ = with_component_text(
            "Dar mayor peso visual a la cuota mensual que al total y situar la carta antes del botón")
        self.assertEqual(preflight(plan)["status"], "STRUCTURAL_PASS_SEMANTIC_PENDING")

    # --- contraejemplos de la revisión independiente de GPT (PR #4843) ---
    def test_fp01_official_logo_with_third_party_ban_passes(self):
        plan, _ = with_component_text("Usar el logo oficial de Saly. No inventar logotipos de terceros")
        self.assertEqual(preflight(plan)["status"], "STRUCTURAL_PASS_SEMANTIC_PENDING")

    def test_fp03_equivalent_wording_passes(self):
        plan, dec = with_literal("Botón sólido y completo.", "Botón sólido y completo")
        plan["direction"]["scene"]["instruction"] = "Botón de relleno uniforme que ocupa todo el ancho, sin recortes"
        self.assertEqual(prepare_positive_review(plan, dec)["qa_independent"], "NOT_EVALUATED")

    def test_fn01_external_brand_colors_vs_logo_ban_is_warning_not_block(self):
        found = inspect_instruction_conflicts([
            "Representar las marcas externas en sus colores corporativos",
            "No inventar logotipos de terceros"])
        self.assertEqual([f[0] for f in found], ["WARNING"])

    def test_fn02_attribute_on_wrong_subject_blocks(self):
        plan, dec = with_literal("Botón sólido y completo.", "Botón sólido y completo")
        plan["direction"]["scene"]["instruction"] = "Botón transparente. Mostrar una tarjeta sólida y completa"
        with self.assertRaises(CreativeProcessBlocked) as cm:
            prepare_positive_review(plan, dec)
        self.assertEqual(str(cm.exception), "CREATIVE_F4_REQUIREMENT_ATTRIBUTE_DROPPED")

    def test_fn03_generic_run_of_words_blocks(self):
        plan, _ = with_component_text(
            "Diseñar una interfaz premium, moderna, elegante y con un impacto visual espectacular")
        with self.assertRaises(ArtBlocked) as cm:
            preflight(plan)
        self.assertEqual(str(cm.exception), "INSTRUCTION_ONLY_GENERIC")

    def test_dimension_target_vs_reference(self):
        found = inspect_dimension_requirements(
            "Pantalla 390 × 844 px.", "Generar una pantalla de 400 × 900 px. Referencia original: 390 × 844 px.")
        self.assertEqual(blocking(found)[0][1], "DIMENSIONS_ALTERED")
        ok = inspect_dimension_requirements(
            "Pantalla 390 × 844 px.", "Pantalla de 390 × 844 px. Referencia anterior: 400 × 900 px.")
        self.assertEqual(blocking(ok), [])

    def test_pf06_warning_is_logged_from_real_path(self):
        plan, dec = with_literal("Pantalla 390 × 844 px exactos.", "390 × 844")
        plan["direction"]["scene"]["instruction"] = "Pantalla de 390 × 844 px con relación clara"
        with self.assertLogs("creative_positive_gate", level="WARNING") as logs:
            prepare_positive_review(plan, dec)
        self.assertTrue(any("DIMENSIONS_NOT_VERIFIABLE_BEFORE_RENDER" in l for l in logs.output))

    def test_diagnostics_do_not_alter_plan_hash_or_add_keys(self):
        plan, dec = fixture()
        before = copy.deepcopy(plan)
        out = prepare_positive_review(plan, dec)
        self.assertEqual(plan, before)
        self.assertNotIn("warnings", out)

    def test_prompt_integrity_function(self):
        self.assertEqual(verify_prompt_integrity("a", "0" * 64)[0][1], "PROMPT_HASH_MISMATCH")
        self.assertEqual(verify_prompt_integrity("a", "ca978112ca1bbdcafac231b39a23dc4da786eff8147c4e72b9807785afee48bb"), [])


if __name__ == "__main__":
    unittest.main()
