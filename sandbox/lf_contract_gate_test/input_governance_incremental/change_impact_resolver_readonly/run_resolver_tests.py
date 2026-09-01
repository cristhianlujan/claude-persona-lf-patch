"""Deterministic benchmark/negative tests for READ_ONLY Change Impact Resolver."""
from __future__ import annotations
import ast, json, re, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
sys.path.insert(0, str(HERE))
from change_impact_resolver_readonly import ResolverContext, resolve

GOLD = ROOT / "sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql"
OVERLAY = HERE / "change_impact_l3c_adjudication_overlay_v1.json"


def parse_gold() -> list[dict]:
    rows = []
    line_re = re.compile(r"^\s*\('CI-[A-Z]+-\d{2}'.*\),?\s*$")
    for line in GOLD.read_text(encoding="utf-8").splitlines():
        if not line_re.match(line):
            continue
        literal = re.sub(r"''", r"\\'", line.strip().rstrip(","))
        try:
            row = ast.literal_eval(literal)
        except Exception as exc:
            raise AssertionError(f"GOLD_PARSE_FAILED:{line}") from exc
        if len(row) != 7: raise AssertionError(f"GOLD_ROW_SHAPE:{row[0]}")
        rows.append({"case_id":row[0],"case_family":row[1],"mutation":row[2],"expected_decision":row[3],
                     "expected_impacts":set(json.loads(row[4])),"source_anchor":row[5],"rationale":row[6]})
    if len(rows) != 50: raise AssertionError(f"GOLD_CASE_COUNT:{len(rows)}")
    return rows


def apply_adjudication(rows: list[dict]) -> list[dict]:
    overlay = json.loads(OVERLAY.read_text(encoding="utf-8"))
    assert overlay["gold_status"] == "CANDIDATE_RESEARCH"
    assert overlay["authorization"] == {"scoped_pass_authorized":False,"downstream_authorized":False,"production_authorized":False}
    by_id = {row["case_id"]: dict(row) for row in rows}
    for case_id, decision in overlay["decision_corrections"].items(): by_id[case_id]["expected_decision"] = decision
    for case_id, additions in overlay["impact_additions"].items(): by_id[case_id]["expected_impacts"] |= set(additions)
    for case_id, anchor in overlay["anchor_replacements"].items(): by_id[case_id]["source_anchor"] = anchor
    return [by_id[row["case_id"]] for row in rows]


