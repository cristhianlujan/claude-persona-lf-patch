-- LF IG Familia B: Owner V2 for OBS003, OBS004, DAT003 after canonical PG17 Train PR #4333.
-- TEC006 excluded from Owner V2: old native patch missing title; OBS005 already verified V2.
-- Only canonical Step70 and lf_ig_rule_owner_decide_v2 change the 3 target rules.
-- Backend E2E NOT_TESTED.
BEGIN;
CREATE TEMP TABLE ig_b_obsdat_specs(
 code text PRIMARY KEY,parent text NOT NULL,screen text NOT NULL,
 source_sha text NOT NULL,proposal_sha text NOT NULL,candidate_sha text NOT NULL,
 config_scope text NOT NULL,config_key text NOT NULL,config_value text NOT NULL,
 config_type text NOT NULL,config_ref_field text NOT NULL,pg17_marker text NOT NULL
) ON COMMIT DROP;
INSERT INTO ig_b_obsdat_specs VALUES
('REG_OBS_003','EXEC-PROFILE-GATE2-4EB598CC54DA31538C309B33','ONB_001','95728aa2994d42ac14873ac66a280287b38e11893d87b725530413112c017b51','fecd54d5d0b799352ae35c5d9e65ad0d4e012939f3483136ec38db1e3e18313b','95a02202cc7697ee5b0468f0ebfa4831839c2d6a3e979c9ba1af6fe3e3f9b676','ALERTAS','PASO1_SUBMIT_ERROR_RATE_MAX','0.05','DECIMAL','paso1_submit_error_rate_config_ref','IG_B_REG_OBS_003_REAL_PG17_PROOF_COMPLETE'),
('REG_OBS_004','EXEC-PROFILE-GATE2-ED95B810E2A8CC09BDA0211D','ONB_001','7945d27ca7ca05305d0c41abbb591bb4059b828f73bd815aaaaf7bdcd8e90660','d7455e46f17701b8acd6eb937c1fcab15d62aa44ab8cfa8e5d06f8d3c04cd0af','36d040466e485e57abcc68175ea7a553f8d8d24a741f7c627daaadf6d3306e44','OBSERVABILIDAD','CORE_WEB_VITALS_ALERT_SESSIONS_PERCENT','10','INTEGER','alerta_porcentaje_sesiones_config_ref','IG_B_REG_OBS_004_REAL_PG17_PROOF_COMPLETE'),
('REG_DAT_003','EXEC-PROFILE-GATE2-CD293DC8600BC2C9390C7106','PASO3_MULTI_OFERTA','f75ae3f8cd8cf6f96759d70aa0a30d3a9d552d1b2bda7f89020b73f5bb955f32','d70efdb141043803e5808fd887f884667da3924a3e01229c7ca0f759b2a1915c','83566314a625392a95af9c88481058c4e6d7ceeeae4406bf0ab15c462ed32ebe','UX','SELECTION_RECALC_MAX_LATENCY_MS','100','INTEGER','latencia_maxima_ms_config_ref','IG_B_REG_DAT_003_REAL_PG17_PROOF_COMPLETE');
DO $apply$
DECLARE x record;v_old jsonb;v_profile jsonb;v_patch jsonb;v_new jsonb;v_auto jsonb;v_step jsonb;v_dec jsonb;
 v_report jsonb;v_checks jsonb;v_readback jsonb;before_total int;other_before text;other_after text;
 train CONSTANT text:='EXEC-DB-TRAIN-PR4333-20261119112900-R44515583081';
 train_run CONSTANT text:='44515583081';
 train_head CONSTANT text:='8574dafd6a58fb8da55976d9e3a195d5dbb1c05c';
 train_event CONSTANT bigint:=22158;
 train_receipt CONSTANT text:='58a411c7108e73e2197bb13345b29e79cea147f1a395cd13a6fa5f1758251acb';
 test_sql_sha CONSTANT text:='acc7c36f91ab8ecd126d2e36e3480182aa68695e22db0b2bea0b730877da5847';
