-- T-TARGET-EVID / PAULO-186 — TARGETED_EVIDENCE_ACQUISITION v1.
-- Owner: SUPER_ADMIN. IG is consumer only.
-- R16 Git-first. Read-only planner: no evidence fetch, no repair, no approval, no runtime mutation.

DO $pre$
DECLARE
  v_typed record;
BEGIN
  SELECT r.status,c.version,c.manifest_sha256
    INTO v_typed
  FROM public.lf_capability_registry r
  JOIN public.lf_capability_current c USING(capability_code)
  WHERE r.capability_code='TYPED_EVIDENCE_REGISTRY';
  IF NOT FOUND OR v_typed.status<>'ACTIVE' OR v_typed.version IS NULL OR v_typed.manifest_sha256 !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'BLOCK_T_TARGET_EVID_TYPED_EVIDENCE_REGISTRY_NOT_CURRENT';
  END IF;
  IF to_regprocedure('private.fn_lf_typed_evidence_payload_valid_v3(text,jsonb)') IS NULL THEN
    RAISE EXCEPTION 'BLOCK_T_TARGET_EVID_TYPED_EVIDENCE_VALIDATOR_MISSING';
  END IF;
  IF to_regprocedure('public.fn_lf_capability_promote_v1(text,text,text,text,text)') IS NULL THEN
    RAISE EXCEPTION 'BLOCK_T_TARGET_EVID_CAPABILITY_PROMOTER_MISSING';
  END IF;
END
$pre$;

