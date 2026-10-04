-- M7.8 exact rollback for source-stale cached-v2 cutover.
-- Restores only the single caller token cached_v2 -> cached_v1.

DO $rollback$
DECLARE
  v_sig constant regprocedure := 'programacion.fn_input_governance_recurate_source_stale_v1(integer,text,text,bigint)'::regprocedure;
  v_candidate_md5 constant text := '996a6b3c0fc095ec714a70251adc14ef';
  v_baseline_md5 constant text := '6066729809da6cc8ed05a89e5b4da222';
  v_def text;
  v_old text;
BEGIN
  v_def:=pg_get_functiondef(v_sig);
  IF md5(v_def)<>v_candidate_md5 THEN
    RAISE EXCEPTION 'BLOCK_M78_ROLLBACK_CANDIDATE_DRIFT expected=% got=%',v_candidate_md5,md5(v_def);
  END IF;
  v_old:=replace(
    v_def,
    'fn_input_governance_bootstrap_classify_v2_cached_v2',
    'fn_input_governance_bootstrap_classify_v2_cached_v1'
  );
  IF v_old=v_def OR md5(v_old)<>v_baseline_md5 THEN
    RAISE EXCEPTION 'BLOCK_M78_ROLLBACK_RECONSTRUCTION expected=% got=%',v_baseline_md5,md5(v_old);
  END IF;
  EXECUTE v_old;
  IF md5(pg_get_functiondef(v_sig))<>v_baseline_md5 THEN
    RAISE EXCEPTION 'BLOCK_M78_ROLLBACK_READBACK';
  END IF;
END
$rollback$;
