from __future__ import annotations

from dataclasses import dataclass
import re
import unicodedata
from typing import Iterable, FrozenSet


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


def extract_semantic_atoms(mutation: str) -> FrozenSet[str]:
    """Normalize research fixture prose into semantic atoms.

    Production integration should prefer already-structured delta facts. This adapter exists
    only so the research benchmark can exercise the structured core without case ids or gold
    labels. Unknown/compound phrasing fails closed instead of inheriting a STABLE label.
    """
    s = _norm(mutation)
    atoms: set[str] = set()

    if (
        s.startswith("mantener ")
        or s.startswith("conservar ")
        or re.search(r"\bpermanece\b", s)
        or _has(
            s,
            "misma copy canonica",
            "reconcilia mensaje al canonico",
            "reconciliar el mensaje con el error canonico",
            "reconciliar el mensaje con el canonico",
            "sin cambios",
            "exactamente como esta",
        )
    ):
        atoms.add("STABLE")
    if _has(
        s,
        "whitespace/formatting",
        "solo whitespace",
        "espacios y sangria",
        "espacios/sangria",
        "formato no visible",
        "sin efecto visual",
    ):
        atoms.update(("STABLE", "WHITESPACE_ONLY"))
    if _has(s, "nombre canonico", "alinear el nombre al canonico") and _has(
        s, "intactos", "sin cambiar", "conservar", "sin cambios"
    ):
        atoms.update(("STABLE", "CANONICAL_RECONCILIATION"))
    if _has(s, "solo copy hacia fuente") and _has(s, "mantener", "conservar"):
        atoms.add("STABLE")
    if re.search(r"\b(pero|ademas|simultaneamente|aunque)\b", s) or _has(
        s, "no obstante", "sin embargo", "a la vez"
    ):
        atoms.add("COMPOUND_SIGNAL")

    if _has(
        s,
        "sin fuente",
        "sin autoridad",
        "no respaldada",
        "no declarada",
        "carece de respaldo",
        "sin decision fuente",
        "no tiene decision fuente",
        "inventar endpoint/schema",
        "nuevo ad hoc",
        "inedita",
    ):
        atoms.add("AUTHORITY_MISSING")
    if _has(
        s,
        "crear ruta nueva",
        "ruta nueva",
        "token nuevo",
        "filtro nuevo",
        "campo nuevo",
        "error nuevo",
        "action nueva",
        "accion nueva",
        "segunda action no declarada",
        "segunda accion no declarada",
        "agregar estado/transicion",
        "estado nuevo",
        "navegacion inedita",
    ):
        atoms.add("AUTHORITY_MISSING")

    if _has(s, "eliminar historial"):
        atoms.add("COPY_CONTRADICTION")
    if _has(s, "otro permiso existente", "copy pertenece a otro recurso"):
        atoms.add("COPY_WRONG_PERMISSION")
    if ("export" in s and "delete" in s) or _has(s, "sustituir export por delete", "reemplazar export por delete"):
        atoms.add("ACTION_DELETE")
    if _has(s, "eliminar action binding", "quitar action binding", "retirar action binding", "eliminar vinculacion de accion"):
        atoms.add("REMOVE_ACTION_BINDING")
    if _has(s, "segunda action no declarada", "segunda accion no declarada", "action nueva", "accion nueva"):
        atoms.add("NEW_ACTION")
    if _has(s, "otro recurso", "otra capacidad"):
        atoms.add("CROSS_RESOURCE")
    if _has(
        s,
        "reemplazar por b2b_evidence_export",
        "reemplazar por otro permiso",
        "sustituir por otro permiso",
        "sustituir la autorizacion por otro permiso",
    ):
        atoms.add("REPLACE_PERMISSION")
    if _has(
        s,
        "quitar permission ref",
        "retirar permission ref",
        "eliminar permission ref",
        "quitar la autorizacion",
        "retirar la autorizacion",
    ):
        atoms.add("REMOVE_PERMISSION")

    if _has(s, "otra ruta existente", "otra ruta"):
        atoms.add("CROSS_ROUTE")
    if _has(s, "eliminar relacion screen_route", "quitar relacion screen_route", "retirar screen_route"):
        atoms.add("REMOVE_ROUTE_BINDING")
    if _has(s, "route ref inexistente", "ruta inexistente", "referencia de ruta inexistente"):
        atoms.add("BROKEN_ROUTE")
    if _has(s, "crear ruta nueva", "ruta nueva", "navegacion inedita"):
        atoms.add("NEW_ROUTE")

    if _has(s, "otro token existente", "token distinto sin equivalencia", "token diferente sin equivalencia"):
        atoms.add("OTHER_TOKEN_UNPROVEN")
    if _has(s, "eliminar component_token_id", "quitar component_token_id", "retirar component_token_id"):
        atoms.add("REMOVE_COMPONENT_TOKEN")
    if _has(s, "deprecado", "deprecated", "obsoleto"):
        atoms.add("DEPRECATED_TOKEN")
    if _has(s, "crear token nuevo", "token nuevo"):
        atoms.add("NEW_TOKEN")

    if _has(s, "data_type", "tipo de dato", "text -> integer", "texto a entero"):
        atoms.add("TYPE_CHANGE")
    if _has(s, "required false -> true", "opcional a obligatorio", "hacer obligatorio", "hacerlo obligatorio", "de opcional a requerido"):
        atoms.add("REQUIREDNESS_CHANGE")
    if _has(s, "agregar filtro nuevo", "campo nuevo", "filtro nuevo"):
        atoms.add("NEW_FIELD")
    if _has(s, "sensitive/pii", "clasificacion pii", "sensible/pii", "privacidad"):
        atoms.add("PII_CHANGE")
    if _has(
        s,
        "eliminar validacion de user editable requerido",
        "quitar la regla que valida un input requerido editable",
        "retirar validacion de input requerido",
        "eliminar validacion requerida",
    ):
        atoms.add("REMOVE_REQUIRED_VALIDATION")
    if _has(
        s,
        "warning no bloqueante -> error bloqueante",
        "warning a error",
        "advertencia a error",
        "no bloqueante a bloqueante",
        "advertencia no bloqueante en error bloqueante",
    ):
        atoms.add("VALIDATION_SEVERITY_CHANGE")
    if _has(s, "min/max", "minimo/maximo") and _has(s, "sin fuente", "sin autoridad"):
        atoms.add("VALIDATION_PARAM_NO_AUTH")
    if _has(s, "system/readonly", "solo lectura", "readonly") and _has(s, "validacion"):
        atoms.add("READONLY_VALIDATION")

    if _has(s, "origen/destino", "cambiar origen", "cambiar destino", "modificar el origen", "modificar el destino"):
        atoms.add("TRANSITION_ENDPOINT_CHANGE")
    if _has(s, "permission guard", "guard de permiso", "guarda de permiso") and _has(s, "eliminar", "quitar", "retirar"):
        atoms.add("REMOVE_PERMISSION_GUARD")
    if _has(s, "agregar estado/transicion", "agregar estado", "nueva transicion", "nuevo estado"):
        atoms.add("ADD_STATE_TRANSITION")
    if _has(s, "estado de otra pantalla", "cross-screen", "otra pantalla"):
        atoms.add("CROSS_SCREEN_STATE")

    if _has(s, "403 -> 200") or ("200" in s and _has(s, "no autorizado", "no esta autorizado", "sin autorizacion", "sin permiso")):
        atoms.add("HTTP_FAILOPEN")
    if _has(s, "retryable false -> true", "hacer reintentable", "reintento habilitado"):
        atoms.add("RETRYABILITY_CHANGE")
    if _has(s, "divulga detalle sensible", "expone detalle sensible", "filtra informacion sensible", "revela informacion sensible"):
        atoms.add("SENSITIVE_DISCLOSURE")
    if _has(s, "crear error nuevo", "error nuevo no definido"):
        atoms.add("NEW_ERROR")

    if _has(s, "artifact-only", "solo artefacto") and _has(s, "api_data_contract", "api global", "gap api", "api"):
        atoms.add("ARTIFACT_ONLY")
    if _has(s, "filtros/query", "filtros o query", "comportamiento de filtros", "consulta/filtros"):
        atoms.add("FILTER_QUERY_CHANGE")
    if _has(s, "paginacion", "page size"):
        atoms.add("PAGINATION_CHANGE")
    if _has(
        s,
        "payload/formato",
        "cuerpo y formato",
        "cuerpo/formato",
        "formato de exportacion",
        "formato devuelto por exportacion",
        "cuerpo y formato devuelto por exportacion",
        "respuesta de exportacion",
    ):
        atoms.add("EXPORT_PAYLOAD_CHANGE")
    if _has(s, "inventar endpoint/schema", "endpoint nuevo", "schema nuevo", "esquema nuevo"):
        atoms.add("INVENT_ENDPOINT_SCHEMA")

    return frozenset(atoms)


