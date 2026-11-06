-- LF Input Governance L7: deterministic native Validator precheck for model CANDIDATE.
-- Not an independent semantic judge, NOT a semantic PASS, and NOT a DB writer.
-- Requires the source-frozen semantic packet from migration 20261106164000.
-- EKB: GOV-032; IG-M811-NEGATIVE-TEST-FAIL-NOT-PASS-001.
BEGIN;
CREATE OR REPLACE FUNCTION programacion.fn_input_governance_semantic_candidate_precheck_core_v1(
  p_run_id bigint, p_validator_identity text, p_receipt_id bigint, p_candidate jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','programacion','public'
AS $precheck$
DECLARE
  v_packet jsonb;
  v_d jsonb;
  v_s jsonb;
  v_codes text[]:=ARRAY[]::text[];
  v_ref jsonb;
  v_refs text[];
  v_missing int;
  v_find text;
  v_family text;
  v_ref_val text;
  v_prov jsonb;
  v_field text;
  v_source_count integer;
  v_decisions_count integer;
BEGIN
  IF jsonb_typeof(p_candidate)<>'object' THEN
     RAISE EXCEPTION 'IG_SEMANTIC_CANDIDATE_NOT_OBJECT';
  END IF;
  -- Revalidate exact current source packet and verified handoff under the DB role.
  v_packet:=programacion.fn_input_governance_semantic_packet_core_v1(
       p_run_id,p_validator_identity,p_receipt_id);
  IF v_packet->>'source_integrity_verified'<>'true'
     OR v_packet->>'status'<>'READY_FOR_MODEL_CANDIDATE' THEN
     RAISE EXCEPTION 'IG_SEMANTIC_CANDIDATE_UNPINNED_SOURCE:%',p_run_id;
  END IF;
  IF p_candidate->>'status'<>'SEMANTIC_MODEL_CANDIDATE_UNATTESTED'
     OR p_candidate->>'provider'<>'OPENAI'
     OR nullif(p_candidate->>'provider_response_id','') IS NULL
     OR nullif(p_candidate->>'model_id','') IS NULL
     OR nullif(p_candidate->>'prompt_version','') IS NULL
     OR p_candidate->>'prompt_sha256' !~ '^[a-f0-9]{64}$'
     OR p_candidate->>'raw_response_sha256' !~ '^[a-f0-9]{64}$'
     OR (p_candidate->>'model_call_count')::integer IS DISTINCT FROM 1
     OR (p_candidate->>'run_id')::bigint IS DISTINCT FROM p_run_id
     OR (p_candidate->>'handoff_receipt_id')::bigint IS DISTINCT FROM p_receipt_id
     OR p_candidate->>'validator_identity' IS DISTINCT FROM p_validator_identity
     OR p_candidate->>'source_snapshot_sha256' IS DISTINCT FROM v_packet->>'source_snapshot_sha256'
     OR p_candidate->>'db_packet_sha256' IS DISTINCT FROM v_packet->>'db_packet_sha256'
     OR p_candidate->>'semantic_pass_authorized' IS DISTINCT FROM 'false'
     OR p_candidate->>'official_write_authorized' IS DISTINCT FROM 'false'
     OR p_candidate->>'production_authorized' IS DISTINCT FROM 'false'
     OR p_candidate->>'semantic_independence_credited' IS DISTINCT FROM 'false' THEN
     RAISE EXCEPTION 'IG_SEMANTIC_CANDIDATE_BINDING_OR_AUTHORITY_INVALID:%',p_run_id;
  END IF;
  IF p_candidate#>>'{decision,schema_version}' <> 'IG_SEMANTIC_VERDICT_V1'
     OR p_candidate#>>'{decision,subject}' IS DISTINCT FROM v_packet->>'screen_code'
     OR p_candidate#>>'{decision,overall_assessment}' NOT IN (
          'RESEARCH_REQUIRED','PARTIAL','DECLARATIVE_COMPLETE_ONLY','NOT_PROVEN_SAFE')
     OR jsonb_typeof(p_candidate#>'{decision,decisions}')<>'array' THEN
     RAISE EXCEPTION 'IG_SEMANTIC_CANDIDATE_DECISION_SHAPE_INVALID:%',p_run_id;
  END IF;
  v_source_count:=jsonb_array_length(v_packet->'sources');
  v_decisions_count:=jsonb_array_length(p_candidate#>'{decision,decisions}');
  IF v_source_count<>v_decisions_count THEN
     RAISE EXCEPTION 'IG_SEMANTIC_CANDIDATE_SOURCE_COVERAGE_INVALID:%',p_run_id;
  END IF;
  SELECT array_agg(s.value->>'ref' ORDER BY s.value->>'ref') INTO v_refs
  FROM jsonb_array_elements(v_packet->'sources') s(value);
  FOR v_d IN SELECT value FROM jsonb_array_elements(p_candidate#>'{decision,decisions}') LOOP
     IF jsonb_typeof(v_d)<>'object' OR jsonb_typeof(v_d->'evidence_refs')<>'array'
        OR jsonb_typeof(v_d->'missing_evidence')<>'array'
        OR jsonb_typeof(v_d->'counterexamples_checked')<>'array'
        OR nullif(btrim(coalesce(v_d->>'reason','')),'') IS NULL
        OR v_d->>'implementation_verified'<>'false'
        OR v_d->>'production_verified'<>'false' THEN
        RAISE EXCEPTION 'IG_SEMANTIC_CANDIDATE_DECISION_INVALID:%',p_run_id;
     END IF;
     v_find:=v_d->>'finding';
     IF v_find NOT IN ('SOURCE_INCOMPLETE','DECLARATIVE_COMPLETE_IMPLEMENTATION_PENDING',
            'CONTRADICTION','NOT_PROVEN_SAFE','RESEARCH_REQUIRED','NOT_APPLICABLE') THEN
        RAISE EXCEPTION 'IG_SEMANTIC_CANDIDATE_FINDING_INVALID:%',v_find;
     END IF;
     IF v_d->>'source_code'=ANY(v_codes) THEN
        RAISE EXCEPTION 'IG_SEMANTIC_CANDIDATE_DUPLICATE_SOURCE_CODE:%',v_d->>'source_code';
     END IF;
     v_codes:=array_append(v_codes,v_d->>'source_code');
     SELECT s.value INTO v_s FROM jsonb_array_elements(v_packet->'sources') s(value)
       WHERE s.value->>'code'=v_d->>'source_code'
         AND s.value->>'family'=v_d->>'family_code';
     IF v_s IS NULL OR NOT (v_d->'evidence_refs' ? (v_s->>'ref')) THEN
        RAISE EXCEPTION 'IG_SEMANTIC_CANDIDATE_SOURCE_OR_REF_INVALID:%',p_run_id;
     END IF;
     FOR v_ref IN SELECT value FROM jsonb_array_elements(v_d->'evidence_refs') LOOP
        v_ref_val:=v_ref#>>'{}';
        IF v_ref_val IS NULL OR NOT (v_ref_val=ANY(v_refs)) THEN
            RAISE EXCEPTION 'IG_SEMANTIC_CANDIDATE_UNGROUNDED_EVIDENCE:%',v_ref_val;
        END IF;
     END LOOP;
     IF v_find='NOT_APPLICABLE' AND v_s->'applicability_authority'='null'::jsonb THEN
         RAISE EXCEPTION 'IG_SEMANTIC_CANDIDATE_NA_WITHOUT_AUTHORITY:%',p_run_id;
     END IF;
     v_prov:=coalesce(v_s->'parameter_provenance','{}'::jsonb);
     FOR v_field IN SELECT jsonb_array_elements_text(v_s->'required_provenance_fields') LOOP
         IF NOT (v_prov ? v_field)
             AND v_find NOT IN ('SOURCE_INCOMPLETE','RESEARCH_REQUIRED','NOT_PROVEN_SAFE') THEN
            RAISE EXCEPTION 'IG_SEMANTIC_CANDIDATE_FALSE_PROVENANCE_COMPLETE:%',p_run_id;
         END IF;
     END LOOP;
  END LOOP;
  RETURN jsonb_build_object(
    'status','CANDIDATE_PRECHECKED_NOT_OFFICIAL',
    'run_id',p_run_id,
    'handoff_receipt_id',p_receipt_id,
    'validated_model_candidate_binding',true,
    'validated_source_count',v_source_count,
    'source_snapshot_sha256',v_packet->>'source_snapshot_sha256',
    'db_packet_sha256',v_packet->>'db_packet_sha256',
    'semantic_judge_independence_accredited',false,
    'semantic_pass_authorized',false,
    'official_write_authorized',false,
    'production_authorized',false);
END;
$precheck$;

CREATE OR REPLACE FUNCTION public.fn_input_governance_semantic_candidate_precheck_v1(
    p_run_id bigint,p_validator_identity text,p_receipt_id bigint,p_ticket uuid,
    p_candidate jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','programacion'
AS $wrapper$
BEGIN
    PERFORM public.lf_profile_ig_ticket_verify_v1(p_ticket,NULL,p_run_id);
    RETURN programacion.fn_input_governance_semantic_candidate_precheck_core_v1(
        p_run_id,p_validator_identity,p_receipt_id,p_candidate);
END;
$wrapper$;
REVOKE ALL ON FUNCTION programacion.fn_input_governance_semantic_candidate_precheck_core_v1(bigint,text,bigint,jsonb)
    FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.fn_input_governance_semantic_candidate_precheck_v1(bigint,text,bigint,uuid,jsonb)
    FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fn_input_governance_semantic_candidate_precheck_v1(bigint,text,bigint,uuid,jsonb)
    TO service_role;
COMMIT;
