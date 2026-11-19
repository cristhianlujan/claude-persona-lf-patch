-- IG V2 PANTALLA CREATE: authentic Product Director RUN, Step50/60 and signed Train source.
-- Transaction-only positive and negative through canonical Step70 + owner_decide_v2 + RULE_CREATE_APPLY.
-- ROLLBACK is mandatory; this is NOT a promotion, replacement, or production activation.
BEGIN;
DO $lf_ig_pg17_owner_create$
DECLARE
 v_parent constant text := 'EXEC-PROFILE-GATE2-103AA9E9039805D81315B92F';
 v_rule constant text := 'IG-PG17-SCREEN-CREATE-001';
 v_source constant text := '4b652b2dc6f5082d8c571c6e573d4fe4684101922f531aa4cbbfbe92f7822986';
 v_patch_sha constant text := 'd122d6cbf21d15954701b0bd90be8fed1e176f0a7b7c861b3336d36845d925ca';
 v_tr constant text := '44507153208';
 v_te constant text := 'EXEC-DB-TRAIN-PR4358-20261119103331-R44507153208';
 v_ref constant text := 'github://cristhianlujan/claude-persona-lf-patch/actions/runs/44507153208#RULE_CONTRACT_LEVEL';
 v_patch jsonb;
 v_train record; v_ev record;
 v_sha text; v_candidate_sha text; v_pg_sha text; v_readback_sha text;
 v_manifest_sha text; v_old_md5 text; v_after_md5 text;
 v_hist_md5 text; v_hist_after text; v_cfg jsonb;
 v_rule_count integer; v_screen_id integer;
 v_auto jsonb; v_bridge jsonb; v_dec jsonb;
 v_error text; v_denied boolean := false; v_positive boolean := false;
