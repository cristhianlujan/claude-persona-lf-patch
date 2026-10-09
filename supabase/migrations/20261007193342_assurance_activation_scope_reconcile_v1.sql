-- Reconcile ASSURANCE_EVALUATOR activation authority using append-only Assurance catalogs.
-- Removes the accidental global dependency on full PASE F06/F09/F10 completion.
-- New rule: exact orchestrator dispatch receipt + exact subject binding + explicit human GO.
-- Historical V1 rows remain immutable; corrected claim/obligation/defeater/binding rows are V2.

DO $pre$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_capability_current
    WHERE capability_code='ASSURANCE_EVALUATOR' AND version='1.0.0'
  ) THEN
    RAISE EXCEPTION 'BLOCK_ASSURANCE_SCOPE_RECONCILE_CURRENT_PRESTATE';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_assurance_subject_bindings
    WHERE binding_code='BIND-INPUT-GOVERNANCE-CONTRACT-5_13-ASSURANCE-V1'
      AND subject_type='OPERATION'
      AND subject_code='EJECUCION_INPUT_GOVERNANCE_LF'
      AND standard_claim_code='INPUT_GOVERNANCE_CONTRACT_5_13_ASSURANCE_V1'
      AND standard_claim_version=1
      AND status='CANDIDATO'
  ) THEN
    RAISE EXCEPTION 'BLOCK_ASSURANCE_SCOPE_RECONCILE_IG_BINDING_PRESTATE';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.lf_assurance_subject_bindings
    WHERE status='ACTIVE' AND subject_code='*'
  ) THEN
    RAISE EXCEPTION 'BLOCK_ASSURANCE_SCOPE_RECONCILE_ACTIVE_WILDCARD';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.lf_assurance_claim_catalog
    WHERE claim_code='INPUT_GOVERNANCE_CONTRACT_5_13_ASSURANCE_V1' AND version=2
  ) OR EXISTS (
    SELECT 1 FROM public.lf_capability_version_registry
    WHERE capability_code='ASSURANCE_EVALUATOR' AND version='1.0.1'
  ) THEN
    RAISE EXCEPTION 'BLOCK_ASSURANCE_SCOPE_RECONCILE_ALREADY_MATERIALIZED';
  END IF;
END
$pre$;

