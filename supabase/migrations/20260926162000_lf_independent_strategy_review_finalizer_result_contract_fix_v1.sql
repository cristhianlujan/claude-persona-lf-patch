-- Repair only the independent-review wrapper success/currentness contract.
-- EKB: INDEPENDENT-REVIEW-FINALIZER-RESULT-CONTRACT-MISMATCH-001
-- No schema/table/route/runtime/production activation.

DO $pre$
DECLARE
  wrapper_def text;
  finalizer_def text;
BEGIN
  SELECT pg_get_functiondef('public.lf_independent_strategy_review_finalize_v1(text)'::regprocedure)
    INTO wrapper_def;
  SELECT pg_get_functiondef('public.lf_finalize_qualification_independent_review_v1(uuid,text,jsonb)'::regprocedure)
    INTO finalizer_def;

  IF position($x$r->>'result'='QUALIFIED'$x$ in wrapper_def)=0 THEN
    RAISE EXCEPTION 'LF_INDEPENDENT_REVIEW_RESULT_FIX_EXPECTED_OLD_WRAPPER_CONTRACT_MISSING';
  END IF;
  IF position($x$'QUALIFIED_WITH_INDEPENDENT_REVIEW'$x$ in finalizer_def)=0 THEN
    RAISE EXCEPTION 'LF_INDEPENDENT_REVIEW_RESULT_FIX_FINALIZER_SUCCESS_CONTRACT_MISSING';
  END IF;
END
$pre$;

CREATE OR REPLACE FUNCTION public.lf_independent_strategy_review_finalize_v1(p_execution_id text)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  x public.lf_operation_execution%rowtype;
  qid uuid;
  test_id uuid;
  jrid uuid;
  jr public.lf_test_judge_results%rowtype;
  review_ref jsonb;
  r jsonb;
  rev text;
  current_ok boolean;
BEGIN
  SELECT * INTO x FROM public.lf_operation_execution WHERE execution_id=p_execution_id FOR UPDATE;
  IF NOT FOUND OR x.operation_code<>'REVISION_INDEPENDIENTE_ESTRATEGIA_LF' OR x.status<>'COMPLETED' OR x.completed_at IS NULL THEN
    RETURN jsonb_build_object('result','BLOCKED','code','REVIEWER_EXECUTION_NOT_COMPLETED');
  END IF;
  qid:=(x.manifest->>'qualification_id')::uuid;
  test_id:=(x.manifest->>'test_run_id')::uuid;
  jrid:=(x.checkpoint_payload->>'judge_result_id')::uuid;
  SELECT * INTO jr FROM public.lf_test_judge_results WHERE judge_result_id=jrid;
  IF NOT FOUND OR jr.test_run_id<>test_id OR jr.created_by_execution_id<>p_execution_id THEN
    RETURN jsonb_build_object('result','BLOCKED','code','FINALIZER_JUDGE_BINDING_INVALID');
  END IF;
  review_ref:=jsonb_build_object(
    'review_type','S36_ASSURANCE',
    'review_context','INDEPENDENT_OPERATION_CONTEXT',
    'assessor_execution_id',p_execution_id,
    'reviewer_operation_code','REVISION_INDEPENDIENTE_ESTRATEGIA_LF',
    'judge_result_id',jrid::text,
    'verdict',jr.verdict,
    'evidence_refs',coalesce(x.checkpoint_payload->'evidence_refs','[]'::jsonb),
    'qualification_id',qid::text,
    'test_run_id',test_id::text,
    'snapshot_id',x.manifest->>'snapshot_id',
    'revision_sha256',x.manifest->>'revision_sha256',
    'suite_set_fingerprint',x.manifest->>'suite_set_fingerprint'
  );
  r:=public.lf_finalize_qualification_independent_review_v1(qid,p_execution_id,review_ref);
  rev:=x.manifest->>'revision_sha256';
  current_ok:=public.lf_qualification_current_v1('STRATEGY',x.target_code,rev);
  UPDATE public.lf_operation_execution
     SET checkpoint_payload=coalesce(checkpoint_payload,'{}'::jsonb)||jsonb_build_object(
       'finalizer_receipt',r,'qualification_current_after',current_ok,'finalized_at',clock_timestamp()
     ),updated_at=clock_timestamp(),updated_by_execution_id=p_execution_id
   WHERE execution_id=p_execution_id;

  -- Both values are retained as success aliases for compatibility, but the
  -- currently deployed canonical finalizer returns QUALIFIED_WITH_INDEPENDENT_REVIEW.
  -- Any successful qualification must read back as current or the transaction fails closed.
  IF r->>'result' IN ('QUALIFIED','QUALIFIED_WITH_INDEPENDENT_REVIEW') AND NOT current_ok THEN
    RAISE EXCEPTION 'LF_INDEPENDENT_STRATEGY_REVIEW_FINALIZER_CURRENTNESS_FAILED:%',r;
  END IF;
  RETURN r||jsonb_build_object('qualification_current',current_ok,'reviewer_execution_id',p_execution_id);
END
$function$;

COMMENT ON FUNCTION public.lf_independent_strategy_review_finalize_v1(text) IS
'Finalizes the independent Strategy reviewer operation and delegates qualification materialization to the canonical qualification finalizer. Successful qualification aliases require qualification_current readback=true; otherwise the transaction fails closed.';
