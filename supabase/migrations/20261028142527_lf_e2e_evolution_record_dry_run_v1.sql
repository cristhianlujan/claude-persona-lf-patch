-- Prueba E2E de Profile Updater: registrar los pasos previos y method_selection / evolution_decision (UPDATE) con v1.4 activa,
-- usando el recibo PROFILE_ASSESSMENT verificado real del perfil, SOLO dentro de un subbloque que SIEMPRE se revierte.
-- Pasos, jueces, contratos y politicas se activan unicamente dentro del subbloque. Sin efecto persistente.
-- Termina siempre con una excepcion que lleva el resultado compacto.
DO $mig$
DECLARE
 c_exec constant text := 'EXEC-E2E-EVOREC-20261028-V1';
 c_head constant text := '8dabb3a1bfd68dc90b78b09233000bce92d35ee9';
 c_rcpt constant text := '9f758577-c9f6-4744-852b-a03827b466f6';
 c_rsha constant text := '692618756e551011b52487bc7091ed5f14f166c66f99f9ecea95619c0f5634fc';
 v_train text; v_fp_before text; v_fp_after text; v_n_after int;
 v_setup text; v_begin text; v_res jsonb; v_err text; v_p jsonb; v_k text; s text;
 v_log text[] := array[]::text[]; v_route jsonb; v_route_err text;
