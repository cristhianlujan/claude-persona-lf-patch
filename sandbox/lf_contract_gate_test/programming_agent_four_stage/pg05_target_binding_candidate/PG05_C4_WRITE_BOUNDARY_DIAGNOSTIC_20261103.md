# PG-05_C4 — Bloqueo de cambios fuera de write-scope por solución (2026-11-03)

## Requisito

PG-05_C4: una escritura fuera de scope debe devolver BLOCK y el desvío bloquea solamente la solución afectada. Se aplica después de C1 (target), C2 (recursos) y C3 (matriz de choques/locks). El componente fuente no concede permisos ni reemplaza Changeset Governance.

## Componente

`tools/pg05_c4_write_boundary_preflight_v1.py` expone:

`prepare_pg05_c4(pg04_exit, pg05_c2, pg05_c3, change_proposals)`

Entradas: tres sobres candidatos con hashes completos y vínculos cruzados, todos sin autoridad; una propuesta por `solution_id`, con `source_head_sha`, `proposal_ref` y lista tipada de cambios. Cada cambio identifica `operation` (ADD/MODIFY/DELETE/RENAME/MIGRATION/DDL/DML), `resource` (REPO_PATH o DB_OBJECT) y `change_ref`.

### Clasificación conservadora

- `BLOCK_OUT_OF_WRITE_SCOPE`: un cambio intenta modificar un recurso que no está declarado **exactamente** entre los recursos write del propietario. Un directorio padre en C2 no implica permiso para archivos hijos. No se admiten rutas ambiguas, glob, relativas con `..`, etc.
- `BLOCK_SHARED_READ_ONLY_RESOURCE`: recurso compartido de solo lectura en la propia solución.
- `BLOCK_CROSS_SOLUTION_WRITE_COLLISION`: el recurso puede interferir con los recursos de escritura de otra solución, también por rutas padre/hijo u objetos DB jerárquicos.
- `BLOCK_CROSS_SOLUTION_SHARED_READ_CONFLICT`: el cambio puede modificar algo que otra solución utiliza como contrato compartido READ_ONLY.
- `REQUIRES_EXISTING_REPOSITORY_PATH_ADMISSION`: cualquier ruta `.github/` necesita el control canónico `lf_repository_path_admission.py`. Este marcador es **bloqueante** hasta ese control.
- `BLOCK_RENAME_REQUIRES_OLD_AND_NEW_PATH_BINDINGS`: un RENAME no puede admitirse con un único recurso; necesita resolver origen y destino en un contrato posterior.
- Incompatibilidad entre operación de BD y recurso de archivo, o viceversa: `BLOCK_DB_OPERATION_WRONG_RESOURCE_KIND` / `BLOCK_FILE_OPERATION_WRONG_RESOURCE_KIND`.

Cada propuesta recibe `diagnostic_status=BLOCKED_SCOPE_VIOLATION` cuando tiene cualquier hallazgo, o `NO_SCOPE_VIOLATION_VISIBLE` si no hay hallazgos visibles. **NO_SCOPE_VIOLATION_VISIBLE no significa ALLOW**, ni garantiza un diff real válido. Ambos resultados conservan `write_allowed=false`.

La salida `PG05_C4_WRITE_BOUNDARY_DIAGNOSTIC_CANDIDATE_V1` incluye `affected_solutions` y `unaffected_solutions_not_promoted`, con aislamiento por solución, pero nunca altera el estado oficial de otra unidad. Las referencias aportadas por el caller no están autenticadas; `real_diff_verified=false`, `repository_path_admission_executed=false`, `source_head_currentness_verified=false`, `writer_lock_verified=false` y `pg05_admitted=false`.

## Límites importantes

1. No se leen diffs reales ni se verifican permisos GitHub, DB, HEAD vigente o cambios transitivos.
2. Un recurso `DB_OBJECT` queda identificado de manera lógica; aliases, SQL dinámico, triggers, side effects o colisiones físicas necesitan el resolvedor autorizado.
3. No se adquieren locks, no se escribe en repositorios ni Supabase, no se activa ningún escritor.
4. Se preserva `CANDIDATE_NOT_ADMITTED`, `production_authority=false`, `handoff_allowed=false`.
5. El checkpoint requiere **pruebas negativas ejecutadas** antes de considerarse terminado. Por instrucción del Owner, estas pruebas se mantienen aplazadas y **C4 oficial sigue PENDING**.

## Siguiente paso

PG-05_C5: preparación de aseguramiento independiente, reutilizando `INDEPENDENT_ASSURANCE` y los sobres C1–C4. No se debe iniciar una segunda operación de juez ni dar autoridad a resultados candidatos.

**Dictamen:** `PG05_C4_SOURCE_DIAGNOSTIC_READY / REAL_DIFF_AND_PATH_ADMISSION_NOT_VERIFIED / NEGATIVE_TESTS_DEFERRED / C4_OFFICIAL_PENDING`.
