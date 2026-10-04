-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / T-CONS-ADM / PAULO-190
-- CONSUMER_ADMISSION transversal capability.
-- Owner: SUPER_ADMIN. IG remains a consumer.
-- Reuses CURRENTNESS_AUTHORITY, CAPABILITY_VERSION_COMPATIBILITY and
-- T-CONSUMERS prior art via ASSET_RETIREMENT_GOVERNANCE.
-- No N-13/N-15 mutation; no production/runtime effect.

DO $pre$
DECLARE
  v_cur record;
  v_compat record;
  v_retire record;
BEGIN
  SELECT r.status,r.owner_scope,c.version,c.manifest_sha256
    INTO v_cur
  FROM public.lf_capability_registry r
  JOIN public.lf_capability_current c USING(capability_code)
  WHERE r.capability_code='CURRENTNESS_AUTHORITY';
  IF NOT FOUND OR v_cur.status<>'ACTIVE' OR v_cur.version IS NULL
     OR v_cur.manifest_sha256 !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'BLOCK_T_CONS_ADM_CURRENTNESS_AUTHORITY_NOT_CURRENT';
  END IF;

  SELECT r.status,r.owner_scope,c.version,c.manifest_sha256
    INTO v_compat
  FROM public.lf_capability_registry r
  JOIN public.lf_capability_current c USING(capability_code)
  WHERE r.capability_code='CAPABILITY_VERSION_COMPATIBILITY';
  IF NOT FOUND OR v_compat.status<>'ACTIVE' OR v_compat.version IS NULL
     OR v_compat.manifest_sha256 !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'BLOCK_T_CONS_ADM_VERSION_COMPATIBILITY_NOT_CURRENT';
  END IF;

  SELECT r.status,r.owner_scope,c.version,c.manifest_sha256
    INTO v_retire
  FROM public.lf_capability_registry r
  JOIN public.lf_capability_current c USING(capability_code)
  WHERE r.capability_code='ASSET_RETIREMENT_GOVERNANCE';
  IF NOT FOUND OR v_retire.status<>'ACTIVE' OR v_retire.version IS NULL
     OR v_retire.manifest_sha256 !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'BLOCK_T_CONS_ADM_RETIREMENT_GOVERNANCE_NOT_CURRENT';
  END IF;
END
$pre$;

