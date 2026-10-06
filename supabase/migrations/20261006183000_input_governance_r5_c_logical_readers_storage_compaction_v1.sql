-- R5-C DRAFT ONLY — logical validator evidence readers + governed STORAGE_COMPACTION transition.
-- DO NOT APPLY WITHOUT: (1) Claude review, (2) explicit Cristhian OK, (3) contract 5.13.x disposition.
-- This candidate performs no historical compaction. R5-E remains separate.

DO $r5c_preflight$
DECLARE
  v_actual text;
  v_sets bigint;
BEGIN
  IF to_regclass('programacion.input_validator_assertion_sets_v1') IS NULL
     OR to_regprocedure('programacion.fn_input_validator_evidence_rehydrate_v1(jsonb)') IS NULL THEN
    RAISE EXCEPTION 'R5C_REQUIRES_R5A';
  END IF;

  SELECT count(*) INTO v_sets FROM programacion.input_validator_assertion_sets_v1;
  IF v_sets <> 3379 THEN
    RAISE EXCEPTION 'R5C_REQUIRES_VERIFIED_R5B expected_sets=3379 actual=%',v_sets;
  END IF;

  v_actual:=md5(pg_get_functiondef('programacion.fn_input_validator_evidence_rehydrate_v1(jsonb)'::regprocedure));
  IF v_actual IS DISTINCT FROM '1fcbd090ac0d38945d61bc385870ab64' THEN
    RAISE EXCEPTION 'R5C_BASE_MD5_MISMATCH function=rehydrate expected=% actual=%',
      '1fcbd090ac0d38945d61bc385870ab64',coalesce(v_actual,'<NULL>');
  END IF;

  v_actual:=md5(pg_get_functiondef('programacion.fn_guard_input_family_assessment_update()'::regprocedure));
  IF v_actual IS DISTINCT FROM '1ed8d14016692bae1f7c83e0fb784ce9' THEN
    RAISE EXCEPTION 'R5C_BASE_MD5_MISMATCH function=family_assessment_update expected=% actual=%',
      '1ed8d14016692bae1f7c83e0fb784ce9',coalesce(v_actual,'<NULL>');
  END IF;

  v_actual:=md5(pg_get_functiondef('programacion.fn_guard_input_family_execution_update()'::regprocedure));
  IF v_actual IS DISTINCT FROM 'a2e62e0aa8aaea5d3e0a4c48c69a5faa' THEN
    RAISE EXCEPTION 'R5C_BASE_MD5_MISMATCH function=family_execution_update expected=% actual=%',
      'a2e62e0aa8aaea5d3e0a4c48c69a5faa',coalesce(v_actual,'<NULL>');
  END IF;

  v_actual:=md5(pg_get_functiondef('programacion.fn_guard_input_validator_semantic_coherence_v512()'::regprocedure));
  IF v_actual IS DISTINCT FROM 'b4f4e6d0f97255cd3cfe1f77df80ecb5' THEN
    RAISE EXCEPTION 'R5C_BASE_MD5_MISMATCH function=semantic_coherence_v512 expected=% actual=%',
      'b4f4e6d0f97255cd3cfe1f77df80ecb5',coalesce(v_actual,'<NULL>');
  END IF;

  v_actual:=md5(pg_get_functiondef('programacion.fn_input_auth006_build_assertions(bigint,bigint,text)'::regprocedure));
  IF v_actual IS DISTINCT FROM '8f46becafa22ae24cf21f316d2516511' THEN
    RAISE EXCEPTION 'R5C_BASE_MD5_MISMATCH function=auth006_build_assertions expected=% actual=%',
      '8f46becafa22ae24cf21f316d2516511',coalesce(v_actual,'<NULL>');
  END IF;

  v_actual:=md5(pg_get_functiondef('programacion.fn_input_owner_decision_assertions(bigint,bigint,text)'::regprocedure));
  IF v_actual IS DISTINCT FROM 'c672695362826666ac8da5799982bbad' THEN
    RAISE EXCEPTION 'R5C_BASE_MD5_MISMATCH function=owner_decision_assertions expected=% actual=%',
      'c672695362826666ac8da5799982bbad',coalesce(v_actual,'<NULL>');
  END IF;

  v_actual:=md5(pg_get_functiondef('programacion.fn_input_v58_build_assertions(bigint,bigint,text)'::regprocedure));
  IF v_actual IS DISTINCT FROM '385b6a7c7cfaf56bff3c6aa8d41539d8' THEN
    RAISE EXCEPTION 'R5C_BASE_MD5_MISMATCH function=v58_build_assertions expected=% actual=%',
      '385b6a7c7cfaf56bff3c6aa8d41539d8',coalesce(v_actual,'<NULL>');
  END IF;

  v_actual:=md5(pg_get_functiondef('programacion.fn_guard_input_governance_continuation_currentness_v1()'::regprocedure));
  IF v_actual IS DISTINCT FROM '69cf918a8510c6ba40302cbba56e5c99' THEN
    RAISE EXCEPTION 'R5C_BASE_MD5_MISMATCH function=continuation_currentness expected=% actual=%',
      '69cf918a8510c6ba40302cbba56e5c99',coalesce(v_actual,'<NULL>');
  END IF;
END
$r5c_preflight$;

