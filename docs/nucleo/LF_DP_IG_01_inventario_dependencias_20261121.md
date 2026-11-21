# DP-IG-01 — Inventariar dependencias de perfiles e IG

Fecha: 2026-11-21. Diagnóstico exclusivamente documental y reproducible, sin cambios de comportamiento.
Estado: EVIDENCIA DE DIAGNÓSTICO; cierre condicionado al Merge Train y readback de main.
Fuente Git anclada: 1b3b8385d368d37ef21220a218a05d2feaf7b1a7. Supabase LF_SUPABASE_SANDBOX, proyecto mhwmirqcgxxukpctffuv, PostgreSQL 17.6, rol supabase_read_only_user. Ningún escritor invocado.

## Alcance y límites

Inventario de políticas, catálogo y descriptores, adapters, funciones, contratos, transportes, y consumos observables. No se modifican perfiles, Router, IG, T_REMED, skills, lectores, escritores, permisos, reglas, versiones, tablas legadas, ni bindings. No se ejecuta perfil ni IG ni se fabrican tickets. No se anticipa D8: el inventario no decide arquitectura, reemplazo de dependencia, cutover o eliminación. F6 no autorizada. Ninguna regla se publica; no se crea V4 checkout. Se distingue disponibilidad, referencia estática e invocación observada de ejecución certificada.

Fuentes originales: plan LF_plan_acople_desacople_nucleo_reglas.md y deltas SALY_AM, F0_vocab36_enums, F4_y_bindings, todos leídos; el archivo ACTUALIZADO_20261121 no pudo recuperarse íntegramente. Este anexo reconstruye únicamente el criterio DP-IG-01 con su definición recuperada, sin sustituir el documento ni redefinir DP-IG-02..05.

## 1. Perfiles y skill

Consulta del catálogo real:
```sql
SELECT p.profile_code,p.selection_mode,p.enabled,p.owner_decision_required,
 p.required_operation,p.allowed_effects,c.status,c.effect,d.descriptor_status,
 r.descriptor_status AS profile_status
FROM public.lf_skill_selector_policy_v1 p
JOIN public.lf_skill_catalog_v1 c USING(skill_code)
JOIN public.lf_skill_selection_registry_v1 d USING(skill_code)
LEFT JOIN public.lf_profile_selection_registry_v1 r USING(profile_code)
WHERE p.skill_code='INPUT_GOVERNANCE_CONTEXT_PACK' ORDER BY p.profile_code;
SELECT descriptor_status,count(*) FROM public.lf_profile_selection_registry_v1 GROUP BY 1;
```

10/10 perfiles del registro CURRENT tienen SEMANTIC_OPTIONAL, enabled=true, owner_decision_required=false, required_operation=EJECUCION_PERFIL_LF, allowed_effects={READ_ONLY}, skill READY/READ_ONLY y descriptor CURRENT:
- ACT-0051
- PERFIL-CUSTOMER-FINANCIAL-UX-DECISIONING
- PERFIL-CX-TRUST-EXPERIENCE-ARCHITECT-LF-20260531
- PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF
- PERFIL-GAMIFICATION-SYSTEM-ARCHITECT
- PERFIL-PRODUCT-DIRECTOR-LF
- PERFIL-QUALITY-PACK
- PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF
- PERFIL-UI-ARCHITECT
- PERFIL-UX-PRODUCT-EXPERIENCE-ARCHITECT-LF-20260531

