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

## 5. Lo que este borrador NO cubre (CT01 no puede cerrarse con esto)
- Código fuente de las otras 5 Edge de perfiles y del workflow de GitHub (llamadores y firmas de entrada/salida).
- Contratos y schemas JSON de `skills/profile_creator/contracts/*` y SRCR V0_7R1 (campos de entrada/salida).
- Políticas (`v_lf_operation_policy_snapshot`) como superficie con firma.
- Falsificador negativo ejecutado (firma obsoleta o sin propietario → falla y señala consumidor).
- Contrato de aserción de CT01, migración de cierre y recibo del agente independiente.

## 6. Ruta de cierre verificada
La operación `CIERRE_CHECKPOINT_INGENIERIA_LF` está en `OP_CANDIDATE`/`CANDIDATO_READ_ONLY`, con un único vínculo de proveedor y sin activar; el conector de transición está documentado como no instalado. La ruta usada por los cierres previos (p. ej. `lf_pe10_c5_admission_event_close_v1`) es una **migración de cierre por checkpoint vía Merge Train**. CT01 seguirá esa ruta.
