# PG-08_C5 — Lint de contratos OpenAPI y catálogo de BD (2026-11-04)

## Contrato oficial y límite
Fuente: `supabase/migrations/20261028160000_lf_programming_pg00_standards_checkpoints_decisions_v2.sql`.

**Checkpoint PG-08_C5:** “Lint de contratos: Spectral sobre OpenAPI, oasdiff (breaking), lint de catálogo de la BD migrada”.

**Criterio de salida:** `0 BLOCK`.

No es un checkpoint completado. Esta fuente únicamente prepara y comprueba la estructura de observaciones aportadas por un invocador; **no** ejecuta Spectral, oasdiff, migraciones, lint de BD, GitHub Actions ni llamadas a IA.

## Reutilización y procedencia
Se reutilizan:
- `PG08_C1_BUILD_COMPILATION_CANDIDATE_V1`: repositorio, base HEAD, HEAD candidato, digest del diff y procedencia declarada del ejecutor.
- `PG08_C4_TEST_AND_LOCAL_FLYWAY_CANDIDATE_V1`: identidad del mismo candidato y cadena de SHA desde C1, C3 y C2 por sus respectivos sobres.

La procedencia declarada puede ser `GPT_NATIVE`, `CLAUDE_NATIVE` o `WORKER_API`. Se preserva el dato sin convertirlo en prueba de invocación del modelo. No se crea un nuevo despachador.

## Componente
`tools/pg08_c5_contract_lint_candidate_v1.py` expone:
`prepare_pg08_c5(pg08_c1, pg08_c4, contract_observations)`

Cada solución exige exactamente tres evaluaciones diferenciadas:
1. `SPECTRAL_OPENAPI`: revisión del contrato OpenAPI con Spectral.
2. `OASDIFF_BREAKING`: comparación de la API base y la candidata, con clasificación de cambios incompatibles.
3. `MIGRATED_DB_CATALOG`: lint del catálogo de base de datos migrada.

Cada evaluación debe declarar explícitamente `REQUIRED` o `NOT_APPLICABLE` y aportar una referencia a la decisión de aplicabilidad.

Para una evaluación `REQUIRED` se exigen: comando y referencia, herramienta y versión, configuración SHA-256, digests declarados de contratos base/candidato, stdout/stderr SHA-256, referencia de recibo, resultado, exit code y hallazgos con severidad `BLOCK/WARN/INFO`.

`NOT_APPLICABLE` no produce falsas evidencias de ejecución: los campos de ejecución deben venir `null` y la lista de hallazgos vacía. **La decisión de no aplicabilidad permanece no verificada** hasta la inspección gobernada del target y su CI.

Se rechazan omisiones, duplicados, cambio de identidad del target/HEAD/diff/ejecutor, contradicciones entre exit code y resultado, y `PASS` junto con hallazgos declarados como `BLOCK`.

## Diferencia entre reporte y evidencia real
El invocador puede suministrar referencias formalmente válidas que no correspondan a un artefacto real. Este productor no autentica:
- la selección de herramientas ni que el OpenAPI exista;
- la comparación exacta de versiones para detectar breaking changes;
- que el catálogo analizado corresponda a una BD local migrada;
- las reglas y configuración vigentes del CI;
- los recibos, hashes o resultados efectivamente emitidos.

Un reporte con cero `BLOCK` genera solamente `REPORTED_ZERO_BLOCK_UNVERIFIED`. Cualquier exclusión de evaluación genera `REPORTED_APPLICABILITY_UNVERIFIED` cuando no hay otros problemas declarados.

La salida `PG08_C5_CONTRACT_LINT_CANDIDATE_V1` fuerza siempre:
`contract_checks_executed_by_this_component=false`,
`diff_readback_verified=false`,
`applicability_verified=false`,
`migrated_db_catalog_verified=false`,
`receipts_authenticated=false`,
`pg08_c5_pass=false`,
`pg08_c5_admitted=false`,
`handoff_allowed=false`,
`production_authority=false`.

## Para alcanzar C5 oficial
1. Confirmar aplicabilidad de los tres controles desde el target exacto y los contratos tecnológicos.
2. Readback del HEAD candidato y del diff real.
3. Ejecutar las herramientas sobre los contratos y el catálogo real de la BD local migrada.
4. Autenticar versiones, comandos, configuración, recibos y hallazgos.
5. Obtener calificación independiente antes de marcar `0 BLOCK`.

## Estado y continuación
**`PG08_C5_SOURCE_PREPARED / CONTRACT_LINT_NOT_EXECUTED / OFFICIAL_PENDING`**.

Siguiente: `PG-08_C6`, recibos por check de herramienta, versión, digest de configuración y SHA, como feedback y no veredicto.

El Owner mantiene pausadas las pruebas oficiales. No se modifica Supabase, Análisis, main ni el código de producto. El cambio permanece en PR draft #3528.
