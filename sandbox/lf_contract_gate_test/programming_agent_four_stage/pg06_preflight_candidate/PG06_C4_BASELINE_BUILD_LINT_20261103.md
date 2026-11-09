# PG-06_C4 — Línea base de build y lint del target sin cambios (2026-11-03)

## Requisito oficial

PG-06_C4: **“Línea base: build + lint del target sin cambios; se registran las violaciones previas”**. Criterio de salida: **“Línea base con digest”**. Fuente: `supabase/migrations/20261028160000_lf_programming_pg00_standards_checkpoints_decisions_v2.sql`.

La línea base debe permitir distinguir un fallo preexistente en la revisión base del repositorio de una regresión causada por futuras modificaciones del Worker. Eso exige comandos y observaciones ligados al **target exacto**, no al repositorio de infraestructura donde está este componente.

## Implementación fuente candidata

`tools/pg06_c4_baseline_capture_candidate_v1.py` expone:

`prepare_pg06_c4(pg05_exit, pg06_c1, pg06_c2, pg06_c3, baseline_observations)`

El paquete de observación debe incluir:
- `target_repo` y `base_head_sha` exactos, iguales al `target_binding` de PG-05 → PG-06;
- `observation_ref` y `execution_environment_ref`;
- `unchanged_target_claim=true`, tratada como **declaración no autenticada**, jamás como prueba de un árbol limpio;
- por cada solución, resultados **BUILD** y **LINT** con `command_id`, `command_ref`, `command_sha256`, `execution_receipt_ref`, `stdout_sha256`, `stderr_sha256`, `result`, `exit_code` y `violation_refs`.

El preflight exige cobertura BUILD+LINT para todas las soluciones declaradas, referencias de evidencia por comando, hashes de formato válido, sin comandos duplicados y coherencia entre `PASS`/exit code cero y `FAIL`/exit code distinto de cero. Los hallazgos reportados se preservan por solución como `preexisting_violation_refs`.

**No inventa comandos** ni decide qué perfil debe ejecutar Maven, pnpm, Node u otras herramientas: corresponde al perfil técnico y al catálogo que resuelve PG-06_C2.

## Salida

`PG06_C4_BASELINE_BUILD_LINT_CANDIDATE_V1` conserva:
- hashes exactos de los sobres upstream PG05 → PG06, C1, C2 y C3;
- `observation_manifest_sha256` y `baseline_digest_recorded`;
- resultados reportados `REPORTED_BASELINE_FAILURE` o `REPORTED_BASELINE_PASS_UNVERIFIED`, **no** una admisión de ejecución;
- `unchanged_target_verified=false`;
- `build_lint_executed_by_this_component=false`;
- `receipts_authenticated=false`, `pg06_ready=false`, `write_allowed=false`, `handoff_allowed=false`, `production_authority=false`.

## Qué sigue faltando para C4 oficial

1. Obtener un `target_binding` legítimo, admitido, con base SHA vigente.
2. Comprobar que el repositorio de destino está exactamente en esa base y sin cambios; recolectar prueba de árbol limpio.
3. Ejecutar realmente BUILD y LINT con las herramientas autorizadas y registrar sus salidas y fallos existentes.
4. Autenticar recibos, fingerprints y referencias, calificando el contrato exact-HEAD.
5. Rechazar confundir declaraciones del caller con resultados observados por una herramienta.

**Estado:** `PG06_C4_SOURCE_BASELINE_MANIFEST_PREPARED / REAL_BUILD_LINT_NOT_RUN / TARGET_UNCHANGED_NOT_VERIFIED / OFFICIAL_PENDING`.

Las pruebas Python siguen aplazadas por decisión del Owner. No se modificó el target, Análisis, Supabase ni main; el desarrollo permanece en el draft PR #3528.
