-- T-ADMIT / PAULO-185 — SAFE_CHANGE_ADMISSION transversal capability.
-- Owner: SUPER_ADMIN.
-- Scope: domain-agnostic, read-only classification. It never executes a change.
-- Reuse: TYPED_EVIDENCE_REGISTRY + INDEPENDENT_ASSURANCE.
-- R16: Git-first source. R17 is not applicable unless runtime is reached accidentally.

DO $pre$
DECLARE
  v_typed record;
  v_indep record;
BEGIN
  SELECT r.status,r.owner_scope,c.version,c.manifest_sha256
    INTO v_typed
  FROM public.lf_capability_registry r
  JOIN public.lf_capability_current c USING(capability_code)
  WHERE r.capability_code='TYPED_EVIDENCE_REGISTRY';
  IF NOT FOUND OR v_typed.status<>'ACTIVE' OR v_typed.version IS NULL OR v_typed.manifest_sha256 !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'BLOCK_T_ADMIT_TYPED_EVIDENCE_REGISTRY_NOT_CURRENT';
  END IF;

  SELECT r.status,r.owner_scope,c.version,c.manifest_sha256
    INTO v_indep
  FROM public.lf_capability_registry r
  JOIN public.lf_capability_current c USING(capability_code)
  WHERE r.capability_code='INDEPENDENT_ASSURANCE';
  IF NOT FOUND OR v_indep.status<>'ACTIVE' OR v_indep.owner_scope<>'SUPER_ADMIN'
     OR v_indep.version IS NULL OR v_indep.manifest_sha256 !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'BLOCK_T_ADMIT_INDEPENDENT_ASSURANCE_NOT_CURRENT';
  END IF;

  IF to_regprocedure('private.fn_lf_typed_evidence_payload_valid_v3(text,jsonb)') IS NULL THEN
    RAISE EXCEPTION 'BLOCK_T_ADMIT_TYPED_EVIDENCE_VALIDATOR_MISSING';
  END IF;
  IF to_regprocedure('public.lf_independent_assurance_measure_v1(text,text,text,integer,jsonb)') IS NULL THEN
    RAISE EXCEPTION 'BLOCK_T_ADMIT_INDEPENDENT_ASSURANCE_MEASURE_MISSING';
  END IF;
END
$pre$;

