CREATE OR REPLACE FUNCTION programacion.fn_engineering_action_spec_assertion_contract_v1(p_plan_code text, p_unit_code text, p_checkpoint_code text, p_spec jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
  v_spec jsonb := coalesce(p_spec,'{}'::jsonb);
  v_material boolean := coalesce((v_spec->>'requires_material_execution')::boolean,false);
  v_kind text := coalesce(v_spec->>'action_kind','');
  v_explicit jsonb := v_spec->'assertion_contract';
  v_result_contract jsonb;
  v_exec jsonb;
  v_code text;
  v_current_version text;
  v_current_manifest_sha text;
  v_validator_ref text;
  v_output_schema text;
  v_manifest jsonb;
  v_output_fields jsonb := '[]'::jsonb;
  v_consumer_assertion jsonb;
  v_pass_when jsonb;
  v_required_nonempty jsonb := '[]'::jsonb;
begin
  if coalesce(v_spec->>'status','')<>'READY' then
    return jsonb_build_object(
      'schema_version','ENGINEERING_ASSERTION_CONTRACT_V1',
      'status','BLOCK_ACTION_SPEC_NOT_READY',
      'plan_code',p_plan_code,
      'unit_code',p_unit_code,
      'checkpoint_code',p_checkpoint_code
    );
  end if;

  if not v_material then
    return jsonb_build_object(
      'schema_version','ENGINEERING_ASSERTION_CONTRACT_V1',
      'status','NOT_REQUIRED',
      'plan_code',p_plan_code,
      'unit_code',p_unit_code,
      'checkpoint_code',p_checkpoint_code,
      'reason','NON_MATERIAL_CHECKPOINT'
    );
  end if;

  if v_kind='DECLARED_CAPABILITY_TEST_EXECUTION' then
    v_result_contract:=v_spec#>'{capability_execution,result_contract}';
    v_pass_when:=v_result_contract->'pass_when';

    if jsonb_typeof(v_result_contract)<>'object'
       or nullif(btrim(coalesce(v_result_contract->>'test_code','')),'') is null
       or jsonb_typeof(v_pass_when)<>'object' then
      return jsonb_build_object(
        'schema_version','ENGINEERING_ASSERTION_CONTRACT_V1',
        'status','BLOCK_ASSERTION_CONTRACT_INCOMPLETE',
        'mode','CAPABILITY_TEST_RESULT_CONTRACT',
        'reason','EXACT_TEST_CODE_AND_PASS_WHEN_REQUIRED',
        'plan_code',p_plan_code,
        'unit_code',p_unit_code,
        'checkpoint_code',p_checkpoint_code
      );
    end if;

    return jsonb_strip_nulls(jsonb_build_object(
      'schema_version','ENGINEERING_ASSERTION_CONTRACT_V1',
      'status','READY',
      'mode','CAPABILITY_TEST_RESULT_CONTRACT',
      'plan_code',p_plan_code,
      'unit_code',p_unit_code,
      'checkpoint_code',p_checkpoint_code,
      'expected_status','PASS',
      'test_code',v_result_contract->>'test_code',
      'suite_code',nullif(v_result_contract->>'suite_code',''),
      'pass_when',v_pass_when
    ));
  end if;

  if v_kind='TRANSVERSAL_REPOSITORY_CAPABILITY_EXECUTION' then
    -- rama no ejercida por CT01 (action_kind=GOVERNED_MATERIAL_VERIFICATION); omitida en la réplica local
    return jsonb_build_object('status','LOCAL_REPLICA_BRANCH_NOT_COPIED');
  end if;

  if jsonb_typeof(v_explicit)='object' then
    v_pass_when:=v_explicit->'pass_when';
    if jsonb_typeof(v_pass_when)<>'object' then
      return jsonb_build_object(
        'schema_version','ENGINEERING_ASSERTION_CONTRACT_V1',
        'status','BLOCK_ASSERTION_CONTRACT_INCOMPLETE',
        'mode','EXPLICIT_PASS_WHEN_SUBSET',
        'reason','PASS_WHEN_OBJECT_REQUIRED',
        'plan_code',p_plan_code,
        'unit_code',p_unit_code,
        'checkpoint_code',p_checkpoint_code
      );
    end if;

    return jsonb_build_object(
      'schema_version','ENGINEERING_ASSERTION_CONTRACT_V1',
      'status','READY',
      'mode',coalesce(nullif(v_explicit->>'mode',''),'EXPLICIT_PASS_WHEN_SUBSET'),
      'plan_code',p_plan_code,
      'unit_code',p_unit_code,
      'checkpoint_code',p_checkpoint_code,
      'expected_status','PASS',
      'pass_when',v_pass_when
    );
  end if;

  return jsonb_build_object(
    'schema_version','ENGINEERING_ASSERTION_CONTRACT_V1',
    'status','BLOCK_ASSERTION_CONTRACT_REQUIRED',
    'mode','UNBOUND_MATERIAL_RESULT',
    'reason','MATERIAL_DONE_REQUIRES_MACHINE_VERIFIABLE_ASSERTION_BINDING',
    'plan_code',p_plan_code,
    'unit_code',p_unit_code,
    'checkpoint_code',p_checkpoint_code,
    'action_kind',v_kind
  );
end;
$function$;
