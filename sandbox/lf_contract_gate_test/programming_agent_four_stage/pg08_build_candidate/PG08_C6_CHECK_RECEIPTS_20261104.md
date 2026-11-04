# PG-08_C6 — Recibos por check como feedback, no veredicto (2026-11-04)

## Contrato oficial
Fuente: `supabase/migrations/20261028160000_lf_programming_pg00_standards_checkpoints_decisions_v2.sql`.

**PG-08_C6:** “Recibos de cada check con herramienta, versión, digest de configuración y SHA; marcados como feedback, no veredicto”.

Criterio de salida: **Recibos completos**. El requisito real exige ejecuciones de herramientas y recibos auténticos; este candidato solo organiza información reportada por consumidores anteriores.

## Reutilización — sin duplicar checks
`tools/pg08_c6_check_receipts_candidate_v1.py` expone:

`prepare_pg08_c6(pg08_c1, pg08_c2, pg08_c3, pg08_c4, pg08_c5)`

El productor consume exclusivamente los sobres fuente existentes. No invoca compiladores, linters, tests, Flyway, Spectral, oasdiff, GitHub Actions, modelos ni Supabase.

Valida:
- Esquema y SHA-256 de los cinco sobres y cadena C1→C2→C3→C4→C5.
- Identidad única por solución; coincidencia del repositorio, base SHA, HEAD candidato, digest de diff y modalidad de ejecución `GPT_NATIVE | CLAUDE_NATIVE | WORKER_API`.
- Estado fuente no admitido y ninguna autoridad prematura.
- Identidad por check y conservación de los datos declarados existentes; nunca inventa campos faltantes.
- Una o más observaciones de build provenientes de `PG-08_C1.commands_reported`, además de las verificaciones de C2–C5.

Cada entrada incluye tipo y checkpoint, resultado declarado, herramienta, versión, configuración SHA, hashes stdout/stderr, comando y referencia de recibo cuando existen, hash del propio registro fuente y listado de carencias. Todo se marca `feedback_only=true`.

## Huecos detectados en el material de entrada

**PG-08_C2** conserva `tool_name`, `tool_version`, `config_sha256`, `execution_receipt_ref` y `command_id`, pero no guarda `command_ref`, `stdout_sha256` ni `stderr_sha256` en sus `checks_reported`. C6 deja esos campos como `null` y registra `missing_source_fields`. No reconstruye hash ni crea recibos ficticios.

**PG-08_C5** admite checks declarados como `NOT_APPLICABLE`. No se presentan como ejecuciones y requieren prueba independiente de no aplicabilidad.

**Los cinco sobres** contienen observaciones declaradas por invocadores, no recibos autenticados. Igualdad de hash del sobre no equivale a autenticidad de la ejecución.

El componente no transforma un `PASS` reportado en veredicto real. Incluso sin carencias aparentes, `receipt_set_complete=false`, `final_verdict_issued=false` y `pg08_c6_pass=false`.

## Garantías y bloqueos restantes
Para cerrar PG-08_C6 oficialmente se necesita:
1. Readback del HEAD exacto, target, diff y configuración real de CI.
2. Ejecución de C1–C5 por herramientas reales y persistencia de recibos por cada check.
3. Resolver el transporte íntegro de evidencias de C2 (comando y stdout/stderr) sin falsificar ni sobrescribir pruebas anteriores.
4. Acreditar la aplicabilidad de las verificaciones de contratos y BD.
5. Verificar procedencia y autenticidad de las evidencias, incluyendo herramienta/versión, digest de configuración y el SHA del código evaluado.
6. Evaluación independiente del conjunto antes del veredicto del siguiente bloque.

**Estado:** `PG08_C6_SOURCE_FEEDBACK_ASSEMBLER_PREPARED / RECEIPTS_UNAUTHENTICATED / OFFICIAL_PENDING`.

La salida conserva `receipt_completeness_verified=false`, `tool_execution_verified=false`, `exact_head_readback_verified=false`, `receipts_authenticated=false`, `pg08_c6_admitted=false`, `handoff_allowed=false` y `production_authority=false`.

## Ruta posterior
Siguiente checkpoint: **PG-08_C7 — fronteras de arquitectura** (Spring Modulith / ArchUnit). No regresar a PG-00 ni crear otro Worker.

Este cambio está solo en PR draft #3528. No modifica Análisis, Supabase, main ni el código de producto; las pruebas oficiales siguen pausadas por decisión del Owner.
