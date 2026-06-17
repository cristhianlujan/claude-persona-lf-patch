---
name: analisis-riesgo-contenido-lf
description: Analiza y clasifica el riesgo de contenido capturado de fuentes financieras
  peruanas. Usar cuando se requiera evaluar si un artículo, noticia o documento regulatorio
  capturado es seguro para producción, necesita revisión humana (HITL) o debe bloquearse
  antes de ingresar al pipeline LF. Activar después de extracción (ACT-0052/0054/0055)
  y antes de generación de contenido.
asset_code: ACT-0056
operation_code: ANALISIS_RIESGO_CONTENIDO_LF
version: v0.1
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

**Código:** ACT-0056  
**Operation code:** ANALISIS_RIESGO_CONTENIDO_LF  
**Estado:** CANDIDATO / READ_ONLY  
**Impacto automático:** BLOQUEADO

## Cuándo usar

- Después de extracción (ACT-0052 / ACT-0054 / ACT-0055)
- Antes de generación de contenido
- Cuando se requiere evaluar riesgo de un artículo, noticia o documento regulatorio capturado

## Cuándo NO usar

- Como puerta de entrada directa (siempre vía Router)
- Sin evidencia verificable de captura previa
- En modo producción sin gate formal

## Decisiones permitidas (5 valores)

| Decisión | Descripción |
|---|---|
| ALLOW_CANDIDATE_READ_ONLY | Contenido válido modo sandbox |
| ALLOW_PROD_GATE | Contenido válido apto producción |
| RESEARCH_OR_HITL | Grounding insuficiente — requiere investigación |
| HITL_REQUIRED | Riesgo alto — requiere revisión humana |
| BLOCK_OR_HITL | P0/P1 crítico — bloquear o escalar |

## Steps internos (9 obligatorios)

1. S1-A Router — verificación fuente operativa
2. S2-A Case Read — leer caso verificable
3. S3-A Visible Evidence — validar evidencia mínima
4. S4-A Classification — clasificar claim/topic/risk_family/funnel
5. S5-A Grounding — check de fundamentación
6. S6-A Risk Judge — P0/P1 + PII + promesas sensibles
7. S7-A HITL Judge — determinar revisión humana
8. S8-A Decision Matrix — emitir decisión dentro de schema
9. S9-A Evidence Close — pack + write lf_content_decisions + evento

## Restricciones

```
NO_PROD: true
NO_RUNTIME_ABIERTO: true
NO_VAL_WRITE: true
NO_ESCRITURA_AUTOMATICA: true
IMPACTO_AUTOMATICO: BLOQUEADO
```

