from __future__ import annotations

import inspect
import json
import math
from pathlib import Path
import re
import time

from change_impact_resolver_readonly_v1 import RuntimeAuthority, resolve_change_impact


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


runtime = RuntimeAuthority(
    behavioral_contract_present=True,
    operation_schema_authority_materialized=False,
)
gold = load_gold()
assert len(gold) == 50, f"EXPECTED_50_CASES:{len(gold)}"
assert len({row['case_family'] for row in gold}) == 10, "EXPECTED_10_FAMILIES"
assert "CI-" not in inspect.getsource(resolve_change_impact), "RESOLVER_MUST_NOT_MEMORIZE_CASE_IDS"

correct_decisions = 0
tp = fp = fn = 0
unsafe_under_block = 0
unnecessary_global_block = 0
unknown_mixed_fail_closed_violations = 0
shared_nonstable_fail_closed_violations = 0
results: list[dict[str, object]] = []

for row in gold:
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
            "uncertainty": result.uncertainty,
            "shared_dependency": result.shared_dependency,
            "fail_closed": result.fail_closed,
            "rationale_code": result.rationale_code,
        }
    )

precision = tp / (tp + fp) if tp + fp else 1.0
recall = tp / (tp + fn) if tp + fn else 1.0
accuracy = correct_decisions / len(gold)

adversarial = [
    ("COPY_RECONCILIATION", "Renombrar al nombre canónico y conservar acción, permiso y geometría intactos.", "SCOPED_CANDIDATE"),
    ("COPY_RECONCILIATION", "Agregar copy inédita sin fuente.", "HUMAN_REQUIRED"),
    ("ACTION_SEMANTICS", "Crear action nueva sin autoridad.", "HUMAN_REQUIRED"),
    ("ACTION_SEMANTICS", "Cambiar action EXPORT -> DELETE.", "GLOBAL_ESCALATE"),
    ("PERMISSION_BINDING", "Mantener B2B_LOAD_HISTORY_EXPORT.", "SCOPED_CANDIDATE"),
    ("PERMISSION_BINDING", "Reemplazar por otro permiso existente.", "GLOBAL_ESCALATE"),
    ("ROUTING_NAVIGATION", "Introducir route ref inexistente.", "GLOBAL_ESCALATE"),
    ("ROUTING_NAVIGATION", "Crear ruta nueva sin autoridad.", "HUMAN_REQUIRED"),
    ("DESIGN_COMPONENT", "Usar token DEPRECADO.", "SCOPED_BLOCK"),
    ("FIELD_CONTRACT", "Agregar campo nuevo sin fuente.", "HUMAN_REQUIRED"),
    ("VALIDATION", "Modificar min/max sin fuente.", "HUMAN_REQUIRED"),
    ("STATE_TRANSITION", "Eliminar permission guard de transición.", "GLOBAL_ESCALATE"),
    ("ERROR_UI_MESSAGE", "Mensaje divulga detalle sensible.", "SCOPED_BLOCK"),
    ("API_DATA_CONTRACT", "Cambiar payload/formato de exportación.", "HUMAN_REQUIRED"),
    ("API_DATA_CONTRACT", "Pedido artifact-only de copy con API_DATA_CONTRACT global abierto.", "SCOPED_CANDIDATE"),
    ("COPY_RECONCILIATION", "Cambiar copy de forma desconocida y material.", "GLOBAL_ESCALATE"),
    ("ERROR_UI_MESSAGE", "Crear error nuevo no definido.", "HUMAN_REQUIRED"),
    ("STATE_TRANSITION", "Mantener estados y transiciones vigentes.", "SCOPED_CANDIDATE"),
    ("API_DATA_CONTRACT", "Cambiar comportamiento de filtros/query.", "GLOBAL_ESCALATE"),
    ("UNKNOWN_SURFACE", "Mutación cualquiera.", "HUMAN_REQUIRED"),
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
    "schema": "INPUT_GOV_CHANGE_IMPACT_RESOLVER_READONLY_EVAL_V1",
    "authority": {
        "governance_issue": 414,
        "adjudication_run_id": 75,
        "handoff_message_id": 41,
        "gold_status": "CANDIDATE_RESEARCH",
        "scoped_pass_authorized": False,
        "downstream_authorized": False,
        "production_authorized": False,
    },
    "runtime_authority": {
        "behavioral_contract_present": runtime.behavioral_contract_present,
        "operation_schema_authority_materialized": runtime.operation_schema_authority_materialized,
    },
    "resolver_quality": {
        "cases": len(gold),
        "families": len({row['case_family'] for row in gold}),
        "exact_decision_accuracy": accuracy,
        "impact_precision": precision,
        "impact_recall": recall,
        "unsafe_under_block": unsafe_under_block,
        "unnecessary_global_block": unnecessary_global_block,
        "unknown_mixed_fail_closed_violations": unknown_mixed_fail_closed_violations,
        "shared_nonstable_fail_closed_violations": shared_nonstable_fail_closed_violations,
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
        "input_mutation_utf8_bytes": sum(len((str(row['case_family']) + str(row['mutation'])).encode('utf-8')) for row in gold),
        "tokens": "NOT_OBSERVED",
        "depth": "NOT_CLAIMED_BY_THIS_HARNESS",
    },
    "quality_domains": {
        "resolver_quality": "MEASURED",
        "gate_quality": "NOT_EXECUTED_BY_THIS_HARNESS",
        "profile_quality": "NOT_EXECUTED_BY_THIS_HARNESS",
        "orchestrator_quality": "NOT_EXECUTED_BY_THIS_HARNESS",
    },
    "failures": {
        "decision_or_impact_mismatches": [
            item for item in results
            if item["expected_decision"] != item["actual_decision"]
            or item["expected_impacts"] != item["actual_impacts"]
        ],
        "adversarial_failures": adversarial_failures,
    },
}

print(json.dumps(summary, ensure_ascii=False, sort_keys=True))

assert accuracy == 1.0
assert precision == 1.0
assert recall == 1.0
assert unsafe_under_block == 0
assert unnecessary_global_block == 0
assert unknown_mixed_fail_closed_violations == 0
assert shared_nonstable_fail_closed_violations == 0
assert not adversarial_failures