Cuatro filas del adapter ADAPTER-LF-SHELL-PROFILE-20260827: ACT-0051, GAMIFICATION-SYSTEM-ARCHITECT, PRODUCT-DIRECTOR-LF, UI-ARCHITECT (códigos íntegros arriba). En las cuatro: READ_ONLY, discoverable=true, runtime_enabled=true, receipt_required=true como metadata. La metadata no prueba que Router ejecute IG, ni que estos sean cuatro perfiles adicionales.
```sql
SELECT adapter_code,target_asset_code,adapter_operational_status,
 adapter_metadata->>'router_discoverable' AS discoverable,
 adapter_metadata->>'runtime_enabled' AS runtime_enabled,
 adapter_metadata->>'input_governance_receipt_required' AS receipt_required
FROM public.v_lf_router_adapter_bindings
WHERE adapter_metadata ? 'input_governance_receipt_required' ORDER BY 1,2;
SELECT profile_code,selection_mode,count(*) AS receipts
FROM public.lf_profile_skill_selection_receipt_v1
WHERE skill_code='INPUT_GOVERNANCE_CONTEXT_PACK' GROUP BY 1,2 ORDER BY 1,2;
SELECT profile_code,status,count(*) AS n FROM public.lf_skill_invocation_v1
WHERE skill_code='INPUT_GOVERNANCE_CONTEXT_PACK' GROUP BY 1,2 ORDER BY 1,2;
```
Registro de recibos de selección: 0 filas para la skill en la consulta. Invocaciones: PRODUCT-DIRECTOR-LF 4 BLOCKED + 2 FAILED; UI-ARCHITECT 4 BLOCKED; total 10. No demuestra ausencia histórica de éxito en otras superficies; no sumar tickets/receipts como nuevas invocaciones.

## 2. Dependencias de código

Fuente desplegada de catálogo SQL y huellas MD5 (pg_get_functiondef), no ejecuciones. Referencias estáticas pueden ser comentarios o nombres de contrato; no implican llamada efectiva. Las rutas de adapter alternativas quedan inventariadas sin habilitarse.

| Objeto | MD5 observado | Relación observada |
|---|---|---|
| public.lf_profile_native_bridge_prepare_v1 | ea7d74b10a02749368dfb636a58f1ad0 | input_validate + selector/invocación de skill + ticket genérico |
| public.lf_profile_execution_input_validate_v1 | bfd4ccd94408635bd34a151f2db4e6c2 | step 40; sin token literal del resolver IG en cuerpo |
| public.lf_profile_skill_invoke_selected_v1 | 5518b63ac3a1707ffeda5989a9f1d5c4 | invocador seleccionado |
| public.lf_skill_h_input_governance_context_pack_v1 | e20544acc09117d97d642f323ec94b54 | referencia a resolver IG y contratos |
| programacion.fn_lf_profile_input_governance_resolve_v1 | 37c08b86b3595e77bf94dae7e5451386 | política/catálogo/descriptor; pantalla semántica; ejecutor IG |
| programacion.fn_lf_profile_adapter_input_governance_resolve_v1 | aa486273f5d3f734678e99cfed2dafb5 | adapters; contratos, pantallas y readiness; ejecutor IG |
| programacion.fn_lf_router_input_governance_derive_v1 | 648a0153006ff26ac4b0471fedff4682 | función conservada; contratos y pantallas; no implica invocación actual |
| programacion.fn_input_governance_execute(integer,text) | 68a6a5466ed40a06d673eb1cffc24ec2 | pantallas, contratos, readiness |
| public.fn_input_governance_execute(integer,text) | 0d4986afda598f52d110b9cfde834d78 | superficie executora |
| public.fn_input_governance_execute(integer,text,uuid) | cd2961df94d99744787e10a393126d51 | superficie executora con ticket |
| public.lf_profile_input_governance_requirement_v1 | c2367d2e342108f09f77762406723a54 | requisito conservado |
| public.lf_profile_input_governance_runtime_ticket_issue_v1 | 7945acf4d72bc1d7b85a0f646405a16a | step40 y agent Edge |
| public.lf_profile_input_governance_runtime_ticket_consume_v1 | c695c14a3ff158202855c9a68264a6c8 | consumidor ticket IG |
| public.lf_profile_skill_runtime_ticket_issue_v1 | c28d4fa9c071b5b760724f44669619d0 | invocador skill |
| public.lf_profile_skill_runtime_ticket_consume_v1 | 6f8faf566fa9218c62e3621c06932799 | consume ticket IG |
| public.lf_profile_native_bridge_record_report_v1 | 83cca1d0731ecbaaa02e09222ad0d1f7 | reporte Step80; no certificar promoción |
 