_MATERIAL_ATOMS = frozenset({
    "ACTION_DELETE", "REMOVE_ACTION_BINDING", "NEW_ACTION", "CROSS_RESOURCE",
    "REPLACE_PERMISSION", "REMOVE_PERMISSION", "CROSS_ROUTE", "REMOVE_ROUTE_BINDING",
    "BROKEN_ROUTE", "NEW_ROUTE", "OTHER_TOKEN_UNPROVEN", "REMOVE_COMPONENT_TOKEN",
    "DEPRECATED_TOKEN", "NEW_TOKEN", "TYPE_CHANGE", "REQUIREDNESS_CHANGE", "NEW_FIELD",
    "PII_CHANGE", "REMOVE_REQUIRED_VALIDATION", "VALIDATION_SEVERITY_CHANGE",
    "VALIDATION_PARAM_NO_AUTH", "READONLY_VALIDATION", "TRANSITION_ENDPOINT_CHANGE",
    "REMOVE_PERMISSION_GUARD", "ADD_STATE_TRANSITION", "CROSS_SCREEN_STATE", "HTTP_FAILOPEN",
    "RETRYABILITY_CHANGE", "SENSITIVE_DISCLOSURE", "NEW_ERROR", "FILTER_QUERY_CHANGE",
    "PAGINATION_CHANGE", "EXPORT_PAYLOAD_CHANGE", "INVENT_ENDPOINT_SCHEMA",
})
_SAFE_NONMATERIAL_ATOMS = frozenset({"WHITESPACE_ONLY", "CANONICAL_RECONCILIATION"})


