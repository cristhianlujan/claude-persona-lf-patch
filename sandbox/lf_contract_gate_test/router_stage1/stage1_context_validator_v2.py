#!/usr/bin/env python3
"""Read-only validator for the canonical LF Router Stage 1 V2 contract.

Stage 1 V2 exposes only the canonical dimensions Canal, Negocio and Alcance.
It never exposes the retired V1 field `sistema`, never resolves canonical
references, and never grants execution authority.
"""
from __future__ import annotations

import copy
import re
from typing import Any, Iterable

V2_SCHEMA = "LF_ROUTER_STAGE1_V2"
CHANNELS = frozenset({"PRODUCTO", "PROGRAMACION", "OPERACIONES"})
DEFAULT_REGISTERED_BUSINESSES = frozenset({"LF"})
SCOPE_STATES = frozenset({"NOT_REQUIRED", "UNRESOLVED", "MULTIPLE_MATCHES"})
CODE = re.compile(r"^[A-Z][A-Z0-9_]{1,63}$")
HINT = re.compile(r"^[A-Z][A-Z0-9_]{2,63}$")
ASSET_CODE_RE = re.compile(
    r"\b(?:ACT-\d{3,5}|REG_[A-Z0-9_]+|PERFIL-[A-Z0-9-]+|ADAPTER-[A-Z0-9-]+|"
    r"SKILL-[A-Z0-9-]+|EDGE_FN_[A-Z0-9_]+)\b",
    re.I,
)
TRANSVERSAL_ROUTE = "GESTION_ACTIVOS_IA"
MAX_FORMAS = 4
MAX_ALTERNATIVAS = 3


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
    # Stage 1 may describe the target, never certify its canonical identity.
    if scope.get("target_ref") is not None or scope.get("verified") is True:
        errors.append("ALCANCE_NO_PUEDE_CERTIFICARSE_EN_STAGE1")


