-- Transversal consumer reconciliation at current INDEPENDENT_ASSURANCE 2.0.1.
-- Preserve historical manifests. Do not alter assurance provider or create a new gate.
DO $change$
DECLARE v_safe jsonb; v_rev jsonb; v_human jsonb; v_safe_sha text; v_rev_sha text; v_human_sha text;
DECLARE v_result jsonb;
DECLARE v_actor text := 'IG_DUAL_SCOPE_RECONCILIATION_20261009';
BEGIN
  IF (SELECT version FROM public.lf_capability_current WHERE capability_code='INDEPENDENT_ASSURANCE') <> '2.0.1'
     OR (SELECT manifest_sha256 FROM public.lf_capability_current WHERE capability_code='INDEPENDENT_ASSURANCE')
       <> 'f87727d3c81f3cda4c4ea8f5c23d7715bcda9e0f08bd1b2eae1188117b946d35'
  THEN RAISE EXCEPTION 'INDEPENDENT_ASSURANCE_CURRENT_DRIFT'; END IF;
  IF (SELECT version FROM public.lf_capability_current WHERE capability_code='SAFE_CHANGE_ADMISSION') <> '1.0.1'
  OR (SELECT version FROM public.lf_capability_current WHERE capability_code='REVERSIBLE_CANDIDATE_VERIFICATION') <> '1.0.2'
  OR (SELECT version FROM public.lf_capability_current WHERE capability_code='HUMAN_ESCALATION_ADMISSION') <> '1.0.3'
  THEN RAISE EXCEPTION 'CONSUMER_BASE_DRIFT'; END IF;
  SELECT manifest INTO STRICT v_safe FROM public.lf_capability_version_registry
  WHERE capability_code='SAFE_CHANGE_ADMISSION' AND version='1.0.1';
  v_safe := jsonb_set(jsonb_set(jsonb_set(v_safe,
    '{version}','"1.0.2"'::jsonb),
    '{dependencies,INDEPENDENT_ASSURANCE}',
    '{"version":"2.0.1","manifest_sha256":"f87727d3c81f3cda4c4ea8f5c23d7715bcda9e0f08bd1b2eae1188117b946d35"}'::jsonb),
    '{supersession_reason}',to_jsonb('Pinned provider upgraded after canonical measurement compatibility test; unchanged classifier semantics'::text));
  v_safe_sha := encode(extensions.digest(convert_to(v_safe::text,'UTF8'),'sha256'),'hex');
  INSERT INTO public.lf_capability_version_registry(
    capability_code,version,version_major,version_minor,version_patch,release_state,supersedes_version,
    manifest,manifest_sha256,source_ref,docs_ref,validator_ref,created_by_execution_id)
  SELECT capability_code,'1.0.2',1,0,2,'RELEASED','1.0.1',v_safe,v_safe_sha,
    'supabase/migrations/20261009134500_ig_transversal_assurance_consumers_v1.sql',
    docs_ref,validator_ref,v_actor
  FROM public.lf_capability_version_registry WHERE capability_code='SAFE_CHANGE_ADMISSION' AND version='1.0.1';
  v_result := public.fn_lf_capability_promote_v1('SAFE_CHANGE_ADMISSION','1.0.2',
    '14495cac9611071b3bf153497c54fc31bbfea51a3b29331274d774035994b3da',v_actor,
    'Compatible current independent assurance, exact required 2.0.1 measurement');
  IF v_result->>'decision'<>'PROMOTED_CURRENT' THEN RAISE EXCEPTION 'SAFE_PROMOTE_FAILED:%',v_result; END IF;

  SELECT manifest INTO STRICT v_rev FROM public.lf_capability_version_registry
   WHERE capability_code='REVERSIBLE_CANDIDATE_VERIFICATION' AND version='1.0.2';
  v_rev := jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(jsonb_set(v_rev,
     '{version}','"1.0.3"'::jsonb),
     '{dependencies,independent_assurance}',
     '{"version":"2.0.1","consumption":"REQUIRED_RECEIPT_FAIL_CLOSED","capability_code":"INDEPENDENT_ASSURANCE","manifest_sha256":"f87727d3c81f3cda4c4ea8f5c23d7715bcda9e0f08bd1b2eae1188117b946d35"}'::jsonb),
     '{contract,baseline_oracle_contract,required_version}','"2.0.1"'::jsonb),
     '{contract,baseline_oracle_contract,required_manifest_sha256}',
     '"f87727d3c81f3cda4c4ea8f5c23d7715bcda9e0f08bd1b2eae1188117b946d35"'::jsonb),
     '{delivery,source_blob_sha1}','"b619ea4238e4a97867b29447f9f80e5ac8079151"'::jsonb),
     '{delivery,test_blob_sha1}','"6647b86a71c9489f276e53e013e839310e486163"'::jsonb),
     '{delivery,source_commit}','"b23416192a2a87e8407c8d758af424611f9fd80a"'::jsonb);
  v_rev := jsonb_set(jsonb_set(jsonb_set(jsonb_set(v_rev,
     '{currentness,source_blob_sha1}','"b619ea4238e4a97867b29447f9f80e5ac8079151"'::jsonb),
     '{currentness,test_blob_sha1}','"6647b86a71c9489f276e53e013e839310e486163"'::jsonb),
     '{currentness,source_commit}','"b23416192a2a87e8407c8d758af424611f9fd80a"'::jsonb),
     '{qualification,scope}','"NEW_V2_0_1_RECEIPT_REGRESSION_REQUIRED"'::jsonb);
  v_rev := jsonb_set(v_rev,'{supersession_reason}',
    to_jsonb('Canonical 2.0.1 receipt format, Python code and adversarial tests pinned to exact Git blobs'::text));
  v_rev_sha := encode(extensions.digest(convert_to(v_rev::text,'UTF8'),'sha256'),'hex');
  INSERT INTO public.lf_capability_version_registry(
    capability_code,version,version_major,version_minor,version_patch,release_state,supersedes_version,
    manifest,manifest_sha256,source_ref,docs_ref,validator_ref,created_by_execution_id)
  SELECT capability_code,'1.0.3',1,0,3,'RELEASED','1.0.2',v_rev,v_rev_sha,
    'github://cristhianlujan/claude-persona-lf-patch@b23416192a2a87e8407c8d758af424611f9fd80a/sandbox/lf_contract_gate_test/transversal_assets/reversible_candidate_verification/reversible_candidate_verification_v1.py',
    docs_ref,validator_ref,v_actor
  FROM public.lf_capability_version_registry
  WHERE capability_code='REVERSIBLE_CANDIDATE_VERIFICATION' AND version='1.0.2';
  v_result := public.fn_lf_capability_promote_v1('REVERSIBLE_CANDIDATE_VERIFICATION','1.0.3',
    'e66afa12db0acac27c154d948f60efcc8469e13345b1669a4ae6ff4fd6dbe777',v_actor,
    'Canonical measure receipt contract plus Python regression');
  IF v_result->>'decision'<>'PROMOTED_CURRENT' THEN RAISE EXCEPTION 'REV_PROMOTE_FAILED:%',v_result; END IF;

  SELECT manifest INTO STRICT v_human FROM public.lf_capability_version_registry
  WHERE capability_code='HUMAN_ESCALATION_ADMISSION' AND version='1.0.3';
  v_human := jsonb_set(jsonb_set(v_human,
     '{version}','"1.0.4"'::jsonb),
     '{dependencies,SAFE_CHANGE_ADMISSION}',
     jsonb_build_object('version','1.0.2','manifest_sha256',v_safe_sha));
  v_human := jsonb_set(v_human,'{supersession_reason}',
     to_jsonb('Rebind human routing to tested current safe change classification; preserve fail closed'::text));
  v_human_sha:=encode(extensions.digest(convert_to(v_human::text,'UTF8'),'sha256'),'hex');
  INSERT INTO public.lf_capability_version_registry(
    capability_code,version,version_major,version_minor,version_patch,release_state,supersedes_version,
    manifest,manifest_sha256,source_ref,docs_ref,validator_ref,created_by_execution_id)
  SELECT capability_code,'1.0.4',1,0,4,'RELEASED','1.0.3',v_human,v_human_sha,
    'supabase/migrations/20261009134500_ig_transversal_assurance_consumers_v1.sql',
    docs_ref,validator_ref,v_actor
  FROM public.lf_capability_version_registry
  WHERE capability_code='HUMAN_ESCALATION_ADMISSION' AND version='1.0.3';
  v_result := public.fn_lf_capability_promote_v1('HUMAN_ESCALATION_ADMISSION','1.0.4',
    '5e8243bbde714c2c6316b3165bd5560193a498e1628750aa0c30ac159ed6182d',v_actor,
    'Downstream exact SHA coupling of Safe Change Admission');
  IF v_result->>'decision'<>'PROMOTED_CURRENT' THEN RAISE EXCEPTION 'HUMAN_PROMOTE_FAILED:%',v_result; END IF;
END $change$;
