-- C1 only: check current readback and persist checkpoint via existing transition.
-- Router ACT-0001 -> ACTUALIZACION_DB_LF -> LF Migration Merge Train.
-- C2/C3 remain PENDING; no profile runtime activation or GOLDEN promotion.
BEGIN;
DO $a16q_c1_close$
DECLARE
 v_plan constant text := 'PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1';
 v_evidence constant text := 'github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/ANALYSIS_A16Q_C1_ROUTER_CONSUMER_INVENTORY_V1.md@9185fe6e09e0af79d0db145fe80bcc8d65173565#blob:28e020ba05721892524bfc7971cd7c0f3a8f9878';
 v_actor constant text := 'LF_MIGRATION_MERGE_TRAIN_A16Q_C1';
 v_boot jsonb;
 v_positive jsonb;
 v_negative jsonb;
 v_meta jsonb;
 v_result jsonb;
 v_assets integer;
 v_bindings integer;
 v_consumers integer;
 v_legacy_succeeded integer;
 v_legacy_router_bound integer;
BEGIN
 SELECT unit_metadata INTO STRICT v_meta
 FROM programacion.engineering_plan_units
 WHERE plan_code=v_plan AND unit_code='A16Q' AND id=807 AND work_item_id=1126
 FOR UPDATE;

 IF v_meta#>>'{action_specs_v1,A16Q_C1,action_kind}' <> 'READBACK_ONCE'
    OR v_meta#>>'{action_specs_v1,A16Q_C1,requires_material_execution}' <> 'false'
    OR v_meta#>>'{a16q_c1_inventory_v1,state}' <> 'RESEARCH_EVIDENCE_ONLY_NOT_CHECKPOINT_PASS'
    OR coalesce(jsonb_array_length(v_meta#>'{a16q_c1_inventory_v1,gaps}'),0) <> 5
    OR v_meta#>>'{production_activation}' <> 'false'
    OR v_meta#>>'{golden_promoted}' <> 'false'
 THEN RAISE EXCEPTION 'A16Q_C1_INVENTORY_SOURCE_DRIFT'; END IF;

 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=1126 AND status='PENDING') <> 3
    OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=1126) <> 3
 THEN RAISE EXCEPTION 'A16Q_C1_CHECKPOINT_PRESTATE_DRIFT'; END IF;

 v_boot:=programacion.fn_engineering_unit_bootstrap_v3(v_plan,'A16Q');
 IF v_boot#>>'{current_checkpoint,checkpoint_code}' <> 'A16Q_C1'
    OR v_boot#>>'{execution_readiness,status}' <> 'READY'
    OR v_boot#>>'{execution_readiness,source_currentness,status}' <> 'CURRENT'
    OR v_boot->>'action_spec_gate' <> 'PASS'
    OR v_boot#>>'{action_spec,action_kind}' <> 'READBACK_ONCE'
 THEN RAISE EXCEPTION 'A16Q_C1_READBACK_NOT_READY:%',v_boot#>'{execution_readiness,reasons}'; END IF;

 -- Source assets and consumer binding readbacks. No runtime/model dispatch.
 SELECT count(*) INTO v_assets FROM public.lf_activos
 WHERE codigo_activo IN (
  'ACT-0001','ACT-0051','PERFIL-UI-ARCHITECT',
  'ADAPTER-LF-SHELL-PROFILE-20260827',
  'ADAPTER-PROJECT-BRAND-MOCKUP-RENDER-LF-20260827',
  'PROFILES_GITHUB_ACTIONS_BATCH_QUEUE_WORKER_V1','PROFILE_RUNTIME_API_SERVICE',
  'ROUTER_DOWNSTREAM_AUTHORITY','OPERATION_EFFECT_GUARD','OPERATION_MATERIALIZATION_GUARD');
 SELECT count(*) INTO v_bindings
 FROM public.v_lf_router_adapter_bindings
 WHERE target_asset_code IN ('PERFIL-UI-ARCHITECT','ACT-0051');
 SELECT count(*) INTO v_consumers
 FROM public.lf_activos
 WHERE codigo_activo IN ('PROFILES_GITHUB_ACTIONS_BATCH_QUEUE_WORKER_V1','PROFILE_RUNTIME_API_SERVICE')
 AND estado_operativo='READ_ONLY' AND runtime_estado='CANDIDATE_READ_ONLY';
 IF v_assets<>10 OR v_bindings<>2 OR v_consumers<>2
 THEN RAISE EXCEPTION 'A16Q_C1_CURRENT_ASSET_BINDING_DRIFT:%/%/%',v_assets,v_bindings,v_consumers; END IF;

 v_positive:=public.lf_router_resolve_v1(
 'Inspeccionar el perfil UI Architect para inventario de arquitectura',
 'PERFIL-UI-ARCHITECT','ASSET_INSPECTION','PERFIL','DIRECT');
 IF v_positive->>'status'<>'READY_INSPECTION'
    OR v_positive#>>'{asset,codigo_activo}'<>'PERFIL-UI-ARCHITECT'
    OR jsonb_array_length(coalesce(v_positive->'adapters','[]'::jsonb))<>1
 THEN RAISE EXCEPTION 'A16Q_C1_ROUTER_DISCOVERY_NOT_PROVEN'; END IF;

 v_negative:=public.lf_router_resolve_v1(
 'Ejecutar el perfil frontend prototype architect solo como prueba de enrutamiento sin efecto',
 'ACT-0051','PROFILE_EXECUTION','PERFIL','DIRECT');
 IF v_negative->>'status'<>'BLOCKED'
    OR v_negative->>'blocking_code'<>'BLOCK_PROFILE_RUNTIME_STATE_NOT_AUTHORIZED'
    OR v_negative->>'downstream_execution_allowed'<>'false'
 THEN RAISE EXCEPTION 'A16Q_C1_ROUTER_NEGATIVE_NOT_PROVEN'; END IF;

 SELECT count(*) FILTER(WHERE status='SUCCEEDED'),
        count(*) FILTER(WHERE status='SUCCEEDED' AND receipt ? 'router_binding')
 INTO v_legacy_succeeded,v_legacy_router_bound
 FROM private.lf_profile_runtime_queue_v1;
 IF v_legacy_succeeded<1 OR v_legacy_router_bound>0
 THEN RAISE EXCEPTION 'A16Q_C1_LEGACY_CONSUMER_EVIDENCE_CHANGED'; END IF;

 -- Non-material READBACK_ONCE explicitly does not require an assertion receipt.
 IF (SELECT programacion.fn_engineering_action_spec_assertion_contract_v1(
       v_plan,'A16Q','A16Q_C1',
       programacion.fn_engineering_checkpoint_action_spec_v3(v_plan,'A16Q','A16Q_C1')
     )->>'status') <> 'NOT_REQUIRED'
 THEN RAISE EXCEPTION 'A16Q_C1_WRONG_ASSERTION_MODE'; END IF;

 v_result:=programacion.fn_engineering_checkpoint_transition_v1(
  v_plan,'A16Q','A16Q_C1','DONE',v_evidence,v_actor,
  format('READBACK_ONCE C1: 10/10 assets, 2 adapter bindings, 2 candidate consumers; Router positive READY_INSPECTION, negative BLOCK_PROFILE_RUNTIME_STATE_NOT_AUTHORIZED; historical SUCCEEDED=%s, Router-bound historical SUCCEEDED=%s; C2 E2E and C3 independent review remain unproven.',v_legacy_succeeded,v_legacy_router_bound)
 );

 IF v_result#>>'{transition,status}'<>'APPLIED'
    OR v_result#>>'{transition,checkpoint_code}'<>'A16Q_C1'
 THEN RAISE EXCEPTION 'A16Q_C1_TRANSITION_NOT_APPLIED'; END IF;

 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=1126 AND checkpoint_code='A16Q_C1'
       AND status='DONE' AND evidence_ref=v_evidence)<>1
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=1126 AND checkpoint_code IN ('A16Q_C2','A16Q_C3')
       AND status='PENDING')<>2
 OR (SELECT count(*) FROM programacion.engineering_work_items
     WHERE id=1126 AND status='IN_PROGRESS')<>1
 OR (SELECT unit_metadata->>'golden_promoted' FROM programacion.engineering_plan_units
     WHERE id=807) <> 'false'
 THEN RAISE EXCEPTION 'A16Q_C1_POSTTRANSITION_READBACK_FAILED'; END IF;
END;
$a16q_c1_close$;
COMMIT;
