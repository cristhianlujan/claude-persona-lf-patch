# SKILL — ORQUESTADOR PIPELINE LF (ACT-0058)

**Código:** ACT-0058
**Nombre canónico:** SKILL_ORQUESTADOR_PIPELINE_LF
**Estado:** EN_REVISION / CANDIDATE_READ_ONLY
**Tabla de control:** lf_pipeline_runs
**Impacto automático:** BLOQUEADO
**Versión:** v0.1-candidato

## Rol

Orquestador end-to-end del pipeline de inteligencia competitiva LF.
Coordina la ejecución secuencial de las skills de captura, homologación,
análisis de riesgo y escritura en base de conocimiento.

## Ruta obligatoria

Router → v_lf_fuente_operativa → ACT-0058 (EN_REVISION) → lf_pipeline_runs → Operación → Verificación → Cierre

## Pipeline bajo control

```
ACT-0052 Extracción web      ─┐
ACT-0054 Extracción noticias ─┼→ ACT-0053 Homologación → ACT-0056 Análisis riesgo → ACT-0057 KB Write
ACT-0055 Extracción docs reg ─┘
```

## Fuentes objetivo (scheduler)

- reevalua.com
- finanty.com
- perudeudas.info
- youtube.com (canales finanzas PE)
- reddit.com/r/PERU

## Keywords objetivo

- "salir de Infocorp"
- "negociar deuda"
- "constancia de no adeudo"

## Tabla de control: lf_pipeline_runs

| Campo | Tipo | Descripción |
|---|---|---|
| pipeline_run_id | UUID PK | ID único del run |
| source_url | TEXT | URL fuente procesada |
| keyword_matched | TEXT | Keyword disparador |
| stage_current | TEXT | CAPTURA/HOMOLOGACION/ANALISIS/KB_WRITE/COMPLETED/FAILED/HITL |
| stage_status | TEXT | PENDING/RUNNING/COMPLETED/FAILED/HITL |
| capture_run_id | UUID FK | → lf_capture_runs.run_id |
| homolog_record_id | UUID FK | → lf_homologated_records.homolog_id |
| decision_id | UUID FK | → lf_content_decisions.decision_id |
| kb_id | UUID FK | → lf_knowledge_base.kb_id |
| hitl_triggered | BOOLEAN | HITL activado |
| retry_count | INT | Reintentos (max 3) |

## Contratos (12)

| Orden | Código | Stage |
|---|---|---|
| 10 | CONTRACT_ACT0058_S1A_ROUTER_V1 | Router |
| 20 | CONTRACT_ACT0058_S2A_INIT_RUN_V1 | Init + dedup 24h |
| 30 | CONTRACT_ACT0058_S3A_SCOPE_FILTER_V1 | Scope dominios |
| 40 | CONTRACT_ACT0058_S4A_KEYWORD_MATCH_V1 | Keywords |
| 50 | CONTRACT_ACT0058_S5A_STAGE_CAPTURA_V1 | Captura |
| 60 | CONTRACT_ACT0058_S6A_STAGE_HOMOLOG_V1 | Homologación |
| 70 | CONTRACT_ACT0058_S7A_STAGE_ANALISIS_V1 | Análisis riesgo |
| 80 | CONTRACT_ACT0058_S8A_HITL_TRIGGER_V1 | HITL gate |
| 90 | CONTRACT_ACT0058_S9A_STAGE_KB_WRITE_V1 | KB Write |
| 100 | CONTRACT_ACT0058_S10A_COMPLETED_V1 | Completed |
| 110 | CONTRACT_ACT0058_S11A_FAILED_RETRY_V1 | Retry (max 3) |
| 120 | CONTRACT_ACT0058_S12A_AUDIT_TRAIL_V1 | Audit trail |

## Reglas de gobernanza

- impacto_automatico = BLOQUEADO
- No merge a main sin CI verde
- DRY_RUN requerido antes de gate APROBADO
- HITL obligatorio si lf_content_decisions.hitl_required = TRUE
- Deduplicación por source_url en ventana 24h
- retry_count máximo: 3

## Insumo base

Reporte de Inteligencia Competitiva LF (Google Doc ID: 1aeyx7-PqLc1VZI7Fe8Rd5aONnlacjVZQuvHoalSt7R8)
Leído y asimilado en sesión 2026-06-17.

## Evento Supabase

id=319 — CONSTRUCCION_ACTIVO / ACT-0058 / Fases 1-4 completadas

