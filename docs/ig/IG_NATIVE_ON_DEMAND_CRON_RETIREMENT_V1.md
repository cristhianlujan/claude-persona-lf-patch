# Input Governance — transición a ejecución bajo demanda GPT Native (candidato v1)

**Estado:** PROPOSED / NON-PRODUCTION / NO_CUTOVER.
**Fecha de verificación:** 2026-10-26.
**Alcance:** reemplazar exclusivamente el *despacho periódico* de `ig-direct-sql-worker-v1`, reutilizando el motor SQL gobernado. No modificar reglas, familias, controles EKB, Router ACT-0001 ni ejecución de otros perfiles.
**Autoridad:** contrato vivo en `programacion.contratos`; este documento NO sustituye ni revisa su autoridad.

## Objetivo y decisión

La cadencia de 30 segundos fue creada como mecanismo de transporte y continuación, **no** como requisito funcional de Input Governance. El objetivo autorizado es:

`Router/perfil existente -> IG currentness/readback -> (si falta) GPT Native en conversación actual -> Curator SQL -> handoff verificado -> Validator SQL -> evidencias/readback -> consumidor`.

**No usar** Edge / HTTP / RPC REST como orquestador de procesamiento ni API remota de modelo. Las consultas del agente a Supabase siguen necesitando un transporte de datos gobernado y permisos; GPT Native no concede por sí mismo permisos SQL.

La ruta de checkpoints M10.7 `GPT_NATIVE` (`programacion.fn_engineering_test_executor_resolve_v1`) **no constituye** evidencia de que Curator y Validator enteros tengan un nuevo runtime operativo.

## Evidencia observada (read-only, 2026-10-26)

| Fuente | Estado material |
|---|---|
| `cron.job` | id=45, `ig-direct-sql-worker-v1`, cada 30 segundos, activo; invoca `programacion.fn_input_governance_queue_worker_v1()` |
| `programacion.ig_direct_requests_v1` | 8 solicitudes históricas, 8 DONE, 0 QUEUED |
| `cron.job_run_details` (24 h) | 2875 ejecuciones succeeded; ~0.007 s promedio. Succeeded del cron **no equivale** a IG READY. |
| `programacion.fn_input_governance_queue_worker_v1` | toma 1 QUEUED; hasta 10 pasos por tick, límite acumulado 20; continúa con `NEXT_CRON_TICK` tras umbral de ~30 segundos |
| `programacion.fn_input_governance_direct_step_v1` | trabajo incremental; orquesta readback, Curator materialize, receipt de handoff y validación en fragmentos |
| `pg_proc` | `direct_step` = SECURITY DEFINER, owner postgres, ACL explícita `{postgres=X/postgres}`; lector actual **sin EXECUTE** |
| Sesión Supabase de inspección | `supabase_read_only_user`, `statement_timeout=120000` ms; no hay evidencia de ruta GPT Native con permiso de mutación |
| `programacion.fn_input_governance_worker_spec*` | tres funciones citan explícitamente `POSTGRES_SQL_WORKER:ig-direct-sql-worker-v1` |
| `programacion.fn_lf_router_input_governance_resolve_v1` | retorna despachos con referencia al cron cuando falta readiness |
| `public.lf_profile_execution_input_validate_v1` | ante PENDING puede encolar con `fn_input_governance_queue_submit_v1`; depende del cron para progresar |
| Contrato vivo `INPUT_GOVERNANCE_EXECUTION_CONTRACT` | id=42, rev 1.7; conserva `SUPABASE_EDGE_FUNCTION` para curator, validator, runtime_orchestrator; posible divergencia entre contrato e implementación, NO corregir sin análisis de autoridad |

EKB focal consultado:
- `IG-DIRECT-SQL-WORKER-EDGE-REDUCTION-001`: el cron SQL evitó múltiples workers Edge y un `statement_timeout` de una vía REST.
- `IG-SQL-WORKER-BUDGET-OVERRUN-001`: un worker superó 95 segundos (116.615 s); la segmentación limita tiempo entre pasos, no el tiempo de un paso individual.
- `IG-M107-NATIVE-EXECUTOR-ROUTE-CORRECTION-044`: M10.7 habilitó RUN_TEST en GPT Native / Claude Native current context; sin fallback remoto.
- `IG-M107-CP3-TRANSPORT-CPU-TRADEOFF-004`: menor espera de transporte no soluciona tiempo SQL del Validator.
- `DB-GIT-DRIFT-UNGOVERNED-PERSISTENT-OBJECT-001`: cualquier cambio DB persistente exige Git-first.
- `docs/input-governance/ADR_M10_6_RUNTIME_AND_REGISTRY_AUTHORITY_V1.md`: distinguir registro/runtime/contrato; no duplicar autoridad ni promover por inferencia.

