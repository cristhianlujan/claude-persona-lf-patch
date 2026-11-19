-- Familia B ALR004+ALR005, Owner V2 full title via existing canonical writer only.
-- Tested PG17 PR #4401 exact Train receipt. No direct DML on lf_ops.reglas.
BEGIN;
CREATE TEMP TABLE ig_b_alr45_specs(code text PRIMARY KEY,parent text,screen text,source_sha text,proposal_sha text,candidate_sha text) ON COMMIT DROP;
INSERT INTO ig_b_alr45_specs VALUES
('REG_ALR_004','EXEC-PROFILE-GATE2-E20D2C0F25D8B32CF9CD6EA3','ONB_001','aaa2aed1bb7ce2697b814dab5909cd151f642c5a89032a9f3763db8ce5011505','fe5dd29eec29d98db3053c8bb7a6a3c4e283ae1b3821de9900cff09478ee63f5','bb60d95cbc9aacba740aa4a490759d8d4079770878047324b89a909df552321c'),
('REG_ALR_005','EXEC-PROFILE-GATE2-5ABE133CA01BE0AD525073E0','ONB_001','4b2d32422b36f65637cdf5901f93570fe60aa4abf1528f47cd301e5b43f38b72','206ce6e62e928c6b29dbca57fc672b06bfecb21b1ea0a343ba7780577ae0c369','27b73cdf590967e30f6968f11b33e34bdd41c87d589e0d472a75e232095aa8a3');
DO $apply$
DECLARE x record;v_old jsonb;v_profile jsonb;v_patch jsonb;v_new jsonb;v_auto jsonb;v_step jsonb;v_dec jsonb;
 v_report jsonb;v_checks jsonb;v_readback jsonb;v_count int;v_other_before text;v_other_after text;
 train CONSTANT text:='EXEC-DB-TRAIN-PR4401-20261119121345-R44521603878';
 train_run CONSTANT text:='44521603878';
 train_head CONSTANT text:='5253a3a673fd51ebde82a7e040f96a3347127511';
 train_event CONSTANT bigint:=22174;
 train_receipt CONSTANT text:='22896fcc6f5da79ad8046fd1383182e79f261e67b09d855b09c3f59498f59094';
 test_sql_sha CONSTANT text:='317bd1765680a4ac35ef9c2f0cb8a46d23feeb69f9b1c7d3f1d65d5f7ea4c7dc';
