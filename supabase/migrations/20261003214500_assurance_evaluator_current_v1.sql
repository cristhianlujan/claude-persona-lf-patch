-- ASSURANCE_EVALUATOR v1.0.0 current promotion.
-- Owner: SUPER_ADMIN.
-- Scope: promote the existing fail-closed evaluator source bundle to CURRENT availability only.
-- Execution remains deferred: no ACTIVE subject binding, no entry-guard activation, no PASE-global gate,
-- no ASSURANCE_COMPLETENESS reintroduction, no runtime/deploy/production cutover.
-- EKB: ASSURANCE-METHOD-CANDIDATE-NOT-PASE-CONTROL-001;
--      ASSURANCE-EVALUATOR-REVIEW-REFERENCE-NO-PROVIDER-BOUND-READBACK-001;
--      ASSURANCE-ORCHESTRATOR-ENTRYPOINT-GAP-001.

DO $pre$
DECLARE
  v_count integer;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_capability_registry
    WHERE capability_code='ASSURANCE_EVALUATOR'
      AND capability_kind='TRANSVERSAL'
      AND owner_scope='SUPER_ADMIN'
      AND status='ACTIVE'
      AND entry_guard_required IS FALSE
      AND entry_guard_code='ORCHESTRATOR_EXECUTION_GUARD_V1'
  ) THEN
    RAISE EXCEPTION 'BLOCK_ASSURANCE_EVALUATOR_REGISTRY_PRESTATE';
  END IF;

  SELECT count(*) INTO v_count FROM public.lf_capability_current
  WHERE capability_code='ASSURANCE_EVALUATOR';
  IF v_count<>0 THEN
    RAISE EXCEPTION 'BLOCK_ASSURANCE_EVALUATOR_CURRENT_ALREADY_PRESENT:%',v_count;
  END IF;

  SELECT count(*) INTO v_count FROM public.lf_capability_version_registry
  WHERE capability_code='ASSURANCE_EVALUATOR';
  IF v_count<>0 THEN
    RAISE EXCEPTION 'BLOCK_ASSURANCE_EVALUATOR_VERSION_ALREADY_PRESENT:%',v_count;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_activos
    WHERE codigo_activo='ASSURANCE_EVALUATOR'
      AND archived_at IS NULL
      AND estado_documental='VIGENTE'
      AND estado_operativo='READ_ONLY'
      AND runtime_estado='NO_HABILITADO'
      AND owner_name='SUPER_ADMIN'
      AND metadata#>>'{entry_contract,guard_code}'='ORCHESTRATOR_EXECUTION_GUARD_V1'
      AND metadata#>>'{entry_contract,required}'='true'
  ) THEN
    RAISE EXCEPTION 'BLOCK_ASSURANCE_EVALUATOR_ASSET_PRESTATE';
  END IF;

  SELECT count(*) INTO v_count
  FROM public.lf_assurance_subject_bindings
  WHERE status='ACTIVE';
  IF v_count<>0 THEN
    RAISE EXCEPTION 'BLOCK_ASSURANCE_EVALUATOR_GLOBAL_ACTIVE_BINDING_PRESTATE:%',v_count;
  END IF;
END
$pre$;

DO $promote$
DECLARE
  v_execution_id constant text := 'CHATGPT-SADM-ASSURANCE-EVALUATOR-CURRENT-20261003';
  v_manifest jsonb;
  v_manifest_sha text;
  v_promote jsonb;
