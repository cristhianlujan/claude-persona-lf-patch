-- IG_CURATOR_VALIDATOR_REFACTOR_V2
-- Contract audit / 10-unit batch.
-- Scope: M6.12, M6.2, M6.7, N-17, M1.A8, M10.1, M10.11, M10.12, M10.2, M4.7.
-- Only three units require canonical contract correction.

do $audit_pre$
begin
  if not exists (
    select 1 from programacion.engineering_plan_units
    where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
      and unit_code='M10.12'
      and unit_metadata#>>'{transversal_execution_v1,REUSE_LEGACY_RETIREMENT,capabilities,0,handler}'='REPOSITORY_CAPABILITY_EXECUTOR'
  ) then
    raise exception 'AUDIT10_M10_12_BASE_DRIFT';
  end if;

  if not exists (
    select 1 from programacion.engineering_plan_units
    where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
      and unit_code='M6.2'
      and unit_metadata#>>'{action_specs_v1,GRAPH_SHA_RECEIPT,status}'='READY'
  ) then
    raise exception 'AUDIT10_M6_2_BASE_DRIFT';
  end if;

  if not exists (
    select 1 from programacion.engineering_plan_units
    where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
      and unit_code='M4.7'
      and unit_metadata#>>'{action_specs_v1,NEG_NO_PROMOTION,status}'='READY'
  ) then
    raise exception 'AUDIT10_M4_7_BASE_DRIFT';
  end if;
end
$audit_pre$;

