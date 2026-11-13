# L28 — Prueba B07 ejecutada: alcance, SHA y NO-GO

**Resultado verificable:** en PostgreSQL 17.6 y 18.7 reales sobre contenedores aislados con una **copia PARCIAL de objetos LF + esquema SALY reconstruido de metadata live**, la prueba de preimagen/rollback post-datos de **UN campo SALY conocido** obtuvo **PASS parcial**. El requisito B07 LF4/SALY5 queda **NO-GO / ABIERTO**. No se inventó SQL UP/DOWN de 9 campos ni se modificó Supabase.

## Fuentes leídas ANTES de la prueba
- EKB: `INPUT GOVERNANCE LF — INSTRUCCIONES OPERATIVAS V1.4`, estado `CANDIDATO VERIFICADO PARCIALMENTE`; fuente de arquitectura, contratos/runtime prevalecen.
- L28 `12_criterios_cierre_motor_7.md`, blob pre-prueba `7541d3844523728096f1da34be8303b1b22662db`: requiere LF 4 columnas, SALY 5 incluyendo `lifecycle_state`, DDL UP/DOWN, RLS/constraints, preimagen, rollback **post-datos**, migración/fuente y readback; no especifica **nombres exactos del total de 9 columnas ni migración UP/DOWN**.
- Supabase actual `mhwmirqcgxxukpctffuv` (Postgres **17.6**): lectura únicamente mediante `supabase_read_only_user` en `postgres`. `2026-11-13T07:17:31.348Z` observación de versión. No DDL, DML, funciones ejecutoras ni RUN tocados en vivo.
- Ledger live: versiones `20261113030000_lf_ig_rule_lifecycle_writer_v2`, `20261113070051_lf_asset_owner_one_name_guard_v1` y `20261113071927_lf_asset_owner_one_name_backfill_v1` registradas; V2 está desplegada. Estos son **otros cambios, NO el UP/DOWN B07**.

## Preimagen de datos y esquema live (solo SELECT)
**as_of datos `2026-11-13T07:22:33.229Z`.** SHA calculado en Supabase con `extensions.digest(...,'sha256')` (columnas para esquema; filas JSONB canonizadas por id para datos).

| Tabla | Filas reales | SHA256 datos | columnas actuales | SHA256 columnas |
|---|---:|---|---:|---|
| `lf_ops.reglas` | 578 (412 VIGENTE +166 CANDIDATO) | `15caa058184e52db3572bd0884810d0b731703d72e989c9e33dccc59ce983d8f` | 15 | `3ef1850f478371ca03147a65380262fcddb2f9a131ae2e00ed515abab97b987c` |
| `saly.reglas` | 14 (14 VALIDADO) | `588bf6b8368eb48ff93ae3edaebf1e80018364c3078a409aeb153836d55256c7` | 18 | `bd44713bc7fbef670b9fd2f1851e63ae5e6aed697f097ac7ececd9823cfe40c8` |

- `saly.reglas` **NO** contiene `lifecycle_state`. `lf_ops.reglas` tampoco. Mantener `estado=VALIDADO` en SALY y **no extrapolar** `VIGENTE` de LF.
- RLS: `lf_ops.reglas` enabled / 1 policy; `saly.reglas` enabled / 0 policies; prueba de políticas/consumidores completa pendiente.
- V2 realmente desplegadas (SHA256 `pg_get_functiondef`): `lf_ig_rule_finalize_v2(text)` `8006ce964db2cd4a53ad1cd378242c940f2f525259fe4053425a4ff1489f6cc9`; `lf_ig_rule_owner_decide_v2(text,text,text,jsonb)` `7abcb0301ed490d18d6f2f05d1bcd7aaba8292420c985e40bda57824717415fa`. Ninguna de estas definiciones contiene `lifecycle_state` ni referencia a `saly.reglas`; por eso **V2 instalada ≠ B07 instalado**.

