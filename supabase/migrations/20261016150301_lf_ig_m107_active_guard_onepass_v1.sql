-- M10.7 B: NO disabled triggers; existing three paths preserved.
DO $preflight$ BEGIN
 IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo IN ('IG-M107-B-POSITIVE-RUN-BUNDLE-032','IG-M107-B-ONEPASS-TIMING-031'))<>2
 THEN RAISE EXCEPTION 'IG_M107_B_PRIOR_EKB_INCOMPLETE'; END IF;
 IF (SELECT md5(pg_get_functiondef(p.oid)) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='programacion' AND p.proname='fn_guard_input_family_assessment_update') IS DISTINCT FROM '3992ea214300ed7a4c444667d9927f1e' THEN RAISE EXCEPTION 'IG_M107_B_GUARD_DRIFT:fn_guard_input_family_assessment_update'; END IF;
IF (SELECT md5(pg_get_functiondef(p.oid)) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='programacion' AND p.proname='fn_guard_input_gap_proposal_update_v512') IS DISTINCT FROM '3590db9dd48aa36725b0bd7c7975fa9c' THEN RAISE EXCEPTION 'IG_M107_B_GUARD_DRIFT:fn_guard_input_gap_proposal_update_v512'; END IF;
IF (SELECT md5(pg_get_functiondef(p.oid)) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='programacion' AND p.proname='fn_guard_input_governance_continuation_currentness_v1') IS DISTINCT FROM '4f2352389ca15561c6693f1e9a82867b' THEN RAISE EXCEPTION 'IG_M107_B_GUARD_DRIFT:fn_guard_input_governance_continuation_currentness_v1'; END IF;
 IF (SELECT count(*) FROM pg_trigger t JOIN pg_proc p ON t.tgfoid=p.oid WHERE p.proname='fn_guard_input_governance_continuation_currentness_v1' AND NOT t.tgisinternal AND t.tgenabled IN ('O','A'))<>3
 THEN RAISE EXCEPTION 'IG_M107_B_SHARED_GUARD_BINDING_CHANGED'; END IF;
END $preflight$;
CREATE OR REPLACE FUNCTION programacion.fn_guard_input_governance_continuation_currentness_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion'
AS $function$
DECLARE
  v_admission jsonb;
  v_compaction jsonb;
BEGIN
  IF tg_op='UPDATE'
     AND tg_table_schema='programacion'
     AND tg_table_name='input_family_assessments' THEN
    IF old.validator_outcome<>'PENDING'
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
  END IF;

  -- Only defer UPDATE admission to the mandatory final BEFORE UPDATE guard.
  -- The INSERT path (including chunk timings) retains full currentness here.
  IF TG_OP='UPDATE' AND TG_TABLE_SCHEMA='programacion'
    AND TG_TABLE_NAME IN ('input_family_assessments','input_gap_proposals') THEN
    RETURN NEW;
  END IF;
  v_admission:=programacion.fn_input_governance_continuation_currentness_v1(new.run_id);
  IF NOT coalesce((v_admission->>'continuation_current')::boolean,false) THEN
    RAISE EXCEPTION 'INPUT_GOVERNANCE_CONTINUATION_CURRENTNESS_BLOCKED:table=%:run=%:code=%',
      tg_table_name,new.run_id,coalesce(v_admission->>'code','CURRENTNESS_UNKNOWN');
  END IF;
  RETURN new;
END;
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
  v_bundle jsonb; v_bad_assertions integer; v_assertion jsonb; v_eval jsonb; v_governance_family boolean;
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
    v_eval:=programacion.fn_input_evaluate_assertion(old.run_id,old.family_code,v_assertion); if new.validator_outcome='PASS' and coalesce((v_eval->>'passed')::boolean,false) is not true then raise exception 'VALIDATOR_ASSERTION_FAILED:%',old.family_code; end if;
  end loop;
  IF coalesce((v_bundle->>'full_manifest_current')::boolean,false) IS NOT TRUE THEN raise exception 'SOURCE_SNAPSHOT_STALE_DURING_VALIDATION:%',old.family_code; END IF;
  v_payload:=jsonb_build_object('curator_sha256',old.curator_sha256,'semantic_depth_sha256',old.semantic_depth_sha256,'source_snapshot_sha256',v_run_sha,'validator_outcome',new.validator_outcome,'validator_findings',new.validator_findings,'validator_evidence',v_logical_validator_evidence,'validator_identity',new.validator_identity,'validator_assessed_at',new.validator_assessed_at); new.validator_sha256:=programacion.fn_v09_sha256_jsonb(v_payload); return new;
