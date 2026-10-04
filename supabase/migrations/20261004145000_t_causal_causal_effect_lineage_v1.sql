-- T-CAUSAL / PAULO-188 — CAUSAL_EFFECT_LINEAGE v1.0.0
-- Repository-bound transversal causal lineage evaluator. No IG runtime cutover.
-- Owner: SUPER_ADMIN. IG remains a consumer.

DO $pre$
BEGIN
  IF EXISTS (SELECT 1 FROM public.lf_capability_registry WHERE capability_code='CAUSAL_EFFECT_LINEAGE') THEN
    RAISE EXCEPTION 'BLOCK_T_CAUSAL_REGISTRY_ALREADY_PRESENT';
  END IF;
  IF EXISTS (SELECT 1 FROM public.lf_capability_version_registry WHERE capability_code='CAUSAL_EFFECT_LINEAGE') THEN
    RAISE EXCEPTION 'BLOCK_T_CAUSAL_VERSION_ALREADY_PRESENT';
  END IF;
  IF EXISTS (SELECT 1 FROM public.lf_capability_current WHERE capability_code='CAUSAL_EFFECT_LINEAGE') THEN
    RAISE EXCEPTION 'BLOCK_T_CAUSAL_CURRENT_ALREADY_PRESENT';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_capability_current
    WHERE capability_code='TYPED_EVIDENCE_REGISTRY'
      AND version='3.0.0'
      AND manifest_sha256='0fb00eeeb84567129bde17df0fac9f04c136a874518010a21af60c37810134da'
  ) THEN
    RAISE EXCEPTION 'BLOCK_T_CAUSAL_TYPED_EVIDENCE_NOT_CURRENT';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_capability_current
    WHERE capability_code='EVIDENCE_LEDGER'
      AND version='1.1.0'
      AND manifest_sha256='b9c21eaa0cb4eceec3e6a0ae78272ed2da84e408e804c127ed6e43d1360f0982'
  ) THEN
    RAISE EXCEPTION 'BLOCK_T_CAUSAL_EVIDENCE_LEDGER_NOT_CURRENT';
  END IF;
END
$pre$;

DO $register$
DECLARE
  v_execution_id constant text := 'CHATGPT-IG-T-CAUSAL-PAULO-188-20261004';
  v_source_commit constant text := 'd0b5a37221f2a389c4593e02f8c2e9dc30cf8a06';
  v_source_blob constant text := 'f15cc736d2eabbfa3bd9f6211ca69ef324956eb8';
  v_test_blob constant text := 'c9ee26258133e3990f40be9c028e2f29463630a1';
  v_manifest jsonb;
  v_manifest_sha text;
  v_promote jsonb;
