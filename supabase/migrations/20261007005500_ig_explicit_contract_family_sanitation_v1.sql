-- IG explicit contract family sanitation v1.
-- One-time conversion of the 171 open HEURISTIC_BLOCKED checkpoints observed on 2026-10-07.
-- Runtime semantics are frozen by exact unit_code + checkpoint_code mapping below.
-- No title/regex/action-kind inference is used after this migration.

do $sanitation$
declare
  r record;
  v_pack jsonb;
  v_queries jsonb;
  v_artifacts jsonb;
  v_assets jsonb;
  v_events jsonb;
  v_objects jsonb;
  v_missing jsonb;
  v_spec jsonb;
  v_status text;
  v_expected text;
  v_required jsonb;
  v_requires_material boolean;
  v_before integer;
  v_after integer;
begin
  select count(*)
    into v_before
  from programacion.engineering_plan_units pu
  join programacion.engineering_work_checkpoints c on c.work_item_id=pu.work_item_id
  where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    and pu.disposition='ASSIGNED'
    and c.required
    and c.status not in ('DONE','NOT_APPLICABLE')
    and programacion.fn_engineering_checkpoint_action_spec_v3(
          'IG_CURATOR_VALIDATOR_REFACTOR_V2',pu.unit_code,c.checkpoint_code
        )->>'contract_source'='HEURISTIC_BLOCKED';

  if v_before<>171 then
    raise exception 'IG_EXPLICIT_FAMILY_SANITATION_BASE_DRIFT expected=171 actual=%',v_before;
  end if;

  for r in
    select *
    from (values
    ('M1.9','M1_HANDOFF_TERMINAL','TERMINAL_ACCEPTANCE_REQUIRED','TERMINAL_RECONCILE'),
    ('M1.9','M1_INDEPENDENT_READBACK','TERMINAL_ACCEPTANCE_REQUIRED','TERMINAL_RECONCILE'),
    ('M1.A8','NEG_UNMARKED_CLAUSE','VERIFY_ASSERTION_REQUIRED','VERIFY_QUERY_ONCE'),
    ('M10.0','BUNDLE_M9_BINDING','MATERIALIZATION_CONTRACT_REQUIRED','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('M10.0','CUTOVER_READY_PRECONDITION','DECISION_AUTHORITY_REQUIRED','DECISION_GATE'),
    ('M10.0','HUMAN_DECISION_RECORD','DECISION_AUTHORITY_REQUIRED','DECISION_GATE'),
    ('M10.0','NEG_SHA_MISMATCH','VERIFY_ASSERTION_REQUIRED','VERIFY_QUERY_ONCE'),
    ('M10.0','REUSE_SADM_AUTHORITY','DECISION_AUTHORITY_REQUIRED','DECISION_GATE'),
    ('M10.1','NEG_INTERNAL_CALL','VERIFY_ASSERTION_REQUIRED','VERIFY_QUERY_ONCE'),
    ('M10.1','PROFILES_ADAPTERS_CONSUMERS','MATERIALIZATION_CONTRACT_REQUIRED','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('M10.1','ROUTER_MIGRATED','MATERIALIZATION_CONTRACT_REQUIRED','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('M10.11','NEG_CALLER_DENIED','VERIFY_ASSERTION_REQUIRED','VERIFY_QUERY_ONCE'),
    ('M10.11','REVOKE_MIGRATION','MATERIALIZATION_CONTRACT_REQUIRED','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('M10.12','BATCH_DROP_NO_CASCADE','MATERIALIZATION_CONTRACT_REQUIRED','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('M10.12','NEG_CASCADE','VERIFY_ASSERTION_REQUIRED','VERIFY_QUERY_ONCE'),
    ('M10.12','REUSE_LEGACY_RETIREMENT','MATERIALIZATION_CONTRACT_REQUIRED','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('M10.13','CLOSURE_GATE_REUSE','TERMINAL_ACCEPTANCE_REQUIRED','TERMINAL_RECONCILE'),
    ('M10.13','FINAL_HANDOFF','TERMINAL_ACCEPTANCE_REQUIRED','TERMINAL_RECONCILE'),
    ('M10.13','NEG_FALSE_CLOSURE','TERMINAL_ACCEPTANCE_REQUIRED','TERMINAL_RECONCILE'),
    ('M10.2','NEG_REVERSE','AUTHORED_TEST_DRILL_REQUIRED','ROLLBACK_DRILL'),
    ('M10.2','RUNTIME_PREFLIGHT','MATERIALIZATION_CONTRACT_REQUIRED','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('M10.2','SWITCH_ONLY_MIGRATION','MATERIALIZATION_CONTRACT_REQUIRED','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('M10.3','ROLLBACK_DRILL','AUTHORED_TEST_DRILL_REQUIRED','ROLLBACK_DRILL'),
    ('M10.4','NEG_NEW_MIGRATION','VERIFY_ASSERTION_REQUIRED','VERIFY_QUERY_ONCE'),
    ('M10.5','NEG_STALE_RUN','VERIFY_ASSERTION_REQUIRED','VERIFY_QUERY_ONCE'),
    ('M10.5','NEW_RUNS_VNEXT','MATERIALIZATION_CONTRACT_REQUIRED','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('M10.7','NEG_INSUFFICIENT','VERIFY_ASSERTION_REQUIRED','VERIFY_QUERY_ONCE'),
    ('M10.7','NO_FALSE_PASS','AUTHORED_TEST_DRILL_REQUIRED','FAULT_INJECTION_TIMEOUT'),
    ('M10.8','ARCHIVED_BUNDLE_RECOVERABLE','MATERIALIZATION_CONTRACT_REQUIRED','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('M10.8','EXPIRY_DECISION','DECISION_AUTHORITY_REQUIRED','DECISION_GATE'),
    ('M10.8','ROLLBACK_MODE_ASIS','READ_ONLY_EVIDENCE','OBSERVE_ONCE'),
    ('M3.11','HANDOFF_EVENT','MUTATION_TARGET_ASSERTION_REQUIRED','MUTATION_EXECUTION'),
    ('M3.11','INDEPENDENT_READBACK_TERMINAL','MUTATION_TARGET_ASSERTION_REQUIRED','MUTATION_EXECUTION'),
    ('M4.10','ADJUDICATE_DIVERGENCES','DECISION_AUTHORITY_REQUIRED','DECISION_GATE'),
    ('M4.10','NEG_UNADJUDICATED','VERIFY_ASSERTION_REQUIRED','VERIFY_QUERY_ONCE'),
    ('M4.11','DECISIONAL_BINDING_VIA_RELEASE','DECISION_AUTHORITY_REQUIRED','DECISION_GATE'),
    ('M4.12','CORRELATION_RERUN','MATERIALIZATION_CONTRACT_REQUIRED','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('M4.12','M4_HANDOFF_READBACK','TERMINAL_ACCEPTANCE_REQUIRED','TERMINAL_RECONCILE'),
    ('M4.12','NEG_PATH_WITHOUT_EVIDENCE','MUTATION_TARGET_ASSERTION_REQUIRED','MUTATION_EXECUTION'),
    ('M4.3','NEG_STRUCTURAL','VERIFY_ASSERTION_REQUIRED','VERIFY_QUERY_ONCE'),
    ('M4.3','STRUCTURAL_GATE_CONTROLS','DECISION_AUTHORITY_REQUIRED','DECISION_GATE'),
    ('M4.6','CROSS_FAMILY_CASES','MATERIALIZATION_CONTRACT_REQUIRED','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('M4.6','NEG_CONTRADICTION','VERIFY_ASSERTION_REQUIRED','VERIFY_QUERY_ONCE'),
    ('M4.7','NEG_NO_PROMOTION','VERIFY_ASSERTION_REQUIRED','VERIFY_QUERY_ONCE'),
    ('M4.9','MUTATION_ASIS','READ_ONLY_EVIDENCE','OBSERVE_ONCE'),
    ('M4.9','MUTATION_CATALOG_T1_T10','MUTATION_TARGET_ASSERTION_REQUIRED','MUTATION_EXECUTION'),
    ('M4.9','MUTATION_READBACK','READ_ONLY_EVIDENCE','READBACK_ONCE'),
    ('M4.9','NEG_FALSE_PASS','MUTATION_TARGET_ASSERTION_REQUIRED','MUTATION_EXECUTION'),
    ('M5.10','HANDOFF_EVENT','MUTATION_TARGET_ASSERTION_REQUIRED','MUTATION_EXECUTION'),
    ('M5.10','INDEPENDENT_READBACK','TERMINAL_ACCEPTANCE_REQUIRED','TERMINAL_RECONCILE'),
    ('M5.10','NEGATIVE_OPEN_UNIT','VERIFY_ASSERTION_REQUIRED','VERIFY_QUERY_ONCE'),
    ('M5.2','DECISION_TABLE','DECISION_AUTHORITY_REQUIRED','DECISION_GATE'),
    ('M5.2','NEGATIVE_AMBIGUOUS','VERIFY_ASSERTION_REQUIRED','VERIFY_QUERY_ONCE'),
    ('M5.2','NO_REVISION_LITERALS','MATERIALIZATION_CONTRACT_REQUIRED','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('M5.2','PLAN_EXECUTE_SPLIT','MATERIALIZATION_CONTRACT_REQUIRED','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('M5.2','TERMINAL','TERMINAL_ACCEPTANCE_REQUIRED','TERMINAL_RECONCILE'),
    ('M5.3','CANARY_FORMALIZED','MATERIALIZATION_CONTRACT_REQUIRED','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('M5.3','CONTEXT_ASIS','READ_ONLY_EVIDENCE','OBSERVE_ONCE'),
    ('M5.3','CONTEXT_OBJECT','MATERIALIZATION_CONTRACT_REQUIRED','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('M5.3','NEGATIVE_STALE_CONTEXT','VERIFY_ASSERTION_REQUIRED','VERIFY_QUERY_ONCE'),
    ('M5.3','ONE_GRAPH_COUNT','MATERIALIZATION_CONTRACT_REQUIRED','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('M5.3','TERMINAL','TERMINAL_ACCEPTANCE_REQUIRED','TERMINAL_RECONCILE'),
    ('M5.4','CORE_INVOCATION','MATERIALIZATION_CONTRACT_REQUIRED','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('M5.4','NEGATIVE_NO_CLASSIFY','VERIFY_ASSERTION_REQUIRED','VERIFY_QUERY_ONCE'),
    ('M5.4','SEMANTIC_PLAN_RESOLVERS','MATERIALIZATION_CONTRACT_REQUIRED','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('M5.4','TERMINAL','TERMINAL_ACCEPTANCE_REQUIRED','TERMINAL_RECONCILE'),
    ('M5.5','EXPLICIT_FINGERPRINT','MATERIALIZATION_CONTRACT_REQUIRED','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('M5.5','NEGATIVE_ZERO_SHA','AUTHORED_TEST_DRILL_REQUIRED','ROLLBACK_DRILL'),
    ('M5.5','TERMINAL','TERMINAL_ACCEPTANCE_REQUIRED','TERMINAL_RECONCILE'),
    ('M5.5','TRIGGER_VERIFY_ONLY','MATERIALIZATION_CONTRACT_REQUIRED','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('M5.6','PARITY_PER_STRATEGY','AUTHORED_TEST_DRILL_REQUIRED','ROLLBACK_DRILL'),
    ('M5.6','SINGLE_PIPELINE','MATERIALIZATION_CONTRACT_REQUIRED','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('M5.6','TERMINAL','TERMINAL_ACCEPTANCE_REQUIRED','TERMINAL_RECONCILE'),
    ('M5.8','APPLY_POLICY','MATERIALIZATION_CONTRACT_REQUIRED','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('M5.8','NEGATIVE_REBIND_GAPS','VERIFY_ASSERTION_REQUIRED','VERIFY_QUERY_ONCE'),
    ('M5.8','POLICY_DECLARED','MATERIALIZATION_CONTRACT_REQUIRED','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('M5.8','TERMINAL','TERMINAL_ACCEPTANCE_REQUIRED','TERMINAL_RECONCILE'),
    ('M5.9','HANDOFF_ASIS','TERMINAL_ACCEPTANCE_REQUIRED','TERMINAL_RECONCILE'),
    ('M5.9','NEGATIVE_NO_INVOKE','AUTHORED_TEST_DRILL_REQUIRED','DECLARED_TEST_EXECUTION'),
    ('M5.9','PERSIST_RECEIPT','MATERIALIZATION_CONTRACT_REQUIRED','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('M5.9','TERMINAL','TERMINAL_ACCEPTANCE_REQUIRED','TERMINAL_RECONCILE'),
    ('M6.10','API_CONTRACT','MATERIALIZATION_CONTRACT_REQUIRED','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('M6.10','NEGATIVE_MISSING_RECEIPT','VERIFY_ASSERTION_REQUIRED','VERIFY_QUERY_ONCE'),
    ('M6.10','READONLY_IMPL','MATERIALIZATION_CONTRACT_REQUIRED','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('M6.10','TERMINAL','TERMINAL_ACCEPTANCE_REQUIRED','TERMINAL_RECONCILE'),
    ('M6.12','MANIFEST_VIEW','MATERIALIZATION_CONTRACT_REQUIRED','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('M6.12','NEGATIVE_REPRO','VERIFY_ASSERTION_REQUIRED','VERIFY_QUERY_ONCE'),
    ('M6.12','TERMINAL','TERMINAL_ACCEPTANCE_REQUIRED','TERMINAL_RECONCILE'),
    ('M6.13','HANDOFF_EVENT','MUTATION_TARGET_ASSERTION_REQUIRED','MUTATION_EXECUTION'),
    ('M6.13','INDEPENDENT_READBACK','TERMINAL_ACCEPTANCE_REQUIRED','TERMINAL_RECONCILE'),
    ('M6.13','NEGATIVE_OPEN_UNIT','VERIFY_ASSERTION_REQUIRED','VERIFY_QUERY_ONCE'),
    ('M6.2','GRAPH_SHA_RECEIPT','MATERIALIZATION_CONTRACT_REQUIRED','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('M6.2','NEGATIVE_TAMPER','VERIFY_ASSERTION_REQUIRED','VERIFY_QUERY_ONCE'),
    ('M6.2','TERMINAL','TERMINAL_ACCEPTANCE_REQUIRED','TERMINAL_RECONCILE'),
    ('M6.7','INHERIT_PARENT_SHA','MATERIALIZATION_CONTRACT_REQUIRED','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('M6.7','NEGATIVE_NO_REASON','AUTHORED_TEST_DRILL_REQUIRED','ROLLBACK_DRILL'),
    ('M6.7','TERMINAL','TERMINAL_ACCEPTANCE_REQUIRED','TERMINAL_RECONCILE'),
    ('M7.10','FIXTURES','MATERIALIZATION_CONTRACT_REQUIRED','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('M7.10','NEGATIVE_BLOCKED','VERIFY_ASSERTION_REQUIRED','VERIFY_QUERY_ONCE'),
    ('M7.10','TERMINAL','TERMINAL_ACCEPTANCE_REQUIRED','TERMINAL_RECONCILE'),
    ('M7.11','CASES_50','MATERIALIZATION_CONTRACT_REQUIRED','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('M7.11','NEG_CASE_MUTATED','VERIFY_ASSERTION_REQUIRED','VERIFY_QUERY_ONCE'),
    ('M7.11','REGISTER_SUITE','MATERIALIZATION_CONTRACT_REQUIRED','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('M7.12','HARD_GUARD_NEGATIVE','VERIFY_ASSERTION_REQUIRED','VERIFY_QUERY_ONCE'),
    ('M7.12','JUDGE_NON_DECISIONAL','DECISION_AUTHORITY_REQUIRED','DECISION_GATE'),
    ('M7.12','SUITE_REGISTER_MIGRATION','MATERIALIZATION_CONTRACT_REQUIRED','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('M7.13','CRITERIA_AS_CONTROLS','MATERIALIZATION_CONTRACT_REQUIRED','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('M7.13','FALSE_PASS_BLOCKS','MUTATION_TARGET_ASSERTION_REQUIRED','MUTATION_EXECUTION'),
    ('M7.13','NO_OWN_GATE_NEGATIVE','VERIFY_ASSERTION_REQUIRED','VERIFY_QUERY_ONCE'),
    ('M7.14','M7_ALL_DONE_GATE','DECISION_AUTHORITY_REQUIRED','DECISION_GATE'),
    ('M7.14','M7_EVIDENCE_BUNDLE','MATERIALIZATION_CONTRACT_REQUIRED','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('M7.14','M7_HANDOFF_EVENT','TERMINAL_ACCEPTANCE_REQUIRED','TERMINAL_RECONCILE'),
    ('M7.14','M7_INDEPENDENT_READBACK','TERMINAL_ACCEPTANCE_REQUIRED','TERMINAL_RECONCILE'),
    ('M7.9','REBIND_CASES','MATERIALIZATION_CONTRACT_REQUIRED','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('M7.9','TERMINAL','TERMINAL_ACCEPTANCE_REQUIRED','TERMINAL_RECONCILE'),
    ('M8.10','SLO_OVER_LIMIT_NEGATIVE','VERIFY_ASSERTION_REQUIRED','VERIFY_QUERY_ONCE'),
    ('M8.11','RECEIPT_PER_RUN','MATERIALIZATION_CONTRACT_REQUIRED','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('M8.11','REGRESSION_GATE_NEGATIVE','AUTHORED_TEST_DRILL_REQUIRED','FAULT_INJECTION'),
    ('M8.12','M8_ALL_DONE_GATE','DECISION_AUTHORITY_REQUIRED','DECISION_GATE'),
    ('M8.12','M8_EVIDENCE_BUNDLE','MATERIALIZATION_CONTRACT_REQUIRED','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('M8.12','M8_HANDOFF_EVENT','TERMINAL_ACCEPTANCE_REQUIRED','TERMINAL_RECONCILE'),
    ('M8.12','M8_INDEPENDENT_READBACK','TERMINAL_ACCEPTANCE_REQUIRED','TERMINAL_RECONCILE'),
    ('M8.2','NEGATIVE_SHA_STABLE','VERIFY_ASSERTION_REQUIRED','VERIFY_QUERY_ONCE'),
    ('M8.2','PER_FAMILY_RESOLVER','MATERIALIZATION_CONTRACT_REQUIRED','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('M8.2','TERMINAL','TERMINAL_ACCEPTANCE_REQUIRED','TERMINAL_RECONCILE'),
    ('M8.2','TIMING_SINK','MATERIALIZATION_CONTRACT_REQUIRED','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('M8.5','JIT_ASIS','READ_ONLY_EVIDENCE','OBSERVE_ONCE'),
    ('M8.5','JIT_EXEC','MATERIALIZATION_CONTRACT_REQUIRED','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('M8.5','NEGATIVE_SKIPPED','VERIFY_ASSERTION_REQUIRED','VERIFY_QUERY_ONCE'),
    ('M8.5','TERMINAL','TERMINAL_ACCEPTANCE_REQUIRED','TERMINAL_RECONCILE'),
    ('M8.6','BATCH_COMMON','MATERIALIZATION_CONTRACT_REQUIRED','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('M8.6','NEGATIVE_PARITY','VERIFY_ASSERTION_REQUIRED','VERIFY_QUERY_ONCE'),
    ('M8.6','READS_ASIS','READ_ONLY_EVIDENCE','OBSERVE_ONCE'),
    ('M8.6','TERMINAL','TERMINAL_ACCEPTANCE_REQUIRED','TERMINAL_RECONCILE'),
    ('M8.8','DEADLINE_CHUNKING','MATERIALIZATION_CONTRACT_REQUIRED','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('M8.8','NEG_SLOW_FAMILY','AUTHORED_TEST_DRILL_REQUIRED','DECLARED_TEST_EXECUTION'),
    ('M8.8','PARITY_M7_GATE','VERIFY_ASSERTION_REQUIRED','VERIFY_QUERY_ONCE'),
    ('M8.9','EXPLAIN_BASELINE','READ_ONLY_EVIDENCE','OBSERVE_ONCE'),
    ('M8.9','NO_PLAN_NO_INDEX_NEGATIVE','VERIFY_ASSERTION_REQUIRED','VERIFY_QUERY_ONCE'),
    ('M9.0','BUNDLE_MANIFEST_SHA','MATERIALIZATION_CONTRACT_REQUIRED','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('M9.0','DRIFT_NEGATIVE','VERIFY_ASSERTION_REQUIRED','VERIFY_QUERY_ONCE'),
    ('M9.0','PARITY_GIT_RUNTIME','VERIFY_ASSERTION_REQUIRED','VERIFY_QUERY_ONCE'),
    ('M9.10','DRILL_READBACK','READ_ONLY_EVIDENCE','READBACK_ONCE'),
    ('M9.10','RESIDUE_NEGATIVE','VERIFY_ASSERTION_REQUIRED','VERIFY_QUERY_ONCE'),
    ('M9.10','ROLLBACK_DRILL','AUTHORED_TEST_DRILL_REQUIRED','ROLLBACK_DRILL'),
    ('M9.12','CLOSURE_GATE_CONSUME','TERMINAL_ACCEPTANCE_REQUIRED','TERMINAL_RECONCILE'),
    ('M9.12','NOT_PRODUCTION_NEGATIVE','VERIFY_ASSERTION_REQUIRED','VERIFY_QUERY_ONCE'),
    ('M9.13','M9_ALL_DONE_GATE','DECISION_AUTHORITY_REQUIRED','DECISION_GATE'),
    ('M9.13','M9_EVIDENCE_BUNDLE','MATERIALIZATION_CONTRACT_REQUIRED','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('M9.13','M9_HANDOFF_EVENT','TERMINAL_ACCEPTANCE_REQUIRED','TERMINAL_RECONCILE'),
    ('M9.13','M9_INDEPENDENT_READBACK','TERMINAL_ACCEPTANCE_REQUIRED','TERMINAL_RECONCILE'),
    ('M9.2','ADR_M17_PRESENT','DECISION_AUTHORITY_REQUIRED','DECISION_GATE'),
    ('M9.2','NO_REWRITE_NEGATIVE','VERIFY_ASSERTION_REQUIRED','VERIFY_QUERY_ONCE'),
    ('M9.3','FULL_PIPELINE_CANDIDATE','MATERIALIZATION_CONTRACT_REQUIRED','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('M9.3','ZERO_AUTH_WRITES_NEGATIVE','VERIFY_ASSERTION_REQUIRED','VERIFY_QUERY_ONCE'),
    ('M9.5','D4_BLOCKS_NEGATIVE','AUTHORED_TEST_DRILL_REQUIRED','FAULT_INJECTION'),
    ('M9.6','ADJUDICATE_EACH','DECISION_AUTHORITY_REQUIRED','DECISION_GATE'),
    ('M9.6','AUTHORITY_M17','DECISION_AUTHORITY_REQUIRED','DECISION_GATE'),
    ('M9.6','UNRESOLVED_NEGATIVE','VERIFY_ASSERTION_REQUIRED','VERIFY_QUERY_ONCE'),
    ('M9.7','RECEIPT_MISSING_NEGATIVE','VERIFY_ASSERTION_REQUIRED','VERIFY_QUERY_ONCE'),
    ('M9.7','REPLAY_REPRODUCIBLE','AUTHORED_TEST_DRILL_REQUIRED','REPRODUCIBILITY_EXECUTION'),
    ('M9.8','CLOSURE_GATE_ASIS','TERMINAL_ACCEPTANCE_REQUIRED','TERMINAL_RECONCILE'),
    ('M9.8','GATE_FAIL_NEGATIVE','VERIFY_ASSERTION_REQUIRED','VERIFY_QUERY_ONCE'),
    ('M9.9','CANARY_PATTERN_ASIS','READ_ONLY_EVIDENCE','OBSERVE_ONCE'),
    ('M9.9','ROLLBACK_TRIGGER_NEGATIVE','AUTHORED_TEST_DRILL_REQUIRED','ROLLBACK_DRILL'),
    ('N-17','NEG_HEURISTIC_CAUSALITY','VERIFY_ASSERTION_REQUIRED','VERIFY_QUERY_ONCE'),
    ('N-18','NEG_OVERTRACKING','VERIFY_ASSERTION_REQUIRED','VERIFY_QUERY_ONCE'),
    ('N-6','ADR_APPROVED','DECISION_AUTHORITY_REQUIRED','DECISION_GATE'),
    ('N-6','DERIVE_FROM_RULE','MATERIALIZATION_CONTRACT_REQUIRED','MATERIALIZE_DECLARED_DELIVERABLE'),
    ('N-6','NEGATIVE_ESCALATE','VERIFY_ASSERTION_REQUIRED','VERIFY_QUERY_ONCE'),
    ('N-6','TERMINAL','TERMINAL_ACCEPTANCE_REQUIRED','TERMINAL_RECONCILE')
    ) as m(unit_code,checkpoint_code,contract_family,explicit_action_kind)
  loop
    select pu.unit_metadata#>array['source_pack_v1','checkpoint_inputs',r.checkpoint_code]
      into v_pack
    from programacion.engineering_plan_units pu
    where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
      and pu.unit_code=r.unit_code
      and pu.disposition='ASSIGNED';

    if v_pack is null then
      v_pack:='{}'::jsonb;
    end if;

    v_queries:=coalesce(v_pack#>'{inputs,queries}','[]'::jsonb);
    v_artifacts:=coalesce(v_pack#>'{inputs,artifacts}','[]'::jsonb);
    v_assets:=coalesce(v_pack#>'{inputs,assets}','[]'::jsonb);
    v_events:=coalesce(v_pack#>'{inputs,events}','[]'::jsonb);
    v_objects:=coalesce(v_pack#>'{inputs,db_objects}','[]'::jsonb);
    v_missing:=coalesce(v_pack->'missing_typed','[]'::jsonb);

    if r.contract_family='READ_ONLY_EVIDENCE' then
      if jsonb_array_length(v_queries)=0 then
        raise exception 'IG_READ_ONLY_EVIDENCE_QUERY_MISSING:%/%',r.unit_code,r.checkpoint_code;
      end if;
      v_status:='READY';
      v_requires_material:=false;
      v_expected:='Execute only the exact bounded source-pack readback/observation queries and persist their evidence. No semantic mutation, title inference, hidden discovery, or production activation.';
      v_required:=jsonb_build_object(
        'query_source','SOURCE_PACK_V1_EXACT',
        'semantic_pass_predicate','NOT_REQUIRED_FOR_EVIDENCE_ONLY_READBACK'
      );

    elsif r.contract_family='VERIFY_ASSERTION_REQUIRED' then
      v_status:='BLOCK_VERIFICATION_ASSERTION_REQUIRED';
      v_requires_material:=true;
      v_expected:='Checkpoint remains fail-closed until a machine-verifiable assertion_contract/pass_when is authored for the declared verification queries.';
      v_required:=jsonb_build_object(
        'verification_queries','SOURCE_PACK_V1_EXACT',
        'assertion_contract',jsonb_build_object(
          'pass_when','REQUIRED_MACHINE_VERIFIABLE_OBJECT'
        )
      );

    elsif r.contract_family='TERMINAL_ACCEPTANCE_REQUIRED' then
      v_status:='BLOCK_TERMINAL_ACCEPTANCE_CONTRACT_REQUIRED';
      v_requires_material:=true;
      v_expected:='Checkpoint remains fail-closed until terminal acceptance is expressed as machine-verifiable readback plus assertion receipt; narrative closure is forbidden.';
      v_required:=jsonb_build_object(
        'terminal_readback','REQUIRED',
        'assertion_contract',jsonb_build_object('pass_when','REQUIRED'),
        'assertion_receipt','REQUIRED_BEFORE_DONE'
      );

    elsif r.contract_family='MATERIALIZATION_CONTRACT_REQUIRED' then
      v_status:='BLOCK_MATERIALIZATION_CONTRACT_REQUIRED';
      v_requires_material:=true;
      v_expected:='Checkpoint remains fail-closed until the implementation source, exact mutation target and machine-verifiable result assertion are explicitly authored. Source-pack artifacts are evidence only.';
      v_required:=jsonb_build_object(
        'implementation_ref','REQUIRED',
        'mutation_target','REQUIRED_EXPLICIT',
        'assertion_contract','REQUIRED',
        'evidence_artifacts_role','EVIDENCE_ONLY'
      );

    elsif r.contract_family='DECISION_AUTHORITY_REQUIRED' then
      v_status:='BLOCK_DECISION_AUTHORITY_CONTRACT_REQUIRED';
      v_requires_material:=true;
      v_expected:='Checkpoint remains fail-closed until the exact decision authority, decision record contract and machine-verifiable acceptance binding are explicitly authored.';
      v_required:=jsonb_build_object(
        'authority_ref','REQUIRED',
        'decision_record_contract','REQUIRED',
        'assertion_contract','REQUIRED'
      );

    elsif r.contract_family='MUTATION_TARGET_ASSERTION_REQUIRED' then
      v_status:='BLOCK_MUTATION_TARGET_ASSERTION_REQUIRED';
      v_requires_material:=true;
      v_expected:='Checkpoint remains fail-closed until mutation target, rollback boundary and post-mutation assertion contract are explicit. Evidence artifacts cannot grant write authority.';
      v_required:=jsonb_build_object(
        'mutation_target','REQUIRED_EXPLICIT',
        'rollback_contract','REQUIRED',
        'assertion_contract','REQUIRED',
        'evidence_artifacts_role','EVIDENCE_ONLY'
      );

    elsif r.contract_family='AUTHORED_TEST_DRILL_REQUIRED' then
      v_status:='BLOCK_AUTHORED_TEST_DRILL_CONTRACT_REQUIRED';
      v_requires_material:=true;
      v_expected:='Checkpoint remains fail-closed until an exact authored test/fault/rollback/reproducibility contract names the bounded execution, expected result and machine-verifiable assertion.';
      v_required:=jsonb_build_object(
        'test_or_drill_contract','REQUIRED_EXACT',
        'bounded_execution','REQUIRED',
        'assertion_contract','REQUIRED',
        'fallback_case_discovery','FORBIDDEN'
      );
    else
      raise exception 'IG_EXPLICIT_FAMILY_UNSUPPORTED:%',r.contract_family;
    end if;

    v_spec:=jsonb_strip_nulls(jsonb_build_object(
      'schema_version','ENGINEERING_ACTION_SPEC_V3',
      'status',v_status,
      'checkpoint_code',r.checkpoint_code,
      'action_kind',r.explicit_action_kind,
      'recipe_mode','EXPLICIT_FAMILY_CONTRACT_V1',
      'precision','EXPLICIT_FAMILY_SANITATION_V1',
      'contract_family',r.contract_family,
      'contract_source','EXPLICIT_ACTION_SPEC',
      'requires_material_execution',v_requires_material,
      'mutation_policy',case
        when r.contract_family='READ_ONLY_EVIDENCE' then 'NO_DOMAIN_MUTATION'
        when r.contract_family in (
          'MATERIALIZATION_CONTRACT_REQUIRED',
          'MUTATION_TARGET_ASSERTION_REQUIRED'
        ) then 'EXPLICIT_TARGET_REQUIRED'
        else 'NO_IMPLICIT_MUTATION'
      end,
      'expected',v_expected,
      'verification_queries',case
        when jsonb_array_length(v_queries)>0 then v_queries
        else null
      end,
      'target',jsonb_build_object(
        'declared_objects',v_objects,
        'declared_artifacts',v_artifacts,
        'declared_assets',v_assets,
        'declared_events',v_events,
        'mutation_artifacts','[]'::jsonb
      ),
      'source_pack_missing_typed',v_missing,
      'required_contract',v_required,
      'forbidden',jsonb_build_array(
        'INFER_EXECUTION_SEMANTICS_FROM_TITLE',
        'INFER_EXECUTION_SEMANTICS_FROM_REGEX',
        'TREAT_EVIDENCE_ARTIFACT_AS_MUTATION_TARGET',
        'SYNTHETIC_PASS_WITHOUT_MACHINE_ASSERTION'
      ),
      'persist',case
        when r.contract_family='READ_ONLY_EVIDENCE' then
          jsonb_build_object(
            'on_pass','DONE',
            'entrypoint','programacion.fn_engineering_checkpoint_transition_v1',
            'next_state','RETURNED_BOOTSTRAP_ONLY'
          )
        else null
      end
    ));

    update programacion.engineering_plan_units pu
       set unit_metadata=jsonb_set(
         coalesce(pu.unit_metadata,'{}'::jsonb),
         '{action_specs_v1}',
         coalesce(pu.unit_metadata->'action_specs_v1','{}'::jsonb)
           || jsonb_build_object(r.checkpoint_code,v_spec),
         true
       )
     where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
       and pu.unit_code=r.unit_code
       and pu.disposition='ASSIGNED';

    if not found then
      raise exception 'IG_EXPLICIT_FAMILY_UNIT_NOT_FOUND:%/%',r.unit_code,r.checkpoint_code;
    end if;
  end loop;

  select count(*)
    into v_after
  from programacion.engineering_plan_units pu
  join programacion.engineering_work_checkpoints c on c.work_item_id=pu.work_item_id
  where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    and pu.disposition='ASSIGNED'
    and c.required
    and c.status not in ('DONE','NOT_APPLICABLE')
    and programacion.fn_engineering_checkpoint_action_spec_v3(
          'IG_CURATOR_VALIDATOR_REFACTOR_V2',pu.unit_code,c.checkpoint_code
        )->>'contract_source'='HEURISTIC_BLOCKED';

  if v_after<>0 then
    raise exception 'IG_EXPLICIT_FAMILY_SANITATION_INCOMPLETE remaining=%',v_after;
  end if;
end;
$sanitation$;

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
) values (
  'ENGINEERING-IG-HEURISTIC-CONTRACT-FAMILY-SANITATION-001',
  'ENGINEERING_ORCHESTRATION',
  'Open IG checkpoints must use explicit contract families instead of title-derived semantics',
  '171 open IG checkpoints were fail-closed as HEURISTIC_BLOCKED because their execution semantics were inferred from checkpoint titles/regex. They are now frozen by exact unit_code+checkpoint_code into seven explicit families. Only nine evidence-only readbacks/observations are READY; every verification, terminal, materialization, decision, mutation and test/drill family stays explicitly fail-closed until its missing machine contract is authored.',
  'Execution semantics were absent from unit action_specs_v1 and the legacy compiler attempted to infer material behavior from titles.',
  'TITLE_REGEX_INFERENCE_FOR_OPEN_CHECKPOINT_EXECUTION',
  'Author exact action_specs_v1 at checkpoint definition time. Evidence-only source-pack reads may be READY when bounded; all semantic verification/mutation/decision/test/terminal work must name machine-verifiable acceptance and, where applicable, mutation authority.',
  'Plan sanitation must report heuristic_blocked=0. Exact family counts: READ_ONLY_EVIDENCE=9, VERIFY_ASSERTION_REQUIRED=43, TERMINAL_ACCEPTANCE_REQUIRED=34, MATERIALIZATION_CONTRACT_REQUIRED=48, DECISION_AUTHORITY_REQUIRED=16, MUTATION_TARGET_ASSERTION_REQUIRED=8, AUTHORED_TEST_DRILL_REQUIRED=13.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','ACTIVO',
  'supabase://programacion.engineering_plan_units/IG_CURATOR_VALIDATOR_REFACTOR_V2; github://cristhianlujan/claude-persona-lf-patch/supabase/migrations/20261007005500_ig_explicit_contract_family_sanitation_v1.sql',
  'EXECUTION',
  array['ENGINEERING_SCHEDULER','PROGRAMMING_AGENT']::text[],
  'R2_NO_VE','LOUD_EARLY',
  'IG open checkpoint explicit-contract sanitation',
  'supabase://programacion.engineering_plan_units'
)
on conflict (codigo) do update set
  descripcion=excluded.descripcion,
  causa_raiz=excluded.causa_raiz,
  patron=excluded.patron,
  prevencion=excluded.prevencion,
  validacion=excluded.validacion,
  evidencia=excluded.evidencia,
  ultima_vez=now(),
  updated_at=now();