BEGIN
 IF current_setting('server_version_num')::integer / 10000 <> 17 THEN
  RAISE EXCEPTION 'IG_CREATE_PG17_REQUIRED';
 END IF;
 SELECT count(*) INTO v_rule_count FROM lf_ops.reglas;
 IF v_rule_count<>586 THEN RAISE EXCEPTION 'IG_CREATE_BASELINE_DRIFT:%',v_rule_count; END IF;
 IF EXISTS(SELECT 1 FROM lf_ops.reglas WHERE codigo=v_rule)
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE rule_code=v_rule)
 OR EXISTS(SELECT 1 FROM public.lf_ig_functional_train_evidence_v1 WHERE rule_code=v_rule)
 THEN RAISE EXCEPTION 'IG_CREATE_PREMATURE_DECISION_OR_RULE'; END IF;
 SELECT id INTO STRICT v_screen_id FROM lf_ops.pantallas
 WHERE codigo='B2B-CARGA-002' AND activa;
 IF v_screen_id<>44 THEN RAISE EXCEPTION 'IG_CREATE_SCREEN_ID_DRIFT'; END IF;

 SELECT s.evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}'
 INTO STRICT v_patch
 FROM public.lf_operation_execution_steps s
 JOIN public.lf_operation_execution p ON p.execution_id=s.execution_id
 WHERE s.execution_id=v_parent AND s.step_id='execute_profile'
 AND s.status='STEP_PASS_WITH_EVIDENCE'
 AND p.status='IN_PROGRESS' AND p.operation_code='EJECUCION_PERFIL_LF'
 AND p.target_code='PERFIL-PRODUCT-DIRECTOR-LF'
 AND p.manifest#>>'{screen_selection_result,selected_screen_code}'='B2B-CARGA-002'
 AND p.manifest->>'read_only'='true' AND p.manifest->>'no_write'='true'
 AND s.evidence_payload#>>'{profile_output,deliverable_created,product_decision,proposed_by}'='PERFIL-PRODUCT-DIRECTOR-LF';
 IF v_patch->>'rule_code' IS DISTINCT FROM v_rule
 OR v_patch->>'change_kind' IS DISTINCT FROM 'CREATE'
 OR v_patch#>>'{changes,valor_config,lf_rule_scope}' IS DISTINCT FROM 'PANTALLA'
 OR v_patch#>'{changes,valor_config,lf_screen_ids}' IS DISTINCT FROM jsonb_build_array(v_screen_id)
 OR v_patch#>>'{changes,valor_config,production_authorized}' IS DISTINCT FROM 'false'
 OR v_patch#>>'{changes,es_transversal}' IS DISTINCT FROM 'false'
 THEN RAISE EXCEPTION 'IG_CREATE_PATCH_SCOPE_DRIFT'; END IF;
 v_sha:=encode(extensions.digest(convert_to(v_patch::text,'UTF8'),'sha256'),'hex');
 IF v_sha IS DISTINCT FROM v_patch_sha
 OR v_source IS DISTINCT FROM encode(extensions.digest(convert_to('LF_RULE_ABSENT:'||v_rule,'UTF8'),'sha256'),'hex')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps WHERE execution_id=v_parent
 AND step_id='output_validate' AND status='STEP_PASS_WITH_EVIDENCE'
 AND evidence_payload->>'output_contract_result'='PASS')
 THEN RAISE EXCEPTION 'IG_CREATE_PROFILE_PROPOSAL_OR_STEP60_NOT_EXACT'; END IF;

 SELECT * INTO STRICT v_train FROM public.lf_operation_execution e WHERE e.execution_id=v_te
 AND e.operation_code='ACTUALIZACION_DB_LF' AND e.status='COMPLETED'
 AND e.manifest->>'train_run_id'=v_tr
 AND e.updated_by_execution_id='LF-MIGRATION-TRAIN-RUN-'||v_tr;
 SELECT * INTO STRICT v_ev FROM public.lf_eventos evt
 WHERE evt.entidad_codigo=v_te AND evt.evento_tipo='MIGRATION_TRAIN_RECEIPT_RECORDED'
 AND evt.origen='lf-migration-merge-train'
 AND evt.payload#>>'{receipt,train_run_id}'=v_tr
 AND evt.payload#>>'{receipt,heads,final_head}'=v_train.manifest->>'head_sha'
 AND evt.payload#>>'{receipt,heads,final_head_is_execution_head}'='true'
 AND evt.payload#>>'{receipt,terminal_status}'='COMPLETED'
 AND evt.payload#>>'{receipt,parity,migration_source_parity}'='PASS'
 AND evt.payload#>>'{receipt,ledger_readback,matches_target}'='true'
 AND encode(extensions.digest(convert_to((evt.payload->'receipt')::text,'UTF8'),'sha256'),'hex')
 =evt.payload->>'receipt_sha256';
 IF NOT EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations
   WHERE version='20261119103331' AND name='lf_ig_pg17_screen_create_contract_proof_v1')
 OR NOT EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations
   WHERE version='20261119093701' AND name='lf_rule_create_onboarding_layer1_pg17_v1')
 OR NOT EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations
   WHERE version='20261119100514' AND name='lf_ig_v2_create_phase2_pilot_fence_pg17_v1')
 THEN RAISE EXCEPTION 'IG_CREATE_TRAIN_PROOF_OR_GUARD_LEDGER_MISSING'; END IF;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.codigo)::text,'[]')) INTO v_old_md5 FROM lf_ops.reglas r;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(h) ORDER BY h.codigo,h.version)::text,'[]')) INTO v_hist_md5 FROM lf_ops.reglas_versiones h;

 -- Evidence hashes are computed from the observed, signed PG17 train apply and current readback,
 -- not hardcoded, guessed, or modeled as a provider receipt.
 v_candidate_sha:=encode(extensions.digest(convert_to(
   jsonb_build_object('rule_code',v_rule,'candidate_state','CANDIDATO',
    'change_kind','CREATE','candidate_changes',v_patch->'changes')::text,'UTF8'),'sha256'),'hex');
 v_pg_sha:=encode(extensions.digest(convert_to((v_ev.payload#>'{receipt,apply}')::text,'UTF8'),'sha256'),'hex');
 v_readback_sha:=encode(extensions.digest(convert_to(
   jsonb_build_object('rules_md5',v_old_md5,'history_md5',v_hist_md5,
      'profile_run',v_parent,'proposal_sha',v_patch_sha,'source_sha',v_source,
      'signed_train_event_id',v_ev.id,'train_head',v_train.manifest->>'head_sha')::text,
   'UTF8'),'sha256'),'hex');
 v_manifest_sha:=encode(extensions.digest(convert_to(
   jsonb_build_object('proof','RULE_CONTRACT_LEVEL','pg17_train',v_tr,
      'train_event',v_ev.id,'screen_id',v_screen_id,
      'scope','PANTALLA','patch_sha',v_sha,
      'negative_contract_cases',2,'historical_writer_negative_cases',8)::text,
   'UTF8'),'sha256'),'hex');
 INSERT INTO public.lf_ig_functional_train_evidence_v1(
   rule_code,source_snapshot_sha256,proposal_sha256,candidate_snapshot_sha256,
   train_execution_id,train_run_id,train_event_id,train_head_sha,
   pg_rollback_status,independent_readback_status,functional_checks_status,
   negative_checks_status,pg_report_sha256,readback_sha256,check_manifest_sha256,report_ref
 ) VALUES (
   v_rule,v_source,v_patch_sha,v_candidate_sha,
   v_te,v_tr,v_ev.id,v_train.manifest->>'head_sha',
   'PASS','PASS','PASS','PASS',
   v_pg_sha,v_readback_sha,v_manifest_sha,v_ref);

 -- Entire canonical Step70/decision/skill/writer is inside a real PL/pgSQL subtransaction.
 -- A success sentinel forces ROLLBACK of all effects from that subtransaction.
 BEGIN
   v_auto:=public.lf_ig_step70_functional_train_auto_v1(v_parent);
   IF v_auto->>'status' IS DISTINCT FROM 'PASS'
   THEN RAISE EXCEPTION 'IG_CREATE_AUTO_STEP70_NOT_PASS:%',v_auto; END IF;
   v_bridge:=public.lf_profile_native_bridge_record_semantic_v1(v_parent,v_auto,v_ref,v_parent);
   IF v_bridge->>'status' IS DISTINCT FROM 'SEMANTIC_JUDGE_RECORDED'
   THEN RAISE EXCEPTION 'IG_CREATE_BRIDGE_STEP70_BLOCKED:%',v_bridge; END IF;

   -- Negative: real owner V2 must reject mismatched source preimage.
   v_error:=NULL;
   BEGIN
     PERFORM public.lf_ig_rule_owner_decide_v2(v_parent,v_rule,repeat('0',64),
       '{"usuario":"Cristhian Lujan","veredicto":"APROBAR"}'::jsonb);
   EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
   END;
   IF v_error IS NULL OR strpos(v_error,'LF_IG_OWNER_SOURCE_PREIMAGE_DRIFT')=0
   THEN RAISE EXCEPTION 'IG_CREATE_NEGATIVE_OWNER_SHA_NOT_REJECTED:%',coalesce(v_error,'NONE'); END IF;
   v_denied:=true;

   -- Positive: official owner_v2 -> skill_invoke_v1 -> RULE_CREATE_APPLY -> writer -> 7-step readback.
   v_dec:=public.lf_ig_rule_owner_decide_v2(v_parent,v_rule,v_source,
     '{"usuario":"Cristhian Lujan","veredicto":"APROBAR"}'::jsonb);
   IF v_dec->>'status' IS DISTINCT FROM 'APPROVED_AND_CANDIDATO_VERIFIED'
     OR v_dec->>'kind' IS DISTINCT FROM 'CREATE'
     OR v_dec->>'promotion_authorized' IS DISTINCT FROM 'false'
     OR (SELECT count(*) FROM public.lf_operation_execution_steps
         WHERE execution_id=v_dec->>'child_execution_id' AND status='PASS_CLEAN')<>7
     OR NOT EXISTS (SELECT 1 FROM lf_ops.reglas r WHERE r.codigo=v_rule AND r.estado='CANDIDATO'
         AND r.pendiente_decision AND r.valor_config->>'lf_rule_scope'='PANTALLA'
         AND r.valor_config->'lf_screen_ids'='[44]'::jsonb
         AND r.created_by=v_dec->>'child_execution_id')
     OR NOT EXISTS (SELECT 1 FROM public.lf_ig_rule_change_v2 ch
         WHERE ch.parent_execution_id=v_parent AND ch.child_execution_id=v_dec->>'child_execution_id'
           AND ch.rule_code=v_rule AND ch.kind='CREATE' AND ch.state='CANDIDATE_VERIFIED')
     OR EXISTS(SELECT 1 FROM public.lf_rule_promotion_v1 WHERE rule_code=v_rule)
   THEN RAISE EXCEPTION 'IG_CREATE_REAL_POSITIVE_CHILD_OR_READBACK_FAILED:%',v_dec; END IF;
   IF (SELECT count(*) FROM lf_ops.reglas)<>v_rule_count+1 THEN
      RAISE EXCEPTION 'IG_CREATE_TEST_RULE_COUNT_NOT_PLUS_ONE'; END IF;
   RAISE NOTICE 'IG_CREATE_REAL_POSITIVE_VERIFIED:rule=% child=% status=CANDIDATO steps=7 scope=PANTALLA screen_id=%',
      v_rule,v_dec->>'child_execution_id',v_screen_id;
   RAISE EXCEPTION 'IG_CREATE_PG17_POSITIVE_ROLLBACK_SENTINEL';
 EXCEPTION WHEN OTHERS THEN
   IF SQLERRM='IG_CREATE_PG17_POSITIVE_ROLLBACK_SENTINEL' THEN
     v_positive:=true;
     RAISE NOTICE 'IG_CREATE_PG17_SUBTRANSACTION_ROLLBACK_PASS';
   ELSE
     RAISE EXCEPTION 'IG_CREATE_PG17_REAL_FUNC_BLOCKED:%',SQLERRM;
   END IF;
 END;

 -- All effects in nested subtransaction must be gone, including Step70 and child.
 SELECT md5(coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.codigo)::text,'[]')) INTO v_after_md5 FROM lf_ops.reglas r;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(h) ORDER BY h.codigo,h.version)::text,'[]')) INTO v_hist_after FROM lf_ops.reglas_versiones h;
 IF NOT v_positive OR NOT v_denied OR v_after_md5 IS DISTINCT FROM v_old_md5
 OR v_hist_after IS DISTINCT FROM v_hist_md5
 OR EXISTS (SELECT 1 FROM lf_ops.reglas WHERE codigo=v_rule)
 OR EXISTS (SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE rule_code=v_rule)
 OR EXISTS (SELECT 1 FROM public.lf_operation_execution_steps
   WHERE execution_id=v_parent AND step_id='semantic_judge')
 THEN RAISE EXCEPTION 'IG_CREATE_PG17_POST_ROLLBACK_READBACK_FAILED'; END IF;
 RAISE NOTICE 'IG_CREATE_PG17_REAL_OWNER_CREATE_PASS:negative_sha=1 positive_pantalla=1 rollback=PASS history_untouched=true';
END;
$lf_ig_pg17_owner_create$;
ROLLBACK;
-- No rule, decision, skill, promotion or train evidence persists. Merge Train ledger records test source only.
