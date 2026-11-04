# PG-04_C6 — Retorno de PG-07 por presupuesto de contexto (2026-11-03)

## Alcance

Se implementó una **arista de reparación candidata** `PG-07_C3 → PG-04_C6` en `tools/pg04_pg07_budget_feedback_candidate_v1.py`. Esta arista pertenece al flujo de control y **no** se agrega al grafo DAG de dependencias entre soluciones de PG-04.

Fuente: `supabase/migrations/20261028160000_lf_programming_pg00_standards_checkpoints_decisions_v2.sql`: PG-04_C6 define «Vuelta desde PG-07 cuando un lote excede el presupuesto de contexto: se reparte de nuevo (arista de reparación, no ciclo)»; PG-07_C3 exige proyección por tarea, sin repo/spec completos, sin truncar material, referencia exacta JIT o retorno a PG-04 y presupuesto según el perfil del modelo, nunca fijo.

El mecanismo transversal existente `CONTEXT_BUDGET_GOVERNANCE` ya define `fn_lf_router_preflight_v1`, ledger `private.lf_context_budget_events_v2` y readback `public.v_lf_context_budget_latest_v2`. Este adaptador **no invoca** esas funciones, no estima tokens, no incluye otro limitador y no modifica su política. El README transversal histórico menciona soft=1500/hard=3000 como límites de su época, **que no deben copiarse como límite PG-07 por solución**: para PG-07 aplica política vigente y perfil del modelo.

## Contrato de entrada candidato

`prepare_pg07_budget_feedback(partition, budget_feedback)` requiere:
- `partition` candidata PG04 con `candidate_sha256` exacto (hash verificado).
- `budget_feedback.schema_version=PG07_CONTEXT_BUDGET_FEEDBACK_CANDIDATE_V1`.
- `source_capability=CONTEXT_BUDGET_GOVERNANCE`.
- `budget_evaluation_ref` y `model_profile_ref` explícitos.
- `partition_sha256` y `solution_id` que correspondan a la solución congelada.
- `context_status=GREEN|YELLOW|RED`, exclusivamente **declarado** por caller, nunca medido en este adaptador.
- `source_mode=CALLER_SUPPLIED_UNVERIFIED` para prohibir que la entrada sintética declare autoridad.
- `material_ref_ids` y `jit_candidate_ref_ids` como conjuntos únicos; los JIT candidatos deben ser un subconjunto de referencias materiales.

## Reglas de salida

| PG-07 reportado | Acción propuesta en PG-04 | Qué NO se afirma |
|---|---|---|
| GREEN | `CONTINUE_CONDITIONALLY_ON_AUTHENTIC_READBACK` | No se afirma PASS de presupuesto |
| YELLOW | `NO_EXTRA_PREFETCH_RETRIEVE_JIT_ONLY` | No se omiten referencias materiales |
| RED | `ASSESS_JIT_OR_REPARTITION` | No se declara reparado ni GREEN |

Para RED, `repair_required=true`, pero el adaptador **no reparte automáticamente** el lote. Debe existir recibo real de PG-07, decisión sobre materialidad y una nueva partición completa evaluada por el productor PG04 y el revisor competente. La nueva partición debe preservar el 100 % de requisitos y aceptación, los átomos y procedencia, y un DAG válido antes de nueva proyección PG07.

Todos los resultados conservan `CANDIDATE_NOT_ADMITTED`, `budget_readback_attested=false`, `budget_engine_invoked=false`, `material_truncation_allowed=false`, `auto_repartition_allowed=false`, `pg07_budget_pass_claim_allowed=false`, `production_authority=false` y `handoff_allowed=false`.

Se preserva en el paquete congelado la solución original, sus átomos, requisitos, aceptaciones y dependencias, para que un proceso gobernado posterior pueda contrastar cualquier reparación.

## Límite y estado

`PG04_C6_REPAIR_EDGE_SOURCE_READY / CURRENT_BUDGET_RECEIPT_NOT_VERIFIED / REPARTITION_NOT_EXECUTED / NO_RUNTIME_AUTHORITY`.

**No se añadieron ni ejecutaron pruebas de C6**, siguiendo la decisión de aplazarlas por ahora. No se cerró ningún checkpoint en Supabase. No se alteró Análisis, PG-07, las funciones de context budget ni `main`.

El siguiente checkpoint de desarrollo de PG-04 es **C7**, aseguramiento independiente de la cobertura. El preflight de C7 ya está preparado en `tools/pg04_independent_review_request_v1.py`; faltan el sujeto real VERIFIED y la revisión gobernada, que no deben reemplazarse con el laboratorio.

## Continuación — repartición controlada de una solución RED

Se añadió tools/pg04_c6_repartition_proposal_v1.py con propose_repartition(partition, budget_edge, original_obligations, split_plan).

Entradas: partición candidata y SHA original, arista de presupuesto RED con digest válido, obligaciones originales y propuesta explícita de al menos dos grupos con su justificación semántica y evidencia de que JIT no resulta suficiente o no aplica. Las referencias aportadas por el llamador NO están autenticadas.

Controles estructurales: todo átomo original se asigna una sola vez y a un único grupo; coinciden la fuente, el scope y las referencias EXISTING/NEW; requisitos y aceptaciones de cada átomo y del conjunto no se pierden; coimplement_with no se separa; las dependencias atómicas de la solución se convierten en dependencias entre los nuevos grupos y se exige un DAG acíclico. Las dependencias externas no resolubles bloquean.

Una solución externa que dependía de la original pasa a depender conservadoramente de todos los hijos. Se registra downstream_rebound_conservatively para que el juez revise si es posible una relación más precisa. Este comportamiento no autoriza duplicar las obligaciones.

Salida: PG04_C6_REPARTITION_PROPOSAL_V1 con proposed_solutions, el hash original y nuevo, cobertura global y next_gate=INDEPENDENT_SEMANTIC_REVIEW_THEN_PG07_CURRENT_REMEASUREMENT. Mantiene semantic_boundary_verified=false, budget_readback_attested=false, pg07_remeasurement_executed=false, independent_judge_executed=false, production_authority=false y handoff_allowed=false.

Límite: la división propuesta NO prueba que el contexto ahora quepa; no se consultó PG-07 ni se ejecutó juez. No se afirmó PASS ni se cerró C6. La semántica y autoridad de las referencias deben validarse fuera de este componente, y un actor autorizado debe aceptar la separación antes de un nuevo intento de PG-07.

Se aplazan las pruebas siguiendo la instrucción del Owner; sin cambios en Análisis, Supabase ni main.
