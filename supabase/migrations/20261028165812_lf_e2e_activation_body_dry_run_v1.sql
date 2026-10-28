-- Prueba E2E: ejecuta el CUERPO EXACTO de la migracion de activacion dentro de un subbloque que SIEMPRE se revierte y comprueba el resultado.
-- Sin efecto persistente. Termina siempre con una excepcion que lleva el resultado compacto.
DO $mig$
DECLARE
 v_train text; v_fp_before text; v_fp_after text; v_body_err text; v_begin text; v_route jsonb; v_route_err text; v_pol text; v_n_after int;
 c_exec constant text := 'EXEC-E2E-ACTBODY-20261028-V1';
BEGIN
 SELECT execution_id INTO v_train FROM public.lf_operation_execution
 WHERE operation_code='ACTUALIZACION_DB_LF' AND target_type='MIGRATION'
  AND target_code LIKE '%lf_e2e_activation_body_dry_run_v1' AND status='IN_PROGRESS' ORDER BY created_at DESC LIMIT 1;
 IF v_train IS NULL THEN RAISE EXCEPTION 'E2E_ACTBODY_TRAIN_TRANSPORT_REQUIRED'; END IF;
 SELECT md5(coalesce((SELECT string_agg(to_jsonb(x)::text,'|' ORDER BY x.step_id) FROM public.lf_operation_steps x WHERE operation_code='ACTUALIZACION_PERFIL_LF'),'')||
            coalesce((SELECT string_agg(to_jsonb(x)::text,'|' ORDER BY x.step_id) FROM public.lf_operation_step_judge_bindings x WHERE operation_code='ACTUALIZACION_PERFIL_LF'),'')||
            coalesce((SELECT string_agg(to_jsonb(x)::text,'|' ORDER BY x.step_id) FROM public.lf_operation_step_contracts x WHERE operation_code='ACTUALIZACION_PERFIL_LF'),'')||
            coalesce((SELECT string_agg(to_jsonb(x)::text,'|' ORDER BY x.judge_code) FROM public.lf_operation_judges x WHERE operation_code='ACTUALIZACION_PERFIL_LF'),'')||
            coalesce((SELECT string_agg(policy_version||status,'|' ORDER BY policy_version) FROM public.lf_policy_versions WHERE policy_code='POL-PROFILE-UPDATE-PASS'),'')) INTO v_fp_before;
 BEGIN
   BEGIN
     EXECUTE $q$DO $body$
DECLARE
 v_n int; v_active int;
BEGIN
 -- Estado previo exigido: nada de la evolucion esta activo todavia.
 IF (SELECT count(*) FROM public.lf_policy_versions WHERE policy_code='POL-PROFILE-UPDATE-PASS' AND policy_version='v1.1' AND status='ACTIVE')<>1
    OR (SELECT count(*) FROM public.lf_policy_versions WHERE policy_code='POL-PROFILE-UPDATE-PASS' AND policy_version='v1.4-evolved-routing-candidate' AND status='CANDIDATE' AND policy_sha LIKE '5ae6804ded17%')<>1
    OR (SELECT count(*) FROM public.lf_operation_steps WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND step_id IN ('method_selection','evolution_decision') AND active IS FALSE)<>2
    OR (SELECT count(*) FROM public.lf_operation_step_judge_bindings WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND step_id IN ('method_selection','evolution_decision') AND status='CANDIDATE')<>2
    OR (SELECT count(*) FROM public.lf_operation_step_contracts WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND step_id IN ('method_selection','evolution_decision') AND status='CANDIDATE')<>2
    OR (SELECT count(*) FROM public.lf_operation_judges WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND judge_code IN ('JUDGE-PE10-V02-METHOD-SELECTION','JUDGE-PE10-V02-EVOLUTION-DECISION') AND status='CANDIDATO_READ_ONLY')<>2
 THEN RAISE EXCEPTION 'PE10_ACTIVATE_PRESTATE_INVALID'; END IF;

 UPDATE public.lf_operation_steps SET active=true WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND step_id IN ('method_selection','evolution_decision');
 UPDATE public.lf_operation_step_judge_bindings SET status='ACTIVE_ENFORCEMENT' WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND step_id IN ('method_selection','evolution_decision');
 UPDATE public.lf_operation_step_contracts SET status='ACTIVE_ENFORCEMENT' WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND step_id IN ('method_selection','evolution_decision');
 UPDATE public.lf_operation_judges SET status='ACTIVE_ENFORCEMENT' WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND judge_code IN ('JUDGE-PE10-V02-METHOD-SELECTION','JUDGE-PE10-V02-EVOLUTION-DECISION');
 UPDATE public.lf_policy_versions SET status='SUPERSEDED' WHERE policy_code='POL-PROFILE-UPDATE-PASS' AND policy_version='v1.1';
 UPDATE public.lf_policy_versions SET status='ACTIVE' WHERE policy_code='POL-PROFILE-UPDATE-PASS' AND policy_version='v1.4-evolved-routing-candidate';

 -- Readback: exactamente lo esperado y una sola politica activa.
 SELECT count(*) INTO v_active FROM public.lf_policy_versions WHERE policy_code='POL-PROFILE-UPDATE-PASS' AND status='ACTIVE';
 IF v_active<>1
    OR (SELECT count(*) FROM public.lf_policy_versions WHERE policy_code='POL-PROFILE-UPDATE-PASS' AND policy_version='v1.4-evolved-routing-candidate' AND status='ACTIVE')<>1
    OR (SELECT count(*) FROM public.lf_operation_steps WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND step_id IN ('method_selection','evolution_decision') AND active AND required)<>2
    OR (SELECT count(*) FROM public.lf_operation_step_judge_bindings WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND step_id IN ('method_selection','evolution_decision') AND status='ACTIVE_ENFORCEMENT')<>2
    OR (SELECT count(*) FROM public.lf_operation_step_contracts WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND step_id IN ('method_selection','evolution_decision') AND status='ACTIVE_ENFORCEMENT')<>2
    OR (SELECT count(*) FROM public.lf_operation_judges WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND judge_code IN ('JUDGE-PE10-V02-METHOD-SELECTION','JUDGE-PE10-V02-EVOLUTION-DECISION') AND status='ACTIVE_ENFORCEMENT')<>2
 THEN RAISE EXCEPTION 'PE10_ACTIVATE_READBACK_FAILED'; END IF;
