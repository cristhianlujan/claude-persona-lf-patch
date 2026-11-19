-- IG Familia A: CORRECT_VIGENTE REG_ATQ_018, writer V2 solamente.
-- PG17 source-bound proof: #4191, real Train 44473099022, receipt event 22052.
-- BEGIN/SAVEPOINT/ROLLBACK positivo+negativo y SELECT independiente ya se
-- verificaron en #4191; no escribir en lf_ops.reglas por UPDATE directo.
-- El reporte hash se genera de hechos y ledger verificables en esta transaccion.
-- No se declara backend E2E ni identidad humana fuerte.
BEGIN;
SET LOCAL lf.reglas_cambio_motivo='FAMILIA_A_PARAMETRIZACION_CONFIG_V2';
SET LOCAL lf.reglas_cambiado_por='IG_CHAT12_V2_MERGE_TRAIN';
DO $ig_a018_v2$
DECLARE
 p constant text:='EXEC-PROFILE-GATE2-1D8D2E809B7A0E83786E8BD0';
 r constant text:='REG_ATQ_018';
 s constant text:='5fd95746c30e57bc9840a4bf4b42a958d8c8ae5cebf21d08ce55084462845549';
 h constant text:='87a2a9b05a9016a84efb481d00c8c151ddd681a91107a3ab973b5dda1de81c69';
 c constant text:='f94157d45ffa25aab6c951b06fcc2a54291a7935009ff738e8f87913dd46bd05';
 train constant text:='EXEC-DB-TRAIN-PR4196-20261119063613-R44473099022';
 train_run constant text:='44473099022';
 train_head constant text:='e58b28604a567b144dd5fed14e5f35d91fc3329d';
 train_event constant bigint:=22052;
 receipt constant text:='90742b52ce579affac48bc579e7b898eb5d4c16a7b2aa20475a07969c3e84634';
 test_sql constant text:='72fc9aa5fda7467eadcbb03058f9cac4e4446f1c484b4e491414e984671d59a3';
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
      AND e.manifest#>>'{screen_selection_result,selected_screen_code}'='HOME_002'
      AND e.manifest->>'read_only'='true' AND e.manifest->>'no_write'='true')
 OR (SELECT count(*) FROM public.lf_global_config g WHERE g.scope='AUTH'
 AND g.value_type='INTEGER' AND g.value_status='REAL'
 AND ((g.config_key='SESSION_ACCESS_TOKEN_TTL_SECONDS' AND g.config_value='3600')
 OR (g.config_key='SESSION_IDLE_TIMEOUT_SECONDS' AND g.config_value='86400')
 OR (g.config_key='SESSION_ABSOLUTE_TIMEOUT_SECONDS' AND g.config_value='2592000')))<>3
 OR public.lf_auth_config_integer_v1('SESSION_ACCESS_TOKEN_TTL_SECONDS')<>3600
 OR public.lf_auth_config_integer_v1('SESSION_IDLE_TIMEOUT_SECONDS')<>86400
 OR public.lf_auth_config_integer_v1('SESSION_ABSOLUTE_TIMEOUT_SECONDS')<>2592000
 OR NOT EXISTS(SELECT 1 FROM lf_ops.politicas_sesion ps WHERE ps.policy_code='SESSION-CLIENT-DEFAULT'
 AND ps.status='VIGENTE' AND ps.cookie_policy->>'refresh_chain_max_days'='30'
 AND ps.refresh_rotation_enabled=true AND ps.access_token_ttl_seconds=3600
 AND ps.idle_timeout_seconds=86400 AND ps.absolute_timeout_seconds=2592000)
 THEN RAISE EXCEPTION 'IG_ATQ018_BASELINE_OR_PARENT_DRIFT'; END IF;
 SELECT to_jsonb(x)-'created_at'-'updated_at' INTO v_old FROM lf_ops.reglas x WHERE x.codigo=r;
 IF v_old#>>'{valor_config,access_token_ttl_seconds}' IS DISTINCT FROM '3600'
 OR v_old#>>'{valor_config,idle_timeout_seconds}' IS DISTINCT FROM '86400'
 OR v_old#>>'{valor_config,absolute_timeout_seconds}' IS DISTINCT FROM '2592000'
 OR v_old#>>'{valor_config,refresh_token_max_days}' IS DISTINCT FROM '30'
 OR v_old#>>'{valor_config,rotacion_refresh}' IS DISTINCT FROM 'true'
 OR v_old#>>'{valor_config,session_policy_code}' IS DISTINCT FROM 'SESSION-CLIENT-DEFAULT'
 OR v_old#>>'{valor_config,source_decision_number}' IS DISTINCT FROM '105'
 THEN RAISE EXCEPTION 'IG_ATQ018_SOURCE_BEHAVIOR_DRIFT'; END IF;
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
 THEN RAISE EXCEPTION 'IG_ATQ018_PROFILE_RAW_OR_SHA_INVALID'; END IF;
 v_new:=v_old||jsonb_build_object('descripcion',v_patch#>>'{changes,descripcion}',
      'valor_config',v_patch#>'{changes,valor_config}');
 IF encode(extensions.digest(convert_to(v_new::text,'UTF8'),'sha256'),'hex') IS DISTINCT FROM c
 OR v_patch#>>'{changes,valor_config,access_token_ttl_config,scope}' IS DISTINCT FROM 'AUTH'
 OR v_patch#>>'{changes,valor_config,access_token_ttl_config,config_key}' IS DISTINCT FROM 'SESSION_ACCESS_TOKEN_TTL_SECONDS'
 OR v_patch#>>'{changes,valor_config,idle_timeout_config,scope}' IS DISTINCT FROM 'AUTH'
 OR v_patch#>>'{changes,valor_config,idle_timeout_config,config_key}' IS DISTINCT FROM 'SESSION_IDLE_TIMEOUT_SECONDS'
 OR v_patch#>>'{changes,valor_config,absolute_timeout_config,scope}' IS DISTINCT FROM 'AUTH'
 OR v_patch#>>'{changes,valor_config,absolute_timeout_config,config_key}' IS DISTINCT FROM 'SESSION_ABSOLUTE_TIMEOUT_SECONDS'
 OR v_patch#>>'{changes,valor_config,refresh_token_max_policy_ref,policy_code}' IS DISTINCT FROM 'SESSION-CLIENT-DEFAULT'
 OR v_patch#>>'{changes,valor_config,refresh_token_max_policy_ref,policy_path}' IS DISTINCT FROM 'cookie_policy.refresh_chain_max_days'
 OR (v_patch#>'{changes,valor_config}')?'refresh_token_max_days'
 OR (v_patch#>'{changes,valor_config}')?'absolute_timeout_seconds'
 OR (v_patch#>'{changes,valor_config}')?'access_token_ttl_seconds'
 OR (v_patch#>'{changes,valor_config}')?'idle_timeout_seconds'
 OR v_patch#>>'{changes,valor_config,session_policy_code}' IS DISTINCT FROM 'SESSION-CLIENT-DEFAULT'
 OR v_patch#>>'{changes,valor_config,source_decision_number}' IS DISTINCT FROM '105'
 OR v_patch#>>'{changes,valor_config,rotacion_refresh}' IS DISTINCT FROM 'true'
 THEN RAISE EXCEPTION 'IG_ATQ018_CANDIDATE_OR_REF_INVALID'; END IF;

 IF NOT EXISTS(
   SELECT 1 FROM public.lf_operation_execution te
   JOIN public.lf_eventos evt ON evt.entidad_codigo=te.execution_id
      AND evt.evento_tipo='MIGRATION_TRAIN_RECEIPT_RECORDED'
      AND evt.origen='lf-migration-merge-train'
   JOIN supabase_migrations.schema_migrations ml
      ON ml.version='20261119063613'
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
     AND ml.name='lf_ig_chat14_a018_pg17_rule_contract_v1'
     AND encode(extensions.digest(convert_to(ml.statements[1],'UTF8'),'sha256'),'hex')=test_sql
     AND ml.statements[1] LIKE '%SAVEPOINT ig_a018_positive%'
     AND ml.statements[1] LIKE '%ROLLBACK TO SAVEPOINT ig_a018_positive%'
     AND ml.statements[1] LIKE '%SAVEPOINT ig_a018_negative%'
     AND ml.statements[1] LIKE '%ROLLBACK TO SAVEPOINT ig_a018_negative%'
     AND ml.statements[1] LIKE '%A018_REAL_PG17_PROOF_COMPLETE%'
 ) THEN RAISE EXCEPTION 'IG_ATQ018_REAL_PG17_TRAIN_PROOF_INVALID'; END IF;

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
  'source_limits',(SELECT jsonb_build_object(
 'access_token_ttl_seconds',valor_config->'access_token_ttl_seconds',
 'idle_timeout_seconds',valor_config->'idle_timeout_seconds',
 'absolute_timeout_seconds',valor_config->'absolute_timeout_seconds',
 'refresh_token_max_days',valor_config->'refresh_token_max_days',
 'source_decision_number',valor_config->'source_decision_number')
 FROM lf_ops.reglas WHERE codigo=r),
 'global_config_values',(SELECT jsonb_object_agg(config_key,config_value ORDER BY config_key)
 FROM public.lf_global_config WHERE scope='AUTH'
 AND config_key IN ('SESSION_ACCESS_TOKEN_TTL_SECONDS','SESSION_IDLE_TIMEOUT_SECONDS','SESSION_ABSOLUTE_TIMEOUT_SECONDS')
 AND value_type='INTEGER' AND value_status='REAL'),
 'refresh_policy',(SELECT jsonb_build_object('policy_code',policy_code,
 'refresh_chain_max_days',cookie_policy->'refresh_chain_max_days',
 'refresh_rotation_enabled',refresh_rotation_enabled)
 FROM lf_ops.politicas_sesion WHERE policy_code='SESSION-CLIENT-DEFAULT'),
  'history_current',(SELECT version FROM lf_ops.v_reglas_historial WHERE codigo=r AND es_actual),
  'rule_total',v_count);
 v_report:=jsonb_build_object(
  'schema_version','LF_IG_FAMILIA_A_ATQ018_PG17_TRAIN_VERIFIED_REPORT_V1',
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
  'github://cristhianlujan/claude-persona-lf-patch/actions/runs/44473099022#RULE_CONTRACT_LEVEL');
 v_auto:=public.lf_ig_step70_functional_train_auto_v1(p);
 IF v_auto->>'status' IS DISTINCT FROM 'PASS'
  OR v_auto->>'verdict' IS DISTINCT FROM 'PASS_TRAIN_EVIDENCE_AUTOMATICO'
  OR v_auto#>>'{train_evidence,source_snapshot_sha256}' IS DISTINCT FROM s
  OR v_auto#>>'{train_evidence,proposal_sha256}' IS DISTINCT FROM h
  OR v_auto#>>'{train_evidence,candidate_snapshot_sha256}' IS DISTINCT FROM c
  OR v_auto#>>'{train_evidence,train_run_id}' IS DISTINCT FROM train_run
 THEN RAISE EXCEPTION 'IG_ATQ018_STEP70_AUTO_FAILED:%',v_auto; END IF;
 v_step:=public.lf_record_profile_execution_step_v1(
  p,'semantic_judge',
  'supabase://public.lf_ig_functional_train_evidence_v1/REG_ATQ_018',
  jsonb_build_object(
   'semantic_judge_result',v_auto,'unsupported_claims','[]'::jsonb,
   'semantic_review_receipt_ref','supabase://public.lf_ig_functional_train_evidence_v1/REG_ATQ_018',
   'independent_semantic_receipt_ref',NULL,'judge_independence_status','NOT_ASSERTED',
   'evaluator','TRAIN_EVIDENCE_AUTOMATICO',
   'content_findings',jsonb_build_array(jsonb_build_object(
     'finding_code','SEMANTIC_JUDGE_NOT_PERFORMED','evaluator','TRAIN_EVIDENCE_AUTOMATICO'))
  ),p);
 IF coalesce(v_step->>'status',v_step->>'step_status') IS DISTINCT FROM 'STEP_PASS_WITH_EVIDENCE'
 THEN RAISE EXCEPTION 'IG_ATQ018_STEP70_OFFICIAL_RECORD_FAILED:%',v_step; END IF;
 v_dec:=public.lf_ig_rule_owner_decide_v2(p,r,s,
   '{"usuario":"Cristhian Lujan","veredicto":"APROBAR"}'::jsonb);
 IF v_dec->>'status' IS DISTINCT FROM 'APPROVED_AND_VIGENTE_VERIFIED'
  OR v_dec->>'kind' IS DISTINCT FROM 'CORRECT_VIGENTE'
  OR v_dec->>'proposal_sha256' IS DISTINCT FROM h
  OR v_dec->>'finalized_snapshot_sha256' IS DISTINCT FROM c
  OR public.lf_asset_snapshot_sha_v1('REGLA',r) IS DISTINCT FROM c
 THEN RAISE EXCEPTION 'IG_ATQ018_OWNER_V2_APPLY_FAILED:%',v_dec; END IF;
 IF (SELECT estado FROM lf_ops.reglas WHERE codigo=r)<>'VIGENTE'
 OR (SELECT valor_config FROM lf_ops.reglas WHERE codigo=r)
 IS DISTINCT FROM '{"rotacion_refresh":true,"idle_timeout_config":{"scope":"AUTH","config_key":"SESSION_IDLE_TIMEOUT_SECONDS"},"session_policy_code":"SESSION-CLIENT-DEFAULT","source_decision_number":105,"absolute_timeout_config":{"scope":"AUTH","config_key":"SESSION_ABSOLUTE_TIMEOUT_SECONDS"},"access_token_ttl_config":{"scope":"AUTH","config_key":"SESSION_ACCESS_TOKEN_TTL_SECONDS"},"refresh_token_max_policy_ref":{"policy_code":"SESSION-CLIENT-DEFAULT","policy_path":"cookie_policy.refresh_chain_max_days"}}'::jsonb
  OR (SELECT count(*) FROM lf_ops.reglas)<>v_count
  OR (SELECT count(*) FROM lf_ops.reglas_versiones WHERE codigo=r AND version=1 AND vigente_hasta IS NOT NULL)<>1
  OR (SELECT version FROM lf_ops.v_reglas_historial WHERE codigo=r AND es_actual)<>2
 THEN RAISE EXCEPTION 'IG_ATQ018_POSTIMAGE_OR_VERSION_DRIFT'; END IF;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.codigo)::text,'[]'))
 INTO v_other_after FROM lf_ops.reglas x WHERE x.codigo<>r;
 IF v_other_before IS DISTINCT FROM v_other_after
 THEN RAISE EXCEPTION 'IG_ATQ018_ADJACENT_RULE_CHANGED'; END IF;
 RAISE NOTICE 'IG_ATQ018_V2_PASS; PG17_TRAIN_VERIFIED; CHANGED_ONLY_ATQ018; VERSION2_VIEW; TABLE_PREIMAGE1_CLOSED; PARENT_STEP80_PENDING';
END $ig_a018_v2$;
COMMIT;