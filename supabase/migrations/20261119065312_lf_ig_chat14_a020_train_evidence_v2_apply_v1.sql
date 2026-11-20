-- IG Familia A: CORRECT_VIGENTE REG_ATQ_020, writer V2 solamente.
-- PG17 source-bound proof: #4191, real Train 44474411286, receipt event 22056.
-- BEGIN/SAVEPOINT/ROLLBACK positivo+negativo y SELECT independiente ya se
-- verificaron en #4191; no escribir en lf_ops.reglas por UPDATE directo.
-- El reporte hash se genera de hechos y ledger verificables en esta transaccion.
-- No se declara backend E2E ni identidad humana fuerte.
BEGIN;
SET LOCAL lf.reglas_cambio_motivo='FAMILIA_A_PARAMETRIZACION_CONFIG_V2';
SET LOCAL lf.reglas_cambiado_por='IG_CHAT12_V2_MERGE_TRAIN';
DO $ig_a020_v2$
DECLARE
 p constant text:='EXEC-PROFILE-GATE2-F11127D166FAA6CFF00D9C70';
 r constant text:='REG_ATQ_020';
 s constant text:='1ff8c4a3780c816d64e7289860e920d7b3ee5f87b2abda7104a29a5c76725a75';
 h constant text:='8446fc017ac92efa1038164822c115bf1088682fbeae5e0d5d176e351f8bf708';
 c constant text:='5c1cb188df8716dbc84041b293a03fb8c18b67b2883a8ee1e9e5ce3882e82e7f';
 train constant text:='EXEC-DB-TRAIN-PR4202-20261119064728-R44474411286';
 train_run constant text:='44474411286';
 train_head constant text:='6e895d0042e4d99bf165e572ff329400b3b034d9';
 train_event constant bigint:=22056;
 receipt constant text:='e7817f739dd265faee9075ca77d8e76ac2f87046db8db7ee65b44052dfa982f2';
 test_sql constant text:='8bbdc08ddeee0dbe5f919118f61f8fe7c7d72272260777dae01fd3dba89f8c8a';
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
 AND ((g.config_key='JWT_DISTINCT_GEO_LIMIT' AND g.config_value='2')
 OR (g.config_key='JWT_GEO_WINDOW_MINUTES' AND g.config_value='10')))<>2
 OR public.lf_auth_config_integer_v1('JWT_DISTINCT_GEO_LIMIT')<>2
 OR public.lf_auth_config_integer_v1('JWT_GEO_WINDOW_MINUTES')<>10
 THEN RAISE EXCEPTION 'IG_ATQ020_BASELINE_OR_PARENT_DRIFT'; END IF;
 SELECT to_jsonb(x)-'created_at'-'updated_at' INTO v_old FROM lf_ops.reglas x WHERE x.codigo=r;
 IF v_old#>>'{valor_config,condicion}' IS DISTINCT FROM '2_geos_distintas_en_10min'
 OR v_old#>>'{valor_config,accion}' IS DISTINCT FROM 'revocar_y_forzar_reautenticacion'
 OR v_old#>>'{valor_config,notificar_usuario}' IS DISTINCT FROM 'true'
 OR position('más de 2 ubicaciones' in v_old->>'descripcion')=0
 OR position('menos de 10 minutos' in v_old->>'descripcion')=0
 THEN RAISE EXCEPTION 'IG_ATQ020_SOURCE_BEHAVIOR_DRIFT'; END IF;
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
 THEN RAISE EXCEPTION 'IG_ATQ020_PROFILE_RAW_OR_SHA_INVALID'; END IF;
 v_new:=v_old||jsonb_build_object('descripcion',v_patch#>>'{changes,descripcion}',
      'valor_config',v_patch#>'{changes,valor_config}');
 IF encode(extensions.digest(convert_to(v_new::text,'UTF8'),'sha256'),'hex') IS DISTINCT FROM c
 OR v_patch#>>'{changes,valor_config,jwt_distinct_geo_limit_config,scope}' IS DISTINCT FROM 'AUTH'
 OR v_patch#>>'{changes,valor_config,jwt_distinct_geo_limit_config,config_key}' IS DISTINCT FROM 'JWT_DISTINCT_GEO_LIMIT'
 OR v_patch#>>'{changes,valor_config,jwt_geo_window_config,scope}' IS DISTINCT FROM 'AUTH'
 OR v_patch#>>'{changes,valor_config,jwt_geo_window_config,config_key}' IS DISTINCT FROM 'JWT_GEO_WINDOW_MINUTES'
 OR v_patch#>>'{changes,valor_config,comparador_geos}' IS DISTINCT FROM 'SUPERA_MAXIMO'
 OR v_patch#>>'{changes,valor_config,comparador_ventana}' IS DISTINCT FROM 'MENOR_QUE_VENTANA'
 OR v_patch#>>'{changes,valor_config,accion}' IS DISTINCT FROM 'revocar_y_forzar_reautenticacion'
 OR v_patch#>>'{changes,valor_config,notificar_usuario}' IS DISTINCT FROM 'true'
 OR (v_patch#>'{changes,valor_config}')?'condicion'
 THEN RAISE EXCEPTION 'IG_ATQ020_CANDIDATE_OR_REF_INVALID'; END IF;

 IF NOT EXISTS(
   SELECT 1 FROM public.lf_operation_execution te
   JOIN public.lf_eventos evt ON evt.entidad_codigo=te.execution_id
      AND evt.evento_tipo='MIGRATION_TRAIN_RECEIPT_RECORDED'
      AND evt.origen='lf-migration-merge-train'
   JOIN supabase_migrations.schema_migrations ml
      ON ml.version='20261119064728'
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
     AND ml.name='lf_ig_chat14_a020_pg17_rule_contract_v1'
     AND encode(extensions.digest(convert_to(ml.statements[1],'UTF8'),'sha256'),'hex')=test_sql
     AND ml.statements[1] LIKE '%SAVEPOINT ig_a020_positive%'
     AND ml.statements[1] LIKE '%ROLLBACK TO SAVEPOINT ig_a020_positive%'
     AND ml.statements[1] LIKE '%SAVEPOINT ig_a020_negative%'
     AND ml.statements[1] LIKE '%ROLLBACK TO SAVEPOINT ig_a020_negative%'
     AND ml.statements[1] LIKE '%A020_REAL_PG17_PROOF_COMPLETE%'
 ) THEN RAISE EXCEPTION 'IG_ATQ020_REAL_PG17_TRAIN_PROOF_INVALID'; END IF;

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
 'legacy_condicion',valor_config->'condicion',
 'accion',valor_config->'accion',
 'notificar_usuario',valor_config->'notificar_usuario')
 FROM lf_ops.reglas WHERE codigo=r),
 'global_config_values',(SELECT jsonb_object_agg(config_key,config_value ORDER BY config_key)
 FROM public.lf_global_config WHERE scope='AUTH'
 AND config_key IN ('JWT_DISTINCT_GEO_LIMIT','JWT_GEO_WINDOW_MINUTES')
 AND value_type='INTEGER' AND value_status='REAL'),
  'history_current',(SELECT version FROM lf_ops.v_reglas_historial WHERE codigo=r AND es_actual),
  'rule_total',v_count);
 v_report:=jsonb_build_object(
  'schema_version','LF_IG_FAMILIA_A_ATQ020_PG17_TRAIN_VERIFIED_REPORT_V1',
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
  'github://cristhianlujan/claude-persona-lf-patch/actions/runs/44474411286#RULE_CONTRACT_LEVEL');
 v_auto:=public.lf_ig_step70_functional_train_auto_v1(p);
 IF v_auto->>'status' IS DISTINCT FROM 'PASS'
  OR v_auto->>'verdict' IS DISTINCT FROM 'PASS_TRAIN_EVIDENCE_AUTOMATICO'
  OR v_auto#>>'{train_evidence,source_snapshot_sha256}' IS DISTINCT FROM s
  OR v_auto#>>'{train_evidence,proposal_sha256}' IS DISTINCT FROM h
  OR v_auto#>>'{train_evidence,candidate_snapshot_sha256}' IS DISTINCT FROM c
  OR v_auto#>>'{train_evidence,train_run_id}' IS DISTINCT FROM train_run
 THEN RAISE EXCEPTION 'IG_ATQ020_STEP70_AUTO_FAILED:%',v_auto; END IF;
 v_step:=public.lf_record_profile_execution_step_v1(
  p,'semantic_judge',
  'supabase://public.lf_ig_functional_train_evidence_v1/REG_ATQ_020',
  jsonb_build_object(
   'semantic_judge_result',v_auto,'unsupported_claims','[]'::jsonb,
   'semantic_review_receipt_ref','supabase://public.lf_ig_functional_train_evidence_v1/REG_ATQ_020',
   'independent_semantic_receipt_ref',NULL,'judge_independence_status','NOT_ASSERTED',
   'evaluator','TRAIN_EVIDENCE_AUTOMATICO',
   'content_findings',jsonb_build_array(jsonb_build_object(
     'finding_code','SEMANTIC_JUDGE_NOT_PERFORMED','evaluator','TRAIN_EVIDENCE_AUTOMATICO'))
  ),p);
 IF coalesce(v_step->>'status',v_step->>'step_status') IS DISTINCT FROM 'STEP_PASS_WITH_EVIDENCE'
 THEN RAISE EXCEPTION 'IG_ATQ020_STEP70_OFFICIAL_RECORD_FAILED:%',v_step; END IF;
 v_dec:=public.lf_ig_rule_owner_decide_v2(p,r,s,
   '{"usuario":"Cristhian Lujan","veredicto":"APROBAR"}'::jsonb);
 IF v_dec->>'status' IS DISTINCT FROM 'APPROVED_AND_VIGENTE_VERIFIED'
  OR v_dec->>'kind' IS DISTINCT FROM 'CORRECT_VIGENTE'
  OR v_dec->>'proposal_sha256' IS DISTINCT FROM h
  OR v_dec->>'finalized_snapshot_sha256' IS DISTINCT FROM c
  OR public.lf_asset_snapshot_sha_v1('REGLA',r) IS DISTINCT FROM c
 THEN RAISE EXCEPTION 'IG_ATQ020_OWNER_V2_APPLY_FAILED:%',v_dec; END IF;
 IF (SELECT estado FROM lf_ops.reglas WHERE codigo=r)<>'VIGENTE'
 OR (SELECT valor_config FROM lf_ops.reglas WHERE codigo=r)
 IS DISTINCT FROM '{"accion":"revocar_y_forzar_reautenticacion","comparador_geos":"SUPERA_MAXIMO","notificar_usuario":true,"comparador_ventana":"MENOR_QUE_VENTANA","jwt_geo_window_config":{"scope":"AUTH","config_key":"JWT_GEO_WINDOW_MINUTES"},"jwt_distinct_geo_limit_config":{"scope":"AUTH","config_key":"JWT_DISTINCT_GEO_LIMIT"}}'::jsonb
  OR (SELECT count(*) FROM lf_ops.reglas)<>v_count
  OR (SELECT count(*) FROM lf_ops.reglas_versiones WHERE codigo=r AND version=1 AND vigente_hasta IS NOT NULL)<>1
  OR (SELECT version FROM lf_ops.v_reglas_historial WHERE codigo=r AND es_actual)<>2
 THEN RAISE EXCEPTION 'IG_ATQ020_POSTIMAGE_OR_VERSION_DRIFT'; END IF;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.codigo)::text,'[]'))
 INTO v_other_after FROM lf_ops.reglas x WHERE x.codigo<>r;
 IF v_other_before IS DISTINCT FROM v_other_after
 THEN RAISE EXCEPTION 'IG_ATQ020_ADJACENT_RULE_CHANGED'; END IF;
 RAISE NOTICE 'IG_ATQ020_V2_PASS; PG17_TRAIN_VERIFIED; CHANGED_ONLY_ATQ020; VERSION2_VIEW; TABLE_PREIMAGE1_CLOSED; PARENT_STEP80_PENDING';
END $ig_a020_v2$;
COMMIT;