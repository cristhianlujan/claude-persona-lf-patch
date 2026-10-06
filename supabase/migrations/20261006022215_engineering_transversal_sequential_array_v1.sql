
create or replace function programacion.fn_engineering_transversal_sequence_state_v1(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text
)
returns jsonb
language sql
stable
as $$
with u as (
  select pu.work_item_id,
         pu.unit_metadata#>array['transversal_execution_v1',p_checkpoint_code] as tx
  from programacion.engineering_plan_units pu
  where pu.plan_code=p_plan_code
    and pu.unit_code=p_unit_code
),
c as (
  select u.*,
         coalesce(u.tx->'capabilities','[]'::jsonb) as capabilities,
         encode(extensions.digest(convert_to(coalesce(u.tx->'capabilities','[]'::jsonb)::text,'UTF8'),'sha256'),'hex') as sequence_digest
  from u
),
items as (
  select
    e.ordinality::int as index_1,
    e.value as item,
    case
      when jsonb_typeof(e.value)='string' then trim(both '"' from e.value::text)
      else e.value->>'capability_code'
    end as capability_code,
    case
      when jsonb_typeof(e.value)='object' then e.value->>'handler'
      when trim(both '"' from e.value::text)='CONTROL_EQUIVALENCE_JUDGE' then 'T_EQUIV_SHADOW'
      else null
    end as handler
  from c
  cross join lateral jsonb_array_elements(c.capabilities) with ordinality e(value,ordinality)
),
marked as (
  select
    i.*,
    exists(
      select 1
      from programacion.engineering_work_updates wu
      cross join c
      where wu.work_item_id=c.work_item_id
        and wu.reported_by='ENGINEERING_TRANSVERSAL_STEP_V1'
        and wu.summary=
          'TRANSVERSAL_STEP_DONE|'||p_checkpoint_code||'|'||c.sequence_digest||'|'||
          i.index_1::text||'|'||coalesce(i.capability_code,'')
    ) as done
  from items i
),
next_item as (
  select *
  from marked
  where not done
  order by index_1
  limit 1
)
select jsonb_build_object(
  'schema_version','ENGINEERING_TRANSVERSAL_SEQUENCE_STATE_V1',
  'plan_code',p_plan_code,
  'unit_code',p_unit_code,
  'checkpoint_code',p_checkpoint_code,
  'mode',coalesce((select tx->>'mode' from c),''),
  'sequence_digest',coalesce((select sequence_digest from c),''),
  'total',coalesce((select jsonb_array_length(capabilities) from c),0),
  'completed',coalesce((select count(*) from marked where done),0),
  'all_done',coalesce((select bool_and(done) from marked),false) and coalesce((select count(*) from marked),0)>0,
  'next_index',coalesce((select index_1 from next_item),0),
  'current_item',(select item from next_item),
  'current_capability_code',(select capability_code from next_item),
  'current_handler',(select handler from next_item),
  'is_last',coalesce(
    (select index_1=(select count(*) from marked) from next_item),
    false
  )
);
$$;

create or replace function programacion.fn_engineering_transversal_step_transition_v1(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text,
  p_sequence_digest text,
  p_capability_index integer,
  p_capability_code text,
  p_evidence_ref text,
  p_actor text,
  p_detail text default null
)
returns jsonb
language plpgsql
as $$
declare
  v_state jsonb;
  v_work_item_id bigint;
  v_summary text;