BEGIN
  v_manifest := jsonb_build_object(
    'schema_version','LF_CAPABILITY_MANIFEST_V1',
    'capability_code','ASSURANCE_EVALUATOR',
    'version','1.0.0',
    'owner','SUPER_ADMIN',
    'mode','CURRENT_AVAILABLE_EXECUTION_DEFERRED',
    'contract',jsonb_build_object(
      'input','exact Router applicability + exact ACTIVE subject binding + canonical claim/obligation/defeater/evidence snapshots',
      'output','lf-assurance-evaluator-runner-result/v1',
      'result_states',jsonb_build_array('PASS','FAIL','OPEN','UNPROVEN','FALSE_PASS_RISK'),
      'no_global_gate',true
    ),
    'source_bundle',jsonb_build_object(
      'base_head','3f275d5f2bc114afe46ef94672cc34d57f33ebf2',
      'core',jsonb_build_object('path','sandbox/lf_contract_gate_test/assurance_evaluator_boundary/assurance_evaluator_core_v1.py','git_blob_sha1','640a21915751bb31b21a38bf137995faf4872c6b'),
      'runner',jsonb_build_object('path','sandbox/lf_contract_gate_test/assurance_evaluator_boundary/assurance_evaluator_runner_v1.py','git_blob_sha1','4300d74065b838165339ad45f6cbdc35c7410cca'),
      'activation_gate',jsonb_build_object('path','sandbox/lf_contract_gate_test/assurance_evaluator_boundary/assurance_activation_gate_v1.py','git_blob_sha1','b68311402b2219bb080120dba14b4beb7f842e47'),
      'legacy_review_guard',jsonb_build_object('path','sandbox/lf_contract_gate_test/assurance_evaluator_boundary/assurance_legacy_s36_guard_v1.py','git_blob_sha1','7b342bd00e46779151789c15131165a6faf660a9'),
      'call_contract',jsonb_build_object(
        'path','sandbox/lf_contract_gate_test/assurance_evaluator_boundary/assurance_evaluator_call_contract_v1.json',
        'git_blob_sha1','9fc00c172ab97b83d17354bbb2a4e99f6e418705',
        'sha256','3a17d94b182dea4793592571913084ac3ceb1d40d954cb055e6c3ceb43038a20'
      ),
      'core_test',jsonb_build_object('path','sandbox/lf_contract_gate_test/assurance_evaluator_boundary/test_assurance_evaluator_core_v1.py','git_blob_sha1','252501053c3cf1a6a2471cfeb9bd2e52542f8bd6','observed_checks',16),
      'activation_qualification_event','supabase://public/lf_eventos/19934'
    ),
    'entry',jsonb_build_object(
      'guard','ORCHESTRATOR_EXECUTION_GUARD_V1',
      'guard_contract_declared',true,
      'guard_enforcement_state','DEFERRED_UNTIL_PASE_F06_F09_F10_PLUS_EXPLICIT_HUMAN_GO',
      'bind_entrypoint','public.fn_lf_capability_bind_from_orchestrator_v1',
      'activation_gate','ASSURANCE_ACTIVATION_GATE_V1',
      'subject_binding_policy','EXACT_ACTIVE_ONLY',
      'wildcard_active_binding','BLOCK'
    ),
    'limitations',jsonb_build_object(
      'independent_review_without_provider_bound_receipt','UNPROVEN',
      'unsupported_closure_semantics','UNPROVEN',
      'direct_database_discovery',false,
      'evidence_write_owner',false,
      'pase_closure_owner',false
    ),
    'compatibility',jsonb_build_object(
      'assurance_completeness_reintroduced',false,
      'global_pase_control',false,
      'active_subject_binding_count',0,
      'entry_guard_required_live',false,
      'runtime_activation',false,
      'production_activation',false
    ),
    'qualification',jsonb_build_object(
      'core_regression','PASS_16_OF_16',
      'activation_boundary','PASS_9_CHECKS_REPLAYED_TWICE',
      'activation_event_id',19934,
      'exact_blob_pinning',true
    ),
    'rollback',jsonb_build_object(
      'supported',true,
      'mode','CURRENT_POINTER_AND_VERSION_ROW_RESTORE',
      'subject_bindings_untouched',true,
      'entry_guard_untouched',true
    )
  );
  v_manifest_sha := encode(extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),'hex');

  INSERT INTO public.lf_capability_version_registry(
    capability_code,version,version_major,version_minor,version_patch,release_state,supersedes_version,
    manifest,manifest_sha256,source_ref,docs_ref,validator_ref,created_by_execution_id
  ) VALUES (
    'ASSURANCE_EVALUATOR','1.0.0',1,0,0,'RELEASED',NULL,
    v_manifest,v_manifest_sha,
    'github://cristhianlujan/claude-persona-lf-patch@3f275d5f2bc114afe46ef94672cc34d57f33ebf2/sandbox/lf_contract_gate_test/assurance_evaluator_boundary/assurance_evaluator_runner_v1.py',
    'github://cristhianlujan/claude-persona-lf-patch/sandbox/lf_contract_gate_test/assurance_evaluator_boundary/README.md',
    'github://cristhianlujan/claude-persona-lf-patch@3f275d5f2bc114afe46ef94672cc34d57f33ebf2/sandbox/lf_contract_gate_test/assurance_evaluator_boundary/test_assurance_evaluator_core_v1.py',
    v_execution_id
  );

  v_promote := public.fn_lf_capability_promote_v1(
    'ASSURANCE_EVALUATOR','1.0.0',NULL,v_execution_id,
    'Make the qualified fail-closed Assurance evaluator available as CURRENT without authorizing execution; subject activation remains behind PASE activation authority and explicit human GO.'
  );
  IF coalesce((v_promote->>'ready')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'BLOCK_ASSURANCE_EVALUATOR_PROMOTION:%',v_promote::text;
  END IF;

  UPDATE public.lf_activos
  SET version='1.0.0',
      runtime_estado='REPOSITORY_BOUND',
      impacto_automatico='BLOQUEADO',
      ultima_revision='3a17d94b182dea4793592571913084ac3ceb1d40d954cb055e6c3ceb43038a20',
      raw_payload=coalesce(raw_payload,'{}'::jsonb) || jsonb_build_object(
        'status','CURRENT_AVAILABLE_EXECUTION_DEFERRED',
        'current_pointer_present',true,
        'active_subject_bindings',0,
        'entry_guard_enforced',false,
        'runtime_authorized',false,
        'production_authorized',false
      ),
      metadata=jsonb_set(
        jsonb_set(
          jsonb_set(
            coalesce(metadata,'{}'::jsonb),
            '{inventory_status}',
            to_jsonb('CURRENT_AVAILABLE_EXECUTION_DEFERRED'::text),true
          ),
          '{entry_contract,enforcement_state}',
          to_jsonb('DECLARED_DEFERRED_UNTIL_PASE_F06_F09_F10_PLUS_EXPLICIT_HUMAN_GO'::text),true
        ),
        '{call_contract}',
        jsonb_build_object(
          'schema_version','lf-assurance-evaluator-call-contract/v1',
          'ref','sandbox/lf_contract_gate_test/assurance_evaluator_boundary/assurance_evaluator_call_contract_v1.json',
          'sha256','3a17d94b182dea4793592571913084ac3ceb1d40d954cb055e6c3ceb43038a20',
          'dispatch_entrypoint','public.fn_lf_orchestrator_dispatch_receipt_v1',
          'bind_entrypoint','public.fn_lf_capability_bind_from_orchestrator_v1',
          'activation_gate','ASSURANCE_ACTIVATION_GATE_V1',
          'subject_binding_policy','EXACT_ACTIVE_ONLY',
          'execution_deferred',true,
          'global_assurance_gate',false
        ),true
      ),
      updated_at=clock_timestamp(),
      updated_by_execution_id=v_execution_id
  WHERE codigo_activo='ASSURANCE_EVALUATOR' AND archived_at IS NULL;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_capability_current c
    JOIN public.lf_capability_version_registry v
      ON v.capability_code=c.capability_code AND v.version=c.version
    WHERE c.capability_code='ASSURANCE_EVALUATOR'
      AND c.version='1.0.0'
      AND c.manifest_sha256=v.manifest_sha256
  ) THEN
    RAISE EXCEPTION 'BLOCK_ASSURANCE_EVALUATOR_CURRENT_READBACK';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.lf_assurance_subject_bindings WHERE status='ACTIVE'
  ) THEN
    RAISE EXCEPTION 'BLOCK_ASSURANCE_EVALUATOR_PROMOTION_ACTIVATED_BINDING';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_capability_registry
    WHERE capability_code='ASSURANCE_EVALUATOR'
      AND entry_guard_required IS FALSE
      AND entry_guard_code='ORCHESTRATOR_EXECUTION_GUARD_V1'
  ) THEN
    RAISE EXCEPTION 'BLOCK_ASSURANCE_EVALUATOR_PROMOTION_CHANGED_ENTRY_GUARD';
  END IF;
END
$promote$;