-- M10.12: ASSET_RETIREMENT_GOVERNANCE is a governance-contract readback capability.
-- Do not send its JSON contract to the repository RUN_TEST executor.
update programacion.engineering_plan_units pu
set unit_metadata = jsonb_set(
  pu.unit_metadata,
  '{transversal_execution_v1,REUSE_LEGACY_RETIREMENT,capabilities,0}',
  (
    (pu.unit_metadata#>'{transversal_execution_v1,REUSE_LEGACY_RETIREMENT,capabilities,0}')
      - 'execution_input'
  ) || jsonb_build_object(
    'handler','CAPABILITY_CURRENT_READBACK',
    'capability_code','ASSET_RETIREMENT_GOVERNANCE'
  ),
  true
)
where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and pu.unit_code='M10.12';

-- M6.2: fail closed at contract boundary until the ledger execution binding is canonical.
-- This prevents the executor from reaching Git authoring and then discovering no valid
-- public.lf_operation_execution binding for fn_lf_evidence_ledger_anchor_v1.
update programacion.engineering_plan_units pu
set unit_metadata = jsonb_set(
  pu.unit_metadata,
  '{action_specs_v1,GRAPH_SHA_RECEIPT}',
  (
    pu.unit_metadata#>'{action_specs_v1,GRAPH_SHA_RECEIPT}'
  )
  || jsonb_build_object(
    'status','BLOCK_MATERIALIZATION_CONTRACT_REQUIRED',
    'precision','EXACT_EVIDENCE_LEDGER_EXECUTION_BINDING_REQUIRED_V1',
    'blocking_codes',jsonb_build_array('EVIDENCE_LEDGER_EXECUTION_BINDING_MISSING'),
    'required_contract',
      coalesce(pu.unit_metadata#>'{action_specs_v1,GRAPH_SHA_RECEIPT,required_contract}','{}'::jsonb)
      || jsonb_build_object(
        'execution_binding','REQUIRED_CANONICAL',
        'execution_binding_authority','public.lf_operation_execution',
        'ledger_entrypoint','public.fn_lf_evidence_ledger_anchor_v1',
        'binding_rule','EXACT_PLAN_UNIT_OR_GOVERNED_WRAPPER',
        'hardcoded_foreign_execution_id','FORBIDDEN'
      ),
    'handler_requirement',jsonb_build_object(
      'handler','EVIDENCE_LEDGER_EXECUTION_BINDING_RESOLVER',
      'status','INPUT_REQUIRED',
      'required_before_execution',jsonb_build_array(
        'CANONICAL_EXECUTION_ID_BOUND_TO_M6_2_OR_PLAN',
        'ORCHESTRATOR_OR_GOVERNED_WRAPPER_PROVENANCE',
        'POST_WRITE_LEDGER_READBACK'
      ),
      'inference','FORBIDDEN'
    ),
    'expected','Do not author/apply GRAPH_SHA_RECEIPT until a canonical EVIDENCE_LEDGER operation execution is bound to M6.2/PAULO-049 or supplied by a governed wrapper; then emit and read back the graph-SHA receipt.'
  ),
  true
)
where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and pu.unit_code='M6.2';

-- M4.7: the negative requires a real persisted FAIL/BLOCKED attempt.
-- SentinelX-only code execution + aggregate run counts cannot manufacture or prove it.
update programacion.engineering_plan_units pu
set unit_metadata = jsonb_set(
  pu.unit_metadata,
  '{action_specs_v1,NEG_NO_PROMOTION}',
  (
    pu.unit_metadata#>'{action_specs_v1,NEG_NO_PROMOTION}'
  )
  || jsonb_build_object(
    'status','BLOCK_MATERIALIZATION_CONTRACT_REQUIRED',
    'precision','EXACT_NEGATIVE_FIXTURE_AND_READBACK_REQUIRED_V1',
    'blocking_codes',jsonb_build_array('NEGATIVE_EXECUTION_CONTRACT_INCOMPLETE'),
    'required_contract',jsonb_build_object(
      'real_negative_fixture','REQUIRED',
      'receipt_outcome','FAIL_OR_BLOCKED_REQUIRED',
      'receipt_findings_readback','REQUIRED',
      'run_currentness_before_after','REQUIRED',
      'promotion_delta','MUST_EQUAL_ZERO',
      'cleanup','REQUIRED_IF_TEST_FIXTURE_PERSISTS'
    ),
    'handler_requirement',jsonb_build_object(
      'handler','AUTHORED_NEGATIVE_WITH_DB_FIXTURE',
      'status','INPUT_REQUIRED',
      'required_before_execution',jsonb_build_array(
        'EXACT_FIXTURE_ENTRYPOINT_OR_CASE_CODE',
        'EXACT_FAIL_OR_BLOCKED_EXPECTED_OUTCOME',
        'EXACT_RECEIPT_READBACK_QUERY',
        'EXACT_NO_PROMOTION_READBACK_QUERY',
        'FIXTURE_CLEANUP_CONTRACT'
      ),
      'existing_exact_case_set_found',false,
      'fallback_case_discovery','FORBIDDEN'
    ),
    'expected','Execute only after the contract identifies an exact controlled fixture/case that produces a real persisted FAIL/BLOCKED receipt, proves typed findings, and proves zero promotion/currentness change.'
  ),
  true
)
where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and pu.unit_code='M4.7';

do $audit_post$
declare
  v_spec jsonb;
  v_input jsonb;
  v_packet jsonb;
begin
  -- M10.12 must now compile cleanly by capability-current readback.
  v_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M10.12','REUSE_LEGACY_RETIREMENT'
  );
  select coalesce(
           unit_metadata#>'{source_pack_v2,checkpoint_inputs,REUSE_LEGACY_RETIREMENT}',
           unit_metadata#>'{source_pack_v1,checkpoint_inputs,REUSE_LEGACY_RETIREMENT}',
           '{}'::jsonb
         )
    into v_input
  from programacion.engineering_plan_units
  where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_code='M10.12';

  v_packet:=programacion.fn_engineering_execution_packet_from_spec_v1(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M10.12','REUSE_LEGACY_RETIREMENT',v_spec,v_input
  );

  if coalesce(v_spec->>'status','')<>'READY'
     or coalesce(v_packet->>'status','')<>'READY' then
    raise exception 'AUDIT10_M10_12_POSTCHECK_FAILED spec=% packet=%',
      v_spec->>'status',v_packet->>'status';
  end if;

  -- M6.2 must fail closed before material execution until binding is supplied.
  v_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M6.2','GRAPH_SHA_RECEIPT'
  );
  if coalesce(v_spec->>'status','')='READY'
     or not (coalesce(v_spec->'blocking_codes','[]'::jsonb) ? 'EVIDENCE_LEDGER_EXECUTION_BINDING_MISSING') then
    raise exception 'AUDIT10_M6_2_POSTCHECK_FAILED:%',v_spec::text;
  end if;

  -- M4.7 must fail closed before RUN_TEST until exact negative fixture exists.
  v_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M4.7','NEG_NO_PROMOTION'
  );
  if coalesce(v_spec->>'status','')='READY'
     or not (coalesce(v_spec->'blocking_codes','[]'::jsonb) ? 'NEGATIVE_EXECUTION_CONTRACT_INCOMPLETE') then
    raise exception 'AUDIT10_M4_7_POSTCHECK_FAILED:%',v_spec::text;
  end if;
end
$audit_post$;
