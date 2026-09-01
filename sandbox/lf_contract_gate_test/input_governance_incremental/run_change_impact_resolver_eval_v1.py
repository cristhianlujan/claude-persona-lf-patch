from __future__ import annotations

import inspect
import json
import math
from pathlib import Path
import re
import time

from change_impact_resolver_readonly_v1 import (
    RuntimeAuthority,
    extract_semantic_atoms,
    resolve_change_impact,
    resolve_change_impact_atoms,
)


ROW_RE = re.compile(
    r"\(\s*'((?:''|[^'])*)'\s*,\s*'((?:''|[^'])*)'\s*,\s*'((?:''|[^'])*)'\s*,\s*'((?:''|[^'])*)'\s*,\s*'((?:''|[^'])*)'\s*,\s*'((?:''|[^'])*)'\s*,\s*'((?:''|[^'])*)'\s*\)"
)


def _sql_unescape(value: str) -> str:
    return value.replace("''", "'")


def load_gold() -> list[dict[str, object]]:
    text = Path(__file__).with_name("change_impact_l3c_gold_50.sql").read_text(encoding="utf-8")
    rows: list[dict[str, object]] = []
    for match in ROW_RE.finditer(text):
        case_code, case_family, mutation, decision, impacts_json, anchor, rationale = (
            _sql_unescape(x) for x in match.groups()
        )
        if not case_code.startswith("CI-"):
            continue
        rows.append(
            {
                "case_code": case_code,
                "case_family": case_family,
                "mutation": mutation,
                "expected_decision": decision,
                "expected_impacts": set(json.loads(impacts_json)),
                "source_anchor": anchor,
                "rationale": rationale,
            }
        )
    return rows


def percentile(values: list[float], p: float) -> float:
    ordered = sorted(values)
    pos = (len(ordered) - 1) * p
    lo = math.floor(pos)
    hi = math.ceil(pos)
    if lo == hi:
        return ordered[lo]
    return ordered[lo] * (hi - pos) + ordered[hi] * (pos - lo)


def evaluate(rows: list[dict[str, object]], runtime: RuntimeAuthority) -> dict[str, object]:
    correct_decisions = 0
    tp = fp = fn = 0
    unsafe_under_block = 0
    unnecessary_global_block = 0
    unknown_mixed_fail_closed_violations = 0
    shared_nonstable_fail_closed_violations = 0
    results: list[dict[str, object]] = []

    for row in rows:
        result = resolve_change_impact(str(row["case_family"]), str(row["mutation"]), runtime)
        expected_impacts = set(row["expected_impacts"])
        predicted_impacts = set(result.impacted_families)
        correct_decisions += int(result.decision == row["expected_decision"])
        tp += len(expected_impacts & predicted_impacts)
        fp += len(predicted_impacts - expected_impacts)
        fn += len(expected_impacts - predicted_impacts)

        expected_decision = str(row["expected_decision"])
        if expected_decision in {"GLOBAL_ESCALATE", "HUMAN_REQUIRED", "SCOPED_BLOCK"} and result.decision == "SCOPED_CANDIDATE":
            unsafe_under_block += 1
        if expected_decision in {"SCOPED_CANDIDATE", "SCOPED_BLOCK"} and result.decision == "GLOBAL_ESCALATE":
            unnecessary_global_block += 1
        if result.uncertainty in {"UNKNOWN", "MIXED"} and not result.fail_closed:
            unknown_mixed_fail_closed_violations += 1
        if result.shared_dependency and result.rationale_code != "STABLE_BOUNDED" and not result.fail_closed:
            shared_nonstable_fail_closed_violations += 1

        results.append(
            {
                "case_code": row["case_code"],
                "expected_decision": expected_decision,
                "actual_decision": result.decision,
                "expected_impacts": sorted(expected_impacts),
                "actual_impacts": sorted(predicted_impacts),
                "semantic_atoms": sorted(extract_semantic_atoms(str(row["mutation"]))),
                "uncertainty": result.uncertainty,
                "shared_dependency": result.shared_dependency,
                "fail_closed": result.fail_closed,
                "rationale_code": result.rationale_code,
            }
        )

    precision = tp / (tp + fp) if tp + fp else 1.0
    recall = tp / (tp + fn) if tp + fn else 1.0
    accuracy = correct_decisions / len(rows)
    mismatches = [
        item for item in results
        if item["expected_decision"] != item["actual_decision"]
        or item["expected_impacts"] != item["actual_impacts"]
    ]
    return {
        "cases": len(rows),
        "exact_decision_accuracy": accuracy,
        "impact_precision": precision,
        "impact_recall": recall,
        "unsafe_under_block": unsafe_under_block,
        "unnecessary_global_block": unnecessary_global_block,
        "unknown_mixed_fail_closed_violations": unknown_mixed_fail_closed_violations,
        "shared_nonstable_fail_closed_violations": shared_nonstable_fail_closed_violations,
        "mismatches": mismatches,
    }