BEGIN
  v_manifest := jsonb_build_object(
    'schema_version','LF_CAPABILITY_MANIFEST_V1',
    'capability_code','CAUSAL_EFFECT_LINEAGE',
    'version','1.0.0',
    'owner','SUPER_ADMIN',
    'contract',jsonb_build_object(
      'inputs',jsonb_build_array(
        'parent_identity','correlation_identity','provenance','currentness',
        'producer_receipt','receiver_effect_receipt','receiver_readback'
      ),
      'outputs',jsonb_build_array('state','reasons','causal_edge_digest','business_authority','execution_permission'),
      'states',jsonb_build_array('LINKED','UNLINKED','AMBIGUOUS'),
      'identity','SCOPED_OPAQUE_ONLY',
      'causal_proof','EXPLICIT_RECEIPT_CROSSLINK_PLUS_RECEIVER_READBACK',
      'name_match','NON_PROBATIVE',
      'same_object','NON_PROBATIVE',
      'timestamp_proximity','NON_PROBATIVE',
      'pii_allowed',false,
      'business_authority',false,
      'execution_permission',false,
      'receiver_effect_readback_required',true
    ),
    'delivery',jsonb_build_object(
      'mode','REPOSITORY_BOUND_PURE_PYTHON',
      'runtime_deploy_required',false,
      'active_runtime_cutover',false,
      'source_commit',v_source_commit,
      'source_blob_sha1',v_source_blob,
      'test_blob_sha1',v_test_blob
    ),
    'installation',jsonb_build_object(
      'required',false,
      'reinstall_required',false,
      'runtime_deploy_required',false
    ),
    'dependencies',jsonb_build_object(
      'TYPED_EVIDENCE_REGISTRY',jsonb_build_object(
        'capability_code','TYPED_EVIDENCE_REGISTRY',
        'version','3.0.0',
        'manifest_sha256','0fb00eeeb84567129bde17df0fac9f04c136a874518010a21af60c37810134da'
      ),
      'EVIDENCE_LEDGER',jsonb_build_object(
        'capability_code','EVIDENCE_LEDGER',
        'version','1.1.0',
        'manifest_sha256','b9c21eaa0cb4eceec3e6a0ae78272ed2da84e408e804c127ed6e43d1360f0982'
      )
    ),
    'compatibility',jsonb_build_object(
      'provider_contract','LF_CAUSAL_EFFECT_LINEAGE_V1',
      'domain_agnostic',true,
      'unknown_or_missing_proof','UNLINKED',
      'conflicting_explicit_proof','AMBIGUOUS',
      'ledger_duplicated',false,
      'business_authority_owned',false,
      'active_runtime_cutover',false
    ),
    'migration',jsonb_build_object(
      'id','T_CAUSAL_CAUSAL_EFFECT_LINEAGE_V1',
      'mode','CAPABILITY_REGISTRY_AND_CURRENT_POINTER_ONLY',
      'runtime_cutover',false
    ),
    'consumer_proofs',jsonb_build_object(
      'ig',jsonb_build_object(
        'plan','IG_CURATOR_VALIDATOR_REFACTOR_V2',
        'unit','N-17',
        'role','CONSUMER',
        'boundary','ASYNC_JOB',
        'binding_ref','sandbox/lf_contract_gate_test/transversal_assets/causal_effect_lineage/ig_n17_consumer_binding_v1.json',
        'unit_executed',false,
        'receiver_readback_proven',true
      ),
      'non_ig',jsonb_build_object(
        'consumer_ref','POST_PASE_PROOF_CONSUMER',
        'boundary','ASYNC_EVENT',
        'fixture_ref','sandbox/lf_contract_gate_test/transversal_assets/causal_effect_lineage/non_ig_async_consumer_fixture_v1.json',
        'receiver_readback_proven',true
      )
    ),
    'qualification',jsonb_build_object(
      'observation','PASS_CAUSAL_EFFECT_LINEAGE_V1 checks=24 states=3 async_consumers=2 heuristic_negative=PASS receiver_readbacks=2',
      'checks',24,
      'states_covered',3,
      'async_consumers',2,
      'heuristic_negative','PASS',
      'receiver_readbacks',2
    ),
    'usage',jsonb_build_object(
      'call','evaluate_lineage(request)',
      'consumer_supplies_domain_context',true,
      'linked_requires_receiver_readback',true,
      'result_is_business_authority',false,
      'result_is_execution_permission',false
    ),
    'currentness',jsonb_build_object(
      'source_event','event://20170',
      'transversalization_event','event://20265',
      'source_commit',v_source_commit,
      'source_blob_sha1',v_source_blob,
      'validator_blob_sha1',v_test_blob,
      'dependency_currentness_pinned',true
    ),
    'rollback',jsonb_build_object(
      'supported',true,
      'mode','REMOVE_CURRENT_VERSION_AND_REGISTRY_ROWS',
      'runtime_state_untouched',true,
      'evidence_ledger_untouched',true
    )
  );

  v_manifest_sha := encode(extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),'hex');

  INSERT INTO public.lf_capability_registry(
    capability_code,capability_name,capability_kind,owner_scope,status,description,
    created_by_execution_id,updated_by_execution_id,entry_guard_required,entry_guard_code
  ) VALUES (
    'CAUSAL_EFFECT_LINEAGE','Causal Effect Lineage','TRANSVERSAL','SUPER_ADMIN','ACTIVE',
    'Domain-agnostic causal continuity evaluator requiring explicit scoped identities, verified producer/receiver receipts and receiver-effect readback; heuristic similarity is non-probative.',
    v_execution_id,v_execution_id,false,'ORCHESTRATOR_EXECUTION_GUARD_V1'
  );

  INSERT INTO public.lf_capability_version_registry(
    capability_code,version,version_major,version_minor,version_patch,release_state,supersedes_version,
    manifest,manifest_sha256,source_ref,docs_ref,validator_ref,created_by_execution_id
  ) VALUES (
    'CAUSAL_EFFECT_LINEAGE','1.0.0',1,0,0,'RELEASED',NULL,
    v_manifest,v_manifest_sha,
    'github://cristhianlujan/claude-persona-lf-patch@'||v_source_commit||'/sandbox/lf_contract_gate_test/transversal_assets/causal_effect_lineage/causal_effect_lineage_v1.py',
    'github://cristhianlujan/claude-persona-lf-patch@'||v_source_commit||'/sandbox/lf_contract_gate_test/transversal_assets/causal_effect_lineage/README.md',
    'github://cristhianlujan/claude-persona-lf-patch@'||v_source_commit||'/sandbox/lf_contract_gate_test/transversal_assets/causal_effect_lineage/test_causal_effect_lineage_v1.py',
    v_execution_id
  );

  v_promote := public.fn_lf_capability_promote_v1(
    'CAUSAL_EFFECT_LINEAGE','1.0.0',NULL,v_execution_id,
    'T-CAUSAL generic causal lineage qualified over two async consumers with explicit receiver-effect readback; repository-bound, no runtime cutover.'
  );

  IF coalesce((v_promote->>'ready')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'BLOCK_T_CAUSAL_PROMOTION:%',v_promote::text;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_capability_registry r
    JOIN public.lf_capability_current c USING(capability_code)
    JOIN public.lf_capability_version_registry vr
      ON vr.capability_code=c.capability_code AND vr.version=c.version AND vr.manifest_sha256=c.manifest_sha256
    WHERE r.capability_code='CAUSAL_EFFECT_LINEAGE'
      AND r.capability_kind='TRANSVERSAL'
      AND r.owner_scope='SUPER_ADMIN'
      AND r.status='ACTIVE'
      AND c.version='1.0.0'
      AND vr.manifest#>>'{contract,identity}'='SCOPED_OPAQUE_ONLY'
      AND vr.manifest#>>'{contract,name_match}'='NON_PROBATIVE'
      AND vr.manifest#>>'{contract,same_object}'='NON_PROBATIVE'
      AND vr.manifest#>>'{contract,timestamp_proximity}'='NON_PROBATIVE'
      AND (vr.manifest#>>'{contract,pii_allowed}')::boolean IS FALSE
      AND (vr.manifest#>>'{contract,business_authority}')::boolean IS FALSE
      AND (vr.manifest#>>'{contract,receiver_effect_readback_required}')::boolean IS TRUE
  ) THEN
    RAISE EXCEPTION 'BLOCK_T_CAUSAL_CURRENT_READBACK';
  END IF;
END
$register$;
