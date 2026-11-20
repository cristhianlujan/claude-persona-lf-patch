#!/usr/bin/env python3
"""Serialize this pilot's measured captures and explicit native review.

Not an autonomous auditor. Re-run discovery and semantic review for a new target;
never reuse these authored diagnoses as if newly detected or newly executed.
"""
import copy
import datetime as dt
import hashlib
import json
from pathlib import Path
from audit_v2 import STEP_ORDERS, flow_verdict, lot_coverage, plan_summary, sample_metrics
from contract_reviews_v2 import reviews
from render_audit_v2 import render

PACK = Path(__file__).resolve().parents[1]
ROOT = PACK.parents[1]
REL = PACK.relative_to(ROOT).as_posix()
INPUT = REL + "/reports/v2_inputs/"


def read(name): return json.loads((ROOT / (INPUT + name)).read_text())


def build():
    capture = read("source_capture.json")
    binding = read("bindings_readback.json")
    probes = read("negative_probes.json")
    collected = dt.datetime.now(dt.timezone.utc).isoformat()
    run = capture["source_run"]
    evidence = []
    def ev(ident, kind, origin, ref, claim, observed=None, source_run=None):
        evidence.append({"id": ident, "kind": kind, "origin": origin, "capture_ref": ref,
            "capture_sha256": hashlib.sha256((ROOT / ref.partition("#")[0]).read_bytes()).hexdigest(),
            "source_execution_id": source_run, "observed_at": observed,
            "collected_at": collected, "claim": claim})
        return ident
    ev("E-SOURCE", "CODE_READ_ONLY", "SOURCE_FILE", INPUT + "live_functions.sql",
       "Definiciones SQL leídas, incluidas escritoras NO invocadas; no es una migración.")
    ev("E-PRIOR", "MEASURED_PREVIOUSLY", "PRIOR_REPORT", INPUT + "previous_report.json#/text",
       "Informe anterior preservado; sus pruebas no se convierten en mediciones actuales.",
       capture["source_report"]["modified_at"] if "modified_at" in capture["source_report"] else "2026-11-16T03:45:01.150970Z", run)
    ev("E-PARENT", "MEASURED_THIS_AUDIT", "LIVE_EXISTING_RUN", INPUT + "source_capture.json#/parent_rows",
       "SELECT de padre existente COMPLETED; esta auditoría no lo ejecutó.", source_run=run)
    ev("E-BINDINGS", "MEASURED_THIS_AUDIT", "LIVE_EXISTING_RUN", INPUT + "bindings_readback.json#/rows",
       "Proyección actual de enlaces guardados; no rehash de los artefactos originales.", source_run=run)
    ev("E-PROBES", "MEASURED_THIS_AUDIT", "LOCAL_HELPER", INPUT + "negative_probes.json",
       "Reproductores actuales sobre helpers LF con entradas sintéticas y red prohibida; no E2E.", probes["executed_at"])
    ev("E-COHORT", "MEASURED_THIS_AUDIT", "LIVE_EXISTING_RUN", INPUT + "source_capture.json#/cohort",
       "Últimas 20 corridas de cuatro perfiles: presencia de referencias y señal IG, no tasa semántica de falsos PASS.")
    ev("E-SCAN", "CODE_READ_ONLY", "SOURCE_FILE", INPUT + "pass_scan.json",
       "Barrido estático acotado a seis archivos; la clasificación contextual se revisó nativamente.")
    ev("E-CONTRACTS", "CODE_READ_ONLY", "SOURCE_FILE", REL + "/scripts/contract_reviews_v2.py",
       "Revisión nativa por tipo, literal y consumidor; misma autoría/contexto, sin autoridad de efectos.")
    ev("E-EKB", "CODE_READ_ONLY", "SOURCE_FILE", REL + "/references/ekb_current_snapshot.json",
       "Snapshot EKB histórico de V1 leído; V2 no vuelve a certificar vigencia por SQL.")
    ev("E-METADATA", "MEASURED_THIS_AUDIT", "LIVE_METADATA", INPUT + "runtime_metadata.json#/rows/0",
       "Cierre: PG17.6, supabase_read_only_user. Cambiaron hashes de bridge_prepare y record_report desde la captura inicial; no se reauditaron esas nuevas definiciones.",
       read("runtime_metadata.json")["rows"][0]["captured_at"])
    ev("E-CURRENTNESS", "CODE_READ_ONLY", "SOURCE_FILE", INPUT + "base_currentness.json",
       "Comparación Git: los tres helpers Step70 no cambiaron entre fuente auditada y base de entrega; SQL dinámico nuevo sin reauditar.")
    rows = {r["step_order"]: r for r in capture["step_rows"]}
    facts = {
        0: "Existe el padre y un recibo de init_execution enlazado por execution_id.",
        10: "Existe referencia de autorización del Router y el paso está persistido como PASS.",
        20: "El paso identifica PERFIL-PRODUCT-DIRECTOR-LF y la fuente lf_activos.",
        30: "Se guardaron revisión bd599aff y digest de la fuente del perfil.",
        40: "Se guardaron scope y finding de selección; receipts=[]: no prueba ejecución IG.",
        45: "Se guardó context_receipt_ref y digest de contexto.",
        47: "La política guardada dice research_baseline NOT_REQUIRED / NOT_APPLICABLE.",
        50: "Se guardó artefacto del perfil con digest de candidato y digest del contexto 45.",
        60: "Se guardó validación determinista PASS y el mismo digest externo de 50.",
        70: "Se guardó PASS_REVIEWED_CURRENT_CONTEXT con candidato/alcance enlazados; no prueba independencia.",
        80: "Se guardó reporte con no_write_performed=true e ig_findings_reported=true; no es recibo IG."}
    steps = []
    for order in STEP_ORDERS:
        row = rows[order]
        ident = ev("E-STEP-" + str(order), "MEASURED_THIS_AUDIT", "LIVE_EXISTING_RUN",
            INPUT + "source_capture.json#/step_rows/" + str(capture["step_rows"].index(row)),
            "SELECT actual: " + facts[order] + " Puntero guardado: " + str(row["evidence_ref"]),
            row["observed_at"], run)
        unresolved = ["Resolver el recibo/artefacto referenciado y cotejar contenido, hash, autoridad y consumidor.",
                      "No es una ejecución nueva de esta auditoría."]
        if order == 40: unresolved.append("IG no fue invocado en esta corrida; selector opcional y ejecución son obligaciones distintas.")
        if order == 60: unresolved.append("El raw hash interno de source_bound_validation difiere del digest externo; comprobar representación antes de diagnosticar drift.")
        steps.append({"order": order, "name": row["step_id"], "execution_id": run,
            "reported_status": row["status"], "what_worked": facts[order],
            "receipt_ref": row["evidence_ref"],
            "behavior_status": "PERSISTED_RECEIPT_OBSERVED", "runtime_origin": "EXISTING_RUN",
            "evidence_kind": "MEASURED_THIS_AUDIT", "evidence_refs": [ident, "E-BINDINGS"],
            "resolved_receipts": [], "unresolved": unresolved, "confidence": "HIGH",
            "confidence_reason": "Alta para existencia y valores persistidos; no se extrapola a ejecución o efecto no revalidado."})
    hop_data = [
        (0,10,"init_execution","Router",["execution_id","profile_code"],"NOT_APPLICABLE","Candidato aún no existe; la autorización tiene referencia propia.",[]),
        (10,20,"Router","profile_resolve",["execution_id","profile_code","authorization_ref"],"NOT_VERIFIED","No se revalidó el digest de autorización; candidate_sha256 aún no aplica.",[]),
        (20,30,"profile_resolve","profile_source_read",["profile_code","source_ref","source_revision"],"SOURCE_CHECK_OBSERVED","Fuente bd599aff y profile_source_digest guardados; no se rehashó aquí el perfil original.",[]),
        (30,40,"profile_source_read","input_validate",["execution_id","profile_source_ref","input_context","resolved_scope"],"NOT_VERIFIED","Hash de fuente y scope son identidades diferentes; falta traza del derivado.",[]),
        (40,45,"input_validate","context_admission",["execution_id","scope_sha256","input_governance","skill_findings"],"NOT_VERIFIED","scope→context_receipt es derivación, no comparación de hashes iguales.",["Resolución de scope requerida antes de seleccionar IG no demostrada en el input del selector; evidencia anterior describe llegada tardía."]),
        (45,47,"context_admission","research_baseline_freeze",["execution_id","context_receipt_ref","context_receipt_digest"],"NOT_APPLICABLE","Baseline se declara NOT_REQUIRED; no se exige candidato antes de 50.",[]),
        (47,50,"research_baseline_freeze","execute_profile",["execution_id","research_baseline_binding","context_receipt_digest"],"RECORDED_MATCH","Digest de contexto 45=50; baseline NOT_APPLICABLE guardado, sin forzar hash inexistente.",[]),
        (50,60,"execute_profile","output_validate",["raw_output_sha256","candidate_digest","profile_output_ref"],"RECORDED_MATCH","Digest externo 50=60; el hash de RAW interno corresponde a otra representación pendiente de resolver.",[]),
        (60,70,"output_validate","semantic_judge",["candidate_digest","scope_sha256","deterministic_validation"],"RECORDED_MATCH","848f908e… es el mismo candidato externo 50/60/70 tras quitar prefijo sha256:.",[]),
        (70,80,"semantic_judge","report_output",["candidate_sha256","scope_packet_sha256","verdict","evaluation_mode"],"RECORDED_MATCH","Candidato y scope guardados coinciden 70/80; no prueba autorización de efecto.",[])]
    hops = [{"id": "H-" + str(a) + "-" + str(b), "from_step": a, "to_step": b,
        "sender": sender, "receiver": receiver, "fields_sent": fields, "fields_lost": lost,
        "run_binding": "RECORDED_PARENT_MATCH", "hash_binding": state, "hash_semantics": meaning,
        "applicability_reason": "Identidad aplicable a esta fase; no exigir candidate_sha256 antes de producir el candidato.",
        "evidence_refs": ["E-STEP-" + str(a), "E-STEP-" + str(b), "E-BINDINGS", "E-SOURCE"],
        "unverified": ["Se cotejan registros del mismo padre, no una traza nueva del transporte."] +
                      (["Resolver/recalcular el hash aplicable."] if state == "NOT_VERIFIED" else [])}
        for a,b,sender,receiver,fields,state,meaning,lost in hop_data]
    for sender, receiver, suffix in [("input_validate", "IG runtime", "REQUEST"), ("IG runtime", "execute_profile", "RETURN")]:
        hops.append({"id": "H-IG-" + suffix, "from_step": 40, "to_step": 50,
            "sender": sender, "receiver": receiver, "fields_sent": [], "fields_lost": [],
            "run_binding": "NOT_APPLICABLE", "hash_binding": "NOT_APPLICABLE",
            "hash_semantics": "No hay invocación IG registrada; no se inventa request, respuesta ni hash.",
            "applicability_reason": "IG es opcional en este run; queda sin prueba del recorrido con IG ejecutado.",
            "evidence_refs": ["E-STEP-40", "E-COHORT"], "unverified": ["Recorrido E2E que invoque y consuma IG."]})
    indexes = capture["indexes"] + read("selector_indexes.json")["indexes"]
    queries = []
    measured = [(q,"AUDIT_QUERY", "source_capture.json", i) for i,q in enumerate(capture["query_measurements"])]
    measured += [(q,"FLOW_QUERY", "runtime_query_plans.json", i) for i,q in enumerate(read("runtime_query_plans.json")["queries"])]
    for query, role, filename, index in measured:
        summary = plan_summary(query["plan"])
        tables = sorted({n["Relation Name"] for n in summary["nodes"] if "Relation Name" in n})
        joins = []
        if query["id"] == "Q_RUNTIME_SELECTION":
            joins = ["policy LEFT JOIN skill_catalog por skill_code", "LEFT JOIN selection_registry por skill_code; descriptor CURRENT y filtros de canal"]
        if query["id"] == "Q_RECENT_COHORT":
            joins = ["cohort LEFT JOIN steps por execution_id", "cohort LEFT JOIN invocations por parent_execution_id"]
        ptr = "/query_measurements/" if filename == "source_capture.json" else "/queries/"
        ident = ev("E-" + query["id"], "MEASURED_THIS_AUDIT", "LIVE_QUERY_PLAN",
            INPUT + filename + "#" + ptr + str(index), "EXPLAIN ANALYZE BUFFERS de SELECT en transacción READ ONLY con ROLLBACK; muestra única.")
        queries.append({"id": query["id"], "sql": query["sql"], "role": role,
            "source_ref": query.get("source_function", "Consulta construida para esta auditoría"),
            "tables": tables, "joins": joins,
            "existing_indexes": sorted({i["indexname"] for i in indexes if i["tablename"] in tables}),
            "measurement_status": "MEASURED", "evidence_refs": [ident], "transaction_read_only": True,
            "rollback_included": True, "analyze_executes_query": True,
            "execution_ms": summary["execution_ms"], "shared_hit_blocks": summary["shared_hit_blocks"],
            "shared_read_blocks": summary["shared_read_blocks"], "sample_count": 1,
            "frequency_measured": False, "frequency_source": None, "materialization_basis": None,
            "materialization_decision": "NOT_EVALUATED", "limitations": [
                "Frecuencia, p95, cache fría y concurrencia no medidos; no autoriza recomendar MV.",
                "Plan y permisos corresponden al rol de lectura usado; RLS del consumidor final no revalidada."]})
    for name in ("lf_profile_native_bridge_prepare_v1", "lf_profile_native_bridge_record_semantic_v1", "lf_profile_native_bridge_record_report_v1"):
        queries.append({"id": "UNMEASURED-" + name, "sql": "-- Definición exportada; NO invocar rutina escritora: " + name,
            "role": "SOURCE_INVENTORY_ONLY", "source_ref": INPUT + "live_functions.sql", "tables": [], "joins": [],
            "existing_indexes": [], "measurement_status": "NOT_MEASURED", "evidence_refs": ["E-SOURCE"],
            "transaction_read_only": False, "rollback_included": False, "analyze_executes_query": True,
            "execution_ms": None, "shared_hit_blocks": None, "shared_read_blocks": None, "sample_count": 0,
            "frequency_measured": False, "frequency_source": None, "materialization_basis": None,
            "materialization_decision": "NOT_EVALUATED", "limitations": [
                "Inventario parcial de fuente; llamadas internas/dinámicas y consultas de otros pasos no agotadas.",
                "ANALYZE ejecutaría la función; ROLLBACK no hace seguros efectos externos o secuencias. No se midió."]})
    emitters = []
    for source in read("pass_scan.json"):
        for item in source["sites"]:
            site = copy.deepcopy(item)
            line, file = site["line"], site["file"]
            site["classification"] = "NOT_EMITTER"
            site["context_review"] = "Comparación/constante de validación: no es una emisión de PASS ni un defecto por contener esa palabra."
            required = ["Contexto válido según SPEC/EVAL", "RUN y hashes aplicables enlazados", "No conceder efecto sin política vigente"]
            expected = "Romper el campo aplicable debe producir código causal y ningún PASS del consumidor."
            tested = None
            if file == "scripts/lf_profile_native_resume.py":
                if line in (913,914,919,920,921,929):
                    site["classification"] = "EMITTER"
                    site["context_review"] = "build_semantic_receipt serializa el dictamen y flags; revisar el validador previo y no confundir procedencia con EVAL material."
                    if line != 914: tested = "EXECUTED_ACCEPTED_BROKEN_INPUT"
                    else: expected = "INDEPENDENT_EVAL_CONTEXT sin aislamiento acreditado no debe emitir independencia; negativo no ejecutado aquí."
                elif site["marker"] == "DYNAMIC:outcome":
                    site["classification"] = "EMITTER_CANDIDATE"
                    site["context_review"] = "Outcome propagado desde consumidor: resolver valores y ramas; no se acredita revisión exhaustiva de emisiones dinámicas."
                elif site["marker"] == "DYNAMIC:status":
                    site["context_review"] = "Estado de transporte/HTTP, no un PASS semántico. Revisar consumidor si sus dominios de estado cambian."
            elif file.endswith("lf_step70_separate_call_receipt_v1.py") and line == 127:
                site["classification"] = "EMITTER"; tested = "EXECUTED_ACCEPTED_BROKEN_INPUT"
                site["context_review"] = "Reproducción actual: EVAL material inválido termina en PASS contextual. Falta de independencia por sí sola sí puede permitir pase contextual."
            elif file.endswith("lf_step70_same_llm_eval_v1.py"):
                site["classification"] = "EMITTER"; tested = "EXECUTED_REJECTED_BROKEN_INPUT"
                expected = "Hash candidato incorrecto debe devolver EVAL FAIL; ejecutado. source_refs=['x'] aún acepta entrada rota, LF-DA-003."
                site["context_review"] = "PASS derivado de errors=[]; negativo de hash rechaza, pero hay obligación SPEC omitida en referencias. Un negativo no prueba todas las ramas."
            elif file.endswith("profile_continuation.ts"):
                site["classification"] = "EMITTER"
                required += ["RPC STEP_RECORDED y STEP_PASS_WITH_EVIDENCE", "Un único paso PASS en getLedger", "GitHub HEAD/sha y autoridad del hijo validados"]
                expected = "RPC rechazado, ledger vacío/duplicado o HEAD inválido debe bloquear sin añadir receipt PASS."
                site["context_review"] = "Emisión del hijo ACTUALIZACION_SKILL_LF, no ejecución IG; guardas leídas, negativo no ejecutado."
            elif file.endswith("lf_generic_rule_engine_and_abandon_v1.sql") and line == 69:
                site["classification"] = "EMITTER"
                required += ["request con status APPLIED", "Readback regla VIGENTE y target enlazado", "Política y score actuales"]
                expected = "Sin autoridad, score o readback VIGENTE, no devolver APPLIED; requiere sandbox aislado de escritura, no ejecutado."
                site["context_review"] = "APPLIED tiene comprobación del request y regla vigente. No ejecutar writer para probar el auditor."
            elif file.endswith("live_functions.sql") and line == 858:
                site["classification"] = "EMITTER"
                required = ["Reporte ligado al RUN y candidato", "Finding/resultado IG identificado por tipo", "No confundir reporte de selección con invocación IG"]
                expected = "Con finding de selección y sin invocación no afirmar IG ejecutado; negativo del writer no ejecutado."
                site["context_review"] = "Asignación ig_findings_reported=true; SELECT confirma 9/9 reportados sin invocación. Semántica de nombre ambigua; no prueba 9 falsos PASS."
            elif site["marker"] == "DEFAULT_TRUE":
                site["classification"] = "RISK_PATTERN_ONLY"
                site["context_review"] = "COALESCE(...,true) actúa como guard fail-closed en este contexto; no marcar defecto sin seguir la negación y su consumidor."
            if site["classification"] in ("EMITTER", "EMITTER_CANDIDATE"):
                site["evidence_required"] = required
                site["negative_test"]["expected_rejection"] = expected
            if tested:
                site["negative_test"].update(status=tested,
                    command="python " + REL + "/scripts/v2_negative_probes.py --output " + INPUT + "negative_probes.json",
                    evidence_refs=["E-PROBES"])
            emitters.append(site)
    prior = json.loads((PACK / "reports/pilot_report.json").read_text())
    findings = copy.deepcopy(prior["findings"])
    for finding in findings:
        suffix = finding["before_ref"].split("#",1)[1]
        ref = INPUT + "negative_probes.json#/step70" + suffix
        for test in (finding["positive_test"], finding["negative_test"]): test["evidence_ref"] = ref
        finding["before_ref"] = ref
        finding["observed_result"]["command"] = "python " + REL + "/scripts/v2_negative_probes.py --output " + INPUT + "negative_probes.json"
        finding["observed_result"]["evidence_refs"] = [ref]
        finding["readback"]["evidence_refs"] = [ref]
        finding.update(evidence_kind="MEASURED_THIS_AUDIT", confidence="HIGH",
            confidence_reason="Reproductor local reejecutado sobre helpers LF sin cambios desde el commit citado; no demuestra aceptación SQL ni promoción.",
            current_audit_evidence_refs=["E-PROBES"])
    tasks = []
    def task(ident, description, status, refs, reason):
        tasks.append({"id": ident, "description": description, "status": status, "evidence_refs": refs, "reason": reason})
    for ident, description, refs in [
        ("T01","Leer reporte previo y distinguir mediciones históricas",["E-PRIOR"]),
        ("T02","Leer 11 pasos persistidos y explicitar lo comprobado",["E-PARENT", "E-BINDINGS"]),
        ("T03","Construir matriz de todos los saltos con identidades aplicables",["E-BINDINGS", "E-SOURCE"]),
        ("T04","Medir 8 SELECT seguros e inventariar writer no ejecutado",["E-Q_STEPS", "E-Q_RUNTIME_SELECTION"]),
        ("T05","Muestrear últimas 20 corridas y denominadores",["E-COHORT"]),
        ("T06","Inventariar y clasificar 45 sitios PASS/riesgo de seis fuentes",["E-SCAN"]),
        ("T07","Reproducir tres defectos de helpers Step70",["E-PROBES"]),
        ("T08","Revisar 13 contratos por tipo/literal/consumidor",["E-CONTRACTS"]),
        ("T09","Distinguir metadatos y digests externos/internos",["E-BINDINGS"])]:
        task(ident, description, "VERIFIED", refs, "Evidencia guardada y alcance exacto visible; no declara completo lo no leído.")
    for ident, description, reason in [
        ("T10","Resolver todos los artefactos originales y rehash de recibos","Punteros guardados no sustituyen descarga/resolución de contenido."),
        ("T11","Frecuencia × costo, p95, cache fría y concurrencia","Una muestra por consulta, sin frecuencia observada."),
        ("T12","Ejecutar negativo por cada emisor PASS y cada rama","Algunos negativos locales ejecutados; writers y dinámicos sin ejecución."),
        ("T13","Agotar SQL/RPC dinámico de los once pasos","Inventario inicial acotado; no se asegura exhaustividad."),
        ("T14","Nuevo E2E Perfil→IG ejecutado→Perfil y efectos del consumidor","La prueba pedida recorre código; no se invocó runtime ni se creó run nuevo.")]:
        task(ident, description, "NOT_EXECUTED", [], reason)
    checklist = [{"ekb_code": c["ekb_code"], "applies": c["applies"], "result": "NOT_VERIFIED",
        "reason": "Antecedente V1 leído y conservado; vigencia EKB no reconsultada en V2. " + c["reason"],
        "evidence_refs": ["E-EKB"], "evidence_kind": "CODE_READ_ONLY"} for c in prior["checklist"]]
    report = {"schema_version": "LF_DEEP_AUDIT_REPORT_V2", "phases": [1,2,3,4,5,6],
        "checklist": checklist, "audit_context": {
        "audit_id": "LF-PIGP-V2-20261116", "source_revision": capture["source_commit"],
        "started_at": capture["exported_at"], "source_execution_id": run,
        "source_run_started_at": capture["parent_rows"][0]["started_at"], "new_e2e_executed": False,
        "ig_execution_required": True, "ig_invocation_verified": False, "promotion_authorized": False, "authority_ref": None},
        "audit_tasks": tasks, "completion": {"lot_coverage_percent": lot_coverage(tasks)["percent"],
            "flow_verdict": "FLOW_NOT_ACCREDITED", "flow_reasons": [], "unknown_scope": [
                "La cobertura usa obligaciones conocidas del lote (9/14); no porcentaje de todo el repositorio.",
                "Cobertura pendiente de consumidores/SQL dinámicos aún no inventariados."]},
        "evidence_catalog": evidence, "steps": steps, "hops": hops, "sql_queries": queries,
        "pass_emitters": emitters, "pass_scan_scope": {
            "files": [s["file"] for s in read("pass_scan.json")], "literal_scan_complete": True,
            "dynamic_emissions_complete": False, "limitations": [
                "Completo para literales detectables en los seis archivos fijados; no para todo LF.",
                "Ramas dinámicas, SQL invocado y negatives de escritores requieren siguiente lote."]},
        "run_sample": {"query": capture["cohort_query"], "requested_n": 20,
            "sampled_runs": len(capture["cohort"]), "metrics": sample_metrics(capture["cohort"]),
            "evidence_refs": ["E-COHORT"], "limitations": [
                "Últimas 20 de cuatro perfiles, no muestra aleatoria ni historial completo.",
                "0 referencias ausentes no equivale a 0 falsos PASS; tasa semántica NO MEDIDA."]},
        "contracts": reviews(), "findings": findings, "limitations": [
            "Revisiones C01/C02/C06/C09 describen snapshots V1 preservados; no se presentan como defecto pendiente ya reparado en V2.",
            "Formatos por tipo y análisis semántico nativo; el script valida consistencia y no decide calidad por palabras.",
            "Nota de contrato aceptable solo acredita el cometido revisado; no independencia ni permiso de promoción.",
            "EKB de V1 se conserva histórico; este lote no vuelve a certificar su vigencia completa.",
            "Fuente auditada 274b3c5; base de entrega a9b1248. Helpers Step70 sin cambios. SELECT final detectó cambios en bridge_prepare/record_report: nuevas definiciones NO REAUDITADAS, ver base_currentness/runtime_metadata.",
            "HTML: estructura/colores/escape verificados estáticamente. Chromium bloqueó socket(); visualización y filtro en navegador NOT_VERIFIED, ver html_readback_v2.json.",
            "Sin producción, migraciones, promoción ni reparaciones funcionales LF. Reporte nuevo no habilita runtime."]}
    result = flow_verdict(report)
    report["completion"].update(flow_verdict=result["verdict"], flow_reasons=result["reasons"])
    return report


if __name__ == "__main__":
    result = build()
    output = PACK / "reports/perfil_ig_perfil_v2.json"
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    md, html = render(result, json.loads((PACK / "references/contract_profiles_v2.json").read_text()))
    output.with_suffix(".md").write_text(md)
    output.with_suffix(".html").write_text(html)
    print(json.dumps({"report": str(output.relative_to(ROOT)), "coverage": result["completion"]["lot_coverage_percent"],
        "flow": result["completion"]["flow_verdict"], "steps": len(result["steps"]), "sql": len(result["sql_queries"]),
        "contracts": len(result["contracts"]), "pass_sites": len(result["pass_emitters"])}))
