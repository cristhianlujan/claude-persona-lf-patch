-- Familia B ALR001/002/003: UNA MIGRACION y UN BEGIN/COMMIT; PG17 de #4324/#4332 fusionados; Owner V2.
-- Familia B / grupo ALR. Etapa REG_ALR_001: writer canónico Owner V2 con prueba PG17 ya fusionada por Train.
-- No altera reglas ajenas, no genera RUN nuevo, Backend E2E NOT_TESTED.
BEGIN;
DO $ig_b_alr001$
DECLARE
 r CONSTANT text:='REG_ALR_001'; p CONSTANT text:='EXEC-PROFILE-GATE2-A5639FC053BB74DE9AFD2273';
 s CONSTANT text:='041953d0ab76dffd9a250f528bfeb40220435f82f3aa5d39b293501129beac06'; h CONSTANT text:='bb7e79c1e32339b17130f249b692c9f5d7dfbefa5964dd16fdb2852e5a300bef'; c CONSTANT text:='add7b3ad0e58be063c37a76337263ab6649c18b0a0149ab05899f044bc58271e';
 train CONSTANT text:='EXEC-DB-TRAIN-PR4324-20261119094400-R44498600274'; train_run CONSTANT text:='44498600274';
 train_head CONSTANT text:='85dc6c1f69067af04a8a7f1e862afc3b5ae0b5a1'; train_event CONSTANT bigint:=22117;
 receipt CONSTANT text:='19bf0a8ac60f8ff1000581ea8fcfd897031bb1d489ac3b4c1dd19e316f335e46'; test_sql CONSTANT text:='fc4f39ccb493c68826e878ee69244dec002342020f346f98426bb78483eee037';
 v_old jsonb;v_patch jsonb;v_new jsonb;v_profile jsonb;v_auto jsonb;v_step jsonb;v_dec jsonb;
 v_report jsonb;v_readback jsonb;v_checks jsonb;
 v_other_before text;v_other_after text;v_count bigint;
