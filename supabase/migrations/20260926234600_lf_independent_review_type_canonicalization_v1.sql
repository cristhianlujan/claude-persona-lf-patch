-- Canonicalize new Independent Review evidence to INDEPENDENT_REVIEW.
-- EKB: S36-ASSURANCE-BOUNDARY-CONTAMINATION-001
-- Source-first candidate only. Historical S36_ASSURANCE judge rows remain readable.
-- Apply ordering: after INDEPENDENT_REVIEW_FINALIZER_RESULT_CONTRACT_FIX (#1094).
-- No runtime/production activation and no historical evidence rewrite.

DO $cutover$
DECLARE
  v_oid oid;
  v_def text;
  v_new text;
  v_old text;
  v_count integer;
BEGIN
  -- 1) New semantic-review steps must no longer accept S36_ASSURANCE.
  v_oid := to_regprocedure('public.lf_record_independent_strategy_review_step_v1(text,text,text,jsonb,text)');
  IF v_oid IS NULL THEN
    RAISE EXCEPTION 'LF_INDEPENDENT_REVIEW_TYPE_STEP_RECORDER_MISSING';
  END IF;
  SELECT pg_get_functiondef(v_oid) INTO v_def;
  v_old := $$p_evidence_payload->>'review_type' IN ('S36_ASSURANCE','INDEPENDENT_HOLDOUT')$$;
  v_count := (length(v_def)-length(replace(v_def,v_old,'')))/length(v_old);
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'LF_INDEPENDENT_REVIEW_TYPE_STEP_RECORDER_PRESTATE:%',v_count;
  END IF;
  v_new := replace(
    v_def,
    v_old,
    $$p_evidence_payload->>'review_type' IN ('INDEPENDENT_REVIEW','INDEPENDENT_HOLDOUT')$$
  );
  EXECUTE v_new;

  -- 2) Canonical reviewer judge rows are emitted as INDEPENDENT_REVIEW.
  v_oid := to_regprocedure('public.lf_independent_strategy_review_record_judge_v1(text,text,jsonb,text,jsonb)');
  IF v_oid IS NULL THEN
    RAISE EXCEPTION 'LF_INDEPENDENT_REVIEW_TYPE_JUDGE_RECORDER_MISSING';
  END IF;
  SELECT pg_get_functiondef(v_oid) INTO v_def;
  v_old := $$'STRATEGY-QUAL-A03-INDEPENDENT-REVIEW-V1','S36_ASSURANCE',upper(p_verdict)$$;
  v_count := (length(v_def)-length(replace(v_def,v_old,'')))/length(v_old);
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'LF_INDEPENDENT_REVIEW_TYPE_JUDGE_RECORDER_PRESTATE:%',v_count;
  END IF;
  v_new := replace(
    v_def,
    v_old,
    $$'STRATEGY-QUAL-A03-INDEPENDENT-REVIEW-V1','INDEPENDENT_REVIEW',upper(p_verdict)$$
  );
  EXECUTE v_new;

  -- 3) Reviewer output carries the canonical review_type downstream.
  v_oid := to_regprocedure('public.lf_independent_strategy_review_finalize_v1(text)');
  IF v_oid IS NULL THEN
    RAISE EXCEPTION 'LF_INDEPENDENT_REVIEW_TYPE_WRAPPER_FINALIZER_MISSING';
  END IF;
  SELECT pg_get_functiondef(v_oid) INTO v_def;
  v_old := $$'review_type','S36_ASSURANCE'$$;
  v_count := (length(v_def)-length(replace(v_def,v_old,'')))/length(v_old);
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'LF_INDEPENDENT_REVIEW_TYPE_WRAPPER_FINALIZER_PRESTATE:%',v_count;
  END IF;
  v_new := replace(v_def,v_old,$$'review_type','INDEPENDENT_REVIEW'$$);
  EXECUTE v_new;

  -- 4) Qualification accepts the new canonical type while keeping legacy rows readable.
  -- S36_ASSURANCE compatibility is readback-only: it requires an already-persisted
  -- historical S36 judge row bound to the exact reviewer execution.
  v_oid := to_regprocedure('public.lf_finalize_qualification_independent_review_v1(uuid,text,jsonb)');
  IF v_oid IS NULL THEN
    RAISE EXCEPTION 'LF_INDEPENDENT_REVIEW_TYPE_QUALIFICATION_FINALIZER_MISSING';
  END IF;
  SELECT pg_get_functiondef(v_oid) INTO v_def;

  v_old := $$if v_review_type not in ('INDEPENDENT_HOLDOUT','S36_ASSURANCE') then$$;
  v_count := (length(v_def)-length(replace(v_def,v_old,'')))/length(v_old);
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'LF_INDEPENDENT_REVIEW_TYPE_QUAL_REVIEW_TYPE_PRESTATE:%',v_count;
  END IF;
  v_new := replace(
    v_def,
    v_old,
    $$if v_review_type not in ('INDEPENDENT_HOLDOUT','INDEPENDENT_REVIEW','S36_ASSURANCE') then$$
  );

  v_old := $$  if (p_review_ref->>'assessor_execution_id') is distinct from p_reviewer_execution_id then$$;
  v_count := (length(v_new)-length(replace(v_new,v_old,'')))/length(v_old);
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'LF_INDEPENDENT_REVIEW_TYPE_QUAL_ASSESSOR_PRESTATE:%',v_count;
  END IF;
  v_new := replace(
    v_new,
    v_old,
    $$  if v_review_type='S36_ASSURANCE' and not exists (
    select 1
    from public.lf_test_judge_results legacy_jr
    where legacy_jr.created_by_execution_id=p_reviewer_execution_id
      and legacy_jr.judge_type='S36_ASSURANCE'
  ) then
    return jsonb_build_object('result','BLOCKED','code','QUAL_REVIEW_LEGACY_S36_NOT_PERSISTED');
  end if;

  if (p_review_ref->>'assessor_execution_id') is distinct from p_reviewer_execution_id then$$
  );

  -- Live source has four equivalent judge filters: PASS path, FAIL path and two
  -- materialization/readback branches. All four must consume the canonical type.
  v_old := $$jr.judge_type in ('QUALITY_PACK','INDEPENDENT_HOLDOUT','S36_ASSURANCE')$$;
  v_count := (length(v_new)-length(replace(v_new,v_old,'')))/length(v_old);
  IF v_count <> 4 THEN
    RAISE EXCEPTION 'LF_INDEPENDENT_REVIEW_TYPE_QUAL_JUDGE_FILTER_PRESTATE:%',v_count;
  END IF;
  v_new := replace(
    v_new,
    v_old,
    $$jr.judge_type in ('QUALITY_PACK','INDEPENDENT_HOLDOUT','INDEPENDENT_REVIEW','S36_ASSURANCE')$$
  );
  EXECUTE v_new;
END
$cutover$;

-- This lot deliberately does not alter public.lf_record_test_judge_result_v1 yet.
-- CARD expertise still has a separate S36_ASSURANCE consumer and must be canonicalized
-- in its own owner PR before the generic judge recorder retires that legacy input value.
