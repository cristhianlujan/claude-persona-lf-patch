-- Router hook for the governed profile updater.
-- The Router (ACT-0001) returns the first step of ACTUALIZACION_PERFIL_LF (init_execution) with its resolver_ref.
-- That ref said GPT_RUNTIME_WITH_SUPABASE_CONTEXT, so a native chat tried to call lf_profile_update_begin_v1 and stopped
-- on its read-only connection. The ref now names the governed dispatch route (issue + label / single-command runner).
-- Data only: one column of one row. No function, trigger, registry, execution or profile change.
-- Exact row + status + preimage guard; any drift aborts the whole migration.
BEGIN;
DO $lf_hook$
DECLARE
  v_op constant text := 'ACTUALIZACION_PERFIL_LF';
  v_step constant text := 'init_execution';
  v_old constant text := 'GPT_RUNTIME_WITH_SUPABASE_CONTEXT';
  v_new constant text := 'GOVERNED_PROFILE_UPDATE_DISPATCH_V1 (issue+label lf-profile-update-governed or scripts/lf_profile_update_run.py; see CLAUDE.md "Single-command update"; no direct DB begin)';
  v_total_before bigint;
  v_others_before bigint;
BEGIN
  SELECT COUNT(*) INTO v_total_before FROM public.lf_operation_step_contracts;
  SELECT COUNT(*) INTO v_others_before FROM public.lf_operation_step_contracts
    WHERE NOT (operation_code = v_op AND step_id = v_step) AND resolver_ref = v_new;
  IF v_others_before <> 0 THEN RAISE EXCEPTION 'ROUTER_HOOK_NEW_REF_ALREADY_PRESENT_ELSEWHERE'; END IF;

  IF (SELECT COUNT(*) FROM public.lf_operation_step_contracts
        WHERE operation_code = v_op AND step_id = v_step
          AND status = 'ACTIVE_ENFORCEMENT' AND resolver_ref = v_old) <> 1
  THEN RAISE EXCEPTION 'ROUTER_HOOK_PREIMAGE_DRIFT'; END IF;

  UPDATE public.lf_operation_step_contracts
     SET resolver_ref = v_new
   WHERE operation_code = v_op AND step_id = v_step
     AND status = 'ACTIVE_ENFORCEMENT' AND resolver_ref = v_old;
  IF NOT FOUND THEN RAISE EXCEPTION 'ROUTER_HOOK_UPDATE_REJECTED'; END IF;

  IF (SELECT COUNT(*) FROM public.lf_operation_step_contracts WHERE resolver_ref = v_new) <> 1
     OR (SELECT COUNT(*) FROM public.lf_operation_step_contracts
           WHERE operation_code = v_op AND step_id = v_step AND resolver_ref = v_new) <> 1
     OR (SELECT COUNT(*) FROM public.lf_operation_step_contracts) <> v_total_before
     OR (SELECT COUNT(*) FROM public.lf_operation_step_contracts
           WHERE operation_code = v_op AND resolver_ref = v_old) <> 13
  THEN RAISE EXCEPTION 'ROUTER_HOOK_READBACK_FAILED'; END IF;
END
$lf_hook$;
COMMIT;
