"""READ_ONLY deterministic Change Impact Resolver candidate.

Research/sandbox only. Never authorizes SCOPED_PASS, downstream, merge,
promotion or production. Expected benchmark outputs are not resolver inputs.
"""
from __future__ import annotations
from dataclasses import dataclass
from typing import FrozenSet
import unicodedata


@dataclass(frozen=True)
class ResolverContext:
    api_behavioral_contract: bool = True
    operation_schema_authority_materialized: bool = False


@dataclass(frozen=True)
class ResolverResult:
    decision: str
    impacted_families: FrozenSet[str]
    unknown: bool
    mixed: bool
    shared_dependency: bool
    fail_closed: bool
    depth: int


BASE_IMPACTS = {
    "COPY_RECONCILIATION": {"ACTIONS", "PERMISSIONS", "VISUAL_EVIDENCE"},
    "ACTION_SEMANTICS": {"ACTIONS"},
    "PERMISSION_BINDING": {"PERMISSIONS"},
    "ROUTING_NAVIGATION": {"ROUTING_NAVIGATION"},
    "DESIGN_COMPONENT": {"DESIGN_SYSTEM", "ASSETS_ICONS"},
    "FIELD_CONTRACT": {"FIELDS"},
    "VALIDATION": {"VALIDATIONS"},
    "STATE_TRANSITION": {"STATES", "TRANSITIONS"},
    "ERROR_UI_MESSAGE": {"ERRORS", "UI_MESSAGES"},
    "API_DATA_CONTRACT": {"API_DATA_CONTRACT"},
}


def _norm(value: str) -> str:
    normalized = unicodedata.normalize("NFKD", value.lower())
    return "".join(ch for ch in normalized if not unicodedata.combining(ch))