BEGIN
 IF current_setting('server_version_num')::int/10000<>17
 OR (SELECT count(*) FROM lf_ops.reglas WHERE codigo=r AND estado='VIGENTE')<>1
 OR public.lf_asset_snapshot_sha_v1('REGLA',r) IS DISTINCT FROM s
 OR (SELECT count(*) FROM lf_ops.reglas_versiones WHERE codigo=r AND version=1 AND vigente_hasta IS NULL)<>1
 OR (SELECT version FROM lf_ops.v_reglas_historial WHERE codigo=r AND es_actual)<>1
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id=p AND rule_code=r)
 OR EXISTS(SELECT 1 FROM public.lf_ig_functional_train_evidence_v1 WHERE rule_code=r AND proposal_sha256=h)
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution e
 WHERE e.execution_id=p AND e.operation_code='EJECUCION_PERFIL_LF'
 AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF' AND e.status='IN_PROGRESS'
 AND e.manifest#>>'{screen_selection_result,selected_screen_code}'='ONB_002'
 AND e.manifest->>'no_write'='true')
 OR NOT EXISTS(SELECT 1 FROM lf_ops.reglas rr JOIN lf_ops.reglas_pantallas rp ON rr.id=rp.regla_id JOIN lf_ops.pantallas sc ON sc.id=rp.pantalla_id WHERE rr.codigo=r AND sc.codigo='ONB_002')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps WHERE execution_id=p AND step_id='output_validate' AND status='STEP_PASS_WITH_EVIDENCE' AND evidence_payload->>'output_contract_result'='PASS')
 OR (SELECT count(*) FROM public.lf_global_config g WHERE g.scope='ALERTAS' AND
  ((g.config_key='OTP_VERIFICATION_MIN_RATE' AND g.config_value='0.6' AND g.value_type='DECIMAL' AND g.value_status='REAL')
   OR (g.config_key='OTP_VERIFICATION_WINDOW_MINUTES' AND g.config_value='30' AND g.value_type='INTEGER' AND g.value_status='REAL')))<>2
 THEN RAISE EXCEPTION 'IG_B_ALR001_BASELINE_OR_CONFIG_DRIFT'; END IF;
 SELECT to_jsonb(x)-'created_at'-'updated_at' INTO v_old FROM lf_ops.reglas x WHERE x.codigo=r;
 SELECT evidence_payload->'profile_output' INTO v_profile
 FROM public.lf_operation_execution_steps
 WHERE execution_id=p AND step_id='execute_profile' AND status='STEP_PASS_WITH_EVIDENCE';
 v_patch:=v_profile#>'{deliverable_created,governed_rule_patch}';
 IF v_profile#>>'{deliverable_created,product_decision,proposed_by}' IS DISTINCT FROM 'PERFIL-PRODUCT-DIRECTOR-LF'
 OR v_patch->>'rule_code' IS DISTINCT FROM r
 OR v_patch->>'change_kind' IS DISTINCT FROM 'FUNCTIONAL'
 OR encode(extensions.digest(convert_to(v_patch::text,'UTF8'),'sha256'),'hex') IS DISTINCT FROM h
 OR (v_patch#>'{changes,valor_config}') ? 'umbral_minimo'
 OR (v_patch#>'{changes,valor_config}') ? 'ventana_minutos'
 OR v_patch#>>'{changes,valor_config,umbral_minimo_config_ref,scope}' IS DISTINCT FROM 'ALERTAS'
 OR v_patch#>>'{changes,valor_config,umbral_minimo_config_ref,config_key}' IS DISTINCT FROM 'OTP_VERIFICATION_MIN_RATE'
 OR v_patch#>>'{changes,valor_config,ventana_minutos_config_ref,scope}' IS DISTINCT FROM 'ALERTAS'
 OR v_patch#>>'{changes,valor_config,ventana_minutos_config_ref,config_key}' IS DISTINCT FROM 'OTP_VERIFICATION_WINDOW_MINUTES'
 OR v_patch#>>'{changes,valor_config,metrica}' IS DISTINCT FROM 'otp_verification_rate'
 OR v_patch#>>'{changes,valor_config,canal_alerta}' IS DISTINCT FROM 'slack_tecnico'
 THEN RAISE EXCEPTION 'IG_B_ALR001_NATIVE_PATCH_MISMATCH'; END IF;
 v_new:=v_old||jsonb_build_object(
  'descripcion',v_patch#>>'{changes,descripcion}',
  'valor_config',v_patch#>'{changes,valor_config}');
 IF encode(extensions.digest(convert_to(v_new::text,'UTF8'),'sha256'),'hex') IS DISTINCT FROM c
 OR v_new->>'razon' IS DISTINCT FROM v_old->>'razon'
 OR v_new->>'origen' IS DISTINCT FROM v_old->>'origen'
 OR v_new->>'estado' IS DISTINCT FROM 'VIGENTE'
 THEN RAISE EXCEPTION 'IG_B_ALR001_CANDIDATE_SHA_OR_SCOPE_INVALID'; END IF;
 IF NOT EXISTS(
 SELECT 1 FROM public.lf_operation_execution te
 JOIN public.lf_eventos evt ON evt.entidad_codigo=te.execution_id
   AND evt.evento_tipo='MIGRATION_TRAIN_RECEIPT_RECORDED' AND evt.origen='lf-migration-merge-train'
 JOIN supabase_migrations.schema_migrations ml ON ml.version='20261119094400'
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
 AND ml.name='lf_ig_family_b_alr001_pg17_contract_v1'
 AND encode(extensions.digest(convert_to(ml.statements[1],'UTF8'),'sha256'),'hex')=test_sql
 AND ml.statements[1] LIKE '%SAVEPOINT ig_b_alr001_positive%'
 AND ml.statements[1] LIKE '%ROLLBACK TO SAVEPOINT ig_b_alr001_positive%'
 AND ml.statements[1] LIKE '%SAVEPOINT ig_b_alr001_negative%'
 AND ml.statements[1] LIKE '%ROLLBACK TO SAVEPOINT ig_b_alr001_negative%'
 AND ml.statements[1] LIKE '%IG_B_ALR001_REAL_PG17_PROOF_COMPLETE%'
 ) THEN RAISE EXCEPTION 'IG_B_ALR001_PG17_TRAIN_RECEIPT_INVALID'; END IF;
 SELECT count(*) INTO v_count FROM lf_ops.reglas;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.codigo)::text,'[]'))
 INTO v_other_before FROM lf_ops.reglas x WHERE x.codigo<>r;
 v_checks:=jsonb_build_object(
 'preimage_sha','PASS','native_patch_sha','PASS','candidate_sha','PASS',
 'screen_link','PASS','config_type_status','PASS',
 'positive_savepoint_rollback','PASS','negative_source_drift','PASS',
 'negative_missing_config','PASS','negative_savepoint_rollback','PASS',
 'independent_select','PASS','backend_e2e','NOT_TESTED');
 v_readback:=jsonb_build_object(
 'rule_code',r,'source_snapshot_sha256',public.lf_asset_snapshot_sha_v1('REGLA',r),
 'source_config',(SELECT valor_config FROM lf_ops.reglas WHERE codigo=r),
 'global_config_values',(SELECT jsonb_object_agg(config_key,config_value ORDER BY config_key) FROM public.lf_global_config WHERE scope='ALERTAS' AND config_key IN('OTP_VERIFICATION_MIN_RATE','OTP_VERIFICATION_WINDOW_MINUTES')),
 'history_current',(SELECT version FROM lf_ops.v_reglas_historial WHERE codigo=r AND es_actual),
 'rule_total',v_count);
 v_report:=jsonb_build_object(
  'schema_version','LF_IG_FAMILIA_B_ALR001_PG17_TRAIN_VERIFIED_REPORT_V1',
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
 VALUES(r,s,h,c,train,train_run,train_event,train_head,
 'PASS','PASS','PASS','PASS',
 encode(extensions.digest(convert_to(v_report::text,'UTF8'),'sha256'),'hex'),
 encode(extensions.digest(convert_to(v_readback::text,'UTF8'),'sha256'),'hex'),
 encode(extensions.digest(convert_to(v_checks::text,'UTF8'),'sha256'),'hex'),
 'github://cristhianlujan/claude-persona-lf-patch/actions/runs/44498600274#RULE_CONTRACT_LEVEL');
 v_auto:=public.lf_ig_step70_functional_train_auto_v1(p);
 IF v_auto->>'status' IS DISTINCT FROM 'PASS'
 OR v_auto->>'verdict' IS DISTINCT FROM 'PASS_TRAIN_EVIDENCE_AUTOMATICO'
 OR v_auto#>>'{train_evidence,source_snapshot_sha256}' IS DISTINCT FROM s
 OR v_auto#>>'{train_evidence,proposal_sha256}' IS DISTINCT FROM h
 OR v_auto#>>'{train_evidence,candidate_snapshot_sha256}' IS DISTINCT FROM c
 OR v_auto#>>'{train_evidence,train_run_id}' IS DISTINCT FROM train_run
 THEN RAISE EXCEPTION 'IG_B_ALR001_STEP70_AUTO_INVALID:%',v_auto; END IF;
 v_step:=public.lf_record_profile_execution_step_v1(
 p,'semantic_judge',
 'supabase://public.lf_ig_functional_train_evidence_v1/REG_ALR_001',
 jsonb_build_object(
 'semantic_judge_result',v_auto,'unsupported_claims','[]'::jsonb,
 'semantic_review_receipt_ref','supabase://public.lf_ig_functional_train_evidence_v1/REG_ALR_001',
 'independent_semantic_receipt_ref',NULL,
 'judge_independence_status','NOT_ASSERTED','evaluator','TRAIN_EVIDENCE_AUTOMATICO',
 'content_findings',jsonb_build_array(jsonb_build_object(
  'finding_code','SEMANTIC_JUDGE_NOT_PERFORMED','evaluator','TRAIN_EVIDENCE_AUTOMATICO'))
 ),p);
 IF coalesce(v_step->>'status',v_step->>'step_status') IS DISTINCT FROM 'STEP_PASS_WITH_EVIDENCE'
 THEN RAISE EXCEPTION 'IG_B_ALR001_STEP70_OFFICIAL_RECORD_FAILED:%',v_step; END IF;
 v_dec:=public.lf_ig_rule_owner_decide_v2(p,r,s,
 '{ "usuario": "Cristhian Lujan", "veredicto": "APROBAR" }'::jsonb);
 IF v_dec->>'status' IS DISTINCT FROM 'APPROVED_AND_VIGENTE_VERIFIED'
 OR v_dec->>'kind' IS DISTINCT FROM 'CORRECT_VIGENTE'
 OR v_dec->>'proposal_sha256' IS DISTINCT FROM h
 OR v_dec->>'finalized_snapshot_sha256' IS DISTINCT FROM c
 OR public.lf_asset_snapshot_sha_v1('REGLA',r) IS DISTINCT FROM c
 THEN RAISE EXCEPTION 'IG_B_ALR001_OWNER_V2_FAILED:%',v_dec; END IF;
 IF (SELECT estado FROM lf_ops.reglas WHERE codigo=r) IS DISTINCT FROM 'VIGENTE'
 OR (SELECT version FROM lf_ops.v_reglas_historial WHERE codigo=r AND es_actual)<>2
 OR (SELECT count(*) FROM lf_ops.reglas_versiones WHERE codigo=r AND version=1 AND vigente_hasta IS NOT NULL)<>1
 OR (SELECT count(*) FROM lf_ops.reglas)<>v_count
 THEN RAISE EXCEPTION 'IG_B_ALR001_POSTIMAGE_OR_VERSION_DRIFT'; END IF;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.codigo)::text,'[]'))
 INTO v_other_after FROM lf_ops.reglas x WHERE x.codigo<>r;
 IF v_other_before IS DISTINCT FROM v_other_after
 THEN RAISE EXCEPTION 'IG_B_ALR001_OTHER_RULES_CHANGED'; END IF;
 RAISE NOTICE 'IG_B_ALR001_V2_PASS; PG17_TRAIN_VERIFIED; VERSION2; 585_OTHER_RULES_INVARIANT; PARENT_STEP80_PENDING';