Consulta reproducible de llamadas potenciales:
```sql
WITH f AS (
 SELECT n.nspname AS sch,p.proname AS fn,
 pg_get_function_identity_arguments(p.oid) AS args,
 md5(pg_get_functiondef(p.oid)) AS body_md5,lower(p.prosrc) AS src
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE p.prokind='f' AND n.nspname IN ('public','programacion','lf_ops')
)
SELECT sch,fn,args,body_md5,array(
 SELECT x FROM unnest(ARRAY['fn_lf_profile_input_governance_resolve_v1',
 'fn_lf_profile_adapter_input_governance_resolve_v1','lf_profile_execution_input_validate_v1',
 'lf_profile_input_governance_requirement_v1','lf_profile_input_governance_runtime_ticket_issue_v1',
 'lf_profile_input_governance_runtime_ticket_consume_v1','lf_profile_skill_invoke_selected_v1',
 'lf_skill_h_input_governance_context_pack_v1','fn_input_governance_execute',
 'lf_profile_skill_runtime_ticket_issue_v1','lf_profile_skill_runtime_ticket_consume_v1',
 'fn_lf_router_input_governance_derive_v1','input_readiness_context_pack_runtime_v1',
 'input-governance-agent-v1','lf_ops.reglas','programacion.input_readiness_runs',
 'lf_ops.pantallas','programacion.contratos']) AS t(x)
 WHERE strpos(src,x)>0 ORDER BY x) AS refs
FROM f WHERE fn ~ '(profile.*(governance|skill|input_validate|bridge_prepare|bridge_record_report)|fn_input_governance_execute|router_input_governance|lf_skill_h_input_governance_context_pack)'
 OR src ~ '(fn_lf_profile_(adapter_)?input_governance_resolve_v1|lf_profile_execution_input_validate_v1|lf_profile_input_governance_(requirement|runtime_ticket_issue|runtime_ticket_consume)_v1|input_readiness_context_pack_runtime_v1|input-governance-agent-v1)'
ORDER BY sch,fn,args;
```

Git anclado: supabase/migrations/20261114182712_lf_router_ig_skill_policy_only_v1.sql (blob 3d67fe19f1d9c304caf52afede92f84ec2540dbd, líneas 59–79, 188–214); supabase/functions/lf-profiles-governance-caller-v1/caller.ts (blob e3de51c339b968b1aadebdaca1637c157b6fef46, líneas 15–16, 373–393, 647); scripts/lf_profile_native_resume.py, candidatos localizados por búsqueda de código. Inventario edge publicado (metadata, no paridad byte a byte): input-governance-agent-v1 ACTIVE v20; input-governance-curator-v1 ACTIVE v16; input-governance-validator-v1 ACTIVE v21; lf-profiles-governance-caller-v1 ACTIVE v106. La ruta de skill observada por SQL es selección opcional, handler, resolver, ejecución IG. El transporte histórico CONTEXT_PACK_RUNTIME_ACTION y el ticket RPC siguen en código; distinguir existencia de uso. No se llama a las Edge ni se comprueba una respuesta en runtime.

## 3. Contratos y persistencia

