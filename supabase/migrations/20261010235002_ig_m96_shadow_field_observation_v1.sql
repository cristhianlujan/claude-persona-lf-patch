BEGIN;
-- M9.6: nondecisional field-difference projection from the canonical shadow.
CREATE OR REPLACE FUNCTION programacion.fn_ig_m96_shadow_field_probe_v1(p_screen_id integer,p_version_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path TO 'pg_catalog'
AS $probe$
DECLARE j jsonb; f jsonb; a jsonb:='[]'::jsonb; n int:=0; oc int:=0; nd int:=0;
 cur text; alt text; fam text; ref text; diff jsonb;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM lf_ops.pantallas WHERE id=p_screen_id AND activa AND module_id IS NOT NULL)
 THEN RETURN jsonb_build_object('status','BLOCKED','reason','SCREEN_NOT_ACTIVE_OR_JOINABLE'); END IF;
 j:=programacion.fn_input_governance_shadow_evaluate_v2(p_screen_id,p_version_id);
 IF j->>'shadow_contract' IS DISTINCT FROM 'INPUT_GOVERNANCE_SHADOW_EVALUATOR_V2'
 OR jsonb_typeof(j->'families') IS DISTINCT FROM 'array'
 THEN RETURN jsonb_build_object('status','BLOCKED','reason','CANONICAL_SHADOW_INVALID'); END IF;
 FOR f IN SELECT value FROM jsonb_array_elements(j->'families') LOOP
  n:=n+1;
  IF f#>>'{independent_oracle,implemented}' IS DISTINCT FROM 'true' THEN CONTINUE; END IF;
  fam:=f->>'family_code';cur:=f#>>'{current_result,coverage_status}';
  alt:=f#>>'{independent_oracle,classification}';
  IF nullif(btrim(coalesce(fam,'')),'') IS NULL
   OR coalesce(cur,'') NOT IN ('COMPLETE','PARTIAL','MISSING')
   OR coalesce(alt,'') NOT IN ('COMPLETE','PARTIAL','MISSING')
  THEN RETURN jsonb_build_object('status','BLOCKED','reason','ORACLE_NOT_COMPARABLE'); END IF;
  oc:=oc+1;
  IF cur=alt THEN CONTINUE; END IF;
  nd:=nd+1;ref:=format('screen:%s/family:%s',p_screen_id,fam);
  diff:=jsonb_build_object('diff_ref',ref||'/coverage_status',
   'consumer_code','INPUT_GOVERNANCE','subject_scope',ref,
   'family_code',fam,'field_path','coverage_status',
   'current_value',cur,'candidate_value',alt,
   'current_sha256',programacion.fn_v09_sha256_jsonb(to_jsonb(cur)),
   'candidate_sha256',programacion.fn_v09_sha256_jsonb(to_jsonb(alt)),
   'oracle_reason',f#>>'{independent_oracle,reason}',
   'oracle_source_refs',f#>'{independent_oracle,source_refs}');
  a:=a||jsonb_build_array(diff||jsonb_build_object('diff_sha256',programacion.fn_v09_sha256_jsonb(diff)));
 END LOOP;
 IF n IS DISTINCT FROM (j#>>'{summary,family_count}')::integer
 OR oc IS DISTINCT FROM (j#>>'{summary,oracle_implemented_family_count}')::integer
 OR nd IS DISTINCT FROM (j#>>'{summary,oracle_divergence_count}')::integer
 THEN RETURN jsonb_build_object('status','BLOCKED','reason','CANONICAL_SUMMARY_DRIFT'); END IF;
 RETURN jsonb_build_object('schema_version','IG_M96_SHADOW_FIELD_OBSERVATION_V1',
 'status','BLOCKED_PENDING_FIELD_POLICY_AND_ADJUDICATION',
 'screen_id',p_screen_id,'version_id',p_version_id,
 'canonical_shadow_sha256',j->>'shadow_sha256',
 'family_count',n,'oracles_implemented',oc,
 'oracles_missing',n-oc,'field_diff_count',nd,
 'field_diffs',a,'typed_receipt_emitted',false,
 'human_decisions_emitted',false,'production_authorized',false);
END $probe$;
REVOKE ALL ON FUNCTION programacion.fn_ig_m96_shadow_field_probe_v1(integer,bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION programacion.fn_ig_m96_shadow_field_probe_v1(integer,bigint) TO service_role;
COMMENT ON FUNCTION programacion.fn_ig_m96_shadow_field_probe_v1(integer,bigint)
IS 'Canonical read-only M9.6 per-field observations; incomplete oracles/policies never imply equivalence or adjudication.';
DO $tests$
DECLARE r jsonb; v_screen integer;
BEGIN
 SELECT pantalla_id INTO v_screen FROM programacion.v_input_governance_representative_cohort_v1
 WHERE cohort_type_code='RECOVERY' ORDER BY representative_rank LIMIT 1;
 IF v_screen IS NULL THEN RAISE EXCEPTION 'M96_GOVERNED_COHORT_MISSING'; END IF;
 r:=programacion.fn_ig_m96_shadow_field_probe_v1(v_screen,19);
 IF r->>'status'<>'BLOCKED_PENDING_FIELD_POLICY_AND_ADJUDICATION'
 OR jsonb_array_length(r->'field_diffs')<>(r->>'field_diff_count')::integer
 OR (r->>'oracles_missing')::int<=0
 OR (r->>'typed_receipt_emitted')::boolean
 OR (r->>'production_authorized')::boolean
 THEN RAISE EXCEPTION 'M96_REAL_FIELD_OBSERVATION_FAILED:%',r; END IF;
 IF programacion.fn_ig_m96_shadow_field_probe_v1(-1,19)->>'reason'<>'SCREEN_NOT_ACTIVE_OR_JOINABLE'
 THEN RAISE EXCEPTION 'M96_MISSING_SCREEN_NEGATIVE_FAILED'; END IF;
END $tests$;
COMMIT;