CREATE OR REPLACE FUNCTION programacion.fn_input_validator_storage_compaction_check_v1(
  p_old_row jsonb,
  p_new_row jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog','programacion'
AS $function$
DECLARE
  v_old_evidence jsonb:=p_old_row->'validator_evidence';
  v_new_evidence jsonb:=p_new_row->'validator_evidence';
  v_ref text;
  v_assertions jsonb;
  v_actual_sha text;
  v_logical jsonb;
BEGIN
  -- Clause 1: apart from validator_evidence, no column may change.
  -- validator_sha256 is checked separately in clause 5 so it has an independent negative test.
  IF (p_old_row - 'validator_evidence' - 'validator_sha256')
       IS DISTINCT FROM
     (p_new_row - 'validator_evidence' - 'validator_sha256') THEN
    RETURN jsonb_build_object('allowed',false,'code','R5C_NON_EVIDENCE_COLUMN_CHANGED');
  END IF;

  -- Clause 2: exact inline -> reference representation transition.
  IF jsonb_typeof(v_old_evidence) <> 'object'
     OR jsonb_typeof(v_old_evidence->'assertions') <> 'array'
     OR jsonb_array_length(v_old_evidence->'assertions') = 0
     OR jsonb_typeof(v_new_evidence) <> 'object'
     OR v_new_evidence ? 'assertions'
     OR NOT (v_new_evidence ? 'assertion_set_sha256')
     OR coalesce(v_new_evidence->>'assertion_set_sha256','') !~ '^[0-9a-f]{64}$' THEN
    RETURN jsonb_build_object('allowed',false,'code','R5C_STORAGE_SHAPE_INVALID');
  END IF;

  v_ref:=v_new_evidence->>'assertion_set_sha256';

  -- Clause 4: referenced set must exist and remain content-addressed.
  SELECT s.assertions INTO v_assertions
  FROM programacion.input_validator_assertion_sets_v1 s
  WHERE s.assertion_set_sha256=v_ref;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('allowed',false,'code','R5C_ASSERTION_SET_NOT_FOUND');
  END IF;

  v_actual_sha:=programacion.fn_v09_sha256_jsonb(v_assertions);
  IF v_actual_sha IS DISTINCT FROM v_ref THEN
    RETURN jsonb_build_object(
      'allowed',false,
      'code','R5C_ASSERTION_SET_CONTENT_HASH_MISMATCH',
      'expected',v_ref,
      'actual',v_actual_sha
    );
  END IF;

  -- Clause 3: exact logical evidence equality after rehydration.
  v_logical:=programacion.fn_input_validator_evidence_rehydrate_v1(v_new_evidence);
  IF v_logical IS DISTINCT FROM v_old_evidence THEN
    RETURN jsonb_build_object('allowed',false,'code','R5C_REHYDRATED_EVIDENCE_MISMATCH');
  END IF;

  -- Clause 5: validator receipt hash is immutable.
  IF p_new_row->>'validator_sha256' IS DISTINCT FROM p_old_row->>'validator_sha256' THEN
    RETURN jsonb_build_object('allowed',false,'code','R5C_VALIDATOR_SHA256_CHANGED');
  END IF;

  RETURN jsonb_build_object('allowed',true,'code','STORAGE_COMPACTION');
END;
$function$;

REVOKE ALL ON FUNCTION programacion.fn_input_validator_storage_compaction_check_v1(jsonb,jsonb)
FROM PUBLIC,anon,authenticated,service_role;

-- Negative/positive self-tests for all five owner clauses.
DO $r5c_storage_tests$
DECLARE
  v_sha1 text; v_sha2 text; v_assert1 jsonb;
  v_missing text:=repeat('f',64);
  v_old jsonb; v_new jsonb; v_result jsonb;
BEGIN
  SELECT assertion_set_sha256,assertions
    INTO v_sha1,v_assert1
  FROM programacion.input_validator_assertion_sets_v1
  ORDER BY assertion_set_sha256
  LIMIT 1;

  SELECT assertion_set_sha256
    INTO v_sha2
  FROM programacion.input_validator_assertion_sets_v1
  WHERE assertion_set_sha256<>v_sha1
  ORDER BY assertion_set_sha256
  LIMIT 1;

  IF EXISTS (
    SELECT 1 FROM programacion.input_validator_assertion_sets_v1
    WHERE assertion_set_sha256=v_missing
  ) THEN
    v_missing:=repeat('e',64);
  END IF;
  IF EXISTS (
    SELECT 1 FROM programacion.input_validator_assertion_sets_v1
    WHERE assertion_set_sha256=v_missing
  ) THEN
    RAISE EXCEPTION 'R5C_NEGATIVE_TEST_NO_MISSING_SHA_AVAILABLE';
  END IF;

  v_old:=jsonb_build_object(
    'id',1,'run_id',1,'family_code','SELFTEST',
    'validator_sha256',repeat('a',64),
    'sentinel','UNCHANGED',
    'validator_evidence',jsonb_build_object(
      'execution_id','R5C-SELFTEST',
      'assertions',v_assert1
    )
  );
  v_new:=jsonb_build_object(
    'id',1,'run_id',1,'family_code','SELFTEST',
    'validator_sha256',repeat('a',64),
    'sentinel','UNCHANGED',
    'validator_evidence',jsonb_build_object(
      'execution_id','R5C-SELFTEST',
      'assertion_set_sha256',v_sha1
    )
  );

  v_result:=programacion.fn_input_validator_storage_compaction_check_v1(v_old,v_new);
  IF coalesce((v_result->>'allowed')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'R5C_POSITIVE_STORAGE_COMPACTION_SELFTEST_FAILED:%',v_result;
  END IF;

  -- Clause 1 negative: a non-evidence column changed.
  v_result:=programacion.fn_input_validator_storage_compaction_check_v1(
    v_old,
    jsonb_set(v_new,'{sentinel}','"CHANGED"'::jsonb)
  );
  IF v_result->>'code'<>'R5C_NON_EVIDENCE_COLUMN_CHANGED' THEN
    RAISE EXCEPTION 'R5C_NEGATIVE_CLAUSE1_FAILED:%',v_result;
  END IF;

  -- Clause 2 negative: NEW illegally carries inline assertions too.
  v_result:=programacion.fn_input_validator_storage_compaction_check_v1(
    v_old,
    jsonb_set(
      v_new,'{validator_evidence}',
      (v_new->'validator_evidence')||jsonb_build_object('assertions',v_assert1)
    )
  );
  IF v_result->>'code'<>'R5C_STORAGE_SHAPE_INVALID' THEN
    RAISE EXCEPTION 'R5C_NEGATIVE_CLAUSE2_FAILED:%',v_result;
  END IF;

  -- Clause 3 negative: valid different assertion set rehydrates to different logical evidence.
  v_result:=programacion.fn_input_validator_storage_compaction_check_v1(
    v_old,
    jsonb_set(v_new,'{validator_evidence,assertion_set_sha256}',to_jsonb(v_sha2))
  );
  IF v_result->>'code'<>'R5C_REHYDRATED_EVIDENCE_MISMATCH' THEN
    RAISE EXCEPTION 'R5C_NEGATIVE_CLAUSE3_FAILED:%',v_result;
  END IF;

  -- Clause 4 negative: referenced assertion set does not exist.
  v_result:=programacion.fn_input_validator_storage_compaction_check_v1(
    v_old,
    jsonb_set(v_new,'{validator_evidence,assertion_set_sha256}',to_jsonb(v_missing))
  );
  IF v_result->>'code'<>'R5C_ASSERTION_SET_NOT_FOUND' THEN
    RAISE EXCEPTION 'R5C_NEGATIVE_CLAUSE4_FAILED:%',v_result;
  END IF;

  -- Clause 5 negative: validator_sha256 changed.
  v_result:=programacion.fn_input_validator_storage_compaction_check_v1(
    v_old,
    jsonb_set(v_new,'{validator_sha256}',to_jsonb(repeat('b',64)))
  );
  IF v_result->>'code'<>'R5C_VALIDATOR_SHA256_CHANGED' THEN
    RAISE EXCEPTION 'R5C_NEGATIVE_CLAUSE5_FAILED:%',v_result;
  END IF;
END
$r5c_storage_tests$;

-- Continuation-currentness gate: terminal receipts may only perform exact STORAGE_COMPACTION.
CREATE OR REPLACE FUNCTION programacion.fn_guard_input_governance_continuation_currentness_v1()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,programacion
AS $function$
DECLARE
  v_admission jsonb;
  v_compaction jsonb;
BEGIN
  IF tg_op='UPDATE'
     AND tg_table_schema='programacion'
     AND tg_table_name='input_family_assessments'
     AND old.validator_outcome<>'PENDING'
     AND (
       old.validator_outcome IS DISTINCT FROM new.validator_outcome
       OR old.validator_findings IS DISTINCT FROM new.validator_findings
       OR old.validator_evidence IS DISTINCT FROM new.validator_evidence
       OR old.validator_identity IS DISTINCT FROM new.validator_identity
       OR old.validator_sha256 IS DISTINCT FROM new.validator_sha256
       OR old.validator_assessed_at IS DISTINCT FROM new.validator_assessed_at
     ) THEN
    IF old.validator_evidence IS DISTINCT FROM new.validator_evidence THEN
      v_compaction:=programacion.fn_input_validator_storage_compaction_check_v1(
        to_jsonb(old),to_jsonb(new)
      );
      IF coalesce((v_compaction->>'allowed')::boolean,false) IS TRUE THEN
        RETURN new;
      END IF;
      RAISE EXCEPTION 'VALIDATOR_RECEIPT_IMMUTABLE:%:%',
        old.family_code,coalesce(v_compaction->>'code','STORAGE_COMPACTION_REJECTED');
    END IF;
    RAISE EXCEPTION 'VALIDATOR_RECEIPT_IMMUTABLE:%',old.family_code;
  END IF;

  v_admission:=programacion.fn_input_governance_continuation_currentness_v1(new.run_id);
  IF NOT coalesce((v_admission->>'continuation_current')::boolean,false) THEN
    RAISE EXCEPTION 'INPUT_GOVERNANCE_CONTINUATION_CURRENTNESS_BLOCKED:table=%:run=%:code=%',
      tg_table_name,new.run_id,coalesce(v_admission->>'code','CURRENTNESS_UNKNOWN');
  END IF;
  RETURN new;
END;
$function$;

-- Static final R5-C definitions. No pg_get_functiondef/replace/EXECUTE runtime patching.
CREATE OR REPLACE FUNCTION programacion.fn_guard_input_family_assessment_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion'
AS $function$
declare
  v_logical_validator_evidence jsonb;
  v_storage_compaction jsonb;
  v_payload jsonb; v_run_status text; v_run_sha text; v_curator_identity text; v_validator_identity text; v_validator_component_id bigint;
  v_version_id bigint; v_pantalla_id integer; v_run_contract_revision text; v_run_contract_sha text;
  v_contract_revision text; v_contract_payload jsonb; v_contract_sha text;
  v_current_manifest jsonb; v_current_sha text; v_bad_assertions integer; v_assertion jsonb; v_eval jsonb; v_governance_family boolean;
begin
  -- R5-C: terminal receipts remain immutable except for exact representation-only STORAGE_COMPACTION.
  if old.validator_outcome<>'PENDING'
     and new.validator_evidence is distinct from old.validator_evidence then
    v_storage_compaction:=programacion.fn_input_validator_storage_compaction_check_v1(
      to_jsonb(old),to_jsonb(new)
    );
    if coalesce((v_storage_compaction->>'allowed')::boolean,false) is true then
      return new;
    end if;
    raise exception 'VALIDATOR_RECEIPT_IMMUTABLE:%:%',
      old.family_code,
      coalesce(v_storage_compaction->>'code','STORAGE_COMPACTION_REJECTED');
  end if;

  if new.run_id is distinct from old.run_id or new.family_code is distinct from old.family_code or new.severity is distinct from old.severity or new.applicability is distinct from old.applicability or new.coverage_status is distinct from old.coverage_status or new.well_defined_status is distinct from old.well_defined_status or new.story_ready_status is distinct from old.story_ready_status or new.implementation_ready_status is distinct from old.implementation_ready_status or new.qa_ready_status is distinct from old.qa_ready_status or new.production_ready_status is distinct from old.production_ready_status or new.source_refs is distinct from old.source_refs or new.rationale is distinct from old.rationale or new.blockers is distinct from old.blockers or new.negative_requirements is distinct from old.negative_requirements or new.test_obligations is distinct from old.test_obligations or new.freshness is distinct from old.freshness or new.curator_evidence is distinct from old.curator_evidence or new.curator_sha256 is distinct from old.curator_sha256 or new.subject_coverage is distinct from old.subject_coverage or new.threat_coverage is distinct from old.threat_coverage or new.semantic_depth_sha256 is distinct from old.semantic_depth_sha256 or new.created_at is distinct from old.created_at then raise exception 'CURATOR_FIELDS_IMMUTABLE:%',old.family_code; end if;
  if old.validator_outcome<>'PENDING' then raise exception 'VALIDATOR_RECEIPT_IMMUTABLE:%',old.family_code; end if;
  if new.validator_outcome='PENDING' then raise exception 'VALIDATOR_UPDATE_MUST_BE_TERMINAL:%',old.family_code; end if;
  v_logical_validator_evidence:=programacion.fn_input_validator_evidence_rehydrate_v1(new.validator_evidence);
  select r.status,r.source_snapshot_sha256,r.curator_identity,r.validator_identity,r.validator_component_id,r.version_id,r.pantalla_id,r.contract_revision,r.contract_snapshot_sha256 into v_run_status,v_run_sha,v_curator_identity,v_validator_identity,v_validator_component_id,v_version_id,v_pantalla_id,v_run_contract_revision,v_run_contract_sha from programacion.input_readiness_runs r where r.id=old.run_id;
  if v_run_status<>'VALIDATING' then raise exception 'VALIDATOR_REQUIRES_VALIDATING_RUN:%',old.family_code; end if;
  if v_validator_component_id is null then raise exception 'RUN_VALIDATOR_COMPONENT_REQUIRED'; end if;
  if v_validator_identity is null or v_validator_identity=v_curator_identity then raise exception 'VALIDATOR_IDENTITY_NOT_INDEPENDENT'; end if;
  if new.validator_identity is distinct from v_validator_identity then raise exception 'VALIDATOR_IDENTITY_MISMATCH:%',old.family_code; end if;
  select c.especificacion->>'contract_revision',jsonb_build_object('id',c.id,'version_id',c.version_id,'contrato_codigo',c.contrato_codigo,'fail_closed',c.fail_closed,'estado',c.estado,'especificacion',c.especificacion) into v_contract_revision,v_contract_payload from programacion.contratos c where c.version_id=v_version_id and c.contrato_codigo='INPUT_READINESS_CONTRACT';
  v_contract_sha:=programacion.fn_v09_sha256_jsonb(v_contract_payload);
  if v_run_contract_revision is distinct from v_contract_revision or v_run_contract_sha is distinct from v_contract_sha then raise exception 'INPUT_READINESS_CONTRACT_PIN_STALE_DURING_VALIDATION:%',old.family_code; end if;
  if new.validator_assessed_at is null then new.validator_assessed_at:=now(); end if;
  if jsonb_typeof(v_logical_validator_evidence)<>'object' or v_logical_validator_evidence='{}'::jsonb then raise exception 'VALIDATOR_EVIDENCE_REQUIRED:%',old.family_code; end if;
  if v_logical_validator_evidence->>'source_snapshot_sha256' is distinct from v_run_sha then raise exception 'VALIDATOR_EVIDENCE_SOURCE_SNAPSHOT_MISMATCH:%',old.family_code; end if;
  if v_logical_validator_evidence->>'curator_sha256' is distinct from old.curator_sha256 then raise exception 'VALIDATOR_EVIDENCE_CURATOR_HASH_MISMATCH:%',old.family_code; end if;
  if coalesce((v_logical_validator_evidence->>'direct_source_readback')::boolean,false) is not true then raise exception 'VALIDATOR_DIRECT_SOURCE_READBACK_REQUIRED:%',old.family_code; end if;
  if v_logical_validator_evidence->>'execution_mode'<>'INDEPENDENT_VALIDATOR' then raise exception 'VALIDATOR_EXECUTION_MODE_REQUIRED:%',old.family_code; end if;
  if coalesce(v_logical_validator_evidence->>'contract_revision','')<>v_contract_revision then raise exception 'VALIDATOR_EVIDENCE_CONTRACT_REVISION_MISMATCH:%',old.family_code; end if;
  if v_contract_revision in ('5.7','5.8','5.9') and v_logical_validator_evidence->>'semantic_depth_sha256' is distinct from old.semantic_depth_sha256 then raise exception 'VALIDATOR_EVIDENCE_SEMANTIC_DEPTH_MISMATCH:%',old.family_code; end if;
  if jsonb_typeof(v_logical_validator_evidence->'assertions')<>'array' or jsonb_array_length(v_logical_validator_evidence->'assertions')=0 then raise exception 'VALIDATOR_ASSERTIONS_REQUIRED:%',old.family_code; end if;
  select count(*) into v_bad_assertions from jsonb_array_elements(v_logical_validator_evidence->'assertions') a where jsonb_typeof(a)<>'object' or not (a?'actual') or not (a?'expected') or not (a?'operator') or not (a?'source_ref') or not (a?'path');
  if v_bad_assertions>0 then raise exception 'VALIDATOR_ASSERTION_SCHEMA_INVALID:%',old.family_code; end if;
  v_governance_family:=old.family_code in ('SOURCE_AUTHORITY_PROVENANCE','FRESHNESS_INVALIDATION','NEGATIVE_REQUIREMENTS','CONFLICT_PRECEDENCE','APPLICABILITY_READINESS');
  for v_assertion in select value from jsonb_array_elements(v_logical_validator_evidence->'assertions') loop
    if v_assertion->'source_ref'->>'kind' in ('SCREEN','SCREEN_RULE_SET','SCREEN_STATE_SET','CURRENT_VISUAL_ARTIFACT','CAPABILITY_ABSENCE','SCREEN_CANONICAL_GRAPH') then if not (v_assertion->'source_ref'?'pantalla_id') or (v_assertion->'source_ref'->>'pantalla_id')::integer<>v_pantalla_id then raise exception 'VALIDATOR_SCREEN_SOURCE_REF_REQUIRES_EXPLICIT_PANTALLA_ID:%',old.family_code; end if; end if;
    if v_governance_family then if not programacion.fn_input_governance_assertion_relevant(old.family_code,v_assertion->'source_ref',v_assertion->'path') then raise exception 'GOVERNANCE_VALIDATOR_ASSERTION_REQUIRES_INDEPENDENT_AUTHORITY:%',old.family_code; end if; else if not programacion.fn_input_assertion_is_relevant(old.family_code,v_assertion->'source_ref',v_assertion->'path') then raise exception 'VALIDATOR_ASSERTION_NOT_RELEVANT:%',old.family_code; end if; end if;
    v_eval:=programacion.fn_input_evaluate_assertion(old.run_id,old.family_code,v_assertion); if new.validator_outcome='PASS' and coalesce((v_eval->>'passed')::boolean,false) is not true then raise exception 'VALIDATOR_ASSERTION_FAILED:%',old.family_code; end if;
  end loop;
  v_current_manifest:=programacion.fn_input_build_source_manifest(old.run_id); v_current_sha:=programacion.fn_v09_sha256_jsonb(v_current_manifest); if v_current_sha<>v_run_sha then raise exception 'SOURCE_SNAPSHOT_STALE_DURING_VALIDATION:%',old.family_code; end if;
  v_payload:=jsonb_build_object('curator_sha256',old.curator_sha256,'semantic_depth_sha256',old.semantic_depth_sha256,'source_snapshot_sha256',v_run_sha,'validator_outcome',new.validator_outcome,'validator_findings',new.validator_findings,'validator_evidence',v_logical_validator_evidence,'validator_identity',new.validator_identity,'validator_assessed_at',new.validator_assessed_at); new.validator_sha256:=programacion.fn_v09_sha256_jsonb(v_payload); return new;
end;
$function$;

CREATE OR REPLACE FUNCTION programacion.fn_guard_input_family_execution_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion'
AS $function$
declare
  v_logical_validator_evidence jsonb;
  v_validator_component_id bigint; v_curator_execution_id text; v_validator_execution_id text; v_assertion jsonb; v_eval jsonb; v_expected_result text;
begin
  if old.validator_outcome<>'PENDING' or new.validator_outcome='PENDING' then return new; end if;
  v_logical_validator_evidence:=programacion.fn_input_validator_evidence_rehydrate_v1(new.validator_evidence);
  select validator_component_id into v_validator_component_id from programacion.input_readiness_runs where id=old.run_id;
  v_curator_execution_id:=old.curator_evidence->>'execution_id';
  v_validator_execution_id:=v_logical_validator_evidence->>'execution_id';
  if nullif(btrim(coalesce(v_validator_execution_id,'')),'') is null then raise exception 'VALIDATOR_EXECUTION_ID_REQUIRED:%',old.family_code; end if;
  if v_validator_execution_id=v_curator_execution_id then raise exception 'VALIDATOR_EXECUTION_ID_NOT_INDEPENDENT:%',old.family_code; end if;
  if coalesce((v_logical_validator_evidence->>'component_id')::bigint,-1)<>v_validator_component_id then raise exception 'VALIDATOR_EVIDENCE_COMPONENT_MISMATCH:%',old.family_code; end if;
  if v_logical_validator_evidence->>'validated_curator_execution_id' is distinct from v_curator_execution_id then raise exception 'VALIDATOR_CURATOR_EXECUTION_BINDING_MISMATCH:%',old.family_code; end if;
  if jsonb_typeof(v_logical_validator_evidence->'assertions')<>'array' then raise exception 'VALIDATOR_ASSERTIONS_REQUIRED:%',old.family_code; end if;
  for v_assertion in select value from jsonb_array_elements(v_logical_validator_evidence->'assertions') loop
    if upper(coalesce(v_assertion->>'result','')) not in ('PASS','FAIL') then raise exception 'ASSERTION_RESULT_REQUIRED:%',old.family_code; end if;
    if nullif(coalesce(v_assertion->>'source_observed_sha256',''),'') is null then raise exception 'ASSERTION_SOURCE_SHA_REQUIRED:%',old.family_code; end if;
    v_eval:=programacion.fn_input_evaluate_assertion(old.run_id,old.family_code,v_assertion);
    v_expected_result:=case when coalesce((v_eval->>'passed')::boolean,false) then 'PASS' else 'FAIL' end;
    if upper(v_assertion->>'result')<>v_expected_result then raise exception 'ASSERTION_STORED_RESULT_MISMATCH:%',old.family_code; end if;
    if v_assertion->>'source_observed_sha256' is distinct from v_eval->>'source_observed_sha256' then raise exception 'ASSERTION_STORED_SOURCE_SHA_MISMATCH:%',old.family_code; end if;
    if new.validator_outcome='PASS' and v_expected_result<>'PASS' then raise exception 'VALIDATOR_PASS_CONTAINS_FAILED_ASSERTION:%',old.family_code; end if;
  end loop;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION programacion.fn_guard_input_validator_semantic_coherence_v512()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion'
AS $function$
declare
  v_logical_validator_evidence jsonb;
  v_revision text;
  v_version_id bigint;
  v_pantalla_id integer;
  v_assertion jsonb;
  v_eval jsonb;
  v_positive_requirement boolean := false;
  v_na_authority jsonb;
  v_blocker jsonb;
  v_false_missing boolean := false;
  v_graph jsonb;
  v_rules jsonb;
  v_otp_present boolean := false;
  v_a11y_core_complete boolean := false;
begin
  if old.validator_outcome<>'PENDING' or new.validator_outcome='PENDING' then return new; end if;
  v_logical_validator_evidence:=programacion.fn_input_validator_evidence_rehydrate_v1(new.validator_evidence);
  select contract_revision,version_id,pantalla_id into v_revision,v_version_id,v_pantalla_id
  from programacion.input_readiness_runs where id=old.run_id;
  if (v_revision is null or v_revision not in ('5.12','5.13')) then return new; end if;

  if jsonb_typeof(v_logical_validator_evidence->'assertions')='array' then
    for v_assertion in select value from jsonb_array_elements(v_logical_validator_evidence->'assertions')
    loop
      if coalesce(v_assertion->>'operator','')='CONTAINS'
         and jsonb_typeof(v_assertion->'expected')='array'
         and jsonb_array_length(v_assertion->'expected')>0
         and coalesce(v_assertion->'source_ref'->>'kind','') in ('SCREEN_CANONICAL_GRAPH','SCREEN_RULE_SET','RULE','SECURITY_POLICY_SET','SCREEN_STATE_SET') then
        v_eval:=programacion.fn_input_evaluate_assertion(old.run_id,old.family_code,v_assertion);
        if coalesce((v_eval->>'passed')::boolean,false) is true then v_positive_requirement:=true; end if;
      end if;
    end loop;
  end if;

  if new.validator_outcome='PASS' and old.applicability='NOT_APPLICABLE' then
    v_na_authority:=programacion.fn_input_na_positive_authority_v512(old.family_code,v_pantalla_id,v_version_id);
    if coalesce((v_na_authority->>'qualified')::boolean,false) is not true then
      raise exception 'V512_VALIDATOR_NA_WITHOUT_POSITIVE_EXCLUSION:%:%',v_pantalla_id,old.family_code;
    end if;
  end if;

  if new.validator_outcome='PASS' and v_positive_requirement then
    if old.family_code in ('REDUCED_MOTION','FORCED_COLORS_CONTRAST') then
      if old.applicability<>'APPLICABLE' or old.coverage_status<>'COMPLETE' or old.well_defined_status<>'COMPLETE' then
        raise exception 'V512_VALIDATOR_SOURCE_CANDIDATE_REQUIREMENT_SEMANTICS_MISMATCH:%:% expected=APPLICABLE/COMPLETE/COMPLETE actual=%/%/%',v_pantalla_id,old.family_code,old.applicability,old.coverage_status,old.well_defined_status;
      end if;
    elsif old.family_code='THEME_LIGHT_DARK_SYSTEM' then
      if old.applicability<>'APPLICABLE' or old.coverage_status not in ('PARTIAL','COMPLETE') or old.well_defined_status not in ('PARTIAL','COMPLETE') then
        raise exception 'V512_VALIDATOR_THEME_SEMANTICS_MISMATCH:% actual=%/%/%',v_pantalla_id,old.applicability,old.coverage_status,old.well_defined_status;
      end if;
    end if;

    for v_blocker in select value from jsonb_array_elements(coalesce(old.blockers,'[]'::jsonb))
    loop
      if (old.family_code='REDUCED_MOTION' and v_blocker->>'code'='REDUCED_MOTION_REQUIREMENT_MISSING')
         or (old.family_code='FORCED_COLORS_CONTRAST' and v_blocker->>'code'='FORCED_COLORS_REQUIREMENT_MISSING')
         or (old.family_code='THEME_LIGHT_DARK_SYSTEM' and v_blocker->>'code'='THEME_REQUIREMENTS_NOT_LINKED') then
        v_false_missing:=true;
      end if;
    end loop;
    if v_false_missing then raise exception 'V512_VALIDATOR_FALSE_MISSING_BLOCKER_CONTRADICTS_SOURCE:%:%',v_pantalla_id,old.family_code; end if;
  end if;

  v_graph:=programacion.fn_input_screen_canonical_graph(v_pantalla_id,v_version_id);
  v_rules:=coalesce(v_graph->'canonical_contract'->'rules','[]'::jsonb);

  if new.validator_outcome='PASS' and old.family_code='ACCESSIBILITY' then
    select count(distinct r->>'rule_code')=4 into v_a11y_core_complete
    from jsonb_array_elements(v_rules) r
    where r->>'rule_code' in ('B2B-RULE-A11Y-001','B2B-RULE-A11Y-002','B2B-RULE-A11Y-003','B2B-RULE-A11Y-004');
    if v_a11y_core_complete and (old.coverage_status<>'COMPLETE' or old.well_defined_status<>'COMPLETE') then
      raise exception 'V512_VALIDATOR_ACCESSIBILITY_CORE_PRESENT_BUT_CANDIDATE_INCOMPLETE:%',v_pantalla_id;
    end if;
  end if;

  if new.validator_outcome='PASS' and old.family_code='MFA_OTP_SSO' then
    select exists(
      select 1 from jsonb_array_elements(v_rules) r
      where (r->'config' ? 'otp_operation_id') or (r->'config' ? 'otp_policy_id') or (r->'config' ? 'email_otp_policy_code')
    ) into v_otp_present;
    if v_otp_present and old.applicability='NOT_APPLICABLE' then
      raise exception 'V512_VALIDATOR_OTP_PRESENT_BUT_FAMILY_NOT_APPLICABLE:%',v_pantalla_id;
    end if;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION programacion.fn_input_auth006_build_assertions(p_run_id bigint, p_seed_run_id bigint, p_family_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion'
AS $function$
declare specs jsonb; olda jsonb; tpl jsonb; reb jsonb; outj jsonb:='[]'::jsonb;
begin
  case p_family_code
    when 'SCREEN_IDENTITY' then specs:=jsonb_build_array(jsonb_build_object('source_ref',jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',56),'path',jsonb_build_array('observed','screen_code'),'operator','EQ','expected','B2B-AUTH-006'));
    when 'OBJECTIVE_OUTCOMES' then specs:=jsonb_build_array(jsonb_build_object('source_ref',jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',56),'path',jsonb_build_array('observed','canonical_contract','context','screen','objective'),'operator','EQ','expected','Validar la identidad mediante OTP de recuperación y habilitar exclusivamente un contexto PASSWORD_UPDATE_ONLY antes de B2B-AUTH-003.'));
    when 'FIELDS' then specs:=jsonb_build_array(jsonb_build_object('source_ref',jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',56),'path',jsonb_build_array('observed','canonical_contract','fields'),'operator','CONTAINS','expected','[{"field_id":306,"field_code":"B2B_FLD_RECOVERY_EMAIL_OTP_CODE","required":true,"sensitive":true,"logs_allowed":false,"analytics_allowed":false,"retention_class":"TRANSIENT","ui":{"context_key":"PASSWORD_RECOVERY_OTP_CODE","component_token_id":40,"component_token_code":"otp_pin"}}]'::jsonb));
    when 'VALIDATIONS' then specs:=jsonb_build_array(jsonb_build_object('source_ref',jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',56),'path',jsonb_build_array('observed','canonical_contract','fields'),'operator','CONTAINS','expected','[{"field_id":306,"validations":[{"validation_id":101,"validation_code":"B2B_VAL_RECOVERY_EMAIL_OTP_REQUIRED","blocking":true,"config":{"required":true}},{"validation_id":102,"validation_code":"B2B_VAL_RECOVERY_EMAIL_OTP_POLICY","blocking":true,"config":{"otp_policy_id":2,"relation_key":"otp_policy_id","server_side_validation":"REQUIRED","numeric_thresholds_in_validation":"DENY"}}]}]'::jsonb));
    when 'ACTIONS' then specs:=jsonb_build_array(jsonb_build_object('source_ref',jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',56),'path',jsonb_build_array('observed','canonical_contract','rules'),'operator','CONTAINS','expected','[{"rule_code":"B2B-RULE-AUTH-037","config":{"otp_policy_id":2,"verify_screen_id":56,"success_scope":"PASSWORD_UPDATE_ONLY","server_side_generation":"REQUIRED","server_side_verification":"REQUIRED","mfa_satisfaction":"DENY","operational_session_creation":"DENY"}},{"rule_code":"B2B-RULE-AUTH-038","config":{"otp_policy_id":2,"verify_screen_id":56,"hardcoded_expiry":"DENY","hardcoded_resend_countdown":"DENY"}}]'::jsonb));
    when 'ROUTING_NAVIGATION' then specs:=jsonb_build_array(
      jsonb_build_object('source_ref',jsonb_build_object('kind','ROUTE_SET','ids',jsonb_build_array(11)),'path',jsonb_build_array('observed'),'operator','CONTAINS','expected','[{"route_id":11,"route_code":"B2B_ROUTE_AUTH_RECOVERY_VERIFY","pantalla_id":56,"route_pattern":"/b2b/auth/verificar-recuperacion","authentication_required":false}]'::jsonb),
      jsonb_build_object('source_ref',jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',56),'path',jsonb_build_array('observed','canonical_contract','rules'),'operator','CONTAINS','expected','[{"rule_code":"B2B-RULE-AUTH-029","config":{"recovery_verify_route_id":11,"recovery_verify_screen_id":56,"password_update_screen_id":53,"client_context_promotion":"DENY","grant_mode":"OPAQUE_ONE_TIME_SERVER_VERIFIED"}}]'::jsonb));
    when 'PROFILES' then specs:=jsonb_build_array(jsonb_build_object('source_ref',jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',56),'path',jsonb_build_array('observed','canonical_contract','profiles'),'operator','ARRAY_LENGTH_EQ','expected',0));
    when 'SESSION' then specs:=jsonb_build_array(jsonb_build_object('source_ref',jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',56),'path',jsonb_build_array('observed','canonical_contract','rules'),'operator','CONTAINS','expected','[{"rule_code":"B2B-RULE-AUTH-037","config":{"operational_session_creation":"DENY","mfa_satisfaction":"DENY"}},{"rule_code":"B2B-RULE-AUTH-029","config":{"operational_authorization_before_completion":"DENY","client_context_promotion":"DENY"}}]'::jsonb));
    when 'MFA_OTP_SSO' then specs:=jsonb_build_array(jsonb_build_object('source_ref',jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',56),'path',jsonb_build_array('observed','canonical_contract','rules'),'operator','CONTAINS','expected','[{"rule_code":"B2B-RULE-AUTH-037","config":{"otp_policy_id":2,"otp_operation_id":5,"delivery_channel":"EMAIL","delivery_provider":"BREVO","server_side_verification":"REQUIRED","mfa_satisfaction":"DENY"}}]'::jsonb));
    when 'PRIVACY_PII' then specs:=jsonb_build_array(
      jsonb_build_object('source_ref',jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',56),'path',jsonb_build_array('observed','canonical_contract','fields'),'operator','CONTAINS','expected','[{"field_id":306,"sensitive":true,"logs_allowed":false,"analytics_allowed":false,"masking_rule":"MASK_FULL","retention_class":"TRANSIENT","pii_classification":"SENSITIVE"}]'::jsonb),
      jsonb_build_object('source_ref',jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',56),'path',jsonb_build_array('observed','canonical_contract','rules'),'operator','CONTAINS','expected','[{"rule_code":"B2B-RULE-AUTH-037","config":{"otp_value_logs":"DENY","otp_value_analytics":"DENY"}}]'::jsonb));
    when 'ERRORS' then specs:=jsonb_build_array(
      jsonb_build_object('source_ref',jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',56),'path',jsonb_build_array('observed','canonical_contract','rules'),'operator','CONTAINS','expected','[{"rule_code":"B2B-RULE-AUTH-029","config":{"invalid_recovery_error_id":39}}]'::jsonb),
      jsonb_build_object('source_ref',jsonb_build_object('kind','ERROR_SET','ids',jsonb_build_array(39)),'path',jsonb_build_array('observed'),'operator','CONTAINS','expected','[{"error_id":39,"error_code":"LF-B2B-AUTH-006","user_title":"Enlace de recuperación no válido","user_message_template":"El enlace de recuperación ya no es válido o venció.","action_label":"Solicitar otro enlace"}]'::jsonb));
    when 'UI_MESSAGES' then specs:=jsonb_build_array(
      jsonb_build_object('source_ref',jsonb_build_object('kind','MESSAGE_SET','ids',jsonb_build_array(17)),'path',jsonb_build_array('observed'),'operator','CONTAINS','expected','[{"message":{"message_id":17,"message_code":"MSG-B2B-AUTH-RECOVERY-REQUESTED","body_template":"Si existe una cuenta asociada a ese correo, recibirás un código de verificación para continuar con la recuperación."},"screen_links":[{"pantalla_id":56,"context_key":"RECOVERY_OTP_ENTRY_NOTICE"}]}]'::jsonb),
      jsonb_build_object('source_ref',jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',56),'path',jsonb_build_array('observed','canonical_contract','fields'),'operator','CONTAINS','expected','[{"field_id":306,"validations":[{"validation_id":101,"message":null},{"validation_id":102,"message":null}]}]'::jsonb));
    when 'DEPENDENCIES' then specs:=jsonb_build_array(jsonb_build_object('source_ref',jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',56),'path',jsonb_build_array('observed','canonical_contract','context','screen','dependencies'),'operator','CONTAINS','expected','["SEC-B2B-PASSWORD-CREDENTIAL","SEC-B2B-AUTH-PROVIDER-ARCHITECTURE","SEC-B2B-AUTH-FAIL-CLOSED","OTP_POL_B2B_AUTH_EMAIL_BREVO"]'::jsonb));
    when 'RUNTIME_CONFIG' then specs:=jsonb_build_array(jsonb_build_object('source_ref',jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',56),'path',jsonb_build_array('observed','canonical_contract','rules'),'operator','CONTAINS','expected','[{"rule_code":"B2B-RULE-AUTH-037","config":{"delivery_provider":"BREVO","delivery_provider_status":"PENDING_CREDENTIALS_IMPLEMENTATION","production_authorized":false,"server_side_generation":"REQUIRED","server_side_verification":"REQUIRED"}}]'::jsonb));
    when 'VISUAL_EVIDENCE' then specs:=jsonb_build_array(jsonb_build_object('source_ref',jsonb_build_object('kind','CURRENT_VISUAL_ARTIFACT','pantalla_id',56),'path',jsonb_build_array('observed'),'operator','CONTAINS','expected','[{"artifact":{"id":14,"pantalla_id":56,"artifact_code":"B2B-AUTH-006-DESKTOP-LIGHT-CANDIDATO-VISUAL-V01","mime_type":"image/png","is_current":true,"storage_provider":"GOOGLE_DRIVE","storage_object_path":"18T1XH6oMavtbECVFu_IstKM8e_GIO38B"}}]'::jsonb));
    else specs:=null;
  end case;
  if specs is not null then return programacion.fn_input_rebind_assertion_specs(p_run_id,p_family_code,specs); end if;
  for olda in select x.value from programacion.input_family_assessments a cross join lateral jsonb_array_elements(programacion.fn_input_validator_evidence_rehydrate_v1(a.validator_evidence)->'assertions') x(value) where a.run_id=p_seed_run_id and a.family_code=p_family_code loop
    tpl:=olda-'actual'-'result'-'source_observed_sha256'; if tpl->'source_ref' ? 'pantalla_id' then tpl:=jsonb_set(tpl,'{source_ref,pantalla_id}','56'::jsonb,true); end if;
    reb:=programacion.fn_input_rebind_assertion(p_run_id,p_family_code,tpl); if reb->>'result'<>'PASS' then raise exception 'AUTH006_INHERITED_ASSERTION_FAILED family=% source=% path=% expected=% actual=%',p_family_code,reb->'source_ref',reb->'path',reb->'expected',reb->'actual'; end if; outj:=outj||jsonb_build_array(reb);
  end loop;
  if jsonb_array_length(outj)=0 then raise exception 'AUTH006_ASSERTIONS_EMPTY:%',p_family_code; end if;
  return outj;
end$function$;

CREATE OR REPLACE FUNCTION programacion.fn_input_owner_decision_assertions(p_new_run_id bigint, p_parent_run_id bigint, p_family_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion', 'lf_ops'
AS $function$
declare
  v_screen integer;
  v_specs jsonb;
  v_old jsonb;
  v_rebound jsonb;
  v_out jsonb:='[]'::jsonb;
  v_terms bigint;
  v_privacy bigint;
  v_support bigint;
begin
  select pantalla_id into v_screen from programacion.input_readiness_runs where id=p_new_run_id;
  if v_screen is null then raise exception 'OWNER_DECISION_RUN_NOT_FOUND:%',p_new_run_id; end if;

  select route_id into v_terms from lf_ops.rutas where route_code='B2B_ROUTE_LEGAL_TERMS';
  select route_id into v_privacy from lf_ops.rutas where route_code='B2B_ROUTE_LEGAL_PRIVACY';
  select route_id into v_support from lf_ops.rutas where route_code='B2B_ROUTE_SUPPORT';

  if v_screen=51 and p_family_code='ACTIONS' then
    v_specs:=jsonb_build_array(
      jsonb_build_object(
        'source_ref',jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',51),
        'path',jsonb_build_array('observed','canonical_contract','rules'),
        'operator','CONTAINS',
        'expected',jsonb_build_array(
          jsonb_build_object('rule_code','B2B-RULE-AUTH-036','config',jsonb_build_object('actions',jsonb_build_array(
            jsonb_build_object('action_code','OPEN_TERMS','route_id',v_terms,'target_status','APPROVED_B2B_CANONICAL'),
            jsonb_build_object('action_code','OPEN_PRIVACY','route_id',v_privacy,'target_status','APPROVED_B2B_CANONICAL'),
            jsonb_build_object('action_code','CONTACT_SUPPORT','route_id',v_support,'target_status','APPROVED_B2B_CANONICAL')
          ))),
          jsonb_build_object('rule_code','B2B-RULE-NAV-LEGAL-001','pending_decision',false,'config',jsonb_build_object(
            'route_target_status','APPROVED_B2B_CANONICAL','public_front_reuse','DENY','blocks_story',false,'blocks_implementation',false
          ))
        )
      )
    );
  elsif v_screen=51 and p_family_code='ROUTING_NAVIGATION' then
    v_specs:=jsonb_build_array(
      jsonb_build_object(
        'source_ref',jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',51),
        'path',jsonb_build_array('observed','canonical_contract','rules'),
        'operator','CONTAINS',
        'expected',jsonb_build_array(
          jsonb_build_object('rule_code','B2B-RULE-NAV-LEGAL-001','pending_decision',false,'config',jsonb_build_object(
            'current_b2b_route_ids',jsonb_build_array(v_terms,v_privacy,v_support),
            'route_target_status','APPROVED_B2B_CANONICAL','public_front_reuse','DENY'
          ))
        )
      ),
      jsonb_build_object(
        'source_ref',jsonb_build_object('kind','ROUTE_SET','ids',jsonb_build_array(9,10,12,13,v_terms,v_privacy,v_support)),
        'path',jsonb_build_array('observed'),
        'operator','CONTAINS',
        'expected',jsonb_build_array(
          jsonb_build_object('route_id',v_terms,'route_code','B2B_ROUTE_LEGAL_TERMS','authentication_required',false),
          jsonb_build_object('route_id',v_privacy,'route_code','B2B_ROUTE_LEGAL_PRIVACY','authentication_required',false),
          jsonb_build_object('route_id',v_support,'route_code','B2B_ROUTE_SUPPORT','authentication_required',false)
        )
      )
    );
  elsif v_screen=52 and p_family_code='SESSION' then
    v_specs:=jsonb_build_array(
      jsonb_build_object(
        'source_ref',jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',52),
        'path',jsonb_build_array('observed','canonical_contract','rules'),
        'operator','CONTAINS',
        'expected',jsonb_build_array(
          jsonb_build_object('rule_code','B2B-RULE-AUTH-028','config',jsonb_build_object(
            'operational_session_creation','DENY',
            'authentication_completion','DENY',
            'operational_access_grant','DENY',
            'success_context_scope','PASSWORD_RECOVERY_CHALLENGE_ONLY'
          ))
        )
      )
    );
  elsif v_screen=54 and p_family_code='ERRORS' then
    v_specs:=jsonb_build_array(
      jsonb_build_object(
        'source_ref',jsonb_build_object('kind','ERROR_SET','ids',jsonb_build_array(40)),
        'path',jsonb_build_array('observed'),
        'operator','CONTAINS',
        'expected',jsonb_build_array(jsonb_build_object(
          'error_id',40,
          'error_code','LF-B2B-AUTH-007',
          'user_title','Código no válido',
          'user_message_template','El código ingresado no es válido o ya venció. Solicita uno nuevo e inténtalo nuevamente.',
          'suggested_action','Solicita un nuevo código de verificación para continuar.',
          'action_label','Reenviar código'
        ))
      )
    );
  elsif v_screen=56 and p_family_code='ERRORS' then
    v_specs:=jsonb_build_array(
      jsonb_build_object(
        'source_ref',jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',56),
        'path',jsonb_build_array('observed','canonical_contract','rules'),
        'operator','CONTAINS',
        'expected',jsonb_build_array(jsonb_build_object('rule_code','B2B-RULE-AUTH-029','config',jsonb_build_object('invalid_recovery_error_id',39)))
      ),
      jsonb_build_object(
        'source_ref',jsonb_build_object('kind','ERROR_SET','ids',jsonb_build_array(39)),
        'path',jsonb_build_array('observed'),
        'operator','CONTAINS',
        'expected',jsonb_build_array(jsonb_build_object(
          'error_id',39,
          'error_code','LF-B2B-AUTH-006',
          'user_title','Código de recuperación no válido',
          'user_message_template','El código ingresado no es válido o ya venció. Solicita un nuevo código para continuar.',
          'suggested_action','Solicita un nuevo código de recuperación para continuar.',
          'action_label','Reenviar código'
        ))
      )
    );
  else
    v_specs:=null;
  end if;

  if v_specs is not null then
    return programacion.fn_input_rebind_assertion_specs(p_new_run_id,p_family_code,v_specs);
  end if;

  for v_old in
    select x.value
    from programacion.input_family_assessments a
    cross join lateral jsonb_array_elements(programacion.fn_input_validator_evidence_rehydrate_v1(a.validator_evidence)->'assertions') x(value)
    where a.run_id=p_parent_run_id and a.family_code=p_family_code
  loop
    v_rebound:=programacion.fn_input_rebind_assertion(p_new_run_id,p_family_code,v_old);
    if v_rebound->>'result'<>'PASS' then
      raise exception 'OWNER_DECISION_REBOUND_FAILED screen=% family=% source=% path=% expected=% actual=%',v_screen,p_family_code,v_rebound->'source_ref',v_rebound->'path',v_rebound->'expected',v_rebound->'actual';
    end if;
    v_out:=v_out||jsonb_build_array(v_rebound);
  end loop;
  if jsonb_array_length(v_out)=0 then raise exception 'OWNER_DECISION_ASSERTIONS_EMPTY:%:%',v_screen,p_family_code; end if;
  return v_out;
end;
$function$;

CREATE OR REPLACE FUNCTION programacion.fn_input_v58_build_assertions(p_new_run_id bigint, p_parent_run_id bigint, p_family_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion'
AS $function$
declare
  v_pantalla_id integer;
  v_old jsonb;
  v_tpl jsonb;
  v_rebound jsonb;
  v_out jsonb := '[]'::jsonb;
begin
  select pantalla_id into v_pantalla_id
  from programacion.input_readiness_runs where id=p_new_run_id;
  if v_pantalla_id is null then raise exception 'V58_ASSERTION_NEW_RUN_NOT_FOUND:%',p_new_run_id; end if;

  for v_old in
    select x.value
    from programacion.input_family_assessments a
    cross join lateral jsonb_array_elements(programacion.fn_input_validator_evidence_rehydrate_v1(a.validator_evidence)->'assertions') x(value)
    where a.run_id=p_parent_run_id and a.family_code=p_family_code
  loop
    if v_pantalla_id=51 and p_family_code='VISUAL_EVIDENCE'
       and v_old->'source_ref'->>'kind'='CURRENT_VISUAL_ARTIFACT' then
      v_tpl:=jsonb_build_object(
        'source_ref',jsonb_build_object('kind','CURRENT_VISUAL_ARTIFACT','pantalla_id',51),
        'path',jsonb_build_array('observed'),'operator','CONTAINS',
        'expected',jsonb_build_array(
          jsonb_build_object('artifact',jsonb_build_object('pantalla_id',51,'is_current',true,'status','CANDIDATO_VISUAL','storage_provider','GOOGLE_DRIVE','storage_metadata',jsonb_build_object('variant_code','B2B-AUTH-001-DESKTOP-LIGHT','canonical_canvas',true))),
          jsonb_build_object('artifact',jsonb_build_object('pantalla_id',51,'is_current',true,'status','CANDIDATO_VISUAL','storage_provider','GOOGLE_DRIVE','storage_metadata',jsonb_build_object('variant_code','B2B-AUTH-001-TABLET-LIGHT','canonical_canvas',true))),
          jsonb_build_object('artifact',jsonb_build_object('pantalla_id',51,'is_current',true,'status','CANDIDATO_VISUAL','storage_provider','GOOGLE_DRIVE','storage_metadata',jsonb_build_object('variant_code','B2B-AUTH-001-MOBILE-LIGHT','canonical_canvas',true)))
        )
      );
    else
      v_tpl:=programacion.fn_input_v512_assertion_template(v_pantalla_id,p_family_code,v_old);
    end if;
    v_rebound:=programacion.fn_input_rebind_assertion(p_new_run_id,p_family_code,v_tpl);
    if v_rebound->>'result'<>'PASS' then
      raise exception 'V58_REBOUND_ASSERTION_FAILED screen=% family=% source=% path=%',v_pantalla_id,p_family_code,v_rebound->'source_ref',v_rebound->'path';
    end if;
    v_out:=v_out || jsonb_build_array(v_rebound);
  end loop;

  if jsonb_array_length(v_out)=0 then raise exception 'V58_ASSERTION_SET_EMPTY:%:%',v_pantalla_id,p_family_code; end if;
  return v_out;
end;
$function$;

-- Postconditions: exact final definitions are part of the governed artifact.
DO $r5c_postcheck$
DECLARE
  v_actual text;
BEGIN
  v_actual:=md5(pg_get_functiondef('programacion.fn_guard_input_family_assessment_update()'::regprocedure));
  IF v_actual IS DISTINCT FROM '3992ea214300ed7a4c444667d9927f1e' THEN
    RAISE EXCEPTION 'R5C_FINAL_MD5_MISMATCH function=family_assessment_update expected=% actual=%',
      '3992ea214300ed7a4c444667d9927f1e',coalesce(v_actual,'<NULL>');
  END IF;

  v_actual:=md5(pg_get_functiondef('programacion.fn_guard_input_family_execution_update()'::regprocedure));
  IF v_actual IS DISTINCT FROM '19760955ab8271b6edbfb4c8a3b2380d' THEN
    RAISE EXCEPTION 'R5C_FINAL_MD5_MISMATCH function=family_execution_update expected=% actual=%',
      '19760955ab8271b6edbfb4c8a3b2380d',coalesce(v_actual,'<NULL>');
  END IF;

  v_actual:=md5(pg_get_functiondef('programacion.fn_guard_input_governance_continuation_currentness_v1()'::regprocedure));
  IF v_actual IS DISTINCT FROM '7f1172972e08b70df9328799c4118955' THEN
    RAISE EXCEPTION 'R5C_FINAL_MD5_MISMATCH function=continuation_currentness expected=% actual=%',
      '7f1172972e08b70df9328799c4118955',coalesce(v_actual,'<NULL>');
  END IF;

  v_actual:=md5(pg_get_functiondef('programacion.fn_guard_input_validator_semantic_coherence_v512()'::regprocedure));
  IF v_actual IS DISTINCT FROM '5f47ef6f1e0a8d5ee8ccd830ef9ba297' THEN
    RAISE EXCEPTION 'R5C_FINAL_MD5_MISMATCH function=semantic_coherence_v512 expected=% actual=%',
      '5f47ef6f1e0a8d5ee8ccd830ef9ba297',coalesce(v_actual,'<NULL>');
  END IF;

  v_actual:=md5(pg_get_functiondef('programacion.fn_input_auth006_build_assertions(bigint,bigint,text)'::regprocedure));
  IF v_actual IS DISTINCT FROM 'fcbe577977533315efa654e37f6fedaf' THEN
    RAISE EXCEPTION 'R5C_FINAL_MD5_MISMATCH function=auth006_build_assertions expected=% actual=%',
      'fcbe577977533315efa654e37f6fedaf',coalesce(v_actual,'<NULL>');
  END IF;

  v_actual:=md5(pg_get_functiondef('programacion.fn_input_owner_decision_assertions(bigint,bigint,text)'::regprocedure));
  IF v_actual IS DISTINCT FROM 'faaf7a7e0b6da0ac40eb740ecfda064a' THEN
    RAISE EXCEPTION 'R5C_FINAL_MD5_MISMATCH function=owner_decision_assertions expected=% actual=%',
      'faaf7a7e0b6da0ac40eb740ecfda064a',coalesce(v_actual,'<NULL>');
  END IF;

  v_actual:=md5(pg_get_functiondef('programacion.fn_input_v58_build_assertions(bigint,bigint,text)'::regprocedure));
  IF v_actual IS DISTINCT FROM 'af95bfa42f649250c3585db9a6cb35fb' THEN
    RAISE EXCEPTION 'R5C_FINAL_MD5_MISMATCH function=v58_build_assertions expected=% actual=%',
      'af95bfa42f649250c3585db9a6cb35fb',coalesce(v_actual,'<NULL>');
  END IF;
END
$r5c_postcheck$;
