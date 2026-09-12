# Ejemplos — SKILL_ESCRITURA_BASE_CONOCIMIENTO_LF v0.2

## CASO BUENO — POSITIVO/EDUCATIVO (ALLOW_PROD_GATE)

**Upstream decision:** ALLOW_PROD_GATE
**topic:** reinsercion_financiera
**source_url:** https://finanty.pe/reinsercion
**kb_category:** EDUCACION_FINANCIERA
**kb_polarity:** POSITIVO
**kb_dimension:** EDUCATIVO
**summary:** Finanty ofrece enfoque documental para recuperacion financiera sin promesas de eliminacion.
**key_insights:** ["Enfoque humano sin claim sensible", "Diferenciador vs competidores que prometen eliminar deuda"]
**kb_enriched:**
  identidad: {tipo_contenido: "articulo_educativo", autor_o_fuente: "finanty.pe"}
  confianza: {aliados: ["SBS"], pruebas: ["casos documentados"]}
  conversion: {objeciones_resueltas: ["¿Es legal?", "¿Funciona realmente?"]}
  uso_semantico: {preguntas_respondidas: ["como salir de infocorp"], keywords_primarios: ["infocorp","rehabilitacion"]}
  propuesta_comercial: {diferenciador_lf: "proceso transparente sin promesas falsas", angulo_uso: "educacion top funnel"}
  riesgo_cumplimiento: {flags: [], advertencias: []}
**quality_score:** 8.5
**consumer_ready:** false (DRY_RUN)
**resultado:** PASS_FULL_SKILL_RUN — kb_id generado, readback OK

---

## CASO ALERTA — NEGATIVO/ALERTA (ALERT_CAPTURE)

**Upstream decision:** ALERT_CAPTURE
**topic:** practica_abusiva_deudores
**source_url:** https://www.indecopi.gob.pe/resoluciones/2025-empresa-quita-deudas
**kb_category:** ALERTA_MERCADO
**kb_polarity:** NEGATIVO
**kb_dimension:** ALERTA
**summary:** Empresa "Quita Deudas Peru SAC" sancionada por INDECOPI por cobrar adelantado sin prestar servicio.
**key_insights:** ["Patron de estafa documentado", "Sancion INDECOPI verificada", "Target: deudores vulnerables"]
**kb_enriched:**
  identidad: {tipo_contenido: "resolucion_regulatoria", autor_o_fuente: "INDECOPI"}
  confianza: {aliados: ["INDECOPI"], pruebas: ["Resolucion 0234-2025/SPC"]}
  conversion: {objeciones_resueltas: [], llamadas_accion_validas: ["denuncia ante INDECOPI"]}
  uso_semantico: {preguntas_respondidas: ["como evitar estafas de deudas"], keywords_primarios: ["estafa","cobro adelantado","infocorp"]}
  propuesta_comercial: {diferenciador_lf: "LF no cobra adelantado — modelo transparente", angulo_uso: "contenido de proteccion y diferenciacion"}
  riesgo_cumplimiento: {flags: ["mencionar empresa requiere verificacion legal"], advertencias: ["no usar nombre empresa sin asesor legal"]}
**alert_actor:** "Quita Deudas Peru SAC"
**alert_evidence_url:** "https://www.indecopi.gob.pe/resoluciones/2025-empresa-quita-deudas"
**quality_score:** 9.0
**consumer_ready:** false (requiere revision legal antes de publicar)
**resultado:** PASS_FULL_SKILL_RUN — kb_id generado como NEGATIVO/ALERTA

---

## CASO REGULATORIO — NEUTRAL/REGULATORIO (ALLOW_PROD_GATE)

**Upstream decision:** ALLOW_PROD_GATE
**topic:** prescripcion_deudas_peru
**source_url:** https://www.sbs.gob.pe/normativa/prescripcion-creditos
**kb_category:** MARCO_REGULATORIO
**kb_polarity:** NEUTRAL
**kb_dimension:** REGULATORIO
**summary:** Norma SBS sobre plazos de prescripcion de deudas en el sistema financiero peruano.
**key_insights:** ["Plazo 10 años hipotecas", "Plazo 3 años deudas de consumo", "Prescripcion no elimina de Infocorp automaticamente"]
**kb_enriched:**
  identidad: {tipo_contenido: "normativa_oficial", autor_o_fuente: "SBS Peru"}
  confianza: {aliados: ["SBS"], pruebas: ["Resolucion SBS vigente"]}
  conversion: {objeciones_resueltas: ["¿Mi deuda ya prescribio?"], llamadas_accion_validas: ["consultar con asesor"]}
  uso_semantico: {preguntas_respondidas: ["cuando prescribe una deuda en peru"], keywords_primarios: ["prescripcion","deuda","infocorp","plazo"]}
  propuesta_comercial: {diferenciador_lf: "informacion regulatoria verificada", angulo_uso: "contexto educativo de respaldo"}
  riesgo_cumplimiento: {flags: ["prescripcion no equivale a eliminacion KB"], advertencias: ["aclarar diferencia prescripcion vs limpieza historial"]}
**quality_score:** 9.5
**consumer_ready:** false (DRY_RUN)
**resultado:** PASS_FULL_SKILL_RUN

---

## CASO MALO — BLOCKED (sin cambios)

**Upstream decision:** BLOCK_OR_HITL
**Resultado:** BLOCKED_UPSTREAM_DECISION_NOT_ALLOW
**Razon:** Solo ALLOW_PROD_GATE o ALERT_CAPTURE pueden entrar al KB.

---

## CASO AMBIGUO — NEEDS_REPAIR (sin cambios)

**Upstream decision:** ALLOW_PROD_GATE
**topic:** educacion_crediticia
**visible_text:** (muy corto, insuficiente para summary)
**Resultado:** NEEDS_REPAIR — kb_enriched vacio, summary insuficiente
**Accion:** S5-B debe intentar generar kb_enriched con raw_text. Si raw_text insuficiente, marcar failure_reason=kb_enriched_no_generado en pipeline_runs.
