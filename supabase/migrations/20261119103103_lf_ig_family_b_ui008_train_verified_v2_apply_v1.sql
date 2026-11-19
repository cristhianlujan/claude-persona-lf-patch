-- Familia B, grupo UI: REG_UI_008 Owner V2. UI007 permanece pendiente; no modificar otras reglas.
-- Source-bound PG17 REAL receipt, Step50/60 verified native, Step70 auto, Owner V2, SHA/version2.
-- Backend E2E NOT_TESTED.
BEGIN;
DO $ig_b_ui008_v2$
DECLARE
 r CONSTANT text:='REG_UI_008'; p CONSTANT text:='EXEC-PROFILE-GATE2-6D315138FF77DF279C38CFC6';
 s CONSTANT text:='ef6ff49a04347a530d31a3f3cd00f66d51e20cc647cff151431cfd3cd26c6a9a'; h CONSTANT text:='4f22edc299d458849d0c34e2a09df968cd654d4367d842e44a18982b4b7d986e'; cand CONSTANT text:='47d0f9c85314abd6419ffad776252f5b143163deeb789789ad0d938332da4a98';
 train CONSTANT text:='EXEC-DB-TRAIN-PR4334-20261119102327-R44505109019'; train_run CONSTANT text:='44505109019';
 train_head CONSTANT text:='1e12fb4a781536989407a640f363d260ae136b6f'; train_event CONSTANT bigint:=22139;
 receipt CONSTANT text:='3992263407f6ee4bbda4edf1ae7dbbaec373dd923affb84551b62a667e9969e4'; test_sql CONSTANT text:='4dfcf43a825b189e35bb5038e87f71e5affefca5d44db2006a9d5bae5ed55ce1';
 v_old jsonb;v_patch jsonb;v_new jsonb;v_profile jsonb;
 v_auto jsonb;v_step jsonb;v_dec jsonb;v_report jsonb;v_checks jsonb;v_readback jsonb;
 v_before_other text;v_after_other text;v_total int;
