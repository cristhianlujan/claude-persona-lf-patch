---
name: escritura-base-conocimiento-lf
description: Persiste contenido validado por ACT-0056 en la base de conocimiento LF.
  Usar cuando una decision ALLOW_PROD_GATE o ALERT_CAPTURE ha sido emitida por
  SKILL_ANALISIS_RIESGO_CONTENIDO_LF y el contenido debe escribirse en lf_knowledge_base.
  Desde v0.3 el S5-B Semantic Enrichment es OBLIGATORIO y BLOQUEANTE — si kb_enriched
  queda vacio el INSERT fallara por trigger de BD. No omitir bajo ninguna circunstancia.
  Activar despues de analisis de riesgo (ACT-0056) y antes de generacion de contenido.
asset_code: ACT-0057
operation_code: ESCRITURA_BASE_CONOCIMIENTO_LF
version: v0.3
estado: CANDIDATO_READ_ONLY
runtime_estado: CANDIDATE_READ_ONLY
impacto_automatico: BLOQUEADO
aliases:
  - kb_writer
  - escritura_kb
  - knowledge_base_writer
upstream_skill: ACT-0056
upstream_filter: ALLOW_PROD_GATE | ALERT_CAPTURE
tabla_resultados: lf_knowledge_base
---

# SKILL_ESCRITURA_BASE_CONOCIMIENTO_LF

## Identidad

Persiste contenido validado en la base de conocimiento LF. Cierra el pipeline de ingesta.
Desde v0.3 el S5-B Semantic Enrichment es OBLIGATORIO y BLOQUEANTE — un trigger de BD
rechaza cualquier INSERT con kb_enriched vacio.

**Codigo:** ACT-0057
**Operation code:** ESCRITURA_BASE_CONOCIMIENTO_LF
**Version:** v0.3
**Estado:** CANDIDATO / READ_ONLY
**Impacto automatico:** BLOQUEADO

## Posicion en el pipeline

```
ACT-0052/0054/0055 (Extraccion)
  -> ACT-0053 (Homologacion)
    -> ACT-0056 (Analisis Riesgo) -- ALLOW_PROD_GATE | ALERT_CAPTURE
      -> ACT-0057 (Escritura KB) <- AQUI
        -> Generacion contenido / Social Listening / Alertas usuario
```

## Cuando usar

- Cuando ACT-0056 emite decision ALLOW_PROD_GATE (contenido positivo/neutral)
- Cuando ACT-0056 emite decision ALERT_CAPTURE (contenido negativo verificado)
- Para persistir conocimiento validado en lf_knowledge_base con kb_enriched completo
- Como paso previo a generacion de contenido o social listening

## Cuando NO usar

- Sin decision ALLOW_PROD_GATE o ALERT_CAPTURE verificada de ACT-0056
- Sin gate formal en modo DRY_RUN/SANDBOX
- Como puerta de entrada directa (siempre via Router)
- ALERT_CAPTURE sin alert_evidence_url verificada

## Steps internos (11 obligatorios desde v0.3)

1. S1-A Router
2. S2-A Upstream Decision Read — acepta ALLOW_PROD_GATE o ALERT_CAPTURE
3. S3-A Content Validation
4. S4-A KB Classification — determina kb_category, kb_polarity, kb_dimension
5. S5-A Summary Generation — genera summary y key_insights
6. **S5-B Semantic Enrichment — OBLIGATORIO Y BLOQUEANTE (ver regla abajo)**
7. S6-A Dedup Check
8. S7-A KB Write — escribe con kb_enriched, kb_polarity, kb_dimension
9. S8-A Readback Verification
10. S8-B Alert Verification — si kb_polarity=NEGATIVO: verificar alert_actor y alert_evidence
11. S9-A Evidence Close

## REGLA S5-B — CRITICA — NO OMITIR

**El campo kb_enriched NUNCA puede quedar vacio.**
**Un trigger de BD (trg_block_empty_kb_enriched) rechaza el INSERT si kb_enriched = {}.**
**Si omites S5-B el pipeline falla con error: KB_ENRICHED_VACIO.**