## Diseño mínimo candidato (NO IMPLEMENTADO)

1. **Conservar entrada:** Router/Gate 2 y `EJECUCION_PERFIL_LF/input_validate` continúan decidiendo si IG es requerido. Router deriva; nunca ejecuta el procesamiento.
2. **Fast path actual:** `programacion.fn_input_governance_execute` entrega el run COMPLETED CURRENT solo después de los controles existentes de EKB/freshness/full PASS. No se despierta un worker si no hay cambios.
3. **Stale/ausente:** el perfil ya autorizado invoca en la **misma conversación GPT Native** la ejecución por pasos. Cada paso consulta autoridad vigente y persiste resultados usando las funciones gobernadas existentes. **Requisito previo bloqueante:** identificar una superficie de escritura con identidad acotada que pueda ejecutar estos pasos sin otorgar permisos amplios ni exponer la función SECURITY DEFINER; no asumir que el conector read_only sirve.
4. **Curator → Validator:** conservar separación de identidad, handoff VERIFIED, snapshot/hash, Q0-Q8, triggers, política de gaps, receipts, rechazo de false PASS, negative tests. No convertir salida semántica de GPT en autoridad canónica.
5. **Continuación:** persistir `run_id`, estado y receipts; en la siguiente invocación del perfil retomar el mismo run, sin repetir trabajo válido y con currentness revalidada. La interrupción del chat debe quedar como PENDING/BLOCKED verificable, no como READY; **no se promete avance en background**.
6. **Límite:** un procesamiento de 3–4 minutos es compatible con varios pasos en una conversación, pero NO con una única consulta larga si el transporte tiene presupuesto inferior. Medir costo por fragmento y probar timeouts reales antes del cutover.

## Dependencias a intervenir tras resolver el permiso

- `programacion.fn_input_governance_worker_spec`.
- `programacion.fn_input_governance_worker_spec_known_current_v1`.
- `programacion.fn_input_governance_worker_spec_known_no_current_v1`.
- `programacion.fn_lf_router_input_governance_resolve_v1`.
- `public.lf_profile_execution_input_validate_v1`.
- Revisar por alcance el contrato vivo id=42, el resolvedor directo `programacion.fn_lf_profile_input_governance_resolve_v1`, adaptadores/consumidores, OIDC queue submit/poll y registros de activos. Evitar sustituir nombres de transporte por otro hardcode; usar autoridad contractual versionada.
- Mantener cola/worker originales operativos durante pruebas. No eliminar la persistencia histórica ni los receipts.

## Gates de verificación (obligatorios, sin falsos cierres)

| Gate | Prueba / condición de salida | Evidencia esperada | Estado |
|---|---|---|---|
| G0 | Permiso y canal real GPT Native -> escritura acotada -> readback; sin Edge/HTTP como orquestador | Identidad, acción oficial, permisos, ejecución negativa sin autoridad | BLOCKED |
| G1 | Paridad de CURRENT sin recomputar ni disparar trabajo | Run, SHA, EKB, outcome de perfil | NOT_RUN |
| G2 | Una pantalla STALE/ausente con Curator y Validator; comparación fuente y 47 familias | RUN nuevo, identidades separadas, VERIFIED handoff, Q0-Q8, tiempo por fase, readback | NOT_RUN |
| G3 | Cancelación/reanudación, colisión de concurrencia y hash modificado | PENDING/BLOCKED sin READY, resume exacto, fallos negativos | NOT_RUN |
| G4 | Adaptador/perfil/router sin cambio de derivación | Mismo handoff y gates, ninguna reentrada circular | NOT_RUN |
| G5 | Retirar cron solo tras 0 QUEUED y 0 consumidores vivos dependientes; observación y rollback | Git-first migration PR/merge/ledger exacto, DB, logs y readback | NOT_RUN |

**Rollback:** si no hay progresión nativa válida, mantener o restaurar el cron anterior por migración gobernada y verificar que no haya doble procesamiento concurrente. Nunca activar dos orquestadores productores al mismo tiempo.

**No es aprobación de producción.** La migración final exige evidencia G0–G4 y el procedimiento oficial Git-first/Train; este documento es diseño candidato y diagnóstico reproducible, no ejecución.