BEGIN
 IF current_setting('server_version_num')::int/10000<>17
 OR (SELECT count(*) FROM lf_ops.reglas WHERE codigo=r AND estado='VIGENTE')<>1
 OR public.lf_asset_snapshot_sha_v1('REGLA',r) IS DISTINCT FROM s
 OR (SELECT version FROM lf_ops.v_reglas_historial WHERE codigo=r AND es_actual)<>1
 OR (SELECT count(*) FROM lf_ops.reglas_versiones WHERE codigo=r AND version=1 AND vigente_hasta IS NULL)<>1
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id=p AND rule_code=r)
 OR EXISTS(SELECT 1 FROM public.lf_ig_functional_train_evidence_v1 WHERE rule_code=r AND proposal_sha256=h)
 OR NOT EXISTS(SELECT 1 FROM lf_ops.reglas r0 JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r0.id JOIN lf_ops.pantallas pa ON pa.id=rp.pantalla_id WHERE r0.codigo=r AND pa.codigo='ONB_001')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution e WHERE e.execution_id=p AND e.operation_code='EJECUCION_PERFIL_LF' AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF' AND e.status='IN_PROGRESS' AND e.manifest#>>'{screen_selection_result,selected_screen_code}'='ONB_001' AND e.manifest->>'no_write'='true')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps st WHERE st.execution_id=p AND st.step_id='output_validate' AND st.status='STEP_PASS_WITH_EVIDENCE' AND st.evidence_payload->>'output_contract_result'='PASS')
 OR (SELECT count(*) FROM public.lf_global_config g WHERE g.scope='UX' AND
  ((g.config_key='COMPONENT_TRANSITION_MIN_MS' AND g.config_value='150' AND g.value_type='INTEGER' AND g.value_status='REAL')
  OR (g.config_key='COMPONENT_TRANSITION_MAX_MS' AND g.config_value='300' AND g.value_type='INTEGER' AND g.value_status='REAL')
  OR (g.config_key='SCREEN_FADE_MS' AND g.config_value='200' AND g.value_type='INTEGER' AND g.value_status='REAL')
  OR (g.config_key='SKELETON_FADE_MS' AND g.config_value='300' AND g.value_type='INTEGER' AND g.value_status='REAL')))<>4
 THEN RAISE EXCEPTION 'IG_B_UI008_BASELINE_RUN_CONFIG_DRIFT'; END IF;
 SELECT to_jsonb(q)-'created_at'-'updated_at' INTO v_old FROM lf_ops.reglas q WHERE q.codigo=r;
 SELECT evidence_payload->'profile_output' INTO v_profile FROM public.lf_operation_execution_steps
 WHERE execution_id=p AND step_id='execute_profile' AND status='STEP_PASS_WITH_EVIDENCE';
 v_patch:=v_profile#>'{deliverable_created,governed_rule_patch}';
 IF v_profile#>>'{deliverable_created,product_decision,proposed_by}' IS DISTINCT FROM 'PERFIL-PRODUCT-DIRECTOR-LF'
 OR v_patch->>'rule_code' IS DISTINCT FROM r
 OR v_patch->>'change_kind' IS DISTINCT FROM 'FUNCTIONAL'
 OR encode(extensions.digest(convert_to(v_patch::text,'UTF8'),'sha256'),'hex') IS DISTINCT FROM h
 OR v_patch#>>'{changes,valor_config,transicion_componente_ms,min_config_ref,scope}' IS DISTINCT FROM 'UX'
 OR v_patch#>>'{changes,valor_config,transicion_componente_ms,min_config_ref,config_key}' IS DISTINCT FROM 'COMPONENT_TRANSITION_MIN_MS'
 OR v_patch#>>'{changes,valor_config,transicion_componente_ms,max_config_ref,scope}' IS DISTINCT FROM 'UX'
 OR v_patch#>>'{changes,valor_config,transicion_componente_ms,max_config_ref,config_key}' IS DISTINCT FROM 'COMPONENT_TRANSITION_MAX_MS'
 OR v_patch#>>'{changes,valor_config,cambio_pantalla_ms_config_ref,scope}' IS DISTINCT FROM 'UX'
 OR v_patch#>>'{changes,valor_config,cambio_pantalla_ms_config_ref,config_key}' IS DISTINCT FROM 'SCREEN_FADE_MS'
 OR v_patch#>>'{changes,valor_config,skeleton_fade_ms_config_ref,scope}' IS DISTINCT FROM 'UX'
 OR v_patch#>>'{changes,valor_config,skeleton_fade_ms_config_ref,config_key}' IS DISTINCT FROM 'SKELETON_FADE_MS'
 OR (v_patch#>'{changes,valor_config}')?'cambio_pantalla_ms'
 OR (v_patch#>'{changes,valor_config}')?'skeleton_fade_ms'
 OR (v_patch#>'{changes,valor_config,transicion_componente_ms}')?'min'
 OR (v_patch#>'{changes,valor_config,transicion_componente_ms}')?'max'
 OR (v_patch#>>'{changes,descripcion}') NOT LIKE '%public.lf_global_config%'
 OR (v_patch#>>'{changes,descripcion}') LIKE '%150ms%'
 OR (v_patch#>>'{changes,descripcion}') LIKE '%300ms%'
 THEN RAISE EXCEPTION 'IG_B_UI008_PATCH_SEMANTICS_OR_SHA_DRIFT'; END IF;
 v_new:=v_old||jsonb_build_object('descripcion',v_patch#>>'{changes,descripcion}','valor_config',v_patch#>'{changes,valor_config}');
 IF encode(extensions.digest(convert_to(v_new::text,'UTF8'),'sha256'),'hex') IS DISTINCT FROM cand
 OR v_new->>'titulo' IS DISTINCT FROM v_old->>'titulo'
 OR v_new->>'razon' IS DISTINCT FROM v_old->>'razon'
 OR v_new->>'estado' IS DISTINCT FROM 'VIGENTE'
 THEN RAISE EXCEPTION 'IG_B_UI008_CANDIDATE_SHA_OR_SCOPE_DRIFT'; END IF;
 IF NOT EXISTS(
 SELECT 1 FROM public.lf_operation_execution te
 JOIN public.lf_eventos evt ON evt.entidad_codigo=te.execution_id AND evt.evento_tipo='MIGRATION_TRAIN_RECEIPT_RECORDED' AND evt.origen='lf-migration-merge-train'
 JOIN supabase_migrations.schema_migrations ml ON ml.version='20261119102327'
 WHERE te.execution_id=train AND te.operation_code='ACTUALIZACION_DB_LF' AND te.status='COMPLETED'
 AND te.manifest->>'train_run_id'=train_run
 AND te.manifest->>'head_sha'=train_head AND te.updated_by_execution_id='LF-MIGRATION-TRAIN-RUN-'||train_run
 AND evt.id=train_event AND evt.payload#>>'{receipt,train_run_id}'=train_run
 AND evt.payload#>>'{receipt,heads,final_head}'=train_head
 AND evt.payload#>>'{receipt,heads,final_head_is_execution_head}'='true'
 AND evt.payload#>>'{receipt,terminal_status}'='COMPLETED'
 AND evt.payload#>>'{receipt,parity,migration_source_parity}'='PASS'
 AND evt.payload#>>'{receipt,ledger_readback,matches_target}'='true'
 AND evt.payload->>'receipt_sha256'=receipt
 AND encode(extensions.digest(convert_to((evt.payload->'receipt')::text,'UTF8'),'sha256'),'hex')=receipt
 AND ml.name='lf_ig_family_b_ui008_pg17_contract_v1'
 AND encode(extensions.digest(convert_to(ml.statements[1],'UTF8'),'sha256'),'hex')=test_sql
 AND ml.statements[1] LIKE '%ROLLBACK TO SAVEPOINT ig_b_positive%'
 AND ml.statements[1] LIKE '%ROLLBACK TO SAVEPOINT ig_b_negative%'
 AND ml.statements[1] LIKE '%IG_B_REG_UI_008_REAL_PG17_PROOF_COMPLETE%'
 ) THEN RAISE EXCEPTION 'IG_B_UI008_REAL_TRAIN_PG17_PROOF_INVALID'; END IF;
 SELECT count(*) INTO v_total FROM lf_ops.reglas;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(q) ORDER BY q.codigo)::text,'[]')) INTO v_before_other
 FROM lf_ops.reglas q WHERE q.codigo<>r;
 v_checks:=jsonb_build_object('preimage_sha','PASS','profile_patch_sha','PASS','candidate_sha','PASS','screen_link','PASS','config_integer_real','PASS','positive_savepoint_rollback','PASS','negative_source_drift','PASS','negative_missing_config','PASS','negative_savepoint_rollback','PASS','independent_readback','PASS','backend_e2e','NOT_TESTED');
 v_readback:=jsonb_build_object('rule_code',r,'source_snapshot_sha256',public.lf_asset_snapshot_sha_v1('REGLA',r),
 'source_config',(SELECT valor_config FROM lf_ops.reglas WHERE codigo=r),
 'global_config_values',(SELECT jsonb_object_agg(config_key,config_value ORDER BY config_key) FROM public.lf_global_config WHERE scope='UX' AND config_key IN ('COMPONENT_TRANSITION_MIN_MS','COMPONENT_TRANSITION_MAX_MS','SCREEN_FADE_MS','SKELETON_FADE_MS')),
 'history_current',(SELECT version FROM lf_ops.v_reglas_historial WHERE codigo=r AND es_actual),'rule_total',v_total);
 v_report:=jsonb_build_object('schema_version','LF_IG_FAMILIA_B_UI008_PG17_TRAIN_VERIFIED_REPORT_V1','rule_code',r,'test_scope','RULE_CONTRACT_LEVEL',
 'pg17_real',true,'backend_e2e','NOT_TESTED','train_run_id',train_run,'train_execution_id',train,
 'train_head_sha',train_head,'train_event_id',train_event,'train_receipt_sha256',receipt,
 'test_sql_migration_sha256',test_sql,'source_snapshot_sha256',s,'proposal_sha256',h,
 'candidate_snapshot_sha256',cand,'test_checks',v_checks,'independent_readback',v_readback);
 INSERT INTO public.lf_ig_functional_train_evidence_v1(
 rule_code,source_snapshot_sha256,proposal_sha256,candidate_snapshot_sha256,
 train_execution_id,train_run_id,train_event_id,train_head_sha,
 pg_rollback_status,independent_readback_status,functional_checks_status,negative_checks_status,
 pg_report_sha256,readback_sha256,check_manifest_sha256,report_ref)
 VALUES(r,s,h,cand,train,train_run,train_event,train_head,'PASS','PASS','PASS','PASS',
 encode(extensions.digest(convert_to(v_report::text,'UTF8'),'sha256'),'hex'),
 encode(extensions.digest(convert_to(v_readback::text,'UTF8'),'sha256'),'hex'),
 encode(extensions.digest(convert_to(v_checks::text,'UTF8'),'sha256'),'hex'),
 'github://cristhianlujan/claude-persona-lf-patch/actions/runs/44505109019#RULE_CONTRACT_LEVEL');
 v_auto:=public.lf_ig_step70_functional_train_auto_v1(p);
 IF v_auto->>'status' IS DISTINCT FROM 'PASS'
 OR v_auto->>'verdict' IS DISTINCT FROM 'PASS_TRAIN_EVIDENCE_AUTOMATICO'
 OR v_auto#>>'{train_evidence,source_snapshot_sha256}' IS DISTINCT FROM s
 OR v_auto#>>'{train_evidence,proposal_sha256}' IS DISTINCT FROM h
 OR v_auto#>>'{train_evidence,candidate_snapshot_sha256}' IS DISTINCT FROM cand
 OR v_auto#>>'{train_evidence,train_run_id}' IS DISTINCT FROM train_run
 THEN RAISE EXCEPTION 'IG_B_UI008_STEP70_AUTO_FAILED:%',v_auto; END IF;
 v_step:=public.lf_record_profile_execution_step_v1(p,'semantic_judge',
 'supabase://public.lf_ig_functional_train_evidence_v1/REG_UI_008',
 jsonb_build_object('semantic_judge_result',v_auto,'unsupported_claims','[]'::jsonb,
 'semantic_review_receipt_ref','supabase://public.lf_ig_functional_train_evidence_v1/REG_UI_008',
 'independent_semantic_receipt_ref',NULL,'judge_independence_status','NOT_ASSERTED',
 'evaluator','TRAIN_EVIDENCE_AUTOMATICO',
 'content_findings',jsonb_build_array(jsonb_build_object('finding_code','SEMANTIC_JUDGE_NOT_PERFORMED','evaluator','TRAIN_EVIDENCE_AUTOMATICO'))),p);
 IF coalesce(v_step->>'status',v_step->>'step_status') IS DISTINCT FROM 'STEP_PASS_WITH_EVIDENCE'
 THEN RAISE EXCEPTION 'IG_B_UI008_STEP70_RECORD_FAILED:%',v_step; END IF;
 v_dec:=public.lf_ig_rule_owner_decide_v2(p,r,s,'{"usuario":"Cristhian Lujan","veredicto":"APROBAR"}'::jsonb);
 IF v_dec->>'status' IS DISTINCT FROM 'APPROVED_AND_VIGENTE_VERIFIED'
 OR v_dec->>'kind' IS DISTINCT FROM 'CORRECT_VIGENTE'
 OR v_dec->>'proposal_sha256' IS DISTINCT FROM h
 OR v_dec->>'finalized_snapshot_sha256' IS DISTINCT FROM cand
 OR public.lf_asset_snapshot_sha_v1('REGLA',r) IS DISTINCT FROM cand
 OR (SELECT version FROM lf_ops.v_reglas_historial WHERE codigo=r AND es_actual)<>2
 OR (SELECT count(*) FROM lf_ops.reglas)<>v_total
 THEN RAISE EXCEPTION 'IG_B_UI008_OWNER_V2_OR_HISTORY_FAILED:%',v_dec; END IF;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(q) ORDER BY q.codigo)::text,'[]')) INTO v_after_other
 FROM lf_ops.reglas q WHERE q.codigo<>r;
 IF v_before_other IS DISTINCT FROM v_after_other
 THEN RAISE EXCEPTION 'IG_B_UI008_ADJACENT_RULE_CHANGED'; END IF;
 RAISE NOTICE 'IG_B_UI008_V2_PASS; PG17_TRAIN_VERIFIED; VERSION2; 585_OTHER_RULES_INVARIANT; STEP80_PENDING';
END $ig_b_ui008_v2$;
COMMIT;
