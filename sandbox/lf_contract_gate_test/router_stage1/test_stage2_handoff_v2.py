#!/usr/bin/env python3
"""Tests for safe Stage1 V2 -> Stage2 legacy LF route handoff."""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(__file__))
from stage2_handoff_v2 import prepare_handoff


def case(**kwargs):
    d = {
        "schema_version": "LF_ROUTER_STAGE1_V2",
        "texto_original": "Consultar mi oferta en LF",
        "es_operacion": True,
        "respuesta_directa": False,
        "accion": "consultar", "sujeto": "oferta",
        "correcciones": [], "formas_busqueda": ["oferta"],
        "ambiguo": False, "alternativas": [], "pregunta_usuario": None,
        "capability_hint": "ESTADO_EN_CURSO",
        "downstream_execution_allowed": False,
        "canal_candidato": "OPERACIONES", "negocio_codigo": "LF",
        "negocios_afectados": [], "ruta_transversal": None,
        "razon_seleccion": "Consulta existente",
        "alcance": {"target_type": "OFERTA", "target_hint": "mi oferta"},
    }
    d.update(kwargs)
    return d


class Handoff(unittest.TestCase):
    def test_lf_uses_existing_stage2_without_new_engine(self):
        result = prepare_handoff(case())
        self.assertEqual(result["paso"], "HANDOFF_STAGE2_LF")
        self.assertEqual(result["entrypoint"], "public.lf_router_route_v1")
        self.assertEqual(result["canal_candidato"], "OPERACIONES")
        self.assertFalse(result["downstream_execution_allowed"])
        self.assertFalse(result["effect_authorized"])
        self.assertFalse(result["alcance_verificado"])
        self.assertEqual(result["stage1_v1_payload"]["schema_version"], "LF_ROUTER_STAGE1_V1")
        self.assertEqual(result["stage1_v1_payload"]["sistema"], "LF")  # internal V1 compatibility only

    def test_untrusted_hint_does_not_skip_level1(self):
        result = prepare_handoff(case())
        self.assertIsNone(result["stage1_v1_payload"]["capability_hint"])
        self.assertTrue(result["capability_hint_bypassed_until_authority"])

    def test_saly_has_no_unauthorized_route(self):
        result = prepare_handoff(case(negocio_codigo="SALY"))
        self.assertEqual(result["paso"], "NEGOCIO_NO_HABILITADO")
        self.assertNotIn("entrypoint", result)

    def test_future_registered_business_still_cannot_dispatch(self):
        newer = case(negocio_codigo="FUTUREBIZ")
        result = prepare_handoff(newer, registered_businesses={"LF", "SALY", "FUTUREBIZ"})
        self.assertEqual(result["paso"], "NEGOCIO_NO_HABILITADO")
        self.assertNotIn("entrypoint", result)

    def test_cross_business_is_not_implicit_authorization(self):
        result = prepare_handoff(case(negocio_codigo=None,
                                      negocios_afectados=["LF", "SALY"]))
        self.assertEqual(result["paso"], "MULTINEGOCIO_PENDIENTE")
        self.assertFalse(result["effect_authorized"])

    def test_invalid_scope_blocks_handoff(self):
        result = prepare_handoff(case(alcance={"target_type": "OFERTA",
                                              "target_ref": "123", "verified": True}))
        self.assertEqual(result["paso"], "INVALID_STAGE1_V2")
        self.assertNotIn("entrypoint", result)

    def test_ambiguous_stops_before_stage2(self):
        result = prepare_handoff(case(ambiguo=True, alternativas=["LF", "SALY"],
                                      pregunta_usuario="¿LF o SALY?"))
        self.assertEqual(result["paso"], "ASK_USER")
        self.assertNotIn("entrypoint", result)

    def test_direct_answer_needs_no_scope(self):
        result = prepare_handoff(case(
            texto_original="¿Qué hace el Router?", es_operacion=False,
            respuesta_directa=True, accion=None, sujeto=None,
            formas_busqueda=[], canal_candidato=None, negocio_codigo=None,
            alcance=None, capability_hint=None, razon_seleccion=None,
        ))
        self.assertEqual(result["paso"], "DIRECT_ANSWER")

    def test_profile_management_without_fourth_channel(self):
        result = prepare_handoff(case(
            texto_original="Actualizar perfil UI Architect",
            accion="actualizar", sujeto="perfil", formas_busqueda=["perfil UI Architect"],
            canal_candidato=None, ruta_transversal="GESTION_ACTIVOS_IA",
        ))
        self.assertEqual(result["paso"], "HANDOFF_STAGE2_LF")
        self.assertIsNone(result["canal_candidato"])
        self.assertEqual(result["ruta_transversal"], "GESTION_ACTIVOS_IA")

    def test_business_mismatch_fails_closed(self):
        result = prepare_handoff(case(negocio_codigo="SALY"))
        self.assertEqual(result["paso"], "INVALID_STAGE1_V2")


if __name__ == "__main__":
    unittest.main(verbosity=2)
