#!/usr/bin/env python3
"""Non-executing Stage 1 V2 -> existing LF Stage 2 compatibility handoff.

V2 canonical input uses negocio_codigo and never exposes the retired `sistema`
field. The temporary V1 payload may synthesize `sistema` internally because the
currently deployed lf_router_route_v1 contract still requires it.

Never calls Supabase and never grants execution. Business-specific handlers,
canonical target resolution and admission belong to Stage 2 and its authority.
"""
from __future__ import annotations

import copy
from typing import Any, Iterable

from stage1_context_validator_v2 import validate


def prepare_handoff(stage1: Any, registered_businesses: Iterable[str] | None = None) -> dict[str, Any]:
    result = validate(stage1, registered_businesses=registered_businesses)
    base = {
        "schema_version": "LF_ROUTER_STAGE2_HANDOFF_CANDIDATE_V2",
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
            **base, "paso": "ASK_USER",
            "pregunta_usuario": stage1.get("pregunta_usuario"),
            "alternativas": stage1.get("alternativas", []),
        }
    if result["negocios_afectados"]:
        return {
            **base, "paso": "MULTINEGOCIO_PENDIENTE",
            "negocios_afectados": result["negocios_afectados"],
            "motivo": "Sin habilitacion transversal ni vinculaciones de autoridad por negocio",
        }
    if result["negocio_codigo"] != "LF":
        return {
            **base, "paso": "NEGOCIO_NO_HABILITADO",
            "negocio_codigo": result["negocio_codigo"],
            "motivo": "El router SQL disponible solo soporta LF",
        }
    if step != "LEVEL1_SEARCH":
        return {**base, "paso": "NO_DISPATCH", "motivo": "Stage 1 no admite busqueda"}

    # Existing V1 dispatches capability_hint immediately. A model-supplied
    # hint is not sufficient evidence for a business operation, so disable
    # direct hint dispatch in this source candidate. Preserve level-1 search.
    v1 = copy.deepcopy(result["normalized_stage1_v1"])
    v1["capability_hint"] = None
    return {
        **base,
        "paso": "HANDOFF_STAGE2_LF",
        "entrypoint": "public.lf_router_route_v1",
        "legacy_stage1_v1_payload": v1,
        "canal_candidato": result["canal_candidato"],
        "negocio_codigo": "LF",
        "ruta_transversal": result["ruta_transversal"],
        "alcance_candidato": result["alcance_candidato"],
        "alcance_verificado": False,
        "capability_hint_bypassed_until_authority": True,
        "nota": "La ruta SQL existente busca candidatos. No confirma canal, identidad, tenant, permisos ni implementacion.",
    }
