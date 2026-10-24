#!/usr/bin/env python3
"""Compatibility-safe, read-only Stage 1 V2 channel/business/scope validator.

Stage 1 is model-authored. This module validates a CANDIDATE classification
without selecting assets, granting permissions, or executing an operation.
The current LF_ROUTER_STAGE1_V1 / lf_router_route_v1 remain unchanged.
"""
from __future__ import annotations

import copy
import re
from typing import Any

from stage1_validator_v1 import validate as validate_v1

V2_SCHEMA = "LF_ROUTER_STAGE1_V2"
CHANNELS = frozenset({"PRODUCTO", "PROGRAMACION", "OPERACIONES"})
BUSINESSES = frozenset({"LF", "SALY"})
SCOPE_STATES = frozenset({"NOT_REQUIRED", "UNRESOLVED", "MULTIPLE_MATCHES"})
CODE = re.compile(r"^[A-Z][A-Z0-9_]{1,63}$")
TRANSVERSAL_ROUTE = "GESTION_ACTIVOS_IA"


def _nonempty(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _valid_scope(scope: Any, errors: list[str]) -> None:
    if scope is None:
        return
    if not isinstance(scope, dict):
        errors.append("ALCANCE_INVALID")
        return
    kind = scope.get("target_type")
    hint = scope.get("target_hint")
    state = scope.get("resolution_status", "UNRESOLVED")
    if not isinstance(kind, str) or not CODE.fullmatch(kind):
        errors.append("ALCANCE_TIPO_INVALIDO")
    if hint is not None and not _nonempty(hint):
        errors.append("ALCANCE_PISTA_INVALIDA")
    if state not in SCOPE_STATES:
        errors.append("ALCANCE_ESTADO_NO_PERMITIDO_EN_STAGE1")
    # A Stage1 model must not assert resolved IDs or authorizations.
    if scope.get("target_ref") is not None or scope.get("verified") is True:
        errors.append("ALCANCE_NO_PUEDE_CERTIFICARSE_EN_STAGE1")


def normalize_to_v1(candidate: dict[str, Any]) -> dict[str, Any]:
    """Return the exact V1-compatible fields for the existing Stage 2 route."""
    fields = (
        "texto_original", "es_operacion", "respuesta_directa", "sistema",
        "accion", "sujeto", "correcciones", "formas_busqueda", "ambiguo",
        "alternativas", "pregunta_usuario", "capability_hint",
        "downstream_execution_allowed",
    )
    result = {key: copy.deepcopy(candidate[key]) for key in fields if key in candidate}
    result["schema_version"] = "LF_ROUTER_STAGE1_V1"
    return result


def validate(candidate: Any) -> dict[str, Any]:
    """Validate V2; do not authorize dispatch. Keep V1 negative cases."""
    if not isinstance(candidate, dict):
        return {"valid": False, "codes": ["NOT_AN_OBJECT"], "next_step": "INVALID"}
    errors: list[str] = []
    if candidate.get("schema_version") != V2_SCHEMA:
        errors.append("BAD_V2_SCHEMA_VERSION")

    normalized = normalize_to_v1(candidate)
    old = validate_v1(normalized)
    errors.extend(old["codes"])

    is_operation = candidate.get("es_operacion") is True
    channel = candidate.get("canal_candidato")
    business = candidate.get("negocio_codigo")
    transversal = candidate.get("ruta_transversal")
    systems = candidate.get("sistema")
    businesses = candidate.get("negocios_afectados", [])
    explanation = candidate.get("razon_seleccion")
    _valid_scope(candidate.get("alcance"), errors)

    if businesses is None:
        businesses = []
    if not isinstance(businesses, list) or not all(
        isinstance(x, str) and x in BUSINESSES for x in businesses
    ) or len(businesses) != len(set(businesses)):
        errors.append("NEGOCIOS_AFECTADOS_INVALIDOS")
        businesses = []

    if is_operation:
        if transversal is not None:
            if transversal != TRANSVERSAL_ROUTE or channel is not None:
                errors.append("RUTA_TRANSVERSAL_INVALIDA")
        elif channel not in CHANNELS:
            errors.append("CANAL_NO_RECONOCIDO")
        if not _nonempty(explanation):
            errors.append("RAZON_SELECCION_REQUERIDA")
        if business is not None and business not in BUSINESSES:
            errors.append("NEGOCIO_NO_REGISTRADO_EN_V2")
        if systems in BUSINESSES:
            if business != systems or businesses:
                errors.append("NEGOCIO_NO_COINCIDE_CON_SISTEMA")
        elif business is not None:
            errors.append("NEGOCIO_NO_COINCIDE_CON_SISTEMA")
        if businesses and (business is not None or len(businesses) < 2):
            errors.append("MULTINEGOCIO_INCONSISTENTE")
    else:
        if channel is not None or transversal is not None or business is not None:
            errors.append("NO_OPERACION_NO_TIENE_RUTA")
        if businesses:
            errors.append("NO_OPERACION_NO_TIENE_NEGOCIOS")
        if candidate.get("alcance") is not None:
            errors.append("NO_OPERACION_NO_TIENE_ALCANCE")

    if errors:
        return {"valid": False, "codes": sorted(set(errors)), "next_step": "INVALID"}

    return {
        "valid": True,
        "codes": [],
        "next_step": old["next_step"],
        "normalized_stage1_v1": normalized,
        "canal_candidato": channel,
        "negocio_codigo": business,
        "negocios_afectados": list(businesses),
        "ruta_transversal": transversal,
        "alcance_candidato": copy.deepcopy(candidate.get("alcance")),
        "downstream_execution_allowed": False,
        "classification_only": True,
    }