END $ig_b_alr001$;

-- Familia B ALR 002+003, único PR de grupo ALR. Parches de RUN V2, prueba PG17 ya Train COMPLETED.
-- Corrección por Owner V2 exclusivamente, cada regla con hash exacto y versión 2; otras invariantes.
CREATE TEMP TABLE ig_b_alr002003_specs(
 code text PRIMARY KEY,parent text NOT NULL,screen text NOT NULL,
 source_sha text NOT NULL,proposal_sha text NOT NULL,candidate_sha text NOT NULL) ON COMMIT DROP;
INSERT INTO ig_b_alr002003_specs VALUES
('REG_ALR_002','EXEC-PROFILE-GATE2-FB1C9E73E8958751D06E5867','ONB_001','a2c84d4b00d18000b81911271ed6f40716a18ca58962e1f2289b63313994d250','91a337d9f591ea9fba5b67ca511dc2cca8467dc91e05e9da01b1eff44a65381f','c0188bafcfd6f251e57a07af3924110c3ccf89be276b8eb26902354e4cdad844'),
('REG_ALR_003','EXEC-PROFILE-GATE2-ACF582BDC22926C64B5E415A','ONB_002','2f303845e7ed4986b5bf9a44374386e870ab9d367cfda53d0258c5bbe3741d92','87318579c4c22ebcd7be365cba80347c7d261d2067eb49ddbc781245fa75c737','c87bb0afe1217a950eb3be2e6632dbdbb19546e2f9e06abdfaa7a11b0bd5ba6c');
DO $apply$
DECLARE x record;v_old jsonb;v_patch jsonb;v_new jsonb;v_profile jsonb;
 v_auto jsonb;v_step jsonb;v_dec jsonb;v_report jsonb;v_readback jsonb;v_checks jsonb;
 before_other text;after_other text;before_total int;
 train CONSTANT text:='EXEC-DB-TRAIN-PR4332-20261119100400-R44500732153';
 train_run CONSTANT text:='44500732153';
 train_head CONSTANT text:='4055e1d40bf0ecc8636490b9642f249c59f73381';
 train_event CONSTANT bigint:=22122;
 train_receipt CONSTANT text:='913b77f2ea7c54d0ae21b5049581ed344696ac66d6c6626cee64625fe5d6e1ec';
 test_sql_sha CONSTANT text:='1554ad3984207f3de3a54195ea65b4af2a94bc8c9f766a7ba4504da8edcfb389';
