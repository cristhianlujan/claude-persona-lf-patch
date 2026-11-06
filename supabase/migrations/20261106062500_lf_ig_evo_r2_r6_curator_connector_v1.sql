-- IG-EVO R2-R6 attachment to native proposal materializer (no new runtime).
-- Database change by governed Merge Train ONLY. Assumes prior two migrations.
-- Source patch fail-closes if R1 hook is absent; preserves SECURITY DEFINER grants.
BEGIN;
DO $patch$
DECLARE
  v_def text;
  v_orig text;
  v_old_decl text:='  v_r1_inserted integer;';
  v_new_decl text;
  v_target text:=E'  select count(*)\n    into v_close_candidates';
  v_added text;
  v_body text;
BEGIN
  SELECT pg_get_functiondef(
    'programacion.fn_input_governance_materialize_gap_proposals_v1(bigint)'::regprocedure)
  INTO v_orig;
  IF v_orig IS NULL
     OR position('v_r1_scan:=programacion.fn_ig_evo_r1_parameter_provenance_v1' in v_orig)=0
     OR position('IG-EVO R1' in v_orig)=0 THEN
    RAISE EXCEPTION 'IG_EVO_R2_R6_R1_PREREQUISITE_OR_DRIFT';
  END IF;
  IF to_regprocedure('programacion.fn_ig_evo_r2_r6_diagnostics_v1(integer,bigint)') IS NULL THEN
    RAISE EXCEPTION 'IG_EVO_R2_R6_SCANNER_NOT_INSTALLED';
  END IF;
  IF (length(v_orig)-length(replace(v_orig,v_old_decl,'')))/length(v_old_decl)<>1
    OR (length(v_orig)-length(replace(v_orig,v_target,'')))/length(v_target)<>1 THEN
    RAISE EXCEPTION 'IG_EVO_R2_R6_CURATOR_SOURCE_UNSAFE';
  END IF;
  v_new_decl:=v_old_decl||E'\n  v_r2_r6_scan jsonb;\n  v_r2_r6_finding jsonb;\n  v_r2_r6_assessment record;\n  v_r2_r6_inserted integer;\n  v_r2_r6_gap text;';
  v_added:=$added$
  -- IG-EVO R2-R6 candidates: no semantic PASS and no inference of GLOBAL.
  v_r2_r6_scan:=programacion.fn_ig_evo_r2_r6_diagnostics_v1(v_run.pantalla_id,p_run_id);
  if v_r2_r6_scan->>'schema_version'<>'IG_EVO_R2_R6_DIAGNOSTICS_V1'
     or (v_r2_r6_scan->>'pantalla_id')::integer is distinct from v_run.pantalla_id
     or (v_r2_r6_scan->>'run_id')::bigint is distinct from p_run_id then
    raise exception 'IG_EVO_R2_R6_SCAN_CONTRACT_INVALID:%',p_run_id;
  end if;
  for v_r2_r6_finding in
    select value from jsonb_array_elements(v_r2_r6_scan->'findings')
  loop
    select * into v_r2_r6_assessment
    from programacion.input_family_assessments
    where run_id=p_run_id and family_code=v_r2_r6_finding->>'family_code';
    if not found then
      raise exception 'IG_EVO_R2_R6_FAMILY_MISSING:%:%',
        p_run_id,v_r2_r6_finding->>'family_code';
    end if;
    if coalesce((v_r2_r6_finding->>'case_count')::integer,0)<=0
       or v_r2_r6_finding->>'semantic_pass_authorized'<>'false' then
      raise exception 'IG_EVO_R2_R6_FINDING_INVALID:%',v_r2_r6_finding->>'detector';
    end if;
    v_r2_r6_gap:=v_r2_r6_finding->>'gap_code';
    insert into programacion.input_gap_proposals(
      run_id,assessment_id,family_code,gap_code,proposal_kind,proposed_payload,canonical_target,
      source_refs,evidence_refs,confidence,stage_impact,contradictions_checked,status,
      curator_identity,curator_execution_id
    ) values (
      p_run_id,v_r2_r6_assessment.id,v_r2_r6_assessment.family_code,
      v_r2_r6_gap,v_r2_r6_finding->>'proposal_kind',
      jsonb_build_object(
        'gap_classification',case
          when v_r2_r6_assessment.family_code in('CONFLICT_PRECEDENCE','SECURITY')
            then 'SEMANTIC_EVIDENCE_GAP'
          else 'GOVERNANCE_EVIDENCE_GAP' end,
        'agent_action','RESOLVE_PENDING_SOURCE_OR_EVIDENCE_INTERNALLY',
        'gap_policy_ref',v_policy_ref,'gap_policy_schema',v_policy->>'schema_version',
        'gap_policy_action','CREATE','synthesis_mode','HOLD_FOR_EVIDENCE',
        'policy_result','RECOMENDADA',
        'targeted_evidence_before_escalation','TARGETED_EVIDENCE_ACQUISITION',
        'canonical_change_admission','SAFE_CHANGE_ADMISSION',
        'no_effective_change_result',v_policy->>'no_effective_change_result',
        'positive_owner_escalation_authority',false,
        'pending_marker_is_not_owner_authority',true,
        'no_invention',true,'proposal_is_canonical_source',false,
        'automatic_canonicalization','DENY',
        'analysis_revision','IG_EVO_R2_R6_DIAGNOSTICS_V1',
        'remediation_policy_revision','INPUT_GAP_POLICY_V1',
        'detector_code',v_r2_r6_finding->>'detector',
        'detector_finding',v_r2_r6_finding,
        'source_readback_limit','SCOPE_GRAPH_ONLY_EXACT_SEMANTIC_SOURCE_NOT_VERIFIED',
        'semantic_quality_evaluated',false,'semantic_quality_verdict','NOT_TESTED',
        'semantic_pass_authorized',false,'automatic_promotion_authorized',false
      ),
      jsonb_build_object('pantalla_id',v_run.pantalla_id,
        'family_code',v_r2_r6_assessment.family_code),
      jsonb_build_array(jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH',
        'pantalla_id',v_run.pantalla_id)),
      '[]'::jsonb,
      null,
      jsonb_build_object(
        'story',v_r2_r6_assessment.story_ready_status,
        'implementation',v_r2_r6_assessment.implementation_ready_status,
        'qa',v_r2_r6_assessment.qa_ready_status,
        'production',v_r2_r6_assessment.production_ready_status),
      jsonb_build_array(
        'NO_AUTO_PROMOTION','SEMANTIC_SCOPE_NOT_TESTED',
        'NO_ASSUMPTION_OF_GLOBAL_APPLICABILITY',
        'FINDINGS_GROUPED_BY_DETECTOR','EXACT_SOURCE_PENDING_VALIDATOR'),
      'PROPOSED',v_run.curator_identity,
      coalesce(v_r2_r6_assessment.curator_evidence->>'execution_id','UNKNOWN')
    ) on conflict (run_id,family_code,gap_code) do nothing;
    get diagnostics v_r2_r6_inserted = row_count;
    if v_r2_r6_inserted=1 then
      v_count:=v_count+1; v_auto:=v_auto+1; v_create:=v_create+1;
    else
      v_inherit:=v_inherit+1;
    end if;
  end loop;
