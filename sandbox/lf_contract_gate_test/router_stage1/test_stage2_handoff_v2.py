#!/usr/bin/env python3
"""Tests for canonical Stage1 V2 -> Stage2 LF handoff."""
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
        "accion": "consultar",
        "sujeto": "oferta",
        "correcciones": [],
        "formas_busqueda": ["oferta"],
        "ambiguo": False,
        "alternativas": [],
        "pregunta_usuario": None,
        "capability_hint": "ESTADO_EN_CURSO",
        "downstream_execution_allowed": False,
        "canal_candidato": "OPERACIONES",
        "negocio_codigo": "LF",
        "negocios_afectados": [],
        "ruta_transversal": None,
        "razon_seleccion": "Consulta existente",
        "alcance": {"target_type": "OFERTA", "target_hint": "mi oferta"},
    }
    d.update(kwargs)
    return d


class Handoff(unittest.TestCase):
    def test_lf_preserves_v2_payload_to_single_stage2_entrypoint(self):
        source = case()
        result = prepare_handoff(source)
        self.assertEqual(result["paso"], "HANDOFF_STAGE2_LF")
        self.assertEqual(result["entrypoint"], "public.lf_router_route_v1")
        self.assertEqual(result["stage1_v2_payload"], source)
        self.assertEqual(result["canal_candidato"], "OPERACIONES")
        self.assertEqual(result["negocio_codigo"], "LF")
        self.assertEqual(result["alcance"]["target_type"], "OFERTA")
        self.assertNotIn("sistema", result["stage1_v2_payload"])
        self.assertFalse(result["downstream_execution_allowed"])
        self.assertFalse(result["effect_authorized"])
        self.assertFalse(result["alcance_verificado"])

    def test_capability_hint_remains_candidate_not_authority(self):
        result = prepare_handoff(case())
        self.assertEqual(result["capability_hint_authority"], "CANDIDATE_ONLY")
        self.assertEqual(result["stage1_v2_payload"]["capability_hint"], "ESTADO_EN_CURSO")
        self.assertFalse(result["effect_authorized"])

    def test_product_channel_is_preserved(self):
        result = prepare_handoff(case(
            canal_candidato="PRODUCTO",
            accion="definir",
            razon_seleccion="Modificar definición canónica",
        ))
        self.assertEqual(result["paso"], "HANDOFF_STAGE2_LF")
        self.assertEqual(result["canal_candidato"], "PRODUCTO")

    def test_programming_channel_is_preserved(self):
        result = prepare_handoff(case(
            canal_candidato="PROGRAMACION",
            accion="corregir",
            razon_seleccion="Corrección técnica sobre definición vigente",
        ))
        self.assertEqual(result["paso"], "HANDOFF_STAGE2_LF")
        self.assertEqual(result["canal_candidato"], "PROGRAMACION")

    def test_registered_non_lf_business_is_not_dispatched(self):
        result = prepare_handoff(
            case(negocio_codigo="NEWBIZ"),
            registered_businesses={"LF", "NEWBIZ"},
        )
        self.assertEqual(result["paso"], "NEGOCIO_NO_HABILITADO")
        self.assertNotIn("entrypoint", result)

    def test_cross_business_stops_before_stage2(self):
        result = prepare_handoff(
            case(negocio_codigo=None, negocios_afectados=["LF", "NEWBIZ"]),
            registered_businesses={"LF", "NEWBIZ"},
        )
        self.assertEqual(result["paso"], "MULTINEGOCIO_PENDIENTE")
        self.assertFalse(result["effect_authorized"])

    def test_invalid_scope_blocks_handoff(self):
        result = prepare_handoff(case(
            alcance={"target_type": "OFERTA", "target_ref": "123", "verified": True}
        ))
        self.assertEqual(result["paso"], "INVALID_STAGE1_V2")
        self.assertNotIn("entrypoint", result)

    def test_legacy_sistema_blocks_handoff(self):
        result = prepare_handoff(case(sistema="LF"))
        self.assertEqual(result["paso"], "INVALID_STAGE1_V2")
        self.assertIn("CAMPO_LEGACY_SISTEMA_NO_PERMITIDO_EN_V2", result["codigos"])

    def test_ambiguous_stops_before_stage2(self):
        result = prepare_handoff(case(
            ambiguo=True,
            alternativas=["producto", "programación"],
            pregunta_usuario="¿Es un cambio funcional o una corrección técnica?",
        ))
        self.assertEqual(result["paso"], "ASK_USER")
        self.assertNotIn("entrypoint", result)

    def test_direct_answer_needs_no_scope(self):
        result = prepare_handoff(case(
            texto_original="¿Qué hace el Router?",
            es_operacion=False,
            respuesta_directa=True,
            accion=None,
            sujeto=None,
            formas_busqueda=[],
            canal_candidato=None,
            negocio_codigo=None,
            alcance=None,
            capability_hint=None,
            razon_seleccion=None,
        ))
        self.assertEqual(result["paso"], "DIRECT_ANSWER")

    def test_profile_management_without_fourth_channel(self):
        result = prepare_handoff(case(
            texto_original="Actualizar perfil UI Architect",
            accion="actualizar",
            sujeto="perfil",
            formas_busqueda=["perfil UI Architect"],
            canal_candidato=None,
            ruta_transversal="GESTION_ACTIVOS_IA",
        ))
        self.assertEqual(result["paso"], "HANDOFF_STAGE2_LF")
        self.assertIsNone(result["canal_candidato"])
        self.assertEqual(result["ruta_transversal"], "GESTION_ACTIVOS_IA")


if __name__ == "__main__":
    unittest.main(verbosity=2)