```sql
SELECT DISTINCT ON (contrato_codigo) contrato_codigo,id,version_id,
 especificacion->'allowed_consumers' AS allowed_consumers,fail_closed,
 md5(especificacion::text) AS hash
FROM programacion.contratos WHERE estado='defined'
 AND contrato_codigo ~* '^INPUT_(GOVERNANCE|READINESS|FRESHNESS)'
ORDER BY contrato_codigo,id DESC;
SELECT step_order,step_id,resolver_ref,status,required_evidence_keys
FROM public.lf_operation_step_contracts WHERE operation_code='EJECUCION_PERFIL_LF' ORDER BY step_order;
```
Últimas filas defined por id, todas fail_closed=true y version_id=19 (identificador, no revisión semántica): FRESHNESS_DELTA id39 hash 422b4d32a631eedcc4245c7cdd0c7153; GOVERNANCE_DIVERGENCE_LEVELS id50 df6c10aed3673a87a15ce6cfc1b2b55f; GOVERNANCE_EXECUTION id42 20e761d1192c27568026f896c7a1bf15 (STORY_CREATOR, CONTEXT_PACK, MANUAL); GOVERNANCE_MODULE_HEALTH id41 f61dcad1b33e46488c7627b3bca94f6d; READINESS id37 229eb569cf7e988ec1b222df91b70876.
11 contratos de pasos ACTIVE_ENFORCEMENT, órdenes 0/10/20/30/40/45/47/50/60/70/80. Paso 40 input_validate requiere input_scope, activation_trigger_match, scope_authority_packet, scope_authority_packet_sha256. Rutas de readiness y cobertura: programacion.input_readiness_runs, input_family_assessments, input_family_inheritable_members_v1, input_family_inheritable_sources_v1, input_family_reuse_map_v1, input_governance_cohort_memberships, input_governance_cohort_types, public.v_lf_input_family_coverage_by_screen_v1. Existencia no equivale a dependencia directa de todos los perfiles.
Preservar segregación de autoridad y contenido; no interpretar hallazgo de IG como permiso de efecto.

## 4. Prueba PG17 real (SELECT-only, sin mutación)

Ejecutada en la base indicada con BEGIN READ ONLY / ROLLBACK. Negativas son variantes CTE (no UPDATE/DELETE); test de referencia textual no equivale a invocar la función. Resultado 103/103: positive_policy 10/10, negative_policy 90/90, positive_source_token 1/1, negative_missing_token 1/1, no_direct_resolver_token_step40 1/1. server_version=17.6; transaction_read_only=on; policy_md5=ee7cbe99eca484257556069c32360f8b. Sin efecto persistente. Si una fuente deriva, volver a inspeccionar, no aprobar automáticamente.
```sql
BEGIN READ ONLY;
WITH base AS (
 SELECT p.profile_code,p.enabled,p.owner_decision_required,p.selection_mode,p.required_operation,p.allowed_effects,c.status,c.effect,d.descriptor_status,d.descriptor->>'schema_version' AS schema_version
 FROM public.lf_skill_selector_policy_v1 p JOIN public.lf_skill_catalog_v1 c USING(skill_code) JOIN public.lf_skill_selection_registry_v1 d USING(skill_code)
 WHERE p.skill_code='INPUT_GOVERNANCE_CONTEXT_PACK'
), variants AS (
 SELECT b.*, t.label, t.expected FROM base b CROSS JOIN (VALUES ('original',true),('disabled',false),('owner_required',false),('mandatory',false),('wrong_operation',false),('write_effect',false),('not_ready',false),('wrong_catalog_effect',false),('stale_descriptor',false),('wrong_schema',false)) t(label,expected)
), eval AS (
 SELECT profile_code,label,expected,COALESCE((CASE WHEN label='disabled' THEN false ELSE enabled END)
 AND NOT (CASE WHEN label='owner_required' THEN true ELSE owner_decision_required END)
 AND (CASE WHEN label='mandatory' THEN 'MANDATORY' ELSE selection_mode END)='SEMANTIC_OPTIONAL'
 AND (CASE WHEN label='wrong_operation' THEN 'ZZT_DIAGNOSTIC' ELSE required_operation END)='EJECUCION_PERFIL_LF'
 AND (CASE WHEN label='write_effect' THEN ARRAY['WRITE']::text[] ELSE allowed_effects END)=ARRAY['READ_ONLY']::text[]
 AND (CASE WHEN label='not_ready' THEN 'DISABLED' ELSE status END)='READY'
 AND (CASE WHEN label='wrong_catalog_effect' THEN 'WRITE' ELSE effect END)='READ_ONLY'
 AND (CASE WHEN label='stale_descriptor' THEN 'STALE' ELSE descriptor_status END)='CURRENT'
 AND (CASE WHEN label='wrong_schema' THEN 'ZZT_INVALID' ELSE schema_version END)='LF_SKILL_SELECTION_DESCRIPTOR_V1',false) AS actual FROM variants
), refs AS (
 SELECT p.proname,lower(p.prosrc) AS src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('public','programacion') AND p.prokind='f'
), checks AS (
 SELECT 'positive_policy' AS test,count(*) AS cases,count(*) FILTER (WHERE actual=expected) AS passed FROM eval WHERE label='original'
 UNION ALL SELECT 'negative_policy', count(*),count(*) FILTER (WHERE actual=expected) FROM eval WHERE label<>'original'
 UNION ALL SELECT 'positive_source_token',count(*),count(*) FILTER (WHERE strpos(src,'fn_lf_profile_input_governance_resolve_v1')>0) FROM refs WHERE proname='lf_skill_h_input_governance_context_pack_v1'
 UNION ALL SELECT 'negative_missing_token',count(*),count(*) FILTER (WHERE strpos(replace(src,'fn_lf_profile_input_governance_resolve_v1','zzt_removed_dependency'),'fn_lf_profile_input_governance_resolve_v1')=0) FROM refs WHERE proname='lf_skill_h_input_governance_context_pack_v1'
 UNION ALL SELECT 'no_direct_resolver_token_step40',count(*),count(*) FILTER (WHERE strpos(src,'fn_lf_profile_input_governance_resolve_v1')=0) FROM refs WHERE proname='lf_profile_execution_input_validate_v1'
)
SELECT current_setting('server_version') AS pg_version,current_setting('transaction_read_only') AS read_only, jsonb_agg(to_jsonb(checks) ORDER BY test) AS checks,(SELECT md5(string_agg(to_jsonb(base)::text,'|' ORDER BY profile_code)) FROM base) AS policy_md5 FROM checks;
ROLLBACK;
```
Readback previo al PR: 586 lf_ops.reglas, 14 saly.reglas, 10 lf_ops.nucleo_reglas, 14 saly.nucleo_reglas. Repetir conteos y hash tras Train; comparar. No prueba invariancia de todos los contenidos por sí solo.
```sql
SELECT (SELECT count(*) FROM lf_ops.reglas) AS legadas_lf,
 (SELECT count(*) FROM saly.reglas) AS legadas_saly,
 (SELECT count(*) FROM lf_ops.nucleo_reglas) AS nucleo_lf,
 (SELECT count(*) FROM saly.nucleo_reglas) AS nucleo_saly;
```

