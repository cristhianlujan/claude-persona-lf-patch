-- Ensayo de rollback v0.2->v0.1 (PE10A_OP09) y comprobacion de la ejecucion abierta, SOLO dentro de subbloques que SIEMPRE se revierten:
--   1) ejecuta el CUERPO EXACTO de la activacion; 2) intenta una transicion de estado sobre la ejecucion real abierta del UI Architect
--   (no debe ser bloqueada por la politica nueva); 3) aplica el SQL de reversion y compara la huella completa con el estado inicial.
-- Sin efecto persistente. Termina siempre con una excepcion que lleva el resultado compacto.
DO $mig$
DECLARE
 c_open constant text := 'EXEC-ACTUALIZACION-PERFIL-UI-ARCHITECT-ROUTER-RETURN-20261023-001';
 v_train text; v_f0 text[]; v_f1 text[]; v_f2 text[]; v_f3 text[]; v_dif text; v_act_err text; v_tr_err text; v_rev_err text; v_open_before text; v_open_after text; v_sup jsonb;
BEGIN
 SELECT execution_id INTO v_train FROM public.lf_operation_execution
 WHERE operation_code='ACTUALIZACION_DB_LF' AND target_type='MIGRATION'
  AND target_code LIKE '%lf_e2e_activation_rehearsal2_dry_run_v1' AND status='IN_PROGRESS' ORDER BY created_at DESC LIMIT 1;
 IF v_train IS NULL THEN RAISE EXCEPTION 'E2E_REHEARSAL_TRAIN_TRANSPORT_REQUIRED'; END IF;
 SELECT ARRAY[
   md5(coalesce((SELECT string_agg((to_jsonb(x)-'updated_at')::text,'|' ORDER BY x.step_id) FROM public.lf_operation_steps x WHERE operation_code='ACTUALIZACION_PERFIL_LF'),'')),
   md5(coalesce((SELECT string_agg((to_jsonb(x)-'updated_at')::text,'|' ORDER BY x.step_id) FROM public.lf_operation_step_judge_bindings x WHERE operation_code='ACTUALIZACION_PERFIL_LF'),'')),
   md5(coalesce((SELECT string_agg((to_jsonb(x)-'updated_at')::text,'|' ORDER BY x.step_id) FROM public.lf_operation_step_contracts x WHERE operation_code='ACTUALIZACION_PERFIL_LF'),'')),
   md5(coalesce((SELECT string_agg((to_jsonb(x)-'updated_at')::text,'|' ORDER BY x.judge_code) FROM public.lf_operation_judges x WHERE operation_code='ACTUALIZACION_PERFIL_LF'),'')),
   md5(coalesce((SELECT string_agg((to_jsonb(x)-'updated_at')::text,'|' ORDER BY x.policy_version) FROM public.lf_policy_versions x WHERE policy_code='POL-PROFILE-UPDATE-PASS'),'')),
   md5(coalesce((SELECT string_agg(to_jsonb(x)::text,'|' ORDER BY x.step_id) FROM public.lf_operation_steps x WHERE operation_code='ACTUALIZACION_PERFIL_LF'),''))] INTO v_f0;
 SELECT status INTO v_open_before FROM public.lf_operation_execution WHERE execution_id=c_open;
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
   EXCEPTION WHEN OTHERS THEN v_act_err := left(SQLERRM,100); END;
   SELECT ARRAY[
   md5(coalesce((SELECT string_agg((to_jsonb(x)-'updated_at')::text,'|' ORDER BY x.step_id) FROM public.lf_operation_steps x WHERE operation_code='ACTUALIZACION_PERFIL_LF'),'')),
   md5(coalesce((SELECT string_agg((to_jsonb(x)-'updated_at')::text,'|' ORDER BY x.step_id) FROM public.lf_operation_step_judge_bindings x WHERE operation_code='ACTUALIZACION_PERFIL_LF'),'')),
   md5(coalesce((SELECT string_agg((to_jsonb(x)-'updated_at')::text,'|' ORDER BY x.step_id) FROM public.lf_operation_step_contracts x WHERE operation_code='ACTUALIZACION_PERFIL_LF'),'')),
   md5(coalesce((SELECT string_agg((to_jsonb(x)-'updated_at')::text,'|' ORDER BY x.judge_code) FROM public.lf_operation_judges x WHERE operation_code='ACTUALIZACION_PERFIL_LF'),'')),
   md5(coalesce((SELECT string_agg((to_jsonb(x)-'updated_at')::text,'|' ORDER BY x.policy_version) FROM public.lf_policy_versions x WHERE policy_code='POL-PROFILE-UPDATE-PASS'),'')),
   md5(coalesce((SELECT string_agg(to_jsonb(x)::text,'|' ORDER BY x.step_id) FROM public.lf_operation_steps x WHERE operation_code='ACTUALIZACION_PERFIL_LF'),''))] INTO v_f1;
   SELECT jsonb_build_object('v11_superseded_at',(SELECT superseded_at FROM public.lf_policy_versions WHERE policy_code='POL-PROFILE-UPDATE-PASS' AND policy_version='v1.1'),
          'v14_effective_at',(SELECT effective_at FROM public.lf_policy_versions WHERE policy_code='POL-PROFILE-UPDATE-PASS' AND policy_version='v1.4-evolved-routing-candidate')) INTO v_sup;
   BEGIN
     BEGIN
       UPDATE public.lf_operation_execution SET status='BLOCKED' WHERE execution_id=c_open;
     EXCEPTION WHEN OTHERS THEN v_tr_err := left(SQLERRM,120); END;
     RAISE EXCEPTION 'E2E_INNER_ROLLBACK';
   EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'E2E_INNER_ROLLBACK' THEN RAISE; END IF; END;
   BEGIN
     UPDATE public.lf_operation_steps SET active=false WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND step_id IN ('method_selection','evolution_decision');
     UPDATE public.lf_operation_step_judge_bindings SET status='CANDIDATE' WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND step_id IN ('method_selection','evolution_decision');
     UPDATE public.lf_operation_step_contracts SET status='CANDIDATE' WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND step_id IN ('method_selection','evolution_decision');
     UPDATE public.lf_operation_judges SET status='CANDIDATO_READ_ONLY' WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND judge_code IN ('JUDGE-PE10-V02-METHOD-SELECTION','JUDGE-PE10-V02-EVOLUTION-DECISION');
     UPDATE public.lf_policy_versions SET status='CANDIDATE' WHERE policy_code='POL-PROFILE-UPDATE-PASS' AND policy_version='v1.4-evolved-routing-candidate';
     UPDATE public.lf_policy_versions SET status='ACTIVE', superseded_at=NULL WHERE policy_code='POL-PROFILE-UPDATE-PASS' AND policy_version='v1.1';
   EXCEPTION WHEN OTHERS THEN v_rev_err := left(SQLERRM,100); END;
   SELECT ARRAY[
   md5(coalesce((SELECT string_agg((to_jsonb(x)-'updated_at')::text,'|' ORDER BY x.step_id) FROM public.lf_operation_steps x WHERE operation_code='ACTUALIZACION_PERFIL_LF'),'')),
   md5(coalesce((SELECT string_agg((to_jsonb(x)-'updated_at')::text,'|' ORDER BY x.step_id) FROM public.lf_operation_step_judge_bindings x WHERE operation_code='ACTUALIZACION_PERFIL_LF'),'')),
   md5(coalesce((SELECT string_agg((to_jsonb(x)-'updated_at')::text,'|' ORDER BY x.step_id) FROM public.lf_operation_step_contracts x WHERE operation_code='ACTUALIZACION_PERFIL_LF'),'')),
   md5(coalesce((SELECT string_agg((to_jsonb(x)-'updated_at')::text,'|' ORDER BY x.judge_code) FROM public.lf_operation_judges x WHERE operation_code='ACTUALIZACION_PERFIL_LF'),'')),
   md5(coalesce((SELECT string_agg((to_jsonb(x)-'updated_at')::text,'|' ORDER BY x.policy_version) FROM public.lf_policy_versions x WHERE policy_code='POL-PROFILE-UPDATE-PASS'),'')),
   md5(coalesce((SELECT string_agg(to_jsonb(x)::text,'|' ORDER BY x.step_id) FROM public.lf_operation_steps x WHERE operation_code='ACTUALIZACION_PERFIL_LF'),''))] INTO v_f2;
   SELECT string_agg(i::text,',') INTO v_dif FROM generate_subscripts(v_f0,1) i WHERE v_f0[i] IS DISTINCT FROM v_f2[i];
   RAISE EXCEPTION 'E2E_FORCED_ROLLBACK';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'E2E_FORCED_ROLLBACK' THEN RAISE; END IF; END;
 SELECT ARRAY[
   md5(coalesce((SELECT string_agg((to_jsonb(x)-'updated_at')::text,'|' ORDER BY x.step_id) FROM public.lf_operation_steps x WHERE operation_code='ACTUALIZACION_PERFIL_LF'),'')),
   md5(coalesce((SELECT string_agg((to_jsonb(x)-'updated_at')::text,'|' ORDER BY x.step_id) FROM public.lf_operation_step_judge_bindings x WHERE operation_code='ACTUALIZACION_PERFIL_LF'),'')),
   md5(coalesce((SELECT string_agg((to_jsonb(x)-'updated_at')::text,'|' ORDER BY x.step_id) FROM public.lf_operation_step_contracts x WHERE operation_code='ACTUALIZACION_PERFIL_LF'),'')),
   md5(coalesce((SELECT string_agg((to_jsonb(x)-'updated_at')::text,'|' ORDER BY x.judge_code) FROM public.lf_operation_judges x WHERE operation_code='ACTUALIZACION_PERFIL_LF'),'')),
   md5(coalesce((SELECT string_agg((to_jsonb(x)-'updated_at')::text,'|' ORDER BY x.policy_version) FROM public.lf_policy_versions x WHERE policy_code='POL-PROFILE-UPDATE-PASS'),'')),
   md5(coalesce((SELECT string_agg(to_jsonb(x)::text,'|' ORDER BY x.step_id) FROM public.lf_operation_steps x WHERE operation_code='ACTUALIZACION_PERFIL_LF'),''))] INTO v_f3;
 SELECT status INTO v_open_after FROM public.lf_operation_execution WHERE execution_id=c_open;
 RAISE EXCEPTION 'E2E_REHEARSAL %', jsonb_build_object('activar_err',v_act_err,'cambio_tras_activar',v_f0<>v_f1,'transicion_abierta_err',v_tr_err,
    'revertir_err',v_rev_err,'comp_distintos_tras_revertir_1pasos_2jueces_enl_3contratos_4jueces_5politicas_6pasos_con_updated_at',v_dif,'intacto_final',v_f0=v_f3,'abierta_antes_despues',v_open_before||'>'||v_open_after,'fechas',v_sup);
END
$mig$;
