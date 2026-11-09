# PG-05_C1 — Destino exacto y plan de rama (candidato de solo lectura)

**Alcance:** preparar la entrada PG-04 → PG-05_C1 sin abrir ninguna rama, adquirir un lock o conceder permiso de escritura.

## Fuente del requisito

El checkpoint PG-05_C1 en `supabase/migrations/20261028160000_lf_programming_pg00_standards_checkpoints_decisions_v2.sql` exige recibir `repo_full_name` y `base_head_sha` del `target_binding` del paquete, **sin inferirlos**, y crear posteriormente la rama `lf/prog-<work_code>/<slug>`.

PG-05_C2 usa write-scope por solución y contratos compartidos de solo lectura por defecto; PG-05_C3 exige locks para evitar choques materiales entre writers; ninguno de esos controles se ejecuta aquí.

## Implementación

`tools/pg05_c1_target_binding_preflight_v1.py` expone `prepare_pg05_c1(pg04_exit, work_code, slug)` y consume el sobre `PG04_TO_PG05_EXIT_CANDIDATE_V1` del productor PG-04.

Controles:
- Verifica digest SHA256 íntegro del sobre de salida y que siga `CANDIDATE_NOT_ADMITTED`, sin autorización de ejecución, escritura o creación de rama.
- Recibe literalmente el `target_binding` congelado del paquete y requiere `source_attested=false`. Si el destino no está presente, devuelve `BLOCKED` con `PG05_TARGET_BINDING_MISSING` y rama nula. **No usa el repositorio del PR como valor por defecto**.
- Con los campos explícitos, exige la forma `owner/repo`, SHA base de 40 hexadecimales y referencia de binding no vacía. La estructura es solo formato; aún no prueba existencia/currentness/autoridad.
- Construye solamente el **nombre candidato** `lf/prog-<work_code>/<slug>`, a partir de `work_code` y `slug` tipados con caracteres permitidos, sin llamar a GitHub create-branch.
- Comprueba IDs únicos de soluciones, listas de `write_scope_candidates` no vacías y flags `execution_allowed=false`, `shared_contract_access_default=READ_ONLY`, `pg05_write_scope_authorized=false` y `pg05_parallel_writer_lock_acquired=false`.
- El resultado queda incondicionalmente `branch_created=false`, `branch_collision_checked=false`, `writer_lock_acquired=false`, `target_binding_currentness_verified=false`, `base_head_repository_readback_verified=false`, `pg04_independent_assurance_verified=false`, `pg05_admitted=false`, `write_allowed=false` y `handoff_allowed=false`.

### Estados

| Situación de entrada | Resultado del preflight | Efecto |
|---|---|---|
| Falta el `target_binding` | `BLOCKED / PG05_TARGET_BINDING_MISSING` | No hay rama candidata |
| `target_binding` con formato incorrecto | Excepción `PG05_TARGET_BINDING_INVALID` | No hay resultado admisible |
| `target_binding` estructuralmente válido | `CANDIDATE_NOT_ADMITTED / PG05_TARGET_BINDING_UNATTESTED_AND_PG04_UNADMITTED` | Solo nombre de rama candidato |
| PG-04 contiene flags falsos de ejecución o escritura | Excepción, fail-closed | No se concede escritura |

## Bloqueadores para crear una rama real

1. **Admisión PG-04:** sujeto congelado con receipt EVIDENCE_LEDGER VERIFIED, juez independiente y readback autorizado.
2. **Vinculación de destino:** `target_binding` auténtico, current y coherente con repo/base HEAD en GitHub.
3. **Gobernanza de ramas:** verificar existencia/colisión, permisos y ruta autorizada antes de invocar una acción mutante.
4. **PG-05_C2/C3:** write-scope y locking por solución antes de permitir writers.

No se modificaron Análisis, Supabase, `main`, targets ni GitHub branch refs de producto. Se añadió código fuente únicamente a la rama draft del PR #3528. Las pruebas permanecen aplazadas por instrucción del Owner; **no se atribuye PASS exact-HEAD**.

**Dictamen:** `PG05_C1_SOURCE_PREFLIGHT_READY / TARGET_BINDING_NOT_ATTESTED / BRANCH_NOT_CREATED / PG05_C1_OFFICIAL_PENDING`.