runtime = RuntimeAuthority(
    behavioral_contract_present=True,
    operation_schema_authority_materialized=False,
)
gold = load_gold()
assert len(gold) == 50, f"EXPECTED_50_CASES:{len(gold)}"
assert len({row['case_family'] for row in gold}) == 10, "EXPECTED_10_FAMILIES"
core_source = inspect.getsource(resolve_change_impact_atoms)
assert "CI-" not in inspect.getsource(resolve_change_impact), "RESOLVER_MUST_NOT_MEMORIZE_CASE_IDS"
assert "CI-" not in core_source, "CORE_MUST_NOT_MEMORIZE_CASE_IDS"
assert "mutation" not in core_source, "STRUCTURED_CORE_MUST_NOT_READ_RAW_MUTATION_TEXT"

gold_quality = evaluate(gold, runtime)

# Independent-of-gold wording holdout. The cases intentionally paraphrase semantics instead
# of copying benchmark strings. They test the text adapter; the core itself consumes only atoms.
holdout_rows = [
    ("H-COPY-01","COPY_RECONCILIATION","Únicamente cambia espacios y sangría; el usuario no percibe diferencia.","SCOPED_CANDIDATE",["VISUAL_EVIDENCE"]),
    ("H-COPY-02","COPY_RECONCILIATION","Se propone una etiqueta inédita y carece de respaldo canónico.","HUMAN_REQUIRED",["ACTIONS","PERMISSIONS","UI_MESSAGES","VISUAL_EVIDENCE","SOURCE_AUTHORITY_PROVENANCE"]),
    ("H-COPY-03","COPY_RECONCILIATION","El texto de exportar se reemplaza por el texto perteneciente a otro permiso existente.","SCOPED_BLOCK",["ACTIONS","PERMISSIONS","VISUAL_EVIDENCE"]),
    ("H-COPY-04","COPY_RECONCILIATION","Alinear el nombre al canónico conservando acción, permiso y geometría sin cambios.","SCOPED_CANDIDATE",["ACTIONS","PERMISSIONS","VISUAL_EVIDENCE"]),
    ("H-ACT-01","ACTION_SEMANTICS","Conservar EXPORT exactamente como está.","SCOPED_CANDIDATE",["ACTIONS"]),
    ("H-ACT-02","ACTION_SEMANTICS","Sustituir EXPORT por DELETE.","GLOBAL_ESCALATE",["ACTIONS","PERMISSIONS","SECURITY","API_DATA_CONTRACT"]),
    ("H-ACT-03","ACTION_SEMANTICS","Retirar la vinculación de acción del elemento.","GLOBAL_ESCALATE",["ACTIONS","PERMISSIONS","API_DATA_CONTRACT"]),
    ("H-ACT-04","ACTION_SEMANTICS","Añadir una segunda acción inédita sin autoridad.","HUMAN_REQUIRED",["ACTIONS","PERMISSIONS","API_DATA_CONTRACT","SOURCE_AUTHORITY_PROVENANCE"]),
    ("H-PERM-01","PERMISSION_BINDING","Mantener el permiso B2B_LOAD_HISTORY_EXPORT.","SCOPED_CANDIDATE",["PERMISSIONS"]),
    ("H-PERM-02","PERMISSION_BINDING","Sustituir la autorización por otro permiso existente.","GLOBAL_ESCALATE",["PERMISSIONS","ACTIONS","SECURITY","API_DATA_CONTRACT"]),
    ("H-PERM-03","PERMISSION_BINDING","Retirar la autorización que protege la exportación.","GLOBAL_ESCALATE",["PERMISSIONS","ACTIONS","SECURITY","API_DATA_CONTRACT"]),
    ("H-PERM-04","PERMISSION_BINDING","Crear un permiso nuevo ad hoc sin autoridad.","HUMAN_REQUIRED",["PERMISSIONS","SECURITY","ACTIONS","SOURCE_AUTHORITY_PROVENANCE"]),
    ("H-ROUTE-01","ROUTING_NAVIGATION","Mantener la ruta actual sin cambios.","SCOPED_CANDIDATE",["ROUTING_NAVIGATION"]),
    ("H-ROUTE-02","ROUTING_NAVIGATION","Redirigir hacia otra ruta ya existente.","GLOBAL_ESCALATE",["ROUTING_NAVIGATION","ACTIONS"]),
    ("H-ROUTE-03","ROUTING_NAVIGATION","Retirar la relación SCREEN_ROUTE.","GLOBAL_ESCALATE",["ROUTING_NAVIGATION"]),
    ("H-ROUTE-04","ROUTING_NAVIGATION","Añadir una navegación inédita que no tiene decisión fuente.","HUMAN_REQUIRED",["ROUTING_NAVIGATION","SOURCE_AUTHORITY_PROVENANCE"]),
    ("H-DESIGN-01","DESIGN_COMPONENT","Mantener download_file_action y conservar la representación visual.","SCOPED_CANDIDATE",["DESIGN_SYSTEM","ASSETS_ICONS","VISUAL_EVIDENCE"]),
    ("H-DESIGN-02","DESIGN_COMPONENT","Usar un token distinto sin equivalencia demostrada.","SCOPED_BLOCK",["DESIGN_SYSTEM","ASSETS_ICONS","ACCESSIBILITY","VISUAL_EVIDENCE"]),
    ("H-DESIGN-03","DESIGN_COMPONENT","Quitar component_token_id del control.","SCOPED_BLOCK",["DESIGN_SYSTEM","ASSETS_ICONS"]),
    ("H-DESIGN-04","DESIGN_COMPONENT","Cambiar al token marcado como obsoleto.","SCOPED_BLOCK",["DESIGN_SYSTEM","ASSETS_ICONS","VISUAL_EVIDENCE"]),
    ("H-FIELD-01","FIELD_CONTRACT","Mantener B2B_FLD_SEARCH_QUERY sin cambios.","SCOPED_CANDIDATE",["FIELDS"]),
    ("H-FIELD-02","FIELD_CONTRACT","Cambiar el tipo de dato de texto a entero.","GLOBAL_ESCALATE",["FIELDS","VALIDATIONS","API_DATA_CONTRACT"]),
    ("H-FIELD-03","FIELD_CONTRACT","Hacer obligatorio el campo que antes era opcional.","GLOBAL_ESCALATE",["FIELDS","VALIDATIONS","UI_MESSAGES","API_DATA_CONTRACT"]),
    ("H-FIELD-04","FIELD_CONTRACT","Añadir un filtro nuevo sin fuente.","HUMAN_REQUIRED",["FIELDS","VALIDATIONS","API_DATA_CONTRACT","DESIGN_SYSTEM","SOURCE_AUTHORITY_PROVENANCE"]),
    ("H-VAL-01","VALIDATION","Mantener las validaciones actuales.","SCOPED_CANDIDATE",["VALIDATIONS"]),
    ("H-VAL-02","VALIDATION","Quitar la regla que valida un input requerido editable.","GLOBAL_ESCALATE",["VALIDATIONS","FIELDS","API_DATA_CONTRACT"]),
    ("H-VAL-03","VALIDATION","Convertir una advertencia no bloqueante en error bloqueante.","GLOBAL_ESCALATE",["VALIDATIONS","UI_MESSAGES","OBJECTIVE_OUTCOMES"]),
    ("H-VAL-04","VALIDATION","Añadir validación a un campo de solo lectura.","SCOPED_BLOCK",["VALIDATIONS","FIELDS"]),
    ("H-STATE-01","STATE_TRANSITION","Mantener los estados y transiciones vigentes.","SCOPED_CANDIDATE",["STATES","TRANSITIONS"]),
    ("H-STATE-02","STATE_TRANSITION","Modificar el origen de una transición.","GLOBAL_ESCALATE",["STATES","TRANSITIONS","ACTIONS"]),
    ("H-STATE-03","STATE_TRANSITION","Retirar el guard de permiso de la transición.","GLOBAL_ESCALATE",["TRANSITIONS","PERMISSIONS","SECURITY"]),
    ("H-STATE-04","STATE_TRANSITION","Agregar un estado nuevo sin autoridad.","HUMAN_REQUIRED",["STATES","TRANSITIONS","ACTIONS","SOURCE_AUTHORITY_PROVENANCE"]),
    ("H-ERR-01","ERROR_UI_MESSAGE","Reconciliar el mensaje con el error canónico.","SCOPED_CANDIDATE",["ERRORS","UI_MESSAGES","VISUAL_EVIDENCE"]),
    ("H-ERR-02","ERROR_UI_MESSAGE","Responder 200 cuando el usuario no está autorizado.","GLOBAL_ESCALATE",["ERRORS","SECURITY","API_DATA_CONTRACT"]),
    ("H-ERR-03","ERROR_UI_MESSAGE","Hacer reintentable un error de autorización.","GLOBAL_ESCALATE",["ERRORS","SECURITY","TIMEOUT_RETRY"]),
    ("H-ERR-04","ERROR_UI_MESSAGE","El mensaje expone detalle sensible.","SCOPED_BLOCK",["ERRORS","UI_MESSAGES","SECURITY"]),
    ("H-API-01","API_DATA_CONTRACT","Solicitud solo artefacto de copy; el gap API global no toca el delta.","SCOPED_CANDIDATE",["ACTIONS","PERMISSIONS","VISUAL_EVIDENCE"]),
    ("H-API-02","API_DATA_CONTRACT","Modificar el comportamiento de filtros o query.","GLOBAL_ESCALATE",["API_DATA_CONTRACT","FIELDS","VALIDATIONS","OBJECTIVE_OUTCOMES"]),
    ("H-API-03","API_DATA_CONTRACT","Modificar la paginación server-side.","GLOBAL_ESCALATE",["API_DATA_CONTRACT","FIELDS","OBJECTIVE_OUTCOMES"]),
    ("H-API-04","API_DATA_CONTRACT","Alterar el cuerpo y formato devuelto por exportación.","HUMAN_REQUIRED",["API_DATA_CONTRACT","ACTIONS","PERMISSIONS","SOURCE_AUTHORITY_PROVENANCE"]),
]
holdout = [
    {
        "case_code": code,
        "case_family": family,
        "mutation": mutation,
        "expected_decision": decision,
        "expected_impacts": set(impacts),
    }
    for code, family, mutation, decision, impacts in holdout_rows
]
holdout_quality = evaluate(holdout, runtime)

