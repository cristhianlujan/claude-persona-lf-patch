-- Prueba E2E de Profile Updater (paso ruta efectiva): begin + lf_profile_update_effective_route_v1 sobre el perfil real,
-- dentro de un subbloque que SIEMPRE se revierte. Sin efecto persistente. Termina siempre con una excepcion que lleva el resultado.
DO $mig$
DECLARE
 c_exec constant text := 'EXEC-E2E-ROUTE-DRYRUN-20261028-V1';
 v_train text; v_n_after int; v_e1 text; v_e2 text; v_e3 text;
 v_snap jsonb; v_route jsonb; v_neg jsonb;
BEGIN
 SELECT execution_id INTO v_train FROM public.lf_operation_execution
 WHERE operation_code='ACTUALIZACION_DB_LF' AND target_type='MIGRATION'
  AND target_code LIKE '%lf_e2e_effective_route_dry_run_v1' AND status='IN_PROGRESS' ORDER BY created_at DESC LIMIT 1;
 IF v_train IS NULL THEN RAISE EXCEPTION 'E2E_ROUTE_TRAIN_TRANSPORT_REQUIRED'; END IF;
 IF EXISTS (SELECT 1 FROM public.lf_operation_execution WHERE execution_id=c_exec) THEN RAISE EXCEPTION 'E2E_ROUTE_PRESTATE_INVALID'; END IF;

 BEGIN
   BEGIN
     PERFORM public.lf_profile_update_begin_v1(c_exec,'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF','cristhianlujan/claude-persona-lf-patch',
        'profiles/systemic_root_cause_repair_lf/SKILL.md',repeat('b',64),'idem-e2e-route-20261028',v_train,'{}'::jsonb);
   EXCEPTION WHEN OTHERS THEN v_e1 := SQLERRM; END;
   SELECT jsonb_build_object('pol',e.manifest#>>'{operation_policy_snapshots,PASS_POLICY,policy_code}',
            'ver',e.manifest#>>'{operation_policy_snapshots,PASS_POLICY,policy_version}',
            'req',jsonb_typeof(e.manifest#>'{operation_policy_snapshots,PASS_POLICY,policy_payload,required_steps}'),
            'byout',jsonb_typeof(e.manifest#>'{operation_policy_snapshots,PASS_POLICY,policy_payload,required_steps_by_outcome}'))
     INTO v_snap FROM public.lf_operation_execution e WHERE e.execution_id=c_exec;
   BEGIN v_route := public.lf_profile_update_effective_route_v1(c_exec);
   EXCEPTION WHEN OTHERS THEN v_e2 := SQLERRM; END;
   BEGIN v_neg := public.lf_profile_update_effective_route_v1('EXEC-NO-EXISTE-E2E');
   EXCEPTION WHEN OTHERS THEN v_e3 := SQLERRM; END;
   RAISE EXCEPTION 'E2E_FORCED_ROLLBACK';
 EXCEPTION WHEN OTHERS THEN
   IF SQLERRM <> 'E2E_FORCED_ROLLBACK' THEN RAISE; END IF;
 END;

 SELECT count(*) INTO v_n_after FROM public.lf_operation_execution WHERE execution_id=c_exec;
 RAISE EXCEPTION 'E2E_ROUTE_RESULT %', jsonb_build_object('begin_err',v_e1,'snap',v_snap,'neg_err',v_e3,'neg',v_neg,'route_err',v_e2,'tras_rollback',v_n_after,'route',v_route);
END
$mig$;
