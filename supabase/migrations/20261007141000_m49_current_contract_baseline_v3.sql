-- M4.9 mutation campaign v3.
-- Frozen-parent assertions apply only within the same contract revision.
-- The mutation harness creates a temporary current-contract baseline when needed,
-- then runs the existing rollback-only case v2 and rolls the baseline back too.

do $patch_validate_v2_revision_guard$
declare
  v_def text;
  v_old text;
  v_new text;
begin
  v_def:=pg_get_functiondef(
    'programacion.fn_input_governance_validate_v2(bigint,text)'::regprocedure
  );
  v_old:=
'v_assertions:=case when v_parent is not null then programacion.fn_input_v58_build_assertions(p_run_id,v_parent,a.family_code) else programacion.fn_input_governance_bootstrap_assertions_v1(p_run_id,a.family_code) end;';

  if position(v_old in v_def)=0 then
    raise exception 'M49_VALIDATE_V2_FROZEN_PARENT_ANCHOR_MISSING';
  end if;

  v_new:=replace(
    v_def,
    v_old,
'v_assertions:=case
      when v_parent is not null
       and (select pr.contract_revision
            from programacion.input_readiness_runs pr
            where pr.id=v_parent) is not distinct from v_contract_revision
      then programacion.fn_input_v58_build_assertions(p_run_id,v_parent,a.family_code)
      else programacion.fn_input_governance_bootstrap_assertions_v1(p_run_id,a.family_code)
    end;'
  );
  execute v_new;
end;
$patch_validate_v2_revision_guard$;

create or replace function programacion.fn_engineering_ig_validator_mutation_case_v3(
  p_case integer,
  p_pantalla_id integer default 54
) returns jsonb
language plpgsql
volatile
set search_path to 'pg_catalog','programacion','public','lf_ops','extensions'
set statement_timeout to '180s'
as $f$
declare
  v_version bigint:=public.fn_lf_version_compatibility_current_version_id_v1(
    'PROGRAMACION_CONTRACT','INPUT_READINESS_CONTRACT','INPUT_GOVERNANCE_AGENT'
  );
  v_current_revision text;
  v_latest_revision text;
  v_baseline_curator text:='INPUT_CURATOR:EDGE:input-governance-curator-v1:M49B'||substr(replace(gen_random_uuid()::text,'-',''),1,12);
  v_baseline_validator text:='INPUT_VALIDATOR:EDGE:input-governance-validator-v1:M49B'||substr(replace(gen_random_uuid()::text,'-',''),1,12);
  v_cur jsonb;
  v_val jsonb;
  v_baseline_run bigint;
  v_baseline_status text;
  v_baseline_revision text;
  v_case_result jsonb;
  v_i integer;
  v_marker text:='M49_V3_BASELINE_ROLLBACK_'||p_case::text;
begin
  if p_case not between 1 and 10 then
    raise exception 'M49_V3_CASE_OUT_OF_RANGE:%',p_case;
  end if;

  select c.especificacion->>'contract_revision'
    into v_current_revision
  from programacion.contratos c
  where c.version_id=v_version
    and c.contrato_codigo='INPUT_READINESS_CONTRACT'
    and c.estado='defined'
    and c.fail_closed;

  if v_current_revision is null then
    raise exception 'M49_V3_CURRENT_CONTRACT_REVISION_UNRESOLVED';
  end if;

  select r.contract_revision
    into v_latest_revision
  from programacion.input_readiness_runs r
  where r.version_id=v_version
    and r.pantalla_id=p_pantalla_id
    and r.status='COMPLETED'
  order by r.id desc
  limit 1;

  if v_latest_revision is not distinct from v_current_revision then
    return programacion.fn_engineering_ig_validator_mutation_case_v2(
      p_case,p_pantalla_id
    ) || jsonb_build_object(
      'baseline_mode','REUSE_CURRENT_CONTRACT_BASELINE',
      'baseline_contract_revision',v_current_revision
    );
  end if;

  begin
    v_cur:=programacion.fn_input_governance_curator_rebind_v1(
      p_pantalla_id,'MANUAL',v_baseline_curator,true
    );
    v_baseline_run:=coalesce(
      (v_cur->>'run_id')::bigint,
      (v_cur->>'latest_run_id')::bigint
    );
    if v_baseline_run is null then
      raise exception 'M49_V3_BASELINE_RUN_NOT_CREATED:%',v_cur;
    end if;

    for v_i in 1..8 loop
      v_val:=programacion.fn_input_governance_validator_validate_v1(
        v_baseline_run,v_baseline_validator
      );
      select r.status,r.contract_revision
        into v_baseline_status,v_baseline_revision
      from programacion.input_readiness_runs r
      where r.id=v_baseline_run;
      exit when v_baseline_status='COMPLETED';
    end loop;

    if v_baseline_status<>'COMPLETED'
       or v_baseline_revision is distinct from v_current_revision then
      raise exception 'M49_V3_BASELINE_NOT_CURRENT_COMPLETED:run=% status=% revision=% current=% last=%',
        v_baseline_run,v_baseline_status,v_baseline_revision,v_current_revision,v_val;
    end if;

    v_case_result:=programacion.fn_engineering_ig_validator_mutation_case_v2(
      p_case,p_pantalla_id
    );

    raise exception '%',v_marker;
  exception when others then
    if sqlerrm<>v_marker then
      raise;
    end if;
  end;

  if exists(
    select 1
    from programacion.input_readiness_runs r
    where r.curator_identity=v_baseline_curator
       or r.validator_identity=v_baseline_validator
  ) then
    raise exception 'M49_V3_BASELINE_RESIDUE:%',p_case;
  end if;

  return v_case_result || jsonb_build_object(
    'baseline_mode','TEMP_CURRENT_CONTRACT_BASELINE_ROLLBACK',
    'baseline_contract_revision',v_current_revision,
    'baseline_rollback_clean',true
  );
