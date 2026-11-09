# PG-12_C1 — Identidad reproducible del candidato (2026-11-04)

## Criterio oficial (consulta de solo lectura)
**PG-12_C1:** «Base SHA, SHA/tree del candidato, digest del diff, paths y objetos cambiados, builder».

**Criterio de salida de PG-12:** «La identidad del candidato puede reconstruirse sin inferencias posteriores».

## Componente fuente
`tools/pg12_c1_candidate_identity_v1.py` expone `prepare_pg12_c1(pg11_c5, repo_ref, base_commit_sha, candidate_commit_sha, candidate_tree_sha, diff_sha256, changed_objects, builder_principal_ref, builder_provenance_ref)`.

Produce un sobre candidato que describe una base, un commit, su árbol, SHA-256 del diff, lista ordenada de rutas, objetos Git tipados y procedencia declarada del constructor.

Valida forma de identificadores Git y SHA-256, integridad del sobre PG-11_C5, ausencia de autoridad, cobertura de rutas declaradas 1:1 con PG-11_C5, coherencia de altas, bajas, modificaciones y renombres, y coincidencia de builder/procedencia declarados con C5. Rechaza objetos duplicados y rutas no canónicas.

## No significa todavía
- **No** lee realmente el árbol Git, los blobs, el contenido del diff ni valida que los SHA correspondan al repositorio indicado.
- **No** valida que el builder haya creado el commit ni que la identidad/procedencia declarada corresponda a una persona/agente autenticado.
- Un SHA-256 del sobre establece únicamente consistencia interna sobre las declaraciones; **no demuestra reconstrucción reproducible real**.
- El commit que incorpora este archivo al PR es independiente del `candidate_commit_sha` que podría suministrarse en futuras ejecuciones. No debe tratarse el HEAD de desarrollo del componente como prueba de identidad de un candidato de programación.

Todos los indicadores de readback, autenticación y reconstrucción permanecen `false`, al igual que `pg12_c1_pass`, `pg12_c1_admitted`, `handoff_allowed` y `production_authority`.

**Estado:** `PG12_C1_SOURCE_PREPARED / NOT_TESTED / NOT_QUALIFIED / OFFICIAL_PENDING`.

## Deuda técnica diferida
1. Ejecutar lectura real de base/HEAD/tree y objetos contra Git, calcular el diff canónico y su SHA-256.
2. Contrastar rutas completas del diff con los registros C1–C5 y evidencias de builder desde una fuente confiable.
3. Guardar recibo de reconstrucción y pruebas adversariales sobre SHA, rutas, renombres, objetos incompletos o identidad de builder falsa; revisión independiente del HEAD exacto.

**Siguiente desarrollo:** PG-12_C2 — fuentes/contexto/versiones/herramientas/costos y mapa identificador → term_id.

PR #3528 continúa draft, sin modificar Análisis, Supabase, main ni producto.
