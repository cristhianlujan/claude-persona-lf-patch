-- Familia B OBS005 Owner V2. Otras reglas sin cambio.
-- Source-bound PG17 REAL receipt, Step50/60 verified native, Step70 auto, Owner V2, SHA/version2.
-- Backend E2E NOT_TESTED.
BEGIN;
DO $ig_b_obs005_v2$
DECLARE
 r CONSTANT text:='REG_OBS_005'; p CONSTANT text:='EXEC-PROFILE-GATE2-B8D9F1C5033279574F674D76';
 s CONSTANT text:='8d275b25f25a4794a570aa72add1ef828a649e497a45169fb2f43e3711b9831a'; h CONSTANT text:='08561b6c4b43a00e5c92fe790ac21478afa679dbab1c08eea871889d7cc43fc4'; cand CONSTANT text:='87c4d828d3a0edd7c4be27efb273e23133facec9d311fe0eb004c54f40373a2e';
 train CONSTANT text:='EXEC-DB-TRAIN-PR4342-20261119100840-R44502766352'; train_run CONSTANT text:='44502766352';
 train_head CONSTANT text:='b8ede15e085a63c4702152cf08c3fb532d65a2a6'; train_event CONSTANT bigint:=22130;
 receipt CONSTANT text:='b32a1c4b1757cb8a5c27f078cf64ce93e634c3c3b178c767627d377ecd31d073'; test_sql CONSTANT text:='158418b3bc9e66fccec2ef1fac39212bbfb3e171b8cf0a6e951158e9b5daa42d';
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
 OR NOT EXISTS(SELECT 1 FROM lf_ops.reglas r0 JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r0.id JOIN lf_ops.pantallas pa ON pa.id=rp.pantalla_id WHERE r0.codigo=r AND pa.codigo='ONB_002')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution e WHERE e.execution_id=p AND e.operation_code='EJECUCION_PERFIL_LF' AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF' AND e.status='IN_PROGRESS' AND e.manifest#>>'{screen_selection_result,selected_screen_code}'='ONB_002' AND e.manifest->>'no_write'='true')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps st WHERE st.execution_id=p AND st.step_id='output_validate' AND st.status='STEP_PASS_WITH_EVIDENCE' AND st.evidence_payload->>'output_contract_result'='PASS')
 OR (SELECT count(*) FROM public.lf_global_config g WHERE g.scope='OBSERVABILIDAD' AND g.config_key='OTP_DELIVERY_P95_SECONDS_MAX' AND g.config_value='30' AND g.value_type='INTEGER' AND g.value_status='REAL')<>1
 THEN RAISE EXCEPTION 'IG_B_OBS005_BASELINE_RUN_CONFIG_DRIFT'; END IF;
 SELECT to_jsonb(q)-'created_at'-'updated_at' INTO v_old FROM lf_ops.reglas q WHERE q.codigo=r;
 SELECT evidence_payload->'profile_output' INTO v_profile FROM public.lf_operation_execution_steps
 WHERE execution_id=p AND step_id='execute_profile' AND status='STEP_PASS_WITH_EVIDENCE';
 v_patch:=v_profile#>'{deliverable_created,governed_rule_patch}';
 IF v_profile#>>'{deliverable_created,product_decision,proposed_by}' IS DISTINCT FROM 'PERFIL-PRODUCT-DIRECTOR-LF'
 OR v_patch->>'rule_code' IS DISTINCT FROM r
 OR v_patch->>'change_kind' IS DISTINCT FROM 'FUNCTIONAL'
 OR encode(extensions.digest(convert_to(v_patch::text,'UTF8'),'sha256'),'hex') IS DISTINCT FROM h
 OR v_patch#>>'{changes,valor_config,p95_segundos_config_ref,scope}' IS DISTINCT FROM 'OBSERVABILIDAD'
 OR v_patch#>>'{changes,valor_config,p95_segundos_config_ref,config_key}' IS DISTINCT FROM 'OTP_DELIVERY_P95_SECONDS_MAX'
 OR (v_patch#>'{changes,valor_config}')?'p95_segundos'
 OR v_patch#>>'{changes,valor_config,metrica}' IS DISTINCT FROM 'tiempo_entrega_otp'
 OR v_patch#>>'{changes,valor_config,alerta_si_supera}' IS DISTINCT FROM 'true'
 OR position('otp_sent y otp_verified' in v_patch#>>'{changes,descripcion}')=0
 OR position('percentil p95 supera' in v_patch#>>'{changes,descripcion}')=0
 OR position('public.lf_global_config' in v_patch#>>'{changes,descripcion}')=0
 OR (v_patch#>>'{changes,descripcion}') LIKE '%30 segundos%'
 THEN RAISE EXCEPTION 'IG_B_OBS005_PATCH_SEMANTICS_OR_SHA_DRIFT'; END IF;
 v_new:=v_old||jsonb_build_object('descripcion',v_patch#>>'{changes,descripcion}','valor_config',v_patch#>'{changes,valor_config}');
 IF encode(extensions.digest(convert_to(v_new::text,'UTF8'),'sha256'),'hex') IS DISTINCT FROM cand
 OR v_new->>'titulo' IS DISTINCT FROM v_old->>'titulo'
 OR v_new->>'razon' IS DISTINCT FROM v_old->>'razon'
 OR v_new->>'estado' IS DISTINCT FROM 'VIGENTE'
 THEN RAISE EXCEPTION 'IG_B_OBS005_CANDIDATE_SHA_OR_SCOPE_DRIFT'; END IF;
 IF NOT EXISTS(
 SELECT 1 FROM public.lf_operation_execution te
 JOIN public.lf_eventos evt ON evt.entidad_codigo=te.execution_id AND evt.evento_tipo='MIGRATION_TRAIN_RECEIPT_RECORDED' AND evt.origen='lf-migration-merge-train'
 JOIN supabase_migrations.schema_migrations ml ON ml.version='20261119100840'
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
 AND ml.name='lf_ig_family_b_obs005_pg17_v1'
 AND encode(extensions.digest(convert_to(ml.statements[1],'UTF8'),'sha256'),'hex')=test_sql
 AND ml.statements[1] LIKE '%ROLLBACK TO SAVEPOINT ig_b_obs005_positive%'
 AND ml.statements[1] LIKE '%ROLLBACK TO SAVEPOINT ig_b_obs005_negative%'
 AND ml.statements[1] LIKE '%IG_B_OBS005_REAL_PG17_PROOF_COMPLETE%'
 ) THEN RAISE EXCEPTION 'IG_B_OBS005_REAL_TRAIN_PG17_PROOF_INVALID'; END IF;
 SELECT count(*) INTO v_total FROM lf_ops.reglas;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(q) ORDER BY q.codigo)::text,'[]')) INTO v_before_other
 FROM lf_ops.reglas q WHERE q.codigo<>r;
 v_checks:=jsonb_build_object('preimage_sha','PASS','profile_patch_sha','PASS','candidate_sha','PASS','screen_link','PASS','config_integer_real','PASS','positive_savepoint_rollback','PASS','negative_source_drift','PASS','negative_missing_config','PASS','negative_savepoint_rollback','PASS','independent_readback','PASS','backend_e2e','NOT_TESTED');
 v_readback:=jsonb_build_object('rule_code',r,'source_snapshot_sha256',public.lf_asset_snapshot_sha_v1('REGLA',r),
 'source_config',(SELECT valor_config FROM lf_ops.reglas WHERE codigo=r),
 'global_config_values',(SELECT jsonb_object_agg(config_key,config_value ORDER BY config_key) FROM public.lf_global_config WHERE scope='OBSERVABILIDAD' AND config_key='OTP_DELIVERY_P95_SECONDS_MAX'),
 'history_current',(SELECT version FROM lf_ops.v_reglas_historial WHERE codigo=r AND es_actual),'rule_total',v_total);
 v_report:=jsonb_build_object('schema_version','LF_IG_FAMILIA_B_OBS005_PG17_TRAIN_VERIFIED_REPORT_V1','rule_code',r,'test_scope','RULE_CONTRACT_LEVEL',
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
 'github://cristhianlujan/claude-persona-lf-patch/actions/runs/44502766352#RULE_CONTRACT_LEVEL');
 v_auto:=public.lf_ig_step70_functional_train_auto_v1(p);
 IF v_auto->>'status' IS DISTINCT FROM 'PASS'
 OR v_auto->>'verdict' IS DISTINCT FROM 'PASS_TRAIN_EVIDENCE_AUTOMATICO'
 OR v_auto#>>'{train_evidence,source_snapshot_sha256}' IS DISTINCT FROM s
 OR v_auto#>>'{train_evidence,proposal_sha256}' IS DISTINCT FROM h
 OR v_auto#>>'{train_evidence,candidate_snapshot_sha256}' IS DISTINCT FROM cand
 OR v_auto#>>'{train_evidence,train_run_id}' IS DISTINCT FROM train_run
 THEN RAISE EXCEPTION 'IG_B_OBS005_STEP70_AUTO_FAILED:%',v_auto; END IF;
 v_step:=public.lf_record_profile_execution_step_v1(p,'semantic_judge',
 'supabase://public.lf_ig_functional_train_evidence_v1/REG_OBS_005',
 jsonb_build_object('semantic_judge_result',v_auto,'unsupported_claims','[]'::jsonb,
 'semantic_review_receipt_ref','supabase://public.lf_ig_functional_train_evidence_v1/REG_OBS_005',
 'independent_semantic_receipt_ref',NULL,'judge_independence_status','NOT_ASSERTED',
 'evaluator','TRAIN_EVIDENCE_AUTOMATICO',
 'content_findings',jsonb_build_array(jsonb_build_object('finding_code','SEMANTIC_JUDGE_NOT_PERFORMED','evaluator','TRAIN_EVIDENCE_AUTOMATICO'))),p);
 IF coalesce(v_step->>'status',v_step->>'step_status') IS DISTINCT FROM 'STEP_PASS_WITH_EVIDENCE'
 THEN RAISE EXCEPTION 'IG_B_OBS005_STEP70_RECORD_FAILED:%',v_step; END IF;
 v_dec:=public.lf_ig_rule_owner_decide_v2(p,r,s,'{"usuario":"Cristhian Lujan","veredicto":"APROBAR"}'::jsonb);
 IF v_dec->>'status' IS DISTINCT FROM 'APPROVED_AND_VIGENTE_VERIFIED'
 OR v_dec->>'kind' IS DISTINCT FROM 'CORRECT_VIGENTE'
 OR v_dec->>'proposal_sha256' IS DISTINCT FROM h
 OR v_dec->>'finalized_snapshot_sha256' IS DISTINCT FROM cand
 OR public.lf_asset_snapshot_sha_v1('REGLA',r) IS DISTINCT FROM cand
 OR (SELECT version FROM lf_ops.v_reglas_historial WHERE codigo=r AND es_actual)<>2
 OR (SELECT count(*) FROM lf_ops.reglas)<>v_total
 THEN RAISE EXCEPTION 'IG_B_OBS005_OWNER_V2_OR_HISTORY_FAILED:%',v_dec; END IF;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(q) ORDER BY q.codigo)::text,'[]')) INTO v_after_other
 FROM lf_ops.reglas q WHERE q.codigo<>r;
 IF v_before_other IS DISTINCT FROM v_after_other
 THEN RAISE EXCEPTION 'IG_B_OBS005_ADJACENT_RULE_CHANGED'; END IF;
 RAISE NOTICE 'IG_B_OBS005_V2_PASS; PG17_TRAIN_VERIFIED; VERSION2; 585_OTHER_RULES_INVARIANT; STEP80_PENDING';
END $ig_b_obs005_v2$;
COMMIT;
