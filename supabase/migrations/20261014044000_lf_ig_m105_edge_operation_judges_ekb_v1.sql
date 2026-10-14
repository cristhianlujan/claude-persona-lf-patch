-- M10.5 CP2 — EKB lesson: Operation registry must materialize step judges
-- via its own governed Train migration; source CI is not runtime qualification.
-- EKB only. No Router activation, no deployment, no CP2 screen execution.
DO $m105_edge_ekb$
DECLARE
  v_code constant text := 'IG-M105-EDGE-OPERATION-STEPS-OMITTED-013';
  v_op constant text := 'DEPLOY_SUPABASE_EDGE_FUNCTION_LF';
BEGIN
  IF EXISTS (SELECT 1 FROM public.lf_error_knowledge WHERE codigo=v_code) THEN
    RAISE EXCEPTION 'M105_EDGE_EKB_ALREADY_REGISTERED';
  END IF;
  IF (SELECT count(*) FROM public.lf_operation_steps WHERE operation_code=v_op AND required=true)=8
    AND (SELECT count(*) FROM public.lf_operation_step_contracts WHERE operation_code=v_op AND status='ACTIVE_ENFORCEMENT')=8
    AND (SELECT count(*) FROM public.lf_operation_judges WHERE operation_code=v_op AND status='ACTIVE_ENFORCEMENT')=8
    AND (SELECT count(*) FROM public.lf_operation_step_judge_bindings WHERE operation_code=v_op AND status='ACTIVE_ENFORCEMENT')=8
    AND EXISTS (
      SELECT 1 FROM public.lf_router_action_registry
      WHERE operation_code=v_op AND status='CANDIDATO_READ_ONLY' AND write_allowed=false
    )
    AND EXISTS (
      SELECT 1 FROM supabase_migrations.schema_migrations
      WHERE version='20261014043340' AND name='lf_edge_deploy_step_judges_candidate_v1'
        AND idempotency_key='gitblob:0a23748f3c22fb5561d5f77b2d3ec52d54160854'
    )
  THEN
    NULL;
  ELSE
    RAISE EXCEPTION 'M105_EDGE_EKB_STEP_JUDGES_NOT_READBACK_VERIFIED';
  END IF;

  INSERT INTO public.lf_error_knowledge (
    codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
    severidad,frecuencia,primera_vez,ultima_vez,lote_origen,pr,estado,evidencia,
    created_at,updated_at,lifecycle_phase,consumer_role,root_cause_family,
    detectability,source_context,source_ref
  ) VALUES (
    v_code,'INPUT_GOVERNANCE',
    'Edge deployment Operation was registered without required step contracts and mini-judges',
    'For M10.5 CP2, PR #2568 created DEPLOY_SUPABASE_EDGE_FUNCTION_LF, its Router and eight required steps as CANDIDATO_READ_ONLY. A live readback then showed 0/8 step contracts and 0/8 judge bindings, so operation qualification could not be claimed. PR #2576 added scoped deterministic judges for all eight, test corrections and Train-governed bindings. The Operation remains non-executable.',
    'The initial Operation bootstrap registered step definitions but deferred their nature-specific validation/binding, while a source-only CI PASS could be mistaken for materialized qualification.',
    'Registered operation steps without one concrete bound validator per required step; false progress possible when source merge is conflated with operational route readiness.',
    'Before requesting runtime authorization, enforce per-operation readback: required steps = active step contracts = active judge definitions = active judge bindings; require distinct step evidence and positive/negative tests. Reuse the existing LF Operation and effect-guard tables, never create parallel judge engines. Keep Router write_allowed=false until a trusted executor, canonical R17, scoped credentials and runtime authorization are independently verified.',
    'PR #2576 source-only initial CI test FAILED because the close fixture used effect_state=RESERVED; corrected fixture tests close with SUCCEEDED and checks each negative explicitly; final tests PASS. Train run #38511945025 SUCCESS. Git main merge 86502aeefa27b6950e260761308fdcfdd20b2669; ledger exact version 20261014043340 Git blob 0a23748f3c22fb5561d5f77b2d3ec52d54160854; live Supabase 8 contracts, 8 judges, 8 bindings, Router write_allowed=false. No Edge deployment or CP2 real jobs credited.',
    'ALTA',1,clock_timestamp(),clock_timestamp(),'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.5/CP2',
    'PR #2568; PR #2576','resuelto',
    'GitHub #2568/#2576, workflow run 38511945025, supabase_migrations.schema_migrations:20261014043340, public.lf_operation_step_contracts/public.lf_operation_judges/public.lf_operation_step_judge_bindings',
    clock_timestamp(),clock_timestamp(),
    'OPERATION_QUALIFICATION',ARRAY['OPERATION_EXECUTOR','ENGINEERING_VALIDATOR']::text[],
    'MISSING_STEP_VALIDATOR_BINDINGS','LIVE_REGISTRY_AND_LEDGER_READBACK',
    'M10.5/CP2; DEPLOY_SUPABASE_EDGE_FUNCTION_LF; operation candidate only',
    'https://github.com/cristhianlujan/claude-persona-lf-patch/pull/2576'
  );

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_error_knowledge
    WHERE codigo=v_code AND estado='resuelto'
      AND source_ref='https://github.com/cristhianlujan/claude-persona-lf-patch/pull/2576'
  ) THEN
    RAISE EXCEPTION 'M105_EDGE_EKB_READBACK_FAILED';
  END IF;
END $m105_edge_ekb$;
