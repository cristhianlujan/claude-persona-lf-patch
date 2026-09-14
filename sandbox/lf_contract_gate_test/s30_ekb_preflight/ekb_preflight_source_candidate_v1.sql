-- SOURCE CANDIDATE ONLY. DO NOT APPLY FROM THIS PR.
-- Resolves applicable EKB from existing public views and separates knowledge resolution
-- from executed preventive-control evidence.

create or replace function public.lf_ekb_preflight_v1(
  p_operation_code text,
  p_execution_id text,
  p_lifecycle_phases text[],
  p_consumer_roles text[],
  p_required_codes text[] default array[]::text[],
  p_control_coverage jsonb default '{"coverage_version":"LF_EKB_CONTROL_COVERAGE_V1","bindings":[]}'::jsonb
) returns jsonb
language plpgsql
stable
security invoker
set search_path to 'pg_catalog','public','extensions'
as $$
declare
  v_execution public.lf_operation_execution%rowtype;
  v_phases text[];
  v_roles text[];
  v_required text[];
  v_required_missing text[];
  v_duplicate_codes text[];
  v_selected_codes text[];
  v_control_codes text[];
  v_unhandled text[];
  v_missing_bindings text[];
  v_duplicate_bindings text[];
  v_unknown_bindings text[];
  v_bad_bindings text[];
  v_pending_bindings text[];
  v_blocked_bindings text[];
  v_errors jsonb;
  v_rules jsonb;
  v_best jsonb;
  v_bindings jsonb;
  v_core jsonb;
  v_result text;
  v_pass boolean;
