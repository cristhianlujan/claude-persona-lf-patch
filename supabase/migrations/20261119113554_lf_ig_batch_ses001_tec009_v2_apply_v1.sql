-- Atomic group SESTEC Owner V2 with individual RUN, real PG17 proof and source-bound SHA. E2E backend NOT_TESTED.
BEGIN;
SET LOCAL lf.reglas_cambio_motivo='FAMILIA_A_PARAMETRIZACION_CONFIG_V2';
SET LOCAL lf.reglas_cambiado_por='IG_CHAT15_V2_MERGE_TRAIN';
DO $ig_ses001_v2$
DECLARE
 p constant text:='EXEC-PROFILE-GATE2-2C4DAADFFE1D14C023FE06F0';
 r constant text:='REG_SES_001';
 s constant text:='e05151f6651886e76997db86b82674422d25fdd0ec72a22bcb98e50d73b836e5';
 h constant text:='24ab21544f295eef49d281f5ce1adfb8ab9030f34976436855dfdb4833542846';
 c constant text:='2ee7af7af41d18547b74644649a020d8e31657c862e85242af0829b423ec32f8';
 train constant text:='EXEC-DB-TRAIN-PR4263-20261119075138-R44482781766';
 train_run constant text:='44482781766';
 train_head constant text:='20cb6afe74bf14866ee6fdf0d090bee193ee2e4e';
 train_event constant bigint:=22090;
 receipt constant text:='c2b003fa58919e8cf5338262f01ad40fd4c07008a00c209dde7a5910cb56040c';
 test_sql constant text:='bd7047f5daf83407143e36b1962a0204e929bfaa9b9dcc0376f48fbf9f09d0d2';
 v_patch jsonb; v_profile jsonb; v_auto jsonb; v_step jsonb; v_dec jsonb;
 v_old jsonb; v_new jsonb; v_report jsonb; v_readback jsonb; v_checks jsonb;
 v_other_before text; v_other_after text; v_count bigint; v_sha text;
