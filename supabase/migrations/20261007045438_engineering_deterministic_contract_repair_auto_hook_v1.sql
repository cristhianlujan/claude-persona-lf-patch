-- Deterministic contract repair auto-hook v1.
-- Reconciles tested runtime functions into canonical Git source.
-- Supported blockers are repaired only with exact registered/explicit inputs.
-- Missing semantic inputs remain fail-closed; title/regex inference is forbidden.

CREATE OR REPLACE FUNCTION programacion.fn_engineering_jsonb_nonempty_array_v1(p_value jsonb)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
select case
  when jsonb_typeof(p_value)='array' then jsonb_array_length(p_value)>0
  else false
end;
$function$
;

CREATE OR REPLACE FUNCTION programacion.fn_engineering_assertion_input_valid_v1(p_value jsonb)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
select case
  when jsonb_typeof(p_value)='object'
   and jsonb_typeof(p_value->'pass_when')='object'
  then true
  else false
end;
$function$
;

CREATE OR REPLACE FUNCTION programacion.fn_engineering_packet_apply_explicit_write_contract_v1(p_packet jsonb, p_action_spec jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'programacion', 'public', 'pg_catalog'
AS $function$
declare
  v_contract jsonb:=p_action_spec->'materialization_contract';
  v_plan jsonb:='[]'::jsonb;
  v_item jsonb;
  v_patch jsonb;
  v_entrypoint text;
  v_call_template text;
  v_owned boolean:=
    coalesce(p_action_spec#>>'{repair_contract,schema_version}','')='ENGINEERING_CONTRACT_REPAIR_V1'
    and coalesce(p_action_spec#>>'{repair_contract,previous_blocker}','')='BLOCK_MATERIALIZATION_CONTRACT_REQUIRED';
begin
  -- This adapter belongs only to deterministic materialization repairs.
  -- Existing action specs keep their prior packet semantics unchanged.
  if not v_owned
     or coalesce(p_packet->>'status','')<>'READY'
     or coalesce(p_packet->>'execution_capability','')<>'WRITE_DB' then
    return p_packet;
  end if;

  if jsonb_typeof(v_contract)<>'object' then
    return p_packet || jsonb_build_object(
      'status','BLOCK_EXPLICIT_WRITE_CONTRACT_REQUIRED',
      'execution_allowed',false,
      'block_reasons',
        coalesce(p_packet->'block_reasons','[]'::jsonb)
        || jsonb_build_array('EXPLICIT_WRITE_CONTRACT_OBJECT_REQUIRED'),
      'connector_plan','[]'::jsonb
    );
  end if;

  v_entrypoint:=nullif(btrim(coalesce(v_contract->>'entrypoint','')),'');
  v_call_template:=nullif(btrim(coalesce(v_contract->>'call_template','')),'');

  if v_entrypoint is null and v_call_template is null then
    return p_packet || jsonb_build_object(
      'status','BLOCK_EXPLICIT_WRITE_CONTRACT_REQUIRED',
      'execution_allowed',false,
      'block_reasons',
        coalesce(p_packet->'block_reasons','[]'::jsonb)
        || jsonb_build_array('EXPLICIT_WRITE_ENTRYPOINT_OR_CALL_TEMPLATE_REQUIRED'),
      'connector_plan','[]'::jsonb
    );
  end if;

  for v_item in
    select value from jsonb_array_elements(coalesce(p_packet->'connector_plan','[]'::jsonb))
  loop
    if v_item->>'operation'='WRITE_DB' then
      v_patch:=jsonb_strip_nulls(jsonb_build_object(
        'entrypoint',v_entrypoint,
        'call_template',v_call_template,
        'implementation_ref',nullif(btrim(coalesce(p_action_spec->>'implementation_ref','')),'')
      ));
      v_item:=v_item || v_patch;
    end if;
    v_plan:=v_plan||jsonb_build_array(v_item);
  end loop;

  return jsonb_set(
    p_packet || jsonb_build_object(
      'explicit_write_contract_gate',jsonb_build_object(
        'status','PASS',
        'source','DETERMINISTIC_CONTRACT_REPAIR_V1',
        'raw_sql_inference','FORBIDDEN'
      )
    ),
    '{connector_plan}',v_plan,true
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION programacion.fn_engineering_execution_packet_from_spec_v1(p_plan_code text, p_unit_code text, p_checkpoint_code text, p_action_spec jsonb, p_execution_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'programacion', 'public', 'pg_catalog'
AS $function$
declare
  v_packet jsonb;
  v_budget int;
  v_spec jsonb := programacion.fn_engineering_action_spec_artifact_roles_v1(
    coalesce(p_action_spec,'{}'::jsonb)
  );
  v_material boolean := coalesce((p_action_spec->>'requires_material_execution')::boolean,false);
  v_kind text := coalesce(p_action_spec->>'action_kind','');
  v_title text := coalesce(p_action_spec->>'checkpoint_title','');
begin
  if v_material
     and v_kind not in ('READBACK_ONCE','OBSERVE_ONCE','DECISION_GATE','TERMINAL_RECONCILE') then
    v_spec := jsonb_set(
      v_spec,
      '{checkpoint_title}',
      to_jsonb('execute material: ' || v_title),
      true
    );
  end if;

  v_packet:=programacion.fn_engineering_execution_packet_from_spec_core_v1(
    p_plan_code,p_unit_code,p_checkpoint_code,v_spec,p_execution_input
  );

  v_packet:=programacion.fn_engineering_execution_packet_apply_transversal_adapter_v1(
    v_packet,p_plan_code,p_unit_code,p_checkpoint_code,p_action_spec
  );

  v_packet:=programacion.fn_engineering_execution_packet_apply_bounded_checkpoint_test_v1(
    v_packet,p_plan_code,p_unit_code,p_checkpoint_code,p_action_spec
  );

  v_packet:=programacion.fn_engineering_packet_apply_test_contract_guard_v1(
    v_packet,p_action_spec
  );

  v_packet:=programacion.fn_engineering_packet_apply_assertion_guard_v1(
    v_packet,p_plan_code,p_unit_code,p_checkpoint_code,p_action_spec
  );

  v_budget:=nullif(p_action_spec#>>'{read_budget,checkpoint_queries_max}','')::int;

  if v_budget is null then
    select nullif(
      coalesce(
        pu.unit_metadata#>>'{source_fast_path_v2,read_budget,checkpoint_queries_max}',
        pu.unit_metadata#>>'{source_fast_path_v1,preferred_queries_max}'
      ),''
    )::int
    into v_budget
    from programacion.engineering_plan_units pu
    where pu.plan_code=p_plan_code
      and pu.unit_code=p_unit_code;
  end if;

  v_packet:=programacion.fn_engineering_packet_apply_read_budget_v1(
    v_packet,v_budget
  );

  v_packet:=programacion.fn_engineering_packet_apply_governed_merge_v1(v_packet);

  return v_packet || jsonb_build_object(
    'artifact_role_contract',v_spec->'artifact_role_contract',
    'evidence_artifacts',v_spec#>'{target,evidence_artifacts}',
    'mutation_artifacts',v_spec#>'{target,mutation_artifacts}',
    'readonly_policy',jsonb_build_object(
      'scope','EXPLICIT_READ_ACTIONS_ONLY',
      'materiality_authority','ACTION_SPEC_REQUIRES_MATERIAL_EXECUTION',
      'title_based_materiality_downgrade','FORBIDDEN',
      'material_actions_allowed',jsonb_build_array('WRITE_DB','WRITE_GIT','RUN_TEST')
    )
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION programacion.fn_engineering_contract_repair_core_v1(p_plan_code text, p_unit_code text, p_checkpoint_code text, p_expected_blocker text, p_patch jsonb, p_apply boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'programacion', 'public', 'extensions', 'pg_catalog'
AS $function$
declare
  v_meta jsonb;
  v_current jsonb;
  v_compiled jsonb;
  v_candidate jsonb;
  v_packet jsonb;
  v_readiness jsonb;
  v_after_spec jsonb;
  v_after_readiness jsonb;
  v_digest text;
begin
  if p_plan_code is null or btrim(p_plan_code)='' or
     p_unit_code is null or btrim(p_unit_code)='' or
     p_checkpoint_code is null or btrim(p_checkpoint_code)='' or
     p_expected_blocker is null or btrim(p_expected_blocker)='' then
    return jsonb_build_object(
      'schema_version','ENGINEERING_CONTRACT_REPAIR_V1',
      'status','INPUT_REQUIRED',
      'reason','PLAN_UNIT_CHECKPOINT_AND_BLOCKER_REQUIRED'
    );
  end if;

  if jsonb_typeof(p_patch) <> 'object' then
    return jsonb_build_object(
      'schema_version','ENGINEERING_CONTRACT_REPAIR_V1',
      'status','INPUT_REQUIRED',
      'reason','PATCH_OBJECT_REQUIRED'
    );
  end if;

  if p_apply then
    select pu.unit_metadata into v_meta
    from programacion.engineering_plan_units pu
    where pu.plan_code=p_plan_code and pu.unit_code=p_unit_code
    for update;
  else
    select pu.unit_metadata into v_meta
    from programacion.engineering_plan_units pu
    where pu.plan_code=p_plan_code and pu.unit_code=p_unit_code;
  end if;

  if not found then
    return jsonb_build_object(
      'schema_version','ENGINEERING_CONTRACT_REPAIR_V1',
      'status','NOT_FOUND',
      'plan_code',p_plan_code,'unit_code',p_unit_code,'checkpoint_code',p_checkpoint_code
    );
  end if;

  v_current:=v_meta#>array['action_specs_v1',p_checkpoint_code];
  if v_current is null then
    return jsonb_build_object(
      'schema_version','ENGINEERING_CONTRACT_REPAIR_V1',
      'status','NOT_APPLICABLE',
      'reason','EXPLICIT_ACTION_SPEC_MISSING',
      'plan_code',p_plan_code,'unit_code',p_unit_code,'checkpoint_code',p_checkpoint_code
    );
  end if;

  v_compiled:=programacion.fn_engineering_checkpoint_action_spec_v3(
    p_plan_code,p_unit_code,p_checkpoint_code
  );

  if coalesce(v_compiled->>'status','')='READY' then
    return jsonb_build_object(
      'schema_version','ENGINEERING_CONTRACT_REPAIR_V1',
      'status','ALREADY_READY',
      'plan_code',p_plan_code,'unit_code',p_unit_code,'checkpoint_code',p_checkpoint_code
    );
  end if;

  if coalesce(v_compiled->>'status','')<>p_expected_blocker then
    return jsonb_build_object(
      'schema_version','ENGINEERING_CONTRACT_REPAIR_V1',
      'status','NOT_APPLICABLE',
      'reason','CURRENT_BLOCKER_DIFFERS',
      'expected_blocker',p_expected_blocker,
      'current_blocker',v_compiled->>'status',
      'plan_code',p_plan_code,'unit_code',p_unit_code,'checkpoint_code',p_checkpoint_code
    );
  end if;

  v_candidate:=v_current || (p_patch - 'target');

  if p_patch->'target' is not null then
    if jsonb_typeof(p_patch->'target')<>'object' then
      return jsonb_build_object(
        'schema_version','ENGINEERING_CONTRACT_REPAIR_V1',
        'status','INPUT_REQUIRED',
        'reason','TARGET_OBJECT_REQUIRED'
      );
    end if;

    v_candidate:=jsonb_set(
      v_candidate,'{target}',
      coalesce(v_current->'target','{}'::jsonb) || (p_patch->'target'),true
    );
  end if;

  v_candidate:=v_candidate || jsonb_build_object(
    'status','READY',
    'contract_source','EXPLICIT_ACTION_SPEC',
    'precision','DETERMINISTIC_CONTRACT_REPAIR_V1',
    'repair_contract',jsonb_build_object(
      'schema_version','ENGINEERING_CONTRACT_REPAIR_V1',
      'previous_blocker',p_expected_blocker,
      'mode','EXACT_INPUT_ONLY',
      'inference','FORBIDDEN'
    )
  );

  v_digest:=encode(extensions.digest(convert_to(v_candidate::text,'UTF8'),'sha256'),'hex');

  v_packet:=programacion.fn_engineering_execution_packet_from_spec_v1(
    p_plan_code,p_unit_code,p_checkpoint_code,v_candidate,'{}'::jsonb
  );

  v_readiness:=programacion.fn_engineering_checkpoint_execution_readiness_from_payload_v1(
    p_plan_code,p_unit_code,p_checkpoint_code,v_candidate,v_packet
  );

  if coalesce(v_packet->>'status','')<>'READY'
     or not coalesce((v_readiness#>>'{gates,COMPILE_READY}')::boolean,false)
     or not coalesce((v_readiness#>>'{gates,ACTION_EXACT}')::boolean,false)
     or not coalesce((v_readiness#>>'{gates,ERROR_CLOSED}')::boolean,false) then
    return jsonb_build_object(
      'schema_version','ENGINEERING_CONTRACT_REPAIR_V1',
      'status','PATCH_REJECTED',
      'reason','CANDIDATE_NOT_EXECUTION_EXACT',
      'plan_code',p_plan_code,
      'unit_code',p_unit_code,
      'checkpoint_code',p_checkpoint_code,
      'expected_blocker',p_expected_blocker,
      'candidate_sha256',v_digest,
      'packet_status',v_packet->>'status',
      'readiness_gates',v_readiness->'gates',
      'readiness_reasons',v_readiness->'reasons'
    );
  end if;

  if not p_apply then
    return jsonb_build_object(
      'schema_version','ENGINEERING_CONTRACT_REPAIR_V1',
      'status','DRY_RUN_READY',
      'plan_code',p_plan_code,
      'unit_code',p_unit_code,
      'checkpoint_code',p_checkpoint_code,
      'resolved_blocker',p_expected_blocker,
      'candidate_sha256',v_digest,
      'execution_capability',v_packet->>'execution_capability',
      'post_compile_status',v_packet->>'status',
      'post_readiness_status',v_readiness->>'status',
      'post_readiness_reasons',v_readiness->'reasons'
    );
  end if;

  v_candidate:=v_candidate || jsonb_build_object(
    'repair_receipt',jsonb_build_object(
      'schema_version','ENGINEERING_CONTRACT_REPAIR_RECEIPT_V1',
      'resolved_blocker',p_expected_blocker,
      'candidate_sha256',v_digest,
      'applied_at',now()
    )
  );

  update programacion.engineering_plan_units pu
     set unit_metadata=jsonb_set(
       coalesce(pu.unit_metadata,'{}'::jsonb),
       '{action_specs_v1}',
       coalesce(pu.unit_metadata->'action_specs_v1','{}'::jsonb)
         || jsonb_build_object(p_checkpoint_code,v_candidate),
       true
     )
   where pu.plan_code=p_plan_code and pu.unit_code=p_unit_code;

  if not found then
    raise exception 'ENGINEERING_CONTRACT_REPAIR_UPDATE_LOST:%/%/%',
      p_plan_code,p_unit_code,p_checkpoint_code;
  end if;

  v_after_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(
    p_plan_code,p_unit_code,p_checkpoint_code
  );
  v_after_readiness:=programacion.fn_engineering_checkpoint_execution_readiness_v1(
    p_plan_code,p_unit_code,p_checkpoint_code
  );

  if coalesce(v_after_spec->>'status','')<>'READY'
     or not coalesce((v_after_readiness#>>'{gates,COMPILE_READY}')::boolean,false)
     or not coalesce((v_after_readiness#>>'{gates,ACTION_EXACT}')::boolean,false)
     or not coalesce((v_after_readiness#>>'{gates,ERROR_CLOSED}')::boolean,false) then
    raise exception 'ENGINEERING_CONTRACT_REPAIR_POSTCHECK_FAILED:%/%/% status=% reasons=%',
      p_plan_code,p_unit_code,p_checkpoint_code,
      coalesce(v_after_spec->>'status','(null)'),
      coalesce(v_after_readiness->'reasons','[]'::jsonb)::text;
  end if;

  return jsonb_build_object(
    'schema_version','ENGINEERING_CONTRACT_REPAIR_V1',
    'status','REPAIRED',
    'plan_code',p_plan_code,
    'unit_code',p_unit_code,
    'checkpoint_code',p_checkpoint_code,
    'resolved_blocker',p_expected_blocker,
    'candidate_sha256',v_digest,
    'post_action_spec_status',v_after_spec->>'status',
    'post_readiness_status',v_after_readiness->>'status',
    'post_readiness_reasons',v_after_readiness->'reasons'
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION programacion.fn_engineering_repair_block_verification_assertion_v1(p_plan_code text, p_unit_code text, p_checkpoint_code text, p_contract jsonb, p_apply boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'programacion', 'public', 'pg_catalog'
AS $function$
declare
  v_spec jsonb;
  v_test_code text;
begin
  if not programacion.fn_engineering_assertion_input_valid_v1(p_contract->'assertion_contract') then
    return jsonb_build_object(
      'schema_version','ENGINEERING_FAMILY_REPAIR_V1','status','INPUT_REQUIRED',
      'blocker','BLOCK_VERIFICATION_ASSERTION_REQUIRED',
      'required',jsonb_build_array('assertion_contract.pass_when OBJECT')
    );
  end if;

  v_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(
    p_plan_code,p_unit_code,p_checkpoint_code
  );

  if not programacion.fn_engineering_jsonb_nonempty_array_v1(v_spec->'verification_queries') then
    return jsonb_build_object(
      'schema_version','ENGINEERING_FAMILY_REPAIR_V1','status','INPUT_REQUIRED',
      'blocker','BLOCK_VERIFICATION_ASSERTION_REQUIRED',
      'required',jsonb_build_array('EXISTING verification_queries'),
      'reason','NO_EXACT_VERIFICATION_QUERY_TO_BIND'
    );
  end if;

  v_test_code:='VERIFY:'||upper(replace(p_unit_code,'.','-'))||':'||upper(p_checkpoint_code);

  return programacion.fn_engineering_contract_repair_core_v1(
    p_plan_code,p_unit_code,p_checkpoint_code,
    'BLOCK_VERIFICATION_ASSERTION_REQUIRED',
    jsonb_build_object(
      'action_kind','DECLARED_TEST_EXECUTION',
      'recipe_mode','EXECUTE_DECLARED_TEST_CASESET',
      'mutation_policy','TEST_EVIDENCE_ONLY',
      'assertion_contract',p_contract->'assertion_contract',
      'test_execution_contract',jsonb_build_object(
        'mode','EXPLICIT_VERIFICATION_QUERY',
        'test_code',v_test_code
      ),
      'target',jsonb_build_object(
        'declared_objects',jsonb_build_array(
          'public.lf_test_suite_runs','public.lf_test_runs','public.lf_test_assertion_results'
        ),
        'mutation_artifacts','[]'::jsonb
      ),
      'required_contract',jsonb_build_object('satisfied_by','DETERMINISTIC_CONTRACT_REPAIR_V1')
    ),
    p_apply
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION programacion.fn_engineering_repair_block_terminal_acceptance_v1(p_plan_code text, p_unit_code text, p_checkpoint_code text, p_contract jsonb, p_apply boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'programacion', 'public', 'pg_catalog'
AS $function$
declare v_spec jsonb;
begin
  if coalesce(jsonb_typeof(p_contract->'terminal_readback'),'')<>'object'
     or not programacion.fn_engineering_assertion_input_valid_v1(p_contract->'assertion_contract') then
    return jsonb_build_object(
      'schema_version','ENGINEERING_FAMILY_REPAIR_V1','status','INPUT_REQUIRED',
      'blocker','BLOCK_TERMINAL_ACCEPTANCE_CONTRACT_REQUIRED',
      'required',jsonb_build_array('terminal_readback OBJECT','assertion_contract.pass_when OBJECT')
    );
  end if;

  v_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(
    p_plan_code,p_unit_code,p_checkpoint_code
  );
  if not programacion.fn_engineering_jsonb_nonempty_array_v1(v_spec->'verification_queries') then
    return jsonb_build_object(
      'schema_version','ENGINEERING_FAMILY_REPAIR_V1','status','INPUT_REQUIRED',
      'blocker','BLOCK_TERMINAL_ACCEPTANCE_CONTRACT_REQUIRED',
      'required',jsonb_build_array('EXISTING verification_queries')
    );
  end if;

  return programacion.fn_engineering_contract_repair_core_v1(
    p_plan_code,p_unit_code,p_checkpoint_code,
    'BLOCK_TERMINAL_ACCEPTANCE_CONTRACT_REQUIRED',
    jsonb_build_object(
      'terminal_readback',p_contract->'terminal_readback',
      'assertion_contract',p_contract->'assertion_contract',
      'required_contract',jsonb_build_object('satisfied_by','DETERMINISTIC_CONTRACT_REPAIR_V1')
    ),p_apply
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION programacion.fn_engineering_repair_block_decision_authority_v1(p_plan_code text, p_unit_code text, p_checkpoint_code text, p_contract jsonb, p_apply boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'programacion', 'public', 'pg_catalog'
AS $function$
declare v_spec jsonb;
begin
  if nullif(btrim(coalesce(p_contract->>'authority_ref','')),'') is null
     or coalesce(jsonb_typeof(p_contract->'decision_record_contract'),'')<>'object'
     or not programacion.fn_engineering_assertion_input_valid_v1(p_contract->'assertion_contract') then
    return jsonb_build_object(
      'schema_version','ENGINEERING_FAMILY_REPAIR_V1','status','INPUT_REQUIRED',
      'blocker','BLOCK_DECISION_AUTHORITY_CONTRACT_REQUIRED',
      'required',jsonb_build_array(
        'authority_ref TEXT','decision_record_contract OBJECT','assertion_contract.pass_when OBJECT'
      )
    );
  end if;

  v_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(
    p_plan_code,p_unit_code,p_checkpoint_code
  );
  if not programacion.fn_engineering_jsonb_nonempty_array_v1(v_spec->'verification_queries') then
    return jsonb_build_object(
      'schema_version','ENGINEERING_FAMILY_REPAIR_V1','status','INPUT_REQUIRED',
      'blocker','BLOCK_DECISION_AUTHORITY_CONTRACT_REQUIRED',
      'required',jsonb_build_array('EXISTING verification_queries')
    );
  end if;

  return programacion.fn_engineering_contract_repair_core_v1(
    p_plan_code,p_unit_code,p_checkpoint_code,
    'BLOCK_DECISION_AUTHORITY_CONTRACT_REQUIRED',
    jsonb_build_object(
      'authority_ref',p_contract->>'authority_ref',
      'decision_record_contract',p_contract->'decision_record_contract',
      'assertion_contract',p_contract->'assertion_contract',
      'required_contract',jsonb_build_object('satisfied_by','DETERMINISTIC_CONTRACT_REPAIR_V1')
    ),p_apply
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION programacion.fn_engineering_repair_block_materialization_contract_v1(p_plan_code text, p_unit_code text, p_checkpoint_code text, p_contract jsonb, p_apply boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'programacion', 'public', 'pg_catalog'
AS $function$
declare
  v_db jsonb:=p_contract#>'{mutation_target,db_objects}';
  v_art jsonb:=p_contract#>'{mutation_target,artifacts}';
  v_db_nonempty boolean:=programacion.fn_engineering_jsonb_nonempty_array_v1(v_db);
  v_art_nonempty boolean:=programacion.fn_engineering_jsonb_nonempty_array_v1(v_art);
  v_write jsonb:=p_contract->'materialization_contract';
begin
  if nullif(btrim(coalesce(p_contract->>'implementation_ref','')),'') is null
     or coalesce(jsonb_typeof(p_contract->'mutation_target'),'')<>'object'
     or not (v_db_nonempty or v_art_nonempty)
     or not programacion.fn_engineering_assertion_input_valid_v1(p_contract->'assertion_contract') then
    return jsonb_build_object(
      'schema_version','ENGINEERING_FAMILY_REPAIR_V1','status','INPUT_REQUIRED',
      'blocker','BLOCK_MATERIALIZATION_CONTRACT_REQUIRED',
      'required',jsonb_build_array(
        'implementation_ref TEXT',
        'mutation_target.db_objects[] OR mutation_target.artifacts[]',
        'assertion_contract.pass_when OBJECT'
      )
    );
  end if;

  if not v_art_nonempty and v_db_nonempty and (
       coalesce(jsonb_typeof(v_write),'')<>'object'
       or (
         nullif(btrim(coalesce(v_write->>'entrypoint','')),'') is null
         and nullif(btrim(coalesce(v_write->>'call_template','')),'') is null
       )
     ) then
    return jsonb_build_object(
      'schema_version','ENGINEERING_FAMILY_REPAIR_V1','status','INPUT_REQUIRED',
      'blocker','BLOCK_MATERIALIZATION_CONTRACT_REQUIRED',
      'required',jsonb_build_array(
        'materialization_contract.entrypoint OR materialization_contract.call_template for WRITE_DB'
      )
    );
  end if;

  return programacion.fn_engineering_contract_repair_core_v1(
    p_plan_code,p_unit_code,p_checkpoint_code,
    'BLOCK_MATERIALIZATION_CONTRACT_REQUIRED',
    jsonb_build_object(
      'implementation_ref',p_contract->>'implementation_ref',
      'materialization_contract',coalesce(v_write,'{}'::jsonb),
      'assertion_contract',p_contract->'assertion_contract',
      'target',jsonb_build_object(
        'declared_objects',case when coalesce(jsonb_typeof(v_db),'')='array' then v_db else '[]'::jsonb end,
        'mutation_artifacts',case when coalesce(jsonb_typeof(v_art),'')='array' then v_art else '[]'::jsonb end
      ),
      'required_contract',jsonb_build_object('satisfied_by','DETERMINISTIC_CONTRACT_REPAIR_V1')
    ),p_apply
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION programacion.fn_engineering_repair_block_mutation_target_assertion_v1(p_plan_code text, p_unit_code text, p_checkpoint_code text, p_contract jsonb, p_apply boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'programacion', 'public', 'pg_catalog'
AS $function$
declare
  v_db jsonb:=p_contract#>'{mutation_target,db_objects}';
  v_art jsonb:=p_contract#>'{mutation_target,artifacts}';
  v_test jsonb:=p_contract->'test_execution_contract';
begin
  if coalesce(jsonb_typeof(p_contract->'mutation_target'),'')<>'object'
     or not (
       programacion.fn_engineering_jsonb_nonempty_array_v1(v_db)
       or programacion.fn_engineering_jsonb_nonempty_array_v1(v_art)
     )
     or coalesce(jsonb_typeof(p_contract->'rollback_contract'),'')<>'object'
     or not programacion.fn_engineering_assertion_input_valid_v1(p_contract->'assertion_contract')
     or coalesce(jsonb_typeof(v_test),'')<>'object'
     or coalesce(v_test->>'mode','') not in ('AUTHORED_NEGATIVE','EXPLICIT_VERIFICATION_QUERY')
     or nullif(btrim(coalesce(v_test->>'test_code','')),'') is null then
    return jsonb_build_object(
      'schema_version','ENGINEERING_FAMILY_REPAIR_V1','status','INPUT_REQUIRED',
      'blocker','BLOCK_MUTATION_TARGET_ASSERTION_REQUIRED',
      'required',jsonb_build_array(
        'mutation_target.db_objects[] OR mutation_target.artifacts[]',
        'rollback_contract OBJECT',
        'assertion_contract.pass_when OBJECT',
        'test_execution_contract {mode,test_code}'
      )
    );
  end if;

  return programacion.fn_engineering_contract_repair_core_v1(
    p_plan_code,p_unit_code,p_checkpoint_code,
    'BLOCK_MUTATION_TARGET_ASSERTION_REQUIRED',
    jsonb_build_object(
      'assertion_contract',p_contract->'assertion_contract',
      'rollback_contract',p_contract->'rollback_contract',
      'test_execution_contract',v_test,
      'target',jsonb_build_object(
        'declared_objects',case when coalesce(jsonb_typeof(v_db),'')='array' then v_db else '[]'::jsonb end,
        'mutation_artifacts',case when coalesce(jsonb_typeof(v_art),'')='array' then v_art else '[]'::jsonb end
      ),
      'required_contract',jsonb_build_object('satisfied_by','DETERMINISTIC_CONTRACT_REPAIR_V1')
    ),p_apply
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION programacion.fn_engineering_repair_block_test_execution_contract_v1(p_plan_code text, p_unit_code text, p_checkpoint_code text, p_contract jsonb, p_apply boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'programacion', 'public', 'pg_catalog'
AS $function$
declare v_test jsonb:=p_contract->'test_execution_contract';
begin
  if coalesce(jsonb_typeof(v_test),'')<>'object'
     or coalesce(v_test->>'mode','') not in ('AUTHORED_NEGATIVE','EXPLICIT_VERIFICATION_QUERY')
     or nullif(btrim(coalesce(v_test->>'test_code','')),'') is null
     or not programacion.fn_engineering_assertion_input_valid_v1(p_contract->'assertion_contract') then
    return jsonb_build_object(
      'schema_version','ENGINEERING_FAMILY_REPAIR_V1','status','INPUT_REQUIRED',
      'blocker','BLOCK_TEST_EXECUTION_CONTRACT_MISSING',
      'required',jsonb_build_array('test_execution_contract {mode,test_code}','assertion_contract.pass_when OBJECT')
    );
  end if;

  return programacion.fn_engineering_contract_repair_core_v1(
    p_plan_code,p_unit_code,p_checkpoint_code,
    'BLOCK_TEST_EXECUTION_CONTRACT_MISSING',
    jsonb_build_object(
      'test_execution_contract',v_test,
      'assertion_contract',p_contract->'assertion_contract',
      'required_contract',jsonb_build_object('satisfied_by','DETERMINISTIC_CONTRACT_REPAIR_V1')
    ),p_apply
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION programacion.fn_engineering_repair_block_authored_test_drill_v1(p_plan_code text, p_unit_code text, p_checkpoint_code text, p_contract jsonb, p_apply boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'programacion', 'public', 'pg_catalog'
AS $function$
declare v_drill jsonb:=p_contract->'test_or_drill_contract';
begin
  if coalesce(jsonb_typeof(v_drill),'')<>'object'
     or coalesce(v_drill->>'mode','') not in ('AUTHORED_NEGATIVE','EXPLICIT_VERIFICATION_QUERY')
     or nullif(btrim(coalesce(v_drill->>'test_code','')),'') is null
     or coalesce(jsonb_typeof(v_drill->'bounded_execution'),'')<>'object'
     or not programacion.fn_engineering_assertion_input_valid_v1(p_contract->'assertion_contract') then
    return jsonb_build_object(
      'schema_version','ENGINEERING_FAMILY_REPAIR_V1','status','INPUT_REQUIRED',
      'blocker','BLOCK_AUTHORED_TEST_DRILL_CONTRACT_REQUIRED',
      'required',jsonb_build_array(
        'test_or_drill_contract {mode,test_code,bounded_execution}',
        'assertion_contract.pass_when OBJECT'
      )
    );
  end if;

  return programacion.fn_engineering_contract_repair_core_v1(
    p_plan_code,p_unit_code,p_checkpoint_code,
    'BLOCK_AUTHORED_TEST_DRILL_CONTRACT_REQUIRED',
    jsonb_build_object(
      'test_or_drill_contract',v_drill,
      'test_execution_contract',v_drill,
      'assertion_contract',p_contract->'assertion_contract',
      'required_contract',jsonb_build_object('satisfied_by','DETERMINISTIC_CONTRACT_REPAIR_V1')
    ),p_apply
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION programacion.fn_engineering_contract_repair_payload_v1(p_plan_code text, p_unit_code text, p_checkpoint_code text, p_blocker text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'programacion', 'public', 'pg_catalog'
AS $function$
declare
  v_meta jsonb;
  v_spec jsonb;
  v_registered jsonb;
  v_derived jsonb := '{}'::jsonb;
begin
  select pu.unit_metadata
    into v_meta
  from programacion.engineering_plan_units pu
  where pu.plan_code=p_plan_code
    and pu.unit_code=p_unit_code;

  if not found then
    return null;
  end if;

  v_spec:=v_meta#>array['action_specs_v1',p_checkpoint_code];
  v_registered:=v_meta#>array[
    'contract_repair_inputs_v1',
    p_checkpoint_code,
    p_blocker
  ];

  if v_spec is null then
    return v_registered;
  end if;

  case p_blocker
    when 'BLOCK_VERIFICATION_ASSERTION_REQUIRED' then
      if jsonb_typeof(v_spec->'assertion_contract')='object' then
        v_derived:=jsonb_build_object(
          'assertion_contract',v_spec->'assertion_contract'
        );
      end if;

    when 'BLOCK_TERMINAL_ACCEPTANCE_CONTRACT_REQUIRED' then
      v_derived:=jsonb_strip_nulls(jsonb_build_object(
        'terminal_readback',case when jsonb_typeof(v_spec->'terminal_readback')='object'
          then v_spec->'terminal_readback' else null end,
        'assertion_contract',case when jsonb_typeof(v_spec->'assertion_contract')='object'
          then v_spec->'assertion_contract' else null end
      ));

    when 'BLOCK_DECISION_AUTHORITY_CONTRACT_REQUIRED' then
      v_derived:=jsonb_strip_nulls(jsonb_build_object(
        'authority_ref',nullif(btrim(coalesce(v_spec->>'authority_ref','')),''),
        'decision_record_contract',case when jsonb_typeof(v_spec->'decision_record_contract')='object'
          then v_spec->'decision_record_contract' else null end,
        'assertion_contract',case when jsonb_typeof(v_spec->'assertion_contract')='object'
          then v_spec->'assertion_contract' else null end
      ));

    when 'BLOCK_MATERIALIZATION_CONTRACT_REQUIRED' then
      v_derived:=jsonb_strip_nulls(jsonb_build_object(
        'implementation_ref',nullif(btrim(coalesce(v_spec->>'implementation_ref','')),''),
        'mutation_target',jsonb_build_object(
          'db_objects',coalesce(v_spec#>'{target,declared_objects}','[]'::jsonb),
          'artifacts',coalesce(v_spec#>'{target,mutation_artifacts}','[]'::jsonb)
        ),
        'materialization_contract',case when jsonb_typeof(v_spec->'materialization_contract')='object'
          then v_spec->'materialization_contract' else null end,
        'assertion_contract',case when jsonb_typeof(v_spec->'assertion_contract')='object'
          then v_spec->'assertion_contract' else null end
      ));

    when 'BLOCK_MUTATION_TARGET_ASSERTION_REQUIRED' then
      v_derived:=jsonb_strip_nulls(jsonb_build_object(
        'mutation_target',jsonb_build_object(
          'db_objects',coalesce(v_spec#>'{target,declared_objects}','[]'::jsonb),
          'artifacts',coalesce(v_spec#>'{target,mutation_artifacts}','[]'::jsonb)
        ),
        'rollback_contract',case when jsonb_typeof(v_spec->'rollback_contract')='object'
          then v_spec->'rollback_contract' else null end,
        'test_execution_contract',case when jsonb_typeof(v_spec->'test_execution_contract')='object'
          then v_spec->'test_execution_contract' else null end,
        'assertion_contract',case when jsonb_typeof(v_spec->'assertion_contract')='object'
          then v_spec->'assertion_contract' else null end
      ));

    when 'BLOCK_TEST_EXECUTION_CONTRACT_MISSING' then
      v_derived:=jsonb_strip_nulls(jsonb_build_object(
        'test_execution_contract',case when jsonb_typeof(v_spec->'test_execution_contract')='object'
          then v_spec->'test_execution_contract' else null end,
        'assertion_contract',case when jsonb_typeof(v_spec->'assertion_contract')='object'
          then v_spec->'assertion_contract' else null end
      ));

    when 'BLOCK_AUTHORED_TEST_DRILL_CONTRACT_REQUIRED' then
      v_derived:=jsonb_strip_nulls(jsonb_build_object(
        'test_or_drill_contract',case
          when jsonb_typeof(v_spec->'test_or_drill_contract')='object'
            then v_spec->'test_or_drill_contract'
          when jsonb_typeof(v_spec->'test_execution_contract')='object'
            then v_spec->'test_execution_contract'
          else null
        end,
        'assertion_contract',case when jsonb_typeof(v_spec->'assertion_contract')='object'
          then v_spec->'assertion_contract' else null end
      ));
    else
      return v_registered;
  end case;

  return coalesce(v_derived,'{}'::jsonb) || coalesce(v_registered,'{}'::jsonb);
end;
$function$
;

CREATE OR REPLACE FUNCTION programacion.fn_engineering_contract_repair_dispatch_v1(p_plan_code text, p_unit_code text, p_checkpoint_code text, p_apply boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'programacion', 'public', 'pg_catalog'
AS $function$
declare
  v_spec jsonb;
  v_blocker text;
  v_payload jsonb;
begin
  v_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(
    p_plan_code,p_unit_code,p_checkpoint_code
  );

  if v_spec is null then
    return jsonb_build_object(
      'schema_version','ENGINEERING_CONTRACT_REPAIR_DISPATCH_V1',
      'status','NOT_FOUND',
      'plan_code',p_plan_code,
      'unit_code',p_unit_code,
      'checkpoint_code',p_checkpoint_code
    );
  end if;

  v_blocker:=coalesce(v_spec->>'status','');

  if v_blocker='READY' then
    return jsonb_build_object(
      'schema_version','ENGINEERING_CONTRACT_REPAIR_DISPATCH_V1',
      'status','ALREADY_READY',
      'plan_code',p_plan_code,
      'unit_code',p_unit_code,
      'checkpoint_code',p_checkpoint_code
    );
  end if;

  if v_blocker not in (
    'BLOCK_VERIFICATION_ASSERTION_REQUIRED',
    'BLOCK_TERMINAL_ACCEPTANCE_CONTRACT_REQUIRED',
    'BLOCK_DECISION_AUTHORITY_CONTRACT_REQUIRED',
    'BLOCK_MATERIALIZATION_CONTRACT_REQUIRED',
    'BLOCK_MUTATION_TARGET_ASSERTION_REQUIRED',
    'BLOCK_TEST_EXECUTION_CONTRACT_MISSING',
    'BLOCK_AUTHORED_TEST_DRILL_CONTRACT_REQUIRED'
  ) then
    return jsonb_build_object(
      'schema_version','ENGINEERING_CONTRACT_REPAIR_DISPATCH_V1',
      'status','NOT_SUPPORTED',
      'blocker',v_blocker,
      'plan_code',p_plan_code,
      'unit_code',p_unit_code,
      'checkpoint_code',p_checkpoint_code
    );
  end if;

  v_payload:=programacion.fn_engineering_contract_repair_payload_v1(
    p_plan_code,p_unit_code,p_checkpoint_code,v_blocker
  );

  if v_payload is null or v_payload='{}'::jsonb then
    return jsonb_build_object(
      'schema_version','ENGINEERING_CONTRACT_REPAIR_DISPATCH_V1',
      'status','INPUT_REQUIRED',
      'blocker',v_blocker,
      'plan_code',p_plan_code,
      'unit_code',p_unit_code,
      'checkpoint_code',p_checkpoint_code,
      'input_source','unit_metadata.contract_repair_inputs_v1 OR explicit action_spec'
    );
  end if;

  case v_blocker
    when 'BLOCK_VERIFICATION_ASSERTION_REQUIRED' then
      return programacion.fn_engineering_repair_block_verification_assertion_v1(
        p_plan_code,p_unit_code,p_checkpoint_code,v_payload,p_apply
      );
    when 'BLOCK_TERMINAL_ACCEPTANCE_CONTRACT_REQUIRED' then
      return programacion.fn_engineering_repair_block_terminal_acceptance_v1(
        p_plan_code,p_unit_code,p_checkpoint_code,v_payload,p_apply
      );
    when 'BLOCK_DECISION_AUTHORITY_CONTRACT_REQUIRED' then
      return programacion.fn_engineering_repair_block_decision_authority_v1(
        p_plan_code,p_unit_code,p_checkpoint_code,v_payload,p_apply
      );
    when 'BLOCK_MATERIALIZATION_CONTRACT_REQUIRED' then
      return programacion.fn_engineering_repair_block_materialization_contract_v1(
        p_plan_code,p_unit_code,p_checkpoint_code,v_payload,p_apply
      );
    when 'BLOCK_MUTATION_TARGET_ASSERTION_REQUIRED' then
      return programacion.fn_engineering_repair_block_mutation_target_assertion_v1(
        p_plan_code,p_unit_code,p_checkpoint_code,v_payload,p_apply
      );
    when 'BLOCK_TEST_EXECUTION_CONTRACT_MISSING' then
      return programacion.fn_engineering_repair_block_test_execution_contract_v1(
        p_plan_code,p_unit_code,p_checkpoint_code,v_payload,p_apply
      );
    when 'BLOCK_AUTHORED_TEST_DRILL_CONTRACT_REQUIRED' then
      return programacion.fn_engineering_repair_block_authored_test_drill_v1(
        p_plan_code,p_unit_code,p_checkpoint_code,v_payload,p_apply
      );
  end case;

  return jsonb_build_object(
    'schema_version','ENGINEERING_CONTRACT_REPAIR_DISPATCH_V1',
    'status','NOT_SUPPORTED',
    'blocker',v_blocker
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION programacion.fn_engineering_unit_contract_repair_prepass_v1(p_plan_code text, p_unit_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'programacion', 'public', 'pg_catalog'
AS $function$
declare
  r record;
  v_result jsonb;
  v_results jsonb:='[]'::jsonb;
  v_attempted int:=0;
  v_repaired int:=0;
  v_input_required int:=0;
  v_rejected int:=0;
begin
  for r in
    select c.checkpoint_code,c.sequence_no
    from programacion.engineering_plan_units pu
    join programacion.engineering_work_checkpoints c
      on c.work_item_id=pu.work_item_id
    where pu.plan_code=p_plan_code
      and pu.unit_code=p_unit_code
      and c.status in ('PENDING','IN_PROGRESS')
    order by c.sequence_no,c.checkpoint_code
  loop
    if coalesce(
      programacion.fn_engineering_checkpoint_action_spec_v3(
        p_plan_code,p_unit_code,r.checkpoint_code
      )->>'status',''
    ) not in (
      'BLOCK_VERIFICATION_ASSERTION_REQUIRED',
      'BLOCK_TERMINAL_ACCEPTANCE_CONTRACT_REQUIRED',
      'BLOCK_DECISION_AUTHORITY_CONTRACT_REQUIRED',
      'BLOCK_MATERIALIZATION_CONTRACT_REQUIRED',
      'BLOCK_MUTATION_TARGET_ASSERTION_REQUIRED',
      'BLOCK_TEST_EXECUTION_CONTRACT_MISSING',
      'BLOCK_AUTHORED_TEST_DRILL_CONTRACT_REQUIRED'
    ) then
      continue;
    end if;

    v_attempted:=v_attempted+1;
    v_result:=programacion.fn_engineering_contract_repair_dispatch_v1(
      p_plan_code,p_unit_code,r.checkpoint_code,true
    );

    if v_result->>'status'='REPAIRED' then
      v_repaired:=v_repaired+1;
    elsif v_result->>'status'='INPUT_REQUIRED' then
      v_input_required:=v_input_required+1;
    elsif v_result->>'status'='PATCH_REJECTED' then
      v_rejected:=v_rejected+1;
    end if;

    v_results:=v_results||jsonb_build_array(
      jsonb_build_object(
        'checkpoint_code',r.checkpoint_code,
        'result',v_result
      )
    );
  end loop;

  return jsonb_build_object(
    'schema_version','ENGINEERING_UNIT_CONTRACT_REPAIR_PREPASS_V1',
    'plan_code',p_plan_code,
    'unit_code',p_unit_code,
    'attempted',v_attempted,
    'repaired',v_repaired,
    'input_required',v_input_required,
    'rejected',v_rejected,
    'results',v_results
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION programacion.fn_engineering_plan_contract_repair_prepass_v1(p_plan_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'programacion', 'public', 'pg_catalog'
AS $function$
declare
  r record;
  v_result jsonb;
  v_results jsonb:='[]'::jsonb;
  v_units int:=0;
  v_attempted int:=0;
  v_repaired int:=0;
  v_input_required int:=0;
  v_rejected int:=0;
begin
  for r in
    select pu.unit_code
    from programacion.engineering_plan_units pu
    join programacion.engineering_work_items w on w.id=pu.work_item_id
    where pu.plan_code=p_plan_code
      and pu.disposition='ASSIGNED'
      and w.status in ('BACKLOG','READY','IN_PROGRESS')
    order by pu.id
  loop
    v_result:=programacion.fn_engineering_unit_contract_repair_prepass_v1(
      p_plan_code,r.unit_code
    );

    if coalesce((v_result->>'attempted')::int,0)>0 then
      v_units:=v_units+1;
      v_attempted:=v_attempted+coalesce((v_result->>'attempted')::int,0);
      v_repaired:=v_repaired+coalesce((v_result->>'repaired')::int,0);
      v_input_required:=v_input_required+coalesce((v_result->>'input_required')::int,0);
      v_rejected:=v_rejected+coalesce((v_result->>'rejected')::int,0);
      v_results:=v_results||jsonb_build_array(v_result);
    end if;
  end loop;

  return jsonb_build_object(
    'schema_version','ENGINEERING_PLAN_CONTRACT_REPAIR_PREPASS_V1',
    'plan_code',p_plan_code,
    'units_with_supported_blockers',v_units,
    'attempted',v_attempted,
    'repaired',v_repaired,
    'input_required',v_input_required,
    'rejected',v_rejected,
    'results',v_results
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION programacion.fn_engineering_unit_bootstrap_with_contract_repair_v1(p_plan_code text, p_unit_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'programacion', 'public', 'pg_catalog'
AS $function$
declare
  v_bootstrap jsonb;
  v_checkpoint_code text;
  v_status text;
  v_repair jsonb;
begin
  v_bootstrap:=programacion.fn_engineering_unit_bootstrap_v3(
    p_plan_code,p_unit_code
  );

  v_checkpoint_code:=nullif(
    btrim(coalesce(v_bootstrap#>>'{current_checkpoint,checkpoint_code}','')),
    ''
  );

  if v_checkpoint_code is null then
    return v_bootstrap || jsonb_build_object(
      'contract_repair_auto',jsonb_build_object(
        'schema_version','ENGINEERING_CONTRACT_REPAIR_AUTO_V1',
        'status','NOT_APPLICABLE',
        'reason','NO_CURRENT_CHECKPOINT'
      )
    );
  end if;

  v_status:=coalesce(
    programacion.fn_engineering_checkpoint_action_spec_v3(
      p_plan_code,p_unit_code,v_checkpoint_code
    )->>'status',''
  );

  if v_status not in (
    'BLOCK_VERIFICATION_ASSERTION_REQUIRED',
    'BLOCK_TERMINAL_ACCEPTANCE_CONTRACT_REQUIRED',
    'BLOCK_DECISION_AUTHORITY_CONTRACT_REQUIRED',
    'BLOCK_MATERIALIZATION_CONTRACT_REQUIRED',
    'BLOCK_MUTATION_TARGET_ASSERTION_REQUIRED',
    'BLOCK_TEST_EXECUTION_CONTRACT_MISSING',
    'BLOCK_AUTHORED_TEST_DRILL_CONTRACT_REQUIRED'
  ) then
    return v_bootstrap || jsonb_build_object(
      'contract_repair_auto',jsonb_build_object(
        'schema_version','ENGINEERING_CONTRACT_REPAIR_AUTO_V1',
        'status','NOT_APPLICABLE',
        'checkpoint_code',v_checkpoint_code,
        'action_spec_status',v_status
      )
    );
  end if;

  v_repair:=programacion.fn_engineering_contract_repair_dispatch_v1(
    p_plan_code,p_unit_code,v_checkpoint_code,true
  );

  if v_repair->>'status'='REPAIRED' then
    v_bootstrap:=programacion.fn_engineering_unit_bootstrap_v3(
      p_plan_code,p_unit_code
    );
  end if;

  return v_bootstrap || jsonb_build_object(
    'contract_repair_auto',
    jsonb_build_object(
      'schema_version','ENGINEERING_CONTRACT_REPAIR_AUTO_V1',
      'checkpoint_code',v_checkpoint_code,
      'detected_blocker',v_status,
      'result',v_repair,
      'rebootstrap_after_repair',(v_repair->>'status'='REPAIRED')
    )
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION programacion.fn_engineering_parallel_pilot_pick_unit_v1(p_plan_code text, p_run_id bigint)
 RETURNS text
 LANGUAGE plpgsql
 SET search_path TO 'programacion', 'public', 'pg_catalog'
AS $function$
declare
  r record;
  v_admission jsonb;
  v_repair jsonb;
begin
  update programacion.engineering_parallel_pilot_lane_runs
     set status='ERROR',
         finished_at=coalesce(finished_at,now()),
         result_summary=coalesce(result_summary,'LEASE_EXPIRED')
   where status='RUNNING'
     and lease_expires_at < now();

  for r in
    select pu.unit_code
    from programacion.engineering_plan_units pu
    join programacion.engineering_work_items w
      on w.id=pu.work_item_id
    where pu.plan_code=p_plan_code
      and pu.disposition='ASSIGNED'
      and w.status in ('BACKLOG','READY','IN_PROGRESS')
      and programacion.fn_engineering_effective_open_blocker_count_v1(w.id)=0
      and not exists (
        select 1
        from programacion.fn_engineering_effective_dependencies_v1(w.id) d
        where d.is_unmet
      )
      and not exists (
        select 1
        from programacion.engineering_parallel_pilot_lane_runs lr
        where lr.plan_code=p_plan_code
          and lr.unit_code=pu.unit_code
          and lr.status='RUNNING'
      )
      and not exists (
        select 1
        from programacion.engineering_parallel_pilot_lane_runs lr
        where lr.run_id=p_run_id
          and lr.unit_code=pu.unit_code
      )
    order by
      case w.priority
        when 'P0' then 0
        when 'P1' then 1
        when 'P2' then 2
        when 'P3' then 3
        else 9
      end,
      pu.id
  loop
    v_repair:=programacion.fn_engineering_unit_contract_repair_prepass_v1(
      p_plan_code,r.unit_code
    );

    v_admission:=programacion.fn_engineering_unit_scheduler_admission_v2(
      p_plan_code,r.unit_code
    );

    if coalesce((v_admission->>'claimable')::boolean,false)
       and v_admission->>'lane_mode'='EXECUTION_READY' then
      return r.unit_code;
    end if;
  end loop;

  return null;
end;
$function$
;

CREATE OR REPLACE FUNCTION programacion.fn_engineering_parallel_executor_start_v1(p_plan_code text, p_actor text DEFAULT 'ENGINEERING_PARALLEL_EXECUTOR_V1'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'programacion', 'public', 'pg_catalog'
AS $function$
declare
  v_storage jsonb;
  v_repair jsonb;
  v_reduction jsonb;
begin
  v_repair:=programacion.fn_engineering_plan_contract_repair_prepass_v1(
    p_plan_code
  );

  v_reduction:=programacion.fn_engineering_plan_contract_reduction_v1(
    p_plan_code
  );

  v_storage := programacion.fn_engineering_parallel_scheduler_storage_start_v1(
    p_plan_code,
    coalesce(nullif(p_actor,''),'ENGINEERING_PARALLEL_EXECUTOR_V1')
  );

  return v_storage
    || jsonb_build_object(
      'executor_contract','ENGINEERING_PARALLEL_EXECUTOR_V1',
      'execution_scope','UNIT_TO_TERMINAL',
      'selection_policy','DEPENDENCIES_CLEAR_AND_EXECUTION_READY_ONLY',
      'contract_preflight','AUTO_REPAIR_THEN_PLAN_REDUCTION_THEN_CANONICAL_EXECUTION_ADMISSION',
      'contract_repair_prepass',v_repair,
      'contract_reduction',v_reduction,
      'parallel_execution_contract',jsonb_build_object(
        'db_scheduler_role','CLAIM_REFILL_AND_STATE_ONLY',
        'lane_worker_model','EXTERNAL_CONCURRENT_WORKERS',
        'dispatch_entrypoint','programacion.fn_engineering_parallel_executor_dispatch_bundle_v1',
        'claim_before_worker','EXECUTION_READY_ADMISSION_REQUIRED',
        'execution_permission','CANONICAL_EXECUTION_ADMISSION_REQUIRED',
        'contract_repair_in_lane','FORBIDDEN',
        'contract_repair_before_claim','AUTOMATIC_SUPPORTED_FAMILIES',
        'repair_input_policy','EXACT_REGISTERED_OR_EXPLICIT_ONLY',
        'repair_inference','FORBIDDEN',
        'same_unit_double_claim','FORBIDDEN',
        'real_parallelism_condition','ACTIVE_LANES_MUST_BE_EXECUTED_CONCURRENTLY_BY_HOST'
      ),
      'unit_loop',jsonb_build_array(
        'PLAN_CONTRACT_REPAIR_PREPASS',
        'PLAN_CONTRACT_REDUCTION_READBACK',
        'UNIT_CONTRACT_REPAIR_BEFORE_CLAIM',
        'SCHEDULER_EXECUTION_READY_ADMISSION',
        'EXECUTE_CURRENT_PACKET',
        'HEARTBEAT_WHEN_REQUIRED',
        'CHECKPOINT_TRANSITION',
        'USE_RETURNED_BOOTSTRAP',
        'REPEAT_UNTIL_UNIT_TERMINAL_OR_YIELD'
      ),
      'success_guard','WORK_ITEM_DONE_AND_REQUIRED_CHECKPOINTS_TERMINAL',
      'legacy_scheduler_storage',true
    );
end;
$function$
;

CREATE OR REPLACE FUNCTION programacion.fn_engineering_parallel_executor_dispatch_bundle_v1(p_run_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'programacion', 'public', 'pg_catalog'
AS $function$
with r as (
  select id,plan_code,status,max_lanes,max_turns_per_lane
  from programacion.engineering_parallel_pilot_runs
  where id=p_run_id
), lanes as materialized (
  select
    lr.lane_no,
    lr.turn_no,
    lr.unit_code,
    lr.status,
    programacion.fn_engineering_unit_scheduler_admission_v2(
      lr.plan_code,lr.unit_code
    ) as scheduler_admission,
    programacion.fn_engineering_unit_bootstrap_with_contract_repair_v1(
      lr.plan_code,lr.unit_code
    ) as bootstrap
  from programacion.engineering_parallel_pilot_lane_runs lr
  join r on r.id=lr.run_id
  where lr.status='RUNNING'
  order by lr.lane_no,lr.turn_no
)
select jsonb_build_object(
  'schema_version','ENGINEERING_PARALLEL_DISPATCH_BUNDLE_V4',
  'run_id',r.id,
  'plan_code',r.plan_code,
  'run_status',r.status,
  'dispatch_policy','CONCURRENT_EXECUTION_READY_LANES',
  'worker_contract','ONE_WORKER_PER_EXECUTION_READY_LANE',
  'repair_before_worker','AUTOMATIC_SUPPORTED_FAMILIES',
  'lane_count',(select count(*) from lanes),
  'lanes',coalesce(
    (
      select jsonb_agg(
        jsonb_build_object(
          'lane_no',lane_no,
          'turn_no',turn_no,
          'unit_code',unit_code,
          'status',status,
          'lane_mode',scheduler_admission->>'lane_mode',
          'scheduler_admission',scheduler_admission,
          'worker_next_action',
            case
              when scheduler_admission->>'lane_mode'='EXECUTION_READY'
                then 'EXECUTE_CURRENT_PACKET'
              when scheduler_admission->>'lane_mode'='REDUCTION_REQUIRED'
                then 'YIELD_TO_PLAN_REDUCTION'
              else 'YIELD_CURRENT_UNIT'
            end,
          'bootstrap',bootstrap
        )
        order by lane_no,turn_no
      )
      from lanes
    ),
    '[]'::jsonb
  )
)
from r;
$function$
;

CREATE OR REPLACE FUNCTION programacion.fn_engineering_checkpoint_transition_v1(p_plan_code text, p_unit_code text, p_checkpoint_code text, p_new_status text, p_evidence_ref text, p_actor text, p_detail text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'programacion', 'public', 'pg_catalog'
AS $function$
declare
  v_work_item_id bigint;
  v_current_code text;
  v_existing_status text;
  v_remaining int;
  v_open_blockers int;
  v_unmet_deps int;
  v_result jsonb;
  v_progress text;
  v_next text;
begin
  if p_new_status not in ('DONE','NOT_APPLICABLE','IN_PROGRESS') then
    raise exception using message = (
      programacion.fn_engineering_error_contract_v1('CHECKPOINT_TRANSITION_STATUS_UNSUPPORTED')
      || jsonb_build_object('received',p_new_status)
    )::text;
  end if;

  select pu.work_item_id into v_work_item_id
  from programacion.engineering_plan_units pu
  where pu.plan_code=p_plan_code and pu.unit_code=p_unit_code;

  if v_work_item_id is null then
    raise exception 'Canonical unit not found: %/%',p_plan_code,p_unit_code;
  end if;

  select c.status into v_existing_status
  from programacion.engineering_work_checkpoints c
  where c.work_item_id=v_work_item_id and c.checkpoint_code=p_checkpoint_code;

  if v_existing_status in ('DONE','NOT_APPLICABLE') then
    return programacion.fn_engineering_unit_bootstrap_with_contract_repair_v1(
      p_plan_code,p_unit_code
    ) || jsonb_build_object(
      'transition',jsonb_build_object(
        'status','NOOP_ALREADY_TERMINAL',
        'checkpoint_code',p_checkpoint_code
      )
    );
  end if;

  select c.checkpoint_code into v_current_code
  from programacion.engineering_work_checkpoints c
  where c.work_item_id=v_work_item_id
    and c.status not in ('DONE','NOT_APPLICABLE')
  order by c.sequence_no
  limit 1;

  if v_current_code is distinct from p_checkpoint_code then
    raise exception 'Checkpoint % is not current; current=%',p_checkpoint_code,v_current_code;
  end if;

  if p_new_status in ('DONE','NOT_APPLICABLE')
     and coalesce(nullif(btrim(p_evidence_ref),''),nullif(btrim(p_detail),'')) is null then
    raise exception 'Terminal checkpoint transition requires evidence_ref or detail';
  end if;

  update programacion.engineering_work_checkpoints
     set status=p_new_status,
         evidence_ref=coalesce(nullif(p_evidence_ref,''),evidence_ref),
         completed_at=case when p_new_status='DONE' then now() else completed_at end,
         updated_at=now(),
         updated_by_execution_id=coalesce(
           nullif(p_actor,''),
           'ENGINEERING_CHECKPOINT_TRANSITION_V1'
         )
   where work_item_id=v_work_item_id
     and checkpoint_code=p_checkpoint_code;

  if p_new_status='IN_PROGRESS' then
    update programacion.engineering_work_items
       set status='IN_PROGRESS',
           started_at=coalesce(started_at,now()),
           updated_at=now()
     where id=v_work_item_id
       and status not in ('DONE','CANCELLED');
  else
    select count(*) into v_remaining
    from programacion.engineering_work_checkpoints c
    where c.work_item_id=v_work_item_id
      and c.required
      and c.status not in ('DONE','NOT_APPLICABLE');

    select programacion.fn_engineering_effective_open_blocker_count_v1(v_work_item_id)
      into v_open_blockers;

    select count(*) into v_unmet_deps
    from programacion.fn_engineering_effective_dependencies_v1(v_work_item_id) d
    where d.is_unmet;

    if v_remaining=0 and v_open_blockers=0 and v_unmet_deps=0 then
      update programacion.engineering_work_items
         set status='DONE',
             completed_at=coalesce(completed_at,now()),
             started_at=coalesce(started_at,now()),
             updated_at=now()
       where id=v_work_item_id
         and status<>'CANCELLED';
    else
      update programacion.engineering_work_items
         set status='IN_PROGRESS',
             started_at=coalesce(started_at,now()),
             completed_at=null,
             updated_at=now()
       where id=v_work_item_id
         and status not in ('DONE','CANCELLED');
    end if;
  end if;

  v_result:=programacion.fn_engineering_unit_bootstrap_with_contract_repair_v1(
    p_plan_code,p_unit_code
  );

  v_progress:=coalesce(v_result#>>'{state,progress_pct}','0');
  v_next:=coalesce(v_result#>>'{terminal_action}','UNKNOWN');

  insert into programacion.engineering_work_updates(
    work_item_id,update_type,summary,detail,next_action,evidence_refs,
    reported_by,observed_at,created_by_execution_id
  ) values (
    v_work_item_id,
    'PROGRESS',
    'Checkpoint '||p_checkpoint_code||' -> '||p_new_status||
      '; ledger_progress='||v_progress||'%',
    p_detail,
    v_next||coalesce(' / '||(v_result#>>'{current_checkpoint,checkpoint_code}'),''),
    case
      when nullif(p_evidence_ref,'') is null then '[]'::jsonb
      else jsonb_build_array(p_evidence_ref)
    end,
    coalesce(nullif(p_actor,''),'ENGINEERING_CHECKPOINT_TRANSITION_V1'),
    now(),
    coalesce(nullif(p_actor,''),'ENGINEERING_CHECKPOINT_TRANSITION_V1')
  );

  return v_result || jsonb_build_object(
    'transition',jsonb_build_object(
      'status','APPLIED',
      'checkpoint_code',p_checkpoint_code,
      'new_status',p_new_status,
      'ledger_progress_pct',v_progress,
      'next_terminal_action',v_next,
      'auto_contract_repair_evaluated',true
    )
  );
end;
$function$
;

revoke execute on function programacion.fn_engineering_jsonb_nonempty_array_v1(jsonb) from public, anon, authenticated;
revoke execute on function programacion.fn_engineering_assertion_input_valid_v1(jsonb) from public, anon, authenticated;
revoke execute on function programacion.fn_engineering_packet_apply_explicit_write_contract_v1(jsonb,jsonb) from public, anon, authenticated;
revoke execute on function programacion.fn_engineering_contract_repair_core_v1(text,text,text,text,jsonb,boolean) from public, anon, authenticated;
revoke execute on function programacion.fn_engineering_repair_block_verification_assertion_v1(text,text,text,jsonb,boolean) from public, anon, authenticated;
revoke execute on function programacion.fn_engineering_repair_block_terminal_acceptance_v1(text,text,text,jsonb,boolean) from public, anon, authenticated;
revoke execute on function programacion.fn_engineering_repair_block_decision_authority_v1(text,text,text,jsonb,boolean) from public, anon, authenticated;
revoke execute on function programacion.fn_engineering_repair_block_materialization_contract_v1(text,text,text,jsonb,boolean) from public, anon, authenticated;
revoke execute on function programacion.fn_engineering_repair_block_mutation_target_assertion_v1(text,text,text,jsonb,boolean) from public, anon, authenticated;
revoke execute on function programacion.fn_engineering_repair_block_test_execution_contract_v1(text,text,text,jsonb,boolean) from public, anon, authenticated;
revoke execute on function programacion.fn_engineering_repair_block_authored_test_drill_v1(text,text,text,jsonb,boolean) from public, anon, authenticated;
revoke execute on function programacion.fn_engineering_contract_repair_payload_v1(text,text,text,text) from public, anon, authenticated;
revoke execute on function programacion.fn_engineering_contract_repair_dispatch_v1(text,text,text,boolean) from public, anon, authenticated;
revoke execute on function programacion.fn_engineering_unit_contract_repair_prepass_v1(text,text) from public, anon, authenticated;
revoke execute on function programacion.fn_engineering_plan_contract_repair_prepass_v1(text) from public, anon, authenticated;
revoke execute on function programacion.fn_engineering_unit_bootstrap_with_contract_repair_v1(text,text) from public, anon, authenticated;

grant execute on function programacion.fn_engineering_parallel_executor_start_v1(text,text) to public;
grant execute on function programacion.fn_engineering_parallel_pilot_pick_unit_v1(text,bigint) to public;
grant execute on function programacion.fn_engineering_parallel_executor_dispatch_bundle_v1(bigint) to public;
grant execute on function programacion.fn_engineering_checkpoint_transition_v1(text,text,text,text,text,text,text) to public;

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
) values (
  'ENGINEERING-DETERMINISTIC-CONTRACT-REPAIR-AUTO-001',
  'ENGINEERING_ORCHESTRATION',
  'Supported contract blockers are repaired immediately when exact repair inputs exist',
  'Seven recurring contract blocker families now route through deterministic repair procedures. The executor runs a plan-wide repair prepass before lane selection, unit repair before each claim/refill, dispatch repair before worker execution, and transition-time repair before returning the next bootstrap. Missing semantic inputs remain INPUT_REQUIRED; inference and synthetic PASS are forbidden.',
  'The previous plan reduction prepass grouped supported blockers but never executed their repair procedures, so execution could stop with NO_ELIGIBLE_UNITS even when a deterministic repair path existed.',
  'BLOCKER_GROUPED_BUT_REPAIR_NOT_DISPATCHED',
  'Route only the seven declared blocker families through fn_engineering_contract_repair_dispatch_v1. Accept exact registered or explicit inputs only; compile, ACTION_EXACT and ERROR_CLOSED must pass before persisting.',
  'PASS when executor start exposes contract_repair_prepass; pick/refill invokes unit prepass; dispatch uses fn_engineering_unit_bootstrap_with_contract_repair_v1; checkpoint transition evaluates auto repair; unsupported or incomplete repair input remains fail-closed.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','ACTIVO',
  'supabase://programacion.fn_engineering_contract_repair_dispatch_v1; supabase://programacion.fn_engineering_parallel_executor_start_v1; supabase://programacion.fn_engineering_checkpoint_transition_v1',
  'EXECUTION',
  array['ENGINEERING_SCHEDULER','ENGINEERING_EXECUTOR','PROGRAMMING_AGENT']::text[],
  'R5_EROSION_PROCESO','LOUD_EARLY',
  'Deterministic contract repair auto-dispatch',
  'supabase://programacion.fn_engineering_contract_repair_dispatch_v1'
)
on conflict (codigo) do update set
  descripcion=excluded.descripcion,
  causa_raiz=excluded.causa_raiz,
  patron=excluded.patron,
  prevencion=excluded.prevencion,
  validacion=excluded.validacion,
  evidencia=excluded.evidencia,
  estado=excluded.estado,
  ultima_vez=now(),
  updated_at=now();
