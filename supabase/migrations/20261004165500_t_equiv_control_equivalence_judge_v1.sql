-- T-EQUIV / PAULO-034 — CONTROL_EQUIVALENCE_JUDGE transversal capability.
-- Owner: SUPER_ADMIN. Repository-pure/read-only comparator; no business/runtime mutation.

DO $cap$
DECLARE
  v_execution_id constant text := 'CHATGPT-T-EQUIV-PAULO-034-20261004';
  v_manifest jsonb;
  v_manifest_sha text;
  v_existing_sha text;
  v_promote jsonb;
BEGIN
  IF to_regprocedure('public.fn_lf_capability_promote_v1(text,text,text,text,text)') IS NULL THEN
    RAISE EXCEPTION 'BLOCK_T_EQUIV_CAPABILITY_PROMOTER_MISSING';
  END IF;

  v_manifest:=jsonb_build_object(
    'schema_version','LF_CAPABILITY_MANIFEST_V1',
    'capability_code','CONTROL_EQUIVALENCE_JUDGE',
    'version','1.0.0',
    'owner','SUPER_ADMIN',
    'contract',jsonb_build_object(
      'input','current JSON + candidate JSON for one frozen subject + explicit consumer field policy',
      'output','PASS_EQUIVALENT|DIVERGENCE_CLASSIFIED|BLOCKED_DIVERGENCE|BLOCKED_UNCLASSIFIED_DIVERGENCE|BLOCKED',
      'authority','READ_ONLY_FAIL_CLOSED_COMPARISON',
      'global_semantics',jsonb_build_object(
        'D0','EXACT_EQUALITY',
        'D4','KNOWN_FALSE_PASS_RISK_ALWAYS_BLOCKING',
        'D1_D2_D3_D5','CONSUMER_DECLARED_MEANING_AND_EXACT_FIELD_MAPPING'
      ),
      'unmapped_divergence','BLOCKED_UNCLASSIFIED_DIVERGENCE',
      'executes_change',false
    ),
    'delivery',jsonb_build_object(
      'mode','REPOSITORY_PURE_COMPARATOR',
      'source','sandbox/lf_contract_gate_test/transversal_assets/control_equivalence/control_equivalence_judge_v1.py',
      'test','sandbox/lf_contract_gate_test/transversal_assets/control_equivalence/test_control_equivalence_judge_v1.py'
    ),
    'installation',jsonb_build_object(
      'required',false,
      'reinstall_required',false,
      'package_update_mode','SOURCE_PLUS_CAPABILITY_REGISTRY'
    ),
    'dependencies',jsonb_build_object(),
    'compatibility',jsonb_build_object(
      'domain_agnostic',true,
      'ig_owner',false,
      'executes_changes',false,
      'runtime_mutation',false,
      'production_activation',false,
      'parallel_currentness_engine',false,
      'parallel_evidence_engine',false,
      'parallel_execution_engine',false
    ),
    'migration',jsonb_build_object(
      'work_code','PAULO-034',
      'unit_code','T-EQUIV',
      'mode','REGISTER_REPOSITORY_PURE_COMPARATOR'
    ),
    'rollback',jsonb_build_object(
      'supported',true,
      'mode','REGISTRY_POINTER_ROLLBACK',
      'rule','remove only CONTROL_EQUIVALENCE_JUDGE v1/current/registry when no bindings remain; never mutate consumer evidence'
    ),
    'usage',jsonb_build_object(
      'entrypoint','public.fn_lf_capability_bind_from_orchestrator_v1',
      'provider_source','sandbox/lf_contract_gate_test/transversal_assets/control_equivalence/control_equivalence_judge_v1.py',
      'policy_schema','lf-control-equivalence-policy/v1',
      'ig_m7_8_policy','EXACT_ONLY_ALL_DIVERGENCE_BLOCKS',
      'docs','sandbox/lf_contract_gate_test/transversal_assets/control_equivalence/README.md'
    ),
    'currentness',jsonb_build_object(
      'source_revision_immutable',false,
      'verification','MIGRATION_SOURCE_PARITY_REQUIRED_POST_MERGE',
      'consumer_policy_binding','REQUIRED_PER_EXECUTION_OR_GOVERNED_CONSUMER_CONTRACT'
    )
  );
  v_manifest_sha:=encode(extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),'hex');

  INSERT INTO public.lf_capability_registry(
    capability_code,capability_name,capability_kind,owner_scope,status,description,
    created_by_execution_id,updated_by_execution_id,entry_guard_required,entry_guard_code
  ) VALUES (
    'CONTROL_EQUIVALENCE_JUDGE','Control Equivalence Judge','TRANSVERSAL','SUPER_ADMIN','ACTIVE',
    'Domain-agnostic read-only equivalence judge. D0 exact and D4 false-pass blocking are global; other divergence meanings are consumer policy.',
    v_execution_id,v_execution_id,true,'ORCHESTRATOR_EXECUTION_GUARD_V1'
  )
  ON CONFLICT(capability_code) DO UPDATE SET
    capability_name=excluded.capability_name,
    capability_kind='TRANSVERSAL',
    owner_scope='SUPER_ADMIN',
    status='ACTIVE',
    description=excluded.description,
    entry_guard_required=true,
    entry_guard_code='ORCHESTRATOR_EXECUTION_GUARD_V1',
    updated_at=clock_timestamp(),
    updated_by_execution_id=v_execution_id;

  SELECT manifest_sha256 INTO v_existing_sha
  FROM public.lf_capability_version_registry
  WHERE capability_code='CONTROL_EQUIVALENCE_JUDGE' AND version='1.0.0';
  IF v_existing_sha IS NOT NULL AND v_existing_sha<>v_manifest_sha THEN
    RAISE EXCEPTION 'BLOCK_T_EQUIV_VERSION_MANIFEST_CONFLICT';
  END IF;

  INSERT INTO public.lf_capability_version_registry(
    capability_code,version,version_major,version_minor,version_patch,release_state,supersedes_version,
    manifest,manifest_sha256,source_ref,docs_ref,validator_ref,created_by_execution_id
  ) VALUES (
    'CONTROL_EQUIVALENCE_JUDGE','1.0.0',1,0,0,'RELEASED',NULL,
    v_manifest,v_manifest_sha,
    'github://cristhianlujan/claude-persona-lf-patch/sandbox/lf_contract_gate_test/transversal_assets/control_equivalence/control_equivalence_judge_v1.py',
    'github://cristhianlujan/claude-persona-lf-patch/sandbox/lf_contract_gate_test/transversal_assets/control_equivalence/README.md',
    'github://cristhianlujan/claude-persona-lf-patch/sandbox/lf_contract_gate_test/transversal_assets/control_equivalence/test_control_equivalence_judge_v1.py',
    v_execution_id
  ) ON CONFLICT(capability_code,version) DO NOTHING;

  v_promote:=public.fn_lf_capability_promote_v1(
    'CONTROL_EQUIVALENCE_JUDGE','1.0.0',NULL,v_execution_id,
    'T-EQUIV closes the generic read-only equivalence capability without inventing consumer-specific D1/D2/D3/D5 semantics.'
  );
  IF coalesce((v_promote->>'ready')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'BLOCK_T_EQUIV_CURRENT_POINTER:%',v_promote::text;
  END IF;

  IF NOT EXISTS(
    SELECT 1 FROM public.lf_capability_registry r
    JOIN public.lf_capability_current c USING(capability_code)
    WHERE r.capability_code='CONTROL_EQUIVALENCE_JUDGE'
      AND r.status='ACTIVE' AND r.owner_scope='SUPER_ADMIN'
      AND c.version='1.0.0' AND c.manifest_sha256=v_manifest_sha
  ) THEN
    RAISE EXCEPTION 'BLOCK_T_EQUIV_TERMINAL_READBACK';
  END IF;
END
$cap$;