BEGIN
 SELECT execution_id INTO v_train FROM public.lf_operation_execution
 WHERE operation_code='ACTUALIZACION_DB_LF' AND target_type='MIGRATION'
  AND target_code LIKE '%lf_e2e_evolution_record_dry_run_v1' AND status='IN_PROGRESS' ORDER BY created_at DESC LIMIT 1;
 IF v_train IS NULL THEN RAISE EXCEPTION 'E2E_EVOREC_TRAIN_TRANSPORT_REQUIRED'; END IF;
 IF EXISTS (SELECT 1 FROM public.lf_operation_execution WHERE execution_id=c_exec) THEN RAISE EXCEPTION 'E2E_EVOREC_PRESTATE_INVALID'; END IF;
 SELECT md5(coalesce((SELECT string_agg(to_jsonb(x)::text,'|' ORDER BY x.step_id) FROM public.lf_operation_steps x WHERE operation_code='ACTUALIZACION_PERFIL_LF'),'')||
            coalesce((SELECT string_agg(to_jsonb(x)::text,'|' ORDER BY x.step_id) FROM public.lf_operation_step_judge_bindings x WHERE operation_code='ACTUALIZACION_PERFIL_LF'),'')||
            coalesce((SELECT string_agg(to_jsonb(x)::text,'|' ORDER BY x.step_id) FROM public.lf_operation_step_contracts x WHERE operation_code='ACTUALIZACION_PERFIL_LF'),'')||
            coalesce((SELECT string_agg(policy_version||status,'|' ORDER BY policy_version) FROM public.lf_policy_versions WHERE policy_code='POL-PROFILE-UPDATE-PASS'),'')) INTO v_fp_before;

 BEGIN
   BEGIN
     UPDATE public.lf_operation_steps SET active=true WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND step_id IN ('method_selection','evolution_decision');
     UPDATE public.lf_operation_step_judge_bindings SET status='ACTIVE_ENFORCEMENT' WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND step_id IN ('method_selection','evolution_decision');
     UPDATE public.lf_operation_step_contracts SET status='ACTIVE_ENFORCEMENT' WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND step_id IN ('method_selection','evolution_decision');
     UPDATE public.lf_policy_versions SET status='SUPERSEDED' WHERE policy_code='POL-PROFILE-UPDATE-PASS' AND policy_version='v1.1';
     UPDATE public.lf_policy_versions SET status='ACTIVE' WHERE policy_code='POL-PROFILE-UPDATE-PASS' AND policy_version='v1.4-evolved-routing-candidate';
   EXCEPTION WHEN OTHERS THEN v_setup := SQLERRM; END;
   BEGIN
     PERFORM public.lf_profile_update_begin_v1(c_exec,'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF','cristhianlujan/claude-persona-lf-patch',
        'profiles/systemic_root_cause_repair_lf/SKILL.md',repeat('f',64),'idem-e2e-evorec-20261028',v_train,
        jsonb_build_object('initial_main_revision',c_head));
   EXCEPTION WHEN OTHERS THEN v_begin := SQLERRM; END;

   FOREACH s IN ARRAY ARRAY['router','profile_resolve','baseline_read','method_selection','evolution_decision'] LOOP
     v_p := '{}'::jsonb;
     FOR v_k IN SELECT jsonb_array_elements_text(b.required_evidence_keys) FROM public.lf_operation_step_judge_bindings b
                WHERE b.operation_code='ACTUALIZACION_PERFIL_LF' AND b.step_id=s AND b.status='ACTIVE_ENFORCEMENT' LOOP
       v_p := v_p || jsonb_build_object(v_k,'e2e-test');
     END LOOP;
     IF s IN ('method_selection','evolution_decision') THEN
       v_p := v_p || jsonb_build_object('profile_slug','systemic_root_cause_repair_lf','source_head_sha',c_head,
              'profile_assessment_receipt_id',c_rcpt,'profile_assessment_sha256',c_rsha,'profile_assessment',jsonb_build_object('result','e2e-test'));
       IF s='method_selection' THEN
         v_p := v_p || jsonb_build_object('selector_version','1.0.0','selected_methods','[]'::jsonb,'no_additional_method_needed',true,
                'empty_selection_reason','e2e-test','method_execution_permitted',false);
       ELSE
         v_p := v_p || jsonb_build_object('decision','UPDATE','evolution_mode','PATCH','decision_evidence_ref','e2e-test','github_write_permitted',false);
       END IF;
     END IF;
     v_err := NULL; v_res := NULL;
     BEGIN v_res := public.lf_record_profile_operation_step_v1(c_exec,s,'e2e://'||s,v_p,v_train);
     EXCEPTION WHEN OTHERS THEN v_err := left(SQLERRM,120); END;
     v_log := v_log || (s||'='||coalesce(v_res->>'outcome','ERR')||coalesce(':'||(v_res->>'code'),'')||coalesce(':'||v_err,''));
   END LOOP;

   BEGIN v_route := public.lf_profile_update_effective_route_v1(c_exec);
   EXCEPTION WHEN OTHERS THEN v_route_err := left(SQLERRM,120); END;
   RAISE EXCEPTION 'E2E_FORCED_ROLLBACK';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'E2E_FORCED_ROLLBACK' THEN RAISE; END IF; END;

 SELECT md5(coalesce((SELECT string_agg(to_jsonb(x)::text,'|' ORDER BY x.step_id) FROM public.lf_operation_steps x WHERE operation_code='ACTUALIZACION_PERFIL_LF'),'')||
            coalesce((SELECT string_agg(to_jsonb(x)::text,'|' ORDER BY x.step_id) FROM public.lf_operation_step_judge_bindings x WHERE operation_code='ACTUALIZACION_PERFIL_LF'),'')||
            coalesce((SELECT string_agg(to_jsonb(x)::text,'|' ORDER BY x.step_id) FROM public.lf_operation_step_contracts x WHERE operation_code='ACTUALIZACION_PERFIL_LF'),'')||
            coalesce((SELECT string_agg(policy_version||status,'|' ORDER BY policy_version) FROM public.lf_policy_versions WHERE policy_code='POL-PROFILE-UPDATE-PASS'),'')) INTO v_fp_after;
 SELECT count(*) INTO v_n_after FROM public.lf_operation_execution WHERE execution_id=c_exec;

 RAISE EXCEPTION 'E2E_EVOREC_RESULT %', jsonb_build_object('intacto',v_fp_before=v_fp_after,'rollback_filas',v_n_after,
   'setup_err',v_setup,'begin_err',v_begin,'ruta_err',v_route_err,'ruta_resultado',v_route->>'outcome','ruta_pasos',jsonb_array_length(v_route->'effective_steps'),
   'registros',to_jsonb(v_log));
END
$mig$;
