-- Prueba E2E de Profile Updater (paso init): ejecuta lf_profile_update_begin_v1 de verdad contra el perfil real
-- PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF dentro de un subbloque que SIEMPRE se revierte. No deja ningun efecto persistente.
-- Resultado: la migracion termina SIEMPRE con una excepcion que lleva el resultado (el Train la registra en la ejecucion BLOQUEADA).
-- Pruebas: (1) begin crea ejecucion + paso init; (2) repetir con la misma clave es idempotente; (3) tras el rollback no queda nada.
DO $mig$
DECLARE
 c_op constant text := 'ACTUALIZACION_PERFIL_LF';
 c_exec constant text := 'EXEC-E2E-BEGIN-DRYRUN-20261028-V1';
 c_sha constant text := repeat('a',64);
 v_train text; v_n_before int; v_n_after int; v_steps_after int;
 v_r1 jsonb; v_e1 text; v_r2 jsonb; v_e2 text; v_row jsonb; v_step jsonb;
BEGIN
 SELECT execution_id INTO v_train FROM public.lf_operation_execution
 WHERE operation_code='ACTUALIZACION_DB_LF' AND target_type='MIGRATION'
  AND target_code LIKE '%lf_e2e_begin_dry_run_v1' AND status='IN_PROGRESS' ORDER BY created_at DESC LIMIT 1;
 IF v_train IS NULL THEN RAISE EXCEPTION 'E2E_BEGIN_TRAIN_TRANSPORT_REQUIRED'; END IF;

 SELECT count(*) INTO v_n_before FROM public.lf_operation_execution WHERE execution_id=c_exec;
 IF v_n_before<>0 THEN RAISE EXCEPTION 'E2E_BEGIN_PRESTATE_INVALID'; END IF;

 BEGIN
   BEGIN
     v_r1 := public.lf_profile_update_begin_v1(c_exec,'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF','cristhianlujan/claude-persona-lf-patch',
        'profiles/systemic_root_cause_repair_lf/SKILL.md',c_sha,'idem-e2e-begin-20261028',v_train,'{}'::jsonb);
   EXCEPTION WHEN OTHERS THEN v_e1 := SQLERRM; END;
   SELECT to_jsonb(x)-'manifest'-'checkpoint_payload' INTO v_row FROM public.lf_operation_execution x WHERE execution_id=c_exec;
   SELECT to_jsonb(s) INTO v_step FROM public.lf_operation_execution_steps s WHERE execution_id=c_exec AND step_id='init_execution';
   BEGIN
     v_r2 := public.lf_profile_update_begin_v1(c_exec,'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF','cristhianlujan/claude-persona-lf-patch',
        'profiles/systemic_root_cause_repair_lf/SKILL.md',c_sha,'idem-e2e-begin-20261028',v_train,'{}'::jsonb);
   EXCEPTION WHEN OTHERS THEN v_e2 := SQLERRM; END;
   RAISE EXCEPTION 'E2E_FORCED_ROLLBACK';
 EXCEPTION WHEN OTHERS THEN
   IF SQLERRM <> 'E2E_FORCED_ROLLBACK' THEN RAISE; END IF;
 END;

 SELECT count(*) INTO v_n_after FROM public.lf_operation_execution WHERE execution_id=c_exec;
 SELECT count(*) INTO v_steps_after FROM public.lf_operation_execution_steps WHERE execution_id=c_exec;

 RAISE EXCEPTION 'E2E_BEGIN_RESULT %', jsonb_build_object(
   'llamada_1_resultado',v_r1,'llamada_1_error',v_e1,
   'ejecucion_creada',v_row,'paso_init',v_step,
   'llamada_2_resultado',v_r2,'llamada_2_error',v_e2,
   'filas_ejecucion_tras_rollback',v_n_after,'filas_pasos_tras_rollback',v_steps_after);
END
$mig$;