# Additional fail-closed probes do not copy adjudicated benchmark wording.
adversarial = [
    ("UNKNOWN_SURFACE", "Mutación cualquiera.", "HUMAN_REQUIRED"),
    ("COPY_RECONCILIATION", "Cambio material no reconocido.", "GLOBAL_ESCALATE"),
    ("ACTION_SEMANTICS", "Cambiar la capacidad de forma no catalogada.", "GLOBAL_ESCALATE"),
    ("PERMISSION_BINDING", "Crear autorización inédita sin fuente.", "HUMAN_REQUIRED"),
    ("ROUTING_NAVIGATION", "Referencia de ruta inexistente.", "GLOBAL_ESCALATE"),
    ("DESIGN_COMPONENT", "Crear token nuevo para acomodar el pedido.", "HUMAN_REQUIRED"),
    ("FIELD_CONTRACT", "Agregar campo nuevo sin autoridad.", "HUMAN_REQUIRED"),
    ("VALIDATION", "Modificar mínimo/máximo sin fuente.", "HUMAN_REQUIRED"),
    ("STATE_TRANSITION", "Referenciar estado de otra pantalla.", "GLOBAL_ESCALATE"),
    ("ERROR_UI_MESSAGE", "Crear error nuevo no definido.", "HUMAN_REQUIRED"),
]
adversarial_failures = []
for surface, mutation, expected in adversarial:
    actual = resolve_change_impact(surface, mutation, runtime)
    if actual.decision != expected:
        adversarial_failures.append(
            {"surface": surface, "mutation": mutation, "expected": expected, "actual": actual.decision}
        )

