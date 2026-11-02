-- LF Profile Updater: append-only candidate revision within the ORIGINAL governed execution.
-- No new table, operation, step, executor or replay of historical github_write/github_readback.
-- Deployment governed separately; do not run directly outside Merge Train / migration transport.
CREATE OR REPLACE FUNCTION public.lf_profile_update_candidate_amend_v1(
  p_execution_id text,
  p_previous_commit text,
  p_candidate_commit text,
  p_evidence jsonb,
  p_actor_execution_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $fn$
DECLARE
  v_exec public.lf_operation_execution%rowtype;
  v_write public.lf_operation_execution_steps%rowtype;
  v_readback public.lf_operation_execution_steps%rowtype;
  v_prior text;
  v_branch text;
  v_entries jsonb;
  v_last jsonb;
  v_receipt jsonb;
  v_now timestamptz := statement_timestamp();
BEGIN
  IF p_execution_id IS NULL OR p_actor_execution_id IS DISTINCT FROM p_execution_id
     OR p_previous_commit !~ '^[0-9a-f]{40}$'
     OR p_candidate_commit !~ '^[0-9a-f]{40}$'
     OR p_previous_commit = p_candidate_commit
     OR jsonb_typeof(p_evidence) IS DISTINCT FROM 'object'
  THEN RETURN jsonb_build_object('outcome','BLOCKED','code','PROFILE_AMEND_INPUT_INVALID'); END IF;

  SELECT * INTO v_exec FROM public.lf_operation_execution WHERE execution_id = p_execution_id FOR UPDATE;
  IF NOT FOUND OR v_exec.operation_code <> 'ACTUALIZACION_PERFIL_LF'
     OR v_exec.status <> 'IN_PROGRESS'
     OR v_exec.target_type <> 'PERFIL'
     OR NULLIF(btrim(v_exec.target_repo),'') IS NULL
     OR coalesce(v_exec.manifest->>'router_semantic_receipt_sha256','') = ''
  THEN RETURN jsonb_build_object('outcome','BLOCKED','code','PROFILE_AMEND_EXECUTION_NOT_ELIGIBLE'); END IF;

  SELECT * INTO v_write FROM public.lf_operation_execution_steps
    WHERE execution_id=p_execution_id AND step_id='github_write';
  SELECT * INTO v_readback FROM public.lf_operation_execution_steps
    WHERE execution_id=p_execution_id AND step_id='github_readback';
  IF v_write.status IS DISTINCT FROM 'STEP_PASS_WITH_EVIDENCE'
     OR v_readback.status IS DISTINCT FROM 'STEP_PASS_WITH_EVIDENCE'
     OR v_write.evidence_payload->>'server_trust_context_source' IS DISTINCT FROM 'run-creacion-perfil-lf'
     OR v_readback.evidence_payload->>'server_trust_context_source' IS DISTINCT FROM 'run-creacion-perfil-lf'
     OR v_write.evidence_payload->>'server_trust_context_valid' IS DISTINCT FROM 'true'
     OR v_readback.evidence_payload->>'server_trust_context_valid' IS DISTINCT FROM 'true'
     OR v_write.evidence_payload->>'commit_sha' IS DISTINCT FROM v_readback.evidence_payload->>'exact_head'
  THEN RETURN jsonb_build_object('outcome','BLOCKED','code','PROFILE_AMEND_ORIGINAL_RECEIPTS_UNVERIFIED'); END IF;

  IF EXISTS (
    SELECT 1 FROM public.lf_operation_execution_steps
    WHERE execution_id=p_execution_id AND step_order >= 90
  ) THEN RETURN jsonb_build_object('outcome','BLOCKED','code','PROFILE_AMEND_AFTER_VALIDATION_FORBIDDEN'); END IF;

  v_entries := coalesce(v_exec.manifest->'candidate_amendments','[]'::jsonb);
  IF jsonb_typeof(v_entries) IS DISTINCT FROM 'array'
  THEN RETURN jsonb_build_object('outcome','BLOCKED','code','PROFILE_AMEND_CHAIN_INVALID'); END IF;
  IF jsonb_array_length(v_entries) >= 50
  THEN RETURN jsonb_build_object('outcome','BLOCKED','code','PROFILE_AMEND_CHAIN_LIMIT_REACHED'); END IF;
  IF jsonb_array_length(v_entries)>0 THEN
    v_last := v_entries->(jsonb_array_length(v_entries)-1);
    v_prior := v_last->>'candidate_commit';
  ELSE
    v_prior := v_write.evidence_payload->>'commit_sha';
  END IF;
  v_branch := v_write.evidence_payload->>'branch';

  -- True idempotent replay, including the exact same bound predecessor and verified receipt.
  IF v_last IS NOT NULL AND v_last->>'candidate_commit'=p_candidate_commit
     AND v_last->>'previous_commit'=p_previous_commit
     AND (v_last->'verified_source' - 'observed_at') = (p_evidence - 'observed_at')
  THEN RETURN jsonb_build_object('outcome','AMENDMENT_RECORDED','replay',true,'execution_id',p_execution_id,
         'candidate_commit',p_candidate_commit,'amendment_count',jsonb_array_length(v_entries)); END IF;

  IF v_prior IS DISTINCT FROM p_previous_commit
  THEN RETURN jsonb_build_object('outcome','BLOCKED','code','PROFILE_AMEND_STALE_PREDECESSOR',
                'effective_candidate_commit',v_prior); END IF;

  -- Only trust source data that was recomputed by the existing OIDC authorized edge runtime.
  IF p_evidence->>'source' IS DISTINCT FROM 'run-creacion-perfil-lf'
     OR p_evidence->>'resolver' IS DISTINCT FROM 'GITHUB_PROFILE_AMENDMENT_V1'
     OR p_evidence->>'repository' IS DISTINCT FROM v_exec.target_repo
     OR p_evidence->>'target_root_path' IS DISTINCT FROM v_exec.manifest->>'target_root_path'
     OR p_evidence->>'branch' IS DISTINCT FROM v_branch
     OR p_evidence->>'previous_commit' IS DISTINCT FROM p_previous_commit
     OR p_evidence->>'candidate_commit' IS DISTINCT FROM p_candidate_commit
     OR p_evidence->>'identity_preserved' IS DISTINCT FROM 'true'
     OR p_evidence->>'head_verified' IS DISTINCT FROM 'true'
     OR jsonb_typeof(p_evidence->'changed_profile_files') IS DISTINCT FROM 'array'
  THEN RETURN jsonb_build_object('outcome','BLOCKED','code','PROFILE_AMEND_SERVER_PROOF_INVALID'); END IF;

  IF jsonb_array_length(p_evidence->'changed_profile_files') = 0 THEN
    RETURN jsonb_build_object('outcome','BLOCKED','code','PROFILE_AMEND_PROFILE_DIFF_EMPTY');
  END IF;

  v_receipt := jsonb_build_object(
    'ordinal',jsonb_array_length(v_entries)+1,'previous_commit',p_previous_commit,
    'candidate_commit',p_candidate_commit,'branch',v_branch,'recorded_at',v_now,
    'actor_execution_id',p_actor_execution_id,'verified_source',p_evidence
  );
  UPDATE public.lf_operation_execution
    SET manifest=jsonb_set(manifest,'{candidate_amendments}',v_entries||jsonb_build_array(v_receipt),true),
        updated_by_execution_id=p_actor_execution_id,updated_at=v_now
    WHERE execution_id=p_execution_id;
  RETURN jsonb_build_object('outcome','AMENDMENT_RECORDED','replay',false,'execution_id',p_execution_id,
         'previous_commit',p_previous_commit,'candidate_commit',p_candidate_commit,
         'amendment_count',jsonb_array_length(v_entries)+1,'original_step70_immutable',true,
         'original_step80_immutable',true);
END
$fn$;
COMMENT ON FUNCTION public.lf_profile_update_candidate_amend_v1(text,text,text,jsonb,text) IS
'Append a server-verified candidate revision to the existing updater manifest; original step70/80 never changed; before step90 only.';
REVOKE ALL ON FUNCTION public.lf_profile_update_candidate_amend_v1(text,text,text,jsonb,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.lf_profile_update_candidate_amend_v1(text,text,text,jsonb,text) TO service_role;