CREATE OR REPLACE FUNCTION public.lf_safe_change_admission_classify_v1(p_request jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, private, extensions
AS $fn$
DECLARE
  v_item jsonb;
  v_schema text;
  v_payload jsonb;
  v_evidence_count integer := 0;
  v_consumer_ref text;
  v_auth_state text;
  v_auth_ref text;
  v_change_required boolean;
  v_scope_bounded boolean;
  v_materiality_level text;
  v_rev_state text;
  v_negative boolean;
  v_rollback boolean;
  v_readback boolean;
  v_rec_state text;
  v_confidence text;
  v_indep_required boolean := false;
  v_indep jsonb;
  v_indep_state text := 'NOT_REQUIRED';
  v_self_manifest jsonb;
  v_expected_typed_version text;
  v_expected_typed_sha text;
  v_expected_indep_version text;
  v_expected_indep_sha text;
  v_live_typed_version text;
  v_live_typed_sha text;
  v_live_indep_version text;
  v_live_indep_sha text;
  v_classification text;
  v_code text;
  v_permission text := 'NO_EXECUTION_PERMISSION';
BEGIN
  IF p_request IS NULL OR jsonb_typeof(p_request)<>'object' THEN
    RETURN jsonb_build_object(
      'schema_version','LF_SAFE_CHANGE_ADMISSION_RESULT_V1',
      'classification','UNKNOWN','code','INVALID_REQUEST',
      'execution_permission','NO_EXECUTION_PERMISSION','effects_executed',false
    );
  END IF;

  -- Exact dependency currentness is part of the capability contract.
  SELECT vr.manifest
    INTO v_self_manifest
  FROM public.lf_capability_current c
  JOIN public.lf_capability_version_registry vr
    ON vr.capability_code=c.capability_code AND vr.version=c.version
  WHERE c.capability_code='SAFE_CHANGE_ADMISSION'
    AND vr.manifest_sha256=c.manifest_sha256;
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'schema_version','LF_SAFE_CHANGE_ADMISSION_RESULT_V1',
      'classification','UNKNOWN','code','CAPABILITY_NOT_CURRENT',
      'execution_permission','NO_EXECUTION_PERMISSION','effects_executed',false
    );
  END IF;

  v_expected_typed_version:=v_self_manifest#>>'{dependencies,TYPED_EVIDENCE_REGISTRY,version}';
  v_expected_typed_sha:=v_self_manifest#>>'{dependencies,TYPED_EVIDENCE_REGISTRY,manifest_sha256}';
  v_expected_indep_version:=v_self_manifest#>>'{dependencies,INDEPENDENT_ASSURANCE,version}';
  v_expected_indep_sha:=v_self_manifest#>>'{dependencies,INDEPENDENT_ASSURANCE,manifest_sha256}';

  SELECT version,manifest_sha256 INTO v_live_typed_version,v_live_typed_sha
  FROM public.lf_capability_current WHERE capability_code='TYPED_EVIDENCE_REGISTRY';
  SELECT version,manifest_sha256 INTO v_live_indep_version,v_live_indep_sha
  FROM public.lf_capability_current WHERE capability_code='INDEPENDENT_ASSURANCE';

  IF v_live_typed_version IS DISTINCT FROM v_expected_typed_version
     OR v_live_typed_sha IS DISTINCT FROM v_expected_typed_sha
     OR v_live_indep_version IS DISTINCT FROM v_expected_indep_version
     OR v_live_indep_sha IS DISTINCT FROM v_expected_indep_sha THEN
    RETURN jsonb_build_object(
      'schema_version','LF_SAFE_CHANGE_ADMISSION_RESULT_V1',
      'classification','UNKNOWN','code','DEPENDENCY_CURRENTNESS_DRIFT',
      'execution_permission','NO_EXECUTION_PERMISSION','effects_executed',false,
      'dependency_readback',jsonb_build_object(
        'typed_evidence_registry',jsonb_build_object('expected_version',v_expected_typed_version,'live_version',v_live_typed_version,'expected_manifest_sha256',v_expected_typed_sha,'live_manifest_sha256',v_live_typed_sha),
        'independent_assurance',jsonb_build_object('expected_version',v_expected_indep_version,'live_version',v_live_indep_version,'expected_manifest_sha256',v_expected_indep_sha,'live_manifest_sha256',v_live_indep_sha)
      )
    );
  END IF;

  v_consumer_ref:=nullif(btrim(coalesce(p_request->>'consumer_ref','')),'');

  IF jsonb_typeof(p_request#>'{evidence,items}') IS DISTINCT FROM 'array'
     OR jsonb_array_length(p_request#>'{evidence,items}')=0 THEN
    RETURN jsonb_build_object(
      'schema_version','LF_SAFE_CHANGE_ADMISSION_RESULT_V1',
      'classification','UNKNOWN','code','EVIDENCE_MISSING_OR_INVALID_SHAPE',
      'execution_permission','NO_EXECUTION_PERMISSION','effects_executed',false,
      'consumer_ref',v_consumer_ref
    );
  END IF;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_request#>'{evidence,items}')
  LOOP
    IF jsonb_typeof(v_item)<>'object' THEN
      RETURN jsonb_build_object('schema_version','LF_SAFE_CHANGE_ADMISSION_RESULT_V1','classification','UNKNOWN','code','EVIDENCE_ITEM_INVALID','execution_permission','NO_EXECUTION_PERMISSION','effects_executed',false,'consumer_ref',v_consumer_ref);
    END IF;
    v_schema:=nullif(btrim(coalesce(v_item->>'schema_version','')),'');
    v_payload:=v_item->'payload';
    IF v_schema IS NULL OR jsonb_typeof(v_payload) IS DISTINCT FROM 'object'
       OR v_payload->>'evidence_schema_version' IS DISTINCT FROM v_schema
       OR private.fn_lf_typed_evidence_payload_valid_v3(v_schema,v_payload) IS NOT TRUE THEN
      RETURN jsonb_build_object(
        'schema_version','LF_SAFE_CHANGE_ADMISSION_RESULT_V1',
        'classification','UNKNOWN','code','TYPED_EVIDENCE_INVALID',
        'execution_permission','NO_EXECUTION_PERMISSION','effects_executed',false,
        'consumer_ref',v_consumer_ref,'invalid_schema_version',v_schema
      );
    END IF;
    v_evidence_count:=v_evidence_count+1;
  END LOOP;

  IF p_request#>'{evidence,independence}' IS NOT NULL THEN
    IF jsonb_typeof(p_request#>'{evidence,independence}')<>'object' THEN
      RETURN jsonb_build_object('schema_version','LF_SAFE_CHANGE_ADMISSION_RESULT_V1','classification','UNKNOWN','code','INDEPENDENCE_EVIDENCE_INVALID_SHAPE','execution_permission','NO_EXECUTION_PERMISSION','effects_executed',false,'consumer_ref',v_consumer_ref);
    END IF;
    IF (p_request#>'{evidence,independence}') ? 'required'
       AND jsonb_typeof(p_request#>'{evidence,independence,required}')<>'boolean' THEN
      RETURN jsonb_build_object('schema_version','LF_SAFE_CHANGE_ADMISSION_RESULT_V1','classification','UNKNOWN','code','INDEPENDENCE_REQUIRED_INVALID','execution_permission','NO_EXECUTION_PERMISSION','effects_executed',false,'consumer_ref',v_consumer_ref);
    END IF;
    v_indep_required:=coalesce((p_request#>>'{evidence,independence,required}')::boolean,false);
    IF v_indep_required THEN
      v_indep:=public.lf_independent_assurance_measure_v1(
        p_request#>>'{evidence,independence,dependency_schema}',
        p_request#>>'{evidence,independence,producer_root}',
        p_request#>>'{evidence,independence,reviewer_root}',
        coalesce((p_request#>>'{evidence,independence,max_depth}')::integer,8),
        coalesce(p_request#>'{evidence,independence,context}','{}'::jsonb)
      );
      v_indep_state:=coalesce(v_indep->>'state','BLOCKED');
      IF v_indep_state IN ('BLOCKED','UNPROVEN') THEN
        RETURN jsonb_build_object(
          'schema_version','LF_SAFE_CHANGE_ADMISSION_RESULT_V1',
          'classification','UNKNOWN','code','INDEPENDENCE_NOT_PROVEN',
          'execution_permission','NO_EXECUTION_PERMISSION','effects_executed',false,
          'consumer_ref',v_consumer_ref,'independent_assurance',v_indep
        );
      ELSIF v_indep_state='NOT_INDEPENDENT' THEN
        RETURN jsonb_build_object(
          'schema_version','LF_SAFE_CHANGE_ADMISSION_RESULT_V1',
          'classification','REQUIERE_DECISION','code','INDEPENDENCE_NEGATIVE',
          'execution_permission','NO_EXECUTION_PERMISSION','effects_executed',false,
          'consumer_ref',v_consumer_ref,'independent_assurance',v_indep
        );
      ELSIF v_indep_state<>'INDEPENDENT' THEN
        RETURN jsonb_build_object('schema_version','LF_SAFE_CHANGE_ADMISSION_RESULT_V1','classification','UNKNOWN','code','INDEPENDENCE_STATE_UNKNOWN','execution_permission','NO_EXECUTION_PERMISSION','effects_executed',false,'consumer_ref',v_consumer_ref,'independent_assurance',v_indep);
      END IF;
    END IF;
  END IF;

  IF jsonb_typeof(p_request->'authority') IS DISTINCT FROM 'object' THEN
    RETURN jsonb_build_object('schema_version','LF_SAFE_CHANGE_ADMISSION_RESULT_V1','classification','UNKNOWN','code','AUTHORITY_MISSING','execution_permission','NO_EXECUTION_PERMISSION','effects_executed',false,'consumer_ref',v_consumer_ref);
  END IF;
  v_auth_state:=upper(coalesce(p_request#>>'{authority,state}',''));
  v_auth_ref:=nullif(btrim(coalesce(p_request#>>'{authority,authority_ref}','')),'');
  IF v_auth_state NOT IN ('SUFFICIENT','INSUFFICIENT','UNKNOWN') THEN
    RETURN jsonb_build_object('schema_version','LF_SAFE_CHANGE_ADMISSION_RESULT_V1','classification','UNKNOWN','code','AUTHORITY_STATE_INVALID','execution_permission','NO_EXECUTION_PERMISSION','effects_executed',false,'consumer_ref',v_consumer_ref);
  END IF;
  IF v_auth_state='SUFFICIENT' AND v_auth_ref IS NULL THEN
    RETURN jsonb_build_object('schema_version','LF_SAFE_CHANGE_ADMISSION_RESULT_V1','classification','UNKNOWN','code','SUFFICIENT_AUTHORITY_WITHOUT_REF','execution_permission','NO_EXECUTION_PERMISSION','effects_executed',false,'consumer_ref',v_consumer_ref);
  END IF;

  IF jsonb_typeof(p_request->'materiality') IS DISTINCT FROM 'object'
     OR jsonb_typeof(p_request#>'{materiality,change_required}') IS DISTINCT FROM 'boolean'
     OR jsonb_typeof(p_request#>'{materiality,scope_bounded}') IS DISTINCT FROM 'boolean' THEN
    RETURN jsonb_build_object('schema_version','LF_SAFE_CHANGE_ADMISSION_RESULT_V1','classification','UNKNOWN','code','MATERIALITY_INVALID','execution_permission','NO_EXECUTION_PERMISSION','effects_executed',false,'consumer_ref',v_consumer_ref);
  END IF;
  v_change_required:=(p_request#>>'{materiality,change_required}')::boolean;
  v_scope_bounded:=(p_request#>>'{materiality,scope_bounded}')::boolean;
  v_materiality_level:=upper(coalesce(p_request#>>'{materiality,level}',''));
  IF v_materiality_level NOT IN ('LOW','MEDIUM','HIGH') THEN
    RETURN jsonb_build_object('schema_version','LF_SAFE_CHANGE_ADMISSION_RESULT_V1','classification','UNKNOWN','code','MATERIALITY_LEVEL_INVALID','execution_permission','NO_EXECUTION_PERMISSION','effects_executed',false,'consumer_ref',v_consumer_ref);
  END IF;

  IF jsonb_typeof(p_request->'reversibility') IS DISTINCT FROM 'object'
     OR jsonb_typeof(p_request#>'{reversibility,negative_proven}') IS DISTINCT FROM 'boolean'
     OR jsonb_typeof(p_request#>'{reversibility,rollback_proven}') IS DISTINCT FROM 'boolean'
     OR jsonb_typeof(p_request#>'{reversibility,readback_proven}') IS DISTINCT FROM 'boolean' THEN
    RETURN jsonb_build_object('schema_version','LF_SAFE_CHANGE_ADMISSION_RESULT_V1','classification','UNKNOWN','code','REVERSIBILITY_INVALID','execution_permission','NO_EXECUTION_PERMISSION','effects_executed',false,'consumer_ref',v_consumer_ref);
  END IF;
  v_rev_state:=upper(coalesce(p_request#>>'{reversibility,state}',''));
  IF v_rev_state NOT IN ('DEMONSTRATED','NOT_DEMONSTRATED') THEN
    RETURN jsonb_build_object('schema_version','LF_SAFE_CHANGE_ADMISSION_RESULT_V1','classification','UNKNOWN','code','REVERSIBILITY_STATE_INVALID','execution_permission','NO_EXECUTION_PERMISSION','effects_executed',false,'consumer_ref',v_consumer_ref);
  END IF;
  v_negative:=(p_request#>>'{reversibility,negative_proven}')::boolean;
  v_rollback:=(p_request#>>'{reversibility,rollback_proven}')::boolean;
  v_readback:=(p_request#>>'{reversibility,readback_proven}')::boolean;
  IF v_rev_state='DEMONSTRATED' AND (NOT v_rollback OR NOT v_readback) THEN
    RETURN jsonb_build_object('schema_version','LF_SAFE_CHANGE_ADMISSION_RESULT_V1','classification','UNKNOWN','code','REVERSIBILITY_CLAIM_CONTRADICTED','execution_permission','NO_EXECUTION_PERMISSION','effects_executed',false,'consumer_ref',v_consumer_ref);
  END IF;

  IF jsonb_typeof(p_request->'recommendation') IS DISTINCT FROM 'object' THEN
    RETURN jsonb_build_object('schema_version','LF_SAFE_CHANGE_ADMISSION_RESULT_V1','classification','UNKNOWN','code','RECOMMENDATION_MISSING','execution_permission','NO_EXECUTION_PERMISSION','effects_executed',false,'consumer_ref',v_consumer_ref);
  END IF;
  v_rec_state:=upper(coalesce(p_request#>>'{recommendation,state}',''));
  v_confidence:=upper(coalesce(p_request#>>'{recommendation,confidence}',''));
  IF v_rec_state NOT IN ('FAVORABLE','UNFAVORABLE') OR v_confidence NOT IN ('LOW','MEDIUM','HIGH') THEN
    RETURN jsonb_build_object('schema_version','LF_SAFE_CHANGE_ADMISSION_RESULT_V1','classification','UNKNOWN','code','RECOMMENDATION_INVALID','execution_permission','NO_EXECUTION_PERMISSION','effects_executed',false,'consumer_ref',v_consumer_ref);
  END IF;

  -- Classification precedence is intentionally fail-closed.
  IF v_change_required IS FALSE THEN
    v_classification:='VERIFY_NO_CHANGE'; v_code:='NO_MATERIAL_CHANGE_REQUIRED';
  ELSIF v_auth_state='UNKNOWN' THEN
    v_classification:='UNKNOWN'; v_code:='AUTHORITY_UNKNOWN';
  ELSIF v_auth_state='INSUFFICIENT' THEN
    v_classification:='REQUIERE_DECISION'; v_code:='AUTHORITY_INSUFFICIENT';
  ELSIF v_scope_bounded IS FALSE OR v_materiality_level='HIGH' OR v_rec_state='UNFAVORABLE' THEN
    v_classification:='REQUIERE_DECISION'; v_code:='MATERIAL_DECISION_REQUIRED';
  ELSIF v_scope_bounded IS TRUE
        AND v_rev_state='DEMONSTRATED'
        AND v_negative IS TRUE
        AND v_rollback IS TRUE
        AND v_readback IS TRUE
        AND v_auth_state='SUFFICIENT'
        AND v_rec_state='FAVORABLE'
        AND (NOT v_indep_required OR v_indep_state='INDEPENDENT') THEN
    v_classification:='AUTOMATIZABLE'; v_code:='SAFE_ADMISSION_CRITERIA_SATISFIED';
    v_permission:='DOWNSTREAM_EXECUTION_ELIGIBLE';
  ELSE
    v_classification:='RECOMENDADA'; v_code:='RECOMMENDATION_WITHOUT_EXECUTION_PERMISSION';
  END IF;

  RETURN jsonb_build_object(
    'schema_version','LF_SAFE_CHANGE_ADMISSION_RESULT_V1',
    'classification',v_classification,
    'code',v_code,
    'execution_permission',v_permission,
    'effects_executed',false,
    'consumer_ref',v_consumer_ref,
    'evidence',jsonb_build_object('state','VALID','typed_item_count',v_evidence_count,'independence_state',v_indep_state),
    'authority',jsonb_build_object('state',v_auth_state,'authority_ref',v_auth_ref),
    'materiality',jsonb_build_object('change_required',v_change_required,'scope_bounded',v_scope_bounded,'level',v_materiality_level),
    'reversibility',jsonb_build_object('state',v_rev_state,'negative_proven',v_negative,'rollback_proven',v_rollback,'readback_proven',v_readback),
    'recommendation',jsonb_build_object('state',v_rec_state,'confidence',v_confidence),
    'independent_assurance',v_indep
  );
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'schema_version','LF_SAFE_CHANGE_ADMISSION_RESULT_V1',
    'classification','UNKNOWN','code','FAIL_CLOSED_INTERNAL_ERROR',
    'execution_permission','NO_EXECUTION_PERMISSION','effects_executed',false,
    'consumer_ref',v_consumer_ref
  );
END
$fn$;

REVOKE ALL ON FUNCTION public.lf_safe_change_admission_classify_v1(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.lf_safe_change_admission_classify_v1(jsonb) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.lf_safe_change_admission_classify_v1(jsonb) TO service_role;

DO $cutover$
DECLARE
  v_execution_id constant text := 'CHATGPT-T-ADMIT-PAULO-185-20261004';
  v_typed_version text;
  v_typed_sha text;
  v_indep_version text;
  v_indep_sha text;
  v_manifest jsonb;
  v_manifest_sha text;
  v_existing_sha text;
  v_promote jsonb;
BEGIN
  SELECT version,manifest_sha256 INTO v_typed_version,v_typed_sha
  FROM public.lf_capability_current WHERE capability_code='TYPED_EVIDENCE_REGISTRY';
  SELECT version,manifest_sha256 INTO v_indep_version,v_indep_sha
  FROM public.lf_capability_current WHERE capability_code='INDEPENDENT_ASSURANCE';

  v_manifest:=jsonb_build_object(
    'schema_version','LF_CAPABILITY_MANIFEST_V1',
    'capability_code','SAFE_CHANGE_ADMISSION',
    'version','1.0.0',
    'owner','SUPER_ADMIN',
    'contract',jsonb_build_object(
      'input','typed evidence + authority + materiality + reversibility + recommendation + optional independent-assurance proof',
      'output','exactly one of AUTOMATIZABLE|RECOMENDADA|REQUIERE_DECISION|UNKNOWN|VERIFY_NO_CHANGE plus execution_permission',
      'authority','READ_ONLY_FAIL_CLOSED_ADMISSION_CLASSIFICATION',
      'recommendation_is_permission',false
    ),
    'classification_states',jsonb_build_array('AUTOMATIZABLE','RECOMENDADA','REQUIERE_DECISION','UNKNOWN','VERIFY_NO_CHANGE'),
    'dependencies',jsonb_build_object(
      'TYPED_EVIDENCE_REGISTRY',jsonb_build_object('version',v_typed_version,'manifest_sha256',v_typed_sha),
      'INDEPENDENT_ASSURANCE',jsonb_build_object('version',v_indep_version,'manifest_sha256',v_indep_sha)
    ),
    'compatibility',jsonb_build_object(
      'domain_agnostic',true,
      'ig_owner',false,
      'executes_changes',false,
      'runtime_mutation',false,
      'production_activation',false,
      'parallel_evidence_engine',false,
      'parallel_assurance_engine',false
    ),
    'usage',jsonb_build_object(
      'entrypoint','public.fn_lf_capability_bind_from_orchestrator_v1',
      'classify','public.lf_safe_change_admission_classify_v1',
      'consumer_ref_semantics','OPAQUE_NO_DOMAIN_BRANCHING',
      'docs','sandbox/lf_contract_gate_test/transversal_assets/safe_change_admission/README.md'
    ),
    'automation_gate',jsonb_build_object(
      'scope_bounded_required',true,
      'authority_sufficient_required',true,
      'negative_proven_required',true,
      'rollback_proven_required',true,
      'readback_proven_required',true,
      'reversibility_demonstrated_required',true,
      'favorable_recommendation_required',true,
      'unknown_fail_closed',true
    ),
    'currentness',jsonb_build_object(
      'dependency_binding','EXACT_VERSION_AND_MANIFEST_SHA256',
      'source_revision_immutable',false,
      'verification','MIGRATION_SOURCE_PARITY_REQUIRED_POST_MERGE'
    ),
    'migration',jsonb_build_object('work_code','PAULO-185','unit_code','T-ADMIT','mode','CAPABILITY_REGISTRY_CURRENTNESS_PLUS_READ_ONLY_CLASSIFIER'),
    'rollback',jsonb_build_object('supported',true,'mode','TRANSACTIONAL_SOURCE_ROLLBACK','rule','remove only SAFE_CHANGE_ADMISSION v1/current/registry and classifier; never mutate dependency capabilities')
  );
  v_manifest_sha:=encode(extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),'hex');

  INSERT INTO public.lf_capability_registry(
    capability_code,capability_name,capability_kind,owner_scope,status,description,
    created_by_execution_id,updated_by_execution_id,entry_guard_required,entry_guard_code
  ) VALUES (
    'SAFE_CHANGE_ADMISSION','Safe Change Admission','TRANSVERSAL','SUPER_ADMIN','ACTIVE',
    'Domain-agnostic read-only admission classification separating recommendation from execution permission.',
    v_execution_id,v_execution_id,true,'ORCHESTRATOR_EXECUTION_GUARD_V1'
  )
  ON CONFLICT(capability_code) DO UPDATE SET
    capability_name=excluded.capability_name,
    capability_kind='TRANSVERSAL',
    owner_scope='SUPER_ADMIN',
    status='ACTIVE',
    description=excluded.description,
    entry_guard_required=true,
    entry_guard_code='ORCHESTRATOR_EXECUTION_GUARD_V1',
    updated_at=clock_timestamp(),
    updated_by_execution_id=v_execution_id;

  SELECT manifest_sha256 INTO v_existing_sha
  FROM public.lf_capability_version_registry
  WHERE capability_code='SAFE_CHANGE_ADMISSION' AND version='1.0.0';
  IF v_existing_sha IS NOT NULL AND v_existing_sha<>v_manifest_sha THEN
    RAISE EXCEPTION 'BLOCK_T_ADMIT_CAPABILITY_VERSION_MANIFEST_CONFLICT';
  END IF;

  INSERT INTO public.lf_capability_version_registry(
    capability_code,version,version_major,version_minor,version_patch,release_state,supersedes_version,
    manifest,manifest_sha256,source_ref,docs_ref,validator_ref,created_by_execution_id
  ) VALUES (
    'SAFE_CHANGE_ADMISSION','1.0.0',1,0,0,'RELEASED',NULL,
    v_manifest,v_manifest_sha,
    'supabase://public/lf_safe_change_admission_classify_v1',
    'github://cristhianlujan/claude-persona-lf-patch/sandbox/lf_contract_gate_test/transversal_assets/safe_change_admission/README.md',
    'supabase://public/lf_safe_change_admission_classify_v1',
    v_execution_id
  ) ON CONFLICT(capability_code,version) DO NOTHING;

  v_promote:=public.fn_lf_capability_promote_v1(
    'SAFE_CHANGE_ADMISSION','1.0.0',NULL,v_execution_id,
    'T-ADMIT materializes domain-agnostic safe admission. Classification never executes a change.'
  );
  IF coalesce((v_promote->>'ready')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'BLOCK_T_ADMIT_CAPABILITY_CURRENT_POINTER:%',v_promote::text;
  END IF;

  IF NOT EXISTS(
    SELECT 1 FROM public.lf_capability_registry r
    JOIN public.lf_capability_current c USING(capability_code)
    WHERE r.capability_code='SAFE_CHANGE_ADMISSION'
      AND r.status='ACTIVE' AND r.owner_scope='SUPER_ADMIN'
      AND r.entry_guard_required=true AND r.entry_guard_code='ORCHESTRATOR_EXECUTION_GUARD_V1'
      AND c.version='1.0.0' AND c.manifest_sha256=v_manifest_sha
  ) THEN
    RAISE EXCEPTION 'BLOCK_T_ADMIT_POST_CURRENT_READBACK_FAILED';
  END IF;
END
$cutover$;
