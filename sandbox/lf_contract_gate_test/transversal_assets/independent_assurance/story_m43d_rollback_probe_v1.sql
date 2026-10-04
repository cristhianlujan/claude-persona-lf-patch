-- SC-M4.3D rollback-only probe. Executed only inside the canonical rollback harness.
-- No persistent effect is authorized by this probe.
DO $probe$
DECLARE
  r jsonb;
  v_rev text;
  v_route jsonb;
BEGIN
  r := public.lf_operation_requalification_bootstrap_v1(
    'SC-M4.3D-ROLLBACK-PROBE-20261003',
    'REVISION_INDEPENDIENTE_ESTRATEGIA_LF',
    'STRATEGY_INDEPENDENT_REVIEW',
    'ec4b0a7c9b1b274252e75fc8a5967bc268c685ab75f725a34455efeafb957651',
    'SC-M4.3D-ROLLBACK-PROBE-20261003',
    'SC-M4.3D-ROLLBACK-PROBE-20261003',
    '5cb641d8a187d3926698a750823ad13074694fad'
  );

  IF coalesce((r->>'qualification_current')::boolean,false) IS NOT TRUE
     OR r->>'bootstrap_execution_status' <> 'COMPLETED' THEN
    RAISE EXCEPTION 'SC_M43D_REQUALIFICATION_FAILED:%', r;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_capability_current
    WHERE capability_code='INDEPENDENT_ASSURANCE'
      AND version='1.0.0'
      AND manifest_sha256='a6f5e2fe21ed305b6d47e8722035685b243cfc4e697ff397d1724e5d34f6c6e8'
  ) THEN
    RAISE EXCEPTION 'SC_M43D_CURRENT_V1_CHANGED_BEFORE_PROMOTION';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_capability_version_registry
    WHERE capability_code='INDEPENDENT_ASSURANCE'
      AND version='2.0.0'
      AND release_state='RELEASED'
      AND manifest#>>'{contract,supported_subjects,STORY_IMPLEMENTATION_PACKAGE,path}'='GENERIC_SUBJECT_EXTENSION'
  ) THEN
    RAISE EXCEPTION 'SC_M43D_STORY_SPECIALIZATION_MISSING';
  END IF;

  IF (SELECT applies_to_asset_type FROM public.lf_operation_registry
      WHERE operation_code='REVISION_INDEPENDIENTE_ESTRATEGIA_LF') IS NOT NULL THEN
    RAISE EXCEPTION 'SC_M43D_OPERATION_NOT_MULTISUBJECT';
  END IF;

  IF (SELECT count(*) FROM public.lf_operation_judges
      WHERE operation_code='REVISION_INDEPENDIENTE_ESTRATEGIA_LF'
        AND status='ACTIVE_ENFORCEMENT') <> 6 THEN
    RAISE EXCEPTION 'SC_M43D_JUDGE_COUNT_DRIFT';
  END IF;

  IF to_regprocedure('public.lf_independent_review_begin_v2(text,text,text,text,text,uuid,text,text,text,uuid,text,text,text,jsonb)') IS NULL
     OR to_regprocedure('public.lf_record_independent_review_step_v2(text,text,text,jsonb,text,text)') IS NULL
     OR to_regprocedure('public.lf_independent_strategy_review_begin_v1(text,text,bigint,text,text,text,text,text)') IS NULL
     OR to_regprocedure('public.lf_record_independent_strategy_review_step_v1(text,text,text,jsonb,text)') IS NULL THEN
    RAISE EXCEPTION 'SC_M43D_REQUIRED_ENTRYPOINT_MISSING';
  END IF;

  v_rev := public.lf_operation_revision_sha256_v1('REVISION_INDEPENDIENTE_ESTRATEGIA_LF');
  IF NOT public.lf_qualification_current_v1('OPERATION','REVISION_INDEPENDIENTE_ESTRATEGIA_LF',v_rev) THEN
    RAISE EXCEPTION 'SC_M43D_POST_REQUALIFICATION_NOT_CURRENT:%', v_rev;
  END IF;

  v_route := public.lf_router_resolve_v1(
    'revision independiente de qualification de estrategia',
    NULL,
    'STRATEGY_INDEPENDENT_REVIEW',
    'STRATEGY',
    'ROUTER'
  );
  IF v_route->>'status' <> 'READY_TO_EXECUTE'
     OR v_route->>'operation_code' <> 'REVISION_INDEPENDIENTE_ESTRATEGIA_LF' THEN
    RAISE EXCEPTION 'SC_M43D_STRATEGY_ROUTE_REGRESSION:%', v_route;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_execution
    WHERE execution_id='SC-M4.3D-ROLLBACK-PROBE-20261003'
      AND status='COMPLETED'
      AND lease_owner IS NULL
      AND lease_expires_at IS NULL
  ) THEN
    RAISE EXCEPTION 'SC_M43D_EXECUTION_OR_LEASE_INVALID';
  END IF;
END
$probe$;

SELECT 'PASS_SC_M43D_ROLLBACK_REQUALIFICATION_PROBE' AS probe_result;
