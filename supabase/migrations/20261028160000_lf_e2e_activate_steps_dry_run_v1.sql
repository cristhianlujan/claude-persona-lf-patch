-- Prueba E2E de Profile Updater: activar method_selection y evolution_decision (pasos + jueces) SOLO dentro de subbloques que
-- SIEMPRE se revierten, y medir la ruta efectiva en dos escenarios:
--   A) politica vigente v1.1 con los pasos activos: debe seguir LEGACY_FROZEN (no romper el camino actual).
--   B) politica candidata v1.4 con los pasos activos: debe dar AWAITING_EVOLUTION_DECISION.
-- Sin efecto persistente. Termina siempre con una excepcion que lleva el resultado.
DO $mig$
DECLARE
 v_train text; v_fp_before text; v_fp_after text;
 v_a_err text; v_a_ver text; v_a jsonb; v_a_n int;
 v_b_err text; v_b_ver text; v_b jsonb; v_b_n int;
BEGIN
 SELECT execution_id INTO v_train FROM public.lf_operation_execution
 WHERE operation_code='ACTUALIZACION_DB_LF' AND target_type='MIGRATION'
  AND target_code LIKE '%lf_e2e_activate_steps_dry_run_v1' AND status='IN_PROGRESS' ORDER BY created_at DESC LIMIT 1;
 IF v_train IS NULL THEN RAISE EXCEPTION 'E2E_STEPS_TRAIN_TRANSPORT_REQUIRED'; END IF;
 IF EXISTS (SELECT 1 FROM public.lf_operation_execution WHERE execution_id IN ('EXEC-E2E-STEPS-A-20261028-V1','EXEC-E2E-STEPS-B-20261028-V1')) THEN
   RAISE EXCEPTION 'E2E_STEPS_PRESTATE_INVALID'; END IF;
 SELECT md5(coalesce((SELECT string_agg(to_jsonb(s)::text,'|' ORDER BY s.step_id) FROM public.lf_operation_steps s WHERE operation_code='ACTUALIZACION_PERFIL_LF'),'')||
            coalesce((SELECT string_agg(to_jsonb(b)::text,'|' ORDER BY b.step_id) FROM public.lf_operation_step_judge_bindings b WHERE operation_code='ACTUALIZACION_PERFIL_LF'),'')||
            coalesce((SELECT string_agg(policy_version||status,'|' ORDER BY policy_version) FROM public.lf_policy_versions WHERE policy_code='POL-PROFILE-UPDATE-PASS'),'')) INTO v_fp_before;

 -- Escenario A: pasos activos + politica vigente v1.1
 BEGIN
   BEGIN
     UPDATE public.lf_operation_steps SET active=true WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND step_id IN ('method_selection','evolution_decision');
     UPDATE public.lf_operation_step_judge_bindings SET status='ACTIVE_ENFORCEMENT' WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND step_id IN ('method_selection','evolution_decision');
     PERFORM public.lf_profile_update_begin_v1('EXEC-E2E-STEPS-A-20261028-V1','PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF','cristhianlujan/claude-persona-lf-patch',
        'profiles/systemic_root_cause_repair_lf/SKILL.md',repeat('d',64),'idem-e2e-steps-a-20261028',v_train,'{}'::jsonb);
     SELECT e.manifest#>>'{operation_policy_snapshots,PASS_POLICY,policy_version}' INTO v_a_ver FROM public.lf_operation_execution e WHERE e.execution_id='EXEC-E2E-STEPS-A-20261028-V1';
     v_a := public.lf_profile_update_effective_route_v1('EXEC-E2E-STEPS-A-20261028-V1');
   EXCEPTION WHEN OTHERS THEN v_a_err := SQLERRM; END;
   RAISE EXCEPTION 'E2E_FORCED_ROLLBACK';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'E2E_FORCED_ROLLBACK' THEN RAISE; END IF; END;

 -- Escenario B: pasos activos + politica candidata v1.4
 BEGIN
   BEGIN
     UPDATE public.lf_operation_steps SET active=true WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND step_id IN ('method_selection','evolution_decision');
     UPDATE public.lf_operation_step_judge_bindings SET status='ACTIVE_ENFORCEMENT' WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND step_id IN ('method_selection','evolution_decision');
     UPDATE public.lf_policy_versions SET status='SUPERSEDED' WHERE policy_code='POL-PROFILE-UPDATE-PASS' AND policy_version='v1.1';
     UPDATE public.lf_policy_versions SET status='ACTIVE' WHERE policy_code='POL-PROFILE-UPDATE-PASS' AND policy_version='v1.4-evolved-routing-candidate';
     PERFORM public.lf_profile_update_begin_v1('EXEC-E2E-STEPS-B-20261028-V1','PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF','cristhianlujan/claude-persona-lf-patch',
        'profiles/systemic_root_cause_repair_lf/SKILL.md',repeat('e',64),'idem-e2e-steps-b-20261028',v_train,'{}'::jsonb);
     SELECT e.manifest#>>'{operation_policy_snapshots,PASS_POLICY,policy_version}' INTO v_b_ver FROM public.lf_operation_execution e WHERE e.execution_id='EXEC-E2E-STEPS-B-20261028-V1';
     v_b := public.lf_profile_update_effective_route_v1('EXEC-E2E-STEPS-B-20261028-V1');
   EXCEPTION WHEN OTHERS THEN v_b_err := SQLERRM; END;
   RAISE EXCEPTION 'E2E_FORCED_ROLLBACK';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'E2E_FORCED_ROLLBACK' THEN RAISE; END IF; END;

 SELECT md5(coalesce((SELECT string_agg(to_jsonb(s)::text,'|' ORDER BY s.step_id) FROM public.lf_operation_steps s WHERE operation_code='ACTUALIZACION_PERFIL_LF'),'')||
            coalesce((SELECT string_agg(to_jsonb(b)::text,'|' ORDER BY b.step_id) FROM public.lf_operation_step_judge_bindings b WHERE operation_code='ACTUALIZACION_PERFIL_LF'),'')||
            coalesce((SELECT string_agg(policy_version||status,'|' ORDER BY policy_version) FROM public.lf_policy_versions WHERE policy_code='POL-PROFILE-UPDATE-PASS'),'')) INTO v_fp_after;
 SELECT count(*) INTO v_a_n FROM public.lf_operation_execution WHERE execution_id='EXEC-E2E-STEPS-A-20261028-V1';
 SELECT count(*) INTO v_b_n FROM public.lf_operation_execution WHERE execution_id='EXEC-E2E-STEPS-B-20261028-V1';

 RAISE EXCEPTION 'E2E_STEPS_RESULT %', jsonb_build_object('intacto',v_fp_before=v_fp_after,'rollback_filas',v_a_n+v_b_n,
   'A_err',v_a_err,'A_pol',v_a_ver,'A',v_a->>'outcome','A_pasos',jsonb_array_length(v_a->'effective_steps'),
   'B_err',v_b_err,'B_pol',v_b_ver,'B_pasos',jsonb_array_length(v_b->'effective_steps'),'B',v_b);
END
$mig$;