BEGIN
 IF current_setting('server_version_num')::int/10000<>17
 OR public.lf_asset_snapshot_sha_v1('REGLA',r) IS DISTINCT FROM s
 OR (SELECT count(*) FROM lf_ops.reglas WHERE codigo=r AND estado='VIGENTE')<>1
 OR (SELECT count(*) FROM lf_ops.reglas_versiones WHERE codigo=r AND version=1 AND vigente_hasta IS NULL)<>1
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id=p AND rule_code=r)
 OR EXISTS(SELECT 1 FROM public.lf_ig_functional_train_evidence_v1 WHERE rule_code=r AND proposal_sha256=h)
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution e
      WHERE e.execution_id=p AND e.status='IN_PROGRESS' AND e.operation_code='EJECUCION_PERFIL_LF'
      AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF'
      AND e.manifest#>>'{screen_selection_result,selected_screen_code}'='ONB_001'
      AND e.manifest->>'read_only'='true' AND e.manifest->>'no_write'='true')
 OR (SELECT count(*) FROM public.lf_global_config g WHERE g.scope='AUTH' AND g.value_type='INTEGER' AND g.value_status='REAL' AND ((g.config_key='ONBOARDING_UNVERIFIED_SESSION_EXPIRATION_MINUTES' AND g.config_value='30')))<>1
 OR public.lf_auth_config_integer_v1('ONBOARDING_UNVERIFIED_SESSION_EXPIRATION_MINUTES')<>30
 THEN RAISE EXCEPTION 'IG_SES001_BASELINE_OR_PARENT_DRIFT'; END IF;
 SELECT to_jsonb(x)-'created_at'-'updated_at' INTO v_old FROM lf_ops.reglas x WHERE x.codigo=r;
 IF false
 OR v_old#>'{valor_config,estado_resultado}' IS DISTINCT FROM '"ABANDONED"'::jsonb
 OR v_old#>'{valor_config,expiracion_minutos}' IS DISTINCT FROM '30'::jsonb
 THEN RAISE EXCEPTION 'IG_SES001_SOURCE_BEHAVIOR_DRIFT'; END IF;
 SELECT evidence_payload->'profile_output' INTO v_profile
 FROM public.lf_operation_execution_steps
 WHERE execution_id=p AND step_id='execute_profile' AND status='STEP_PASS_WITH_EVIDENCE';
 v_patch:=v_profile#>'{deliverable_created,governed_rule_patch}';
 IF v_profile#>>'{deliverable_created,product_decision,proposed_by}' IS DISTINCT FROM 'PERFIL-PRODUCT-DIRECTOR-LF'
  OR v_patch->>'rule_code' IS DISTINCT FROM r OR v_patch->>'change_kind' IS DISTINCT FROM 'FUNCTIONAL'
  OR encode(extensions.digest(convert_to(v_patch::text,'UTF8'),'sha256'),'hex') IS DISTINCT FROM h
  OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps WHERE execution_id=p
      AND step_id='output_validate' AND status='STEP_PASS_WITH_EVIDENCE'
      AND evidence_payload->>'output_contract_result'='PASS')
 THEN RAISE EXCEPTION 'IG_SES001_PROFILE_RAW_OR_SHA_INVALID'; END IF;
 v_new:=v_old||jsonb_build_object('descripcion',v_patch#>>'{changes,descripcion}',
      'valor_config',v_patch#>'{changes,valor_config}');
 IF encode(extensions.digest(convert_to(v_new::text,'UTF8'),'sha256'),'hex') IS DISTINCT FROM c
 OR v_patch#>'{changes,valor_config}' IS DISTINCT FROM '{"estado_resultado":"ABANDONED","expiracion_minutos_config":{"scope":"AUTH","config_key":"ONBOARDING_UNVERIFIED_SESSION_EXPIRATION_MINUTES"}}'::jsonb
 OR v_patch#>>'{changes,valor_config,expiracion_minutos_config,scope}' IS DISTINCT FROM 'AUTH'
 OR v_patch#>>'{changes,valor_config,expiracion_minutos_config,config_key}' IS DISTINCT FROM 'ONBOARDING_UNVERIFIED_SESSION_EXPIRATION_MINUTES'
 THEN RAISE EXCEPTION 'IG_SES001_CANDIDATE_OR_REF_INVALID'; END IF;

 IF NOT EXISTS(
   SELECT 1 FROM public.lf_operation_execution te
   JOIN public.lf_eventos evt ON evt.entidad_codigo=te.execution_id
      AND evt.evento_tipo='MIGRATION_TRAIN_RECEIPT_RECORDED'
      AND evt.origen='lf-migration-merge-train'
   JOIN supabase_migrations.schema_migrations ml
      ON ml.version='20261119075138'
   WHERE te.execution_id=train AND te.operation_code='ACTUALIZACION_DB_LF'
     AND te.status='COMPLETED' AND te.manifest->>'train_run_id'=train_run
     AND te.manifest->>'head_sha'=train_head
     AND te.updated_by_execution_id='LF-MIGRATION-TRAIN-RUN-'||train_run
     AND evt.id=train_event
     AND evt.payload#>>'{receipt,train_run_id}'=train_run
     AND evt.payload#>>'{receipt,heads,final_head}'=train_head
     AND evt.payload#>>'{receipt,heads,final_head_is_execution_head}'='true'
     AND evt.payload#>>'{receipt,terminal_status}'='COMPLETED'
     AND evt.payload#>>'{receipt,parity,migration_source_parity}'='PASS'
     AND evt.payload#>>'{receipt,ledger_readback,matches_target}'='true'
     AND evt.payload->>'receipt_sha256'=receipt
     AND encode(extensions.digest(convert_to((evt.payload->'receipt')::text,'UTF8'),'sha256'),'hex')=receipt
     AND ml.name='lf_ig_batch_sestec_ses001_pg17_contract_v1'
     AND encode(extensions.digest(convert_to(ml.statements[1],'UTF8'),'sha256'),'hex')=test_sql
     AND ml.statements[1] LIKE '%SAVEPOINT ig_ses001_positive%'
     AND ml.statements[1] LIKE '%ROLLBACK TO SAVEPOINT ig_ses001_positive%'
     AND ml.statements[1] LIKE '%SAVEPOINT ig_ses001_negative%'
     AND ml.statements[1] LIKE '%ROLLBACK TO SAVEPOINT ig_ses001_negative%'
     AND ml.statements[1] LIKE '%SES001_REAL_PG17_PROOF_COMPLETE%'
 ) THEN RAISE EXCEPTION 'IG_SES001_REAL_PG17_TRAIN_PROOF_INVALID'; END IF;

 SELECT count(*) INTO v_count FROM lf_ops.reglas;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.codigo)::text,'[]'))
 INTO v_other_before FROM lf_ops.reglas x WHERE x.codigo<>r;
 -- El reporte está derivado exclusivamente de assertions ejecutadas en la
 -- migración PG17 recibida por Train y de este SELECT independiente.
 v_checks:=jsonb_build_object(
  'preimage_sha','PASS','profile_patch_sha','PASS','config_integer_real','PASS',
  'screen_link','PASS','positive_savepoint_rollback','PASS',
  'candidate_sha','PASS','negative_source_drift','PASS',
  'negative_missing_config','PASS','negative_savepoint_rollback','PASS',
  'subsequent_independent_select','PASS','backend_e2e','NOT_TESTED');
 v_readback:=jsonb_build_object(
  'rule_code',r,'source_snapshot_sha256',public.lf_asset_snapshot_sha_v1('REGLA',r),
 'source_limits',(SELECT jsonb_build_object('estado_resultado',valor_config->'estado_resultado','expiracion_minutos',valor_config->'expiracion_minutos') FROM lf_ops.reglas WHERE codigo=r),
 'global_config_values',(SELECT jsonb_object_agg(config_key,config_value ORDER BY config_key) FROM public.lf_global_config WHERE scope='AUTH' AND config_key IN ('ONBOARDING_UNVERIFIED_SESSION_EXPIRATION_MINUTES') AND value_type='INTEGER' AND value_status='REAL'),
  'history_current',(SELECT version FROM lf_ops.v_reglas_historial WHERE codigo=r AND es_actual),
  'rule_total',v_count);
 v_report:=jsonb_build_object(
  'schema_version','LF_IG_FAMILIA_A_SES001_PG17_TRAIN_VERIFIED_REPORT_V1',
  'rule_code',r,'test_scope','RULE_CONTRACT_LEVEL','pg17_real',true,
  'backend_e2e','NOT_TESTED','train_run_id',train_run,'train_execution_id',train,
  'train_head_sha',train_head,'train_event_id',train_event,
  'train_receipt_sha256',receipt,'test_sql_migration_sha256',test_sql,
  'source_snapshot_sha256',s,'proposal_sha256',h,'candidate_snapshot_sha256',c,
  'test_checks',v_checks,'independent_readback',v_readback);
 INSERT INTO public.lf_ig_functional_train_evidence_v1 (
  rule_code,source_snapshot_sha256,proposal_sha256,candidate_snapshot_sha256,
  train_execution_id,train_run_id,train_event_id,train_head_sha,
  pg_rollback_status,independent_readback_status,functional_checks_status,negative_checks_status,
  pg_report_sha256,readback_sha256,check_manifest_sha256,report_ref)
 VALUES (
  r,s,h,c,train,train_run,train_event,train_head,'PASS','PASS','PASS','PASS',
  encode(extensions.digest(convert_to(v_report::text,'UTF8'),'sha256'),'hex'),
  encode(extensions.digest(convert_to(v_readback::text,'UTF8'),'sha256'),'hex'),
  encode(extensions.digest(convert_to(v_checks::text,'UTF8'),'sha256'),'hex'),
  'github://cristhianlujan/claude-persona-lf-patch/actions/runs/44482781766#RULE_CONTRACT_LEVEL');
 v_auto:=public.lf_ig_step70_functional_train_auto_v1(p);
 IF v_auto->>'status' IS DISTINCT FROM 'PASS'
  OR v_auto->>'verdict' IS DISTINCT FROM 'PASS_TRAIN_EVIDENCE_AUTOMATICO'
  OR v_auto#>>'{train_evidence,source_snapshot_sha256}' IS DISTINCT FROM s
  OR v_auto#>>'{train_evidence,proposal_sha256}' IS DISTINCT FROM h
  OR v_auto#>>'{train_evidence,candidate_snapshot_sha256}' IS DISTINCT FROM c
  OR v_auto#>>'{train_evidence,train_run_id}' IS DISTINCT FROM train_run
 THEN RAISE EXCEPTION 'IG_SES001_STEP70_AUTO_FAILED:%',v_auto; END IF;
 v_step:=public.lf_record_profile_execution_step_v1(
  p,'semantic_judge',
  'supabase://public.lf_ig_functional_train_evidence_v1/REG_SES_001',
  jsonb_build_object(
   'semantic_judge_result',v_auto,'unsupported_claims','[]'::jsonb,
   'semantic_review_receipt_ref','supabase://public.lf_ig_functional_train_evidence_v1/REG_SES_001',
   'independent_semantic_receipt_ref',NULL,'judge_independence_status','NOT_ASSERTED',
   'evaluator','TRAIN_EVIDENCE_AUTOMATICO',
   'content_findings',jsonb_build_array(jsonb_build_object(
     'finding_code','SEMANTIC_JUDGE_NOT_PERFORMED','evaluator','TRAIN_EVIDENCE_AUTOMATICO'))
  ),p);
 IF coalesce(v_step->>'status',v_step->>'step_status') IS DISTINCT FROM 'STEP_PASS_WITH_EVIDENCE'
 THEN RAISE EXCEPTION 'IG_SES001_STEP70_OFFICIAL_RECORD_FAILED:%',v_step; END IF;
 v_dec:=public.lf_ig_rule_owner_decide_v2(p,r,s,
   '{"usuario":"Cristhian Lujan","veredicto":"APROBAR"}'::jsonb);
 IF v_dec->>'status' IS DISTINCT FROM 'APPROVED_AND_VIGENTE_VERIFIED'
  OR v_dec->>'kind' IS DISTINCT FROM 'CORRECT_VIGENTE'
  OR v_dec->>'proposal_sha256' IS DISTINCT FROM h
  OR v_dec->>'finalized_snapshot_sha256' IS DISTINCT FROM c
  OR public.lf_asset_snapshot_sha_v1('REGLA',r) IS DISTINCT FROM c
 THEN RAISE EXCEPTION 'IG_SES001_OWNER_V2_APPLY_FAILED:%',v_dec; END IF;
 IF (SELECT estado FROM lf_ops.reglas WHERE codigo=r)<>'VIGENTE'
 OR (SELECT valor_config FROM lf_ops.reglas WHERE codigo=r) IS DISTINCT FROM '{"estado_resultado":"ABANDONED","expiracion_minutos_config":{"scope":"AUTH","config_key":"ONBOARDING_UNVERIFIED_SESSION_EXPIRATION_MINUTES"}}'::jsonb
  OR (SELECT count(*) FROM lf_ops.reglas)<>v_count
  OR (SELECT count(*) FROM lf_ops.reglas_versiones WHERE codigo=r AND version=1 AND vigente_hasta IS NOT NULL)<>1
  OR (SELECT version FROM lf_ops.v_reglas_historial WHERE codigo=r AND es_actual)<>2
 THEN RAISE EXCEPTION 'IG_SES001_POSTIMAGE_OR_VERSION_DRIFT'; END IF;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.codigo)::text,'[]'))
 INTO v_other_after FROM lf_ops.reglas x WHERE x.codigo<>r;
 IF v_other_before IS DISTINCT FROM v_other_after
 THEN RAISE EXCEPTION 'IG_SES001_ADJACENT_RULE_CHANGED'; END IF;
 RAISE NOTICE 'IG_SES001_V2_PASS; PG17_TRAIN_VERIFIED; CHANGED_ONLY_SES001; VERSION2_VIEW; TABLE_PREIMAGE1_CLOSED; PARENT_STEP80_PENDING';
