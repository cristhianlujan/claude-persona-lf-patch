-- Retire S36_ASSURANCE as a writable judge type.
-- Historical lf_test_judge_results rows remain immutable/readable.
-- Dependencies: after #1117 INDEPENDENT_REVIEW type canonicalization and
-- #1119 CARD_OPERATIONS controlled-assurance canonicalization.
-- EKB: S36-ASSURANCE-BOUNDARY-CONTAMINATION-001

DO $cutover$
DECLARE
  v_oid oid;
  v_def text;
  v_old text;
  v_new text;
  v_count integer;
BEGIN
  v_oid := to_regprocedure('public.lf_record_test_judge_result_v1(uuid,text,text,text,text,jsonb,text,jsonb)');
  IF v_oid IS NULL THEN
    RAISE EXCEPTION 'LF_TEST_JUDGE_RECORDER_MISSING';
  END IF;

  SELECT pg_get_functiondef(v_oid) INTO v_def;
  v_old := $$if v_judge_type not in ('QUALITY_PACK','INDEPENDENT_HOLDOUT','S36_ASSURANCE') then$$;
  v_count := (length(v_def)-length(replace(v_def,v_old,'')))/length(v_old);
  IF v_count<>1 THEN
    RAISE EXCEPTION 'LF_TEST_JUDGE_RECORDER_S36_PRESTATE:%',v_count;
  END IF;

  v_new := replace(
    v_def,
    v_old,
    $$if v_judge_type not in ('QUALITY_PACK','INDEPENDENT_HOLDOUT','INDEPENDENT_REVIEW') then$$
  );
  EXECUTE v_new;

  SELECT pg_get_functiondef(v_oid) INTO v_def;
  IF v_def ILIKE '%S36_ASSURANCE%' THEN
    RAISE EXCEPTION 'LF_TEST_JUDGE_RECORDER_S36_STILL_WRITABLE';
  END IF;
  IF v_def NOT ILIKE '%INDEPENDENT_REVIEW%' THEN
    RAISE EXCEPTION 'LF_TEST_JUDGE_RECORDER_INDEPENDENT_REVIEW_MISSING';
  END IF;
END
$cutover$;

-- Deliberately no UPDATE/DELETE of public.lf_test_judge_results.
-- The 9 observed historical S36_ASSURANCE rows are lineage/readback evidence only.