end;
$function$;

CREATE OR REPLACE FUNCTION programacion.fn_guard_input_gap_proposal_update_v512()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion'
AS $function$
declare
  v_run record;
  v_payload jsonb;
  v_ref jsonb;
  v_observed jsonb;
  v_readbacks jsonb := '[]'::jsonb;
  v_bundle jsonb;
begin
  if new.run_id is distinct from old.run_id or new.assessment_id is distinct from old.assessment_id or new.family_code is distinct from old.family_code or new.gap_code is distinct from old.gap_code or new.proposal_kind is distinct from old.proposal_kind or new.proposed_payload is distinct from old.proposed_payload or new.canonical_target is distinct from old.canonical_target or new.source_refs is distinct from old.source_refs or new.evidence_refs is distinct from old.evidence_refs or new.confidence is distinct from old.confidence or new.stage_impact is distinct from old.stage_impact or new.contradictions_checked is distinct from old.contradictions_checked or new.curator_identity is distinct from old.curator_identity or new.curator_execution_id is distinct from old.curator_execution_id or new.curator_sha256 is distinct from old.curator_sha256 or new.created_at is distinct from old.created_at then
    raise exception 'V512_PROPOSAL_CURATOR_FIELDS_IMMUTABLE:%',old.id;
  end if;
  if old.validator_outcome<>'PENDING' then raise exception 'V512_PROPOSAL_VALIDATOR_RECEIPT_IMMUTABLE:%',old.id; end if;
  v_bundle:=programacion.fn_ig_m107_manifest_guard_bundle_v1(old.run_id);
  IF coalesce((v_bundle#>>'{g1,continuation_current}')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'INPUT_GOVERNANCE_CONTINUATION_CURRENTNESS_BLOCKED:table=%:run=%:code=%',
      TG_TABLE_NAME,old.run_id,coalesce(v_bundle#>>'{g1,code}','CURRENTNESS_UNKNOWN');
  END IF;
  if new.validator_outcome='PENDING' then raise exception 'V512_PROPOSAL_VALIDATION_MUST_BE_TERMINAL:%',old.id; end if;
  select * into v_run from programacion.input_readiness_runs where id=old.run_id;
  if v_run.status<>'VALIDATING' then raise exception 'V512_PROPOSAL_VALIDATOR_REQUIRES_VALIDATING_RUN:%',old.run_id; end if;
  if new.validator_identity is null or new.validator_identity=v_run.curator_identity or new.validator_identity is distinct from v_run.validator_identity then
    raise exception 'V512_PROPOSAL_VALIDATOR_NOT_INDEPENDENT:%',old.id;
  end if;
  if new.validator_evidence='{}'::jsonb then raise exception 'V512_PROPOSAL_VALIDATOR_EVIDENCE_REQUIRED:%',old.id; end if;
  if coalesce((new.validator_evidence->>'direct_source_readback')::boolean,false) is not true then raise exception 'V512_PROPOSAL_DIRECT_SOURCE_READBACK_REQUIRED:%',old.id; end if;
  if new.validator_evidence->>'source_snapshot_sha256' is distinct from v_run.source_snapshot_sha256 then raise exception 'V512_PROPOSAL_SOURCE_SNAPSHOT_MISMATCH:%',old.id; end if;

  if coalesce((v_bundle->>'full_manifest_current')::boolean,false) IS NOT TRUE then
    raise exception 'V512_PROPOSAL_SOURCE_SNAPSHOT_STALE:%',old.id;
  end if;

  for v_ref in select value from jsonb_array_elements(old.source_refs)
  loop
    if coalesce(v_ref->>'kind','')='INPUT_GAP_PROPOSAL' then raise exception 'V512_PROPOSAL_CANNOT_VALIDATE_FROM_PROPOSAL_SOURCE:%',old.id; end if;
    v_observed:=programacion.fn_input_resolve_source_ref(v_ref,v_run.pantalla_id,v_run.version_id);
    v_readbacks:=v_readbacks || jsonb_build_array(jsonb_build_object(
      'source_ref',v_ref,
      'source_observed_sha256',programacion.fn_v09_sha256_jsonb(v_observed)
    ));
  end loop;
  if new.validator_evidence->'source_readbacks' is distinct from v_readbacks then
    raise exception 'V512_PROPOSAL_SOURCE_READBACK_DIGEST_MISMATCH:%',old.id;
  end if;

  if new.validator_outcome='PASS' and new.status not in ('VALIDATED','HUMAN_DECISION_REQUIRED') then raise exception 'V512_PROPOSAL_PASS_STATUS_INVALID:%',old.id; end if;
  if new.validator_outcome='FAIL' and new.status<>'REJECTED' then raise exception 'V512_PROPOSAL_FAIL_STATUS_INVALID:%',old.id; end if;
  new.validated_at:=coalesce(new.validated_at,now());
  v_payload:=jsonb_build_object('curator_sha256',old.curator_sha256,'validator_identity',new.validator_identity,'validator_outcome',new.validator_outcome,'validator_evidence',new.validator_evidence,'status',new.status,'validated_at',new.validated_at);
  new.validator_sha256:=programacion.fn_v09_sha256_jsonb(v_payload);
  return new;
end;
$function$;

DO $post$ BEGIN
 IF (SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='programacion' AND c.relname IN ('input_family_assessments','input_gap_proposals')
 AND t.tgenabled IN ('O','A') AND NOT t.tgisinternal)<>16 THEN
 RAISE EXCEPTION 'IG_M107_B_GUARD_TRIGGER_COUNT_DRIFT'; END IF;
END $post$;
DO $profile$
DECLARE
  v_code constant text:='IG-M107-B-ACTIVE-GUARD-ONEPASS-033';
  v_before_count integer;
  v_curator jsonb;
  v_run_id bigint;
  v_plan_family jsonb;
  v_plan_proposal jsonb;
  v_probe_error text;
  v_validator_id text;
  v_validator_component bigint;
  v_run programacion.input_readiness_runs%rowtype;
  v_family programacion.input_family_assessments%rowtype;
  v_prop programacion.input_gap_proposals%rowtype;
  v_parent_has_contract boolean;
  v_assertions jsonb;
  v_evidence jsonb;
  v_physical jsonb;
  v_bad_physical jsonb;
  v_assert_sha text;
  v_eval jsonb;
  v_assertion jsonb;
  v_readbacks jsonb:='[]'::jsonb;
  v_obs jsonb;
  v_ref jsonb;
  v_started timestamptz;
  v_curator_ms bigint;
  v_family_ms numeric;
  v_proposal_ms numeric;
  v_family_triggers jsonb;
  v_proposal_triggers jsonb;
  v_family_trigger_count int;
  v_proposal_trigger_count int;
  v_trial int;
  v_evidence_payload jsonb;
  v_bundle jsonb; v_source_negative text;
BEGIN
  IF EXISTS (SELECT 1 FROM public.lf_error_knowledge WHERE codigo=v_code) THEN
    RAISE EXCEPTION 'IG_M107_PROFILE_ALREADY_EXISTS';
  END IF;
  IF (SELECT status FROM programacion.input_readiness_runs WHERE id=933)<>'COMPLETED'
     OR (SELECT max(id) FROM programacion.input_readiness_runs WHERE pantalla_id=43)<>933
     OR (programacion.fn_input_run_source_currentness_v1(933)->>'source_current')<>'false'
  THEN RAISE EXCEPTION 'IG_M107_PROFILE_SCREEN43_PRECONDITION_DRIFT'; END IF;
  SELECT count(*) INTO v_before_count FROM programacion.input_readiness_runs WHERE pantalla_id=43;
  v_started:=clock_timestamp();

  BEGIN
    -- Curator runtime uses the already governed production SQL route but
    -- is wholly local to this rollback subtransaction.
    v_curator:=programacion.fn_input_governance_direct_step_v1(43,'MANUAL');
    IF v_curator->>'status'<>'VALIDATOR_RUNTIME_REQUIRED'
       OR v_curator->>'step'<>'CURATOR_MATERIALIZED'
       OR v_curator->>'next_action'<>'REINVOKE_SAME_SCREEN'
    THEN RAISE EXCEPTION 'IG_M107_PROFILE_UNEXPECTED_CURATOR:%',left(v_curator::text,450); END IF;
    v_run_id:=(v_curator->>'run_id')::bigint;
    v_curator_ms:=round(extract(epoch from (clock_timestamp()-v_started))*1000)::bigint;
    SELECT * INTO STRICT v_run FROM programacion.input_readiness_runs WHERE id=v_run_id;
    -- Contract: a CURATING run has NO sealed source snapshot. The run guard
    -- computes it on CURATING -> VALIDATING; source_current applies only to
    -- COMPLETED runs. Do not conflate lifecycle with fresh-source dimensions.
    IF v_run.status<>'CURATING'
       OR v_run.pantalla_id<>43
       OR v_run.version_id<>19
       OR v_run.source_snapshot_sha256 IS NOT NULL
       OR (SELECT count(*) FROM programacion.input_family_assessments WHERE run_id=v_run_id)<>47
    THEN RAISE EXCEPTION 'IG_M107_PROFILE_CURATOR_READBACK_INVALID'; END IF;

    v_validator_id:='INPUT_VALIDATOR:SQL:ig-governed-dispatch-v1:'||gen_random_uuid()::text;
    SELECT id INTO STRICT v_validator_component FROM programacion.componentes
     WHERE version_id=v_run.version_id AND componente_codigo='INPUT_VALIDATOR';
    UPDATE programacion.input_readiness_runs
       SET status='VALIDATING',
           validator_identity=v_validator_id,
           validator_component_id=v_validator_component
     WHERE id=v_run_id;
    SELECT * INTO STRICT v_run FROM programacion.input_readiness_runs WHERE id=v_run_id;
    -- The manifest is now generated and VALIDATING admission must be true
    -- across contract/policy/source dimensions; terminal lifecycle remains false.
    IF v_run.status<>'VALIDATING'
       OR v_run.source_snapshot_sha256 IS NULL
       OR (programacion.fn_input_governance_continuation_currentness_v1(v_run_id)->>'continuation_current')<>'true'
    THEN RAISE EXCEPTION 'IG_M107_PROFILE_VALIDATING_STAGE_MISSING'; END IF;
    v_bundle:=programacion.fn_ig_m107_manifest_guard_bundle_v1(v_run_id);
    IF (v_bundle->>'full_manifest_current')::boolean IS NOT TRUE
      OR (v_bundle#>>'{g1,continuation_current}')::boolean IS NOT TRUE
    THEN RAISE EXCEPTION 'IG_M107_B_POSITIVE_ONEPASS_NOT_CURRENT'; END IF;

    SELECT * INTO STRICT v_family FROM programacion.input_family_assessments
      WHERE run_id=v_run_id AND family_code='SCREEN_IDENTITY' AND validator_outcome='PENDING';
    SELECT EXISTS (
      SELECT 1 FROM programacion.input_family_assessments pa
      CROSS JOIN LATERAL jsonb_array_elements(
       programacion.fn_input_validator_evidence_rehydrate_v1(pa.validator_evidence)->'assertions') j(x)
      WHERE pa.run_id=v_run.supersedes_run_id AND pa.family_code=v_family.family_code
      AND j.x#>>'{source_ref,kind}'='CONTRACT'
    ) INTO v_parent_has_contract;
    IF v_run.supersedes_run_id IS NOT NULL AND NOT v_parent_has_contract THEN
      v_assertions:=programacion.fn_input_v58_build_assertions(v_run_id,v_run.supersedes_run_id,v_family.family_code);
    ELSE
      v_assertions:=programacion.fn_input_governance_bootstrap_assertions_v1(v_run_id,v_family.family_code);
    END IF;
    IF jsonb_array_length(v_assertions)<>1 THEN
      RAISE EXCEPTION 'IG_M107_PROFILE_EXPECT_SINGLE_ASSERTION';
    END IF;
    FOR v_assertion IN SELECT value FROM jsonb_array_elements(v_assertions) LOOP
      v_eval:=programacion.fn_input_evaluate_assertion(v_run_id,v_family.family_code,v_assertion);
      IF coalesce((v_eval->>'passed')::boolean,false) IS NOT TRUE
         OR v_assertion->>'result'<>'PASS'
         OR v_assertion->>'source_observed_sha256' IS DISTINCT FROM v_eval->>'source_observed_sha256'
      THEN RAISE EXCEPTION 'IG_M107_PROFILE_POSITIVE_ASSERTION_FAILED'; END IF;
    END LOOP;
    v_assert_sha:=programacion.fn_v09_sha256_jsonb(v_assertions);
    INSERT INTO programacion.input_validator_assertion_sets_v1(assertion_set_sha256,assertions)
    VALUES (v_assert_sha,v_assertions) ON CONFLICT(assertion_set_sha256) DO NOTHING;
    IF (SELECT assertions FROM programacion.input_validator_assertion_sets_v1
        WHERE assertion_set_sha256=v_assert_sha) IS DISTINCT FROM v_assertions
    THEN RAISE EXCEPTION 'IG_M107_PROFILE_ASSERTION_SET_DRIFT'; END IF;

    v_evidence:=jsonb_build_object(
     'component_id',v_validator_component,'execution_id',gen_random_uuid()::text,
     'validated_curator_execution_id',v_family.curator_evidence->>'execution_id',
     'execution_mode','INDEPENDENT_VALIDATOR',
     'runtime','SUPABASE_EDGE_FUNCTION:input-governance-validator-v1',
     'direct_source_readback',true,'contract_revision',v_run.contract_revision,
     'source_snapshot_sha256',v_run.source_snapshot_sha256,
     'curator_sha256',v_family.curator_sha256,
     'semantic_depth_sha256',v_family.semantic_depth_sha256,
     'bootstrap_classifier_sha256',NULL,
     'semantic_conclusion_independence','UNPROVEN',
     'validation_phase','SOURCE_INTEGRITY',
     'semantic_comparison_requested',false,'semantic_independence_credited',false,
     'analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX',
     'assertions',v_assertions);
    v_physical:=(v_evidence-'assertions')||
      jsonb_build_object('assertion_set_sha256',v_assert_sha);
    IF programacion.fn_input_validator_evidence_rehydrate_v1(v_physical)
       IS DISTINCT FROM v_evidence THEN
      RAISE EXCEPTION 'IG_M107_PROFILE_PHYSICAL_EVIDENCE_DRIFT'; END IF;

    -- Explicit negative: same family, false source SHA must fail closed.
    v_bad_physical:=jsonb_set(v_physical,'{source_snapshot_sha256}',
       to_jsonb(repeat('0',64)),true);
    v_probe_error:=NULL;
    BEGIN
      UPDATE programacion.input_family_assessments
         SET validator_outcome='PASS',validator_findings='[]'::jsonb,
             validator_evidence=v_bad_physical,
             validator_identity=v_validator_id,validator_assessed_at=clock_timestamp()
       WHERE id=v_family.id;
    EXCEPTION WHEN OTHERS THEN
      v_probe_error:=SQLSTATE||':'||left(SQLERRM,220);
    END;
    IF v_probe_error IS NULL
      OR (SELECT validator_outcome FROM programacion.input_family_assessments
           WHERE id=v_family.id)<>'PENDING'
    THEN RAISE EXCEPTION 'IG_M107_PROFILE_TAMPER_NOT_REJECTED'; END IF;

    -- Real family UPDATE with all six active guards, returned timing per trigger.
    EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
       UPDATE programacion.input_family_assessments
       SET validator_outcome=$1,validator_findings=$2,
           validator_evidence=$3,validator_identity=$4,
           validator_assessed_at=clock_timestamp()
       WHERE id=$5'
       INTO v_plan_family
       USING 'PASS'::text,'[]'::jsonb,v_physical,v_validator_id,v_family.id;
    v_family_ms:=(v_plan_family->0->>'Execution Time')::numeric;
    v_family_triggers:=coalesce(v_plan_family->0->'Triggers','[]'::jsonb);
    -- EXPLAIN reports both user-defined and internal FK triggers.
    -- Count the governed application triggers by exact catalogue identity;
    -- preserve FK timings in v_family_triggers without treating them as missing gates.
    SELECT count(*) INTO v_family_trigger_count
    FROM jsonb_array_elements(v_family_triggers) jt(value)
    WHERE jt.value->>'Trigger Name' IN (
      SELECT tgname FROM pg_trigger WHERE NOT tgisinternal
      AND tgenabled IN ('O','A') AND tgtype&16=16
      AND tgrelid='programacion.input_family_assessments'::regclass
    );
    IF (SELECT validator_outcome FROM programacion.input_family_assessments
          WHERE id=v_family.id)<>'PASS'
        OR v_family_trigger_count<>6 THEN
       RAISE EXCEPTION 'IG_M107_PROFILE_FAMILY_TRIGGERS_INCOMPLETE:%',v_family_triggers;
    END IF;

    -- Proposal control; source readback must match same source SHA.
    SELECT * INTO STRICT v_prop FROM programacion.input_gap_proposals
      WHERE run_id=v_run_id AND validator_outcome='PENDING'
      ORDER BY id LIMIT 1;
    v_readbacks:='[]'::jsonb;
    FOR v_ref IN SELECT value FROM jsonb_array_elements(v_prop.source_refs) LOOP
      v_obs:=programacion.fn_input_resolve_source_ref(v_ref,v_run.pantalla_id,v_run.version_id);
      v_readbacks:=v_readbacks||jsonb_build_array(jsonb_build_object(
        'source_ref',v_ref,'source_observed_sha256',
        programacion.fn_v09_sha256_jsonb(v_obs)));
    END LOOP;
    v_evidence:=jsonb_build_object(
      'direct_source_readback',true,
      'source_snapshot_sha256',v_run.source_snapshot_sha256,
      'source_readbacks',v_readbacks,
      'analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX',
      'proposal_is_canonical_source',false,
      'automatic_canonicalization','DENY');
    -- Real authority mutation is performed only in nested rollback scope.
    BEGIN
      UPDATE lf_ops.pantalla_artefactos SET is_current=false WHERE pantalla_id=43 AND is_current=true;
      IF NOT FOUND THEN RAISE EXCEPTION 'IG_M107_B_NO_SOURCE_TO_MUTATE'; END IF;
      UPDATE programacion.input_gap_proposals SET
        validator_identity=v_validator_id,validator_outcome='PASS',
        status=CASE WHEN v_prop.proposal_kind='HUMAN_DECISION_REQUIRED'
          THEN 'HUMAN_DECISION_REQUIRED' ELSE 'VALIDATED' END,
        validator_evidence=v_evidence,validated_at=clock_timestamp()
        WHERE id=v_prop.id;
      RAISE EXCEPTION 'IG_M107_B_MUTATION_FALSE_PASS';
    EXCEPTION WHEN OTHERS THEN
      v_source_negative:=SQLERRM;
      IF v_source_negative LIKE '%MUTATION_FALSE_PASS%'
        OR v_source_negative LIKE '%NO_SOURCE_TO_MUTATE%'
        OR (v_source_negative NOT LIKE '%SOURCE%'
            AND v_source_negative NOT LIKE '%CURRENTNESS%'
            AND v_source_negative NOT LIKE '%VISUAL%')
      THEN RAISE; END IF;
    END;
    IF (SELECT count(*) FROM lf_ops.pantalla_artefactos WHERE pantalla_id=43 AND is_current=true)<>1
      THEN RAISE EXCEPTION 'IG_M107_B_VISUAL_SOURCE_NOT_RESTORED'; END IF;
    EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
      UPDATE programacion.input_gap_proposals
      SET validator_identity=$1,validator_outcome=$2,
          status=CASE WHEN proposal_kind=''HUMAN_DECISION_REQUIRED''
                 THEN ''HUMAN_DECISION_REQUIRED'' ELSE ''VALIDATED'' END,
          validator_evidence=$3,validated_at=clock_timestamp()
      WHERE id=$4'
      INTO v_plan_proposal USING v_validator_id,'PASS'::text,v_evidence,v_prop.id;
    v_proposal_ms:=(v_plan_proposal->0->>'Execution Time')::numeric;
    v_proposal_triggers:=coalesce(v_plan_proposal->0->'Triggers','[]'::jsonb);
    SELECT count(*) INTO v_proposal_trigger_count
    FROM jsonb_array_elements(v_proposal_triggers) jt(value)
    WHERE jt.value->>'Trigger Name' IN (
      SELECT tgname FROM pg_trigger WHERE NOT tgisinternal
      AND tgenabled IN ('O','A') AND tgtype&16=16
      AND tgrelid='programacion.input_gap_proposals'::regclass
    );
    IF (SELECT validator_outcome FROM programacion.input_gap_proposals
         WHERE id=v_prop.id)<>'PASS' OR v_proposal_trigger_count<>2 THEN
      RAISE EXCEPTION 'IG_M107_PROFILE_PROPOSAL_TRIGGERS_INCOMPLETE:%',
         v_proposal_triggers;
    END IF;

    -- Intentional rollback including ALL runtime/canonical/receipt/proposal effects.
    RAISE EXCEPTION 'IG_M107_PROFILE_EXPECTED_ROLLBACK' USING ERRCODE='PZ127';
  EXCEPTION WHEN SQLSTATE 'PZ127' THEN NULL;
  END;

  IF v_plan_family IS NULL OR v_plan_proposal IS NULL
      OR v_family_ms IS NULL OR v_proposal_ms IS NULL
      OR v_run_id IS NULL OR v_probe_error IS NULL
  THEN RAISE EXCEPTION 'IG_M107_PROFILE_NO_MATERIAL_POSITIVE_AND_NEGATIVE'; END IF;
  IF EXISTS(SELECT 1 FROM programacion.input_readiness_runs WHERE id=v_run_id)
      OR EXISTS(SELECT 1 FROM programacion.input_family_assessments WHERE run_id=v_run_id)
      OR EXISTS(SELECT 1 FROM programacion.input_gap_proposals WHERE run_id=v_run_id)
      OR (SELECT count(*) FROM programacion.input_readiness_runs WHERE pantalla_id=43)<>v_before_count
      OR (SELECT status FROM programacion.input_readiness_runs WHERE id=933)<>'COMPLETED'
  THEN RAISE EXCEPTION 'IG_M107_PROFILE_ROLLBACK_RESIDUE'; END IF;


  IF v_bundle IS NULL OR v_source_negative IS NULL THEN RAISE EXCEPTION 'IG_M107_B_TEST_INCOMPLETE'; END IF;
  INSERT INTO public.lf_error_knowledge(
 id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
 frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,created_at,updated_at,
 lifecycle_phase,root_cause_family,detectability,source_context,source_ref)
 VALUES(
 gen_random_uuid(),v_code,'GOVERNANCE',
 'M10.7 B: guards activos combinan currentness y full manifest',
 'Para los UPDATE de familias/propuestas, el guard final realiza G1 y full con un manifiesto fresco; el guard previo mantiene immutabilidad y sigue comprobando currentness en INSERT de chunks.',
 'Dos manifest reads en triggers distintos para un mismo UPDATE de validacion.',
 'PER_ROW_ONEPASS_TWO_INDEPENDENT_VERDICTS',
 'Conservar los 21 triggers, rechazar cambios de fuentes y SHA tamper, y reutilizar solo dentro de la llamada del guard final; sin cache entre sentencias.',
 'Train: una pantalla, 1 familia PASS con 6 triggers, 1 propuesta PASS con 2 triggers, SHA tamper rechazado y modificacion de fuente real bloqueada; rollback sin residuos.',
 'HIGH',1,clock_timestamp(),clock_timestamp(),
 'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.7/LOT_B','ACTIVO',
 jsonb_build_object('schema_version','IG_M107_B_ACTIVE_GUARD_ONEPASS_V1',
  'screen_id',43,'run_rolled_back',v_run_id,'onepass_full_current',v_bundle->>'full_manifest_current',
  'family_ms',v_family_ms,'proposal_ms',v_proposal_ms,
  'family_triggers',v_family_trigger_count,'proposal_triggers',v_proposal_trigger_count,
  'tamper_negative',v_probe_error,'source_mutation_negative',v_source_negative,
  'fixture_clean',true,'chunk_insert_currentness_code_retained',true,
  'cp3_closed',false)::text,clock_timestamp(),clock_timestamp(),
 'VALIDATION','R5_EROSION_PROCESO','LOUD_EARLY',
 'One-screen rolled-back source mutation and valid validator receipts',
 'docs/ig/IG_M107_B_ACTIVE_GUARDS_ONEPASS_V1.md');
 IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo=v_code)<>1
 THEN RAISE EXCEPTION 'IG_M107_B_EKB_FAILED'; END IF;
END $profile$;
