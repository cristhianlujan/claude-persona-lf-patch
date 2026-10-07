-- ENGINEERING material assertion packet guard v1
-- Compile assertion binding into every material packet so executors know the
-- exact machine result they must record before CHECKPOINT_TRANSITION -> DONE.

create or replace function programacion.fn_engineering_packet_apply_assertion_guard_v1(
  p_packet jsonb,
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text,
  p_action_spec jsonb
)
returns jsonb
language plpgsql
stable
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_material boolean := coalesce((p_action_spec->>'requires_material_execution')::boolean,false);
  v_contract jsonb;
  v_plan jsonb := '[]'::jsonb;
  v_item jsonb;
  v_exec_contract jsonb;
  v_operation text;
  v_status text := coalesce(p_packet->>'status','');
begin
  if not v_material then
    return p_packet || jsonb_build_object(
      'assertion_gate',jsonb_build_object(
        'status','NOT_REQUIRED',
        'reason','NON_MATERIAL_CHECKPOINT'
      )
    );
  end if;

  v_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1(
    p_plan_code,p_unit_code,p_checkpoint_code,p_action_spec
  );

  if coalesce(v_contract->>'status','')<>'READY' then
    return p_packet
      || jsonb_build_object(
        'status',case
          when v_status='READY' then 'BLOCK_ASSERTION_CONTRACT_REQUIRED'
          else v_status
        end,
        'execution_allowed',false,
        'assertion_contract',v_contract,
        'assertion_gate',jsonb_build_object(
          'status','BLOCK',
          'reason',coalesce(v_contract->>'status','ASSERTION_CONTRACT_NOT_READY')
        ),
        'block_reasons',
          coalesce(p_packet->'block_reasons','[]'::jsonb)
          || jsonb_build_array('ASSERTION_CONTRACT_REQUIRED'),
        'connector_plan','[]'::jsonb
      );
  end if;

  if v_status<>'READY' then
    return p_packet || jsonb_build_object(
      'assertion_contract',v_contract,
      'assertion_gate',jsonb_build_object(
        'status','PASS',
        'execution_blocked_elsewhere',true
      )
    );
  end if;

  for v_item in
    select value
    from jsonb_array_elements(coalesce(p_packet->'connector_plan','[]'::jsonb))
  loop
    v_operation:=coalesce(v_item->>'operation','');

    if v_operation in ('RUN_TEST','WRITE_DB','WRITE_GIT') then
      v_exec_contract:=coalesce(v_item->'executor_contract','{}'::jsonb)
        || jsonb_build_object(
          'assertion_receipt_required',true,
          'assertion_contract',v_contract,
          'assertion_receipt_entrypoint',
            'programacion.fn_engineering_checkpoint_assertion_record_v1',
          'assertion_receipt_call_template',
            format(
              'select programacion.fn_engineering_checkpoint_assertion_record_v1(%L,%L,%L,<p_result_jsonb>,<p_actor>)',
              p_plan_code,p_unit_code,p_checkpoint_code
            ),
          'transition_requires_current_receipt',true,
          'synthetic_assertion_pass','FORBIDDEN'
        );

      v_item:=v_item || jsonb_build_object(
        'executor_contract',v_exec_contract
      );
    end if;

    v_plan:=v_plan||jsonb_build_array(v_item);
  end loop;

  return jsonb_set(
    p_packet || jsonb_build_object(
      'assertion_contract',v_contract,
      'assertion_gate',jsonb_build_object(
        'status','PASS',
        'receipt_required_before_done',true,
        'storage_boundary_guard',
          'programacion.fn_guard_engineering_material_checkpoint_done_v1'
      )
    ),
    '{connector_plan}',
    v_plan,
    true
  );
end;
$function$;

comment on function programacion.fn_engineering_packet_apply_assertion_guard_v1(jsonb,text,text,text,jsonb)
is 'Material packet guard: blocks unbound material results; otherwise injects the exact assertion contract and receipt recorder into material connector operations before DONE can persist.';

create or replace function programacion.fn_engineering_execution_packet_from_spec_v1(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text,
  p_action_spec jsonb,
  p_execution_input jsonb
)
returns jsonb
language plpgsql
stable
set search_path to 'programacion','public','pg_catalog'
as $function$
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
$function$;

comment on function programacion.fn_engineering_execution_packet_from_spec_v1(text,text,text,jsonb,jsonb)
is 'Canonical packet wrapper: artifact roles -> core -> transversal adapter -> strict test guard -> material assertion binding -> read budget -> governed merge.';

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
) values (
  'ENGINEERING-MATERIAL-DONE-ASSERTION-BINDING-001',
  'ENGINEERING_ORCHESTRATION',
  'Material checkpoint DONE requires a machine-verifiable assertion receipt',
  'The engineering transition boundary accepted DONE when evidence_ref/detail was merely non-empty. Action Spec, execution packet and typed material result were not consulted, so narrative evidence could theoretically close a material checkpoint without proving its declared result.',
  'Execution evidence and ledger transition were connected only by free-text evidence_ref, not by a digest-bound assertion contract and structured PASS receipt.',
  'MATERIAL_DONE_ACCEPTS_NARRATIVE_EVIDENCE_WITHOUT_MACHINE_RESULT_BINDING',
  'Derive assertion contracts from explicit pass_when, declared capability test result_contract, or the current released repository capability output+validator. Record a structured receipt on the canonical checkpoint row and enforce its current contract digest in a BEFORE UPDATE status=DONE guard.',
  'PASS when material packets expose ENGINEERING_ASSERTION_CONTRACT_V1 and assertion receipt entrypoint; material DONE without receipt is blocked; a matching structured PASS receipt enables DONE; non-material checkpoints remain unaffected; stale contract digests fail closed.',
  'CRITICAL',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','ACTIVO',
  'supabase://programacion.fn_engineering_action_spec_assertion_contract_v1; supabase://programacion.fn_engineering_checkpoint_assertion_record_v1; supabase://programacion.fn_guard_engineering_material_checkpoint_done_v1; supabase://programacion.fn_engineering_packet_apply_assertion_guard_v1',
  'EXECUTION',
  array['ENGINEERING_SCHEDULER','PROGRAMMING_AGENT']::text[],
  'R2_NO_VE','LOUD_EARLY',
  'Reparador V0.7 / Card V3 material assertion binding',
  'supabase://programacion.engineering_work_checkpoints'
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