$added$;
  v_def:=replace(v_orig,v_old_decl,v_new_decl);
  v_def:=replace(v_def,v_target,v_added||v_target);
  IF v_def=v_orig OR position('fn_ig_evo_r2_r6_diagnostics_v1' in v_def)=0 THEN
    RAISE EXCEPTION 'IG_EVO_R2_R6_CURATOR_PATCH_NOOP';
  END IF;
  -- pg_get_functiondef has no terminating semicolon; append one safely.
  EXECUTE rtrim(v_def,';'||E'\n')||';';
END $patch$;

DO $post$
DECLARE v_doc jsonb; v_def text; v_n integer;
BEGIN
 v_doc:=programacion.fn_ig_evo_r2_r6_diagnostics_v1(51,949);
 IF v_doc->>'schema_version'<>'IG_EVO_R2_R6_DIAGNOSTICS_V1'
 OR jsonb_typeof(v_doc->'findings')<>'array'
 OR v_doc->>'canonical_write_authorized'<>'false' THEN
  RAISE EXCEPTION 'IG_EVO_R2_R6_DIAGNOSTIC_SHAPE_INVALID';
 END IF;
 IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_doc->'findings') x
   WHERE x->>'detector'='R2') THEN
  RAISE EXCEPTION 'IG_EVO_R2_FALSE_POSITIVE_TEMPORARY_IP';
 END IF;
 IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_doc->'findings') x
   WHERE x->>'semantic_pass_authorized'<>'false' OR x->>'auto_apply'<>'false') THEN
  RAISE EXCEPTION 'IG_EVO_R2_R6_UNAUTHORIZED_PROMOTION';
 END IF;
 SELECT pg_get_functiondef(
   'programacion.fn_input_governance_materialize_gap_proposals_v1(bigint)'::regprocedure)
 INTO v_def;
 IF position('fn_ig_evo_r1_parameter_provenance_v1' in v_def)=0
 OR position('fn_ig_evo_r2_r6_diagnostics_v1' in v_def)=0
 OR position('SEMANTIC_SCOPE_NOT_TESTED' in v_def)=0 THEN
  RAISE EXCEPTION 'IG_EVO_R2_R6_NATIVE_CURATOR_NOT_CONNECTED';
 END IF;
 SELECT count(*) INTO v_n
 FROM programacion.input_family_assessments
 WHERE run_id=949 AND family_code IN(
   'SOURCE_AUTHORITY_PROVENANCE','CONFLICT_PRECEDENCE',
   'APPLICABILITY_READINESS','SECURITY');
 IF v_n<>4 THEN RAISE EXCEPTION 'IG_EVO_R2_R6_FAMILIES_UNAVAILABLE:%',v_n; END IF;
END $post$;
COMMIT;