begin
  v_state:=programacion.fn_engineering_transversal_sequence_state_v1(
    p_plan_code,p_unit_code,p_checkpoint_code
  );

  if coalesce(v_state->>'sequence_digest','')<>coalesce(p_sequence_digest,'') then
    raise exception 'TRANSVERSAL_SEQUENCE_DIGEST_MISMATCH';
  end if;
  if coalesce((v_state->>'next_index')::int,0)<>p_capability_index then
    raise exception 'TRANSVERSAL_SEQUENCE_INDEX_MISMATCH:expected=% got=%',
      v_state->>'next_index',p_capability_index;
  end if;
  if coalesce(v_state->>'current_capability_code','')<>coalesce(p_capability_code,'') then
    raise exception 'TRANSVERSAL_SEQUENCE_CAPABILITY_MISMATCH:expected=% got=%',
      v_state->>'current_capability_code',p_capability_code;
  end if;
  if coalesce((v_state->>'is_last')::boolean,false) then
    raise exception 'TRANSVERSAL_SEQUENCE_LAST_STEP_MUST_USE_CHECKPOINT_TRANSITION';
  end if;
  if coalesce(nullif(btrim(p_evidence_ref),''),nullif(btrim(p_detail),'')) is null then
    raise exception 'TRANSVERSAL_STEP_EVIDENCE_REQUIRED';
  end if;

  select pu.work_item_id into v_work_item_id
  from programacion.engineering_plan_units pu
  where pu.plan_code=p_plan_code and pu.unit_code=p_unit_code;

  if v_work_item_id is null then
    raise exception 'TRANSVERSAL_SEQUENCE_UNIT_NOT_FOUND';
  end if;

  v_summary:=
    'TRANSVERSAL_STEP_DONE|'||p_checkpoint_code||'|'||p_sequence_digest||'|'||
    p_capability_index::text||'|'||p_capability_code;

  if not exists(
    select 1
    from programacion.engineering_work_updates
    where work_item_id=v_work_item_id
      and reported_by='ENGINEERING_TRANSVERSAL_STEP_V1'
      and summary=v_summary
  ) then
    insert into programacion.engineering_work_updates(
      work_item_id,update_type,summary,detail,next_action,evidence_refs,
      reported_by,observed_at,created_by_execution_id
    ) values (
      v_work_item_id,
      'PROGRESS',
      v_summary,
      p_detail,
      'CONTINUE_CURRENT_CHECKPOINT_TRANSVERSAL_SEQUENCE',
      case when nullif(btrim(coalesce(p_evidence_ref,'')),'') is null
        then '[]'::jsonb else jsonb_build_array(p_evidence_ref) end,
      'ENGINEERING_TRANSVERSAL_STEP_V1',
      now(),
      coalesce(nullif(btrim(p_actor),''),'ENGINEERING_TRANSVERSAL_STEP_V1')
    );
  end if;

  return programacion.fn_engineering_unit_bootstrap_v3(p_plan_code,p_unit_code)
    || jsonb_build_object(
      'transversal_step_transition',
      jsonb_build_object(
        'status','APPLIED',
        'checkpoint_code',p_checkpoint_code,
        'sequence_digest',p_sequence_digest,
        'capability_index',p_capability_index,
        'capability_code',p_capability_code,
        'next_sequence_state',
          programacion.fn_engineering_transversal_sequence_state_v1(
            p_plan_code,p_unit_code,p_checkpoint_code
          )
      )
    );
end;
$$;

create or replace function programacion.fn_engineering_transversal_capability_action_spec_v1(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text,
  p_item jsonb
)
returns jsonb
language plpgsql
stable
as $$
declare
  v_base jsonb;
  v_code text;
  v_handler text;
  v_plan_digest text;
