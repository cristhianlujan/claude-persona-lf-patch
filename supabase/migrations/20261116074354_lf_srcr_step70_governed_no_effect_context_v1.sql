BEGIN;
DO $lf$
DECLARE d text; d0 text; anchor text:=$needle$ IF v40 IS NULL OR v50 IS NULL OR v60 IS NULL$needle$; addon text:=$addon$
 -- Scope-compatible, strictly no-effect repair report. A governed Step40
 -- is not a READ_ONLY_WITH_IG_FINDINGS run; refuse all write/effect claims.
 IF v40 IS NOT NULL AND v50 IS NOT NULL AND v60 IS NOT NULL
    AND v40->>'analysis_scope'='GOVERNED_REPAIR'
    AND v40->>'mutation_authorized'='true'
    AND v40->>'promotion_authorized'='false'
    AND v40#>>'{input_governance,analysis_scope}'='GOVERNED_REPAIR'
    AND jsonb_typeof(v40->'allowed_actions')='array'
    AND v40->'allowed_actions' <@ '["ANALYZE","PROPOSE","VALIDATE","REPORT"]'::jsonb
    AND e.manifest#>>'{repair_execution_authority,mode}'='GOVERNED_REPAIR_WRITE'
    AND e.manifest#>>'{repair_execution_authority,promotion_allowed}'='false'
    AND v60#>>'{deterministic_validation,status}'='PASS'
    AND v50->>'raw_output_sha256' ~ '^[0-9a-f]{64}$'
    AND v50->>'raw_output_sha256'=v60->>'raw_output_sha256'
    AND v50#>>'{profile_output,repair_execution,mode}'='AUTHORIZED_NOT_EXECUTED'
    AND v50#>'{profile_output,repair_execution,changes}'='[]'::jsonb
    AND v50#>>'{profile_output,repair_execution,promotion_performed}'='false'
 THEN RETURN true; END IF;
$addon$;
BEGIN
 d:=pg_get_functiondef('public.lf_profile_srcr_same_context_candidate_scope_v1(text)'::regprocedure); d0:=d;
 IF position(anchor IN d)=0 OR position('READ_ONLY_WITH_IG_FINDINGS' IN d)=0 THEN RAISE EXCEPTION 'LF_SRCR_STEP70_GOVERNED_SOURCE_DRIFT'; END IF;
 d:=replace(d,anchor,addon||anchor);
 IF d=d0 THEN RAISE EXCEPTION 'LF_SRCR_STEP70_GOVERNED_PATCH_NOT_APPLIED'; END IF;
 IF position('Scope-compatible, strictly no-effect repair report' IN d)=0 THEN RAISE EXCEPTION 'LF_SRCR_STEP70_GOVERNED_PATCH_NOT_APPLIED'; END IF;
 EXECUTE d;
END $lf$;
COMMIT;
