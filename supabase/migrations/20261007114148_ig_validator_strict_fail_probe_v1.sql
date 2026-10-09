-- Generic rollback-only probe for a real Validator FAIL receipt.
-- Used by M4.7 and reusable by any checkpoint that must prove the FAIL path.
-- No production/runtime activation; the candidate assertion-builder mutation and test run are rolled back.

create or replace function programacion.fn_engineering_ig_validator_assertion_fail_probe_v1(
  p_pantalla_id integer default null
) returns jsonb
language plpgsql
volatile
set search_path to 'pg_catalog','programacion','public','lf_ops'
as $f$
declare
  v_sig regprocedure:='programacion.fn_input_governance_bootstrap_assertions_v1(bigint,text)'::regprocedure;
  v_screen integer:=p_pantalla_id;
  v_orig text;
  v_candidate text;
  v_md5 text;
  v_curator_id text:='INPUT_CURATOR:EDGE:input-governance-curator-v1:M47F'||substr(replace(gen_random_uuid()::text,'-',''),1,12);
  v_validator_id text:='INPUT_VALIDATOR:EDGE:input-governance-validator-v1:M47F'||substr(replace(gen_random_uuid()::text,'-',''),1,12);
  v_cur jsonb;
  v_val jsonb;
  v_run bigint;
  v_i integer;
  v_pending integer:=0;
  v_fail integer:=0;
  v_blocked integer:=0;
  v_screen_identity_outcome text;
  v_screen_identity_findings jsonb;
  v_result jsonb:='{}'::jsonb;
  v_err text;
  v_rollback boolean:=false;
begin
  perform pg_advisory_xact_lock(hashtextextended('IG_VALIDATOR_ASSERTION_FAIL_PROBE',0));

  if v_screen is null then
    select r.pantalla_id into v_screen
    from programacion.input_readiness_runs r
    join lf_ops.pantallas p on p.id=r.pantalla_id and p.activa
    where r.status='COMPLETED'
      and r.invalidated_at is null
      and programacion.fn_input_readiness_run_is_current(r.id)
      and (select count(*) from programacion.input_family_assessments a where a.run_id=r.id)=r.family_count
    order by r.id desc
    limit 1;
  end if;
  if v_screen is null then
    raise exception 'STRICT_FAIL_PROBE_NO_ELIGIBLE_BASELINE_SCREEN';
  end if;

  v_orig:=pg_get_functiondef(v_sig);
  v_md5:=md5(v_orig);

  begin
    -- Create an isolated successor from a valid completed baseline.
    v_cur:=programacion.fn_input_governance_curator_rebind_v1(
      v_screen,'MANUAL',v_curator_id,true
    );
    v_run:=coalesce((v_cur->>'run_id')::bigint,(v_cur->>'latest_run_id')::bigint);
    if v_run is null then
      raise exception 'STRICT_FAIL_PROBE_NO_SELFTEST_RUN:%',v_cur;
    end if;

    -- After Curator materialization, change only the expected value of one
    -- independent assertion. The classifier remains untouched, therefore the
    -- Validator must reach the assertion-failure branch rather than BLOCKED.
    v_candidate:=replace(
      v_orig,
      'v_eval:=programacion.fn_input_evaluate_assertion(p_run_id,p_family_code,v_assertion);',
      'if p_family_code=''SCREEN_IDENTITY'' then v_assertion:=jsonb_set(v_assertion,''{expected}'',to_jsonb(''__ENGINEERING_FORCED_ASSERTION_MISMATCH__''::text),true); end if; v_eval:=programacion.fn_input_evaluate_assertion(p_run_id,p_family_code,v_assertion);'
    );
    if v_candidate=v_orig then
      raise exception 'STRICT_FAIL_PROBE_ASSERTION_PATCH_NOT_APPLIED';
    end if;
    execute v_candidate;

    for v_i in 1..8 loop
      v_val:=programacion.fn_input_governance_validate_v2(v_run,v_validator_id);
      select count(*) filter(where validator_outcome='PENDING')
        into v_pending
      from programacion.input_family_assessments
      where run_id=v_run;
      exit when v_pending=0;
    end loop;

    select
      count(*) filter(where validator_outcome='FAIL'),
      count(*) filter(where validator_outcome='BLOCKED')
      into v_fail,v_blocked
    from programacion.input_family_assessments
    where run_id=v_run;

    select validator_outcome,validator_findings
      into v_screen_identity_outcome,v_screen_identity_findings
    from programacion.input_family_assessments
    where run_id=v_run and family_code='SCREEN_IDENTITY';

    v_result:=jsonb_build_object(
      'status',case
        when v_val->>'status'='VALIDATION_FAILED'
         and v_fail>=1
         and v_screen_identity_outcome='FAIL'
         and coalesce(v_screen_identity_findings,'[]'::jsonb) @>
             jsonb_build_array(jsonb_build_object(
               'finding_type','ASSERTION_FAILURE',
               'finding_code','VALIDATOR_ASSERTION_FAILED',
               'family_code','SCREEN_IDENTITY'
             ))
         and not coalesce((v_val->>'promotion_authorized')::boolean,false)
         and not (select status='COMPLETED' from programacion.input_readiness_runs where id=v_run)
        then 'PASS' else 'FAIL' end,
      'scenario','REAL_ASSERTION_FAILURE',
      'pantalla_id',v_screen,
      'validator_terminal',v_val->>'status',
      'validator_fail_count',v_fail,
      'validator_blocked_count',v_blocked,
      'screen_identity_outcome',v_screen_identity_outcome,
      'screen_identity_findings',coalesce(v_screen_identity_findings,'[]'::jsonb),
      'promotion_authorized',coalesce((v_val->>'promotion_authorized')::boolean,false),
      'run_completed',(select status='COMPLETED' from programacion.input_readiness_runs where id=v_run),
      'test_passed',
        v_val->>'status'='VALIDATION_FAILED'
        and v_fail>=1
        and v_screen_identity_outcome='FAIL'
        and coalesce(v_screen_identity_findings,'[]'::jsonb) @>
            jsonb_build_array(jsonb_build_object(
              'finding_type','ASSERTION_FAILURE',
              'finding_code','VALIDATOR_ASSERTION_FAILED',
              'family_code','SCREEN_IDENTITY'
            ))
        and not coalesce((v_val->>'promotion_authorized')::boolean,false)
        and not (select status='COMPLETED' from programacion.input_readiness_runs where id=v_run)
    );

    if not coalesce((v_result->>'test_passed')::boolean,false) then
      raise exception 'STRICT_FAIL_PROBE_FALSE_PASS:%',v_result;
    end if;

    -- Force rollback of the candidate function and all self-test rows.
    raise exception 'IG_STRICT_FAIL_PROBE_ROLLBACK_OK';
  exception when others then
    v_err:=sqlerrm;
    if v_err='IG_STRICT_FAIL_PROBE_ROLLBACK_OK' then
      v_rollback:=true;
    else
      raise;
    end if;
  end;

  if not v_rollback then
    raise exception 'STRICT_FAIL_PROBE_ROLLBACK_NOT_OBSERVED';
  end if;
  if md5(pg_get_functiondef(v_sig))<>v_md5 then
    raise exception 'STRICT_FAIL_PROBE_ASSERTION_BUILDER_RESIDUE';
  end if;
  if exists(
    select 1 from programacion.input_readiness_runs
    where curator_identity=v_curator_id or validator_identity=v_validator_id
  ) then
    raise exception 'STRICT_FAIL_PROBE_RUN_RESIDUE';
  end if;

  return v_result||jsonb_build_object(
    'durable_residue',false,
    'assertion_builder_restored',true,
    'semantic_authority_bound',true,
    'adversarial_case_executed',true,
    'receipt_semantics','REAL_VALIDATOR_FAIL'
  );