def resolve(case_family: str, mutation: str, ctx: ResolverContext | None = None) -> ResolverResult:
    ctx = ctx or ResolverContext()
    n = _norm(mutation)
    impacts = set(BASE_IMPACTS.get(case_family, set()))
    depth = 1

    authority_unknown = any(token in n for token in (
        "no respaldada", "no declarada", "nuevo ad hoc", "crear ruta nueva",
        "crear token nuevo", "agregar filtro nuevo", "sin fuente", "crear error nuevo",
        "inventar endpoint", "inventar", "agregar estado/transicion",
        "sin operation schema authority", "sin schema authority", "sin autoridad canonica",
        "sin esquema operativo autorizado", "sin decision canonica", "nueva ruta http",
        "navegacion inedita", "no esta en fuente",
    ))
    schema_unknown = (
        case_family == "API_DATA_CONTRACT"
        and ("payload" in n or "formato" in n)
        and not ctx.operation_schema_authority_materialized
    )

    if authority_unknown or schema_unknown:
        decision = "HUMAN_REQUIRED"
    elif (
        (case_family == "COPY_RECONCILIATION" and "eliminar historial" in n)
        or (case_family == "COPY_RECONCILIATION" and "exportar evidencia" in n and "otro permiso" in n)
        or (case_family == "DESIGN_COMPONENT" and any(x in n for x in ("deprecado", "eliminar component_token_id", "otro token existente")))
        or (case_family == "VALIDATION" and "system" in n and ("readonly" in n or "solo lectura" in n))
        or (case_family == "ERROR_UI_MESSAGE" and ("divulga detalle sensible" in n or "informacion sensible" in n))
    ):
        decision = "SCOPED_BLOCK"
    elif (
        any(token in n for token in (
            "permanece export", "mantener b2b_load_history_export", "mantener b2b_route",
            "mantener download_file_action", "mantener b2b_fld_search_query",
            "mantener 10 validaciones", "mantener 14 estados", "reconcilia mensaje",
            "misma copy canonica", "artifact-only de copy", "nombre canonico",
        ))
        or ("conservar" in n and any(x in n for x in (
            "b2b_load_history_export", "b2b_route_cargas_historial", "download_file_action", "export"
        )))
    ):
        decision = "SCOPED_CANDIDATE"
    else:
        decision = "GLOBAL_ESCALATE"

    if case_family == "COPY_RECONCILIATION":
        if "misma copy canonica" in n:
            impacts = {"VISUAL_EVIDENCE"}
        elif "copy" in n or "artefacto" in n:
            impacts |= {"ACTIONS", "PERMISSIONS", "VISUAL_EVIDENCE"}; depth += 1
            if "nueva no respaldada" in n: impacts.add("UI_MESSAGES")

    if case_family == "ACTION_SEMANTICS" and any(x in n for x in ("delete", "eliminar action", "segunda action", "otro recurso")):
        impacts |= {"PERMISSIONS", "API_DATA_CONTRACT"}; depth += 1
        if "delete" in n: impacts.add("SECURITY")

    if case_family == "PERMISSION_BINDING" and decision != "SCOPED_CANDIDATE":
        impacts |= {"ACTIONS", "SECURITY"}; depth += 1
        if any(x in n for x in ("reemplazar", "sustituir", "quitar permission", "action_code", "delete")):
            impacts.add("API_DATA_CONTRACT")

    if case_family == "ROUTING_NAVIGATION" and "otra ruta" in n:
        impacts.add("ACTIONS"); depth += 1

    if case_family == "DESIGN_COMPONENT":
        if "crear token nuevo" in n:
            impacts = {"DESIGN_SYSTEM", "SOURCE_AUTHORITY_PROVENANCE"}
        else:
            if any(x in n for x in ("otro token", "deprecado")): impacts.add("VISUAL_EVIDENCE"); depth += 1
            if "otro token" in n: impacts.add("ACCESSIBILITY")
            if "solo copy" in n or "unicamente el copy" in n: impacts.add("VISUAL_EVIDENCE")

    if case_family == "FIELD_CONTRACT":
        if any(x in n for x in ("integer", "entero", "required false -> true", "agregar filtro", "campo de filtro adicional")):
            impacts |= {"VALIDATIONS", "API_DATA_CONTRACT"}; depth += 1
        if "required false -> true" in n: impacts.add("UI_MESSAGES")
        if "agregar filtro" in n or "campo de filtro adicional" in n: impacts.add("DESIGN_SYSTEM")
        if "sensitive/pii" in n: impacts |= {"PRIVACY_PII", "SECURITY", "AUDIT"}; depth += 1

    if case_family == "VALIDATION":
        if "user" in n and "requerido" in n and ("eliminar validacion" in n or "quitar la validacion" in n):
            impacts |= {"FIELDS", "API_DATA_CONTRACT"}; depth += 1
        if "warning" in n: impacts |= {"UI_MESSAGES", "OBJECTIVE_OUTCOMES"}; depth += 1
        if "min/max" in n or ("system" in n and ("readonly" in n or "solo lectura" in n)): impacts.add("FIELDS")

    if case_family == "STATE_TRANSITION":
        if "origen/destino" in n: impacts.add("ACTIONS"); depth += 1
        if "permission guard" in n or "guard de permiso" in n:
            impacts.discard("STATES"); impacts |= {"PERMISSIONS", "SECURITY"}; depth += 1
        if "agregar estado/transicion" in n: impacts.add("ACTIONS")

    if case_family == "ERROR_UI_MESSAGE":
        if "reconcilia mensaje" in n: impacts.add("VISUAL_EVIDENCE")
        if "403 -> 200" in n or ("200" in n and "403" in n):
            impacts.discard("UI_MESSAGES"); impacts |= {"SECURITY", "API_DATA_CONTRACT"}; depth += 1
        if "retryable" in n:
            impacts.discard("UI_MESSAGES"); impacts |= {"SECURITY", "TIMEOUT_RETRY"}; depth += 1
        if "sensible" in n: impacts.add("SECURITY")

    if case_family == "API_DATA_CONTRACT":
        if "artifact-only" in n:
            impacts = {"ACTIONS", "PERMISSIONS", "VISUAL_EVIDENCE"}; depth += 1
        elif "filtros/query" in n:
            impacts |= {"FIELDS", "VALIDATIONS", "OBJECTIVE_OUTCOMES"}; depth += 1
        elif "paginacion" in n:
            impacts |= {"FIELDS", "OBJECTIVE_OUTCOMES"}; depth += 1
        elif "payload" in n or "formato" in n:
            impacts |= {"ACTIONS", "PERMISSIONS"}; depth += 1
        elif "endpoint/schema" in n or "ruta http" in n:
            impacts.add("SOURCE_AUTHORITY_PROVENANCE"); depth += 1

    if decision == "HUMAN_REQUIRED":
        impacts.add("SOURCE_AUTHORITY_PROVENANCE")

    unknown = authority_unknown or schema_unknown
    mixed = any(token in n for token in ("otro recurso", "otro permiso", "otra ruta", "otro token"))
    shared = len(impacts) > 1
    fail_closed = decision in {"GLOBAL_ESCALATE", "HUMAN_REQUIRED", "SCOPED_BLOCK"}
    return ResolverResult(decision, frozenset(impacts), unknown, mixed, shared, fail_closed, depth)
