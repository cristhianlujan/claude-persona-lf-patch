#!/usr/bin/env python3
"""Pruebas positivas y negativas del contrato de la etapa 1 (frases reales del propietario)."""
import copy
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(__file__))
from stage1_validator_v1 import validate  # noqa: E402


def base(**kw):
    d = {
        "schema_version": "LF_ROUTER_STAGE1_V1", "texto_original": "crear history de usuario", "es_operacion": True,
        "respuesta_directa": False, "sistema": "LF", "accion": "crear", "sujeto": "historias de usuario",
        "correcciones": [{"de": "history", "a": "historias"}],
        "formas_busqueda": ["historias de usuario", "user stories"], "ambiguo": False, "alternativas": [],
        "pregunta_usuario": None, "capability_hint": None, "downstream_execution_allowed": False,
    }
    d.update(kw)
    return d


class Stage1(unittest.TestCase):
    def test_direct_answer_no_search(self):
        r = validate(base(texto_original="¿qué hora es en Lima?", es_operacion=False, respuesta_directa=True, sistema=None,
                          accion=None, sujeto=None, correcciones=[], formas_busqueda=[]))
        self.assertEqual((r["valid"], r["next_step"]), (True, "DIRECT_ANSWER"), r)

    def test_operation_goes_to_level1_with_correction(self):
        r = validate(base())
        self.assertEqual((r["valid"], r["next_step"]), (True, "LEVEL1_SEARCH"), r)

    def test_spec_driving_is_valid_and_goes_to_level1(self):
        r = validate(base(texto_original="spec driving", sujeto="spec-driven", accion=None,
                          correcciones=[{"de": "spec driving", "a": "spec-driven"}],
                          formas_busqueda=["spec-driven", "specification driven"]))
        self.assertEqual((r["valid"], r["next_step"]), (True, "LEVEL1_SEARCH"), r)

    def test_ambiguous_asks_one_question(self):
        r = validate(base(texto_original="el perfil", ambiguo=True, alternativas=["perfil de producto", "perfil de UI"],
                          pregunta_usuario="¿Cuál perfil: producto o UI?"))
        self.assertEqual((r["valid"], r["next_step"]), (True, "ASK_USER"), r)

    def test_other_system_not_supported_yet(self):
        r = validate(base(sistema="SALY"))
        self.assertEqual((r["valid"], r["next_step"]), (True, "SYSTEM_NOT_SUPPORTED"), r)

    def test_typed_code_may_appear_in_forms(self):
        r = validate(base(texto_original="muéstrame ACT-0043", formas_busqueda=["ACT-0043"]))
        self.assertTrue(r["valid"], r)

    # negativos
    def expect(self, d, code):
        r = validate(d)
        self.assertFalse(r["valid"], r)
        self.assertIn(code, r["codes"], r)
        self.assertEqual(r["next_step"], "INVALID")

    def test_invented_code(self):
        self.expect(base(formas_busqueda=["ACT-0043"]), "INVENTED_ASSET_CODE")

    def test_downstream_true(self):
        self.expect(base(downstream_execution_allowed=True), "DOWNSTREAM_EXECUTION_MUST_BE_FALSE")

    def test_non_operation_without_direct_answer(self):
        self.expect(base(es_operacion=False, respuesta_directa=False, formas_busqueda=[]), "NON_OPERATION_REQUIRES_DIRECT_ANSWER")

    def test_non_operation_that_searches(self):
        self.expect(base(es_operacion=False, respuesta_directa=True), "NON_OPERATION_MUST_NOT_SEARCH")

    def test_operation_without_forms(self):
        self.expect(base(formas_busqueda=[]), "FORMAS_BUSQUEDA_REQUIRED")

    def test_too_many_forms(self):
        self.expect(base(formas_busqueda=list("abcde")), "TOO_MANY_FORMAS")

    def test_ambiguous_without_question(self):
        self.expect(base(ambiguo=True, alternativas=["a", "b"]), "AMBIGUOUS_REQUIRES_ALTERNATIVES_AND_ONE_QUESTION")

    def test_two_questions(self):
        self.expect(base(ambiguo=True, alternativas=["a", "b"], pregunta_usuario="¿A? ¿B? ¿C?"), "MORE_THAN_ONE_QUESTION")

    def test_alternatives_without_ambiguity(self):
        self.expect(base(alternativas=["a", "b"]), "ALTERNATIVES_WITHOUT_AMBIGUITY")

    def test_bad_hint(self):
        self.expect(base(capability_hint="regla crear"), "CAPABILITY_HINT_INVALID")

    def test_noop_correction(self):
        self.expect(base(correcciones=[{"de": "perfil", "a": "Perfil"}]), "CORRECCIONES_INVALID")

    def test_missing_original_and_schema(self):
        d = copy.deepcopy(base())
        d.pop("texto_original"); d["schema_version"] = "X"
        r = validate(d)
        self.assertIn("ORIGINAL_TEXT_REQUIRED", r["codes"]); self.assertIn("BAD_SCHEMA_VERSION", r["codes"])

    def test_not_an_object(self):
        self.assertEqual(validate([])["next_step"], "INVALID")


if __name__ == "__main__":
    unittest.main(verbosity=1)
