-- Prueba E2E de Profile Updater: ruta efectiva con la politica candidata v1.4-evolved-routing, SOLO dentro de un subbloque que
-- SIEMPRE se revierte (v1.4 activa y v1.1 reemplazada unicamente dentro del subbloque). Sin efecto persistente.
-- Termina siempre con una excepcion que lleva el resultado.
DO $mig$
DECLARE
 c_exec constant text := 'EXEC-E2E-ROUTEV14-DRYRUN-20261028-V1';
 v_train text; v_n_after int; v_pol_before text; v_pol_after text; v_e0 text; v_e1 text; v_e2 text; v_ver text; v_route jsonb;
BEGIN
 SELECT execution_id INTO v_train FROM public.lf_operation_execution
 WHERE operation_code='ACTUALIZACION_DB_LF' AND target_type='MIGRATION'
  AND target_code LIKE '%lf_e2e_route_v14_dry_run_v1' AND status='IN_PROGRESS' ORDER BY created_at DESC LIMIT 1;
 IF v_train IS NULL THEN RAISE EXCEPTION 'E2E_ROUTEV14_TRAIN_TRANSPORT_REQUIRED'; END IF;
 IF EXISTS (SELECT 1 FROM public.lf_operation_execution WHERE execution_id=c_exec) THEN RAISE EXCEPTION 'E2E_ROUTEV14_PRESTATE_INVALID'; END IF;
 SELECT string_agg(policy_version||'='||status,',' ORDER BY policy_version) INTO v_pol_before FROM public.lf_policy_versions WHERE policy_code='POL-PROFILE-UPDATE-PASS';

 BEGIN
   BEGIN
     UPDATE public.lf_policy_versions SET status='SUPERSEDED' WHERE policy_code='POL-PROFILE-UPDATE-PASS' AND policy_version='v1.1';
     UPDATE public.lf_policy_versions SET status='ACTIVE' WHERE policy_code='POL-PROFILE-UPDATE-PASS' AND policy_version='v1.4-evolved-routing-candidate';
   EXCEPTION WHEN OTHERS THEN v_e0 := SQLERRM; END;
   BEGIN
     PERFORM public.lf_profile_update_begin_v1(c_exec,'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF','cristhianlujan/claude-persona-lf-patch',
        'profiles/systemic_root_cause_repair_lf/SKILL.md',repeat('c',64),'idem-e2e-routev14-20261028',v_train,'{}'::jsonb);
   EXCEPTION WHEN OTHERS THEN v_e1 := SQLERRM; END;
   SELECT e.manifest#>>'{operation_policy_snapshots,PASS_POLICY,policy_version}' INTO v_ver FROM public.lf_operation_execution e WHERE e.execution_id=c_exec;
   BEGIN v_route := public.lf_profile_update_effective_route_v1(c_exec);
   EXCEPTION WHEN OTHERS THEN v_e2 := SQLERRM; END;
   RAISE EXCEPTION 'E2E_FORCED_ROLLBACK';
 EXCEPTION WHEN OTHERS THEN
   IF SQLERRM <> 'E2E_FORCED_ROLLBACK' THEN RAISE; END IF;
 END;

 SELECT count(*) INTO v_n_after FROM public.lf_operation_execution WHERE execution_id=c_exec;
 SELECT string_agg(policy_version||'='||status,',' ORDER BY policy_version) INTO v_pol_after FROM public.lf_policy_versions WHERE policy_code='POL-PROFILE-UPDATE-PASS';
 RAISE EXCEPTION 'E2E_ROUTEV14_RESULT %', jsonb_build_object('politicas_intactas',v_pol_before=v_pol_after,'tras_rollback',v_n_after,
   'err_politica',v_e0,'err_begin',v_e1,'err_ruta',v_e2,'politica_enlazada',v_ver,'ruta',v_route);
END
$mig$;
