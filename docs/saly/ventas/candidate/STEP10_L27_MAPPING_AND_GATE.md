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

## L28 · 2026-11-20 — segunda migración candidata (mismo PR #4457)
La candidata `20261120235100_lf_saly_ventas_discovery_coverage_fk_v1.sql`
se ejecuta **después** de la L27. Implementa seis tablas de cobertura, no crea
una segunda tabla `ventas_hallazgos`, y añade a `ventas_discovery_ingestas`:
- `consulta_id uuid NOT NULL`, FK compuesta con el recibo de consulta exacto;
- `fuente_habilitada=true` y FK a `ventas_discovery_catalogo` con
  `persist_business_data=true` y `habilitada=true`;
- fuentes comerciales solo con `rights_evidence_ref` y `rights_checked_at`; declarar
  autorización sin evidencia fechada falla `CHECK` en PostgreSQL;
- FKs de consulta → ejecución → fuente planificada → versión de catálogo;
- guard de `CERRADO` deshabilitado hasta contar con evaluación de cobertura 21/21;
- RLS para las seis tablas, sin `GRANT` a clientes y sin carga de datos.

**Riesgos por resolver antes del Merge Train:**
1. PG17 real y BEGIN/ROLLBACK del conjunto **L27+L28**: aún no verificados.
2. Las referencias de RUN quedan dentro del ledger de descubrimiento; falta su
   vínculo autenticado al RUN padre del Router y operación nativa.
3. La autoría de `rights_status=PERSISTENCIA_PERMITIDA` y la activación del
   catálogo requieren decisión gobernada, evidencia contractual y revisión legal;
   el fixture sintético PG17 NO es esa autorización.
4. La protección permanente de cierre del RUN exige un gate evaluador que
   verifique snapshot de catálogo, aplicabilidad de fuentes y recibos por lote.
5. El catálogo L20 v0.2 sigue sin despliegue: 21 especificaciones, 0 conectores
   productivos. Las fuentes ya investigadas no equivalen a ejecución completa.
6. Dado que `consulta_id` se incorpora con NOT NULL y sin default, la migración
   fallará deliberadamente si la tabla L27 recibió filas antes de unir el ledger.

**Siguiente checkpoint:** HEAD exacto → clasificación/PASE PASS → PG17 aislado
positivo y negativo → operación gobernada → Merge Train → readback SELECT.
Ningún merge ni carga automática deben adelantarse a esos controles.

## L29 · Verificación real y bloqueo de RUN gobernado
- Archivo: `supabase/tests/saly_ventas_l29_pg17_isolated_runner.sh`.
  Solo acepta PostgreSQL **17** en `127.0.0.1:5432`,
  `PGDATABASE=saly_sales_ci_l29`, `PGUSER=postgres` y base vacía.
  Crea el esquema de prueba, prueba L27+L28 dentro de `BEGIN/ROLLBACK`,
  luego aplica ambas migraciones solo a esa base de pruebas y ejecuta
  los dos scripts PG17 y los dos SELECT readbacks; comprueba nueve tablas
  con RLS y ningún registro ficticio persistido.
- **NO ejecutado en este lote:** el entorno de la conversación no dispone
  de binarios PostgreSQL, y el intento de instalar paquetes terminó por
  timeout. Este script es reproducible, NO evidencia PG17 PASS.
- La única ejecución real PostgreSQL confirmada es la anterior
  [GitHub Actions 44832330360](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/44832330360);
  corresponde a L26 y no valida el HEAD L29.
- Nuevo readback SELECT:
  `supabase/tests/saly_ventas_l29_router_parent_readback.sql`.
  Metadatos actuales observados: `public.lf_operation_execution.execution_id`
  es PK; se encontraron únicamente dos RUN de
  `EJECUCION_PERFIL_LF` con contexto `business=SALY`,
  ambos `PERFIL-UI-ARCHITECT` en `IN_PROGRESS`. El registro de
  operaciones no muestra una operación SALY/VENTAS/DISCOVERY explícita.
- **NO vincular** `run_ref` ni dar permiso de escritura usando esos RUN de UI:
  no acreditan ejecución del perfil comercial, selección por Router
  ni autoridad de efectos. El FK a `public.lf_operation_execution` y
  las verificaciones de business/canal/perfil/estado pertenecen a un
  lote posterior con contrato de RUN autorizado. No se introdujo un
  FK engañoso a una ejecución arbitraria.
- Gate real pendiente: especificar y probar el perfil/operación
  competente para SALY Ventas (sin reutilizar UI), emitir un RUN admitido
  y ligar su `execution_id` de manera inmutable con el RUN de discovery.
  Antes de eso, `run_ref` es solo trazabilidad local, no autorización.

**Resultado L29**: preparación verificable, sin writer, sin merge,
sin despliegue y sin contactos o empresas introducidos a la base.
