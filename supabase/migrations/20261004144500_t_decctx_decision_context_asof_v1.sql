-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / T-DECCTX / PAULO-187
-- DECISION_CONTEXT_ASOF transversal capability v1.
-- Owner: SUPER_ADMIN. IG is a consumer only.
-- Historical context stores references, versions and digests only; latest mutable state is never historical authority.
-- Reuse: CURRENTNESS_AUTHORITY + CAPABILITY_VERSION_COMPATIBILITY + TYPED_EVIDENCE_REGISTRY.

DO $pre$
DECLARE
  v_count integer;
BEGIN
  SELECT count(*) INTO v_count
  FROM public.lf_capability_registry r
  JOIN public.lf_capability_current c USING(capability_code)
  WHERE r.capability_code IN ('CURRENTNESS_AUTHORITY','CAPABILITY_VERSION_COMPATIBILITY','TYPED_EVIDENCE_REGISTRY')
    AND r.status='ACTIVE'
    AND c.version IS NOT NULL
    AND c.manifest_sha256 ~ '^[0-9a-f]{64}$';
  IF v_count <> 3 THEN
    RAISE EXCEPTION 'BLOCK_T_DECCTX_REQUIRED_CAPABILITY_NOT_CURRENT:%',v_count;
  END IF;

  IF to_regprocedure('private.fn_lf_typed_evidence_payload_valid_v3(text,jsonb)') IS NULL THEN
    RAISE EXCEPTION 'BLOCK_T_DECCTX_TYPED_EVIDENCE_VALIDATOR_MISSING';
  END IF;

  IF EXISTS (SELECT 1 FROM public.lf_capability_registry WHERE capability_code='DECISION_CONTEXT_ASOF') THEN
    RAISE EXCEPTION 'BLOCK_T_DECCTX_CAPABILITY_PREEXISTING';
  END IF;
END
$pre$;

