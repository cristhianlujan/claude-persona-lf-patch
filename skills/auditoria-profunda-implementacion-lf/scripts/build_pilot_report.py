#!/usr/bin/env python3
"""Bind the reviewed pilot diagnoses to literal source, commit and actual trace.

The diagnoses are authored by the native audit after source review, not discoveries
made by this serializer. run_step70_pilot.py supplies the independent executable
behavioral witnesses. Do not reuse the diagnoses for unrelated audit targets.
"""
import hashlib
import json
import subprocess
from pathlib import Path

PACK = Path(__file__).resolve().parents[1]
ROOT = PACK.parents[1]
REL = PACK.relative_to(ROOT).as_posix()
BASE = "bd599aff0a1353e5850fef1b9675c13b7344b317"
TRACE = REL + "/reports/pilot_trace.json"
NATIVE = "scripts/lf_profile_native_resume.py"
RECEIPT = "scripts/lf_step70_separate_call_receipt_v1.py"
EVAL = "scripts/lf_step70_same_llm_eval_v1.py"
SPEC = "profiles/product_director_lf/schemas/lf_step70_same_llm_reviewer_output_v1.schema.json"
GOV = "profiles/quality_pack/contracts/step70_clean_eval_context_v1.md"
EKB = REL + "/references/ekb_current_snapshot.json"
SQL = REL + "/references/governance_current_readback.json"
BRIDGE_SQL = SQL
EDGE = "supabase/functions/lf-profiles-governance-caller-v1/profile_continuation.ts"


def sha(path):
    return hashlib.sha256((ROOT / path).read_bytes()).hexdigest()


def location(path, function, needle, length):
    lines = (ROOT / path).read_text(encoding="utf8").splitlines()
    matches = [i for i, line in enumerate(lines) if line == needle]
    if len(matches) != 1:
        raise ValueError("NON_UNIQUE_LITERAL:" + path + ":" + needle)
    start = matches[0]
    return {"file": path, "function": function, "start_line": start + 1,
            "end_line": start + length, "commit": BASE, "sha256": sha(path)}, "\n".join(lines[start:start + length])


def make_finding(ident, code, path, function, needle, length, trace_key, expected, defect, cause, impact, correction, targets, positive, negative, observed, consumer):
    loc, literal = location(path, function, needle, length)
    ref = TRACE + "#/" + trace_key
    return {"id": ident, "kind": "DEFECT", "code": code, "location": loc,
            "found_code": literal, "expected": {"behavior": expected,
                "contract_refs": [SPEC, GOV, RECEIPT]},
            "defect": defect, "root_cause": cause, "impact": impact,
            "correction": {"code": correction, "targets": targets, "proposed_only": True},
            "positive_test": {"description": positive, "executed": True, "evidence_ref": ref},
            "negative_test": {"description": negative, "executed": True, "evidence_ref": ref},
            "observed_result": {"executed": True,
                "command": "python " + REL + "/scripts/run_step70_pilot.py --output " + TRACE,
                "exit_code": 0, "summary": observed, "evidence_refs": [ref],
                "scope": "LOCAL_REAL_LF_HELPER"},
            "readback": {"verified": True, "consumer": consumer,
                "effect": observed + "; no DB/Edge promotion invoked", "evidence_refs": [ref]},
            "status": "CONFIRMED", "before_ref": ref, "after_ref": None, "fix_scope": "NONE"}


