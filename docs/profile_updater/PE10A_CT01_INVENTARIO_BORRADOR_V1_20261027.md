# PE10A_CT01 — Inventario de superficies (BORRADOR para revisión independiente)

Fecha: 2026-10-27 · Alcance acordado: **ruta de actualización de perfiles** (ACTUALIZACION_PERFIL_LF) · Exact-head del repo: `e7f50a6ab345d4b40a66d34d46669661fd22c657` (main tras PR #3204).
**Estado: el checkpoint `PE10A_CT01` sigue PENDING.** Este documento es evidencia material de entrada; no es un cierre ni un recibo. El recibo independiente lo debe emitir otro agente.

## Cómo se obtuvo (todo ejecutado, solo lectura)
Consultas a `pg_proc`/`pg_roles`/`aclexplode` en Supabase `mhwmirqcgxxukpctffuv`, `lf_activos`, `lf_operation_step_contracts`, `lf_operation_step_judge_bindings`, `get_edge_function`/`list_edge_functions`, y búsqueda exacta en el repo (sin `.git` ni `supabase/migrations`).

## 1. Superficies SQL (9) — firma exacta en producción
| Función (schema public) | Argumentos | Retorno | Vol. | SECDEF | md5(prosrc) | ACL (EXECUTE) |
|---|---|---|---|---|---|---|
| lf_profile_update_begin_v1 | p_execution_id text, p_target_code text, p_target_repo text, p_target_path text, p_request_sha256 text, p_idempotency_key text, p_actor_execution_id text, p_manifest jsonb | jsonb | volatile | no | deb4d57cbe7d35ad93401056bd1ab071 | postgres, service_role |
| lf_profile_update_effective_route_v1 | p_execution_id text | jsonb | stable | no | da620cf19a9a10d18e0d5d39ff743f2e | postgres, service_role |
| lf_profile_update_evolution_step_guard_v1 | p_execution_id text, p_step_id text, p_payload jsonb | text | stable | no | bd713a5a0cbc93619980f493723f7f6b | postgres, service_role |
| lf_profile_update_post_merge_reconcile_v1 | p_execution_id text, p_merge_sha text, p_entrypoint_sha text, p_manifest_sha text, p_profile_pack_id text, p_pr_number integer, p_actor_execution_id text | jsonb | volatile | no | 8b1f02ec4583e9870437bca2e152187d | postgres, service_role |
| lf_profile_update_result_class_v1 | p_value jsonb | text | immutable | no | 19f4b9cdf0f2e23dad120d01b9c8660e | postgres, service_role |
| lf_profile_update_substantive_block_v1 | p_execution_id text, p_step_id text, p_payload jsonb, p_manifest jsonb | text | stable | no | 06a07b442f19076542ae7fbec9513897 | postgres, service_role |
| lf_profile_update_verified_receipt_v1 | p_subject_type text, p_subject_ref text, p_receipt_id text, p_subject_sha256 text, p_source_head_sha text | boolean | stable | **sí** | 7c163d3308ecba94ad066e6df8446e80 | postgres, service_role |
| lf_router_governed_caller_route_v1 | p_caller jsonb, p_target_code text, p_target_path text | jsonb | volatile | **sí** | 5615b6371d1da49f9dfe8cce186d41bc | postgres, service_role, **supabase_read_only_user** |
| lf_record_profile_operation_step_v1 *(no estaba en la lista inicial; descubierta por cierre de consumidores)* | p_execution_id text, p_step_id text, p_evidence_ref text, p_evidence_payload jsonb, p_actor_execution_id text | jsonb | volatile | no | 03f8c6a1ada0321ced8682afb74d3f0f | postgres, service_role |

Propietario de base de datos de las 9: rol `postgres`.

## 2. Consumidores
**Dentro de la base de datos (búsqueda del nombre en `prosrc`, schemas public y programacion):**
- `lf_record_profile_operation_step_v1` consume: effective_route, evolution_step_guard, substantive_block.
- `lf_profile_update_substantive_block_v1` consume: result_class.
- `lf_profile_update_evolution_step_guard_v1` consume: verified_receipt.
- Sin consumidor SQL: begin, post_merge_reconcile, governed_caller_route.

**Fuera de la base de datos (repo, exact-head `e7f50a6`):**
- begin → `supabase/functions/run-creacion-perfil-lf/index.ts`.
- governed_caller_route → `run-creacion-perfil-lf/index.ts` (línea 257) y `sandbox/lf_contract_gate_test/profile_creator_customer_caller_source_test.py`.
- post_merge_reconcile → `sandbox/lf_contract_gate_test/authority_readback/*` (inventario, adaptadores, proyección SQL).
- Conteo exacto de archivos que nombran cada función (sin `.git`, `supabase/migrations` ni `docs`): effective_route 5, evolution_step_guard 5, result_class 2, substantive_block 2, verified_receipt 8 (todos en `skills/profile_creator/contracts/*` y `skills/profile_creator/evals/*`); lf_record_profile_operation_step_v1: 11 en `skills/profile_creator/`, 1 en `sandbox/` y 3 fuera de esas carpetas (por identificar en el inventario definitivo); governed_caller_route: 1 en `sandbox/` y 1 fuera (el `index.ts` del Edge en `main`).
- Workflow: `.github/workflows/lf-customer-profile-creator-governance-caller.yml`.

## 3. Propietario canónico
- **Edge (6)**: registradas en `lf_activos`, propietario `LF_GOVERNANCE`, `runtime_estado=CANDIDATE_READ_ONLY`: run-creacion-perfil-lf, run-formalizacion-perfil-lf, run-github-write-perfil-lf, run-github-readback-perfil-lf, lf-profiles-governance-caller-v1, lf-profile-creator-governance-caller-v1.
- **SQL (9): ninguna tiene registro en `lf_activos`.**
- Vinculación por contrato de pasos: **solo** `lf_profile_update_evolution_step_guard_v1` figura como `resolver_ref` (pasos 35 `method_selection` y 37 `evolution_decision`, ambos `CANDIDATE` e inactivos, sin juez). El resto de pasos usa `GPT_RUNTIME_WITH_SUPABASE_CONTEXT` o `public.v_lf_fuente_operativa.ACT-0001 + public.lf_operation_registry` (router).

## 4. Hallazgos
1. **Deriva Edge desplegado vs GitHub main, con la misma etiqueta de versión.** Ambos declaran `ENDPOINT_VERSION = "v22-profile-update-server-trust-context"`. `main` (blob `45e2302d164740fcdf60b4c894feba9922a4b664`, sha256 `76a32c20…34ab`) llama a `lf_router_governed_caller_route_v1` y contiene `required_profile_steps.ts`; el Edge desplegado (Supabase v35, `ezbr_sha256` `1aceef7b…6224`, archivos `index.ts` y `deno.json`) no llama a esa función ni tiene ese archivo. La etiqueta de versión no detecta esta deriva.
2. **9 de 9 superficies SQL sin propietario canónico registrado**; solo 1 con vínculo operativo, y está inactivo.
3. **`lf_router_governed_caller_route_v1`**: SECURITY DEFINER, volátil, con EXECUTE concedido a `supabase_read_only_user`. *No verificado* si su cuerpo escribe; queda como punto a revisar en `PE10A_CT05`, no como hallazgo cerrado.
4. **Sin consumidor SQL ni en el Edge desplegado** para `lf_router_governed_caller_route_v1` (solo en `main` y en un test).
5. La lista inicial de superficies estaba incompleta: faltaba `lf_record_profile_operation_step_v1`, que consume 3 de las 8.

## 5. Ampliación (v2 del borrador, misma fecha)

### 5.1 Consumidores que faltaban identificar
- `lf_record_profile_operation_step_v1` fuera de `skills/` y `sandbox/`: `supabase/functions/run-creacion-perfil-lf/{index.ts (línea 386), required_profile_steps.ts, required_profile_steps.test.mjs}`. Además aparece en 12 migraciones históricas (definiciones y correcciones sucesivas).
- `lf_router_governed_caller_route_v1` fuera de `sandbox/`: `run-creacion-perfil-lf/index.ts` en `main` (línea 257) y la migración que la creó (`20261023163624_lf_router_governed_callers_v1.sql`). El Edge desplegado no la llama (ver hallazgo 1).
- Contratos y evals de `skills/profile_creator/` que nombran cada función: effective_route → 5 archivos, evolution_step_guard → 5, result_class → 2, substantive_block → 2, verified_receipt → 8, record_step → 11. **begin, post_merge_reconcile y governed_caller_route no aparecen en ningún contrato de `skills/profile_creator/`.**

### 5.2 Edge de perfiles (código desplegado leído, solo lectura)
| Edge | Versión | verify_jwt | Qué llama / acepta |
|---|---|---|---|
| lf-profile-creator-governance-caller-v1 | v17 | no (OIDC propio) | OIDC GitHub exacto (repo, workflow, ref). Acciones: `profile_creator_init_v1`, `profile_update_init_v1`, `profile_operation_next_step_v1`, record_step y record_batch. Delega **todo** a `run-creacion-perfil-lf`; no llama RPC SQL directamente. Resuelve la revisión vigente de `main` por la API pública de GitHub y fija el SHA. |
| lf-profiles-governance-caller-v1 | v25 | no (OIDC propio o ticket de runtime) | Acciones de input-governance y CP2; para perfiles solo `profile_creator_init_v1` / `profile_creator_record_step_v1`, que delega al slug configurado. Llama a RPC `lf_profile_input_governance_runtime_ticket_consume_v1`, `lf_input_gov_recuration_allowlist_v1`, `fn_input_governance_queue_*_oidc_v1`, `fn_ig_m105_cp2_*`. No toca las 9 superficies SQL. |
| run-github-write-perfil-lf | v20 | sí + service role | Escribe un pack en una rama `lf/**` (no `main`), solo bajo `profiles/` y `sandbox/lf_contract_gate_test/receipts/`; exige `pre_write_gate_passed`. Sin RPC SQL. |
| run-github-readback-perfil-lf | v20 | sí + service role | Relee archivos y compara SHA. Sin RPC SQL. |
| run-formalizacion-perfil-lf | v17 | sí + service role | Solo DRY_RUN; `database_accessed=false`. Sin RPC SQL. |
| run-creacion-perfil-lf | v35 | no relevado en esta pasada | Único Edge que llama a las superficies SQL (`lf_profile_update_begin_v1`, `lf_record_profile_operation_step_v1`, `lf_router_resolve_v1`). |

Consecuencia para CT01: de las 6 Edge, **solo `run-creacion-perfil-lf` es consumidor de las superficies SQL**. Las otras 5 son transporte, escritura/relectura o dry-run, y no necesitan firma SQL en el inventario.

### 5.3 Workflow
`.github/workflows/lf-customer-profile-creator-governance-caller.yml`: dispara por `push` a `lf/profiles/profile-creator-customer-caller-20260902` o `workflow_dispatch` (acciones `source_canary_only`, `profile_update_init`, `profile_update_record_batch`). Es la identidad OIDC que acepta `lf-profile-creator-governance-caller-v1` (`ref` y `workflow_ref` exactos; para actualización solo `refs/heads/main` + `workflow_dispatch`). Un cambio de nombre del workflow o de la rama rompe el caller sin que ninguna prueba SQL lo detecte.

### 5.4 Políticas como superficie
`public.v_lf_operation_policy_snapshot`, operación `ACTUALIZACION_PERFIL_LF` (5 políticas requeridas), `policy_sha` observados:
- PASS_POLICY `POL-PROFILE-UPDATE-PASS` v1.1 → `f96451a2…b942`
- GOVERNANCE_LIFECYCLE `POL-LF-OPERATION-LIFECYCLE` v1.1-operational-closure → `2adb62f8…3c00`
- POLICY_CONSUMPTION `POL-LF-POLICY-CONSUMPTION` v1.3-assurance-cutover → `a6bd42d3…aa22f`
- SOURCE_RESOLUTION `POL-LF-SOURCE-RESOLUTION` v1.4-… → `5fab0c7f…ae46`
- STATE_MODEL `POL-LF-STATE-MODEL` v2.0-canonical-lifecycle → `f0d039a7…b495b3`
`EJECUCION_PERFIL_LF` comparte 4 de ellas (mismos SHA) y añade `POL-LF-ACTIVATION-ROUTING` v1.0.

### 5.5 Falsificador ejecutado (solo lectura, producción)
Se congeló la tabla de la sección 1 (firma, md5 del cuerpo, SECURITY DEFINER) y se comparó con `pg_proc`:

| Caso | Resultado | Consumidor señalado |
|---|---|---|
| POSITIVE (9 funciones) | 9/9 PASS | — |
| NEG_MD5_OBSOLETE (`result_class` con md5 falso) | FAIL_BODY_DRIFT | `lf_profile_update_substantive_block_v1` |
| NEG_ARGS_OBSOLETE (`effective_route` con un argumento extra) | FAIL_SIGNATURE_DRIFT | `lf_record_profile_operation_step_v1` |
| NEG_OWNERLESS_NEW (`lf_profile_update_ghost_v1`) | FAIL_MISSING_OR_OWNERLESS | ninguno |

Límites: la columna de consumidores es una búsqueda de texto del nombre en `prosrc`, por lo que **no distingue una llamada de un comentario o mensaje**; en dos filas el resultado es bidireccional (record_step menciona a effective_route y effective_route menciona a record_step), lo que prueba la mención, no el sentido de la llamada. La comparación no cubre ACL, triggers ni dependencias fuera de `public`. El falsificador corre sobre una copia congelada hecha por mí; una versión que viva en el repo y falle en CI sigue pendiente.

### 5.6 Contratos de `skills/profile_creator/contracts/` (medido)
- 16 JSON: los 16 parsean. Se inventariaron sus claves de primer nivel (p. ej. `update_server_trust_context_contract.json`: contract_code, operation_code, step_id, status, purpose, architecture, trust_boundary, server_context, decision_matrix, activation_gate). `resolver_dispatch_contract.json` es el único con `schema_version` y 1 resolver declarado.
- 7 SQL candidatos: 5 definen exactamente 1 función; `profile_update_v02_governed_stage_rollback_candidate_v1.sql` y `update_step60_dedicated_judge_materialization_v1.sql` definen 0.
- Contratos que nombran superficies SQL: ver 5.1. Los candidatos `*_candidate_v1.sql` son fuente candidata, no estado desplegado; el estado vigente es el de la sección 1.
- No se encontró en el repo ningún archivo con `V0_7R1` en su ruta (búsqueda por nombre, profundidad 4).
- Limite: se inventariaron claves, no se validó el contenido de cada campo contra producción.

### 5.7 Python y schemas (medido; pedidos por la prueba positiva de CT01)
- **Python que nombra las superficies (11 archivos):** `sandbox/lf_contract_gate_test/authority_readback/authority_readback_adapters_v1.py`, `sandbox/lf_contract_gate_test/profile_creator_customer_caller_source_test.py` y 9 en `skills/profile_creator/evals/` (batch_resume_contract, profile_operation_blocked_evidence_contract, profile_operation_common_recorder_contract, profile_update_helpers_rollback_probe_v1, test_profile_update_output_receipt_reader_candidate_v1, test_profile_update_recorder_route_candidate_v1, update_recorder_readiness_contract, update_server_trust_context_contract). El generador del falsificador (`gen_falsifier_sql.py`) también los nombra y es parte de este trabajo.
- **Schemas (2):** `missing_input.schema.json` (requeridos: status, missing_inputs, blocking_codes, next_gate) y `output.schema.json` (requeridos: status, profile_pack_id, source_authority, deliverable_created, files_created, evidence_map, blocking_codes, next_gate). Ninguno describe la entrada/salida de las funciones SQL; describen la salida del creador de perfiles.
- **Brecha para CT01:** el plan pide "firma entrada/salida" por superficie. Las funciones SQL la tienen (sección 1). Para las Edge solo se relevaron las acciones aceptadas, no un schema formal de respuesta, porque **no existe uno en el repo**. Esto debe decidirse (documentar o declararlo fuera de alcance) antes de cerrar CT01.
- **Hallazgo de CT01 en el plan:** el checkpoint no tiene `assertion_contract` ni validador atado (`validator_contract_status = EXACT_EXISTING_VALIDATOR_TO_BE_BOUND_PER_CHECKPOINT`). Hay que definir esa condición de cierre antes de la migración de cierre.

### 5.8 Ronda 1 de revisión independiente (GPT, 2026-10-27) — resultado FAIL, aceptado tras verificación propia
Revisor: sesión de ChatGPT con conectores de solo lectura a GitHub y Supabase (no es el productor). Veredicto: **FAIL** en P5 (superficies faltantes). P1, P3 y P4 PASS; P2 NO_VERIFICADO (no ejecutó el script Python del repo; replicó la comparación en SQL y detectó una mutación propia `secdef`).
Omisiones señaladas y **comprobadas por el productor en producción** (solo lectura):
| Superficie | Firma / md5 / SECDEF | Hallazgo |
|---|---|---|
| `lf_router_resolve_v1` | 5 args text · `4fd692a2…54a24` · no · STABLE | La llama `run-creacion-perfil-lf` y 19 funciones SQL. Al ser STABLE no puede escribir; el texto "DML" de su cuerpo es falso positivo. |
| `lf_router_semantic_resume_route_v1` | `p_request jsonb, p_result jsonb` · `140b1e04…cb2038d80b3bd03005cb3` · **sí** · volátil | La llama `lf_router_governed_caller_route_v1`. Sin DML en el texto. EXECUTE: postgres, service_role, supabase_read_only_user. |
| `lf_record_creacion_perfil_step_v1` | 5 args · `f7d1ad06…ae0ad` · no · volátil | La llama `run-creacion-perfil-lf` (rama de creación). **EXECUTE concedido a `anon` y `authenticated`.** No se verificó si es explotable. |
Efecto en el inventario: **9 → 12 superficies SQL** (`frozen_inventory_v1.json` v2). Falsificador sobre las 12: 12/12 PASS.
Sobre `lf_router_governed_caller_route_v1` (pregunta de CT05): la cadena governed_caller_route → semantic_resume_route → resolve no muestra DML en el texto y la hoja es STABLE; **no se demostró** que no haya efectos indirectos en toda la cadena.
Limitación del revisor: la sección `independence` declara evidencia técnica obtenida directamente por conectores y, según la parte visible de su respuesta, **sin atestación del proveedor**. No sirve todavía como recibo de cierre.

### 5.9 Decisión de alcance del dueño (2026-10-27, 17:52 Lima)
Texto del dueño: las funciones del router y su encadenamiento se ven **al final**, en la integración; primero se obtiene bien el funcionamiento propio del updater.
Aplicación en `frozen_inventory_v1.json` (v3), campo `scope` por superficie:
| Alcance | Funciones | n |
|---|---|---|
| `UPDATER` (cierra CT01) | begin, effective_route, evolution_step_guard, post_merge_reconcile, result_class, substantive_block, verified_receipt, lf_record_profile_operation_step_v1 | 8 |
| `DEFERRED_ROUTER` (se ve en la integración, **no se pierde**) | lf_router_governed_caller_route_v1, lf_router_resolve_v1, lf_router_semantic_resume_route_v1 | 3 |
| `OUT_OF_SCOPE_CREATION` (ruta de creación, no de actualización) | lf_record_creacion_perfil_step_v1 | 1 |
Falsificador con `scope` (probado en producción): UPDATER 8 PASS · DEFERRED_ROUTER 3 PASS · OUT_OF_SCOPE_CREATION 1 PASS · 3 mutaciones negativas detectadas. Las 12 siguen vigiladas contra deriva; solo las 8 de alcance UPDATER cuentan para cerrar CT01.
Pendientes que esta decisión **no resuelve** y deben quedar rastreados fuera de CT01: (1) el chequeo de escrituras indirectas de la cadena del router (PE10A_CT05 u otro checkpoint de integración); (2) el permiso EXECUTE de `anon`/`authenticated` sobre `lf_record_creacion_perfil_step_v1` (ruta de creación; no verificado si es explotable).
Nota de coherencia: la especificación de CT01 en el plan dice "todas las superficies tocadas". El alcance se acota aquí por decisión del dueño; el plan no se modificó. El cierre de CT01 debe citar esta decisión.

## 6. Lo que sigue sin cubrirse (CT01 no puede cerrarse con esto)
- Contenido campo a campo de los contratos (solo claves de primer nivel) y SRCR V0_7R1 (no localizado por nombre).
- Falsificador en CI: existe en `docs/profile_updater/pe10a_ct01_falsifier/` (probado a mano contra producción), pero no corre solo.
- Revisar si el cuerpo de `lf_router_governed_caller_route_v1` escribe (CT05).
- Contrato de aserción de CT01, migración de cierre y recibo del agente independiente.

## 7. Ruta de cierre verificada
La operación `CIERRE_CHECKPOINT_INGENIERIA_LF` está en `OP_CANDIDATE`/`CANDIDATO_READ_ONLY`, con un único vínculo de proveedor y sin activar; el conector de transición está documentado como no instalado. La ruta usada por los cierres previos (p. ej. `lf_pe10_c5_admission_event_close_v1`) es una **migración de cierre por checkpoint vía Merge Train**. CT01 seguirá esa ruta.

### 5.10 Enumeración exhaustiva de archivos de la ruta de actualización (ronda 2 → corrección)
Origen: la ronda 2 (GPT) dio FAIL conservador: P1, P2, P4 PASS; P5 NO_VERIFICADO porque no podía probar exhaustividad de contratos/workflows. Comprobación propia: el inventario nombraba solo 2 de los 15 contratos propios del updater y no listaba los validadores ni la Edge `lf-profile-creator-governance-caller-v1` (acción `profile_update_init_v1`) ni el workflow `lf-customer-profile-creator-governance-caller.yml` (acciones `profile_update_init` y `profile_update_record_batch`) como superficies del updater. Los 5 "transporte/OIDC" de 5.2 incluían entonces una Edge que sí inicia actualizaciones: se corrige aquí.
Método reproducible: `pe10a_ct01_falsifier/enumerate_updater_files.sh` (git ls-files en `.github/workflows`, `supabase/functions`, `skills/profile_creator/{contracts,validators}`, `docs/{reconcile,programming-agent,operations}` + grep del patrón `lf_profile_update_|lf_record_profile_operation_step_v1|ACTUALIZACION_PERFIL_LF|profile_update_`). Resultado congelado en `frozen_updater_files_v1.json` (path + blob sha1 + categoría; 43 archivos). La categoría la asigna el productor y puede impugnarse.

| Categoría | n | Archivos |
|---|---|---|
| `UPDATER_EDGE` | 4 | `supabase/functions/lf-profile-creator-governance-caller-v1/index.ts`, `supabase/functions/run-creacion-perfil-lf/index.ts`, `supabase/functions/run-creacion-perfil-lf/required_profile_steps.test.mjs`, `supabase/functions/run-creacion-perfil-lf/required_profile_steps.ts` |
| `UPDATER_WORKFLOW` | 1 | `.github/workflows/lf-customer-profile-creator-governance-caller.yml` |
| `UPDATER_CONTRACT` | 15 | `profile_creator/contracts/profile_evolution_phase_separation_v1.json`, `profile_creator/contracts/profile_operation_blocked_evidence_v1.json`, `profile_creator/contracts/profile_operation_common_recorder_v1.sql`, `profile_creator/contracts/profile_update_effective_route_reader_candidate_v1.sql`, `profile_creator/contracts/profile_update_evolution_step_guard_candidate_v1.sql`, `profile_creator/contracts/profile_update_evolved_routing_candidate_v1.json`, `profile_creator/contracts/profile_update_recorder_conditional_route_candidate_v1.sql`, `profile_creator/contracts/profile_update_v02_governed_stage_rollback_candidate_v1.sql`, `profile_creator/contracts/profile_update_verified_receipt_reader_candidate_v1.sql`, `profile_creator/contracts/update_judge_semantics_contract.json`, `profile_creator/contracts/update_judge_semantics_source_v1.json`, `profile_creator/contracts/update_revision_continuity_contract.json`, `profile_creator/contracts/update_server_trust_context_contract.json`, `profile_creator/contracts/update_step60_dedicated_judge_materialization_v1.sql`, `profile_creator/contracts/update_step60_judge_rebaseline_v1.json` |
| `UPDATER_VALIDATOR` | 5 | `profile_creator/validators/execute_profile_evolution_v02.py`, `profile_creator/validators/plan_profile_evolution.py`, `profile_creator/validators/plan_s26_profile_update.py`, `profile_creator/validators/profile_evolution_oidc_recorder_v02.py`, `profile_creator/validators/profile_updater_same_chat_v02.py` |
| `RELATED_CONTRACT_MENTIONS_UPDATE` | 8 | `profile_creator/contracts/dependency_consumer_measurement_v1.md`, `profile_creator/contracts/existing_artifact_remediation_contract.json`, `profile_creator/contracts/gpt_native_in_chat_capture_contract_v1.json`, `profile_creator/contracts/profile_expert_asis_tobe_gap_contract_v1.json`, `profile_creator/contracts/resolver_dispatch_contract.json`, `profile_creator/contracts/s26_learning_preflight_v1.json`, `profile_creator/contracts/s26_profile_baseline_v1.json`, `profile_creator/contracts/targeted_evidence_drilldown_v1.md` |
| `RELATED_VALIDATOR_MENTIONS_UPDATE` | 5 | `profile_creator/validators/evaluate_s26_learning_preflight.py`, `profile_creator/validators/evaluate_s26_profile_baseline.py`, `profile_creator/validators/measure_dependencies_v1.py`, `profile_creator/validators/profile_output_shape_preflight_v1.py`, `profile_creator/validators/run_bound_profile_output_validator_v1.py` |
| `DEFERRED_ROUTER_DOC` | 5 | `docs/operations/PROTOCOLO_CONSUMO_COMPACTO_ROUTER_LF.md`, `docs/programming-agent/LF_ROUTER_CHANNEL_POLICY_CANDIDATE_V1.md`, `docs/programming-agent/LF_ROUTER_FLOW_V1.md`, `docs/reconcile/PRE_BASELINE_INVENTORY_20261019.json`, `docs/reconcile/RECONCILE_BATCH_2.md` |

Límites: es búsqueda textual del patrón (no demuestra comportamiento); un archivo del updater que no nombre ninguno de los 4 patrones no aparece. Los contratos `UPDATER_CONTRACT` se ven por existencia y claves, no se validó su contenido campo a campo. Las Edge de `lf-profiles-governance-caller-v1` (Input Governance/CP2) no nombran el patrón y se clasifican `OTRO`; su lista completa de RPC dinámicos no está demostrada (declarado por el revisor de la ronda 2).
