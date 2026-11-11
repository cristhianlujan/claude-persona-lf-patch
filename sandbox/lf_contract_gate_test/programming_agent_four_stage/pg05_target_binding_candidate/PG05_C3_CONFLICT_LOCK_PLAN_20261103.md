# PG-05_C3 — Conflictos materiales y plan de locks entre escritores (2026-11-03)

## Mandato y propiedad

El checkpoint PG-05_C3 exige lock y detección de choques entre writers; solo se admite ejecución paralela cuando no exista choque material sin resolver. Se reutiliza el circuito transversal de Changeset Governance para la admisión de rutas y familias; este componente **no** modifica su validador ni crea un nuevo servicio de locks.

**Componente:** `tools/pg05_c3_collision_lock_plan_candidate_v1.py`. Función `prepare_pg05_c3(pg04_exit, pg05_c2)`.

## Entradas

- Sobre `PG04_TO_PG05_EXIT_CANDIDATE_V1`, congelado y con checksum íntegro.
- Sobre `PG05_C2_WRITE_SCOPE_RESOLUTION_CANDIDATE_V1` del mismo paquete, congelado, con alcance por solución y recursos exactos.
- Todos los flags de autoridad y lock deben ser falsos; no se aceptan sobres admitidos como si fueran fuentes de esta simulación.
- Identidades de soluciones iguales, dependencias de PG-04 explícitas y DAG sin ciclos.

## Evaluación conservadora

La matriz produce una fila por pareja de soluciones:

1. **WRITE_WRITE_MATERIAL_OVERLAP:** mismo archivo, o un archivo/ruta dentro de otra ruta declarada; mismo objeto BD o un objeto BD declarado con relación jerárquica de nombres.
2. **WRITE_SHARED_READ_ONLY_CONFLICT:** una solución intenta escribir un recurso que otra consume como compartido de solo lectura, incluidas rutas padre/hijo y objetos BD con relación jerárquica.
3. **DEPENDENCY_ORDER:** existe dependencia directa o transitiva entre las soluciones, por lo que no se despachan concurrentemente.
4. Sin choque visible: `NOT_PROVEN_SAFE_FOR_PARALLELISM`, **no un PASS de paralelismo**. Puede haber aliases, objetos físicos colindantes, triggers o recursos dinámicos no resueltos.

La clasificación de un par con causas es `BLOCK_CONCURRENT_WRITERS`. Todos los pares mantienen `parallel_execution_allowed=false` por ausencia de autoridad real.

Además, cada solución genera un **lock request candidato**, con los identificadores exactos de recursos a reservar. Tiene `lock_owner_execution_id=null`, `lock_receipt_id=null` y `lock_acquired=false`.

## Límites

Este script:
- no llama al mecanismo real de adquisición, no reserva nada y no escribe en BD;
- no crea ramas de producto, no inspecciona HEADs del destino ni ejecuta Git;
- no reemplaza `lf_repository_path_admission.py`, y marca `repo_path_admission_verified=false`;
- no certifica aliasing, existencia real ni vigencia de L3 y scope;
- no admite ejecución paralela por mera ausencia de coincidencias exactas.

La salida `PG05_C3_CONFLICT_LOCK_PLAN_CANDIDATE_V1` se mantiene `CANDIDATE_NOT_ADMITTED`, `safe_parallelism_attested=false`, `actual_lock_mechanism_resolved=false`, `locks_acquired=false`, `writer_dispatch_allowed=false`, `pg05_admitted=false`, `production_authority=false`, `handoff_allowed=false`.

## Desbloqueo real

1. Resolver `target_binding` auténtico, PG-04 con revisión independiente y scope C2 atestiguado.
2. Readback CURRENT de los recursos reales, incluyendo aliases, colindancias y objetos BD mutables involucrados.
3. Consumir la política de ruta y Changeset Governance existente; no duplicar circuitos.
4. Obtener locks de la autoridad de ejecución real, con recibos ligados al SHA base, recursos y ejecución.
5. Verificar orden del DAG; solo entonces autorizar un writer o la concurrencia de pares independientes.

**Estado:** `PG05_C3_CONFLICT_MATRIX_SOURCE_READY / LOCK_PLAN_SOURCE_READY / REAL_LOCK_UNRESOLVED / OFFICIAL_PENDING`.

Las pruebas Python se mantienen en pausa por decisión del Owner. No se declaró PASS de código exact-HEAD, no se modificó Análisis, Supabase ni main.
