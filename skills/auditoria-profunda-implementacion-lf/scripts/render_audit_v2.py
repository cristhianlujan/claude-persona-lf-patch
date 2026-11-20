#!/usr/bin/env python3
"""Render exact report data as accessible Markdown and colored contract matrix."""
import argparse
import html
import json
from pathlib import Path
from audit_v2 import COLORS, negative_coverage

LABELS = {"ACCEPTABLE": "Aceptable", "WEAK": "Débil", "MISSING": "Faltante", "CONTRADICTORY": "Contradictorio",
          "NOT_EVALUATED": "No evaluado", "NOT_APPLICABLE": "No aplica", "LOW": "Bajo", "MEDIUM": "Medio"}


def esc(value): return html.escape(str(value), quote=True)
def md(value): return str(value).replace("|", "\\|").replace("\n", " ")


def render(report, profile_data):
    columns = profile_data["columns"]
    c = report["completion"]
    verdict = "FLUJO ACREDITADO" if c["flow_verdict"] == "FLOW_ACCREDITED" else "FLUJO NO ACREDITADO"
    context = report["audit_context"]
    lines = ["# Auditoría Perfil → IG → Perfil — reporte V2", "",
        f"**{verdict}.** Cobertura del lote conocido: **{c['lot_coverage_percent']} %**. Nueva ejecución E2E: **{context['new_e2e_executed']}**.", "",
        "La tabla muestra observaciones precisas y sus límites. Un estado guardado como PASS no acredita por sí mismo el comportamiento completo.", "",
        "## Lo que funcionó y lo que falta por paso", "",
        "| Paso | Qué se comprobó | Estado reportado | Tipo de evidencia | Recibo / evidencia | Falta comprobar | Confianza |",
        "|---|---|---|---|---|---|---|"]
    for s in report["steps"]:
        lines.append("| " + " | ".join(map(md, [s["order"], s["what_worked"], s["reported_status"], s["evidence_kind"],
            str(s["receipt_ref"]) + "; " + ", ".join(s["evidence_refs"]), "; ".join(s["unresolved"]), s["confidence"] + ": " + s["confidence_reason"]])) + " |")
    lines += ["", "## SQL medido e inventario pendiente", "",
        "ANALYZE ejecuta el SELECT. Los planes medidos se capturaron con BEGIN READ ONLY y ROLLBACK, timeout de 3 s. Las funciones escritoras no se invocaron.", "",
        "| Consulta | Rol | Tablas / joins | Índices existentes | Ejecución ms | Buffers hit/read | Muestras | Frecuencia | Materialización |",
        "|---|---|---|---|---|---|---|---|---|"]
    for q in report["sql_queries"]:
        lines.append("| " + " | ".join(map(md, [q["id"], q["role"], ", ".join(q["tables"]) + "; " + "; ".join(q["joins"]),
            ", ".join(q["existing_indexes"]) or "No resueltos", q["execution_ms"] if q["measurement_status"] == "MEASURED" else "NO MEDIDO",
            f"{q['shared_hit_blocks']}/{q['shared_read_blocks']}", q["sample_count"], "Medida" if q["frequency_measured"] else "NO MEDIDA", q["materialization_decision"]])) + " |")
    lines += ["", "Hay consultas del flujo y consultas creadas para esta auditoría: sus costos no se atribuyen entre sí. Una muestra no acredita p95, cache fría ni concurrencia. El SQL interno dinámico no resuelto sigue fuera de cobertura. Un nodo Materialize no es una vista materializada.", "",
        "## Transporte en cada salto", "", "| Salto | Emisor → receptor | Campos enviados | Perdidos | RUN | Hash y significado | No verificado |", "|---|---|---|---|---|---|---|"]
    for h in report["hops"]:
        lines.append("| " + " | ".join(map(md, [h["id"], h["sender"] + " → " + h["receiver"], ", ".join(h["fields_sent"]),
            ", ".join(h["fields_lost"]) or "Sin pérdida demostrada", h["run_binding"], h["hash_binding"] + ": " + h["hash_semantics"], "; ".join(h["unverified"])])) + " |")
    metrics = report["run_sample"]["metrics"]
    lines += ["", "## Muestra de corridas", "", f"N solicitado: {report['run_sample']['requested_n']}; N observado: {metrics['sampled_runs']}.", "",
        "Estados observados: " + md(metrics["run_status_counts"]) + ".", "",
        "| Indicador | Numerador / denominador | Interpretación |", "|---|---|---|",
        f"| PASS sin referencia | {metrics['pass_missing_evidence_ref']} / {metrics['persisted_pass_steps']} ({metrics['pass_missing_evidence_ref_percent']} %) | Presencia de puntero; no calidad semántica |",
        f"| IG reportado sin invocación registrada | {metrics['ig_reported_without_invocation']} / {metrics['ig_reported_runs']} ({metrics['ig_reported_without_invocation_percent']} %) | Señal de nomenclatura/observabilidad; IG puede ser opcional |",
        "| Tasa real de falsos PASS | NO MEDIDA | Requiere resolver contrato y ejecutar negativos por caso |", "",
        "## Matriz de contratos", "", "🟢 Aceptable · 🟡 contenido débil · 🔴 faltante/contradicción · ⚪ no evaluado · — no aplica. La nota no usa longitud ni cantidad de palabras.", "",
        "| Contrato / tipo | " + " | ".join(columns.values()) + " | Nota |",
        "|---|" + "---|" * (len(columns) + 1)]
    html_rows = []
    for r in report["contracts"]:
        values, cells = [], []
        for field in columns:
            cell = r["fields"][field]; state = cell["status"]; icon, color = COLORS[state]
            values.append(icon + " " + LABELS[state])
            detail = ("<p><b>Literal:</b></p><pre>" + esc(cell["literal"] if cell["literal"] is not None else "Ausente / no leído") + "</pre>"
                + "<p><b>Evaluación contextual:</b> " + esc(cell["reason"]) + "</p>"
                + "<p><b>Obligación del consumidor:</b> " + esc(cell["consumer_expectation"]) + "</p>"
                + "<p><b>Fuente:</b> " + esc("; ".join(cell["source_refs"])) + "</p>"
                + "<p><b>Redacción / corrección propuesta:</b></p><pre>" + esc(cell["proposed_rewrite"] or "No requerida / pendiente de evaluación") + "</pre>")
            cells.append(f'<td style="background:{color}"><details><summary>{icon} {esc(LABELS[state])}</summary>{detail}</details></td>')
        lines.append("| " + md(r["id"] + " " + r["name"] + " / " + r["type"]) + " | " + " | ".join(values) + " | " + LABELS[r["grade"]] + " |")
        html_rows.append('<tr data-grade="' + esc(r["grade"]) + '"><th scope="row">' + esc(r["id"] + " " + r["name"]) + "<small>" + esc(r["type"] + " · " + r["format"]) + "</small></th>" + "".join(cells) + "<th>" + esc(LABELS[r["grade"]]) + "</th></tr>")
    lines += ["", "Cada celda del HTML incluye literal, fuente, motivo contextual y propuesta exacta. Nota contractual no equivale a aprobación del flujo. Revisión de contenido: CURRENT_CONTEXT_SPEC; no acredita independencia.", ""]
    for r in report["contracts"]:
        lines += ["### " + r["id"] + " — " + r["name"], ""]
        for key, cell in r["fields"].items():
            if cell["status"] in ("WEAK", "MISSING", "CONTRADICTORY"):
                lines += ["- " + columns[key] + ": **" + LABELS[cell["status"]] + "**. " + cell["reason"],
                          "  Propuesta: " + str(cell["proposed_rewrite"]), "  Fuente: " + "; ".join(cell["source_refs"])]
        lines.append("")
    nc = negative_coverage(report["pass_emitters"])
    lines += ["## Barrido de PASS", "", f"Sitios inventariados: {len(report['pass_emitters'])}; emisores confirmados por lectura contextual: {nc['emitters']}; negativos que rechazaron la entrada rota: {nc['negatives_verified']}.", "",
        "Los negativos que ACEPTAN entrada rota se muestran como defecto, nunca como verificación verde. Los sitios no ejecutados conservan pendiente su negativo. Emisiones dinámicas no agotadas: la cobertura no es exhaustiva.", "",
        "| Archivo:línea | Marcador | Clasificación | Evidencia exigida por contrato | Negativo | Dictamen contextual |", "|---|---|---|---|---|---|"]
    for e in report["pass_emitters"]:
        lines.append("| " + " | ".join(map(md, [e["file"] + ":" + str(e["line"]), e["marker"], e["classification"],
            "; ".join(e["evidence_required"]), e["negative_test"]["status"] + ": " + e["negative_test"]["expected_rejection"], e["context_review"]])) + " |")
    lines += ["", "## Hallazgos y procedencia", "", "| ID | Estado | Tipo de evidencia | Confianza y motivo | Defecto |", "|---|---|---|---|---|"]
    for f in report["findings"]:
        lines.append("| " + " | ".join(map(md, [f["id"], f["status"], f["evidence_kind"], f["confidence"] + ": " + f["confidence_reason"], f["defect"]])) + " |")
    for f in report["findings"]:
        loc = f["location"]
        lines += ["", "### " + f["id"], "", "Ubicación: " + loc["file"] + ":" + str(loc["start_line"]) +
            " · " + loc["function"] + " · commit " + loc["commit"], "", "Código encontrado:", "", "```", f["found_code"], "```", "",
            "Esperado: " + f["expected"]["behavior"], "Contrato: " + "; ".join(f["expected"]["contract_refs"]), "",
            "Defecto: " + f["defect"], "", "Causa raíz: " + f["root_cause"], "", "Impacto: " + "; ".join(f["impact"]), "",
            "Corrección propuesta (sin aplicar):", "", "```", f["correction"]["code"], "```", "",
            "Prueba positiva: " + f["positive_test"]["description"] + " · " + str(f["positive_test"]["evidence_ref"]), "",
            "Prueba negativa: " + f["negative_test"]["description"] + " · " + str(f["negative_test"]["evidence_ref"]), "",
            "Resultado observado: " + f["observed_result"]["summary"], "Comando: `" + f["observed_result"]["command"] + "`", "",
            "Readback: " + f["readback"]["consumer"] + " → " + f["readback"]["effect"], "",
            "Estado: " + f["status"] + " · " + f["evidence_kind"] + " · " + f["confidence"] + ": " + f["confidence_reason"]]
    lines += ["", "## Catálogo de evidencia", "", "| ID | Tipo / origen | Captura / afirmación |", "|---|---|---|"]
    for e in report["evidence_catalog"]:
        lines.append("| " + " | ".join(map(md, [e["id"], e["kind"] + " / " + e["origin"], e["capture_ref"] + "; " + e["claim"]])) + " |")
    lines += ["", "## Checklist EKB", "", "Snapshot V1 preservado; estado actual EKB no reconsultado. No sustituye política vigente.", "",
        "| Código | Resultado de esta auditoría | Procedencia | Evidencia |", "|---|---|---|---|"]
    for check in report["checklist"]:
        lines.append("| " + " | ".join(map(md,[check["ekb_code"],check["result"],check["evidence_kind"],", ".join(check["evidence_refs"])])) + " |")
    lines += ["", "## Límites y cierre", ""] + ["- " + x for x in report["limitations"] + c["unknown_scope"]]
    lines += ["", f"**{verdict}.** Cobertura del lote: {c['lot_coverage_percent']} %. No se transforma un lote terminado en aprobación E2E.", ""]
    markdown = "\n".join(lines)
    header = ''.join('<th scope="col">' + esc(label) + '</th>' for label in ["Contrato / tipo", *columns.values(), "Nota"])
    html_text = '''<!doctype html><html lang="es"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Contratos LF — auditoría V2</title><style>
body{font:15px system-ui;margin:24px;color:#172554;background:#fafafa}h1{font-size:25px}p{max-width:1050px;line-height:1.5}.banner{padding:16px;background:#fff7ed;border-left:5px solid #ea580c} .scroll{overflow:auto;max-height:76vh;border:1px solid #cbd5e1}table{border-collapse:separate;border-spacing:0;font-size:13px}th,td{border-right:1px solid #cbd5e1;border-bottom:1px solid #cbd5e1;padding:10px;vertical-align:top;min-width:150px}thead th{position:sticky;top:0;background:#172554;color:white;z-index:2}tbody th:first-child{position:sticky;left:0;background:#eef2ff;z-index:1;min-width:205px}small{display:block;color:#475569;margin-top:7px}summary{cursor:pointer;font-weight:600}pre{white-space:pre-wrap;overflow-wrap:anywhere;max-width:420px}details[open]{min-width:330px}label{display:block;margin:18px 0}select{padding:8px} .full{white-space:pre-wrap;background:white;padding:18px;border:1px solid #cbd5e1;font:13px ui-monospace}
</style><h1>Matriz de calidad contractual LF</h1>'''
    html_text += '<p class="banner"><strong>' + esc(verdict) + '</strong> · Cobertura del lote conocido: ' + esc(c["lot_coverage_percent"]) + ' %. No equivale a E2E nuevo. Cada color incluye texto y detalle expandible.</p>'
    html_text += '<p>🟢 Aceptable · 🟡 contenido presente pero débil · 🔴 falta o contradicción · ⚪ no evaluado · — no aplica. Calificar significado y compatibilidad, sin usar longitud.</p><label>Filtrar nota: <select id="grade"><option value="">Todos</option><option value="LOW">Bajo</option><option value="MEDIUM">Medio</option><option value="ACCEPTABLE">Aceptable</option><option value="NOT_EVALUATED">No evaluado</option></select></label>'
    html_text += '<div class="scroll"><table><thead><tr>' + header + '</tr></thead><tbody>' + ''.join(html_rows) + '</tbody></table></div><h2>Reporte completo y evidencia</h2><p>La evidencia medida, histórica y solo leída se distingue en el reporte. Tabla de pasos, transporte, SQL, muestreo y PASS:</p><div class="full">' + esc(markdown) + '</div>'
    html_text += "<script>document.getElementById('grade').addEventListener('change',function(){for(const r of document.querySelectorAll('tbody tr'))r.hidden=!!this.value&&r.dataset.grade!==this.value;});</script></html>\n"
    return markdown, html_text


if __name__ == "__main__":
    parser = argparse.ArgumentParser(); parser.add_argument("report", type=Path); parser.add_argument("--output-prefix", type=Path, required=True)
    args = parser.parse_args(); root = Path(__file__).resolve().parents[1]
    report = json.loads(args.report.read_text()); profiles = json.loads((root / "references/contract_profiles_v2.json").read_text())
    markdown, html_text = render(report, profiles)
    args.output_prefix.parent.mkdir(parents=True, exist_ok=True)
    args.output_prefix.with_suffix(".md").write_text(markdown, encoding="utf8")
    args.output_prefix.with_suffix(".html").write_text(html_text, encoding="utf8")
