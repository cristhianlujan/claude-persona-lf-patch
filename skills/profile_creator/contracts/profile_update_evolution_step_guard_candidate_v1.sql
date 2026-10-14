-- Candidate-only; designed for invocation INSIDE the existing
-- public.lf_record_profile_operation_step_v1 substantive validation path.
-- Never directly install/GRANT as a standalone UPDATE/NO_CHANGE authority.
--
-- Prerequisite: verified_receipt reader with narrow SECURITY DEFINER scope.
CREATE OR REPLACE FUNCTION public.lf_profile_update_evolution_step_guard_v1(
  p_execution_id text,
  p_step_id text,
  p_payload jsonb
) RETURNS text
LANGUAGE plpgsql STABLE
SET search_path = pg_catalog,public
AS $guard$
DECLARE
  e public.lf_operation_execution%rowtype;
  recorded public.lf_operation_execution_steps%rowtype;
  portfolio jsonb;
  r record;
  m record;
  method_data jsonb;
  slug text;
  decision text;
  mode text;
BEGIN
  IF p_step_id NOT IN ('method_selection','evolution_decision') THEN RETURN NULL; END IF;
  SELECT * INTO e FROM public.lf_operation_execution WHERE execution_id=p_execution_id;
  IF NOT FOUND OR e.operation_code<>'ACTUALIZACION_PERFIL_LF'
     OR e.manifest#>'{operation_policy_snapshots,PASS_POLICY,policy_payload,required_steps_by_outcome}' IS NULL
  THEN RETURN 'EVOLUTION_OPERATION_CONTEXT_INVALID'; END IF;
  IF jsonb_typeof(p_payload) <> 'object' THEN RETURN 'EVOLUTION_EVIDENCE_NOT_OBJECT'; END IF;
  slug:=split_part(e.target_path,'/',2);
  IF NULLIF(slug,'') IS NULL OR p_payload->>'profile_slug'<>slug THEN
    RETURN 'EVOLUTION_PROFILE_IDENTITY_MISMATCH';
  END IF;
  IF p_payload->>'source_head_sha'<>coalesce(e.manifest->>'initial_main_revision','')
     OR p_payload->>'source_head_sha' !~ '^[0-9a-f]{40}$'
  THEN RETURN 'EVOLUTION_SOURCE_REVISION_MISMATCH'; END IF;
  IF NOT public.lf_profile_update_verified_receipt_v1(
       'PROFILE_ASSESSMENT',slug,
       p_payload->>'profile_assessment_receipt_id',
       p_payload->>'profile_assessment_sha256',
       p_payload->>'source_head_sha'
  ) THEN RETURN 'EVOLUTION_PROFILE_ASSESSMENT_NOT_VERIFIED'; END IF;

  IF p_step_id='method_selection' THEN
    IF p_payload->>'selector_version' IS DISTINCT FROM (
      SELECT version FROM public.lf_capability_current
       WHERE capability_code='CAPABILITY_SELECTOR'
    ) THEN RETURN 'EVOLUTION_SELECTOR_VERSION_STALE'; END IF;
    SELECT v.manifest#>'{qualified_method_portfolio}' INTO portfolio
      FROM public.lf_capability_current c
      JOIN public.lf_capability_version_registry v
        ON v.capability_code=c.capability_code AND v.version=c.version
     WHERE c.capability_code='METHOD_PACK_REGISTRY'
       AND v.release_state='RELEASED';
    IF jsonb_typeof(portfolio)<>'array'
       OR jsonb_typeof(p_payload->'selected_methods')<>'array'
    THEN RETURN 'EVOLUTION_METHOD_PORTFOLIO_INVALID'; END IF;

    IF jsonb_array_length(p_payload->'selected_methods')=0 THEN
      IF p_payload->'no_additional_method_needed' IS DISTINCT FROM 'true'::jsonb
         OR nullif(btrim(p_payload->>'empty_selection_reason'),'') IS NULL
      THEN RETURN 'EVOLUTION_EMPTY_METHOD_UNJUSTIFIED'; END IF;
    ELSE
      IF p_payload->'no_additional_method_needed'='true'::jsonb THEN
        RETURN 'EVOLUTION_METHOD_SELECTION_CONTRADICTORY';
      END IF;
    END IF;
    FOR r IN SELECT value AS item FROM jsonb_array_elements(p_payload->'selected_methods')
    LOOP
      IF jsonb_typeof(r.item)<>'object' OR
         nullif(btrim(r.item->>'method_id'),'') IS NULL OR
         nullif(btrim(r.item->>'exact_version'),'') IS NULL OR
         nullif(btrim(r.item->>'receipt_id'),'') IS NULL
      THEN RETURN 'EVOLUTION_METHOD_RECORD_INVALID'; END IF;
      SELECT item INTO method_data
        FROM jsonb_array_elements(portfolio) item
       WHERE item->>'method_id'=r.item->>'method_id'
         AND item->>'exact_version'=r.item->>'exact_version'
         AND item->>'qualification_state'='QUALIFIED'
       LIMIT 1;
      IF method_data IS NULL THEN RETURN 'EVOLUTION_METHOD_NOT_QUALIFIED'; END IF;
      IF NOT public.lf_profile_update_verified_receipt_v1(
        'METHOD_QUALIFICATION',
        (r.item->>'method_id')||'@'||(r.item->>'exact_version'),
        r.item->>'receipt_id',
        r.item->>'subject_sha256',
        r.item->>'source_head_sha'
      ) THEN RETURN 'EVOLUTION_METHOD_QUALIFICATION_UNVERIFIED'; END IF;
    END LOOP;
    IF p_payload->'method_execution_permitted' IS DISTINCT FROM 'false'::jsonb
    THEN RETURN 'EVOLUTION_SELECTION_ILLEGAL_EXECUTION_PERMISSION'; END IF;
    RETURN NULL;
  END IF;

  SELECT * INTO recorded FROM public.lf_operation_execution_steps
   WHERE execution_id=p_execution_id AND step_id='method_selection';
  IF NOT FOUND OR recorded.status <> 'STEP_PASS_WITH_EVIDENCE'
     OR recorded.evidence_payload->>'recorded_by_rpc'<>'lf_record_profile_operation_step_v1'
     OR recorded.evidence_payload->>'mini_judge_result'<>'STEP_PASS_WITH_EVIDENCE'
  THEN RETURN 'EVOLUTION_SELECTION_STEP_NOT_CLEAN'; END IF;
  IF recorded.evidence_payload->>'profile_assessment_receipt_id'
     IS DISTINCT FROM p_payload->>'profile_assessment_receipt_id'
  THEN RETURN 'EVOLUTION_DECISION_ASSESSMENT_RECEIPT_MISMATCH'; END IF;
  decision:=p_payload->>'decision';
  mode:=p_payload->>'evolution_mode';
  IF decision='NO_CHANGE' AND mode<>'NO_CHANGE' THEN
    RETURN 'EVOLUTION_NO_CHANGE_MODE_INVALID';
  ELSIF decision='UPDATE' AND mode NOT IN ('PATCH','SPECIALIZE','ADAPT','REARCHITECT','OPTIMIZE')
  THEN RETURN 'EVOLUTION_UPDATE_MODE_INVALID';
  ELSIF decision IS NULL OR decision NOT IN ('NO_CHANGE','UPDATE')
  THEN RETURN 'EVOLUTION_DECISION_NOT_ADMITTED';
  END IF;
  IF nullif(btrim(p_payload->>'decision_evidence_ref'),'') IS NULL THEN
    RETURN 'EVOLUTION_DECISION_EVIDENCE_MISSING';
  END IF;
  IF p_payload->'github_write_permitted' IS DISTINCT FROM 'false'::jsonb THEN
    RETURN 'EVOLUTION_DECISION_CANNOT_AUTHORIZE_WRITE';
  END IF;
  RETURN NULL;
END;
$guard$;

-- Keep this check as one component of the existing substantive recorder.
-- The registered judge must additionally verify typed assertions and
-- no outstanding blockers. No direct PASS is returned or declared here.
