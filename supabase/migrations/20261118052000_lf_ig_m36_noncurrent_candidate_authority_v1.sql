-- IG 23:55 owner-delegated: field catalog noncurrent is CANDIDATE_AUTHORITY.
-- Scope: exact M3.6 typed blocker mapping only; preserve original blocker,
-- evidence, applicability, fail-closed, earlier-stage policy, and all 7 #4064 sources.
-- DO-only migration for governed Train; BEGIN/ROLLBACK harness calls this same DO.
DO $m36$
DECLARE
  sig regprocedure:='programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(integer,text,bigint,jsonb)'::regprocedure;
  d text;
  needle text:=$old$        when upper(coalesce(b.value->>'code','')) ~ '(CANDIDATE|NOT_IMPLEMENTATION_READY)'
          then 'CANDIDATE_AUTHORITY'$old$;
  insertion text:=$new$        when upper(coalesce(b.value->>'code',''))='EXPLICIT_FIELD_REFERENCE_NONCURRENT'
          then 'CANDIDATE_AUTHORITY'
        when upper(coalesce(b.value->>'code','')) ~ '(CANDIDATE|NOT_IMPLEMENTATION_READY)'
          then 'CANDIDATE_AUTHORITY'$new$;
BEGIN
  d:=pg_get_functiondef(sig);
  IF md5(d) <> '61d47a6400cf910ace71936413863e16'
    THEN RAISE EXCEPTION 'IG_M36_PREIMAGE_SOURCE_DRIFT expected=61d47a6400cf910ace71936413863e16 got=%',md5(d); END IF;
  IF (length(d)-length(replace(d,needle,'')))/length(needle) <> 1
    THEN RAISE EXCEPTION 'IG_M36_NONCURRENT_MAPPING_ANCHOR_NOT_UNIQUE'; END IF;
  d:=replace(d,needle,insertion);
  EXECUTE d;
  IF md5(pg_get_functiondef(sig))='61d47a6400cf910ace71936413863e16'
    OR position($marker$when upper(coalesce(b.value->>'code',''))='EXPLICIT_FIELD_REFERENCE_NONCURRENT'
          then 'CANDIDATE_AUTHORITY'$marker$ in pg_get_functiondef(sig))=0
    THEN RAISE EXCEPTION 'IG_M36_NONCURRENT_CANDIDATE_SOURCE_READBACK_FAIL'; END IF;
  RAISE NOTICE 'IG_M36_NONCURRENT_SOURCE_PATCH_PASS original_md5=61d47a6400cf910ace71936413863e16 candidate_md5=%',md5(pg_get_functiondef(sig));
END;
$m36$;
