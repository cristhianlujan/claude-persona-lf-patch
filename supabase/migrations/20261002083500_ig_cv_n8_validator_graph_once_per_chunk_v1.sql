-- N-8 / PAULO-173
-- Build the canonical screen graph once per validator chunk and reuse it for
-- the 10-family classifier loop. Git-first only; runtime activation is separate.

DO $n8$
DECLARE
  v_proc regprocedure := 'programacion.fn_input_governance_validate_v2(bigint,text)'::regprocedure;
  v_before_src text;
  v_after_src text;
  v_def text;
  v_new text;
  v_old_decl constant text := $old_decl$  v_payload jsonb; v_result jsonb; v_prop jsonb; a record; v_pending_before integer;$old_decl$;
  v_new_decl constant text := $new_decl$  v_payload jsonb; v_result jsonb; v_prop jsonb; a record; v_pending_before integer; v_run_version_id bigint; v_graph jsonb;$new_decl$;
  v_old_select constant text := $old_select$  select status,pantalla_id,family_count,curator_identity,validator_identity,contract_revision
    into v_status,v_pantalla_id,v_family_count,v_curator_identity,v_existing_validator,v_contract_revision
  from programacion.input_readiness_runs
  where id=p_run_id and version_id=19 and scope->>'analysis_revision'='INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX';$old_select$;
  v_new_select constant text := $new_select$  select status,pantalla_id,family_count,curator_identity,validator_identity,contract_revision,version_id
    into v_status,v_pantalla_id,v_family_count,v_curator_identity,v_existing_validator,v_contract_revision,v_run_version_id
  from programacion.input_readiness_runs
  where id=p_run_id and version_id=19 and scope->>'analysis_revision'='INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX';$new_select$;
  v_old_loop constant text := $old_loop$  select count(*) into v_pending_before from programacion.input_family_assessments where run_id=p_run_id and validator_outcome='PENDING';

  for a in$old_loop$;
  v_new_loop constant text := $new_loop$  select count(*) into v_pending_before from programacion.input_family_assessments where run_id=p_run_id and validator_outcome='PENDING';
  v_graph:=programacion.fn_input_screen_canonical_graph(v_pantalla_id,v_run_version_id);

  for a in$new_loop$;
  v_old_call constant text := $old_call$v_expected:=programacion.fn_input_governance_bootstrap_classify_v2(v_pantalla_id,a.family_code,19);$old_call$;
  v_new_call constant text := $new_call$v_expected:=programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(v_pantalla_id,a.family_code,v_run_version_id,v_graph);$new_call$;
BEGIN
  SELECT p.prosrc, pg_get_functiondef(p.oid)
    INTO v_before_src, v_def
  FROM pg_proc p
  WHERE p.oid=v_proc;

  IF md5(v_before_src) <> 'b4b186c5a832d1f83bcb6db45230c0d7' THEN
    RAISE EXCEPTION 'N8_VALIDATOR_SOURCE_DRIFT expected=b4b186c5a832d1f83bcb6db45230c0d7 actual=%', md5(v_before_src);
  END IF;

  IF position(v_old_decl in v_def)=0
     OR position(v_old_select in v_def)=0
     OR position(v_old_loop in v_def)=0
     OR position(v_old_call in v_def)=0 THEN
    RAISE EXCEPTION 'N8_VALIDATOR_PATCH_ANCHOR_MISSING';
  END IF;

  v_new:=replace(v_def,v_old_decl,v_new_decl);
  v_new:=replace(v_new,v_old_select,v_new_select);
  v_new:=replace(v_new,v_old_loop,v_new_loop);
  v_new:=replace(v_new,v_old_call,v_new_call);

  IF position(v_old_call in v_new)>0
     OR position(v_new_call in v_new)=0
     OR position('v_graph:=programacion.fn_input_screen_canonical_graph(v_pantalla_id,v_run_version_id);' in v_new)=0 THEN
    RAISE EXCEPTION 'N8_VALIDATOR_PATCH_POSTCONDITION_FAILED';
  END IF;

  EXECUTE v_new;

  SELECT p.prosrc INTO v_after_src
  FROM pg_proc p
  WHERE p.oid=v_proc;

  IF md5(v_after_src)=md5(v_before_src) THEN
    RAISE EXCEPTION 'N8_VALIDATOR_SOURCE_UNCHANGED';
  END IF;

  IF position('fn_input_governance_bootstrap_classify_v2_cached_v2' in v_after_src)=0
     OR position('fn_input_screen_canonical_graph' in v_after_src)=0 THEN
    RAISE EXCEPTION 'N8_VALIDATOR_LIVE_POSTCONDITION_FAILED';
  END IF;
END
$n8$;

COMMENT ON FUNCTION programacion.fn_input_governance_validate_v2(bigint,text)
IS 'N-8: canonical graph built once per validator chunk and reused by cached classifier; semantic output must remain equivalent.';