CREATE OR REPLACE FUNCTION public.fn_lf_assurance_subject_binding_activate_v1(
  p_candidate_binding_code text,
  p_active_binding_code text,
  p_consumer_execution_id text,
  p_dispatch_receipt_id uuid,
  p_human_go_ref text,
  p_actor_execution_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','private','extensions'
AS $function$
DECLARE
  v_candidate public.lf_assurance_subject_bindings%rowtype;
  v_existing public.lf_assurance_subject_bindings%rowtype;
  v_receipt private.lf_orchestrator_dispatch_receipts_v1%rowtype;
  v_cap_binding public.lf_capability_binding%rowtype;
  v_current public.lf_capability_current%rowtype;
  v_capability_code text;
BEGIN
  IF btrim(coalesce(p_candidate_binding_code,''))='' OR
     btrim(coalesce(p_active_binding_code,''))='' OR
     btrim(coalesce(p_consumer_execution_id,''))='' OR
     p_dispatch_receipt_id IS NULL OR
     btrim(coalesce(p_human_go_ref,''))='' OR
     btrim(coalesce(p_actor_execution_id,''))='' THEN
    RETURN jsonb_build_object('ready',false,'decision','BLOCK_INVALID_ACTIVATION_IDENTITY');
  END IF;

  SELECT * INTO v_candidate
  FROM public.lf_assurance_subject_bindings
  WHERE binding_code=p_candidate_binding_code;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ready',false,'decision','BLOCK_UNKNOWN_CANDIDATE_SUBJECT_BINDING');
  END IF;
  IF v_candidate.status<>'CANDIDATO' THEN
    RETURN jsonb_build_object('ready',false,'decision','BLOCK_SUBJECT_BINDING_NOT_CANDIDATE','status',v_candidate.status);
  END IF;
  IF v_candidate.subject_code='*' THEN
    RETURN jsonb_build_object('ready',false,'decision','BLOCK_WILDCARD_SUBJECT_BINDING');
  END IF;

  v_capability_code := v_candidate.activation_condition->>'capability_code';
  IF btrim(coalesce(v_capability_code,''))='' THEN
    RETURN jsonb_build_object('ready',false,'decision','BLOCK_BINDING_CAPABILITY_UNDECLARED');
  END IF;

  SELECT * INTO v_receipt
  FROM private.lf_orchestrator_dispatch_receipts_v1
  WHERE receipt_id=p_dispatch_receipt_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ready',false,'decision','BLOCK_UNKNOWN_ORCHESTRATOR_DISPATCH_RECEIPT');
  END IF;

  IF v_receipt.consumer_execution_id IS DISTINCT FROM p_consumer_execution_id
     OR v_receipt.capability_code IS DISTINCT FROM v_capability_code
     OR v_receipt.dispatch_scope->>'candidate_binding_code' IS DISTINCT FROM p_candidate_binding_code
     OR v_receipt.dispatch_scope->>'active_binding_code' IS DISTINCT FROM p_active_binding_code
     OR v_receipt.dispatch_scope->>'subject_type' IS DISTINCT FROM v_candidate.subject_type
     OR v_receipt.dispatch_scope->>'subject_code' IS DISTINCT FROM v_candidate.subject_code
     OR v_receipt.dispatch_scope->>'human_go_ref' IS DISTINCT FROM p_human_go_ref THEN
    RETURN jsonb_build_object('ready',false,'decision','BLOCK_SUBJECT_ACTIVATION_CROSSBIND_MISMATCH');
  END IF;

  SELECT * INTO v_cap_binding
  FROM public.lf_capability_binding
  WHERE execution_id=p_consumer_execution_id
    AND capability_code=v_capability_code
    AND binding_state='BOUND';

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ready',false,'decision','BLOCK_CAPABILITY_NOT_BOUND_FROM_ORCHESTRATOR');
  END IF;

  SELECT * INTO v_current
  FROM public.lf_capability_current
  WHERE capability_code=v_capability_code;

  IF NOT FOUND OR
     v_cap_binding.bound_version IS DISTINCT FROM v_current.version OR
     v_cap_binding.bound_manifest_sha256 IS DISTINCT FROM v_current.manifest_sha256 THEN
    RETURN jsonb_build_object('ready',false,'decision','BLOCK_CAPABILITY_BINDING_NOT_CURRENT');
  END IF;

  SELECT * INTO v_existing
  FROM public.lf_assurance_subject_bindings
  WHERE binding_code=p_active_binding_code;

  IF FOUND THEN
    IF v_existing.status='ACTIVE'
       AND v_existing.subject_type=v_candidate.subject_type
       AND v_existing.subject_code=v_candidate.subject_code
       AND v_existing.activation_condition->>'activated_receipt_id'=p_dispatch_receipt_id::text THEN
      RETURN jsonb_build_object(
        'ready',true,'decision','ACTIVE_BINDING_REPLAY',
        'binding_code',v_existing.binding_code,
        'subject_type',v_existing.subject_type,
        'subject_code',v_existing.subject_code,
        'capability_code',v_capability_code
      );
    END IF;
    RETURN jsonb_build_object('ready',false,'decision','BLOCK_ACTIVE_BINDING_CODE_COLLISION');
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.lf_assurance_subject_bindings b
    WHERE b.subject_type=v_candidate.subject_type
      AND b.subject_code=v_candidate.subject_code
      AND b.status='ACTIVE'
  ) THEN
    RETURN jsonb_build_object('ready',false,'decision','BLOCK_AMBIGUOUS_ACTIVE_SUBJECT_BINDING');
  END IF;

  INSERT INTO public.lf_assurance_subject_bindings(
    binding_code,subject_type,subject_code,standard_claim_code,standard_claim_version,
    benchmark_suite_code,activation_condition,required,status,source_ref,created_by_execution_id
  ) VALUES (
    p_active_binding_code,
    v_candidate.subject_type,
    v_candidate.subject_code,
    v_candidate.standard_claim_code,
    v_candidate.standard_claim_version,
    v_candidate.benchmark_suite_code,
    coalesce(v_candidate.activation_condition,'{}'::jsonb) || jsonb_build_object(
      'mode','ACTIVE_EXACT_ORCHESTRATOR_RECEIPT_PLUS_HUMAN_GO',
      'global_pase_phase_completion_required',false,
      'orchestrator_dispatch_receipt_required',true,
      'human_go_required',true,
      'activated_receipt_id',p_dispatch_receipt_id::text,
      'activated_consumer_execution_id',p_consumer_execution_id,
      'human_go_ref',p_human_go_ref,
      'activated_by_execution_id',p_actor_execution_id,
      'activated_at',clock_timestamp()
    ),
    v_candidate.required,
    'ACTIVE',
    coalesce(v_candidate.source_ref,'') || ';supabase://private/lf_orchestrator_dispatch_receipts_v1/' || p_dispatch_receipt_id::text,
    p_actor_execution_id
  );

  RETURN jsonb_build_object(
    'ready',true,'decision','SUBJECT_BINDING_ACTIVATED_APPEND_ONLY',
    'binding_code',p_active_binding_code,
    'candidate_binding_code',p_candidate_binding_code,
    'subject_type',v_candidate.subject_type,
    'subject_code',v_candidate.subject_code,
    'capability_code',v_capability_code,
    'dispatch_receipt_id',p_dispatch_receipt_id,
    'human_go_ref',p_human_go_ref
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_lf_assurance_subject_binding_activate_v1(text,text,text,uuid,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_lf_assurance_subject_binding_activate_v1(text,text,text,uuid,text,text) TO service_role;

DO $reconcile$
DECLARE
  v_exec constant text := 'CHATGPT-ASSURANCE-ACTIVATION-SCOPE-RECONCILE-20261007';
  v_old_manifest jsonb;
  v_old_sha text;
  v_docs text;
  v_validator text;
  v_manifest jsonb;
  v_new_sha text;
  v_promote jsonb;
BEGIN
  INSERT INTO public.lf_assurance_claim_catalog(
    claim_code,version,parent_claim_code,parent_claim_version,subject_type,subject_code,
    claim_class,claim_text,criticality,applicability,closure_rule,methodology_version,
    status,source_ref,created_by_execution_id
  )
  SELECT
    claim_code,2,parent_claim_code,parent_claim_version,subject_type,subject_code,
    claim_class,claim_text,criticality,applicability,
    (coalesce(closure_rule,'{}'::jsonb) - 'activation_requires') || jsonb_build_object(
      'activation_authority','EXACT_ORCHESTRATOR_DISPATCH_RECEIPT_PLUS_EXPLICIT_HUMAN_GO',
      'global_pase_phase_completion_required',false
    ),
    methodology_version,status,
    coalesce(source_ref,'') || '#activation-scope-reconcile-v2',
    v_exec
  FROM public.lf_assurance_claim_catalog
  WHERE claim_code='INPUT_GOVERNANCE_CONTRACT_5_13_ASSURANCE_V1' AND version=1;

  INSERT INTO public.lf_assurance_obligation_catalog(
    obligation_code,version,claim_code,claim_version,requirement_ref,implementation_ref,
    condition_ref,verification_method,positive_test_ref,negative_test_ref,adversarial_test_ref,
    structural_coverage_mode,evidence_contract,failure_taxonomy_code,required,status,
    source_ref,created_by_execution_id
  )
  SELECT
    obligation_code,2,claim_code,2,requirement_ref,implementation_ref,
    condition_ref,verification_method,positive_test_ref,negative_test_ref,adversarial_test_ref,
    structural_coverage_mode,evidence_contract,failure_taxonomy_code,required,status,
    coalesce(source_ref,'') || '#activation-scope-reconcile-v2',
    v_exec
  FROM public.lf_assurance_obligation_catalog
  WHERE claim_code='INPUT_GOVERNANCE_CONTRACT_5_13_ASSURANCE_V1' AND claim_version=1;

  INSERT INTO public.lf_assurance_defeater_catalog(
    defeater_code,version,claim_code,claim_version,obligation_code,defeater_class,
    description,required_counterevidence,zero_effect_required,status,source_ref,created_by_execution_id
  )
  SELECT
    defeater_code,2,claim_code,2,obligation_code,defeater_class,
    description,required_counterevidence,zero_effect_required,status,
    coalesce(source_ref,'') || '#activation-scope-reconcile-v2',
    v_exec
  FROM public.lf_assurance_defeater_catalog
  WHERE claim_code='INPUT_GOVERNANCE_CONTRACT_5_13_ASSURANCE_V1' AND claim_version=1;

  INSERT INTO public.lf_assurance_subject_bindings(
    binding_code,subject_type,subject_code,standard_claim_code,standard_claim_version,
    benchmark_suite_code,activation_condition,required,status,source_ref,created_by_execution_id
  )
  SELECT
    'BIND-INPUT-GOVERNANCE-CONTRACT-5_13-ASSURANCE-V2',
    subject_type,subject_code,standard_claim_code,2,
    benchmark_suite_code,
    (coalesce(activation_condition,'{}'::jsonb) - 'activation_decision') || jsonb_build_object(
      'mode','CANDIDATE_EXACT_ORCHESTRATOR_RECEIPT_PLUS_HUMAN_GO',
      'activation_authority','EXACT_ORCHESTRATOR_DISPATCH_RECEIPT_PLUS_EXPLICIT_HUMAN_GO',
      'global_pase_phase_completion_required',false,
      'orchestrator_dispatch_receipt_required',true,
      'human_go_required',true,
      'canonical_entrypoint','public.fn_lf_capability_bind_from_orchestrator_v1'
    ),
    required,'CANDIDATO',
    coalesce(source_ref,'') || '#activation-scope-reconcile-v2',
    v_exec
  FROM public.lf_assurance_subject_bindings
  WHERE binding_code='BIND-INPUT-GOVERNANCE-CONTRACT-5_13-ASSURANCE-V1';

  SELECT vr.manifest,c.manifest_sha256,vr.docs_ref,vr.validator_ref
    INTO v_old_manifest,v_old_sha,v_docs,v_validator
  FROM public.lf_capability_current c
  JOIN public.lf_capability_version_registry vr
    ON vr.capability_code=c.capability_code AND vr.version=c.version
  WHERE c.capability_code='ASSURANCE_EVALUATOR' AND c.version='1.0.0';

  IF v_old_manifest IS NULL THEN
    RAISE EXCEPTION 'BLOCK_ASSURANCE_SCOPE_RECONCILE_CURRENT_READ';
  END IF;

  v_manifest := v_old_manifest || jsonb_build_object(
    'version','1.0.1',
    'mode','CURRENT_AVAILABLE_ENTRY_GUARDED'
  );
  v_manifest := jsonb_set(v_manifest,'{compatibility,entry_guard_required_live}','true'::jsonb,true);
  v_manifest := jsonb_set(v_manifest,'{entry,guard_enforcement_state}',to_jsonb('REQUIRED_EXACT_ORCHESTRATOR_RECEIPT_PLUS_EXPLICIT_HUMAN_GO'::text),true);
  v_manifest := jsonb_set(v_manifest,'{entry,activation_authority}',to_jsonb('EXACT_ORCHESTRATOR_DISPATCH_RECEIPT_PLUS_EXPLICIT_HUMAN_GO'::text),true);
  v_manifest := jsonb_set(v_manifest,'{entry,global_pase_phase_completion_required}','false'::jsonb,true);
  v_manifest := jsonb_set(v_manifest,'{migration,subject_binding_activation}','false'::jsonb,true);
  v_manifest := jsonb_set(v_manifest,'{currentness,authority_ref}',to_jsonb('github://cristhianlujan/claude-persona-lf-patch/supabase/migrations/20261007191500_assurance_activation_scope_reconcile_v1.sql'::text),true);
  v_new_sha := encode(extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),'hex');

  INSERT INTO public.lf_capability_version_registry(
    capability_code,version,version_major,version_minor,version_patch,release_state,supersedes_version,
    manifest,manifest_sha256,source_ref,docs_ref,validator_ref,created_by_execution_id
  ) VALUES (
    'ASSURANCE_EVALUATOR','1.0.1',1,0,1,'RELEASED','1.0.0',
    v_manifest,v_new_sha,
    'github://cristhianlujan/claude-persona-lf-patch/supabase/migrations/20261007191500_assurance_activation_scope_reconcile_v1.sql',
    v_docs,v_validator,v_exec
  );

  UPDATE public.lf_capability_registry
  SET entry_guard_required=true,
      entry_guard_code='ORCHESTRATOR_EXECUTION_GUARD_V1',
      updated_at=clock_timestamp(),
      updated_by_execution_id=v_exec
  WHERE capability_code='ASSURANCE_EVALUATOR';

  UPDATE public.lf_activos
  SET raw_payload=coalesce(raw_payload,'{}'::jsonb) || jsonb_build_object(
        'status','CURRENT_AVAILABLE_ENTRY_GUARDED',
        'current_pointer_present',true,
        'entry_guard_enforced',true,
        'runtime_authorized',false,
        'production_authorized',false
      ),
      metadata=jsonb_set(
        coalesce(metadata,'{}'::jsonb),
        '{entry_contract,enforcement_state}',
        to_jsonb('REQUIRED_EXACT_ORCHESTRATOR_RECEIPT_PLUS_EXPLICIT_HUMAN_GO'::text),
        true
      ),
      updated_at=clock_timestamp(),
      updated_by_execution_id=v_exec
  WHERE codigo_activo='ASSURANCE_EVALUATOR' AND archived_at IS NULL;

  v_promote := public.fn_lf_capability_promote_v1(
    'ASSURANCE_EVALUATOR','1.0.1',v_old_sha,v_exec,
    'Remove accidental global F06/F09/F10 dependency; enforce exact orchestrator receipt plus explicit human GO for subject-scoped activation.'
  );
  IF coalesce((v_promote->>'ready')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'BLOCK_ASSURANCE_SCOPE_RECONCILE_PROMOTION:%',v_promote::text;
  END IF;
END
$reconcile$;

DO $readback$
DECLARE
  v_obligations integer;
  v_defeaters integer;
BEGIN
  SELECT count(*) INTO v_obligations
  FROM public.lf_assurance_obligation_catalog
  WHERE claim_code='INPUT_GOVERNANCE_CONTRACT_5_13_ASSURANCE_V1' AND claim_version=2;

  SELECT count(*) INTO v_defeaters
  FROM public.lf_assurance_defeater_catalog
  WHERE claim_code='INPUT_GOVERNANCE_CONTRACT_5_13_ASSURANCE_V1' AND claim_version=2;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_capability_current
    WHERE capability_code='ASSURANCE_EVALUATOR' AND version='1.0.1'
  ) THEN RAISE EXCEPTION 'BLOCK_ASSURANCE_SCOPE_RECONCILE_CURRENT_101'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_capability_registry
    WHERE capability_code='ASSURANCE_EVALUATOR'
      AND entry_guard_required IS TRUE
      AND entry_guard_code='ORCHESTRATOR_EXECUTION_GUARD_V1'
  ) THEN RAISE EXCEPTION 'BLOCK_ASSURANCE_SCOPE_RECONCILE_ENTRY_GUARD'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_assurance_claim_catalog
    WHERE claim_code='INPUT_GOVERNANCE_CONTRACT_5_13_ASSURANCE_V1'
      AND version=2
      AND closure_rule->>'global_pase_phase_completion_required'='false'
  ) THEN RAISE EXCEPTION 'BLOCK_ASSURANCE_SCOPE_RECONCILE_CLAIM_V2'; END IF;

  IF v_obligations<>60 THEN
    RAISE EXCEPTION 'BLOCK_ASSURANCE_SCOPE_RECONCILE_OBLIGATION_COUNT:%',v_obligations;
  END IF;

  IF v_defeaters<>6 THEN
    RAISE EXCEPTION 'BLOCK_ASSURANCE_SCOPE_RECONCILE_DEFEATER_COUNT:%',v_defeaters;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_assurance_subject_bindings
    WHERE binding_code='BIND-INPUT-GOVERNANCE-CONTRACT-5_13-ASSURANCE-V2'
      AND standard_claim_version=2
      AND status='CANDIDATO'
      AND activation_condition->>'global_pase_phase_completion_required'='false'
      AND activation_condition->>'orchestrator_dispatch_receipt_required'='true'
      AND activation_condition->>'human_go_required'='true'
  ) THEN RAISE EXCEPTION 'BLOCK_ASSURANCE_SCOPE_RECONCILE_BINDING_V2'; END IF;
END
$readback$;
