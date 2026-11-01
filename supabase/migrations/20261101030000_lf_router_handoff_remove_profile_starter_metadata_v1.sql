-- ACT-0001 is routing/selection/context-only. Remove old unapproved
-- Stage 06/07 direct/intermediate profile-launch instructions from live SQL.
-- The canonical EJECUCION_PERFIL_LF operation is NOT implemented or replaced
-- here; no execute privileges, writers or execution rows are changed.
BEGIN;
DO $cleanup$
DECLARE v_src text; v_prev text;
BEGIN
  SELECT pg_get_functiondef(
    'public.lf_router_pipeline_context_profile_semantic_submit_v2(text,text)'::regprocedure
  ) INTO v_src;
  IF v_src IS NULL
     OR position('DISPATCH_GOVERNED_PROFILE_RUNNER' in v_src)=0
     OR position('scripts/lf_profile_router_admit.py' in v_src)=0
     OR position('profile_execution_begin_from_router_context_v1' in v_src)=0
  THEN RAISE EXCEPTION 'BLOCK_ROUTER_SEMANTIC_HANDOFF_SOURCE_DRIFT'; END IF;
  v_prev:=v_src;
  v_src:=replace(v_src,
    $old$         'next_step','GOVERNED_PROFILE_EXECUTION_REQUIRED',
         'next_action','DISPATCH_GOVERNED_PROFILE_RUNNER',
         'terminal',false,
         'continuation_required',true,
         'stop_allowed',false,
         'continuation_runner','scripts/lf_profile_router_admit.py',
         'continuation_trigger','lf-profile-admit-governed',
         'continuation_stage06_action','router_profile_admit_context_v2',
         'continuation_stage07_action','profile_execution_begin_from_router_context_v1',$old$,
    $new$          'next_step','PROFILE_HANDOFF_REQUIRED',
          'next_action','HANDOFF_CONTEXT_TO_SELECTED_PROFILE',
          'terminal',false,
          'continuation_required',true,
          'stop_allowed',false,
          'execution_owner','EJECUCION_PERFIL_LF',
          'router_execution_authority',false,$new$
  );
  IF v_prev=v_src THEN RAISE EXCEPTION 'BLOCK_ROUTER_SEMANTIC_HANDOFF_PATCH_NOT_APPLIED'; END IF;
  EXECUTE v_src;

  SELECT pg_get_functiondef(
    'public.lf_router_pipeline_context_profile_admit_v2(jsonb,text)'::regprocedure
  ) INTO v_src;
  IF v_src IS NULL
     OR position('scripts/lf_profile_router_admit.py' in v_src)=0
     OR position('profile_execution_begin_from_router_context_v1' in v_src)=0
  THEN RAISE EXCEPTION 'BLOCK_ROUTER_ADMIT_HANDOFF_SOURCE_DRIFT'; END IF;
  v_prev:=v_src;
  v_src:=replace(v_src,
    $old$   'next_action','EJECUCION_PERFIL_LF_BEGIN_REQUIRED',
   'terminal',false,
   'continuation_required',true,
   'stop_allowed',false,
   'continuation_runner','scripts/lf_profile_router_admit.py',
   'continuation_stage07_action','profile_execution_begin_from_router_context_v1',$old$,
    $new$    'next_action','HANDOFF_CONTEXT_TO_SELECTED_PROFILE',
    'terminal',false,
    'continuation_required',true,
    'stop_allowed',false,
    'execution_owner','EJECUCION_PERFIL_LF',
    'router_execution_authority',false,$new$
  );
  IF v_prev=v_src THEN RAISE EXCEPTION 'BLOCK_ROUTER_ADMIT_HANDOFF_PATCH_NOT_APPLIED'; END IF;
  EXECUTE v_src;

  -- Remove explicit Edge starter metadata from Router's after-selection
  -- response. Return selected-profile ownership, never a launcher/fallback.
  SELECT pg_get_functiondef(
    'public.lf_router_profile_after_selection_v1(jsonb,jsonb)'::regprocedure
  ) INTO v_src;
  IF v_src IS NULL
     OR position('profile_execution_begin_from_router_context_v1' in v_src)=0
  THEN RAISE EXCEPTION 'BLOCK_ROUTER_AFTER_SELECTION_SOURCE_DRIFT'; END IF;
  v_prev:=v_src;
  v_src:=replace(v_src,$old$    'gate2_pass_entrypoint','public.lf_router_pipeline_context_profile_admit_v2',
    'siguiente_operacion',jsonb_build_object(
      'operation_code','EJECUCION_PERFIL_LF',
      'entrypoint','profile_execution_begin_from_router_context_v1',
      'materializer','public.lf_profile_execution_begin_from_handoff_v1',
      'context_hydrator','public.lf_profile_execution_channel_context_v1',
      'router_reentry_before_execution',false,
      'return_to_router_after_profile_result',true,
      'effect_authority',false
    ),$old$,$new$    'gate2_pass_entrypoint','public.lf_router_pipeline_context_profile_admit_v2',
    'siguiente_operacion',jsonb_build_object(
      'operation_code','EJECUCION_PERFIL_LF',
      'execution_owner','SELECTED_PROFILE',
      'context_hydrator','public.lf_profile_execution_channel_context_v1',
      'router_reentry_before_execution',false,
      'return_to_router_after_profile_result',true,
      'effect_authority',false
    ),$new$);
  IF v_prev=v_src THEN RAISE EXCEPTION 'BLOCK_ROUTER_AFTER_SELECTION_PATCH_NOT_APPLIED'; END IF;
  EXECUTE v_src;

  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname IN ('lf_router_pipeline_context_profile_semantic_submit_v2','lf_router_pipeline_context_profile_admit_v2','lf_router_profile_after_selection_v1')
      AND (
        position('scripts/lf_profile_router_admit.py' in pg_get_functiondef(p.oid))>0
        OR position('profile_execution_begin_from_router_context_v1' in pg_get_functiondef(p.oid))>0
        OR position('DISPATCH_GOVERNED_PROFILE_RUNNER' in pg_get_functiondef(p.oid))>0
      )
  ) THEN RAISE EXCEPTION 'BLOCK_ROUTER_PROFILE_LAUNCH_METADATA_NOT_REMOVED'; END IF;
END
$cleanup$;
COMMIT;