end;
$f$;

comment on function programacion.fn_engineering_ig_validator_assertion_fail_probe_v1(integer)
is 'Rollback-only engineering probe. Creates a self-test successor, injects one assertion expectation mismatch after Curator, runs the real validate_v2 writer to terminal VALIDATION_FAILED, requires VALIDATOR_ASSERTION_FAILED findings and zero promotion, then rolls back function and run changes.';

do $selftest$
declare
  r jsonb;
begin
  r:=programacion.fn_engineering_ig_validator_assertion_fail_probe_v1(54);
  if r->>'status'<>'PASS'
     or r->>'validator_terminal'<>'VALIDATION_FAILED'
     or coalesce((r->>'validator_fail_count')::int,0)<1
     or coalesce((r->>'promotion_authorized')::boolean,true)
     or coalesce((r->>'durable_residue')::boolean,true) then
    raise exception 'IG_STRICT_FAIL_PROBE_SELFTEST_FAILED:%',r;
  end if;
end;
$selftest$;

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
) values (
  'ENGINEERING-IG-VALIDATOR-REAL-FAIL-PROBE-001',
  'ENGINEERING_TESTING',
  'Validator FAIL-path proof must exercise a real assertion failure, not substitute BLOCKED',
  'A classifier mismatch proves BLOCKED but does not satisfy checkpoints whose exit criterion explicitly requires at least one observable FAIL.',
  'The negative proof previously exercised only the classifier-block branch.',
  'CURATOR_SELFTEST -> ASSERTION_EXPECTATION_MUTATION -> VALIDATE_V2 -> VALIDATION_FAILED -> FINDINGS -> ZERO_PROMOTION -> ROLLBACK',
  'Use the rollback-only strict FAIL probe when the contract explicitly distinguishes FAIL from BLOCKED. Never relabel BLOCKED as FAIL.',
  'PASS when the probe returns VALIDATION_FAILED, validator_fail_count>=1, SCREEN_IDENTITY outcome FAIL with VALIDATOR_ASSERTION_FAILED, promotion_authorized=false, run_completed=false and durable_residue=false.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','ACTIVO',
  'supabase://programacion.fn_engineering_ig_validator_assertion_fail_probe_v1',
  'TEST',
  array['ENGINEERING_EXECUTOR','PROGRAMMING_AGENT']::text[],
  'R2_NO_VE','LOUD_EARLY',
  'M4.7 strict FAIL receipt proof',
  'supabase://programacion.fn_engineering_ig_validator_assertion_fail_probe_v1'
)
on conflict (codigo) do update set
  descripcion=excluded.descripcion,
  causa_raiz=excluded.causa_raiz,
  patron=excluded.patron,
  prevencion=excluded.prevencion,
  validacion=excluded.validacion,
  evidencia=excluded.evidencia,
  ultima_vez=now(),
  estado=excluded.estado,
  updated_at=now();
