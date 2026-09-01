"""READ_ONLY deterministic Change Impact Resolver candidate.

Research/sandbox only. It never authorizes SCOPED_PASS, downstream, merge,
promotion or production. Resolver inputs do not include adjudicated expected
decision/impact outputs.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import FrozenSet


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


def resolve(case_family: str, mutation: str, ctx: ResolverContext | None = None) -> ResolverResult:
    ctx = ctx or ResolverContext()
    m = mutation.lower()
    impacts = set(BASE_IMPACTS.get(case_family, set()))
    depth = 1

    authority_unknown = any(token in m for token in (
        "no respaldada", "no declarada", "nuevo ad hoc", "crear ruta nueva",
        "crear token nuevo", "agregar filtro nuevo", "sin fuente", "crear error nuevo",
        "inventar endpoint", "inventar", "agregar estado/transición",
        "sin operation schema authority", "sin schema authority", "sin autoridad canónica",
    ))
    schema_unknown = (
        case_family == "API_DATA_CONTRACT"
        and ("payload" in m or "formato" in m)
        and not ctx.operation_schema_authority_materialized
    )

    if authority_unknown or schema_unknown:
        decision = "HUMAN_REQUIRED"
    elif any(token in m for token in (
        "eliminar historial", "copy 'exportar evidencia'", "otro token existente",
        "eliminar component_token_id", "token deprecado", "system/readonly",
        "divulga detalle sensible",
    )):
        decision = "SCOPED_BLOCK"
    elif any(token in m for token in (
        "permanece export", "mantener b2b_load_history_export", "mantener b2b_route",
        "mantener download_file_action", "mantener b2b_fld_search_query",
        "mantener 10 validaciones", "mantener 14 estados", "reconcilia mensaje",
        "misma copy canónica", "artifact-only de copy", "nombre canónico",
    )):
        decision = "SCOPED_CANDIDATE"
    else:
        decision = "GLOBAL_ESCALATE"

    if case_family == "COPY_RECONCILIATION":
        if "misma copy canónica" in m:
            impacts = {"VISUAL_EVIDENCE"}
        elif "copy" in m or "artefacto" in m:
            impacts |= {"ACTIONS", "PERMISSIONS", "VISUAL_EVIDENCE"}; depth += 1
            if "nueva no respaldada" in m: impacts.add("UI_MESSAGES")
    if case_family == "ACTION_SEMANTICS" and any(t in m for t in ("delete", "eliminar action", "segunda action", "otro recurso")):
        impacts |= {"PERMISSIONS", "API_DATA_CONTRACT"}; depth += 1
        if "delete" in m: impacts.add("SECURITY")
    if case_family == "PERMISSION_BINDING" and decision != "SCOPED_CANDIDATE":
        impacts |= {"ACTIONS", "SECURITY"}; depth += 1
        if any(t in m for t in ("reemplazar", "quitar permission", "action_code", "delete")):
            impacts.add("API_DATA_CONTRACT")
    if case_family == "ROUTING_NAVIGATION" and "otra ruta" in m:
        impacts.add("ACTIONS"); depth += 1
    if case_family == "DESIGN_COMPONENT":
        if "crear token nuevo" in m:
            impacts = {"DESIGN_SYSTEM", "SOURCE_AUTHORITY_PROVENANCE"}
        else:
            if any(t in m for t in ("otro token", "deprecado")): impacts.add("VISUAL_EVIDENCE"); depth += 1
            if "otro token" in m: impacts.add("ACCESSIBILITY")
            if "solo copy" in m: impacts.add("VISUAL_EVIDENCE")
    if case_family == "FIELD_CONTRACT":
        if any(t in m for t in ("integer", "required false -> true", "agregar filtro")):
            impacts |= {"VALIDATIONS", "API_DATA_CONTRACT"}; depth += 1
        if "required false -> true" in m: impacts.add("UI_MESSAGES")
        if "agregar filtro" in m: impacts.add("DESIGN_SYSTEM")
        if "sensitive/pii" in m: impacts |= {"PRIVACY_PII", "SECURITY", "AUDIT"}; depth += 1
    if case_family == "VALIDATION":
        if "user editable requerido" in m: impacts |= {"FIELDS", "API_DATA_CONTRACT"}; depth += 1
        if "warning" in m: impacts |= {"UI_MESSAGES", "OBJECTIVE_OUTCOMES"}; depth += 1
        if "min/max" in m or "system/readonly" in m: impacts.add("FIELDS")
    if case_family == "STATE_TRANSITION":
        if "origen/destino" in m: impacts.add("ACTIONS"); depth += 1
        if "permission guard" in m:
            impacts.discard("STATES"); impacts |= {"PERMISSIONS", "SECURITY"}; depth += 1
        if "agregar estado/transición" in m: impacts.add("ACTIONS")
    if case_family == "ERROR_UI_MESSAGE":
        if "reconcilia mensaje" in m: impacts.add("VISUAL_EVIDENCE")
        if "403 -> 200" in m:
            impacts.discard("UI_MESSAGES"); impacts |= {"SECURITY", "API_DATA_CONTRACT"}; depth += 1
        if "retryable" in m:
            impacts.discard("UI_MESSAGES"); impacts |= {"SECURITY", "TIMEOUT_RETRY"}; depth += 1
        if "divulga" in m: impacts.add("SECURITY")
    if case_family == "API_DATA_CONTRACT":
        if "artifact-only" in m: impacts = {"ACTIONS", "PERMISSIONS", "VISUAL_EVIDENCE"}; depth += 1
        elif "filtros/query" in m: impacts |= {"FIELDS", "VALIDATIONS", "OBJECTIVE_OUTCOMES"}; depth += 1
        elif "paginación" in m: impacts |= {"FIELDS", "OBJECTIVE_OUTCOMES"}; depth += 1
        elif "payload/formato" in m: impacts |= {"ACTIONS", "PERMISSIONS"}; depth += 1
        elif "endpoint/schema" in m: impacts.add("SOURCE_AUTHORITY_PROVENANCE"); depth += 1
    if decision == "HUMAN_REQUIRED": impacts.add("SOURCE_AUTHORITY_PROVENANCE")

    unknown = authority_unknown or schema_unknown
    mixed = any(token in m for token in ("otro recurso", "otro permiso", "otra ruta", "otro token"))
    shared = len(impacts) > 1
    fail_closed = decision in {"GLOBAL_ESCALATE", "HUMAN_REQUIRED", "SCOPED_BLOCK"}
    return ResolverResult(decision, frozenset(impacts), unknown, mixed, shared, fail_closed, depth)
