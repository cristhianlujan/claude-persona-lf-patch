# D-04 · Matriz de integración (DISEÑO únicamente)

| Subsistema existente | Entrada candidata desde núcleo | Salida esperada | Identidad exacta | Evidencia / autoridad | Riesgos y bloqueantes | Adaptador FUTURO |
|---|---|---|---|---|---|---|
| `PROGRAMMING_SIMPLE_EXECUTOR_V1` | DAG validado, unidad elegible, bindings validador/checkpoint | Resultado de validación de cada checkpoint y run unit | plan, unit, checkpoint, execution_id, run_id y HEAD | Validador actual y receipts frescos por run; registry ACTIVE | `COMPLETE` significa no más run units RUNNING, **no cierre PIP-1 acreditado**; false COMPLETE si dependientes bloqueados | Read-only snapshot mapper; cierre verificado separado |
| `OPERATION_NEUTRAL_STEP_RECORDER` | Referencia de paso ejecutado, intento, outcome | Receipt/step recorded y readback | operation, step, attempt, execution_id, hash | `lf_record_operation_step_core_v1`; autoridad de recorder existente | No duplicar ledger; binding anti-replay | Adapter idempotente en capa de efectos futura |
| `LF_EVIDENCE_LEDGER_V1` | Exact-head receipt ref + provider | VERIFIED/REJECTED/ANCHORED, readback | source_head_sha, subject_sha256, receipt_sha256, provider | Ledger canónico; juez de evidencia | `VERIFIED` debe leerse en la fuente, nunca inferido desde string | Verifier port (sin implementación) |
| `programming-agent` Worker | Work unit admission y paquete pinned | Resultado de ejecución controlada | job/run/unit exact head, workspace scope | Worker checks visibles/holdout | Worker no puede merge/deploy; límites de costo y permisos | Dry-run request DTO |
| `programming-agent` Runner | Snapshot, execution fingerprint, pruebas | PASS/FAIL/BLOCKED con evidencia | exact HEAD + EKB + run_id | Runner y CI independientes | `PASS` sin binding a checkpoint no acredita | Result translator read-only |
| Router ACT-0001 | Intención clasificada, no emitida por núcleo | Resolución y ruta autorizada | act, route, operation, request ID | Router manda sobre DB_WRITE | Cualquier escritura requiere `ACTUALIZACION_DB_LF` y Train | Solo diseño de solicitud futura |
| PASE | Manifest + exact PR diff | PLAN/APPLY/BLOCK | PR HEAD, source SHA, file classes | Required check del repo | NO PASE oficial sin checkout completo/PR/manifest | CI integration future |
| Merge Train | PR aprobado por controles | merge receipt exact-head | PR, SHA, Train event/receipt | Train única ruta a main | No bypass y no auto-label | Listener read-only eventual |
| Testing | Handoff PG-14 + contratos de pruebas | result receipt + decision | versioned handoff, execution, artifact digest | Testing posee su autoridad | No inferir Testing PASS de programación DONE | Typed handoff envelope future |

**No existe ningún adaptador con efectos en este paquete.** El núcleo sólo puede devolver cierre sintético local.
