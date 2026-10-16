-- IG M10.7/C: one evaluator call per family validation.
-- Preserve the execution guard's independence checks and the final guard's
-- source/resolution, result, SHA and outcome checks. Never disable triggers.
DO $guard$
BEGIN
 IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo IN
  ('IG-M107-B-ACTIVE-GUARD-ONEPASS-033','IG-M107-B-POSITIVE-RUN-BUNDLE-032'))<>2
 THEN RAISE EXCEPTION 'IG_M107_C_EKB_PRIOR_PROOF_MISSING'; END IF;
 IF (SELECT md5(pg_get_functiondef(p.oid)) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='programacion' AND p.proname='fn_guard_input_family_assessment_update') IS DISTINCT FROM 'fb1d1cd7013f572cd837501b5b120750' THEN RAISE EXCEPTION 'IG_M107_C_FUNCTION_DRIFT:fn_guard_input_family_assessment_update'; END IF;
IF (SELECT md5(pg_get_functiondef(p.oid)) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='programacion' AND p.proname='fn_guard_input_family_execution_update') IS DISTINCT FROM '19760955ab8271b6edbfb4c8a3b2380d' THEN RAISE EXCEPTION 'IG_M107_C_FUNCTION_DRIFT:fn_guard_input_family_execution_update'; END IF;
 IF (SELECT count(*) FROM pg_trigger t JOIN pg_proc p ON p.oid=t.tgfoid WHERE p.proname IN
 ('fn_guard_input_family_execution_update','fn_guard_input_family_assessment_update') AND t.tgenabled IN ('O','A') AND NOT t.tgisinternal)<>2
 THEN RAISE EXCEPTION 'IG_M107_C_TRIGGER_BINDING_DRIFT'; END IF;
 IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo='IG-M107-C-ONE-EVALUATION-034')<>0
 THEN RAISE EXCEPTION 'IG_M107_C_EKB_EXISTS'; END IF;
END $guard$;
CREATE OR REPLACE FUNCTION programacion.fn_guard_input_family_execution_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion'
AS $function$
declare
  v_logical_validator_evidence jsonb;
  v_validator_component_id bigint; v_curator_execution_id text; v_validator_execution_id text; v_assertion jsonb;
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
    -- The mandatory final family guard independently re-evaluates this assertion
    -- from live SQL exactly once, and checks both result and source SHA.
    -- This earlier execution guard still requires assertion shape and execution binding.
  end loop;
  return new;
end;
$function$;
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
  v_bundle jsonb; v_bad_assertions integer; v_assertion jsonb; v_eval jsonb; v_expected_result text; v_governance_family boolean;
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
  v_bundle:=programacion.fn_ig_m107_manifest_guard_bundle_v1(old.run_id);
  IF coalesce((v_bundle#>>'{g1,continuation_current}')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'INPUT_GOVERNANCE_CONTINUATION_CURRENTNESS_BLOCKED:table=%:run=%:code=%',
      TG_TABLE_NAME,old.run_id,coalesce(v_bundle#>>'{g1,code}','CURRENTNESS_UNKNOWN');
  END IF;
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
    -- Same source evaluator and independent relevance gate, but one SQL resolution.
    v_eval:=programacion.fn_input_evaluate_assertion(old.run_id,old.family_code,v_assertion);
    v_expected_result:=case when coalesce((v_eval->>'passed')::boolean,false) then 'PASS' else 'FAIL' end;
    if upper(v_assertion->>'result')<>v_expected_result then raise exception 'ASSERTION_STORED_RESULT_MISMATCH:%',old.family_code; end if;
    if v_assertion->>'source_observed_sha256' is distinct from v_eval->>'source_observed_sha256' then raise exception 'ASSERTION_STORED_SOURCE_SHA_MISMATCH:%',old.family_code; end if;
    if new.validator_outcome='PASS' and v_expected_result<>'PASS' then raise exception 'VALIDATOR_PASS_CONTAINS_FAILED_ASSERTION:%',old.family_code; end if;
  end loop;
  IF coalesce((v_bundle->>'full_manifest_current')::boolean,false) IS NOT TRUE THEN raise exception 'SOURCE_SNAPSHOT_STALE_DURING_VALIDATION:%',old.family_code; END IF;
  v_payload:=jsonb_build_object('curator_sha256',old.curator_sha256,'semantic_depth_sha256',old.semantic_depth_sha256,'source_snapshot_sha256',v_run_sha,'validator_outcome',new.validator_outcome,'validator_findings',new.validator_findings,'validator_evidence',v_logical_validator_evidence,'validator_identity',new.validator_identity,'validator_assessed_at',new.validator_assessed_at); new.validator_sha256:=programacion.fn_v09_sha256_jsonb(v_payload); return new;
end;
$function$;
DO $post$
DECLARE v_execution text; v_final text;
BEGIN
 SELECT pg_get_functiondef('programacion.fn_guard_input_family_execution_update()'::regprocedure) INTO v_execution;
 SELECT pg_get_functiondef('programacion.fn_guard_input_family_assessment_update()'::regprocedure) INTO v_final;
 IF position('fn_input_evaluate_assertion(' in v_execution)>0
 OR (length(v_final)-length(replace(v_final,'fn_input_evaluate_assertion(','')))<>length('fn_input_evaluate_assertion(')
 OR position('ASSERTION_STORED_RESULT_MISMATCH:' in v_final)=0
 OR position('ASSERTION_STORED_SOURCE_SHA_MISMATCH:' in v_final)=0
 OR position('VALIDATOR_PASS_CONTAINS_FAILED_ASSERTION:' in v_final)=0
 THEN RAISE EXCEPTION 'IG_M107_C_EVAL_RELOCATION_SHAPE_FAILED'; END IF;
 IF (SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
   JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='programacion' AND c.relname='input_family_assessments'
   AND t.tgenabled IN ('O','A') AND NOT t.tgisinternal AND (t.tgtype & 16)=16)<>6
 THEN RAISE EXCEPTION 'IG_M107_C_TRIGGER_COUNT_CHANGED'; END IF;
END $post$;