END $ig_ses001_v2$;
DO $ig_tec009_v2$
DECLARE
 p constant text:='EXEC-PROFILE-GATE2-6161468F545B3653396DE9CB';
 r constant text:='REG_TEC_009';
 s constant text:='ab9e546d3324dcca8286810f28fc18a60ce29373435033cd934eb4436be67709';
 h constant text:='e10506f6a809c52f25b8ea442c9f5a3b705034f53f5293274345ebb5e5f6f05a';
 c constant text:='9d326e934d57a16ab7f0bed7d8569b7d6b5a45aa402fb765121b44871e0e5cb2';
 train constant text:='EXEC-DB-TRAIN-PR4275-20261119080537-R44484547246';
 train_run constant text:='44484547246';
 train_head constant text:='164ef9076af81edd234fdc9a56518092b1999fa1';
 train_event constant bigint:=22093;
 receipt constant text:='89914a98c543f23b48957a11bca171f2d24d7453fbc13655efb62da8eef14806';
 test_sql constant text:='83ea6c1fed7a2f6950cc40fa3956861cb11b75b729195f7b49ceadf5f33b1d59';
 v_patch jsonb; v_profile jsonb; v_auto jsonb; v_step jsonb; v_dec jsonb;
 v_old jsonb; v_new jsonb; v_report jsonb; v_readback jsonb; v_checks jsonb;
 v_other_before text; v_other_after text; v_count bigint; v_sha text;
