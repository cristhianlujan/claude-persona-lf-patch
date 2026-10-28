-- Prueba E2E de Profile Updater: CIERRE COMPLETO hasta report_output en dos escenarios, SOLO dentro de subbloques que SIEMPRE se revierten:
--   A) politica vigente v1.1 + pasos/jueces/contratos PE10 activos (el camino actual no debe romperse: 15 pasos).
--   B) politica candidata v1.4 + PE10 activos (ruta UPDATE de 17 pasos).
-- Sin efecto persistente. Termina siempre con una excepcion que lleva el resultado compacto.
DO $mig$
DECLARE
 c_head constant text := '8dabb3a1bfd68dc90b78b09233000bce92d35ee9';
 c_rcpt constant text := '9f758577-c9f6-4744-852b-a03827b466f6';
 c_rsha constant text := '692618756e551011b52487bc7091ed5f14f166c66f99f9ecea95619c0f5634fc';
 c_repo constant text := 'cristhianlujan/claude-persona-lf-patch';
 c_path constant text := 'profiles/systemic_root_cause_repair_lf/SKILL.md';
 v_train text; v_fp_before text; v_fp_after text; v_n_after int;
 sc int; v_exec text; v_steps text[]; s text; v_p jsonb; v_k text; v_pass jsonb; v_res jsonb; v_err text;
 v_ok int; v_fail text; v_status text; v_setup text; v_begin text; v_out jsonb := '{}'::jsonb; v_trust jsonb;
