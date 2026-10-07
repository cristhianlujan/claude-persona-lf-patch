-- PROGRAMMING_SIMPLE_EXECUTOR_V1 qualification-proof hardening.
-- Exact test_run_id lookup only; no historical plan/unit scan.
-- A qualifying PASS must be semantically bound to the validator/resolver it proves.

create or replace function programacion.fn_programming_qualification_test_pass_v1(
  p_test_run_id uuid,
  p_subject_type text,
  p_subject_code text,
  p_test_role text
)
returns boolean
language sql
stable
set search_path to 'public','pg_catalog'
as $function$
select exists (
  select 1
  from public.lf_test_runs t
  where t.test_run_id=p_test_run_id
    and t.status in ('PASS','PASSED')
    and t.completed_at is not null
    and coalesce(t.metadata->>'programming_subject_type','')=p_subject_type
    and coalesce(t.metadata->>'programming_subject_code','')=p_subject_code
    and coalesce(t.metadata->>'programming_test_role','')=p_test_role
);
$function$;

create or replace function programacion.fn_programming_rule_admission_v1(
  p_validation_code text,
  p_failure_code text default 'VALIDATION_FAILED'
)
returns jsonb
language plpgsql
stable
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v programacion.programming_validation_registry%rowtype;
  r programacion.programming_resolver_registry%rowtype;
  pv programacion.programming_validation_registry%rowtype;
begin
  select * into v
  from programacion.programming_validation_registry
  where validation_code=p_validation_code;

  if not found then
    return jsonb_build_object(
      'schema_version','PROGRAMMING_RULE_ADMISSION_V1',
      'admitted',false,
      'reason','VALIDATION_NOT_REGISTERED',
      'validation_code',p_validation_code
    );
  end if;

  if v.status<>'ACTIVE'
     or not v.deterministic
     or nullif(btrim(v.validator_handler),'') is null
     or nullif(btrim(coalesce(v.positive_test_ref,'')),'') is null
     or nullif(btrim(coalesce(v.negative_test_ref,'')),'') is null
     or v.positive_test_run_id is null
     or v.negative_test_run_id is null
     or not programacion.fn_programming_qualification_test_pass_v1(
       v.positive_test_run_id,'VALIDATION',v.validation_code,'POSITIVE'
     )
     or not programacion.fn_programming_qualification_test_pass_v1(
       v.negative_test_run_id,'VALIDATION',v.validation_code,'NEGATIVE'
     ) then
    return jsonb_build_object(
      'schema_version','PROGRAMMING_RULE_ADMISSION_V1',
      'admitted',false,
      'reason','VALIDATION_NOT_ACTIVE_PROVEN_DETERMINISTIC',
      'validation_code',v.validation_code,
      'validation_status',v.status,
      'deterministic',v.deterministic,
      'qualification_contract','EXACT_TEST_RUN_ID_AND_SUBJECT_ROLE_MATCH'
    );
  end if;

  if v.rule_mode='BLOCKING_AUTOMATIC' then
    select * into r
    from programacion.programming_resolver_registry
    where validation_code=v.validation_code
      and failure_code=p_failure_code
      and status='ACTIVE';

    if not found then
      return jsonb_build_object(
        'schema_version','PROGRAMMING_RULE_ADMISSION_V1',
        'admitted',false,
        'reason','ACTIVE_RESOLVER_REQUIRED',
        'validation_code',v.validation_code,
        'failure_code',p_failure_code
      );
    end if;

    if not r.deterministic
       or nullif(btrim(r.resolver_handler),'') is null
       or nullif(btrim(coalesce(r.resolver_test_ref,'')),'') is null
       or nullif(btrim(coalesce(r.post_validation_test_ref,'')),'') is null
       or r.resolver_test_run_id is null
       or r.post_validation_test_run_id is null
       or not programacion.fn_programming_qualification_test_pass_v1(
         r.resolver_test_run_id,'RESOLVER',r.resolver_code,'RESOLVER'
       )
       or not programacion.fn_programming_qualification_test_pass_v1(
         r.post_validation_test_run_id,'RESOLVER',r.resolver_code,'POST_VALIDATION'
       ) then
      return jsonb_build_object(
        'schema_version','PROGRAMMING_RULE_ADMISSION_V1',
        'admitted',false,
        'reason','RESOLVER_NOT_PROVEN_DETERMINISTIC',
        'resolver_code',r.resolver_code,
        'qualification_contract','EXACT_TEST_RUN_ID_AND_SUBJECT_ROLE_MATCH'
      );
    end if;

    select * into pv
    from programacion.programming_validation_registry
    where validation_code=r.post_validation_code;

    if not found
       or pv.status<>'ACTIVE'
       or not pv.deterministic
       or nullif(btrim(coalesce(pv.positive_test_ref,'')),'') is null
       or nullif(btrim(coalesce(pv.negative_test_ref,'')),'') is null
       or pv.positive_test_run_id is null
       or pv.negative_test_run_id is null
       or not programacion.fn_programming_qualification_test_pass_v1(
         pv.positive_test_run_id,'VALIDATION',pv.validation_code,'POSITIVE'
       )
       or not programacion.fn_programming_qualification_test_pass_v1(
         pv.negative_test_run_id,'VALIDATION',pv.validation_code,'NEGATIVE'
       ) then
      return jsonb_build_object(
        'schema_version','PROGRAMMING_RULE_ADMISSION_V1',
        'admitted',false,
        'reason','POST_VALIDATION_NOT_ACTIVE_PROVEN',
        'post_validation_code',r.post_validation_code,
        'qualification_contract','EXACT_TEST_RUN_ID_AND_SUBJECT_ROLE_MATCH'
      );
    end if;

    return jsonb_build_object(
      'schema_version','PROGRAMMING_RULE_ADMISSION_V1',
      'admitted',true,
      'validation_code',v.validation_code,
      'rule_code',v.rule_code,
      'rule_mode',v.rule_mode,
      'validator_handler',v.validator_handler,
      'resolver',jsonb_build_object(
        'resolver_code',r.resolver_code,
        'resolver_handler',r.resolver_handler,
        'preconditions',r.preconditions,
        'post_validation_code',r.post_validation_code
      ),
      'qualification_lookup','EXACT_TEST_RUN_ID_ONLY',
      'runtime_history_scan',false,
      'reuse_policy','REUSE_PROCEDURE_NOT_PASS'
    );
  end if;

  return jsonb_build_object(
    'schema_version','PROGRAMMING_RULE_ADMISSION_V1',
    'admitted',true,
    'validation_code',v.validation_code,
    'rule_code',v.rule_code,
    'rule_mode',v.rule_mode,
    'validator_handler',v.validator_handler,
    'qualification_lookup','EXACT_TEST_RUN_ID_ONLY',
    'runtime_history_scan',false,
    'reuse_policy','REUSE_PROCEDURE_NOT_PASS'
  );