BEGIN
 IF current_setting('server_version_num')::int/10000<>17 OR (SELECT count(*) FROM ig_b_alr45_specs)<>2 THEN
 RAISE EXCEPTION 'IG_B_ALR45_OWNER_V2_SPECS_OR_PG17_VERSION_INVALID'; END IF;
 IF NOT EXISTS (
 SELECT 1 FROM public.lf_operation_execution te
 JOIN public.lf_eventos evt ON evt.entidad_codigo=te.execution_id AND evt.evento_tipo='MIGRATION_TRAIN_RECEIPT_RECORDED' AND evt.origen='lf-migration-merge-train'
 JOIN supabase_migrations.schema_migrations ml ON ml.version='20261119121345'
 WHERE te.execution_id=train AND te.operation_code='ACTUALIZACION_DB_LF' AND te.status='COMPLETED'
 AND te.manifest->>'train_run_id'=train_run AND te.manifest->>'head_sha'=train_head
 AND te.updated_by_execution_id='LF-MIGRATION-TRAIN-RUN-'||train_run
 AND evt.id=train_event AND evt.payload#>>'{receipt,train_run_id}'=train_run
 AND evt.payload#>>'{receipt,heads,final_head}'=train_head
 AND evt.payload#>>'{receipt,heads,final_head_is_execution_head}'='true'
 AND evt.payload#>>'{receipt,terminal_status}'='COMPLETED'
 AND evt.payload#>>'{receipt,parity,migration_source_parity}'='PASS'
 AND evt.payload#>>'{receipt,ledger_readback,matches_target}'='true'
 AND evt.payload->>'receipt_sha256'=train_receipt
 AND encode(extensions.digest(convert_to((evt.payload->'receipt')::text,'UTF8'),'sha256'),'hex')=train_receipt
 AND ml.name='lf_ig_family_b_alr004005_full_title_pg17_v1'
 AND encode(extensions.digest(convert_to(ml.statements[1],'UTF8'),'sha256'),'hex')=test_sql_sha
 AND ml.statements[1] LIKE '%ROLLBACK TO SAVEPOINT ig_b_alr45_positive%'
 AND ml.statements[1] LIKE '%ROLLBACK TO SAVEPOINT ig_b_alr45_negative%'
 AND ml.statements[1] LIKE '%IG_B_ALR45_FULL_TITLE_REAL_PG17_PROOF_COMPLETE%'
 ) THEN RAISE EXCEPTION 'IG_B_ALR45_OWNER_V2_TRAIN_PROOF_INVALID'; END IF;
 SELECT count(*) INTO v_count FROM lf_ops.reglas;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.codigo)::text,'[]')) INTO v_other_before FROM lf_ops.reglas r WHERE r.codigo NOT IN('REG_ALR_004','REG_ALR_005');
 FOR x IN SELECT * FROM ig_b_alr45_specs ORDER BY code LOOP
 IF (SELECT count(*) FROM lf_ops.reglas r WHERE r.codigo=x.code AND r.estado='VIGENTE')<>1
 OR public.lf_asset_snapshot_sha_v1('REGLA',x.code) IS DISTINCT FROM x.source_sha
 OR (SELECT version FROM lf_ops.v_reglas_historial WHERE codigo=x.code AND es_actual)<>1
 OR (SELECT count(*) FROM lf_ops.reglas_versiones WHERE codigo=x.code AND version=1 AND vigente_hasta IS NULL)<>1
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id=x.parent AND rule_code=x.code)
 OR EXISTS(SELECT 1 FROM public.lf_ig_functional_train_evidence_v1 WHERE rule_code=x.code AND proposal_sha256=x.proposal_sha)
 OR NOT EXISTS(SELECT 1 FROM lf_ops.reglas r JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id JOIN lf_ops.pantallas p ON p.id=rp.pantalla_id WHERE r.codigo=x.code AND p.codigo=x.screen)
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution e WHERE e.execution_id=x.parent AND e.operation_code='EJECUCION_PERFIL_LF' AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF' AND e.status='IN_PROGRESS' AND e.manifest#>>'{screen_selection_result,selected_screen_code}'=x.screen AND e.manifest->>'no_write'='true')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps s WHERE s.execution_id=x.parent AND s.step_id='output_validate' AND s.status='STEP_PASS_WITH_EVIDENCE' AND s.evidence_payload->>'output_contract_result'='PASS')
 THEN RAISE EXCEPTION 'IG_B_ALR45_RULE_OR_RUN_DRIFT:%',x.code; END IF;
 SELECT to_jsonb(r)-'created_at'-'updated_at' INTO v_old FROM lf_ops.reglas r WHERE r.codigo=x.code;
 SELECT evidence_payload->'profile_output' INTO v_profile FROM public.lf_operation_execution_steps WHERE execution_id=x.parent AND step_id='execute_profile' AND status='STEP_PASS_WITH_EVIDENCE';
 v_patch:=v_profile#>'{deliverable_created,governed_rule_patch}';
 IF v_profile#>>'{deliverable_created,product_decision,proposed_by}' IS DISTINCT FROM 'PERFIL-PRODUCT-DIRECTOR-LF'
 OR v_patch->>'rule_code' IS DISTINCT FROM x.code OR v_patch->>'change_kind' IS DISTINCT FROM 'FUNCTIONAL'
 OR encode(extensions.digest(convert_to(v_patch::text,'UTF8'),'sha256'),'hex') IS DISTINCT FROM x.proposal_sha
 OR (v_patch#>>'{changes,titulo}') NOT LIKE '%public.lf_global_config%'
 OR (v_patch#>>'{changes,descripcion}') NOT LIKE '%public.lf_global_config%'
 OR (v_patch#>>'{changes,titulo}') ~ '[0-9]+[[:space:]]*(%|ms|segundos)'
 THEN RAISE EXCEPTION 'IG_B_ALR45_NATIVE_PATCH_TITLE_SHA_DRIFT:%',x.code; END IF;
 IF x.code='REG_ALR_004' AND (
 v_patch#>>'{changes,valor_config,umbral_maximo_config_ref,config_key}' IS DISTINCT FROM 'PASO1_SUBMIT_ERROR_RATE_MAX'
 OR v_patch#>>'{changes,valor_config,ventana_minutos_config_ref,config_key}' IS DISTINCT FROM 'PASO1_SUBMIT_ERROR_WINDOW_MINUTES'
 OR (SELECT count(*) FROM public.lf_global_config WHERE scope='ALERTAS' AND value_status='REAL' AND
 ((config_key='PASO1_SUBMIT_ERROR_RATE_MAX' AND config_value='0.05' AND value_type='DECIMAL') OR (config_key='PASO1_SUBMIT_ERROR_WINDOW_MINUTES' AND config_value='15' AND value_type='INTEGER')))<>2
 ) THEN RAISE EXCEPTION 'IG_B_ALR004_CONFIG_DRIFT'; END IF;
 IF x.code='REG_ALR_005' AND (
 v_patch#>>'{changes,valor_config,umbral_ms_config_ref,config_key}' IS DISTINCT FROM 'LCP_ALERT_THRESHOLD_MS'
 OR v_patch#>>'{changes,valor_config,porcentaje_sesiones_config_ref,config_key}' IS DISTINCT FROM 'LCP_ALERT_SESSIONS_RATIO'
 OR v_patch#>>'{changes,valor_config,ventana_horas_config_ref,config_key}' IS DISTINCT FROM 'LCP_ALERT_WINDOW_HOURS'
 OR (SELECT count(*) FROM public.lf_global_config WHERE scope='ALERTAS' AND value_status='REAL' AND
 ((config_key='LCP_ALERT_THRESHOLD_MS' AND config_value='4000' AND value_type='INTEGER')
 OR (config_key='LCP_ALERT_SESSIONS_RATIO' AND config_value='0.2' AND value_type='DECIMAL')
 OR (config_key='LCP_ALERT_WINDOW_HOURS' AND config_value='1' AND value_type='INTEGER')))<>3
 ) THEN RAISE EXCEPTION 'IG_B_ALR005_CONFIG_DRIFT'; END IF;
 v_new:=v_old||jsonb_build_object('titulo',v_patch#>>'{changes,titulo}','descripcion',v_patch#>>'{changes,descripcion}','valor_config',v_patch#>'{changes,valor_config}');
 IF encode(extensions.digest(convert_to(v_new::text,'UTF8'),'sha256'),'hex') IS DISTINCT FROM x.candidate_sha
 OR v_new->>'titulo' IS NULL OR v_new->>'titulo'=v_old->>'titulo'
 OR v_new->>'razon' IS DISTINCT FROM v_old->>'razon'
 OR v_new->>'origen' IS DISTINCT FROM v_old->>'origen'
 OR v_new->>'estado' IS DISTINCT FROM 'VIGENTE'
 THEN RAISE EXCEPTION 'IG_B_ALR45_FULL_CANDIDATE_SCOPE_SHA_INVALID:%',x.code; END IF;
 v_checks:=jsonb_build_object('preimage_sha','PASS','native_patch_sha','PASS','full_title_candidate_sha','PASS','screen_link','PASS','config_real','PASS',
 'positive_rollback','PASS','negative_source_drift','PASS','negative_missing_config','PASS','negative_rollback','PASS','independent_select','PASS','backend_e2e','NOT_TESTED');
 v_readback:=jsonb_build_object('rule_code',x.code,'source_snapshot_sha256',public.lf_asset_snapshot_sha_v1('REGLA',x.code),
 'source_config',(SELECT valor_config FROM lf_ops.reglas WHERE codigo=x.code),
 'config_values',(SELECT jsonb_object_agg(config_key,config_value ORDER BY config_key) FROM public.lf_global_config WHERE scope='ALERTAS' AND config_key IN('PASO1_SUBMIT_ERROR_RATE_MAX','PASO1_SUBMIT_ERROR_WINDOW_MINUTES','LCP_ALERT_THRESHOLD_MS','LCP_ALERT_SESSIONS_RATIO','LCP_ALERT_WINDOW_HOURS')),
 'history_current',(SELECT version FROM lf_ops.v_reglas_historial WHERE codigo=x.code AND es_actual),'rule_total',v_count);
 v_report:=jsonb_build_object('schema_version','LF_IG_FAMILIA_B_ALR45_TITLE_PG17_TRAIN_VERIFIED_V1','rule_code',x.code,'test_scope','RULE_CONTRACT_LEVEL','pg17_real',true,'backend_e2e','NOT_TESTED',
 'train_run_id',train_run,'train_execution_id',train,'train_head_sha',train_head,'train_event_id',train_event,'train_receipt_sha256',train_receipt,
 'test_sql_migration_sha256',test_sql_sha,'source_snapshot_sha256',x.source_sha,'proposal_sha256',x.proposal_sha,'candidate_snapshot_sha256',x.candidate_sha,
 'test_checks',v_checks,'independent_readback',v_readback);
 INSERT INTO public.lf_ig_functional_train_evidence_v1(rule_code,source_snapshot_sha256,proposal_sha256,candidate_snapshot_sha256,
 train_execution_id,train_run_id,train_event_id,train_head_sha,pg_rollback_status,independent_readback_status,functional_checks_status,negative_checks_status,
 pg_report_sha256,readback_sha256,check_manifest_sha256,report_ref)
 VALUES(x.code,x.source_sha,x.proposal_sha,x.candidate_sha,train,train_run,train_event,train_head,'PASS','PASS','PASS','PASS',
 encode(extensions.digest(convert_to(v_report::text,'UTF8'),'sha256'),'hex'),
 encode(extensions.digest(convert_to(v_readback::text,'UTF8'),'sha256'),'hex'),
 encode(extensions.digest(convert_to(v_checks::text,'UTF8'),'sha256'),'hex'),
 'github://cristhianlujan/claude-persona-lf-patch/actions/runs/44521603878#RULE_CONTRACT_LEVEL');
 v_auto:=public.lf_ig_step70_functional_train_auto_v1(x.parent);
 IF v_auto->>'status' IS DISTINCT FROM 'PASS' OR v_auto->>'verdict' IS DISTINCT FROM 'PASS_TRAIN_EVIDENCE_AUTOMATICO'
 OR v_auto#>>'{train_evidence,source_snapshot_sha256}' IS DISTINCT FROM x.source_sha
 OR v_auto#>>'{train_evidence,proposal_sha256}' IS DISTINCT FROM x.proposal_sha
 OR v_auto#>>'{train_evidence,candidate_snapshot_sha256}' IS DISTINCT FROM x.candidate_sha
 OR v_auto#>>'{train_evidence,train_run_id}' IS DISTINCT FROM train_run
 THEN RAISE EXCEPTION 'IG_B_ALR45_STEP70_AUTO_INVALID:%:%',x.code,v_auto; END IF;
 v_step:=public.lf_record_profile_execution_step_v1(x.parent,'semantic_judge',
 'supabase://public.lf_ig_functional_train_evidence_v1/'||x.code,
 jsonb_build_object('semantic_judge_result',v_auto,'unsupported_claims','[]'::jsonb,
 'semantic_review_receipt_ref','supabase://public.lf_ig_functional_train_evidence_v1/'||x.code,
 'independent_semantic_receipt_ref',NULL,'judge_independence_status','NOT_ASSERTED','evaluator','TRAIN_EVIDENCE_AUTOMATICO',
 'content_findings',jsonb_build_array(jsonb_build_object('finding_code','SEMANTIC_JUDGE_NOT_PERFORMED','evaluator','TRAIN_EVIDENCE_AUTOMATICO'))),x.parent);
 IF coalesce(v_step->>'status',v_step->>'step_status') IS DISTINCT FROM 'STEP_PASS_WITH_EVIDENCE'
 THEN RAISE EXCEPTION 'IG_B_ALR45_STEP70_RECORD_FAILED:%:%',x.code,v_step; END IF;
 v_dec:=public.lf_ig_rule_owner_decide_v2(x.parent,x.code,x.source_sha,'{"usuario":"Cristhian Lujan","veredicto":"APROBAR"}'::jsonb);
 IF v_dec->>'status' IS DISTINCT FROM 'APPROVED_AND_VIGENTE_VERIFIED'
 OR v_dec->>'kind' IS DISTINCT FROM 'CORRECT_VIGENTE'
 OR v_dec->>'proposal_sha256' IS DISTINCT FROM x.proposal_sha
 OR v_dec->>'finalized_snapshot_sha256' IS DISTINCT FROM x.candidate_sha
 OR public.lf_asset_snapshot_sha_v1('REGLA',x.code) IS DISTINCT FROM x.candidate_sha
 OR (SELECT version FROM lf_ops.v_reglas_historial WHERE codigo=x.code AND es_actual)<>2
 THEN RAISE EXCEPTION 'IG_B_ALR45_OWNER_V2_RESULT_INVALID:%:%',x.code,v_dec; END IF;
 END LOOP;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.codigo)::text,'[]')) INTO v_other_after FROM lf_ops.reglas r WHERE r.codigo NOT IN('REG_ALR_004','REG_ALR_005');
 IF v_count<>(SELECT count(*) FROM lf_ops.reglas) OR v_other_before IS DISTINCT FROM v_other_after
 THEN RAISE EXCEPTION 'IG_B_ALR45_OTHER_RULES_CHANGED'; END IF;
 RAISE NOTICE 'IG_B_ALR45_OWNER_V2_COMPLETE; 2_VERSION2; ALL_OTHER_RULES_INVARIANT; STEP80_PENDING; BACKEND_E2E_NOT_TESTED';
END $apply$;
COMMIT;