CREATE TABLE private.lf_decision_context_asof_v1 (
  context_id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
  decision_ref text NOT NULL UNIQUE,
  consumer_code text NOT NULL,
  subject_ref text NOT NULL,
  subject_version text NOT NULL,
  decided_at timestamptz NOT NULL,
  effective_at timestamptz NOT NULL,
  context_payload jsonb NOT NULL,
  context_sha256 text NOT NULL UNIQUE CHECK (context_sha256 ~ '^[0-9a-f]{64}$'),
  created_by_execution_id text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX lf_decision_context_asof_subject_idx
  ON private.lf_decision_context_asof_v1(consumer_code,subject_ref,decided_at DESC,created_at DESC);

CREATE TRIGGER trg_00_guard_lf_decision_context_asof_v1
BEFORE INSERT OR UPDATE OR DELETE ON private.lf_decision_context_asof_v1
FOR EACH ROW EXECUTE FUNCTION private.fn_guard_governed_relation_v3('APPEND_ONLY');
ALTER TABLE private.lf_decision_context_asof_v1
  ENABLE ALWAYS TRIGGER trg_00_guard_lf_decision_context_asof_v1;

DO $schema$
DECLARE
  v_required text[] := ARRAY[
    'evidence_schema_version','decision_ref','consumer_code','subject','actor_authority',
    'governing','times','authority_refs','extensions'
  ];
  v_preimage jsonb;
  v_sha text;
BEGIN
  v_preimage := jsonb_build_object(
    'schema_version','decision-context-asof/v1',
    'validator_version','v3.1',
    'required_keys',to_jsonb(v_required),
    'description','Immutable decision context using authority references, versions and digests; no mutable authority copies.'
  );
  v_sha := encode(extensions.digest(convert_to(v_preimage::text,'UTF8'),'sha256'),'hex');

  INSERT INTO private.lf_typed_evidence_schema_registry_v3(
    schema_version,validator_version,required_keys,description,active,registry_sha256,
    registered_by_execution_id,registered_at
  ) VALUES (
    'decision-context-asof/v1','v3.1',v_required,
    'Immutable decision context using authority references, versions and digests; extensible consumer metadata is non-authoritative.',
    true,v_sha,'CHATGPT-IG-CV-T-DECCTX-20261004',now()
  );
END
$schema$;

CREATE OR REPLACE FUNCTION private.fn_lf_decision_context_asof_payload_valid_v1(p_context jsonb)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, public, private, extensions
AS $fn$
DECLARE
  v_item jsonb;
  v_decided timestamptz;
  v_effective timestamptz;
  v_code text;
  v_count integer;
BEGIN
  IF p_context IS NULL OR jsonb_typeof(p_context)<>'object' THEN RETURN false; END IF;
  IF p_context->>'evidence_schema_version' IS DISTINCT FROM 'decision-context-asof/v1' THEN RETURN false; END IF;
  IF private.fn_lf_typed_evidence_payload_valid_v3('decision-context-asof/v1',p_context) IS NOT TRUE THEN RETURN false; END IF;

  IF nullif(btrim(coalesce(p_context->>'decision_ref','')),'') IS NULL
     OR nullif(btrim(coalesce(p_context->>'consumer_code','')),'') IS NULL THEN RETURN false; END IF;

  IF jsonb_typeof(p_context->'subject')<>'object'
     OR nullif(btrim(coalesce(p_context#>>'{subject,ref}','')),'') IS NULL
     OR nullif(btrim(coalesce(p_context#>>'{subject,version}','')),'') IS NULL THEN RETURN false; END IF;

  IF jsonb_typeof(p_context->'actor_authority')<>'object'
     OR nullif(btrim(coalesce(p_context#>>'{actor_authority,actor_ref}','')),'') IS NULL
     OR nullif(btrim(coalesce(p_context#>>'{actor_authority,authority_ref}','')),'') IS NULL
     OR nullif(btrim(coalesce(p_context#>>'{actor_authority,authority_version}','')),'') IS NULL
     OR coalesce(p_context#>>'{actor_authority,authority_sha256}','') !~ '^[0-9a-f]{64}$' THEN RETURN false; END IF;

  IF jsonb_typeof(p_context->'governing')<>'object'
     OR nullif(btrim(coalesce(p_context#>>'{governing,policy_ref}','')),'') IS NULL
     OR nullif(btrim(coalesce(p_context#>>'{governing,policy_version}','')),'') IS NULL
     OR coalesce(p_context#>>'{governing,policy_sha256}','') !~ '^[0-9a-f]{64}$'
     OR nullif(btrim(coalesce(p_context#>>'{governing,terms_ref}','')),'') IS NULL
     OR nullif(btrim(coalesce(p_context#>>'{governing,terms_version}','')),'') IS NULL
     OR coalesce(p_context#>>'{governing,terms_sha256}','') !~ '^[0-9a-f]{64}$' THEN RETURN false; END IF;

  -- Core authority branches are refs/digests only. Copies/snapshots are not accepted as historical authority.
  IF (p_context->'actor_authority') ?| ARRAY['payload','content','snapshot','document','body']
     OR (p_context->'governing') ?| ARRAY['policy_payload','terms_payload','payload','content','snapshot','document','body'] THEN RETURN false; END IF;

  IF jsonb_typeof(p_context->'times')<>'object' THEN RETURN false; END IF;
  BEGIN
    v_decided := (p_context#>>'{times,decided_at}')::timestamptz;
    v_effective := (p_context#>>'{times,effective_at}')::timestamptz;
  EXCEPTION WHEN OTHERS THEN
    RETURN false;
  END;
  IF v_decided IS NULL OR v_effective IS NULL THEN RETURN false; END IF;

  IF jsonb_typeof(p_context->'authority_refs')<>'array' OR jsonb_array_length(p_context->'authority_refs')<3 THEN RETURN false; END IF;
  FOR v_item IN SELECT value FROM jsonb_array_elements(p_context->'authority_refs') LOOP
    IF jsonb_typeof(v_item)<>'object'
       OR nullif(btrim(coalesce(v_item->>'capability_code','')),'') IS NULL
       OR nullif(btrim(coalesce(v_item->>'version','')),'') IS NULL
       OR coalesce(v_item->>'manifest_sha256','') !~ '^[0-9a-f]{64}$'
       OR nullif(btrim(coalesce(v_item->>'authority_ref','')),'') IS NULL THEN RETURN false; END IF;
  END LOOP;

  FOREACH v_code IN ARRAY ARRAY['CURRENTNESS_AUTHORITY','CAPABILITY_VERSION_COMPATIBILITY','TYPED_EVIDENCE_REGISTRY'] LOOP
    SELECT count(*) INTO v_count
    FROM jsonb_array_elements(p_context->'authority_refs') e
    WHERE e->>'capability_code'=v_code;
    IF v_count<>1 THEN RETURN false; END IF;
  END LOOP;

  IF jsonb_typeof(p_context->'extensions')<>'object' THEN RETURN false; END IF;
  RETURN true;
END
$fn$;

CREATE OR REPLACE FUNCTION public.fn_lf_decision_context_asof_record_v1(
  p_context jsonb,
  p_actor_execution_id text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, extensions
AS $fn$
DECLARE
  v_manifest jsonb;
  v_code text;
  v_expected_version text;
  v_expected_sha text;
  v_live_version text;
  v_live_sha text;
  v_ref_version text;
  v_ref_sha text;
  v_count integer;
  v_digest text;
  v_existing private.lf_decision_context_asof_v1%rowtype;
  v_row private.lf_decision_context_asof_v1%rowtype;
BEGIN
  IF nullif(btrim(coalesce(p_actor_execution_id,'')),'') IS NULL THEN
    RETURN jsonb_build_object('schema_version','LF_DECISION_CONTEXT_ASOF_RECEIPT_V1','state','BLOCKED','code','ACTOR_EXECUTION_ID_MISSING');
  END IF;

  SELECT vr.manifest INTO v_manifest
  FROM public.lf_capability_current c
  JOIN public.lf_capability_version_registry vr
    ON vr.capability_code=c.capability_code AND vr.version=c.version AND vr.manifest_sha256=c.manifest_sha256
  WHERE c.capability_code='DECISION_CONTEXT_ASOF';
  IF NOT FOUND THEN
    RETURN jsonb_build_object('schema_version','LF_DECISION_CONTEXT_ASOF_RECEIPT_V1','state','BLOCKED','code','CAPABILITY_NOT_CURRENT');
  END IF;

  IF private.fn_lf_decision_context_asof_payload_valid_v1(p_context) IS NOT TRUE THEN
    RETURN jsonb_build_object('schema_version','LF_DECISION_CONTEXT_ASOF_RECEIPT_V1','state','BLOCKED','code','CONTEXT_SCHEMA_INVALID');
  END IF;

  -- Reuse exact current dependency revisions; do not build a temporal/currentness authority here.
  FOREACH v_code IN ARRAY ARRAY['CURRENTNESS_AUTHORITY','CAPABILITY_VERSION_COMPATIBILITY','TYPED_EVIDENCE_REGISTRY'] LOOP
    v_expected_version := v_manifest#>>ARRAY['dependencies',v_code,'version'];
    v_expected_sha := v_manifest#>>ARRAY['dependencies',v_code,'manifest_sha256'];
    SELECT version,manifest_sha256 INTO v_live_version,v_live_sha
    FROM public.lf_capability_current WHERE capability_code=v_code;

    SELECT count(*),min(e->>'version'),min(e->>'manifest_sha256')
      INTO v_count,v_ref_version,v_ref_sha
    FROM jsonb_array_elements(p_context->'authority_refs') e
    WHERE e->>'capability_code'=v_code;

    IF v_count<>1
       OR v_live_version IS DISTINCT FROM v_expected_version
       OR v_live_sha IS DISTINCT FROM v_expected_sha
       OR v_ref_version IS DISTINCT FROM v_live_version
       OR v_ref_sha IS DISTINCT FROM v_live_sha THEN
      RETURN jsonb_build_object(
        'schema_version','LF_DECISION_CONTEXT_ASOF_RECEIPT_V1','state','BLOCKED','code','DEPENDENCY_CURRENTNESS_OR_REFERENCE_DRIFT',
        'dependency',v_code,'expected_version',v_expected_version,'live_version',v_live_version,
        'expected_manifest_sha256',v_expected_sha,'live_manifest_sha256',v_live_sha,
        'referenced_version',v_ref_version,'referenced_manifest_sha256',v_ref_sha
      );
    END IF;
  END LOOP;

  v_digest := encode(extensions.digest(convert_to(p_context::text,'UTF8'),'sha256'),'hex');

  SELECT * INTO v_existing
  FROM private.lf_decision_context_asof_v1
  WHERE decision_ref=p_context->>'decision_ref';
  IF FOUND THEN
    IF v_existing.context_sha256 IS DISTINCT FROM v_digest THEN
      RETURN jsonb_build_object(
        'schema_version','LF_DECISION_CONTEXT_ASOF_RECEIPT_V1','state','BLOCKED','code','DECISION_REF_REPLAY_CONFLICT',
        'decision_ref',p_context->>'decision_ref','existing_context_sha256',v_existing.context_sha256,'candidate_context_sha256',v_digest
      );
    END IF;
    RETURN jsonb_build_object(
      'schema_version','LF_DECISION_CONTEXT_ASOF_RECEIPT_V1','state','RECORDED','code','IDEMPOTENT_REPLAY',
      'context_id',v_existing.context_id,'decision_ref',v_existing.decision_ref,
      'consumer_code',v_existing.consumer_code,'subject_ref',v_existing.subject_ref,'subject_version',v_existing.subject_version,
      'context_sha256',v_existing.context_sha256,'decided_at',v_existing.decided_at,'effective_at',v_existing.effective_at
    );
  END IF;

  INSERT INTO private.lf_decision_context_asof_v1(
    decision_ref,consumer_code,subject_ref,subject_version,decided_at,effective_at,
    context_payload,context_sha256,created_by_execution_id
  ) VALUES (
    p_context->>'decision_ref',p_context->>'consumer_code',p_context#>>'{subject,ref}',p_context#>>'{subject,version}',
    (p_context#>>'{times,decided_at}')::timestamptz,(p_context#>>'{times,effective_at}')::timestamptz,
    p_context,v_digest,p_actor_execution_id
  ) RETURNING * INTO v_row;

  RETURN jsonb_build_object(
    'schema_version','LF_DECISION_CONTEXT_ASOF_RECEIPT_V1','state','RECORDED','code','NEW_CONTEXT',
    'context_id',v_row.context_id,'decision_ref',v_row.decision_ref,'consumer_code',v_row.consumer_code,
    'subject_ref',v_row.subject_ref,'subject_version',v_row.subject_version,'context_sha256',v_row.context_sha256,
    'decided_at',v_row.decided_at,'effective_at',v_row.effective_at
  );
END
$fn$;

CREATE OR REPLACE FUNCTION public.fn_lf_decision_context_asof_resolve_v1(
  p_consumer_code text,
  p_subject_ref text,
  p_as_of timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, private
AS $fn$
DECLARE
  v_row private.lf_decision_context_asof_v1%rowtype;
BEGIN
  IF nullif(btrim(coalesce(p_consumer_code,'')),'') IS NULL
     OR nullif(btrim(coalesce(p_subject_ref,'')),'') IS NULL
     OR p_as_of IS NULL THEN
    RETURN jsonb_build_object('schema_version','LF_DECISION_CONTEXT_ASOF_RESOLUTION_V1','state','UNKNOWN','code','INVALID_QUERY');
  END IF;

  SELECT * INTO v_row
  FROM private.lf_decision_context_asof_v1
  WHERE consumer_code=p_consumer_code
    AND subject_ref=p_subject_ref
    AND decided_at<=p_as_of
  ORDER BY decided_at DESC,created_at DESC,context_id DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'schema_version','LF_DECISION_CONTEXT_ASOF_RESOLUTION_V1','state','UNKNOWN','code','NO_CONTEXT_AT_ASOF',
      'consumer_code',p_consumer_code,'subject_ref',p_subject_ref,'as_of',p_as_of
    );
  END IF;

  RETURN jsonb_build_object(
    'schema_version','LF_DECISION_CONTEXT_ASOF_RESOLUTION_V1','state','RESOLVED','code','HISTORICAL_CONTEXT',
    'context_id',v_row.context_id,'decision_ref',v_row.decision_ref,'consumer_code',v_row.consumer_code,
    'subject_ref',v_row.subject_ref,'subject_version',v_row.subject_version,
    'decided_at',v_row.decided_at,'effective_at',v_row.effective_at,
    'context_sha256',v_row.context_sha256,'context',v_row.context_payload,
    'resolution_basis','IMMUTABLE_RECORDED_CONTEXT','latest_reinterpreted',false
  );
END
$fn$;

DO $cap$
DECLARE
  v_exec text := 'CHATGPT-IG-CV-T-DECCTX-20261004';
  v_curr_version text;
  v_curr_sha text;
  v_compat_version text;
  v_compat_sha text;
  v_typed_version text;
  v_typed_sha text;
  v_manifest jsonb;
  v_manifest_sha text;
BEGIN
  SELECT version,manifest_sha256 INTO v_curr_version,v_curr_sha
  FROM public.lf_capability_current WHERE capability_code='CURRENTNESS_AUTHORITY';
  SELECT version,manifest_sha256 INTO v_compat_version,v_compat_sha
  FROM public.lf_capability_current WHERE capability_code='CAPABILITY_VERSION_COMPATIBILITY';
  SELECT version,manifest_sha256 INTO v_typed_version,v_typed_sha
  FROM public.lf_capability_current WHERE capability_code='TYPED_EVIDENCE_REGISTRY';

  v_manifest := jsonb_build_object(
    'schema_version','LF_CAPABILITY_MANIFEST_V1',
    'capability_code','DECISION_CONTEXT_ASOF',
    'version','1.0.0',
    'contract',jsonb_build_object(
      'input','decision-context-asof/v1',
      'output','LF_DECISION_CONTEXT_ASOF_RECEIPT_V1 + LF_DECISION_CONTEXT_ASOF_RESOLUTION_V1',
      'subject_identity','subject.ref + subject.version',
      'authority_identity','actor_authority refs/version/digest',
      'governing_identity','policy/terms refs/version/digests',
      'temporal_semantics','RECORDED_AS_OF_NOT_LATEST_MUTABLE',
      'extensions','consumer-specific non-authoritative metadata only'
    ),
    'delivery',jsonb_build_object(
      'mode','SUPABASE_NATIVE_TRANSVERSAL_CAPABILITY',
      'record','public.fn_lf_decision_context_asof_record_v1',
      'resolve','public.fn_lf_decision_context_asof_resolve_v1',
      'store','private.lf_decision_context_asof_v1'
    ),
    'dependencies',jsonb_build_object(
      'CURRENTNESS_AUTHORITY',jsonb_build_object('version',v_curr_version,'manifest_sha256',v_curr_sha,'role','SOURCE_CURRENTNESS_AUTHORITY'),
      'CAPABILITY_VERSION_COMPATIBILITY',jsonb_build_object('version',v_compat_version,'manifest_sha256',v_compat_sha,'role','VERSION_PIN_AUTHORITY'),
      'TYPED_EVIDENCE_REGISTRY',jsonb_build_object('version',v_typed_version,'manifest_sha256',v_typed_sha,'role','SCHEMA_VALIDATION_AUTHORITY')
    ),
    'currentness',jsonb_build_object(
      'authority','CURRENTNESS_AUTHORITY',
      'latest_is_asof',false,
      'historical_receipt_immutable',true
    ),
    'compatibility',jsonb_build_object(
      'version_authority','CAPABILITY_VERSION_COMPATIBILITY',
      'unknown_state','FAIL_CLOSED_ON_RECORD_ONLY',
      'historical_resolve_survives_later_dependency_mutation',true,
      'duplicate_temporal_authority_forbidden',true
    ),
    'evidence',jsonb_build_object(
      'schema_registry','TYPED_EVIDENCE_REGISTRY',
      'schema_version','decision-context-asof/v1',
      'authority_copy_forbidden',true,
      'references_and_digests_only',true
    ),
    'consumers',jsonb_build_object(
      'generic',true,
      'ig_role','CONSUMER',
      'ig_binding','IG_CURATOR_VALIDATOR_REFACTOR_V2:N-16',
      'non_ig_supported',true
    ),
    'installation',jsonb_build_object('required',false,'reinstall_required',false,'package_update_mode','DATABASE_NATIVE_CUTOVER'),
    'rollback',jsonb_build_object('supported',true,'rule','REMOVE_CURRENT_POINTER_AND_NEW_ASOF_ASSETS_ONLY_IF_NO_CONSUMER_DATA_EXISTS')
  );
  v_manifest_sha := encode(extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),'hex');

  INSERT INTO public.lf_capability_registry(
    capability_code,capability_name,capability_kind,owner_scope,status,description,
    created_by_execution_id,updated_by_execution_id,entry_guard_required,entry_guard_code
  ) VALUES (
    'DECISION_CONTEXT_ASOF','Decision Context As-Of','TRANSVERSAL','SUPER_ADMIN','ACTIVE',
    'Versioned immutable decision context resolver. Stores authority references/digests and reconstructs historical context without latest reinterpretation.',
    v_exec,v_exec,false,'ORCHESTRATOR_EXECUTION_GUARD_V1'
  );

  INSERT INTO public.lf_capability_version_registry(
    capability_code,version,version_major,version_minor,version_patch,release_state,
    supersedes_version,manifest,manifest_sha256,source_ref,docs_ref,validator_ref,created_by_execution_id
  ) VALUES (
    'DECISION_CONTEXT_ASOF','1.0.0',1,0,0,'RELEASED',null,v_manifest,v_manifest_sha,
    'supabase/migrations/20261004144500_t_decctx_decision_context_asof_v1.sql',
    'sandbox/lf_contract_gate_test/transversal_assets/decision_context_asof/README.md',
    'sandbox/lf_contract_gate_test/transversal_assets/decision_context_asof/test_decision_context_asof_v1.sql',v_exec
  );

  INSERT INTO public.lf_capability_current(
    capability_code,version,manifest_sha256,previous_version,promoted_by_execution_id,promotion_reason
  ) VALUES (
    'DECISION_CONTEXT_ASOF','1.0.0',v_manifest_sha,null,v_exec,
    'T-DECCTX: generic immutable as-of decision context; IG consumer only; no parallel temporal authority'
  );
END
$cap$;

DO $post$
DECLARE
  v_owner text;
  v_version text;
  v_sha text;
  v_manifest jsonb;
BEGIN
  SELECT r.owner_scope,c.version,c.manifest_sha256,vr.manifest
    INTO v_owner,v_version,v_sha,v_manifest
  FROM public.lf_capability_registry r
  JOIN public.lf_capability_current c USING(capability_code)
  JOIN public.lf_capability_version_registry vr
    ON vr.capability_code=c.capability_code AND vr.version=c.version AND vr.manifest_sha256=c.manifest_sha256
  WHERE r.capability_code='DECISION_CONTEXT_ASOF' AND r.status='ACTIVE';

  IF v_owner IS DISTINCT FROM 'SUPER_ADMIN' OR v_version IS DISTINCT FROM '1.0.0' OR v_sha !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'T_DECCTX_CAPABILITY_CURRENT_POSTCONDITION_FAILED';
  END IF;
  IF v_manifest#>>'{consumers,ig_role}' IS DISTINCT FROM 'CONSUMER'
     OR coalesce((v_manifest#>>'{compatibility,duplicate_temporal_authority_forbidden}')::boolean,false) IS NOT TRUE
     OR coalesce((v_manifest#>>'{currentness,latest_is_asof}')::boolean,true) IS NOT FALSE THEN
    RAISE EXCEPTION 'T_DECCTX_GENERIC_CONTRACT_POSTCONDITION_FAILED';
  END IF;
  IF to_regprocedure('public.fn_lf_decision_context_asof_record_v1(jsonb,text)') IS NULL
     OR to_regprocedure('public.fn_lf_decision_context_asof_resolve_v1(text,text,timestamptz)') IS NULL THEN
    RAISE EXCEPTION 'T_DECCTX_FUNCTION_POSTCONDITION_FAILED';
  END IF;
END
$post$;
