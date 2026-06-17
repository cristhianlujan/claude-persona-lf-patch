---
name: escritura-base-conocimiento-lf
description: Persiste contenido validado por ACT-0056 en la base de conocimiento LF.
  Usar cuando una decision ALLOW_PROD_GATE ha sido emitida por SKILL_ANALISIS_RIESGO_CONTENIDO_LF
  y el contenido debe escribirse en lf_knowledge_base para uso downstream. Activar
  despues de analisis de riesgo (ACT-0056) y antes de generacion de contenido o social listening.
asset_code: ACT-0057
operation_code: ESCRITURA_BASE_CONOCIMIENTO_LF
version: v0.1
estado: CANDIDATO_READ_ONLY
runtime_estado: CANDIDATE_READ_ONLY
impacto_automatico: BLOQUEADO
aliases:
  - kb_writer
  - escritura_kb
  - knowledge_base_writer
upstream_skill: ACT-0056
upstream_filter: ALLOW_PROD_GATE
tabla_resultados: lf_knowledge_base
---

# SKILL_ESCRITURA_BASE_CONOCIMIENTO_LF

## Identidad

Persiste contenido validado en la base de conocimiento LF. Cierra el pipeline de ingesta.

**Codigo:** ACT-0057
**Operation code:** ESCRITURA_BASE_CONOCIMIENTO_LF
**Estado:** CANDIDATO / READ_ONLY
**Impacto automatico:** BLOQUEADO

## Posicion en el pipeline

```
ACT-0052/0054/0055 (Extraccion)
  -> ACT-0053 (Homologacion)
    -> ACT-0056 (Analisis Riesgo) -- ALLOW_PROD_GATE
      -> ACT-0057 (Escritura KB) <- AQUI
        -> Generacion contenido / Social Listening
```

## Cuando usar

- Cuando ACT-0056 emite decision ALLOW_PROD_GATE
- Para persistir conocimiento validado en lf_knowledge_base
- Como paso previo a generacion de contenido o social listening

## Cuando NO usar

- Sin decision ALLOW_PROD_GATE verificada de ACT-0056
- Sin gate formal en modo DRY_RUN/SANDBOX
- Como puerta de entrada directa (siempre via Router)

## Steps internos (9 obligatorios)

1. S1-A Router
2. S2-A Upstream Decision Read -- solo ALLOW_PROD_GATE
3. S3-A Content Validation
4. S4-A KB Classification
5. S5-A Summary Generation
6. S6-A Dedup Check
7. S7-A KB Write
8. S8-A Readback Verification
9. S9-A Evidence Close

## Restricciones

```
NO_PROD: true
NO_RUNTIME_ABIERTO: true
NO_VAL_WRITE: true
NO_ESCRITURA_AUTOMATICA: true
IMPACTO_AUTOMATICO: BLOQUEADO
```