CREATE OR REPLACE FUNCTION public.lf_targeted_evidence_acquisition_plan_v1(p_request jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
STABLE
SET search_path = pg_catalog, public, private, extensions
AS $fn$
DECLARE
  v_self_manifest jsonb;
  v_expected_typed_version text;
  v_expected_typed_sha text;
  v_live_typed_version text;
  v_live_typed_sha text;
  v_consumer_ref text;
  v_reason jsonb;
  v_candidate jsonb;
  v_evidence jsonb;
  v_candidate_ref text;
  v_source_ref text;
  v_cost integer;
  v_available boolean;
  v_material boolean;
  v_coverage integer;
  v_best_cost integer;
  v_best_coverage integer := -1;
  v_best_ref text;
  v_best jsonb;
  v_reason_count integer := 0;
  v_evidence_count integer := 0;
  v_candidate_count integer := 0;
  v_distinct_candidate_count integer := 0;
BEGIN
  IF p_request IS NULL OR jsonb_typeof(p_request)<>'object' THEN
    RETURN jsonb_build_object('schema_version','LF_TARGETED_EVIDENCE_ACQUISITION_RESULT_V1','state','STOP','code','INVALID_REQUEST','automation_options_exhausted',false,'effects_executed',false);
  END IF;

  SELECT vr.manifest INTO v_self_manifest
  FROM public.lf_capability_current c
  JOIN public.lf_capability_version_registry vr
    ON vr.capability_code=c.capability_code AND vr.version=c.version AND vr.manifest_sha256=c.manifest_sha256
  WHERE c.capability_code='TARGETED_EVIDENCE_ACQUISITION';
  IF NOT FOUND THEN
    RETURN jsonb_build_object('schema_version','LF_TARGETED_EVIDENCE_ACQUISITION_RESULT_V1','state','STOP','code','CAPABILITY_NOT_CURRENT','automation_options_exhausted',false,'effects_executed',false);
  END IF;

  v_expected_typed_version:=v_self_manifest#>>'{dependencies,TYPED_EVIDENCE_REGISTRY,version}';
  v_expected_typed_sha:=v_self_manifest#>>'{dependencies,TYPED_EVIDENCE_REGISTRY,manifest_sha256}';
  SELECT version,manifest_sha256 INTO v_live_typed_version,v_live_typed_sha
  FROM public.lf_capability_current WHERE capability_code='TYPED_EVIDENCE_REGISTRY';
  IF v_live_typed_version IS DISTINCT FROM v_expected_typed_version OR v_live_typed_sha IS DISTINCT FROM v_expected_typed_sha THEN
    RETURN jsonb_build_object('schema_version','LF_TARGETED_EVIDENCE_ACQUISITION_RESULT_V1','state','STOP','code','DEPENDENCY_CURRENTNESS_DRIFT','automation_options_exhausted',false,'effects_executed',false);
  END IF;

  v_consumer_ref:=nullif(btrim(coalesce(p_request->>'consumer_ref','')),'');

  IF jsonb_typeof(p_request->'unresolved_reasons') IS DISTINCT FROM 'array' THEN
    RETURN jsonb_build_object('schema_version','LF_TARGETED_EVIDENCE_ACQUISITION_RESULT_V1','state','STOP','code','UNRESOLVED_REASONS_INVALID','automation_options_exhausted',false,'effects_executed',false,'consumer_ref',v_consumer_ref);
  END IF;
  FOR v_reason IN SELECT value FROM jsonb_array_elements(p_request->'unresolved_reasons') LOOP
    IF jsonb_typeof(v_reason)<>'string' OR nullif(btrim(v_reason#>>'{}'),'') IS NULL THEN
      RETURN jsonb_build_object('schema_version','LF_TARGETED_EVIDENCE_ACQUISITION_RESULT_V1','state','STOP','code','UNRESOLVED_REASON_INVALID','automation_options_exhausted',false,'effects_executed',false,'consumer_ref',v_consumer_ref);
    END IF;
    v_reason_count:=v_reason_count+1;
  END LOOP;

  IF v_reason_count=0 THEN
    RETURN jsonb_build_object(
      'schema_version','LF_TARGETED_EVIDENCE_ACQUISITION_RESULT_V1','state','STOP','code','STOP_DECISION_RESOLVED',
      'next_evidence',NULL,'stop_when','NO_UNRESOLVED_REASON_REMAINS','remaining_reasons',p_request->'unresolved_reasons',
      'automation_options_exhausted',false,'effects_executed',false,'consumer_ref',v_consumer_ref
    );
  END IF;

  IF p_request ? 'current_evidence' THEN
    IF jsonb_typeof(p_request->'current_evidence') IS DISTINCT FROM 'array' THEN
      RETURN jsonb_build_object('schema_version','LF_TARGETED_EVIDENCE_ACQUISITION_RESULT_V1','state','STOP','code','CURRENT_EVIDENCE_INVALID_SHAPE','automation_options_exhausted',false,'effects_executed',false,'consumer_ref',v_consumer_ref);
    END IF;
    FOR v_evidence IN SELECT value FROM jsonb_array_elements(p_request->'current_evidence') LOOP
      IF jsonb_typeof(v_evidence)<>'object'
         OR nullif(btrim(coalesce(v_evidence->>'schema_version','')),'') IS NULL
         OR jsonb_typeof(v_evidence->'payload') IS DISTINCT FROM 'object'
         OR v_evidence->'payload'->>'evidence_schema_version' IS DISTINCT FROM v_evidence->>'schema_version'
         OR private.fn_lf_typed_evidence_payload_valid_v3(v_evidence->>'schema_version',v_evidence->'payload') IS NOT TRUE THEN
        RETURN jsonb_build_object('schema_version','LF_TARGETED_EVIDENCE_ACQUISITION_RESULT_V1','state','STOP','code','TYPED_EVIDENCE_INVALID','automation_options_exhausted',false,'effects_executed',false,'consumer_ref',v_consumer_ref);
      END IF;
      v_evidence_count:=v_evidence_count+1;
    END LOOP;
  END IF;

  IF jsonb_typeof(p_request->'candidates') IS DISTINCT FROM 'array' THEN
    RETURN jsonb_build_object('schema_version','LF_TARGETED_EVIDENCE_ACQUISITION_RESULT_V1','state','STOP','code','CANDIDATES_INVALID_SHAPE','automation_options_exhausted',false,'effects_executed',false,'consumer_ref',v_consumer_ref);
  END IF;

  SELECT count(*),count(distinct nullif(btrim(value->>'candidate_ref'),''))
    INTO v_candidate_count,v_distinct_candidate_count
  FROM jsonb_array_elements(p_request->'candidates');
  IF v_candidate_count<>v_distinct_candidate_count THEN
    RETURN jsonb_build_object('schema_version','LF_TARGETED_EVIDENCE_ACQUISITION_RESULT_V1','state','STOP','code','DUPLICATE_OR_EMPTY_CANDIDATE_REF','automation_options_exhausted',false,'effects_executed',false,'consumer_ref',v_consumer_ref);
  END IF;

  FOR v_candidate IN SELECT value FROM jsonb_array_elements(p_request->'candidates') LOOP
    IF jsonb_typeof(v_candidate)<>'object'
       OR jsonb_typeof(v_candidate->'covers_reasons') IS DISTINCT FROM 'array'
       OR jsonb_typeof(v_candidate->'available') IS DISTINCT FROM 'boolean'
       OR jsonb_typeof(v_candidate->'material') IS DISTINCT FROM 'boolean'
       OR coalesce(v_candidate->>'acquisition_cost_rank','') !~ '^[0-9]+$' THEN
      RETURN jsonb_build_object('schema_version','LF_TARGETED_EVIDENCE_ACQUISITION_RESULT_V1','state','STOP','code','CANDIDATE_INVALID','automation_options_exhausted',false,'effects_executed',false,'consumer_ref',v_consumer_ref);
    END IF;

    v_candidate_ref:=btrim(v_candidate->>'candidate_ref');
    v_source_ref:=nullif(btrim(coalesce(v_candidate->>'source_ref','')),'');
    v_cost:=(v_candidate->>'acquisition_cost_rank')::integer;
    v_available:=(v_candidate->>'available')::boolean;
    v_material:=(v_candidate->>'material')::boolean;

    SELECT count(distinct r.reason)
      INTO v_coverage
    FROM (SELECT jsonb_array_elements_text(p_request->'unresolved_reasons') reason) r
    JOIN (SELECT jsonb_array_elements_text(v_candidate->'covers_reasons') reason) c USING(reason);

    IF v_available AND v_material AND v_source_ref IS NOT NULL AND v_coverage>0 THEN
      IF v_best IS NULL
         OR v_cost<v_best_cost
         OR (v_cost=v_best_cost AND v_coverage>v_best_coverage)
         OR (v_cost=v_best_cost AND v_coverage=v_best_coverage AND v_candidate_ref<v_best_ref) THEN
        v_best:=v_candidate;
        v_best_cost:=v_cost;
        v_best_coverage:=v_coverage;
        v_best_ref:=v_candidate_ref;
      END IF;
    END IF;
  END LOOP;

  IF v_best IS NULL THEN
    RETURN jsonb_build_object(
      'schema_version','LF_TARGETED_EVIDENCE_ACQUISITION_RESULT_V1','state','STOP','code','STOP_NO_DECISION_CHANGING_EVIDENCE',
      'next_evidence',NULL,
      'stop_when','NO_ELIGIBLE_MATERIAL_EVIDENCE_CAN_COVER_ANY_UNRESOLVED_REASON',
      'remaining_reasons',p_request->'unresolved_reasons',
      'automation_options_exhausted',true,
      'typed_evidence_count',v_evidence_count,
      'effects_executed',false,'consumer_ref',v_consumer_ref
    );
  END IF;

  RETURN jsonb_build_object(
    'schema_version','LF_TARGETED_EVIDENCE_ACQUISITION_RESULT_V1','state','CONTINUE','code','NEXT_MINIMAL_EVIDENCE_SELECTED',
    'next_evidence',v_best,
    'stop_when',jsonb_build_object(
      'after_acquisition','RECOMPUTE_WITH_UPDATED_EVIDENCE',
      'terminal_if',jsonb_build_array('NO_UNRESOLVED_REASON_REMAINS','NO_ELIGIBLE_MATERIAL_EVIDENCE_CAN_COVER_ANY_UNRESOLVED_REASON')
    ),
    'remaining_reasons',p_request->'unresolved_reasons',
    'covered_reason_count',v_best_coverage,
    'automation_options_exhausted',false,
    'typed_evidence_count',v_evidence_count,
    'effects_executed',false,'consumer_ref',v_consumer_ref
  );
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('schema_version','LF_TARGETED_EVIDENCE_ACQUISITION_RESULT_V1','state','STOP','code','FAIL_CLOSED_INTERNAL_ERROR','automation_options_exhausted',false,'effects_executed',false,'consumer_ref',v_consumer_ref);
END
$fn$;

REVOKE ALL ON FUNCTION public.lf_targeted_evidence_acquisition_plan_v1(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.lf_targeted_evidence_acquisition_plan_v1(jsonb) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.lf_targeted_evidence_acquisition_plan_v1(jsonb) TO service_role;

DO $cutover$
DECLARE
  v_execution_id constant text := 'CHATGPT-T-TARGET-EVID-PAULO-186-20261004';
  v_typed_version text;
  v_typed_sha text;
  v_manifest jsonb;
  v_manifest_sha text;
  v_existing_sha text;
  v_promote jsonb;
BEGIN
  SELECT version,manifest_sha256 INTO v_typed_version,v_typed_sha
  FROM public.lf_capability_current WHERE capability_code='TYPED_EVIDENCE_REGISTRY';

  v_manifest:=jsonb_build_object(
    'schema_version','LF_CAPABILITY_MANIFEST_V1',
    'capability_code','TARGETED_EVIDENCE_ACQUISITION',
    'version','1.0.0',
    'owner','SUPER_ADMIN',
    'contract',jsonb_build_object(
      'input','unresolved reasons + optional typed current evidence + candidate acquisitions',
      'output','CONTINUE with next_evidence or STOP with stop_when and automation_options_exhausted',
      'authority','READ_ONLY_DETERMINISTIC_EVIDENCE_ACQUISITION_PLANNER',
      'executes_acquisition',false
    ),
    'delivery',jsonb_build_object('mode','SUPABASE_NATIVE_READ_ONLY_PLANNER','function','public.lf_targeted_evidence_acquisition_plan_v1'),
    'installation',jsonb_build_object('required',false,'reinstall_required',false,'package_update_mode','DATABASE_NATIVE_CUTOVER'),
    'dependencies',jsonb_build_object('TYPED_EVIDENCE_REGISTRY',jsonb_build_object('version',v_typed_version,'manifest_sha256',v_typed_sha)),
    'compatibility',jsonb_build_object(
      'domain_agnostic',true,'ig_owner',false,'executes_changes',false,'runtime_mutation',false,
      'production_activation',false,'parallel_evidence_engine',false,'parallel_currentness_engine',false
    ),
    'migration',jsonb_build_object('work_code','PAULO-186','unit_code','T-TARGET-EVID','mode','CAPABILITY_REGISTRY_CURRENTNESS_PLUS_READ_ONLY_PLANNER'),
    'rollback',jsonb_build_object('supported',true,'mode','TRANSACTIONAL_SOURCE_ROLLBACK','rule','remove only TARGETED_EVIDENCE_ACQUISITION v1/current/registry and planner; never mutate dependency capabilities'),
    'usage',jsonb_build_object(
      'entrypoint','public.fn_lf_capability_bind_from_orchestrator_v1',
      'plan','public.lf_targeted_evidence_acquisition_plan_v1',
      'consumer_ref_semantics','OPAQUE_NO_DOMAIN_BRANCHING',
      'docs','sandbox/lf_contract_gate_test/transversal_assets/targeted_evidence_acquisition/README.md'
    ),
    'currentness',jsonb_build_object('dependency_binding','EXACT_VERSION_AND_MANIFEST_SHA256','source_revision_immutable',false,'verification','MIGRATION_SOURCE_PARITY_REQUIRED_POST_MERGE'),
    'stop_rule',jsonb_build_object(
      'continue','AT_LEAST_ONE_AVAILABLE_MATERIAL_CANDIDATE_COVERS_AN_UNRESOLVED_REASON',
      'stop_resolved','NO_UNRESOLVED_REASON_REMAINS',
      'stop_exhausted','NO_ELIGIBLE_MATERIAL_EVIDENCE_CAN_COVER_ANY_UNRESOLVED_REASON'
    )
  );
  v_manifest_sha:=encode(extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),'hex');

  INSERT INTO public.lf_capability_registry(
    capability_code,capability_name,capability_kind,owner_scope,status,description,
    created_by_execution_id,updated_by_execution_id,entry_guard_required,entry_guard_code
  ) VALUES (
    'TARGETED_EVIDENCE_ACQUISITION','Targeted Evidence Acquisition','TRANSVERSAL','SUPER_ADMIN','ACTIVE',
    'Domain-agnostic read-only planner selecting minimal evidence that can still change a pending decision and stopping when evidence options are exhausted.',
    v_execution_id,v_execution_id,true,'ORCHESTRATOR_EXECUTION_GUARD_V1'
  )
  ON CONFLICT(capability_code) DO UPDATE SET
    capability_name=excluded.capability_name,capability_kind='TRANSVERSAL',owner_scope='SUPER_ADMIN',status='ACTIVE',
    description=excluded.description,entry_guard_required=true,entry_guard_code='ORCHESTRATOR_EXECUTION_GUARD_V1',
    updated_at=clock_timestamp(),updated_by_execution_id=v_execution_id;

  SELECT manifest_sha256 INTO v_existing_sha
  FROM public.lf_capability_version_registry
  WHERE capability_code='TARGETED_EVIDENCE_ACQUISITION' AND version='1.0.0';
  IF v_existing_sha IS NOT NULL AND v_existing_sha<>v_manifest_sha THEN
    RAISE EXCEPTION 'BLOCK_T_TARGET_EVID_CAPABILITY_VERSION_MANIFEST_CONFLICT';
  END IF;

  INSERT INTO public.lf_capability_version_registry(
    capability_code,version,version_major,version_minor,version_patch,release_state,supersedes_version,
    manifest,manifest_sha256,source_ref,docs_ref,validator_ref,created_by_execution_id
  ) VALUES (
    'TARGETED_EVIDENCE_ACQUISITION','1.0.0',1,0,0,'RELEASED',NULL,
    v_manifest,v_manifest_sha,
    'supabase://public/lf_targeted_evidence_acquisition_plan_v1',
    'github://cristhianlujan/claude-persona-lf-patch/sandbox/lf_contract_gate_test/transversal_assets/targeted_evidence_acquisition/README.md',
    'supabase://public/lf_targeted_evidence_acquisition_plan_v1',
    v_execution_id
  ) ON CONFLICT(capability_code,version) DO NOTHING;

  v_promote:=public.fn_lf_capability_promote_v1(
    'TARGETED_EVIDENCE_ACQUISITION','1.0.0',NULL,v_execution_id,
    'T-TARGET-EVID materializes the read-only next-evidence planner; it executes no acquisition or business effect.'
  );
  IF coalesce((v_promote->>'ready')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'BLOCK_T_TARGET_EVID_CAPABILITY_CURRENT_POINTER:%',v_promote::text;
  END IF;
END
$cutover$;

DO $tests$
DECLARE
  v_result jsonb;
BEGIN
  v_result:=public.lf_targeted_evidence_acquisition_plan_v1(jsonb_build_object(
    'consumer_ref','NON_IG:GENERIC_CASE',
    'unresolved_reasons',jsonb_build_array('R1','R2'),
    'current_evidence','[]'::jsonb,
    'candidates',jsonb_build_array(
      jsonb_build_object('candidate_ref','C_MORE','source_ref','source://more','covers_reasons',jsonb_build_array('R1','R2'),'acquisition_cost_rank',2,'available',true,'material',true),
      jsonb_build_object('candidate_ref','C_MIN','source_ref','source://min','covers_reasons',jsonb_build_array('R1'),'acquisition_cost_rank',1,'available',true,'material',true)
    )
  ));
  IF v_result->>'state'<>'CONTINUE' OR v_result#>>'{next_evidence,candidate_ref}'<>'C_MIN' THEN
    RAISE EXCEPTION 'BLOCK_T_TARGET_EVID_MINIMAL_SELECTION:%',v_result::text;
  END IF;

  v_result:=public.lf_targeted_evidence_acquisition_plan_v1(jsonb_build_object(
    'consumer_ref','NON_IG:PAYMENT_POLICY',
    'unresolved_reasons',jsonb_build_array('PAYMENT_LIMIT_UNPROVEN'),
    'current_evidence','[]'::jsonb,
    'candidates',jsonb_build_array(
      jsonb_build_object('candidate_ref','POLICY_READBACK','source_ref','authority://payment-policy','covers_reasons',jsonb_build_array('PAYMENT_LIMIT_UNPROVEN'),'acquisition_cost_rank',1,'available',true,'material',true)
    )
  ));
  IF v_result->>'state'<>'CONTINUE' OR v_result#>>'{next_evidence,candidate_ref}'<>'POLICY_READBACK' THEN
    RAISE EXCEPTION 'BLOCK_T_TARGET_EVID_NON_IG_CONSUMER:%',v_result::text;
  END IF;

  v_result:=public.lf_targeted_evidence_acquisition_plan_v1(jsonb_build_object(
    'consumer_ref','ANTI_OVERSEARCH',
    'unresolved_reasons',jsonb_build_array('R1'),
    'current_evidence','[]'::jsonb,
    'candidates',jsonb_build_array(
      jsonb_build_object('candidate_ref','IRRELEVANT','source_ref','source://irrelevant','covers_reasons',jsonb_build_array('R9'),'acquisition_cost_rank',1,'available',true,'material',true)
    )
  ));
  IF v_result->>'state'<>'STOP' OR v_result->>'code'<>'STOP_NO_DECISION_CHANGING_EVIDENCE' OR coalesce((v_result->>'automation_options_exhausted')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'BLOCK_T_TARGET_EVID_OVERSEARCH_NEGATIVE:%',v_result::text;
  END IF;

  v_result:=public.lf_targeted_evidence_acquisition_plan_v1(jsonb_build_object(
    'consumer_ref','RESOLVED_CASE','unresolved_reasons','[]'::jsonb,'current_evidence','[]'::jsonb,'candidates','[]'::jsonb
  ));
  IF v_result->>'state'<>'STOP' OR v_result->>'code'<>'STOP_DECISION_RESOLVED' THEN
    RAISE EXCEPTION 'BLOCK_T_TARGET_EVID_RESOLVED_STOP:%',v_result::text;
  END IF;
END
$tests$;