## 5. EKB y plan delta

Revisado public.lf_error_knowledge: LF-IG-SKILL-FAILED-STEP40-FINDING-20261114-001 ACTIVO; LF-PROFILE-STEP80-IG-CLEARANCE-OMITTED-20261116-001 CANDIDATO; LF-NUCLEO-IG-FAMILIES-WITHOUT-RULES-20261120-001 ACTIVO. Conservar esos estados; sin nuevo hallazgo distinto que justifique crear una fila. La existencia del inventario no resuelve los hallazgos.
```sql
SELECT codigo,estado,titulo FROM public.lf_error_knowledge
WHERE codigo ILIKE '%DP-IG%' OR codigo ILIKE '%NUCLEO%IG%'
 OR codigo ILIKE '%IG%SKILL%' OR codigo ILIKE '%SKILL%IG%'
 OR codigo ILIKE '%PROFILE%IG%' OR codigo ILIKE '%IG%PROFILE%'
 OR codigo ILIKE '%IG%PERFIL%' OR codigo ILIKE '%PERFIL%IG%' ORDER BY codigo;
```
Tablero núcleo 70/100, F4 1/3, A4 2/4. DP-IG-01 inventario: EVIDENCIA LISTA, pendiente PASE/Train/readback; no añadir puntos al denominador original de 100. DP-IG-02..05 permanecen abiertas, sin redefinir sus criterios a falta del texto original íntegro. D8 pendiente del dueño. No iniciar el siguiente criterio en este lote. Las tres casillas de bindings de Paulo siguen abiertas. Ruta de publicación documental: PR único sin migración, checks, Merge Train oficial, readback Git y SELECT de invariantes; no se hace merge manual.
