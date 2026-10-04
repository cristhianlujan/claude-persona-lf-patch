-- Rollback-only executable proof for SC-M4.3D / SC-IMP-035.
-- Runs after the exact source migrations inside the enclosing transaction.
-- No state from this probe may survive the final ROLLBACK.

-- 1) Prove the subject extension intentionally invalidates the prior OPERATION qualification.
SELECT jsonb_build_object(
  'marker','SC_M43D_POST_SOURCE_DIAGNOSTIC',
  'revision_sha256',public.lf_operation_revision_sha256_v1('REVISION_INDEPENDIENTE_ESTRATEGIA_LF'),
  'qualification_current',public.lf_qualification_current_v1(
    'OPERATION',
    'REVISION_INDEPENDIENTE_ESTRATEGIA_LF',
    public.lf_operation_revision_sha256_v1('REVISION_INDEPENDIENTE_ESTRATEGIA_LF')
  ),
  'matching_receipts',coalesce((
    select jsonb_agg(jsonb_build_object(
      'qualification_id',qualification_id,
      'revision_sha256',revision_sha256,
      'lifecycle_state_code',lifecycle_state_code,
      'created_by_execution_id',created_by_execution_id,
      'qualified_at',qualified_at
    ) order by created_at desc)
    from public.lf_qualification_receipts
    where subject_type='OPERATION'
      and subject_code='REVISION_INDEPENDIENTE_ESTRATEGIA_LF'
      and revision_sha256=public.lf_operation_revision_sha256_v1('REVISION_INDEPENDIENTE_ESTRATEGIA_LF')
      and invalidated_at is null
  ),'[]'::jsonb)
) as sc_m43d_post_source_diagnostic;

-- 2) Execute the canonical exact-revision OPERATION requalification using the
--    repaired bootstrap. The enclosing runner will roll all of this back.
DO $sc_m43d_requal$
DECLARE
  r jsonb;
  v_revision text;
  v_route_count integer;
BEGIN
  r:=public.lf_operation_requalification_bootstrap_v1(
    'SC-M4.3D-REQUALIFICATION-PROBE-20261004',
    'REVISION_INDEPENDIENTE_ESTRATEGIA_LF',
    'STRATEGY_INDEPENDENT_REVIEW',
    'a35c9e9f1266cd2b97f6c0034d7cccb2d5b97a6c2f7a824e3a03d3d4c159776e',
    'sc:m43d:exact-operation-requalification:653383ac9eaa5595ef42d1e802a0c3421064ad04',
    'CHATGPT-T-INDEP-PAULO-035-20261002',
    '653383ac9eaa5595ef42d1e802a0c3421064ad04'
  );

  v_revision:=public.lf_operation_revision_sha256_v1('REVISION_INDEPENDIENTE_ESTRATEGIA_LF');

  IF coalesce((r->>'qualification_current')::boolean,false) IS NOT TRUE
     OR NOT public.lf_qualification_current_v1(
       'OPERATION','REVISION_INDEPENDIENTE_ESTRATEGIA_LF',v_revision
     ) THEN
    RAISE EXCEPTION 'BLOCK_SC_M43D_EXACT_OPERATION_REQUALIFICATION_NOT_CURRENT:%',r;
  END IF;

  IF r->>'revision_sha256' IS DISTINCT FROM v_revision
     OR r->>'bootstrap_execution_status' IS DISTINCT FROM 'COMPLETED'
     OR coalesce((r->>'runtime_activation')::boolean,true)
     OR coalesce((r->>'production_activation')::boolean,true)
     OR coalesce((r->>'promotion_authorized')::boolean,true)
     OR coalesce((r->>'router_activation_authorized')::boolean,true) THEN
    RAISE EXCEPTION 'BLOCK_SC_M43D_REQUALIFICATION_RECEIPT_INVALID:%',r;
  END IF;

  -- 3) Backward-compatible Strategy surface must remain singular and callable.
  SELECT count(*) INTO v_route_count
  FROM public.lf_router_action_registry
  WHERE asset_type='STRATEGY'
    AND action_code='STRATEGY_INDEPENDENT_REVIEW'
    AND operation_code='REVISION_INDEPENDIENTE_ESTRATEGIA_LF'
    AND status='ACTIVE';

  IF v_route_count<>1 THEN
    RAISE EXCEPTION 'BLOCK_SC_M43D_STRATEGY_ROUTE_REGRESSION:%',v_route_count;
  END IF;

  IF to_regprocedure('public.lf_independent_strategy_review_begin_v1(text,uuid,uuid,bigint,text,text,text,jsonb)') IS NULL
     OR to_regprocedure('public.lf_record_independent_strategy_review_step_v1(text,text,text,jsonb,text)') IS NULL
     OR to_regprocedure('public.lf_independent_strategy_review_record_judge_v1(text,text,jsonb,text,jsonb)') IS NULL
     OR to_regprocedure('public.lf_independent_strategy_review_finalize_v1(text)') IS NULL THEN
    RAISE EXCEPTION 'BLOCK_SC_M43D_STRATEGY_COMPATIBILITY_SURFACE_MISSING';
  END IF;

  RAISE NOTICE 'PASS_SC_M43D_EXACT_OPERATION_REQUALIFICATION revision=% execution=%',
    v_revision,r->>'execution_id';
  RAISE NOTICE 'PASS_SC_M43D_STRATEGY_COMPATIBILITY_SURFACE';
END
$sc_m43d_requal$;

SELECT jsonb_build_object(
  'marker','SC_M43D_POST_REQUALIFICATION_READBACK',
  'revision_sha256',public.lf_operation_revision_sha256_v1('REVISION_INDEPENDIENTE_ESTRATEGIA_LF'),
  'qualification_current',public.lf_qualification_current_v1(
    'OPERATION',
    'REVISION_INDEPENDIENTE_ESTRATEGIA_LF',
    public.lf_operation_revision_sha256_v1('REVISION_INDEPENDIENTE_ESTRATEGIA_LF')
  ),
  'requalification_execution_status',(
    select status from public.lf_operation_execution
    where execution_id='SC-M4.3D-REQUALIFICATION-PROBE-20261004'
  ),
  'strategy_route_count',(
    select count(*) from public.lf_router_action_registry
    where asset_type='STRATEGY'
      and action_code='STRATEGY_INDEPENDENT_REVIEW'
      and operation_code='REVISION_INDEPENDIENTE_ESTRATEGIA_LF'
      and status='ACTIVE'
  )
) as sc_m43d_post_requalification_readback;

SELECT 'PASS_SC_M43D_ROLLBACK_REQUALIFICATION_PROBE' AS probe_result;
