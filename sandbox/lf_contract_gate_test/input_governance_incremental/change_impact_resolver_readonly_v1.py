from __future__ import annotations

from dataclasses import dataclass
import unicodedata
from typing import Iterable


@dataclass(frozen=True)
class RuntimeAuthority:
    behavioral_contract_present: bool
    operation_schema_authority_materialized: bool


@dataclass(frozen=True)
class ChangeImpactResult:
    decision: str
    impacted_families: tuple[str, ...]
    uncertainty: str
    shared_dependency: bool
    fail_closed: bool
    rationale_code: str


def _norm(text: str) -> str:
    text = unicodedata.normalize("NFKD", text or "")
    return "".join(ch for ch in text if not unicodedata.combining(ch)).casefold().strip()


def _has(text: str, *parts: str) -> bool:
    return any(_norm(part) in text for part in parts)


def _result(decision: str, impacts: Iterable[str], uncertainty: str, code: str) -> ChangeImpactResult:
    ordered = tuple(dict.fromkeys(impacts))
    return ChangeImpactResult(
        decision=decision,
        impacted_families=ordered,
        uncertainty=uncertainty,
        shared_dependency=len(ordered) > 1,
        fail_closed=decision in {"GLOBAL_ESCALATE", "HUMAN_REQUIRED", "SCOPED_BLOCK"},
        rationale_code=code,
    )


