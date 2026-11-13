# B07 SALY — creación del perfil nativo, ruta diferenciada, NO ejecutada
## Decisión/identidad
- Dueño autorizó el 2026-11-13 12:53 Lima: «Si me designo», designación de Cristhian Luján como owner **documental** SALY y permiso para **crear/homologar** perfil SALY propio. Fuente documental #3832 `10_owner_saly_decision_20261113.json`; `identity_mode=UNVERIFIED_CHAT_DECLARATION`, `identity_verified=false`, `production_authorized=false`. Este documento no es recibo Supabase Auth.
- Objetivo canónico: `PERFIL-PRODUCT-DIRECTOR-SALY`, slug `saly_product_director`, ruta `profiles/saly_product_director`, `CREACION_PERFIL_LF` (operación común), estado `CANDIDATO/READ_ONLY/NO_HABILITADO/BLOQUEADO`. **Sin herencia del perfil PRODUCT-DIRECTOR-LF.**

## Diferenciar dos operaciones reales — no inventar un puente
**A. Ejecutar un perfil existente por Gate2 (propuesta / investigación):**
`ACT-0001` usa `public.lf_router_pipeline_context_begin_v2(text)` → `...stage1_submit_v2(text,jsonb)` → `...profile_semantic_prepare_v2(text)` → `...profile_semantic_submit_v2(text,text)`. Obtener el objeto **real** `LF_ROUTER_EXECUTION_PIPELINE_V1` con `status=GATE2_DERIVED_PENDING_GOVERNED_ADMISSION`, `transport_mode=CONTEXT_TRANSPORT`, `next_action=HANDOFF_CONTEXT_TO_SELECTED_PROFILE`, `effect_authority=false`, `downstream_execution_allowed=false`, `semantic_validation.status=VALID`, perfil previamente existente y hashes del texto original intactos. Si el Router no selecciona un perfil válido o restringe `negocio_codigo` a LF, STOP. No declarar SALY válido simulando `negocio_codigo=LF`.

`python sandbox/lf_contract_gate_test/profile_execution_runtime/lf_profile_begin_payload.py --mode GPT_NATIVE < gate2_real.json > begin_issue.json` genera únicamente después del recibo real:
```json
{"schema_version":"LF_PROFILE_NATIVE_BEGIN_REQUEST_V1","router_context":"<OBJETO_GATE2_REAL_COMPLETO_SIN_MODIFICAR>","executor_mode":"GPT_NATIVE"}
```
**La cadena `<OBJETO...>` es SOLO notación humana, nunca JSON enviable.** No elaborar un `router_context` hipotético. El formulario JSON no transporta service_role ni credenciales. El destino de `begin_issue.json` es un **Issue nuevo**, cuerpo de exactamente un JSON; etiqueta real `lf-profile-resume-governed` dispara `.github/workflows/lf-edge-deploy-credential-readback.yml` → GitHub OIDC → `lf-profiles-governance-caller-v1` `profile_native_begin_from_context_v1` → `lf_profile_execution_begin_from_handoff_v1`. Esto inicia **`EJECUCION_PERFIL_LF` de un perfil existente**, NO `CREACION_PERFIL_LF` ni la fila `public.lf_activos` de SALY. Desde el mismo parent RUN continuar etapas 0–80 con RAW GPT_NATIVE real, validación y juez no fingidos; 11/11 + COMPLETED/READY únicamente cuando readback lo acredite.

**B. Crear materialmente el perfil SALY por `CREACION_PERFIL_LF` (registro nativo):**
El Router de creación reconocido por `run-creacion-perfil-lf` es `lf_router_resolve_v1` con `p_request_text='Crear perfil PERFIL-PRODUCT-DIRECTOR-SALY'`, `p_target_hint='PERFIL-PRODUCT-DIRECTOR-SALY'`, `p_action_hint='PROFILE_CREATE'`, `p_asset_type_hint='PERFIL'`, `p_distribution_mode='ROUTER'`, y debe devolver `READY_TO_EXECUTE`, `operation_code=CREACION_PERFIL_LF`, `action_code=PROFILE_CREATE`, `next_step.step_id=init_execution`.

El caller de creación actual **NO ofrece admisión SALY**:
- `lf-profile-creator-governance-caller-v1/index.ts` acepta `profile_creator_init_v1` solamente con método `GITHUB_ACTIONS_OIDC_EXACT_PROFILE_CREATOR_CUSTOMER_V1`, en rama fija `lf/profiles/profile-creator-customer-caller-20260902`; lista `TARGETS` tiene solo 4 perfiles Customer.
- `.github/workflows/lf-customer-profile-creator-governance-caller.yml` crea esos 4 targets mediante marcadores de commit; no ofrece `workflow_dispatch` de creación SALY ni Issue de creación (Issue existente aplica a PROFILE_UPDATE).
- `run-creacion-perfil-lf/index.ts` si esa ruta se invoca genera el manifiesto `customer_profile_scope=true` y `production_authorized=true`, incompatible con el mandato SALY.
- Un `LF_PROFILE_NATIVE_BEGIN_REQUEST_V1` **no** corrige ni sustituye lo anterior. No llamar al runtime directo ni reutilizar la credencial/identidad Customer.