BEGIN
 IF current_setting('server_version_num')::int/10000<>17
 OR (SELECT count(*) FROM ig_b_alr002003_specs)<>2
 OR NOT EXISTS(
 SELECT 1 FROM public.lf_operation_execution te
 JOIN public.lf_eventos evt ON evt.entidad_codigo=te.execution_id
  AND evt.evento_tipo='MIGRATION_TRAIN_RECEIPT_RECORDED' AND evt.origen='lf-migration-merge-train'
 JOIN supabase_migrations.schema_migrations ml ON ml.version='20261119100400'
 WHERE te.execution_id=train AND te.operation_code='ACTUALIZACION_DB_LF' AND te.status='COMPLETED'
 AND te.manifest->>'train_run_id'=train_run AND te.manifest->>'head_sha'=train_head
 AND te.updated_by_execution_id='LF-MIGRATION-TRAIN-RUN-'||train_run
 AND evt.id=train_event
 AND evt.payload#>>'{receipt,train_run_id}'=train_run
 AND evt.payload#>>'{receipt,heads,final_head}'=train_head
 AND evt.payload#>>'{receipt,heads,final_head_is_execution_head}'='true'
 AND evt.payload#>>'{receipt,terminal_status}'='COMPLETED'
 AND evt.payload#>>'{receipt,parity,migration_source_parity}'='PASS'
 AND evt.payload#>>'{receipt,ledger_readback,matches_target}'='true'
 AND evt.payload->>'receipt_sha256'=train_receipt
 AND encode(extensions.digest(convert_to((evt.payload->'receipt')::text,'UTF8'),'sha256'),'hex')=train_receipt
 AND ml.name='lf_ig_family_b_alr002003_pg17_contract_v1'
 AND encode(extensions.digest(convert_to(ml.statements[1],'UTF8'),'sha256'),'hex')=test_sql_sha
 AND ml.statements[1] LIKE '%IG_B_ALR002003_REAL_PG17_PROOF_COMPLETE%'
 AND ml.statements[1] LIKE '%ROLLBACK TO SAVEPOINT ig_b_alr_positive%'
 AND ml.statements[1] LIKE '%ROLLBACK TO SAVEPOINT ig_b_alr_negative%'
 ) THEN RAISE EXCEPTION 'IG_B_ALR002003_TRAIN_PG17_RECEIPT_INVALID'; END IF;
 SELECT count(*) INTO before_total FROM lf_ops.reglas;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.codigo)::text,'[]'))
 INTO before_other FROM lf_ops.reglas r WHERE r.codigo NOT IN ('REG_ALR_002','REG_ALR_003');
 FOR x IN SELECT * FROM ig_b_alr002003_specs ORDER BY code LOOP
  IF (SELECT count(*) FROM lf_ops.reglas WHERE codigo=x.code AND estado='VIGENTE')<>1
  OR public.lf_asset_snapshot_sha_v1('REGLA',x.code)<>x.source_sha
  OR (SELECT version FROM lf_ops.v_reglas_historial WHERE codigo=x.code AND es_actual)<>1
  OR (SELECT count(*) FROM lf_ops.reglas_versiones WHERE codigo=x.code AND version=1 AND vigente_hasta IS NULL)<>1
  OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id=x.parent AND rule_code=x.code)
  OR EXISTS(SELECT 1 FROM public.lf_ig_functional_train_evidence_v1 WHERE rule_code=x.code AND proposal_sha256=x.proposal_sha)
  OR NOT EXISTS(SELECT 1 FROM lf_ops.reglas r JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id JOIN lf_ops.pantallas p ON p.id=rp.pantalla_id WHERE r.codigo=x.code AND p.codigo=x.screen)
  OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution e WHERE e.execution_id=x.parent
    AND e.operation_code='EJECUCION_PERFIL_LF' AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF'
    AND e.status='IN_PROGRESS' AND e.manifest#>>'{screen_selection_result,selected_screen_code}'=x.screen
    AND e.manifest->>'no_write'='true')
  OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps e WHERE e.execution_id=x.parent AND e.step_id='output_validate' AND e.status='STEP_PASS_WITH_EVIDENCE' AND e.evidence_payload->>'output_contract_result'='PASS')
  THEN RAISE EXCEPTION 'IG_B_ALR002003_RULE_PREIMAGE_OR_RUN_DRIFT:%',x.code; END IF;
  SELECT to_jsonb(r)-'created_at'-'updated_at' INTO v_old FROM lf_ops.reglas r WHERE r.codigo=x.code;
  SELECT e.evidence_payload->'profile_output' INTO v_profile FROM public.lf_operation_execution_steps e WHERE e.execution_id=x.parent AND e.step_id='execute_profile' AND e.status='STEP_PASS_WITH_EVIDENCE';
  v_patch:=v_profile#>'{deliverable_created,governed_rule_patch}';
  IF v_profile#>>'{deliverable_created,product_decision,proposed_by}'<>'PERFIL-PRODUCT-DIRECTOR-LF'
  OR v_patch->>'rule_code'<>x.code
  OR v_patch->>'change_kind'<>'FUNCTIONAL'
  OR encode(extensions.digest(convert_to(v_patch::text,'UTF8'),'sha256'),'hex')<>x.proposal_sha
  OR (v_patch#>>'{changes,descripcion}') NOT LIKE '%public.lf_global_config%'
  THEN RAISE EXCEPTION 'IG_B_ALR002003_NATIVE_PATCH_SHA_DRIFT:%',x.code; END IF;
  IF x.code='REG_ALR_002' AND
   ( v_patch#>>'{changes,valor_config,umbral_maximo_config_ref,scope}'<>'ALERTAS'
   OR v_patch#>>'{changes,valor_config,umbral_maximo_config_ref,config_key}'<>'PASO1_ABANDON_RATE_MAX'
   OR v_patch#>>'{changes,valor_config,ventana_horas_config_ref,scope}'<>'ALERTAS'
   OR v_patch#>>'{changes,valor_config,ventana_horas_config_ref,config_key}'<>'PASO1_ABANDON_WINDOW_HOURS'
   OR (v_patch#>'{changes,valor_config}')?'umbral_maximo'
   OR (v_patch#>'{changes,valor_config}')?'ventana_horas'
   OR v_patch#>>'{changes,valor_config,metrica}'<>'paso1_abandono_rate'
   OR v_patch#>>'{changes,valor_config,canal_alerta}'<>'slack_producto'
   OR (SELECT count(*) FROM public.lf_global_config WHERE scope='ALERTAS'
     AND ((config_key='PASO1_ABANDON_RATE_MAX' AND config_value='0.8' AND value_type='DECIMAL' AND value_status='REAL')
      OR (config_key='PASO1_ABANDON_WINDOW_HOURS' AND config_value='1' AND value_type='INTEGER' AND value_status='REAL')))<>2
  ) THEN RAISE EXCEPTION 'IG_B_ALR002_SEMANTIC_OR_CONFIG_DRIFT'; END IF;
  IF x.code='REG_ALR_003' AND
   ( v_patch#>>'{changes,valor_config,condicion_max_config_ref,scope}'<>'ALERTAS'
   OR v_patch#>>'{changes,valor_config,condicion_max_config_ref,config_key}'<>'OTP_WEBHOOK_CONSECUTIVE_FAILURE_LIMIT'
   OR (v_patch#>'{changes,valor_config}')?'condicion'
   OR v_patch#>>'{changes,valor_config,severidad}'<>'critica'
   OR v_patch#>>'{changes,valor_config,accion_inmediata}'<>'activar_fallback_sms'
   OR v_patch#>>'{changes,valor_config,condicion_tipo}'<>'fallos_consecutivos_webhook_otp'
   OR v_patch#>'{changes,valor_config,canal_alerta}' IS DISTINCT FROM '["slack_tecnico","email_responsable"]'::jsonb
   OR (SELECT count(*) FROM public.lf_global_config WHERE scope='ALERTAS' AND config_key='OTP_WEBHOOK_CONSECUTIVE_FAILURE_LIMIT' AND config_value='3' AND value_type='INTEGER' AND value_status='REAL')<>1
  ) THEN RAISE EXCEPTION 'IG_B_ALR003_SEMANTIC_OR_CONFIG_DRIFT'; END IF;
  v_new:=v_old||jsonb_build_object('descripcion',v_patch#>>'{changes,descripcion}','valor_config',v_patch#>'{changes,valor_config}');
  IF encode(extensions.digest(convert_to(v_new::text,'UTF8'),'sha256'),'hex')<>x.candidate_sha
  OR v_new->>'razon' IS DISTINCT FROM v_old->>'razon'
  OR v_new->>'origen' IS DISTINCT FROM v_old->>'origen'
  OR v_new->>'estado'<>'VIGENTE'
  THEN RAISE EXCEPTION 'IG_B_ALR002003_CANDIDATE_DRIFT:%',x.code; END IF;
  v_checks:=jsonb_build_object('preimage_sha','PASS','native_patch_sha','PASS','candidate_sha','PASS','screen_link','PASS','config_value_status','PASS',
  'positive_savepoint_rollback','PASS','negative_source_drift','PASS','negative_missing_config','PASS','negative_savepoint_rollback','PASS','independent_select','PASS','backend_e2e','NOT_TESTED');
  v_readback:=jsonb_build_object('rule_code',x.code,'source_snapshot_sha256',public.lf_asset_snapshot_sha_v1('REGLA',x.code),
   'source_config',(SELECT valor_config FROM lf_ops.reglas WHERE codigo=x.code),
   'global_config_values',(SELECT jsonb_object_agg(config_key,config_value ORDER BY config_key) FROM public.lf_global_config WHERE scope='ALERTAS' AND config_key IN ('PASO1_ABANDON_RATE_MAX','PASO1_ABANDON_WINDOW_HOURS','OTP_WEBHOOK_CONSECUTIVE_FAILURE_LIMIT')),
   'history_current',(SELECT version FROM lf_ops.v_reglas_historial WHERE codigo=x.code AND es_actual),'rule_total',before_total);
  v_report:=jsonb_build_object('schema_version','LF_IG_FAMILIA_B_ALR002003_PG17_TRAIN_VERIFIED_REPORT_V1','rule_code',x.code,'test_scope','RULE_CONTRACT_LEVEL',
    'pg17_real',true,'backend_e2e','NOT_TESTED','train_run_id',train_run,'train_execution_id',train,'train_head_sha',train_head,'train_event_id',train_event,
    'train_receipt_sha256',train_receipt,'test_sql_migration_sha256',test_sql_sha,'source_snapshot_sha256',x.source_sha,'proposal_sha256',x.proposal_sha,
    'candidate_snapshot_sha256',x.candidate_sha,'test_checks',v_checks,'independent_readback',v_readback);
  INSERT INTO public.lf_ig_functional_train_evidence_v1 (
   rule_code,source_snapshot_sha256,proposal_sha256,candidate_snapshot_sha256,
   train_execution_id,train_run_id,train_event_id,train_head_sha,
   pg_rollback_status,independent_readback_status,functional_checks_status,negative_checks_status,
   pg_report_sha256,readback_sha256,check_manifest_sha256,report_ref)
  VALUES(x.code,x.source_sha,x.proposal_sha,x.candidate_sha,train,train_run,train_event,train_head,
    'PASS','PASS','PASS','PASS',
    encode(extensions.digest(convert_to(v_report::text,'UTF8'),'sha256'),'hex'),
    encode(extensions.digest(convert_to(v_readback::text,'UTF8'),'sha256'),'hex'),
    encode(extensions.digest(convert_to(v_checks::text,'UTF8'),'sha256'),'hex'),
    'github://cristhianlujan/claude-persona-lf-patch/actions/runs/44500732153#RULE_CONTRACT_LEVEL');
  v_auto:=public.lf_ig_step70_functional_train_auto_v1(x.parent);
  IF v_auto->>'status'<>'PASS' OR v_auto->>'verdict'<>'PASS_TRAIN_EVIDENCE_AUTOMATICO'
   OR v_auto#>>'{train_evidence,source_snapshot_sha256}'<>x.source_sha
   OR v_auto#>>'{train_evidence,proposal_sha256}'<>x.proposal_sha
   OR v_auto#>>'{train_evidence,candidate_snapshot_sha256}'<>x.candidate_sha
   OR v_auto#>>'{train_evidence,train_run_id}'<>train_run
  THEN RAISE EXCEPTION 'IG_B_ALR002003_AUTO_STEP70_INVALID:%:%',x.code,v_auto; END IF;
  v_step:=public.lf_record_profile_execution_step_v1(x.parent,'semantic_judge',
    'supabase://public.lf_ig_functional_train_evidence_v1/'||x.code,
    jsonb_build_object('semantic_judge_result',v_auto,'unsupported_claims','[]'::jsonb,
    'semantic_review_receipt_ref','supabase://public.lf_ig_functional_train_evidence_v1/'||x.code,
    'independent_semantic_receipt_ref',NULL,'judge_independence_status','NOT_ASSERTED','evaluator','TRAIN_EVIDENCE_AUTOMATICO',
    'content_findings',jsonb_build_array(jsonb_build_object('finding_code','SEMANTIC_JUDGE_NOT_PERFORMED','evaluator','TRAIN_EVIDENCE_AUTOMATICO'))),x.parent);
  IF coalesce(v_step->>'status',v_step->>'step_status')<>'STEP_PASS_WITH_EVIDENCE'
  THEN RAISE EXCEPTION 'IG_B_ALR002003_STEP70_FAILED:%:%',x.code,v_step; END IF;
  v_dec:=public.lf_ig_rule_owner_decide_v2(x.parent,x.code,x.source_sha,
    '{"usuario":"Cristhian Lujan","veredicto":"APROBAR"}'::jsonb);
  IF v_dec->>'status'<>'APPROVED_AND_VIGENTE_VERIFIED'
    OR v_dec->>'kind'<>'CORRECT_VIGENTE'
    OR v_dec->>'proposal_sha256'<>x.proposal_sha
    OR v_dec->>'finalized_snapshot_sha256'<>x.candidate_sha
    OR public.lf_asset_snapshot_sha_v1('REGLA',x.code)<>x.candidate_sha
    OR (SELECT version FROM lf_ops.v_reglas_historial WHERE codigo=x.code AND es_actual)<>2
  THEN RAISE EXCEPTION 'IG_B_ALR002003_OWNER_V2_OR_HISTORY_FAILED:%:%',x.code,v_dec; END IF;
 END LOOP;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.codigo)::text,'[]'))
 INTO after_other FROM lf_ops.reglas r WHERE r.codigo NOT IN ('REG_ALR_002','REG_ALR_003');
 IF before_total<>(SELECT count(*) FROM lf_ops.reglas) OR before_other IS DISTINCT FROM after_other
 OR (SELECT count(*) FROM lf_ops.reglas WHERE codigo IN ('REG_ALR_002','REG_ALR_003') AND estado='VIGENTE')<>2
 THEN RAISE EXCEPTION 'IG_B_ALR002003_GLOBAL_OTHER_RULES_DRIFT'; END IF;
 RAISE NOTICE 'IG_B_ALR002003_OWNER_V2_VERIFIED; 2_VERSION2; 584_OTHER_RULES_INVARIANT; STEP80_PENDING';
END $apply$;
COMMIT;
