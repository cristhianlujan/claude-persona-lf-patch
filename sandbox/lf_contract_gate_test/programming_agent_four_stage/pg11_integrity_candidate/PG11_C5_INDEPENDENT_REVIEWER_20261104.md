# PG-11_C5 — Separación entre constructor y revisor (2026-11-04)

## Criterio oficial (Supabase solo lectura)
**PG-11_C5:** «El revisor es distinto del constructor». Criterio compartido PG-11: «Diff final no contiene cambios huérfanos, deuda inventada ni scope creep». Estado oficial **PENDING**.

## Fuente preparada
`tools/pg11_c5_independent_reviewer_candidate_v1.py`, función `prepare_pg11_c5(pg11_c4, review_observations, review_policy_ref)`.

La fuente recibe el sobre C4 y su SHA-256, y una declaración de constructor/revisor por cada ruta cambiada. Requiere cobertura exacta del conjunto de rutas, identidades y procedencias referenciadas, política de revisión y alcance de cada revisión. Rechaza duplicados, cambios sin revisor asignado e identidades declaradas iguales, así como `reviewer_is_builder_reported=true`.

Incluso cuando se declaran identidades distintas y `reviewer_independence_reported=true`, no se afirma independencia auténtica: podrían ser alias o cuentas controladas por el mismo principal. Las referencias aportadas por el constructor no son comprobantes de un proveedor de identidades.

## Límites y deuda técnica diferida
- Contrastar identidades reales del constructor, revisor, ownership y delegaciones con una autoridad de identidades, no depender de cadenas declaradas.
- Verificar el alcance completo del diff real y artefactos de C1–C4; bloquear autorevisión directa o indirecta.
- Ejecutar efectivamente la revisión independiente, recoger recibo y dictamen congelados sobre HEAD exacto, y probar negativos de alias, duplicados, scope parcial y reviewer inexistente.
- Integrar guardia real al circuito PG sin reemplazar al despachador ni inventar permisos.

El componente mantiene `reviewer_independence_verified=false`, `independent_review_executed=false`, `pg11_c5_pass=false`, `handoff_allowed=false`, `production_authority=false`.

**Estado:** `PG11_C5_SOURCE_PREPARED / REVIEW_NOT_EXECUTED / OFFICIAL_PENDING`.

**PG-11:** 5/5 fuentes candidatas preparadas; 0/5 checkpoints oficiales calificados. Pruebas e integración permanecen como deuda técnica convenida.

**Siguiente desarrollo:** PG-12_C1 — identidad reproducible del candidato (base SHA, SHA/tree, digest del diff, paths, objetos cambiados, builder). Sin Análisis, Supabase write, main ni cambios productivos. PR #3528 sigue en draft.