end;
$function$;

comment on function programacion.fn_programming_qualification_test_pass_v1(uuid,text,text,text) is
'Qualification proof for PROGRAMMING_SIMPLE_EXECUTOR_V1. Reads exactly one lf_test_runs primary key and requires semantic subject+role markers; never scans plan/unit runtime history.';

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
  severidad,estado,source_ref,updated_at
)
values (
  'PROGRAMMING-SIMPLE-QUALIFICATION-PROOF-001',
  'PROGRAMMING_GOVERNANCE',
  'Qualification proof is not runtime history and must be exact-subject bound',
  'Validator/resolver admission must not search prior plan or unit history. A new rule can qualify with fresh tests. The admission path resolves exact lf_test_runs primary keys and requires metadata binding to the validator/resolver subject and test role.',
  'Treating any historical PASS as proof can either reject new procedures with no history or accidentally admit a procedure using unrelated historical evidence.',
  'QUALIFICATION TEST -> exact test_run_id -> subject_code + role match -> PASS/PASSED; runtime unit -> fresh current validation receipt.',
  'Never scan previous plan/unit executions for admission. Store exact qualification test_run_ids. Require metadata programming_subject_type/programming_subject_code/programming_test_role to match the registry subject.',
  'fn_programming_qualification_test_pass_v1 performs a primary-key lookup only. Rule admission fails for an unrelated PASS test and succeeds for a fresh correctly bound qualification test. Current checkpoint closure still requires current run/unit/checkpoint PASS.',
  'HIGH',
  'ACTIVO',
  'github://cristhianlujan/claude-persona-lf-patch/supabase/migrations/20261007223500_programming_simple_qualification_proof_v1.sql',
  now()
)
on conflict (codigo) do update
set titulo=excluded.titulo,
    descripcion=excluded.descripcion,
    causa_raiz=excluded.causa_raiz,
    patron=excluded.patron,
    prevencion=excluded.prevencion,
    validacion=excluded.validacion,
    severidad=excluded.severidad,
    estado=excluded.estado,
    source_ref=excluded.source_ref,
    updated_at=excluded.updated_at;