end;
$f$;

comment on function programacion.fn_engineering_ig_validator_mutation_case_v3(integer,integer)
is 'M4.9 generic per-mutation executor. Ensures a same-contract completed baseline inside a rollback scope before invoking mutation_case_v2; no baseline or fixture residue persists.';

update public.lf_test_suite_cases c
set metadata=coalesce(c.metadata,'{}'::jsonb)
  || jsonb_build_object(
    'case_entrypoint','programacion.fn_engineering_ig_validator_mutation_case_v3',
    'baseline_policy','SAME_CONTRACT_REVISION_OR_TEMP_ROLLBACK_BASELINE'
  ),
  updated_at=now(),
  updated_by_execution_id='EXEC-M49-CAMPAIGN-V3-20261007'
where c.suite_code='INPUT_GOVERNANCE_REGRESSION'
  and c.metadata->>'unit_code'='M4.9'
  and c.metadata->>'checkpoint_code'='RUN_CAMPAIGN';

update programacion.engineering_plan_units pu
set unit_metadata=jsonb_set(
  pu.unit_metadata,
  '{action_specs_v1,RUN_CAMPAIGN,test_execution_contract}',
  coalesce(pu.unit_metadata#>'{action_specs_v1,RUN_CAMPAIGN,test_execution_contract}','{}'::jsonb)
  || jsonb_build_object(
    'case_entrypoint','programacion.fn_engineering_ig_validator_mutation_case_v3(integer,integer)',
    'baseline_policy','SAME_CONTRACT_REVISION_OR_TEMP_ROLLBACK_BASELINE',
    'contract_revision_compatibility','REQUIRED_FOR_FROZEN_PARENT_ASSERTIONS'
  ),
  true
)
where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and pu.unit_code='M4.9'
  and pu.disposition='ASSIGNED';

do $proof$
declare
  r jsonb;
begin
  r:=programacion.fn_engineering_ig_validator_mutation_case_v3(10,54);
  if r->>'status'<>'PASS'
     or coalesce((r->>'detected')::boolean,false) is not true
     or coalesce((r->>'false_pass')::boolean,true) is not false
     or coalesce((r->>'rollback_clean')::boolean,false) is not true
     or coalesce((r->>'baseline_rollback_clean')::boolean,true) is not true
     or coalesce(r->>'technical_error','') not like '%V58_REBOUND_ASSERTION_FAILED%' then
    raise exception 'M49_V3_T10_PROOF_FAILED:%',r;
  end if;
end;
$proof$;

do $post$
declare
  v_def text;
  v_spec jsonb;
begin
  v_def:=pg_get_functiondef(
    'programacion.fn_input_governance_validate_v2(bigint,text)'::regprocedure
  );
  if position('pr.contract_revision' in v_def)=0
     or position('fn_input_v58_build_assertions(p_run_id,v_parent,a.family_code)' in v_def)=0 then
    raise exception 'M49_V3_REVISION_AWARE_FROZEN_ORACLE_NOT_ACTIVE';
  end if;

  v_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M4.9','RUN_CAMPAIGN'
  );
  if v_spec#>>'{test_execution_contract,case_entrypoint}'
     is distinct from 'programacion.fn_engineering_ig_validator_mutation_case_v3(integer,integer)' then
    raise exception 'M49_V3_ACTION_SPEC_ENTRYPOINT_MISMATCH:%',v_spec;
  end if;
end;
$post$;

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
) values (
  'IG-VALIDATOR-FROZEN-ORACLE-CONTRACT-REVISION-002',
  'INPUT_GOVERNANCE',
  'Frozen parent assertions require contract-revision compatibility',
  'A frozen parent receipt is a valid independent oracle only when parent and successor share the same INPUT_READINESS_CONTRACT revision. After revision 5.13 -> 5.13.1, unconditional parent rebind rejected legitimate contract drift before mutation evaluation.',
  'The first T10 repair applied frozen-parent assertions to every successor without distinguishing contract migration from same-contract source drift.',
  'IF_PARENT_REVISION_EQUALS_CURRENT_USE_FROZEN_PARENT_ASSERTIONS_ELSE_ESTABLISH_CURRENT_REVISION_BASELINE',
  'Validator uses frozen parent assertions only within the same contract revision. Mutation campaigns create a temporary current-revision completed baseline inside rollback before injecting defects.',
  'PASS when no durable baseline residue remains, T10 is rejected by the frozen 5.13.1 parent oracle, false_pass=false, and normal contract migration can bootstrap under the new revision.',
  'CRITICAL',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','ACTIVO',
  'supabase://programacion.fn_input_governance_validate_v2+programacion.fn_engineering_ig_validator_mutation_case_v3',
  'VALIDATION',
  array['INPUT_VALIDATOR','ENGINEERING_EXECUTOR']::text[],
  'R2_NO_VE','LOUD_EARLY',
  'M4.9 T10 current-contract baseline compatibility',
  'supabase://programacion.fn_engineering_ig_validator_mutation_case_v3'
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
