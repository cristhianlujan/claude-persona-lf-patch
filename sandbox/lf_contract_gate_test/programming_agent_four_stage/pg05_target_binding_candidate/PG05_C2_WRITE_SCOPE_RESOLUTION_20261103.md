# PG-05_C2 — Resolución de write-scope por solución (2026-11-03)

## Objetivo

Convertir los write-scope candidatos de PG-04 en recursos explícitos y auditables para PG-05, conservando la política de que **el contrato compartido es de solo lectura por defecto**. Esto es únicamente **preparación fuente**, no autorización para un writer.

## Fuentes y reuso

- El contrato `PROGRAMMING_ENTRY_CONTRACT_V1` asigna la propiedad del write-scope a PG-05 y prohíbe inferir repositorio/HEAD.
- El checkpoint PG-05_C2 exige rutas y objetos de BD derivados del lote, respetando la estructura L3; lo compartido entre soluciones es de solo lectura por defecto.
- La admisión general de rutas GitHub ya está implementada en `sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_repository_path_admission.py`, propiedad de Changeset Governance. **No se ha duplicado**: la nueva pieza declara `repository_path_admission_executed=false` y la requiere al tomar decisiones ejecutables.
- PG-05_C3 conserva la propiedad de locks y resolución de colisiones.

## Componente agregado

`tools/pg05_c2_write_scope_candidate_v1.py` expone:

`prepare_pg05_c2(pg04_exit, pg05_c1, scope_resolutions)`

Solo consume sobres candidatos con hashes exactos:
- `PG04_TO_PG05_EXIT_CANDIDATE_V1`
- `PG05_C1_TARGET_BINDING_PREFLIGHT_CANDIDATE_V1`

Para cada solución, el llamador debe suministrar explícitamente:
- `solution_id` igual al del paquete;
- `l3_structure_ref` que justifique la ubicación de rutas y recursos, sin inferencia;
- un `resolved_scope` por cada `write_scope_candidate` original, con `scope_token`, `derivation_ref` y lista de `resources`;
- `resources` con `kind=REPO_PATH` y ruta relativa exacta del repositorio, o `kind=DB_OBJECT` y nombre calificado `schema.object` (admite un tercer segmento para miembros específicos), más `source_ref`;
- una vinculación `shared_read_ref` por cada contrato compartido, con recurso exacto y `access=READ_ONLY`.

No acepta globbing, rutas absolutas, `..`, rutas con `\` ni tokens de scope sin resolver. No inventa directorios L3, nombres de tablas o paths. Rechaza rutas repetidas dentro de la misma solución y la coexistencia de lectura compartida/escritura para el mismo recurso dentro de esa solución. Rechaza ausencia de mapeo de contratos compartidos.

## Solapamientos y límites

El productor C2 clasifica recursos exactos compartidos entre writers:
- `PG05_C3_WRITE_COLLISION_UNRESOLVED` cuando dos soluciones proponen escribir el mismo recurso exacto;
- `SHARED_READ_ONLY_WRITE_CONFLICT` cuando una solución intenta escribir un recurso que otra declaró lectura compartida.

Las colisiones se documentan en `collisions_for_pg05_c3`; no se otorga lock ni se permite ejecución paralela. Una ruta que sea ancestro de otra o un recurso semánticamente equivalente bajo dos aliases todavía requiere inspección por la gobernanza que resuelve recursos. **No** se afirma ausencia de choques materiales porque no se ejecutó ese control.

El resultado conserva `CANDIDATE_NOT_ADMITTED`, los recursos con sus referencias, bandera `write_scope_authorized=false`, `resource_existence_verified=false`, `l3_structure_currentness_verified=false`, `repository_path_admission_executed=false`, `writer_lock_acquired=false`, `branch_created=false`, `pg05_admitted=false`, `production_authority=false` y `handoff_allowed=false`.

## Estado y próximos pasos

`PG05_C2_SCOPE_RESOLVER_SOURCE_READY / TARGET_AND_L3_UNVERIFIED / PG05_C3_COLLISION_REVIEW_REQUIRED / OFFICIAL_C2_PENDING`.

**Sin ejecutar nuevas pruebas Python**, conforme a la decisión de posponerlas; este avance no se puede declarar PASS de ejecución exact-HEAD. No se creó branch de producto, no se realizó escritura en Supabase ni se modificaron Análisis o `main`.

El siguiente checkpoint es **PG-05_C3**, prevención real de choques entre writers y locks; no deberá admitir paralelismo por ausencia de duplicados exactos únicamente.