def evaluate():
    rows = apply_adjudication(parse_gold())
    ctx = ResolverContext(api_behavioral_contract=True, operation_schema_authority_materialized=False)
    decision_ok = tp = fp = fn = unsafe_under_block = unnecessary_global_block = 0
    unknown_count = mixed_count = shared_count = unknown_fail_closed = mixed_fail_closed = shared_fail_closed = 0
    depths = []
    for row in rows:
        result = resolve(row["case_family"], row["mutation"], ctx)
        decision_ok += int(result.decision == row["expected_decision"])
        tp += len(result.impacted_families & row["expected_impacts"]); fp += len(result.impacted_families - row["expected_impacts"]); fn += len(row["expected_impacts"] - result.impacted_families)
        depths.append(result.depth)
        unknown_count += int(result.unknown); mixed_count += int(result.mixed); shared_count += int(result.shared_dependency)
        unknown_fail_closed += int(result.unknown and result.fail_closed); mixed_fail_closed += int(result.mixed and result.fail_closed); shared_fail_closed += int(result.shared_dependency and result.fail_closed)
        if row["expected_decision"] in {"GLOBAL_ESCALATE","HUMAN_REQUIRED"} and result.decision in {"SCOPED_CANDIDATE","SCOPED_BLOCK"}: unsafe_under_block += 1
        if row["expected_decision"] in {"SCOPED_CANDIDATE","SCOPED_BLOCK"} and result.decision == "GLOBAL_ESCALATE": unnecessary_global_block += 1
    precision = tp/(tp+fp) if tp+fp else 1.0; recall = tp/(tp+fn) if tp+fn else 1.0
    assert decision_ok == 50, f"DECISION_ACCURACY:{decision_ok}/50"
    assert precision == 1.0 and recall == 1.0, (precision, recall)
    assert unsafe_under_block == 0 and unnecessary_global_block == 0
    assert shared_count == 42, f"SHARED_COUNT:{shared_count}"
    assert unknown_count == unknown_fail_closed and mixed_count == mixed_fail_closed

    controls = [
        ("API_DATA_CONTRACT","Crear endpoint alterno sin operation schema authority","HUMAN_REQUIRED",True,True,False),
        ("FIELD_CONTRACT","Agregar campo nuevo sin fuente canónica","HUMAN_REQUIRED",True,True,False),
        ("PERMISSION_BINDING","Reemplazar por permiso existente de otro recurso","GLOBAL_ESCALATE",True,False,True),
        ("ACTION_SEMANTICS","Cambiar action EXPORT -> DELETE","GLOBAL_ESCALATE",True,False,False),
        ("STATE_TRANSITION","Eliminar permission guard de transición","GLOBAL_ESCALATE",True,False,False),
        ("DESIGN_COMPONENT","Usar token DEPRECADO","SCOPED_BLOCK",True,False,False),
        ("ACTION_SEMANTICS","EXPORT permanece EXPORT","SCOPED_CANDIDATE",False,False,False),
    ]
    for family, mutation, expected, fail_closed, unknown, mixed in controls:
        result = resolve(family, mutation, ctx)
        assert result.decision == expected and result.fail_closed is fail_closed and result.unknown is unknown and result.mixed is mixed

    adversarial = [
        ("API_DATA_CONTRACT","Modificar el formato de salida de exportación sin contrato de request/response","HUMAN_REQUIRED"),
        ("API_DATA_CONTRACT","Definir una nueva ruta HTTP sin esquema operativo autorizado","HUMAN_REQUIRED"),
        ("FIELD_CONTRACT","Incorporar un campo de filtro adicional que no está en fuente","HUMAN_REQUIRED"),
        ("ROUTING_NAVIGATION","Añadir navegación inédita sin decisión canónica","HUMAN_REQUIRED"),
        ("PERMISSION_BINDING","Sustituir permiso de historial por permiso de evidencia","GLOBAL_ESCALATE"),
        ("ACTION_SEMANTICS","Transformar la capacidad EXPORT en DELETE","GLOBAL_ESCALATE"),
        ("STATE_TRANSITION","Retirar el guard de permiso de una transición","GLOBAL_ESCALATE"),
        ("FIELD_CONTRACT","Cambiar el tipo de un campo de texto a entero","GLOBAL_ESCALATE"),
        ("VALIDATION","Quitar la validación de un input USER requerido","GLOBAL_ESCALATE"),
        ("ERROR_UI_MESSAGE","Responder 200 ante un caso no autorizado que antes era 403","GLOBAL_ESCALATE"),
        ("COPY_RECONCILIATION","Solo ajustar espacios invisibles manteniendo la misma copy canónica","SCOPED_CANDIDATE"),
        ("DESIGN_COMPONENT","Conservar download_file_action y modificar únicamente el copy","SCOPED_CANDIDATE"),
        ("PERMISSION_BINDING","Conservar B2B_LOAD_HISTORY_EXPORT sin cambios","SCOPED_CANDIDATE"),
        ("ROUTING_NAVIGATION","Conservar B2B_ROUTE_CARGAS_HISTORIAL y SCREEN_ROUTE","SCOPED_CANDIDATE"),
        ("DESIGN_COMPONENT","Seleccionar un token marcado DEPRECADO","SCOPED_BLOCK"),
        ("COPY_RECONCILIATION","Cambiar Exportar por Eliminar historial sin tocar fuente","SCOPED_BLOCK"),
        ("VALIDATION","Añadir validación a un campo SYSTEM de solo lectura","SCOPED_BLOCK"),
        ("ERROR_UI_MESSAGE","Mostrar en el error información sensible interna","SCOPED_BLOCK"),
    ]
    for family, mutation, expected in adversarial:
        result = resolve(family, mutation, ctx)
        assert result.decision == expected, (family, mutation, result.decision, expected)
        if expected != "SCOPED_CANDIDATE": assert result.fail_closed

    print(json.dumps({"resolver_quality":{"cases":50,"exact_decision_accuracy":decision_ok/50,"impact_precision":precision,"impact_recall":recall,
        "unsafe_under_block":unsafe_under_block,"unnecessary_global_block":unnecessary_global_block,
        "unknown_cases":unknown_count,"unknown_fail_closed":unknown_fail_closed,"mixed_cases":mixed_count,"mixed_fail_closed":mixed_fail_closed,
        "shared_dependency_cases":shared_count,"shared_fail_closed":shared_fail_closed,"heldout_controls":len(controls),"heldout_pass":len(controls),
        "adversarial_paraphrases":len(adversarial),"adversarial_pass":len(adversarial),"depth_min":min(depths),"depth_max":max(depths)},
        "authorization":{"scoped_pass_authorized":False,"downstream_authorized":False,"production_authorized":False}}, sort_keys=True))


if __name__ == "__main__": evaluate()
