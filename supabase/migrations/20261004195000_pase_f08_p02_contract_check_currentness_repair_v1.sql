-- LF_PASE_POST_PASE_GLOBAL_ARCHITECTURE_V1 / PASE-ATOM-F08-P02
-- Reconciles LF_CONTRACT_CHECK current authority with the already-retired legacy bridge.
-- Functional Contract Check source is unchanged. No runtime/deploy/production activation.
DO $f08$
DECLARE
  v_exec constant text := 'CHATGPT-PASE-F08-P02-CONTRACT-CHECK-CURRENTNESS-REPAIR-20261004';
  v_old_manifest jsonb;
  v_manifest jsonb;
  v_manifest_sha text;
  v_existing_sha text;
  v_promote jsonb;
BEGIN
  SELECT manifest
    INTO v_old_manifest
  FROM public.lf_capability_version_registry
  WHERE capability_code='LF_CONTRACT_CHECK'
    AND version='1.4.0'
    AND release_state='RELEASED'
    AND manifest_sha256='664214317fbc089b70e66f82cabcf1862e26b1e2e0156a573d4be705934b4d07';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'BLOCK_F08_P02_CONTRACT_CHECK_V140_AUTHORITY_DRIFT';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_capability_current
    WHERE capability_code='LF_CONTRACT_CHECK'
      AND version='1.4.0'
      AND manifest_sha256='664214317fbc089b70e66f82cabcf1862e26b1e2e0156a573d4be705934b4d07'
  ) THEN
    RAISE EXCEPTION 'BLOCK_F08_P02_CONTRACT_CHECK_CURRENT_DRIFT';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_activos
    WHERE codigo_activo='GITHUB_CONTRACT_GATE_LF'
      AND archived_at IS NULL
      AND metadata#>>'{contract_check_bridge_transition,status}'='RETIRED'
      AND coalesce((metadata#>>'{contract_check_bridge_transition,cleanup_required}')::boolean,true)=false
      AND coalesce((metadata#>>'{contract_check_bridge_transition,retired_implementation_executable}')::boolean,true)=false
      AND metadata#>>'{contract_check_bridge_transition,canonical_entrypoint}'='sandbox/lf_contract_gate_test/contract_check_carrier/contract_check_carrier_v1.py'
      AND metadata->>'canonical_contract_check_capability'='LF_CONTRACT_CHECK'
  ) THEN
    RAISE EXCEPTION 'BLOCK_F08_P02_BRIDGE_RETIREMENT_AUTHORITY_MISSING';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_activos
    WHERE codigo_activo='LF_CONTRACT_CHECK'
      AND archived_at IS NULL
      AND version='1.4.0'
      AND estado_operativo='READ_ONLY'
      AND runtime_estado='NO_HABILITADO'
      AND impacto_automatico='BLOQUEADO'
      AND coalesce((metadata#>>'{entry_contract,required}')::boolean,false)=true
      AND metadata#>>'{entry_contract,guard_code}'='ORCHESTRATOR_EXECUTION_GUARD_V1'
  ) THEN
    RAISE EXCEPTION 'BLOCK_F08_P02_CONTRACT_CHECK_ASSET_PREIMAGE_DRIFT';
  END IF;

  v_manifest := jsonb_set(v_old_manifest,'{version}',to_jsonb('1.4.1'::text),true);
  v_manifest := jsonb_set(v_manifest,'{usage}',coalesce(v_manifest->'usage','{}'::jsonb)-'bridge',true);
  v_manifest := jsonb_set(v_manifest,'{delivery}',coalesce(v_manifest->'delivery','{}'::jsonb)-'legacy_bridge',true);
  v_manifest := jsonb_set(
    v_manifest,'{compatibility}',
    jsonb_build_object(
      'legacy_implementation','LF_CONTRACT_CHECK_V0_21',
      'bridge_transition','RETIRED',
      'bridge_cleanup_required',false,
      'legacy_bridge_preserved',false,
      'new_consumers_allowed_on_bridge',false,
      'legacy_implementation_executable',false,
      'retirement_authority_asset','GITHUB_CONTRACT_GATE_LF',
      'retirement_evidence_event_id',19426
    ),true
  );
  v_manifest := jsonb_set(v_manifest,'{migration,bridge_cleanup_state}',to_jsonb('COMPLETE_RETIRED_SOURCE_ABSENT'::text),true);
  v_manifest := jsonb_set(v_manifest,'{currentness,authority_metadata_reconciled_from}',to_jsonb('GITHUB_CONTRACT_GATE_LF.contract_check_bridge_transition'::text),true);
  v_manifest := jsonb_set(v_manifest,'{currentness,functional_source_unchanged}', 'true'::jsonb,true);

  v_manifest_sha := encode(extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),'hex');

  SELECT manifest_sha256 INTO v_existing_sha
  FROM public.lf_capability_version_registry
  WHERE capability_code='LF_CONTRACT_CHECK' AND version='1.4.1';
  IF v_existing_sha IS NOT NULL AND v_existing_sha<>v_manifest_sha THEN
    RAISE EXCEPTION 'BLOCK_F08_P02_CONTRACT_CHECK_V141_CONFLICT';
  END IF;

  INSERT INTO public.lf_capability_version_registry(
    capability_code,version,version_major,version_minor,version_patch,release_state,supersedes_version,
    manifest,manifest_sha256,source_ref,docs_ref,validator_ref,created_by_execution_id
  )
  SELECT capability_code,'1.4.1',1,4,1,'RELEASED','1.4.0',
         v_manifest,v_manifest_sha,source_ref,docs_ref,validator_ref,v_exec
  FROM public.lf_capability_version_registry
  WHERE capability_code='LF_CONTRACT_CHECK' AND version='1.4.0'
  ON CONFLICT(capability_code,version) DO NOTHING;

  v_promote := public.fn_lf_capability_promote_v1(
    'LF_CONTRACT_CHECK','1.4.1',
    '664214317fbc089b70e66f82cabcf1862e26b1e2e0156a573d4be705934b4d07',
    v_exec,
    'F08-P02 authority-metadata reconciliation after legacy Contract Check bridge retirement; functional source and runtime state unchanged.'
  );
  IF coalesce((v_promote->>'ready')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'BLOCK_F08_P02_CONTRACT_CHECK_PROMOTION:%',v_promote::text;
  END IF;

  UPDATE public.lf_activos
     SET version='1.4.1',
         metadata=jsonb_set(
           coalesce(metadata,'{}'::jsonb),
           '{compatibility_bridge_projection}',
           jsonb_build_object(
             'status','RETIRED',
             'cleanup_required',false,
             'legacy_implementation_executable',false,
             'authority_asset','GITHUB_CONTRACT_GATE_LF',
             'authority_event_id',19426
           ),true),
         updated_at=now(),
         updated_by_execution_id=v_exec
   WHERE codigo_activo='LF_CONTRACT_CHECK'
     AND archived_at IS NULL
     AND version='1.4.0'
     AND estado_operativo='READ_ONLY'
     AND runtime_estado='NO_HABILITADO'
     AND impacto_automatico='BLOQUEADO';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'BLOCK_F08_P02_CONTRACT_CHECK_ASSET_UPDATE';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_capability_current c
    JOIN public.lf_capability_version_registry v USING(capability_code,version)
    JOIN public.lf_activos a ON a.codigo_activo=c.capability_code AND a.archived_at IS NULL
    WHERE c.capability_code='LF_CONTRACT_CHECK'
      AND c.version='1.4.1'
      AND c.manifest_sha256=v_manifest_sha
      AND v.manifest_sha256=v_manifest_sha
      AND NOT (v.manifest#>'{usage}' ? 'bridge')
      AND NOT (v.manifest#>'{delivery}' ? 'legacy_bridge')
      AND coalesce((v.manifest#>>'{compatibility,bridge_cleanup_required}')::boolean,true)=false
      AND coalesce((v.manifest#>>'{compatibility,legacy_bridge_preserved}')::boolean,true)=false
      AND coalesce((v.manifest#>>'{compatibility,legacy_implementation_executable}')::boolean,true)=false
      AND a.version='1.4.1'
      AND a.estado_operativo='READ_ONLY'
      AND a.runtime_estado='NO_HABILITADO'
      AND a.impacto_automatico='BLOQUEADO'
  ) THEN
    RAISE EXCEPTION 'BLOCK_F08_P02_CONTRACT_CHECK_POSTCHECK';
  END IF;
END
$f08$;
