#!/usr/bin/env python3
"""Positive and negative source checks for LF Stage1 V2; no live Router call."""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(__file__))
from stage1_context_validator_v2 import normalize_to_v1, validate


def base(**patch):
    out = {
        "schema_version": "LF_ROUTER_STAGE1_V2",
        "texto_original": "Consultar el estado de una oferta en LF",
        "es_operacion": True, "respuesta_directa": False,
        "accion": "consultar", "sujeto": "oferta",
        "correcciones": [], "formas_busqueda": ["estado oferta"],
        "ambiguo": False, "alternativas": [], "pregunta_usuario": None,
        "capability_hint": None, "downstream_execution_allowed": False,
        "canal_candidato": "OPERACIONES", "negocio_codigo": "LF",
        "negocios_afectados": [], "ruta_transversal": None,
        "razon_seleccion": "Es una consulta de datos vigentes",
        "alcance": {"target_type": "OFERTA", "target_hint": "la oferta del usuario",
                    "resolution_status": "UNRESOLVED"},
    }
    out.update(patch)
    return out


class Stage1V2(unittest.TestCase):
    def assert_block(self, case, code):
        response = validate(case)
        self.assertFalse(response["valid"], response)
        self.assertEqual(response["next_step"], "INVALID", response)
        self.assertIn(code, response["codes"], response)

    def test_ops_lf_offer_candidate(self):
        result = validate(base())
        self.assertTrue(result["valid"], result)
        self.assertEqual(result["next_step"], "LEVEL1_SEARCH")
        self.assertEqual(result["canal_candidato"], "OPERACIONES")
        self.assertFalse(result["downstream_execution_allowed"])

    def test_product_definition(self):
        result = validate(base(canal_candidato="PRODUCTO", accion="definir",
                               razon_seleccion="Cambiar definición canónica"))
        self.assertTrue(result["valid"], result)

    def test_programming_lifecycle(self):
        result = validate(base(canal_candidato="PROGRAMACION",
                               razon_seleccion="Desarrollo técnico autorizado"))
        self.assertTrue(result["valid"], result)

    def test_unscoped_operation(self):
        result = validate(base(alcance=None))
        self.assertTrue(result["valid"], result)

    def test_saly_recognized_but_not_dispatched(self):
        result = validate(base(negocio_codigo="SALY"))
        self.assertTrue(result["valid"], result)
        self.assertEqual(result["next_step"], "SYSTEM_NOT_SUPPORTED")

    def test_new_business_not_fabricated(self):
        self.assert_block(base(negocio_codigo="UNKNOWN_BIZ"),
                          "NEGOCIO_NO_REGISTRADO_EN_V2")

    def test_future_registered_business_does_not_need_new_channel(self):
        future = base(negocio_codigo="NEWBIZ")
        unregistered = validate(future)
        self.assertFalse(unregistered["valid"], unregistered)
        self.assertIn("NEGOCIO_NO_REGISTRADO_EN_V2", unregistered["codes"])
        registered = validate(future, registered_businesses={"LF", "SALY", "NEWBIZ"})
        self.assertTrue(registered["valid"], registered)
        self.assertEqual(registered["next_step"], "SYSTEM_NOT_SUPPORTED")

    def test_invalid_registry_fails_closed(self):
        out = validate(base(), registered_businesses={"LF", "not a business"})
        self.assertFalse(out["valid"], out)
        self.assertIn("CATALOGO_NEGOCIOS_INVALIDO", out["codes"])

    def test_legacy_v1_shape_is_preserved(self):
        normalized = normalize_to_v1(base())
        self.assertEqual(normalized["schema_version"], "LF_ROUTER_STAGE1_V1")
        self.assertNotIn("sistema", base())
        self.assertEqual(normalized["sistema"], "LF")
        for unexpected in ("canal_candidato", "negocio_codigo", "alcance",
                           "ruta_transversal", "negocios_afectados"):
            self.assertNotIn(unexpected, normalized)

    def test_direct_profile_update_no_fourth_channel(self):
        x = base(texto_original="Actualizar el perfil UI Architect",
                 accion="actualizar", sujeto="perfil", formas_busqueda=["perfil UI Architect"],
                 canal_candidato=None, ruta_transversal="GESTION_ACTIVOS_IA")
        self.assertTrue(validate(x)["valid"], validate(x))

    def test_only_three_channels(self):
        self.assert_block(base(canal_candidato="SISTEMA"), "CANAL_NO_RECONOCIDO")
        self.assert_block(base(canal_candidato="PERFILES_SKILLS"),
                          "CANAL_NO_RECONOCIDO")

    def test_business_is_required_for_single_business_operation(self):
        self.assert_block(base(negocio_codigo=None), "NEGOCIO_REQUERIDO_EN_V2")

    def test_legacy_sistema_field_is_rejected(self):
        self.assert_block(base(sistema="LF"), "CAMPO_LEGACY_SISTEMA_NO_PERMITIDO_EN_V2")

    def test_multibusiness_is_explicit_and_does_not_auto_dispatch(self):
        x = base(negocio_codigo=None,
                 negocios_afectados=["LF", "SALY"],
                 canal_candidato="PRODUCTO", alcance=None)
        result = validate(x)
        self.assertTrue(result["valid"], result)
        self.assertEqual(result["next_step"], "SYSTEM_NOT_SUPPORTED")
        self.assertFalse(result["downstream_execution_allowed"])

    def test_duplicate_business_rejected(self):
        self.assert_block(base(negocio_codigo=None,
                               negocios_afectados=["LF", "LF"]), "NEGOCIOS_AFECTADOS_INVALIDOS")

    def test_scope_does_not_claim_verified_ref(self):
        self.assert_block(base(alcance={"target_type": "EMPRESA",
                                      "target_ref": "company-123",
                                      "resolution_status": "RESOLVED"}),
                          "ALCANCE_NO_PUEDE_CERTIFICARSE_EN_STAGE1")

    def test_scope_not_fixed_enum(self):
        result = validate(base(alcance={"target_type": "CAMPAÑA",
                                        "target_hint": "comercial"}))
        self.assertFalse(result["valid"])  # Typed code must be ASCII, not a fixed list.
        result = validate(base(alcance={"target_type": "CAMPANA_2026",
                                        "target_hint": "campaña comercial"}))
        self.assertTrue(result["valid"], result)

    def test_scope_does_not_grant_permission(self):
        self.assert_block(base(alcance={"target_type": "CLIENTE",
                                      "target_hint": "DNI",
                                      "verified": True}),
                          "ALCANCE_NO_PUEDE_CERTIFICARSE_EN_STAGE1")

    def test_no_effect_escalation(self):
        self.assert_block(base(downstream_execution_allowed=True),
                          "DOWNSTREAM_EXECUTION_MUST_BE_FALSE")

    def test_ambiguous_v1_contract_still_applies(self):
        result = validate(base(ambiguo=True, alternativas=["LF", "SALY"],
                               pregunta_usuario="¿Qué negocio?"))
        self.assertTrue(result["valid"], result)
        self.assertEqual(result["next_step"], "ASK_USER")

    def test_non_operation_must_be_scope_free(self):
        x = base(texto_original="¿Qué significa canal?", es_operacion=False,
                 respuesta_directa=True, accion=None, sujeto=None,
                 formas_busqueda=[], canal_candidato=None, negocio_codigo=None,
                 alcance=None, razon_seleccion=None)
        self.assertEqual(validate(x)["next_step"], "DIRECT_ANSWER")
        self.assert_block({**x, "alcance": {"target_type": "REGLA"}},
                          "NO_OPERACION_NO_TIENE_ALCANCE")

    def test_transversal_with_channel_is_invalid(self):
        self.assert_block(base(ruta_transversal="GESTION_ACTIVOS_IA"),
                          "RUTA_TRANSVERSAL_INVALIDA")


if __name__ == "__main__":
    unittest.main(verbosity=2)
