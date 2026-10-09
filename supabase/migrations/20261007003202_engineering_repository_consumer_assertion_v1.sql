-- Repository capability consumer assertion overlay v1.
-- Provider validation proves the output is valid for the released capability.
-- Consumer pass_when proves that the valid output satisfies this checkpoint.

create or replace function programacion.fn_engineering_action_spec_assertion_contract_v1(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text,
  p_spec jsonb
)
returns jsonb
language plpgsql
stable
set search_path to 'programacion','public','pg_catalog'
as $function$
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
    v_exec:=coalesce(v_spec->'capability_execution','{}'::jsonb);
    v_code:=nullif(btrim(coalesce(v_exec->>'capability_code','')),'');

    select c.version,c.manifest_sha256,v.validator_ref,v.manifest
      into v_current_version,v_current_manifest_sha,v_validator_ref,v_manifest
    from public.lf_capability_current c
    join public.lf_capability_version_registry v
      on v.capability_code=c.capability_code
     and v.version=c.version
     and v.release_state='RELEASED'
    where c.capability_code=v_code;

    v_output_schema:=coalesce(
      nullif(btrim(coalesce(v_manifest#>>'{contract,output}','')),''),
      nullif(btrim(coalesce(v_manifest#>>'{compatibility,provider_contract}','')),'')
    );

    if jsonb_typeof(v_manifest#>'{contract,outputs}')='array' then
      v_output_fields:=v_manifest#>'{contract,outputs}';
    end if;

    -- A repository consumer may add semantic acceptance without changing the
    -- provider capability. Prefer an explicit top-level assertion, otherwise
    -- read the assertion attached to this exact transversal capability item.
    if jsonb_typeof(v_explicit)='object' then
      v_consumer_assertion:=v_explicit;
    else
      select item->'assertion_contract'
        into v_consumer_assertion
      from programacion.engineering_plan_units pu
      cross join lateral jsonb_array_elements(
        coalesce(
          pu.unit_metadata#>array[
            'transversal_execution_v1',
            p_checkpoint_code,
            'capabilities'
          ],
          '[]'::jsonb
        )
      ) item
      where pu.plan_code=p_plan_code
        and pu.unit_code=p_unit_code
        and item->>'capability_code'=v_code
        and jsonb_typeof(item->'assertion_contract')='object'
      limit 1;
    end if;

    if v_consumer_assertion is not null then
      v_pass_when:=v_consumer_assertion->'pass_when';
      if jsonb_typeof(v_pass_when)<>'object' then
        return jsonb_build_object(
          'schema_version','ENGINEERING_ASSERTION_CONTRACT_V1',
          'status','BLOCK_ASSERTION_CONTRACT_INCOMPLETE',
          'mode','REPOSITORY_CAPABILITY_VALIDATED_OUTPUT',
          'reason','CONSUMER_PASS_WHEN_OBJECT_REQUIRED',
          'plan_code',p_plan_code,
          'unit_code',p_unit_code,
          'checkpoint_code',p_checkpoint_code,
          'capability_code',v_code
        );
      end if;

      if v_consumer_assertion ? 'required_nonempty_fields' then
        if jsonb_typeof(v_consumer_assertion->'required_nonempty_fields')<>'array' then
          return jsonb_build_object(
            'schema_version','ENGINEERING_ASSERTION_CONTRACT_V1',
            'status','BLOCK_ASSERTION_CONTRACT_INCOMPLETE',
            'mode','REPOSITORY_CAPABILITY_VALIDATED_OUTPUT',
            'reason','REQUIRED_NONEMPTY_FIELDS_ARRAY_REQUIRED',
            'plan_code',p_plan_code,
            'unit_code',p_unit_code,
            'checkpoint_code',p_checkpoint_code,
            'capability_code',v_code
          );
        end if;
        v_required_nonempty:=v_consumer_assertion->'required_nonempty_fields';
      end if;
    end if;

    if v_code is null
       or v_current_version is null
       or v_current_manifest_sha is null
       or nullif(btrim(coalesce(v_validator_ref,'')),'') is null
       or v_output_schema is null
       or coalesce((v_exec->>'result_evidence_required')::boolean,false)=false then
      return jsonb_build_object(
        'schema_version','ENGINEERING_ASSERTION_CONTRACT_V1',
        'status','BLOCK_ASSERTION_CONTRACT_INCOMPLETE',
        'mode','REPOSITORY_CAPABILITY_VALIDATED_OUTPUT',
        'reason','CURRENT_RELEASE_OUTPUT_VALIDATOR_AND_RESULT_EVIDENCE_REQUIRED',
        'plan_code',p_plan_code,
        'unit_code',p_unit_code,
        'checkpoint_code',p_checkpoint_code,
        'capability_code',v_code
      );
    end if;

    if v_exec->>'current_version' is distinct from v_current_version
       or v_exec->>'manifest_sha256' is distinct from v_current_manifest_sha then
      return jsonb_build_object(
        'schema_version','ENGINEERING_ASSERTION_CONTRACT_V1',
        'status','BLOCK_ASSERTION_CONTRACT_STALE_CAPABILITY',
        'mode','REPOSITORY_CAPABILITY_VALIDATED_OUTPUT',
        'reason','ACTION_SPEC_CAPABILITY_CURRENTNESS_MISMATCH',
        'plan_code',p_plan_code,
        'unit_code',p_unit_code,
        'checkpoint_code',p_checkpoint_code,
        'capability_code',v_code,
        'expected_version',v_current_version,
        'expected_manifest_sha256',v_current_manifest_sha
      );
    end if;

    return jsonb_strip_nulls(jsonb_build_object(
      'schema_version','ENGINEERING_ASSERTION_CONTRACT_V1',
      'status','READY',
      'mode','REPOSITORY_CAPABILITY_VALIDATED_OUTPUT',
      'plan_code',p_plan_code,
      'unit_code',p_unit_code,
      'checkpoint_code',p_checkpoint_code,
      'expected_status','PASS',
      'expected_validator_status','PASS',
      'capability_code',v_code,
      'version',v_current_version,
      'manifest_sha256',v_current_manifest_sha,
      'result_schema',v_output_schema,
      'validator_ref',v_validator_ref,
      'output_fields',case
        when jsonb_array_length(v_output_fields)>0 then v_output_fields
        else null
      end,
      'pass_when',v_pass_when,
      'required_nonempty_fields',case
        when jsonb_array_length(v_required_nonempty)>0 then v_required_nonempty
        else null
      end,
      'consumer_assertion_bound',v_consumer_assertion is not null
    ));
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

create or replace function programacion.fn_engineering_checkpoint_assertion_record_v1(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text,
  p_result jsonb,
  p_actor text
)
returns jsonb
language plpgsql
security definer
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_work_item_id bigint;
  v_checkpoint_id bigint;
  v_current_code text;
  v_spec jsonb;
  v_contract jsonb;
  v_contract_sha text;
  v_mode text;
  v_pass boolean := false;
  v_pass_when jsonb;
  v_result_sha text;
  v_evidence_ref text;
  v_recorded_at timestamptz := clock_timestamp();
  v_receipt jsonb;
  v_receipt_sha text;
  v_observed jsonb;
  v_semantic_ok boolean := true;
  v_fields_ok boolean := true;
  v_nonempty_ok boolean := true;
begin
  if jsonb_typeof(p_result)<>'object' then
    raise exception 'ENGINEERING_ASSERTION_RESULT_OBJECT_REQUIRED:%/%/%',
      p_plan_code,p_unit_code,p_checkpoint_code;
  end if;

  select pu.work_item_id
    into v_work_item_id
  from programacion.engineering_plan_units pu
  where pu.plan_code=p_plan_code
    and pu.unit_code=p_unit_code
    and pu.disposition='ASSIGNED';

  if v_work_item_id is null then
    raise exception 'ENGINEERING_ASSERTION_UNIT_NOT_FOUND:%/%',p_plan_code,p_unit_code;
  end if;

  select c.id
    into v_checkpoint_id
  from programacion.engineering_work_checkpoints c
  where c.work_item_id=v_work_item_id
    and c.checkpoint_code=p_checkpoint_code
  for update;

  if v_checkpoint_id is null then
    raise exception 'ENGINEERING_ASSERTION_CHECKPOINT_NOT_FOUND:%/%/%',
      p_plan_code,p_unit_code,p_checkpoint_code;
  end if;

  select c.checkpoint_code
    into v_current_code
  from programacion.engineering_work_checkpoints c
  where c.work_item_id=v_work_item_id
    and c.status not in ('DONE','NOT_APPLICABLE')
  order by c.sequence_no
  limit 1;

  if v_current_code is distinct from p_checkpoint_code then
    raise exception 'ENGINEERING_ASSERTION_CHECKPOINT_NOT_CURRENT:% current=%',
      p_checkpoint_code,coalesce(v_current_code,'<terminal>');
  end if;

  v_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(
    p_plan_code,p_unit_code,p_checkpoint_code
  );
  v_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1(
    p_plan_code,p_unit_code,p_checkpoint_code,v_spec
  );

  if coalesce(v_contract->>'status','')<>'READY' then
    raise exception 'ENGINEERING_ASSERTION_CONTRACT_NOT_READY:%',
      coalesce(v_contract::text,'{}');
  end if;

  v_contract_sha:=programacion.fn_v09_sha256_jsonb(v_contract);
  v_mode:=v_contract->>'mode';
  v_observed:=p_result->'observed';

  if v_mode='CAPABILITY_TEST_RESULT_CONTRACT' then
    v_pass_when:=v_contract->'pass_when';
    v_evidence_ref:=nullif(btrim(coalesce(p_result->>'evidence_ref','')),'');
    v_pass :=
      p_result->>'status'='PASS'
      and p_result->>'test_code'=v_contract->>'test_code'
      and (
        v_contract->>'suite_code' is null
        or p_result->>'suite_code'=v_contract->>'suite_code'
      )
      and jsonb_typeof(v_observed)='object'
      and v_observed @> v_pass_when
      and v_evidence_ref is not null;

  elsif v_mode='REPOSITORY_CAPABILITY_VALIDATED_OUTPUT' then
    v_evidence_ref:=nullif(btrim(coalesce(p_result->>'validator_evidence_ref','')),'');

    if jsonb_typeof(v_contract->'pass_when')='object' then
      v_semantic_ok :=
        jsonb_typeof(v_observed)='object'
        and v_observed @> (v_contract->'pass_when');
    end if;

    if jsonb_typeof(v_contract->'output_fields')='array'
       and jsonb_array_length(v_contract->'output_fields')>0 then
      if jsonb_typeof(v_observed)<>'object' then
        v_fields_ok:=false;
      else
        select not exists (
          select 1
          from jsonb_array_elements_text(v_contract->'output_fields') f(field_name)
          where not (v_observed ? f.field_name)
        ) into v_fields_ok;
      end if;
    end if;

    if jsonb_typeof(v_contract->'required_nonempty_fields')='array'
       and jsonb_array_length(v_contract->'required_nonempty_fields')>0 then
      if jsonb_typeof(v_observed)<>'object' then
        v_nonempty_ok:=false;
      else
        select not exists (
          select 1
          from jsonb_array_elements_text(v_contract->'required_nonempty_fields') f(field_name)
          where not (v_observed ? f.field_name)
             or jsonb_typeof(v_observed->f.field_name)='null'
             or nullif(btrim(coalesce(v_observed->>f.field_name,'')),'') is null
        ) into v_nonempty_ok;
      end if;
    end if;

    v_pass :=
      p_result->>'status'='PASS'
      and p_result->>'validator_status'='PASS'
      and p_result->>'capability_code'=v_contract->>'capability_code'
      and p_result->>'version'=v_contract->>'version'
      and p_result->>'manifest_sha256'=v_contract->>'manifest_sha256'
      and p_result->>'result_schema'=v_contract->>'result_schema'
      and p_result->>'validator_ref'=v_contract->>'validator_ref'
      and v_evidence_ref is not null
      and v_semantic_ok
      and v_fields_ok
      and v_nonempty_ok;

  elsif v_mode='EXPLICIT_PASS_WHEN_SUBSET' then
    v_pass_when:=v_contract->'pass_when';
    v_evidence_ref:=nullif(btrim(coalesce(p_result->>'evidence_ref','')),'');
    v_pass :=
      p_result->>'status'='PASS'
      and jsonb_typeof(v_observed)='object'
      and v_observed @> v_pass_when
      and v_evidence_ref is not null;
  else
    raise exception 'ENGINEERING_ASSERTION_MODE_UNSUPPORTED:%',v_mode;
  end if;

  if not v_pass then
    raise exception 'ENGINEERING_ASSERTION_RESULT_FAILED:%/%/% mode=%',
      p_plan_code,p_unit_code,p_checkpoint_code,v_mode;
  end if;

  v_result_sha:=programacion.fn_v09_sha256_jsonb(p_result);

  v_receipt:=jsonb_build_object(
    'schema_version','ENGINEERING_CHECKPOINT_ASSERTION_RECEIPT_V1',
    'passed',true,
    'mode',v_mode,
    'plan_code',p_plan_code,
    'unit_code',p_unit_code,
    'checkpoint_code',p_checkpoint_code,
    'contract_sha256',v_contract_sha,
    'result_sha256',v_result_sha,
    'evidence_ref',v_evidence_ref,
    'recorded_at',v_recorded_at,
    'recorded_by',coalesce(nullif(btrim(p_actor),''),'ENGINEERING_ASSERTION_RECORDER')
  );
  v_receipt_sha:=programacion.fn_v09_sha256_jsonb(v_receipt);

  update programacion.engineering_work_checkpoints
     set assertion_contract_sha256=v_contract_sha,
         assertion_receipt=v_receipt,
         assertion_receipt_sha256=v_receipt_sha,
         assertion_recorded_at=v_recorded_at,
         assertion_recorded_by=coalesce(nullif(btrim(p_actor),''),'ENGINEERING_ASSERTION_RECORDER'),
         updated_at=now(),
         updated_by_execution_id=coalesce(nullif(btrim(p_actor),''),'ENGINEERING_ASSERTION_RECORDER')
   where id=v_checkpoint_id;

  return v_receipt || jsonb_build_object(
    'assertion_receipt_sha256',v_receipt_sha
  );
end;
$function$;

revoke all on function programacion.fn_engineering_checkpoint_assertion_record_v1(text,text,text,jsonb,text) from public;
revoke execute on function programacion.fn_engineering_checkpoint_assertion_record_v1(text,text,text,jsonb,text) from anon;
revoke execute on function programacion.fn_engineering_checkpoint_assertion_record_v1(text,text,text,jsonb,text) from authenticated;
grant execute on function programacion.fn_engineering_checkpoint_assertion_record_v1(text,text,text,jsonb,text) to service_role;
grant execute on function programacion.fn_engineering_checkpoint_assertion_record_v1(text,text,text,jsonb,text) to postgres;

-- Author the consumer semantic criterion at the exact N-17 capability item.
update programacion.engineering_plan_units pu
set unit_metadata=jsonb_set(
  pu.unit_metadata,
  '{transversal_execution_v1,TYPED_CAUSAL_IDENTITY,capabilities}',
  (
    select jsonb_agg(
      case
        when item->>'capability_code'='CAUSAL_EFFECT_LINEAGE' then
          item || jsonb_build_object(
            'assertion_contract',jsonb_build_object(
              'mode','REPOSITORY_CAPABILITY_VALIDATED_OUTPUT',
              'pass_when',jsonb_build_object(
                'state','LINKED',
                'business_authority',false,
                'execution_permission',false
              ),
              'required_nonempty_fields',jsonb_build_array('causal_edge_digest')
            )
          )
        else item
      end
      order by ord
    )
    from jsonb_array_elements(
      pu.unit_metadata#>'{transversal_execution_v1,TYPED_CAUSAL_IDENTITY,capabilities}'
    ) with ordinality x(item,ord)
  ),
  true
)
where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and pu.unit_code='N-17';

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
) values (
  'ENGINEERING-REPOSITORY-CAPABILITY-CONSUMER-ASSERTION-001',
  'ENGINEERING_ORCHESTRATION',
  'Repository capability validation and consumer semantic acceptance are separate assertions',
  'A released repository capability can prove that an output is structurally valid while the consuming checkpoint still needs a narrower semantic outcome. N-17 requires CAUSAL_EFFECT_LINEAGE state LINKED without business authority or execution permission.',
  'The first material assertion gate bound provider output schema and validator authority but did not yet carry consumer-specific semantic pass_when from transversal metadata.',
  'PROVIDER_VALID_OUTPUT_DOES_NOT_IMPLY_CONSUMER_ACCEPTANCE',
  'Allow each transversal capability item to declare assertion_contract.pass_when and required_nonempty_fields. Combine those consumer assertions with the current released provider version, manifest, output contract and validator in the derived receipt contract.',
  'PASS when N-17 derives READY REPOSITORY_CAPABILITY_VALIDATED_OUTPUT with provider_contract LF_CAUSAL_EFFECT_LINEAGE_V1, all five output fields, state=LINKED, business_authority=false, execution_permission=false and nonempty causal_edge_digest; all six open material READY checkpoints then have READY assertion contracts.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','ACTIVO',
  'supabase://programacion.fn_engineering_action_spec_assertion_contract_v1; github://sandbox/lf_contract_gate_test/transversal_assets/causal_effect_lineage/ig_n17_consumer_binding_v1.json',
  'EXECUTION',
  array['ENGINEERING_SCHEDULER','CAPABILITY_CONSUMER']::text[],
  'R2_NO_VE','LOUD_EARLY',
  'N-17 TYPED_CAUSAL_IDENTITY',
  'supabase://programacion.engineering_plan_units/IG_CURATOR_VALIDATOR_REFACTOR_V2/N-17'
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