## Prueba PG17.6 y PG18.7 REAL (CI, no proveedor Supabase)
- [PR #3810 (DRAFT, solo tests)](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3810), commit `9603bb13068364c4ee386eb91c813074a28ca3be`.
- [GitHub Actions R17 run 43385755925](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/43385755925), job `131753702972`: **SUCCESS**; 234 tests totales `OK` (2 nuevos de B07, no 234 exclusivamente B07). PASE run `43385756065` SUCCESS.
- Test exacto `sandbox/lf_contract_gate_test/edge_function_operation/test_ig_b07_lifecycle_preflight_pg18_pg176.py`: levanta `postgres:17.6` y `postgres:18`, ejecuta slice SQL derivado de objetos reales + fuente migración V2 exacta #3803 (con un RUN de Train **sintético solo en contenedor**), recrea `saly.reglas` en su forma observada con 1 fila **SINTÉTICA** `VALIDADO`.
- Obtiene SHA de estructura/filas/RLS en contenedor, `BEGIN` → añade `saly.reglas.lifecycle_state` (campo conocido, nullable; **NO DDL canónico**) → actualiza **fila SINTÉTICA**, conservando `estado=VALIDADO` → `ROLLBACK` → readback por SHA y catálogo: SHA igual, columna retirada, `estado` intacto, V2 sigue presente.
- **PG17.6 `170006`**: `PASS_B07_PARTIAL_SCHEMA_PREIMAGE_SHA256_postgres_17.6` SHA `f9a98b49960143b7980d59420c64142f384053b4044a44cea2c4f34f3a200c9e` + `PASS_B07_PARTIAL_SALY_KNOWN_FIELD_POST_DATA_ROLLBACK_postgres_17.6`.
- **PG18.7 `180007`**: `PASS_B07_PARTIAL_SCHEMA_PREIMAGE_SHA256_postgres_18` SHA `df15ae232da652c0303f08c637735718ae56ff897ea934a2d8d594cd04156ec0` + `PASS_B07_PARTIAL_SALY_KNOWN_FIELD_POST_DATA_ROLLBACK_postgres_18`.
- En ambas: `B07_NO_GO_MISSING_APPROVED_LF4_SALY5_UP_DOWN_AND_FULL_CONSUMER_PROOF` + `COPY_SCOPE=LIVE_OBJECT_SLICE_PLUS_RECONSTRUCTED_SALY_SCHEMA_SYNTHETIC_DATA`. **Los dos hashes CI NO son hashes de la BD viva**.

## Qué prueba y qué NO prueba
| Control | Resultado |
|---|---|
| V2 en Supabase: firmas y source readback SELECT | PASS presencia |
| Preimagen live LF/SALY y estados reportados | PASS SELECT, con hashes |
| PG17.6 y 18.7 aplican V2 en un slice aislado | PASS test CI |
| ROLLBACK **post-UPDATE sintético** de 1 campo conocido SALY | PASS / solo campo |
| Modelo de **9 columnas exactas** LF4/SALY5 | **NOT_TESTED: especificación exacta ausente** |
| DDL UP/DOWN completo + índices, constraints, políticas, vistas, consumidores y backfill realista | **NOT_TESTED** |
| Reversión tras datos reales/copies completas y aplicación por Train del B07 | **NOT_TESTED** |
| Cierre B07 y gate G11 | **NO-GO / ABIERTO** |

## Siguiente lote y dueño
1. Arquitectura/DBA prepara **matriz exacta** LF4/SALY5 por tabla/campo, semántica de transiciones y compatibilidad con `saly.reglas.estado=VALIDADO`; **el dueño debe decidir/ratificar campos y significados**, no improvisarlos en SQL.
2. Ingeniería materializa SQL UP/DOWN y pruebas de datos representativos, negativos, RLS, políticas, índices, todos los consumidores, PG17.6/18.7, antes y después con SHA; **sin necesitar una nueva decisión por cada test**.
3. Escritura gobernada exclusivamente por Train en base temporal, solo con preimagen SHA, recibos y rollback seguro; el readback real podrá informar B07, pero **sin firma/evidencia no se cierra**.
4. **No ejecutar DDL directo** ni cambiar RUN históricos. Mantener `0/7` cerrados en plan.

**Dictamen:** `B07_PARTIAL_TEST_PASS / B07_GO_NO_GO=NO_GO / G11=NO_VERIFICADO`.