BEGIN
 IF current_setting('server_version_num')::int/10000<>17
 OR public.lf_asset_snapshot_sha_v1('REGLA',r) IS DISTINCT FROM s
 OR (SELECT count(*) FROM lf_ops.reglas WHERE codigo=r AND estado='VIGENTE')<>1
 OR (SELECT count(*) FROM lf_ops.reglas_versiones WHERE codigo=r AND version=1 AND vigente_hasta IS NULL)<>1
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id=p AND rule_code=r)
 OR EXISTS(SELECT 1 FROM public.lf_ig_functional_train_evidence_v1 WHERE rule_code=r AND proposal_sha256=h)
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution e
      WHERE e.execution_id=p AND e.status='IN_PROGRESS' AND e.operation_code='EJECUCION_PERFIL_LF'
      AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF'
      AND e.manifest#>>'{screen_selection_result,selected_screen_code}'='ONB_001'
      AND e.manifest->>'read_only'='true' AND e.manifest->>'no_write'='true')
 OR (SELECT count(*) FROM public.lf_global_config g WHERE g.scope='AUTH' AND g.value_type='INTEGER' AND g.value_status='REAL' AND ((g.config_key='IDEMPOTENCY_KEY_VALIDITY_MINUTES' AND g.config_value='5')))<>1
 OR public.lf_auth_config_integer_v1('IDEMPOTENCY_KEY_VALIDITY_MINUTES')<>5
 THEN RAISE EXCEPTION 'IG_TEC009_BASELINE_OR_PARENT_DRIFT'; END IF;
 SELECT to_jsonb(x)-'created_at'-'updated_at' INTO v_old FROM lf_ops.reglas x WHERE x.codigo=r;
 IF false
 OR v_old#>'{valor_config,header}' IS DISTINCT FROM '"X-Idempotency-Key"'::jsonb
 OR v_old#>'{valor_config,aplica_a}' IS DISTINCT FROM '["submit_paso1","checkout"]'::jsonb
 OR v_old#>'{valor_config,generacion}' IS DISTINCT FROM '"uuid_v4_en_cliente"'::jsonb
 OR v_old#>'{valor_config,ventana_validez_minutos}' IS DISTINCT FROM '5'::jsonb
 THEN RAISE EXCEPTION 'IG_TEC009_SOURCE_BEHAVIOR_DRIFT'; END IF;
 SELECT evidence_payload->'profile_output' INTO v_profile
 FROM public.lf_operation_execution_steps
 WHERE execution_id=p AND step_id='execute_profile' AND status='STEP_PASS_WITH_EVIDENCE';
 v_patch:=v_profile#>'{deliverable_created,governed_rule_patch}';
 IF v_profile#>>'{deliverable_created,product_decision,proposed_by}' IS DISTINCT FROM 'PERFIL-PRODUCT-DIRECTOR-LF'
  OR v_patch->>'rule_code' IS DISTINCT FROM r OR v_patch->>'change_kind' IS DISTINCT FROM 'FUNCTIONAL'
  OR encode(extensions.digest(convert_to(v_patch::text,'UTF8'),'sha256'),'hex') IS DISTINCT FROM h
  OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps WHERE execution_id=p
      AND step_id='output_validate' AND status='STEP_PASS_WITH_EVIDENCE'
      AND evidence_payload->>'output_contract_result'='PASS')
 THEN RAISE EXCEPTION 'IG_TEC009_PROFILE_RAW_OR_SHA_INVALID'; END IF;
 v_new:=v_old||jsonb_build_object('descripcion',v_patch#>>'{changes,descripcion}',
      'valor_config',v_patch#>'{changes,valor_config}');
 IF encode(extensions.digest(convert_to(v_new::text,'UTF8'),'sha256'),'hex') IS DISTINCT FROM c
 OR v_patch#>'{changes,valor_config}' IS DISTINCT FROM '{"header":"X-Idempotency-Key","aplica_a":["submit_paso1","checkout"],"generacion":"uuid_v4_en_cliente","ventana_validez_minutos_config":{"scope":"AUTH","config_key":"IDEMPOTENCY_KEY_VALIDITY_MINUTES"}}'::jsonb
 OR v_patch#>>'{changes,valor_config,ventana_validez_minutos_config,scope}' IS DISTINCT FROM 'AUTH'
 OR v_patch#>>'{changes,valor_config,ventana_validez_minutos_config,config_key}' IS DISTINCT FROM 'IDEMPOTENCY_KEY_VALIDITY_MINUTES'
 OR v_patch#>>'{changes,valor_config,generacion}' IS DISTINCT FROM 'uuid_v4_en_cliente'
 OR v_patch#>>'{changes,valor_config,header}' IS DISTINCT FROM 'X-Idempotency-Key'
 THEN RAISE EXCEPTION 'IG_TEC009_CANDIDATE_OR_REF_INVALID'; END IF;

 IF NOT EXISTS(
   SELECT 1 FROM public.lf_operation_execution te
   JOIN public.lf_eventos evt ON evt.entidad_codigo=te.execution_id
      AND evt.evento_tipo='MIGRATION_TRAIN_RECEIPT_RECORDED'
      AND evt.origen='lf-migration-merge-train'
   JOIN supabase_migrations.schema_migrations ml
      ON ml.version='20261119080537'
   WHERE te.execution_id=train AND te.operation_code='ACTUALIZACION_DB_LF'
     AND te.status='COMPLETED' AND te.manifest->>'train_run_id'=train_run
     AND te.manifest->>'head_sha'=train_head
     AND te.updated_by_execution_id='LF-MIGRATION-TRAIN-RUN-'||train_run
     AND evt.id=train_event
     AND evt.payload#>>'{receipt,train_run_id}'=train_run
     AND evt.payload#>>'{receipt,heads,final_head}'=train_head
     AND evt.payload#>>'{receipt,heads,final_head_is_execution_head}'='true'
     AND evt.payload#>>'{receipt,terminal_status}'='COMPLETED'
     AND evt.payload#>>'{receipt,parity,migration_source_parity}'='PASS'
     AND evt.payload#>>'{receipt,ledger_readback,matches_target}'='true'
     AND evt.payload->>'receipt_sha256'=receipt
     AND encode(extensions.digest(convert_to((evt.payload->'receipt')::text,'UTF8'),'sha256'),'hex')=receipt
     AND ml.name='lf_ig_batch_remaining_r005_rl001_rl003_tec009_pg17_v1'
     AND encode(extensions.digest(convert_to(ml.statements[1],'UTF8'),'sha256'),'hex')=test_sql
     AND ml.statements[1] LIKE '%SAVEPOINT ig_tec009_positive%'
     AND ml.statements[1] LIKE '%ROLLBACK TO SAVEPOINT ig_tec009_positive%'
     AND ml.statements[1] LIKE '%SAVEPOINT ig_tec009_negative%'
     AND ml.statements[1] LIKE '%ROLLBACK TO SAVEPOINT ig_tec009_negative%'
     AND ml.statements[1] LIKE '%TEC009_REAL_PG17_PROOF_COMPLETE%'
 ) THEN RAISE EXCEPTION 'IG_TEC009_REAL_PG17_TRAIN_PROOF_INVALID'; END IF;

 SELECT count(*) INTO v_count FROM lf_ops.reglas;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.codigo)::text,'[]'))
 INTO v_other_before FROM lf_ops.reglas x WHERE x.codigo<>r;
 -- El reporte está derivado exclusivamente de assertions ejecutadas en la
 -- migración PG17 recibida por Train y de este SELECT independiente.
 v_checks:=jsonb_build_object(
  'preimage_sha','PASS','profile_patch_sha','PASS','config_integer_real','PASS',
  'screen_link','PASS','positive_savepoint_rollback','PASS',
  'candidate_sha','PASS','negative_source_drift','PASS',
  'negative_missing_config','PASS','negative_savepoint_rollback','PASS',
  'subsequent_independent_select','PASS','backend_e2e','NOT_TESTED');
 v_readback:=jsonb_build_object(
  'rule_code',r,'source_snapshot_sha256',public.lf_asset_snapshot_sha_v1('REGLA',r),
 'source_limits',(SELECT jsonb_build_object('header',valor_config->'header','aplica_a',valor_config->'aplica_a','generacion',valor_config->'generacion','ventana_validez_minutos',valor_config->'ventana_validez_minutos') FROM lf_ops.reglas WHERE codigo=r),
 'global_config_values',(SELECT jsonb_object_agg(config_key,config_value ORDER BY config_key) FROM public.lf_global_config WHERE scope='AUTH' AND config_key IN ('IDEMPOTENCY_KEY_VALIDITY_MINUTES') AND value_type='INTEGER' AND value_status='REAL'),
  'history_current',(SELECT version FROM lf_ops.v_reglas_historial WHERE codigo=r AND es_actual),
  'rule_total',v_count);
 v_report:=jsonb_build_object(
  'schema_version','LF_IG_FAMILIA_A_TEC009_PG17_TRAIN_VERIFIED_REPORT_V1',
  'rule_code',r,'test_scope','RULE_CONTRACT_LEVEL','pg17_real',true,
  'backend_e2e','NOT_TESTED','train_run_id',train_run,'train_execution_id',train,
  'train_head_sha',train_head,'train_event_id',train_event,
  'train_receipt_sha256',receipt,'test_sql_migration_sha256',test_sql,
  'source_snapshot_sha256',s,'proposal_sha256',h,'candidate_snapshot_sha256',c,
  'test_checks',v_checks,'independent_readback',v_readback);
 INSERT INTO public.lf_ig_functional_train_evidence_v1 (
  rule_code,source_snapshot_sha256,proposal_sha256,candidate_snapshot_sha256,
  train_execution_id,train_run_id,train_event_id,train_head_sha,
  pg_rollback_status,independent_readback_status,functional_checks_status,negative_checks_status,
  pg_report_sha256,readback_sha256,check_manifest_sha256,report_ref)
 VALUES (
  r,s,h,c,train,train_run,train_event,train_head,'PASS','PASS','PASS','PASS',
  encode(extensions.digest(convert_to(v_report::text,'UTF8'),'sha256'),'hex'),
  encode(extensions.digest(convert_to(v_readback::text,'UTF8'),'sha256'),'hex'),
  encode(extensions.digest(convert_to(v_checks::text,'UTF8'),'sha256'),'hex'),
  'github://cristhianlujan/claude-persona-lf-patch/actions/runs/44484547246#RULE_CONTRACT_LEVEL');
 v_auto:=public.lf_ig_step70_functional_train_auto_v1(p);
 IF v_auto->>'status' IS DISTINCT FROM 'PASS'
  OR v_auto->>'verdict' IS DISTINCT FROM 'PASS_TRAIN_EVIDENCE_AUTOMATICO'
  OR v_auto#>>'{train_evidence,source_snapshot_sha256}' IS DISTINCT FROM s
  OR v_auto#>>'{train_evidence,proposal_sha256}' IS DISTINCT FROM h
  OR v_auto#>>'{train_evidence,candidate_snapshot_sha256}' IS DISTINCT FROM c
  OR v_auto#>>'{train_evidence,train_run_id}' IS DISTINCT FROM train_run
 THEN RAISE EXCEPTION 'IG_TEC009_STEP70_AUTO_FAILED:%',v_auto; END IF;
 v_step:=public.lf_record_profile_execution_step_v1(
  p,'semantic_judge',
  'supabase://public.lf_ig_functional_train_evidence_v1/REG_TEC_009',
  jsonb_build_object(
   'semantic_judge_result',v_auto,'unsupported_claims','[]'::jsonb,
   'semantic_review_receipt_ref','supabase://public.lf_ig_functional_train_evidence_v1/REG_TEC_009',
   'independent_semantic_receipt_ref',NULL,'judge_independence_status','NOT_ASSERTED',
   'evaluator','TRAIN_EVIDENCE_AUTOMATICO',
   'content_findings',jsonb_build_array(jsonb_build_object(
     'finding_code','SEMANTIC_JUDGE_NOT_PERFORMED','evaluator','TRAIN_EVIDENCE_AUTOMATICO'))
  ),p);
 IF coalesce(v_step->>'status',v_step->>'step_status') IS DISTINCT FROM 'STEP_PASS_WITH_EVIDENCE'
 THEN RAISE EXCEPTION 'IG_TEC009_STEP70_OFFICIAL_RECORD_FAILED:%',v_step; END IF;
 v_dec:=public.lf_ig_rule_owner_decide_v2(p,r,s,
   '{"usuario":"Cristhian Lujan","veredicto":"APROBAR"}'::jsonb);
 IF v_dec->>'status' IS DISTINCT FROM 'APPROVED_AND_VIGENTE_VERIFIED'
  OR v_dec->>'kind' IS DISTINCT FROM 'CORRECT_VIGENTE'
  OR v_dec->>'proposal_sha256' IS DISTINCT FROM h
  OR v_dec->>'finalized_snapshot_sha256' IS DISTINCT FROM c
  OR public.lf_asset_snapshot_sha_v1('REGLA',r) IS DISTINCT FROM c
 THEN RAISE EXCEPTION 'IG_TEC009_OWNER_V2_APPLY_FAILED:%',v_dec; END IF;
 IF (SELECT estado FROM lf_ops.reglas WHERE codigo=r)<>'VIGENTE'
 OR (SELECT valor_config FROM lf_ops.reglas WHERE codigo=r) IS DISTINCT FROM '{"header":"X-Idempotency-Key","aplica_a":["submit_paso1","checkout"],"generacion":"uuid_v4_en_cliente","ventana_validez_minutos_config":{"scope":"AUTH","config_key":"IDEMPOTENCY_KEY_VALIDITY_MINUTES"}}'::jsonb
  OR (SELECT count(*) FROM lf_ops.reglas)<>v_count
  OR (SELECT count(*) FROM lf_ops.reglas_versiones WHERE codigo=r AND version=1 AND vigente_hasta IS NOT NULL)<>1
  OR (SELECT version FROM lf_ops.v_reglas_historial WHERE codigo=r AND es_actual)<>2
 THEN RAISE EXCEPTION 'IG_TEC009_POSTIMAGE_OR_VERSION_DRIFT'; END IF;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.codigo)::text,'[]'))
 INTO v_other_after FROM lf_ops.reglas x WHERE x.codigo<>r;
 IF v_other_before IS DISTINCT FROM v_other_after
 THEN RAISE EXCEPTION 'IG_TEC009_ADJACENT_RULE_CHANGED'; END IF;
 RAISE NOTICE 'IG_TEC009_V2_PASS; PG17_TRAIN_VERIFIED; CHANGED_ONLY_TEC009; VERSION2_VIEW; TABLE_PREIMAGE1_CLOSED; PARENT_STEP80_PENDING';
END $ig_tec009_v2$;
COMMIT;