begin
  v_base:=programacion.fn_engineering_checkpoint_action_spec_v3_legacy(
    p_plan_code,p_unit_code,p_checkpoint_code
  );

  v_code:=case
    when jsonb_typeof(p_item)='string' then trim(both '"' from p_item::text)
    else nullif(btrim(coalesce(p_item->>'capability_code','')),'')
  end;

  v_handler:=case
    when jsonb_typeof(p_item)='object' then nullif(btrim(coalesce(p_item->>'handler','')),'')
    when v_code='CONTROL_EQUIVALENCE_JUDGE' then 'T_EQUIV_SHADOW'
    else null
  end;

  if v_code is null then
    return v_base || jsonb_build_object(
      'status','BLOCK_TRANSVERSAL_CAPABILITY_CODE_MISSING',
      'precision','STRUCTURAL_TRANSVERSAL_SEQUENCE'
    );
  end if;

  if v_handler='CAPABILITY_CURRENT_READBACK' then
    return v_base || jsonb_build_object(
      'status','READY',
      'precision','STRUCTURAL_TRANSVERSAL_SEQUENCE',
      'action_kind','READBACK_ONCE',
      'recipe_mode','READBACK_EXACT',
      'requires_material_execution',false,
      'mutation_policy','NO_DOMAIN_MUTATION',
      'transversal_capability_code',v_code,
      'target',jsonb_build_object(
        'checkpoint',p_checkpoint_code,
        'declared_objects',jsonb_build_array(
          'public.lf_capability_registry',
          'public.lf_capability_current',
          'public.lf_capability_version_registry'
        ),
        'declared_assets','[]'::jsonb,
        'declared_artifacts','[]'::jsonb,
        'declared_events','[]'::jsonb
      ),
      'verification_queries',jsonb_build_array(
        format(
          'select r.capability_code,r.status,c.version,v.release_state,v.manifest_sha256 from public.lf_capability_registry r join public.lf_capability_current c using(capability_code) join public.lf_capability_version_registry v on v.capability_code=c.capability_code and v.version=c.version where r.capability_code=%L and r.status=''ACTIVE'' and v.release_state=''RELEASED''',
          v_code
        )
      ),
      'expected','Capability must be ACTIVE with CURRENT RELEASED exact version before next transversal step',
      'action_steps',jsonb_build_array(
        'READ_CURRENT_CAPABILITY_AUTHORITY',
        'ASSERT_ACTIVE_CURRENT_RELEASED',
        'PERSIST_TRANSVERSAL_STEP_DONE',
        'USE_RETURNED_BOOTSTRAP'
      )
    );
  end if;

  if v_handler='T_EQUIV_SHADOW' and v_code='CONTROL_EQUIVALENCE_JUDGE' then
    v_plan_digest := encode(
      extensions.digest(
        convert_to(
          p_plan_code||':'||p_unit_code||'|CONTROL_EQUIVALENCE_JUDGE|EXACT_ONLY',
          'UTF8'
        ),
        'sha256'
      ),
      'hex'
    );

    return v_base || jsonb_build_object(
      'status','READY',
      'schema_version','ENGINEERING_ACTION_SPEC_V3',
      'precision','STRUCTURAL_TRANSVERSAL_SEQUENCE',
      'action_kind','DECLARED_CAPABILITY_TEST_EXECUTION',
      'recipe_mode','EXECUTE_DECLARED_CAPABILITY_TEST',
      'requires_material_execution',true,
      'mutation_policy','TEST_EVIDENCE_ONLY',
      'transversal_capability_code',v_code,
      'target',
        coalesce(v_base->'target','{}'::jsonb)
        || jsonb_build_object(
          'declared_objects',
          coalesce(v_base#>'{target,declared_objects}','[]'::jsonb)
          || jsonb_build_array(
            'programacion.fn_input_governance_shadow_evaluate_v2',
            'programacion.fn_input_governance_shadow_sweep_v2',
            'public.lf_capability_current',
            'public.lf_capability_binding',
            'public.lf_operation_execution',
            'public.lf_test_suite_cases',
            'public.lf_test_suite_runs',
            'public.lf_test_runs',
            'public.lf_test_assertion_results'
          )
        ),
      'capability_execution',jsonb_build_object(
        'contract','DECLARED_CAPABILITY_SHADOW_V1',
        'capability_code','CONTROL_EQUIVALENCE_JUDGE',
        'version_policy','CURRENT_EXACT_MANIFEST',
        'policy_mode','EXACT_ONLY_ALL_DIVERGENCE_BLOCKS',
        'currentness_source','public.lf_capability_current',
        'orchestrator_operation_code','ORQUESTACION_PIPELINE_LF',
        'consumer_operation_code','GITHUB_CONTRACT_GATE_LF',
        'target_type','ENGINEERING_PLAN_UNIT_BINDING_PROOF',
        'target_code',p_plan_code||':'||p_unit_code,
        'plan_digest',v_plan_digest,
        'binding_recipe_entrypoint','programacion.fn_engineering_capability_bind_receipt_v1',
        'run_test_persistence_entrypoint','programacion.fn_engineering_run_test_persist_v1',
        'result_contract',jsonb_build_object(
          'suite_code','INPUT_GOVERNANCE_REGRESSION',
          'test_code','M3_9_SHADOW_T_EQUIV_CORPUS',
          'pass_when',jsonb_build_object(
            'shadow_contract','M3_9_T_EQUIV_CORPUS_V1',
            'screen_count',3,
            'fresh_t_equiv_binding_receipt',true,
            'domain_mutation',false,
            'diff_adjudication','NEXT_CHECKPOINT'
          )
        ),
        'orchestrator_reserve_entrypoint','public.fn_lf_operation_reserve_execution_v1',
        'consumer_reserve_entrypoint','public.fn_lf_operation_reserve_execution_v1',
        'dispatch_entrypoint','public.fn_lf_orchestrator_dispatch_receipt_v1',
        'binding_entrypoint','public.fn_lf_capability_bind_from_orchestrator_v1',
        'binding_readback_source','public.lf_capability_binding',
        'execution_readback_source','public.lf_operation_execution',
        'shadow_entrypoint','programacion.fn_input_governance_shadow_evaluate_v2',
        'fresh_receipt_required',true,
        'execution_id_prefix','T-EQUIV-IG-M3-9-',
        'orchestrator_execution_id_prefix','T-EQUIV-ORCH-IG-M3-9-',
        'plan_digest_seed',p_plan_code||':'||p_unit_code||'|CONTROL_EQUIVALENCE_JUDGE|EXACT_ONLY',
        'corpus_screen_ids',jsonb_build_array(1,43,58),
        'domain_mutation','FORBIDDEN',
        'comparison_only',true
      ),
      'verification_queries',jsonb_build_array(
        $q$with v as (
          select public.fn_lf_version_compatibility_current_version_id_v1(
            'PROGRAMACION_CONTRACT',
            'INPUT_READINESS_CONTRACT',
            'INPUT_GOVERNANCE_AGENT'
          ) as version_id
        ), s(id) as (
          values (1),(43),(58)
        )
        select jsonb_build_object(
          'shadow_contract','M3_9_T_EQUIV_CORPUS_V1',
          'version_id',max(v.version_id),
          'screen_count',count(*),
          'screens',jsonb_agg(
            jsonb_build_object(
              'pantalla_id',s.id,
              'shadow',programacion.fn_input_governance_shadow_evaluate_v2(s.id,v.version_id)
            ) order by s.id
          )
        )
        from s cross join v$q$
      ),
      'material_contract',jsonb_build_object(
        'scope','CURRENT_CHECKPOINT_ONLY',
        'heartbeat_required',true,
        'verification_mode','CAPABILITY_OWNED',
        'design_boundary','BIND_SELECTED_TRANSVERSAL_THEN_EXECUTE_DECLARED_SCOPE_ONLY',
        'persist_on_pass','programacion.fn_engineering_checkpoint_transition_v1',
        'execution_semantics','REAL_SHADOW_AND_FRESH_RECEIPT_REQUIRED'
      ),
      'action_steps',jsonb_build_array(
        'BIND_CURRENT_SELECTED_TRANSVERSAL_AND_PERSIST_FRESH_RECEIPT',
        'EXECUTE_EXISTING_SHADOW_ON_DECLARED_CORPUS',
        'PERSIST_REAL_TEST_EVIDENCE',
        'VERIFY_BINDING_AND_SHADOW_RECEIPTS',
        'PERSIST_DONE_ONLY_AFTER_REAL_EXECUTION',
        'USE_RETURNED_BOOTSTRAP'
      ),
      'forbidden',
        coalesce(v_base->'forbidden','[]'::jsonb)
        || jsonb_build_array(
          'CREATE_PARALLEL_SHADOW_ENGINE',
          'SYNTHETIC_PASS_WITHOUT_SHADOW_EXECUTION',
          'REUSE_OLD_BINDING_AS_THIS_RUN_RECEIPT',
          'MUTATE_DOMAIN_DATA'
        )
    );
  end if;

  return v_base || jsonb_build_object(
    'status','BLOCK_TRANSVERSAL_CAPABILITY_HANDLER_MISSING',
    'precision','STRUCTURAL_TRANSVERSAL_SEQUENCE',
    'transversal_capability_code',v_code,
    'transversal_handler',v_handler
  );
end;
$$;

create or replace function programacion.fn_engineering_checkpoint_action_spec_v3(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text default null
)
returns jsonb
language plpgsql
stable
as $$
declare
  v_base jsonb;
  v_tx jsonb;
  v_cp text;
  v_state jsonb;
  v_item jsonb;
  v_spec jsonb;
begin
  v_base:=programacion.fn_engineering_checkpoint_action_spec_v3_legacy(
    p_plan_code,p_unit_code,p_checkpoint_code
  );
  if v_base is null then return null; end if;

  v_cp:=coalesce(p_checkpoint_code,v_base->>'checkpoint_code');

  select pu.unit_metadata#>array['transversal_execution_v1',v_cp]
    into v_tx
  from programacion.engineering_plan_units pu
  where pu.plan_code=p_plan_code
    and pu.unit_code=p_unit_code;

  if v_tx is null then return v_base; end if;

  if coalesce(v_tx->>'mode','')='SELECT' then
    return v_base || jsonb_build_object(
      'status','BLOCK_TRANSVERSAL_SELECTOR_RUNTIME_REQUIRED',
      'precision','STRUCTURAL_TRANSVERSAL_SELECT',
      'transversal_execution',v_tx,
      'transversal_gate','SELECTOR_REQUIRED'
    );
  end if;

  if coalesce(v_tx->>'mode','')<>'EXPLICIT' then
    return v_base || jsonb_build_object(
      'status','BLOCK_TRANSVERSAL_MODE_INVALID',
      'transversal_execution',v_tx
    );
  end if;

  v_state:=programacion.fn_engineering_transversal_sequence_state_v1(
    p_plan_code,p_unit_code,v_cp
  );

  if coalesce((v_state->>'total')::int,0)=0 then
    return v_base || jsonb_build_object(
      'status','BLOCK_TRANSVERSAL_CAPABILITIES_MISSING',
      'transversal_execution',v_tx
    );
  end if;

  if coalesce((v_state->>'all_done')::boolean,false) then
    return v_base || jsonb_build_object(
      'status','BLOCK_TRANSVERSAL_SEQUENCE_ALREADY_COMPLETE_REQUIRES_CHECKPOINT_TRANSITION',
      'transversal_execution',v_tx,
      'transversal_sequence',v_state
    );
  end if;

  v_item:=v_state->'current_item';
  v_spec:=programacion.fn_engineering_transversal_capability_action_spec_v1(
    p_plan_code,p_unit_code,v_cp,v_item
  );

  return v_spec || jsonb_build_object(
    'transversal_execution',v_tx,
    'transversal_sequence',v_state,
    'transversal_gate',
      case when v_spec->>'status'='READY' then 'PASS_CURRENT_ITEM' else 'BLOCK_CURRENT_ITEM' end,
    'forbidden',
      coalesce(v_spec->'forbidden','[]'::jsonb)
      || jsonb_build_array('FALLBACK_TO_TITLE_HEURISTIC_WHEN_EXPLICIT_DECLARED')
  );
end;
$$;

do $$
declare
  v_body text;
begin
  if not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='programacion'
      and p.proname='fn_engineering_execution_packet_from_spec_v1_legacy'
  ) then
    select routine_definition into v_body
    from information_schema.routines
    where routine_schema='programacion'
      and routine_name='fn_engineering_execution_packet_from_spec_v1';

    if v_body is null then
      raise exception 'EXECUTION_PACKET_V1_SOURCE_NOT_FOUND';
    end if;

    execute
      'create function programacion.fn_engineering_execution_packet_from_spec_v1_legacy(' ||
      'p_plan_code text, p_unit_code text, p_checkpoint_code text, p_action_spec jsonb, p_execution_input jsonb) ' ||
      'returns jsonb language sql stable as ' || quote_literal(v_body);
  end if;