CREATE OR REPLACE FUNCTION public.lf_consumer_admission_evaluate_v1(p_request jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $fn$
DECLARE
  v_self_manifest jsonb;
  v_expected_cur_version text;
  v_expected_cur_sha text;
  v_expected_compat_version text;
  v_expected_compat_sha text;
  v_expected_retire_version text;
  v_expected_retire_sha text;
  v_live_cur_version text;
  v_live_cur_sha text;
  v_live_compat_version text;
  v_live_compat_sha text;
  v_live_retire_version text;
  v_live_retire_sha text;
  v_consumer text;
  v_applicability text;
  v_requiredness text;
  v_capability_code text;
  v_requested_version text;
  v_requested_sha text;
  v_live_version text;
  v_live_sha text;
  v_currentness jsonb;
  v_currentness_decision text;
  v_currentness_ready boolean;
  v_receiver_state text;
  v_receiver_receipt text;
  v_state text;
  v_code text;
BEGIN
  IF p_request IS NULL OR jsonb_typeof(p_request)<>'object' THEN
    RETURN jsonb_build_object(
      'schema_version','LF_CONSUMER_ADMISSION_RESULT_V1',
      'state','UNKNOWN','code','INVALID_REQUEST',
      'requiredness',NULL,'applicability',NULL,
      'retirement_hook','ASSET_RETIREMENT_GOVERNANCE'
    );
  END IF;

  SELECT vr.manifest
    INTO v_self_manifest
  FROM public.lf_capability_current c
  JOIN public.lf_capability_version_registry vr
    ON vr.capability_code=c.capability_code
   AND vr.version=c.version
   AND vr.manifest_sha256=c.manifest_sha256
  WHERE c.capability_code='CONSUMER_ADMISSION';

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'schema_version','LF_CONSUMER_ADMISSION_RESULT_V1',
      'state','UNKNOWN','code','CAPABILITY_NOT_CURRENT',
      'retirement_hook','ASSET_RETIREMENT_GOVERNANCE'
    );
  END IF;

  v_expected_cur_version:=v_self_manifest#>>'{dependencies,CURRENTNESS_AUTHORITY,version}';
  v_expected_cur_sha:=v_self_manifest#>>'{dependencies,CURRENTNESS_AUTHORITY,manifest_sha256}';
  v_expected_compat_version:=v_self_manifest#>>'{dependencies,CAPABILITY_VERSION_COMPATIBILITY,version}';
  v_expected_compat_sha:=v_self_manifest#>>'{dependencies,CAPABILITY_VERSION_COMPATIBILITY,manifest_sha256}';
  v_expected_retire_version:=v_self_manifest#>>'{dependencies,ASSET_RETIREMENT_GOVERNANCE,version}';
  v_expected_retire_sha:=v_self_manifest#>>'{dependencies,ASSET_RETIREMENT_GOVERNANCE,manifest_sha256}';

  SELECT version,manifest_sha256 INTO v_live_cur_version,v_live_cur_sha
  FROM public.lf_capability_current WHERE capability_code='CURRENTNESS_AUTHORITY';
  SELECT version,manifest_sha256 INTO v_live_compat_version,v_live_compat_sha
  FROM public.lf_capability_current WHERE capability_code='CAPABILITY_VERSION_COMPATIBILITY';
  SELECT version,manifest_sha256 INTO v_live_retire_version,v_live_retire_sha
  FROM public.lf_capability_current WHERE capability_code='ASSET_RETIREMENT_GOVERNANCE';

  IF v_live_cur_version IS DISTINCT FROM v_expected_cur_version
     OR v_live_cur_sha IS DISTINCT FROM v_expected_cur_sha
     OR v_live_compat_version IS DISTINCT FROM v_expected_compat_version
     OR v_live_compat_sha IS DISTINCT FROM v_expected_compat_sha
     OR v_live_retire_version IS DISTINCT FROM v_expected_retire_version
     OR v_live_retire_sha IS DISTINCT FROM v_expected_retire_sha THEN
    RETURN jsonb_build_object(
      'schema_version','LF_CONSUMER_ADMISSION_RESULT_V1',
      'state','UNKNOWN','code','DEPENDENCY_CURRENTNESS_DRIFT',
      'retirement_hook','ASSET_RETIREMENT_GOVERNANCE',
      'dependency_readback',jsonb_build_object(
        'CURRENTNESS_AUTHORITY',jsonb_build_object(
          'expected_version',v_expected_cur_version,'live_version',v_live_cur_version,
          'expected_manifest_sha256',v_expected_cur_sha,'live_manifest_sha256',v_live_cur_sha),
        'CAPABILITY_VERSION_COMPATIBILITY',jsonb_build_object(
          'expected_version',v_expected_compat_version,'live_version',v_live_compat_version,
          'expected_manifest_sha256',v_expected_compat_sha,'live_manifest_sha256',v_live_compat_sha),
        'ASSET_RETIREMENT_GOVERNANCE',jsonb_build_object(
          'expected_version',v_expected_retire_version,'live_version',v_live_retire_version,
          'expected_manifest_sha256',v_expected_retire_sha,'live_manifest_sha256',v_live_retire_sha)
      )
    );
  END IF;

  v_consumer:=nullif(btrim(coalesce(p_request->>'consumer_ref','')),'');
  v_applicability:=upper(btrim(coalesce(p_request->>'applicability','')));
  v_requiredness:=upper(btrim(coalesce(p_request->>'requiredness','')));

  IF v_consumer IS NULL THEN
    RETURN jsonb_build_object(
      'schema_version','LF_CONSUMER_ADMISSION_RESULT_V1',
      'state','UNKNOWN','code','CONSUMER_REF_REQUIRED',
      'requiredness',nullif(v_requiredness,''),'applicability',nullif(v_applicability,''),
      'retirement_hook','ASSET_RETIREMENT_GOVERNANCE'
    );
  END IF;

  IF v_applicability NOT IN ('APPLICABLE','NOT_APPLICABLE','UNKNOWN') THEN
    RETURN jsonb_build_object(
      'schema_version','LF_CONSUMER_ADMISSION_RESULT_V1',
      'consumer_ref',v_consumer,'state','UNKNOWN','code','APPLICABILITY_INVALID',
      'requiredness',nullif(v_requiredness,''),'applicability',nullif(v_applicability,''),
      'retirement_hook','ASSET_RETIREMENT_GOVERNANCE'
    );
  END IF;

  IF v_requiredness NOT IN ('REQUIRED','OPTIONAL','NOT_APPLICABLE') THEN
    RETURN jsonb_build_object(
      'schema_version','LF_CONSUMER_ADMISSION_RESULT_V1',
      'consumer_ref',v_consumer,'state','UNKNOWN','code','REQUIREDNESS_INVALID',
      'requiredness',nullif(v_requiredness,''),'applicability',v_applicability,
      'retirement_hook','ASSET_RETIREMENT_GOVERNANCE'
    );
  END IF;

  IF v_applicability='NOT_APPLICABLE' THEN
    IF v_requiredness='REQUIRED' THEN
      RETURN jsonb_build_object(
        'schema_version','LF_CONSUMER_ADMISSION_RESULT_V1',
        'consumer_ref',v_consumer,'state','UNKNOWN',
        'code','APPLICABILITY_REQUIREDNESS_CONTRADICTION',
        'requiredness',v_requiredness,'applicability',v_applicability,
        'retirement_hook','ASSET_RETIREMENT_GOVERNANCE'
      );
    END IF;
    RETURN jsonb_build_object(
      'schema_version','LF_CONSUMER_ADMISSION_RESULT_V1',
      'consumer_ref',v_consumer,'state','NOT_REQUIRED','code','NOT_APPLICABLE',
      'requiredness',v_requiredness,'applicability',v_applicability,
      'retirement_hook','ASSET_RETIREMENT_GOVERNANCE'
    );
  END IF;

  IF v_applicability='UNKNOWN' THEN
    RETURN jsonb_build_object(
      'schema_version','LF_CONSUMER_ADMISSION_RESULT_V1',
      'consumer_ref',v_consumer,'state','UNKNOWN','code','APPLICABILITY_UNKNOWN',
      'requiredness',v_requiredness,'applicability',v_applicability,
      'retirement_hook','ASSET_RETIREMENT_GOVERNANCE'
    );
  END IF;

  IF v_requiredness='NOT_APPLICABLE' THEN
    RETURN jsonb_build_object(
      'schema_version','LF_CONSUMER_ADMISSION_RESULT_V1',
      'consumer_ref',v_consumer,'state','UNKNOWN',
      'code','APPLICABILITY_REQUIREDNESS_CONTRADICTION',
      'requiredness',v_requiredness,'applicability',v_applicability,
      'retirement_hook','ASSET_RETIREMENT_GOVERNANCE'
    );
  END IF;

  IF jsonb_typeof(p_request->'capability') IS DISTINCT FROM 'object' THEN
    RETURN jsonb_build_object(
      'schema_version','LF_CONSUMER_ADMISSION_RESULT_V1',
      'consumer_ref',v_consumer,'state','UNKNOWN','code','CAPABILITY_IDENTITY_REQUIRED',
      'requiredness',v_requiredness,'applicability',v_applicability,
      'retirement_hook','ASSET_RETIREMENT_GOVERNANCE'
    );
  END IF;

  v_capability_code:=nullif(btrim(coalesce(p_request#>>'{capability,code}','')),'');
  v_requested_version:=nullif(btrim(coalesce(p_request#>>'{capability,version}','')),'');
  v_requested_sha:=nullif(btrim(coalesce(p_request#>>'{capability,manifest_sha256}','')),'');

  IF v_capability_code IS NULL OR v_requested_version IS NULL
     OR v_requested_sha IS NULL OR v_requested_sha !~ '^[0-9a-f]{64}$' THEN
    RETURN jsonb_build_object(
      'schema_version','LF_CONSUMER_ADMISSION_RESULT_V1',
      'consumer_ref',v_consumer,'state','UNKNOWN','code','CAPABILITY_IDENTITY_INVALID',
      'requiredness',v_requiredness,'applicability',v_applicability,
      'retirement_hook','ASSET_RETIREMENT_GOVERNANCE'
    );
  END IF;

  SELECT c.version,c.manifest_sha256
    INTO v_live_version,v_live_sha
  FROM public.lf_capability_current c
  JOIN public.lf_capability_version_registry vr
    ON vr.capability_code=c.capability_code
   AND vr.version=c.version
   AND vr.manifest_sha256=c.manifest_sha256
  WHERE c.capability_code=v_capability_code
    AND vr.release_state='RELEASED';

  IF NOT FOUND THEN
    v_state:=case when v_requiredness='REQUIRED' then 'BLOCK' else 'HOLD' end;
    RETURN jsonb_build_object(
      'schema_version','LF_CONSUMER_ADMISSION_RESULT_V1',
      'consumer_ref',v_consumer,'state',v_state,'code','CAPABILITY_CURRENT_UNRESOLVED',
      'requiredness',v_requiredness,'applicability',v_applicability,
      'capability_code',v_capability_code,
      'compatibility_authority','CAPABILITY_VERSION_COMPATIBILITY',
      'currentness_authority','CURRENTNESS_AUTHORITY',
      'retirement_hook','ASSET_RETIREMENT_GOVERNANCE'
    );
  END IF;

  IF v_requested_version IS DISTINCT FROM v_live_version
     OR v_requested_sha IS DISTINCT FROM v_live_sha THEN
    v_state:=case when v_requiredness='REQUIRED' then 'BLOCK' else 'HOLD' end;
    RETURN jsonb_build_object(
      'schema_version','LF_CONSUMER_ADMISSION_RESULT_V1',
      'consumer_ref',v_consumer,'state',v_state,'code','CAPABILITY_VERSION_STALE_OR_INCOMPATIBLE',
      'requiredness',v_requiredness,'applicability',v_applicability,
      'capability_code',v_capability_code,
      'requested_version',v_requested_version,'current_version',v_live_version,
      'requested_manifest_sha256',v_requested_sha,'current_manifest_sha256',v_live_sha,
      'compatibility_authority','CAPABILITY_VERSION_COMPATIBILITY',
      'currentness_authority','CURRENTNESS_AUTHORITY',
      'retirement_hook','ASSET_RETIREMENT_GOVERNANCE'
    );
  END IF;

  v_currentness:=p_request->'currentness';
  IF jsonb_typeof(v_currentness) IS DISTINCT FROM 'object'
     OR v_currentness->>'schema_version' IS DISTINCT FROM 'LF_CURRENTNESS_AUTHORITY_RECEIPT_V1'
     OR v_currentness->>'authority_layer' IS DISTINCT FROM 'CURRENTNESS_AUTHORITY' THEN
    RETURN jsonb_build_object(
      'schema_version','LF_CONSUMER_ADMISSION_RESULT_V1',
      'consumer_ref',v_consumer,'state','UNKNOWN','code','CURRENTNESS_AUTHORITY_RECEIPT_REQUIRED',
      'requiredness',v_requiredness,'applicability',v_applicability,
      'capability_code',v_capability_code,'capability_version',v_requested_version,
      'compatibility_authority','CAPABILITY_VERSION_COMPATIBILITY',
      'currentness_authority','CURRENTNESS_AUTHORITY',
      'retirement_hook','ASSET_RETIREMENT_GOVERNANCE'
    );
  END IF;

  v_currentness_decision:=upper(coalesce(v_currentness->>'decision',''));
  IF jsonb_typeof(v_currentness->'ready') IS DISTINCT FROM 'boolean' THEN
    RETURN jsonb_build_object(
      'schema_version','LF_CONSUMER_ADMISSION_RESULT_V1',
      'consumer_ref',v_consumer,'state','UNKNOWN','code','CURRENTNESS_READY_INVALID',
      'requiredness',v_requiredness,'applicability',v_applicability,
      'capability_code',v_capability_code,'capability_version',v_requested_version,
      'compatibility_authority','CAPABILITY_VERSION_COMPATIBILITY',
      'currentness_authority','CURRENTNESS_AUTHORITY',
      'retirement_hook','ASSET_RETIREMENT_GOVERNANCE'
    );
  END IF;
  v_currentness_ready:=(v_currentness->>'ready')::boolean;

  IF v_currentness_ready IS NOT TRUE
     OR v_currentness_decision NOT IN ('CURRENT','CURRENT_REBOUND') THEN
    IF v_currentness_decision IN ('UNKNOWN','UNKNOWN_FAIL_CLOSED','') THEN
      v_state:='UNKNOWN'; v_code:='CURRENTNESS_UNKNOWN';
    ELSE
      v_state:=case when v_requiredness='REQUIRED' then 'BLOCK' else 'HOLD' end;
      v_code:='CURRENTNESS_NOT_CURRENT';
    END IF;
    RETURN jsonb_build_object(
      'schema_version','LF_CONSUMER_ADMISSION_RESULT_V1',
      'consumer_ref',v_consumer,'state',v_state,'code',v_code,
      'requiredness',v_requiredness,'applicability',v_applicability,
      'capability_code',v_capability_code,'capability_version',v_requested_version,
      'compatibility_authority','CAPABILITY_VERSION_COMPATIBILITY',
      'currentness_authority','CURRENTNESS_AUTHORITY',
      'currentness_decision',nullif(v_currentness_decision,''),
      'retirement_hook','ASSET_RETIREMENT_GOVERNANCE'
    );
  END IF;

  IF jsonb_typeof(p_request->'receiver_status') IS DISTINCT FROM 'object' THEN
    RETURN jsonb_build_object(
      'schema_version','LF_CONSUMER_ADMISSION_RESULT_V1',
      'consumer_ref',v_consumer,'state','UNKNOWN','code','RECEIVER_STATUS_REQUIRED',
      'requiredness',v_requiredness,'applicability',v_applicability,
      'capability_code',v_capability_code,'capability_version',v_requested_version,
      'compatibility_authority','CAPABILITY_VERSION_COMPATIBILITY',
      'currentness_authority','CURRENTNESS_AUTHORITY',
      'retirement_hook','ASSET_RETIREMENT_GOVERNANCE'
    );
  END IF;

  v_receiver_state:=upper(btrim(coalesce(p_request#>>'{receiver_status,state}','')));
  v_receiver_receipt:=nullif(btrim(coalesce(p_request#>>'{receiver_status,receipt_ref}','')),'');

  IF v_receiver_state NOT IN ('PASS','HOLD','BLOCK','UNKNOWN') THEN
    RETURN jsonb_build_object(
      'schema_version','LF_CONSUMER_ADMISSION_RESULT_V1',
      'consumer_ref',v_consumer,'state','UNKNOWN','code','RECEIVER_STATUS_INVALID',
      'requiredness',v_requiredness,'applicability',v_applicability,
      'capability_code',v_capability_code,'capability_version',v_requested_version,
      'compatibility_authority','CAPABILITY_VERSION_COMPATIBILITY',
      'currentness_authority','CURRENTNESS_AUTHORITY',
      'retirement_hook','ASSET_RETIREMENT_GOVERNANCE'
    );
  END IF;

  IF v_receiver_state='PASS' AND v_receiver_receipt IS NULL THEN
    RETURN jsonb_build_object(
      'schema_version','LF_CONSUMER_ADMISSION_RESULT_V1',
      'consumer_ref',v_consumer,'state','UNKNOWN','code','RECEIVER_PASS_RECEIPT_REQUIRED',
      'requiredness',v_requiredness,'applicability',v_applicability,
      'capability_code',v_capability_code,'capability_version',v_requested_version,
      'compatibility_authority','CAPABILITY_VERSION_COMPATIBILITY',
      'currentness_authority','CURRENTNESS_AUTHORITY',
      'retirement_hook','ASSET_RETIREMENT_GOVERNANCE'
    );
  END IF;

  v_state:=v_receiver_state;
  v_code:=case v_receiver_state
    when 'PASS' then 'CONSUMER_ADMITTED'
    when 'HOLD' then 'RECEIVER_HOLD'
    when 'BLOCK' then 'RECEIVER_BLOCK'
    else 'RECEIVER_UNKNOWN'
  end;

  RETURN jsonb_build_object(
    'schema_version','LF_CONSUMER_ADMISSION_RESULT_V1',
    'consumer_ref',v_consumer,'state',v_state,'code',v_code,
    'requiredness',v_requiredness,'applicability',v_applicability,
    'capability_code',v_capability_code,'capability_version',v_requested_version,
    'capability_manifest_sha256',v_requested_sha,
    'receiver_receipt_ref',v_receiver_receipt,
    'compatibility_authority','CAPABILITY_VERSION_COMPATIBILITY',
    'currentness_authority','CURRENTNESS_AUTHORITY',
    'currentness_decision',v_currentness_decision,
    'retirement_hook','ASSET_RETIREMENT_GOVERNANCE'
  );
END
$fn$;

COMMENT ON FUNCTION public.lf_consumer_admission_evaluate_v1(jsonb)
IS 'T-CONS-ADM domain-agnostic consumer admission. Version compatibility and currentness are consumed from existing authorities; no local semantic fallback.';

CREATE OR REPLACE FUNCTION public.lf_consumer_admission_aggregate_v1(
  p_results jsonb,
  p_policy jsonb DEFAULT '{"required_unknown_fail_closed":true}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $fn$
DECLARE
  v_required_count integer:=0;
  v_required_block integer:=0;
  v_required_hold integer:=0;
  v_required_unknown integer:=0;
  v_required_pass integer:=0;
  v_optional_nonpass integer:=0;
  v_invalid integer:=0;
  v_fail_closed boolean:=true;
  v_optional_veto boolean:=false;
  v_policy_ref text;
  v_state text;
  v_code text;
BEGIN
  IF jsonb_typeof(coalesce(p_results,'null'::jsonb))<>'array' THEN
    RETURN jsonb_build_object(
      'schema_version','LF_CONSUMER_ADMISSION_AGGREGATE_V1',
      'state','BLOCK','code','AGGREGATE_INPUT_INVALID','truthful_pass',false
    );
  END IF;

  IF p_policy IS NULL OR jsonb_typeof(p_policy)<>'object' THEN
    RETURN jsonb_build_object(
      'schema_version','LF_CONSUMER_ADMISSION_AGGREGATE_V1',
      'state','BLOCK','code','AGGREGATE_POLICY_INVALID','truthful_pass',false
    );
  END IF;

  IF p_policy ? 'required_unknown_fail_closed'
     AND jsonb_typeof(p_policy->'required_unknown_fail_closed')<>'boolean' THEN
    RETURN jsonb_build_object(
      'schema_version','LF_CONSUMER_ADMISSION_AGGREGATE_V1',
      'state','BLOCK','code','REQUIRED_UNKNOWN_POLICY_INVALID','truthful_pass',false
    );
  END IF;
  v_fail_closed:=coalesce((p_policy->>'required_unknown_fail_closed')::boolean,true);

  IF p_policy ? 'optional_nonpass_veto'
     AND jsonb_typeof(p_policy->'optional_nonpass_veto')<>'boolean' THEN
    RETURN jsonb_build_object(
      'schema_version','LF_CONSUMER_ADMISSION_AGGREGATE_V1',
      'state','BLOCK','code','OPTIONAL_VETO_POLICY_INVALID','truthful_pass',false
    );
  END IF;
  v_optional_veto:=coalesce((p_policy->>'optional_nonpass_veto')::boolean,false);
  v_policy_ref:=nullif(btrim(coalesce(p_policy->>'policy_proof_ref','')),'');

  IF v_optional_veto AND v_policy_ref IS NULL THEN
    RETURN jsonb_build_object(
      'schema_version','LF_CONSUMER_ADMISSION_AGGREGATE_V1',
      'state','BLOCK','code','OPTIONAL_VETO_POLICY_PROOF_REQUIRED','truthful_pass',false
    );
  END IF;

  WITH q AS (
    SELECT
      upper(btrim(coalesce(e.value->>'requiredness',''))) AS requiredness,
      upper(btrim(coalesce(e.value->>'state',''))) AS state,
      e.value AS item
    FROM jsonb_array_elements(p_results) e(value)
  )
  SELECT
    count(*) filter(where requiredness='REQUIRED'),
    count(*) filter(where requiredness='REQUIRED' and state='PASS'),
    count(*) filter(where requiredness='REQUIRED' and state='BLOCK'),
    count(*) filter(where requiredness='REQUIRED' and state='HOLD'),
    count(*) filter(where requiredness='REQUIRED' and state='UNKNOWN'),
    count(*) filter(where requiredness='OPTIONAL' and state<>'PASS'),
    count(*) filter(where requiredness not in ('REQUIRED','OPTIONAL','NOT_APPLICABLE')
                         or state not in ('PASS','HOLD','BLOCK','NOT_REQUIRED','UNKNOWN'))
  INTO
    v_required_count,v_required_pass,v_required_block,v_required_hold,
    v_required_unknown,v_optional_nonpass,v_invalid
  FROM q;

  IF v_invalid>0 THEN
    RETURN jsonb_build_object(
      'schema_version','LF_CONSUMER_ADMISSION_AGGREGATE_V1',
      'state','BLOCK','code','AGGREGATE_ITEM_INVALID','truthful_pass',false,
      'invalid_count',v_invalid
    );
  END IF;

  IF v_required_block>0 THEN
    v_state:='BLOCK'; v_code:='REQUIRED_CONSUMER_BLOCK';
  ELSIF v_required_unknown>0 AND v_fail_closed THEN
    v_state:='BLOCK'; v_code:='REQUIRED_UNKNOWN_FAIL_CLOSED';
  ELSIF v_required_unknown>0 THEN
    v_state:='UNKNOWN'; v_code:='REQUIRED_UNKNOWN';
  ELSIF v_required_hold>0 THEN
    v_state:='HOLD'; v_code:='REQUIRED_CONSUMER_HOLD';
  ELSIF v_optional_veto AND v_optional_nonpass>0 THEN
    v_state:='HOLD'; v_code:='OPTIONAL_POLICY_VETO';
  ELSIF v_required_count=0 THEN
    v_state:='NOT_REQUIRED'; v_code:='NO_REQUIRED_CONSUMERS';
  ELSE
    v_state:='PASS'; v_code:='ALL_REQUIRED_CONSUMERS_ADMITTED';
  END IF;

  RETURN jsonb_build_object(
    'schema_version','LF_CONSUMER_ADMISSION_AGGREGATE_V1',
    'state',v_state,'code',v_code,
    'truthful_pass',(v_state='PASS'),
    'required_count',v_required_count,
    'required_pass_count',v_required_pass,
    'required_block_count',v_required_block,
    'required_hold_count',v_required_hold,
    'required_unknown_count',v_required_unknown,
    'optional_nonpass_count',v_optional_nonpass,
    'required_unknown_fail_closed',v_fail_closed,
    'optional_nonpass_veto',v_optional_veto,
    'policy_proof_ref',v_policy_ref
  );
END
$fn$;

COMMENT ON FUNCTION public.lf_consumer_admission_aggregate_v1(jsonb,jsonb)
IS 'Truthful aggregate for CONSUMER_ADMISSION. REQUIRED non-PASS prevents aggregate PASS; OPTIONAL/N/A cannot veto without explicit policy proof.';

DO $register$
DECLARE
  v_execution_id constant text:='CHATGPT-T-CONS-ADM-PAULO-190-20261004';
  v_cur_version text;
  v_cur_sha text;
  v_compat_version text;
  v_compat_sha text;
  v_retire_version text;
  v_retire_sha text;
  v_manifest jsonb;
  v_manifest_sha text;
  v_existing_sha text;
  v_promote jsonb;
BEGIN
  SELECT version,manifest_sha256 INTO v_cur_version,v_cur_sha
  FROM public.lf_capability_current WHERE capability_code='CURRENTNESS_AUTHORITY';
  SELECT version,manifest_sha256 INTO v_compat_version,v_compat_sha
  FROM public.lf_capability_current WHERE capability_code='CAPABILITY_VERSION_COMPATIBILITY';
  SELECT version,manifest_sha256 INTO v_retire_version,v_retire_sha
  FROM public.lf_capability_current WHERE capability_code='ASSET_RETIREMENT_GOVERNANCE';

  v_manifest:=jsonb_build_object(
    'schema_version','LF_CAPABILITY_MANIFEST_V1',
    'capability_code','CONSUMER_ADMISSION',
    'version','1.0.0',
    'owner','SUPER_ADMIN',
    'contract',jsonb_build_object(
      'input','applicability + requiredness + capability/version + CURRENTNESS_AUTHORITY receipt + receiver_status',
      'output','PASS|HOLD|BLOCK|NOT_REQUIRED|UNKNOWN',
      'aggregate','truthful REQUIRED-aware aggregate with policy-proven optional veto only',
      'history_is_authority',false,
      'same_value_proves_compatibility',false
    ),
    'delivery',jsonb_build_object(
      'mode','SUPABASE_NATIVE_READ_ONLY_CLASSIFIER',
      'evaluate_function','public.lf_consumer_admission_evaluate_v1',
      'aggregate_function','public.lf_consumer_admission_aggregate_v1'
    ),
    'installation',jsonb_build_object(
      'required',false,
      'reinstall_required',false,
      'package_update_mode','DATABASE_NATIVE_CUTOVER'
    ),
    'dependencies',jsonb_build_object(
      'CURRENTNESS_AUTHORITY',jsonb_build_object(
        'version',v_cur_version,'manifest_sha256',v_cur_sha),
      'CAPABILITY_VERSION_COMPATIBILITY',jsonb_build_object(
        'version',v_compat_version,'manifest_sha256',v_compat_sha),
      'ASSET_RETIREMENT_GOVERNANCE',jsonb_build_object(
        'version',v_retire_version,'manifest_sha256',v_retire_sha)
    ),
    'compatibility',jsonb_build_object(
      'domain_agnostic',true,
      'ig_owner',false,
      'ig_role','CONSUMER',
      'duplicates_currentness_authority',false,
      'duplicates_version_compatibility',false,
      'local_semantic_fallback',false,
      'production_activation',false,
      'runtime_mutation',false
    ),
    'migration',jsonb_build_object(
      'work_code','PAULO-190',
      'unit_code','T-CONS-ADM',
      'plan_code','IG_CURATOR_VALIDATOR_REFACTOR_V2',
      'mode','CAPABILITY_REGISTRY_CURRENTNESS_PLUS_READ_ONLY_CLASSIFIER'
    ),
    'rollback',jsonb_build_object(
      'supported',true,
      'mode','TRANSACTIONAL_SOURCE_ROLLBACK',
      'rule','remove only CONSUMER_ADMISSION v1/current/registry/functions/binding proof; never mutate N-13, N-15 or dependency capabilities'
    ),
    'usage',jsonb_build_object(
      'docs','sandbox/lf_contract_gate_test/transversal_assets/consumer_admission/README.md',
      'entrypoint','public.fn_lf_capability_bind_from_orchestrator_v1',
      'evaluate','public.lf_consumer_admission_evaluate_v1',
      'aggregate','public.lf_consumer_admission_aggregate_v1',
      'drain_retirement_hook','ASSET_RETIREMENT_GOVERNANCE'
    ),
    'currentness',jsonb_build_object(
      'dependency_binding','EXACT_VERSION_AND_MANIFEST_SHA256',
      'authority_receipt_schema','LF_CURRENTNESS_AUTHORITY_RECEIPT_V1',
      'history_authorization_forbidden',true
    ),
    'prior_art',jsonb_build_array('N-13','N-15','T-CONSUMERS'),
    'states',jsonb_build_array('PASS','HOLD','BLOCK','NOT_REQUIRED','UNKNOWN')
  );
  v_manifest_sha:=encode(extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),'hex');

  INSERT INTO public.lf_capability_registry(
    capability_code,capability_name,capability_kind,owner_scope,status,description,
    created_by_execution_id,updated_by_execution_id,entry_guard_required,entry_guard_code
  ) VALUES (
    'CONSUMER_ADMISSION','Consumer Admission','TRANSVERSAL','SUPER_ADMIN','ACTIVE',
    'Domain-agnostic REQUIRED-aware admission composed on existing currentness/version authorities.',
    v_execution_id,v_execution_id,true,'ORCHESTRATOR_EXECUTION_GUARD_V1'
  )
  ON CONFLICT(capability_code) DO UPDATE SET
    capability_name=excluded.capability_name,
    capability_kind=excluded.capability_kind,
    owner_scope=excluded.owner_scope,
    status=excluded.status,
    description=excluded.description,
    updated_at=clock_timestamp(),
    updated_by_execution_id=excluded.updated_by_execution_id,
    entry_guard_required=excluded.entry_guard_required,
    entry_guard_code=excluded.entry_guard_code;

  SELECT manifest_sha256 INTO v_existing_sha
  FROM public.lf_capability_version_registry
  WHERE capability_code='CONSUMER_ADMISSION' AND version='1.0.0';

  IF v_existing_sha IS NOT NULL AND v_existing_sha<>v_manifest_sha THEN
    RAISE EXCEPTION 'BLOCK_T_CONS_ADM_CAPABILITY_VERSION_MANIFEST_CONFLICT';
  END IF;

  INSERT INTO public.lf_capability_version_registry(
    capability_code,version,version_major,version_minor,version_patch,release_state,supersedes_version,
    manifest,manifest_sha256,source_ref,docs_ref,validator_ref,created_by_execution_id
  ) VALUES (
    'CONSUMER_ADMISSION','1.0.0',1,0,0,'RELEASED',NULL,
    v_manifest,v_manifest_sha,
    'supabase://public/lf_consumer_admission_evaluate_v1',
    'github://cristhianlujan/claude-persona-lf-patch/sandbox/lf_contract_gate_test/transversal_assets/consumer_admission/README.md',
    'supabase://public/lf_consumer_admission_aggregate_v1',
    v_execution_id
  ) ON CONFLICT(capability_code,version) DO NOTHING;

  v_promote:=public.fn_lf_capability_promote_v1(
    'CONSUMER_ADMISSION','1.0.0',NULL,v_execution_id,
    'T-CONS-ADM materializes reusable truthful consumer admission without runtime effects.'
  );
  IF coalesce((v_promote->>'ready')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'BLOCK_T_CONS_ADM_CAPABILITY_CURRENT_POINTER:%',v_promote::text;
  END IF;

  IF NOT EXISTS(
    SELECT 1
    FROM public.lf_capability_registry r
    JOIN public.lf_capability_current c USING(capability_code)
    WHERE r.capability_code='CONSUMER_ADMISSION'
      AND r.status='ACTIVE'
      AND r.owner_scope='SUPER_ADMIN'
      AND r.entry_guard_required=true
      AND r.entry_guard_code='ORCHESTRATOR_EXECUTION_GUARD_V1'
      AND c.version='1.0.0'
      AND c.manifest_sha256=v_manifest_sha
  ) THEN
    RAISE EXCEPTION 'BLOCK_T_CONS_ADM_CAPABILITY_READBACK_FAILED';
  END IF;
END
$register$;

DO $tests$
DECLARE
  v_cur_version text;
  v_cur_sha text;
  v_compat_version text;
  v_compat_sha text;
  v_receipt jsonb;
  v_ig_pass jsonb;
  v_non_ig_pass jsonb;
  v_stale jsonb;
  v_hold jsonb;
  v_unknown jsonb;
  v_agg jsonb;
BEGIN
  SELECT version,manifest_sha256 INTO v_cur_version,v_cur_sha
  FROM public.lf_capability_current WHERE capability_code='CURRENTNESS_AUTHORITY';
  SELECT version,manifest_sha256 INTO v_compat_version,v_compat_sha
  FROM public.lf_capability_current WHERE capability_code='CAPABILITY_VERSION_COMPATIBILITY';

  v_receipt:=jsonb_build_object(
    'schema_version','LF_CURRENTNESS_AUTHORITY_RECEIPT_V1',
    'authority_layer','CURRENTNESS_AUTHORITY',
    'decision','CURRENT',
    'ready',true,
    'receipt_sha256',repeat('a',64)
  );

  -- IG is a consumer only.
  v_ig_pass:=public.lf_consumer_admission_evaluate_v1(jsonb_build_object(
    'consumer_ref','EDGE_FN_INPUT_GOVERNANCE_AGENT_V1',
    'applicability','APPLICABLE',
    'requiredness','REQUIRED',
    'capability',jsonb_build_object(
      'code','CAPABILITY_VERSION_COMPATIBILITY',
      'version',v_compat_version,
      'manifest_sha256',v_compat_sha
    ),
    'currentness',v_receipt,
    'receiver_status',jsonb_build_object(
      'state','PASS','receipt_ref','execution://T-CONS-ADM/IG/receiver-readback'
    )
  ));
  IF v_ig_pass->>'state'<>'PASS' THEN
    RAISE EXCEPTION 'BLOCK_T_CONS_ADM_IG_CONSUMER_POSITIVE:%',v_ig_pass::text;
  END IF;

  -- Second consumer outside IG: same exact contract, no domain branch.
  v_non_ig_pass:=public.lf_consumer_admission_evaluate_v1(jsonb_build_object(
    'consumer_ref','GITHUB_CONTRACT_GATE_LF',
    'applicability','APPLICABLE',
    'requiredness','REQUIRED',
    'capability',jsonb_build_object(
      'code','CURRENTNESS_AUTHORITY',
      'version',v_cur_version,
      'manifest_sha256',v_cur_sha
    ),
    'currentness',v_receipt,
    'receiver_status',jsonb_build_object(
      'state','PASS','receipt_ref','execution://T-CONS-ADM/NON-IG/receiver-readback'
    )
  ));
  IF v_non_ig_pass->>'state'<>'PASS' THEN
    RAISE EXCEPTION 'BLOCK_T_CONS_ADM_SECOND_CONSUMER_POSITIVE:%',v_non_ig_pass::text;
  END IF;

  -- Negative 1: same receiver value/receipt but stale capability version can never PASS.
  v_stale:=public.lf_consumer_admission_evaluate_v1(jsonb_build_object(
    'consumer_ref','EDGE_FN_INPUT_GOVERNANCE_AGENT_V1',
    'applicability','APPLICABLE',
    'requiredness','REQUIRED',
    'capability',jsonb_build_object(
      'code','CURRENTNESS_AUTHORITY',
      'version','0.0.0',
      'manifest_sha256',repeat('b',64)
    ),
    'currentness',v_receipt,
    'receiver_status',jsonb_build_object(
      'state','PASS','receipt_ref','execution://T-CONS-ADM/NEG/same-value'
    )
  ));
  IF v_stale->>'state'='PASS' THEN
    RAISE EXCEPTION 'BLOCK_T_CONS_ADM_FALSE_GREEN_STALE_VERSION';
  END IF;

  -- Negative 2: one REQUIRED HOLD prevents aggregate PASS even when another REQUIRED passes.
  v_hold:=public.lf_consumer_admission_evaluate_v1(jsonb_build_object(
    'consumer_ref','GITHUB_CONTRACT_GATE_LF',
    'applicability','APPLICABLE',
    'requiredness','REQUIRED',
    'capability',jsonb_build_object(
      'code','CURRENTNESS_AUTHORITY',
      'version',v_cur_version,
      'manifest_sha256',v_cur_sha
    ),
    'currentness',v_receipt,
    'receiver_status',jsonb_build_object(
      'state','HOLD','receipt_ref','execution://T-CONS-ADM/HOLD/receiver'
    )
  ));
  v_agg:=public.lf_consumer_admission_aggregate_v1(jsonb_build_array(v_ig_pass,v_hold),'{}'::jsonb);
  IF v_agg->>'state'='PASS' OR v_agg->>'state'<>'HOLD' THEN
    RAISE EXCEPTION 'BLOCK_T_CONS_ADM_TRUTHFUL_AGGREGATE_HOLD:%',v_agg::text;
  END IF;

  -- OPTIONAL HOLD does not veto without governed policy proof.
  v_hold:=v_hold || jsonb_build_object('requiredness','OPTIONAL');
  v_agg:=public.lf_consumer_admission_aggregate_v1(jsonb_build_array(v_ig_pass,v_hold),'{}'::jsonb);
  IF v_agg->>'state'<>'PASS' THEN
    RAISE EXCEPTION 'BLOCK_T_CONS_ADM_OPTIONAL_OVERBLOCK:%',v_agg::text;
  END IF;

  -- Negative 3: REQUIRED UNKNOWN is fail-closed by default policy.
  v_unknown:=public.lf_consumer_admission_evaluate_v1(jsonb_build_object(
    'consumer_ref','EDGE_FN_INPUT_GOVERNANCE_AGENT_V1',
    'applicability','APPLICABLE',
    'requiredness','REQUIRED',
    'capability',jsonb_build_object(
      'code','CURRENTNESS_AUTHORITY',
      'version',v_cur_version,
      'manifest_sha256',v_cur_sha
    ),
    'currentness',jsonb_build_object(
      'schema_version','LF_CURRENTNESS_AUTHORITY_RECEIPT_V1',
      'authority_layer','CURRENTNESS_AUTHORITY',
      'decision','UNKNOWN_FAIL_CLOSED',
      'ready',false
    ),
    'receiver_status',jsonb_build_object(
      'state','PASS','receipt_ref','execution://T-CONS-ADM/UNKNOWN/receiver'
    )
  ));
  IF v_unknown->>'state'<>'UNKNOWN' THEN
    RAISE EXCEPTION 'BLOCK_T_CONS_ADM_UNKNOWN_NOT_PRESERVED:%',v_unknown::text;
  END IF;
  v_agg:=public.lf_consumer_admission_aggregate_v1(jsonb_build_array(v_unknown),'{}'::jsonb);
  IF v_agg->>'state'<>'BLOCK' OR v_agg->>'code'<>'REQUIRED_UNKNOWN_FAIL_CLOSED' THEN
    RAISE EXCEPTION 'BLOCK_T_CONS_ADM_UNKNOWN_NOT_FAIL_CLOSED:%',v_agg::text;
  END IF;
END
$tests$;

DO $binding$
DECLARE
  v_orch_id constant text := 'T-CONS-ADM-ORCH-20261004-V1';
  v_consumer_id constant text := 'T-CONS-ADM-IG-BIND-20261004-V1';
  v_plan_digest constant text := '797751eed3c02073c80e6e3b2ac3b6823fb0e7c46d5a5e662f100edb985b609c';
  v_orch_request_sha constant text := 'e085a85bc0e7e3bcb4af5de201c98230b2748b030b7a21cbea0976808b383b60';
  v_consumer_request_sha constant text := '057b1ba7896c21bc1026629193a577db5f53538930978a2f5c29bc3e12ccb53a';
  v_manifest_sha text;
  v_version text;
  v_orch jsonb;
  v_consumer jsonb;
  v_receipt jsonb;
  v_receipt_id uuid;
  v_bind jsonb;
BEGIN
  SELECT version,manifest_sha256 INTO v_version,v_manifest_sha
  FROM public.lf_capability_current
  WHERE capability_code='CONSUMER_ADMISSION';

  IF NOT FOUND OR v_version<>'1.0.0' OR v_manifest_sha !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'BLOCK_T_CONS_ADM_BIND_CAPABILITY_NOT_CURRENT';
  END IF;

  v_orch:=public.fn_lf_operation_reserve_execution_v1(
    v_orch_id,'ORQUESTACION_PIPELINE_LF',
    'ENGINEERING_PLAN_UNIT_BINDING_PROOF','IG_CURATOR_VALIDATOR_REFACTOR_V2:T-CONS-ADM',
    't-cons-adm-orch-20261004-v1',v_orch_request_sha,v_orch_id,
    NULL,NULL,
    jsonb_build_object(
      'purpose','T_CONS_ADM_IG_BINDING_PROOF',
      'consumer_unit','T-CONS-ADM',
      'capability_code','CONSUMER_ADMISSION',
      'effects_executed',false
    )
  );
  IF coalesce(v_orch->>'result','') NOT IN ('RESERVED_NEW_EXECUTION','REPLAY_EXISTING_EXECUTION') THEN
    RAISE EXCEPTION 'BLOCK_T_CONS_ADM_BIND_ORCH_RESERVE:%',v_orch::text;
  END IF;

  v_consumer:=public.fn_lf_operation_reserve_execution_v1(
    v_consumer_id,'GITHUB_CONTRACT_GATE_LF',
    'ENGINEERING_PLAN_UNIT_BINDING_PROOF','IG_CURATOR_VALIDATOR_REFACTOR_V2:T-CONS-ADM',
    't-cons-adm-ig-bind-20261004-v1',v_consumer_request_sha,v_orch_id,
    NULL,NULL,
    jsonb_build_object(
      'orchestrator_execution_id',v_orch_id,
      'plan_digest',v_plan_digest,
      'capability_code','CONSUMER_ADMISSION',
      'consumer_plan','IG_CURATOR_VALIDATOR_REFACTOR_V2',
      'consumer_unit','T-CONS-ADM',
      'consumer_asset','EDGE_FN_INPUT_GOVERNANCE_AGENT_V1',
      'mode','BINDING_PROOF_ONLY',
      'effects_executed',false
    )
  );
  IF coalesce(v_consumer->>'result','') NOT IN ('RESERVED_NEW_EXECUTION','REPLAY_EXISTING_EXECUTION') THEN
    RAISE EXCEPTION 'BLOCK_T_CONS_ADM_BIND_CONSUMER_RESERVE:%',v_consumer::text;
  END IF;

  IF NOT EXISTS(
    SELECT 1 FROM public.lf_operation_execution
    WHERE execution_id=v_orch_id AND status='IN_PROGRESS'
  ) OR NOT EXISTS(
    SELECT 1 FROM public.lf_operation_execution
    WHERE execution_id=v_consumer_id AND status='IN_PROGRESS'
  ) THEN
    RAISE EXCEPTION 'BLOCK_T_CONS_ADM_BIND_EXECUTION_NOT_ACTIVE';
  END IF;

  v_receipt:=public.fn_lf_orchestrator_dispatch_receipt_v1(
    v_orch_id,v_consumer_id,'CONSUMER_ADMISSION',v_plan_digest,
    jsonb_build_object(
      'consumer_plan','IG_CURATOR_VALIDATOR_REFACTOR_V2',
      'consumer_unit','T-CONS-ADM',
      'consumer_asset','EDGE_FN_INPUT_GOVERNANCE_AGENT_V1',
      'purpose','BINDING_PROOF_ONLY',
      'effects_executed',false
    ),
    v_orch_id
  );
  IF coalesce((v_receipt->>'ready')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'BLOCK_T_CONS_ADM_BIND_DISPATCH:%',v_receipt::text;
  END IF;
  v_receipt_id:=(v_receipt->>'receipt_id')::uuid;

  v_bind:=public.fn_lf_capability_bind_from_orchestrator_v1(
    v_consumer_id,'CONSUMER_ADMISSION',v_manifest_sha,v_plan_digest,v_receipt_id,v_consumer_id
  );
  IF coalesce((v_bind->>'ready')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'BLOCK_T_CONS_ADM_BIND_GUARDED_BIND:%',v_bind::text;
  END IF;

  IF NOT EXISTS(
    SELECT 1
    FROM public.lf_capability_binding b
    JOIN public.lf_capability_current c USING(capability_code)
    WHERE b.execution_id=v_consumer_id
      AND b.capability_code='CONSUMER_ADMISSION'
      AND b.binding_state='BOUND'
      AND b.bound_version=c.version
      AND b.bound_manifest_sha256=c.manifest_sha256
      AND c.version=v_version
      AND c.manifest_sha256=v_manifest_sha
  ) THEN
    RAISE EXCEPTION 'BLOCK_T_CONS_ADM_BIND_EXACT_READBACK_FAILED';
  END IF;

  UPDATE public.lf_operation_execution
  SET status='COMPLETED',
      completed_at=coalesce(completed_at,clock_timestamp()),
      checkpoint_payload=jsonb_build_object(
        'schema_version','LF_T_CONS_ADM_IG_BINDING_PROOF_V1',
        'capability_code','CONSUMER_ADMISSION',
        'consumer_plan','IG_CURATOR_VALIDATOR_REFACTOR_V2',
        'consumer_unit','T-CONS-ADM',
        'consumer_asset','EDGE_FN_INPUT_GOVERNANCE_AGENT_V1',
        'bound_version',v_version,
        'bound_manifest_sha256',v_manifest_sha,
        'dispatch_receipt_id',v_receipt_id,
        'guard_code','ORCHESTRATOR_EXECUTION_GUARD_V1',
        'effects_executed',false
      ),
      updated_by_execution_id=v_consumer_id,
      updated_at=clock_timestamp()
  WHERE execution_id=v_consumer_id;

  UPDATE public.lf_operation_execution
  SET status='COMPLETED',
      completed_at=coalesce(completed_at,clock_timestamp()),
      checkpoint_payload=jsonb_build_object(
        'schema_version','LF_T_CONS_ADM_ORCHESTRATION_PROOF_V1',
        'consumer_execution_id',v_consumer_id,
        'capability_code','CONSUMER_ADMISSION',
        'dispatch_receipt_id',v_receipt_id,
        'effects_executed',false
      ),
      updated_by_execution_id=v_orch_id,
      updated_at=clock_timestamp()
  WHERE execution_id=v_orch_id;
END
$binding$;