# Local Python sandbox microbenchmark only; not a DB/Router production latency claim.
first_start = time.perf_counter_ns()
for row in gold:
    resolve_change_impact(str(row["case_family"]), str(row["mutation"]), runtime)
cold_batch_ms = (time.perf_counter_ns() - first_start) / 1_000_000

for _ in range(100):
    for row in gold:
        resolve_change_impact(str(row["case_family"]), str(row["mutation"]), runtime)

batch_ms: list[float] = []
per_case_us: list[float] = []
for _ in range(500):
    batch_start = time.perf_counter_ns()
    for row in gold:
        case_start = time.perf_counter_ns()
        resolve_change_impact(str(row["case_family"]), str(row["mutation"]), runtime)
        per_case_us.append((time.perf_counter_ns() - case_start) / 1_000)
    batch_ms.append((time.perf_counter_ns() - batch_start) / 1_000_000)

summary = {
    "schema": "INPUT_GOV_CHANGE_IMPACT_RESOLVER_READONLY_EVAL_V2",
    "authority": {
        "governance_issue": 414,
        "adjudication_run_id": 75,
        "handoff_message_id": 41,
        "gold_status": "CANDIDATE_RESEARCH",
        "scoped_pass_authorized": False,
        "downstream_authorized": False,
        "production_authorized": False,
    },
    "architecture": {
        "text_adapter": "SEMANTIC_ATOM_EXTRACTION_RESEARCH_ONLY",
        "structured_core": "resolve_change_impact_atoms",
        "core_reads_raw_mutation_text": False,
        "case_id_memorization_guard": True,
        "production_integration_preference": "STRUCTURED_DELTA_FACTS_NOT_FREE_TEXT",
    },
    "runtime_authority": {
        "behavioral_contract_present": runtime.behavioral_contract_present,
        "operation_schema_authority_materialized": runtime.operation_schema_authority_materialized,
    },
    "resolver_quality": {
        "gold_50x10": {k: v for k, v in gold_quality.items() if k != "mismatches"},
        "paraphrase_holdout_40": {k: v for k, v in holdout_quality.items() if k != "mismatches"},
        "adversarial_pass": len(adversarial) - len(adversarial_failures),
        "adversarial_total": len(adversarial),
    },
    "performance": {
        "scope": "LOCAL_PYTHON_SANDBOX_ONLY",
        "cold_batch50_ms": cold_batch_ms,
        "warm_batch50_p50_ms": percentile(batch_ms, 0.50),
        "warm_batch50_p95_ms": percentile(batch_ms, 0.95),
        "warm_per_case_p50_us": percentile(per_case_us, 0.50),
        "warm_per_case_p95_us": percentile(per_case_us, 0.95),
        "cache": "NONE_EXPLICIT",
    },
    "context": {
        "gold_input_mutation_utf8_bytes": sum(len((str(row['case_family']) + str(row['mutation'])).encode('utf-8')) for row in gold),
        "tokens": "NOT_OBSERVED",
        "depth": "GOLD_50X10_PLUS_PARAPHRASE_HOLDOUT_40_PLUS_ADVERSARIAL_10",
    },
    "quality_domains": {
        "resolver_quality": "MEASURED",
        "gate_quality": "SEPARATE_CANONICAL_CI",
        "profile_quality": "NOT_EXECUTED_BY_THIS_HARNESS",
        "orchestrator_quality": "NOT_EXECUTED_BY_THIS_HARNESS",
    },
    "failures": {
        "gold_mismatches": gold_quality["mismatches"],
        "holdout_mismatches": holdout_quality["mismatches"],
        "adversarial_failures": adversarial_failures,
    },
}

print(json.dumps(summary, ensure_ascii=False, sort_keys=True))

for quality in (gold_quality, holdout_quality):
    assert quality["exact_decision_accuracy"] == 1.0
    assert quality["impact_precision"] == 1.0
    assert quality["impact_recall"] == 1.0
    assert quality["unsafe_under_block"] == 0
    assert quality["unnecessary_global_block"] == 0
    assert quality["unknown_mixed_fail_closed_violations"] == 0
    assert quality["shared_nonstable_fail_closed_violations"] == 0
    assert not quality["mismatches"]
assert not adversarial_failures