end
$$;

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
as $$
declare
  v_packet jsonb;
  v_seq jsonb;
  v_plan jsonb;
  v_last_idx int;
  v_transition jsonb;
  v_new_transition jsonb;
begin
  v_packet:=programacion.fn_engineering_execution_packet_from_spec_v1_legacy(
    p_plan_code,p_unit_code,p_checkpoint_code,p_action_spec,p_execution_input
  );

  v_seq:=p_action_spec->'transversal_sequence';

  if v_seq is null
     or coalesce(p_action_spec->>'status','')<>'READY'
     or coalesce((v_seq->>'total')::int,0)<=1
     or coalesce((v_seq->>'is_last')::boolean,false) then
    return v_packet;
  end if;

  if coalesce(v_packet->>'status','')<>'READY' then
    return v_packet;
  end if;

  v_plan:=coalesce(v_packet->'connector_plan','[]'::jsonb);
  v_last_idx:=jsonb_array_length(v_plan)-1;

  if v_last_idx<0 then
    return v_packet || jsonb_build_object(
      'status','BLOCK_TRANSVERSAL_PACKET_EMPTY'
    );
  end if;

  v_transition:=v_plan->v_last_idx;

  if coalesce(v_transition->>'operation','')<>'CHECKPOINT_TRANSITION' then
    return v_packet || jsonb_build_object(
      'status','BLOCK_TRANSVERSAL_FINAL_TRANSITION_MISSING'
    );
  end if;

  v_new_transition:=jsonb_build_object(
    'seq',coalesce((v_transition->>'seq')::int,v_last_idx+1),
    'provider','SUPABASE',
    'operation','CHECKPOINT_TRANSITION',
    'mode','TRANSVERSAL_STEP',
    'entrypoint','programacion.fn_engineering_transversal_step_transition_v1',
    'returns','NEXT_BOOTSTRAP_V3_USE_AS_ONLY_NEXT_STATE',
    'arguments',jsonb_build_object(
      'p_plan_code',p_plan_code,
      'p_unit_code',p_unit_code,
      'p_checkpoint_code',p_checkpoint_code,
      'p_sequence_digest',v_seq->>'sequence_digest',
      'p_capability_index',(v_seq->>'next_index')::int,
      'p_capability_code',v_seq->>'current_capability_code',
      'p_evidence_ref','<FILL: evidence of THIS transversal capability step>',
      'p_actor','<FILL: agent name>',
      'p_detail','<FILL: live result of THIS transversal capability step>'
    ),
    'call_template',format(
      'select programacion.fn_engineering_transversal_step_transition_v1(%L,%L,%L,%L,%s,%L,<p_evidence_ref>,<p_actor>,<p_detail>)',
      p_plan_code,p_unit_code,p_checkpoint_code,
      v_seq->>'sequence_digest',
      (v_seq->>'next_index')::int,
      v_seq->>'current_capability_code'
    )
  );

  v_plan:=(v_plan - v_last_idx) || jsonb_build_array(v_new_transition);

  return jsonb_set(
    v_packet || jsonb_build_object(
      'transversal_sequence_mode','ONE_BY_ONE_REBOOTSTRAP',
      'transversal_sequence',v_seq
    ),
    '{connector_plan}',
    v_plan,
    true
  );
end;
$$;
