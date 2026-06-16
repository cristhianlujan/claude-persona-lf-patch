# SKILL_EXTRACCION_NOTICIAS_FINANCIERAS_LF

Status: APROBADO / APROBADO_PRODUCCION_CONTROLADA_READ_ONLY
Pack ID: ACT-0054
Version: v0.1
Activo creador: ACT-0043 SKILL_CREATOR_LF
Operation code: EXTRACCION_NOTICIAS_FINANCIERAS_LF
Production blocked: true
Gate aprobado: 2026-06-16 | Criterios: 9 contratos ACTIVE + DRY_RUN CLOSED 2/2 | Evento Supabase: 304-307

## Propósito

Extraer noticias financieras de medios peruanos autorizados (El Comercio, Gestión, RPP,
Peru21, Semana Económica) para alimentar el pipeline de contenido del Marketplace
Libertad Financiera. Solo captura noticias relevantes al dominio LF:
Infocorp, SBS, tasas de crédito, regulación financiera, deuda castigada, finanzas personales.

## Activación

Activar cuando se requiera capturar noticias financieras peruanas vía RSS o URL directa
de artículo de medio autorizado.

## No activar cuando

- El medio no está en la lista blanca LF.
- El contenido no tiene relación con finanzas personales, crédito o regulación.
- El modo de ejecución sea LIVE y el activo esté en estado CANDIDATO.
- El URL ya existe en lf_capture_records (duplicate check).

## Medios autorizados

- El Comercio (sección economía / finanzas)
- Gestión (economía, finanzas personales)
- RPP Noticias (economía)
- Peru21 (economía)
- Semana Económica
- SBS.gob.pe (comunicados oficiales)
- BCRP.gob.pe (notas de prensa)

## Pipeline operativo (S1-A → S7-A)

| Step | ID | Propósito |
|------|----|-----------|
| 1 | S1-A | Router + fuente operativa Supabase |
| 2 | S1-B | Validar fuente: medio autorizado + URL/RSS |
| 3 | S1-C | Confirmar modo sandbox (TEST/DRY_RUN) |
| 4 | S2-A | Duplicate check por url_hash |
| 5 | S3-A | Fetch contenido: titular, cuerpo, fecha, autor |
| 6 | S4-A | Filtro de relevancia LF (score ALTO/MEDIO/BAJO) |
| 7 | S5-A | Clasificación: funnel_stage, topic, risk_level |
| 8 | S6-A | Write a lf_capture_records |
| 9 | S7-A | Cierre lf_capture_runs + evento lf_eventos |

## Temas clave LF

infocorp, historial_crediticio, deuda_castigada, regularizacion_deuda,
consolidacion_deudas, tasa_interes, credito_responsable, sbs_regulacion,
bcrp_politica_monetaria, finanzas_personales_peru

## Output modes

- NOTICIA_CAPTURADA: registro insertado en lf_capture_records
- NOTICIA_IRRELEVANTE: descartada por filtro S4-A
- DUPLICATE_SKIP: URL ya existía en base
- BLOCKED_MEDIO_NO_AUTORIZADO: fuente fuera de lista blanca
- RETURN_TO_WORKER_FOR_SELF_REPAIR

## Regla de bloqueo

Si el score de relevancia es BAJO o el medio no está autorizado,
retornar BLOCKED sin escribir en Supabase.

## Runtime

Este skill es CANDIDATO. No habilitar producción general sin pasar gate formal:
CANDIDATO → EN_REVISION → APROBADO.