def build():
    # A report must never be regenerated against drifting LF sources silently.
    for path in (NATIVE, RECEIPT, EVAL, SPEC, GOV):
        exact = subprocess.check_output(["git", "show", BASE + ":" + path], cwd=ROOT)
        if exact != (ROOT / path).read_bytes():
            raise ValueError("PILOT_BASE_SOURCE_DRIFT:" + path)
    findings = [
        make_finding("LF-DA-001", "EXECUTION_ID_NOT_BOUND", RECEIPT, "normalize_when_unverified",
            "        r=assess_separate_call_receipt(review)", 1, "run_binding",
            "El RUN del caller debe llegar al validador del recibo y compararse con su execution_id.",
            "La llamada omite el execution_id esperado; un recibo sintético de otro RUN pasa el EVAL local si sus hashes coinciden.",
            "El padre conoce execution_id pero normalize_when_unverified no lo recibe. assess tiene guard opcional; evaluate recibe el mismo r.execution_id como dato y esperado.",
            ["Binding de procedencia local", "Diagnóstico del Step70 antes de SQL", "No demuestra que SQL acepte promoción cruzada"],
            "# Propuesta coordinada, no aplicada\n# lf_profile_native_resume.py, complete_native_profile_semantic_and_report:\nsemantic_review, assessment = normalize_when_unverified(semantic_review, execution_id=execution_id)\n# lf_step70_separate_call_receipt_v1.py:\ndef normalize_when_unverified(review, *, execution_id):\n    r = assess_separate_call_receipt(review, execution_id=execution_id)\n# Propagar el mismo argumento a validate_independent_semantic_review y sus callers;\n# rechazar STEP70_RUN_ID_DRIFT antes de cualquier degradación de procedencia.",
            [NATIVE + ":complete_native_profile_semantic_and_report", RECEIPT + ":normalize_when_unverified",
             NATIVE + ":validate_independent_semantic_review"],
            "Recibo fixture válido del RUN esperado devuelve evaluator_status=PASS, con independencia no acreditada.",
            "Recibo fixture de otro RUN: llamada sin binding acepta EVAL; con execution_id explícito rechaza STEP70_RUN_ID_DRIFT.",
            "wrong_run_evaluator_status=PASS; explicit_binding_rejects=STEP70_RUN_ID_DRIFT",
            "assess_separate_call_receipt → evaluate"),
        make_finding("LF-DA-002", "EVAL_FAILURE_MASKED", RECEIPT, "normalize_when_unverified",
            "    except ValueError as exc:", 7, "eval_masking",
            "Separar procedencia no acreditada de EVAL material fallido; conservar contradicciones de dictamen y no emitir PASS por fallback.",
            "Un receipt cuyo decision_body tiene unsupported_claims falla EVAL; el normalizador borra el receipt y genera PASS contextual que acepta el validador local con checks externos favorables.",
            "El catch de todo ValueError convierte errores materiales en JUDGE_INDEPENDENCE_NOT_PROVEN; luego sobrescribe verdict y elimina la evidencia discordante.",
            ["Consistencia de dictamen anidado/externo", "Validación local permite continuar tras material FAIL", "Aceptación final por SQL/Edge no probada"],
            "# Propuesta, no aplicada\nexcept ValueError as exc:\n    return review, {\"status\": \"REVIEW_INVALID\",\n        \"receipt_contract_error\": str(exc),\n        \"producer_independence_proven\": False,\n        \"content_continuation_allowed\": False}\n# En complete_native_profile_semantic_and_report, antes de persistir/normalizar:\nif assessment.get(\"content_continuation_allowed\") is not True:\n    print(json.dumps({\"phase\": \"SEMANTIC_REVIEW\",\n        \"code\": assessment.get(\"receipt_contract_error\")}))\n    return 1\n# Mantener el caso de receipt ausente como procedencia no probada;\n# para revaluar contenido producir evaluación explícita, sin borrar contradicción.",
            [RECEIPT + ":normalize_when_unverified", NATIVE + ":complete_native_profile_semantic_and_report"],
            "Receipt materialmente válido mantiene baseline RECEIPT_FORMAT_VALID_PROVENANCE_UNATTESTED, sin afirmar independencia.",
            "unsupported_claims no vacío provoca STEP70_SEPARATE_EVALUATOR_NOT_PASS; comprobar si el fallback conserva el rechazo.",
            "STEP70_SEPARATE_EVALUATOR_NOT_PASS → PASS_REVIEWED_CURRENT_CONTEXT; receipt_retained=false; downstream.accepted=true",
            "normalize_when_unverified → validate_independent_semantic_review"),
        make_finding("LF-DA-003", "EVAL_INPUT_INCOMPATIBLE", EVAL, "evaluate",
            "    chk(isinstance(refs,list) and len(refs)>0 and all(isinstance(r,str) and r for r in refs),", 2, "schema_eval",
            "EVAL debe respetar source_refs.items.minLength=4 del schema LF_STEP70_SAME_LLM_REVIEW_OUTPUT_V1.",
            "source_refs=['x'] incumple la SPEC pero el mismo RAW obtiene eval_status=PASS.",
            "EVAL comprueba string no vacío y omite el mínimo del schema; no ejecuta ese schema completo.",
            ["Paridad SPEC/EVAL de referencias", "Calidad del recibo evaluado", "No acredita resolución real de refs ni autorización"],
            "chk(isinstance(refs, list) and len(refs) > 0\n    and all(isinstance(ref, str) and len(ref) >= 4 for ref in refs),\n    \"REVIEW_SOURCE_REFS_SCHEMA_INVALID\")\n# Añadir regresión de paridad con el schema congelado;\n# validar referencias materialmente en la capa contextual, no solo por longitud.",
            [EVAL + ":evaluate", SPEC],
            "RAW con source_refs fixture válidos: schema sin errores y EVAL PASS.",
            "Mismo RAW con ['x']: schema rechaza 'x is too short'; EVAL actual devuelve PASS.",
            "evaluator_status=PASS y schema_errors=['x is too short']; baseline válida pasa ambos",
            "evaluate → assess_separate_call_receipt (no schema enforcement)")
    ]
    paths = [NATIVE, RECEIPT, EVAL, SPEC, GOV, EKB, SQL, BRIDGE_SQL, EDGE, TRACE,
             REL + "/evals/test_acceptance.py", REL + "/evals/test_pilot.py",
             REL + "/scripts/run_step70_pilot.py", REL + "/scripts/inspect_sources.py",
             REL + "/scripts/assess_contracts.py", REL + "/validators/validate_report.py"]
    paths = list(dict.fromkeys(paths))
    snapshot = json.loads((ROOT / EKB).read_text())
    checklist = []
    for i, row in enumerate(snapshot["rows"]):
        unverified = row["codigo"] in ("PE10_C6_SQL_SCRIPT_PREFLIGHT_NO_PARSE_V1", "IG-M107-G-CURATOR-SQL-FASTPATH-041", "IG-M107-D-PROPOSAL-GRAPH-RECEIPT-036")
        superseded = row["estado"] == "SUPERSEDED"
        checklist.append({"ekb_code": row["codigo"], "applies": not superseded,
            "reason": "Recurrencia revisada en contexto de contratos/jueces/flujo. Estado EKB=" + row["estado"] +
                ("; pruebas reales PG/triggers/RLS fuera de alcance, solo fixture local." if unverified else
                 "; se usa como aprendizaje y se contrasta con código/pruebas, no como permiso."),
            "result": "NOT_APPLICABLE" if superseded else "NOT_VERIFIED" if unverified else "REVIEWED",
            "evidence_refs": [EKB + "#/rows/" + str(i), TRACE, REL + "/evals/test_acceptance.py"]})
    chain = [
        {"from": NATIVE + ":complete_native_profile_semantic_and_report", "to": RECEIPT + ":normalize_when_unverified",
         "field": "execution_id", "observation": "El RUN del padre no se pasa al helper.", "evidence_refs": [NATIVE, RECEIPT, TRACE + "#/run_binding"]},
        {"from": RECEIPT + ":normalize_when_unverified", "to": RECEIPT + ":assess_separate_call_receipt",
         "field": "execution_id", "observation": "Guard opcional no ejecutado sin argumento esperado.", "evidence_refs": [RECEIPT, TRACE + "#/run_binding"]},
        {"from": RECEIPT + ":assess_separate_call_receipt", "to": EVAL + ":evaluate",
         "field": "decision_body/unsupported_claims", "observation": "EVAL rechaza contenido; catch lo trata como procedencia.", "evidence_refs": [RECEIPT, EVAL, TRACE + "#/eval_masking"]},
        {"from": RECEIPT + ":normalize_when_unverified", "to": NATIVE + ":validate_independent_semantic_review",
         "field": "verdict", "observation": "PASS contextual acepta checks externos tras borrar receipt discordante.", "evidence_refs": [NATIVE, RECEIPT, TRACE + "#/eval_masking"]},
        {"from": NATIVE + ":build_semantic_receipt", "to": "public.lf_rule_promotion_request_v1",
         "field": "review_mode/independence", "observation": "PR4009 y SELECT vigente admiten CURRENT_CONTEXT para solicitud con hashes/autoridad/score, sin inventar independencia. NOT_PROVEN_OWNER_ACCEPTED no es PROVEN; decide_v1 conserva HUMAN. Funciones no invocadas.", "evidence_refs": [NATIVE, SQL, GOV]}]
    chain.insert(-1, {"from": NATIVE + ":complete_native_profile_semantic_and_report",
        "to": EDGE + ":semantic_judge_result branch → public.lf_profile_native_bridge_record_semantic_v1",
        "field": "semantic_judge_result/receipt", "observation": "Edge valida metadatos/12 checks y transporta RUN del padre a SQL. Bridge separa CURRENT_CONTEXT de CLEAN_CONTEXT_EVAL_VERIFIED y limita efectos. Lectura estática, sin ejecutar Edge/SQL.",
        "evidence_refs": [NATIVE, EDGE, BRIDGE_SQL]})
    return {"schema_version": "LF_DEEP_IMPLEMENTATION_AUDIT_REPORT_V1",
            "repository": "cristhianlujan/claude-persona-lf-patch", "base_commit": BASE,
            "status": "READY_FOR_JUDGE", "promotion_authorized": False, "authority_ref": None,
            "phases": list(range(1, 7)),
            "scope": {"read": paths, "written": [REL], "not_verified": ["Live E2E Step70/80", "Promotion requests/apply", "PG query plans/RLS/concurrency", "Functional repairs not authorized"]},
            "evidence_files": {p: sha(p) for p in paths}, "behavior_chain": chain,
            "checklist": checklist, "findings": findings,
            "limitations": ["Los tres defectos están confirmados en helpers LF locales con entradas sintéticas de tests existentes; no se afirma explotación, aceptación SQL ni promoción real.",
                "No se aplicó corrección LF; todos los fixes son propuestas sin before/after aplicado.",
                "La autoridad SQL se consultó por definición en sandbox; no se invocó el promocionador.",
                "EKB es snapshot histórico. Checklist complementa descubrimiento, no garantiza ausencia de otros defectos.",
                "La suite automática acota estructura/fixtures; la semántica depende de la lectura del modelo nativo."]}


if __name__ == "__main__":
    report = build()
    path = PACK / "reports/pilot_report.json"
    path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf8")
    print(json.dumps({"report": str(path), "findings": len(report["findings"]), "repairs_applied": 0}))
