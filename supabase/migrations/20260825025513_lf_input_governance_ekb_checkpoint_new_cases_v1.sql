-- INPUT_GOVERNANCE_AGENT: wire newly verified EKB cases into runtime checkpoints.
-- No screen functional data or readiness contract semantics are modified.
create or replace function programacion.fn_input_governance_ekb_checkpoint(
  p_phase text,
  p_pantalla_id integer,
  p_run_id bigint default null
) returns jsonb
language plpgsql
stable security definer
set search_path to 'pg_catalog','public','programacion','lf_ops'
as $function$
declare
  v_codes text[];
  v_errors jsonb;
  v_rules jsonb;
  v_unhandled jsonb;
  v_receipt jsonb;
begin
  if not exists(
    select 1 from programacion.contratos
    where version_id=19 and contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT'
      and estado='defined' and fail_closed
  ) then
    raise exception 'INPUT_GOVERNANCE_EXECUTION_CONTRACT_NOT_RESOLVABLE';
  end if;
  if not exists(select 1 from lf_ops.pantallas where id=p_pantalla_id) then
    raise exception 'INPUT_GOVERNANCE_SCREEN_NOT_FOUND:%',p_pantalla_id;
  end if;

  v_codes:=case p_phase
    when 'PRE_EXECUTION' then array[
      'GOV-010','DB-001','ARC-006','GOV-007','SRC-001','SRC-006','CI-MIG-001',
      'AUD-040','ARC-015'
    ]
    when 'PRE_CURATOR' then array[
      'GOV-010','DB-001','AUD-019','AUD-038','AUD-039','GOV-012','GOV-013','GOV-014','ARC-011','SQL-013',
      'AUD-040','AUD-041','AUD-042','AUD-043','ARC-015'
    ]
    when 'PRE_VALIDATOR' then array[
      'GOV-010','AUD-001','AUD-019','AUD-038','AUD-039','GOV-012','GOV-013','GOV-014','ARC-006',
      'AUD-040','AUD-041','AUD-042','AUD-043','ARC-015'
    ]
    when 'PRE_STORY_GATE' then array[
      'GOV-010','GOV-012','GOV-013','GOV-014','ARC-011',
      'AUD-040','AUD-043','ARC-015'
    ]
    when 'PRE_CONTEXT_MANIFEST' then array[
      'GOV-010','ARC-006','GOV-007','SRC-001','SRC-006','ARC-015'
    ]
    when 'CLOSE_EKB' then array[
      'GOV-010','ARC-006','GOV-007','SRC-001','SRC-006','AUD-001',
      'AUD-040','AUD-041','AUD-042','AUD-043','ARC-015'
    ]
    else null
  end;

  if v_codes is null then
    raise exception 'INPUT_GOVERNANCE_EKB_PHASE_NOT_DEFINED:%',coalesce(p_phase,'<NULL>');
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'codigo',e.codigo,'severidad',e.severidad,'frecuencia',e.frecuencia,
    'prevencion',e.prevencion,'validacion',e.validacion
  ) order by e.codigo),'[]'::jsonb)
  into v_errors
  from public.lf_error_knowledge e
  where e.estado='activo' and e.codigo=any(v_codes);

  select coalesce(jsonb_agg(jsonb_build_object(
    'regla_codigo',r.regla_codigo,'error_codigo',r.error_codigo,
    'regla',r.regla,'prioridad',r.prioridad
  ) order by r.error_codigo,r.prioridad,r.regla_codigo),'[]'::jsonb)
  into v_rules
  from public.lf_prevention_rules r
  where r.activa and r.error_codigo=any(v_codes);

  select coalesce(jsonb_agg(e.codigo order by e.codigo),'[]'::jsonb)
  into v_unhandled
  from public.lf_error_knowledge e
  where e.estado='activo' and e.codigo=any(v_codes)
    and lower(e.severidad) in ('high','critical')
    and nullif(btrim(coalesce(e.prevencion,'')),'') is null
    and not exists(
      select 1 from public.lf_prevention_rules r
      where r.error_codigo=e.codigo and r.activa
    );

  v_receipt:=jsonb_build_object(
    'schema_version',1,'phase',p_phase,'pantalla_id',p_pantalla_id,'run_id',p_run_id,
    'decision_authority','DEC-INPUT-GOV-EXEC-EKB-001','ekb_read',true,
    'active_errors',v_errors,'active_prevention_rules',v_rules,
    'unhandled_high_critical_codes',v_unhandled,
    'pass',jsonb_array_length(v_unhandled)=0,'observed_at',now()
  );
  return v_receipt||jsonb_build_object('receipt_sha256',programacion.fn_v09_sha256_jsonb(v_receipt));
end;
$function$;
