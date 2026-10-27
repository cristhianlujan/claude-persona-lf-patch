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

## 6. Lo que sigue sin cubrirse (CT01 no puede cerrarse con esto)
- **Schemas JSON de `skills/profile_creator/contracts/*` y SRCR V0_7R1: identificados por nombre, no leídos campo a campo.** No se inventarió entrada/salida de contratos.
- Falsificador reproducible en el repo (hoy es una consulta manual).
- Revisar si el cuerpo de `lf_router_governed_caller_route_v1` escribe (CT05).
- Contrato de aserción de CT01, migración de cierre y recibo del agente independiente.

## 7. Ruta de cierre verificada
La operación `CIERRE_CHECKPOINT_INGENIERIA_LF` está en `OP_CANDIDATE`/`CANDIDATO_READ_ONLY`, con un único vínculo de proveedor y sin activar; el conector de transición está documentado como no instalado. La ruta usada por los cierres previos (p. ej. `lf_pe10_c5_admission_event_close_v1`) es una **migración de cierre por checkpoint vía Merge Train**. CT01 seguirá esa ruta.
