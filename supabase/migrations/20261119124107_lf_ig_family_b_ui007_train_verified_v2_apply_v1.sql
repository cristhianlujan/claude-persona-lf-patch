-- Familia B UI007 Owner V2. Otras reglas sin cambio.
-- Source-bound PG17 REAL receipt, Step50/60 verified native, Step70 auto, Owner V2, SHA/version2.
-- Backend E2E NOT_TESTED.
BEGIN;
DO $ig_b_ui007_v2$
DECLARE
 r CONSTANT text:='REG_UI_007'; p CONSTANT text:='EXEC-PROFILE-GATE2-B61F053224091B267AF23EFD';
 s CONSTANT text:='49dc81d9c04ff59fcbae358df0a33b1ed87ea035a7cf446a02e341384363c274'; h CONSTANT text:='216cb7a8b7c202fb0936d559542c072689a52ff35d11602e48324ad53a43163d'; cand CONSTANT text:='08c6769c06cc3d4a4daaa38f717ed2fa23092dddd8e98debfc678b05c7e747be';
 train CONSTANT text:='EXEC-DB-TRAIN-PR4403-20261119121607-R44521742049'; train_run CONSTANT text:='44521742049';
 train_head CONSTANT text:='fcf12ab62a5655c69aedacd6fd3cce6f9039fc8f'; train_event CONSTANT bigint:=22175;
 receipt CONSTANT text:='d15b8ba6cf2685f14a1eccad9584f3d665f55547240e1ed92b7f19450b3637b3'; test_sql CONSTANT text:='7d8bae8bfad2d3dd5a84921d7736588ee5214b7ab83171154c56932b3040d743';
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
 OR NOT EXISTS(SELECT 1 FROM lf_ops.reglas r0 JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r0.id JOIN lf_ops.pantallas pa ON pa.id=rp.pantalla_id WHERE r0.codigo=r AND pa.codigo='PASO3_MULTI_OFERTA')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution e WHERE e.execution_id=p AND e.operation_code='EJECUCION_PERFIL_LF' AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF' AND e.status='IN_PROGRESS' AND e.manifest#>>'{screen_selection_result,selected_screen_code}'='PASO3_MULTI_OFERTA' AND e.manifest->>'no_write'='true')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps st WHERE st.execution_id=p AND st.step_id='output_validate' AND st.status='STEP_PASS_WITH_EVIDENCE' AND st.evidence_payload->>'output_contract_result'='PASS')
 OR (SELECT count(*) FROM public.lf_global_config g WHERE g.scope='UX' AND g.config_key='HOME_VARIANT_MAX_SKELETON_SECONDS' AND g.config_value='5' AND g.value_type='INTEGER' AND g.value_status='REAL')<>1
 THEN RAISE EXCEPTION 'IG_B_UI007_BASELINE_RUN_CONFIG_DRIFT'; END IF;
 SELECT to_jsonb(q)-'created_at'-'updated_at' INTO v_old FROM lf_ops.reglas q WHERE q.codigo=r;
 SELECT evidence_payload->'profile_output' INTO v_profile FROM public.lf_operation_execution_steps
 WHERE execution_id=p AND step_id='execute_profile' AND status='STEP_PASS_WITH_EVIDENCE';
 v_patch:=v_profile#>'{deliverable_created,governed_rule_patch}';
 IF v_profile#>>'{deliverable_created,product_decision,proposed_by}' IS DISTINCT FROM 'PERFIL-PRODUCT-DIRECTOR-LF'
 OR v_patch->>'rule_code' IS DISTINCT FROM r
 OR v_patch->>'change_kind' IS DISTINCT FROM 'FUNCTIONAL'
 OR encode(extensions.digest(convert_to(v_patch::text,'UTF8'),'sha256'),'hex') IS DISTINCT FROM h
 OR v_patch#>>'{changes,valor_config,duracion_maxima_s_config_ref,scope}' IS DISTINCT FROM 'UX'
 OR v_patch#>>'{changes,valor_config,duracion_maxima_s_config_ref,config_key}' IS DISTINCT FROM 'HOME_VARIANT_MAX_SKELETON_SECONDS'
 OR (v_patch#>'{changes,valor_config}')?'duracion_maxima_s'
 OR v_patch#>>'{changes,valor_config,tipo}' IS DISTINCT FROM 'skeleton_contextual'
 OR v_patch#>>'{changes,valor_config,fallback_si_supera}' IS DISTINCT FROM 'home_variant_sin_oferta'
 OR position('home_variant' in v_patch#>>'{changes,descripcion}')=0
 OR position('public.lf_global_config' in v_patch#>>'{changes,descripcion}')=0
 THEN RAISE EXCEPTION 'IG_B_UI007_PATCH_SEMANTICS_OR_SHA_DRIFT'; END IF;
 v_new:=v_old||jsonb_build_object('descripcion',v_patch#>>'{changes,descripcion}','valor_config',v_patch#>'{changes,valor_config}');
 IF encode(extensions.digest(convert_to(v_new::text,'UTF8'),'sha256'),'hex') IS DISTINCT FROM cand
 OR v_new->>'titulo' IS DISTINCT FROM v_old->>'titulo'
 OR v_new->>'razon' IS DISTINCT FROM v_old->>'razon'
 OR v_new->>'estado' IS DISTINCT FROM 'VIGENTE'
 THEN RAISE EXCEPTION 'IG_B_UI007_CANDIDATE_SHA_OR_SCOPE_DRIFT'; END IF;
 IF NOT EXISTS(
 SELECT 1 FROM public.lf_operation_execution te
 JOIN public.lf_eventos evt ON evt.entidad_codigo=te.execution_id AND evt.evento_tipo='MIGRATION_TRAIN_RECEIPT_RECORDED' AND evt.origen='lf-migration-merge-train'
 JOIN supabase_migrations.schema_migrations ml ON ml.version='20261119121607'
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
 AND ml.name='lf_ig_family_b_ui007_pg17_v1'
 AND encode(extensions.digest(convert_to(ml.statements[1],'UTF8'),'sha256'),'hex')=test_sql
 AND ml.statements[1] LIKE '%ROLLBACK TO SAVEPOINT ig_b_regui007_positive%'
 AND ml.statements[1] LIKE '%ROLLBACK TO SAVEPOINT ig_b_regui007_negative%'
 AND ml.statements[1] LIKE '%IG_B_regui007_REAL_PG17_PROOF_COMPLETE%'
 ) THEN RAISE EXCEPTION 'IG_B_UI007_REAL_TRAIN_PG17_PROOF_INVALID'; END IF;
 SELECT count(*) INTO v_total FROM lf_ops.reglas;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(q) ORDER BY q.codigo)::text,'[]')) INTO v_before_other
 FROM lf_ops.reglas q WHERE q.codigo<>r;
 v_checks:=jsonb_build_object('preimage_sha','PASS','profile_patch_sha','PASS','candidate_sha','PASS','screen_link','PASS','config_integer_real','PASS','positive_savepoint_rollback','PASS','negative_source_drift','PASS','negative_missing_config','PASS','negative_savepoint_rollback','PASS','independent_readback','PASS','backend_e2e','NOT_TESTED');
 v_readback:=jsonb_build_object('rule_code',r,'source_snapshot_sha256',public.lf_asset_snapshot_sha_v1('REGLA',r),
 'source_config',(SELECT valor_config FROM lf_ops.reglas WHERE codigo=r),
 'global_config_values',(SELECT jsonb_object_agg(config_key,config_value ORDER BY config_key) FROM public.lf_global_config WHERE scope='UX' AND config_key='HOME_VARIANT_MAX_SKELETON_SECONDS'),
 'history_current',(SELECT version FROM lf_ops.v_reglas_historial WHERE codigo=r AND es_actual),'rule_total',v_total);
 v_report:=jsonb_build_object('schema_version','LF_IG_FAMILIA_B_UI007_PG17_TRAIN_VERIFIED_REPORT_V1','rule_code',r,'test_scope','RULE_CONTRACT_LEVEL',
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
 'github://cristhianlujan/claude-persona-lf-patch/actions/runs/44521742049#RULE_CONTRACT_LEVEL');
 v_auto:=public.lf_ig_step70_functional_train_auto_v1(p);
 IF v_auto->>'status' IS DISTINCT FROM 'PASS'
 OR v_auto->>'verdict' IS DISTINCT FROM 'PASS_TRAIN_EVIDENCE_AUTOMATICO'
 OR v_auto#>>'{train_evidence,source_snapshot_sha256}' IS DISTINCT FROM s
 OR v_auto#>>'{train_evidence,proposal_sha256}' IS DISTINCT FROM h
 OR v_auto#>>'{train_evidence,candidate_snapshot_sha256}' IS DISTINCT FROM cand
 OR v_auto#>>'{train_evidence,train_run_id}' IS DISTINCT FROM train_run
 THEN RAISE EXCEPTION 'IG_B_UI007_STEP70_AUTO_FAILED:%',v_auto; END IF;
 v_step:=public.lf_record_profile_execution_step_v1(p,'semantic_judge',
 'supabase://public.lf_ig_functional_train_evidence_v1/REG_UI_007',
 jsonb_build_object('semantic_judge_result',v_auto,'unsupported_claims','[]'::jsonb,
 'semantic_review_receipt_ref','supabase://public.lf_ig_functional_train_evidence_v1/REG_UI_007',
 'independent_semantic_receipt_ref',NULL,'judge_independence_status','NOT_ASSERTED',
 'evaluator','TRAIN_EVIDENCE_AUTOMATICO',
 'content_findings',jsonb_build_array(jsonb_build_object('finding_code','SEMANTIC_JUDGE_NOT_PERFORMED','evaluator','TRAIN_EVIDENCE_AUTOMATICO'))),p);
 IF coalesce(v_step->>'status',v_step->>'step_status') IS DISTINCT FROM 'STEP_PASS_WITH_EVIDENCE'
 THEN RAISE EXCEPTION 'IG_B_UI007_STEP70_RECORD_FAILED:%',v_step; END IF;
 v_dec:=public.lf_ig_rule_owner_decide_v2(p,r,s,'{"usuario":"Cristhian Lujan","veredicto":"APROBAR"}'::jsonb);
 IF v_dec->>'status' IS DISTINCT FROM 'APPROVED_AND_VIGENTE_VERIFIED'
 OR v_dec->>'kind' IS DISTINCT FROM 'CORRECT_VIGENTE'
 OR v_dec->>'proposal_sha256' IS DISTINCT FROM h
 OR v_dec->>'finalized_snapshot_sha256' IS DISTINCT FROM cand
 OR public.lf_asset_snapshot_sha_v1('REGLA',r) IS DISTINCT FROM cand
 OR (SELECT version FROM lf_ops.v_reglas_historial WHERE codigo=r AND es_actual)<>2
 OR (SELECT count(*) FROM lf_ops.reglas)<>v_total
 THEN RAISE EXCEPTION 'IG_B_UI007_OWNER_V2_OR_HISTORY_FAILED:%',v_dec; END IF;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(q) ORDER BY q.codigo)::text,'[]')) INTO v_after_other
 FROM lf_ops.reglas q WHERE q.codigo<>r;
 IF v_before_other IS DISTINCT FROM v_after_other
 THEN RAISE EXCEPTION 'IG_B_UI007_ADJACENT_RULE_CHANGED'; END IF;
 RAISE NOTICE 'IG_B_UI007_V2_PASS; PG17_TRAIN_VERIFIED; VERSION2; OTHER_RULES_INVARIANT; STEP80_PENDING';
END $ig_b_ui007_v2$;
COMMIT;