begin
  if btrim(coalesce(p_operation_code,'')) = ''
     or btrim(coalesce(p_execution_id,'')) = ''
     or p_lifecycle_phases is null or cardinality(p_lifecycle_phases) = 0
     or p_consumer_roles is null or cardinality(p_consumer_roles) = 0
     or p_required_codes is null
     or p_control_coverage is null or jsonb_typeof(p_control_coverage) <> 'object' then
    raise exception 'LF_EKB_PREFLIGHT_INPUT_INVALID';
  end if;

  select array_agg(distinct lower(btrim(x)) order by lower(btrim(x)))
    into v_phases
    from unnest(p_lifecycle_phases) x
   where nullif(btrim(x),'') is not null;
  select array_agg(distinct lower(btrim(x)) order by lower(btrim(x)))
    into v_roles
    from unnest(p_consumer_roles) x
   where nullif(btrim(x),'') is not null;
  select coalesce(array_agg(distinct btrim(x) order by btrim(x)),array[]::text[])
    into v_required
    from unnest(p_required_codes) x
   where nullif(btrim(x),'') is not null;

  if coalesce(cardinality(v_phases),0) = 0 or coalesce(cardinality(v_roles),0) = 0 then
    raise exception 'LF_EKB_PREFLIGHT_CONTEXT_EMPTY';
  end if;

  if not exists (
    select 1 from public.lf_operation_registry r
     where r.operation_code = p_operation_code
  ) then
    raise exception 'LF_EKB_PREFLIGHT_OPERATION_NOT_REGISTERED:%',p_operation_code;
  end if;

  select * into v_execution
    from public.lf_operation_execution
   where execution_id = p_execution_id;
  if not found
     or v_execution.operation_code <> p_operation_code
     or v_execution.status <> 'IN_PROGRESS' then
    raise exception 'LF_EKB_PREFLIGHT_EXECUTION_BINDING_INVALID';
  end if;

  select array_agg(codigo order by codigo)
    into v_duplicate_codes
    from (
      select codigo
        from public.lf_error_knowledge
       where estado = 'activo'
       group by codigo
      having count(*) <> 1
    ) d;
  if coalesce(cardinality(v_duplicate_codes),0) > 0 then
    v_result := 'BLOCK_EKB_DUPLICATE_ACTIVE_CODE';
    v_core := jsonb_build_object(
      'result',v_result,
      'pass',false,
      'operation_code',p_operation_code,
      'execution_id',p_execution_id,
      'duplicate_active_codes',to_jsonb(v_duplicate_codes)
    );
    return v_core || jsonb_build_object(
      'receipt_sha256',encode(extensions.digest(convert_to(v_core::text,'UTF8'),'sha256'),'hex')
    );
  end if;

  select array_agg(req order by req)
    into v_required_missing
    from unnest(v_required) req
   where not exists (
     select 1 from public.lf_error_knowledge e
      where e.estado='activo' and e.codigo=req
   );

  if coalesce(cardinality(v_required_missing),0) > 0 then
    v_result := 'BLOCK_EKB_REQUIRED_CODE_MISSING';
    v_core := jsonb_build_object(
      'result',v_result,
      'pass',false,
      'operation_code',p_operation_code,
      'execution_id',p_execution_id,
      'required_codes',to_jsonb(v_required),
      'missing_required_codes',to_jsonb(v_required_missing)
    );
    return v_core || jsonb_build_object(
      'receipt_sha256',encode(extensions.digest(convert_to(v_core::text,'UTF8'),'sha256'),'hex')
    );
  end if;

  with selected as (
    select e.*
      from public.lf_error_knowledge e
     where e.estado='activo'
       and (
         e.codigo = any(v_required)
         or (
           lower(btrim(e.lifecycle_phase)) = any(v_phases)
           and exists (
             select 1
               from unnest(e.consumer_role) er(role)
              where lower(btrim(er.role)) = any(v_roles)
           )
         )
       )
  )
  select coalesce(array_agg(codigo order by codigo),array[]::text[]),
         coalesce(jsonb_agg(
           jsonb_build_object(
             'codigo',codigo,
             'categoria',categoria,
             'titulo',titulo,
             'severidad',severidad,
             'frecuencia',frecuencia,
             'lifecycle_phase',lifecycle_phase,
             'consumer_role',consumer_role,
             'detectability',detectability,
             'prevencion',prevencion,
             'validacion',validacion,
             'source_ref',source_ref,
             'selection_reason',case when codigo=any(v_required) then 'EXPLICIT_REQUIRED_CODE' else 'CONTEXT_MATCH' end
           ) order by codigo
         ),'[]'::jsonb)
    into v_selected_codes,v_errors
    from selected;

  select array_agg(e.codigo order by e.codigo)
    into v_unhandled
    from public.lf_error_knowledge e
   where e.codigo = any(v_selected_codes)
     and lower(coalesce(e.severidad,'')) in ('high','critical','alta','alto')
     and nullif(btrim(coalesce(e.prevencion,'')),'') is null
     and not exists (
       select 1 from public.lf_prevention_rules r
        where r.activa and r.error_codigo=e.codigo
     );

  if coalesce(cardinality(v_unhandled),0) > 0 then
    v_result := 'BLOCK_EKB_UNHANDLED_HIGH_CRITICAL';
    v_core := jsonb_build_object(
      'result',v_result,
      'pass',false,
      'operation_code',p_operation_code,
      'execution_id',p_execution_id,
      'lifecycle_phases',to_jsonb(v_phases),
      'consumer_roles',to_jsonb(v_roles),
      'required_codes',to_jsonb(v_required),
      'matched_error_codes',to_jsonb(v_selected_codes),
      'unhandled_high_critical_codes',to_jsonb(v_unhandled)
    );
    return v_core || jsonb_build_object(
      'receipt_sha256',encode(extensions.digest(convert_to(v_core::text,'UTF8'),'sha256'),'hex')
    );
  end if;

  select coalesce(jsonb_agg(
           jsonb_build_object(
             'regla_codigo',r.regla_codigo,
             'error_codigo',r.error_codigo,
             'regla',r.regla,
             'justificacion',r.justificacion,
             'prioridad',r.prioridad,
             'lifecycle_phase',r.lifecycle_phase,
             'consumer_role',r.consumer_role
           ) order by r.error_codigo,r.prioridad nulls last,r.regla_codigo
         ),'[]'::jsonb)
    into v_rules
    from public.lf_prevention_rules r
   where r.activa and r.error_codigo = any(v_selected_codes);

  select coalesce(jsonb_agg(
           jsonb_build_object(
             'id',b.id,
             'categoria',b.categoria,
             'titulo',b.titulo,
             'practica',b.practica,
             'evidencia',b.evidencia
           ) order by b.categoria,b.titulo,b.id
         ),'[]'::jsonb)
    into v_best
    from public.lf_best_practices b
   where b.categoria in (
     select distinct e.categoria
       from public.lf_error_knowledge e
      where e.codigo = any(v_selected_codes)
   );

  select coalesce(array_agg(code order by code),array[]::text[])
    into v_control_codes
    from (
      select e.codigo as code
        from public.lf_error_knowledge e
       where e.codigo = any(v_selected_codes)
         and lower(coalesce(e.severidad,'')) in ('high','critical','alta','alto')
      union
      select unnest(v_required)
    ) x;

  if p_control_coverage->>'coverage_version' <> 'LF_EKB_CONTROL_COVERAGE_V1'
     or jsonb_typeof(coalesce(p_control_coverage->'bindings','null'::jsonb)) <> 'array' then
    raise exception 'LF_EKB_PREFLIGHT_CONTROL_COVERAGE_SHAPE_INVALID';
  end if;
  v_bindings := coalesce(p_control_coverage->'bindings','[]'::jsonb);

  select array_agg(code order by code)
    into v_missing_bindings
    from unnest(v_control_codes) code
   where (
     select count(*)
       from jsonb_array_elements(v_bindings) b
      where b->>'error_code'=code
   ) = 0;

  select array_agg(code order by code)
    into v_duplicate_bindings
    from unnest(v_control_codes) code
   where (
     select count(*)
       from jsonb_array_elements(v_bindings) b
      where b->>'error_code'=code
   ) > 1;

  select array_agg(distinct b->>'error_code' order by b->>'error_code')
    into v_unknown_bindings
    from jsonb_array_elements(v_bindings) b
   where coalesce(b->>'error_code','') <> ''
     and not ((b->>'error_code') = any(v_selected_codes));

  if coalesce(cardinality(v_missing_bindings),0) > 0
     or coalesce(cardinality(v_duplicate_bindings),0) > 0
     or coalesce(cardinality(v_unknown_bindings),0) > 0 then
    v_result := 'BLOCK_EKB_CONTROL_COVERAGE_INCOMPLETE';
  else
    select array_agg(code order by code)
      into v_bad_bindings
      from unnest(v_control_codes) code
     where exists (
       select 1
         from jsonb_array_elements(v_bindings) b
        where b->>'error_code'=code
          and (
            coalesce(b->>'control_mode','') not in ('DETERMINISTIC_CHECK','PROCESS_EVIDENCE','HUMAN_REVIEW')
            or coalesce(b->>'status','') = 'BLOCKED'
            or (
              b->>'status'='PASS'
              and (
                coalesce((b->>'executed')::boolean,false) is not true
                or nullif(btrim(coalesce(b->>'evidence_ref','')),'') is null
                or coalesce(b->>'evidence_sha256','') !~ '^[0-9a-f]{64}$'
              )
            )
          )
     );

    select array_agg(code order by code)
      into v_blocked_bindings
      from unnest(v_control_codes) code
     where exists (
       select 1 from jsonb_array_elements(v_bindings) b
        where b->>'error_code'=code and b->>'status'='BLOCKED'
     );

    select array_agg(code order by code)
      into v_pending_bindings
      from unnest(v_control_codes) code
     where exists (
       select 1 from jsonb_array_elements(v_bindings) b
        where b->>'error_code'=code
          and coalesce(b->>'status','') in ('PENDING','REVIEW_REQUIRED')
     );

    if coalesce(cardinality(v_bad_bindings),0) > 0 or coalesce(cardinality(v_blocked_bindings),0) > 0 then
      v_result := 'BLOCK_EKB_CONTROL_EVIDENCE_INVALID';
    elsif coalesce(cardinality(v_pending_bindings),0) > 0 then
      v_result := 'EKB_RESOLVED_CONTROLS_PENDING';
    else
      v_result := 'PASS_EKB_PREFLIGHT_CONTROLS_BOUND';
    end if;
  end if;

  v_pass := v_result='PASS_EKB_PREFLIGHT_CONTROLS_BOUND';
  v_core := jsonb_build_object(
    'schema_version',1,
    'result',v_result,
    'pass',v_pass,
    'operation_code',p_operation_code,
    'execution_id',p_execution_id,
    'lifecycle_phases',to_jsonb(v_phases),
    'consumer_roles',to_jsonb(v_roles),
    'required_codes',to_jsonb(v_required),
    'matched_error_codes',to_jsonb(v_selected_codes),
    'active_errors',v_errors,
    'active_prevention_rules',v_rules,
    'best_practices_by_selected_category',v_best,
    'required_control_codes',to_jsonb(v_control_codes),
    'control_bindings',v_bindings,
    'missing_control_bindings',to_jsonb(coalesce(v_missing_bindings,array[]::text[])),
    'duplicate_control_bindings',to_jsonb(coalesce(v_duplicate_bindings,array[]::text[])),
    'unknown_control_bindings',to_jsonb(coalesce(v_unknown_bindings,array[]::text[])),
    'pending_control_bindings',to_jsonb(coalesce(v_pending_bindings,array[]::text[])),
    'control_evidence_failures',to_jsonb(coalesce(v_bad_bindings,array[]::text[])),
    'ekb_read',true,
    'controls_executed_for_pass',v_pass,
    'observed_at',clock_timestamp()
  );

  return v_core || jsonb_build_object(
    'receipt_sha256',encode(extensions.digest(convert_to((v_core - 'observed_at')::text,'UTF8'),'sha256'),'hex')
  );
end;
$$;

revoke execute on function public.lf_ekb_preflight_v1(text,text,text[],text[],text[],jsonb) from public, anon, authenticated;
grant execute on function public.lf_ekb_preflight_v1(text,text,text[],text[],text[],jsonb) to service_role;
