# B07 — evidencia de prueba exacta y límites (13-nov-2026)

**Dictamen:** `PASS_B07_CANDIDATE_ONLY` para UP/DOWN en copias SQL aisladas; `B07=ABIERTO/NO-GO`; decisión del dueño pendiente de firma. **No desplegar el SQL**.

## Readback de Supabase (SELECT únicamente)
- As-of UTC: **2026-11-13T08:44:54.033Z**, rol de lectura `supabase_read_only_user` Postgres 17.6.
- `lf_ops.reglas`: **578** filas, **412 VIGENTE + 166 CANDIDATO**. SHA256 de filas ordenadas por id `15caa058184e52db3572bd0884810d0b731703d72e989c9e33dccc59ce983d8f`; SHA256 de esquema `3ef1850f478371ca03147a65380262fcddb2f9a131ae2e00ed515abab97b987c`.
- `saly.reglas`: **14** filas, **14/14 VALIDADO/vigente**. SHA256 de filas `588bf6b8368eb48ff93ae3edaebf1e80018364c3078a409aeb153836d55256c7`; SHA256 de esquema `bd44713bc7fbef670b9fd2f1851e63ae5e6aed697f097ac7ececd9823cfe40c8`.
- Los dos esquemas tienen **0 columnas `lifecycle_*`**; se abstuvo de ejecutar DDL/DML en Supabase.
- `saly.estados=10`, `saly.transiciones=10`, ambas son `ADELANTO`/definiciones `CANDIDATO`; `saly.campos=0`, `saly.validaciones=0`.
- Migraciones SALY de `supabase_migrations.schema_migrations.statements` (fuentes existentes aunque no encontradas en `main`): 
  - `20260813185516` `create_saly_estados_foundation_v01` SHA256 `b423e362f045389f5dca0ab0ae826df9b89e0f0d671cb887afee4b0cc15e633e`.
  - `20260813192048` `create_saly_transiciones_base` SHA256 `bea311b4b9b9111c178b386105158b701856366e1499431719b1822815db42b9`.
  - `20260814035958` `enable_rls_saly_transiciones` SHA256 `91cbe91d4654f069cc9544930bbc0b8cd0809aa75c789bf2c451a2901dc3ea81`.
  - `20260819040820` `create_saly_campos_foundation_v01` SHA256 `f11095dc4e5800205ac9f678a265211679475f24be81cd3b070285d5b9bc9c38`.
  - `20260819051748` `create_saly_validaciones_foundation` SHA256 `78c1c0add11fa5601825ff60a6c399cfb3572b82288d6b779b56168049a93605`.
- Fuente de estado SALY: `SELECT codigo,titulo,estado,vigente,decision_id,fuente FROM saly.reglas ORDER BY id` (14 filas) y metadata `saly.estados/transiciones`; SQL UP/DOWN **no se derivó de un DDL de ciclo existente**: las 9 definiciones nuevas son hipótesis.

## Evidencia GitHub Actions PR #3813
- PR: https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3813 (DRAFT, sin merge).
- Commit fuente de tests `24b3e52655dc7e1cc7b5f67d04ec67f0611dbc9b`.
- [R17 run 43395274869](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/43395274869), job `131784565455`: **suite global FAILURE** (1 error ajeno).
- **PG17.6 REAL:** `test_pg17_6 ... ok`, `PASS_B07_CANDIDATE_postgres_17.6 PG=170006`, preimagen y post-DOWN idénticos: `b59063301d4940d1aba5bca9d8bda4eeaa86187bf53b91452626c97ae7092682`.
- **PG18.7 REAL:** `test_pg18_7 ... ok`, `PASS_B07_CANDIDATE_postgres_18.7 PG=180007`, preimagen y post-DOWN idénticos: `8a4bc4ac1df9e666701060aeefabc687ce23b3baff63dd38fe57a5c10173051f`.
- En ambas: `PASS_B07_NEGATIVES_INCOMPLETE_SHA_ORIGIN_AND_DATA_BEARING_DOWN`, `B07_NOT_CLOSED_ALL_NINE_COLUMNS_INFERRED_OWNER_DECISION_AND_LIVE_TRAIN_MISSING`.
- **PASE SUCCESS** [run 43395275095](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/43395275095).
- **Fallo global, ajeno a B07:** `ERROR: setUpClass (test_ig_act0001_scope_consumer_pg18_v2.ACT0001ScopeConsumerPG18)` → `AssertionError: PR3807_DELTA_OR_ROLLBACK_MISSING`. No se modificó ese test ni esa ruta. La suite informa `Ran 237 tests ... FAILED (errors=1)`. **No afirmar R17 full PASS.**

## Qué sí se ejecutó
1. Dos contenedores desechables `postgres:17.6` y `postgres:18.7`, fuente V2 #3803 sobre slice LF de objeto vivo + 14 filas SALY **de texto sintético** (códigos/estados/decision_id sustentados en SELECT, no datos completos).
2. Preimagen SHA256 del esquema + filas + RLS, SQL UP de 4+5 columnas nuevas, readback exacto 9/9 y preservación de 14 `VALIDADO`.
3. Pruebas negativas: `lifecycle_state` sin bundle bloqueado, SHA inválido bloqueado, origen SALY distinto de `estado` bloqueado.
4. `BEGIN` + escrituras **solo en contenedor** + `ROLLBACK`: estados fuente intactos.
5. DOWN con evidencia nueva **ya confirmada** se bloquea `B07_DOWN_NONEMPTY_EVIDENCE_BLOCKED`, conservando evidencia; tras retirar exclusivamente esa prueba sintética, DOWN revierte y SHA post-DOWN = preimagen.

## Qué NO se ha probado o aprobado
- No es un dump completo, restauración real, prueba de consumidores funcionales, permisos de escritor en vivo o cobertura de todos los activos SALY.
- Las **9 columnas son INFERIDAS**; por ahora `lifecycle_state=NULL` significa «no inicializado», **no** una fase aprobada.
- No se ha probado el SQL en la ruta oficial Merge Train ni conectado al escritor real; no se ha verificado validación semántica de valores, owner firmado ni pruebas completas B07 sobre base temporal.
- DOWN no revierte automáticamente datos nuevos **ya confirmados**: por diseño los bloquea. Una remediación post-datos requiere nueva política de custodia/preimagen.
- **B07 y los demás bloqueos L28 continúan abiertos.**

## Siguiente lote técnico
El dueño revisa la **tarjeta `02_tarjeta_decision_1_pagina.md`** (aprobar propuesta o ajustar 9 campos, estados y semánticas). **No** es autorización de despliegue. Luego Ingeniería implementa contrato oficial, writer, RLS/consumidores, reversión post-datos y batería E2E verificable antes de considerar B07.
