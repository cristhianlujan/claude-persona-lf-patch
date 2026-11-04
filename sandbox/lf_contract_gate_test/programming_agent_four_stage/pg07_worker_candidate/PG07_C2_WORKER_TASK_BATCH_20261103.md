# PG-07_C2 — Preparación de tareas por lote (2026-11-03)

## Contrato

El checkpoint PG-07_C2 exige una tarea por lote con `fn_agent_task_worker_spec`, incluyendo objetivo, referencias, write-scope, comandos de aceptación y vínculo al oráculo oculto separado del repositorio de trabajo. Esta implementación prepara una **proyección candidata**, no ejecuta el Worker ni concede acceso al oráculo.

## Reutilización en lugar de duplicación

`programacion.fn_agent_task_worker_spec(bigint,text,text)` ya produce la especificación visible de la tarea con `schema_version=2` desde `programacion.fn_agent_task_execution_bundle`; este último es privilegiado y contiene `oracle_envelope`. El constructor solo debe consumir la primera función. Fuente existente: `supabase/migrations/20260824041516_programacion_worker_spec_oracle_isolation_v3.sql`.

No se reconstruye ni se modifica el SQL de ese productor; este checkpoint **recibe** una declaración de salida y prepara el paquete mínimo para el Worker.

## Implementación

`tools/pg07_c2_task_batch_projection_v1.py` expone:

`prepare_pg07_c2(pg07_c1, worker_spec_projections, verifier_oracle_bindings)`

El componente:
- valida el hash íntegro y la ausencia de autoridad del preflight PG-07_C1;
- exige una especificación por cada `solution_id`, ligada al `agent_task_id`, `base_head_sha` y `source_snapshot_sha256` ya propuestos en C1;
- conserva el objetivo, cambio esperado, contratos funcionales, alcance, contexto, rutas de escritura, exclusiones, pruebas y comandos de aceptación de la especificación visible V2;
- valida la presencia estructural de campos materiales y límites técnicos de la tarea;
- rechaza llaves reservadas como `hidden_oracle_ref`, `hidden_oracle_sha256`, `oracle_envelope` y `readiness`, incluso si aparecen anidadas;
- mantiene la referencia opaca del oráculo con `access_policy=VERIFIER_ONLY` en `verifier_only_oracle_envelopes`, **fuera de** `worker_payloads`.

**Separación obligatoria de destinatarios:** el despachador autorizado debe proyectar exclusivamente `worker_payloads[].worker_visible_task_spec` hacia el Worker. No debe enviar el sobre completo, que incluye las referencias del verificador. La existencia del campo `verifier_envelopes_worker_delivery_forbidden=true` es solo una política declarada, no una garantía de aislamiento de runtime.

No se puede tratar una `function_result_ref` declarada por el invocador como una lectura auténtica de Supabase. El componente **no invoca** `fn_agent_task_worker_spec`; el readback autorizado y la comparación de sus resultados con las fuentes CURRENT son pendientes reales. Tampoco calcula el presupuesto de contexto, que pertenece a PG-07_C3.

## Estado y límites

`PG07_C2_WORKER_TASK_BATCH_CANDIDATE_V1` declara `worker_spec_runtime_readback_verified=false`, `oracle_access_control_verified=false`, `acceptance_commands_executed=false`, `worker_invoked=false`, `pg07_admitted=false`, `dispatch_allowed=false`, `write_allowed=false`, `production_authority=false` y `handoff_allowed=false`.

**Dictamen:** `PG07_C2_SOURCE_TASK_PROJECTION_PREPARED / ORACLE_RUNTIME_ISOLATION_UNVERIFIED / WORKER_NOT_INVOKED / OFFICIAL_PENDING`.

Siguiente checkpoint **PG-07_C3**: proyección mínima del contexto por tarea y control de presupuesto según el perfil exacto del modelo, sin truncar material y sin introducir el repositorio entero. Pruebas Python aplazadas por decisión del Owner; sin modificaciones de Análisis, Supabase, main ni ramas de producto.
