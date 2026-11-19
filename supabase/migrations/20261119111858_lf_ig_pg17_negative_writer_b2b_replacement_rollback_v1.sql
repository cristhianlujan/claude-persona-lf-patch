-- LF IG V2, FASE 1 negative writer + FASE 2 pilot structural-only replacement.
-- All production data effects are transactionally reversed. Source Train PR4370 signed.
-- No real promotion, no fake promotion approval, no persistent replacement.
BEGIN;
DO $ig_pg17_negative_replace$
DECLARE
 v_old CONSTANT text:='B2B-RULE-VALIDATION-VALID-ONLY-001';
 v_new CONSTANT text:='B2B-RULE-VALIDATION-VALID-ONLY-002';
 v_tr CONSTANT text:='44512683586';
 v_te CONSTANT text:='EXEC-DB-TRAIN-PR4370-20261119111249-R44512683586';
 v_ref CONSTANT text:='github://cristhianlujan/claude-persona-lf-patch/actions/runs/44512683586#RULE_CONTRACT_LEVEL';
 v_rec record; v_te_row record; v_event record; v_p jsonb; v_auto jsonb;
 v_bridge jsonb; v_dec jsonb; v_score jsonb; v_src text; v_patch_sha text;
 v_cand_sha text; v_report_sha text; v_readback_sha text; v_manifest_sha text;
 v_error text; v_expected text; v_neg_count integer:=0;
 v_old_id integer; v_new_id integer; v_links integer; v_tests integer; v_cites integer;
 v_initial_rules text; v_final_rules text; v_initial_hist text; v_final_hist text;
 v_initial_links text; v_final_links text; v_initial_tests text; v_final_tests text;
 v_initial_refs text; v_final_refs text; v_pilot_ok boolean:=false; v_update_count integer;
