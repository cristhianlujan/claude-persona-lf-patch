-- M4.9 final correlated-consensus repair.
-- Frozen parent assertions are reused for operational/EKB authorities.
-- Assertions whose authority is CONTRACT are rebuilt from the current contract revision.

do $patch_validate_v2_authority_class$
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
       and not exists (
         select 1
         from programacion.input_family_assessments pa
         cross join lateral jsonb_array_elements(
           programacion.fn_input_validator_evidence_rehydrate_v1(pa.validator_evidence)->''assertions''
         ) x(value)
         where pa.run_id=v_parent
           and pa.family_code=a.family_code
           and x.value#>>''{source_ref,kind}''=''CONTRACT''
       )
      then programacion.fn_input_v58_build_assertions(p_run_id,v_parent,a.family_code)
      else programacion.fn_input_governance_bootstrap_assertions_v1(p_run_id,a.family_code)
    end;'
  );

  if v_new=v_def then
    raise exception 'M49_VALIDATE_V2_AUTHORITY_CLASS_PATCH_NO_CHANGE';
  end if;

  execute v_new;
end;
$patch_validate_v2_authority_class$;

do $proof$
declare
  t1 jsonb;
  t10 jsonb;
begin
  t1:=programacion.fn_engineering_ig_validator_mutation_case_v2(1,58);
  if t1->>'status'<>'PASS'
     or coalesce((t1->>'detected')::boolean,false) is not true
     or coalesce((t1->>'false_pass')::boolean,true) is not false
     or coalesce((t1->>'rollback_clean')::boolean,false) is not true then
    raise exception 'M49_T1_PROOF_FAILED:%',t1;
  end if;

  t10:=programacion.fn_engineering_ig_validator_mutation_case_v2(10,58);
  if t10->>'status'<>'PASS'
     or coalesce((t10->>'detected')::boolean,false) is not true
     or coalesce((t10->>'false_pass')::boolean,true) is not false
     or coalesce((t10->>'rollback_clean')::boolean,false) is not true
     or coalesce(t10->>'technical_error','') not like '%V58_REBOUND_ASSERTION_FAILED%' then
    raise exception 'M49_T10_PROOF_FAILED:%',t10;
  end if;
end;
$proof$;

do $post$
declare
  v_def text;
begin
  v_def:=pg_get_functiondef(
    'programacion.fn_input_governance_validate_v2(bigint,text)'::regprocedure
  );
  if position('x.value#>>''{source_ref,kind}''=''CONTRACT''' in v_def)=0
     or position('fn_input_v58_build_assertions(p_run_id,v_parent,a.family_code)' in v_def)=0
     or position('fn_input_governance_bootstrap_assertions_v1(p_run_id,a.family_code)' in v_def)=0 then
    raise exception 'M49_AUTHORITY_CLASS_ORACLE_POSTCHECK_FAILED';
  end if;
end;
$post$;

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
) values (
  'IG-VALIDATOR-FROZEN-ORACLE-AUTHORITY-CLASS-003',
  'INPUT_GOVERNANCE',
  'Frozen parent oracle reuse must depend on authority class',
  'After contract revision 5.13 -> 5.13.1, reusing a parent assertion whose authority was INPUT_READINESS_CONTRACT produced a legitimate mismatch before the target mutation. Operational-source assertions remained valid frozen oracles and are required to detect correlated resolver defects.',
  'The first T10 repair reused every parent assertion uniformly, ignoring that CONTRACT authority is revisioned while operational/EKB authorities are independently re-readable.',
  'PARENT_ASSERTION_AUTHORITY=CONTRACT -> CURRENT_CONTRACT_BOOTSTRAP; OTHERWISE -> FROZEN_PARENT_EXPECTED + CURRENT_DIRECT_READBACK',
  'In validate_v2 successor runs, contract-backed assertions are rebuilt from the current contract. Non-contract assertions rebind the frozen parent expected value to current direct source readback.',
  'PASS when T1 still yields the intended classifier mismatch, T10 yields V58_REBOUND_ASSERTION_FAILED with false_pass=false, and both rollback cleanly.',
  'CRITICAL',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','ACTIVO',
  'supabase://programacion.fn_input_governance_validate_v2+programacion.fn_engineering_ig_validator_mutation_case_v2',
  'VALIDATION',
  array['INPUT_VALIDATOR','ENGINEERING_EXECUTOR']::text[],
  'R2_NO_VE','LOUD_EARLY',
  'M4.9 T1/T10 authority-class oracle repair on representative screen 58',
  'supabase://programacion.fn_input_governance_validate_v2'
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
