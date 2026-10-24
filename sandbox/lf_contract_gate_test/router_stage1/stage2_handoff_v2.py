#!/usr/bin/env python3
"""Canonical Stage 1 V2 -> Stage 2 handoff for LF.

The handoff preserves Canal, Negocio and Alcance exactly as V2 fields. It does
not translate to LF_ROUTER_STAGE1_V1 and never creates the retired `sistema`
field. The single Stage 2 entrypoint remains public.lf_router_route_v1, which
must consume LF_ROUTER_STAGE1_V2 directly.
"""
from __future__ import annotations

import copy
from typing import Any, Iterable

from stage1_context_validator_v2 import validate


def prepare_handoff(stage1: Any, registered_businesses: Iterable[str] | None = None) -> dict[str, Any]:
    result = validate(stage1, registered_businesses=registered_businesses)
    base = {
        "schema_version": "LF_ROUTER_STAGE2_HANDOFF_V2",
        "downstream_execution_allowed": False,
        "effect_authorized": False,
    }
    if not result["valid"]:
        return {**base, "paso": "INVALID_STAGE1_V2", "codigos": result["codes"]}

    step = result["next_step"]
    if step == "DIRECT_ANSWER":
        return {**base, "paso": "DIRECT_ANSWER"}
    if step == "ASK_USER":
        return {
            **base,
            "paso": "ASK_USER",
            "pregunta_usuario": stage1.get("pregunta_usuario"),
            "alternativas": stage1.get("alternativas", []),
        }
    if step == "MULTINEGOCIO_PENDIENTE":
        return {
            **base,
            "paso": "MULTINEGOCIO_PENDIENTE",
            "negocios_afectados": result["negocios_afectados"],
        }
    if step == "NEGOCIO_NO_HABILITADO":
        return {
            **base,
            "paso": "NEGOCIO_NO_HABILITADO",
            "negocio_codigo": result["negocio_codigo"],
        }
    if step != "ROUTE_STAGE2":
        return {**base, "paso": "NO_DISPATCH", "motivo": "Stage 1 V2 no admite handoff"}

    payload = copy.deepcopy(stage1)
    return {
        **base,
        "paso": "HANDOFF_STAGE2_LF",
        "entrypoint": "public.lf_router_route_v1",
        "stage1_v2_payload": payload,
        "canal_candidato": result["canal_candidato"],
        "negocio_codigo": result["negocio_codigo"],
        "ruta_transversal": result["ruta_transversal"],
        "alcance": result["alcance"],
        "capability_hint_authority": "CANDIDATE_ONLY",
        "alcance_verificado": False,
        "consumo_requerido": {
            "canal_candidato": True,
            "negocio_codigo": True,
            "alcance": True,
        },
    }
