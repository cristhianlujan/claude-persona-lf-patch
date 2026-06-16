# SKILL_EXTRACCION_DOCUMENTOS_REGULATORIOS_LF

Status: APROBADO / APROBADO_PRODUCCION_CONTROLADA_READ_ONLY / PRUEBA_SANDBOX_PENDING
Pack ID: ACT-0055
Gate aprobado: 2026-06-16 | Criterios: 9 contratos ACTIVE + DRY_RUN CLOSED 2/2 | Evento Supabase: 307
Version: v0.1
Activo creador: ACT-0043 SKILL_CREATOR_LF
Operation code: EXTRACCION_DOCUMENTOS_REGULATORIOS_LF
Production blocked: true

## Propósito

Extraer y procesar documentos regulatorios oficiales del sistema financiero peruano
(SBS, BCRP, INDECOPI, Congreso) para alimentar el corpus autoritativo del Marketplace
Libertad Financiera. Cubre circulares, resoluciones, reglamentos, notas de prensa
oficiales y tablas de tasas de interés publicadas por entes reguladores.

## Activación

Activar cuando se requiera capturar un documento regulatorio oficial de un dominio
autorizado. Soporta tanto PDFs descargables como páginas HTML con tablas de datos.

## No activar cuando

- El dominio no está en lista blanca regulatoria LF.
- El documento ya existe en lf_capture_records (duplicate check por url_hash o código).
- El impacto LF del documento es BAJO (sin relación con crédito, deuda, tasas o regulación financiera personal).
- El modo sea LIVE y el activo esté en CANDIDATO.

## Dominios autorizados

| Entidad | Dominio | Tipos de documento |
|---|---|---|
| SBS | sbs.gob.pe | Circulares, resoluciones, reglamentos, tasas |
| BCRP | bcrp.gob.pe | Notas de prensa, estadísticas, tasas de referencia |
| INDECOPI | indecopi.gob.pe | Resoluciones protección consumidor financiero |
| Congreso | congreso.gob.pe | Leyes financieras, Ley 29571 |

## Pipeline operativo (S1-A → S7-A)

| Step | ID | Propósito |
|------|----|-----------|
| 1 | S1-A | Router + fuente operativa Supabase |
| 2 | S1-B | Validar dominio autorizado + detectar tipo (PDF/HTML) |
| 3 | S1-C | Confirmar modo sandbox |
| 4 | S2-A | Duplicate check por url_hash + codigo_documento |
| 5 | S3-A | Fetch: PDF parser o HTML parser según tipo |
| 6 | S4-A | Clasificación: tipo_regulatorio, impacto_lf, funnel_stage |
| 7 | S5-A | Write a lf_capture_records (content_type=regulatory_doc) |
| 8 | S6-A | Cierre lf_capture_runs |
| 9 | S7-A | Evento lf_eventos con resumen regulatorio |

## Clasificación de impacto LF

- **ALTO**: tasas de interés, Infocorp/central de riesgos, reprogramación deudas, insolvencia
- **MEDIO**: regulación banca general, protección consumidor financiero, transparencia
- **BAJO**: regulación sectorial sin impacto en crédito personal → DESCARTADO

## Output modes

- DOCUMENTO_CAPTURADO: registro en lf_capture_records
- DOCUMENTO_SIN_IMPACTO: descartado por clasificación S4-A
- DUPLICATE_SKIP: ya existe en base
- BLOCKED_DOMINIO_NO_AUTORIZADO: fuente fuera de lista blanca
- RETURN_TO_WORKER_FOR_SELF_REPAIR

## Ventaja diferencial vs ACT-0054 (noticias)

ACT-0055 captura la **fuente primaria** regulatoria — no la interpretación periodística.
La combinación ACT-0054 + ACT-0055 cubre tanto el evento noticioso como
el documento oficial que lo origina, creando corpus completo y trazable.

## Runtime

CANDIDATO. No habilitar producción sin gate formal:
CANDIDATO → EN_REVISION → APROBADO.