BEGIN
 IF current_setting('server_version_num')::int/10000<>17 OR (SELECT count(*) FROM ig_b_obsdat_specs)<>3 THEN
 RAISE EXCEPTION 'IG_B_OBSDAT_PG17_OR_SPEC_COUNT_INVALID'; END IF;
 SELECT count(*) INTO before_total FROM lf_ops.reglas;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.codigo)::text,'[]')) INTO other_before
 FROM lf_ops.reglas r WHERE r.codigo NOT IN('REG_OBS_003','REG_OBS_004','REG_DAT_003');
 IF before_total<>586 THEN RAISE EXCEPTION 'IG_B_OBSDAT_BASE_RULE_COUNT_DRIFT'; END IF;
 FOR x IN SELECT * FROM ig_b_obsdat_specs ORDER BY code LOOP
 IF (SELECT count(*) FROM lf_ops.reglas WHERE codigo=x.code AND estado='VIGENTE')<>1
 OR public.lf_asset_snapshot_sha_v1('REGLA',x.code) IS DISTINCT FROM x.source_sha
 OR (SELECT version FROM lf_ops.v_reglas_historial WHERE codigo=x.code AND es_actual)<>1
 OR (SELECT count(*) FROM lf_ops.reglas_versiones WHERE codigo=x.code AND version=1 AND vigente_hasta IS NULL)<>1
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id=x.parent AND rule_code=x.code)
 OR EXISTS(SELECT 1 FROM public.lf_ig_functional_train_evidence_v1 WHERE rule_code=x.code AND proposal_sha256=x.proposal_sha)
 OR NOT EXISTS(SELECT 1 FROM lf_ops.reglas rr JOIN lf_ops.reglas_pantallas rp ON rr.id=rp.regla_id JOIN lf_ops.pantallas sc ON sc.id=rp.pantalla_id WHERE rr.codigo=x.code AND sc.codigo=x.screen)
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution e WHERE e.execution_id=x.parent AND e.operation_code='EJECUCION_PERFIL_LF' AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF' AND e.status='IN_PROGRESS' AND e.manifest#>>'{screen_selection_result,selected_screen_code}'=x.screen AND e.manifest->>'no_write'='true')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps s WHERE s.execution_id=x.parent AND s.step_id='output_validate' AND s.status='STEP_PASS_WITH_EVIDENCE' AND s.evidence_payload->>'output_contract_result'='PASS')
 OR NOT EXISTS(SELECT 1 FROM public.lf_global_config g WHERE g.scope=x.config_scope AND g.config_key=x.config_key AND g.config_value=x.config_value AND g.value_type=x.config_type AND g.value_status='REAL')
 THEN RAISE EXCEPTION 'IG_B_OBSDAT_SOURCE_RUN_OR_CONFIG_DRIFT:%',x.code; END IF;
 SELECT to_jsonb(r)-'created_at'-'updated_at' INTO v_old FROM lf_ops.reglas r WHERE r.codigo=x.code;
 SELECT s.evidence_payload->'profile_output' INTO v_profile FROM public.lf_operation_execution_steps s WHERE s.execution_id=x.parent AND s.step_id='execute_profile' AND s.status='STEP_PASS_WITH_EVIDENCE';
 v_patch:=v_profile#>'{deliverable_created,governed_rule_patch}';
 IF v_profile#>>'{deliverable_created,product_decision,proposed_by}' IS DISTINCT FROM 'PERFIL-PRODUCT-DIRECTOR-LF'
 OR v_patch->>'rule_code' IS DISTINCT FROM x.code
 OR v_patch->>'change_kind' IS DISTINCT FROM 'FUNCTIONAL'
 OR encode(extensions.digest(convert_to(v_patch::text,'UTF8'),'sha256'),'hex') IS DISTINCT FROM x.proposal_sha
 OR (v_patch#>>'{changes,descripcion}') NOT LIKE '%public.lf_global_config%'
 OR v_patch#>>ARRAY['changes','valor_config',x.config_ref_field,'scope'] IS DISTINCT FROM x.config_scope
 OR v_patch#>>ARRAY['changes','valor_config',x.config_ref_field,'config_key'] IS DISTINCT FROM x.config_key
 OR (v_patch#>'{changes}')?'titulo'
 THEN RAISE EXCEPTION 'IG_B_OBSDAT_NATIVE_PATCH_MISMATCH:%',x.code; END IF;
 IF x.code='REG_OBS_003' AND (
   (v_patch#>>'{changes,valor_config,paso1_submit_error_comparador}') IS DISTINCT FROM 'MAYOR_QUE'
   OR v_patch#>'{changes,valor_config,alertas_criticas}' IS DISTINCT FROM '["otp_whatsapp_send_failed","home_variant_cruce_timeout","paso1_submit_error_rate","paso3_load_failed"]'::jsonb
   OR (v_patch#>'{changes,valor_config}')?'alerta_porcentaje_sesiones'
 ) THEN RAISE EXCEPTION 'IG_B_OBS003_FUNCTIONAL_SEMANTICS_DRIFT'; END IF;
 IF x.code='REG_OBS_004' AND (
   (v_patch#>'{changes,valor_config,alerta_porcentaje_sesiones}') IS NOT NULL
   OR (v_patch#>>'{changes,valor_config,lcp_ms}') IS DISTINCT FROM '2500'
   OR (v_patch#>>'{changes,valor_config,cls}')::numeric IS DISTINCT FROM 0.1::numeric
   OR (v_patch#>>'{changes,valor_config,fid_ms}') IS DISTINCT FROM '100'
 ) THEN RAISE EXCEPTION 'IG_B_OBS004_TECHNICAL_REFERENCE_DRIFT'; END IF;
 IF x.code='REG_DAT_003' AND (
   (v_patch#>'{changes,valor_config}')?'latencia_maxima_ms'
   OR (v_patch#>>'{changes,valor_config,trigger}') IS DISTINCT FROM 'on_change_seleccion_o_modalidad'
   OR v_patch#>'{changes,valor_config,campos_recalculados}' IS DISTINCT FROM '["lista_ofertas","total_hoy","ahorro_total","contador_seleccionadas"]'::jsonb
 ) THEN RAISE EXCEPTION 'IG_B_DAT003_RECALC_SEMANTICS_DRIFT'; END IF;
 v_new:=v_old||jsonb_build_object('descripcion',v_patch#>>'{changes,descripcion}','valor_config',v_patch#>'{changes,valor_config}');
 IF encode(extensions.digest(convert_to(v_new::text,'UTF8'),'sha256'),'hex') IS DISTINCT FROM x.candidate_sha
 OR v_new->>'titulo' IS DISTINCT FROM v_old->>'titulo'
 OR v_new->>'razon' IS DISTINCT FROM v_old->>'razon'
 OR v_new->>'origen' IS DISTINCT FROM v_old->>'origen'
 OR v_new->>'estado' IS DISTINCT FROM 'VIGENTE'
 THEN RAISE EXCEPTION 'IG_B_OBSDAT_CANDIDATE_HASH_OR_SCOPE:%',x.code; END IF;
 IF NOT EXISTS(
 SELECT 1 FROM public.lf_operation_execution te JOIN public.lf_eventos evt ON evt.entidad_codigo=te.execution_id AND evt.evento_tipo='MIGRATION_TRAIN_RECEIPT_RECORDED' AND evt.origen='lf-migration-merge-train'
 JOIN supabase_migrations.schema_migrations ml ON ml.version='20261119112900'
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
 AND ml.name='lf_ig_family_b_obs003004_tec006_dat003_pg17_v1'
 AND encode(extensions.digest(convert_to(ml.statements[1],'UTF8'),'sha256'),'hex')=test_sql_sha
 AND ml.statements[1] LIKE '%'||x.pg17_marker||'%'
 AND ml.statements[1] LIKE '%ROLLBACK TO SAVEPOINT%'
 ) THEN RAISE EXCEPTION 'IG_B_OBSDAT_PG17_TRAIN_RECEIPT_INVALID:%',x.code; END IF;
 v_checks:=jsonb_build_object('preimage_sha','PASS','native_patch_sha','PASS','candidate_sha','PASS','screen_link','PASS',
 'config_real','PASS','positive_savepoint_rollback','PASS','negative_source_drift','PASS','negative_missing_config','PASS',
 'negative_savepoint_rollback','PASS','independent_select','PASS','backend_e2e','NOT_TESTED');
 v_readback:=jsonb_build_object('rule_code',x.code,'source_snapshot_sha256',public.lf_asset_snapshot_sha_v1('REGLA',x.code),
 'config_scope',x.config_scope,'config_key',x.config_key,'config_value',x.config_value,
 'source_config',(SELECT valor_config FROM lf_ops.reglas WHERE codigo=x.code),
 'history_current',(SELECT version FROM lf_ops.v_reglas_historial WHERE codigo=x.code AND es_actual),'rule_total',before_total);
 v_report:=jsonb_build_object('schema_version','LF_IG_FAMILIA_B_OBSDAT_PG17_TRAIN_VERIFIED_REPORT_V1','rule_code',x.code,
 'test_scope','RULE_CONTRACT_LEVEL','pg17_real',true,'backend_e2e','NOT_TESTED',
 'train_run_id',train_run,'train_execution_id',train,'train_head_sha',train_head,'train_event_id',train_event,'train_receipt_sha256',train_receipt,
 'test_sql_migration_sha256',test_sql_sha,'source_snapshot_sha256',x.source_sha,'proposal_sha256',x.proposal_sha,
 'candidate_snapshot_sha256',x.candidate_sha,'test_checks',v_checks,'independent_readback',v_readback);
 INSERT INTO public.lf_ig_functional_train_evidence_v1(rule_code,source_snapshot_sha256,proposal_sha256,candidate_snapshot_sha256,
 train_execution_id,train_run_id,train_event_id,train_head_sha,pg_rollback_status,independent_readback_status,functional_checks_status,negative_checks_status,
 pg_report_sha256,readback_sha256,check_manifest_sha256,report_ref)
 VALUES(x.code,x.source_sha,x.proposal_sha,x.candidate_sha,train,train_run,train_event,train_head,'PASS','PASS','PASS','PASS',
 encode(extensions.digest(convert_to(v_report::text,'UTF8'),'sha256'),'hex'),
 encode(extensions.digest(convert_to(v_readback::text,'UTF8'),'sha256'),'hex'),
 encode(extensions.digest(convert_to(v_checks::text,'UTF8'),'sha256'),'hex'),
 'github://cristhianlujan/claude-persona-lf-patch/actions/runs/44515583081#RULE_CONTRACT_LEVEL');
 v_auto:=public.lf_ig_step70_functional_train_auto_v1(x.parent);
 IF v_auto->>'status' IS DISTINCT FROM 'PASS'
 OR v_auto->>'verdict' IS DISTINCT FROM 'PASS_TRAIN_EVIDENCE_AUTOMATICO'
 OR v_auto#>>'{train_evidence,source_snapshot_sha256}' IS DISTINCT FROM x.source_sha
 OR v_auto#>>'{train_evidence,proposal_sha256}' IS DISTINCT FROM x.proposal_sha
 OR v_auto#>>'{train_evidence,candidate_snapshot_sha256}' IS DISTINCT FROM x.candidate_sha
 OR v_auto#>>'{train_evidence,train_run_id}' IS DISTINCT FROM train_run
 THEN RAISE EXCEPTION 'IG_B_OBSDAT_AUTO_STEP70_FAILED:%:%',x.code,v_auto; END IF;
 v_step:=public.lf_record_profile_execution_step_v1(x.parent,'semantic_judge',
 'supabase://public.lf_ig_functional_train_evidence_v1/'||x.code,
 jsonb_build_object('semantic_judge_result',v_auto,'unsupported_claims','[]'::jsonb,
 'semantic_review_receipt_ref','supabase://public.lf_ig_functional_train_evidence_v1/'||x.code,
 'independent_semantic_receipt_ref',NULL,'judge_independence_status','NOT_ASSERTED',
 'evaluator','TRAIN_EVIDENCE_AUTOMATICO',
 'content_findings',jsonb_build_array(jsonb_build_object('finding_code','SEMANTIC_JUDGE_NOT_PERFORMED','evaluator','TRAIN_EVIDENCE_AUTOMATICO'))),x.parent);
 IF coalesce(v_step->>'status',v_step->>'step_status') IS DISTINCT FROM 'STEP_PASS_WITH_EVIDENCE'
 THEN RAISE EXCEPTION 'IG_B_OBSDAT_OFFICIAL_STEP70_FAILED:%:%',x.code,v_step; END IF;
 v_dec:=public.lf_ig_rule_owner_decide_v2(x.parent,x.code,x.source_sha,'{"usuario":"Cristhian Lujan","veredicto":"APROBAR"}'::jsonb);
 IF v_dec->>'status' IS DISTINCT FROM 'APPROVED_AND_VIGENTE_VERIFIED'
 OR v_dec->>'kind' IS DISTINCT FROM 'CORRECT_VIGENTE'
 OR v_dec->>'proposal_sha256' IS DISTINCT FROM x.proposal_sha
 OR v_dec->>'finalized_snapshot_sha256' IS DISTINCT FROM x.candidate_sha
 OR public.lf_asset_snapshot_sha_v1('REGLA',x.code) IS DISTINCT FROM x.candidate_sha
 OR (SELECT version FROM lf_ops.v_reglas_historial WHERE codigo=x.code AND es_actual)<>2
 THEN RAISE EXCEPTION 'IG_B_OBSDAT_OWNER_V2_VERSION_OR_SHA:%:%',x.code,v_dec; END IF;
 END LOOP;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.codigo)::text,'[]')) INTO other_after FROM lf_ops.reglas r WHERE r.codigo NOT IN('REG_OBS_003','REG_OBS_004','REG_DAT_003');
 IF before_total<>(SELECT count(*) FROM lf_ops.reglas) OR other_before IS DISTINCT FROM other_after
 THEN RAISE EXCEPTION 'IG_B_OBSDAT_ADJACENT_RULES_CHANGED'; END IF;
 RAISE NOTICE 'IG_B_OBSDAT_OWNER_V2_PASS; 3_VERSION2; 583_OTHER_RULES_INVARIANT; BACKEND_E2E_NOT_TESTED; STEP80_PENDING';
END $apply$;
COMMIT;
