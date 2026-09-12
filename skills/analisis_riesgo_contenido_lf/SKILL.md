---
name: analisis-riesgo-contenido-lf
description: Analiza y clasifica el riesgo de contenido capturado de fuentes financieras
  peruanas. Usar cuando se requiera evaluar si un artículo, noticia o documento regulatorio
  capturado es seguro para producción, necesita revisión humana (HITL) o debe bloquearse
  antes de ingresar al pipeline LF. Activar después de extracción (ACT-0052/0054/0055)
  y antes de generación de contenido. También clasifica kb_polarity y kb_dimension
  para el KB multidimensional LF.
asset_code: ACT-0056
operation_code: ANALISIS_RIESGO_CONTENIDO_LF
version: v0.2
estado: CANDIDATO_READ_ONLY
runtime_estado: CANDIDATE_READ_ONLY
impacto_automatico: BLOQUEADO
aliases:
  - JIE
  - JUICIO_INTERPRETACION_ENGINE
  - analisis_riesgo
  - risk_analysis_lf
tabla_resultados: lf_content_decisions
---

# SKILL_ANALISIS_RIESGO_CONTENIDO_LF

## Identidad

Motor de análisis y clasificación de riesgo de contenido capturado de fuentes financieras peruanas.
Desde v0.2 también determina kb_polarity y kb_dimension para el KB multidimensional LF.

**Código:** ACT-0056
**Operation code:** ANALISIS_RIESGO_CONTENIDO_LF
**Estado:** CANDIDATO / READ_ONLY
**Impacto automático:** BLOQUEADO

## Cuándo usar

- Después de extracción (ACT-0052 / ACT-0054 / ACT-0055)
- Antes de escritura al KB (ACT-0057)
- Cuando se requiere evaluar riesgo de un artículo, noticia o documento regulatorio capturado

## Cuándo NO usar

- Como puerta de entrada directa (siempre vía Router)
- Sin evidencia verificable de captura previa
- En modo producción sin gate formal

## Decisiones permitidas (6 valores)

| Decisión | Descripción | kb_polarity resultante |
|---|---|---|
| ALLOW_CANDIDATE_READ_ONLY | Contenido válido modo sandbox | POSITIVO |
| ALLOW_PROD_GATE | Contenido válido apto producción | POSITIVO |
| ALERT_CAPTURE | Empresa/práctica fraudulenta o noticia negativa verificada | NEGATIVO |
| RESEARCH_OR_HITL | Grounding insuficiente — requiere investigación | — |
| HITL_REQUIRED | Riesgo alto — requiere revisión humana | — |
| BLOCK_OR_HITL | P0/P1 crítico — bloquear o escalar | — |

## Clasificación KB multidimensional (nuevo en v0.2)

En S4-A Classification, además de claim/topic/risk_family/funnel, el skill determina:

| Campo | Valores | Criterio |
|---|---|---|
| kb_polarity_suggested | POSITIVO / NEGATIVO / NEUTRAL | POSITIVO=educa/habilita, NEGATIVO=alerta/protege, NEUTRAL=contexto regulatorio |
| kb_dimension_suggested | EDUCATIVO / ALERTA / REGULATORIO / SEÑAL_MERCADO | Según tipo de fuente y contenido |

### Reglas de clasificación

- Artículo educativo sin claims sensibles → POSITIVO / EDUCATIVO
- Empresa fraudulenta o práctica abusiva verificada → NEGATIVO / ALERTA → decisión ALERT_CAPTURE
- Norma SBS/BCRP/INDECOPI → NEUTRAL / REGULATORIO
- Reddit/YouTube/foro con señal de demanda o alerta → POSITIVO o NEGATIVO / SEÑAL_MERCADO
- Contenido sin valor claro → BLOCK_OR_HITL (no entra al KB)

## Steps internos (10 obligatorios desde v0.2)

1. S1-A Router — verificación fuente operativa
2. S2-A Case Read — leer caso verificable
3. S3-A Visible Evidence — validar evidencia mínima
4. S4-A Classification — clasificar claim/topic/risk_family/funnel + kb_polarity_suggested + kb_dimension_suggested
5. S5-A Grounding — check de fundamentación
6. S6-A Risk Judge — P0/P1 + PII + promesas sensibles
7. S7-A HITL Judge — determinar revisión humana
8. S8-A Decision Matrix — emitir decisión dentro de schema
9. S8-B Alert Capture Gate — si ALERT_CAPTURE: verificar evidencia mínima (fuente oficial o testimonio verificable)
10. S9-A Evidence Close — pack + write lf_content_decisions + evento

## Restricciones

```
NO_PROD: true
NO_RUNTIME_ABIERTO: true
NO_VAL_WRITE: true
NO_ESCRITURA_AUTOMATICA: true
IMPACTO_AUTOMATICO: BLOQUEADO
ALERT_CAPTURE_REQUIERE_EVIDENCIA: true
```