Antes de ejecutar S7-A KB Write, debes completar kb_enriched con la siguiente
estructura. Todos los arrays deben tener al menos 1 elemento. No usar arrays vacios.

```json
{
  "identidad": {
    "tipo_contenido": "ARTICULO_EDUCATIVO | LANDING | BLOG_INDEX | GUIA | NOTICIA",
    "autor_o_fuente": "nombre del sitio o autor",
    "fecha_publicacion": "YYYY-MM-DD o null si no disponible",
    "idioma": "es"
  },
  "confianza": {
    "aliados": ["entidad o institucion que respalda el contenido"],
    "pruebas": ["dato concreto o estadistica mencionada en la fuente"],
    "certificaciones": ["regulacion o ente supervisor mencionado, ej: SBS"]
  },
  "conversion": {
    "objeciones_resueltas": ["objecion del usuario que el contenido responde"],
    "llamadas_accion_validas": ["CTA explicito o implicito en la pagina"]
  },
  "uso_semantico": {
    "preguntas_respondidas": ["pregunta concreta que responde el contenido"],
    "keywords_primarios": ["keyword relevante para LF extraido del contenido"]
  },
  "propuesta_comercial": {
    "diferenciador_lf": "como LF se diferencia o complementa respecto a esta fuente",
    "angulo_uso": "uso_lf: benchmark | senal_mercado | contenido_propio | alerta_competidor"
  },
  "riesgo_cumplimiento": {
    "flags": ["flag regulatorio o legal detectado, ej: claim sin respaldo"],
    "advertencias": ["advertencia necesaria si LF usa este contenido"]
  }
}
```

**IMPORTANTE — summary vs visible_text:**
- visible_text = texto literal o descripcion directa de lo que dice la pagina
- summary = interpretacion para uso interno LF — debe ser DIFERENTE a visible_text
- key_insights = array de strings, minimo 3 insights accionables, NO una sola cadena

**Ejemplo correcto de key_insights:**
```json
[
  "Equifax opera en Peru como ex-Infocorp — LF debe usar nombre actualizado.",
  "Deuda +120 dias en categoria Perdida es negociable con descuento — dato clave para usuario.",
  "Pagar la deuda actualiza centrales en 30 dias pero historial permanece 5 anos — expectativa critica.",
  "Diagnostico con DNI es el patron de conversion que usa el competidor — replicable para LF."
]
```

**Ejemplo INCORRECTO (no usar):**
```json
["central de riesgo / deuda castigada / carta de no adeudo"]
```

## Reglas de clasificacion KB multidimensional

| decision upstream | kb_polarity | kb_dimension |
|---|---|---|
| ALLOW_PROD_GATE + content_type EDUCATIVO | POSITIVO | EDUCATIVO |
| ALLOW_PROD_GATE + fuente SBS/BCRP/INDECOPI | NEUTRAL | REGULATORIO |
| ALLOW_PROD_GATE + fuente social/foro | POSITIVO o NEGATIVO | SENAL_MERCADO |
| ALERT_CAPTURE | NEGATIVO | ALERTA |
| fuente es competidor directo (reevalua, finanty, etc) | NEUTRAL | EDUCATIVO + risk_family=COMPETENCIA |

## Restricciones

```
NO_PROD: true
NO_RUNTIME_ABIERTO: true
NO_VAL_WRITE: true
NO_ESCRITURA_AUTOMATICA: true
IMPACTO_AUTOMATICO: BLOQUEADO
KB_ENRICHED_OBLIGATORIO: true
KB_ENRICHED_VACIO_BLOQUEA_WRITE: true
SUMMARY_DIFERENTE_A_VISIBLE_TEXT: true
KEY_INSIGHTS_MINIMO_3_ITEMS: true
ALERT_CAPTURE_REQUIERE_ALERT_ACTOR: true
```