END
$body$;$q$;
   EXCEPTION WHEN OTHERS THEN v_body_err := left(SQLERRM,100); END;
   BEGIN
     PERFORM public.lf_profile_update_begin_v1(c_exec,'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF','cristhianlujan/claude-persona-lf-patch',
        'profiles/systemic_root_cause_repair_lf/SKILL.md',repeat('9',64),'idem-e2e-actbody-20261028',v_train,
        jsonb_build_object('initial_main_revision','8dabb3a1bfd68dc90b78b09233000bce92d35ee9'));
   EXCEPTION WHEN OTHERS THEN v_begin := left(SQLERRM,80); END;
   SELECT e.manifest#>>'{operation_policy_snapshots,PASS_POLICY,policy_version}' INTO v_pol FROM public.lf_operation_execution e WHERE e.execution_id=c_exec;
   BEGIN v_route := public.lf_profile_update_effective_route_v1(c_exec);
   EXCEPTION WHEN OTHERS THEN v_route_err := left(SQLERRM,80); END;
   RAISE EXCEPTION 'E2E_FORCED_ROLLBACK';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'E2E_FORCED_ROLLBACK' THEN RAISE; END IF; END;
 SELECT md5(coalesce((SELECT string_agg(to_jsonb(x)::text,'|' ORDER BY x.step_id) FROM public.lf_operation_steps x WHERE operation_code='ACTUALIZACION_PERFIL_LF'),'')||
            coalesce((SELECT string_agg(to_jsonb(x)::text,'|' ORDER BY x.step_id) FROM public.lf_operation_step_judge_bindings x WHERE operation_code='ACTUALIZACION_PERFIL_LF'),'')||
            coalesce((SELECT string_agg(to_jsonb(x)::text,'|' ORDER BY x.step_id) FROM public.lf_operation_step_contracts x WHERE operation_code='ACTUALIZACION_PERFIL_LF'),'')||
            coalesce((SELECT string_agg(to_jsonb(x)::text,'|' ORDER BY x.judge_code) FROM public.lf_operation_judges x WHERE operation_code='ACTUALIZACION_PERFIL_LF'),'')||
            coalesce((SELECT string_agg(policy_version||status,'|' ORDER BY policy_version) FROM public.lf_policy_versions WHERE policy_code='POL-PROFILE-UPDATE-PASS'),'')) INTO v_fp_after;
 SELECT count(*) INTO v_n_after FROM public.lf_operation_execution WHERE execution_id=c_exec;
 RAISE EXCEPTION 'E2E_ACTBODY %', jsonb_build_object('intacto',v_fp_before=v_fp_after,'filas',v_n_after,'cuerpo_err',v_body_err,'begin_err',v_begin,
    'politica_enlazada',v_pol,'ruta',coalesce(v_route->>'outcome',v_route_err),'ruta_pasos',jsonb_array_length(v_route->'effective_steps'));
END
$mig$;
