# PG-07_C4 — Contrato primero, reglas y formateadores (2026-11-03)

## Mandato
El checkpoint oficial PG-07_C4 indica: **“Contrato primero (STD-API-06); skills y STD con ejemplos OK/NO en el contexto; formateadores antes de entregar el patch”**.

No se duplican validadores C6, el compilador de contexto ni Changeset Governance. El componente agregado es un **enlace de preparación** sin ejecución.

## Código incorporado
`tools/pg07_c4_contract_first_standards_candidate_v1.py` expone:

`prepare_pg07_c4(pg07_c1, pg07_c2, pg07_c3, standards_catalog_selection, solution_policy_plans)`

### Entradas
- Sobres fuente C1/C2/C3 con hashes completos y vínculos de origen.
- Selección de catálogo `catalog_ref`, `catalog_sha256`, `catalog_version`, `selection_ref` y `entries`.
- Cada regla `STD`, `SKILL` o `CONTRACT` contiene identificador, versión, ref y SHA de fuente, ejemplos OK/NO cuando aplica, y soluciones destinatarias.
- Plan explícito por solución con regla de contrato primero, referencias de reglas y comandos de formateo (`formatter_tool_ref`, `command_ref`, `scope_ref`, `expected_artifact_ref`).

### Comprobaciones candidatas
1. Mismo conjunto de soluciones C2/C3 y ausencia de autoridad de despacho.
2. Selección por solución exactamente igual a las entradas del catálogo declaradas aplicables.
3. Regla de contrato primero presente entre las STD o contratos requeridos.
4. Todas las referencias seleccionadas deben estar también en la proyección de contexto C3 (por `ref_id`). La equivalencia de `rule_id` y `ref_id` es una **convención del manifiesto candidato**, pendiente de validar frente al catálogo C6 real.
5. Cada solución tiene al menos un comando de formateo declarado; no se inventa el comando ejecutable ni la herramienta.
6. Cuando C3 marca `BLOCK_CONTEXT_BUDGET`, C4 conserva el bloqueo.
7. Resultado `PG07_C4_CONTRACT_FIRST_STANDARDS_CANDIDATE_V1` con huella de la selección, reglas, ejemplos y plan de formateo.

### Límites
El catálogo entregado por el llamador NO demuestra que `STD-API-06` tenga determinado texto, alcance o versión. El buscador de código no devolvió una definición íntegra verificable de STD-API-06; no se improvisa su contenido. Debe consultarse la fuente C6 gobernada y comprobar en cada tarea si STD-API-06 aplica; no debe imponerse ciegamente sobre todas las tareas.

Tampoco se ha demostrado que el Worker reciba únicamente las reglas seleccionadas ni que las referencias `OK/NO` se hayan leído. **Los formateadores se planifican, pero no se ejecutan.** Su ejecución obligatoria ocurre sobre el diff real antes de entregar el patch y requiere recibos del ejecutor autorizado.

Se mantienen `catalog_currentness_verified=false`, `std_api_06_authenticity_verified=false`, `ok_no_examples_readback_verified=false`, `formatters_executed=false`, `patch_delivered=false`, `worker_invoked=false`, `dispatch_allowed=false`, `production_authority=false` y `handoff_allowed=false`.

**Dictamen:** `PG07_C4_SOURCE_RULE_AND_FORMATTER_PLAN_PREPARED / LIVE_C6_CATALOG_UNVERIFIED / FORMATTING_NOT_EXECUTED / OFFICIAL_PENDING`.

Pruebas Python aún en pausa por decisión del Owner. No se modifica Análisis, Supabase, main ni ninguna rama productiva.

Siguiente paso de ruta crítica: **PG-07_C5** — iteraciones explicables y ligadas al objetivo; cambios de objetivo, aceptación o scope deben ir a PG-10, nunca aplicarse en silencio.
