# PG-08_C2 — Formato y lint sobre el diff (candidato fuente, 2026-11-04)

## Contrato oficial y frontera

Fuente oficial: `supabase/migrations/20261028160000_lf_programming_pg00_standards_checkpoints_decisions_v2.sql`.

- **Checkpoint**: `PG-08_C2`.
- **Título**: “Formato + lint (incluye nombres) sobre el diff, con la configuración del CI”.
- **Criterio de salida**: **“0 BLOCK nuevos frente a la línea base”**.

Esta implementación no ejecuta linter, formatter, CI, ni obtiene una revisión de GitHub. Se limita a preparar un sobre de observaciones **reportadas y no autenticadas**, listo para un futuro consumidor que ejecute los checks.

## Qué se reutiliza (sin recrear)

1. `PG-06_C4_BASELINE_BUILD_LINT_CANDIDATE_V1`: líneas base de lint del target sin modificar y `preexisting_violation_refs` por solución. El propio PG-06_C4 aún no acredita la equivalencia de los hallazgos ni la autenticidad de su recibo.
2. `PG-08_C1_BUILD_COMPILATION_CANDIDATE_V1`: por solución, misma base, candidato HEAD, digest del diff y ejecutor declarado. PG-08_C1 tampoco acredita la ejecución real del build.
3. Se conserva la declaración de procedencia `GPT_NATIVE | CLAUDE_NATIVE | WORKER_API`, sin inferir que un GPT nativo llamó al Worker por API.

No se modifica PG-07, no se crea otro ejecutor ni se altera el circuito de perfiles.

## Código agregado

`tools/pg08_c2_format_lint_delta_candidate_v1.py` expone:

`prepare_pg08_c2(pg06_c4, pg08_c1, lint_observations)`

Recibe un lote con cobertura 1:1 de `solution_id`. Cada observación declara target, base HEAD, candidate HEAD y digest de diff exactamente iguales a PG-08_C1, y dos checks —`FORMAT` y `LINT`— con IDs únicos, referencias de comando, herramienta, versión, SHA-256 de configuración/stdout/stderr, estado, exit code y recibo declarado.

Los hallazgos incluyen `violation_ref`, severidad `BLOCK|WARN|INFO`, regla, path relativo, línea y si corresponden al diff o repositorio. Un `violation_ref` presente en la línea base LINT de PG-06_C4 se clasifica **`REPORTED_PREEXISTING`**; uno ausente, **`REPORTED_NEW`**. No se afirma equivalencia probada: los `violation_ref` aportados por el invocador aún deben vincularse a identidades estables de regla/archivo/ubicación.

Los resultados posibles son `REPORTED_NEW_BLOCKERS`, `REPORTED_CHECK_NOT_PASS` o `REPORTED_NO_NEW_BLOCKERS_UNVERIFIED`. El resultado `PASS` de un comando no se acepta junto a hallazgos de severidad `BLOCK`.

## Límites críticos

**No** declarar `PASS` de PG-08_C2 porque las referencias reportadas coincidan; los siguientes controles siguen pendientes:

- Readback del commit, diff y paths afectados.
- Ejecución real de formato y lint configurados por el CI del target (incluidas reglas de nombres).
- Verificación exacta de la línea base PG-06_C4 y de la configuración usada por ambas corridas.
- Equivalencia independiente de hallazgos a través de la base y el diff, no solamente igualdad de identificadores aportados.
- Readback/autenticación de recibos y versiones de las herramientas.
- Controles de una salida parcial o fallida de cualquiera de los dos checks.

El resultado fuerza `pg08_c2_pass=false`, `format_lint_executed_by_this_component=false`, `baseline_currentness_verified=false`, `diff_readback_verified=false`, `ci_configuration_verified=false`, `receipts_authenticated=false`, `pg08_c2_admitted=false`, `handoff_allowed=false` y `production_authority=false`.

## Estado

`PG08_C2_SOURCE_PREPARED / FORMAT_LINT_NOT_EXECUTED / OFFICIAL_PENDING`.

Por instrucción anterior del Owner, no se ejecutaron las pruebas oficiales. No se cambió Supabase, el repositorio de producto, Análisis o main. El cambio está contenido en PR draft #3528.