def validate(candidate: Any, registered_businesses: Iterable[str] | None = None) -> dict[str, Any]:
    """Validate canonical V2 fields without translating to the legacy V1 schema."""
    if not isinstance(candidate, dict):
        return {"valid": False, "codes": ["NOT_AN_OBJECT"], "next_step": "INVALID"}

    errors: list[str] = []
    allowed = (
        DEFAULT_REGISTERED_BUSINESSES
        if registered_businesses is None
        else frozenset(registered_businesses)
    )
    if not allowed or not all(isinstance(x, str) and CODE.fullmatch(x) for x in allowed):
        errors.append("CATALOGO_NEGOCIOS_INVALIDO")

    if candidate.get("schema_version") != V2_SCHEMA:
        errors.append("BAD_V2_SCHEMA_VERSION")
    if "sistema" in candidate:
        errors.append("CAMPO_LEGACY_SISTEMA_NO_PERMITIDO_EN_V2")
    if not _nonempty(candidate.get("texto_original")):
        errors.append("ORIGINAL_TEXT_REQUIRED")
    if candidate.get("downstream_execution_allowed") is not False:
        errors.append("DOWNSTREAM_EXECUTION_MUST_BE_FALSE")

    is_operation = candidate.get("es_operacion")
    ambiguous = candidate.get("ambiguo")
    if not isinstance(is_operation, bool):
        errors.append("ES_OPERACION_BOOL_REQUIRED")
    if not isinstance(ambiguous, bool):
        errors.append("AMBIGUO_BOOL_REQUIRED")

    formas = candidate.get("formas_busqueda", [])
    alternatives = candidate.get("alternativas", [])
    corrections = candidate.get("correcciones", [])
    question = candidate.get("pregunta_usuario")
    capability_hint = candidate.get("capability_hint")

    if not isinstance(formas, list) or not all(_nonempty(x) for x in formas):
        errors.append("FORMAS_BUSQUEDA_INVALID")
        formas = []
    if len(formas) > MAX_FORMAS:
        errors.append("TOO_MANY_FORMAS")

    if not isinstance(alternatives, list) or not all(_nonempty(x) for x in alternatives):
        errors.append("ALTERNATIVAS_INVALID")
        alternatives = []
    if len(alternatives) > MAX_ALTERNATIVAS:
        errors.append("TOO_MANY_ALTERNATIVAS")

    if question is not None and not _nonempty(question):
        errors.append("PREGUNTA_INVALID")
    if isinstance(question, str) and question.count("?") + question.count("¿") > 2:
        errors.append("MORE_THAN_ONE_QUESTION")

    if capability_hint is not None and not (
        isinstance(capability_hint, str) and HINT.fullmatch(capability_hint)
    ):
        errors.append("CAPABILITY_HINT_INVALID")

    if not isinstance(corrections, list) or not all(
        isinstance(c, dict)
        and _nonempty(c.get("de"))
        and _nonempty(c.get("a"))
        and c["de"].strip().lower() != c["a"].strip().lower()
        for c in corrections
    ):
        errors.append("CORRECCIONES_INVALID")

    original = candidate.get("texto_original")
    original = original if isinstance(original, str) else ""
    typed_codes = {m.group(0).upper() for m in ASSET_CODE_RE.finditer(original)}
    for phrase in formas:
        for match in ASSET_CODE_RE.finditer(phrase):
            if match.group(0).upper() not in typed_codes:
                errors.append("INVENTED_ASSET_CODE")
                break

    channel = candidate.get("canal_candidato")
    business = candidate.get("negocio_codigo")
    affected_businesses = candidate.get("negocios_afectados", [])
    transversal = candidate.get("ruta_transversal")
    reason = candidate.get("razon_seleccion")
    scope = candidate.get("alcance")
    _valid_scope(scope, errors)

    if affected_businesses is None:
        affected_businesses = []
    if (
        not isinstance(affected_businesses, list)
        or not all(isinstance(x, str) and x in allowed for x in affected_businesses)
        or len(affected_businesses) != len(set(affected_businesses))
    ):
        errors.append("NEGOCIOS_AFECTADOS_INVALIDOS")
        affected_businesses = []

    if is_operation is False:
        if candidate.get("respuesta_directa") is not True:
            errors.append("NON_OPERATION_REQUIRES_DIRECT_ANSWER")
        if formas or capability_hint is not None:
            errors.append("NON_OPERATION_MUST_NOT_SEARCH")
        if channel is not None or transversal is not None or business is not None:
            errors.append("NO_OPERACION_NO_TIENE_RUTA")
        if affected_businesses:
            errors.append("NO_OPERACION_NO_TIENE_NEGOCIOS")
        if scope is not None:
            errors.append("NO_OPERACION_NO_TIENE_ALCANCE")
    elif is_operation is True:
        if candidate.get("respuesta_directa") is True:
            errors.append("OPERATION_CANNOT_BE_DIRECT_ANSWER")
        if not (_nonempty(candidate.get("sujeto")) or _nonempty(candidate.get("accion"))):
            errors.append("SUBJECT_OR_ACTION_REQUIRED")
        if not formas:
            errors.append("FORMAS_BUSQUEDA_REQUIRED")
        if transversal is not None:
            if transversal != TRANSVERSAL_ROUTE or channel is not None:
                errors.append("RUTA_TRANSVERSAL_INVALIDA")
        elif channel not in CHANNELS:
            errors.append("CANAL_NO_RECONOCIDO")
        if not _nonempty(reason):
            errors.append("RAZON_SELECCION_REQUERIDA")
        if business is None and not affected_businesses:
            errors.append("NEGOCIO_REQUERIDO_EN_V2")
        if business is not None and business not in allowed:
            errors.append("NEGOCIO_NO_REGISTRADO_EN_V2")
        if affected_businesses and (business is not None or len(affected_businesses) < 2):
            errors.append("MULTINEGOCIO_INCONSISTENTE")

    if ambiguous is True and not (
        2 <= len(alternatives) <= MAX_ALTERNATIVAS and _nonempty(question)
    ):
        errors.append("AMBIGUOUS_REQUIRES_ALTERNATIVES_AND_ONE_QUESTION")
    if ambiguous is False and alternatives:
        errors.append("ALTERNATIVES_WITHOUT_AMBIGUITY")

    if errors:
        return {"valid": False, "codes": sorted(set(errors)), "next_step": "INVALID"}

    if is_operation is False:
        next_step = "DIRECT_ANSWER"
    elif ambiguous is True:
        next_step = "ASK_USER"
    elif affected_businesses:
        next_step = "MULTINEGOCIO_PENDIENTE"
    elif business != "LF":
        next_step = "NEGOCIO_NO_HABILITADO"
    else:
        next_step = "ROUTE_STAGE2"

    return {
        "valid": True,
        "codes": [],
        "next_step": next_step,
        "canal_candidato": channel,
        "negocio_codigo": business,
        "negocios_afectados": list(affected_businesses),
        "ruta_transversal": transversal,
        "alcance": copy.deepcopy(scope),
        "downstream_execution_allowed": False,
        "classification_only": True,
    }