BEGIN
 SELECT execution_id INTO v_train FROM public.lf_operation_execution
 WHERE operation_code='ACTUALIZACION_DB_LF' AND target_type='MIGRATION'
  AND target_code LIKE '%lf_e2e_full_close_dry_run_v1' AND status='IN_PROGRESS' ORDER BY created_at DESC LIMIT 1;
 IF v_train IS NULL THEN RAISE EXCEPTION 'E2E_FULL_TRAIN_TRANSPORT_REQUIRED'; END IF;
 IF EXISTS (SELECT 1 FROM public.lf_operation_execution WHERE execution_id IN ('EXEC-E2E-FULL-A-20261028-V1','EXEC-E2E-FULL-B-20261028-V1')) THEN RAISE EXCEPTION 'E2E_FULL_PRESTATE_INVALID'; END IF;
 SELECT md5(coalesce((SELECT string_agg(to_jsonb(x)::text,'|' ORDER BY x.step_id) FROM public.lf_operation_steps x WHERE operation_code='ACTUALIZACION_PERFIL_LF'),'')||
            coalesce((SELECT string_agg(to_jsonb(x)::text,'|' ORDER BY x.step_id) FROM public.lf_operation_step_judge_bindings x WHERE operation_code='ACTUALIZACION_PERFIL_LF'),'')||
            coalesce((SELECT string_agg(to_jsonb(x)::text,'|' ORDER BY x.step_id) FROM public.lf_operation_step_contracts x WHERE operation_code='ACTUALIZACION_PERFIL_LF'),'')||
            coalesce((SELECT string_agg(to_jsonb(x)::text,'|' ORDER BY x.judge_code) FROM public.lf_operation_judges x WHERE operation_code='ACTUALIZACION_PERFIL_LF'),'')||
            coalesce((SELECT string_agg(policy_version||status,'|' ORDER BY policy_version) FROM public.lf_policy_versions WHERE policy_code='POL-PROFILE-UPDATE-PASS'),'')) INTO v_fp_before;

 FOR sc IN 1..2 LOOP
  v_exec := CASE sc WHEN 1 THEN 'EXEC-E2E-FULL-A-20261028-V1' ELSE 'EXEC-E2E-FULL-B-20261028-V1' END;
  v_steps := ARRAY['router','profile_resolve','baseline_read','method_selection','evolution_decision','change_scope','regression_plan',
    'pre_write_execution_binding_gate','github_write','github_readback','deterministic_validation','semantic_judge','regression_after',
    'post_merge_reconcile','close','report_output'];
  IF sc=1 THEN v_steps := array_remove(array_remove(v_steps,'method_selection'),'evolution_decision'); END IF;
  v_ok := 0; v_fail := NULL; v_status := NULL; v_setup := NULL; v_begin := NULL;
  BEGIN
   BEGIN
     UPDATE public.lf_operation_steps SET active=true WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND step_id IN ('method_selection','evolution_decision');
     UPDATE public.lf_operation_step_judge_bindings SET status='ACTIVE_ENFORCEMENT' WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND step_id IN ('method_selection','evolution_decision');
     UPDATE public.lf_operation_step_contracts SET status='ACTIVE_ENFORCEMENT' WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND step_id IN ('method_selection','evolution_decision');
     UPDATE public.lf_operation_judges SET status='ACTIVE_ENFORCEMENT' WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND judge_code IN ('JUDGE-PE10-V02-METHOD-SELECTION','JUDGE-PE10-V02-EVOLUTION-DECISION');
     IF sc=2 THEN
       UPDATE public.lf_policy_versions SET status='SUPERSEDED' WHERE policy_code='POL-PROFILE-UPDATE-PASS' AND policy_version='v1.1';
       UPDATE public.lf_policy_versions SET status='ACTIVE' WHERE policy_code='POL-PROFILE-UPDATE-PASS' AND policy_version='v1.4-evolved-routing-candidate';
     END IF;
   EXCEPTION WHEN OTHERS THEN v_setup := left(SQLERRM,80); END;
   BEGIN
     PERFORM public.lf_profile_update_begin_v1(v_exec,'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF',c_repo,c_path,repeat('f',64),'idem-'||v_exec,v_train,
        jsonb_build_object('initial_main_revision',c_head));
   EXCEPTION WHEN OTHERS THEN v_begin := left(SQLERRM,80); END;

   FOREACH s IN ARRAY v_steps LOOP
     v_p := '{}'::jsonb;
     FOR v_k IN SELECT jsonb_array_elements_text(b.required_evidence_keys) FROM public.lf_operation_step_judge_bindings b
                WHERE b.operation_code='ACTUALIZACION_PERFIL_LF' AND b.step_id=s AND b.status='ACTIVE_ENFORCEMENT' LOOP
       v_p := v_p || jsonb_build_object(v_k,'e2e-test');
     END LOOP;
     IF s IN ('method_selection','evolution_decision') THEN
       SELECT j.pass_if INTO v_pass FROM public.lf_operation_judges j JOIN public.lf_operation_step_judge_bindings b
         ON b.operation_code=j.operation_code AND b.judge_code=j.judge_code
        WHERE b.operation_code='ACTUALIZACION_PERFIL_LF' AND b.step_id=s AND j.status='ACTIVE_ENFORCEMENT';
       v_p := v_p || jsonb_build_object('assertions_checked',coalesce(v_pass,'[]'::jsonb),'hard_fails_checked','[]'::jsonb,
              'profile_slug','systemic_root_cause_repair_lf','source_head_sha',c_head,
              'profile_assessment_receipt_id',c_rcpt,'profile_assessment_sha256',c_rsha,'profile_assessment',jsonb_build_object('result','e2e-test'));
       IF s='method_selection' THEN
         v_p := v_p || jsonb_build_object('selector_version','1.0.0','selected_methods','[]'::jsonb,'no_additional_method_needed',true,
                'empty_selection_reason','e2e-test','method_execution_permitted',false);
       ELSE
         v_p := v_p || jsonb_build_object('decision','UPDATE','evolution_mode','PATCH','decision_evidence_ref','e2e-test','github_write_permitted',false);
       END IF;
     ELSIF s='pre_write_execution_binding_gate' THEN
       v_trust := jsonb_build_object('resolver','GITHUB_PUBLIC_API_EXACT_REF_V1','repository',c_repo,'ref','main','target_path',c_path,
                  'bound_revision',c_head,'continuity_state','CURRENT_BOUND','revision_sha',c_head,'target_blob_sha',c_head,'baseline_revision',c_head);
       v_p := v_p || jsonb_build_object('server_trust_context_valid',true,'server_trust_context_source','run-creacion-perfil-lf',
                  'server_trust_context',v_trust,'bound_revision',c_head,'pre_write_gate_passed',true);
     ELSIF s='github_write' THEN v_p := v_p || jsonb_build_object('identity_preserved',true);
     ELSIF s='github_readback' THEN v_p := v_p || jsonb_build_object('sha_match',true,'identity_preserved',true,'exact_head',c_head);
     ELSIF s='deterministic_validation' THEN v_p := v_p || jsonb_build_object('validator_result','PASS','malformed_input_result','PASS');
     ELSIF s='semantic_judge' THEN v_p := v_p || jsonb_build_object('semantic_judge_result','PASS');
     ELSIF s='regression_after' THEN v_p := v_p || jsonb_build_object('adversarial_result','PASS','holdout_result','PASS');
     ELSIF s='close' THEN v_p := v_p || jsonb_build_object('all_required_steps_clean',true,'runtime_unchanged',true,'no_auto_promotion',true,'open_blockers','[]'::jsonb);
     ELSIF s='report_output' THEN v_p := v_p || jsonb_build_object('open_blockers','[]'::jsonb,'next_gate','e2e-test');
     END IF;
     v_err := NULL; v_res := NULL;
     BEGIN v_res := public.lf_record_profile_operation_step_v1(v_exec,s,'e2e://'||s,v_p,v_train);
     EXCEPTION WHEN OTHERS THEN v_err := replace(left(SQLERRM,100),'LF_PROD_ENFORCEMENT_BLOCK: ',''); END;
     IF v_res->>'outcome'='STEP_RECORDED' THEN v_ok := v_ok+1;
     ELSE v_fail := s||'/'||coalesce(v_res->>'code','ERR')||coalesce('/'||v_err,''); EXIT; END IF;
   END LOOP;
   SELECT status INTO v_status FROM public.lf_operation_execution WHERE execution_id=v_exec;
   v_out := v_out || jsonb_build_object(CASE sc WHEN 1 THEN 'A' ELSE 'B' END,
      jsonb_build_object('ok',v_ok,'de',cardinality(v_steps),'fallo',v_fail,'estado',v_status,'setup',v_setup,'begin',v_begin));
   RAISE EXCEPTION 'E2E_FORCED_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'E2E_FORCED_ROLLBACK' THEN RAISE; END IF; END;
 END LOOP;

 SELECT md5(coalesce((SELECT string_agg(to_jsonb(x)::text,'|' ORDER BY x.step_id) FROM public.lf_operation_steps x WHERE operation_code='ACTUALIZACION_PERFIL_LF'),'')||
            coalesce((SELECT string_agg(to_jsonb(x)::text,'|' ORDER BY x.step_id) FROM public.lf_operation_step_judge_bindings x WHERE operation_code='ACTUALIZACION_PERFIL_LF'),'')||
            coalesce((SELECT string_agg(to_jsonb(x)::text,'|' ORDER BY x.step_id) FROM public.lf_operation_step_contracts x WHERE operation_code='ACTUALIZACION_PERFIL_LF'),'')||
            coalesce((SELECT string_agg(to_jsonb(x)::text,'|' ORDER BY x.judge_code) FROM public.lf_operation_judges x WHERE operation_code='ACTUALIZACION_PERFIL_LF'),'')||
            coalesce((SELECT string_agg(policy_version||status,'|' ORDER BY policy_version) FROM public.lf_policy_versions WHERE policy_code='POL-PROFILE-UPDATE-PASS'),'')) INTO v_fp_after;
 SELECT count(*) INTO v_n_after FROM public.lf_operation_execution WHERE execution_id IN ('EXEC-E2E-FULL-A-20261028-V1','EXEC-E2E-FULL-B-20261028-V1');
 RAISE EXCEPTION 'E2E_FULL %', (v_out || jsonb_build_object('intacto',v_fp_before=v_fp_after,'filas',v_n_after))::text;
END
$mig$;