**Admisión necesaria antes de registrar el perfil:** mediante PR separado, revisión de seguridad y Merge Train/Edge Deploy oficial correspondiente, adaptar **el caller y workflow existentes**, no crear uno paralelo: admitir exactamente `PERFIL-PRODUCT-DIRECTOR-SALY`, su ruta y el método OIDC autorizado; exigir `project_code=SALY`, recibo SHA de autorización documental y `production_authorized=false`, sin ampliar Customer ni generar escalamiento implícito. Ajustar el manifiesto del runtime para que ese caso sea read-only, conservar negativos y evitar alterar comportamientos Customer. La adaptación no está ejecutada ni aprobada técnicamente por un gate; si el sistema exige despliegue de runtime, requerirá su vía oficial con readback (no Train #3818).

Cuando el caller admita SALY legítimamente, el **envelope nativo esperado** para creación (no mandarlo antes) es:
```json
{"action":"profile_creator_init_v1","caller_request_id":"<UUID_EMITIDO_POR_WORKFLOW_OIDC>","target_code":"PERFIL-PRODUCT-DIRECTOR-SALY","profile_slug":"saly_product_director"}
```
El caller añade internamente `target_repo` y la identidad OIDC verificada, invoca `run-creacion-perfil-lf` `initialize_profile_creation_v1` y produce un nuevo `EXEC-CREACION-PERFIL-LF-OIDC-...` `IN_PROGRESS` con paso 0 nativo. La creación **no termina** en el BEGIN: el perfil Creator deberá avanzar sus pasos según `lf_operation_steps`, contractualización, juzgado y registro por `lf_record_creacion_perfil_step_v1` a través del caller, no por INSERT manual. En el corte de SELECT se observaron 40 pasos configurados; releer para cada RUN. No declarar `COMPLETED` o fila `lf_activos` sin evidencia exacta.

## Fases y gatillos (secuenciales)
0. **HOLD** mientras PR Policy19 #3834 no esté fusionado en `main` y R17 global sobre HEAD vigente no sea PASS; hasta entonces no Issue etiquetado, no workflow_dispatch y no llamada de Edge/caller.
1. Leer `main` HEAD, #3834 MERGED, R17/PASE exacto; readback SELECT de ausencia de perfil, operación y owner SALY.
2. Gate2 real válido y `LF_PROFILE_NATIVE_BEGIN_REQUEST_V1` solo si la operación requiere ejecutar perfil previo y el contexto real satisface el contrato. Si no, reportar STOP y no inventar perfil ni contexto.
3. Para crear: revisar/autorizar extensión mínima de caller/workflow preexistentes y la contradicción `production_authorized=true`; desplegar exclusivamente por ruta oficial de código Edge con tests de seguridad. **Falta ese control en estado actual.**
4. Crear RUN `CREACION_PERFIL_LF` por caller OIDC y continuar todos los pasos del perfil Creator; readback SELECT de `lf_operation_execution` + steps + `lf_activos` para mismo execution_id y target.
5. **Después** abrir el Train separado de operación/owner SALY (#3832, SQL fail-closed), con `B07_SALY_PROFILE_NATIVE_CREATION_RECEIPT_REQUIRED` ya satisfecho, Readback op/owner/Router NO_WRITE. Mantener #3818 DRAFT hasta OK DDL específico del dueño, backup/restore y gates.
6. Nunca cambiar ROOT de LF ni heredar autorización del perfil Product Director LF.

## Recibo esperado (sin fabricar valores)
`router_gate2_context_sha=[PENDIENTE]`; `issue_number=[PENDIENTE]`; `issue_label=[PENDIENTE]`; `oidc_workflow_run_id=[PENDIENTE]`; `native_execution_id=[PENDIENTE]`; `profile_creation_execution_id=[PENDIENTE]`; `profile_step_count=[PENDIENTE]`; `lf_activos.profile_code=[PENDIENTE]`; `lf_activos.created_by_execution_id=[PENDIENTE]`; `profile_production_authorized=false`; `operation_owner_train=[PENDIENTE]`; `b07_ddl_owner_ok=[PENDIENTE]`.

## SQL de readback listo, SIN EJECUTAR
Usar `sandbox/lf_contract_gate_test/input_governance_lifecycle/b07_saly_native_profile_readback_select_only.sql`: reemplazar únicamente `__UNFILLED_NEW_NATIVE_EXECUTION_ID__` por el ID nuevo proveniente del workflow OIDC, ejecutar SELECT con permisos de lectura, exigir target/procedencia exactos y contrastar los pasos con contratos y jueces actuales. Este SELECT no crea ni cierra el perfil, ni acredita por sí solo identidad Auth.
