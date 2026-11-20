-- LF sandbox: resolve E12 governed repair / Step70 same-context incompatibility ONLY
-- for an explicitly NO-EFFECT, source-bound SRCR repair candidate.
-- Preserve existing independent reviewer path and legacy candidate artifact path.
-- No grants, promotion, production, existing execution rewrite, or data mutation.
BEGIN;
DO $patch$
DECLARE
 d text;
 d0 text;
BEGIN
 d:=pg_get_functiondef('public.lf_profile_srcr_same_context_candidate_scope_v1(text)'::regprocedure);
 d0:=d;
 d:=replace(d,
 $old$ IF v40 IS NULL OR v50 IS NULL OR v60 IS NULL$old$,
 $new$ -- E12: a governed SRCR may report an honest NON-EXECUTED repair specification.
 -- This branch cannot bless effects, promotions, or edits to the linked screen rules.
 IF v40 IS NOT NULL AND v50 IS NOT NULL AND v60 IS NOT NULL
    AND v40->>'analysis_scope'='GOVERNED_REPAIR'
    AND v40->>'mutation_authorized'='true'
    AND v40->>'promotion_authorized'='false'
    AND v40#>>'{input_governance,analysis_scope}'='GOVERNED_REPAIR'
    AND jsonb_typeof(v40->'allowed_actions')='array'
    AND v40->'allowed_actions' <@ '["ANALYZE","PROPOSE","VALIDATE","REPORT"]'::jsonb
    AND nullif(v40#>>'{resolved_scope,resolved_screen_code}','') IS NOT NULL
    AND e.manifest#>>'{router_profile_handoff,scope,target_type}'='PANTALLA'
    AND e.manifest#>>'{repair_execution_authority,mode}'='GOVERNED_REPAIR_WRITE'
    AND e.manifest#>>'{repair_execution_authority,promotion_allowed}'='false'
    AND e.manifest->>'no_promotion'='false'
    AND v50#>>'{profile_output,status}'='SYSTEMIC_REPAIR_SPEC'
    AND v50#>>'{profile_output,repair_execution,mode}'='AUTHORIZED_NOT_EXECUTED'
    AND v50#>>'{profile_output,repair_execution,promotion_performed}'='false'
    AND CASE WHEN jsonb_typeof(v50#>'{profile_output,repair_execution,changes}')='array'
        THEN jsonb_array_length(v50#>'{profile_output,repair_execution,changes}')=0
        ELSE false END
    AND v60#>>'{deterministic_validation,status}'='PASS'
    AND coalesce(v50->>'raw_output_sha256','') ~ '^[a-f0-9]{64}$'
    AND v60->>'raw_output_sha256'=v50->>'raw_output_sha256'
    AND NOT EXISTS (
      SELECT 1 FROM lf_ops.reglas r
      JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id
      JOIN lf_ops.pantallas p ON p.id=rp.pantalla_id
      WHERE p.codigo=v40#>>'{resolved_scope,resolved_screen_code}'
        AND r.updated_at >= e.created_at
    )
 THEN RETURN true; END IF;
 IF v40 IS NULL OR v50 IS NULL OR v60 IS NULL$new$);
 IF d=d0 OR position('E12: a governed SRCR may report' in d)=0
 THEN RAISE EXCEPTION 'LF_SRCR_E12_STEP70_NO_EFFECT_PATCH_NOT_APPLIED'; END IF;
 EXECUTE d;
END $patch$;
COMMIT;
