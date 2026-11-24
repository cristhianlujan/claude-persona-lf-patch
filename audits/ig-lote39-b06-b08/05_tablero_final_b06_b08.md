# L39 · B06 / B08 — resultado verificable y NO-GO

**Mandato:** no tocar Supabase vivo ni RUN, no invocar escritores V2. **Operación:** GitHub PR DRAFT #3825 con pruebas PG aisladas; SQL Supabase solo SELECT.

## Tablero

| Bloqueo | Evidencia ejecutada | % de los controles de L38 | Cierre |
|---|---|---:|---|
| B06_OWNER / G03 | 10/12 PASS | **83%** | **ABIERTO**: sin freeze previo a #3806 y sin aceptación independiente G03 |
| B08_IDENTITY / G04 | 4/10 PASS; queries de detección PASS SELECT | **40%** | **ABIERTO**: 0 RUN elegibles, Step70/RAW pendiente de B09 |
| Escrituras Supabase vivo | 0 | n/a | No realizadas |
| Escritores V2 vivo | 0 | n/a | No invocados |
| Producción/G15 | NO-GO | n/a | No promovida |

**Porcentajes = suma de puntos de evidencia; no equivalen a certificar producción.**

## B06 · negativo complementario PG17.6 y PG18.7

Tests nuevos `sandbox/lf_contract_gate_test/edge_function_operation/test_b06_replay_project_isolation_pg17_pg18.py` en PR DRAFT [#3825](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3825); ejecutados en [R17 43447324574](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/43447324574), job `131960086429`.

| Negativo/test ejecutado | PG17.6 | PG18.7 |
|---|---|---|
| Aprobar duplicado de recibo activo: unique constraint + rollback, 0 receipt | PASS | PASS |
| Duplicar recibo archivado: unique constraint + rollback, 0 receipt | PASS | PASS |
| Solo owner SALY no puede aprobar activo LF: falta binding LF, rollback | PASS | PASS |
| Código solo existente en esquema SALY no puede aplicar writer LF | PASS | PASS |
| Aplicación exitosa LF no toca sombra SALY; rollback revierte LF | PASS | PASS |

**10/10 pruebas B06 PASS** en el HEAD auditado: [R17 run 43448773117](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/43448773117), job `131965118963`. **R17 GLOBAL = FAIL:** dos tests B09 FALLAN y un import B09 da ERROR por falta de migración `20261113150000_lf_ig_native_chat_sha_receiver_v1.sql` en main/HEAD; además falla un test legacy de rollback PR3803 PG17.6 por socket PostgreSQL ausente al arrancar. **PASE run 43448773298 = SUCCESS**. Los 10 casos nuevos B06 no fallaron. No se inventó ni copió SQL B09 para enverdecer CI.

**Alcance de la prueba SALY:** aislamiento en tablas/esquemas simulados y binding `lf_ig_project_owner_v2.project_code='LF'`. No demuestra por sí solo segregación productiva de todos los objetos SALY ni firma humana.

## B06 · RUN históricos

13 archivos CSV congelados en [auditoría #3811](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3811), **capturados después** de `#3806` (cutoff por `started_at` 2026-11-13 07:20:12.513028Z). SHA raíz:
`7bae2d2952c1dae06bbe32e498421a3752f9802078d29da4e218d62749512a02`.

En este lote se ejecutaron 13 SELECT independientes de comparación por ID + SHA de fila completa + contador de pasos + SHA del bundle de pasos, contra los 13 blobs congelados:
- **2456/2456** RUN encontrados, 2456/2456 SHA RUN iguales.
- **2456/2456** conteos y **2456/2456** SHA de paquetes de pasos iguales; **8244** pasos incluidos.
- **0** diferencias después de congelación. Segunda consulta de SHA raíz live: idéntica.

**NO ACREDITADO:** que los 2456 RUN permanecían así **ANTES** de #3806. Se necesita backup PITR o auditoría inmutable anterior a 07:20:12 UTC, comparable por ejecución/columna/paso; nadie puede inventarlo. El control G03-11 sigue pendiente.

## B08 · receptor B09 y consulta de elegibilidad

PR [#3823](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3823) es el receptor SHA de B09; su existencia/despliegue no equivale a RUN E2E ni juez Step70 independiente.
- `01_b08_run_eligible_and_raw_sha_readonly.sql`: detector específico AUTH-033/B2B-AUTH-004. SELECT real: **0** elegibles.
- `02_b08_generic_run_patch_sha_select.sql`: detector **general**: CREATE/CANDIDATO/VIGENTE; exige RUN IN_PROGRESS Product Director, manifest/read_only/no_write/no_promotion, input_validate/output_validate, Step70 PASS_INDEPENDENT_SEMANTIC, salida RAW, proponente distinto, pantalla y no decisión duplicada; devuelve `propuesta_sha256_exact_raw`. SELECT real: **0** elegibles.
- SHA documental AUTH-033 L32 `6a398f8cdbd59a4a56099f9deb8ec01a3ea95e62ea1864735546db60c5cfb769` es solo **candidato**; únicamente usar si coincide con SHA RAW del RUN elegible futuro.
- `lf_asset_snapshot_sha_v1` directo sigue bloqueado en rol RO (42501); la consulta devuelve SHA equivalente como **herramienta de inspección**, no como permiso para disparar writer.
- B08 en Supabase temporal declara `identity_verified=false`; no atribuir autenticación humana.

### B08 — seis campos preparados, frase a emitir SOLO en el RUN real

```json
{
 "codigo_regla":"<CODE_FROM_ELIGIBLE_RUN>",
 "propuesta_sha256":"<SHA256_EXACTO_RAW>",
 "veredicto":"RECHAZAR",
 "decisor":"Cristhian Luján",
 "fecha":"<FECHA_ISO8601_REAL_DENTRO_VENTANA_DEL_RUN>",
 "frase_literal":"Yo, Cristhian Luján, RECHAZO la propuesta de la regla <CODE_FROM_ELIGIBLE_RUN>, SHA-256 <SHA256_EXACTO_RAW>, originada en el RUN <EXECUTION_ID_REAL>; no autorizo ejecución ni promoción."
}
```

La consulta detectora se puede ejecutar sin aprobación nueva; **llamar** `public.lf_ig_rule_owner_decide_v2` requiere nueva instrucción efectiva de disparo tras evidencias. La rama `RECHAZAR` registra decisión permanente sin regla/hijo/promoción, ya demostrada en laboratorio histórico PG18; **no se probó writer B08 real en este lote**. Para el mismo `RUN+rule+kind` no se puede sobrescribir el recibo; aprobación posterior exige RUN nuevo. Si se usa `APROBAR`, puede cambiar VIGENTE: no usarlo de primera prueba.

## Riesgos: quién debe decidir

| Riesgo | Requiere aceptación expresa del dueño | Custodia / acción |
|---|---|---|
| Aceptar ausencia de preimagen pre-#3806 y solicitar excepción a G03 | **Sí** si se pretende dispensar criterio; aceptación sola NO convierte NO_ACREDITADO en PASS | Dueño + Arquitectura/DBA/Seguridad, buscar respaldo previo |
| Cerrar G03 con identidad documental no verificada y separación por proyecto/familia | **Sí** para decisión de alcance; además revisión independiente obligatoria | Dueño / IAM / Arquitectura / QA |
| Aplicar `RECHAZAR` a RUN+SHA exactos, dejar recibo inmutable | **Sí**: frase literal real y autorización de disparo | Dueño; operador posterior vía writer oficial |
| Aceptar `identity_verified=false` solo para B08 temporal | **Sí**: aceptación documental, no firma ni autorización de producción | Dueño / Seguridad / IAM |
| Disparar `APROBAR` y riesgo de promover regla | **Sí, autorización separada** | Dueño + Producto/QA, luego ruta oficial |
| Ejecutar tests aislados, SELECT y preparar SQL detector | **No** (mandato vigente ya cubre alcance) | IG / QA / DBA |
| Resolver faltas de datos, nuevos hash/checks y pruebas técnicas | **No**, mientras no haya mutación de fuente oficial | Arquitectura/DBA / Operaciones / QA |

**No se escribió Supabase, no se tocaron RUNs, no se llamó escritor V2 y no se promovió nada.**

### Evidencia entregada
- `03_b06_recibo_g03_actualizado.json`: 10 PASS/12, 2 pendientes.
- `04_b08_procedimiento_post_b09_no_disparar.json`: gates, seis campos, riesgos, rollback.
- `01_b08_run_eligible_and_raw_sha_readonly.sql` y `02_b08_generic_run_patch_sha_select.sql`: ambas consultas ejecutadas SELECT, cero elegibles.
- `sandbox/lf_contract_gate_test/edge_function_operation/test_b06_replay_project_isolation_pg17_pg18.py`: 10 PASS en ambas versiones entre 10 casos.
