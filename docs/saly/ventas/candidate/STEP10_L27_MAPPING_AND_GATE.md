# SALY Ventas · Step 10 · L27 reconciliation contract
Estado: CANDIDATO / NO DEPLOY / NO MERGE. Fuente Saly, nunca LF.

## Objetivo
Mantener un único ledger comercial de descubrimiento y preservar cobertura auditada de
RUN → fuente → conector/substep → consulta/lote → fila/hallazgo.
El archivo SQL oficial de este PR crea **3 tablas**; las tablas de
cobertura del lote L20 siguen pendientes en Supabase.

## Contrato del catálogo candidato
`catalog_version = PE-SALY-DISCOVERY-2026-11-V0.2`.
Ejemplo PTE real **solo identificadores**, sin autorizar ingesta:
- `source_id=PE-PTE`
- `connector_id=SALY-U07-S13-C03`
- `substep_code=13.03`
- `scope_key=LIMA_ICA`
- `batch_key=PTE-2026-08-B0001`
- `query_hash`: SHA-256 de filtros/caso de extracción
- `consulta_evidencia_ref`: referencia al recibo de lectura
- `run_ref`: RUN de discovery, aún SIN FK a ejecución gobernada.

**Advertencia:** `process/source_catalog.pe.v0.2.json` de la candidata U07/L20
marca `PE-PTE` como `persist_business_data=false`, `rights_status=PENDIENTE_VERIFICAR`
y `SPEC_ONLY_NOT_CONNECTED`. La licencia general ODC-By NO habilita automáticamente
la ingesta empresarial en producción ni mensajería. Los ensayos PG17 usan datos
sintéticos y no acreditan derechos sobre el dataset real.

## Convergencia de tablas

| Lote | Concepto | Situación |
| --- | --- | --- |
| L20, propuesta | `ventas_hallazgos` con FK a `ejecuciones` | NO APLICAR CREATE; reemplazado por tabla canónica de L27 |
| L27, PR #4457 | `ventas_hallazgos` con FK a ingesta y RUC opcional | Candidato sin deploy |
| L27, PR #4457 | `ventas_discovery_ingestas` con catalogo/fuente/RUN/lote/consulta + derechos | Candidato sin deploy |
| L27, PR #4457 | `ventas_unidades_operativas` vinculada al hallazgo | Candidato sin deploy |
| L20, pendiente | `ventas_discovery_catalogo`, `runs`, `ejecuciones`, `consultas`, `plan_fuentes`, `plan_batches` | Crear de forma independiente, sin rehacer hallazgos |
| L18, pendiente | `ventas_empresas` e identidad RUC SUNAT (Step20) | Crear antes de FK a empresa validada |

## Dependencias innegociables del siguiente lote
1. Publicar tablas de cobertura L20 en migración **independiente**. Ajustar
`00_step10_audit_extension_PROPOSED.sql` para ELIMINAR su `CREATE TABLE ventas_hallazgos`.
2. Definir FKs (no sólo texto) desde ingesta hacia RUN/consulta y
`(catalog_version,source_id)` hacia catálogo; usar `ALTER` gobernado, nunca asumir tablas aún inexistentes.
3. Añadir `ref_empresa_validada` hacia `ventas_empresas` sólo después del Step20.
4. Writer nativo con autorización de fuente, RUN verificado, idempotencia y SELECT posterior.
5. Ejecutar PG17/ROLLBACK de conjunto ya integrado, PR/PASE/Train exact-head, SELECT de producción.

## Interpretación de resultados
- `FOUND` sólo cuando la consulta y su evidencia existen;
  una fila de hallazgo NO certifica cobertura de catálogo.
- `BLOCKED` para CAPTCHA/red/licencia; jamás `EMPTY` automáticamente.
- `NOT_APPLICABLE` sólo con motivo documentado y política vigente.
- Repetidos RUC NO se eliminan en staging; entidades jurídicas y unidades son conceptos distintos.
- El índice de unicidad de ingesta bloquea replay exacto dentro del RUN,
  pero permite el mismo archivo con hash conocido en RUN distintos.
- No se cargan PTE ni las 15 empresas; 0 escrituras en Supabase mientras no haya vía gobernada.

## Evidencia de no-despliegue
- PR #4457 `DRAFT`; SQL candidato y tests.
- PG17 antiguo run 44832330360 PASS sobre DDL anterior a campos L27;
  **no usarlo como PASS de L27**.
- L26 PASE run 44832735639 PASS; L27 requiere HEAD/CI independiente.
- Último Supabase SELECT: ninguna tabla `ventas_*` del pipeline desplegada.