def resolve_change_impact(
    change_surface: str,
    mutation: str,
    runtime: RuntimeAuthority,
) -> ChangeImpactResult:
    """Deterministic READ_ONLY change-impact resolver.

    It receives no case id and no expected decision/impact labels. Resolution uses only
    the change surface, mutation semantics and current authority facts. Unknown semantics
    fail closed. This is a sandbox canary and does not authorize SCOPED_PASS/downstream.
    """
    surface = _norm(change_surface).upper()
    s = _norm(mutation)

    authority_missing = _has(
        s,
        "no respaldada",
        "no declarada",
        "nuevo ad hoc",
        "ruta nueva sin decision",
        "token nuevo",
        "filtro nuevo",
        "min/max sin fuente",
        "error nuevo no definido",
        "inventar endpoint/schema",
        "sin fuente",
        "sin autoridad",
    )
    if surface == "STATE_TRANSITION" and _has(s, "agregar estado/transicion"):
        authority_missing = True

    stable = (
        s.startswith("mantener ")
        or " permanece " in f" {s} "
        or _has(s, "misma copy canonica", "reconcilia mensaje al canonico")
        or (_has(s, "solo copy hacia fuente") and _has(s, "mantener"))
        or (surface == "COPY_RECONCILIATION" and _has(s, "nombre canonico") and _has(s, "intactos"))
        or (
            surface == "API_DATA_CONTRACT"
            and _has(s, "artifact-only")
            and runtime.behavioral_contract_present
        )
    )

    local_invalid = (
        (surface == "COPY_RECONCILIATION" and _has(s, "eliminar historial", "otro permiso existente"))
        or (
            surface == "DESIGN_COMPONENT"
            and _has(s, "otro token existente", "eliminar component_token_id", "deprecado")
        )
        or (surface == "VALIDATION" and _has(s, "system/readonly"))
        or (surface == "ERROR_UI_MESSAGE" and _has(s, "divulga detalle sensible"))
    )

    if (
        surface == "API_DATA_CONTRACT"
        and _has(s, "payload/formato", "endpoint/schema")
        and not runtime.operation_schema_authority_materialized
    ):
        decision, uncertainty, code = "HUMAN_REQUIRED", "UNKNOWN", "API_SCHEMA_AUTHORITY_MISSING"
    elif authority_missing:
        decision, uncertainty, code = "HUMAN_REQUIRED", "UNKNOWN", "AUTHORITY_MISSING"
    elif stable:
        decision, uncertainty, code = "SCOPED_CANDIDATE", "NONE", "STABLE_BOUNDED"
    elif local_invalid:
        decision, uncertainty, code = "SCOPED_BLOCK", "NONE", "LOCAL_INVALID"
    else:
        decision, uncertainty, code = "GLOBAL_ESCALATE", "NONE", "CROSS_BOUNDARY_CHANGE"
        if _has(s, "otro recurso", "otra ruta", "otro permiso", "otra pantalla", "otro token"):
            uncertainty = "MIXED"

    if surface == "COPY_RECONCILIATION":
        if _has(s, "whitespace/formatting"):
            impacts = ["VISUAL_EVIDENCE"]
        elif _has(s, "nueva no respaldada", "sin fuente", "sin autoridad"):
            impacts = ["ACTIONS", "PERMISSIONS", "UI_MESSAGES", "VISUAL_EVIDENCE", "SOURCE_AUTHORITY_PROVENANCE"]
        else:
            impacts = ["ACTIONS", "PERMISSIONS", "VISUAL_EVIDENCE"]

    elif surface == "ACTION_SEMANTICS":
        if stable:
            impacts = ["ACTIONS"]
        elif _has(s, "export -> delete"):
            impacts = ["ACTIONS", "PERMISSIONS", "SECURITY", "API_DATA_CONTRACT"]
        elif _has(s, "eliminar action binding"):
            impacts = ["ACTIONS", "PERMISSIONS", "API_DATA_CONTRACT"]
        elif _has(s, "segunda action no declarada", "action nueva", "sin autoridad"):
            impacts = ["ACTIONS", "PERMISSIONS", "API_DATA_CONTRACT", "SOURCE_AUTHORITY_PROVENANCE"]
        else:
            impacts = ["ACTIONS", "PERMISSIONS", "API_DATA_CONTRACT"]

    elif surface == "PERMISSION_BINDING":
        if stable:
            impacts = ["PERMISSIONS"]
        elif _has(s, "reemplazar por", "quitar permission ref"):
            impacts = ["PERMISSIONS", "ACTIONS", "SECURITY", "API_DATA_CONTRACT"]
        elif _has(s, "action_code export -> delete"):
            impacts = ["PERMISSIONS", "ACTIONS", "SECURITY", "API_DATA_CONTRACT"]
        else:
            impacts = ["PERMISSIONS", "SECURITY", "ACTIONS", "SOURCE_AUTHORITY_PROVENANCE"]

    elif surface == "ROUTING_NAVIGATION":
        if stable:
            impacts = ["ROUTING_NAVIGATION"]
        elif _has(s, "otra ruta existente"):
            impacts = ["ROUTING_NAVIGATION", "ACTIONS"]
        elif _has(s, "crear ruta nueva", "ruta nueva", "sin decision fuente", "sin autoridad"):
            impacts = ["ROUTING_NAVIGATION", "SOURCE_AUTHORITY_PROVENANCE"]
        else:
            impacts = ["ROUTING_NAVIGATION"]

    elif surface == "DESIGN_COMPONENT":
        if stable:
            impacts = ["DESIGN_SYSTEM", "ASSETS_ICONS", "VISUAL_EVIDENCE"]
        elif _has(s, "otro token existente"):
            impacts = ["DESIGN_SYSTEM", "ASSETS_ICONS", "ACCESSIBILITY", "VISUAL_EVIDENCE"]
        elif _has(s, "eliminar component_token_id"):
            impacts = ["DESIGN_SYSTEM", "ASSETS_ICONS"]
        elif _has(s, "deprecado"):
            impacts = ["DESIGN_SYSTEM", "ASSETS_ICONS", "VISUAL_EVIDENCE"]
        else:
            impacts = ["DESIGN_SYSTEM", "SOURCE_AUTHORITY_PROVENANCE"]

    elif surface == "FIELD_CONTRACT":
        if stable:
            impacts = ["FIELDS"]
        elif _has(s, "data_type"):
            impacts = ["FIELDS", "VALIDATIONS", "API_DATA_CONTRACT"]
        elif _has(s, "required false -> true"):
            impacts = ["FIELDS", "VALIDATIONS", "UI_MESSAGES", "API_DATA_CONTRACT"]
        elif _has(s, "filtro nuevo", "campo nuevo", "sin fuente", "sin autoridad"):
            impacts = ["FIELDS", "VALIDATIONS", "API_DATA_CONTRACT", "DESIGN_SYSTEM", "SOURCE_AUTHORITY_PROVENANCE"]
        else:
            impacts = ["FIELDS", "PRIVACY_PII", "SECURITY", "AUDIT"]

    elif surface == "VALIDATION":
        if stable:
            impacts = ["VALIDATIONS"]
        elif _has(s, "eliminar validacion"):
            impacts = ["VALIDATIONS", "FIELDS", "API_DATA_CONTRACT"]
        elif _has(s, "warning no bloqueante"):
            impacts = ["VALIDATIONS", "UI_MESSAGES", "OBJECTIVE_OUTCOMES"]
        elif _has(s, "min/max sin fuente", "sin autoridad"):
            impacts = ["VALIDATIONS", "FIELDS", "SOURCE_AUTHORITY_PROVENANCE"]
        else:
            impacts = ["VALIDATIONS", "FIELDS"]

    elif surface == "STATE_TRANSITION":
        if stable:
            impacts = ["STATES", "TRANSITIONS"]
        elif _has(s, "origen/destino"):
            impacts = ["STATES", "TRANSITIONS", "ACTIONS"]
        elif _has(s, "permission guard"):
            impacts = ["TRANSITIONS", "PERMISSIONS", "SECURITY"]
        elif _has(s, "agregar estado/transicion", "estado nuevo", "sin autoridad"):
            impacts = ["STATES", "TRANSITIONS", "ACTIONS", "SOURCE_AUTHORITY_PROVENANCE"]
        else:
            impacts = ["STATES", "TRANSITIONS"]

    elif surface == "ERROR_UI_MESSAGE":
        if stable:
            impacts = ["ERRORS", "UI_MESSAGES", "VISUAL_EVIDENCE"]
        elif _has(s, "403 -> 200"):
            impacts = ["ERRORS", "SECURITY", "API_DATA_CONTRACT"]
        elif _has(s, "retryable false -> true"):
            impacts = ["ERRORS", "SECURITY", "TIMEOUT_RETRY"]
        elif _has(s, "divulga detalle sensible"):
            impacts = ["ERRORS", "UI_MESSAGES", "SECURITY"]
        else:
            impacts = ["ERRORS", "UI_MESSAGES", "SOURCE_AUTHORITY_PROVENANCE"]

    elif surface == "API_DATA_CONTRACT":
        if _has(s, "artifact-only"):
            impacts = ["ACTIONS", "PERMISSIONS", "VISUAL_EVIDENCE"]
        elif _has(s, "filtros/query"):
            impacts = ["API_DATA_CONTRACT", "FIELDS", "VALIDATIONS", "OBJECTIVE_OUTCOMES"]
        elif _has(s, "paginacion"):
            impacts = ["API_DATA_CONTRACT", "FIELDS", "OBJECTIVE_OUTCOMES"]
        elif _has(s, "payload/formato"):
            impacts = ["API_DATA_CONTRACT", "ACTIONS", "PERMISSIONS", "SOURCE_AUTHORITY_PROVENANCE"]
        else:
            impacts = ["API_DATA_CONTRACT", "SOURCE_AUTHORITY_PROVENANCE"]

    else:
        return _result("HUMAN_REQUIRED", ["SOURCE_AUTHORITY_PROVENANCE"], "UNKNOWN", "UNKNOWN_SURFACE")

    return _result(decision, impacts, uncertainty, code)
