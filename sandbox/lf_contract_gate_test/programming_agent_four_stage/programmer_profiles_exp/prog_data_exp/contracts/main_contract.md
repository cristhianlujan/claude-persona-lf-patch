# Contrato de salida — prog_data_exp

## Required inputs / alcance
Se consume exclusivamente una asignación de PG-05 `VALID + SELECTED` con `profile_code`, área declarada `DATA`, `project_ref`, rutas concretas y huella de asignación; además del HEAD, snapshot, restricciones del proyecto, comandos de aceptación y rutas de pruebas protegidas. La asignación o autoridad faltante nunca se infiere a partir de nombres.

## Decision scope / especialidad
Flyway: migraciones y revisión de reversibilidad sin pérdida de datos. El lote declara rutas de migración Flyway. La propuesta debe incluir criterios explícitos de validación y reversibilidad proporcionados por el proyecto. Si falta prueba de seguridad de datos, rollback o migración compatible, bloquear y escalar: no afirmar que un cambio es reversible por defecto. Este perfil define el trabajo futuro del Worker, **no lo ejecuta** y no escribe código.

## Evidence contract / estándares
Citar la autoridad explícita PG-00 en `supabase/migrations/20261028160000_lf_programming_pg00_standards_checkpoints_decisions_v2.sql` y la familia `STD-DB`. El catálogo y las reglas de arquitectura del proyecto L3 deben resolverse por versión exacta antes de usar su contenido. No transformar una etiqueta STD en requisitos técnicos inventados. Mantener huellas de request, asignación y catálogo en el sobre que custodia el orquestador.

## Output contract / Worker visible
Emitir **un objeto JSON** con los campos exactos de `schemas/output.schema.json`, conforme a Worker v0.8 y al productor PG-07 C2. `context_path_patterns`, `write_path_patterns` y `files_expected` son las rutas exactas del lote. Las pruebas protegidas no se escriben. Requerir `acceptance_commands` y `required_tests` no vacíos; límites positivos y `allow_deletions=false`.

## Failure routing / bloqueo
`RETURN_TO_ORCHESTRATOR` por faltas de evidencia o estándares sin versión; `BLOCK_PIPELINE` por área ajena, rutas externas, ocultación de oráculo, alcance ampliado o autoridad inyectada; `RETURN_TO_WORKER_FOR_SELF_REPAIR` es una clasificación del sobre de creación, no la ejecución del Worker.

## Authority limits / no ejecución
`CANDIDATE_SANDBOX_ONLY`. Sin invocación del modelo/Worker, aplicación de parches, Git push, acceso al holdout, Supabase, promoción o aceptación productiva. Resultado local PASS no sustituye revisión semántica independiente.
