# PG-08_C7 — Fronteras de arquitectura D15 (2026-11-04)

## Contrato oficial
Fuente: `supabase/migrations/20261028160000_lf_programming_pg00_standards_checkpoints_decisions_v2.sql`.

**PG-08_C7:** “Fronteras de arquitectura (D15): pruebas que verifican que los módulos solo se usan por su API pública o eventos (LF: Spring Modulith verify() / ArchUnit)”.

**Criterio de salida:** `PASS`.

Este componente es exclusivamente de **preparación de fuente**. No invoca tests, Java, Maven, GitHub CI ni modelos.

## Reutilización
- `PG08_C1_BUILD_COMPILATION_CANDIDATE_V1`: identidad declarada del repositorio, base SHA, candidato HEAD, digest del diff y modo de ejecutor.
- `PG08_C6_CHECK_RECEIPT_FEEDBACK_CANDIDATE_V1`: enlace por SHA-256 al conjunto C1–C5 y registro de recibos anteriores como feedback, nunca veredicto.
- Se verifica la igualdad de identidad por solución entre C1 y C6; no se reconstruyen ni duplican los controles ya preparados.

## Implementación
Archivo: `tools/pg08_c7_arch_boundary_candidate_v1.py`.

Función: `prepare_pg08_c7(pg08_c1, pg08_c6, architecture_observations)`.

Para cada solución se exige:
1. Coincidencia exacta de `solution_id`, repo, base SHA, candidate HEAD, digest del diff y `GPT_NATIVE | CLAUDE_NATIVE | WORKER_API`.
2. Referencia explícita del perfil de arquitectura aplicable.
3. Dos declaraciones separadas: `SPRING_MODULITH_VERIFY` y `ARCHUNIT`, cada una `REQUIRED` o `NOT_APPLICABLE`.
4. En caso `REQUIRED`, ID/comando, nombre y versión de herramienta, digests de configuración/stdout/stderr, referencia de recibo, estado y exit code.
5. Hallazgos por check con regla de frontera, módulo origen, módulo destino y severidad `BLOCK | WARN | INFO`.

Se rechazan: esquemas o hashes fuente alterados, autoridad prematura, cobertura incompleta, duplicados, identidad de candidato inconsistente, `PASS` declarado con hallazgos `BLOCK`, exit codes contradictorios o `NOT_APPLICABLE` acompañado de una ejecución inventada.

La decisión de que Modulith o ArchUnit no aplique al proyecto **no** es automática: exige una referencia, pero su pertinencia deberá verificarse contra la configuración real del target. Tampoco basta con un test que supuestamente pasa para asegurar cobertura de todas las fronteras arquitectónicas.

## Límites de evidencia
Los campos del invocador son declaraciones no autenticadas. En particular, el componente no prueba:
- que `verify()` o ArchUnit hayan ejecutado pruebas reales;
- que el conjunto de módulos y fronteras D15 esté completo;
- que el HEAD candidato y el diff declarado correspondan al checkout observado;
- que la herramienta, versión, configuración o recibo sean auténticos;
- que se hayan evitado accesos no permitidos entre módulos.

Incluso con resultados reportados como `PASS`, el sobre conserva `pg08_c7_pass=false`, `architecture_checks_executed_by_this_component=false`, `architecture_profile_verified=false`, `boundary_coverage_verified=false`, `exact_head_readback_verified=false`, `receipts_authenticated=false`, `pg08_c7_admitted=false`, `handoff_allowed=false` y `production_authority=false`.

## Estado
**`PG08_C7_SOURCE_PREPARED / ARCHITECTURE_TESTS_NOT_EXECUTED / OFFICIAL_PENDING`**.

**Siguiente:** PG-08_C8 — infraestructura y contenedores, bajo D14 y STD-IAC/CONT, sin aplicar cambios en nube. Las pruebas y la calificación oficial permanecen pausadas por indicación del Owner.

Se mantiene el PR #3528 en draft. No se altera Análisis, Supabase, main ni el producto.