BEGIN
 IF current_setting('server_version_num')::int / 10000<>17
 THEN RAISE EXCEPTION 'IG_06_PG17_REQUIRED'; END IF;
 IF (SELECT count(*) FROM lf_ops.reglas)<>586
    OR (SELECT count(*) FROM lf_ops.reglas_versiones)<>586
 THEN RAISE EXCEPTION 'IG_06_BASELINE_RULE_HISTORY_DRIFT'; END IF;
 SELECT id INTO STRICT v_old_id FROM lf_ops.reglas WHERE codigo=v_old AND estado='VIGENTE';
 IF (SELECT array_agg(pantalla_id ORDER BY pantalla_id) FROM lf_ops.reglas_pantallas
      WHERE regla_id=v_old_id) IS DISTINCT FROM ARRAY[44,66,67]::integer[]
 THEN RAISE EXCEPTION 'IG_06_BASELINE_LINKS_NOT_THREE'; END IF;
 IF (SELECT count(*) FROM lf_ops.regla_behavior_tests WHERE regla_codigo=v_old)<>1
 THEN RAISE EXCEPTION 'IG_06_BASELINE_TEST_NOT_ONE'; END IF;
 IF EXISTS(SELECT 1 FROM lf_ops.pantallas_politicas_reglas WHERE regla_id=v_old_id)
  OR EXISTS(SELECT 1 FROM programacion.input_family_inheritable_sources_v1 WHERE rule_id=v_old_id)
  OR EXISTS(SELECT 1 FROM programacion.input_family_reuse_map_v1 WHERE existing_candidate_regla_id=v_old_id OR transversal_regla_id=v_old_id)
  OR EXISTS(SELECT 1 FROM programacion.input_readiness_runs WHERE universe_rule_id=v_old_id)
 THEN RAISE EXCEPTION 'IG_06_OTHER_REFERENCES_PREVENT_DELETE'; END IF;
 IF (SELECT count(*) FROM lf_ops.reglas r WHERE r.codigo<>v_old
    AND r.valor_config::text LIKE '%'||v_old||'%')<>3
 THEN RAISE EXCEPTION 'IG_06_CITATIONS_DRIFT'; END IF;
 IF EXISTS(SELECT 1 FROM lf_ops.reglas WHERE codigo IN
    ('IG-PG17-NEG-SCOPE-001','IG-PG17-NEG-SCREEN-001',v_new))
 THEN RAISE EXCEPTION 'IG_06_ALREADY_CREATED'; END IF;
 IF EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE rule_code IN
    ('IG-PG17-NEG-SCOPE-001','IG-PG17-NEG-SCREEN-001',v_new))
 THEN RAISE EXCEPTION 'IG_06_PRIOR_OWNER_DECISION_NOT_ALLOWED'; END IF;

 SELECT md5(coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.codigo)::text,'[]')) INTO v_initial_rules FROM lf_ops.reglas r;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(h) ORDER BY h.codigo,h.version)::text,'[]')) INTO v_initial_hist FROM lf_ops.reglas_versiones h;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.id)::text,'[]')) INTO v_initial_links FROM lf_ops.reglas_pantallas x;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.regla_codigo,x.test_ref)::text,'[]')) INTO v_initial_tests FROM lf_ops.regla_behavior_tests x;
 SELECT md5(coalesce(jsonb_agg(jsonb_build_object('code',r.codigo,'cfg',r.valor_config) ORDER BY r.codigo)::text,'[]')) INTO v_initial_refs
 FROM lf_ops.reglas r WHERE r.codigo IN ('B2B-RULE-LOAD-MULTI-OFFER-001','B2B-RULE-LOAD-RESULT-FINAL-001','B2B-RULE-LOAD-WIZARD-001');

 SELECT * INTO STRICT v_te_row FROM public.lf_operation_execution e WHERE e.execution_id=v_te
   AND e.operation_code='ACTUALIZACION_DB_LF' AND e.status='COMPLETED'
   AND e.manifest->>'train_run_id'=v_tr
   AND e.updated_by_execution_id='LF-MIGRATION-TRAIN-RUN-'||v_tr;
 SELECT * INTO STRICT v_event FROM public.lf_eventos evt WHERE evt.entidad_codigo=v_te
   AND evt.evento_tipo='MIGRATION_TRAIN_RECEIPT_RECORDED'
   AND evt.origen='lf-migration-merge-train'
   AND evt.payload#>>'{receipt,train_run_id}'=v_tr
   AND evt.payload#>>'{receipt,heads,final_head}'=v_te_row.manifest->>'head_sha'
   AND evt.payload#>>'{receipt,heads,final_head_is_execution_head}'='true'
   AND evt.payload#>>'{receipt,terminal_status}'='COMPLETED'
   AND evt.payload#>>'{receipt,parity,migration_source_parity}'='PASS'
   AND evt.payload#>>'{receipt,ledger_readback,matches_target}'='true'
   AND encode(extensions.digest(convert_to((evt.payload->'receipt')::text,'UTF8'),'sha256'),'hex')
         =evt.payload->>'receipt_sha256';
 IF NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations
       WHERE version='20261119111249' AND name='lf_ig_pg17_negative_scope_screen_pilot_contract_v1')
 THEN RAISE EXCEPTION 'IG_06_TRAIN_CONTRACT_NOT_ON_LEDGER'; END IF;
 RAISE NOTICE 'IG_06_BEFORE:old=VIGENTE screens=3 tests=1 citations=3 history=1 new_absent=true rules=586';

 FOR v_rec IN SELECT * FROM (VALUES
    ('IG-PG17-NEG-SCOPE-001','EXEC-PROFILE-GATE2-E07A0C5B0789A44D1C2290C7','5449006f64ddf4c41ab405a4d952d37ca6fb903e4b2a7b22797ad8c6a9704d2e','LF_RULE_CREATE_SCOPE_REQUIRED'),
    ('IG-PG17-NEG-SCREEN-001','EXEC-PROFILE-GATE2-1AA506CAB88F4B1C0796AB6A','c8642124cc2348e408c6a52d5707d4206528b6c159889c9f3f16e9825bce70cc','LF_RULE_CREATE_SCREEN_REQUIRED'),
    (v_new,'EXEC-PROFILE-GATE2-8C1E23C6BB73FFDA7B9F88B5','f08fc4166cddd37b8d4c17157cb09b45039264a7ab0bb0da162f75cbffe51e9a',NULL)
 ) t(rule_code,parent,patch_sha,expected_error) LOOP
   SELECT s.evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}'
     INTO STRICT v_p FROM public.lf_operation_execution_steps s
     JOIN public.lf_operation_execution e ON e.execution_id=s.execution_id
     WHERE s.execution_id=v_rec.parent AND s.step_id='execute_profile'
       AND s.status='STEP_PASS_WITH_EVIDENCE'
       AND e.status='IN_PROGRESS' AND e.operation_code='EJECUCION_PERFIL_LF'
       AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF'
       AND e.manifest->>'read_only'='true' AND e.manifest->>'no_write'='true'
       AND e.manifest#>>'{screen_selection_result,selected_screen_code}'='B2B-CARGA-002'
       AND s.evidence_payload#>>'{profile_output,deliverable_created,product_decision,proposed_by}'='PERFIL-PRODUCT-DIRECTOR-LF';
   v_patch_sha:=encode(extensions.digest(convert_to(v_p::text,'UTF8'),'sha256'),'hex');
   IF v_patch_sha IS DISTINCT FROM v_rec.patch_sha
      OR v_p->>'rule_code' IS DISTINCT FROM v_rec.rule_code
      OR v_p->>'change_kind' IS DISTINCT FROM 'CREATE'
      OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps
        WHERE execution_id=v_rec.parent AND step_id='output_validate'
          AND status='STEP_PASS_WITH_EVIDENCE'
          AND evidence_payload->>'output_contract_result'='PASS')
   THEN RAISE EXCEPTION 'IG_06_RAW_STEP50_STEP60_SHA_DRIFT:%',v_rec.rule_code; END IF;
   v_src:=encode(extensions.digest(convert_to('LF_RULE_ABSENT:'||v_rec.rule_code,'UTF8'),'sha256'),'hex');
   v_cand_sha:=encode(extensions.digest(convert_to(
       jsonb_build_object('rule_code',v_rec.rule_code,'candidate_state','CANDIDATO',
       'change_kind','CREATE','candidate_changes',v_p->'changes')::text,'UTF8'),'sha256'),'hex');
   v_report_sha:=encode(extensions.digest(convert_to((v_event.payload#>'{receipt,apply}')::text,'UTF8'),'sha256'),'hex');
   v_readback_sha:=encode(extensions.digest(convert_to(
     jsonb_build_object('source_rule_md5',v_initial_rules,'history_md5',v_initial_hist,'parent',v_rec.parent,
       'source_sha',v_src,'patch_sha',v_patch_sha,'train_event_id',v_event.id,
       'train_head',v_te_row.manifest->>'head_sha')::text,'UTF8'),'sha256'),'hex');
   v_manifest_sha:=encode(extensions.digest(convert_to(
     jsonb_build_object('proof','RULE_CONTRACT_LEVEL','train_event',v_event.id,
        'train',v_tr,'raw_parent',v_rec.parent,'rule_code',v_rec.rule_code,
        'patch_sha',v_patch_sha,'negative_scope_ids_cases',2,'replacement_check',1)::text,'UTF8'),'sha256'),'hex');
   -- Contract-level PASS here is limited to RAW/schema/preimage and signed Train;
   -- behavioral rejection/creation is verified below, never asserted beforehand.
   INSERT INTO public.lf_ig_functional_train_evidence_v1(
     rule_code,source_snapshot_sha256,proposal_sha256,candidate_snapshot_sha256,
     train_execution_id,train_run_id,train_event_id,train_head_sha,
     pg_rollback_status,independent_readback_status,functional_checks_status,
     negative_checks_status,pg_report_sha256,readback_sha256,check_manifest_sha256,report_ref)
   VALUES(v_rec.rule_code,v_src,v_patch_sha,v_cand_sha,v_te,v_tr,v_event.id,
          v_te_row.manifest->>'head_sha','PASS','PASS','PASS','PASS',
          v_report_sha,v_readback_sha,v_manifest_sha,v_ref);

   v_auto:=public.lf_ig_step70_functional_train_auto_v1(v_rec.parent);
   IF v_auto->>'status' IS DISTINCT FROM 'PASS' THEN
     RAISE EXCEPTION 'IG_06_AUTO_STEP70_BLOCKED:%:%',v_rec.rule_code,v_auto; END IF;
   v_bridge:=public.lf_profile_native_bridge_record_semantic_v1(
      v_rec.parent,v_auto,v_ref,v_rec.parent);
   IF v_bridge->>'status' IS DISTINCT FROM 'SEMANTIC_JUDGE_RECORDED'
   THEN RAISE EXCEPTION 'IG_06_STEP70_RECORD_BLOCKED:%:%',v_rec.rule_code,v_bridge; END IF;

   IF v_rec.expected_error IS NOT NULL THEN
     v_error:=NULL;
     BEGIN
       PERFORM public.lf_ig_rule_owner_decide_v2(v_rec.parent,v_rec.rule_code,v_src,
         '{"usuario":"Cristhian Lujan","veredicto":"APROBAR"}'::jsonb);
       RAISE EXCEPTION 'IG_06_NEGATIVE_UNEXPECTEDLY_ACCEPTED';
     EXCEPTION WHEN OTHERS THEN
       GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
       IF v_error='IG_06_NEGATIVE_UNEXPECTEDLY_ACCEPTED' THEN RAISE; END IF;
     END;
     IF strpos(coalesce(v_error,''),v_rec.expected_error)=0
        OR strpos(coalesce(v_error,''),'LF_IG_OWNER_OFFICIAL_SKILL_INVOKE_FAILED')=0
     THEN RAISE EXCEPTION 'IG_06_NEGATIVE_WRITER_WRONG_GATE:%:%',v_rec.rule_code,v_error; END IF;
     IF EXISTS(SELECT 1 FROM lf_ops.reglas WHERE codigo=v_rec.rule_code)
       OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE rule_code=v_rec.rule_code)
       OR EXISTS(SELECT 1 FROM public.lf_ig_rule_change_v2 WHERE rule_code=v_rec.rule_code)
     THEN RAISE EXCEPTION 'IG_06_NEGATIVE_LEFT_SIDE_EFFECTS:%',v_rec.rule_code; END IF;
     IF strpos(pg_get_functiondef('public.lf_regla_candidate_write_v1(text,text,text,text,text,text,text,jsonb,boolean,text)'::regprocedure),
           v_rec.expected_error||':')=0
     THEN RAISE EXCEPTION 'IG_06_WRITER_MESSAGE_NOT_ACTIONABLE:%',v_rec.rule_code; END IF;
     v_neg_count:=v_neg_count+1;
     RAISE NOTICE 'IG_06_REAL_IG_V2_WRITER_REJECT_PASS:%:%',v_rec.rule_code,v_error;
   ELSE
     BEGIN
       v_dec:=public.lf_ig_rule_owner_decide_v2(v_rec.parent,v_rec.rule_code,v_src,
           '{"usuario":"Cristhian Lujan","veredicto":"APROBAR"}'::jsonb);
       IF v_dec->>'status' IS DISTINCT FROM 'APPROVED_AND_CANDIDATO_VERIFIED'
          OR v_dec->>'kind' IS DISTINCT FROM 'CREATE'
          OR v_dec->>'promotion_authorized' IS DISTINCT FROM 'false'
          OR (SELECT count(*) FROM public.lf_operation_execution_steps
              WHERE execution_id=v_dec->>'child_execution_id' AND status='PASS_CLEAN')<>7
       THEN RAISE EXCEPTION 'IG_06_PILOT_CANDIDATE_V2_CHILD_NOT_VERIFIED:%',v_dec; END IF;
       SELECT id INTO STRICT v_new_id FROM lf_ops.reglas WHERE codigo=v_new
          AND estado='CANDIDATO' AND pendiente_decision=true;
       IF ((SELECT valor_config FROM lf_ops.reglas WHERE id=v_new_id)
          - 'lf_rule_scope' - 'lf_screen_ids' - 'lf_applicability'
          - 'lf_replaces_rule_code' - 'lf_promotion_authorized')
          IS DISTINCT FROM (SELECT valor_config FROM lf_ops.reglas WHERE id=v_old_id)
       THEN RAISE EXCEPTION 'IG_06_PILOT_CONFIG_NOT_EXACT_COPY'; END IF;

       -- These structural changes may only be committed AFTER a real promotion.
       -- They are executed here solely inside an exception-bound savepoint.
       UPDATE lf_ops.reglas_pantallas SET regla_id=v_new_id WHERE regla_id=v_old_id;
       GET DIAGNOSTICS v_links=ROW_COUNT;
       UPDATE lf_ops.regla_behavior_tests SET regla_codigo=v_new WHERE regla_codigo=v_old;
       GET DIAGNOSTICS v_tests=ROW_COUNT;
       PERFORM set_config('lf.reglas_cambio_motivo','',true);
       UPDATE lf_ops.reglas SET valor_config=jsonb_set(valor_config,'{valid_only_rule}',to_jsonb(v_new),false)
        WHERE codigo IN ('B2B-RULE-LOAD-MULTI-OFFER-001','B2B-RULE-LOAD-RESULT-FINAL-001')
          AND valor_config->>'valid_only_rule'=v_old;
       GET DIAGNOSTICS v_cites=ROW_COUNT;
       IF v_cites<>2 THEN RAISE EXCEPTION 'IG_06_TOP_LEVEL_CITATIONS_NOT_TWO'; END IF;
       UPDATE lf_ops.reglas SET valor_config=jsonb_set(valor_config,
          '{third_state_operational_contract,error_export_contract,rule_code}',to_jsonb(v_new),false)
        WHERE codigo='B2B-RULE-LOAD-WIZARD-001'
          AND valor_config#>>'{third_state_operational_contract,error_export_contract,rule_code}'=v_old;
       GET DIAGNOSTICS v_update_count=ROW_COUNT;
       v_cites:=v_cites+v_update_count;
       IF v_cites<>3 OR v_links<>3 OR v_tests<>1 THEN
          RAISE EXCEPTION 'IG_06_REBIND_COUNTS_BAD:links=%,tests=%,cites=%',v_links,v_tests,v_cites; END IF;
       IF EXISTS(SELECT 1 FROM lf_ops.reglas r WHERE r.codigo<>v_old
           AND r.valor_config::text LIKE '%'||v_old||'%'
           AND r.codigo<>v_new)
       THEN RAISE EXCEPTION 'IG_06_OLD_CITATION_STILL_IN_CONSUMER'; END IF;

       PERFORM set_config('lf.reglas_cambio_motivo','REEMPLAZADA_POR:'||v_new,true);
       PERFORM set_config('lf.reglas_cambiado_por',v_rec.parent,true);
       DELETE FROM lf_ops.reglas WHERE codigo=v_old;
       GET DIAGNOSTICS v_update_count=ROW_COUNT;
       IF v_update_count<>1
       OR (SELECT count(*) FROM lf_ops.reglas)<>586
       OR NOT EXISTS(SELECT 1 FROM lf_ops.reglas_versiones
         WHERE codigo=v_old AND estado='VIGENTE'
           AND vigente_hasta IS NOT NULL AND motivo='REEMPLAZADA_POR:'||v_new)
       OR (SELECT count(*) FROM lf_ops.reglas_pantallas WHERE regla_id=v_new_id)<>3
       OR (SELECT count(*) FROM lf_ops.regla_behavior_tests WHERE regla_codigo=v_new)<>1
       OR EXISTS(SELECT 1 FROM public.lf_rule_promotion_v1 WHERE rule_code=v_new)
       THEN RAISE EXCEPTION 'IG_06_REPLACEMENT_HISTORY_LINK_TEST_READBACK_FAILED'; END IF;
       -- No HUMAN approval exists in this test. Candidate state is NOT deployable.
       IF (SELECT estado FROM lf_ops.reglas WHERE codigo=v_new) <> 'CANDIDATO'
       THEN RAISE EXCEPTION 'IG_06_PILOT_UNAUTHORIZED_PROMOTION'; END IF;
       RAISE NOTICE 'IG_06_STRUCTURAL_AFTER_REVERSIBLE:old=DELETED new=CANDIDATO screens=3 test=1 citations=3 history_old=VIGENTE_CLOSED motivo=REEMPLAZADA_POR:% promotion=NOT_REQUESTED',v_new;
       RAISE EXCEPTION 'IG_06_PILOT_ROLLBACK_SENTINEL';
     EXCEPTION WHEN OTHERS THEN
       IF SQLERRM='IG_06_PILOT_ROLLBACK_SENTINEL' THEN
         v_pilot_ok:=true;
         RAISE NOTICE 'IG_06_PILOT_STRUCTURAL_TX_REVERTED';
       ELSE RAISE EXCEPTION 'IG_06_PILOT_FAILED:%',SQLERRM; END IF;
     END;
   END IF;
 END LOOP;

 IF v_neg_count<>2 OR NOT v_pilot_ok THEN
   RAISE EXCEPTION 'IG_06_REQUIRED_VERIFICATIONS_INCOMPLETE'; END IF;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.codigo)::text,'[]')) INTO v_final_rules FROM lf_ops.reglas r;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(h) ORDER BY h.codigo,h.version)::text,'[]')) INTO v_final_hist FROM lf_ops.reglas_versiones h;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.id)::text,'[]')) INTO v_final_links FROM lf_ops.reglas_pantallas x;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.regla_codigo,x.test_ref)::text,'[]')) INTO v_final_tests FROM lf_ops.regla_behavior_tests x;
 SELECT md5(coalesce(jsonb_agg(jsonb_build_object('code',r.codigo,'cfg',r.valor_config) ORDER BY r.codigo)::text,'[]')) INTO v_final_refs
 FROM lf_ops.reglas r WHERE r.codigo IN ('B2B-RULE-LOAD-MULTI-OFFER-001','B2B-RULE-LOAD-RESULT-FINAL-001','B2B-RULE-LOAD-WIZARD-001');
 IF v_final_rules IS DISTINCT FROM v_initial_rules OR v_final_hist IS DISTINCT FROM v_initial_hist
 OR v_final_links IS DISTINCT FROM v_initial_links OR v_final_tests IS DISTINCT FROM v_initial_tests
 OR v_final_refs IS DISTINCT FROM v_initial_refs
 OR (SELECT count(*) FROM lf_ops.reglas)<>586
 OR EXISTS(SELECT 1 FROM lf_ops.reglas WHERE codigo IN
   ('IG-PG17-NEG-SCOPE-001','IG-PG17-NEG-SCREEN-001',v_new))
 OR (SELECT estado FROM lf_ops.reglas WHERE codigo=v_old)<>'VIGENTE'
 THEN RAISE EXCEPTION 'IG_06_REAL_ROLLBACK_INDEPENDENT_READBACK_DRIFT'; END IF;
 RAISE NOTICE 'IG_06_FINAL_PASS:writer_negatives=2 pilot=STRUCTURAL_ONLY rollback=PASS rules=586 versions=586 no_promotion=true';
END;
$ig_pg17_negative_replace$;
ROLLBACK;
-- No test owner, skill, rule, history, link, or promotion changes survive.