def resolve_change_impact_atoms(
    change_surface: str,
    semantic_atoms: FrozenSet[str],
    runtime: RuntimeAuthority,
) -> ChangeImpactResult:
    """Structured deterministic core. It never consumes case ids or expected labels."""
    surface = _norm(change_surface).upper()
    atoms = semantic_atoms
    compound_unknown = (
        "STABLE" in atoms
        and "COMPOUND_SIGNAL" in atoms
        and not bool(atoms & (_MATERIAL_ATOMS | _SAFE_NONMATERIAL_ATOMS))
    )
    conflicting = "STABLE" in atoms and (bool(atoms & _MATERIAL_ATOMS) or compound_unknown)
    stable = "STABLE" in atoms and not conflicting

    if conflicting:
        decision, uncertainty, code = "HUMAN_REQUIRED", "MIXED", "CONFLICTING_SEMANTIC_ATOMS"
    elif surface == "API_DATA_CONTRACT" and "ARTIFACT_ONLY" in atoms and runtime.behavioral_contract_present:
        decision, uncertainty, code = "SCOPED_CANDIDATE", "NONE", "STABLE_BOUNDED"
    elif (
        surface == "API_DATA_CONTRACT"
        and atoms & {"EXPORT_PAYLOAD_CHANGE", "INVENT_ENDPOINT_SCHEMA"}
        and not runtime.operation_schema_authority_materialized
    ):
        decision, uncertainty, code = "HUMAN_REQUIRED", "UNKNOWN", "API_SCHEMA_AUTHORITY_MISSING"
    elif "AUTHORITY_MISSING" in atoms or atoms & {
        "NEW_ROUTE", "NEW_TOKEN", "NEW_FIELD", "ADD_STATE_TRANSITION", "NEW_ERROR", "NEW_ACTION", "INVENT_ENDPOINT_SCHEMA"
    }:
        decision, uncertainty, code = "HUMAN_REQUIRED", "UNKNOWN", "AUTHORITY_MISSING"
    elif stable:
        decision, uncertainty, code = "SCOPED_CANDIDATE", "NONE", "STABLE_BOUNDED"
    elif surface == "COPY_RECONCILIATION" and atoms & {"COPY_CONTRADICTION", "COPY_WRONG_PERMISSION"}:
        decision, uncertainty, code = "SCOPED_BLOCK", "NONE", "LOCAL_INVALID"
    elif surface == "DESIGN_COMPONENT" and atoms & {"OTHER_TOKEN_UNPROVEN", "REMOVE_COMPONENT_TOKEN", "DEPRECATED_TOKEN"}:
        decision, uncertainty, code = "SCOPED_BLOCK", "NONE", "LOCAL_INVALID"
    elif surface == "VALIDATION" and "READONLY_VALIDATION" in atoms:
        decision, uncertainty, code = "SCOPED_BLOCK", "NONE", "LOCAL_INVALID"
    elif surface == "ERROR_UI_MESSAGE" and "SENSITIVE_DISCLOSURE" in atoms:
        decision, uncertainty, code = "SCOPED_BLOCK", "NONE", "LOCAL_INVALID"
    else:
        decision, uncertainty, code = "GLOBAL_ESCALATE", "NONE", "CROSS_BOUNDARY_CHANGE"
        if atoms & {"CROSS_RESOURCE", "CROSS_ROUTE", "CROSS_SCREEN_STATE", "COPY_WRONG_PERMISSION", "OTHER_TOKEN_UNPROVEN", "REPLACE_PERMISSION"}:
            uncertainty = "MIXED"

    if surface == "COPY_RECONCILIATION":
        if stable and "WHITESPACE_ONLY" in atoms:
            impacts = ["VISUAL_EVIDENCE"]
        elif "AUTHORITY_MISSING" in atoms or conflicting:
            impacts = ["ACTIONS", "PERMISSIONS", "UI_MESSAGES", "VISUAL_EVIDENCE", "SOURCE_AUTHORITY_PROVENANCE"]
        else:
            impacts = ["ACTIONS", "PERMISSIONS", "VISUAL_EVIDENCE"]
    elif surface == "ACTION_SEMANTICS":
        if stable:
            impacts = ["ACTIONS"]
        elif "ACTION_DELETE" in atoms:
            impacts = ["ACTIONS", "PERMISSIONS", "SECURITY", "API_DATA_CONTRACT"]
        elif "REMOVE_ACTION_BINDING" in atoms:
            impacts = ["ACTIONS", "PERMISSIONS", "API_DATA_CONTRACT"]
        elif "AUTHORITY_MISSING" in atoms or "NEW_ACTION" in atoms or conflicting:
            impacts = ["ACTIONS", "PERMISSIONS", "API_DATA_CONTRACT", "SOURCE_AUTHORITY_PROVENANCE"]
        else:
            impacts = ["ACTIONS", "PERMISSIONS", "API_DATA_CONTRACT"]
    elif surface == "PERMISSION_BINDING":
        if stable:
            impacts = ["PERMISSIONS"]
        elif atoms & {"REPLACE_PERMISSION", "REMOVE_PERMISSION", "ACTION_DELETE"}:
            impacts = ["PERMISSIONS", "ACTIONS", "SECURITY", "API_DATA_CONTRACT"]
        else:
            impacts = ["PERMISSIONS", "SECURITY", "ACTIONS", "SOURCE_AUTHORITY_PROVENANCE"]
    elif surface == "ROUTING_NAVIGATION":
        if stable:
            impacts = ["ROUTING_NAVIGATION"]
        elif "CROSS_ROUTE" in atoms:
            impacts = ["ROUTING_NAVIGATION", "ACTIONS"]
        elif "AUTHORITY_MISSING" in atoms or "NEW_ROUTE" in atoms or conflicting:
            impacts = ["ROUTING_NAVIGATION", "SOURCE_AUTHORITY_PROVENANCE"]
        else:
            impacts = ["ROUTING_NAVIGATION"]
    elif surface == "DESIGN_COMPONENT":
        if stable:
            impacts = ["DESIGN_SYSTEM", "ASSETS_ICONS", "VISUAL_EVIDENCE"]
        elif "OTHER_TOKEN_UNPROVEN" in atoms:
            impacts = ["DESIGN_SYSTEM", "ASSETS_ICONS", "ACCESSIBILITY", "VISUAL_EVIDENCE"]
        elif "REMOVE_COMPONENT_TOKEN" in atoms:
            impacts = ["DESIGN_SYSTEM", "ASSETS_ICONS"]
        elif "DEPRECATED_TOKEN" in atoms:
            impacts = ["DESIGN_SYSTEM", "ASSETS_ICONS", "VISUAL_EVIDENCE"]
        else:
            impacts = ["DESIGN_SYSTEM", "SOURCE_AUTHORITY_PROVENANCE"]
    elif surface == "FIELD_CONTRACT":
        if stable:
            impacts = ["FIELDS"]
        elif "TYPE_CHANGE" in atoms:
            impacts = ["FIELDS", "VALIDATIONS", "API_DATA_CONTRACT"]
        elif "REQUIREDNESS_CHANGE" in atoms:
            impacts = ["FIELDS", "VALIDATIONS", "UI_MESSAGES", "API_DATA_CONTRACT"]
        elif "AUTHORITY_MISSING" in atoms or "NEW_FIELD" in atoms or conflicting:
            impacts = ["FIELDS", "VALIDATIONS", "API_DATA_CONTRACT", "DESIGN_SYSTEM", "SOURCE_AUTHORITY_PROVENANCE"]
        else:
            impacts = ["FIELDS", "PRIVACY_PII", "SECURITY", "AUDIT"]
    elif surface == "VALIDATION":
        if stable:
            impacts = ["VALIDATIONS"]
        elif "REMOVE_REQUIRED_VALIDATION" in atoms:
            impacts = ["VALIDATIONS", "FIELDS", "API_DATA_CONTRACT"]
        elif "VALIDATION_SEVERITY_CHANGE" in atoms:
            impacts = ["VALIDATIONS", "UI_MESSAGES", "OBJECTIVE_OUTCOMES"]
        elif "AUTHORITY_MISSING" in atoms or "VALIDATION_PARAM_NO_AUTH" in atoms or conflicting:
            impacts = ["VALIDATIONS", "FIELDS", "SOURCE_AUTHORITY_PROVENANCE"]
        else:
            impacts = ["VALIDATIONS", "FIELDS"]
    elif surface == "STATE_TRANSITION":
        if stable:
            impacts = ["STATES", "TRANSITIONS"]
        elif "TRANSITION_ENDPOINT_CHANGE" in atoms:
            impacts = ["STATES", "TRANSITIONS", "ACTIONS"]
        elif "REMOVE_PERMISSION_GUARD" in atoms:
            impacts = ["TRANSITIONS", "PERMISSIONS", "SECURITY"]
        elif "AUTHORITY_MISSING" in atoms or "ADD_STATE_TRANSITION" in atoms or conflicting:
            impacts = ["STATES", "TRANSITIONS", "ACTIONS", "SOURCE_AUTHORITY_PROVENANCE"]
        else:
            impacts = ["STATES", "TRANSITIONS"]
    elif surface == "ERROR_UI_MESSAGE":
        if stable:
            impacts = ["ERRORS", "UI_MESSAGES", "VISUAL_EVIDENCE"]
        elif "HTTP_FAILOPEN" in atoms:
            impacts = ["ERRORS", "SECURITY", "API_DATA_CONTRACT"]
        elif "RETRYABILITY_CHANGE" in atoms:
            impacts = ["ERRORS", "SECURITY", "TIMEOUT_RETRY"]
        elif "SENSITIVE_DISCLOSURE" in atoms:
            impacts = ["ERRORS", "UI_MESSAGES", "SECURITY"]
        else:
            impacts = ["ERRORS", "UI_MESSAGES", "SOURCE_AUTHORITY_PROVENANCE"]
    elif surface == "API_DATA_CONTRACT":
        if "ARTIFACT_ONLY" in atoms and not conflicting:
            impacts = ["ACTIONS", "PERMISSIONS", "VISUAL_EVIDENCE"]
        elif "FILTER_QUERY_CHANGE" in atoms:
            impacts = ["API_DATA_CONTRACT", "FIELDS", "VALIDATIONS", "OBJECTIVE_OUTCOMES"]
        elif "PAGINATION_CHANGE" in atoms:
            impacts = ["API_DATA_CONTRACT", "FIELDS", "OBJECTIVE_OUTCOMES"]
        elif "EXPORT_PAYLOAD_CHANGE" in atoms:
            impacts = ["API_DATA_CONTRACT", "ACTIONS", "PERMISSIONS", "SOURCE_AUTHORITY_PROVENANCE"]
        else:
            impacts = ["API_DATA_CONTRACT", "SOURCE_AUTHORITY_PROVENANCE"]
    else:
        return _result("HUMAN_REQUIRED", ["SOURCE_AUTHORITY_PROVENANCE"], "UNKNOWN", "UNKNOWN_SURFACE")

    return _result(decision, impacts, uncertainty, code)


def resolve_change_impact(
    change_surface: str,
    mutation: str,
    runtime: RuntimeAuthority,
) -> ChangeImpactResult:
    return resolve_change_impact_atoms(change_surface, extract_semantic_atoms(mutation), runtime)
