# PG-08_C1 — Build/compilación posterior a PG-07 (candidato fuente, 2026-11-04)

## Posición exacta en la ruta crítica

El requisito oficial de `PG-08_C1` es **“Build/compilación (V1: ./mvnw verify, pnpm build)”**, con salida **“PASS con versión de herramienta”**. El origen está en `supabase/migrations/20261028160000_lf_programming_pg00_standards_checkpoints_decisions_v2.sql`.

La fuente `PG07_C6_BATCH_EVIDENCE_MANIFEST_CANDIDATE_V1` es **un manifiesto declarado**, no un recibo auténtico del Worker. Los componentes C1–C6 continúan PENDING oficialmente. Este componente no ejecuta build, compilación, validadores ni CI.

## Reutilización sin trabajo repetido

- `PG-06_C4`: preserva build/lint del **target sin cambios** y violaciones preexistentes. No sustituye el build posterior al patch.
- `PG-07_C6`: referencias declaradas a base HEAD, candidato, diff y soluciones. No prueba la autenticidad del resultado ni invocación del modelo.
- `PG-08_C1`: prepara el vínculo entre la solución y **resultados posteriores de build**, incluidas versiones de herramientas, hashes de configuración, stdout/stderr y recibo de ejecución.

No se añade otro Worker, Router, despachador ni ruta de escritura.

## Adaptación híbrida — fuente de código independiente del check

El modo se conserva como procedencia declarada en cada solución:
`GPT_NATIVE`, `CLAUDE_NATIVE` o `WORKER_API`.

Todos deben pasar los mismos controles de build. Un resultado `GPT_NATIVE` no se transforma en `WORKER_API`, y el manifiesto de PG-07_C6 no se interpreta como una llamada al Worker real. La autenticación de procedencia queda pendiente del runtime.

## Código

`tools/pg08_c1_build_compilation_candidate_v1.py`:

`prepare_pg08_c1(pg07_c6, build_observations)`

Validaciones estáticas:
1. Esquema y SHA-256 del manifiesto C6, sin autoridad prematura.
2. Cobertura exactamente una-a-una de `solution_id`.
3. Coincidencia exacta de repositorio, base HEAD, candidato HEAD y digest del diff entre C6 y observación.
4. Declaración explícita de ejecutor y referencia al resultado.
5. Lista no vacía de observaciones de build, IDs no duplicados, nombre y versión de herramienta.
6. Digests de configuración/stdout/stderr, referencia de recibo y coherencia de PASS/FAIL/BLOCKED con el exit code.

Las observaciones provienen del invocador: incluso si declaran PASS, la salida se etiqueta `REPORTED_PASS_UNVERIFIED`. No se hace checkout ni readback de GitHub; no se invoca Maven, pnpm ni un modelo.

La salida `PG08_C1_BUILD_COMPILATION_CANDIDATE_V1` mantiene siempre:
`pg08_c1_pass=false`, `build_executed_by_this_component=false`, `tool_version_verified=false`, `diff_readback_verified=false`, `executor_provenance_verified=false`, `pg08_c1_admitted=false`, `handoff_allowed=false`, `production_authority=false`.

## Qué falta para un PASS real

1. Obtener un patch real por un ejecutor autorizado, con provenance verificable.
2. Readback del repo en HEAD exacto y correspondencia del patch, target, scope y diff.
3. Resolver el build permitido por la tecnología del target, desde la configuración y CI autorizados.
4. Ejecutar build/compilación en aislamiento contra el candidato real y registrar versión de herramienta, exit code y recibos auténticos.
5. Verificar el resultado por un consumidor independiente antes de calificar `PG-08_C1`.

## Estado y límites

**`PG08_C1_SOURCE_PREPARED / BUILD_NOT_EXECUTED / OFFICIAL_PENDING`.**

El Owner mantuvo pausadas las pruebas oficiales. Este cambio es únicamente fuente candidata en PR draft #3528; no altera Análisis, Supabase, el repositorio objetivo ni main. Las compatibilidades dinámicas y pruebas adversariales quedan pendientes.
